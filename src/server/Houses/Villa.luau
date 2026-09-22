--!strict
--[[
	House #2: a brick villa in the Italianate style, generated entirely in
	code. Two floors and a roof you can walk on.

	A central hall runs from the front door to a dog-leg stair at the back,
	and the stair keeps going: up through the first floor and out into a
	belvedere, the square lookout room these houses carry on their roofs,
	which opens onto a flat roof walled in by a parapet and a tall spiked
	iron fence. The roof is somewhere to go, never a way down.

	There are exactly two ways out, the front door and the kitchen door.
	Every other window in the house is barred with round iron bars set close
	enough that nobody fits between them; the belvedere's windows open only
	onto the fenced roof. The fence is higher than anyone can jump from
	anything on the roof, and nothing tall enough to climb stands near it.

	Ground floor: parlour, dining room, kitchen, library, off the hall. First
	floor: master bedroom, nursery, a second bedroom, a sewing room and a
	bathroom. Every door opens (DoorController). Every room on each floor can
	be reached two ways, so a chase loops rather than ending.

	Built from HouseKit, Furnish and Decor. Local space runs +X right, +Y up,
	+Z out of the front door, with Y = 0 the ground floor; the ground is
	FOUND_H below that and the pivot sits on it.
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

local Villa = {}

----------------------------------------------------------------------------
-- Dimensions
----------------------------------------------------------------------------

local STOREY = 14 -- clear floor to ceiling: an Italianate house is tall inside
local SLAB = 1
local FOUND_H = 4 -- a raised base: the ground is this far below the ground floor
local L1 = 0
local L2 = L1 + STOREY + SLAB -- 15
local L3 = L2 + STOREY + SLAB -- 30, the roof
local GROUND = -FOUND_H

-- 64 by 52 across the outer faces.
local HALF_W = 32
local HALF_D = 26
local WALL_T = 1
local PART_T = 0.8
local WALL_X = HALF_W - WALL_T / 2
local WALL_Z = HALF_D - WALL_T / 2
local IN_X = HALF_W - WALL_T
local IN_Z = HALF_D - WALL_T
local HALL_X = 9 -- the hall walls stand at +/- this, both floors
local CROSS_Z = 2 -- the walls between the front and back rooms
local BATH_Z = -7 -- the bathroom's wall, behind the sewing room

--[[
	The stair: two flights a storey, nine steps each, up the left of the
	stair hall to a half landing against the back wall and back down the
	right to the floor above. The same again from the first floor to the
	roof, directly above. Under each landing is a cupboard.
]]
local RISE = (L2 - L1) / 18
local RUN = 1.25
local STEPS = 9
local STAIR_W = 5
local FLIGHT_X = 5
local FOOT_Z = -8.5
local LAND_Z = FOOT_Z - STEPS * RUN -- -19.75
local HALF_RISE = STEPS * RISE -- 7.5
local WELL = FLIGHT_X - STAIR_W / 2 - 0.3 -- 2.2: the flights' inner strings

-- The belvedere: the stair hall carried up through the roof and forward,
-- so there is room to step off the last flight.
local BELV_X = HALL_X
local BELV_Z1 = -2
local BELV_H = 12
local BELV_TOP = L3 + BELV_H

-- The roof: parapet, and the fence inside it.
local PARAPET_H = 3.5
local FENCE_H = 11.5 -- above any jump from anything on the roof
local FENCE_IN = 0.35 -- in from the walls' inner faces
local CORNICE_OUT = 2.4

--[[
	Window lines. Every head, with its lintel and hood or arch, stops under
	the stone band at the first floor or under the frieze at the roof: an
	arch's keystone that ran up into either would read as a mistake.
]]
local LOW_SILL = L1 + 2.5
local LOW_H = 7.5
local KITCHEN_SILL = L1 + 4.3 -- above the worktops
local UP_SILL = L2 + 2.4
local UP_H = 6.8

local DOOR_W = 6 -- the front pair
local DOOR_H = 10.5
local IN_DOOR_W = 5
local IN_DOOR_H = 9.5
local BACK_DOOR_X = -14
local BACK_DOOR_W = 4.5
local BACK_DOOR_H = 9

local PORTICO_X = 10
local PORTICO_D = 8
local PORTICO_Z = HALF_D + PORTICO_D -- 34
local PORTICO_H = 12

local STACK_W = 6
local STACK_D = 7
local STACK_TOP = L3 + 14
local FRONT_STACK_Z = 14
local BACK_STACK_Z = -12

--[[
	Outside: dark red-brown brick, sandstone dressings gone the colour of
	wet sand, the frames the same old oxblood as the manor's, and iron
	everywhere else. Inside the fence, the roof is boards.
]]
local BRICK = rgb(76, 42, 34)
local STONE = rgb(76, 68, 58)
local STONE_DARK = rgb(60, 55, 49)
local BLACK_MARBLE = rgb(40, 36, 34)
local DECK = rgb(58, 48, 40)
local ROOF = rgb(46, 42, 40)
local FRONT_DOOR = rgb(40, 26, 22)
local IRON = C.IRON

----------------------------------------------------------------------------
-- Rooms, and how each is finished
----------------------------------------------------------------------------

local function finish(paper: Color3, wainscot: number, cornice: boolean?): Finish
	return {
		paper = paper,
		wainscot = wainscot,
		rail = C.RAIL,
		skirting = C.RAIL,
		cornice = cornice,
	}
end

local F_HALL = finish(C.PAPER_UMBER, 5.0, true)
local F_PARLOUR = finish(C.PAPER_MAUVE, 3.6, true)
local F_DINING = finish(C.PAPER_OXBLOOD, 4.2, true)
local F_LIBRARY = finish(C.PAPER_SMOKE, 8.0, true)
local F_UPPER = finish(C.PAPER_DAMASK, 4.2, true)
local F_MASTER = finish(rgb(70, 50, 46), 3.4, true)
local F_BEDROOM = finish(C.PAPER_OCHRE, 3.4, false)
local F_NURSERY = finish(rgb(72, 60, 54), 3.0, false)
local F_SEWING = finish(C.PAPER_MAUVE, 3.4, false)
local F_BELVEDERE = finish(C.PAPER_SMOKE, 3.0, false)
local F_KITCHEN: Finish = {
	paper = C.PAPER_SMOKE,
	paperMaterial = M.Plaster,
	wainscot = 4.0,
	rail = C.RAIL,
	skirting = C.RAIL,
}
local F_BATH: Finish = {
	paper = rgb(66, 58, 50),
	paperMaterial = M.Plaster,
	wainscot = 4.6,
	rail = C.RAIL,
	dado = C.TILE_DARK,
	dadoMaterial = M.CeramicTiles,
}

-- The first box containing a point wins, so the cupboards under the
-- landings come before the halls they open off.
local ROOMS: { Room } = {
	{
		name = "UnderLanding",
		level = L1,
		height = HALF_RISE - SLAB,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = -HALF_D,
		z1 = LAND_Z,
	},
	{
		name = "UnderFlightB",
		level = L1,
		height = STOREY,
		x0 = WELL,
		x1 = HALL_X,
		z0 = LAND_Z,
		z1 = FOOT_Z,
	},
	{
		name = "Hall",
		level = L1,
		height = STOREY,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = LAND_Z,
		z1 = HALF_D,
		finish = F_HALL,
	},
	{
		name = "Parlour",
		level = L1,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = CROSS_Z,
		z1 = HALF_D,
		finish = F_PARLOUR,
	},
	{
		name = "Kitchen",
		level = L1,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = -HALF_D,
		z1 = CROSS_Z,
		finish = F_KITCHEN,
	},
	{
		name = "Dining",
		level = L1,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = CROSS_Z,
		z1 = HALF_D,
		finish = F_DINING,
	},
	{
		name = "Library",
		level = L1,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = -HALF_D,
		z1 = CROSS_Z,
		finish = F_LIBRARY,
	},
	{
		name = "LinenCupboard",
		level = L2,
		height = HALF_RISE - SLAB,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = -HALF_D,
		z1 = LAND_Z - PART_T / 2,
	},
	{
		name = "UpperHall",
		level = L2,
		height = STOREY,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = LAND_Z - PART_T / 2,
		z1 = HALF_D,
		finish = F_UPPER,
	},
	{
		name = "Master",
		level = L2,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = CROSS_Z,
		z1 = HALF_D,
		finish = F_MASTER,
	},
	{
		name = "Bedroom",
		level = L2,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = -HALF_D,
		z1 = CROSS_Z,
		finish = F_BEDROOM,
	},
	{
		name = "Nursery",
		level = L2,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = CROSS_Z,
		z1 = HALF_D,
		finish = F_NURSERY,
	},
	{
		name = "Sewing",
		level = L2,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = BATH_Z,
		z1 = CROSS_Z,
		finish = F_SEWING,
	},
	{
		name = "Bathroom",
		level = L2,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = -HALF_D,
		z1 = BATH_Z,
		finish = F_BATH,
	},
	{
		name = "Belvedere",
		level = L3,
		height = BELV_H,
		x0 = -BELV_X,
		x1 = BELV_X,
		z0 = -HALF_D,
		z1 = BELV_Z1,
		finish = F_BELVEDERE,
	},
}

--[[
	How much ground the house takes, in house space: from the kitchen
	stoop's bottom step to the portico's.
]]
Villa.FOOTPRINT = {
	x0 = -HALF_W - 4,
	x1 = HALF_W + 4,
	z0 = -HALF_D - 14,
	z1 = PORTICO_Z + 9,
}

-- Whether a world position is on the footprint of a villa built at `pivot`.
function Villa.footprintContains(pivot: CFrame, position: Vector3): boolean
	local rel = (pivot * CFrame.Angles(0, math.pi, 0)):PointToObjectSpace(position)
	local f = Villa.FOOTPRINT
	return rel.X > f.x0 and rel.X < f.x1 and rel.Z > f.z0 and rel.Z < f.z1
end

----------------------------------------------------------------------------
-- Orientation without conventions
----------------------------------------------------------------------------

--[[
	A world frame at a house-space point whose X and Y axes are the given
	house-space directions. Everything set at an angle on a wall — arch
	stones, brackets — is placed with this, so no rotation order or sign
	convention stands between the arithmetic and the result.
]]
local function oriented(place: Place, pos: Vector3, xDir: Vector3, yDir: Vector3): CFrame
	local rot = place(Vector3.zero).Rotation
	return CFrame.fromMatrix(
		place(pos).Position,
		rot:VectorToWorldSpace(xDir.Unit),
		rot:VectorToWorldSpace(yDir.Unit)
	)
end

----------------------------------------------------------------------------
-- Windows, hoods and the outside walls
----------------------------------------------------------------------------

type Window = {
	at: number,
	sill: number,
	width: number,
	height: number,
	style: string, -- "window" | "open" | "doorway"
	bars: boolean,
	hood: string?, -- "arch" | "segment" | "flat" | nil
}

local function barred(
	at: number,
	sill: number,
	width: number,
	height: number,
	hood: string?
): Window
	return {
		at = at,
		sill = sill,
		width = width,
		height = height,
		style = "window",
		bars = true,
		hood = hood,
	}
end

local function unbarred(
	at: number,
	sill: number,
	width: number,
	height: number,
	hood: string?
): Window
	return {
		at = at,
		sill = sill,
		width = width,
		height = height,
		style = "window",
		bars = false,
		hood = hood,
	}
end

local function doorway(
	at: number,
	sill: number,
	width: number,
	height: number,
	hood: string?
): Window
	return {
		at = at,
		sill = sill,
		width = width,
		height = height,
		style = "doorway",
		bars = false,
		hood = hood,
	}
end

-- Round bars no more than a stud apart, centre to centre: the gaps are
-- under three quarters of a stud, and nobody fits through that sideways.
local function barsFor(width: number): number
	return math.ceil(width / 0.95) - 1
end

type Band = { bottom: number, top: number, windows: { Window } }

local function bands(lower: { Window }, upper: { Window }): { Band }
	return {
		{ bottom = L1, top = L1 + STOREY, windows = lower },
		{ bottom = L1 + STOREY, top = L2, windows = {} },
		{ bottom = L2, top = L2 + STOREY, windows = upper },
		{ bottom = L2 + STOREY, top = L3, windows = {} },
	}
end

--[[
	A dressing over a window head, on the outside face. "arch": a round arch
	of stone voussoirs with a keystone, springing from blocks either side,
	the Italianate window. "flat": a stone hood on two brackets with a round
	moulding under its front edge.
]]
local function hood(
	place: Place,
	parent: Instance,
	axis: string,
	fixed: number,
	outward: number,
	at: number,
	head: number,
	width: number,
	kind: string?
)
	if not kind then
		return
	end
	local along = if axis == "X" then V(1, 0, 0) else V(0, 0, 1)
	local out = if axis == "X" then V(0, 0, outward) else V(outward, 0, 0)
	local face = fixed + outward * WALL_T / 2
	local function onFace(u: number, y: number, n: number): Vector3
		if axis == "X" then
			return V(u, y, face + outward * n)
		end
		return V(face + outward * n, y, u)
	end
	local springY = head + 0.45

	if kind == "arch" or kind == "segment" then
		-- A circle through both springing points and the crown: a half
		-- circle for "arch", a flat segment of a bigger one for "segment".
		local span = width / 2 + 0.85
		local rise = if kind == "arch" then span else 1.1
		local R = (span * span + rise * rise) / (2 * rise)
		local cy = springY + rise - R
		local th0 = math.acos(math.clamp(span / R, -1, 1))
		local sweep = math.pi - 2 * th0
		local blocks = if kind == "arch" then 9 else 7
		local arc = sweep * R / blocks
		for i = 0, blocks - 1 do
			local th = th0 + sweep * (i + 0.5) / blocks
			local key = i == (blocks - 1) / 2
			local rr = R + (if key then 0.15 else 0)
			local tangent = along * -math.sin(th) + V(0, math.cos(th), 0)
			Kit.part(
				if key then "Keystone" else "Voussoir",
				V(arc * 0.9, 0.5, if key then 1.1 else 0.75),
				oriented(
					place,
					onFace(at + rr * math.cos(th), cy + rr * math.sin(th), 0.25),
					tangent,
					out
				),
				Kit.weathered(STONE, 0.06),
				M.Concrete,
				parent
			)
		end
		for _, sgn in { -1, 1 } do
			Kit.part(
				"Springer",
				V(1.0, 0.5, 0.8),
				oriented(place, onFace(at + sgn * span, springY - 0.3, 0.25), along, out),
				STONE,
				M.Concrete,
				parent
			)
		end
		return
	end

	Kit.part(
		"Hood",
		V(width + 1.8, 0.9, 0.5),
		oriented(place, onFace(at, springY + 0.25, 0.45), along, out),
		STONE,
		M.Concrete,
		parent
	)
	Kit.detail(
		Kit.rod(
			"HoodMoulding",
			place(onFace(at - width / 2 - 0.9, springY - 0.02, 0.75)).Position,
			place(onFace(at + width / 2 + 0.9, springY - 0.02, 0.75)).Position,
			0.3,
			STONE,
			M.Concrete,
			parent
		)
	)
	for _, sgn in { -1, 1 } do
		Kit.part(
			"HoodBracket",
			V(0.35, 0.7, 0.9),
			oriented(place, onFace(at + sgn * (width / 2 + 0.55), springY - 0.45, 0.35), along, out),
			STONE,
			M.Concrete,
			parent
		)
	end
end

local function exterior(
	label: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	outward: number,
	wallBands: { Band },
	place: Place,
	parent: Instance,
	insetEnds: number?
)
	local look = if axis == "X" then V(0, 0, outward) else V(outward, 0, 0)
	for _, band in wallBands do
		local openings: { Opening } = {}
		for _, w in band.windows do
			table.insert(
				openings,
				{ at = w.at, width = w.width, sill = w.sill, head = w.sill + w.height }
			)
		end
		Kit.wall({
			name = "Wall" .. label,
			axis = axis,
			fixed = fixed,
			from = from,
			to = to,
			bottom = band.bottom,
			top = band.top,
			thickness = WALL_T,
			openings = openings,
			color = BRICK,
			material = M.Brick,
			place = place,
			parent = parent,
			outward = outward,
			rooms = ROOMS,
			insetEnds = insetEnds,
			weather = 0.06,
		})
		for _, w in band.windows do
			if w.style ~= "doorway" then
				local centre = if axis == "X"
					then V(w.at, w.sill + w.height / 2, fixed)
					else V(fixed, w.sill + w.height / 2, w.at)
				Kit.window(place(centre) * CFrame.new(Vector3.zero, look), w.width, w.height, {
					style = w.style,
					thickness = WALL_T,
					parent = parent,
					bars = if w.bars then barsFor(w.width) else nil,
					barColor = IRON,
				})
			end
			hood(place, parent, axis, fixed, outward, w.at, w.sill + w.height, w.width, w.hood)
		end
	end
end

----------------------------------------------------------------------------
-- Base, dressings, cornice
----------------------------------------------------------------------------

local function foundation(place: Place, parent: Instance)
	-- Two courses of rough stone, the upper set back, stopping under the
	-- ground floor's boards.
	for i, out in { 0.9, 0.45 } do
		local bottom = GROUND + (i - 1) * FOUND_H / 2 - 0.05
		local top = math.min(GROUND + i * FOUND_H / 2, L1 - 0.3)
		Kit.part(
			"Footing",
			V(HALF_W * 2 + out * 2, top - bottom, HALF_D * 2 + out * 2),
			place(V(0, (top + bottom) / 2, 0)),
			Kit.weathered(if i == 1 then STONE_DARK else STONE, 0.05),
			M.Cobblestone,
			parent
		)
	end
end

--[[
	Stone quoins up every corner, long and short in turn. Each is two plates,
	one on each face it wraps, half set into the brick and half proud of it;
	a solid block would run through the corner and out into the room. The
	plate on the side face stops a hundredth short of the front plate's
	outer face, so the two never share a plane.
]]
local function quoins(place: Place, parent: Instance)
	local top = L3 - 3.4
	local h = 1.5
	local t = 0.3
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			local i = 0
			local y = L1 - 0.2
			while y + h <= top do
				local longX = i % 2 == 0
				local sx = if longX then 2.6 else 1.3
				local sz = if longX then 1.3 else 2.6
				local colour = Kit.weathered(STONE, 0.05)
				-- On the front or back face.
				local fx = sx + t / 2 - 0.01
				Kit.part(
					"Quoin",
					V(fx, h - 0.12, t),
					place(V(cx * (HALF_W + t / 2 - 0.01 - fx / 2), y + h / 2, cz * HALF_D)),
					colour,
					M.Concrete,
					parent
				)
				-- On the side face.
				local fz = sz + t / 2 - 0.01
				Kit.part(
					"Quoin",
					V(t, h - 0.12, fz),
					place(V(cx * HALF_W, y + h / 2, cz * (HALF_D + t / 2 - 0.01 - fz / 2))),
					colour,
					M.Concrete,
					parent
				)
				y += h
				i += 1
			end
		end
	end
end

-- A stone band round the house at the first floor, where a string course
-- marks the floor line outside.
local function stringCourse(place: Place, parent: Instance)
	local y = L2 - 0.5
	for _, side in { -1, 1 } do
		Kit.part(
			"StringCourse",
			V(HALF_W * 2 + 0.6, 0.7, 0.5),
			place(V(0, y, side * (HALF_D + 0.1))),
			STONE,
			M.Concrete,
			parent
		)
		Kit.part(
			"StringCourse",
			V(0.5, 0.68, HALF_D * 2 - 0.2),
			place(V(side * (HALF_W + 0.1), y, 0)),
			STONE,
			M.Concrete,
			parent
		)
	end
end

--[[
	The bracketed cornice at the roof line: a frieze, a deep projecting
	cornice, and under it a pair of scrolled brackets every few studs. The
	pairs stop short of the chimney stacks, which the cornice runs into.
]]
local function cornice(place: Place, parent: Instance)
	local top = L3 + 0.2
	local thick = 1.2
	-- The frieze.
	for _, side in { -1, 1 } do
		Kit.part(
			"Frieze",
			V(HALF_W * 2 + 0.3, 2.2, 0.3),
			place(V(0, L3 - 2.1, side * (HALF_D + 0.1))),
			STONE_DARK,
			M.Concrete,
			parent
		)
		Kit.part(
			"Frieze",
			V(0.3, 2.18, HALF_D * 2),
			place(V(side * (HALF_W + 0.1), L3 - 2.1, 0)),
			STONE_DARK,
			M.Concrete,
			parent
		)
	end
	-- The cornice slab, front and back full width, the sides between them.
	local outer = CORNICE_OUT
	for _, side in { -1, 1 } do
		Kit.part(
			"Cornice",
			V((HALF_W + outer) * 2, thick, outer + 0.5),
			place(V(0, top - thick / 2, side * (HALF_D + (outer - 0.5) / 2))),
			STONE,
			M.Concrete,
			parent
		)
		Kit.part(
			"Cornice",
			V(outer + 0.5, thick, HALF_D * 2 - 1),
			place(V(side * (HALF_W + (outer - 0.5) / 2), top - thick / 2, 0)),
			STONE,
			M.Concrete,
			parent
		)
	end
	-- A round moulding along the cornice's edge, all the way round.
	local e = outer - 0.05
	local y = top - thick - 0.05
	local corners = {
		V(-HALF_W - e, y, HALF_D + e),
		V(HALF_W + e, y, HALF_D + e),
		V(HALF_W + e, y, -HALF_D - e),
		V(-HALF_W - e, y, -HALF_D - e),
	}
	for i = 1, 4 do
		Kit.detail(
			Kit.rod(
				"CorniceMoulding",
				place(corners[i]).Position,
				place(corners[i % 4 + 1]).Position,
				0.45,
				STONE,
				M.Concrete,
				parent
			)
		)
	end

	-- Paired brackets.
	local function inStack(side: number, u: number, axis: string): boolean
		if axis ~= "Z" then
			return false
		end
		for _, z in { FRONT_STACK_Z, BACK_STACK_Z } do
			if math.abs(u - z) < STACK_W / 2 + 1 then
				return true
			end
		end
		return false
	end
	local function run(axis: string, side: number, from: number, to: number)
		local span = to - from
		local pairsN = math.floor(span / 5)
		for k = 0, pairsN do
			local c = from + span * k / pairsN
			for _, dx in { -0.45, 0.45 } do
				local u = c + dx
				if inStack(side, u, axis) then
					continue
				end
				local along = if axis == "X" then V(1, 0, 0) else V(0, 0, 1)
				local outDir = if axis == "X" then V(0, 0, side) else V(side, 0, 0)
				local base = if axis == "X" then V(u, 0, side * HALF_D) else V(side * HALF_W, 0, u)
				Kit.part(
					"Bracket",
					V(0.45, 1.7, 1.9),
					oriented(
						place,
						base + outDir * 0.95 + V(0, top - thick - 0.85, 0),
						along,
						V(0, 1, 0)
					),
					STONE,
					M.Concrete,
					parent
				)
				Kit.detail(
					Kit.rod(
						"BracketScroll",
						place(base + outDir * 1.55 + V(0, top - thick - 1.55, 0) - along * 0.24).Position,
						place(base + outDir * 1.55 + V(0, top - thick - 1.55, 0) + along * 0.24).Position,
						0.8,
						STONE,
						M.Concrete,
						parent
					)
				)
			end
		end
	end
	for _, side in { -1, 1 } do
		run("X", side, -HALF_W + 1.5, HALF_W - 1.5)
		run("Z", side, -HALF_D + 1.5, HALF_D - 1.5)
	end
end

----------------------------------------------------------------------------
-- Chimneys
----------------------------------------------------------------------------

type Fireplace = {
	level: number,
	w: number,
	h: number,
	grate: boolean?,
	depth: number?,
	guard: boolean?,
}

--[[
	A chimney stack straddling a side wall, a fireplace in its breast on each
	floor listed, rising through the cornice and the roof well above the
	fence. Worked in the wall's own terms, `u` along it and `n` in from its
	outer face, as the manor's are; inside, the breast is papered to match
	the room above its mantel.
]]
local function chimney(
	place: Place,
	parent: Instance,
	side: number,
	at: number,
	fireplaces: { Fireplace }
)
	local function pt(u: number, y: number, n: number): Vector3
		return V(side * (HALF_W - n), y, at + u)
	end
	local function sz(su: number, sy: number, sn: number): Vector3
		return V(sn, sy, su)
	end
	local function brick(
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
			sz(u1 - u0, y1 - y0, n1 - n0),
			place(pt((u0 + u1) / 2, (y0 + y1) / 2, (n0 + n1) / 2)),
			BRICK,
			M.Brick,
			parent
		)
	end
	local hw, face = STACK_W / 2, STACK_D / 2
	local cursor = GROUND
	for _, fp in fireplaces do
		local d = fp.depth or 2
		local lintelTop = fp.level + fp.h + 1
		brick("Chimney", -hw, hw, cursor, fp.level, -face, face)
		brick("ChimneyBack", -hw, hw, fp.level, lintelTop, -face, face - d)
		brick("ChimneyLintel", -hw, hw, fp.level + fp.h, lintelTop, face - d, face)
		brick("ChimneyPier", -hw, -fp.w / 2, fp.level, fp.level + fp.h, face - d, face)
		brick("ChimneyPier", fp.w / 2, hw, fp.level, fp.level + fp.h, face - d, face)
		Kit.detail(
			Kit.part(
				"Soot",
				sz(fp.w, fp.h, 0.1),
				place(pt(0, fp.level + fp.h / 2, face - d + 0.05)),
				C.SOOT,
				M.Slate,
				parent
			)
		)
		Kit.detail(
			Kit.part(
				"Hearth",
				sz(fp.w + 2, 0.2, d + 1.2),
				place(pt(0, fp.level + 0.1, face - d / 2 + 0.6)),
				C.SLATE,
				M.Slate,
				parent
			)
		)
		-- A marble surround: two round columns and a mantel shelf.
		for _, u in { -fp.w / 2 - 0.45, fp.w / 2 + 0.45 } do
			Kit.detail(
				Kit.rod(
					"MantelColumn",
					place(pt(u, fp.level + 0.2, face + 0.25)).Position,
					place(pt(u, lintelTop - 0.2, face + 0.25)).Position,
					0.6,
					BLACK_MARBLE,
					M.Marble,
					parent
				)
			)
		end
		Kit.soft(
			Kit.part(
				"Mantel",
				sz(fp.w + 2.6, 0.35, 1.3),
				place(pt(0, lintelTop + 0.18, face + 0.45)),
				BLACK_MARBLE,
				M.Marble,
				parent
			)
		)
		Kit.detail(
			Kit.rod(
				"MantelEdge",
				place(pt(-(fp.w + 2.6) / 2, lintelTop + 0.18, face + 1.1)).Position,
				place(pt((fp.w + 2.6) / 2, lintelTop + 0.18, face + 1.1)).Position,
				0.35,
				BLACK_MARBLE,
				M.Marble,
				parent
			)
		)
		if fp.grate ~= false then
			local backN = face - d + 0.3
			for _, u in { -fp.w / 2 + 0.6, fp.w / 2 - 0.6 } do
				local foot = place(pt(u, fp.level + 0.2, face - 0.3)).Position
				Kit.detail(
					Kit.rod("Andiron", foot, foot + V(0, 1.1, 0), 0.14, IRON, M.Metal, parent)
				)
				Kit.detail(
					Kit.ball("AndironTop", foot + V(0, 1.2, 0), 0.3, C.BRASS, M.Metal, parent)
				)
				Kit.detail(
					Kit.rod(
						"AndironBar",
						foot + V(0, 0.4, 0),
						place(pt(u, fp.level + 0.4, backN)).Position,
						0.12,
						IRON,
						M.Metal,
						parent
					)
				)
			end
			Kit.detail(
				Kit.part(
					"Ashes",
					sz(fp.w - 0.6, 0.06, d - 0.5),
					place(pt(0, fp.level + 0.23, face - d / 2)),
					rgb(40, 38, 36),
					M.Slate,
					parent
				)
			)
		end
		if fp.guard then
			-- A nursery fireguard: a curved brass-railed mesh in front.
			local r = fp.w / 2 + 0.6
			local prev: Vector3? = nil
			for k = 0, 8 do
				local a = math.pi * k / 8
				local p = place(
					pt(-math.cos(a) * r, fp.level + 2.6, face + 0.2 + math.sin(a) * 1.4)
				).Position
				if prev then
					Kit.detail(Kit.rod("GuardRail", prev, p, 0.12, C.BRASS, M.Metal, parent))
					Kit.detail(
						Kit.part(
							"GuardMesh",
							V((p - prev).Magnitude, 2.4, 0.05),
							CFrame.lookAt(
								(p + prev) / 2 - V(0, 1.2, 0),
								(p + prev) / 2 - V(0, 1.2, 0) + (p - prev):Cross(Vector3.yAxis)
							),
							IRON,
							M.DiamondPlate,
							parent
						)
					).Transparency =
						0.35
				end
				prev = p
			end
		end

		-- Papered to match the room above the mantel and down both sides.
		local room = Kit.roomAt(ROOMS, pt(0, fp.level + 2, face + 1))
		if room and room.finish then
			local paper = Kit.weathered(room.finish.paper, 0.05)
			local mat = room.finish.paperMaterial or M.Fabric
			local ceil = room.level + room.height
			local y0 = lintelTop + 0.36
			if ceil - y0 > EPS then
				Kit.detail(
					Kit.part(
						"Wallpaper",
						sz(STACK_W, ceil - y0, 0.1),
						place(pt(0, (y0 + ceil) / 2, face + 0.05)),
						paper,
						mat,
						parent
					)
				).CastShadow =
					true
			end
			local n0 = WALL_T + 0.1
			for _, u in { -hw - 0.05, hw + 0.05 } do
				Kit.detail(
					Kit.part(
						"Wallpaper",
						sz(0.1, ceil - room.level, face - n0),
						place(pt(u, (room.level + ceil) / 2, (n0 + face) / 2)),
						paper,
						mat,
						parent
					)
				).CastShadow =
					true
			end
		end
		cursor = lintelTop
	end
	brick("Chimney", -hw, hw, cursor, STACK_TOP, -face, face)
	Kit.part(
		"ChimneyCap",
		sz(STACK_W + 1.4, 0.8, STACK_D + 1.4),
		place(pt(0, STACK_TOP + 0.4, 0)),
		STONE_DARK,
		M.Concrete,
		parent
	)
	for _, u in { -1.3, 1.3 } do
		local base = place(pt(u, STACK_TOP + 0.8, 0)).Position
		Kit.rod("ChimneyPot", base, base + V(0, 2.4, 0), 1.2, rgb(70, 44, 36), M.Brick, parent)
		Kit.detail(
			Kit.disc(
				"PotRim",
				CFrame.new(base + V(0, 2.4, 0)),
				1.5,
				0.25,
				rgb(62, 40, 34),
				M.Brick,
				parent
			)
		)
	end
end

----------------------------------------------------------------------------
-- The roof: parapet, fence, belvedere
----------------------------------------------------------------------------

-- Stretches of a side wall's line not taken by a chimney stack.
local function sideRuns(from: number, to: number, pad: number): { { number } }
	local runs: { { number } } = {}
	local cursor = from
	for _, z in { BACK_STACK_Z, FRONT_STACK_Z } do
		local a, b = z - STACK_W / 2 - pad, z + STACK_W / 2 + pad
		if a > cursor then
			table.insert(runs, { cursor, a })
		end
		cursor = math.max(cursor, b)
	end
	if to > cursor then
		table.insert(runs, { cursor, to })
	end
	return runs
end

--[[
	The parapet: a brick wall on the outside walls' tops with a round stone
	coping, broken only by the chimney stacks and the belvedere's back wall.
	It is outside the fence, so nothing a player can reach stands on it.
]]
local function parapet(place: Place, parent: Instance)
	local y0, y1 = L3 + 0.2, L3 + PARAPET_H
	local function piece(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local d = b - a
		local size = if math.abs(d.X) > math.abs(d.Z)
			then V(math.abs(d.X), y1 - y0, WALL_T)
			else V(WALL_T, y1 - y0 - 0.02, math.abs(d.Z))
		Kit.part(
			"Parapet",
			size,
			place(V(mid.X, (y0 + y1) / 2, mid.Z)),
			Kit.weathered(BRICK, 0.05),
			M.Brick,
			parent
		)
		Kit.rod(
			"Coping",
			place(V(a.X, y1 + 0.2, a.Z)).Position,
			place(V(b.X, y1 + 0.2, b.Z)).Position,
			1.3,
			STONE,
			M.Concrete,
			parent
		)
	end
	piece(V(-HALF_W, 0, WALL_Z), V(HALF_W, 0, WALL_Z))
	piece(V(-HALF_W, 0, -WALL_Z), V(-BELV_X - WALL_T / 2, 0, -WALL_Z))
	piece(V(BELV_X + WALL_T / 2, 0, -WALL_Z), V(HALF_W, 0, -WALL_Z))
	for _, side in { -1, 1 } do
		for _, r in sideRuns(-IN_Z, IN_Z, 0) do
			piece(V(side * WALL_X, 0, r[1]), V(side * WALL_X, 0, r[2]))
		end
	end
end

--[[
	The fence round the roof: round iron bars under a stud apart, from the
	boards to FENCE_H with a ball on each, and three flat rails. It stands
	just inside the parapet, so the parapet's top is out of reach, and it
	runs into the chimney stacks and the belvedere, which are taller still.
]]
local function fence(place: Place, parent: Instance)
	local base = L3
	local top = L3 + FENCE_H
	local function run(a: Vector3, b: Vector3)
		local d = b - a
		local length = d.Magnitude
		if length < 0.5 then
			return
		end
		local dir = d.Unit
		local bars = math.max(1, math.ceil(length / 0.95))
		for i = 0, bars do
			local p = a + dir * (length * i / bars)
			local post = i == 0 or i == bars
			Kit.rod(
				if post then "FencePost" else "FenceBar",
				place(V(p.X, base, p.Z)).Position,
				place(V(p.X, top, p.Z)).Position,
				if post then 0.5 else 0.28,
				IRON,
				M.CorrodedMetal,
				parent
			)
			Kit.detail(
				Kit.ball(
					"Finial",
					place(V(p.X, top + 0.2, p.Z)).Position,
					if post then 0.7 else 0.4,
					IRON,
					M.CorrodedMetal,
					parent
				)
			)
		end
		for _, y in { base + 0.5, base + PARAPET_H - 0.3, top - 0.6 } do
			local mid = (a + b) / 2
			Kit.part(
				"FenceRail",
				if math.abs(d.X) > math.abs(d.Z)
					then V(length, 0.3, 0.14)
					else V(0.14, 0.28, length),
				place(V(mid.X, y, mid.Z)),
				IRON,
				M.CorrodedMetal,
				parent
			)
		end
	end
	local fz = IN_Z - FENCE_IN
	local fx = IN_X - FENCE_IN
	run(V(-fx, 0, fz), V(fx, 0, fz))
	run(V(-fx, 0, -fz), V(-BELV_X - WALL_T / 2 - 0.1, 0, -fz))
	run(V(BELV_X + WALL_T / 2 + 0.1, 0, -fz), V(fx, 0, -fz))
	for _, side in { -1, 1 } do
		for _, r in sideRuns(-fz, fz, 0.05) do
			run(V(side * fx, 0, r[1]), V(side * fx, 0, r[2]))
		end
	end
end

--[[
	The belvedere's roof: a low pyramid on a bracketed cornice, a flat
	boarded ceiling under it, and a weather vane on the point.
]]
local function belvedereRoof(place: Place, parent: Instance)
	local x0, x1 = -BELV_X - WALL_T / 2, BELV_X + WALL_T / 2
	local z0, z1 = -HALF_D, BELV_Z1 + WALL_T / 2
	local zc = (z0 + z1) / 2
	-- Ceiling inside.
	Kit.part(
		"BelvedereCeiling",
		V(x1 - x0 - WALL_T * 2, 0.6, z1 - z0 - WALL_T * 2),
		place(V(0, BELV_TOP - 0.3, zc)),
		DECK,
		M.WoodPlanks,
		parent
	)
	-- Frieze and cornice round the top of its walls.
	local out = 1.8
	Kit.part(
		"BelvedereFrieze",
		V(x1 - x0 + 0.3, 1.4, z1 - z0 + 0.3),
		place(V(0, BELV_TOP - 0.7, zc)),
		STONE_DARK,
		M.Concrete,
		parent
	)
	Kit.part(
		"BelvedereCornice",
		V(x1 - x0 + out * 2, 0.9, z1 - z0 + out * 2),
		place(V(0, BELV_TOP + 0.45, zc)),
		STONE,
		M.Concrete,
		parent
	)
	for _, sx in { -1, 1 } do
		for k = 0, 6 do
			local z = z0 + 1 + (z1 - z0 - 2) * k / 6
			Kit.part(
				"Bracket",
				V(1.4, 1.2, 0.4),
				place(V(sx * (x1 + 0.7), BELV_TOP - 0.6, z)),
				STONE,
				M.Concrete,
				parent
			)
		end
		for k = 0, 5 do
			local x = x0 + 1 + (x1 - x0 - 2) * k / 5
			Kit.part(
				"Bracket",
				V(0.4, 1.2, 1.4),
				place(V(x, BELV_TOP - 0.6, sx > 0 and z1 + 0.7 or z0 - 0.7)),
				STONE,
				M.Concrete,
				parent
			)
		end
	end
	-- The pyramid.
	local eaveY = BELV_TOP + 0.9
	local e = out - 0.1
	local apex = place(V(0, eaveY + 5.5, zc)).Position
	local corners = {
		place(V(x0 - e, eaveY, z1 + e)).Position,
		place(V(x1 + e, eaveY, z1 + e)).Position,
		place(V(x1 + e, eaveY, z0 - e)).Position,
		place(V(x0 - e, eaveY, z0 - e)).Position,
	}
	for i = 1, 4 do
		Kit.triangle(
			"BelvedereRoof",
			corners[i],
			corners[i % 4 + 1],
			apex,
			0.7,
			ROOF,
			M.Slate,
			parent
		)
		Kit.detail(Kit.rod("Hip", corners[i], apex, 0.45, STONE_DARK, M.Concrete, parent))
	end
	local vaneAt = place(V(0, eaveY + 5.5, zc))
	Furnish.weatherVane(CFrame.new(vaneAt.Position) * vaneAt.Rotation, parent)
end

----------------------------------------------------------------------------
-- The portico and the back stoop
----------------------------------------------------------------------------

--[[
	Stone steps: a solid block per step, each running back under the next,
	with the hidden ramp every stair in these houses is walked on, and a
	cheek wall each side with a round coping ending in a stone ball.
]]
local function stoneSteps(
	name: string,
	cx: number,
	width: number,
	zTop: number,
	zBottom: number,
	steps: number,
	place: Place,
	parent: Instance
)
	local dirZ = if zBottom > zTop then 1 else -1
	local run = math.abs(zBottom - zTop)
	local treadRun = run / steps
	local rise = (L1 - GROUND) / steps
	for i = 1, steps do
		-- Step i counted from the top: its tread is at L1 - rise * (i - 1)... the
		-- top step is the portico floor itself, so start one down.
		local topY = L1 - rise * i
		local zFront = zTop + dirZ * treadRun * i
		local zBack = zTop
		Kit.part(
			name,
			V(width, topY - GROUND, math.abs(zFront - zBack)),
			place(V(cx, (topY + GROUND) / 2, (zFront + zBack) / 2)),
			Kit.weathered(STONE_DARK, 0.05),
			M.Slate,
			parent
		)
	end
	-- The ramp: from the ground at the bottom step's nose to the top.
	local a = V(cx, GROUND, zBottom)
	local b = V(cx, L1, zTop)
	local mid = (a + b) / 2
	local along = (b - a).Unit
	local right = V(1, 0, 0)
	local up = right:Cross(along)
	if up.Y < 0 then
		up = -up
	end
	Kit.part(
		name .. "Ramp",
		V(width, 0.8, (b - a).Magnitude),
		oriented(place, mid - up * 0.4, right, up),
		STONE_DARK,
		M.Slate,
		parent
	).Transparency =
		1
	for _, sx in { -1, 1 } do
		local x = cx + sx * (width / 2 + 0.6)
		Kit.part(
			name .. "Cheek",
			V(1.2, L1 - GROUND + 1.2, run + 0.4),
			place(V(x, (L1 + 1.2 + GROUND) / 2, (zTop + zBottom) / 2 + dirZ * 0.2)),
			STONE,
			M.Concrete,
			parent
		)
		Kit.rod(
			name .. "Coping",
			place(V(x, L1 + 1.4, zTop)).Position,
			place(V(x, L1 + 1.4, zBottom + dirZ * 0.4)).Position,
			1.3,
			STONE,
			M.Concrete,
			parent
		)
		Kit.ball(
			name .. "Ball",
			place(V(x, L1 + 2.6, zBottom + dirZ * 0.2)).Position,
			1.6,
			STONE,
			M.Concrete,
			parent
		)
		Kit.part(
			name .. "BallBase",
			V(1.4, 0.3, 1.4),
			place(V(x, L1 + 2.0, zBottom + dirZ * 0.2)),
			STONE,
			M.Concrete,
			parent
		)
	end
end

local function portico(place: Place, parent: Instance)
	-- Floor and the stone base under it.
	Kit.part(
		"PorticoFloor",
		V(PORTICO_X * 2, SLAB, PORTICO_D),
		place(V(0, L1 - SLAB / 2, HALF_D + PORTICO_D / 2)),
		STONE_DARK,
		M.Slate,
		parent
	)
	Kit.part(
		"PorticoBase",
		V(PORTICO_X * 2 + 0.6, FOUND_H - SLAB, PORTICO_D + 0.3),
		place(V(0, GROUND + (FOUND_H - SLAB) / 2, HALF_D + PORTICO_D / 2 + 0.15)),
		STONE,
		M.Cobblestone,
		parent
	)
	stoneSteps("PorticoStep", 0, 7.4, PORTICO_Z, PORTICO_Z + 7, 5, place, parent)

	-- Four round columns across the front, pilasters against the wall.
	local colZ = PORTICO_Z - 1.2
	local beamY = L1 + PORTICO_H
	for _, x in { -9, -5, 5, 9 } do
		local foot = place(V(x, L1, colZ)).Position
		local up = V(0, 1, 0)
		Kit.part(
			"ColumnPlinth",
			V(1.9, 0.9, 1.9),
			CFrame.new(foot + up * 0.45),
			STONE,
			M.Concrete,
			parent
		)
		Kit.detail(
			Kit.disc(
				"ColumnBase",
				CFrame.new(foot + up * 1.05),
				1.7,
				0.3,
				STONE,
				M.Concrete,
				parent
			)
		)
		Kit.rod(
			"Column",
			foot + up * 1.2,
			foot + up * (PORTICO_H - 1.1),
			1.35,
			STONE,
			M.Concrete,
			parent
		)
		Kit.detail(
			Kit.disc(
				"ColumnNeck",
				CFrame.new(foot + up * (PORTICO_H - 1.2)),
				1.55,
				0.2,
				STONE,
				M.Concrete,
				parent
			)
		)
		Kit.detail(
			Kit.disc(
				"Echinus",
				CFrame.new(foot + up * (PORTICO_H - 0.8)),
				1.9,
				0.4,
				STONE,
				M.Concrete,
				parent
			)
		)
		Kit.part(
			"Abacus",
			V(2.1, 0.4, 2.1),
			CFrame.new(foot + up * (PORTICO_H - 0.4)),
			STONE,
			M.Concrete,
			parent
		)
	end
	for _, x in { -9, 9 } do
		Kit.part(
			"Pilaster",
			V(1.4, PORTICO_H, 0.4),
			place(V(x, L1 + PORTICO_H / 2, HALF_D + 0.2)),
			STONE,
			M.Concrete,
			parent
		)
	end
	-- Entablature, roof, cornice, and a balustrade on top nobody can reach.
	Kit.part(
		"Entablature",
		V(PORTICO_X * 2 + 1, 1.4, 1.6),
		place(V(0, beamY + 0.7, colZ)),
		STONE,
		M.Concrete,
		parent
	)
	for _, sx in { -1, 1 } do
		Kit.part(
			"Entablature",
			V(1.58, 1.38, PORTICO_D - 1.6),
			place(V(sx * 9, beamY + 0.7, HALF_D + (PORTICO_D - 1.6) / 2)),
			STONE,
			M.Concrete,
			parent
		)
	end
	local roofY = beamY + 1.4
	Kit.part(
		"PorticoRoof",
		V(PORTICO_X * 2 + 1.6, 0.8, PORTICO_D + 0.8),
		place(V(0, roofY + 0.4, HALF_D + PORTICO_D / 2 + 0.4)),
		ROOF,
		M.Slate,
		parent
	)
	Kit.detail(
		Kit.rod(
			"PorticoMoulding",
			place(V(-PORTICO_X - 0.8, roofY + 0.05, PORTICO_Z + 0.8)).Position,
			place(V(PORTICO_X + 0.8, roofY + 0.05, PORTICO_Z + 0.8)).Position,
			0.45,
			STONE,
			M.Concrete,
			parent
		)
	)
	for _, run in
		{
			{ axis = "X", fixed = PORTICO_Z + 0.2, from = -PORTICO_X, to = PORTICO_X },
			{ axis = "Z", fixed = -PORTICO_X + 0.3, from = HALF_D + 0.5, to = PORTICO_Z },
			{ axis = "Z", fixed = PORTICO_X - 0.3, from = HALF_D + 0.5, to = PORTICO_Z },
		}
	do
		Kit.railing("PorticoTop", roofY + 0.8, run, place, parent, 2.6, STONE_DARK)
	end
	-- Iron railings at the portico's open sides and either side of the steps.
	for _, run in
		{
			{ axis = "X", fixed = colZ + 0.2, from = -8.1, to = -5.9 },
			{ axis = "X", fixed = colZ + 0.2, from = 5.9, to = 8.1 },
			{ axis = "Z", fixed = -PORTICO_X + 0.5, from = HALF_D + 0.6, to = colZ - 0.9 },
			{ axis = "Z", fixed = PORTICO_X - 0.5, from = HALF_D + 0.6, to = colZ - 0.9 },
		}
	do
		Kit.railing("Portico", L1, run, place, parent, 3.6, IRON)
	end
end

local function backStoop(place: Place, parent: Instance)
	local halfW = 5
	local outZ = -HALF_D - 6
	local cx = BACK_DOOR_X
	Kit.part(
		"StoopFloor",
		V(halfW * 2, SLAB, 6),
		place(V(cx, L1 - SLAB / 2, -HALF_D - 3)),
		STONE_DARK,
		M.Slate,
		parent
	)
	Kit.part(
		"StoopBase",
		V(halfW * 2 + 0.4, FOUND_H - SLAB, 6.2),
		place(V(cx, GROUND + (FOUND_H - SLAB) / 2, -HALF_D - 3.1)),
		STONE,
		M.Cobblestone,
		parent
	)
	stoneSteps("StoopStep", cx, 5.4, outZ, outZ - 6, 5, place, parent)
	for _, sx in { -1, 1 } do
		Kit.railing(
			"Stoop",
			L1,
			{ axis = "Z", fixed = cx + sx * (halfW - 0.4), from = outZ + 0.3, to = -HALF_D - 0.3 },
			place,
			parent,
			3.6,
			IRON
		)
	end
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

--[[
	Build the villa. `pivot` is where the ground meets the middle of the
	footprint, and the house faces along the pivot's LookVector.
]]
function Villa.build(pivot: CFrame, parent: Instance): Kit.Built
	Kit.reset(4417)
	local place = Kit.placer(pivot, FOUND_H)

	local model = Instance.new("Model")
	model.Name = "Villa"
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

	--[[
		Hang a door in an opening, with its casing. `into` is the way it
		swings open, `hingeToward` the jamb it hangs on.
	]]
	local function hang(
		axis: string,
		fixed: number,
		along: number,
		level: number,
		w: number,
		h: number,
		into: Vector3,
		hingeToward: Vector3,
		thickness: number,
		o: { [string]: any }?
	): Model
		local centre = if axis == "X"
			then V(along, level + h / 2, fixed)
			else V(fixed, level + h / 2, along)
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
			color = opts.color,
			panel = opts.panel,
			style = opts.style,
			thickness = opts.leaf,
			startAngle = opts.ajar,
			name = opts.name,
		})
	end

	--------------------------------------------------------------------------
	-- Floors, landings, the roof deck
	--------------------------------------------------------------------------

	Kit.slabWithHoles(
		"GroundFloor",
		L1,
		SLAB,
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
	local bOpening: Hole = { x0 = WELL, x1 = HALL_X - PART_T / 2, z0 = LAND_Z, z1 = FOOT_Z }
	Kit.slabWithHoles(
		"FirstFloor",
		L2,
		SLAB,
		-IN_X,
		IN_X,
		-IN_Z,
		IN_Z,
		{ bOpening },
		C.FLOOR,
		M.WoodPlanks,
		place,
		interior
	)
	Kit.slabWithHoles(
		"Roof",
		L3,
		SLAB,
		-IN_X,
		IN_X,
		-IN_Z,
		IN_Z,
		{ bOpening },
		DECK,
		M.WoodPlanks,
		place,
		shell
	)
	for _, y in { L1 + HALF_RISE, L2 + HALF_RISE } do
		local x0, x1 = -HALL_X + PART_T / 2, HALL_X - PART_T / 2
		Kit.part(
			"StairLanding",
			V(x1 - x0, SLAB, LAND_Z + IN_Z),
			place(V(0, y - SLAB / 2, (LAND_Z - IN_Z) / 2)),
			C.FLOOR,
			M.WoodPlanks,
			interior
		)
	end

	-- The hall's floor: black and oxblood tiles in a chequer, as far back as
	-- the foot of the stairs.
	do
		local x0, x1 = -HALL_X + PART_T / 2 + 0.1, HALL_X - PART_T / 2 - 0.1
		local z0, z1 = FOOT_Z + 0.3, IN_Z - 0.1
		local nx, nz = 6, 12
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local w, d = (x1 - x0) / nx, (z1 - z0) / nz
				Kit.detail(
					Kit.part(
						"Tile",
						V(w - 0.04, 0.06, d - 0.04),
						place(V(x0 + w * (i + 0.5), L1 + 0.03, z0 + d * (j + 0.5))),
						Kit.weathered(
							if (i + j) % 2 == 0 then rgb(34, 30, 28) else rgb(66, 36, 30),
							0.06
						),
						M.CeramicTiles,
						interior
					)
				).CastShadow =
					true
			end
		end
		-- Flags in the kitchen, tiles in the bathroom.
		Kit.detail(
			Kit.part(
				"Flags",
				V(IN_X - HALL_X - 0.4, 0.06, IN_Z + CROSS_Z - 0.4),
				place(V(-(IN_X + HALL_X + 0.4) / 2, L1 + 0.03, (-IN_Z + CROSS_Z - 0.4) / 2)),
				C.SLATE,
				M.Slate,
				interior
			)
		).CastShadow =
			true
		Kit.detail(
			Kit.part(
				"Tiles",
				V(IN_X - HALL_X - 0.4, 0.06, IN_Z + BATH_Z - 0.4),
				place(V((IN_X + HALL_X + 0.4) / 2, L2 + 0.03, (-IN_Z + BATH_Z - 0.4) / 2)),
				C.TILE_DARK,
				M.CeramicTiles,
				interior
			)
		).CastShadow =
			true
	end

	--------------------------------------------------------------------------
	-- Outside walls
	--------------------------------------------------------------------------

	foundation(place, shell)
	exterior(
		"Front",
		"X",
		WALL_Z,
		-IN_X,
		IN_X,
		1,
		bands({
			barred(-24, LOW_SILL, 4, LOW_H, "arch"),
			barred(-15, LOW_SILL, 4, LOW_H, "arch"),
			-- The door's own hood is hidden under the portico's roof.
			doorway(0, L1, DOOR_W, DOOR_H, "flat"),
			barred(15, LOW_SILL, 4, LOW_H, "arch"),
			barred(24, LOW_SILL, 4, LOW_H, "arch"),
		}, {
			barred(-24, UP_SILL, 4, UP_H, "segment"),
			barred(-15, UP_SILL, 4, UP_H, "segment"),
			barred(0, UP_SILL, 5, UP_H, "segment"),
			barred(15, UP_SILL, 4, UP_H, "segment"),
			barred(24, UP_SILL, 4, UP_H, "segment"),
		}),
		place,
		shell
	)
	exterior(
		"Back",
		"X",
		-WALL_Z,
		-IN_X,
		IN_X,
		-1,
		bands({
			-- The kitchen's window sits above its worktop.
			barred(-24, KITCHEN_SILL, 4, LOW_SILL + LOW_H - KITCHEN_SILL, "flat"),
			doorway(BACK_DOOR_X, L1, BACK_DOOR_W, BACK_DOOR_H, "flat"),
			-- Small windows on the stair's half landings. The upper one is
			-- tucked right under the frieze and has no hood.
			barred(0, L1 + HALF_RISE + 1.2, 4, 4.1, "flat"),
			barred(24, LOW_SILL, 4, LOW_H, "flat"),
		}, {
			barred(-24, UP_SILL, 4, UP_H, "flat"),
			barred(0, L2 + HALF_RISE + 1.0, 4, 2.9),
			barred(22, UP_SILL + 1.8, 3, UP_H - 1.8, "flat"),
		}),
		place,
		shell
	)
	for _, side in { -1, 1 } do
		exterior(
			if side < 0 then "Left" else "Right",
			"Z",
			side * WALL_X,
			-HALF_D,
			HALF_D,
			side,
			bands({
				barred(21, LOW_SILL, 4, LOW_H, "flat"),
				barred(7, LOW_SILL, 4, LOW_H, "flat"),
				if side < 0
					then barred(-3, KITCHEN_SILL, 4, LOW_SILL + LOW_H - KITCHEN_SILL, "flat")
					else barred(-3, LOW_SILL, 4, LOW_H, "flat"),
				if side < 0
					then barred(-21, KITCHEN_SILL, 4, LOW_SILL + LOW_H - KITCHEN_SILL, "flat")
					else barred(-21, LOW_SILL, 4, LOW_H, "flat"),
			}, {
				barred(21, UP_SILL, 4, UP_H, "flat"),
				barred(7, UP_SILL, 4, UP_H, "flat"),
				barred(-3, UP_SILL, 4, UP_H, "flat"),
				if side < 0
					then barred(-21, UP_SILL, 4, UP_H, "flat")
					else barred(-21, UP_SILL + 1.8, 3, UP_H - 1.8, "flat"),
			}),
			place,
			shell,
			WALL_T
		)
	end
	quoins(place, shell)
	stringCourse(place, shell)
	cornice(place, shell)

	-- The two ways in and out: a pair of doors under the portico, and the
	-- kitchen door at the back.
	do
		local centre = V(0, L1 + DOOR_H / 2, WALL_Z)
		local frame = place(centre) * CFrame.new(Vector3.zero, BACK)
		Kit.window(frame, DOOR_W, DOOR_H, { style = "open", thickness = WALL_T, parent = shell })
		for _, side in { -1, 1 } do
			-- The frame looks into the hall, so its +X is the house's +X and
			-- each leaf hangs on its outer jamb.
			local leafFrame = frame * CFrame.new(side * DOOR_W / 4, 0, 0)
			local leaf = Kit.door(leafFrame, DOOR_W / 2, DOOR_H, {
				parent = doors,
				hinge = side,
				swing = 1,
				gap = 0.06,
				color = FRONT_DOOR,
				panel = rgb(32, 22, 19),
				thickness = 0.45,
				name = if side < 0 then "FrontDoorLeft" else "FrontDoorRight",
			})
			-- A knocker on each leaf: a lion's-head boss and a heavy ring.
			local boss = leafFrame * CFrame.new(-side * 0.4, 0.8, 0.45)
			Kit.detail(Kit.ball("KnockerBoss", boss.Position, 0.5, C.BRASS, M.Metal, leaf))
			local prev: Vector3? = nil
			for k = 0, 10 do
				local a = k * math.pi * 2 / 10
				local p = (boss * CFrame.new(math.sin(a) * 0.45, -0.55 + math.cos(a) * 0.45, 0.05)).Position
				if prev then
					Kit.detail(Kit.rod("KnockerRing", prev, p, 0.1, C.BRASS, M.Metal, leaf))
				end
				prev = p
			end
		end
	end
	hang("X", -WALL_Z, BACK_DOOR_X, L1, BACK_DOOR_W, BACK_DOOR_H, FRONT, RIGHT, WALL_T, {
		outside = true,
		casing = C.FRAME,
		style = "plank",
		color = C.OAK,
		panel = C.WALNUT,
		gap = 0.08,
		name = "KitchenDoor",
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
		bottom: number,
		top: number,
		openings: { Opening },
		insetEnds: number?
	)
		Kit.wall({
			name = name,
			axis = axis,
			fixed = fixed,
			from = from,
			to = to,
			bottom = bottom,
			top = top,
			thickness = PART_T,
			openings = openings,
			color = C.WAINSCOT,
			material = M.WoodPlanks,
			place = place,
			parent = interior,
			rooms = ROOMS,
			insetEnds = insetEnds,
			weather = 0.05,
		})
	end
	local function doorHole(at: number, level: number, w: number?, h: number?): Opening
		return { at = at, width = w or IN_DOOR_W, sill = level, head = level + (h or IN_DOOR_H) }
	end

	for _, level in { L1, L2 } do
		local up = level == L2
		local leftDoor = if up then -27.5 else -20
		for _, side in { -1, 1 } do
			partition(
				"HallWall",
				"Z",
				side * HALL_X,
				-IN_Z,
				IN_Z,
				level,
				level + STOREY,
				{ doorHole(14, level), doorHole(-3, level) }
			)
			partition(
				"CrossWall",
				"X",
				CROSS_Z,
				if side < 0 then -IN_X else HALL_X + PART_T / 2,
				if side < 0 then -HALL_X - PART_T / 2 else IN_X,
				level,
				level + STOREY,
				{ doorHole(if side < 0 then leftDoor else 20, level) },
				PART_T / 2
			)
		end
		-- Off the hall: a door into each room.
		hang("Z", -HALL_X, 14, level, IN_DOOR_W, IN_DOOR_H, LEFT, FRONT, PART_T, {
			name = if up then "MasterDoor" else "ParlourDoor",
		})
		hang("Z", -HALL_X, -3, level, IN_DOOR_W, IN_DOOR_H, LEFT, BACK, PART_T, {
			name = if up then "BedroomDoor" else "KitchenHallDoor",
			ajar = if up then nil else 30,
		})
		hang("Z", HALL_X, 14, level, IN_DOOR_W, IN_DOOR_H, RIGHT, FRONT, PART_T, {
			name = if up then "NurseryDoor" else "DiningDoor",
			ajar = if up then 12 else nil,
		})
		hang("Z", HALL_X, -3, level, IN_DOOR_W, IN_DOOR_H, RIGHT, BACK, PART_T, {
			name = if up then "SewingDoor" else "LibraryDoor",
		})
		-- Between the front and back rooms each side.
		hang("X", CROSS_Z, leftDoor, level, IN_DOOR_W, IN_DOOR_H, BACK, RIGHT, PART_T, {
			name = if up then "MasterBedroomDoor" else "PantryDoor",
		})
		hang("X", CROSS_Z, 20, level, IN_DOOR_W, IN_DOOR_H, BACK, LEFT, PART_T, {
			name = if up then "NurserySewingDoor" else "DiningLibraryDoor",
		})
	end

	-- The bathroom, behind the sewing room.
	partition(
		"BathWall",
		"X",
		BATH_Z,
		HALL_X + PART_T / 2,
		IN_X,
		L2,
		L2 + STOREY,
		{ doorHole(20, L2) },
		PART_T / 2
	)
	hang(
		"X",
		BATH_Z,
		20,
		L2,
		IN_DOOR_W,
		IN_DOOR_H,
		BACK,
		LEFT,
		PART_T,
		{ name = "BathroomDoor", ajar = 25 }
	)

	--------------------------------------------------------------------------
	-- Stairs, cupboards under the landings
	--------------------------------------------------------------------------

	local tread, rail = C.WALNUT, C.RAIL
	type Flight = { name: string, bottom: Vector3, top: Vector3 }
	local flights: { Flight } = {
		{
			name = "FlightA",
			bottom = V(-FLIGHT_X, L1, FOOT_Z),
			top = V(-FLIGHT_X, L1 + HALF_RISE, LAND_Z),
		},
		{
			name = "FlightB",
			bottom = V(FLIGHT_X, L1 + HALF_RISE, LAND_Z),
			top = V(FLIGHT_X, L2, FOOT_Z),
		},
		{
			name = "FlightC",
			bottom = V(-FLIGHT_X, L2, FOOT_Z),
			top = V(-FLIGHT_X, L2 + HALF_RISE, LAND_Z),
		},
		{
			name = "FlightD",
			bottom = V(FLIGHT_X, L2 + HALF_RISE, LAND_Z),
			top = V(FLIGHT_X, L3, FOOT_Z),
		},
	}
	for _, f in flights do
		-- The open side (+1, over the well) gets a balustrade; the side
		-- against the stair hall's wall a rail on brackets.
		Kit.staircase(f.name, f.bottom, f.top, STAIR_W, STEPS, place, interior, {
			rails = { 1 },
			wallRails = { -1 },
			treadColor = tread,
			railColor = rail,
			rotten = 0.08,
		})
	end
	for _, y in { L1 + HALF_RISE, L2 + HALF_RISE } do
		Kit.railing(
			"Landing",
			y,
			{ axis = "X", fixed = LAND_Z - 0.3, from = -WELL - 0.1, to = WELL + 0.1 },
			place,
			interior,
			nil,
			rail
		)
	end
	-- Along the open side of the flight coming up from below, on each floor
	-- it arrives at: the first floor, and the belvedere.
	for _, y in { L2, L3 } do
		Kit.railing(
			"Gallery",
			y,
			{ axis = "Z", fixed = WELL - 0.3, from = LAND_Z, to = FOOT_Z - 1.0 },
			place,
			interior,
			nil,
			rail
		)
	end
	Kit.railing(
		"Gallery",
		L3,
		{ axis = "X", fixed = LAND_Z - 0.3, from = WELL - 0.3, to = HALL_X - PART_T / 2 },
		place,
		interior,
		nil,
		rail
	)

	-- Under the lower landing: a cupboard as wide as the stair hall, running
	-- on under the second flight, behind a small door between the flights.
	local underH = HALF_RISE - SLAB
	partition(
		"UnderLandingWall",
		"X",
		LAND_Z,
		-HALL_X + PART_T / 2,
		WELL,
		L1,
		underH,
		{ doorHole(0, L1, 3.4, underH - 0.5) }
	)
	hang("X", LAND_Z, 0, L1, 3.4, underH - 0.5, BACK, LEFT, PART_T, {
		style = "plank",
		color = C.WALNUT,
		panel = C.OAK,
		name = "UnderStairDoor",
	})
	hide(
		Kit.hideVolume(
			"UnderStairHidingVolume",
			place(V(0, L1 + 2.8, (LAND_Z - IN_Z) / 2)),
			V(15, 5, 4.4),
			"Cupboard",
			1,
			interior
		)
	)
	-- The second flight's underside is closed off from the hall in front.
	partition("UnderFlightWall", "X", FOOT_Z, WELL, HALL_X - PART_T / 2, L1, L2 - SLAB, {})
	-- Under flight B, on its open side: a panel up to the landing's
	-- underside, and a triangle above it following the flight.
	local panelX = WELL + PART_T / 2 - 0.4
	partition("Spandrel", "Z", panelX, LAND_Z, FOOT_Z, L1, underH, {})
	Kit.triangle(
		"Spandrel",
		place(V(panelX, underH, LAND_Z)).Position,
		place(V(panelX, underH, FOOT_Z)).Position,
		place(V(panelX, L2 - 1.0, FOOT_Z)).Position,
		PART_T,
		C.WAINSCOT,
		M.WoodPlanks,
		interior
	)
	-- Under flights A and C: closed dead space, a triangle on the open side.
	for _, level in { L1, L2 } do
		local zFloor = FOOT_Z - 1.0 / (HALF_RISE / (FOOT_Z - LAND_Z))
		Kit.triangle(
			"Spandrel",
			place(V(-panelX, level, zFloor)).Position,
			place(V(-panelX, level, LAND_Z)).Position,
			place(V(-panelX, level + underH, LAND_Z)).Position,
			PART_T,
			C.WAINSCOT,
			M.WoodPlanks,
			interior
		)
	end

	-- Under the upper landing: the linen cupboard, off the first-floor hall.
	local linenZ = LAND_Z - PART_T / 2
	partition(
		"LinenWall",
		"X",
		linenZ,
		-HALL_X + PART_T / 2,
		HALL_X - PART_T / 2,
		L2,
		L2 + underH,
		{ doorHole(0, L2, 3.4, underH - 0.5) }
	)
	hang("X", linenZ, 0, L2, 3.4, underH - 0.5, BACK, RIGHT, PART_T, {
		style = "cabinet",
		name = "LinenCupboardDoor",
	})
	hide(
		Kit.hideVolume(
			"LinenHidingVolume",
			place(V(0, L2 + 2.8, (linenZ - IN_Z) / 2)),
			V(15, 5, 3.6),
			"Cupboard",
			2,
			interior
		)
	)

	--------------------------------------------------------------------------
	-- Chimneys
	--------------------------------------------------------------------------

	chimney(place, shell, -1, FRONT_STACK_Z, {
		{ level = L1, w = 4.4, h = 4.2 },
		{ level = L2, w = 4.0, h = 4.0 },
	})
	chimney(place, shell, -1, BACK_STACK_Z, {
		-- No deeper than the breast allows: the wall's own paper runs
		-- behind the stack, and a deeper firebox would open onto it.
		{ level = L1, w = 5.0, h = 5.0, grate = false, depth = 2.2 },
		{ level = L2, w = 3.6, h = 3.6 },
	})
	chimney(place, shell, 1, FRONT_STACK_Z, {
		{ level = L1, w = 4.4, h = 4.2 },
		{ level = L2, w = 3.6, h = 3.8, guard = true },
	})
	chimney(place, shell, 1, BACK_STACK_Z, {
		{ level = L1, w = 4.4, h = 4.2 },
		{ level = L2, w = 3.2, h = 3.2 },
	})

	--------------------------------------------------------------------------
	-- The roof and the belvedere
	--------------------------------------------------------------------------

	parapet(place, shell)
	fence(place, shell)
	do
		local x = BELV_X
		local belv = { bottom = L3, top = BELV_TOP }
		-- The belvedere's front: its door out onto the roof, and a window.
		exterior("Belvedere", "X", BELV_Z1, -x - WALL_T / 2, x + WALL_T / 2, 1, {
			{
				bottom = belv.bottom,
				top = belv.top,
				windows = {
					doorway(-3, L3, 4.5, 8.5, "flat"),
					unbarred(4.5, L3 + 3, 4, 5.5, "flat"),
				},
			},
		}, place, shell)
		-- Its sides, over the roof.
		for _, side in { -1, 1 } do
			exterior("Belvedere", "Z", side * x, -IN_Z, BELV_Z1 - WALL_T / 2, side, {
				{
					bottom = belv.bottom,
					top = belv.top,
					windows = {
						unbarred(-7, L3 + 3, 4, 5.5, "flat"),
						unbarred(-17, L3 + 3, 4, 5.5, "flat"),
					},
				},
			}, place, shell)
		end
		-- Its back is the house's back wall carried up, over a sheer drop:
		-- barred like every window that looks out of the house.
		exterior("Belvedere", "X", -WALL_Z, -x - WALL_T / 2, x + WALL_T / 2, -1, {
			{
				bottom = belv.bottom,
				top = belv.top,
				windows = { barred(0, L3 + 3, 4, 5.5, "flat") },
			},
		}, place, shell)
		hang("X", BELV_Z1, -3, L3, 4.5, 8.5, FRONT, LEFT, WALL_T, {
			outside = true,
			casing = C.FRAME,
			color = C.DOOR,
			gap = 0.08,
			name = "RoofDoor",
		})
		belvedereRoof(place, shell)
	end

	--------------------------------------------------------------------------
	-- Portico and stoop
	--------------------------------------------------------------------------

	portico(place, shell)
	backStoop(place, shell)

	--------------------------------------------------------------------------
	-- Furniture
	--------------------------------------------------------------------------

	local LINING = 0.3
	local function against(m: Model): Model
		return Furnish.backTo(m, LINING)
	end
	local function curtainsAt(
		axis: string,
		fixed: number,
		along: number,
		head: number,
		w: number,
		into: Vector3,
		colour: Color3?
	)
		local p = if axis == "X" then V(along, head, fixed) else V(fixed, head, along)
		Decor.curtains(
			place(p) * CFrame.new(Vector3.zero, into),
			furniture,
			{ width = w, drop = head - 0.6 - (if head > L2 then L2 else L1), color = colour }
		)
	end
	local HX = HALL_X + PART_T / 2 -- a hall wall's room-side face

	-- The hall: a stand by the door with a coat still on it, a clock, a
	-- console and mirror, a bench, portraits up the stair.
	against(Furnish.hallStand(spot(-HALL_X + PART_T / 2, L1, 21.5, RIGHT), furniture))
	against(Furnish.clock(spot(-HALL_X + PART_T / 2, L1, 5.5, RIGHT), furniture))
	local console = against(
		Furnish.sideTable(
			spot(HALL_X - PART_T / 2, L1, 5.5, LEFT),
			furniture,
			{ width = 3.2, height = 3.2 }
		)
	)
	Decor.candelabra(console.WorldPivot * CFrame.new(0, 3.2, 0), furniture, { height = 1.6 })
	Decor.mirror(
		spot(HALL_X - PART_T / 2 - 0.1, L1 + 7.4, 5.5, LEFT),
		furniture,
		{ width = 2.6, height = 3.6 }
	)
	against(
		Furnish.bench(
			spot(HALL_X - PART_T / 2, L1, 21, LEFT),
			furniture,
			{ length = 5, wood = C.WALNUT }
		)
	)
	against(
		Furnish.bust(
			spot(-HALL_X + PART_T / 2, L1, -6.2, RIGHT),
			furniture,
			{ stone = BLACK_MARBLE }
		)
	)
	Decor.chandelier(spot(0, L1 + STOREY, 14), furniture, { drop = 4, arms = 6 })
	Decor.chandelier(spot(0, L1 + STOREY, 1), furniture, { drop = 3.5, arms = 5 })
	Decor.painting(
		spot(-HALL_X + PART_T / 2 + 0.1, L1 + 8.2, 9, RIGHT),
		furniture,
		{ width = 3, height = 4.2 }
	)
	Decor.painting(
		spot(HALL_X - PART_T / 2 - 0.1, L1 + 8, 21, LEFT),
		furniture,
		{ subject = "landscape", width = 4.4, height = 3, tilt = 3 }
	)
	-- Up the first flight and on the half landing, a family nobody
	-- remembers.
	for i, z in { -11.5, -15.5 } do
		local t = (FOOT_Z - z) / (FOOT_Z - LAND_Z)
		Decor.painting(
			spot(-HALL_X + PART_T / 2 + 0.1, L1 + t * HALF_RISE + 5.2, z, RIGHT),
			furniture,
			{ width = 2.4, height = 3.2, tilt = if i == 2 then -5 else 0 }
		)
	end
	for _, x in { -5.5, 5.5 } do
		Decor.painting(
			spot(x, L1 + HALF_RISE + 4.2, -IN_Z + 0.1, FRONT),
			furniture,
			{ width = 2.2, height = 3 }
		)
	end

	-- The parlour: a séance that was never finished. A round table with the
	-- board on it and the chairs pushed back, the sitting group round the
	-- fire, the piano against the hall wall.
	Decor.rug(
		spot(-20, L1, 14, BACK),
		furniture,
		{ width = 13, length = 17, color = rgb(54, 32, 38) }
	)
	local seance = V(-18.5, L1, 19.5)
	Furnish.roundTable(
		spot(seance.X, L1, seance.Z),
		furniture,
		{ diameter = 5, height = 3.1, name = "SeanceTable" }
	)
	Decor.spiritBoard(spot(seance.X, L1 + 3.1, seance.Z, V(0.2, 0, -1)), furniture)
	Decor.candelabra(spot(seance.X - 1.4, L1 + 3.1, seance.Z + 1.2), furniture, { height = 1.4 })
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.3
		local r = if k == 2 then 4.4 else 3.5
		local p = seance + V(math.cos(a) * r, 0, math.sin(a) * r)
		if k == 4 then
			Furnish.toppledChair(
				spot(p.X, L1, p.Z, V(-math.cos(a + 0.4), 0, -math.sin(a + 0.4))),
				furniture,
				{ seat = C.VELVET_DARK }
			)
		elseif p.Z < IN_Z - 1.6 then
			Furnish.diningChair(
				spot(p.X, L1, p.Z, V(-math.cos(a), 0, -math.sin(a))),
				furniture,
				{ seat = C.VELVET_DARK }
			)
		end
	end
	Furnish.armchair(
		spot(-25.2, L1, 8.6, FRONT + LEFT * 0.4),
		furniture,
		{ cover = C.VELVET_DARK, material = M.Fabric }
	)
	Furnish.sofa(
		spot(-20.5, L1, 9.8, LEFT + BACK * 0.15),
		furniture,
		{ cover = rgb(58, 40, 44), material = M.Fabric }
	)
	against(Furnish.piano(spot(-HX, L1, 6.8, LEFT), furniture))
	against(Furnish.bookcase(spot(-HX, L1, 21.8, LEFT), furniture, { width = 4.4, sparse = true }))
	Furnish.doll(spot(-20.4, L1 + 1.95, 9.2, LEFT), furniture, { dress = C.VELVET })
	for _, x in { -24, -15 } do
		curtainsAt("X", IN_Z, x, L1 + 11.8, 4, BACK, C.VELVET_DARK)
	end
	for _, z in { 21, 7 } do
		curtainsAt("Z", -IN_X, z, L1 + 11.8, 4, RIGHT, C.VELVET_DARK)
	end
	Decor.painting(
		spot(-HALF_W + STACK_D / 2 + 0.1, L1 + 8.2, FRONT_STACK_Z, RIGHT),
		furniture,
		{ width = 3.2, height = 4.2 }
	)

	-- The kitchen: the range in the hearth, a table to hide under, the
	-- sink under the window, the dresser, a hatch to a cellar that isn't.
	Furnish.backTo(
		Furnish.range(
			spot(-HALF_W + STACK_D / 2 - 2.2 + 0.1, L1, BACK_STACK_Z, RIGHT),
			furniture,
			{ width = 4.6, depth = 2.2, pipeTop = 5.0 }
		),
		0.05
	)
	local _, underTable = Furnish.workTable(spot(-20.5, L1, -10, RIGHT), furniture)
	hide(underTable)
	Furnish.stool(spot(-17.5, L1, -7), furniture)
	Furnish.stool(spot(-23.8, L1, -12.8), furniture)
	against(Furnish.counter(spot(-IN_X, L1, -21, RIGHT), furniture, { width = 6, sink = true }))
	against(Furnish.counter(spot(-23.6, L1, -IN_Z, FRONT), furniture, { width = 7.4 }))
	against(Furnish.hutch(spot(-HX, L1, -14, LEFT), furniture))
	-- Clear of the back door's swing and the hall door's.
	Furnish.barrel(spot(-12.2, L1, 0.2), furniture)
	Furnish.barrel(spot(-14.8, L1, 0.3), furniture, { height = 2.6, diameter = 2 })
	Furnish.crate(spot(-28.5, L1, 0.2, BACK), furniture, { size = V(2.8, 2.2, 2.4) })
	Decor.hatch(spot(-26, L1, -4.5), furniture)
	Decor.wallShelf(spot(-IN_X + 0.1, L1 + 6.2, -7.3, RIGHT), furniture, { width = 3 })
	Decor.wallShelf(
		spot(-13.5, L1 + 6.6, CROSS_Z - PART_T / 2 - 0.1, BACK),
		furniture,
		{ width = 3.6 }
	)

	-- The dining room: a long table under a dead chandelier, laid for eight,
	-- one place's chair on its back.
	Decor.rug(
		spot(19.5, L1, 13.5, BACK),
		furniture,
		{ width = 11, length = 17, color = rgb(58, 26, 24) }
	)
	local _, underDining = Furnish.diningTable(spot(19.5, L1, 13.5, RIGHT), furniture, {
		name = "DiningTable",
		length = 12,
		width = 4.6,
		cloth = C.VELVET_DARK,
		floor = 1,
	})
	hide(underDining)
	local dTop = L1 + 4.0 + 0.06
	for i = 0, 3 do
		local z = 13.5 - 4.5 + i * 3
		for _, side in { -1, 1 } do
			local x = 19.5 + side * (4.6 / 2 + 1.6)
			if i == 3 and side == 1 then
				-- Fallen back past the table's end, clear of the hearth.
				Furnish.toppledChair(spot(x + 0.3, L1, z + 1.2, LEFT + BACK * 0.25), furniture)
			else
				Furnish.diningChair(spot(x, L1, z, V(-side, 0, 0)), furniture)
			end
			Decor.placeSetting(
				spot(19.5 + side * (4.6 / 2 - 0.1), dTop, z, V(side, 0, 0)),
				furniture,
				{
					upset = i == 3 and side == 1,
					food = (i + side) % 3 == 0,
				}
			)
		end
	end
	for _, z in { 13.5 - 7.6, 13.5 + 7.6 } do
		Furnish.armchair(
			spot(19.5, L1, z, V(0, 0, 13.5 - z)),
			furniture,
			{ cover = C.VELVET, material = M.Fabric }
		)
	end
	Decor.candelabra(spot(19.5, dTop + 0.08, 12), furniture, { fallen = false })
	Decor.platter(spot(19.5, dTop + 0.08, 15.5), furniture)
	Decor.chandelier(spot(19.5, L1 + STOREY, 13.5), furniture, { drop = 4, arms = 8, radius = 2.4 })
	local board = against(Furnish.sideboard(spot(HX, L1, 21, RIGHT), furniture, { width = 6.4 }))
	Decor.vase(board.WorldPivot * CFrame.new(-1.6, 3.8, 0), furniture)
	against(Furnish.hutch(spot(HX, L1, 6.4, RIGHT), furniture, { width = 6 }))
	for _, x in { 15, 24 } do
		curtainsAt("X", IN_Z, x, L1 + 11.8, 4, BACK)
	end
	for _, z in { 21, 7 } do
		curtainsAt("Z", IN_X, z, L1 + 11.8, 4, LEFT)
	end

	-- The library: shelves on the hall wall and the back wall, a desk, a
	-- chair by the fire, a ladder left against the shelves.
	Decor.rug(
		spot(21, L1, -12, BACK),
		furniture,
		{ width = 12, length = 13, color = rgb(44, 30, 26) }
	)
	for _, z in { -8.8, -14.4, -20 } do
		against(Furnish.bookcase(spot(HX, L1, z, RIGHT), furniture, { width = 5.2, height = 10.5 }))
	end
	against(
		Furnish.bookcase(spot(13.8, L1, -IN_Z, FRONT), furniture, { width = 4.4, height = 10.5 })
	)
	against(
		Furnish.bookcase(
			spot(18.8, L1, -IN_Z, FRONT),
			furniture,
			{ width = 4.4, height = 10.5, sparse = true }
		)
	)
	against(
		Furnish.bookcase(spot(28.6, L1, -IN_Z, FRONT), furniture, { width = 2.8, height = 10.5 })
	)
	Furnish.desk(spot(19.5, L1, -13, RIGHT), furniture)
	Furnish.diningChair(spot(17, L1, -13, RIGHT), furniture, { seat = C.LEATHER })
	Decor.books(spot(19.3, L1 + 3.3, -14.2), furniture, { count = 4 })
	Furnish.armchair(spot(25.5, L1, -7, RIGHT + BACK * 0.6), furniture)
	Furnish.sideTable(spot(25.8, L1, -3.4), furniture, { width = 1.8, height = 2.6 })
	Decor.globe(spot(24.5, L1, -21.5), furniture)
	-- The library ladder: two round rails and rungs, leaning.
	do
		local foot = V(HX + 2.6, L1, -16.5)
		local head = V(HX + 1.0, L1 + 9.6, -16.5)
		for _, dz in { -0.8, 0.8 } do
			Kit.rod(
				"LadderRail",
				place(foot + V(0, 0.1, dz)).Position,
				place(head + V(0, 0, dz)).Position,
				0.24,
				C.OAK,
				M.Wood,
				furniture
			)
		end
		for k = 1, 8 do
			local p = foot:Lerp(head, k / 9)
			Kit.detail(
				Kit.rod(
					"LadderRung",
					place(p + V(0, 0, -0.8)).Position,
					place(p + V(0, 0, 0.8)).Position,
					0.16,
					C.OAK,
					M.Wood,
					furniture
				)
			)
		end
	end
	for _, z in { -3, -21 } do
		curtainsAt("Z", IN_X, z, L1 + 11.8, 4, LEFT, C.VELVET_DARK)
	end

	-- The first-floor hall: a settee under the front window, a chair
	-- turned to face the wall, a table with dead flowers.
	against(
		Furnish.sofa(
			spot(-HALL_X + PART_T / 2, L2, 21, RIGHT),
			furniture,
			{ cover = rgb(56, 42, 36), material = M.Fabric }
		)
	)
	Furnish.rockingChair(spot(4.6, L2, 21.8, FRONT), furniture)
	against(
		Furnish.sideTable(
			spot(HALL_X - PART_T / 2, L2, 7, LEFT),
			furniture,
			{ width = 2.6, height = 3.2 }
		)
	)
	Decor.vase(spot(HALL_X - PART_T / 2 - 1.5, L2 + 3.2, 7), furniture)
	Furnish.diningChair(spot(-6.4, L2, 4, LEFT), furniture, { seat = C.VELVET_DARK })
	Decor.chandelier(spot(0, L2 + STOREY, 10), furniture, { drop = 3.4, arms = 5 })
	Decor.rug(spot(0, L2, 7, BACK), furniture, { width = 5, length = 26, color = rgb(52, 30, 26) })
	curtainsAt("X", IN_Z, 0, L2 + 12.3, 5, BACK, C.VELVET_DARK)
	Decor.painting(
		spot(HALL_X - PART_T / 2 - 0.1, L2 + 8, 20, LEFT),
		furniture,
		{ width = 3.2, height = 4.4, tilt = -4 }
	)

	-- The master bedroom: a four-poster facing the windows, a wardrobe, the
	-- dressing table with its cracked mirror, a rocking chair by the fire.
	Decor.rug(
		spot(-18, L2, 11, BACK),
		furniture,
		{ width = 12, length = 13, color = rgb(62, 36, 32) }
	)
	local bed, underBed =
		Furnish.bed(spot(-17, L2, CROSS_Z + PART_T / 2, FRONT), furniture, { floor = 2 })
	against(bed)
	hide(underBed)
	against(Furnish.nightstand(spot(-22.6, L2, CROSS_Z + PART_T / 2, FRONT), furniture))
	against(Furnish.nightstand(spot(-11.4, L2, CROSS_Z + PART_T / 2, FRONT), furniture))
	local wardrobe, masterWardrobe =
		Furnish.wardrobe(spot(-HX, L2, 21.2, LEFT), furniture, { floor = 2 })
	against(wardrobe)
	hide(masterWardrobe)
	against(Furnish.dressingTable(spot(-HX, L2, 7.6, LEFT), furniture))
	Furnish.stool(spot(-13.8, L2, 7.6), furniture)
	Furnish.rockingChair(spot(-24.6, L2, 18.6, LEFT + BACK * 0.4), furniture)
	Furnish.doll(
		spot(-24.7, L2 + 2.5, 18.7, LEFT + BACK * 0.4),
		furniture,
		{ dress = C.VELVET_DARK }
	)
	for _, x in { -24, -15 } do
		curtainsAt("X", IN_Z, x, L2 + 11.8, 4, BACK, C.VELVET_DARK)
	end
	for _, z in { 21, 7 } do
		curtainsAt("Z", -IN_X, z, L2 + 11.8, 4, RIGHT, C.VELVET_DARK)
	end

	-- The second bedroom: an iron bed against the back wall, a wardrobe, a
	-- washstand, a trunk at the bed's foot.
	local ironBed, underIron =
		Furnish.ironBed(spot(-18, L2, -IN_Z, FRONT), furniture, { floor = 2 })
	against(ironBed)
	hide(underIron)
	-- The wardrobe against the cross wall, where its doors open into the
	-- middle of the room rather than across the bed.
	local w2, bedroomWardrobe = Furnish.wardrobe(
		spot(-20, L2, CROSS_Z - PART_T / 2, BACK),
		furniture,
		{ floor = 2, wood = C.WALNUT }
	)
	against(w2)
	hide(bedroomWardrobe)
	against(Furnish.washstand(spot(-HX, L2, -10, LEFT), furniture))
	Furnish.trunk(spot(-18, L2, -13.2, FRONT), furniture)
	local stand = against(Furnish.nightstand(spot(-13.6, L2, -IN_Z, FRONT), furniture))
	Decor.lantern(stand.WorldPivot * CFrame.new(0, 3.18, 0), furniture)
	Furnish.diningChair(spot(-24, L2, -6.5, RIGHT + FRONT * 0.5), furniture, { seat = C.CLOTH })
	for _, z in { -3, -21 } do
		curtainsAt("Z", -IN_X, z, L2 + 11.8, 4, RIGHT)
	end

	-- The nursery: a cot by the guarded fire, a small iron bed, a rocking
	-- horse, a tea party of dolls at a little table, a toy cupboard big
	-- enough to hide in, and a row of dolls along the wall watching the
	-- door.
	Decor.rug(
		spot(19.5, L2, 13.5, BACK),
		furniture,
		{ width = 11, length = 12, color = rgb(58, 42, 40) }
	)
	Furnish.crib(spot(24.5, L2, 20.5, LEFT), furniture)
	local cot, underCot = Furnish.ironBed(
		spot(HX, L2, 6.8, RIGHT),
		furniture,
		{ width = 4, length = 7.4, floor = 2, name = "SmallBed" }
	)
	against(cot)
	hide(underCot)
	Furnish.rockingHorse(spot(15.5, L2, 21, BACK + RIGHT * 0.5), furniture)
	local party = V(19.5, L2, 12.5)
	Furnish.roundTable(
		spot(party.X, L2, party.Z),
		furniture,
		{ diameter = 2.6, height = 1.8, name = "TeaTable" }
	)
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.4
		local p = party + V(math.cos(a) * 1.9, 0, math.sin(a) * 1.9)
		Furnish.stool(spot(p.X, L2, p.Z), furniture, { height = 1.2 })
		if k ~= 1 then
			Furnish.doll(
				spot(p.X, L2 + 1.25, p.Z, V(-math.cos(a), 0, -math.sin(a))),
				furniture,
				{ dress = if k == 0 then C.VELVET else C.CLOTH }
			)
		end
	end
	for k = 0, 4 do
		Furnish.doll(
			spot(HX + 0.7, L2, 17.4 + k * 1.2, RIGHT),
			furniture,
			{ dress = if k % 2 == 0 then C.VELVET_DARK else C.LINEN }
		)
	end
	local toys, toyCupboard =
		Furnish.wardrobe(spot(26.5, L2, CROSS_Z + PART_T / 2, FRONT), furniture, {
			name = "ToyCupboard",
			floor = 2,
			wood = C.PINE,
			width = 5.4,
			height = 8.6,
		})
	against(toys)
	hide(toyCupboard)
	Furnish.trunk(spot(20.2, L2, 6.2, FRONT), furniture, { cover = rgb(64, 30, 28) })
	for _, x in { 15, 24 } do
		curtainsAt("X", IN_Z, x, L2 + 11.8, 4, BACK, rgb(64, 44, 42))
	end

	-- The sewing room: a treadle machine against the bathroom wall, dress
	-- forms, a table of cut cloth, all clear of the one window.
	against(Furnish.sewingMachine(spot(27.5, L2, BATH_Z + PART_T / 2, FRONT), furniture))
	Furnish.diningChair(spot(27.5, L2, -2.6, BACK), furniture, { seat = C.CLOTH })
	Furnish.mannequin(spot(21.5, L2, -4.5, RIGHT), furniture, { dress = C.VELVET_DARK })
	Furnish.mannequin(spot(14.5, L2, -1, BACK + RIGHT * 0.4), furniture, { dress = C.CLOTH })
	local cutting = against(
		Furnish.sideTable(
			spot(26, L2, CROSS_Z - PART_T / 2, BACK),
			furniture,
			{ width = 4, height = 3 }
		)
	)
	Kit.soft(
		Kit.part(
			"CutCloth",
			V(3.2, 0.06, 1.6),
			cutting.WorldPivot * CFrame.new(0.2, 3.03, 0.1) * CFrame.Angles(0, 0.2, 0),
			C.VELVET,
			M.Fabric,
			furniture
		)
	)
	curtainsAt("Z", IN_X, -3, L2 + 11.8, 3.4, LEFT)

	-- The bathroom: a claw-foot bath, the high-cistern closet, a washstand.
	against(Furnish.bathtub(spot(15.4, L2, -IN_Z, FRONT), furniture))
	against(Furnish.toilet(spot(HX, L2, -11, RIGHT), furniture))
	against(Furnish.washstand(spot(24.2, L2, BATH_Z - PART_T / 2, BACK), furniture))

	-- The belvedere: a telescope at the window, a chair, a table with a log
	-- and a dead lantern, a trunk. Something stood in the corner.
	Furnish.telescope(spot(-6, L3, -7, LEFT), furniture)
	Furnish.diningChair(spot(-4.5, L3, -11, LEFT + FRONT * 0.3), furniture, { seat = C.LEATHER })
	-- The log table, between the two side windows.
	local logTable = against(
		Furnish.sideTable(
			spot(-BELV_X + WALL_T / 2, L3, -12, RIGHT),
			furniture,
			{ width = 2.4, height = 3 }
		)
	)
	Decor.books(logTable.WorldPivot * CFrame.new(0, 3, 0.4), furniture, { count = 2 })
	Decor.lantern(logTable.WorldPivot * CFrame.new(0.3, 3, -0.6), furniture)
	against(Furnish.trunk(spot(-3, L3, -IN_Z, FRONT), furniture))
	Furnish.mannequin(spot(-7.2, L3, -23, FRONT + RIGHT * 0.5), furniture, { dress = C.SOOT })
	Decor.painting(
		spot(-6, L3 + 6.5, -IN_Z + 0.1, FRONT),
		furniture,
		{ subject = "landscape", width = 3, height = 2.4 }
	)

	-- The roof: dead shrubs in urns, iron garden chairs round a table, a
	-- washing line of rags, the telescope's twin left out in the weather.
	for _, p in
		{
			V(-26, 0, 20),
			V(-12, 0, 21.5),
			V(12, 0, 21.5),
			V(26, 0, 20),
			V(-26, 0, -21),
			V(26, 0, -21),
			V(-26, 0, 1),
			V(26, 0, 1),
		}
	do
		Furnish.planter(spot(p.X, L3, p.Z), furniture)
	end
	Furnish.gardenTable(spot(-18, L3, 8), furniture)
	for k = 0, 2 do
		local a = k * 2 * math.pi / 3 + 0.5
		Furnish.gardenChair(
			spot(
				-18 + math.cos(a) * 2.6,
				L3,
				8 + math.sin(a) * 2.6,
				V(-math.cos(a), 0, -math.sin(a))
			),
			furniture
		)
	end
	Furnish.clothesline(spot(18, L3, 9, V(0, 0, -1)), furniture, { span = 16 })
	Furnish.telescope(spot(0, L3, 19, FRONT), furniture, { elevation = 6 })
	Furnish.bench(spot(0, L3, 3.5, FRONT), furniture, { length = 6, wood = rgb(52, 42, 34) })

	--------------------------------------------------------------------------
	-- Dirt, damage and worse
	--------------------------------------------------------------------------

	local function floorAt(x: number, y: number, z: number): CFrame
		return place(V(x, y, z))
	end
	local function wallAt(x: number, y: number, z: number, face: Vector3): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face)
	end
	for _, s in
		{
			{ 3, L1, 18, 2 },
			{ -24, L1, -3, 2.4 },
			{ 26, L1, -16, 1.6 },
			{ -14, L2, 16, 1.8 },
			{ 26, L2, 10, 1.4 },
			{ -24, L2, -20, 1.6 },
			{ -20, L3, 16, 3 },
			{ 22, L3, -12, 2.4 },
			{ 4, L3, -22, 1.8 },
		}
	do
		Decor.stain(floorAt(s[1], s[2], s[3]), dressing, s[4])
	end
	-- Blood from the bath, across the tiles, out under the door.
	Decor.stain(floorAt(18.5, L2, -18), dressing, 1.8, C.BLOOD_OLD)
	local trail = { V(18.5, L2, -16.5), V(19.6, L2, -11), V(20, L2, -7.4) }
	for i = 1, #trail - 1 do
		Decor.smear(
			place(trail[i]).Position,
			place(trail[i + 1]).Position,
			dressing,
			0.8 - i * 0.12
		)
	end
	Decor.stain(floorAt(-18.5, L1, 16.5), dressing, 1.2, C.BLOOD_OLD)
	-- Water down the walls under the roof.
	Decor.drips(wallAt(-26, L2 + 13.4, IN_Z - 0.12, BACK), dressing, 3, 8)
	Decor.drips(wallAt(IN_X - 0.12, L2 + 13.4, -16, LEFT), dressing, 2.4, 6)
	Decor.drips(wallAt(0, L2 + 13.4, -IN_Z + 0.12, FRONT), dressing, 2.6, 9)
	Decor.peel(wallAt(-IN_X + 0.1, L2 + 12.6, 14 + 4.6, RIGHT), dressing, rgb(70, 50, 46))
	Decor.peel(
		wallAt(IN_X - 0.1, L1 + 12.4, 17.8, LEFT),
		dressing,
		C.PAPER_OXBLOOD,
		{ width = 1.8, length = 4.5 }
	)
	Decor.peel(wallAt(-HALL_X + PART_T / 2 + 0.1, L1 + 13, 2, RIGHT), dressing, C.PAPER_UMBER)
	-- Scratches: inside the linen cupboard's door, on the nursery wall at a
	-- child's height, round the barred window in the second bedroom.
	Decor.scratches(wallAt(-3, L2 + 3, LAND_Z - PART_T / 2 - 0.5, BACK), dressing, 2.4)
	Decor.scratches(wallAt(26, L2 + 2.2, IN_Z - 0.12, BACK), dressing, 2.8, rgb(30, 26, 24))
	Decor.scratches(wallAt(-IN_X + 0.12, L2 + 4.6, -21, RIGHT), dressing, 3)
	Decor.brokenBoards(floorAt(-8, L3, 14), dressing)
	Decor.brokenBoards(floorAt(21, L3, -17), dressing)
	Decor.fallenPlaster(floorAt(-24, L2, -9), dressing, STOREY)
	-- Outside: rust from the bars running down the brick.
	for _, p in
		{
			V(-24, L1 + 2.8, HALF_D + 0.3),
			V(15, L2 + 2.8, HALF_D + 0.3),
			V(24, L1 + 2.8, HALF_D + 0.3),
		}
	do
		Decor.drips(wallAt(p.X, p.Y, p.Z, FRONT), dressing, 2.4, 3.6, rgb(52, 32, 24))
	end

	model.Parent = parent

	print(
		string.format(
			"[Villa] %d parts, %d hiding places, roof %d studs above ground",
			Kit.count(),
			#hidingSpots,
			L3 - GROUND
		)
	)

	return {
		model = model,
		entrance = CFrame.lookAt(
			place(V(0, GROUND + 3, PORTICO_Z + 16)).Position,
			place(V(0, GROUND + 3, WALL_Z)).Position
		),
		hidingSpots = hidingSpots,
		partCount = Kit.count(),
	}
end

return Villa
