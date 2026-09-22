#!/usr/bin/env python3
"""
Build one Luau chunk that runs the real Manor.luau against the shim.

Luau's CLI sandboxes each required module's globals, so `game`/`Vector3` set in
one chunk are invisible in another. Wrapping both sources in functions inside a
single chunk makes the shimmed API resolve as upvalues instead, which needs no
edit to the module under test: its source text goes in byte for byte.
"""

import pathlib
import sys

HERE = pathlib.Path(__file__).parent
MANOR = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "../../src/server/Manor.luau"

shim = (HERE / "roblox_shim.luau").read_text()
manor = MANOR.read_text()

PROLOGUE = """--!nocheck
local shim = (function()
"""

MIDDLE = """
end)()

local Vector3 = shim.Vector3
local CFrame = shim.CFrame
local Color3 = shim.Color3
local Enum = shim.Enum
local Instance = shim.Instance
local Random = shim.Random
local game = shim.game

local realPrint = print

local warnings = {}
local function warn(...)
\tlocal bits = {}
\tfor i = 1, select("#", ...) do
\t\ttable.insert(bits, tostring((select(i, ...))))
\tend
\ttable.insert(warnings, table.concat(bits, " "))
end

local prints = {}
local function print(...)
\tlocal bits = {}
\tfor i = 1, select("#", ...) do
\t\ttable.insert(bits, tostring((select(i, ...))))
\tend
\ttable.insert(prints, table.concat(bits, " "))
end

local Manor = (function()
"""

EPILOGUE = """
end)()

local workspace = Instance.new("Folder")
workspace.Name = "Workspace"

local ok, result = pcall(function()
\treturn Manor.build(CFrame.new(), workspace)
end)

for _, w in warnings do
\trealPrint("WARN\\t" .. w)
end
for _, p in prints do
\trealPrint("PRINT\\t" .. p)
end

if not ok then
\trealPrint("ERROR\\t" .. tostring(result))
\treturn
end

realPrint("HIDING\\t" .. tostring(#result.hidingSpots))
realPrint("REPORTED\\t" .. tostring(result.partCount))

local function pathOf(inst)
\tlocal names = {}
\tlocal node = inst.Parent
\twhile node do
\t\ttable.insert(names, 1, node.Name)
\t\tnode = node.Parent
\tend
\treturn table.concat(names, "/")
end

local emitted = 0
for _, inst in shim.captured do
\tlocal class = inst.ClassName
\tif class ~= "Part" and class ~= "WedgePart" then
\t\tcontinue
\tend

\tlocal size = inst.Size
\tlocal frame = inst.CFrame

\tif size == nil or frame == nil then
\t\trealPrint("BADPART\\t" .. tostring(inst.Name))
\t\tcontinue
\tend

\tlocal colour = inst.Color
\tlocal transparency = inst.Transparency or 0
\tlocal collide = inst.CanCollide
\tif collide == nil then
\t\tcollide = true
\tend

\trealPrint(table.concat({
\t\t"PART",
\t\tclass,
\t\tinst.Name,
\t\tpathOf(inst),
\t\tstring.format("%.5f,%.5f,%.5f", size.X, size.Y, size.Z),
\t\tstring.format("%.5f,%.5f,%.5f", frame.p.X, frame.p.Y, frame.p.Z),
\t\tstring.format("%.6f,%.6f,%.6f", frame.r.X, frame.r.Y, frame.r.Z),
\t\tstring.format("%.6f,%.6f,%.6f", frame.u.X, frame.u.Y, frame.u.Z),
\t\tstring.format("%.6f,%.6f,%.6f", frame.b.X, frame.b.Y, frame.b.Z),
\t\tstring.format("%.4f,%.4f,%.4f", colour.R, colour.G, colour.B),
\t\tinst.Material.Name,
\t\tstring.format("%.3f", transparency),
\t\ttostring(collide),
\t\ttable.concat(rawget(inst, "_tags"), ","),
\t}, "\\t"))
\temitted += 1
end

realPrint("EMITTED\\t" .. tostring(emitted))
realPrint("OK")
"""

out = PROLOGUE + shim + MIDDLE + manor + EPILOGUE
(HERE / "combined.luau").write_text(out)

manor_start = out[: out.index(manor)].count("\n") + 1
print(f"combined.luau written; Manor source begins at line {manor_start}")
