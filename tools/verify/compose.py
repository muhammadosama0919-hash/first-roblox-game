#!/usr/bin/env python3
"""
Build one Luau chunk that runs a real house module against the shim, and run it.

    compose.py Manor          -> work/Manor.tsv

Luau's CLI sandboxes each required module's globals, so `game`/`Vector3` set in
one chunk are invisible in another. Wrapping every source in a function inside
a single chunk makes the shimmed API resolve as upvalues instead, which needs
no edit to the modules under test: their source text goes in byte for byte.

The house modules require the shared kit the way they do in Roblox,
`require(script.Parent.HouseKit)`. Here `script` is a table whose Parent maps
each module name to itself and `require` looks the name up, so the same line
works in both places.

The chunk prints one line per instance the build created. Parts carry their
full geometry; folders, models and lights carry enough to rebuild the tree,
with their tags and attributes, because doors and hiding places are found by
those rather than by name.
"""

import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
HOUSES = (HERE / "../../src/server/Houses").resolve()
WORK = HERE / "work"

# Shared modules, in dependency order. Each house is spliced after them.
SHARED = ["HouseKit", "Furnish", "Decor"]

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

-- `script.Parent.X` is the name X; `require` turns the name into the module.
local MODULES = {}
local script = { Parent = setmetatable({}, {
\t__index = function(_, name)
\t\treturn name
\tend,
}) }
local function require(ref)
\tlocal m = MODULES[ref]
\tif m == nil then
\t\terror("shim require: no module " .. tostring(ref), 2)
\tend
\treturn m
end
"""

MODULE = """
MODULES[@NAME@] = (function()
@SOURCE@
end)()
"""

EPILOGUE = """
local House = MODULES[@HOUSE@]
local workspace = Instance.new("Folder")
workspace.Name = "Workspace"

local ok, result = pcall(function()
\treturn House.build(CFrame.Angles(0, math.pi, 0), workspace)
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
local e = result.entrance
realPrint(string.format("ENTRANCE\\t%.4f,%.4f,%.4f\\t%.5f,%.5f,%.5f", e.p.X, e.p.Y, e.p.Z, -e.b.X, -e.b.Y, -e.b.Z))

local function json(value)
\tlocal t = type(value)
\tif t == "number" then
\t\treturn string.format("%.6g", value)
\telseif t == "boolean" then
\t\treturn tostring(value)
\telseif t == "string" then
\t\treturn '"' .. value:gsub('[%c"\\\\]', function(c)
\t\t\treturn string.format("\\\\u%04x", string.byte(c))
\t\tend) .. '"'
\tend
\terror("json: cannot encode " .. t)
end

local function attrs(inst)
\tlocal a = rawget(inst, "_attrs")
\tlocal keys = {}
\tfor k in a do
\t\ttable.insert(keys, k)
\tend
\ttable.sort(keys)
\tlocal bits = {}
\tfor _, k in keys do
\t\ttable.insert(bits, json(k) .. ":" .. json(a[k]))
\tend
\treturn "{" .. table.concat(bits, ",") .. "}"
end

local function tags(inst)
\treturn table.concat(rawget(inst, "_tags"), ",")
end

-- Every instance gets an id (its index in the capture) so the tree can be
-- rebuilt afterwards.
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

-- Only what is actually in the house: a part created and never parented
-- (or parented to something that never reached the model) is not built.
local function inHouse(inst)
\tlocal node = inst
\twhile node do
\t\tif node == result.model then
\t\t\treturn true
\t\tend
\t\tnode = node.Parent
\tend
\treturn false
end

for i, inst in shim.captured do
\tif not inHouse(inst) then
\t\tcontinue
\tend
\tlocal class = inst.ClassName
\tif class == "Folder" or class == "Model" then
\t\tlocal pivot = ""
\t\tlocal wp = if class == "Model" then inst.WorldPivot else nil
\t\tif wp then
\t\t\tpivot = string.format(
\t\t\t\t"%.5f,%.5f,%.5f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
\t\t\t\twp.p.X, wp.p.Y, wp.p.Z, wp.r.X, wp.r.Y, wp.r.Z, wp.u.X, wp.u.Y, wp.u.Z, wp.b.X, wp.b.Y, wp.b.Z
\t\t\t)
\t\tend
\t\trealPrint(table.concat({ "NODE", tostring(i), class, inst.Name, parentId(inst), tags(inst), attrs(inst), pivot }, "\\t"))
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
local orphans = 0
for i, inst in shim.captured do
\tlocal class = inst.ClassName
\tif class ~= "Part" and class ~= "WedgePart" and class ~= "CornerWedgePart" then
\t\tcontinue
\tend
\tif not inHouse(inst) then
\t\torphans += 1
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
\tlocal function flag(name)
\t\tlocal v = inst[name]
\t\tif v == nil then
\t\t\treturn "true"
\t\tend
\t\treturn tostring(v)
\tend
\tlocal shape = inst.Shape
\tlocal shapeName = if shape then shape.Name else "Block"
\tif class ~= "Part" then
\t\tshapeName = "Block"
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
\t\tflag("CanCollide"),
\t\ttags(inst),
\t\ttostring(i),
\t\tparentId(inst),
\t\tflag("CanQuery"),
\t\tflag("CastShadow"),
\t\tshapeName,
\t\tflag("CanTouch"),
\t\tattrs(inst),
\t\tstring.format("%.3f", inst.Reflectance or 0),
\t}, "\\t"))
\temitted += 1
end

realPrint("EMITTED\\t" .. tostring(emitted))
if orphans > 0 then
\trealPrint("WARN\\t" .. tostring(orphans) .. " parts were created but never reached the model")
end
realPrint("OK")
"""


def compose(house: str) -> pathlib.Path:
    shim = (HERE / "roblox_shim.luau").read_text()
    out = PROLOGUE + shim + MIDDLE
    for name in SHARED:
        path = HOUSES / f"{name}.luau"
        if path.exists():
            out += MODULE.replace("@NAME@", repr(name)).replace("@SOURCE@", path.read_text())
    source = (HOUSES / f"{house}.luau").read_text()
    out += MODULE.replace("@NAME@", repr(house)).replace("@SOURCE@", source)
    out += EPILOGUE.replace("@HOUSE@", repr(house))
    WORK.mkdir(exist_ok=True)
    combined = WORK / f"{house}.combined.luau"
    combined.write_text(out)
    return combined


def run(house: str) -> pathlib.Path:
    combined = compose(house)
    tsv = WORK / f"{house}.tsv"
    luau = HERE / "bin" / "luau"
    res = subprocess.run([str(luau), str(combined)], capture_output=True, text=True)
    tsv.write_text(res.stdout)
    if res.returncode != 0 or res.stderr.strip():
        # A syntax or runtime error outside the pcall: say where, in module terms.
        print(res.stderr.strip())
        print(locate(combined, res.stderr))
        sys.exit(1)
    return tsv


def locate(combined: pathlib.Path, stderr: str) -> str:
    """Map a line number in the combined chunk back to a module and line."""
    import re
    m = re.search(r":(\d+):", stderr)
    if not m:
        return ""
    target = int(m.group(1))
    lines = combined.read_text().split("\n")
    current, start = "shim/prologue", 1
    for i, line in enumerate(lines, 1):
        if i > target:
            break
        mm = re.match(r"MODULES\['(\w+)'\] = \(function\(\)", line)
        if mm:
            current, start = mm.group(1), i + 1
    return f"-> {current}.luau line {target - start + 1}"


if __name__ == "__main__":
    house = sys.argv[1] if len(sys.argv) > 1 else "Manor"
    tsv = run(house)
    print(f"{tsv.relative_to(HERE)} written")
