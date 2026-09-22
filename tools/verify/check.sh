#!/usr/bin/env bash
# Execute src/server/Manor.luau for real (against the Roblox API shim), then
# prove the result is walkable and render it. Exits non-zero on any failure.
#
# Needs bin/luau and bin/stylua next to this script; README.md says where
# they come from.
set -euo pipefail
cd "$(dirname "$0")"

MANOR="${1:-../../src/server/Manor.luau}"

echo "== stylua"
./bin/stylua --check "$MANOR"

echo "== execute"
python3 compose.py "$MANOR" >/dev/null
./bin/luau combined.luau > parts.tsv
grep -E '^(PRINT|WARN|ERROR|BADPART)' parts.tsv || true
if grep -qE '^(ERROR|BADPART|WARN)' parts.tsv; then
	echo "!! module reported a problem while building"
	exit 1
fi

echo "== walkability"
python3 nav.py

echo "== render (tools/verify/out/)"
python3 render2.py hero detail cutaway 2>/dev/null | tail -4
