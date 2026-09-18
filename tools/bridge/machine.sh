#!/usr/bin/env bash
# Git Bash / macOS / Linux equivalent of machine.cmd
set -euo pipefail

# ============ EDIT THESE TWO LINES ONCE ============
ROOT="${ROOT:-/c/Users/Admin/Desktop/first-roblox-game}"
TUNNEL="${TUNNEL:-cloudflared}"
NGROK_DOMAIN="${NGROK_DOMAIN:-}"
# ==================================================

PORT="${PORT:-8787}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENFILE="$HOME/.machine-bridge-token"

PY=""
for c in py python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)' >/dev/null 2>&1; then
    PY="$c"; break
  fi
done
[ -n "$PY" ] || { echo "Python 3.8+ not found. Install it and tick 'Add to PATH'."; exit 1; }
[ -d "$ROOT" ] || { echo "ROOT does not exist: $ROOT — edit the top of this file."; exit 1; }

if [ ! -f "$TOKENFILE" ]; then
  "$PY" -c "import secrets;print(secrets.token_hex(24),end='')" > "$TOKENFILE"
  chmod 600 "$TOKENFILE" 2>/dev/null || true
  echo "  Generated a new token: $TOKENFILE"
fi
TOKEN="$(cat "$TOKENFILE")"

printf '\n  root   %s\n  port   %s\n  token  %s\n\n' "$ROOT" "$PORT" "$TOKEN"

"$PY" "$HERE/machine_mcp.py" --root "$ROOT" --token "$TOKEN" --port "$PORT" &
SERVER=$!
# Stop the server whichever way this script exits, so no orphan keeps the
# port -- and your disk -- open after the tunnel dies.
trap 'kill $SERVER 2>/dev/null || true' EXIT INT TERM
sleep 1

if [ "$TUNNEL" = "ngrok" ]; then
  cat <<MSG
  Registration line (paste to Claude ONCE, it never changes):

  claude mcp add --transport http my-machine https://$NGROK_DOMAIN/ --header "Authorization: Bearer $TOKEN"

  Starting tunnel on your fixed domain. Ctrl-C to stop everything.

MSG
  ngrok http --url="https://$NGROK_DOMAIN" "$PORT"
else
  echo "  Using cloudflared. Set TUNNEL=ngrok to switch."
  echo "  Send Claude the https://...trycloudflare.com line below AND the token."
  echo "  You will have to redo this every restart."
  echo
  cloudflared tunnel --url "http://127.0.0.1:$PORT"
fi
