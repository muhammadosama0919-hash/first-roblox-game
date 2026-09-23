--!strict
--[[
	Stands the house this script is in on the world's ground, and keeps the
	world's scenery out of it.

	This project's world is generated when the server starts (World.luau):
	the hills, the pond, and some ninety trees with rocks and bushes scattered
	over the whole map. None of it exists in Studio's editor, so a house
	inserted there cannot be put on ground that is not there yet, and the
	generator knows nothing about the house. Left alone, a house floats over a
	dip or sinks into a hill, and trees come up through its rooms.

	So once the world is built:

	  1. The ground under the house is levelled into a pad at the middle
	     height of the ground it covers: dug out above that, filled in below,
	     across the footprint and a margin round it.
	  2. The house is raised or lowered onto the pad. Only its height
	     changes; where it stands and which way it faces stay as placed. This
	     relies on the house's pivot being at the foot of its foundations,
	     which is where the exporter puts it.
	  3. Every GroundCut in the house is dug out of the pad: an unseen part
	     marking a hole the house needs in the ground, like an open grave.
	     A model can hold a hole's sides but cannot make the hole, and the
	     pad would fill it straight back in.
	  4. Trees, bushes, rocks and reeds inside the footprint are removed,
	     including any planted after this ran.

	Embedded in every exported house model, next to DoorController, so a
	house looks after itself with no other code in the place. Anywhere but
	directly inside a Model it does nothing. In a place without the generator
	(no Workspace.Scenery ever appears) nothing is touched at all: the house
	stays exactly where it was put.

	ManorSpawn also clears scenery from under every house it finds when the
	project's own server code is running. Both only remove things, so running
	both is harmless.
]]

local Workspace = game:GetService("Workspace")

-- The names the world generator gives its scenery. Anything else, in the
-- Scenery folder or out of it, is left alone.
local CLEARABLE = { Tree = true, Bush = true, Rock = true, Reed = true }

-- How far past the house's own edge the pad and the clearing reach. A tree
-- whose trunk just misses the wall still puts its crown through the bedroom,
-- and a pad cut flush to the walls leaves the hillside against them.
local MARGIN = 4

-- How long to wait for the generator to start, and then to finish. It shapes
-- the terrain before anything else, which takes a while on a slow server.
local WORLD_TIMEOUT = 60

-- The ground is sampled on a grid of this many points a side across the pad.
local SAMPLES = 7

-- Extra depth dug above the highest ground and filled below the lowest, so
-- no sliver of the old slope survives at the edges of the pad.
local SLACK = 8

-- Removals come in a burst as the generator plants. One line in the Output
-- window once a burst is over, rather than a line per tree.
local REPORT_AFTER = 2

local parent = script.Parent
if not parent or not parent:IsA("Model") then
	return
end
local house = parent :: Model

local found = Workspace:WaitForChild("Scenery", WORLD_TIMEOUT)
if not found then
	return
end
local scenery = found :: Instance

--[[
	Wait for the generator to finish. It builds the whole world in one go, but
	this thread can be woken the moment the Scenery folder appears, before any
	of it exists; the folder's contents holding still for a second means it
	is done.
]]
local function worldBuilt()
	local deadline = os.clock() + WORLD_TIMEOUT
	local count, since = -1, os.clock()
	while os.clock() < deadline do
		local now = #scenery:GetChildren()
		if now ~= count then
			count, since = now, os.clock()
		elseif os.clock() - since >= 1 then
			return
		end
		task.wait(0.25)
	end
end

--[[
	Level the ground under the house and stand it there. Returns nothing if
	there is no terrain under it to stand on, in which case nothing is moved.
]]
local function standOnGround(): (number?, number?, number?)
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return nil
	end

	local box, size = house:GetBoundingBox()
	local halfX, halfZ = size.X / 2 + MARGIN, size.Z / 2 + MARGIN

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	params.IgnoreWater = true

	local heights: { number } = {}
	for i = 0, SAMPLES - 1 do
		for j = 0, SAMPLES - 1 do
			local point = box:PointToWorldSpace(
				Vector3.new(
					-halfX + 2 * halfX * i / (SAMPLES - 1),
					0,
					-halfZ + 2 * halfZ * j / (SAMPLES - 1)
				)
			)
			local hit =
				Workspace:Raycast(point + Vector3.new(0, 1000, 0), Vector3.new(0, -2000, 0), params)
			if hit then
				table.insert(heights, hit.Position.Y)
			end
		end
	end
	-- Mostly off the edge of the world: better where it was put than on a
	-- pad cut from the few samples that did find ground.
	if #heights < SAMPLES * SAMPLES / 2 then
		return nil
	end

	table.sort(heights)
	local pad = heights[(#heights + 1) // 2]
	local low, high = heights[1], heights[#heights]

	-- The pad turns with the house, so it fits the footprint on any heading.
	local centre = box.Position
	local flat = CFrame.new(centre.X, pad, centre.Z) * box.Rotation
	local area = Vector3.new(2 * halfX, 0, 2 * halfZ)
	local dig = high - pad + SLACK
	local fill = pad - low + SLACK
	-- Dug first, filled second: the voxels the pad's surface passes through
	-- are shared by both, and the fill's share of them is what should stay.
	terrain:FillBlock(
		flat * CFrame.new(0, dig / 2, 0),
		area + Vector3.new(0, dig, 0),
		Enum.Material.Air
	)
	terrain:FillBlock(
		flat * CFrame.new(0, -fill / 2, 0),
		area + Vector3.new(0, fill, 0),
		Enum.Material.Ground
	)

	local pivot = house:GetPivot()
	house:PivotTo(CFrame.new(pivot.X, pad, pivot.Z) * pivot.Rotation)
	return pad, low, high
end

-- Dig out every GroundCut, where the house stands now. Returns how many.
local function digCuts(): number
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return 0
	end
	local count = 0
	for _, d in house:GetDescendants() do
		if d.Name == "GroundCut" and d:IsA("BasePart") then
			terrain:FillBlock(d.CFrame, d.Size, Enum.Material.Air)
			count += 1
		end
	end
	return count
end

worldBuilt()

local ok, pad, low, high = pcall(standOnGround)
if not ok then
	warn(`[{house.Name}] could not be stood on the ground: {pad}`)
elseif pad and low and high then
	print(
		string.format(
			"[%s] stood on the ground at Y = %.1f; the ground under it ran from %.1f to %.1f",
			house.Name,
			pad,
			low,
			high
		)
	)
	local dug, cuts = pcall(digCuts)
	if not dug then
		warn(`[{house.Name}] could not dig its holes in the ground: {cuts}`)
	elseif type(cuts) == "number" and cuts > 0 then
		print(
			string.format(
				"[%s] dug %d hole%s in the ground",
				house.Name,
				cuts,
				if cuts == 1 then "" else "s"
			)
		)
	end
end

----------------------------------------------------------------------------
-- Scenery
----------------------------------------------------------------------------

-- Read after the house has moved. Only its height changed, but reading it
-- here means the order of the two jobs never matters.
local box, size = house:GetBoundingBox()

local function under(position: Vector3): boolean
	local rel = box:PointToObjectSpace(position)
	return math.abs(rel.X) < size.X / 2 + MARGIN and math.abs(rel.Z) < size.Z / 2 + MARGIN
end

local cleared = 0
local reported = 0
local reportPending = false

local function report()
	reportPending = false
	if cleared > reported then
		print(
			string.format(
				"[%s] %d pieces of scenery cleared from under the house",
				house.Name,
				cleared
			)
		)
		reported = cleared
	end
end

local function clear(thing: Instance)
	if not thing.Parent then
		return
	end
	if CLEARABLE[thing.Name] and thing:IsA("PVInstance") and under(thing:GetPivot().Position) then
		thing:Destroy()
		cleared += 1
		if not reportPending then
			reportPending = true
			task.delay(REPORT_AFTER, report)
		end
	end
end

-- Deferred, because destroying a child from inside the ChildAdded that
-- announced it changes its parent while the engine is still setting it,
-- which Roblox refuses with a warning.
scenery.ChildAdded:Connect(function(thing: Instance)
	task.defer(clear, thing)
end)
for _, thing in scenery:GetChildren() do
	clear(thing)
end
