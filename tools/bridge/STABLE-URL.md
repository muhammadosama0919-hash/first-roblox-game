# A permanent URL, so you stop pasting one every time

The tunnel is what keeps changing, not the bridge. A `trycloudflare.com` quick
tunnel mints a new random hostname on every start, and a Claude session reads
its configuration **once, at startup** — so a rotating URL can never be
automated away. Fix the URL and the pasting stops.

**Tailscale Funnel** gives a permanent `https://<machine>.<tailnet>.ts.net`
address. Free on the Personal plan, no domain to buy, no DNS to configure. It
installs as a Windows service that starts at boot, and with `--bg` the tunnel
resumes by itself afterwards — so there is eventually nothing to open at all.

## One-time setup

**1. Install Tailscale.** In PowerShell:

```powershell
winget install --id Tailscale.Tailscale -e
```

Then click the tray icon, choose **Log in**, and sign in with Google or GitHub.

**2. Turn on HTTPS.** Go to `login.tailscale.com/admin/dns`. Enable **MagicDNS**
if it is off, then under **HTTPS Certificates** click **Enable HTTPS**. Funnel
does not work without this.

**3. Pin the machine name.** Do not skip this. By default Tailscale re-derives
the name from your Windows computer name at every start, so renaming the PC
would silently change your public URL months from now:

```powershell
tailscale set --hostname=mcp-box
```

**4. Start machine-bridge.exe** as usual, so the server is listening on 8787.

**5. Publish it.** Open PowerShell **as Administrator** (right-click Start →
Terminal (Admin)):

```powershell
tailscale funnel --bg --https=443 http://127.0.0.1:8787
```

`--bg` is the whole point — without it the tunnel dies with the terminal and
does not come back after a reboot. If a browser opens asking you to approve
Funnel, approve it; that writes the permission into your account so there is no
policy file to hand-edit.

**6. Read your permanent URL:**

```powershell
tailscale funnel status
```

It prints something like `https://mcp-box.yak-bebop.ts.net`. That address is
yours from now on.

**7. Test it from outside — the only test that counts.** On your phone with
**wifi off**, open that URL. You should see `{"error": "unauthorized"}`, which
means the server is alive and refusing anonymous callers, exactly as it should.
Allow up to ten minutes the first time for DNS to propagate.

If the phone cannot reach it even though `tailscale funnel status` looks
correct, that is a known Windows bug. In the admin PowerShell:

```powershell
sc.exe stop Tailscale
sc.exe start Tailscale
```

**8. Do NOT make the server start itself.**

You could drop `machine-bridge.exe` into `shell:startup` so it comes up with
Windows. **Don't**, unless you have decided you want that. Opening the exe by
hand is a real security control: the folder is reachable only while you are
deliberately using it, and closing the window ends the exposure. Autostart
quietly converts that into a service that is live whenever the PC is on.

Leaving the Funnel itself running with `--bg` is fine and does not expose
anything on its own. With nothing listening on `127.0.0.1:8787`, Tailscale has
no origin to forward to and simply returns an error. **The exe is the switch.**
That is the combination worth having: a URL that never changes, and an exposure
that exists only while you are working.

## Then, per repo: auto-connect with no pasting

With a stable URL this file is worth committing. Drop it at the root of any
repo you want connected, on the branch the session checks out:

`.mcp.json`

```json
{
  "mcpServers": {
    "my-machine": {
      "type": "http",
      "url": "https://mcp-box.yak-bebop.ts.net/",
      "headers": {
        "Authorization": "Bearer ${LOCAL_MCP_TOKEN}"
      }
    }
  }
}
```

`"type": "http"` is required — without it Claude Code reads the entry as a
local program and fails. Never hardcode the token; `${VAR}` and
`${VAR:-default}` are both supported in `url` and `headers`.

Two settings on your cloud environment at claude.ai/code, done once:

- **Environment variables** → add `LOCAL_MCP_TOKEN=<your token>`
- **Network access** → set to **Custom**, add `mcp-box.yak-bebop.ts.net` to
  **Allowed domains**, and tick *"Also include default list of common package
  managers"* so npm and PyPI keep working.

That second one is the step everyone misses. An MCP server named in `.mcp.json`
is reached over the session's own network, and the default **Trusted** setting
allows only Anthropic's package registries — so without it the server appears
configured and every call fails.

Start a **new** session and run `/mcp`. It should list the server as connected.
Project-scoped servers load without an approval prompt in cloud sessions.

## Things that will bite you

- **The bridge must be running.** If the exe is closed, or the PC is asleep, a
  session starts normally and the tools are simply *absent* — no error, nothing
  to see. That is the intended behaviour, not a fault.
- **Closing the window ends the exposure, but not the token.** The secret is
  kept in `machine-bridge.json` so the registration stays valid next time.
  Anyone who captured it while you were working could use it the next time you
  open the bridge. Delete that file to force a new one.
- **A changed URL or token means a NEW session.** Configuration is read once at
  startup; there is no way to push a new address into a running session.
- **Your `.ts.net` hostname is not a secret.** Issuing an HTTPS certificate
  publishes it to public Certificate Transparency logs, which people scrape.
  The token is the only thing guarding the folder.
- **Environment variables on a cloud environment are readable by anyone who
  uses that environment.** Treat this token as low-value and rotatable, which
  it is — delete `machine-bridge.json` to get a fresh one.
