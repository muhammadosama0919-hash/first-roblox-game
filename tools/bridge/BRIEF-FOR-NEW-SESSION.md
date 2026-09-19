# Briefing: you have a read-only bridge to the developer's Windows machine

**Read this first. It is addressed to you, the assistant, not to the user.**

The developer runs a small Python MCP server on their Windows PC that exposes
**one folder, read-only**, and puts a public HTTPS tunnel in front of it. You are
in a cloud container and cannot otherwise see their disk at all. This document
tells you how to reach it.

Fill these in from the developer's message. If either is missing, **ask for it
before doing anything else** — nothing here works without both.

```
BRIDGE_URL   = https://__________________.trycloudflare.com
BRIDGE_TOKEN = ________________________________________________
```

The developer gets both by opening `machine-bridge.exe` on their PC; it prints
the token, then the tunnel prints the URL. **If that window is closed, nothing
below works** — that is deliberate, not a fault. Ask them to open it.

---

## 1. Connect

There are two possible ways in. Check for the first; fall back to the second.

**If you have MCP tools** named `list_directory`, `read_file`, `search_files`,
`find_files`, `describe_root`, the bridge is already registered. Use them
directly and skip to section 3.

**Otherwise use HTTP**, which always works as long as the tunnel is up. The
bridge speaks MCP over JSON-RPC 2.0. Set up a helper once:

```bash
cat > /tmp/bridge.sh <<'EOF'
URL="https://PASTE-THE-URL-HERE"
TOK="PASTE-THE-TOKEN-HERE"
call() {
  name="$1"; args="${2:-{\}}"
  curl -sS --max-time 45 \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$name\",\"arguments\":$args}}" \
    "$URL/" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['content'][0]['text'])"
}
EOF
. /tmp/bridge.sh
```

Then every call is `call <tool> '<json args>'`.

## 2. Verify before trusting it

```bash
. /tmp/bridge.sh
call describe_root
```

A healthy reply names the shared folder and says `access: READ ONLY`. Anything
else — see section 5 — means stop and report, do not keep retrying.

## 3. The five tools

| Tool | Arguments | Notes |
| --- | --- | --- |
| `describe_root` | none | What is shared, and what is refused |
| `list_directory` | `{"path":"src/server"}` | Empty path means the root |
| `read_file` | `{"path":"src/server/World.luau","offset":1,"limit":200}` | Line-numbered; **pages** |
| `search_files` | `{"pattern":"function World\\.","glob":"*.luau"}` | Regex; returns `path:line: text` |
| `find_files` | `{"pattern":"*.luau"}` | Recursive glob |

**Search before you read.** Files here can be over half a megabyte. A regex that
returns matching lines costs about 2 KB; reading the same file costs 585 KB and
several calls. Locate first, then read the part you need.

**Reading a large file:** one response caps at 256 KB. When output ends with
`[more follows — call again with offset=N]`, that is the next page:

```bash
call read_file '{"path":"src/server/World.luau"}'
call read_file '{"path":"src/server/World.luau","offset":2982}'
```

`{"offset":900,"limit":60}` reads a specific window, which is usually what you
want after a search hit.

## 4. What you cannot do — read this before planning any work

**The bridge is read-only. There is no write, edit, delete, move or execute
tool, by design.** You cannot change a file on their machine, run their build,
start Rojo, or execute anything. A connector that runs commands is a remote
shell on a public URL, which is why it does not exist.

So the working loop is:

1. You **read** their code through the bridge.
2. You reason about it and write the change **here**.
3. You give the developer the patch or the full file, and **they** apply it.

Do not promise to edit their files. Do not write code that assumes you can.
If a task genuinely needs write access, say so plainly and let them decide —
adding it is their call, not yours.

Other limits worth knowing:

- **Text only.** Non-UTF-8 files are refused after about 64 KB, so `.fbx`,
  `.rbxl` and images cannot be transferred. Do not try.
- **Credential files are hidden.** Anything matching `*.env*`, `*credential*`,
  `*secret*`, `id_rsa*` and similar, plus whole directories named `env`,
  `secrets`, `vault`, `private`. If the startup banner warned about readable
  sensitive files, mention it once and move on; it is the developer's call.
- **Nothing escapes the shared folder.** `..`, absolute paths, symlinks out of
  the tree and traversal inside a glob are all refused. Do not attempt them —
  it is not a puzzle to solve, it is the boundary working.

## 5. When it does not work

| Symptom | Cause | What to tell the developer |
| --- | --- | --- |
| `HTTP 502` | The exe is not running, or the tunnel lost its origin | "Open `machine-bridge.exe`" |
| `HTTP 401` | Wrong or missing token | Ask them to re-read the token from the window |
| Connection refused / DNS failure | Tunnel is down, or the URL has changed | Quick-tunnel URLs change on every restart — ask for the current one |
| `WinError 10048` in their window | A stale copy holds port 8787 | `netstat -ano \| findstr :8787`, then `taskkill /PID <pid> /F` |
| `self-check FAIL` in their window | The bridge cannot answer its own request | The fault is local to their machine; a tunnel cannot help |
| MCP tools listed but every call fails | The session's network allowlist blocks the host | Set Network access to **Custom** and add the tunnel hostname |

A `502` is the common one, and it almost always means the window got closed.
Ask once, do not loop.

## 6. Handling the token

The token is a credential. **Do not echo it into your replies, do not write it
into any file in the repository, and do not commit it.** Keep it in
`/tmp/bridge.sh` and nowhere else. If the developer pastes it in chat, use it,
but do not repeat it back.

The tunnel is public while it runs; the token is the only thing guarding the
folder. When the work is done, remind them once that closing the window ends the
exposure.

---

## Start here

```bash
. /tmp/bridge.sh
call describe_root
call list_directory
```

Then tell the developer what you can see, and ask what they want built.
