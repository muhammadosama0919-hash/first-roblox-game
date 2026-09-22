#!/usr/bin/env python3
"""
Build one Luau chunk that runs the real Manor.luau against the shim.

Luau's CLI sandboxes each required module's globals, so `game`/`Vector3` set in
one chunk are invisible in another. Wrapping both sources in functions inside a
single chunk makes the shimmed API resolve as upvalues instead, which needs no
edit to the module under test: its source text goes in byte for byte.

The chunk prints one line per instance the module created. Parts carry their
full geometry; folders, models and lights carry enough to rebuild the tree.
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

-- Every instance gets an id (its index in the capture) so the tree can be
-- rebuilt afterwards: folders, models and lights are emitted by id and parent
-- id, and each part line ends with its own id and parent id.
local ids = {}
for i, inst in shim.captured do
\tids[inst] = i
end

local function parentId(inst)
\tlocal parent = inst.Parent
\treturn if parent and ids[parent] then tostring(ids[parent]) else "0"
end

local function pathOf(inst)
\tlocal names = {}
\tlocal node = inst.Parent
\twhile node do
\t\ttable.insert(names, 1, node.Name)
\t\tnode = node.Parent
\tend
\treturn table.concat(names, "/")
end

for i, inst in shim.captured do
\tlocal class = inst.ClassName
\tif class == "Folder" or class == "Model" then
\t\trealPrint(table.concat({ "NODE", tostring(i), class, inst.Name, parentId(inst) }, "\\t"))
\telseif class == "PointLight" or class == "SpotLight" or class == "SurfaceLight" then
\t\tlocal c = inst.Color
\t\tlocal shadows = inst.Shadows
\t\tif shadows == nil then
\t\t\tshadows = false
\t\tend
\t\trealPrint(table.concat({
\t\t\t"LIGHT",
\t\t\ttostring(i),
\t\t\tclass,
\t\t\tinst.Name,
\t\t\tparentId(inst),
\t\t\tif c then string.format("%.4f,%.4f,%.4f", c.R, c.G, c.B) else "1,1,1",
\t\t\tstring.format("%.3f", inst.Brightness or 1),
\t\t\tstring.format("%.3f", inst.Range or 8),
\t\t\ttostring(shadows),
\t\t}, "\\t"))
\tend
end

local emitted = 0
for i, inst in shim.captured do
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
\tlocal query = inst.CanQuery
\tif query == nil then
\t\tquery = true
\tend
\tlocal castShadow = inst.CastShadow
\tif castShadow == nil then
\t\tcastShadow = true
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
\t\ttostring(i),
\t\tparentId(inst),
\t\ttostring(query),
\t\ttostring(castShadow),
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
