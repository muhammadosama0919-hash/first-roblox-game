#!/usr/bin/env bash
# Build the Studio-importable files in build/.
#
# These exist so the game can be installed on a machine that has Roblox Studio
# and nothing else — no Rojo, no CLI, no git. If you run Rojo locally, you do
# not need any of this; use `rojo serve` instead.
set -euo pipefail

cd "$(dirname "$0")"
ROJO="${ROJO:-rojo}"

# A complete place: baseplate, spawn, lighting and all the code. Open it
# directly in Studio. Only use this for a fresh start — it REPLACES a place,
# so it would discard any world you have built.
"$ROJO" build place.project.json -o build/first-roblox-game.rbxl

# Individual folders, for updating the code inside a place you already have.
# Each one is rooted at the folder it should become, so it inserts without a
# wrapper: right-click the service in Studio and choose "Insert from File".
#   Shared, Remotes -> ReplicatedStorage
#   Server          -> ServerScriptService
#   Client          -> StarterPlayer > StarterPlayerScripts
for model in Shared Server Client Remotes; do
	"$ROJO" build "build/models/$model.project.json" -o "build/$model.rbxmx"
done

echo "Built:"
ls -1 build/*.rbxl build/*.rbxmx
