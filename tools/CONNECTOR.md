# A custom connector to your machine

This makes a folder on your computer readable from a Claude session running in
the cloud. It is an MCP server — the same mechanism the `github` and `Supabase`
connectors use.

**Read this whole file before running it.** It puts a folder of your disk behind
a public URL, and that is a thing worth understanding before you do it.

## Why it has to work this way

The cloud session has **no inbound route**. Nothing on the internet can dial into
it — that was verified directly, and it is why nothing can "see your machine"
today. Every connector it has is a service it reaches *outbound* over HTTPS.

So the arrow has to point the other way:

```
   cloud session  ──outbound HTTPS──▶  public URL  ──tunnel──▶  your machine
```

Your machine never accepts a connection from Claude. The tunnel service holds an
outbound connection from your side, and traffic flows back down it. That is also
why this works through a home router with no port forwarding.

## Setup

### 1. Generate a token

The tunnel URL is **not** a secret — it is a URL, and URLs end up in logs,
history and error reports. The token is what actually protects you.

```sh
openssl rand -hex 24
```

Windows PowerShell:

```powershell
-join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

### 2. Run the server

Python 3 only, no packages to install.

```sh
python3 machine_mcp.py --root ~/roblox-projects --token PASTE_TOKEN_HERE
```

Point `--root` at the **narrowest folder that is useful**. Not your home
directory. Not `C:\`. The folder holding the project and nothing else.

It binds to `127.0.0.1` on purpose — until you do step 3, nothing outside your
machine can reach it at all.

### 3. Put a public HTTPS URL in front of it

Either works; Cloudflare needs no account for a quick tunnel.

```sh
cloudflared tunnel --url http://localhost:8787
# or
ngrok http 8787
```

Both print a URL like `https://something-random.trycloudflare.com`.

### 4. Register it

```sh
claude mcp add --transport http my-machine https://YOUR-TUNNEL-URL/mcp \
  --header "Authorization: Bearer PASTE_TOKEN_HERE"
```

For a cloud session, the project-scoped form is more likely to reach it —
`.mcp.json` committed at the repo root, which the session clones:

```jsonc
{
  "mcpServers": {
    "my-machine": {
      "type": "http",
      "url": "${MACHINE_URL}/mcp",
      "headers": { "Authorization": "Bearer ${MACHINE_TOKEN}" }
    }
  }
}
```

Use `${VARIABLES}`, not literals. A token committed to git is a token you have
published, and rotating it later does not un-publish it.

## What it exposes

| Tool | Does |
| --- | --- |
| `list_directory` | Lists a folder inside the root |
| `read_file` | Reads one UTF-8 text file, up to 256 KB |
| `find_files` | Recursive glob, e.g. `*.luau` |
| `describe_root` | Reports what is shared and what is refused |

**There is no write, delete, move or execute tool, deliberately.** A connector
that runs commands is a remote shell. A remote shell on a public URL is the
single worst thing to get wrong here, so it does not exist rather than being
guarded.

Tested and passing:

- No token, or a wrong token → `401`
- `../../../../etc/passwd` → refused, path escapes the root
- `/etc/passwd` → refused
- `.env` → refused by filename policy, and hidden from listings
- Files over 256 KB, and non-UTF-8 files → refused rather than streamed

The token is compared in constant time, because a naive `==` leaks it one
character at a time to anyone who can measure response timing.

## The honest risks

**The tunnel is public while it runs.** Anyone who learns the URL can reach the
server. The token is the only thing stopping them. Treat it like a password,
and kill the tunnel when you are done rather than leaving it up.

**Free tunnel URLs are not authenticated.** `trycloudflare.com` quick tunnels
have no access control of their own — this server's token is the whole defence.

**The deny-list is a safety net, not a boundary.** It blocks obvious secret
filenames. It will not catch an API key pasted into a `.luau` file. The real
protection is `--root` pointing somewhere narrow.

**Anything readable is readable by the model, and enters the conversation.**
Do not share a folder containing anything you would not paste into a chat.

## If you want it to reach Roblox Studio too

This reads files. It does not touch Studio. Studio's own MCP server already
exists and exposes reading the DataModel, running Luau and taking screenshots —
but it speaks **stdio**, meaning it only talks to a client on the same machine.
Bridging that to a cloud session would mean writing an HTTP MCP server that
proxies to it, which is a bigger job and a much larger blast radius, since those
tools can execute code in your place.
