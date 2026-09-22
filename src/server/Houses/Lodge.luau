--!strict
--[[
	House #3: a hunting lodge of whole logs, one storey, generated entirely in
	code.

	Everything is on the ground floor and there is a great deal of it. The
	middle of the house is a great room open to the roof: log trusses, log
	purlins, the underside of the boards, and a fieldstone chimney climbing
	the back wall the whole way up from a fireplace you could stand in. The
	rest is under flat ceilings: a bunk room, a kitchen, a bath and a store
	cupboard down one side; the master bedroom, a washroom, a gun cupboard
	and the trophy room down the other; a mud room and a workshop behind the
	chimney that nobody should go into.

	The walls are logs, round, stacked a course at a time with the corners
	overlapping the way notched logs do, so the house is curves inside and
	out. Every door opens (DoorController); the front door and the mud room's
	back door lead out. Almost every room can be left two ways.

	Built from HouseKit, Furnish and Decor. Local space runs +X right, +Y up,
	+Z out of the front door, with Y = 0 the floor; the ground is FOUND_H
	below that and the pivot sits on it.
]]

local Kit = require(script.Parent.HouseKit)
local Furnish = require(script.Parent.Furnish)
local Decor = require(script.Parent.Decor)

type Place = Kit.Place
type Opening = Kit.Opening
type Hole = Kit.Hole
type Room = Kit.Room
type Finish = Kit.Finish
type HidingSpot = Kit.HidingSpot

local C = Kit.C
local M = Enum.Material
local V = Vector3.new
local EPS = Kit.EPS
local rgb = Kit.rgb

local Lodge = {}

----------------------------------------------------------------------------
-- Dimensions
----------------------------------------------------------------------------

local FOUND_H = 3
local L1 = 0
local GROUND = -FOUND_H

-- 88 by 56 across the logs' outer faces.
local HALF_W = 44
local HALF_D = 28
local LOG_D = 1.4 -- a log's diameter, and so the outside walls' thickness
local WALL_X = HALF_W - LOG_D / 2
local WALL_Z = HALF_D - LOG_D / 2
local IN_X = HALF_W - LOG_D
local IN_Z = HALF_D - LOG_D
local COURSE = 1.3 -- a little under a diameter, so no light shows between
local COURSES = 11
local FIRST_LOG = L1 + LOG_D / 2
local WALL_TOP = FIRST_LOG + (COURSES - 1) * COURSE + LOG_D / 2 -- 14.35
local CEIL = 12 -- flat ceilings over everything but the great room
local CEIL_T = 0.6
local PART_T = 0.8

-- The plan.
local GREAT_X = 16 -- the great room lies between x = +/- this
local GREAT_Z0 = -8 -- ... and from here forward to the front wall
local MID_Z0, MID_Z1 = 0, 8 -- the middle band down each side
local SPLIT_X = 28 -- where each middle band is divided

-- The roof: a steep gable over the whole house, ridge along X.
local PITCH = math.rad(40)
local FALL = math.tan(PITCH)
local EAVE = 4
local GABLE_OUT = 4
local ROOF_T = 1.0
local RIDGE = WALL_TOP + HALF_D * FALL -- the rafter line at the ridge
local ROOF_RUN = HALF_D + EAVE
-- The underside of the roof boards: where walls stop under the roof.
local UNDER = (ROOF_T + 0.2) / math.cos(PITCH)
local function roofUnder(z: number): number
	return RIDGE - FALL * math.abs(z) - UNDER
end

-- The great chimney, straddling the great room's back wall.
local CHIMNEY_W = 12
local CHIMNEY_D = 8
local CHIMNEY_Z0, CHIMNEY_Z1 = GREAT_Z0 - CHIMNEY_D / 2, GREAT_Z0 + CHIMNEY_D / 2
local FIRE_W, FIRE_H, FIRE_DEPTH = 7, 6, 3
local STACK_TOP = RIDGE + 5
-- The master bedroom's chimney, on the east gable.
local EAST_Z = 17
local EAST_W, EAST_D = 7, 7

-- The porch: along the front, under a low roof of its own tucked beneath
-- the main roof's eave.
local PORCH_X = 30
local PORCH_D = 10
local PORCH_Z = HALF_D + PORCH_D
local PORCH_HIGH = 10.2

local DOOR_W = 5.5
local DOOR_H = 8.5
local IN_DOOR_W = 4.5
local IN_DOOR_H = 8.5
local BACK_DOOR_X = -8

-- The louvred vent high in each gable.
local VENT_SILL = RIDGE - 13
local VENT_H = 3.2
local VENT_W = 3

-- Window lines: heads under the porch roof where it meets the wall.
local SILL = L1 + 3
local WIN_H = 6.2
local HIGH_SILL = L1 + 4.3 -- above worktops and benches

local LOG = rgb(62, 46, 34)
local LOG_END = rgb(86, 68, 50)
local CHINK = rgb(46, 40, 34)
local STONE = rgb(62, 56, 50)
local STONE_DARK = rgb(50, 46, 42)
local ROOF = rgb(48, 40, 34)
local PANEL = rgb(66, 50, 38)
local BOARD = rgb(56, 44, 34)

----------------------------------------------------------------------------
-- Rooms
----------------------------------------------------------------------------

-- Board walls inside: planks for "paper", a rounded rail and a skirting.
local function boards(wainscot: number, colour: Color3?): Finish
	return {
		paper = colour or PANEL,
		paperMaterial = M.WoodPlanks,
		wainscot = wainscot,
		rail = C.RAIL,
		skirting = C.RAIL,
	}
end
local F_GREAT = boards(4.2, rgb(70, 52, 38))
local F_ROOM = boards(3.6)
local F_DARK = boards(3.6, rgb(58, 44, 34))
local F_BATH: Finish = {
	paper = rgb(64, 52, 42),
	paperMaterial = M.WoodPlanks,
	wainscot = 4.2,
	rail = C.RAIL,
	dado = C.TILE_DARK,
	dadoMaterial = M.CeramicTiles,
}

local ROOMS: { Room } = {
	{
		name = "Great",
		level = L1,
		height = 40,
		x0 = -GREAT_X,
		x1 = GREAT_X,
		z0 = GREAT_Z0,
		z1 = HALF_D,
		finish = F_GREAT,
	},
	{
		name = "Bunk",
		level = L1,
		height = CEIL,
		x0 = -HALF_W,
		x1 = -GREAT_X,
		z0 = MID_Z1,
		z1 = HALF_D,
		finish = F_ROOM,
	},
	{
		name = "Bath",
		level = L1,
		height = CEIL,
		x0 = -HALF_W,
		x1 = -SPLIT_X,
		z0 = MID_Z0,
		z1 = MID_Z1,
		finish = F_BATH,
	},
	{
		name = "Store",
		level = L1,
		height = CEIL,
		x0 = -SPLIT_X,
		x1 = -GREAT_X,
		z0 = MID_Z0,
		z1 = MID_Z1,
	},
	{
		name = "Kitchen",
		level = L1,
		height = CEIL,
		x0 = -HALF_W,
		x1 = -GREAT_X,
		z0 = -HALF_D,
		z1 = MID_Z0,
		finish = F_ROOM,
	},
	{
		name = "Master",
		level = L1,
		height = CEIL,
		x0 = GREAT_X,
		x1 = HALF_W,
		z0 = MID_Z1,
		z1 = HALF_D,
		finish = F_ROOM,
	},
	{
		name = "Washroom",
		level = L1,
		height = CEIL,
		x0 = GREAT_X,
		x1 = SPLIT_X,
		z0 = MID_Z0,
		z1 = MID_Z1,
		finish = F_BATH,
	},
	{
		name = "GunCupboard",
		level = L1,
		height = CEIL,
		x0 = SPLIT_X,
		x1 = HALF_W,
		z0 = MID_Z0,
		z1 = MID_Z1,
	},
	{
		name = "Trophy",
		level = L1,
		height = CEIL,
		x0 = GREAT_X,
		x1 = HALF_W,
		z0 = -HALF_D,
		z1 = MID_Z0,
		finish = F_DARK,
	},
	{
		name = "MudRoom",
		level = L1,
		height = CEIL,
		x0 = -GREAT_X,
		x1 = 0,
		z0 = -HALF_D,
		z1 = GREAT_Z0,
		finish = F_DARK,
	},
	{
		name = "Workshop",
		level = L1,
		height = CEIL,
		x0 = 0,
		x1 = GREAT_X,
		z0 = -HALF_D,
		z1 = GREAT_Z0,
		finish = F_DARK,
	},
}

Lodge.FOOTPRINT = {
	x0 = -HALF_W - GABLE_OUT - 2,
	x1 = HALF_W + GABLE_OUT + 2,
	z0 = -HALF_D - 10,
	z1 = PORCH_Z + 6,
}

-- Whether a world position is on the footprint of a lodge built at `pivot`.
function Lodge.footprintContains(pivot: CFrame, position: Vector3): boolean
	local rel = (pivot * CFrame.Angles(0, math.pi, 0)):PointToObjectSpace(position)
	local f = Lodge.FOOTPRINT
	return rel.X > f.x0 and rel.X < f.x1 and rel.Z > f.z0 and rel.Z < f.z1
end

----------------------------------------------------------------------------
-- Log walls
----------------------------------------------------------------------------

type Window = {
	at: number,
	sill: number,
	width: number,
	height: number,
	style: string, -- "window" | "doorway" | "vent"
	shutters: boolean?,
}

local function win(
	at: number,
	sill: number,
	width: number,
	height: number,
	shutters: boolean?
): Window
	return {
		at = at,
		sill = sill,
		width = width,
		height = height,
		style = "window",
		shutters = shutters,
	}
end

local function doorway(at: number, width: number, height: number): Window
	return { at = at, sill = L1, width = width, height = height, style = "doorway" }
end

--[[
	A log wall: a core of dark chinking pierced for its openings, and a
	round log on it every course, cut where an opening interrupts it. Logs
	run on past each end by `over` (the notched corners), and a course can be
	lifted half a course (`half`) so the logs of two walls meeting at a corner
	interleave. Where a log's end shows, it gets a disc of paler end grain.
	`topY` stops the courses; `clip`, if given, shortens each course to the
	roof above it (the gables).
]]
local function logWall(
	label: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	outward: number,
	windows: { Window },
	half: boolean,
	topY: number,
	over: number,
	place: Place,
	parent: Instance,
	clip: ((number) -> number)?
)
	local openings: { Opening } = {}
	for _, w in windows do
		table.insert(
			openings,
			{ at = w.at, width = w.width, sill = w.sill, head = w.sill + w.height }
		)
	end
	Kit.wall({
		name = "Chinking" .. label,
		axis = axis,
		fixed = fixed,
		from = from,
		to = to,
		bottom = L1,
		top = math.min(topY, WALL_TOP - 0.2),
		thickness = 0.7,
		openings = openings,
		color = CHINK,
		material = M.Concrete,
		place = place,
		parent = parent,
		outward = outward,
	})
	local function at(along: number, y: number): Vector3
		if axis == "X" then
			return V(along, y, fixed)
		end
		return V(fixed, y, along)
	end
	local y = FIRST_LOG + (if half then COURSE / 2 else 0)
	while y <= topY - LOG_D / 2 + 0.01 do
		local lo, hi = from - over, to + over
		local capped = false
		if clip then
			local reach = clip(y)
			if reach < 0.8 then
				break
			end
			if reach < math.max(-lo, hi) then
				lo, hi = math.max(lo, -reach), math.min(hi, reach)
				capped = true
			end
		end
		-- Cut the course wherever an opening takes more than a sliver of it.
		local cuts: { { number } } = {}
		for _, o in openings do
			local overlap = math.min(y + LOG_D / 2, o.head) - math.max(y - LOG_D / 2, o.sill)
			if overlap > 0.15 then
				table.insert(cuts, { o.at - o.width / 2, o.at + o.width / 2 })
			end
		end
		table.sort(cuts, function(p: { number }, q: { number }): boolean
			return p[1] < q[1]
		end)
		local cursor = lo
		local function segment(a: number, b: number)
			if b - a < 0.3 then
				return
			end
			Kit.rod(
				"Log",
				place(at(a, y)).Position,
				place(at(b, y)).Position,
				LOG_D,
				Kit.weathered(LOG, 0.1),
				M.Wood,
				parent
			)
		end
		for _, c in cuts do
			segment(cursor, c[1])
			cursor = math.max(cursor, c[2])
		end
		segment(cursor, hi)
		-- End grain where a log runs out past a corner.
		if over > 0 and not capped then
			for _, e in { lo, hi } do
				local frame = CFrame.new(place(at(e, y)).Position)
					* (
						place(Vector3.zero).Rotation
						* (
							if axis == "X"
								then CFrame.Angles(0, 0, math.pi / 2)
								else CFrame.Angles(math.pi / 2, 0, 0)
						)
					)
				Kit.detail(Kit.disc("LogEnd", frame, LOG_D - 0.12, 0.06, LOG_END, M.Wood, parent))
			end
		end
		y += COURSE
	end

	for _, w in windows do
		if w.style == "doorway" or w.style == "vent" then
			continue
		end
		local look = if axis == "X" then V(0, 0, outward) else V(outward, 0, 0)
		local centre = at(w.at, w.sill + w.height / 2)
		local frame = place(centre) * CFrame.new(Vector3.zero, look)
		Kit.window(frame, w.width, w.height, { thickness = LOG_D, parent = parent })
		if w.shutters then
			-- Board shutters either side, one hanging off its top hinge.
			for _, side in { -1, 1 } do
				local sw = w.width / 2 + 0.2
				local off = CFrame.new(side * (w.width / 2 + 0.45 + sw / 2), 0, -(LOG_D / 2 + 0.45))
				local tilt = if side > 0 then CFrame.Angles(0, 0, math.rad(-9)) else CFrame.identity
				Kit.part(
					"Shutter",
					V(sw, w.height, 0.2),
					frame * off * tilt,
					Kit.weathered(BOARD, 0.1),
					M.WoodPlanks,
					parent
				)
				Kit.detail(
					Kit.part(
						"ShutterBatten",
						V(sw - 0.2, 0.4, 0.12),
						frame * off * tilt * CFrame.new(0, w.height * 0.3, -0.16),
						BOARD,
						M.Wood,
						parent
					)
				)
				Kit.detail(
					Kit.part(
						"ShutterBatten",
						V(sw - 0.2, 0.4, 0.12),
						frame * off * tilt * CFrame.new(0, -w.height * 0.3, -0.16),
						BOARD,
						M.Wood,
						parent
					)
				)
			end
		end
	end
end

----------------------------------------------------------------------------
-- The roof
----------------------------------------------------------------------------

local function slope(side: number): (Vector3, CFrame)
	local normal = V(0, math.cos(PITCH), side * math.sin(PITCH))
	return normal, CFrame.Angles(side * PITCH, 0, 0)
end

--[[
	Both slopes, boarded underneath, with purlins of whole logs running the
	length of the house and out through both gables, a ridge log, rafter
	tails under the eaves, fly rafters along the gable edges. Where a
	chimney comes up through, the purlins stop short of it.
]]
local function roof(place: Place, parent: Instance)
	local x0, x1 = -HALF_W - GABLE_OUT, HALF_W + GABLE_OUT
	for _, side in { -1, 1 } do
		local normal, rot = slope(side)
		local length = ROOF_RUN / math.cos(PITCH)
		local mid = ROOF_RUN / 2
		local centre = V(0, RIDGE - FALL * mid, side * mid) - normal * (ROOF_T / 2)
		Kit.part(
			"RoofSlope",
			V(x1 - x0, ROOF_T, length),
			place(centre) * rot,
			Kit.weathered(ROOF, 0.05),
			M.RoofShingles,
			parent
		)
		Kit.detail(
			Kit.part(
				"RoofBoards",
				V(x1 - x0, 0.2, length),
				place(centre - normal * (ROOF_T / 2 + 0.1)) * rot,
				BOARD,
				M.WoodPlanks,
				parent
			)
		).CastShadow =
			true

		-- Purlins, cut round the chimneys.
		for _, z in { 8.5, 17, 25.6 } do
			local zz = side * z
			local y = RIDGE - FALL * z
			local p = V(0, y, zz) - normal * (ROOF_T + 0.2 + 0.6)
			local runs: { { number } } = { { x0 - 0.6, x1 + 0.6 } }
			if side < 0 and zz > CHIMNEY_Z0 - 0.6 and zz < CHIMNEY_Z1 + 0.6 then
				runs = { { x0 - 0.6, -CHIMNEY_W / 2 - 0.2 }, { CHIMNEY_W / 2 + 0.2, x1 + 0.6 } }
			elseif side > 0 and math.abs(zz - EAST_Z) < EAST_W / 2 + 0.6 then
				runs = { { x0 - 0.6, HALF_W - EAST_D / 2 - 0.2 } }
			end
			for _, r in runs do
				Kit.rod(
					"Purlin",
					place(V(r[1], p.Y, p.Z)).Position,
					place(V(r[2], p.Y, p.Z)).Position,
					1.2,
					Kit.weathered(LOG, 0.08),
					M.Wood,
					parent
				)
			end
		end
		-- Rafter tails under the eaves.
		for k = 0, 23 do
			local x = -46 + k * 4
			local a = V(x, 0, side * (HALF_D - 0.8))
			local b = V(x, 0, side * (ROOF_RUN - 0.3))
			local function under(p: Vector3): Vector3
				local y = RIDGE - FALL * math.abs(p.Z)
				return V(p.X, y, p.Z) - normal * (ROOF_T + 0.2 + 0.35)
			end
			Kit.rod(
				"RafterTail",
				place(under(a)).Position,
				place(under(b)).Position,
				0.7,
				Kit.weathered(LOG, 0.08),
				M.Wood,
				parent
			)
		end
		-- Fly rafters down the gable edges.
		for _, ex in { x0 + 0.4, x1 - 0.4 } do
			local top = V(ex, RIDGE, 0) - normal * (ROOF_T * 0.5)
			local bottom = V(ex, RIDGE - FALL * ROOF_RUN, side * ROOF_RUN) - normal * (ROOF_T * 0.5)
			Kit.rod(
				"FlyRafter",
				place(top).Position,
				place(bottom).Position,
				1.0,
				Kit.weathered(LOG, 0.08),
				M.Wood,
				parent
			)
		end
	end
	Kit.rod(
		"RidgeLog",
		place(V(x0 - 0.8, RIDGE - UNDER - 0.7, 0)).Position,
		place(V(x1 + 0.8, RIDGE - UNDER - 0.7, 0)).Position,
		1.6,
		Kit.weathered(LOG, 0.06),
		M.Wood,
		parent
	)
	Kit.part(
		"RidgeCap",
		V(x1 - x0 + 0.4, 0.8, 2.2),
		place(V(0, RIDGE + 0.1, 0)),
		ROOF,
		M.RoofShingles,
		parent
	)
end

--[[
	A gable end above the wall top: the chinking as a triangle and the log
	courses carried on up, each shorter than the one below, with a louvred
	vent in the middle.
]]
local function gable(place: Place, parent: Instance, side: number)
	local x = side * WALL_X
	Kit.triangle(
		"GableChinking",
		place(V(x, WALL_TOP - 0.2, -HALF_D)).Position,
		place(V(x, WALL_TOP - 0.2, HALF_D)).Position,
		place(V(x, RIDGE - UNDER, 0)).Position,
		0.7,
		CHINK,
		M.Concrete,
		parent
	)
	local ventSill, ventH, ventW = VENT_SILL, VENT_H, VENT_W
	-- The vent: a frame and slats, the chinking dark behind.
	local look = V(side, 0, 0)
	local frame = place(V(x, ventSill + ventH / 2, 0)) * CFrame.new(Vector3.zero, look)
	Kit.window(frame, ventW, ventH, { style = "open", thickness = LOG_D, parent = parent })
	for k = 0, 4 do
		Kit.detail(
			Kit.part(
				"Louvre",
				V(ventW, 0.12, 0.8),
				frame
					* CFrame.new(0, -ventH / 2 + 0.35 + k * 0.62, -0.2)
					* CFrame.Angles(math.rad(-35), 0, 0),
				BOARD,
				M.Wood,
				parent
			)
		)
	end
end

----------------------------------------------------------------------------
-- Stone chimneys
----------------------------------------------------------------------------

--[[
	The great chimney: a fieldstone mass on the great room's back wall with a
	fireplace a man could stand in, a raised hearth, a whole log for a mantel,
	and the stack going on up through the room and out of the roof.
]]
local function greatChimney(place: Place, parent: Instance)
	local hw = CHIMNEY_W / 2
	local z0, z1 = CHIMNEY_Z0, CHIMNEY_Z1
	local function stone(
		name: string,
		xa: number,
		xb: number,
		ya: number,
		yb: number,
		za: number,
		zb: number
	)
		if xb - xa <= EPS or yb - ya <= EPS or zb - za <= EPS then
			return
		end
		Kit.part(
			name,
			V(xb - xa, yb - ya, zb - za),
			place(V((xa + xb) / 2, (ya + yb) / 2, (za + zb) / 2)),
			Kit.weathered(STONE, 0.05),
			M.Cobblestone,
			parent
		)
	end
	local fw = FIRE_W / 2
	local back = z1 - FIRE_DEPTH
	stone("Chimney", -hw, hw, GROUND, L1, z0, z1)
	stone("ChimneyBack", -hw, hw, L1, L1 + FIRE_H + 1.4, z0, back)
	stone("ChimneyPier", -hw, -fw, L1, L1 + FIRE_H, back, z1)
	stone("ChimneyPier", fw, hw, L1, L1 + FIRE_H, back, z1)
	stone("ChimneyLintel", -hw, hw, L1 + FIRE_H, L1 + FIRE_H + 1.4, back, z1)
	-- The breast narrows a stud each side above the mantel, and again where
	-- it meets the roof.
	local y = L1 + FIRE_H + 1.4
	stone("Chimney", -hw + 1, hw - 1, y, roofUnder(z0) - 1, z0, z1 - 0.8)
	stone("Chimney", -hw + 1.8, hw - 1.8, roofUnder(z0) - 1, STACK_TOP, z0 + 0.6, z1 - 1.8)
	Kit.part(
		"ChimneyCap",
		V(CHIMNEY_W - 2.4, 0.8, CHIMNEY_D - 1.2),
		place(V(0, STACK_TOP + 0.4, (z0 + z1) / 2 - 0.6)),
		STONE_DARK,
		M.Slate,
		parent
	)
	Kit.detail(
		Kit.part(
			"Soot",
			V(FIRE_W, FIRE_H, 0.1),
			place(V(0, L1 + FIRE_H / 2, back + 0.05)),
			C.SOOT,
			M.Slate,
			parent
		)
	)
	-- The raised hearth: a stone step running out in front.
	Kit.part(
		"Hearth",
		V(CHIMNEY_W + 1, 0.8, 3),
		place(V(0, L1 + 0.4, z1 + 1.5)),
		STONE_DARK,
		M.Slate,
		parent
	)
	Kit.detail(
		Kit.part(
			"Firebed",
			V(FIRE_W - 0.4, 0.8, FIRE_DEPTH - 0.2),
			place(V(0, L1 + 0.4, back + FIRE_DEPTH / 2)),
			STONE_DARK,
			M.Slate,
			parent
		)
	)
	-- A whole log for a mantel.
	Kit.rod(
		"MantelLog",
		place(V(-hw - 0.4, L1 + FIRE_H + 1.9, z1 + 0.2)).Position,
		place(V(hw + 0.4, L1 + FIRE_H + 1.9, z1 + 0.2)).Position,
		1.1,
		rgb(70, 52, 38),
		M.Wood,
		parent
	)
	-- Andirons, a grate of charred logs, ashes.
	for _, u in { -fw + 0.9, fw - 0.9 } do
		local foot = place(V(u, L1 + 0.8, z1 - 0.4)).Position
		Kit.detail(Kit.rod("Andiron", foot, foot + V(0, 1.4, 0), 0.18, C.IRON, M.Metal, parent))
		Kit.detail(Kit.ball("AndironTop", foot + V(0, 1.5, 0), 0.36, C.IRON, M.Metal, parent))
		Kit.detail(
			Kit.rod(
				"AndironBar",
				foot + V(0, 0.5, 0),
				place(V(u, L1 + 1.3, back + 0.4)).Position,
				0.14,
				C.IRON,
				M.Metal,
				parent
			)
		)
	end
	Kit.detail(
		Kit.part(
			"Ashes",
			V(FIRE_W - 1, 0.08, FIRE_DEPTH - 0.6),
			place(V(0, L1 + 0.84, back + FIRE_DEPTH / 2)),
			rgb(40, 38, 36),
			M.Slate,
			parent
		)
	)
	for k, u in { -1.2, 0.9, 0 } do
		local a = place(V(u - 1.3, L1 + 1.1 + (k - 1) * 0.3, back + 1.0 + k * 0.2)).Position
		local b = place(V(u + 1.3, L1 + 1.1 + (k - 1) * 0.3, back + 1.6 - k * 0.2)).Position
		Kit.detail(Kit.rod("CharredLog", a, b, 0.6, rgb(30, 26, 24), M.Wood, parent))
	end
end

-- The master bedroom's chimney, straddling the east gable wall.
local function eastChimney(place: Place, parent: Instance)
	local hw, face = EAST_W / 2, EAST_D / 2
	local function stone(
		name: string,
		u0: number,
		u1: number,
		y0: number,
		y1: number,
		n0: number,
		n1: number
	)
		if u1 - u0 <= EPS or y1 - y0 <= EPS or n1 - n0 <= EPS then
			return
		end
		Kit.part(
			name,
			V(n1 - n0, y1 - y0, u1 - u0),
			place(V(HALF_W - (n0 + n1) / 2, (y0 + y1) / 2, EAST_Z + (u0 + u1) / 2)),
			Kit.weathered(STONE, 0.05),
			M.Cobblestone,
			parent
		)
	end
	local w, h, d = 3.8, 4.0, 2.0
	stone("Chimney", -hw, hw, GROUND, L1, -face, face)
	stone("ChimneyBack", -hw, hw, L1, L1 + h + 1.2, -face, face - d)
	stone("ChimneyPier", -hw, -w / 2, L1, L1 + h, face - d, face)
	stone("ChimneyPier", w / 2, hw, L1, L1 + h, face - d, face)
	stone("ChimneyLintel", -hw, hw, L1 + h, L1 + h + 1.2, face - d, face)
	local top = RIDGE - FALL * (EAST_Z - EAST_W / 2) + 3.5
	stone("Chimney", -hw, hw, L1 + h + 1.2, top, -face, face)
	Kit.part(
		"ChimneyCap",
		V(EAST_D + 1, 0.7, EAST_W + 1),
		place(V(HALF_W, top + 0.35, EAST_Z)),
		STONE_DARK,
		M.Slate,
		parent
	)
	Kit.detail(
		Kit.part(
			"Soot",
			V(0.1, h, w),
			place(V(HALF_W - (face - d) - 0.05, L1 + h / 2, EAST_Z)),
			C.SOOT,
			M.Slate,
			parent
		)
	)
	Kit.detail(
		Kit.part(
			"Hearth",
			V(d + 1.4, 0.2, w + 2),
			place(V(HALF_W - (face - d / 2 + 0.7), L1 + 0.1, EAST_Z)),
			C.SLATE,
			M.Slate,
			parent
		)
	)
	Kit.rod(
		"MantelLog",
		place(V(HALF_W - face - 0.3, L1 + h + 1.6, EAST_Z - hw - 0.3)).Position,
		place(V(HALF_W - face - 0.3, L1 + h + 1.6, EAST_Z + hw + 0.3)).Position,
		0.9,
		rgb(70, 52, 38),
		M.Wood,
		parent
	)
end

----------------------------------------------------------------------------
-- The porch and the back step
----------------------------------------------------------------------------

-- Rails of whole poles between two points on a deck: a top pole, a bottom
-- pole, and sticks between them.
local function logRail(name: string, a: Vector3, b: Vector3, place: Place, parent: Instance)
	local top, low = 3.4, 0.9
	Kit.rod(
		name .. "Rail",
		place(a + V(0, top, 0)).Position,
		place(b + V(0, top, 0)).Position,
		0.55,
		LOG,
		M.Wood,
		parent
	)
	Kit.rod(
		name .. "Rail",
		place(a + V(0, low, 0)).Position,
		place(b + V(0, low, 0)).Position,
		0.45,
		LOG,
		M.Wood,
		parent
	)
	local n = math.max(2, math.floor((b - a).Magnitude / 1.4))
	for k = 1, n - 1 do
		local p = a:Lerp(b, k / n)
		Kit.detail(
			Kit.rod(
				name .. "Stick",
				place(p + V(0, low, 0)).Position,
				place(p + V(0, top, 0)).Position,
				0.3,
				LOG,
				M.Wood,
				parent
			)
		)
	end
end

local function porch(place: Place, parent: Instance)
	Kit.part(
		"PorchFloor",
		V(PORCH_X * 2, 1, PORCH_D),
		place(V(0, L1 - 0.5, HALF_D + PORCH_D / 2)),
		C.FLOOR,
		M.WoodPlanks,
		parent
	)
	-- Stone piers under the posts, and posts of whole logs.
	local postZ = PORCH_Z - 1
	local posts = { -PORCH_X + 0.6, -17.5, -5, 5, 17.5, PORCH_X - 0.6 }
	local function roofY(z: number): number
		return PORCH_HIGH - (z - HALF_D) * 0.25
	end
	for _, x in posts do
		Kit.part(
			"Pier",
			V(2.2, FOUND_H, 2.2),
			place(V(x, GROUND + FOUND_H / 2 - 1, postZ)),
			STONE,
			M.Cobblestone,
			parent
		)
		Kit.rod(
			"Post",
			place(V(x, L1, postZ)).Position,
			place(V(x, roofY(postZ) - 0.9, postZ)).Position,
			1.0,
			LOG,
			M.Wood,
			parent
		)
	end
	Kit.part(
		"PorchSkirt",
		V(PORCH_X * 2, FOUND_H - 1, 0.4),
		place(V(0, GROUND + (FOUND_H - 1) / 2, PORCH_Z - 0.2)),
		BOARD,
		M.WoodPlanks,
		parent
	)
	-- Beam, ledger, rafters and the roof.
	Kit.rod(
		"PorchBeam",
		place(V(-PORCH_X - 0.8, roofY(postZ) - 0.4, postZ)).Position,
		place(V(PORCH_X + 0.8, roofY(postZ) - 0.4, postZ)).Position,
		0.9,
		LOG,
		M.Wood,
		parent
	)
	Kit.rod(
		"PorchLedger",
		place(V(-PORCH_X, PORCH_HIGH - 0.5, HALF_D + 0.5)).Position,
		place(V(PORCH_X, PORCH_HIGH - 0.5, HALF_D + 0.5)).Position,
		0.8,
		LOG,
		M.Wood,
		parent
	)
	for k = 0, 15 do
		local x = -PORCH_X + 1 + k * (PORCH_X * 2 - 2) / 15
		Kit.rod(
			"PorchRafter",
			place(V(x, roofY(HALF_D + 0.3) - 0.5, HALF_D + 0.3)).Position,
			place(V(x, roofY(PORCH_Z + 0.8) - 0.5, PORCH_Z + 0.8)).Position,
			0.5,
			LOG,
			M.Wood,
			parent
		)
	end
	local run = PORCH_D + 1.2
	local rise = run * 0.25
	local len = math.sqrt(run * run + rise * rise)
	local tilt = math.atan2(rise, run)
	local mid = V(0, PORCH_HIGH - rise / 2 + 0.05, HALF_D + run / 2)
	Kit.part(
		"PorchRoof",
		V(PORCH_X * 2 + 2, 0.6, len),
		place(mid) * CFrame.Angles(tilt, 0, 0),
		Kit.weathered(ROOF, 0.05),
		M.RoofShingles,
		parent
	)
	Kit.detail(
		Kit.part(
			"PorchBoards",
			V(PORCH_X * 2 + 2, 0.12, len),
			place(mid - V(0, 0.36, 0)) * CFrame.Angles(tilt, 0, 0),
			BOARD,
			M.WoodPlanks,
			parent
		)
	)
	-- Railings between the posts, open at the steps.
	local rz = postZ + 0.1
	logRail("Porch", V(-PORCH_X + 0.6, L1, rz), V(-5.5, L1, rz), place, parent)
	logRail("Porch", V(5.5, L1, rz), V(PORCH_X - 0.6, L1, rz), place, parent)
	for _, sx in { -1, 1 } do
		logRail(
			"Porch",
			V(sx * (PORCH_X - 0.6), L1, HALF_D + 0.8),
			V(sx * (PORCH_X - 0.6), L1, rz),
			place,
			parent
		)
	end
	Kit.staircase(
		"PorchStep",
		V(0, GROUND, PORCH_Z + 3.6),
		V(0, L1, PORCH_Z),
		8.4,
		3,
		place,
		parent,
		{ rails = {}, treadColor = C.FLOOR, railColor = LOG, rotten = 0 }
	)
end

local function backStep(place: Place, parent: Instance)
	local cx = BACK_DOOR_X
	Kit.part(
		"BackStepDeck",
		V(9, 1, 5),
		place(V(cx, L1 - 0.5, -HALF_D - 2.5)),
		C.FLOOR,
		M.WoodPlanks,
		parent
	)
	for _, sx in { -1, 1 } do
		Kit.part(
			"Pier",
			V(1.6, FOUND_H, 1.6),
			place(V(cx + sx * 3.8, GROUND + FOUND_H / 2 - 1, -HALF_D - 4.3)),
			STONE,
			M.Cobblestone,
			parent
		)
		logRail(
			"BackStep",
			V(cx + sx * 4.2, L1, -HALF_D - 0.6),
			V(cx + sx * 4.2, L1, -HALF_D - 4.6),
			place,
			parent
		)
	end
	Kit.staircase(
		"BackStepStair",
		V(cx, GROUND, -HALF_D - 5 - 3.6),
		V(cx, L1, -HALF_D - 5),
		6,
		3,
		place,
		parent,
		{ rails = {}, treadColor = C.FLOOR, railColor = LOG, rotten = 0 }
	)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

--[[
	Build the lodge. `pivot` is where the ground meets the middle of the
	footprint, and the house faces along the pivot's LookVector.
]]
function Lodge.build(pivot: CFrame, parent: Instance): Kit.Built
	Kit.reset(7703)
	local place = Kit.placer(pivot, FOUND_H)

	local model = Instance.new("Model")
	model.Name = "Lodge"
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

	local function hang(
		axis: string,
		fixed: number,
		along: number,
		w: number,
		h: number,
		into: Vector3,
		hingeToward: Vector3,
		thickness: number,
		o: { [string]: any }?
	): Model
		local centre = if axis == "X"
			then V(along, L1 + h / 2, fixed)
			else V(fixed, L1 + h / 2, along)
		local frame = place(centre) * CFrame.new(Vector3.zero, into)
		local right = into:Cross(Vector3.yAxis)
		local hinge = if right:Dot(hingeToward) >= 0 then 1 else -1
		local opts: { [string]: any } = o or {}
		Kit.window(frame, w, h, {
			style = "open",
			thickness = thickness,
			parent = if opts.outside then shell else interior,
			color = opts.casing or C.CASING,
		})
		return Kit.door(frame, w, h, {
			parent = doors,
			hinge = hinge,
			swing = 1,
			gap = opts.gap,
			color = opts.color or C.DOOR,
			panel = opts.panel or C.DOOR_PANEL,
			style = opts.style or "plank",
			thickness = opts.leaf,
			startAngle = opts.ajar,
			name = opts.name,
		})
	end

	--------------------------------------------------------------------------
	-- Base, floor, ceilings
	--------------------------------------------------------------------------

	for i, out in { 0.8, 0.4 } do
		local bottom = GROUND + (i - 1) * FOUND_H / 2 - 0.05
		local top = math.min(GROUND + i * FOUND_H / 2, L1 - 0.3)
		Kit.part(
			"Footing",
			V(HALF_W * 2 + out * 2, top - bottom, HALF_D * 2 + out * 2),
			place(V(0, (top + bottom) / 2, 0)),
			Kit.weathered(if i == 1 then STONE_DARK else STONE, 0.05),
			M.Cobblestone,
			shell
		)
	end
	Kit.slabWithHoles(
		"Floor",
		L1,
		1,
		-HALF_W,
		HALF_W,
		-HALF_D,
		HALF_D,
		{},
		C.FLOOR,
		M.WoodPlanks,
		place,
		interior
	)
	-- Flat ceilings everywhere but the great room, with a hole where the
	-- chimney's back half stands in the mud room and workshop.
	local wingX0, wingX1 = GREAT_X + PART_T / 2, IN_X
	for _, side in { -1, 1 } do
		Kit.part(
			"Ceiling",
			V(wingX1 - wingX0, CEIL_T, IN_Z * 2),
			place(V(side * (wingX0 + wingX1) / 2, CEIL + CEIL_T / 2, 0)),
			C.FLOOR,
			M.WoodPlanks,
			interior
		)
	end
	Kit.slabWithHoles(
		"Ceiling",
		CEIL + CEIL_T,
		CEIL_T,
		-GREAT_X + PART_T / 2,
		GREAT_X - PART_T / 2,
		-IN_Z,
		GREAT_Z0 - PART_T / 2,
		{ { x0 = -CHIMNEY_W / 2, x1 = CHIMNEY_W / 2, z0 = CHIMNEY_Z0, z1 = GREAT_Z0 } },
		C.FLOOR,
		M.WoodPlanks,
		place,
		interior
	)

	--------------------------------------------------------------------------
	-- Outside walls
	--------------------------------------------------------------------------

	logWall("Front", "X", WALL_Z, -HALF_W, HALF_W, 1, {
		win(-36, SILL, 5, WIN_H, true),
		win(-24, SILL, 5, WIN_H),
		win(-9, SILL, 5, WIN_H),
		doorway(0, DOOR_W, DOOR_H),
		win(9, SILL, 5, WIN_H),
		win(24, SILL, 5, WIN_H),
		win(36, SILL, 5, WIN_H, true),
	}, false, WALL_TOP, 1.2, place, shell)
	logWall("Back", "X", -WALL_Z, -HALF_W, HALF_W, -1, {
		win(-36, HIGH_SILL, 5, WIN_H - 1.3),
		win(-24, HIGH_SILL, 4, WIN_H - 1.3),
		doorway(BACK_DOOR_X, IN_DOOR_W, IN_DOOR_H),
		win(-2.8, L1 + 5.6, 2.4, 3),
		win(8, HIGH_SILL, 5, WIN_H - 1.3),
		win(24, SILL, 5, WIN_H, true),
		win(36, SILL, 5, WIN_H),
	}, false, WALL_TOP, 1.2, place, shell)
	local vent: Window =
		{ at = 0, sill = VENT_SILL, width = VENT_W, height = VENT_H, style = "vent" }
	local function underRoof(y: number): number
		-- Up to the wall top a course runs its full length past the corners;
		-- above it, it stops under the roof.
		if y + LOG_D / 2 <= WALL_TOP + 0.4 then
			return math.huge
		end
		return (RIDGE - UNDER - (y + LOG_D / 2)) / FALL
	end
	logWall("West", "Z", -WALL_X, -HALF_D, HALF_D, -1, {
		win(17, SILL, 4, WIN_H, true),
		win(4, L1 + 6, 2.4, 3),
		win(-7, HIGH_SILL, 5, WIN_H - 1.3),
		win(-21, HIGH_SILL, 4, WIN_H - 1.3),
		vent,
	}, true, RIDGE - UNDER, 1.2, place, shell, underRoof)
	logWall("East", "Z", WALL_X, -HALF_D, HALF_D, 1, {
		win(23.6, SILL, 4, WIN_H),
		win(11, SILL, 3, WIN_H),
		win(4, L1 + 6, 2.4, 3),
		win(-8, SILL, 5, WIN_H, true),
		win(-20, SILL, 5, WIN_H),
		vent,
	}, true, RIDGE - UNDER, 1.2, place, shell, underRoof)
	-- A heavier sill log round the base, on the stone, broken where a door
	-- stands in the wall: a threshold nobody trips over.
	for _, side in { -1, 1 } do
		local doorX = if side > 0 then 0 else BACK_DOOR_X
		local doorW = if side > 0 then DOOR_W else IN_DOOR_W
		for _, r in
			{
				{ -HALF_W - 0.6, doorX - doorW / 2 - 0.5 },
				{ doorX + doorW / 2 + 0.5, HALF_W + 0.6 },
			}
		do
			Kit.rod(
				"SillLog",
				place(V(r[1], L1 + 0.1, side * WALL_Z)).Position,
				place(V(r[2], L1 + 0.1, side * WALL_Z)).Position,
				1.6,
				LOG,
				M.Wood,
				shell
			)
		end
		Kit.rod(
			"SillLog",
			place(V(side * WALL_X, L1 + 0.12, -HALF_D - 0.6)).Position,
			place(V(side * WALL_X, L1 + 0.12, HALF_D + 0.6)).Position,
			1.58,
			LOG,
			M.Wood,
			shell
		)
	end
	for _, side in { -1, 1 } do
		gable(place, shell, side)
	end

	-- The ways in and out.
	hang("X", WALL_Z, 0, DOOR_W, DOOR_H, BACK, LEFT, LOG_D, {
		outside = true,
		casing = C.FRAME,
		color = rgb(54, 38, 28),
		panel = rgb(44, 32, 24),
		leaf = 0.5,
		gap = 0.08,
		name = "FrontDoor",
	})
	hang("X", -WALL_Z, BACK_DOOR_X, IN_DOOR_W, IN_DOOR_H, FRONT, RIGHT, LOG_D, {
		outside = true,
		casing = C.FRAME,
		gap = 0.08,
		name = "BackDoor",
	})

	--------------------------------------------------------------------------
	-- Partitions and doors
	--------------------------------------------------------------------------

	local function partition(
		name: string,
		axis: string,
		fixed: number,
		from: number,
		to: number,
		openings: { Opening },
		insetEnds: number?
	)
		Kit.wall({
			name = name,
			axis = axis,
			fixed = fixed,
			from = from,
			to = to,
			bottom = L1,
			top = CEIL,
			thickness = PART_T,
			openings = openings,
			color = PANEL,
			material = M.WoodPlanks,
			place = place,
			parent = interior,
			rooms = ROOMS,
			insetEnds = insetEnds,
			weather = 0.06,
		})
	end
	local function doorHole(at: number, w: number?, h: number?): Opening
		return { at = at, width = w or IN_DOOR_W, sill = L1, head = L1 + (h or IN_DOOR_H) }
	end
	local P = PART_T / 2

	-- The great room's sides and back.
	for _, side in { -1, 1 } do
		partition(
			"GreatWall",
			"Z",
			side * GREAT_X,
			-IN_Z,
			IN_Z,
			{ doorHole(18), doorHole(-4), doorHole(-18) }
		)
	end
	partition("GreatBackWall", "X", GREAT_Z0, -GREAT_X + P, -CHIMNEY_W / 2, { doorHole(-11) })
	partition("GreatBackWall", "X", GREAT_Z0, CHIMNEY_W / 2, GREAT_X - P, { doorHole(11) })
	-- Between the mud room and the workshop, behind the chimney.
	partition("BackWall", "Z", 0, -IN_Z, CHIMNEY_Z0, { doorHole(-19) })
	-- The middle bands down each side.
	for _, side in { -1, 1 } do
		local x0, x1 =
			if side < 0 then -IN_X else GREAT_X + P, if side < 0 then -GREAT_X - P else IN_X
		partition("BandWall", "X", MID_Z0, x0, x1, { doorHole(if side < 0 then -22 else 35) }, P)
		partition("BandWall", "X", MID_Z1, x0, x1, { doorHole(if side < 0 then -35 else 22) }, P)
		partition("BandWall", "Z", side * SPLIT_X, MID_Z0 + P, MID_Z1 - P, {})
	end
	-- The great room's walls carry on up to the roof, plain boards.
	for _, side in { -1, 1 } do
		local x = side * GREAT_X
		local zb, zf = GREAT_Z0 + P, IN_Z
		local low = roofUnder(zf)
		Kit.part(
			"GreatWallHigh",
			V(PART_T, low - CEIL, zf - zb),
			place(V(x, (CEIL + low) / 2, (zb + zf) / 2)),
			PANEL,
			M.WoodPlanks,
			interior
		)
		local a = place(V(x, low, zb)).Position
		local b = place(V(x, roofUnder(zb), zb)).Position
		local c = place(V(x, roofUnder(0), 0)).Position
		local d = place(V(x, low, zf)).Position
		Kit.triangle("GreatWallHigh", a, b, c, PART_T, PANEL, M.WoodPlanks, interior)
		Kit.triangle("GreatWallHigh", a, c, d, PART_T, PANEL, M.WoodPlanks, interior)
	end
	for _, r in { { -GREAT_X + P, -CHIMNEY_W / 2 }, { CHIMNEY_W / 2, GREAT_X - P } } do
		local top = roofUnder(GREAT_Z0)
		Kit.part(
			"GreatBackHigh",
			V(r[2] - r[1], top - CEIL, PART_T),
			place(V((r[1] + r[2]) / 2, (CEIL + top) / 2, GREAT_Z0)),
			PANEL,
			M.WoodPlanks,
			interior
		)
	end

	-- Doors. Off the great room first.
	hang("Z", -GREAT_X, 18, IN_DOOR_W, IN_DOOR_H, LEFT, FRONT, PART_T, { name = "BunkRoomDoor" })
	hang(
		"Z",
		-GREAT_X,
		-4,
		IN_DOOR_W,
		IN_DOOR_H,
		LEFT,
		BACK,
		PART_T,
		{ name = "KitchenDoor", ajar = 25 }
	)
	hang("Z", GREAT_X, 18, IN_DOOR_W, IN_DOOR_H, RIGHT, FRONT, PART_T, { name = "MasterDoor" })
	hang("Z", GREAT_X, -4, IN_DOOR_W, IN_DOOR_H, RIGHT, BACK, PART_T, { name = "TrophyRoomDoor" })
	hang("X", GREAT_Z0, -11, IN_DOOR_W, IN_DOOR_H, BACK, LEFT, PART_T, { name = "MudRoomDoor" })
	hang(
		"X",
		GREAT_Z0,
		11,
		IN_DOOR_W,
		IN_DOOR_H,
		BACK,
		LEFT,
		PART_T,
		{ name = "WorkshopDoor", ajar = 15 }
	)
	-- The back of the house.
	hang("Z", -GREAT_X, -18, IN_DOOR_W, IN_DOOR_H, RIGHT, BACK, PART_T, { name = "KitchenMudDoor" })
	hang(
		"Z",
		GREAT_X,
		-18,
		IN_DOOR_W,
		IN_DOOR_H,
		RIGHT,
		BACK,
		PART_T,
		{ name = "TrophyWorkshopDoor" }
	)
	hang("Z", 0, -19, IN_DOOR_W, IN_DOOR_H, RIGHT, BACK, PART_T, { name = "WorkshopMudDoor" })
	-- The middle bands.
	hang("X", MID_Z0, -22, IN_DOOR_W, IN_DOOR_H, FRONT, RIGHT, PART_T, { name = "StoreDoor" })
	hang("X", MID_Z1, -35, IN_DOOR_W, IN_DOOR_H, BACK, LEFT, PART_T, { name = "BathDoor" })
	hang("X", MID_Z1, 22, IN_DOOR_W, IN_DOOR_H, BACK, LEFT, PART_T, { name = "WashroomDoor" })
	hang("X", MID_Z0, 35, IN_DOOR_W, IN_DOOR_H, FRONT, RIGHT, PART_T, { name = "GunCupboardDoor" })

	--------------------------------------------------------------------------
	-- Roof, chimneys, trusses, porch
	--------------------------------------------------------------------------

	roof(place, shell)
	greatChimney(place, shell)
	eastChimney(place, shell)
	porch(place, shell)
	backStep(place, shell)

	-- King-post trusses across the great room, clear of the chimney.
	for _, x in { -10.5, 10.5 } do
		local tieY = WALL_TOP - 0.6
		local ridge = roofUnder(0) - 0.9
		local function onRafter(z: number): Vector3
			return V(x, roofUnder(z) - 0.75, z)
		end
		Kit.rod(
			"TieBeam",
			place(V(x, tieY, -IN_Z)).Position,
			place(V(x, tieY, IN_Z)).Position,
			1.2,
			Kit.weathered(LOG, 0.06),
			M.Wood,
			interior
		)
		for _, s in { -1, 1 } do
			Kit.rod(
				"Principal",
				place(onRafter(s * (IN_Z - 1))).Position,
				place(onRafter(s * 0.6)).Position,
				1.1,
				Kit.weathered(LOG, 0.06),
				M.Wood,
				interior
			)
			Kit.rod(
				"Strut",
				place(V(x, tieY + 0.5, s * 0.5)).Position,
				place(onRafter(s * 12)).Position,
				0.8,
				Kit.weathered(LOG, 0.06),
				M.Wood,
				interior
			)
		end
		Kit.rod(
			"KingPost",
			place(V(x, tieY, 0)).Position,
			place(V(x, ridge, 0)).Position,
			1.0,
			Kit.weathered(LOG, 0.06),
			M.Wood,
			interior
		)
	end

	--------------------------------------------------------------------------
	-- Furniture
	--------------------------------------------------------------------------

	local LINING = 0.3
	local function against(m: Model): Model
		return Furnish.backTo(m, LINING)
	end
	local GX = GREAT_X - PART_T / 2 -- a great room side wall's face
	local RX = GREAT_X + PART_T / 2 -- the same wall's face in the wing
	local LOGFACE = 0.15 -- furniture against a log wall stands clear of the logs' round

	-- The great room. Round the fire: a bearskin, two long leather sofas
	-- facing across it, a stump table between, chairs to the fire.
	local fireZ = CHIMNEY_Z1 + 3
	Decor.bearRug(spot(0, L1, fireZ + 5.6, BACK), furniture)
	Furnish.sofa(
		spot(-7.2, L1, fireZ + 5.5, RIGHT),
		furniture,
		{ cover = C.LEATHER, material = M.Leather, width = 9 }
	)
	Furnish.sofa(
		spot(7.2, L1, fireZ + 5.5, LEFT),
		furniture,
		{ cover = C.LEATHER, material = M.Leather, width = 9 }
	)
	Furnish.stumpTable(spot(0, L1, fireZ + 5.8), furniture)
	Decor.lantern(spot(0.6, L1 + 2.2, fireZ + 5.4), furniture)
	Furnish.armchair(
		spot(-3.6, L1, fireZ + 12, BACK + RIGHT * 0.3),
		furniture,
		{ cover = C.LEATHER_DARK, material = M.Leather }
	)
	Furnish.armchair(
		spot(3.6, L1, fireZ + 12, BACK + LEFT * 0.3),
		furniture,
		{ cover = C.LEATHER_DARK, material = M.Leather }
	)
	Furnish.rockingChair(spot(-8.4, L1, fireZ + 0.8, RIGHT + FRONT * 0.4), furniture)
	Decor.mountedHead(
		spot(0, L1 + 12.5, CHIMNEY_Z1 - 0.8 + 0.05, FRONT),
		furniture,
		{ kind = "elk", scale = 1.6 }
	)
	Furnish.firewood(
		spot(-CHIMNEY_W / 2 - 1.6, L1, CHIMNEY_Z1 + 0.6, FRONT),
		furniture,
		{ width = 2.6, rows = 4 }
	)
	-- The long table and its benches, laid and left.
	Decor.rug(
		spot(8.3, L1, 19.2, BACK),
		furniture,
		{ width = 13, length = 9, color = rgb(62, 30, 26) }
	)
	local _, underTable = Furnish.diningTable(spot(8.3, L1, 19.2, BACK), furniture, {
		name = "LodgeTable",
		length = 11.5,
		width = 4,
		wood = C.OAK,
		floor = 1,
	})
	hide(underTable)
	for _, side in { -1, 1 } do
		Furnish.bench(
			spot(8.3, L1, 19.2 + side * 3.2, V(0, 0, -side)),
			furniture,
			{ length = 10, wood = C.OAK }
		)
		for k = 0, 3 do
			Decor.placeSetting(
				spot(4.3 + k * 2.7, L1 + 4.06, 19.2 + side * 1.9, V(0, 0, side)),
				furniture,
				{
					food = (k + side) % 2 == 0,
					upset = k == 2 and side == 1,
				}
			)
		end
	end
	Decor.candelabra(spot(8.3, L1 + 4.1, 19.2), furniture, { fallen = true })
	Decor.antlerChandelier(spot(-10.5, WALL_TOP - 1.2, 11), furniture, { drop = 2.8 })
	Decor.antlerChandelier(spot(10.5, WALL_TOP - 1.2, 19.2), furniture, { drop = 2.8 })
	-- Along the west wall: a gun rack, a bookcase, a wolf by the door.
	Decor.gunRack(spot(-GX + 0.1, L1 + 6.8, 8, RIGHT), furniture)
	against(Furnish.bookcase(spot(-GX, L1, 24.4, RIGHT), furniture, { width = 3.6 }))
	Furnish.wolfMount(spot(-11.5, L1, 3.5, RIGHT + FRONT * 0.6), furniture)
	against(Furnish.desk(spot(-GX, L1, 12, RIGHT), furniture))
	Furnish.diningChair(spot(-12.4, L1, 12, LEFT), furniture, { seat = C.LEATHER })
	-- Heads on the walls.
	Decor.mountedHead(spot(-GX + 0.1, L1 + 9, 2.5, RIGHT), furniture, { kind = "deer" })
	Decor.mountedHead(spot(GX - 0.1, L1 + 9, 1.5, LEFT), furniture, { kind = "boar" })
	Decor.mountedHead(spot(GX - 0.1, L1 + 9, 10, LEFT), furniture, { kind = "wolf" })
	Decor.mountedHead(
		spot(-4.5, L1 + 11.2, IN_Z - LOGFACE, BACK),
		furniture,
		{ kind = "deer", scale = 0.9 }
	)
	Decor.mountedHead(
		spot(4.5, L1 + 11.2, IN_Z - LOGFACE, BACK),
		furniture,
		{ kind = "deer", scale = 0.9 }
	)
	for _, x in { -9, 9 } do
		Decor.curtains(
			spot(x, L1 + SILL + WIN_H + 0.4, IN_Z, BACK),
			furniture,
			{ width = 5, drop = 9, color = C.RUG }
		)
	end

	-- The bunk room: four double bunks, a stove in the middle, footlockers,
	-- a table where a game of cards stopped.
	local bunkBack = -IN_X + LOGFACE
	for _, z in { 11.8, 23 } do
		local bunk, under = Furnish.bunkBed(spot(bunkBack, L1, z, RIGHT), furniture, { floor = 1 })
		against(bunk)
		hide(under)
		Furnish.trunk(spot(-33.8, L1, z, RIGHT), furniture, { cover = C.LEATHER_DARK })
	end
	for _, z in { 11.8, 23.4 } do
		local bunk, under = Furnish.bunkBed(spot(-RX, L1, z, LEFT), furniture, { floor = 1 })
		against(bunk)
		hide(under)
	end
	Furnish.woodStove(spot(-28.5, L1, 17.5), furniture, { pipeTop = roofUnder(17.5) + 6 })
	local cardZ = 22.6
	Furnish.roundTable(
		spot(-29, L1, cardZ),
		furniture,
		{ diameter = 3.2, height = 3.0, name = "CardTable" }
	)
	Decor.lantern(spot(-29.6, L1 + 3.0, cardZ - 0.4), furniture)
	for k = 0, 2 do
		local a = k * 2 * math.pi / 3 - 0.6
		Furnish.stool(spot(-29 + math.cos(a) * 2.3, L1, cardZ + math.sin(a) * 2.3), furniture)
	end
	Decor.rug(
		spot(-29, L1, 15, BACK),
		furniture,
		{ width = 7, length = 10, color = rgb(58, 40, 30) }
	)
	Decor.curtains(
		spot(-24, L1 + SILL + WIN_H + 0.4, IN_Z, BACK),
		furniture,
		{ width = 5, drop = 9, color = C.RUG }
	)

	-- The bath.
	against(Furnish.bathtub(spot(-35.5, L1, MID_Z0 + P, FRONT), furniture))
	against(Furnish.washstand(spot(-SPLIT_X - P, L1, 4.6, LEFT), furniture))

	-- The store cupboard: shelves of jars, sacks, a place to hide behind the
	-- door.
	Decor.wallShelf(spot(-GREAT_X - P - 0.1, L1 + 4.4, 4, LEFT), furniture, { width = 5 })
	Decor.wallShelf(spot(-GREAT_X - P - 0.1, L1 + 7.0, 4, LEFT), furniture, { width = 5 })
	Furnish.barrel(spot(-26.2, L1, 6.4), furniture, { height = 2.8, diameter = 2 })
	Furnish.crate(spot(-18.2, L1, 6.1, BACK), furniture, { size = V(2.6, 2.2, 2.2) })
	hide(
		Kit.hideVolume(
			"StoreHidingVolume",
			place(V(-24, L1 + 2.8, 5.2)),
			V(4.2, 5, 3.6),
			"Cupboard",
			1,
			interior
		)
	)

	-- The kitchen: a range against the gable wall with its pipe up through
	-- the roof, the sink and pump under the window, a block with a cleaver,
	-- pots over the table, a hatch to nowhere.
	local range = Furnish.range(
		spot(-IN_X + LOGFACE, L1, -14, RIGHT),
		furniture,
		{ width = 5.2, pipeTop = roofUnder(14) + 6 }
	)
	against(range)
	against(
		Furnish.counter(
			spot(-24, L1, -IN_Z + LOGFACE, FRONT),
			furniture,
			{ width = 7.6, sink = true }
		)
	)
	against(Furnish.counter(spot(-36, L1, -IN_Z + LOGFACE, FRONT), furniture, { width = 6 }))
	local _, underWork = Furnish.workTable(spot(-29.5, L1, -12.5), furniture)
	hide(underWork)
	Decor.potRack(spot(-29.5, CEIL, -12.5), furniture, { width = 6, drop = 2.6 })
	against(Furnish.hutch(spot(-RX, L1, -10.6, LEFT), furniture, { width = 6.4 }))
	Furnish.chopBlock(spot(-22.4, L1, -20.4), furniture)
	Furnish.barrel(spot(-40.2, L1, -3.2), furniture)
	Furnish.barrel(spot(-37.8, L1, -2.6), furniture, { height = 2.6, diameter = 2 })
	Decor.hatch(spot(-34, L1, -4.8), furniture)
	Decor.wallShelf(spot(-IN_X + LOGFACE, L1 + 6.4, -1.8, RIGHT), furniture, { width = 2.4 })

	-- The mud room: coats on pegs, boots under a bench, a washtub, snowshoes,
	-- and the way out to the back.
	against(Furnish.hallStand(spot(-GX, L1, -24, RIGHT), furniture))
	-- The bench fits between the chimney's back and the workshop door.
	against(Furnish.bench(spot(-P, L1, -14.1, LEFT), furniture, { length = 4, wood = C.OAK }))
	Furnish.barrel(spot(-3, L1, -24.4), furniture, { height = 1.6, diameter = 2.6 })
	for k = 0, 3 do
		Kit.detail(
			Kit.part(
				"Boot",
				V(0.6, 1.1, 1.2),
				place(V(-2.2, L1 + 0.55, -15.4 + k * 0.85)) * CFrame.Angles(0, 0.1 * k, 0),
				C.LEATHER_DARK,
				M.Leather,
				furniture
			)
		).CastShadow =
			true
	end

	-- The workshop: hooks with what is on them, a bench of tools, a block
	-- and axe, traps, a drain in the floor.
	-- The butcher's table stands under the hooks; the bench is against the
	-- back wall under the window, clear of every door's swing.
	Decor.meatHooks(spot(9, CEIL, -16.2, FRONT), furniture, { width = 9 })
	Decor.meatHooks(spot(9, CEIL, -21, FRONT), furniture, { width = 7.5 })
	Furnish.workTable(spot(9, L1, -18.6, FRONT), furniture, { hide = false, length = 7 })
	against(
		Furnish.workbench(spot(11.2, L1, -IN_Z + LOGFACE, FRONT), furniture, { wallTools = false })
	)
	Furnish.chopBlock(spot(4, L1, -13.8), furniture)
	Decor.bearTrap(spot(3.8, L1, -24, RIGHT), furniture)
	Decor.bearTrap(spot(12, L1, -15, FRONT), furniture)
	Furnish.barrel(spot(1.7, L1, -13.6), furniture)
	Kit.detail(
		Kit.disc(
			"Drain",
			place(V(7.6, L1 + 0.03, -13.9)),
			1.3,
			0.04,
			C.IRON,
			M.DiamondPlate,
			dressing
		)
	)

	-- The trophy room: heads on every wall, a bear standing in the corner, a
	-- rack of guns, a desk, a chair by the window.
	Furnish.bearMount(spot(39.2, L1, -23, BACK * -1 + LEFT * 0.8), furniture)
	type Head = { at: Vector3, face: Vector3, kind: string }
	local heads: { Head } = {
		{ at = V(IN_X - LOGFACE, L1 + 7.2, -14), face = LEFT, kind = "elk" },
		{ at = V(RX + 0.1, L1 + 8, -10), face = RIGHT, kind = "deer" },
		{ at = V(RX + 0.1, L1 + 8, -24), face = RIGHT, kind = "boar" },
		{ at = V(30, L1 + 10, -IN_Z + LOGFACE), face = FRONT, kind = "wolf" },
		{ at = V(30, L1 + 8.6, MID_Z0 - P - 0.1), face = BACK, kind = "deer" },
		{ at = V(20, L1 + 8.6, MID_Z0 - P - 0.1), face = BACK, kind = "wolf" },
	}
	for _, h in heads do
		Decor.mountedHead(
			spot(h.at.X, h.at.Y, h.at.Z, h.face),
			furniture,
			{ kind = h.kind, scale = if h.kind == "elk" then 1.2 else 1 }
		)
	end
	Decor.gunRack(spot(30, L1 + 5.2, -IN_Z + LOGFACE, FRONT), furniture, { missing = false })
	against(Furnish.desk(spot(26, L1, MID_Z0 - P, BACK), furniture))
	Furnish.diningChair(spot(26, L1, -3.2, FRONT), furniture, { seat = C.LEATHER })
	Furnish.armchair(
		spot(36.2, L1, -9, LEFT + FRONT * 0.4),
		furniture,
		{ cover = C.LEATHER, material = M.Leather }
	)
	Decor.bearRug(spot(29, L1, -15, LEFT), furniture, { fur = rgb(56, 42, 32) })
	Decor.globe(spot(21.5, L1, -22.5), furniture)
	against(Furnish.bookcase(spot(IN_X - LOGFACE, L1, -2.6, LEFT), furniture, { width = 3.4 }))

	-- The master bedroom: a bed of logs, a wardrobe to hide in, a trunk, a
	-- rocking chair by the fire.
	local bed, underBed = Furnish.logBed(spot(31, L1, MID_Z1 + P, FRONT), furniture, { floor = 1 })
	against(bed)
	hide(underBed)
	local wardrobe, inWardrobe = Furnish.wardrobe(
		spot(RX, L1, 12, RIGHT),
		furniture,
		{ width = 5.6, wood = C.WALNUT, floor = 1 }
	)
	against(wardrobe)
	hide(inWardrobe)
	Furnish.trunk(spot(31, L1, 20.4, FRONT), furniture, { cover = C.LEATHER_DARK })
	Furnish.rockingChair(spot(37, L1, 21.6, RIGHT + BACK * 0.5), furniture)
	against(Furnish.nightstand(spot(26.4, L1, MID_Z1 + P, FRONT), furniture))
	Decor.lantern(spot(26.4, L1 + 3.18, 9.9), furniture)
	Decor.bearRug(spot(33, L1, 21, RIGHT), furniture)
	Decor.mountedHead(spot(RX + 0.1, L1 + 8.6, 23.5, RIGHT), furniture, { kind = "deer" })
	Decor.curtains(
		spot(24, L1 + SILL + WIN_H + 0.4, IN_Z, BACK),
		furniture,
		{ width = 5, drop = 9, color = C.RUG }
	)

	-- The washroom and the gun cupboard.
	against(Furnish.washstand(spot(SPLIT_X - P, L1, 3.6, LEFT), furniture))
	Furnish.barrel(
		spot(18.2, L1, 2.4),
		furniture,
		{ height = 1.6, diameter = 2.6, name = "Washtub" }
	)
	Decor.gunRack(spot(35.5, L1 + 5, MID_Z1 - P - 0.1, BACK), furniture)
	Furnish.crate(spot(31.5, L1, 5.8, FRONT), furniture, { size = V(2.4, 1.6, 1.8) })
	Furnish.crate(
		spot(31.5, L1, 5.8, FRONT) * CFrame.new(0, 1.62, 0) * CFrame.Angles(0, 0.3, 0),
		furniture,
		{ size = V(2, 1.2, 1.6) }
	)
	hide(
		Kit.hideVolume(
			"GunCupboardHidingVolume",
			place(V(37.2, L1 + 2.8, 4)),
			V(4, 5, 3.6),
			"Cupboard",
			1,
			interior
		)
	)

	-- The porch: chairs to watch the road, wood against the wall, antlers
	-- over the door, a lantern nobody lit, a trap by the step.
	Furnish.rockingChair(spot(-23, L1, 31.4, FRONT + RIGHT * 0.2), furniture)
	Furnish.rockingChair(spot(15, L1, 32.2, FRONT + LEFT * 0.3), furniture)
	against(Furnish.firewood(spot(-15.8, L1, HALF_D, FRONT), furniture, { width = 7, rows = 5 }))
	Furnish.bench(spot(22.5, L1, HALF_D + 1.4, FRONT), furniture, { length = 6, wood = BOARD })
	Decor.antlers(spot(0, L1 + DOOR_H + 1.9, IN_Z - LOGFACE, BACK), furniture, { scale = 1.1 })
	Decor.lantern(spot(-4.2, L1, 30.2), furniture)
	Furnish.chopBlock(spot(-9, GROUND, PORCH_Z + 4.5), furniture)
	Decor.bearTrap(spot(7.4, GROUND, PORCH_Z + 5), furniture)

	--------------------------------------------------------------------------
	-- Dirt, damage and worse
	--------------------------------------------------------------------------

	local function floorAt(x: number, z: number): CFrame
		return place(V(x, L1, z))
	end
	local function wallAt(x: number, y: number, z: number, face: Vector3): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face)
	end
	for _, s in
		{
			{ -6, 14, 2.4 },
			{ 12, 8, 1.8 },
			{ -30, 4.5, 1.4 },
			{ -24, -8, 2.2 },
			{ 30, -6, 1.6 },
			{ -34, 18, 1.8 },
		}
	do
		Decor.stain(floorAt(s[1], s[2]), dressing, s[3])
	end
	-- What happened in the workshop, and the way it was dragged out.
	Decor.stain(floorAt(7.6, -18.4), dressing, 3.2, C.BLOOD_OLD)
	Decor.stain(floorAt(4, -11.6), dressing, 1.4, C.BLOOD)
	local trail = { V(6.5, L1, -19.5), V(1.5, L1, -19.3), V(-4, L1, -21.5), V(-7.4, L1, -25.4) }
	for i = 1, #trail - 1 do
		Decor.smear(
			place(trail[i]).Position,
			place(trail[i + 1]).Position,
			dressing,
			0.9 - i * 0.12
		)
	end
	Decor.stain(floorAt(-7.8, -26), dressing, 1.2, C.BLOOD_OLD)
	-- Claw marks down the inside of the bunk room door's wall and the store.
	Decor.scratches(wallAt(-RX - 0.05, L1 + 5, 21.6, LEFT), dressing, 3)
	Decor.scratches(wallAt(-24, L1 + 4, MID_Z1 - P - 0.05, BACK), dressing, 2.4)
	Decor.scratches(wallAt(GX + 0.05, L1 + 4.6, 13.8, LEFT), dressing, 2.6)
	Decor.fallenPlaster(floorAt(-36, -18), dressing, CEIL)

	model.Parent = parent

	print(
		string.format(
			"[Lodge] %d parts, %d hiding places, ridge %d studs above ground",
			Kit.count(),
			#hidingSpots,
			math.floor(RIDGE - GROUND)
		)
	)

	return {
		model = model,
		entrance = CFrame.lookAt(
			place(V(0, GROUND + 3, PORCH_Z + 16)).Position,
			place(V(0, GROUND + 3, WALL_Z)).Position
		),
		hidingSpots = hidingSpots,
		partCount = Kit.count(),
	}
end

return Lodge
