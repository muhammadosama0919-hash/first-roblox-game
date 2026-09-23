#!/usr/bin/env python3
"""
Run the real Groundwork.server.luau against a mocked world.

    groundwork.py

Groundwork is the script inside every exported house that, once the world is
generated, levels the ground under the house, stands the house on it and
clears the trees out of it. None of that can be seen until the game runs, so
this runs it: the unmodified script, under the Luau CLI, with the shim's
Vector3 and CFrame, against a sloping terrain, a house turned 30 degrees and
floating above it with a hole to dig (a GroundCut) inside it, trees in and
out of its footprint, and one planted after the script has finished. Then
it checks where the house ended up, what was dug and filled, and what was
cleared.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
SHIM = (HERE / "roblox_shim.luau").read_text()
SCRIPT = (ROOT / "src/server/Houses/Groundwork.server.luau").read_text()

HARNESS = r"""
local Vector3 = shim.Vector3
local CFrame = shim.CFrame
local Enum = shim.Enum

local now = 0
local queue = {}
local function runDue()
	local again = true
	while again do
		again = false
		table.sort(queue, function(a, b) return a.t < b.t end)
		for i, job in queue do
			if job.t <= now then
				table.remove(queue, i)
				job.fn(table.unpack(job.args))
				again = true
				break
			end
		end
	end
end
local task = {
	wait = function(s) now += (s or 0.03); runDue() end,
	delay = function(s, fn, ...) table.insert(queue, { t = now + s, fn = fn, args = { ... } }) end,
	defer = function(fn, ...) table.insert(queue, { t = now, fn = fn, args = { ... } }) end,
}
local os = { clock = function() return now end }

local out = {}
local function print(...) table.insert(out, "PRINT " .. table.concat({ ... }, " ")) end
local function warn(...) table.insert(out, "WARN " .. table.concat({ ... }, " ")) end

-- The ground: a slope, high to the east and the north.
local function ground(x, z) return 0.12 * x - 0.05 * z + 3 end

local fills = {}
local terrain = {
	FillBlock = function(_, cf, size, material)
		table.insert(fills, { cf = cf, size = size, material = material.EnumType .. "." .. material.Name })
	end,
}

local scenery = { children = {}, handler = nil }
function scenery:GetChildren()
	local copy = {}
	for _, c in self.children do table.insert(copy, c) end
	return copy
end
scenery.ChildAdded = { Connect = function(_, fn) scenery.handler = fn end }

local function newThing(name, x, z)
	local t = { Name = name, Parent = scenery, at = CFrame.new(x, ground(x, z), z) }
	function t:IsA(c) return c == "PVInstance" end
	function t:GetPivot() return self.at end
	function t:Destroy()
		self.Parent = nil
		for i, c in scenery.children do
			if c == self then table.remove(scenery.children, i) break end
		end
	end
	return t
end
local function plant(name, x, z)
	local t = newThing(name, x, z)
	table.insert(scenery.children, t)
	if scenery.handler then scenery.handler(t) end
	return t
end

-- The house: turned 30 degrees, pivot floating well above the slope. Its box
-- is centred 15 up from the pivot, 80 wide and 90 deep, turned with it.
local pivot = CFrame.new(100, 40, -50) * CFrame.Angles(0, math.rad(30), 0)
local SIZE = Vector3.new(80, 30, 90)
local moves = {}
local house = { Name = "Villa" }
function house:IsA(c) return c == "Model" end
function house:GetPivot() return pivot end
function house:PivotTo(cf) pivot = cf; table.insert(moves, cf) end
function house:GetBoundingBox() return pivot * CFrame.new(0, 15, 0), SIZE end
-- Two parts inside it that move with it: an open grave's GroundCut, and a
-- part that is not one.
local CUT_AT, CUT_SIZE = CFrame.new(12, -2.5, -20), Vector3.new(5.6, 6.2, 9.6)
local function housePart(name, offset, size, class)
	return setmetatable({ Name = name, Size = size }, {
		__index = function(t, k)
			if k == "CFrame" then return pivot * offset end
			if k == "IsA" then return function(_, c) return c == class or c == "BasePart" end end
			return nil
		end,
	})
end
local descendants = {
	housePart("Wall", CFrame.new(0, 5, 0), Vector3.new(10, 10, 1), "Part"),
	housePart("GroundCut", CUT_AT, CUT_SIZE, "Part"),
}
function house:GetDescendants() return descendants end

local Workspace = {}
function Workspace:WaitForChild(name, timeout)
	assert(name == "Scenery" and timeout, "WaitForChild without a deadline")
	return scenery
end
function Workspace:FindFirstChildOfClass(c) return if c == "Terrain" then terrain else nil end
function Workspace:Raycast(origin, dir, params)
	assert(params.IgnoreWater == true, "raycast should ignore water")
	assert(dir.Y < 0, "raycast should point down")
	local y = ground(origin.X, origin.Z)
	return { Position = Vector3.new(origin.X, y, origin.Z) }
end
local game = { GetService = function(_, n) assert(n == "Workspace"); return Workspace end }
local RaycastParams = { new = function() return {} end }
local script = { Parent = house }

-- Trees, in house space (x across, z along), placed before the script runs.
local function worldAt(x, z)
	local p = pivot:PointToWorldSpace(Vector3.new(x, 0, z))
	return p.X, p.Z
end
local before = {}
for _, spec in {
	{ "Tree", 0, 0, true }, { "Tree", 35, 40, true }, { "Bush", -42, -46, true },
	{ "Tree", 50, 0, false }, { "Rock", 0, 55, false }, { "Tree", -60, 60, false },
	{ "Cabin", 0, 10, false },
} do
	local x, z = worldAt(spec[2], spec[3])
	table.insert(before, { plant(spec[1], x, z), spec[4], spec[1] .. " at " .. spec[2] .. "," .. spec[3] })
end
local startPivot = pivot

local function RUN()
__SCRIPT__
end
RUN()

-- A tree planted after the script has finished, inside, and one outside.
local lx, lz = worldAt(-10, 20)
local lateIn = plant("Tree", lx, lz)
local ox, oz = worldAt(0, -70)
local lateOut = plant("Tree", ox, oz)
task.wait(5)

-- What should have happened.
local fails = 0
local function check(ok, what)
	realPrint((if ok then "  ok    " else "  FAIL  ") .. what)
	if not ok then fails += 1 end
end

-- The expected pad: the median of the 7x7 grid the script samples.
local hs = {}
local box = startPivot * CFrame.new(0, 15, 0)
local hx, hz = SIZE.X / 2 + 4, SIZE.Z / 2 + 4
for i = 0, 6 do
	for j = 0, 6 do
		local p = box:PointToWorldSpace(Vector3.new(-hx + 2 * hx * i / 6, 0, -hz + 2 * hz * j / 6))
		table.insert(hs, ground(p.X, p.Z))
	end
end
table.sort(hs)
local pad = hs[25]

check(#moves == 1, "the house was moved once")
local moved = moves[1]
check(math.abs(moved.Y - pad) < 1e-6, string.format("stood at the median ground height %.3f (got %.3f)", pad, moved.Y))
check(math.abs(moved.X - startPivot.X) < 1e-6 and math.abs(moved.Z - startPivot.Z) < 1e-6, "X and Z kept")
local r0, r1 = startPivot.LookVector, moved.LookVector
check((r0 - r1).Magnitude < 1e-9, "heading kept")

check(#fills == 3, "three terrain fills: the pad's dig and fill, then the hole")
if #fills >= 2 then
	local dig, fill = fills[1], fills[2]
	check(dig.material:find("Air") ~= nil and fill.material:find("Ground") ~= nil, "dug with Air, then filled with Ground")
	-- dig spans pad .. high+8, fill spans low-8 .. pad, both across the footprint plus margin
	local digBottom = dig.cf.Y - dig.size.Y / 2
	local fillTop = fill.cf.Y + fill.size.Y / 2
	check(math.abs(digBottom - pad) < 1e-6 and math.abs(fillTop - pad) < 1e-6, "dig starts and fill ends at the pad")
	check(math.abs(dig.cf.Y + dig.size.Y / 2 - (hs[#hs] + 8)) < 1e-6, "dig reaches 8 above the highest ground")
	check(math.abs(fill.cf.Y - fill.size.Y / 2 - (hs[1] - 8)) < 1e-6, "fill reaches 8 below the lowest ground")
	check(math.abs(dig.size.X - (SIZE.X + 8)) < 1e-6 and math.abs(dig.size.Z - (SIZE.Z + 8)) < 1e-6, "pad covers the footprint and a 4-stud margin")
	check((dig.cf.LookVector - startPivot.LookVector).Magnitude < 1e-9, "pad turned with the house")
	local c = startPivot * CFrame.new(0, 15, 0)
	check(math.abs(dig.cf.X - c.X) < 1e-6 and math.abs(dig.cf.Z - c.Z) < 1e-6, "pad centred on the house")
end
if #fills == 3 then
	local hole = fills[3]
	local want = moved * CUT_AT
	check(hole.material:find("Air") ~= nil, "the GroundCut dug with Air, after the pad")
	check((hole.cf.Position - want.Position).Magnitude < 1e-6, "dug where the house stands now, not where it was")
	check((hole.cf.LookVector - want.LookVector).Magnitude < 1e-9, "the hole turned with the house")
	check((hole.size - CUT_SIZE).Magnitude < 1e-9, "the hole the GroundCut's size")
end

for _, b in before do
	local gone = b[1].Parent == nil
	check(gone == b[2], (if b[2] then "cleared: " else "kept:    ") .. b[3])
end
check(lateIn.Parent == nil, "a tree planted afterwards inside was cleared")
check(lateOut.Parent ~= nil, "a tree planted afterwards outside was kept")

for _, line in out do realPrint("  " .. line) end
realPrint(if fails == 0 then "GROUNDWORK OK" else fails .. " FAILURES")
"""

chunk = (
    "--!nocheck\nlocal shim = (function()\n" + SHIM + "\nend)()\nlocal realPrint = print\n"
    + HARNESS.replace("__SCRIPT__", SCRIPT)
)
(HERE / "work").mkdir(exist_ok=True)
path = HERE / "work" / "groundwork.luau"
path.write_text(chunk)
res = subprocess.run([str(HERE / "bin" / "luau"), str(path)], capture_output=True, text=True)
print(res.stdout.rstrip())
if res.stderr.strip():
    print(res.stderr.strip())
sys.exit(0 if res.returncode == 0 and res.stdout.rstrip().endswith("GROUNDWORK OK") else 1)
