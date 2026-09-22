#!/usr/bin/env bash
# Build each house for real (the unmodified module, run against the Roblox API
# shim), prove it, and export it as a model file. Stops at the first failure.
#
#   tools/verify/check.sh               all three houses
#   tools/verify/check.sh Villa         just one
#   RENDER=1 tools/verify/check.sh      also write preview renders to out/<House>/
#
# Needs the binaries in bin/ and api.json next to this script; README.md says
# where they come from.
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -gt 0 ]; then
	houses=("$@")
else
	houses=(Manor Villa Lodge)
fi

echo "== stylua"
./bin/stylua --check ../../src/server/Houses

# The sourcemap is how the checker resolves `require(script.Parent.HouseKit)`.
# Rojo derives it from the real project, so it cannot drift from it. Both run
# from the repo root because the sourcemap's paths are relative to it.
echo "== luau-lsp (strict types)"
mkdir -p work
(
	cd ../..
	tools/verify/bin/rojo sourcemap default.project.json -o tools/verify/work/sourcemap.json
	tools/verify/bin/luau-lsp analyze --platform=roblox \
		--definitions=tools/verify/bin/globalTypes.d.luau \
		--sourcemap=tools/verify/work/sourcemap.json \
		src/server/Houses/*.luau
)

# The script inside every house that stands it on the generated ground.
echo "== Groundwork (the real script, against a mocked world)"
python3 groundwork.py

for house in "${houses[@]}"; do
	echo
	echo "== $house: build"
	python3 compose.py "$house"

	echo "== $house: lights, pale surfaces, door swings, furniture in walls"
	python3 checks.py "$house"

	echo "== $house: walkability"
	python3 nav.py "$house"

	if [ "${RENDER:-0}" = 1 ]; then
		echo "== $house: renders (tools/verify/out/$house/)"
		python3 views.py "$house" >/dev/null
	fi

	echo "== $house: export (build/$house.rbxm, build/$house.rbxmx)"
	python3 export.py "$house"
done
