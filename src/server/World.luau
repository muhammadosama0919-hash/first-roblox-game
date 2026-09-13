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

-- Smoothstep: 0 below `from`, 1 above `to`, with eased ends rather than a kink.
local function smoothstep(value: number, from: number, to: number): number
	local t = math.clamp((value - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	How far a point is from the middle of the pond.
]]
function World.distanceToPond(x: number, z: number): number
	local dx = x - Config.pondCenterX
	local dz = z - Config.pondCenterZ
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	Ground height at a point, before anything is built.

	Three things stacked, in order:
	  1. Two octaves of noise — a broad one for hills, a finer one for lumps.
	  2. Flattening, toward zero inside the clearing and around the pond, so the
	     spawn, the cabin and the water line all sit on level ground.
	  3. The pond basin, carved downward.

	Deterministic: the same coordinates always give the same height, so every
	server builds the same world without storing anything.
]]
function World.heightAt(x: number, z: number): number
	local broad = math.noise(x / 190, z / 190, 7.3)
	local detail = math.noise(x / 55, z / 55, 19.1) * 0.3
	local height = (broad + detail) * Config.hillHeight

	-- Flatten toward the middle.
	local distance = math.sqrt(x * x + z * z)
	height *= smoothstep(
		distance,
		Config.clearingRadius,
		Config.clearingRadius + Config.clearingFalloff
	)

	-- Flatten around the pond too, so its bank is level all the way round
	-- instead of the water line cutting across a hillside.
	local pondDistance = World.distanceToPond(x, z)
	local pondEdge = Config.pondRadius + Config.pondBankWidth
	height *= smoothstep(pondDistance, Config.pondRadius, pondEdge)

	-- Carve the basin: deepest in the middle, easing up to nothing at the rim.
	if pondDistance < Config.pondRadius then
		local bowl = 1 - smoothstep(pondDistance, 0, Config.pondRadius)
		height -= Config.pondDepth * bowl
	end

	return height
end

--[[
	Which material a patch of ground should be.

	Picked from the shape of the land rather than assigned by hand: anything
	near the water line is sand, steep faces are rock, everything else is grass.
	That is what stops the world looking like one flat green sheet.
]]
local function materialAt(x: number, z: number, height: number): Enum.Material
	-- Shoreline: a band of sand either side of the water line, but only near
	-- the pond, so puddle-height ground elsewhere stays grass.
	if World.distanceToPond(x, z) < Config.pondRadius + Config.pondBankWidth * 0.25 then
		if height < Config.waterLevel + 2.5 then
			return Enum.Material.Sand
		end
	end

	-- Slope from finite differences. A tall rise over a short distance reads as
	-- a cliff face, and cliffs are not grassy.
	local step = 5
	local dx = World.heightAt(x + step, z) - World.heightAt(x - step, z)
	local dz = World.heightAt(x, z + step) - World.heightAt(x, z - step)
	local slope = math.sqrt(dx * dx + dz * dz) / (2 * step)

	if slope > 0.62 then
		return Enum.Material.Rock
	elseif slope > 0.4 then
		return Enum.Material.Ground
	end

	return Enum.Material.Grass
end

local function generateTerrain()
	local half = Config.worldSize / 2
	local cell = Config.terrainCell
	local floor = -Config.terrainDepth

	for x = -half, half - cell, cell do
		for z = -half, half - cell, cell do
			-- Sample the centre of the cell rather than a corner, so columns
			-- sit symmetrically on the underlying noise.
			local cx, cz = x + cell / 2, z + cell / 2
			local height = World.heightAt(cx, cz)
			local columnHeight = height - floor

			if columnHeight > 0 then
				terrain:FillBlock(
					CFrame.new(cx, floor + columnHeight / 2, cz),
					Vector3.new(cell, columnHeight, cell),
					materialAt(cx, cz, height)
				)
			end

			-- Then flood the basin. Water goes in as a second pass on top of
			-- the ground column, from the carved floor up to the water line.
			--
			-- Confined to the pond on purpose: the hills dip below the water
			-- line in plenty of hollows, and without this check every one of
			-- them would fill, scattering grass-bottomed puddles with no banks
			-- or reeds across the whole map.
			if height < Config.waterLevel and World.distanceToPond(cx, cz) < Config.pondRadius then
				local depth = Config.waterLevel - height
				terrain:FillBlock(
					CFrame.new(cx, height + depth / 2, cz),
					Vector3.new(cell, depth, cell),
					Enum.Material.Water
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
	Small things on the ground: boulders, bushes and pond reeds.

	None of it is interactive — it exists so the eye has something to measure
	distance against. A hillside with nothing on it reads as flat no matter how
	well it is lit.
]]
local function scatterDetail(parent: Instance, housePosition: Vector3)
	local rng = Random.new(Config.worldSeed + 991)
	local half = Config.worldSize / 2 - 15

	local function pick(): (number, number, number, number)
		local x = rng:NextNumber(-half, half)
		local z = rng:NextNumber(-half, half)
		return x, z, World.heightAt(x, z), World.distanceToPond(x, z)
	end

	-- Boulders: anywhere except underwater and the immediate spawn area.
	for _ = 1, Config.rockCount do
		for _ = 1, 12 do
			local x, z, y, pondDistance = pick()
			if y > Config.waterLevel + 1 and math.sqrt(x * x + z * z) > 22 then
				local size = rng:NextNumber(3, 9)
				local rock = newPart(
					"Rock",
					Vector3.new(
						size,
						size * rng:NextNumber(0.5, 0.9),
						size * rng:NextNumber(0.7, 1.2)
					),
					CFrame.new(x, y + size * 0.15, z)
						* CFrame.Angles(
							rng:NextNumber(-0.3, 0.3),
							rng:NextNumber(0, 6.28),
							rng:NextNumber(-0.3, 0.3)
						),
					-- Boulders near the pond match the sand, not the grass.
					if pondDistance < Config.pondRadius + 14
						then Color3.fromRGB(168, 156, 132)
						else Color3.fromRGB(126, 124, 120),
					Enum.Material.Rock
				)
				rock.Parent = parent
				break
			end
		end
	end

	-- Bushes: clusters of squashed spheres, on grass only.
	for _ = 1, Config.bushCount do
		for _ = 1, 12 do
			local x, z, y, pondDistance = pick()
			if
				y > Config.waterLevel + 3
				and pondDistance > Config.pondRadius + 4
				and math.sqrt(x * x + z * z) > 18
			then
				local size = rng:NextNumber(3.5, 7)
				local bush = newPart(
					"Bush",
					Vector3.new(size, size * 0.7, size),
					CFrame.new(x, y + size * 0.25, z),
					if rng:NextNumber() < 0.5 then LEAF_DARK else LEAF_LIGHT,
					Enum.Material.LeafyGrass
				)
				bush.Shape = Enum.PartType.Ball
				bush.CanCollide = false
				bush.Parent = parent
				break
			end
		end
	end

	-- Reeds: thin blades, only in the shallows right at the water line.
	for _ = 1, Config.reedCount do
		for _ = 1, 12 do
			local x, z, y, pondDistance = pick()
			local inShallows = pondDistance < Config.pondRadius
				and y > Config.waterLevel - 2.5
				and y < Config.waterLevel + 1.2
			if inShallows then
				local height = rng:NextNumber(3, 6.5)
				local reed = newPart(
					"Reed",
					Vector3.new(0.35, height, 0.35),
					CFrame.new(x, y + height / 2, z)
						* CFrame.Angles(
							rng:NextNumber(-0.25, 0.25),
							rng:NextNumber(0, 6.28),
							rng:NextNumber(-0.25, 0.25)
						),
					Color3.fromRGB(118, 142, 78),
					Enum.Material.Grass
				)
				reed.CanCollide = false
				reed.Parent = parent
				break
			end
		end
	end
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

	-- Animated grass blades on Grass terrain. One property, and it does more
	-- for how the ground reads than any amount of scattered geometry.
	terrain.Decoration = true
	terrain.GrassLength = 0.6

	-- Water styling. The defaults are a flat cyan; this is closer to a pond.
	terrain.WaterColor = Color3.fromRGB(38, 92, 104)
	terrain.WaterTransparency = 0.72
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.06
	terrain.WaterWaveSpeed = 8

	generateTerrain()

	local housePosition = Vector3.new(0, 0, -Config.clearingRadius * 0.55)
	buildHouse(housePosition, scenery)

	local trees = plantForest(scenery, housePosition)
	scatterDetail(scenery, housePosition)

	print(string.format("[World] terrain and pond built, %d trees planted", trees))

	return housePosition
end

return World
