--!strict
--[[
	Builds the world at server start: terrain, trees and a cabin.

	All of it is generated in code rather than placed by hand in Studio. That
	is a deliberate trade — a hand-built world looks better, but this one costs
	nothing to regenerate, resize or reshape, and every tree is a few numbers
	rather than an hour of clicking.

	Height comes from math.noise, which is deterministic: the same coordinates
	always give the same height, so the terrain is identical on every server
	without storing anything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local World = {}

local terrain = Workspace.Terrain

-- Colours picked to sit together rather than to be individually pretty.
local BARK = Color3.fromRGB(88, 66, 48)
local LEAF_LIGHT = Color3.fromRGB(104, 150, 68)
local LEAF_DARK = Color3.fromRGB(72, 112, 54)
local WALL = Color3.fromRGB(196, 180, 154)
local BEAM = Color3.fromRGB(96, 72, 52)
local ROOF = Color3.fromRGB(122, 66, 58)
local FLOOR = Color3.fromRGB(142, 108, 74)

--[[
	Ground height at a point, before anything is built.

	Two octaves of noise: a broad one for hills, a finer one for lumpiness. The
	result is flattened to zero inside the clearing so the spawn and the cabin
	sit on level ground, then eased back in over `clearingFalloff` studs so the
	join is not a cliff.
]]
function World.heightAt(x: number, z: number): number
	local broad = math.noise(x / 190, z / 190, 7.3)
	local detail = math.noise(x / 55, z / 55, 19.1) * 0.3

	local raw = (broad + detail) * Config.hillHeight

	local distance = math.sqrt(x * x + z * z)
	if distance <= Config.clearingRadius then
		return 0
	end

	-- smoothstep, so the terrain leaves the clearing gently instead of kinking.
	local t = math.clamp((distance - Config.clearingRadius) / Config.clearingFalloff, 0, 1)
	local eased = t * t * (3 - 2 * t)

	return raw * eased
end

local function generateTerrain()
	local half = Config.worldSize / 2
	local cell = Config.terrainCell
	local floor = -Config.terrainDepth

	for x = -half, half - cell, cell do
		for z = -half, half - cell, cell do
			-- Sample the centre of the cell rather than a corner, so columns
			-- sit symmetrically on the underlying noise.
			local height = World.heightAt(x + cell / 2, z + cell / 2)
			local columnHeight = height - floor

			if columnHeight > 0 then
				terrain:FillBlock(
					CFrame.new(x + cell / 2, floor + columnHeight / 2, z + cell / 2),
					Vector3.new(cell, columnHeight, cell),
					Enum.Material.Grass
				)
			end
		end
	end
end

local function newPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
end

--[[
	One tree: a tapering trunk and three overlapping leaf clusters.

	The clusters are deliberately not concentric — offsetting and scaling them
	differently is what stops a tree reading as "a ball on a stick".
]]
local function plantTree(position: Vector3, rng: Random, parent: Instance)
	local tree = Instance.new("Model")
	tree.Name = "Tree"

	local height = rng:NextNumber(16, 26)
	local thickness = rng:NextNumber(2.2, 3.4)
	local lean = rng:NextNumber(-0.06, 0.06)

	local trunk = newPart(
		"Trunk",
		Vector3.new(height, thickness, thickness),
		CFrame.new(position + Vector3.new(0, height / 2 - 1, 0))
			* CFrame.Angles(lean, 0, math.rad(90) + lean),
		BARK,
		Enum.Material.Wood
	)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Parent = tree

	local crown = position + Vector3.new(0, height - 2, 0)
	for cluster = 1, 3 do
		local radius = rng:NextNumber(7, 11) * (1 - (cluster - 1) * 0.18)
		local offset = Vector3.new(
			rng:NextNumber(-3.5, 3.5),
			(cluster - 1) * rng:NextNumber(2.5, 4),
			rng:NextNumber(-3.5, 3.5)
		)

		local leaves = newPart(
			"Leaves",
			Vector3.new(radius, radius * 0.85, radius),
			CFrame.new(crown + offset),
			if cluster % 2 == 0 then LEAF_DARK else LEAF_LIGHT,
			Enum.Material.LeafyGrass
		)
		leaves.Shape = Enum.PartType.Ball
		leaves.CanCollide = false
		leaves.Parent = tree
	end

	tree.Parent = parent
end

--[[
	A cabin, built from plain Parts.

	Walls with openings are made from several pieces rather than one part, since
	Roblox has no way to cut a hole in a Part. A doorway is the two pieces beside
	it plus the header above it.
]]
local function buildHouse(origin: Vector3, parent: Instance)
	local house = Instance.new("Model")
	house.Name = "Cabin"

	local W, D, H = 28, 24, 14 -- width (X), depth (Z), wall height
	local halfW, halfD = W / 2, D / 2
	local t = 1 -- wall thickness
	local ox, oz = origin.X, origin.Z

	local function place(
		name: string,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		material: Enum.Material
	)
		newPart(name, size, CFrame.new(origin + offset), color, material).Parent = house
	end

	-- Floor and a foundation lip so the cabin does not look like it is floating.
	place("Floor", Vector3.new(W, 1, D), Vector3.new(0, -0.5, 0), FLOOR, Enum.Material.WoodPlanks)
	place(
		"Foundation",
		Vector3.new(W + 2, 2, D + 2),
		Vector3.new(0, -2, 0),
		Color3.fromRGB(120, 118, 112),
		Enum.Material.Slate
	)

	-- Back wall: solid.
	place(
		"WallBack",
		Vector3.new(W, H, t),
		Vector3.new(0, H / 2, -halfD),
		WALL,
		Enum.Material.Sandstone
	)

	-- Front wall: a 7-wide, 10-tall doorway in the middle.
	local doorHalf = 3.5
	local doorTop = 10
	local sidePiece = (W / 2) - doorHalf
	place(
		"WallFrontLeft",
		Vector3.new(sidePiece, H, t),
		Vector3.new(-(doorHalf + sidePiece / 2), H / 2, halfD),
		WALL,
		Enum.Material.Sandstone
	)
	place(
		"WallFrontRight",
		Vector3.new(sidePiece, H, t),
		Vector3.new(doorHalf + sidePiece / 2, H / 2, halfD),
		WALL,
		Enum.Material.Sandstone
	)
	place(
		"DoorHeader",
		Vector3.new(doorHalf * 2, H - doorTop, t),
		Vector3.new(0, doorTop + (H - doorTop) / 2, halfD),
		BEAM,
		Enum.Material.Wood
	)

	-- Side walls: a band below the window, a band above it, and a post at each
	-- end to frame the opening.
	local sillY, headY = 5, 10
	local winHalf = 5
	local post = halfD - winHalf

	for _, side in { -1, 1 } do
		local x = side * halfW
		local label = if side < 0 then "Left" else "Right"

		place(
			"Wall" .. label .. "Lower",
			Vector3.new(t, sillY, D),
			Vector3.new(x, sillY / 2, 0),
			WALL,
			Enum.Material.Sandstone
		)
		place(
			"Wall" .. label .. "Upper",
			Vector3.new(t, H - headY, D),
			Vector3.new(x, headY + (H - headY) / 2, 0),
			WALL,
			Enum.Material.Sandstone
		)
		place(
			"Wall" .. label .. "PostA",
			Vector3.new(t, headY - sillY, post),
			Vector3.new(x, (sillY + headY) / 2, halfD - post / 2),
			WALL,
			Enum.Material.Sandstone
		)
		place(
			"Wall" .. label .. "PostB",
			Vector3.new(t, headY - sillY, post),
			Vector3.new(x, (sillY + headY) / 2, -(halfD - post / 2)),
			WALL,
			Enum.Material.Sandstone
		)

		local glass = newPart(
			"Window" .. label,
			Vector3.new(0.3, headY - sillY, winHalf * 2),
			CFrame.new(origin + Vector3.new(x, (sillY + headY) / 2, 0)),
			Color3.fromRGB(180, 214, 226),
			Enum.Material.Glass
		)
		glass.Transparency = 0.55
		glass.CanCollide = false
		glass.Parent = house
	end

	-- Gabled roof: two slabs leaning against each other.
	local rise = 8
	local run = halfW + 1.5 -- a little overhang past the walls
	local slope = math.atan2(rise, run)
	local slabLength = math.sqrt(run * run + rise * rise)

	for _, side in { -1, 1 } do
		local label = if side < 0 then "Left" else "Right"
		local slab = newPart(
			"Roof" .. label,
			Vector3.new(slabLength, 0.8, D + 4),
			CFrame.new(origin + Vector3.new(-side * run / 2, H + rise / 2, 0))
				* CFrame.Angles(0, 0, side * slope),
			ROOF,
			Enum.Material.Slate
		)
		slab.Parent = house
	end

	-- Triangular fill at each gable end, so the roof is not open to the sky.
	-- A WedgePart's vertical face is its +Z side and it slopes away toward -Z,
	-- so rotating 90 degrees about Y points that face at the ridge.
	for _, zEnd in { halfD, -halfD } do
		for _, side in { -1, 1 } do
			local wedge = Instance.new("WedgePart")
			wedge.Name = "Gable"
			wedge.Size = Vector3.new(t, rise, halfW)
			wedge.CFrame = CFrame.new(origin + Vector3.new(side * halfW / 2, H + rise / 2, zEnd))
				* CFrame.Angles(0, math.rad(-side * 90), 0)
			wedge.Color = WALL
			wedge.Material = Enum.Material.Sandstone
			wedge.Anchored = true
			wedge.Parent = house
		end
	end

	house.Parent = parent
end

--[[
	Scatter trees over the map, skipping the clearing and the cabin.

	Candidates are rejected rather than nudged: nudging a rejected point tends
	to pile trees up against whatever pushed them away.
]]
local function plantForest(parent: Instance, housePosition: Vector3)
	local rng = Random.new(Config.worldSeed)
	local half = Config.worldSize / 2 - 20
	local planted = 0
	local attempts = 0

	while planted < Config.treeCount and attempts < Config.treeCount * 20 do
		attempts += 1

		local x = rng:NextNumber(-half, half)
		local z = rng:NextNumber(-half, half)
		local distance = math.sqrt(x * x + z * z)

		-- Keep the middle clear to play in, and do not grow a tree through the
		-- cabin roof.
		if distance < Config.treeClearRadius then
			continue
		end
		if
			(Vector3.new(x, 0, z) - Vector3.new(housePosition.X, 0, housePosition.Z)).Magnitude < 30
		then
			continue
		end

		local y = World.heightAt(x, z)
		plantTree(Vector3.new(x, y, z), rng, parent)
		planted += 1
	end

	return planted
end

--[[
	Build everything. Returns where the cabin was put, so callers can avoid it.
]]
function World.build(): Vector3
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = Workspace

	generateTerrain()

	local housePosition = Vector3.new(0, 0, -Config.clearingRadius * 0.55)
	buildHouse(housePosition, scenery)

	local trees = plantForest(scenery, housePosition)
	print(string.format("[World] terrain built, %d trees planted", trees))

	return housePosition
end

return World
