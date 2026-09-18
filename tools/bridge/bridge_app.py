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

    print("  2. ngrok static domain, if you have one (Enter to skip).")
    print("     With one, the URL never changes and you register with Claude ONCE.")
    print("     Without one, you paste a fresh cloudflare URL on every restart.")
    domain = input("     domain: ").strip().replace("https://", "").rstrip("/")
    config["ngrok_domain"] = domain
    print()

    config["token"] = secrets.token_hex(24)
    return config


def start_server(root: str, token: str) -> ThreadingHTTPServer:
    machine_mcp.ROOT = pathlib.Path(root).expanduser().resolve()
    machine_mcp.TOKEN = token
    machine_mcp.ALLOW_SECRETS = False

    server = ThreadingHTTPServer(("127.0.0.1", PORT), machine_mcp.Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def tunnel_command(domain: str) -> list[str] | None:
    if domain and shutil.which("ngrok"):
        return ["ngrok", "http", f"--url=https://{domain}", str(PORT)]
    if shutil.which("ngrok"):
        return ["ngrok", "http", str(PORT)]
    if shutil.which("cloudflared"):
        return ["cloudflared", "tunnel", "--url", f"http://localhost:{PORT}"]
    return None


def main() -> int:
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

    root, token, domain = config["root"], config["token"], config.get("ngrok_domain", "")

    print(f"  sharing  {root}")
    print(f"  config   {path}")
    print(f"  access   READ ONLY — no write, delete or execute tool exists")
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

    command = tunnel_command(domain)
    if command is None:
        print("  No tunnel program found on PATH.")
        print("  Install ONE of these, then open this again:")
        print("    ngrok       https://ngrok.com/download   (free static domain)")
        print("    cloudflared https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/")
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
