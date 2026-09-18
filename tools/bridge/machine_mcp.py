#!/usr/bin/env python3
"""
A minimal MCP server that lets a remote Claude session read files on this
machine. Python standard library only — no pip install.

    python3 machine_mcp.py --root ~/projects --token "$(openssl rand -hex 24)"

It speaks MCP over Streamable HTTP on localhost. To reach it from a cloud
session you must put a public HTTPS URL in front of it — see README.md.

DESIGN NOTES, because this is a program that exposes your disk to the internet:

  * READ ONLY. There is no write, delete, move or execute tool, on purpose. A
    connector that can run commands is a remote shell, and a remote shell on a
    public URL is the thing you least want to get wrong.
  * EVERY path is resolved and checked against --root. A request for
    ../../.ssh/id_rsa resolves outside the root and is refused.
  * A bearer token is REQUIRED. Without it the server refuses to start, because
    a tunnel URL is not a secret — it is a URL, and URLs leak.
  * Nothing is ever held whole in memory. Files stream line by line against a
    byte budget, so a stray read of a 2GB file cannot hang anything.

v2 — what changed and why:

  * read_file PAGES instead of refusing. v1 capped files at 256 KB and returned
    "refused" above it, which made the single most important file in the target
    project (a 585 KB World.luau) unreadable. The cap is now per *response*, not
    per file: big files arrive in pages via offset/limit.
  * search_files added. Locating one function in 585 KB by reading it in pages
    is absurd; a regex that returns path:line:text finds it in one call.
  * Line numbers on every read, so a follow-up page or an edit can be described
    precisely.
  * Three holes closed: directories were not themselves checked against the
    deny policy (only their entries were), the POSIX entries in DENY_DIRS could
    never match because of a leading-slash bug, and request bodies were read
    with no size cap.
"""

from __future__ import annotations

import argparse
import fnmatch
import hmac
import json
import os
import pathlib
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOL_VERSION = "2025-06-18"

# A cap on one RESPONSE, not on a file. Anything larger simply pages.
MAX_RESPONSE_BYTES = 256 * 1024
MAX_ENTRIES = 500
MAX_MATCHES = 200
# Nothing legitimate posts a large body at this server; the largest real request
# is a few hundred bytes of JSON-RPC.
MAX_REQUEST_BYTES = 64 * 1024
# Files above this are not worth scanning line by line during a search.
MAX_SEARCH_FILE_BYTES = 8 * 1024 * 1024
# Read in chunks and cap any single line. Text-mode line iteration calls
# readline(), which reads until a newline arrives -- so a minified bundle or a
# one-line .rbxlx would be pulled whole into memory despite the streaming claim.
CHUNK_CHARS = 64 * 1024
MAX_LINE_CHARS = 32 * 1024
# A search runs an attacker-supplied regex. Bound both the input it sees and
# the total time it may burn.
MAX_MATCH_CHARS = 2000
SEARCH_DEADLINE_SECONDS = 10.0
# (group containing a quantifier) followed by a quantifier -- "(a+)+", "(.*)*".
RISKY_REGEX = re.compile(r"\([^)]*[+*][^)]*\)\s*[+*{]")

# Never reveal these, even inside the root. Credentials leak through "just
# reading files" far more often than through anything dramatic, and the wider
# the root the more certain it becomes that something sensitive is in range.
DENY_GLOBS = [
    # keys and certificates
    "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.jks", "*.ppk",
    "id_rsa*", "id_dsa*", "id_ecdsa*", "id_ed25519*", "*.asc", "*.gpg",
    # config files that routinely hold live credentials
    ".env", ".env.*", "*.env", ".netrc", "_netrc", ".git-credentials",
    ".npmrc", ".pypirc", ".dockercfg", ".docker-config.json",
    "credentials", "credentials.json", "client_secret*.json",
    ".htpasswd", "shadow", "sam", "security",
    # anything self-describing
    "*secret*", "*token*", "*password*", "*passwd*", "*.kdbx", "*wallet*",
    # shell history holds pasted tokens surprisingly often
    ".bash_history", ".zsh_history", ".psql_history", "ConsoleHost_history.txt",
]

# Whole directories that are skipped: listing them is as revealing as reading
# them, and none of them contains anything worth sharing. Written WITHOUT
# leading slashes — they are matched as path segments, and a leading slash here
# produced a "//proc/" needle in v1 that could never match anything.
DENY_DIRS = {
    ".ssh", ".gnupg", ".aws", ".azure", "gcloud", ".kube", ".docker",
    ".password-store", ".mozilla", ".thunderbird", "keychains",
    "google/chrome", "bravesoftware", "microsoft/edge", "firefox",
    ".local/share/keyrings", "protected storage", "credentials",
    # OS internals: huge, useless to share, and full of system secrets
    "windows", "system32", "$recycle.bin", "system volume information",
    "proc", "sys", "dev", "private/var/db",
}

ROOT: pathlib.Path
TOKEN: str
ALLOW_SECRETS = False


# --------------------------------------------------------------------------- paths

def resolve(relative: str) -> pathlib.Path:
    """Resolve a client-supplied path inside ROOT, or raise."""
    cleaned = str(relative).lstrip("/\\")

    # Reject NTFS alternate-data-stream syntax and Windows' silent trimming
    # BEFORE anything else looks at the name. Both defeat the filename filters:
    # ".env:$DATA" matches none of DENY_GLOBS, yet NTFS serves it the exact
    # bytes of ".env". Windows likewise strips trailing dots and spaces, so
    # "id_rsa " opens "id_rsa". A colon is also how a drive gets smuggled in.
    for part in pathlib.PurePath(cleaned).parts:
        if ":" in part:
            raise ValueError(f"path component contains a colon: {part}")
        if part != part.rstrip(". ") and part not in (".", ".."):
            raise ValueError(f"path component has a trailing dot or space: {part!r}")

    candidate = (ROOT / cleaned).resolve()

    # Compare resolved paths: this is what defeats .., symlinks out of the tree,
    # and absolute paths smuggled in as the argument.
    if candidate != ROOT and ROOT not in candidate.parents:
        raise ValueError(f"path escapes the shared root: {relative}")

    return candidate


def denied(path: pathlib.Path) -> bool:
    """True if this path, or anything it sits inside, is off limits."""
    if ALLOW_SECRETS:
        return False

    if not _segment_allowed(path.name):
        return True

    # Scan only the part BELOW the root. Matching against the whole absolute
    # path let a segment in the root's own ancestry veto everything: a project
    # at C:\dev\game sits under "dev", so every file in it was refused.
    try:
        relative = path.relative_to(ROOT)
    except ValueError:
        return True

    parts = [_normalise(part) for part in relative.parts]
    lowered = "/" + "/".join(parts) + "/" if parts else "/"
    return any(f"/{d}/" in lowered for d in DENY_DIRS)


def _normalise(segment: str) -> str:
    """The name Windows will actually open, lowercased.

    Win32 strips trailing dots and spaces and treats "name::$DATA" as the
    file's default stream, so "credentials." and ".env " and ".env::$DATA" all
    open the file the deny-list is meant to hide while matching none of its
    patterns. Normalise before comparing, not after.
    """
    stem = segment.split(":", 1)[0]
    trimmed = stem.rstrip(" .")
    return (trimmed or stem or segment).lower()


def _segment_allowed(name: str) -> bool:
    return not any(fnmatch.fnmatch(_normalise(name), pattern) for pattern in DENY_GLOBS)


def inside(path: pathlib.Path) -> bool:
    """True if this path really lands inside ROOT once the OS resolves it.

    Glob results are never passed through resolve(), so this is what catches a
    symlink or an NTFS junction sitting inside the root and pointing out of it.
    """
    try:
        real = path.resolve()
    except (OSError, RuntimeError):
        return False
    return real == ROOT or ROOT in real.parents


def safe_pattern(pattern: str, label: str) -> str:
    """Reject a glob that can leave the root before it reaches rglob().

    resolve() only ever saw the `path` argument. A glob of
    "../../../../etc/passwd" went straight into rglob(), and pathlib expands
    ".." inside a pattern lexically -- so the walk left the root without any
    check at all. That was an arbitrary file read.
    """
    text = str(pattern)
    pure = pathlib.PurePath(text)
    if pure.anchor or pure.drive or ":" in text:
        raise ValueError(f"{label} may not be absolute or contain a drive: {text}")
    if any(part == ".." for part in pure.parts):
        raise ValueError(f"{label} may not traverse upwards: {text}")
    return text


def guard(path: pathlib.Path) -> str | None:
    """The one refusal message used everywhere, so no caller can forget it."""
    if denied(path):
        return "refused: this path matches the connector's secret-file policy"
    return None


# --------------------------------------------------------------------------- tools

TOOLS = [
    {
        "name": "list_directory",
        "description": "List files and folders at a path inside the shared root.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative path. Empty for the root."},
            },
        },
    },
    {
        "name": "read_file",
        "description": (
            "Read a UTF-8 text file inside the shared root, with line numbers. "
            "Large files page rather than fail: pass offset/limit to walk them."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "offset": {"type": "integer", "description": "First line, 1-based. Default 1."},
                "limit": {"type": "integer", "description": "Max lines. Default: fill one page."},
            },
            "required": ["path"],
        },
    },
    {
        "name": "search_files",
        "description": (
            "Regex search across files inside the shared root. Returns "
            "path:line: text. Far cheaper than reading a large file to find one thing."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Python regex."},
                "glob": {"type": "string", "description": "Filename filter, e.g. *.luau. Default *."},
                "path": {"type": "string", "description": "Subfolder to search. Optional."},
                "ignore_case": {"type": "boolean"},
                "max_results": {"type": "integer"},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "find_files",
        "description": "Find files matching a glob, recursively, inside the shared root.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "e.g. *.luau or *.rbxl"},
                "path": {"type": "string", "description": "Subfolder to search. Optional."},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "describe_root",
        "description": "Report what this connector is sharing and what it refuses.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def iter_lines(handle):
    """Yield (number, text, truncated) holding at most one line in memory.

    An over-long line is emitted truncated and numbering still advances. v2
    broke out of the loop instead, which made such a line a permanent dead end:
    the page looked like a clean EOF and the rest of the file was silently
    unreachable at any offset.
    """
    buffer = ""
    number = 0
    overflowing = False

    while True:
        chunk = handle.read(CHUNK_CHARS)
        if not chunk:
            break
        buffer += chunk

        while True:
            newline = buffer.find("\n")
            if newline >= 0:
                line, buffer = buffer[:newline], buffer[newline + 1:]
                if overflowing:
                    overflowing = False          # tail of a line already emitted
                else:
                    number += 1
                    yield number, line.rstrip("\r"), False
            elif not overflowing and len(buffer) > MAX_LINE_CHARS:
                number += 1
                yield number, buffer[:MAX_LINE_CHARS], True
                buffer = ""
                overflowing = True
            else:
                if overflowing:
                    buffer = ""                  # keep discarding the tail
                break

    if buffer and not overflowing:
        number += 1
        yield number, buffer.rstrip("\r"), False


def tool_list_directory(args: dict) -> str:
    target = resolve(args.get("path", ""))

    refusal = guard(target)
    if refusal:
        return refusal
    if not target.is_dir():
        return f"not a directory: {args.get('path', '')}"

    rows = []
    truncated = False
    for entry in sorted(target.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        if len(rows) >= MAX_ENTRIES:
            truncated = True
            break
        if denied(entry) or not inside(entry):
            rows.append(f"  [hidden by policy]  {entry.name}")
        elif entry.is_dir():
            rows.append(f"  <dir>   {entry.name}/")
        else:
            try:
                rows.append(f"  {entry.stat().st_size:>11,}  {entry.name}")
            except OSError:
                rows.append(f"  {'?':>11}  {entry.name}")

    where = target.relative_to(ROOT).as_posix() if target != ROOT else "."
    header = f"{where}  ({len(rows)} entries{', truncated' if truncated else ''})"
    return header + "\n" + "\n".join(rows)


def tool_read_file(args: dict) -> str:
    target = resolve(args["path"])

    refusal = guard(target)
    if refusal:
        return refusal
    if not target.is_file():
        return f"not a file: {args['path']}"

    offset = max(1, int(args.get("offset") or 1))
    limit = max(0, int(args.get("limit") or 0))
    stop_after = offset + limit - 1 if limit > 0 else None

    size = target.stat().st_size
    lines: list[str] = []
    budget = MAX_RESPONSE_BYTES
    last = offset - 1
    more = False
    clipped = False
    reached = 0

    try:
        with target.open("r", encoding="utf-8", errors="strict") as handle:
            for number, text, was_clipped in iter_lines(handle):
                reached = number
                if number < offset:
                    continue
                if stop_after is not None and number > stop_after:
                    more = True
                    break

                cost = len(text.encode("utf-8", "replace")) + 10
                if cost > budget and lines:
                    more = True
                    break

                budget -= cost
                last = number
                clipped = clipped or was_clipped
                lines.append(f"{number:>6}\t{text}" + ("   [line truncated]" if was_clipped else ""))
    except UnicodeDecodeError:
        return f"refused: {args['path']} is not UTF-8 text ({size:,} bytes)"
    except OSError as exc:
        return f"error reading {args['path']}: {exc}"

    if not lines:
        if reached >= offset:
            return (f"{args['path']}: line {offset} alone exceeds the "
                    f"{MAX_RESPONSE_BYTES:,}-byte response budget; it is served truncated "
                    f"on a normal read, so continue from offset={offset + 1}")
        return f"{args['path']}: no lines at offset {offset} ({size:,} bytes total, {reached:,} lines)"

    head = f"{args['path']}  lines {offset}-{last}  ({size:,} bytes)"
    if clipped:
        head += f"\n[one or more lines exceeded {MAX_LINE_CHARS:,} chars and were truncated]"
    if more:
        head += f"\n[more follows — call again with offset={last + 1}]"
    return head + "\n" + "\n".join(lines)


def tool_search_files(args: dict) -> str:
    base = resolve(args.get("path", ""))
    refusal = guard(base)
    if refusal:
        return refusal

    glob = safe_pattern(args.get("glob") or "*", "glob")

    flags = re.IGNORECASE if args.get("ignore_case") else 0
    try:
        needle = re.compile(args["pattern"], flags)
    except re.error as exc:
        return f"bad regex: {exc}"

    # A nested quantifier is the shape that backtracks catastrophically, and a
    # single re.search() cannot be interrupted from Python. Refusing the shape
    # is a blunt guard, not a proof: see SECURITY in SETUP.md.
    if RISKY_REGEX.search(args["pattern"]):
        return ("refused: that pattern nests a quantifier inside a quantified group "
                "(e.g. (a+)+), which can hang the server. Rewrite it more simply.")

    cap = max(1, min(int(args.get("max_results") or MAX_MATCHES), MAX_MATCHES))
    deadline = time.monotonic() + SEARCH_DEADLINE_SECONDS

    hits: list[str] = []
    scanned = 0
    capped = False
    expired = False

    for found in sorted(base.rglob(glob)):
        if len(hits) >= cap:
            capped = True
            break
        if time.monotonic() > deadline:
            expired = True
            break
        # Every glob result is re-checked: rglob never went through resolve().
        if not found.is_file() or not inside(found) or denied(found):
            continue
        try:
            if found.stat().st_size > MAX_SEARCH_FILE_BYTES:
                continue
        except OSError:
            continue

        scanned += 1
        try:
            with found.open("r", encoding="utf-8", errors="strict") as handle:
                for number, text, _ in iter_lines(handle):
                    if needle.search(text[:MAX_MATCH_CHARS]):
                        hits.append(f"  {found.relative_to(ROOT).as_posix()}:{number}: {text[:300]}")
                        if len(hits) >= cap:
                            capped = True
                            break
                    if time.monotonic() > deadline:
                        expired = True
                        break
        except (UnicodeDecodeError, OSError):
            continue
        if capped or expired:
            break

    head = f"{len(hits)} match(es) for /{args['pattern']}/ in {glob} across {scanned} file(s) searched"
    if capped:
        head += f" — stopped at the {cap}-result cap"
    if expired:
        head += f" — stopped after {SEARCH_DEADLINE_SECONDS:g}s"
    return head + ("\n" + "\n".join(hits) if hits else "")


def tool_find_files(args: dict) -> str:
    base = resolve(args.get("path", ""))
    refusal = guard(base)
    if refusal:
        return refusal

    pattern = safe_pattern(args["pattern"], "pattern")

    hits = []
    truncated = False
    for found in sorted(base.rglob(pattern)):
        if len(hits) >= MAX_ENTRIES:
            truncated = True
            break
        if not found.is_file() or not inside(found) or denied(found):
            continue
        try:
            hits.append(f"  {found.stat().st_size:>11,}  {found.relative_to(ROOT).as_posix()}")
        except OSError:
            continue

    head = f"{len(hits)} match(es) for {pattern}{', truncated' if truncated else ''}"
    return head + ("\n" + "\n".join(hits) if hits else "")


def tool_describe_root(_args: dict) -> str:
    return (
        f"sharing: {ROOT}\n"
        f"access: READ ONLY — no write, delete or execute tools exist\n"
        f"response cap: {MAX_RESPONSE_BYTES:,} bytes per read; larger files page "
        f"via offset/limit rather than being refused\n"
        f"text only: non-UTF-8 files are refused, not streamed\n"
        f"credential filters: {'OFF (--allow-secrets)' if ALLOW_SECRETS else 'on'}\n"
        f"refused filename patterns: {', '.join(DENY_GLOBS)}"
    )


HANDLERS = {
    "list_directory": tool_list_directory,
    "read_file": tool_read_file,
    "search_files": tool_search_files,
    "find_files": tool_find_files,
    "describe_root": tool_describe_root,
}


# --------------------------------------------------------------------------- MCP

def handle_rpc(message: dict) -> dict | None:
    method = message.get("method")
    request_id = message.get("id")

    # Notifications have no id and expect no reply.
    if request_id is None:
        return None

    def ok(result):
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    def err(code, text):
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": text}}

    if method == "initialize":
        return ok({
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "machine-bridge", "version": "3.0.0"},
        })

    if method == "tools/list":
        return ok({"tools": TOOLS})

    if method == "tools/call":
        params = message.get("params") or {}
        name = params.get("name")
        handler = HANDLERS.get(name)

        if handler is None:
            return err(-32602, f"unknown tool: {name}")

        try:
            text = handler(params.get("arguments") or {})
        except Exception as exc:                      # noqa: BLE001 - reported to the client
            return ok({"content": [{"type": "text", "text": f"error: {exc}"}], "isError": True})

        return ok({"content": [{"type": "text", "text": text}]})

    if method == "ping":
        return ok({})

    return err(-32601, f"unknown method: {method}")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # Without this a half-open connection pins a thread forever, which is a
    # denial of service available to anyone who can reach the tunnel, with no
    # token required.
    timeout = 15

    def _authorised(self) -> bool:
        header = self.headers.get("Authorization", "")
        presented = header[7:] if header.startswith("Bearer ") else ""
        # Compare as BYTES. http.server decodes headers as Latin-1, and
        # compare_digest raises TypeError on a str containing a non-ASCII
        # character -- so a single header byte like 0xE9 crashed the handler
        # thread before any token check, unauthenticated.
        try:
            return hmac.compare_digest(
                presented.encode("utf-8", "replace"), TOKEN.encode("utf-8")
            )
        except (TypeError, ValueError, AttributeError):
            return False

    def _reject(self, status: int, payload: dict):
        """Refuse a request without leaving its body in the socket.

        An undrained body on a keep-alive connection is parsed as the next
        request line, which desynchronises the stream.
        """
        try:
            pending = int(self.headers.get("Content-Length", 0))
        except ValueError:
            pending = 0
        if 0 < pending <= MAX_REQUEST_BYTES:
            try:
                self.rfile.read(pending)
            except OSError:
                pass
        self.close_connection = True
        self._send(status, payload)

    def _send(self, status: int, payload: dict | None):
        body = json.dumps(payload).encode() if payload is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_POST(self):
        if not self._authorised():
            self._reject(401, {"error": "unauthorized"})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_REQUEST_BYTES:
            # Cap the body. Nothing legitimate is large, and reading an
            # attacker-declared length is how a server gets held open.
            self.close_connection = True
            self._send(413, {"error": "request too large"})
            return

        try:
            message = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send(400, {"jsonrpc": "2.0", "id": None,
                             "error": {"code": -32700, "message": "parse error"}})
            return

        if not isinstance(message, dict):
            self._send(400, {"jsonrpc": "2.0", "id": None,
                             "error": {"code": -32600, "message": "invalid request"}})
            return

        reply = handle_rpc(message)
        self._send(202 if reply is None else 200, reply)

    def do_GET(self):
        # Health check only. Deliberately reveals nothing without the token.
        if not self._authorised():
            self._reject(401, {"error": "unauthorized"})
            return
        self._send(200, {"status": "ok", "root": str(ROOT), "version": "3.0.0"})

    def log_message(self, fmt, *args):
        sys.stderr.write(f"  {self.address_string()} {fmt % args}\n")


def main() -> int:
    global ROOT, TOKEN, ALLOW_SECRETS

    parser = argparse.ArgumentParser(description="Read-only MCP bridge to a folder on this machine.")
    parser.add_argument("--root", required=True, help="folder to share, read only")
    parser.add_argument("--token", default=os.environ.get("MCP_TOKEN", ""),
                        help="bearer token clients must present (or set MCP_TOKEN)")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--host", default="127.0.0.1",
                        help="keep this on localhost and put a tunnel in front")
    parser.add_argument("--allow-secrets", action="store_true",
                        help="DISABLE the credential filters. Everything readable becomes "
                             "readable, including SSH keys and browser password stores.")
    args = parser.parse_args()

    if len(args.token) < 20:
        print("error: --token must be at least 20 characters.", file=sys.stderr)
        print("A tunnel URL is not a secret. Generate one with:", file=sys.stderr)
        print("    openssl rand -hex 24", file=sys.stderr)
        return 2

    ROOT = pathlib.Path(args.root).expanduser().resolve()
    TOKEN = args.token
    ALLOW_SECRETS = args.allow_secrets

    if not ROOT.is_dir():
        print(f"error: {ROOT} is not a directory", file=sys.stderr)
        return 1

    # Sharing a drive root or a home directory is a different proposition from
    # sharing a project folder. Say so plainly rather than letting it pass.
    wide = ROOT == pathlib.Path(ROOT.anchor) or ROOT == pathlib.Path.home()
    if wide or ALLOW_SECRETS:
        print("=" * 68)
        if wide:
            print(f"WIDE SHARE: {ROOT} covers everything below it.")
        if ALLOW_SECRETS:
            print("CREDENTIAL FILTERS ARE OFF. Keys and password stores are readable.")
        print("Anyone with the URL and token gets this. Kill the tunnel when done.")
        print("=" * 68)

    print(f"sharing {ROOT} (read only) on http://{args.host}:{args.port}")
    print("tools: list_directory, read_file, search_files, find_files, describe_root")
    print("Ctrl-C to stop. Nothing can reach this until you put a tunnel in front of it.\n")

    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
