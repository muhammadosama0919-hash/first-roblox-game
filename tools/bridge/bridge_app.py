#!/usr/bin/env python3
"""
Double-clickable front end for machine_mcp.

Built as a single Windows .exe so there is nothing to install: no Python, no
pip, no PATH checkbox. Open it and the bridge is up.

First run asks two questions and remembers the answers. Every run after that
asks nothing — it starts the server, starts the tunnel, and prints the one
registration line.
"""

from __future__ import annotations

import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys
import threading
import traceback
import urllib.error
import urllib.request
import time
from http.server import ThreadingHTTPServer

import machine_mcp

PORT = 8787
APP_NAME = "machine-bridge"


def config_path() -> pathlib.Path:
    """Beside the .exe if that is writable, else %APPDATA%.

    Keeping it beside the exe means moving the exe moves its settings, which is
    what someone expects of a portable tool; falling back matters when it lands
    somewhere read-only like Downloads under a locked-down policy.
    """
    if getattr(sys, "frozen", False):
        beside = pathlib.Path(sys.executable).parent / f"{APP_NAME}.json"
        try:
            beside.touch(exist_ok=True)
            return beside
        except OSError:
            pass

    base = os.environ.get("APPDATA") or os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home()
    folder = pathlib.Path(base) / APP_NAME
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "config.json"


def load(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text() or "{}")
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save(path: pathlib.Path, config: dict) -> None:
    path.write_text(json.dumps(config, indent=2))
    # Best effort: the token lives in here.
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def pick_folder() -> str:
    """A folder picker, falling back to typing.

    Asking someone to type an absolute Windows path is where this kind of tool
    usually loses people; a picker removes the whole class of typo.
    """
    try:
        import tkinter
        from tkinter import filedialog

        root = tkinter.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        chosen = filedialog.askdirectory(title="Choose the project folder to share (read only)")
        root.destroy()
        if chosen:
            return chosen
    except Exception:                                   # noqa: BLE001 - headless, no tk, cancelled
        pass

    return input("  Full path to the folder to share: ").strip().strip('"')


def first_run(config: dict) -> dict:
    print("  First run — two questions, then never again.\n")

    print("  1. Which folder should Claude be able to READ?")
    print("     Pick the project folder, not your whole user folder.\n")
    while True:
        chosen = pick_folder()
        if chosen and pathlib.Path(chosen).is_dir():
            config["root"] = str(pathlib.Path(chosen).resolve())
            break
        print("     Not a folder. Try again.\n")
    print(f"     -> {config['root']}\n")

    print("  2. Which tunnel should put this on a public URL?")
    print("       1) cloudflared  — no account, no limits to think about,")
    print("                         but a NEW URL every time you start it")
    print("       2) ngrok        — free account; a static domain keeps the")
    print("                         URL fixed, but the free tier is metered")
    choice = input("     1 or 2 [1]: ").strip() or "1"
    config["tunnel"] = "ngrok" if choice == "2" else "cloudflared"
    print(f"     -> {config['tunnel']}")

    config["ngrok_domain"] = ""
    if config["tunnel"] == "ngrok":
        domain = input("     ngrok static domain, if you have one (Enter to skip): ")
        config["ngrok_domain"] = domain.strip().replace("https://", "").rstrip("/")
    print()

    config["token"] = secrets.token_hex(24)
    return config


class BridgeServer(ThreadingHTTPServer):
    """A server that complains instead of failing quietly.

    allow_reuse_address is OFF deliberately. On Windows, unlike Linux, it lets
    a SECOND process bind a port a first one already holds -- so a stale copy
    keeps answering while a new one reports a clean start, and the new settings
    appear to do nothing. Refusing to start is far easier to understand.
    """

    allow_reuse_address = False
    daemon_threads = True

    def handle_error(self, request, client_address):
        # The default prints to stderr and carries on, which next to
        # cloudflared's output is invisible. A handler that crashes closes the
        # connection with no reply, which looks exactly like the server being
        # down -- so say so, loudly, on stdout.
        print("\n  !! a request crashed the handler:")
        traceback.print_exc()
        print()


def self_check(token: str) -> tuple[bool, str]:
    """Ask our own server for a reply before handing the port to a tunnel.

    If this fails, no tunnel can help, and the fault is ours rather than the
    tunnel's -- which is exactly the distinction that cannot be made from the
    far side of a 502.
    """
    request = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/", headers={"Authorization": f"Bearer {token}"}
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return True, f"HTTP {response.status} {response.read(160).decode('utf-8', 'replace')}"
    except urllib.error.HTTPError as exc:
        return True, f"HTTP {exc.code} (the server answered, which is what matters)"
    except Exception as exc:                            # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"


def start_server(root: str, token: str) -> ThreadingHTTPServer:
    machine_mcp.ROOT = pathlib.Path(root).expanduser().resolve()
    machine_mcp.TOKEN = token
    machine_mcp.ALLOW_SECRETS = False

    server = BridgeServer(("127.0.0.1", PORT), machine_mcp.Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def tunnel_command(config: dict) -> tuple[list[str] | None, str]:
    """Pick the tunnel the config asks for, not whichever happens to be installed.

    This used to probe PATH and take ngrok whenever it found it, which silently
    overrode the choice: someone who had ngrok installed for something else got
    ngrok whether they wanted it or not, and had to move the binary aside to
    use anything else. The config decides; PATH only says whether it is there.
    """
    port = str(PORT)
    wanted = (config.get("tunnel") or "auto").lower()
    domain = config.get("ngrok_domain", "")

    def ngrok():
        if not shutil.which("ngrok"):
            return None
        if domain:
            return ["ngrok", "http", f"--url=https://{domain}", port]
        return ["ngrok", "http", f"127.0.0.1:{port}"]

    def cloudflared():
        if not shutil.which("cloudflared"):
            return None
        # 127.0.0.1, not "localhost": on Windows localhost resolves to ::1
        # first, and the server binds IPv4 only, so the tunnel would dial an
        # address nothing is listening on.
        return ["cloudflared", "tunnel", "--url", f"http://127.0.0.1:{port}"]

    if wanted == "ngrok":
        return ngrok(), "ngrok"
    if wanted == "cloudflared":
        return cloudflared(), "cloudflared"

    # auto: prefer the one that needs no account.
    chosen = cloudflared()
    if chosen:
        return chosen, "cloudflared"
    return ngrok(), "ngrok"


INSTALL_HINT = {
    "cloudflared": (
        "  Download one file, rename it to cloudflared.exe, and put it in THIS folder:\n"
        "    https://github.com/cloudflare/cloudflared/releases/latest/download/"
        "cloudflared-windows-amd64.exe"
    ),
    "ngrok": "  Install from https://ngrok.com/download",
}


def unbuffer() -> None:
    """Flush every line immediately.

    Python block-buffers stdout whenever it is not a terminal. Redirect this
    program to a file or pipe it, and the banner sits in a buffer until the
    process exits -- but it deliberately does not exit, it waits on the tunnel.
    The result is an empty log and the appearance of a program that never
    started. (This is exactly how the first CI build failed.)
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(line_buffering=True)
        except (AttributeError, ValueError):
            pass


def selftest() -> int:
    """Prove a downloaded binary actually runs, without touching any config.

    Deliberately opens no dialog, writes no file and binds no port, so it is
    safe to run on a build machine and safe for you to run on a fresh download
    before trusting it.
    """
    print(f"  {APP_NAME} self-test")
    print(f"  python   {sys.version.split()[0]}")
    print(f"  frozen   {getattr(sys, 'frozen', False)}")
    print(f"  tools    {', '.join(sorted(machine_mcp.HANDLERS))}")
    print(f"  tunnels  cloudflared={bool(shutil.which('cloudflared'))} ngrok={bool(shutil.which('ngrok'))}")
    print(f"  access   READ ONLY — no write, delete or execute tool exists")
    print("  OK")
    return 0


def main() -> int:
    unbuffer()

    if "--selftest" in sys.argv:
        return selftest()

    override = ""
    if "--tunnel" in sys.argv:
        try:
            override = sys.argv[sys.argv.index("--tunnel") + 1].lower()
        except IndexError:
            print("  --tunnel needs a value: cloudflared, ngrok or auto")
            return 2
        if override not in ("cloudflared", "ngrok", "auto"):
            print(f"  unknown tunnel: {override}")
            return 2

    print()
    print("  " + "=" * 64)
    print(f"  {APP_NAME}  —  read-only bridge from this PC to a Claude session")
    print("  " + "=" * 64)
    print()

    path = config_path()
    config = load(path)
    fresh = "root" not in config or "token" not in config

    if fresh:
        config = first_run(config)
        save(path, config)
    elif not pathlib.Path(config["root"]).is_dir():
        print(f"  The saved folder no longer exists:\n    {config['root']}\n")
        config = first_run(config)
        save(path, config)

    if override:
        config["tunnel"] = override
    root, token, domain = config["root"], config["token"], config.get("ngrok_domain", "")

    print(f"  sharing  {root}")
    print(f"  config   {path}")
    print(f"  access   READ ONLY — no write, delete or execute tool exists")
    print(f"  tunnel   {config.get('tunnel', 'auto')}")
    print()

    try:
        start_server(root, token)
    except OSError as exc:
        print(f"  Could not open port {PORT}: {exc}")
        print("  Another copy is probably already running. Close it and retry.")
        input("\n  Enter to close.")
        return 1

    if domain:
        print("  Paste this to Claude ONCE — the URL and token never change:\n")
        print(f'    claude mcp add --transport http my-machine https://{domain}/ \\')
        print(f'      --header "Authorization: Bearer {token}"')
    else:
        print("  No static domain set, so the URL below is new every restart.")
        print("  Send Claude the https://...trycloudflare.com line AND this token:\n")
        print(f"    {token}")
    print()

    ok, detail = self_check(token)
    print(f"  self-check  {'PASS' if ok else 'FAIL'}  {detail}")
    if not ok:
        print()
        print("  The server will not answer its own requests, so no tunnel can help.")
        print("  Anything above starting with '!!' is the reason. If there is nothing,")
        print("  another copy may hold the port: check Task Manager for stray")
        print("  machine-bridge.exe processes and end them.")
        input("\n  Enter to close.")
        return 1
    print()

    command, picked = tunnel_command(config)
    if command is None:
        print(f"  Tunnel '{picked}' is selected but not installed.")
        print(INSTALL_HINT.get(picked, ""))
        print()
        print("  Then open this again. (Or run with --tunnel ngrok / --tunnel cloudflared")
        print(f"  to use the other one.) Config: {path}")
        print()
        print(f"  The server is running locally on http://127.0.0.1:{PORT} in the meantime.")
        input("  Enter to stop.")
        return 0

    print(f"  Starting tunnel: {' '.join(command)}")
    print("  Close this window to stop everything.\n")

    try:
        subprocess.run(command)
    except KeyboardInterrupt:
        pass
    except FileNotFoundError:
        print("  Tunnel program vanished from PATH.")

    print("\n  Tunnel closed. Server stopped.")
    time.sleep(1)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:                            # noqa: BLE001
        # A .exe that vanishes on error tells the user nothing. Hold the window.
        print(f"\n  Unexpected error: {exc!r}")
        input("\n  Enter to close.")
        raise
