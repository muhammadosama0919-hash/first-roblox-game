--!strict
--[[
	The farm, generated entirely in code: a great barn with a gambrel roof, a
	stave silo and a windpump beside it, the outbuildings round a fenced
	yard, and behind it all a field of dead corn cut into a maze with a
	scarecrow in the middle.

	The barn is the farm's great room. An aisle runs its whole length
	between big doors at both ends, open to the roof, with a hay fork hung
	from the track along the ridge. Stalls down both sides under the hay
	lofts, a tack room and a feed room in the front corners, a steep stair
	to the lofts, which run down both sides and across both ends, and a hay
	door high in the front gable under its hood and hoist.

	Every door opens, the field gates and the stall gates too
	(DoorController). Nothing gives light and nothing inside is pale. Places
	to hide: the harness cupboard in the tack room, under the hay wagon,
	inside the silo, in the outhouse, the tool shed's cupboard.

	Built from HouseKit, Furnish, Decor and Yard. Local space runs +X right,
	+Y up, +Z out of the barn's front doors, with Y = 0 the barn floor; the
	ground is FOUND_H below that and the pivot sits on it, in the middle of
	the barn.
]]

local Kit = require(script.Parent.HouseKit)
local Furnish = require(script.Parent.Furnish)
local Decor = require(script.Parent.Decor)
local Yard = require(script.Parent.Yard)

local Farm = {}

type Place = Kit.Place
type HidingSpot = Kit.HidingSpot

local C = Kit.C
local M = Enum.Material
local V = Vector3.new
local EPS = Kit.EPS
local rgb = Kit.rgb
local fine = Kit.detail

----------------------------------------------------------------------------
-- Dimensions
----------------------------------------------------------------------------

local FOUND_H = 1 -- the barn floor stands this far above the ground
local L1 = 0
local GROUND = -FOUND_H

-- The barn, 36 by 60, its long axis along Z.
local BX, BZ = 18, 30 -- the outer faces of the walls
local WALL_T = 0.8
local IX, IZ = BX - WALL_T, BZ - WALL_T -- their inner faces: 17.2, 29.2
local EAVE = 14 -- the side walls' tops
local KNEE_X, KNEE_Y = 11, 24 -- where the gambrel's two pitches meet
local RIDGE = 29.5
local AISLE = 7 -- half the aisle's width, out to the lofts' edges
local POST_X = 7.4 -- the aisle posts, along the lofts' edges
local LOFT = 12 -- the lofts' floor
local GIRDER_Y = 10.7 -- the underside of the beams the lofts sit on
-- The frames across the barn, each a pair of aisle posts, the lofts' joists
-- and a collar; the stall partitions stand on the same lines.
local BENTS = { 20, 13, 6, -1, -8, -15, -22 }
local FRONT_LOFT, BACK_LOFT = 22, -22 -- the cross lofts: over each end's doors
local DOOR_W, DOOR_H = 12, 11.5 -- the big doors, both leaves
local HAY_W, HAY_SILL, HAY_HEAD = 6, 12.5, 19.5 -- the hay door, high in the front gable
local FEED_DOOR_Z = 22.6 -- the feed room's door out to the yard, in the right wall

-- Around it.
local SILO_X, SILO_Z, SILO_R, SILO_H = 28, -8, 7, 42
local PUMP_X, PUMP_Z = 46, 38
local FENCE_X, FENCE_Z0, FENCE_Z1 = 60, -38, 78
local MAZE_X0, MAZE_Z1, CELL, CELLS = -32, -42, 8, 8

----------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------

local BARN_RED = rgb(78, 34, 28) -- oxide red, a hundred summers faded and grimed
local BATTEN = rgb(62, 27, 23)
local BOARD = rgb(58, 48, 40) -- the boards' inside faces, never painted
local TIMBER = rgb(50, 40, 32) -- the frame
local TRIM = rgb(44, 36, 30)
local ROOF_IRON = rgb(70, 46, 34) -- corrugated iron, rusted through
local STONE = rgb(70, 68, 62)
local EARTH_FLOOR = rgb(50, 42, 34)
local STRAW = rgb(84, 72, 46)
local STAVE = rgb(66, 56, 46)
local DIRT = rgb(48, 38, 30)

--[[
	How much ground the farm takes, in house space: inside the fence, and the
	maze behind it.
]]
Farm.FOOTPRINT = {
	x0 = -FENCE_X - 3,
	x1 = FENCE_X + 3,
	z0 = MAZE_Z1 - CELL * CELLS - 3,
	z1 = FENCE_Z1 + 3,
}

-- Whether a world position is on the footprint of a farm built at `pivot`.
function Farm.footprintContains(pivot: CFrame, position: Vector3): boolean
	local rel = (pivot * CFrame.Angles(0, math.pi, 0)):PointToObjectSpace(position)
	local f = Farm.FOOTPRINT
	return rel.X > f.x0 and rel.X < f.x1 and rel.Z > f.z0 and rel.Z < f.z1
end

-- The underside of the barn roof at `x` across the barn: steep from the
-- eaves to the knee, shallow from the knee to the ridge.
local function roofUnder(x: number): number
	local ax = math.abs(x)
	if ax <= KNEE_X then
		return KNEE_Y + (KNEE_X - ax) * (RIDGE - KNEE_Y) / KNEE_X
	end
	return EAVE + (BX - ax) * (KNEE_Y - EAVE) / (BX - KNEE_X)
end

----------------------------------------------------------------------------
-- Orientation without conventions
----------------------------------------------------------------------------

-- A world frame at a house-space point whose X and Y axes are the given
-- house-space directions.
local function oriented(place: Place, pos: Vector3, xDir: Vector3, yDir: Vector3): CFrame
	local rot = place(Vector3.zero).Rotation
	return CFrame.fromMatrix(
		place(pos).Position,
		rot:VectorToWorldSpace(xDir.Unit),
		rot:VectorToWorldSpace(yDir.Unit)
	)
end

-- A box between two house-space points, `w` by `h` across, its height
-- along `up` (house space) as far as the direction allows: squared timber.
local function beam(
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	up: Vector3,
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance
): Part
	local d = b - a
	local along = d.Unit
	local y = up - along * up:Dot(along)
	if y.Magnitude < EPS then
		y = V(1, 0, 0) - along * along.X
	end
	return Kit.part(
		name,
		V(d.Magnitude, h, w),
		oriented(place, (a + b) / 2, along, y.Unit),
		color,
		material,
		parent
	)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

function Farm.build(pivot: CFrame, parent: Instance): Kit.Built
	Kit.reset(4127)
	local place = Kit.placer(pivot, FOUND_H)

	local model = Instance.new("Model")
	model.Name = "Farm"
	model.WorldPivot = pivot

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		return f
	end
	local shell = folder("Shell")
	local interior = folder("Interior")
	local doors = folder("Doors")
	local furniture = folder("Furniture")
	local dressing = folder("Dressing")
	-- Outside: the fences, gates, paths and small buildings are the grounds;
	-- everything loose in the yard and the field is the farmyard.
	local grounds = folder("Grounds")
	local farmyard = folder("Farmyard")

	local hidingSpots: { HidingSpot } = {}
	local function hide(spot: HidingSpot?)
		if spot then
			table.insert(hidingSpots, spot)
		end
	end
	local function spot(x: number, y: number, z: number, face: Vector3?): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face or V(0, 0, -1))
	end
	local FRONT, BACK, LEFT, RIGHT = V(0, 0, 1), V(0, 0, -1), V(-1, 0, 0), V(1, 0, 0)
	local function part(
		name: string,
		size: Vector3,
		pos: Vector3,
		color: Color3,
		material: Enum.Material,
		parentOf: Instance
	): Part
		return Kit.part(name, size, place(pos), color, material, parentOf)
	end
	local function rod(
		name: string,
		a: Vector3,
		b: Vector3,
		d: number,
		color: Color3,
		material: Enum.Material,
		parentOf: Instance
	): Part
		return Kit.rod(name, place(a).Position, place(b).Position, d, color, material, parentOf)
	end

	--------------------------------------------------------------------------
	-- The barn: floor and foundation
	--------------------------------------------------------------------------

	-- A stone foundation under the walls; inside, packed earth down the
	-- aisle and boards under the stalls and rooms.
	for _, sx in { -1, 1 } do
		part(
			"Foundation",
			V(WALL_T + 0.4, FOUND_H + 0.6, 2 * BZ + 0.4),
			V(sx * (BX - WALL_T / 2), (GROUND - 0.6 + L1) / 2, 0),
			Kit.weathered(STONE, 0.05),
			M.Cobblestone,
			shell
		)
	end
	for _, sz in { -1, 1 } do
		part(
			"Foundation",
			V(2 * IX, FOUND_H + 0.6, WALL_T + 0.4),
			V(0, (GROUND - 0.6 + L1) / 2, sz * (BZ - WALL_T / 2)),
			Kit.weathered(STONE, 0.05),
			M.Cobblestone,
			shell
		)
	end
	part(
		"AisleFloor",
		V(2 * AISLE, 0.6, 2 * IZ),
		V(0, L1 - 0.3, 0),
		EARTH_FLOOR,
		M.Ground,
		interior
	)
	for _, sx in { -1, 1 } do
		part(
			"BarnFloor",
			V(IX - AISLE, 0.6, 2 * IZ),
			V(sx * (IX + AISLE) / 2, L1 - 0.3, 0),
			BOARD,
			M.WoodPlanks,
			interior
		)
	end
	-- Earth ramps up to the sills of both big doorways.
	for _, sz in { -1, 1 } do
		Kit.rightTriangle(
			"Ramp",
			place(V(0, GROUND, sz * BZ)).Position,
			place(V(0, L1, sz * BZ)).Position,
			place(V(0, GROUND, sz * (BZ + 4))).Position,
			DOOR_W + 2,
			DIRT,
			M.Ground,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- The barn: walls
	--------------------------------------------------------------------------

	type Hole = { at: number, width: number, sill: number, head: number }

	--[[
		A barn wall: bare boards inside, red outside with a batten over every
		joint, cut round its openings. One band at a time, as Kit.wall does
		the cutting: the boards and the red are two walls of it, one inside
		the other, so the paint always follows the holes.
	]]
	local function boardWall(
		name: string,
		axis: string,
		fixed: number,
		from: number,
		to: number,
		bottom: number,
		top: number,
		outward: number,
		holes: { Hole }
	)
		local openings: { Kit.Opening } = {}
		for _, h in holes do
			table.insert(openings, { at = h.at, width = h.width, sill = h.sill, head = h.head })
		end
		Kit.wall({
			name = name,
			axis = axis,
			fixed = fixed - outward * 0.075,
			from = from,
			to = to,
			bottom = bottom,
			top = top,
			thickness = WALL_T - 0.15,
			openings = openings,
			color = BOARD,
			material = M.WoodPlanks,
			place = place,
			parent = shell,
			weather = 0.05,
		})
		Kit.wall({
			name = name .. "Cladding",
			axis = axis,
			fixed = fixed + outward * (WALL_T / 2 - 0.075),
			from = from,
			to = to,
			bottom = bottom,
			top = top,
			thickness = 0.15,
			openings = openings,
			color = BARN_RED,
			material = M.WoodPlanks,
			place = place,
			parent = shell,
			weather = 0.04,
		})
		-- Battens every two studs, broken round the holes.
		local across = fixed + outward * (WALL_T / 2 + 0.06)
		local function batten(u: number, y0: number, y1: number)
			if y1 - y0 < 0.3 then
				return
			end
			local pos = if axis == "X"
				then V(u, (y0 + y1) / 2, across)
				else V(across, (y0 + y1) / 2, u)
			local size = if axis == "X" then V(0.3, y1 - y0, 0.12) else V(0.12, y1 - y0, 0.3)
			fine(part("Batten", size, pos, Kit.weathered(BATTEN, 0.05), M.Wood, shell))
		end
		local lo, hi = math.min(from, to), math.max(from, to)
		for u = lo + 1, hi - 0.8, 2 do
			local spans = { { bottom, top } }
			for _, h in holes do
				if math.abs(u - h.at) < h.width / 2 + 0.2 then
					local kept: { { number } } = {}
					for _, s in spans do
						if s[1] < h.sill then
							table.insert(kept, { s[1], math.min(s[2], h.sill) })
						end
						if s[2] > h.head then
							table.insert(kept, { math.max(s[1], h.head), s[2] })
						end
					end
					spans = kept
				end
			end
			for _, s in spans do
				batten(u, s[1], s[2])
			end
		end
	end

	-- The long walls: small windows high in the stalls, the tack room's
	-- window and the feed room's door.
	local STALL_WINDOWS = { 16.5, 2.5, -11.5 }
	for _, sx in { -1, 1 } do
		local holes: { Hole } = {}
		for _, z in STALL_WINDOWS do
			table.insert(holes, { at = z, width = 2.4, sill = 7, head = 9.4 })
		end
		if sx < 0 then
			table.insert(holes, { at = 28.1, width = 1.8, sill = 5, head = 7.4 })
		else
			table.insert(holes, { at = FEED_DOOR_Z, width = 3.6, sill = L1, head = 8 })
		end
		boardWall("BarnWall", "Z", sx * (BX - WALL_T / 2), -BZ, BZ, L1, EAVE, sx, holes)
	end

	-- The gables, in bands: the big doors in the bottom one, the hay door
	-- through the next two at the front, and above the eaves the gambrel's
	-- outline filled with right triangles.
	for _, sz in { -1, 1 } do
		local z = sz * (BZ - WALL_T / 2)
		local front = sz > 0
		boardWall("Gable", "X", z, -IX, IX, L1, HAY_SILL, sz, {
			{ at = 0, width = DOOR_W, sill = L1, head = DOOR_H },
		})
		local hay: { Hole } = if front
			then { { at = 0, width = HAY_W, sill = HAY_SILL, head = HAY_HEAD } }
			else {}
		boardWall("Gable", "X", z, -IX, IX, HAY_SILL, EAVE, sz, hay)
		local upper: { Hole } = if front
			then hay
			else { { at = 0, width = 2.2, sill = 17, head = 19.4 } }
		boardWall("Gable", "X", z, -KNEE_X, KNEE_X, EAVE, KNEE_Y, sz, upper)
		-- The triangles: each drawn twice, boards and paint.
		for _, layer in
			{
				{ off = -0.075, t = WALL_T - 0.15, c = BOARD },
				{ off = WALL_T / 2 - 0.075, t = 0.15, c = BARN_RED },
			}
		do
			local lz = z + sz * layer.off
			local function w(x: number, y: number): Vector3
				return place(V(x, y, lz)).Position
			end
			for _, sx in { -1, 1 } do
				Kit.rightTriangle(
					"Gable",
					w(sx * KNEE_X, EAVE),
					w(sx * KNEE_X, KNEE_Y),
					w(sx * BX, EAVE),
					layer.t,
					layer.c,
					M.WoodPlanks,
					shell
				)
				Kit.rightTriangle(
					"Gable",
					w(0, KNEE_Y),
					w(0, RIDGE),
					w(sx * KNEE_X, KNEE_Y),
					layer.t,
					layer.c,
					M.WoodPlanks,
					shell
				)
			end
		end
		-- Battens on the triangles, each up to the roof line.
		local across = z + sz * (WALL_T / 2 + 0.06)
		for x = -BX + 1, BX - 1, 2 do
			local y0 = if math.abs(x) < KNEE_X then KNEE_Y else EAVE
			local y1 = roofUnder(x) - 0.2
			if y1 - y0 > 0.4 then
				fine(
					part(
						"Batten",
						V(0.3, y1 - y0, 0.12),
						V(x, (y0 + y1) / 2, across),
						Kit.weathered(BATTEN, 0.05),
						M.Wood,
						shell
					)
				)
			end
		end
	end
	-- Corner boards, dark, up each corner.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			fine(
				part(
					"CornerBoard",
					V(0.5, EAVE, 0.5),
					V(sx * (BX + 0.1), EAVE / 2, sz * (BZ + 0.1)),
					TRIM,
					M.Wood,
					shell
				)
			)
		end
	end

	--------------------------------------------------------------------------
	-- The barn: roof
	--------------------------------------------------------------------------

	-- Corrugated iron in sheets across each of the four pitches, the eaves
	-- and gables overhanging; a few sheets gone from the upper pitches, so
	-- the sky shows through from the aisle.
	local OVER = 1.0
	local rz0, rz1 = -BZ - OVER, BZ + OVER
	local nSheets = math.ceil((rz1 - rz0) / 4)
	local sheetW = (rz1 - rz0) / nSheets
	local missing = { [3] = true, [9] = true, [12] = true }
	for _, sx in { -1, 1 } do
		for pitch = 1, 2 do
			local xa = if pitch == 1 then BX + OVER else KNEE_X
			local xb = if pitch == 1 then KNEE_X else 0
			local a, b = V(sx * xa, roofUnder(xa), 0), V(sx * xb, roofUnder(xb), 0)
			local along = (b - a).Unit
			local n = V(-along.Y, along.X, 0)
			if n.Y < 0 then
				n = -n
			end
			for k = 1, nSheets do
				local zc = rz0 + (k - 0.5) * sheetW
				if pitch == 2 and missing[(k + (if sx > 0 then 5 else 0) - 1) % nSheets + 1] then
					continue
				end
				beam(
					"RoofSheet",
					a + n * 0.15 + V(0, 0, zc),
					b + n * 0.15 + V(0, 0, zc),
					sheetW - 0.04,
					0.3,
					n,
					Kit.weathered(ROOF_IRON, 0.08),
					M.CorrodedMetal,
					place,
					shell
				)
			end
		end
	end
	-- A round capping along the ridge, and flashing along each knee.
	rod(
		"RidgeCap",
		V(0, RIDGE + 0.3, rz0),
		V(0, RIDGE + 0.3, rz1),
		0.8,
		ROOF_IRON,
		M.CorrodedMetal,
		shell
	)
	for _, sx in { -1, 1 } do
		rod(
			"KneeFlashing",
			V(sx * KNEE_X, KNEE_Y + 0.3, rz0),
			V(sx * KNEE_X, KNEE_Y + 0.3, rz1),
			0.6,
			ROOF_IRON,
			M.CorrodedMetal,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- The barn: frame and lofts
	--------------------------------------------------------------------------

	local timber = Kit.weathered(TIMBER, 0.04)
	-- Posts along both sides of the aisle, the girders on them, the joists
	-- out to the walls, and the lofts' boards on top.
	for _, sx in { -1, 1 } do
		for _, z in BENTS do
			part(
				"AislePost",
				V(0.8, GIRDER_Y, 0.8),
				V(sx * POST_X, GIRDER_Y / 2, z),
				timber,
				M.Wood,
				interior
			)
			part(
				"Joist",
				V(IX - POST_X - 0.4, LOFT - 0.5 - 11.0, 0.5),
				V(sx * (IX + POST_X + 0.4) / 2, 11.25, z),
				timber,
				M.Wood,
				interior
			)
			part(
				"WallPost",
				V(0.8, EAVE, 0.8),
				V(sx * (IX - 0.4), EAVE / 2, z),
				timber,
				M.Wood,
				interior
			)
		end
		part(
			"Girder",
			V(0.8, LOFT - 0.5 - GIRDER_Y, 2 * IZ),
			V(sx * POST_X, (GIRDER_Y + LOFT - 0.5) / 2, 0),
			timber,
			M.Wood,
			interior
		)
		part(
			"LoftFloor",
			V(IX - AISLE, 0.5, 2 * IZ),
			V(sx * (IX + AISLE) / 2, LOFT - 0.25, 0),
			Kit.weathered(BOARD, 0.04),
			M.WoodPlanks,
			interior
		)
		part(
			"WallPlate",
			V(WALL_T, 0.6, 2 * BZ),
			V(sx * (BX - WALL_T / 2), EAVE + 0.3, 0),
			timber,
			M.Wood,
			shell
		)
	end
	-- The cross lofts over each end's doors, on beams between the girders.
	for _, sz in { -1, 1 } do
		local edge = if sz > 0 then FRONT_LOFT else BACK_LOFT
		part(
			"LoftFloor",
			V(2 * AISLE, 0.5, IZ - math.abs(edge)),
			V(0, LOFT - 0.25, sz * (IZ + math.abs(edge)) / 2),
			Kit.weathered(BOARD, 0.04),
			M.WoodPlanks,
			interior
		)
		for _, z in { edge + sz * 0.4, sz * (IZ - 0.3) } do
			part(
				"LoftBeam",
				V(2 * POST_X - 0.8, LOFT - 0.5 - GIRDER_Y, 0.6),
				V(0, (GIRDER_Y + LOFT - 0.5) / 2, z),
				timber,
				M.Wood,
				interior
			)
		end
	end
	-- Above the lofts: posts up to the knees, a plate along each knee, a
	-- collar across, and the rafters under the iron.
	for _, sx in { -1, 1 } do
		for _, z in BENTS do
			part(
				"KneePost",
				V(0.8, KNEE_Y - LOFT, 0.8),
				V(sx * KNEE_X, (LOFT + KNEE_Y) / 2, z),
				timber,
				M.Wood,
				interior
			)
		end
		part(
			"KneePlate",
			V(0.8, 0.8, 2 * IZ),
			V(sx * KNEE_X, KNEE_Y + 0.4 - 0.8, 0),
			timber,
			M.Wood,
			interior
		)
	end
	for _, z in BENTS do
		part("Collar", V(2 * KNEE_X, 0.7, 0.6), V(0, KNEE_Y - 0.75, z), timber, M.Wood, interior)
	end
	for z = -IZ + 1.2, IZ - 1.0, 3.5 do
		for _, sx in { -1, 1 } do
			for pitch = 1, 2 do
				local xa = if pitch == 1 then BX - 0.1 else KNEE_X
				local xb = if pitch == 1 then KNEE_X else 0.25
				local a, b = V(sx * xa, roofUnder(xa), z), V(sx * xb, roofUnder(xb), z)
				local along = (b - a).Unit
				local n = V(-along.Y, along.X, 0)
				if n.Y < 0 then
					n = -n
				end
				beam(
					"Rafter",
					a - n * 0.3,
					b - n * 0.3,
					0.5,
					0.6,
					n,
					timber,
					M.Wood,
					place,
					interior
				)
			end
		end
	end
	part("RidgeBoard", V(0.5, 0.9, 2 * IZ), V(0, RIDGE - 0.45, 0), timber, M.Wood, interior)

	-- The stair to the back loft, up one side of the aisle.
	Kit.staircase(
		"LoftStair",
		V(-4.7, L1, -9),
		V(-4.7, LOFT, BACK_LOFT + 0.2),
		3,
		12,
		place,
		interior,
		{
			rails = { 1 },
			treadColor = BOARD,
			railColor = timber,
			rotten = 0.1,
		}
	)

	--------------------------------------------------------------------------
	-- The barn: doors
	--------------------------------------------------------------------------

	-- A pair of big doors in each end, swinging out, a crossbuck of dark
	-- trim on the outside of each leaf.
	for _, sz in { -1, 1 } do
		local look = if sz > 0 then FRONT else BACK
		for _, sx in { -1, 1 } do
			local frame = place(V(sx * DOOR_W / 4, L1 + DOOR_H / 2, sz * (BZ - WALL_T / 2)))
				* CFrame.new(Vector3.zero, look)
			local right = look:Cross(Vector3.yAxis)
			local hinge = if right:Dot(V(sx, 0, 0)) >= 0 then 1 else -1
			local door = Kit.door(frame, DOOR_W / 2, DOOR_H, {
				parent = doors,
				hinge = hinge,
				swing = 1,
				thickness = 0.5,
				color = Kit.weathered(BARN_RED, 0.04),
				panel = BATTEN,
				style = "plank",
				gap = 0.12,
				openAngle = 92,
				name = "BarnDoor",
			})
			local leaf = door:FindFirstChild("Leaf") :: BasePart?
			if leaf then
				local cf, w, h = leaf.CFrame, leaf.Size.X, leaf.Size.Y
				-- On the outside face, which is the frame's look side, -Z.
				local face = -(leaf.Size.Z / 2 + 0.2)
				local corners = {
					V(-w / 2 + 0.3, -h / 2 + 0.3, face),
					V(w / 2 - 0.3, -h / 2 + 0.3, face),
					V(w / 2 - 0.3, h / 2 - 0.3, face),
					V(-w / 2 + 0.3, h / 2 - 0.3, face),
				}
				for k = 1, 4 do
					fine(
						Kit.rod(
							"DoorTrim",
							cf * corners[k],
							cf * corners[k % 4 + 1],
							0.3,
							TRIM,
							M.Wood,
							door
						)
					)
				end
				fine(Kit.rod("DoorTrim", cf * corners[1], cf * corners[3], 0.3, TRIM, M.Wood, door))
				fine(Kit.rod("DoorTrim", cf * corners[2], cf * corners[4], 0.3, TRIM, M.Wood, door))
			end
		end
	end
	-- The hay door, a pair of leaves opening out from the front loft.
	for _, sx in { -1, 1 } do
		local frame = place(V(sx * HAY_W / 4, (HAY_SILL + HAY_HEAD) / 2, BZ - WALL_T / 2))
			* CFrame.new(Vector3.zero, FRONT)
		local right = FRONT:Cross(Vector3.yAxis)
		Kit.door(frame, HAY_W / 2, HAY_HEAD - HAY_SILL, {
			parent = doors,
			hinge = if right:Dot(V(sx, 0, 0)) >= 0 then 1 else -1,
			swing = 1,
			thickness = 0.4,
			color = Kit.weathered(BARN_RED, 0.04),
			panel = BATTEN,
			style = "plank",
			gap = 0.1,
			openAngle = 90,
			name = "HayDoor",
		})
	end
	-- The feed room's door out to the yard.
	do
		local frame = place(V(BX - WALL_T / 2, 4, FEED_DOOR_Z)) * CFrame.new(Vector3.zero, RIGHT)
		Kit.door(frame, 3.6, 8, {
			parent = doors,
			hinge = -1,
			swing = 1,
			thickness = 0.4,
			color = Kit.weathered(BARN_RED, 0.04),
			panel = BATTEN,
			style = "plank",
			gap = 0.1,
			name = "FeedRoomDoor",
		})
	end
	-- The hood over the hay door, the hoist beam under it, the pulley, and
	-- the rope hanging down with its hook.
	do
		local ridgeY, eaveY, half, reach = 25.6, 22.6, 3.8, 5.0
		for _, sx in { -1, 1 } do
			local along = V(-sx * half, ridgeY - eaveY, 0).Unit
			local n = V(-along.Y, along.X, 0)
			if n.Y < 0 then
				n = -n
			end
			beam(
				"HoodRoof",
				V(sx * half, eaveY, BZ + reach / 2) + n * 0.15,
				V(0, ridgeY, BZ + reach / 2) + n * 0.15,
				reach,
				0.3,
				n,
				Kit.weathered(ROOF_IRON, 0.06),
				M.CorrodedMetal,
				place,
				shell
			)
		end
		part(
			"HoistBeam",
			V(0.7, 0.8, reach + 2),
			V(0, ridgeY - 1.6, BZ + reach / 2 - 1),
			timber,
			M.Wood,
			shell
		)
		fine(
			Kit.disc(
				"Pulley",
				oriented(place, V(0, ridgeY - 2.5, BZ + reach - 0.6), V(0, 0, 1), V(1, 0, 0)),
				1.0,
				0.3,
				C.IRON,
				M.Metal,
				shell
			)
		)
		fine(
			rod(
				"HoistRope",
				V(0, ridgeY - 2.9, BZ + reach - 0.6),
				V(0, 8.5, BZ + reach - 0.6),
				0.14,
				rgb(60, 50, 36),
				M.Fabric,
				shell
			)
		)
		fine(
			rod(
				"Hook",
				V(0, 8.5, BZ + reach - 0.6),
				V(0, 7.6, BZ + reach - 0.35),
				0.2,
				C.IRON,
				M.Metal,
				shell
			)
		)
		fine(
			rod(
				"Hook",
				V(0, 7.6, BZ + reach - 0.35),
				V(0, 7.9, BZ + reach),
				0.2,
				C.IRON,
				M.Metal,
				shell
			)
		)
	end

	--------------------------------------------------------------------------
	-- The barn: stalls, tack room, feed room
	--------------------------------------------------------------------------

	-- Six stalls a side between the bents: board partitions with a round
	-- rail along the top, a gate into each from the aisle that swings in,
	-- and a manger and hay rack at the back.
	local STALL_H = 5.5
	for _, sx in { -1, 1 } do
		for i = 1, #BENTS - 1 do
			local zHi, zLo = BENTS[i], BENTS[i + 1]
			local zMid = (zHi + zLo) / 2
			-- The partition on the stall's far side (the first one's near side
			-- is the tack or feed room's wall).
			part(
				"StallBoards",
				V(IX - POST_X - 0.4, STALL_H, 0.3),
				V(sx * (IX + POST_X + 0.4) / 2, STALL_H / 2, zLo),
				BOARD,
				M.WoodPlanks,
				interior
			)
			fine(
				rod(
					"StallRail",
					V(sx * (POST_X + 0.4), STALL_H + 0.15, zLo),
					V(sx * IX, STALL_H + 0.15, zLo),
					0.4,
					timber,
					M.Wood,
					interior
				)
			)
			-- The front: the gate at the high end, a fixed panel below it.
			local gateHi = zHi - 0.4
			local gateLo = gateHi - 4.0
			local panelLo = zLo + 0.4
			part(
				"StallFront",
				V(0.3, 5.0, gateLo - panelLo),
				V(sx * POST_X, 0.3 + 2.5, (gateLo + panelLo) / 2),
				BOARD,
				M.WoodPlanks,
				interior
			)
			fine(
				rod(
					"StallRail",
					V(sx * POST_X, 5.45, panelLo),
					V(sx * POST_X, 5.45, gateLo),
					0.35,
					timber,
					M.Wood,
					interior
				)
			)
			local look = V(sx, 0, 0)
			local right = look:Cross(Vector3.yAxis)
			Kit.door(
				place(V(sx * POST_X, 0.3 + 2.5, (gateHi + gateLo) / 2))
					* CFrame.new(Vector3.zero, look),
				4.0,
				5.0,
				{
					parent = doors,
					hinge = if right:Dot(V(0, 0, 1)) >= 0 then 1 else -1,
					swing = 1,
					thickness = 0.3,
					color = Kit.weathered(BOARD, 0.06),
					panel = TIMBER,
					style = "plank",
					gap = 0.12,
					openAngle = 88,
					name = "StallGate",
				}
			)
			-- The manger against the wall, and the rack above it.
			local mx = sx * (IX - 0.9)
			part("Manger", V(1.8, 1.2, 4.0), V(mx, 2.6, zMid), timber, M.WoodPlanks, interior)
			fine(
				rod(
					"MangerRim",
					V(sx * (IX - 1.8), 3.25, zMid - 2),
					V(sx * (IX - 1.8), 3.25, zMid + 2),
					0.25,
					timber,
					M.Wood,
					interior
				)
			)
			for _, dz in { -1.5, 1.5 } do
				fine(
					rod(
						"MangerLeg",
						V(sx * (IX - 1.6), L1, zMid + dz),
						V(sx * (IX - 1.6), 2.0, zMid + dz),
						0.3,
						timber,
						M.Wood,
						interior
					)
				)
			end
			fine(
				rod(
					"HayRack",
					V(sx * (IX - 0.15), 7.6, zMid - 2),
					V(sx * (IX - 0.15), 7.6, zMid + 2),
					0.3,
					timber,
					M.Wood,
					interior
				)
			)
			fine(
				rod(
					"HayRack",
					V(sx * (IX - 1.7), 4.6, zMid - 2),
					V(sx * (IX - 1.7), 4.6, zMid + 2),
					0.25,
					timber,
					M.Wood,
					interior
				)
			)
			for k = 0, 5 do
				local z = zMid - 1.9 + k * 0.76
				fine(
					rod(
						"HayRackSlat",
						V(sx * (IX - 0.15), 7.6, z),
						V(sx * (IX - 1.7), 4.6, z),
						0.16,
						timber,
						M.Wood,
						interior
					)
				)
			end
			-- Old straw on the floor.
			fine(
				part(
					"Straw",
					V(IX - POST_X - 0.8, 0.12, zHi - zLo - 0.6),
					V(sx * (IX + POST_X) / 2, L1 + 0.06, zMid),
					Kit.weathered(STRAW, 0.08),
					M.Grass,
					dressing
				)
			)
		end
	end

	-- The tack room, left front corner, and the feed room opposite: a wall
	-- across at the first bent, and the tack room walled off from the aisle
	-- with a door.
	for _, sx in { -1, 1 } do
		part(
			"RoomWall",
			V(IX - POST_X - 0.4, 11.0, 0.3),
			V(sx * (IX + POST_X + 0.4) / 2, 5.5, BENTS[1]),
			BOARD,
			M.WoodPlanks,
			interior
		)
	end
	Kit.wall({
		name = "RoomWall",
		axis = "Z",
		fixed = -POST_X,
		from = BENTS[1] + 0.4,
		to = IZ,
		bottom = L1,
		top = GIRDER_Y,
		thickness = 0.3,
		openings = { { at = 24.8, width = 3.8, sill = L1, head = 7.8 } },
		color = BOARD,
		material = M.WoodPlanks,
		place = place,
		parent = interior,
	})
	Kit.door(place(V(-POST_X, 3.9, 24.8)) * CFrame.new(Vector3.zero, LEFT), 3.8, 7.8, {
		parent = doors,
		hinge = -1,
		swing = 1,
		thickness = 0.35,
		color = Kit.weathered(BOARD, 0.05),
		panel = TIMBER,
		style = "plank",
		gap = 0.1,
		name = "TackRoomDoor",
	})

	--------------------------------------------------------------------------
	-- The barn: what is in it
	--------------------------------------------------------------------------

	-- The tack room: the harness cupboard, and saddles on their trees with
	-- a collar on a peg over each.
	do
		local press, pressSpot = Furnish.wardrobe(
			spot(-IX, L1, 23.8, RIGHT),
			furniture,
			{ name = "HarnessCupboard", wood = C.WALNUT }
		)
		Furnish.backTo(press, 0.3)
		hide(pressSpot)
		-- Saddles on their trees along the end wall, a collar on the peg above
		-- each. Drawn with their backs toward +Z and slid back to the wall.
		for _, x in { -14.0, -10.4 } do
			local b = Furnish.begin("SaddleRack", spot(x, L1, IZ, BACK), furniture)
			b.box("RackArm", V(0.5, 0.5, 2.0), V(0, 4.6, 0), TIMBER, M.Wood)
			b.box("Saddle", V(1.7, 0.7, 1.8), V(0, 5.1, -0.1), C.LEATHER, M.Leather)
			fine(
				b.rod(
					"Cantle",
					V(-0.7, 5.5, 0.6),
					V(0.7, 5.5, 0.6),
					0.35,
					C.LEATHER_DARK,
					M.Leather
				)
			)
			fine(b.ball("Pommel", V(0, 5.55, -0.8), 0.45, C.LEATHER_DARK, M.Leather))
			for _, sx in { -1, 1 } do
				fine(
					b.rod(
						"StirrupLeather",
						V(sx * 0.9, 5.0, -0.1),
						V(sx * 0.95, 3.4, -0.05),
						0.12,
						C.LEATHER_DARK,
						M.Leather
					)
				)
				fine(
					b.rod(
						"Stirrup",
						V(sx * 0.95, 3.3, -0.35),
						V(sx * 0.95, 3.3, 0.25),
						0.12,
						C.IRON,
						M.Metal
					)
				)
			end
			local n = 8
			for i = 0, n - 1 do
				local a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
				fine(
					b.rod(
						"HorseCollar",
						V(0.9 * math.sin(a0), 8.3 + 1.2 * math.cos(a0), 0.55),
						V(0.9 * math.sin(a1), 8.3 + 1.2 * math.cos(a1), 0.55),
						0.45,
						C.LEATHER,
						M.Leather
					)
				)
			end
			fine(b.rod("Peg", V(0, 9.3, 1.0), V(0, 9.3, 0.3), 0.2, TIMBER, M.Wood))
			Furnish.backTo(b.model, 0.3)
		end
	end

	-- The feed room: grain bins along the wall, sacks, a scoop in a bin.
	for k, x in { 14.8, 11.2 } do
		local b = Furnish.begin("GrainBin", spot(x, L1, IZ, BACK), furniture)
		b.box("BinBody", V(3.4, 3.4, 3.2), V(0, 1.7, 0), TIMBER, M.WoodPlanks)
		local lid = if k == 1
			then CFrame.new(0.2, 3.525, -0.45) * CFrame.Angles(0, 0.12, 0)
			else CFrame.new(0, 3.525, 0)
		b.box("BinLid", V(3.5, 0.25, 3.3), lid.Position, BOARD, M.WoodPlanks, lid.Rotation)
		fine(b.box("Grain", V(3.0, 0.1, 2.8), V(0, 3.0, 0), rgb(76, 64, 40), M.Sand))
		Furnish.backTo(b.model, 0.3)
	end
	for i, pos in { V(8.6, 0, 25.0), V(8.8, 0, 23.1), V(8.7, 1.4, 24.1) } do
		local b = Furnish.begin(
			"Sack",
			spot(pos.X, L1 + pos.Y, pos.Z, BACK) * CFrame.Angles(0, (i - 2) * 0.15, 0),
			furniture
		)
		b.box(
			"Sack",
			V(1.8, 1.4, 1.2),
			V(0, 0.7, 0),
			Kit.weathered(rgb(78, 66, 48), 0.08),
			M.Fabric
		)
		fine(b.ball("SackTop", V(0, 1.45, 0), 0.9, Kit.weathered(rgb(78, 66, 48), 0.08), M.Fabric))
	end

	-- In the aisle: churns by the feed room, a barrow, a heap of loose hay,
	-- a pitchfork against a post, a lantern gone out on a hook.
	for _, pos in { V(10.6, 0, 21.2), V(11.8, 0, 21.5) } do
		Yard.churn(place(pos), furniture)
	end
	do
		local b = Furnish.begin(
			"Wheelbarrow",
			spot(3.6, L1, 12.5, LEFT) * CFrame.Angles(0, 0.4, 0),
			furniture
		)
		b.box(
			"BarrowTray",
			V(2.6, 0.8, 3.0),
			V(0, 1.8, 0),
			TIMBER,
			M.WoodPlanks,
			CFrame.Angles(0.12, 0, 0)
		)
		b.disc(
			"BarrowWheel",
			V(0, 0.9, -2.3),
			1.8,
			0.3,
			C.IRON,
			M.Metal,
			CFrame.Angles(0, 0, math.pi / 2)
		)
		for _, sx in { -1, 1 } do
			fine(
				b.rod(
					"BarrowHandle",
					V(sx * 0.9, 1.3, -1.8),
					V(sx * 1.0, 2.4, 3.2),
					0.28,
					TIMBER,
					M.Wood
				)
			)
			fine(
				b.rod(
					"BarrowLeg",
					V(sx * 0.9, 1.4, 1.0),
					V(sx * 0.9, L1, 1.2),
					0.25,
					TIMBER,
					M.Wood
				)
			)
		end
	end
	Yard.hayBale(spot(-3.8, L1, 20.5, FRONT) * CFrame.Angles(0, 0.3, 0), furniture)
	Yard.hayBale(spot(-3.2, L1 + 1.5, 20.3, FRONT) * CFrame.Angles(0, -0.2, 0), furniture)
	fine(
		part(
			"LooseHay",
			V(5.2, 1.0, 4.4),
			V(-3.0, L1 + 0.5, 15.8),
			Kit.weathered(STRAW, 0.08),
			M.Grass,
			dressing
		)
	)
	fine(rod("Pitchfork", V(6.6, L1, 5.4), V(6.9, 6.6, 5.6), 0.22, TIMBER, M.Wood, furniture))
	for k = -1, 1 do
		fine(
			rod(
				"ForkTine",
				V(6.9 + k * 0.18, 6.4, 5.6),
				V(6.95 + k * 0.2, 7.6, 5.7),
				0.08,
				C.IRON,
				M.Metal,
				furniture
			)
		)
	end
	fine(
		rod(
			"LanternHook",
			V(POST_X - 0.4, 7.8, -1),
			V(POST_X - 1.1, 7.8, -1),
			0.14,
			C.IRON,
			M.Metal,
			dressing
		)
	)
	Decor.lantern(spot(POST_X - 1.05, 5.9, -1), dressing)

	-- The worst stall: blood soaked into the straw and dragged out to the
	-- aisle, a chain hanging from the joist over it with a hook on the end.
	do
		local z = (BENTS[4] + BENTS[5]) / 2
		Decor.stain(place(V(-12.8, L1 + 0.14, z + 0.6)), dressing, 3.4, C.BLOOD)
		Decor.stain(place(V(-10.4, L1 + 0.14, z - 1.4)), dressing, 1.6, C.BLOOD_OLD)
		Decor.smear(
			place(V(-11, L1 + 0.16, z)).Position,
			place(V(-2.5, L1 + 0.05, z - 9)).Position,
			dressing,
			1.4,
			C.BLOOD_OLD
		)
		local top = V(-12.4, LOFT - 1.0, z)
		for k = 0, 5 do
			local a = top + V(0, -k * 0.8, 0)
			fine(rod("Chain", a, a + V(0, -0.75, 0), 0.18, C.IRON, M.Metal, dressing))
		end
		fine(
			rod("Hook", top + V(0, -4.8, 0), top + V(0, -5.6, 0.35), 0.2, C.IRON, M.Metal, dressing)
		)
		fine(
			rod(
				"Hook",
				top + V(0, -5.6, 0.35),
				top + V(0, -5.2, 0.75),
				0.2,
				C.IRON,
				M.Metal,
				dressing
			)
		)
	end

	-- Hay in the lofts: stacks along the walls, a pile over the back doors,
	-- a few bales by the hay door.
	for _, sx in { -1, 1 } do
		for _, z in { 16.5, 2.5, -11.5 } do
			Yard.hayStack(
				spot(sx * 13.2, LOFT, z, RIGHT),
				furniture,
				{ cols = 1, rows = 2, layers = 2 }
			)
		end
	end
	Yard.hayStack(spot(0, LOFT, -27.3, FRONT), furniture, { cols = 3, rows = 2, layers = 3 })
	for _, x in { -5.2, 5.2 } do
		Yard.hayBale(spot(x, LOFT, 26.5, RIGHT), furniture)
	end
	fine(
		part(
			"LooseHay",
			V(4.0, 0.9, 5.0),
			V(-13, LOFT + 0.45, -4.5),
			Kit.weathered(STRAW, 0.08),
			M.Grass,
			dressing
		)
	)

	-- The hay track along the ridge, on hangers from the ridge board, with
	-- the carrier and the grapple fork hung from it over the aisle.
	do
		local trackY = RIDGE - 1.9
		part(
			"HayTrack",
			V(0.3, 0.5, 2 * (IZ - 3)),
			V(0, trackY, 0),
			C.IRON,
			M.CorrodedMetal,
			interior
		)
		for _, z in BENTS do
			fine(
				rod(
					"TrackHanger",
					V(0, trackY + 0.25, z),
					V(0, RIDGE - 0.9, z),
					0.14,
					C.IRON,
					M.Metal,
					interior
				)
			)
		end
		local cz = 14
		fine(
			part(
				"Carrier",
				V(0.8, 0.8, 1.6),
				V(0, trackY - 0.6, cz),
				C.IRON,
				M.CorrodedMetal,
				interior
			)
		)
		for _, dz in { -0.5, 0.5 } do
			fine(
				Kit.disc(
					"CarrierWheel",
					oriented(place, V(0.3, trackY + 0.05, cz + dz), V(0, 1, 0), V(1, 0, 0)),
					0.5,
					0.12,
					C.IRON,
					M.Metal,
					interior
				)
			)
		end
		local forkTop = 16.5
		fine(
			rod(
				"ForkRope",
				V(0, trackY - 1.0, cz),
				V(0, forkTop + 0.3, cz),
				0.14,
				rgb(60, 50, 36),
				M.Fabric,
				interior
			)
		)
		fine(
			rod(
				"GrappleFork",
				V(0, forkTop + 0.3, cz),
				V(0, forkTop - 2.2, cz),
				0.3,
				C.IRON,
				M.Metal,
				interior
			)
		)
		for k = 0, 3 do
			local a = math.pi / 2 * k + math.pi / 4
			local d = V(math.cos(a), 0, math.sin(a))
			local p0 = V(0, forkTop - 2.0, cz)
			local p1 = p0 + d * 1.1 + V(0, -1.2, 0)
			local p2 = p1 + d * -0.3 + V(0, -1.1, 0)
			fine(rod("ForkTine", p0, p1, 0.2, C.IRON, M.Metal, interior))
			fine(rod("ForkTine", p1, p2, 0.18, C.IRON, M.Metal, interior))
		end
	end

	--------------------------------------------------------------------------
	-- The silo
	--------------------------------------------------------------------------

	-- Staves round a circle bound with iron hoops, a steel dome, a door at
	-- the foot toward the yard and the chute up its back. Hollow: the door
	-- shuts, and inside is a hiding place.
	do
		local N = 28
		local doorK = 7 -- the stave the door is centred on, facing about +Z
		local doorA = 2 * math.pi * (doorK + 0.5) / N
		local chord = 2 * SILO_R * math.sin(math.pi / N) + 0.08
		local top = GROUND + SILO_H
		local doorTop = GROUND + 8.2
		local function at(a: number, r: number, y: number): Vector3
			return V(SILO_X + r * math.cos(a), y, SILO_Z + r * math.sin(a))
		end
		for k = 0, N - 1 do
			local a = 2 * math.pi * (k + 0.5) / N
			local y0 = if math.abs(k - doorK) <= 1 then doorTop else GROUND - 0.5
			local tangent = V(-math.sin(a), 0, math.cos(a))
			Kit.part(
				"SiloStave",
				V(chord, top - y0, 0.7),
				oriented(place, at(a, SILO_R - 0.35, (y0 + top) / 2), tangent, V(0, 1, 0)),
				Kit.weathered(STAVE, 0.07),
				M.WoodPlanks,
				shell
			)
		end
		for _, y in { GROUND + 11, GROUND + 19, GROUND + 27, GROUND + 35 } do
			local n = 16
			for k = 0, n - 1 do
				local a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
				fine(
					rod(
						"SiloHoop",
						at(a0, SILO_R + 0.08, y),
						at(a1, SILO_R + 0.08, y),
						0.22,
						C.RUST,
						M.CorrodedMetal,
						shell
					)
				)
			end
		end
		Kit.ball(
			"SiloDome",
			place(V(SILO_X, top, SILO_Z)).Position,
			2 * SILO_R + 0.5,
			rgb(66, 62, 58),
			M.CorrodedMetal,
			shell
		)
		rod(
			"SiloVent",
			V(SILO_X, top + SILO_R, SILO_Z),
			V(SILO_X, top + SILO_R + 1.4, SILO_Z),
			1.2,
			rgb(60, 56, 52),
			M.CorrodedMetal,
			shell
		)
		Kit.disc(
			"SiloVentCap",
			place(V(SILO_X, top + SILO_R + 1.5, SILO_Z)),
			2.0,
			0.3,
			rgb(60, 56, 52),
			M.CorrodedMetal,
			shell
		)
		-- The chute up the back, with its little roof.
		local chuteA = -math.pi / 2
		local chuteP = at(chuteA, SILO_R + 1.1, (GROUND + top - 2) / 2)
		part(
			"SiloChute",
			V(2.8, top - 2 - GROUND, 2.2),
			chuteP,
			Kit.weathered(STAVE, 0.05),
			M.WoodPlanks,
			shell
		)
		part(
			"ChuteCap",
			V(3.4, 0.4, 2.8),
			V(chuteP.X, top - 1.8, chuteP.Z),
			ROOF_IRON,
			M.CorrodedMetal,
			shell
		)
		-- The door, and what is inside.
		local doorP = at(doorA, SILO_R - 0.35, GROUND + 4.1)
		Kit.door(
			spot(doorP.X, doorP.Y, doorP.Z, V(math.cos(doorA), 0, math.sin(doorA))),
			4.0,
			8.0,
			{
				parent = doors,
				hinge = -1,
				swing = 1,
				thickness = 0.35,
				color = Kit.weathered(STAVE, 0.05),
				panel = TIMBER,
				style = "plank",
				gap = 0.1,
				name = "SiloDoor",
			}
		)
		Kit.disc(
			"SiloFloor",
			place(V(SILO_X, GROUND + 0.1, SILO_Z)),
			2 * SILO_R - 1.4,
			0.2,
			rgb(52, 50, 46),
			M.Concrete,
			interior
		)
		Kit.ball(
			"Silage",
			place(V(SILO_X - 1.5, GROUND - 3.2, SILO_Z - 2.5)).Position,
			8.5,
			rgb(58, 52, 34),
			M.Grass,
			interior
		)
		for k = 0, 9 do
			local y = GROUND + 1.5 + k * 1.2
			fine(
				rod(
					"LadderRung",
					at(chuteA - 0.1, SILO_R - 0.9, y),
					at(chuteA + 0.1, SILO_R - 0.9, y),
					0.18,
					C.IRON,
					M.Metal,
					interior
				)
			)
		end
		local inside = Instance.new("Folder")
		inside.Name = "SiloInside"
		inside.Parent = furniture
		hide(
			Kit.hideVolume(
				"SiloHidingVolume",
				place(V(SILO_X, GROUND + 3.2, SILO_Z + 2.5)),
				V(6, 6, 4),
				"Cupboard",
				1,
				inside
			)
		)
	end

	--------------------------------------------------------------------------
	-- The windpump and its tank
	--------------------------------------------------------------------------

	do
		local H = 30
		local base, head = 2.8, 0.7
		local top = GROUND + H
		local function half(y: number): number
			return base + (head - base) * (y - GROUND) / H
		end
		local iron = Kit.weathered(rgb(60, 58, 56), 0.05)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				rod(
					"PumpLeg",
					V(PUMP_X + sx * (base + 0.2), GROUND - 0.6, PUMP_Z + sz * (base + 0.2)),
					V(PUMP_X + sx * head, top, PUMP_Z + sz * head),
					0.45,
					iron,
					M.Metal,
					grounds
				)
			end
		end
		local levels = { GROUND + 0.8, GROUND + 7, GROUND + 14, GROUND + 21, GROUND + 27 }
		for i, y in levels do
			local w = half(y)
			local corners = { V(-w, y, -w), V(w, y, -w), V(w, y, w), V(-w, y, w) }
			for k = 1, 4 do
				local p0, p1 = corners[k], corners[k % 4 + 1]
				fine(
					rod(
						"PumpGirt",
						V(PUMP_X, 0, PUMP_Z) + p0,
						V(PUMP_X, 0, PUMP_Z) + p1,
						0.18,
						iron,
						M.Metal,
						grounds
					)
				)
				if i < #levels then
					local y2 = levels[i + 1]
					local w2 = half(y2)
					local q0 = V(p0.X / w * w2, y2, p0.Z / w * w2)
					local q1 = V(p1.X / w * w2, y2, p1.Z / w * w2)
					local a, b = if i % 2 == 0 then p0 else p1, if i % 2 == 0 then q1 else q0
					fine(
						rod(
							"PumpBrace",
							V(PUMP_X, 0, PUMP_Z) + a,
							V(PUMP_X, 0, PUMP_Z) + b,
							0.12,
							iron,
							M.Metal,
							grounds
						)
					)
				end
			end
		end
		part(
			"PumpPlatform",
			V(3.2, 0.25, 3.2),
			V(PUMP_X, top, PUMP_Z),
			TIMBER,
			M.WoodPlanks,
			grounds
		)
		part("Gearbox", V(1.1, 1.2, 2.2), V(PUMP_X, top + 0.85, PUMP_Z), iron, M.Metal, grounds)
		-- The wheel, facing +Z: a hub, blades round it, a rim; some blades gone.
		local hub = V(PUMP_X, top + 1.4, PUMP_Z + 1.6)
		fine(
			Kit.disc(
				"WheelHub",
				oriented(place, hub, V(1, 0, 0), V(0, 0, 1)),
				0.9,
				0.5,
				iron,
				M.Metal,
				grounds
			)
		)
		local blades = 18
		for k = 0, blades - 1 do
			local a = 2 * math.pi * k / blades
			local dir = V(math.cos(a), math.sin(a), 0)
			if k % 7 ~= 3 then
				fine(
					Kit.part(
						"WheelBlade",
						V(0.9, 3.0, 0.06),
						oriented(place, hub + dir * 2.6, V(-dir.Y, dir.X, 0), dir)
							* CFrame.Angles(0, 0.35, 0),
						Kit.weathered(rgb(64, 60, 56), 0.08),
						M.Metal,
						grounds
					)
				)
			end
			local b0 = 2 * math.pi * k / blades
			local b1 = 2 * math.pi * (k + 1) / blades
			fine(
				rod(
					"WheelRim",
					hub + V(math.cos(b0), math.sin(b0), 0) * 4.1,
					hub + V(math.cos(b1), math.sin(b1), 0) * 4.1,
					0.14,
					iron,
					M.Metal,
					grounds
				)
			)
		end
		fine(
			rod(
				"TailBoom",
				V(PUMP_X, top + 1.1, PUMP_Z - 0.8),
				V(PUMP_X, top + 1.3, PUMP_Z - 5.6),
				0.2,
				iron,
				M.Metal,
				grounds
			)
		)
		fine(
			part(
				"TailVane",
				V(0.1, 2.2, 3.0),
				V(PUMP_X, top + 1.6, PUMP_Z - 6.4),
				Kit.weathered(rgb(64, 60, 56), 0.06),
				M.Metal,
				grounds
			)
		)
		fine(
			rod(
				"PumpRod",
				V(PUMP_X, top, PUMP_Z),
				V(PUMP_X, GROUND + 2.4, PUMP_Z),
				0.14,
				iron,
				M.Metal,
				grounds
			)
		)
		rod(
			"PumpHead",
			V(PUMP_X, GROUND, PUMP_Z),
			V(PUMP_X, GROUND + 2.6, PUMP_Z),
			0.7,
			iron,
			M.Metal,
			grounds
		)
		fine(
			rod(
				"PumpSpout",
				V(PUMP_X + 0.3, GROUND + 2.2, PUMP_Z),
				V(PUMP_X + 5.0, GROUND + 2.0, PUMP_Z),
				0.25,
				iron,
				M.Metal,
				grounds
			)
		)
		-- The tank: a ring of steel with black water in it.
		local tx, tr = PUMP_X + 7.5, 3.8
		local n = 16
		for k = 0, n - 1 do
			local a = 2 * math.pi * (k + 0.5) / n
			local d = V(math.cos(a), 0, math.sin(a))
			Kit.part(
				"StockTank",
				V(2 * tr * math.sin(math.pi / n) + 0.1, 2.2 + 0.4, 0.2),
				oriented(place, V(tx, GROUND + 0.9, PUMP_Z) + d * tr, V(-d.Z, 0, d.X), V(0, 1, 0)),
				Kit.weathered(rgb(62, 60, 58), 0.05),
				M.CorrodedMetal,
				grounds
			)
		end
		fine(
			Kit.disc(
				"TankWater",
				place(V(tx, GROUND + 1.6, PUMP_Z)),
				2 * tr - 0.3,
				0.06,
				rgb(16, 20, 18),
				M.Glass,
				grounds
			)
		)
	end

	--------------------------------------------------------------------------
	-- The outbuildings
	--------------------------------------------------------------------------

	type ShedSpec = {
		name: string,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		low: number, -- the eaves at the back (-Z), where the roof comes down
		high: number, -- the eaves at the front
		floor: number?, -- raised off the ground, on legs
		door: { at: number, width: number, height: number }?, -- in the front wall
		hole: { at: number, width: number, sill: number, head: number }?, -- the front's other opening
		window: number?, -- a window in the left side, at this z
	}
	--[[
		A small board building with a pent roof falling to the back: walls cut
		round a door or hole in the front and a window in one side, the side
		walls' tops following the slope. Returns the door's frame if it has
		one, looking out.
	]]
	local function shed(s: ShedSpec): CFrame?
		local t = 0.4
		local y0 = s.floor or GROUND
		local function slopeAt(z: number): number
			return s.low + (s.high - s.low) * (z - s.z0) / (s.z1 - s.z0)
		end
		local wood = Kit.weathered(rgb(64, 54, 44), 0.06)
		local frontHoles: { Kit.Opening } = {}
		local door = s.door
		if door then
			table.insert(
				frontHoles,
				{ at = door.at, width = door.width, sill = y0, head = y0 + door.height }
			)
		end
		local hole = s.hole
		if hole then
			table.insert(
				frontHoles,
				{ at = hole.at, width = hole.width, sill = y0 + hole.sill, head = y0 + hole.head }
			)
		end
		local function wall(
			axis: string,
			fixed: number,
			from: number,
			to: number,
			top: number,
			holes: { Kit.Opening }
		)
			Kit.wall({
				name = s.name .. "Wall",
				axis = axis,
				fixed = fixed,
				from = from,
				to = to,
				bottom = y0,
				top = top,
				thickness = t,
				openings = holes,
				color = wood,
				material = M.WoodPlanks,
				place = place,
				parent = grounds,
				weather = 0.06,
			})
		end
		wall("X", s.z1 - t / 2, s.x0, s.x1, y0 + s.high, frontHoles)
		wall("X", s.z0 + t / 2, s.x0, s.x1, y0 + s.low, {})
		for _, sx in { -1, 1 } do
			local x = if sx < 0 then s.x0 + t / 2 else s.x1 - t / 2
			local holes: { Kit.Opening } = {}
			local window = s.window
			if window and sx < 0 then
				table.insert(holes, { at = window, width = 1.8, sill = y0 + 3.4, head = y0 + 5.2 })
			end
			wall("Z", x, s.z0 + t, s.z1 - t, y0 + s.low, holes)
			Kit.rightTriangle(
				s.name .. "Wall",
				place(V(x, y0 + s.low, s.z1 - t)).Position,
				place(V(x, y0 + s.high, s.z1 - t)).Position,
				place(V(x, y0 + s.low, s.z0 + t)).Position,
				t,
				wood,
				M.WoodPlanks,
				grounds
			)
		end
		-- The roof: one slope of boards overhanging all round.
		local a = V((s.x0 + s.x1) / 2, y0 + slopeAt(s.z0 - 0.8), s.z0 - 0.8)
		local b = V((s.x0 + s.x1) / 2, y0 + slopeAt(s.z1 + 0.8), s.z1 + 0.8)
		local along = (b - a).Unit
		local n = V(0, along.Z, -along.Y)
		if n.Y < 0 then
			n = -n
		end
		beam(
			s.name .. "Roof",
			a + n * 0.2,
			b + n * 0.2,
			s.x1 - s.x0 + 1.4,
			0.4,
			n,
			Kit.weathered(ROOF_IRON, 0.06),
			M.CorrodedMetal,
			place,
			grounds
		)
		if s.floor then
			part(
				s.name .. "Floor",
				V(s.x1 - s.x0, 0.3, s.z1 - s.z0),
				V((s.x0 + s.x1) / 2, y0 - 0.15, (s.z0 + s.z1) / 2),
				wood,
				M.WoodPlanks,
				grounds
			)
			for _, px in { s.x0 + 0.4, s.x1 - 0.4 } do
				for _, pz in { s.z0 + 0.4, s.z1 - 0.4 } do
					rod(
						s.name .. "Leg",
						V(px, GROUND - 0.6, pz),
						V(px, y0 - 0.3, pz),
						0.5,
						wood,
						M.Wood,
						grounds
					)
				end
			end
		end
		if door then
			return place(V(door.at, y0 + door.height / 2, s.z1 - t / 2))
				* CFrame.new(Vector3.zero, FRONT)
		end
		return nil
	end

	-- The outhouse: a door with a moon cut in it, a seat with a hole, the
	-- smell. A hiding place with the door shut.
	do
		local x0, z0 = -54, 8
		local frame = shed({
			name = "Outhouse",
			x0 = x0,
			x1 = x0 + 5.2,
			z0 = z0,
			z1 = z0 + 5.4,
			low = 7.4,
			high = 8.6,
			door = { at = x0 + 2.6, width = 3.4, height = 7.2 },
		})
		if frame then
			local door = Kit.door(frame, 3.4, 7.2, {
				parent = doors,
				hinge = -1,
				swing = 1,
				thickness = 0.3,
				color = Kit.weathered(rgb(64, 54, 44), 0.05),
				panel = TIMBER,
				style = "plank",
				gap = 0.1,
				name = "OuthouseDoor",
			})
			local leaf = door:FindFirstChild("Leaf") :: BasePart?
			if leaf then
				local face = leaf.CFrame
					* CFrame.new(0, 2.4, -(leaf.Size.Z / 2 + 0.02))
					* CFrame.Angles(math.pi / 2, 0, 0)
				fine(Kit.disc("Moon", face, 0.9, 0.04, rgb(14, 12, 10), M.SmoothPlastic, door))
				fine(
					Kit.disc(
						"Moon",
						face * CFrame.new(0.28, -0.01, -0.06),
						0.8,
						0.05,
						leaf.Color,
						M.Wood,
						door
					)
				)
			end
		end
		local seat =
			Furnish.begin("OuthouseSeat", spot(x0 + 2.6, GROUND, z0 + 0.4, FRONT), furniture)
		seat.box("SeatBox", V(4.4, 2.4, 1.3), V(0, 1.2, -0.65), rgb(58, 48, 40), M.WoodPlanks)
		fine(seat.disc("SeatHole", V(0, 2.42, -0.6), 0.9, 0.04, rgb(12, 10, 8), M.SmoothPlastic))
		local inside = Instance.new("Folder")
		inside.Name = "OuthouseInside"
		inside.Parent = furniture
		hide(
			Kit.hideVolume(
				"OuthouseHidingVolume",
				place(V(x0 + 2.6, GROUND + 3.2, z0 + 3.4)),
				V(3.8, 6, 2.6),
				"Cupboard",
				1,
				inside
			)
		)
	end

	-- The tool shed: a bench under the window, a cupboard to hide in, tools
	-- hung on the walls, a grindstone.
	do
		local x0, z0 = -44, -6
		local frame = shed({
			name = "ToolShed",
			x0 = x0,
			x1 = x0 + 12,
			z0 = z0,
			z1 = z0 + 10,
			low = 8,
			high = 9.4,
			door = { at = x0 + 7.0, width = 3.6, height = 7.6 },
		})
		if frame then
			Kit.door(frame, 3.6, 7.6, {
				parent = doors,
				hinge = 1,
				swing = 1,
				thickness = 0.35,
				color = Kit.weathered(rgb(64, 54, 44), 0.05),
				panel = TIMBER,
				style = "plank",
				gap = 0.1,
				name = "ToolShedDoor",
			})
		end
		local bench = Furnish.workbench(spot(x0 + 7.4, GROUND, z0 + 0.4, FRONT), furniture)
		Furnish.backTo(bench, 0.3)
		local press, pressSpot = Furnish.wardrobe(
			spot(x0 + 0.4, GROUND, z0 + 6.6, RIGHT),
			furniture,
			{ name = "ToolCupboard", wood = TIMBER, width = 5.4, height = 7.2 }
		)
		Furnish.backTo(press, 0.3)
		hide(pressSpot)
		-- A scythe and a saw on the right-hand wall.
		local b = Furnish.begin("HungTools", spot(x0 + 11.6, GROUND, z0 + 6.2, LEFT), furniture)
		fine(b.rod("ScytheSnath", V(-0.8, 2.4, 0.1), V(0.4, 7.8, 0.1), 0.2, TIMBER, M.Wood))
		local prev = V(0.4, 7.8, 0.12)
		for k = 1, 5 do
			local a = k / 5 * 1.3
			local p = V(0.4 - 2.6 * math.sin(a), 7.8 - 0.9 * (1 - math.cos(a)), 0.12)
			fine(b.rod("ScytheBlade", prev, p, 0.1, C.RUST, M.CorrodedMetal))
			prev = p
		end
		fine(b.box("Saw", V(0.9, 2.6, 0.05), V(1.4, 4.6, 0.08), C.RUST, M.CorrodedMetal))
		Furnish.backTo(b.model, 0.05)
		local stone =
			Furnish.begin("Grindstone", spot(x0 + 10.2, GROUND, z0 + 8.2, RIGHT), furniture)
		for _, sx in { -1, 1 } do
			fine(
				stone.rod(
					"GrindLeg",
					V(sx * 0.7, 0, -0.8),
					V(sx * 0.7, 2.4, 0),
					0.3,
					TIMBER,
					M.Wood
				)
			)
			fine(
				stone.rod("GrindLeg", V(sx * 0.7, 0, 0.8), V(sx * 0.7, 2.4, 0), 0.3, TIMBER, M.Wood)
			)
		end
		stone.disc(
			"Grindstone",
			V(0, 2.6, 0),
			2.4,
			0.5,
			rgb(78, 74, 66),
			M.Sandstone,
			CFrame.Angles(0, 0, math.pi / 2)
		)
		fine(stone.rod("GrindCrank", V(0.9, 2.6, 0), V(1.2, 2.0, 0.2), 0.14, C.IRON, M.Metal))
	end

	-- The hen house, on legs with its ramp. The hens are gone.
	do
		local x0, z0 = -46, 56
		shed({
			name = "Coop",
			x0 = x0,
			x1 = x0 + 8,
			z0 = z0,
			z1 = z0 + 5.4,
			low = 3.4,
			high = 4.4,
			floor = GROUND + 2.4,
			hole = { at = x0 + 5.6, width = 1.3, sill = 0, head = 1.6 },
		})
		local foot, lip = V(x0 + 5.6, GROUND, z0 + 9.2), V(x0 + 5.6, GROUND + 2.4, z0 + 5.4)
		beam(
			"CoopRamp",
			foot + V(0, 0.1, 0),
			lip + V(0, -0.05, 0.3),
			1.4,
			0.2,
			V(0, 1, 0),
			TIMBER,
			M.WoodPlanks,
			place,
			grounds
		)
		for k = 1, 6 do
			local p = foot:Lerp(lip, k / 7) + V(0, 0.2, 0)
			fine(
				rod("RampSlat", p + V(-0.6, 0, 0), p + V(0.6, 0, 0), 0.12, TIMBER, M.Wood, grounds)
			)
		end
		for i = 0, 5 do
			fine(
				part(
					"Feather",
					V(0.35, 0.03, 0.12),
					V(x0 + 2 + i * 1.1, GROUND + 0.03, z0 + 7.5 + (i % 3) * 0.8),
					rgb(38, 34, 30),
					M.Fabric,
					dressing
				)
			)
		end
	end

	--------------------------------------------------------------------------
	-- The fence and its gates
	--------------------------------------------------------------------------

	local function run(a: Vector3, b: Vector3): (CFrame, number)
		local d = b - a
		return oriented(place, a, d, Vector3.yAxis), d.Magnitude
	end
	local function fence(x0: number, z0: number, x1: number, z1: number)
		local at, len = run(V(x0, GROUND, z0), V(x1, GROUND, z1))
		Yard.fence(at, len, grounds)
	end
	local function gatePost(x: number, z: number)
		rod(
			"GatePost",
			V(x, GROUND - 0.8, z),
			V(x, GROUND + 5.2, z),
			0.9,
			Kit.weathered(TIMBER, 0.06),
			M.Wood,
			grounds
		)
	end
	local GATE = 6
	-- The front, onto the lane: a pair of field gates.
	for _, sx in { -1, 1 } do
		gatePost(sx * (GATE + 0.3), FENCE_Z1)
		fence(sx * (GATE + 0.3), FENCE_Z1, sx * FENCE_X, FENCE_Z1)
		fence(sx * FENCE_X, FENCE_Z1, sx * FENCE_X, FENCE_Z0)
		local frame = spot(sx * GATE / 2, GROUND + 0.3 + 2.1, FENCE_Z1, BACK)
		local right = BACK:Cross(Vector3.yAxis)
		Yard.barGate(
			frame,
			GATE,
			4.2,
			doors,
			{ hinge = if right:Dot(V(sx, 0, 0)) >= 0 then 1 else -1, name = "FieldGate" }
		)
	end
	Yard.cowSkull(spot(-(GATE + 0.3), GROUND + 5.2, FENCE_Z1, FRONT), farmyard)
	-- The back, out to the corn: one gate behind the barn.
	local BACK_GATE_X = -4
	gatePost(BACK_GATE_X - GATE / 2 - 0.3, FENCE_Z0)
	gatePost(BACK_GATE_X + GATE / 2 + 0.3, FENCE_Z0)
	fence(-FENCE_X, FENCE_Z0, BACK_GATE_X - GATE / 2 - 0.3, FENCE_Z0)
	fence(BACK_GATE_X + GATE / 2 + 0.3, FENCE_Z0, FENCE_X, FENCE_Z0)
	do
		local right = BACK:Cross(Vector3.yAxis)
		Yard.barGate(spot(BACK_GATE_X, GROUND + 0.3 + 2.1, FENCE_Z0, BACK), GATE, 4.2, doors, {
			hinge = if right:Dot(V(-1, 0, 0)) >= 0 then 1 else -1,
			name = "FieldGate",
		})
	end

	-- The track, from the gate up to the barn and out the back to the maze.
	local function track(x: number, z0: number, z1: number, w: number)
		local at, len = run(V(x, GROUND, z0), V(x, GROUND, z1))
		Yard.path(at, len, w, grounds, { style = "gravel", color = DIRT, material = M.Ground })
	end
	track(0, FENCE_Z1 + 3, BZ + 4.2, 10)
	track(BACK_GATE_X + 1, -BZ - 4.2, MAZE_Z1 + 0.8, 7)

	--------------------------------------------------------------------------
	-- The yard
	--------------------------------------------------------------------------

	Yard.well(place(V(-24, GROUND, 52)), farmyard)
	Yard.pumpTrough(spot(24, GROUND, 47, FRONT), farmyard)
	do
		local _, under =
			Yard.wagon(spot(-12, GROUND, 58, FRONT) * CFrame.Angles(0, math.rad(-24), 0), farmyard)
		hide(under)
	end
	Furnish.chopBlock(place(V(-32, GROUND, 22)), farmyard)
	Furnish.firewood(spot(-44, GROUND, 17.6, FRONT), farmyard, { width = 7, rows = 4 })
	for k, pos in { V(40, 0, 64), V(45.4, 0, 64.4), V(42.6, 5, 64.2) } do
		Yard.hayBale(
			spot(pos.X, GROUND + pos.Y, pos.Z, FRONT) * CFrame.Angles(0, (k - 2) * 0.1, 0),
			farmyard,
			{ round = true }
		)
	end
	for _, pos in { V(21.4, 0, 16.2), V(22.6, 0, 17.4), V(21.2, 0, 18.4) } do
		Yard.churn(place(V(pos.X, GROUND, pos.Z)), farmyard)
	end
	Furnish.barrel(place(V(-21.5, GROUND, 33)), farmyard)
	Furnish.barrel(place(V(-23.8, GROUND, 34.2)), farmyard)
	Furnish.crate(spot(-21.6, GROUND, 37.4, FRONT) * CFrame.Angles(0, 0.2, 0), farmyard)
	-- Something was dragged out of the back doors and off into the corn.
	Decor.smear(
		place(V(-2, GROUND + 0.2, -BZ - 4.5)).Position,
		place(V(-3.6, GROUND + 0.2, MAZE_Z1 + 2)).Position,
		dressing,
		1.3,
		C.BLOOD_OLD
	)

	--------------------------------------------------------------------------
	-- The maze
	--------------------------------------------------------------------------

	-- A square of dead corn behind the barn, cut into a maze: cells carved by
	-- a seeded walk so there is exactly one way between any two of them,
	-- then the four in the middle opened into a clearing where the
	-- scarecrow stands. One way in from the barn, one from the field.
	do
		local rng = Random.new(1861)
		local east: { { boolean } } = {} -- east[i][j]: the wall between cell (i, j) and (i + 1, j)
		local south: { { boolean } } = {} -- south[i][j]: between (i, j) and (i, j + 1)
		local seen: { { boolean } } = {}
		for i = 1, CELLS do
			east[i], south[i], seen[i] = {}, {}, {}
			for j = 1, CELLS do
				east[i][j], south[i][j], seen[i][j] = true, true, false
			end
		end
		local stack: { { number } } = { { 1, 1 } }
		seen[1][1] = true
		while #stack > 0 do
			local cur = stack[#stack]
			local i, j = cur[1], cur[2]
			local options: { { number } } = {}
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local ni, nj = i + d[1], j + d[2]
				if ni >= 1 and ni <= CELLS and nj >= 1 and nj <= CELLS and not seen[ni][nj] then
					table.insert(options, { ni, nj })
				end
			end
			if #options == 0 then
				table.remove(stack)
			else
				local pick = options[rng:NextInteger(1, #options)]
				local ni, nj = pick[1], pick[2]
				if ni ~= i then
					east[math.min(i, ni)][j] = false
				else
					south[i][math.min(j, nj)] = false
				end
				seen[ni][nj] = true
				table.insert(stack, pick)
			end
		end
		local mid = CELLS // 2
		east[mid][mid], east[mid][mid + 1] = false, false
		south[mid][mid], south[mid + 1][mid] = false, false

		local ENTRY_COL, SIDE_ROW = 4, 6
		local function cellX(i: number): number
			return MAZE_X0 + (i - 1) * CELL
		end
		local function cellZ(j: number): number
			return MAZE_Z1 - (j - 1) * CELL
		end
		local rows = 0
		local function corn(x0: number, z0: number, x1: number, z1: number)
			rows += 1
			local at, len = run(V(x0, GROUND, z0), V(x1, GROUND, z1))
			Yard.cornRow(at, len, grounds, { seed = rows })
		end
		for i = 1, CELLS do
			for j = 1, CELLS do
				if i < CELLS and east[i][j] then
					corn(cellX(i + 1), cellZ(j), cellX(i + 1), cellZ(j + 1))
				end
				if j < CELLS and south[i][j] then
					corn(cellX(i), cellZ(j + 1), cellX(i + 1), cellZ(j + 1))
				end
			end
		end
		for i = 1, CELLS do
			if i ~= ENTRY_COL then
				corn(cellX(i), cellZ(1), cellX(i + 1), cellZ(1))
			end
			corn(cellX(i), cellZ(CELLS + 1), cellX(i + 1), cellZ(CELLS + 1))
		end
		for j = 1, CELLS do
			if j ~= SIDE_ROW then
				corn(cellX(1), cellZ(j), cellX(1), cellZ(j + 1))
			end
			corn(cellX(CELLS + 1), cellZ(j), cellX(CELLS + 1), cellZ(j + 1))
		end
		-- The ground between the rows, trodden bare.
		local size = CELL * CELLS
		part(
			"Path",
			V(size + 2, 0.3, size + 2),
			V(MAZE_X0 + size / 2, GROUND + 0.02, MAZE_Z1 - size / 2),
			DIRT,
			M.Ground,
			grounds
		)
		-- The clearing: the scarecrow, and the crows on its arms.
		local cx, cz = cellX(mid + 1), cellZ(mid + 1)
		Yard.scarecrow(spot(cx, GROUND, cz, FRONT), farmyard)
		for _, sx in { -1, 1 } do
			Yard.crow(
				spot(cx + sx * 2.6, GROUND + 7.65, cz + 0.1, if sx < 0 then RIGHT else FRONT),
				farmyard
			)
		end
		Yard.crow(spot(cx + 1.8, GROUND, cz + 3.2, LEFT), farmyard, { peck = true })
		print(string.format("[Farm] a maze of %d cells in %d rows of corn", CELLS * CELLS, rows))
	end

	-- Crows about the place: on the barn's ridge, the fence, the windpump.
	for _, pos in { V(-0.1, RIDGE + 0.7, 8), V(0.1, RIDGE + 0.7, -16), V(0, RIDGE + 0.7, -3) } do
		Yard.crow(spot(pos.X, pos.Y, pos.Z, if pos.Z > 0 then LEFT else RIGHT), farmyard)
	end
	-- On two of the side fence's posts.
	local sideRun = FENCE_Z1 - FENCE_Z0
	local sideSpan = sideRun / math.ceil(sideRun / 8)
	for _, k in { 5, 9 } do
		Yard.crow(spot(FENCE_X, GROUND + 4.5, FENCE_Z1 - k * sideSpan, FRONT), farmyard)
	end
	Yard.crow(spot(PUMP_X + 1.2, GROUND + 30.13, PUMP_Z - 1.2, BACK), farmyard)

	model.Parent = parent

	print(string.format("[Farm] %d parts, %d hiding places", Kit.count(), #hidingSpots))

	return {
		model = model,
		entrance = CFrame.lookAt(
			place(V(0, GROUND + 3, FENCE_Z1 + 8)).Position,
			place(V(0, GROUND + 3, BZ)).Position
		),
		hidingSpots = hidingSpots,
		partCount = Kit.count(),
	}
end

return Farm
