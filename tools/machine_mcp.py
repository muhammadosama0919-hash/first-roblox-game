#!/usr/bin/env python3
"""
A minimal MCP server that lets a remote Claude session read files on this
machine. Python standard library only — no pip install.

    python3 machine_mcp.py --root ~/roblox-projects --token "$(openssl rand -hex 24)"

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
  * Binary files and oversized files are refused rather than streamed, so a
    stray read of a 2GB file cannot hang the session.
"""

from __future__ import annotations

import argparse
import fnmatch
import hmac
import json
import os
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOL_VERSION = "2025-06-18"
MAX_READ_BYTES = 256 * 1024
MAX_ENTRIES = 500

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
# them, and none of them contains anything worth sharing.
DENY_DIRS = {
    ".ssh", ".gnupg", ".aws", ".azure", ".config/gcloud", ".kube", ".docker",
    ".password-store", ".mozilla", ".thunderbird", "keychains", "library/keychains",
    "google/chrome", "bravesoftware", "microsoft/edge", "firefox",
    ".local/share/keyrings", "protected storage", "credentials",
    # OS internals: huge, useless to share, and full of system secrets
    "windows", "system32", "$recycle.bin", "system volume information",
    "/proc", "/sys", "/dev", "/private/var/db",
}

ROOT: pathlib.Path
TOKEN: str
ALLOW_SECRETS = False


# --------------------------------------------------------------------------- paths

def resolve(relative: str) -> pathlib.Path:
    """Resolve a client-supplied path inside ROOT, or raise."""
    candidate = (ROOT / relative.lstrip("/")).resolve()

    # Compare resolved paths: this is what defeats .., symlinks out of the tree,
    # and absolute paths smuggled in as the argument.
    if candidate != ROOT and ROOT not in candidate.parents:
        raise ValueError(f"path escapes the shared root: {relative}")

    return candidate


def denied(path: pathlib.Path) -> bool:
    """True if this path, or anything it sits inside, is off limits."""
    if ALLOW_SECRETS:
        return False

    name = path.name.lower()
    if any(fnmatch.fnmatch(name, pattern) for pattern in DENY_GLOBS):
        return True

    # Check every ancestor too. A key inside .ssh must stay hidden even when
    # the filename itself looks innocuous.
    lowered = str(path).replace("\\", "/").lower()
    return any(
        f"/{d}/" in lowered + "/" or lowered.endswith(f"/{d}")
        for d in DENY_DIRS
    )


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
        "description": "Read a UTF-8 text file inside the shared root.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
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


def tool_list_directory(args: dict) -> str:
    target = resolve(args.get("path", ""))
    if not target.is_dir():
        return f"not a directory: {args.get('path', '')}"

    rows = []
    for entry in sorted(target.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        if denied(entry):
            rows.append(f"  [hidden by policy]  {entry.name}")
            continue
        if entry.is_dir():
            rows.append(f"  <dir>   {entry.name}/")
        else:
            rows.append(f"  {entry.stat().st_size:>9,}  {entry.name}")
        if len(rows) >= MAX_ENTRIES:
            rows.append(f"  ... truncated at {MAX_ENTRIES} entries")
            break

    header = f"{target.relative_to(ROOT) if target != ROOT else '.'}  ({len(rows)} entries)"
    return header + "\n" + "\n".join(rows)


def tool_read_file(args: dict) -> str:
    target = resolve(args["path"])

    if denied(target):
        return "refused: this filename matches the connector's secret-file policy"
    if not target.is_file():
        return f"not a file: {args['path']}"

    size = target.stat().st_size
    if size > MAX_READ_BYTES:
        return f"refused: {size:,} bytes exceeds the {MAX_READ_BYTES:,} byte limit"

    try:
        return target.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return f"refused: {args['path']} is not UTF-8 text ({size:,} bytes)"


def tool_find_files(args: dict) -> str:
    base = resolve(args.get("path", ""))
    hits = []

    for found in base.rglob(args["pattern"]):
        if found.is_file() and not denied(found):
            hits.append(f"  {found.stat().st_size:>9,}  {found.relative_to(ROOT)}")
        if len(hits) >= MAX_ENTRIES:
            hits.append("  ... truncated")
            break

    return f"{len(hits)} match(es) for {args['pattern']}\n" + "\n".join(hits)


def tool_describe_root(_args: dict) -> str:
    return (
        f"sharing: {ROOT}\n"
        f"access: READ ONLY — no write, delete or execute tools exist\n"
        f"max file read: {MAX_READ_BYTES:,} bytes, UTF-8 text only\n"
        f"refused filename patterns: {', '.join(DENY_GLOBS)}"
    )


HANDLERS = {
    "list_directory": tool_list_directory,
    "read_file": tool_read_file,
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
            "serverInfo": {"name": "machine-bridge", "version": "1.0.0"},
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

    def _authorised(self) -> bool:
        header = self.headers.get("Authorization", "")
        presented = header[7:] if header.startswith("Bearer ") else ""
        # Constant-time compare: a naive == leaks the token one character at a
        # time to anyone who can measure the response.
        return hmac.compare_digest(presented, TOKEN)

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
            self._send(401, {"error": "unauthorized"})
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            message = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"jsonrpc": "2.0", "id": None,
                             "error": {"code": -32700, "message": "parse error"}})
            return

        reply = handle_rpc(message)
        self._send(202 if reply is None else 200, reply)

    def do_GET(self):
        # Health check only. Deliberately reveals nothing without the token.
        self._send(200 if self._authorised() else 401,
                   {"status": "ok", "root": str(ROOT)} if self._authorised() else {"error": "unauthorized"})

    def log_message(self, fmt, *args):
        sys.stderr.write(f"  {self.address_string()} {fmt % args}\n")


def main() -> int:
    global ROOT, TOKEN

    parser = argparse.ArgumentParser(description=__doc__)
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

    global ALLOW_SECRETS
    ROOT = pathlib.Path(args.root).expanduser().resolve()
    TOKEN = args.token
    ALLOW_SECRETS = args.allow_secrets

    if not ROOT.is_dir():
        print(f"error: {ROOT} is not a directory", file=sys.stderr)
        return 1

    # Sharing a drive root or a home directory is a different proposition from
    # sharing a project folder. Say so plainly rather than letting it pass.
    wide = ROOT == ROOT.anchor or ROOT == pathlib.Path.home()
    if wide or ALLOW_SECRETS:
        print("=" * 68)
        if wide:
            print(f"WIDE SHARE: {ROOT} covers everything below it.")
        if ALLOW_SECRETS:
            print("CREDENTIAL FILTERS ARE OFF. Keys and password stores are readable.")
        print("Anyone with the URL and token gets this. Kill the tunnel when done.")
        print("=" * 68)

    print(f"sharing {ROOT} (read only) on http://{args.host}:{args.port}")
    print("tools: list_directory, read_file, find_files, describe_root")
    print("Ctrl-C to stop. Nothing can reach this until you put a tunnel in front of it.\n")

    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
