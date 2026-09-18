# machine-bridge — one-command setup

Makes one folder on your PC readable from a cloud Claude session. Read only.

## Is there a single line?

**Yes, after a one-time setup — and no, without it.** The thing standing in the
way is not the script, it's the URL.

A `trycloudflare.com` quick tunnel invents a **new random URL every restart**.
The cloud session has no inbound route, so it cannot discover that URL; it has
to travel from your screen to Claude by you pasting it. That paste is
unavoidable *while the URL keeps changing*.

Give the tunnel a **permanent address** and the paste happens exactly once,
ever. After that, starting the bridge is one command.

## One-time setup (about 5 minutes)

**1. Python** — if `py --version` in Git Bash prints nothing, install from
python.org and **tick "Add python.exe to PATH"**. That checkbox is why
`python` was not found last time.

**2. A permanent URL.** ngrok gives one free static domain per account:

- Sign up at `dashboard.ngrok.com`
- **Domains → New Domain** → you get something like `osama-dev.ngrok-free.app`, yours permanently
- Copy your authtoken from **Your Authtoken**, then run once:
  `ngrok config add-authtoken YOUR_AUTHTOKEN`

**3. Point the launcher at your folder.** Open `machine.cmd` and edit the two
lines at the top:

```bat
set "ROOT=C:\Users\Admin\Desktop\first-roblox-game"
set "NGROK_DOMAIN=osama-dev.ngrok-free.app"
```

**4. Run it once.** It generates a token, saves it to
`%USERPROFILE%\.machine-bridge-token`, and prints a registration line. Give
that line to Claude **once**. Both the URL and the token are now permanent, so
it never needs repeating.

## Every time after that

```
machine.cmd
```

That's the single line. Double-click works too. Ctrl-C stops the tunnel and the
server together.

Without step 2 it still works, but you re-paste a new URL on every restart.

## Choosing the tunnel

The tunnel is a setting, not a guess. First run asks; after that it lives in
`machine-bridge.json` next to the exe as `"tunnel": "cloudflared"` or
`"ngrok"`, and `--tunnel cloudflared` / `--tunnel ngrok` overrides it for one
run without editing anything.

Earlier versions probed PATH and took ngrok whenever they found it, which
silently overrode the choice — if you had ngrok installed for something else
you got ngrok, and had to move the binary aside to use anything else.

**cloudflared** needs no account and nothing metered, but hands you a new URL
every start. **ngrok** free is metered (1 GB and 20,000 requests a month) and a
static domain keeps the URL fixed. For reading source files the metering is not
close to binding — the whole project is under a megabyte — but cloudflared is
the default because it needs no signup.

## What it exposes

| Tool | Does |
| --- | --- |
| `list_directory` | Lists a folder inside the root, with sizes |
| `read_file` | Reads UTF-8 text with line numbers; **pages** through big files |
| `search_files` | Regex across files, returns `path:line: text` |
| `find_files` | Recursive glob, e.g. `*.luau` |
| `describe_root` | Reports what is shared and what is refused |

**There is no write, delete, move or execute tool, deliberately.** A connector
that runs commands is a remote shell, and a remote shell on a public URL is the
single worst thing to get wrong.

## Security review

v2 of this script was put through an adversarial review: four independent
reviewers attacking it from different angles (path escape, authentication,
resource exhaustion, plain correctness), then a separate reviewer per finding
whose job was to *refute* it by running the real code. Twelve findings survived
refutation. All twelve are fixed in v3. Five were serious:

| Severity | Defect |
| --- | --- |
| **high** | `search_files`/`find_files` passed the client's `glob` straight to `rglob()`, and pathlib expands `..` inside a glob. `glob="../../../../etc/passwd"` was an **arbitrary file read** of anything the operator could read. This was in v1 too, via `find_files`. |
| **high** | Windows respellings (`credentials.`, `.env `, `.env::$DATA`) matched no deny pattern but open the real file. |
| **high** | A file with no newlines (a minified bundle, a one-line `.rbxlx`) was pulled **entirely into memory** — the opposite of the streaming this file claimed. |
| **high** | A line longer than the response budget was a permanent dead end: the page looked like a clean EOF and the rest of the file was silently unreachable at any offset. |
| **high** | `search_files` ran the client's regex with no bound, so `(a+)+b` froze the whole single-process server. |

And seven lesser ones: `DENY_DIRS` matched against the root's own ancestors (a
project at `C:\dev\game` sits under "dev", so every file in it was refused); a
non-ASCII `Authorization` byte crashed the handler thread *before* the token
check, unauthenticated; no socket timeout, so a half-open connection pinned a
thread forever; 401s left the request body in the socket, desyncing keep-alive;
symlinks and NTFS junctions inside the root were followed out of it; a negative
`max_results` reported a confident `0 match(es)` on a tree full of matches; and
the "capped at N" suffix fired when the result set was exactly complete.

**One guard is a heuristic, not a proof.** A single `re.search()` cannot be
interrupted from Python, so catastrophic backtracking is blocked by *refusing
the pattern shape* `(...+)+` rather than by timing the match out. A determined
attacker holding the token could likely still craft a slow pattern. The token
is the real boundary; this only stops an accident.

## What changed from v1

- **`read_file` pages instead of refusing.** v1 capped at 256 KB per *file*, which
  made your 585 KB `World.luau` unreadable — the most important file in the
  project. The cap is now per *response*: big files arrive in pages.
- **`search_files` added.** Finding one function in 585 KB by reading it in pages
  is absurd. A regex finds it in one call.
- **Line numbers on every read**, so a follow-up page can be requested precisely.
- **Four holes closed**, found by reviewing v1 against Windows path semantics:
  - `.env:$DATA` — NTFS alternate data streams bypassed *every* deny glob and
    served the exact bytes of `.env`. Colons in path components are now refused.
  - `.env ` / `.env.` — Windows silently strips trailing dots and spaces, so these
    opened `.env` while matching no filter. Now refused.
  - Directories were never checked against the deny policy, only their contents.
  - Request bodies were read at an attacker-declared `Content-Length`, uncapped.

## The honest risks

**The tunnel is public while it runs.** Anyone who learns the URL can reach the
server; the token is the only thing stopping them. A static domain is more
convenient *and* more guessable than a random one — which is fine, because the
192-bit token is the real defence, but it means: never paste the token anywhere
public, and kill the tunnel when you are done.

**The deny-list is a safety net, not a boundary.** It blocks obvious secret
filenames. It will not catch an API key pasted inside a `.luau` file. The real
protection is `ROOT` pointing at one project folder.

**Anything readable is readable by the model, and enters the conversation.**
