#!/usr/bin/env bash
# Build the Studio-importable files in build/.
#
# These exist so the game can be installed on a machine that has Roblox Studio
# and nothing else — no Rojo, no CLI, no git. If you run Rojo locally, you do
# not need any of this; use `rojo serve` instead.
set -euo pipefail

cd "$(dirname "$0")"
ROJO="${ROJO:-rojo}"

# A complete place: baseplate, spawn, lighting and all the code.
#
# ############################ WARNING ############################
# This file REPLACES a place wholesale. Once you have done ANY work
# inside Studio — imported a mesh, built geometry, rigged something,
# placed a model — opening a newer .rbxl DESTROYS it. There is no
# merge and no warning from Studio.
#
# From that point on, take the .rbxmx models in build/ instead. They
# carry only code, and insert into a place you already have.
# #################################################################
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
