--!strict
--[[
	The village church and its churchyard, generated entirely in code.

	A stone parish church of the plainest Gothic: a nave of seven bays with
	an aisle either side on round columns and pointed arches, a narrower
	chancel through a tall chancel arch, a porch on the south side, a vestry
	off the chancel on the north, and a tower over the west end of the north
	aisle with a broach spire on it. The tower is the landmark: at ninety
	studs it stands over the fog, and a player lost in the village finds
	their way by it.

	Its stair winds up the inside of the walls round an open well, eight
	flights to the belfry. The bell still hangs in its frame there, and its
	rope comes down the middle of the well to the floor at the bottom.

	Inside, pews face an altar nobody has dressed in years, and there is a
	pulpit, a lectern, a font, an organ and a confessional; the churchyard
	round it is full of leaning stones, and there is a mausoleum at the back
	with its door off the latch. Every door opens (DoorController). Nothing
	gives light and nothing inside is pale: the windows are stained glass,
	gone dark.

	Compass: the altar is east. The front, +Z, is the west end, and a visitor
	walking in at the west door has south (+X) on their right.

	Built from HouseKit, Furnish, Decor and Yard. Local space runs +X right,
	+Y up, +Z out of the west door, with Y = 0 the nave floor; the ground is
	FOUND_H below that and the pivot sits on it.
]]

local Kit = require(script.Parent.HouseKit)
local Furnish = require(script.Parent.Furnish)
local Decor = require(script.Parent.Decor)
local Yard = require(script.Parent.Yard)

local Church = {}

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

----------------------------------------------------------------------------
-- Dimensions
----------------------------------------------------------------------------

local FOUND_H = 2 -- the church stands on a plinth this far above the ground
local L1 = 0
local GROUND = -FOUND_H

-- The nave and its aisles.
local WALL_T = 2
local IN_X = 15 -- the aisle walls' inner faces
local OUT_X = IN_X + WALL_T -- 17
local WALL_X = IN_X + WALL_T / 2
local ARCADE_X = 8 -- the column line, either side
local CLER_T = 1.6 -- the wall the arcade carries
local CLER_IN = ARCADE_X - CLER_T / 2 -- 7.2, its face to the nave
local CLER_OUT = ARCADE_X + CLER_T / 2 -- 8.8, its face to the aisle
local WEST_IN = 30
local WEST_OUT = WEST_IN + WALL_T -- 32
local WEST_Z = WEST_IN + WALL_T / 2
local EAST_T = 1.6
local EAST_IN = -26 -- the chancel arch wall, its face to the nave
local EAST_OUT = EAST_IN - EAST_T -- -27.6
local EAST_Z = EAST_IN - EAST_T / 2
local COLUMN_ZS = { 22, 14, 6, -2, -10, -18 }
local BAY_ZS = { 26, 18, 10, 2, -6, -14, -22 }
local COL_D = 2.4
local CAP_Y = 10 -- the top of the capitals, where the arches spring
local ARCH_W = 2.4 -- half an arcade arch's span at the springing
local AISLE_TOP = 15 -- the aisle walls' tops, at their outer faces
local AISLE_HIGH = 21 -- where the aisle roofs meet the wall over the arcade
local NAVE_TOP = 30

-- The chancel: narrower and lower, one step up through the arch and one
-- more to the altar.
local CH_IN = 6
local CH_T = 1.6
local CH_OUT = CH_IN + CH_T -- 7.6
local CH_WALL = CH_IN + CH_T / 2
local CH_EAST_IN = -50
local CH_EAST_OUT = CH_EAST_IN - CH_T -- -51.6
local CH_EAST_Z = CH_EAST_IN - CH_T / 2
local CH_TOP = 24
local CHOIR_Y = 0.8
local SANCT_Y = 1.6
local SANCT_Z = -42

-- The tower, over the west end of the north aisle. Its east wall is the
-- aisle's north wall carried on up.
local T_X0, T_X1 = -33, -OUT_X + WALL_T -- -33 .. -15
local T_Z0, T_Z1 = 14, WEST_OUT
local T_IX0, T_IX1 = T_X0 + WALL_T, T_X1 - WALL_T -- -31 .. -17
local T_IZ0, T_IZ1 = T_Z0 + WALL_T, T_Z1 - WALL_T -- 16 .. 30
local T_CX, T_CZ = (T_X0 + T_X1) / 2, (T_Z0 + T_Z1) / 2 -- -24, 23
-- The stair: flights along the walls round an open well.
local FLIGHT_W = 3.5
local FLIGHT_RISE = 4.5
local FLIGHT_STEPS = 6
local FLIGHTS = 8
local WELL_X0, WELL_X1 = T_IX0 + FLIGHT_W, T_IX1 - FLIGHT_W -- -27.5 .. -20.5
local WELL_Z0, WELL_Z1 = T_IZ0 + FLIGHT_W, T_IZ1 - FLIGHT_W -- 19.5 .. 26.5
local BELFRY_Y = FLIGHTS * FLIGHT_RISE -- 36
local BELFRY_CEIL = 51
local TOWER_TOP = 52
local SPIRE_TOP = 92
-- Where the bell rope comes down the well.
local ROPE_X, ROPE_Z = -22.3, 25.4

-- The south porch.
local P_X0, P_X1 = OUT_X, 26
local P_Z0, P_Z1 = 8, 20
local P_T = 1.5
local P_TOP = 9
local P_PITCH = math.rad(30)
local SOUTH_DOOR_Z = 14

-- The vestry, north of the chancel, under a lean-to.
local V_X0, V_X1 = -OUT_X, -CH_OUT -- -17 .. -7.6
local V_Z0, V_Z1 = -44, EAST_OUT -- -44 .. -27.6
local V_T = 1.5
local V_LOW = 10
local V_HIGH = 14

-- Roofs.
local PITCH = math.rad(50)
local FALL = math.tan(PITCH)
local ROOF_T = 1.0
local EAVE = 1.2
-- The nave's rafter line: the underside of the roof, meeting each wall's
-- outer face at the wall's top.
local function naveUnder(x: number): number
	return NAVE_TOP + (CLER_OUT - math.abs(x)) * FALL
end
local NAVE_RIDGE = naveUnder(0)
local AISLE_FALL = (AISLE_HIGH - AISLE_TOP) / (OUT_X - CLER_OUT)
local function aisleUnder(x: number): number
	return AISLE_HIGH - (math.abs(x) - CLER_OUT) * AISLE_FALL
end
local function chancelUnder(x: number): number
	return CH_TOP + (CH_OUT - math.abs(x)) * FALL
end
local CH_RIDGE = chancelUnder(0)
local V_FALL = (V_HIGH - V_LOW) / (V_X1 - V_X0)
local function vestryUnder(x: number): number
	return V_HIGH - (V_X1 - x) * V_FALL
end
local P_FALL = math.tan(P_PITCH)
local P_CZ = (P_Z0 + P_Z1) / 2
local function porchUnder(z: number): number
	return P_TOP + ((P_Z1 - P_Z0) / 2 - math.abs(z - P_CZ)) * P_FALL
end

-- The churchyard.
local YARD_X0, YARD_X1 = -66, 60
local YARD_Z0, YARD_Z1 = -92, 66

----------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------

local STONE = rgb(76, 72, 66) -- rubble walling, soot-dark
local DRESSED = rgb(84, 80, 72) -- the cut stone of columns and mouldings
local DRESSED_DARK = rgb(64, 61, 56)
local SLATE = rgb(44, 42, 44)
local FLOOR = rgb(56, 53, 50)
local PLASTER = rgb(72, 66, 58) -- limewash, gone the colour of the stone under it
local OAK = rgb(52, 39, 29)
local OAK_DARK = rgb(40, 30, 23)
local LEAD = rgb(38, 38, 40)
local BRONZE = rgb(66, 60, 44)
-- Stained glass, every colour of it darkened by a century of grime. None
-- of it passes for white: the palest is the amber.
local GLASS = {
	rgb(68, 22, 20),
	rgb(24, 30, 60),
	rgb(72, 56, 24),
	rgb(26, 44, 30),
	rgb(50, 26, 56),
}

local F_CHURCH: Finish = {
	paper = PLASTER,
	paperMaterial = M.Plaster,
	wainscot = 4.5,
	rail = DRESSED_DARK,
}

----------------------------------------------------------------------------
-- Rooms: only the plastered ones. The tower, porch and arcade are bare stone.
----------------------------------------------------------------------------

local ROOMS: { Room } = {
	{
		name = "Vestry",
		level = L1,
		height = V_LOW,
		x0 = V_X0 + V_T,
		x1 = V_X1,
		z0 = V_Z0 + V_T,
		z1 = V_Z1,
		finish = F_CHURCH,
	},
	{
		name = "Nave",
		level = L1,
		height = NAVE_TOP,
		x0 = -CLER_IN,
		x1 = CLER_IN,
		z0 = EAST_IN,
		z1 = WEST_IN,
		finish = F_CHURCH,
	},
	{
		name = "NorthAisle",
		level = L1,
		height = AISLE_TOP,
		x0 = -IN_X,
		x1 = -CLER_IN,
		z0 = EAST_IN,
		z1 = WEST_IN,
		finish = F_CHURCH,
	},
	{
		name = "SouthAisle",
		level = L1,
		height = AISLE_TOP,
		x0 = CLER_IN,
		x1 = IN_X,
		z0 = EAST_IN,
		z1 = WEST_IN,
		finish = F_CHURCH,
	},
	{
		name = "Chancel",
		level = CHOIR_Y,
		height = CH_TOP - CHOIR_Y,
		x0 = -CH_IN,
		x1 = CH_IN,
		z0 = CH_EAST_IN,
		z1 = EAST_OUT,
		finish = F_CHURCH,
	},
}

--[[
	How much ground the church and its yard take, in house space: the whole
	churchyard inside its wall.
]]
Church.FOOTPRINT = {
	x0 = YARD_X0 - 2,
	x1 = YARD_X1 + 2,
	z0 = YARD_Z0 - 2,
	z1 = YARD_Z1 + 6,
}

-- Whether a world position is on the footprint of a church built at `pivot`.
function Church.footprintContains(pivot: CFrame, position: Vector3): boolean
	local rel = (pivot * CFrame.Angles(0, math.pi, 0)):PointToObjectSpace(position)
	local f = Church.FOOTPRINT
	return rel.X > f.x0 and rel.X < f.x1 and rel.Z > f.z0 and rel.Z < f.z1
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
	local y = (up - along * up:Dot(along))
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
-- Pointed arches
----------------------------------------------------------------------------

--[[
	A pointed arch of half-span `w` is two arcs of radius `r`, each centred on
	the opposite springing point. r = 2w is the equilateral arch; smaller is
	a drop arch, flatter at the crown.
]]
local function archRise(w: number, r: number): number
	return math.sqrt(r * r - (r - w) * (r - w))
end

-- The arch's half-width at height `y` above its springing.
local function archHalf(w: number, r: number, y: number): number
	local d = r * r - y * y
	if d <= 0 then
		return 0
	end
	return math.max(0, math.sqrt(d) - (r - w))
end

-- The height above the springing at which the arch is `u` from its middle.
local function archAt(w: number, r: number, u: number): number
	local k = math.abs(u) + r - w
	return math.sqrt(math.max(0, r * r - k * k))
end

-- A point in a wall's own terms: `u` along it, `y` up, `n` out of its middle.
local function wp(axis: string, fixed: number, u: number, y: number, n: number): Vector3
	if axis == "X" then
		return V(u, y, fixed + n)
	end
	return V(fixed + n, y, u)
end
local function wsize(axis: string, len: number, h: number, depth: number): Vector3
	if axis == "X" then
		return V(len, h, depth)
	end
	return V(depth, h, len)
end
local function alongOf(axis: string): Vector3
	return if axis == "X" then V(1, 0, 0) else V(0, 0, 1)
end
local function normalOf(axis: string): Vector3
	return if axis == "X" then V(0, 0, 1) else V(1, 0, 0)
end

--[[
	The stone that fills the top of a rectangular hole down to a pointed
	arch: course by course from the springing to the crown, a block from
	each jamb in to where the curve starts and a right-angled wedge for the
	slope of the curve across the course. The hole itself comes from
	Kit.wall; this only turns its top into an arch.
]]
local function pointedHead(
	name: string,
	axis: string,
	fixed: number,
	at: number,
	w: number,
	r: number,
	spring: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance,
	courses: number?
)
	local n = courses or (if w > 2 then 5 elseif w > 1.3 then 4 else 3)
	local rise = archRise(w, r)
	local function world(u: number, y: number): Vector3
		return place(wp(axis, fixed, u, y, 0)).Position
	end
	for i = 0, n - 1 do
		local y0 = spring + rise * i / n
		local y1 = spring + rise * (i + 1) / n
		local h0 = archHalf(w, r, y0 - spring)
		local h1 = archHalf(w, r, y1 - spring)
		for _, s in { -1, 1 } do
			local jamb, inner = at + s * w, at + s * h0
			if math.abs(jamb - inner) > EPS then
				Kit.part(
					name,
					wsize(axis, math.abs(jamb - inner), y1 - y0, thickness),
					place(wp(axis, fixed, (jamb + inner) / 2, (y0 + y1) / 2, 0)),
					Kit.weathered(color, 0.04),
					material,
					parent
				)
			end
			Kit.rightTriangle(
				name,
				world(at + s * h0, y1),
				world(at + s * h0, y0),
				world(at + s * h1, y1),
				thickness,
				Kit.weathered(color, 0.04),
				material,
				parent
			)
		end
	end
end

--[[
	A round moulding following a pointed arch on one face of a wall: the
	arch's own curve, `offset` further out, from the springing on one side
	over the crown to the other, in short straight rods. `stops` puts a
	carved stop, a ball, at each foot.
]]
local function archMould(
	name: string,
	axis: string,
	fixed: number,
	at: number,
	w: number,
	r: number,
	spring: number,
	face: number,
	offset: number,
	d: number,
	color: Color3,
	place: Place,
	parent: Instance,
	stops: boolean?
)
	local R = r + offset
	local segs = if w > 2 then 5 else 3
	for _, s in { -1, 1 } do
		-- The arc on side `s` is centred on the springing point opposite it.
		local cx = at - s * (r - w)
		local th0 = math.pi / 2 - s * math.pi / 2 -- pointing out to side s
		local th1 = math.acos(math.clamp(s * (at - cx) / R, -1, 1)) -- where it reaches the middle
		th1 = if s > 0 then th1 else math.pi - th1
		local prev: Vector3? = nil
		for k = 0, segs do
			local th = th0 + (th1 - th0) * k / segs
			local p =
				place(wp(axis, fixed, cx + R * math.cos(th), spring + R * math.sin(th), face)).Position
			if prev then
				Kit.detail(Kit.rod(name, prev, p, d, color, M.Concrete, parent))
			end
			prev = p
		end
		if stops then
			Kit.detail(
				Kit.ball(
					name .. "Stop",
					place(wp(axis, fixed, at + s * (w + offset), spring - 0.2, face)).Position,
					d * 2,
					color,
					M.Concrete,
					parent
				)
			)
		end
	end
end

----------------------------------------------------------------------------
-- Stone walls with pointed openings
----------------------------------------------------------------------------

type Win = {
	at: number,
	w: number, -- half the width
	sill: number,
	spring: number,
	r: number, -- the arcs' radius: 2 * w is an equilateral arch
	kind: string, -- "glass" | "slit" | "louvre" | "open" | "door"
	lights: number?, -- tracery lights, for "glass"
	hood: boolean?, -- a hood mould over it outside
	broken: boolean?, -- panes gone from the top of it
	boarded: boolean?, -- planks nailed across it outside
}

local function lancet(
	at: number,
	sill: number,
	width: number,
	spring: number,
	o: { [string]: any }?
): Win
	local opts: { [string]: any } = o or {}
	local w = width / 2
	return {
		at = at,
		w = w,
		sill = sill,
		spring = spring,
		r = opts.r or w * 2,
		kind = opts.kind or "glass",
		lights = opts.lights,
		hood = if opts.hood == nil then true else opts.hood,
		broken = opts.broken,
		boarded = opts.boarded,
	}
end

-- A square-headed door opening, solid wall over it.
local function doorway(at: number, w: number, sill: number, spring: number, hood: boolean): Win
	return { at = at, w = w, sill = sill, spring = spring, r = w * 2, kind = "door", hood = hood }
end

local function apexOf(win: Win): number
	return win.spring + archRise(win.w, win.r)
end

--[[
	Stained glass in a pointed opening: the lights between stone mullions,
	each pane in three bands of colour with a lead line between, the heads
	shaped by the stone that pointedHead laid round them. A broken window
	has lost the top band of a light or two, and the sharp edges are still
	in the lead.
]]
local function glaze(
	axis: string,
	fixed: number,
	win: Win,
	place: Place,
	parent: Instance,
	seed: number
)
	local lights = win.lights or 1
	local apex = apexOf(win)
	local mull = 0.36
	local wear = Kit.wear()
	local edges: { number } = { win.at - win.w }
	for i = 1, lights - 1 do
		table.insert(edges, win.at - win.w + 2 * win.w * i / lights)
	end
	table.insert(edges, win.at + win.w)
	for i = 2, #edges - 1 do
		local u = edges[i]
		local top = win.spring + archAt(win.w, win.r, u - win.at)
		Kit.part(
			"Mullion",
			wsize(axis, mull, top - win.sill, 0.7),
			place(wp(axis, fixed, u, (win.sill + top) / 2, 0)),
			DRESSED,
			M.Concrete,
			parent
		)
	end
	for i = 1, #edges - 1 do
		local u0, u1 = edges[i], edges[i + 1]
		local mid = win.sill + (win.spring - win.sill) * 0.48
		local bands = { { win.sill, mid }, { mid, win.spring }, { win.spring, apex } }
		for b, band in bands do
			local gone = win.broken and b == 3 and (i + seed) % 2 == 0
			if gone then
				-- Shards left in the lead along the bottom of the gap.
				for k = 0, 2 do
					local u = u0 + (u1 - u0) * (k + 0.5) / 3
					Kit.detail(
						Kit.part(
							"Shard",
							wsize(axis, (u1 - u0) / 3.2, wear:NextNumber(0.4, 0.9), 0.08),
							place(wp(axis, fixed, u, band[1] + 0.3, 0))
								* CFrame.Angles(0, 0, wear:NextNumber(-0.5, 0.5)),
							GLASS[(i + b + seed + k) % #GLASS + 1],
							M.Glass,
							parent
						)
					).Transparency =
						0.35
				end
				continue
			end
			local pane = Kit.part(
				"Glass",
				wsize(axis, u1 - u0, band[2] - band[1], 0.12),
				place(wp(axis, fixed, (u0 + u1) / 2, (band[1] + band[2]) / 2, 0)),
				Kit.weathered(GLASS[(i * 2 + b + seed) % #GLASS + 1], 0.08),
				M.Glass,
				parent
			)
			pane.Transparency = 0.35
			pane.CastShadow = false
			if b < 3 then
				Kit.detail(
					Kit.rod(
						"Lead",
						place(wp(axis, fixed, u0, band[2], 0)).Position,
						place(wp(axis, fixed, u1, band[2], 0)).Position,
						0.16,
						LEAD,
						M.Metal,
						parent
					)
				)
			end
		end
	end
end

-- Louvre boards across a belfry opening, tilted to shed rain outward. They
-- collide: nobody climbs out of the belfry through them.
local function louvres(
	axis: string,
	fixed: number,
	win: Win,
	outward: number,
	place: Place,
	parent: Instance
)
	local apex = apexOf(win)
	local along = alongOf(axis)
	local out = normalOf(axis) * outward
	local tilt = math.rad(40)
	local y = win.sill + 0.45
	while y < apex - 0.3 do
		local half = if y <= win.spring then win.w else archHalf(win.w, win.r, y - win.spring)
		if half > 0.25 then
			Kit.part(
				"Louvre",
				V(half * 2, 0.16, WALL_T * 0.8),
				oriented(
					place,
					wp(axis, fixed, win.at, y, 0),
					along,
					V(0, math.cos(tilt), 0) + out * math.sin(tilt)
				),
				Kit.weathered(rgb(48, 42, 36), 0.1),
				M.Wood,
				parent
			)
		end
		y += 0.72
	end
end

type StoneWall = {
	name: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	bottom: number,
	top: number,
	thickness: number?,
	outward: number?,
	wins: { Win }?,
	rooms: { Room }?,
	color: Color3?,
	material: Enum.Material?,
	insetEnds: number?,
}

local wallSeed = 0

--[[
	A stone wall with pointed openings in it: Kit.wall for the rectangles,
	then each opening's head turned into an arch, glazed or louvred or left
	open, and a hood mould over it on the outside.
]]
local function stoneWall(s: StoneWall, place: Place, parent: Instance)
	local t = s.thickness or WALL_T
	local color = s.color or STONE
	local material = s.material or M.Cobblestone
	local wins: { Win } = s.wins or {}
	local openings: { Opening } = {}
	for _, win in wins do
		local head = if win.kind == "door" then win.spring else apexOf(win)
		table.insert(openings, { at = win.at, width = win.w * 2, sill = win.sill, head = head })
	end
	Kit.wall({
		name = s.name,
		axis = s.axis,
		fixed = s.fixed,
		from = s.from,
		to = s.to,
		bottom = s.bottom,
		top = s.top,
		thickness = t,
		openings = openings,
		color = color,
		material = material,
		place = place,
		parent = parent,
		outward = s.outward,
		rooms = s.rooms,
		insetEnds = s.insetEnds,
		weather = 0.05,
	})
	for _, win in wins do
		wallSeed += 1
		if win.kind ~= "door" then
			pointedHead(
				s.name .. "Head",
				s.axis,
				s.fixed,
				win.at,
				win.w,
				win.r,
				win.spring,
				t,
				color,
				material,
				place,
				parent
			)
		end
		if win.kind == "glass" then
			glaze(s.axis, s.fixed, win, place, parent, wallSeed)
			local outward = s.outward
			if win.boarded and outward then
				-- Planks nailed across it outside, not quite level, the top one
				-- hanging off a single nail.
				local wear = Kit.wear()
				local apex = apexOf(win)
				local n = math.max(3, math.floor((apex - win.sill) / 1.6))
				for k = 1, n do
					local y = win.sill + (apex - win.sill - 0.8) * (k - 0.5) / n
					local tilt = wear:NextNumber(-0.18, 0.18) + (if k == n then 0.5 else 0)
					Kit.part(
						"Boarding",
						V(win.w * 2 + 1.0, 0.7, 0.14),
						oriented(
							place,
							wp(s.axis, s.fixed, win.at, y, outward * (t / 2 + 0.1)),
							alongOf(s.axis) * math.cos(tilt) + V(0, math.sin(tilt), 0),
							V(0, math.cos(tilt), 0) - alongOf(s.axis) * math.sin(tilt)
						),
						Kit.weathered(rgb(58, 46, 36), 0.12),
						M.WoodPlanks,
						parent
					)
				end
			end
		elseif win.kind == "louvre" then
			louvres(s.axis, s.fixed, win, s.outward or 1, place, parent)
		end
		local outward = s.outward
		if outward and win.hood then
			if win.kind == "door" then
				-- Over a square-headed door, a drop arch standing on the jambs.
				archMould(
					"HoodMould",
					s.axis,
					s.fixed,
					win.at,
					win.w + 0.5,
					(win.w + 0.5) * 1.25,
					win.spring,
					outward * (t / 2 + 0.2),
					0.2,
					0.5,
					DRESSED,
					place,
					parent,
					true
				)
			else
				archMould(
					"HoodMould",
					s.axis,
					s.fixed,
					win.at,
					win.w,
					win.r,
					win.spring,
					outward * (t / 2 + 0.2),
					0.45,
					0.42,
					DRESSED,
					place,
					parent,
					true
				)
			end
		end
		if outward and win.kind ~= "door" and win.kind ~= "open" and win.sill > s.bottom + 0.5 then
			-- A sill on the outside, sloped by being a rod.
			Kit.detail(
				Kit.rod(
					"StoneSill",
					place(
						wp(
							s.axis,
							s.fixed,
							win.at - win.w - 0.35,
							win.sill - 0.2,
							outward * (t / 2 + 0.15)
						)
					).Position,
					place(
						wp(
							s.axis,
							s.fixed,
							win.at + win.w + 0.35,
							win.sill - 0.2,
							outward * (t / 2 + 0.15)
						)
					).Position,
					0.5,
					DRESSED,
					M.Concrete,
					parent
				)
			)
		end
	end
end

--[[
	A piece of wall that stops under a sloping roof: a rectangle up to the
	lower end of the slope and a wedge for the rest, so it meets the roof's
	underside along its whole length. `ya` is the slope's height at `u0`,
	`yb` at `u1`.
]]
local function underSlope(
	name: string,
	axis: string,
	fixed: number,
	u0: number,
	u1: number,
	bottom: number,
	ya: number,
	yb: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance
)
	local low = math.min(ya, yb)
	if low - bottom > EPS then
		Kit.part(
			name,
			wsize(axis, math.abs(u1 - u0), low - bottom, thickness),
			place(wp(axis, fixed, (u0 + u1) / 2, (bottom + low) / 2, 0)),
			Kit.weathered(color, 0.04),
			material,
			parent
		)
	end
	if math.abs(ya - yb) > EPS then
		local uHigh = if ya > yb then u0 else u1
		local uLow = if ya > yb then u1 else u0
		Kit.rightTriangle(
			name,
			place(wp(axis, fixed, uHigh, low, 0)).Position,
			place(wp(axis, fixed, uHigh, math.max(ya, yb), 0)).Position,
			place(wp(axis, fixed, uLow, low, 0)).Position,
			thickness,
			Kit.weathered(color, 0.04),
			material,
			parent
		)
	end
end

----------------------------------------------------------------------------
-- Roofs
----------------------------------------------------------------------------

--[[
	One pitch of a roof: a slab of slates whose underside runs from (a, ya)
	to (b, yb) across the roof, the length of it along the other axis, with
	boards under it. `axis` is the way the ridge runs.
]]
local function roofPitch(
	name: string,
	axis: string,
	a: number,
	ya: number,
	b: number,
	yb: number,
	from: number,
	to: number,
	color: Color3,
	place: Place,
	parent: Instance,
	boards: Color3?
)
	-- In the roof's own terms: `c` across the ridge, `y` up, `l` along it.
	local function pt(c: number, y: number, l: number): Vector3
		if axis == "Z" then
			return V(c, y, l)
		end
		return V(l, y, c)
	end
	local across = pt(b - a, yb - ya, 0).Unit
	local lengthDir = pt(0, 0, 1)
	local normal = lengthDir:Cross(across)
	if normal.Y < 0 then
		normal = -normal
	end
	local span = pt(b - a, yb - ya, 0).Magnitude
	local lenAlong = math.abs(to - from)
	local midUnder = pt((a + b) / 2, (ya + yb) / 2, (from + to) / 2)
	Kit.part(
		name,
		V(lenAlong, ROOF_T, span),
		oriented(place, midUnder + normal * (ROOF_T / 2), lengthDir, normal),
		Kit.weathered(color, 0.04),
		M.Slate,
		parent
	)
	if boards then
		Kit.detail(
			Kit.part(
				"RoofBoards",
				V(lenAlong - 0.1, 0.2, span - 0.1),
				oriented(place, midUnder - normal * 0.1, lengthDir, normal),
				boards,
				M.WoodPlanks,
				parent
			)
		).CastShadow =
			true
	end
end

----------------------------------------------------------------------------
-- Buttresses
----------------------------------------------------------------------------

--[[
	A stepped buttress against a wall: `foot` is where its middle meets the
	wall at ground level, `out` the way it projects. Each stage stands out
	`depth` from the wall up to `top`, where a sloped weathering takes it
	back to the next stage's face, and the last slopes back into the wall.
]]
local function buttress(
	foot: Vector3,
	out: Vector3,
	width: number,
	stages: { { number } },
	place: Place,
	parent: Instance
)
	local side = out:Cross(Vector3.yAxis).Unit
	local bottom = foot.Y
	for i, stage in stages do
		local top, depth = stage[1], stage[2]
		local nextDepth = if stages[i + 1] then stages[i + 1][2] else 0
		Kit.part(
			"Buttress",
			V(width, top - bottom, depth),
			oriented(
				place,
				foot + out * (depth / 2) + V(0, (bottom + top) / 2 - foot.Y, 0),
				side,
				V(0, 1, 0)
			),
			Kit.weathered(STONE, 0.05),
			M.Cobblestone,
			parent
		)
		local drop = depth - nextDepth
		Kit.rightTriangle(
			"Weathering",
			place(foot + out * nextDepth + V(0, top - foot.Y, 0)).Position,
			place(foot + out * nextDepth + V(0, top - foot.Y + drop * 1.1, 0)).Position,
			place(foot + out * depth + V(0, top - foot.Y, 0)).Position,
			width,
			Kit.weathered(DRESSED_DARK, 0.05),
			M.Concrete,
			parent
		)
		bottom = top
	end
end

----------------------------------------------------------------------------
-- The tower
----------------------------------------------------------------------------

type Flight = { from: Vector3, to: Vector3 }

--[[
	The flights, one to a wall, round and round the well: along the front
	to the west, back along the north wall, along the back to the east and
	forward along the aisle wall, twice. Each arrives in a corner, where the
	next one starts. The well between them stays open from floor to belfry.
]]
local function towerFlights(): { Flight }
	local fz = T_IZ1 - FLIGHT_W / 2
	local lx = T_IX0 + FLIGHT_W / 2
	local bz = T_IZ0 + FLIGHT_W / 2
	local rx = T_IX1 - FLIGHT_W / 2
	local flights: { Flight } = {}
	for i = 0, FLIGHTS - 1 do
		local y0, y1 = i * FLIGHT_RISE, (i + 1) * FLIGHT_RISE
		local k = i % 4
		if k == 0 then
			table.insert(flights, { from = V(WELL_X1, y0, fz), to = V(WELL_X0, y1, fz) })
		elseif k == 1 then
			table.insert(flights, { from = V(lx, y0, WELL_Z1), to = V(lx, y1, WELL_Z0) })
		elseif k == 2 then
			table.insert(flights, { from = V(WELL_X0, y0, bz), to = V(WELL_X1, y1, bz) })
		else
			table.insert(flights, { from = V(rx, y0, WELL_Z0), to = V(rx, y1, WELL_Z1) })
		end
	end
	return flights
end

-- The corner a flight arrives in, as x0, x1, z0, z1.
local function cornerAfter(i: number): (number, number, number, number)
	local k = i % 4
	if k == 0 then
		return T_IX0, WELL_X0, WELL_Z1, T_IZ1
	elseif k == 1 then
		return T_IX0, WELL_X0, T_IZ0, WELL_Z0
	elseif k == 2 then
		return WELL_X1, T_IX1, T_IZ0, WELL_Z0
	end
	return WELL_X1, T_IX1, WELL_Z1, T_IZ1
end

local function towerStair(place: Place, parent: Instance)
	for i, f in towerFlights() do
		Kit.staircase("Tower", f.from, f.to, FLIGHT_W, FLIGHT_STEPS, place, parent, {
			rails = { 1 },
			wallRails = { -1 },
			treadColor = rgb(56, 45, 36),
			railColor = OAK_DARK,
			rotten = 0.1,
		})
		if i < FLIGHTS then
			local x0, x1, z0, z1 = cornerAfter(i - 1)
			local y = f.to.Y
			Kit.part(
				"TowerLanding",
				V(x1 - x0, 0.8, z1 - z0),
				place(V((x0 + x1) / 2, y - 0.4, (z0 + z1) / 2)),
				Kit.weathered(rgb(56, 45, 36), 0.06),
				M.WoodPlanks,
				parent
			)
		end
	end

	-- The belfry floor, open over the last two flights, with a hole for the
	-- rope and a rail along the edges a player could walk off.
	Kit.slabWithHoles("BelfryFloor", BELFRY_Y, 0.8, T_IX0, T_IX1, T_IZ0, T_IZ1, {
		{ x0 = WELL_X0, x1 = T_IX1, z0 = T_IZ0, z1 = WELL_Z0 },
		{ x0 = WELL_X1, x1 = T_IX1, z0 = WELL_Z0, z1 = WELL_Z1 },
		{ x0 = ROPE_X - 0.5, x1 = ROPE_X + 0.5, z0 = ROPE_Z - 0.5, z1 = ROPE_Z + 0.5 },
	}, rgb(54, 44, 36), M.WoodPlanks, place, parent)
	Kit.railing(
		"Belfry",
		BELFRY_Y,
		{ axis = "X", fixed = WELL_Z0, from = WELL_X0, to = WELL_X1 - 0.3 },
		place,
		parent,
		3.6,
		OAK_DARK
	)
	Kit.railing(
		"Belfry",
		BELFRY_Y,
		{ axis = "Z", fixed = WELL_X0, from = T_IZ0 + 0.2, to = WELL_Z0 },
		place,
		parent,
		3.6,
		OAK_DARK
	)
	-- The ceiling under the spire.
	Kit.part(
		"BelfryCeiling",
		V(T_IX1 - T_IX0, TOWER_TOP - BELFRY_CEIL, T_IZ1 - T_IZ0),
		place(V(T_CX, (BELFRY_CEIL + TOWER_TOP) / 2, T_CZ)),
		rgb(40, 34, 29),
		M.WoodPlanks,
		parent
	)
end

--[[
	The bell in its frame: two long sills on the floor, an A-frame at each
	end carrying the headstock on its bearings, and the bell hanging mouth
	down between them. A bell's profile is round everywhere: here it is a
	stack of discs, narrow at the shoulder, waisted, flaring to the lip.
	Beside it, the wheel the rope is wound on, and the rope going down
	through its hole in the floor to the bottom of the tower.
]]
local function bell(place: Place, parent: Instance)
	local frame = Instance.new("Model")
	frame.Name = "BellFrame"
	frame.Parent = parent
	local floor = BELFRY_Y
	local bx, by, bz = -25.5, floor + 6.4, T_CZ -- the bell's mouth centre
	local axleY = by + 4.9
	local sideXs = { -28.8, -21.0 }
	local wood = rgb(44, 34, 27)

	for _, z in { 20.2, 25.8 } do
		Kit.part(
			"FrameSill",
			V(9.0, 0.8, 0.9),
			place(V(-25.4, floor + 0.4, z)),
			Kit.weathered(wood, 0.06),
			M.Wood,
			frame
		)
	end
	for _, x in sideXs do
		Kit.part("FrameSill", V(0.9, 0.8, 6.5), place(V(x, floor + 0.4, bz)), wood, M.Wood, frame)
		for _, z in { 20.4, 25.6 } do
			Kit.rod(
				"FramePost",
				place(V(x, floor + 0.7, z)).Position,
				place(V(x, axleY - 0.6, bz + (z - bz) * 0.12)).Position,
				0.75,
				Kit.weathered(wood, 0.06),
				M.Wood,
				frame
			)
		end
		Kit.part("FrameTie", V(0.6, 0.6, 4.6), place(V(x, floor + 3.6, bz)), wood, M.Wood, frame)
		Kit.part("Bearing", V(1.0, 0.6, 1.4), place(V(x, axleY - 0.6, bz)), C.IRON, M.Metal, frame)
	end

	-- The headstock, with the iron gudgeons on its ends.
	Kit.part("Headstock", V(7.4, 1.0, 1.2), place(V(-24.9, axleY, bz)), wood, M.Wood, frame)
	for _, x in sideXs do
		Kit.detail(
			Kit.rod(
				"Gudgeon",
				place(V(x - 0.5, axleY, bz)).Position,
				place(V(x + 0.5, axleY, bz)).Position,
				0.35,
				C.IRON,
				M.Metal,
				frame
			)
		)
	end

	-- The bell: discs, lip to crown.
	local profile = {
		{ 0.15, 4.4, 0.3 },
		{ 0.45, 4.2, 0.35 },
		{ 0.85, 3.8, 0.45 },
		{ 1.35, 3.35, 0.6 },
		{ 2.0, 3.05, 0.75 },
		{ 2.75, 2.95, 0.75 },
		{ 3.45, 2.85, 0.65 },
		{ 3.95, 2.3, 0.35 },
		{ 4.2, 1.5, 0.2 },
	}
	for _, p in profile do
		Kit.disc(
			"Bell",
			place(V(bx, by + p[1], bz)),
			p[2],
			p[3],
			Kit.weathered(BRONZE, 0.04),
			M.Metal,
			frame
		)
	end
	-- The crown staple up into the headstock, and the clapper hanging in the
	-- mouth, still.
	Kit.rod(
		"Crown",
		place(V(bx, by + 4.2, bz)).Position,
		place(V(bx, axleY - 0.4, bz)).Position,
		0.7,
		BRONZE,
		M.Metal,
		frame
	)
	Kit.detail(
		Kit.rod(
			"Clapper",
			place(V(bx, by + 3.9, bz)).Position,
			place(V(bx, by + 0.9, bz)).Position,
			0.28,
			C.IRON,
			M.Metal,
			frame
		)
	)
	Kit.detail(
		Kit.ball("ClapperBall", place(V(bx, by + 0.75, bz)).Position, 0.9, C.IRON, M.Metal, frame)
	)

	-- The wheel, on the headstock beside the bell: a rim of short rods, a hub
	-- and six spokes.
	local wx, R = ROPE_X, ROPE_Z - bz
	local rim = 14
	for k = 0, rim - 1 do
		local a0, a1 = 2 * math.pi * k / rim, 2 * math.pi * (k + 1) / rim
		Kit.detail(
			Kit.rod(
				"WheelRim",
				place(V(wx, axleY + R * math.sin(a0), bz + R * math.cos(a0))).Position,
				place(V(wx, axleY + R * math.sin(a1), bz + R * math.cos(a1))).Position,
				0.32,
				wood,
				M.Wood,
				frame
			)
		)
	end
	for k = 0, 5 do
		local a = 2 * math.pi * k / 6 + 0.3
		Kit.detail(
			Kit.rod(
				"WheelSpoke",
				place(V(wx, axleY, bz)).Position,
				place(V(wx, axleY + R * math.sin(a), bz + R * math.cos(a))).Position,
				0.22,
				wood,
				M.Wood,
				frame
			)
		)
	end
	Kit.detail(
		Kit.disc(
			"WheelHub",
			oriented(place, V(wx, axleY, bz), V(0, 1, 0), V(1, 0, 0)),
			0.9,
			0.5,
			wood,
			M.Wood,
			frame
		)
	)

	-- The rope: off the wheel, straight down the well, and a striped sally
	-- where hands took hold of it, and the tail coiled on the floor.
	local ropeColor = rgb(66, 56, 42)
	Kit.soft(
		Kit.rod(
			"BellRope",
			place(V(ROPE_X, axleY, ROPE_Z)).Position,
			place(V(ROPE_X, 2.2, ROPE_Z)).Position,
			0.24,
			ropeColor,
			M.Fabric,
			frame
		)
	)
	for k = 0, 5 do
		local y = 4.2 + k * 0.55
		Kit.soft(
			Kit.rod(
				"Sally",
				place(V(ROPE_X, y, ROPE_Z)).Position,
				place(V(ROPE_X, y + 0.55, ROPE_Z)).Position,
				0.62,
				if k % 2 == 0 then rgb(74, 26, 24) else rgb(34, 36, 50),
				M.Fabric,
				frame
			)
		)
	end
	for k = 0, 3 do
		Kit.detail(
			Kit.disc(
				"RopeCoil",
				place(V(ROPE_X - 0.6, 0.12 + k * 0.2, ROPE_Z - 0.4)),
				1.8 - k * 0.28,
				0.2,
				ropeColor,
				M.Fabric,
				frame
			)
		)
	end
end

--[[
	The clock on the tower's west face, stopped: a stone ring, a dark dial,
	twelve bronze marks and two hands at twenty to five.
]]
local function clock(place: Place, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "TowerClock"
	model.Parent = parent
	local cy = 30.5
	local face = WEST_OUT
	local function on(u: number, y: number, n: number): CFrame
		return oriented(place, V(T_CX + u, cy + y, face + n), V(1, 0, 0), V(0, 0, 1))
	end
	Kit.disc("ClockSurround", on(0, 0, 0.15), 7.4, 0.3, DRESSED, M.Concrete, model)
	Kit.detail(Kit.disc("ClockDial", on(0, 0, 0.36), 6.4, 0.14, rgb(30, 30, 32), M.Metal, model))
	for k = 0, 11 do
		local a = math.pi / 2 - 2 * math.pi * k / 12
		local r = 2.65
		local mark = Kit.part(
			"ClockMark",
			V(0.22, 0.6, 0.1),
			oriented(
				place,
				V(T_CX + r * math.cos(a), cy + r * math.sin(a), face + 0.46),
				V(-math.sin(a), math.cos(a), 0),
				V(math.cos(a), math.sin(a), 0)
			),
			BRONZE,
			M.Metal,
			model
		)
		Kit.detail(mark)
	end
	-- Hands: the hour hand two thirds of the way from four to five, the
	-- minute hand on the eight.
	for _, h in { { 4 + 40 / 60, 1.7, 0.3 }, { 8, 2.5, 0.2 } } do
		local a = math.pi / 2 - 2 * math.pi * h[1] / 12
		local dir = V(math.cos(a), math.sin(a), 0)
		Kit.detail(
			Kit.part(
				"ClockHand",
				V(h[3], h[2], 0.08),
				oriented(
					place,
					V(T_CX, cy, face + 0.56) + dir * (h[2] / 2),
					V(dir.Y, -dir.X, 0),
					dir
				),
				rgb(24, 22, 20),
				M.Metal,
				model
			)
		)
	end
	Kit.detail(Kit.disc("ClockBoss", on(0, 0, 0.62), 0.5, 0.14, BRONZE, M.Metal, model))
end

--[[
	The broach spire: an octagon of slate faces rising from the tower's
	square top to a point, with a sloping broach in each corner where the
	square turns into the octagon. Every face is a triangle between points,
	so no face needs a guessed rotation.
]]
local function spire(place: Place, parent: Instance)
	local base = TOWER_TOP
	local apothem = 8.4
	local R = apothem / math.cos(math.rad(22.5))
	local apex = V(T_CX, SPIRE_TOP, T_CZ)
	local verts: { Vector3 } = {}
	for k = 0, 7 do
		local a = math.rad(22.5 + 45 * k)
		table.insert(verts, V(T_CX + R * math.cos(a), base, T_CZ + R * math.sin(a)))
	end
	local function w(p: Vector3): Vector3
		return place(p).Position
	end
	for k = 1, 8 do
		local a, b = verts[k], verts[k % 8 + 1]
		Kit.triangle("Spire", w(a), w(b), w(apex), 0.7, Kit.weathered(SLATE, 0.05), M.Slate, parent)
	end
	-- Broaches: the diagonal faces are the ones centred on 45, 135, 225 and
	-- 315 degrees, and each corner of the square sits below one of them.
	local half = (T_X1 - T_X0) / 2
	for k = 0, 3 do
		local i = 2 * k + 1 -- verts[i], verts[i + 1] bound the diagonal face
		local a, b = verts[i], verts[i % 8 + 1]
		local mid = (a + b) / 2
		local peak = mid + (apex - mid) * 0.26
		local corner =
			V(T_CX + half * math.sign(mid.X - T_CX), base, T_CZ + half * math.sign(mid.Z - T_CZ))
		Kit.triangle(
			"Broach",
			w(corner),
			w(a),
			w(peak),
			0.6,
			Kit.weathered(SLATE, 0.05),
			M.Slate,
			parent
		)
		Kit.triangle(
			"Broach",
			w(corner),
			w(peak),
			w(b),
			0.6,
			Kit.weathered(SLATE, 0.05),
			M.Slate,
			parent
		)
	end
	-- The tower top under it, and a cornice round the edge.
	Kit.part(
		"TowerTop",
		V(T_X1 - T_X0, 0.6, T_Z1 - T_Z0),
		place(V(T_CX, base - 0.3, T_CZ)),
		DRESSED_DARK,
		M.Concrete,
		parent
	)
	for _, s in { -1, 1 } do
		Kit.part(
			"Cornice",
			V(T_X1 - T_X0 + 1.4, 0.9, 0.7),
			place(V(T_CX, base - 0.75, T_CZ + s * (half + 0.35))),
			DRESSED,
			M.Concrete,
			parent
		)
		Kit.part(
			"Cornice",
			V(0.7, 0.9, T_Z1 - T_Z0),
			place(V(T_CX + s * (half + 0.35), base - 0.75, T_CZ)),
			DRESSED,
			M.Concrete,
			parent
		)
	end
	-- A ball and a weathercock on the point.
	Kit.ball("SpireBall", w(apex + V(0, 0.6, 0)), 1.2, BRONZE, M.Metal, parent)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

function Church.build(pivot: CFrame, parent: Instance): Kit.Built
	Kit.reset(9151)
	wallSeed = 0
	local place = Kit.placer(pivot, FOUND_H)

	local model = Instance.new("Model")
	model.Name = "Church"
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
	-- The churchyard: its walls, gates, paths and the mausoleum are the
	-- grounds; the graves, trees and everything else loose in it the yard.
	local grounds = folder("Grounds")
	local yard = folder("Churchyard")

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
		Hang a door in an opening: a plank door with iron straps across it,
		the kind a church has. `into` is the way it swings open, `hingeToward`
		the jamb it hangs on.
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
		local door = Kit.door(frame, w, h, {
			parent = doors,
			hinge = hinge,
			swing = 1,
			gap = opts.gap,
			color = opts.color or OAK,
			panel = opts.panel or OAK_DARK,
			style = opts.style or "plank",
			thickness = opts.leaf or 0.45,
			startAngle = opts.ajar,
			openAngle = opts.openAngle,
			name = opts.name,
		})
		-- Strap hinges: long iron straps across the boards from the hinge
		-- side, riding on the leaf so they swing with it.
		local leaf = door:FindFirstChild("Leaf") :: BasePart?
		if leaf and opts.straps ~= false then
			local lcf, size = leaf.CFrame, leaf.Size
			for _, y in { -size.Y * 0.36, size.Y * 0.36 } do
				for _, face in { -1, 1 } do
					Kit.detail(
						Kit.part(
							"Strap",
							V(size.X * 0.8, 0.28, 0.08),
							lcf * CFrame.new(hinge * size.X * 0.1, y, face * (size.Z / 2 + 0.05)),
							C.IRON,
							M.Metal,
							door
						)
					)
				end
			end
		end
		return door
	end

	--------------------------------------------------------------------------
	-- Floors, plinth and steps
	--------------------------------------------------------------------------

	local base = FOUND_H
	Kit.slabWithHoles(
		"NaveFloor",
		L1,
		base,
		-OUT_X,
		OUT_X,
		EAST_OUT,
		WEST_OUT,
		{},
		FLOOR,
		M.Slate,
		place,
		interior
	)
	Kit.slabWithHoles(
		"TowerFloor",
		L1,
		base,
		T_X0,
		-OUT_X,
		T_Z0,
		T_Z1,
		{},
		FLOOR,
		M.Slate,
		place,
		interior
	)
	Kit.slabWithHoles(
		"ChancelFloor",
		CHOIR_Y,
		base + CHOIR_Y,
		-CH_OUT,
		CH_OUT,
		CH_EAST_OUT,
		EAST_OUT,
		{},
		FLOOR,
		M.Slate,
		place,
		interior
	)
	Kit.part(
		"Sanctuary",
		V(CH_IN * 2, SANCT_Y - CHOIR_Y, SANCT_Z - CH_EAST_IN),
		place(V(0, (CHOIR_Y + SANCT_Y) / 2, (SANCT_Z + CH_EAST_IN) / 2)),
		rgb(50, 46, 44),
		M.Marble,
		interior
	)
	Kit.slabWithHoles(
		"PorchFloor",
		L1,
		base,
		P_X0,
		P_X1,
		P_Z0,
		P_Z1,
		{},
		FLOOR,
		M.Slate,
		place,
		interior
	)
	Kit.slabWithHoles(
		"VestryFloor",
		L1,
		base,
		V_X0,
		V_X1,
		V_Z0,
		V_Z1,
		{},
		C.FLOOR,
		M.WoodPlanks,
		place,
		interior
	)
	-- The step up into the chancel from the vestry, under the door's swing.
	Kit.part(
		"VestryStep",
		V(1.5, CHOIR_Y, 4),
		place(V(V_X1 - 0.75, CHOIR_Y / 2, -32)),
		FLOOR,
		M.Slate,
		interior
	)

	local function step(x0: number, x1: number, z0: number, z1: number, top: number)
		Kit.part(
			"Step",
			V(x1 - x0, top - GROUND, z1 - z0),
			place(V((x0 + x1) / 2, (top + GROUND) / 2, (z0 + z1) / 2)),
			Kit.weathered(DRESSED_DARK, 0.05),
			M.Concrete,
			shell
		)
	end
	step(-6, 6, WEST_OUT, WEST_OUT + 1.6, L1)
	step(-7, 7, WEST_OUT + 1.6, WEST_OUT + 3.2, L1 - 1)
	step(P_X1, P_X1 + 1.6, 10.5, 17.5, L1)
	step(P_X1 + 1.6, P_X1 + 3.2, 10.5, 17.5, L1 - 1)
	step(-13, -7, V_Z0 - 4.5, V_Z0, L1)
	step(-13, -7, V_Z0 - 6, V_Z0 - 4.5, L1 - 1)

	-- A plinth course round the foot of the walls.
	local function plinth(axis: string, fixed: number, out: number, from: number, to: number)
		local len = to - from
		if len <= EPS then
			return
		end
		Kit.part(
			"Plinth",
			wsize(axis, len, 2.6, 0.6),
			place(wp(axis, fixed, (from + to) / 2, GROUND + 1.3, out * 0.3)),
			Kit.weathered(DRESSED_DARK, 0.05),
			M.Concrete,
			shell
		)
	end
	plinth("X", WEST_OUT, 1, T_X0, -4.3)
	plinth("X", WEST_OUT, 1, 4.3, OUT_X + 0.6)
	plinth("Z", OUT_X, 1, EAST_OUT, P_Z0)
	plinth("Z", OUT_X, 1, P_Z1, WEST_OUT)
	plinth("Z", P_X1, 1, P_Z0 - 0.6, 10.5)
	plinth("Z", P_X1, 1, 17.5, P_Z1 + 0.6)
	plinth("X", P_Z0, -1, P_X0, P_X1)
	plinth("X", P_Z1, 1, P_X0, P_X1)
	plinth("X", EAST_OUT, -1, CH_OUT, OUT_X + 0.6)
	plinth("Z", CH_OUT, 1, CH_EAST_OUT - 0.6, EAST_OUT)
	plinth("X", CH_EAST_OUT, -1, -CH_OUT, CH_OUT)
	plinth("Z", -CH_OUT, -1, CH_EAST_OUT - 0.6, V_Z0)
	plinth("X", V_Z0, -1, V_X0 - 0.6, -13)
	plinth("X", V_Z0, -1, -7, V_X1)
	plinth("Z", V_X0, -1, V_Z0, V_Z1)
	plinth("Z", -OUT_X, -1, EAST_OUT, T_Z0)
	plinth("X", T_Z0, -1, T_X0 - 0.6, -OUT_X)
	plinth("Z", T_X0, -1, T_Z0 - 0.6, T_Z1 + 0.6)

	--------------------------------------------------------------------------
	-- The west front
	--------------------------------------------------------------------------

	-- Two bands, because the door and the window above it are in the same
	-- stretch of wall: Kit.wall cuts one row of holes at a time.
	stoneWall({
		name = "WestWall",
		axis = "X",
		fixed = WEST_Z,
		from = -CLER_OUT,
		to = CLER_OUT,
		bottom = L1,
		top = 16,
		outward = 1,
		rooms = ROOMS,
		wins = {
			doorway(0, 4, L1, 11.5, true),
		},
	}, place, shell)
	stoneWall({
		name = "WestWall",
		axis = "X",
		fixed = WEST_Z,
		from = -CLER_OUT,
		to = CLER_OUT,
		bottom = 16,
		top = NAVE_TOP,
		outward = 1,
		rooms = ROOMS,
		wins = { lancet(0, 17.5, 6.4, 22.5, { lights = 2 }) },
	}, place, shell)
	Kit.triangle(
		"WestGable",
		place(V(-CLER_OUT, NAVE_TOP, WEST_Z)).Position,
		place(V(CLER_OUT, NAVE_TOP, WEST_Z)).Position,
		place(V(0, NAVE_RIDGE - 0.05, WEST_Z)).Position,
		WALL_T,
		Kit.weathered(STONE, 0.04),
		M.Cobblestone,
		shell
	)
	-- A blind round window in the gable: a ring of stone round a dark
	-- glass disc.
	do
		local cy = NAVE_TOP + 4.2
		local ring = 12
		for k = 0, ring - 1 do
			local a0, a1 = 2 * math.pi * k / ring, 2 * math.pi * (k + 1) / ring
			Kit.detail(
				Kit.rod(
					"Oculus",
					place(V(1.9 * math.cos(a0), cy + 1.9 * math.sin(a0), WEST_OUT + 0.15)).Position,
					place(V(1.9 * math.cos(a1), cy + 1.9 * math.sin(a1), WEST_OUT + 0.15)).Position,
					0.45,
					DRESSED,
					M.Concrete,
					shell
				)
			)
		end
		Kit.detail(
			Kit.disc(
				"OculusGlass",
				oriented(place, V(0, cy, WEST_OUT + 0.05), V(1, 0, 0), V(0, 0, 1)),
				3.6,
				0.12,
				GLASS[2],
				M.Glass,
				shell
			)
		)
	end
	-- Shafts either side of the west door, with ring capitals.
	for _, s in { -1, 1 } do
		local x = s * 4.55
		Kit.rod(
			"DoorShaft",
			place(V(x, L1 + 0.3, WEST_OUT + 0.25)).Position,
			place(V(x, 11.1, WEST_OUT + 0.25)).Position,
			0.6,
			DRESSED,
			M.Concrete,
			shell
		)
		Kit.detail(
			Kit.disc(
				"ShaftCap",
				place(V(x, 11.25, WEST_OUT + 0.25)),
				0.95,
				0.35,
				DRESSED,
				M.Concrete,
				shell
			)
		)
		Kit.detail(
			Kit.disc(
				"ShaftBase",
				place(V(x, L1 + 0.35, WEST_OUT + 0.25)),
				0.95,
				0.35,
				DRESSED,
				M.Concrete,
				shell
			)
		)
	end

	-- The aisles' west ends.
	stoneWall({
		name = "WestWall",
		axis = "X",
		fixed = WEST_Z,
		from = CLER_OUT,
		to = OUT_X,
		bottom = L1,
		top = AISLE_TOP,
		outward = 1,
		rooms = ROOMS,
	}, place, shell)
	underSlope(
		"WestWall",
		"X",
		WEST_Z,
		CLER_OUT,
		OUT_X,
		AISLE_TOP,
		AISLE_HIGH,
		AISLE_TOP,
		WALL_T,
		STONE,
		M.Cobblestone,
		place,
		shell
	)
	stoneWall({
		name = "WestWall",
		axis = "X",
		fixed = WEST_Z,
		from = -IN_X,
		to = -CLER_OUT,
		bottom = L1,
		top = AISLE_TOP,
		outward = 1,
		rooms = ROOMS,
		wins = { lancet(-11.9, 5.5, 3, 10) },
	}, place, shell)
	underSlope(
		"WestWall",
		"X",
		WEST_Z,
		-IN_X,
		-CLER_OUT,
		AISLE_TOP,
		aisleUnder(IN_X),
		AISLE_HIGH,
		WALL_T,
		STONE,
		M.Cobblestone,
		place,
		shell
	)

	--------------------------------------------------------------------------
	-- The aisle walls
	--------------------------------------------------------------------------

	local southWins: { Win } = {
		doorway(SOUTH_DOOR_Z, 2.2, L1, 8.5, true),
	}
	for _, z in { 2, -6, -22 } do
		table.insert(southWins, lancet(z, 5.5, 3, 10, { boarded = z == -22 }))
	end
	stoneWall({
		name = "SouthWall",
		axis = "Z",
		fixed = WALL_X,
		from = EAST_IN,
		to = WEST_IN,
		bottom = L1,
		top = AISLE_TOP,
		outward = 1,
		rooms = ROOMS,
		wins = southWins,
	}, place, shell)
	local northWins: { Win } = {}
	for _, z in { 10, 2, -6, -14, -22 } do
		table.insert(northWins, lancet(z, 5.5, 3, 10, { broken = z == 2, boarded = z == -14 }))
	end
	stoneWall({
		name = "NorthWall",
		axis = "Z",
		fixed = -WALL_X,
		from = EAST_IN,
		to = T_Z0,
		bottom = L1,
		top = AISLE_TOP,
		outward = -1,
		rooms = ROOMS,
		wins = northWins,
	}, place, shell)

	-- Wedges on the wall tops, up to the roofs' undersides.
	local function topWedge(
		name: string,
		xLow: number,
		yLow: number,
		xHigh: number,
		yHigh: number,
		z0: number,
		z1: number,
		parentTo: Instance
	)
		-- In the XY plane: the right angle under the high end.
		local zc = (z0 + z1) / 2
		Kit.rightTriangle(
			name,
			place(V(xHigh, yLow, zc)).Position,
			place(V(xHigh, yHigh, zc)).Position,
			place(V(xLow, yLow, zc)).Position,
			math.abs(z1 - z0),
			Kit.weathered(STONE, 0.04),
			M.Cobblestone,
			parentTo
		)
	end
	for _, s in { -1, 1 } do
		local z0 = if s > 0 then EAST_IN else EAST_IN
		local z1 = if s > 0 then WEST_IN else T_Z0
		topWedge("WallTop", s * OUT_X, AISLE_TOP, s * IN_X, aisleUnder(IN_X), z0, z1, shell)
		topWedge(
			"WallTop",
			s * CLER_OUT,
			NAVE_TOP,
			s * CLER_IN,
			naveUnder(CLER_IN),
			EAST_IN,
			WEST_IN,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- The arcades and the walls over them
	--------------------------------------------------------------------------

	for _, s in { -1, 1 } do
		local arches: { Win } = {}
		for _, z in BAY_ZS do
			table.insert(arches, {
				at = z,
				w = ARCH_W,
				sill = CAP_Y,
				spring = CAP_Y,
				r = ARCH_W * 2,
				kind = "open",
				hood = false,
			})
		end
		stoneWall({
			name = "Arcade",
			axis = "Z",
			fixed = s * ARCADE_X,
			from = EAST_IN,
			to = WEST_IN,
			bottom = CAP_Y,
			top = AISLE_HIGH,
			thickness = CLER_T,
			wins = arches,
			color = DRESSED_DARK,
			material = M.Concrete,
		}, place, interior)
		for _, z in BAY_ZS do
			archMould(
				"ArchRoll",
				"Z",
				s * ARCADE_X,
				z,
				ARCH_W,
				ARCH_W * 2,
				CAP_Y,
				-s * (CLER_T / 2 + 0.1),
				0.22,
				0.42,
				DRESSED,
				place,
				interior
			)
		end
		local clerestory: { Win } = {}
		for i, z in BAY_ZS do
			table.insert(
				clerestory,
				lancet(z, 23, 2.4, 26.2, { broken = (i + (if s > 0 then 1 else 0)) % 3 == 0 })
			)
		end
		stoneWall({
			name = "Clerestory",
			axis = "Z",
			fixed = s * ARCADE_X,
			from = EAST_IN,
			to = WEST_IN,
			bottom = AISLE_HIGH,
			top = NAVE_TOP,
			thickness = CLER_T,
			outward = s,
			wins = clerestory,
		}, place, shell)

		-- Columns: a square plinth, a round base, the shaft, a round capital
		-- and a square abacus under the arches.
		local function column(z: number, half: boolean)
			local x = s * ARCADE_X
			local c = Kit.weathered(DRESSED, 0.04)
			if half then
				-- Against an end wall: a column sunk to its middle in the wall,
				-- so half of it shows, with half a capital.
				Kit.rod(
					"Respond",
					place(V(x, 0.2, z)).Position,
					place(V(x, CAP_Y - 1.0, z)).Position,
					2.0,
					c,
					M.Concrete,
					interior
				)
				Kit.disc("Capital", place(V(x, CAP_Y - 0.7, z)), 2.7, 0.6, c, M.Concrete, interior)
				local zc = if z > 0 then z - 0.45 else z + 0.45
				Kit.part(
					"Abacus",
					V(3.0, 0.4, 0.9),
					place(V(x, CAP_Y - 0.2, zc)),
					c,
					M.Concrete,
					interior
				)
				return
			end
			Kit.part("ColumnPlinth", V(3.0, 0.6, 3.0), place(V(x, 0.3, z)), c, M.Concrete, interior)
			Kit.disc("ColumnBase", place(V(x, 0.8, z)), 2.9, 0.4, c, M.Concrete, interior)
			Kit.rod(
				"Column",
				place(V(x, 0.9, z)).Position,
				place(V(x, CAP_Y - 1.0, z)).Position,
				COL_D,
				c,
				M.Concrete,
				interior
			)
			Kit.disc("Capital", place(V(x, CAP_Y - 0.8, z)), 2.8, 0.5, c, M.Concrete, interior)
			Kit.disc("Capital", place(V(x, CAP_Y - 0.45, z)), 3.1, 0.3, c, M.Concrete, interior)
			Kit.part(
				"Abacus",
				V(3.2, 0.3, 3.2),
				place(V(x, CAP_Y - 0.15, z)),
				c,
				M.Concrete,
				interior
			)
		end
		for _, z in COLUMN_ZS do
			column(z, false)
		end
		column(WEST_IN, true)
		column(EAST_IN, true)
	end

	--------------------------------------------------------------------------
	-- The east end of the nave and aisles: the chancel arch
	--------------------------------------------------------------------------

	stoneWall({
		name = "ChancelArchWall",
		axis = "X",
		fixed = EAST_Z,
		from = -CLER_OUT,
		to = CLER_OUT,
		bottom = L1,
		top = NAVE_TOP,
		thickness = EAST_T,
		rooms = ROOMS,
		wins = { { at = 0, w = 5, sill = L1, spring = 12, r = 10, kind = "open", hood = false } },
	}, place, shell)
	archMould(
		"ArchRoll",
		"X",
		EAST_Z,
		0,
		5,
		10,
		12,
		EAST_T / 2 + 0.12,
		0.25,
		0.5,
		DRESSED,
		place,
		interior,
		true
	)
	Kit.triangle(
		"EastGable",
		place(V(-CLER_OUT, NAVE_TOP, EAST_Z)).Position,
		place(V(CLER_OUT, NAVE_TOP, EAST_Z)).Position,
		place(V(0, NAVE_RIDGE - 0.05, EAST_Z)).Position,
		EAST_T,
		Kit.weathered(STONE, 0.04),
		M.Cobblestone,
		shell
	)
	stoneWall({
		name = "EastWall",
		axis = "X",
		fixed = EAST_Z,
		from = CLER_OUT,
		to = OUT_X,
		bottom = L1,
		top = AISLE_TOP,
		thickness = EAST_T,
		outward = -1,
		rooms = ROOMS,
	}, place, shell)
	underSlope(
		"EastWall",
		"X",
		EAST_Z,
		CLER_OUT,
		OUT_X,
		AISLE_TOP,
		AISLE_HIGH,
		AISLE_TOP,
		EAST_T,
		STONE,
		M.Cobblestone,
		place,
		shell
	)
	stoneWall({
		name = "EastWall",
		axis = "X",
		fixed = EAST_Z,
		from = -OUT_X,
		to = -CLER_OUT,
		bottom = L1,
		top = AISLE_TOP,
		thickness = EAST_T,
		rooms = ROOMS,
		wins = { doorway(-12.5, 2, L1, 9, false) },
	}, place, shell)
	underSlope(
		"EastWall",
		"X",
		EAST_Z,
		-OUT_X,
		-CLER_OUT,
		AISLE_TOP,
		AISLE_TOP,
		AISLE_HIGH,
		EAST_T,
		STONE,
		M.Cobblestone,
		place,
		shell
	)

	--------------------------------------------------------------------------
	-- The chancel
	--------------------------------------------------------------------------

	stoneWall({
		name = "ChancelWall",
		axis = "Z",
		fixed = CH_WALL,
		from = CH_EAST_IN,
		to = EAST_OUT,
		bottom = L1,
		top = CH_TOP,
		thickness = CH_T,
		outward = 1,
		rooms = ROOMS,
		wins = { lancet(-34, 8, 2.8, 13), lancet(-45, 8, 2.8, 13) },
	}, place, shell)
	stoneWall({
		name = "ChancelWall",
		axis = "Z",
		fixed = -CH_WALL,
		from = CH_EAST_IN,
		to = EAST_OUT,
		bottom = L1,
		top = CH_TOP,
		thickness = CH_T,
		outward = -1,
		rooms = ROOMS,
		wins = {
			doorway(-32, 2, CHOIR_Y, CHOIR_Y + 8.5, false),
			lancet(-38, 15.5, 2.8, 19.5, { broken = true }),
			lancet(-46, 15.5, 2.8, 19.5),
		},
	}, place, shell)
	stoneWall({
		name = "ChancelEast",
		axis = "X",
		fixed = CH_EAST_Z,
		from = -CH_OUT,
		to = CH_OUT,
		bottom = L1,
		top = CH_TOP,
		thickness = CH_T,
		outward = -1,
		rooms = ROOMS,
		wins = { lancet(0, 8.5, 7.2, 15, { lights = 3 }) },
	}, place, shell)
	Kit.triangle(
		"ChancelGable",
		place(V(-CH_OUT, CH_TOP, CH_EAST_Z)).Position,
		place(V(CH_OUT, CH_TOP, CH_EAST_Z)).Position,
		place(V(0, CH_RIDGE - 0.05, CH_EAST_Z)).Position,
		CH_T,
		Kit.weathered(STONE, 0.04),
		M.Cobblestone,
		shell
	)
	for _, s in { -1, 1 } do
		topWedge(
			"WallTop",
			s * CH_OUT,
			CH_TOP,
			s * CH_IN,
			chancelUnder(CH_IN),
			CH_EAST_IN,
			EAST_OUT,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- The tower
	--------------------------------------------------------------------------

	local function belfryLouvre(at: number): Win
		return {
			at = at,
			w = 2,
			sill = BELFRY_Y + 2.5,
			spring = BELFRY_Y + 8.5,
			r = 4,
			kind = "louvre",
			hood = true,
		}
	end
	local function slit(at: number, sill: number): Win
		return {
			at = at,
			w = 0.7,
			sill = sill,
			spring = sill + 4.4,
			r = 1.4,
			kind = "slit",
			hood = true,
		}
	end
	-- Bands of the tower, low to high: each wall's openings in each band.
	-- Openings one above another in the same wall go in separate bands.
	local towerBands: { { bottom: number, top: number, front: { Win }, back: { Win }, left: { Win }, right: { Win } } } =
		{
			{
				bottom = L1,
				top = 12,
				front = { slit(T_CX, 6) },
				back = {},
				left = {},
				right = {
					doorway(T_CZ, 2, L1, 9, false),
				},
			},
			{
				bottom = 12,
				top = 22,
				front = {},
				back = { slit(T_CX, 15.5) },
				left = { slit(T_CZ, 13) },
				right = {},
			},
			{
				bottom = 22,
				top = BELFRY_Y,
				front = {},
				back = {},
				left = { slit(T_CZ, 30) },
				right = { slit(T_CZ, 23) },
			},
			{
				bottom = BELFRY_Y,
				top = TOWER_TOP,
				front = { belfryLouvre(T_CX) },
				back = { belfryLouvre(T_CX) },
				left = { belfryLouvre(T_CZ) },
				right = { belfryLouvre(T_CZ) },
			},
		}
	for _, band in towerBands do
		stoneWall({
			name = "TowerWall",
			axis = "X",
			fixed = T_Z1 - WALL_T / 2,
			from = T_X0,
			to = T_X1,
			bottom = band.bottom,
			top = band.top,
			outward = 1,
			wins = band.front,
		}, place, shell)
		stoneWall({
			name = "TowerWall",
			axis = "X",
			fixed = T_Z0 + WALL_T / 2,
			from = T_X0,
			to = T_X1,
			bottom = band.bottom,
			top = band.top,
			outward = -1,
			wins = band.back,
		}, place, shell)
		stoneWall({
			name = "TowerWall",
			axis = "Z",
			fixed = T_X0 + WALL_T / 2,
			from = T_IZ0,
			to = T_IZ1,
			bottom = band.bottom,
			top = band.top,
			outward = -1,
			wins = band.left,
		}, place, shell)
		-- The east wall is the aisle's north wall carried up: plastered on
		-- the aisle side below the aisle roof, outdoors above it.
		stoneWall({
			name = "TowerWall",
			axis = "Z",
			fixed = T_X1 - WALL_T / 2,
			from = T_IZ0,
			to = T_IZ1,
			bottom = band.bottom,
			top = band.top,
			outward = 1,
			rooms = if band.bottom < AISLE_TOP then ROOMS else nil,
			wins = band.right,
		}, place, shell)
	end
	towerStair(place, interior)
	bell(place, furniture)
	clock(place, shell)
	spire(place, shell)
	Furnish.weatherVane(spot(T_CX, SPIRE_TOP + 1.2, T_CZ), shell)

	--------------------------------------------------------------------------
	-- The south porch
	--------------------------------------------------------------------------

	stoneWall({
		name = "PorchWall",
		axis = "Z",
		fixed = P_X1 - P_T / 2,
		from = P_Z0,
		to = P_Z1,
		bottom = L1,
		top = P_TOP,
		thickness = P_T,
		outward = 1,
		wins = { { at = P_CZ, w = 2.5, sill = L1, spring = 5, r = 4, kind = "open", hood = true } },
	}, place, shell)
	Kit.triangle(
		"PorchGable",
		place(V(P_X1 - P_T / 2, P_TOP, P_Z0)).Position,
		place(V(P_X1 - P_T / 2, P_TOP, P_Z1)).Position,
		place(V(P_X1 - P_T / 2, porchUnder(P_CZ) - 0.05, P_CZ)).Position,
		P_T,
		Kit.weathered(STONE, 0.04),
		M.Cobblestone,
		shell
	)
	for _, s in { -1, 1 } do
		local z = if s < 0 then P_Z0 + P_T / 2 else P_Z1 - P_T / 2
		stoneWall({
			name = "PorchWall",
			axis = "X",
			fixed = z,
			from = P_X0,
			to = P_X1 - P_T,
			bottom = L1,
			top = P_TOP,
			thickness = P_T,
			outward = s,
		}, place, shell)
		-- The wall top under the roof: in the YZ plane this time.
		local zOut = if s < 0 then P_Z0 else P_Z1
		local zIn = if s < 0 then P_Z0 + P_T else P_Z1 - P_T
		Kit.rightTriangle(
			"WallTop",
			place(V((P_X0 + P_X1) / 2, P_TOP, zIn)).Position,
			place(V((P_X0 + P_X1) / 2, porchUnder(zIn), zIn)).Position,
			place(V((P_X0 + P_X1) / 2, P_TOP, zOut)).Position,
			P_X1 - P_X0,
			Kit.weathered(STONE, 0.04),
			M.Cobblestone,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- The vestry
	--------------------------------------------------------------------------

	stoneWall({
		name = "VestryWall",
		axis = "Z",
		fixed = V_X0 + V_T / 2,
		from = V_Z0,
		to = V_Z1,
		bottom = L1,
		top = V_LOW,
		thickness = V_T,
		outward = -1,
		rooms = ROOMS,
		wins = { lancet(-31, 4, 2, 7, { boarded = true }) },
	}, place, shell)
	topWedge("WallTop", V_X0, V_LOW, V_X0 + V_T, vestryUnder(V_X0 + V_T), V_Z0, V_Z1, shell)
	stoneWall({
		name = "VestryWall",
		axis = "X",
		fixed = V_Z0 + V_T / 2,
		from = V_X0 + V_T,
		to = V_X1,
		bottom = L1,
		top = V_LOW,
		thickness = V_T,
		outward = -1,
		rooms = ROOMS,
		wins = { lancet(-13.6, 4, 2.2, 7), doorway(-10, 2, L1, 8.5, true) },
	}, place, shell)
	underSlope(
		"VestryWall",
		"X",
		V_Z0 + V_T / 2,
		V_X0,
		V_X1,
		V_LOW,
		V_LOW,
		V_HIGH,
		V_T,
		STONE,
		M.Cobblestone,
		place,
		shell
	)

	--------------------------------------------------------------------------
	-- Roofs
	--------------------------------------------------------------------------

	local roofBoards = rgb(40, 32, 26)
	for _, s in { -1, 1 } do
		roofPitch(
			"NaveRoof",
			"Z",
			0,
			NAVE_RIDGE,
			s * (CLER_OUT + EAVE),
			naveUnder(CLER_OUT + EAVE),
			EAST_OUT - 0.4,
			WEST_OUT + 0.8,
			SLATE,
			place,
			shell,
			roofBoards
		)
		roofPitch(
			"ChancelRoof",
			"Z",
			0,
			CH_RIDGE,
			s * (CH_OUT + EAVE),
			chancelUnder(CH_OUT + EAVE),
			CH_EAST_OUT - 0.8,
			EAST_OUT,
			SLATE,
			place,
			shell,
			roofBoards
		)
		roofPitch(
			"PorchRoof",
			"X",
			P_CZ,
			porchUnder(P_CZ),
			P_CZ + s * ((P_Z1 - P_Z0) / 2 + 0.8),
			porchUnder(P_CZ + s * ((P_Z1 - P_Z0) / 2 + 0.8)),
			P_X0,
			P_X1 + 0.8,
			SLATE,
			place,
			shell,
			roofBoards
		)
	end
	-- The aisles: lean-tos off the wall over the arcade. The north one is cut
	-- short beside the tower.
	roofPitch(
		"AisleRoof",
		"Z",
		CLER_OUT,
		AISLE_HIGH,
		OUT_X + EAVE,
		aisleUnder(OUT_X + EAVE),
		EAST_OUT - 0.4,
		WEST_OUT + 0.8,
		SLATE,
		place,
		shell,
		roofBoards
	)
	roofPitch(
		"AisleRoof",
		"Z",
		-CLER_OUT,
		AISLE_HIGH,
		-(OUT_X + EAVE),
		aisleUnder(OUT_X + EAVE),
		EAST_OUT - 0.4,
		T_Z0,
		SLATE,
		place,
		shell,
		roofBoards
	)
	roofPitch(
		"AisleRoof",
		"Z",
		-CLER_OUT,
		AISLE_HIGH,
		-IN_X,
		aisleUnder(IN_X),
		T_Z0,
		WEST_OUT + 0.8,
		SLATE,
		place,
		shell,
		roofBoards
	)
	roofPitch(
		"VestryRoof",
		"Z",
		V_X1,
		V_HIGH,
		V_X0 - 1,
		vestryUnder(V_X0 - 1),
		V_Z0 - 0.8,
		V_Z1,
		SLATE,
		place,
		shell,
		roofBoards
	)
	-- Round ridge tiles along the tops.
	Kit.rod(
		"RidgeTiles",
		place(V(0, NAVE_RIDGE + ROOF_T / math.cos(PITCH), EAST_OUT - 0.4)).Position,
		place(V(0, NAVE_RIDGE + ROOF_T / math.cos(PITCH), WEST_OUT + 0.8)).Position,
		1.1,
		SLATE,
		M.Slate,
		shell
	)
	Kit.rod(
		"RidgeTiles",
		place(V(0, CH_RIDGE + ROOF_T / math.cos(PITCH), CH_EAST_OUT - 0.8)).Position,
		place(V(0, CH_RIDGE + ROOF_T / math.cos(PITCH), EAST_OUT)).Position,
		1.0,
		SLATE,
		M.Slate,
		shell
	)
	Kit.rod(
		"RidgeTiles",
		place(V(P_X0, porchUnder(P_CZ) + ROOF_T / math.cos(P_PITCH), P_CZ)).Position,
		place(V(P_X1 + 0.8, porchUnder(P_CZ) + ROOF_T / math.cos(P_PITCH), P_CZ)).Position,
		0.8,
		SLATE,
		M.Slate,
		shell
	)

	--------------------------------------------------------------------------
	-- Buttresses
	--------------------------------------------------------------------------

	local tall = { { 18, 2.5 }, { 38, 1.5 } }
	local low = { { 8, 2.0 }, { 13, 1.2 } }
	local chancelStages = { { 9, 1.8 }, { 17, 1.1 } }
	buttress(V(T_X0 + 1, GROUND, T_Z1), FRONT, 2, tall, place, shell)
	buttress(V(T_X0, GROUND, T_Z1 - 1), LEFT, 2, tall, place, shell)
	buttress(V(T_X0, GROUND, T_Z0 + 1), LEFT, 2, tall, place, shell)
	buttress(V(T_X0 + 1, GROUND, T_Z0), BACK, 2, tall, place, shell)
	buttress(V(T_X1 - 1, GROUND, T_Z1), FRONT, 2, tall, place, shell)
	buttress(V(OUT_X - 1, GROUND, WEST_OUT), FRONT, 2, low, place, shell)
	buttress(V(OUT_X, GROUND, WEST_OUT - 1), RIGHT, 2, low, place, shell)
	for _, z in { 22, 6, -2, -10, -18 } do
		buttress(V(OUT_X, GROUND, z), RIGHT, 1.8, low, place, shell)
	end
	for _, z in { 6, -2, -10, -18 } do
		buttress(V(-OUT_X, GROUND, z), LEFT, 1.8, low, place, shell)
	end
	buttress(V(CH_OUT, GROUND, -39.5), RIGHT, 1.6, chancelStages, place, shell)
	buttress(V(-CH_OUT, GROUND, -48), LEFT, 1.6, chancelStages, place, shell)
	for _, s in { -1, 1 } do
		buttress(V(s * (CH_OUT - 0.8), GROUND, CH_EAST_OUT), BACK, 1.6, chancelStages, place, shell)
		buttress(
			V(s * CH_OUT, GROUND, CH_EAST_OUT + 0.8),
			V(s, 0, 0),
			1.6,
			chancelStages,
			place,
			shell
		)
	end

	--------------------------------------------------------------------------
	-- Doors
	--------------------------------------------------------------------------

	-- The west doors: a pair, opening in.
	for _, s in { -1, 1 } do
		local frame = place(V(s * 2, L1 + 11.5 / 2, WEST_Z)) * CFrame.new(Vector3.zero, BACK)
		local right = BACK:Cross(Vector3.yAxis)
		local hinge = if right:Dot(V(s, 0, 0)) >= 0 then 1 else -1
		local door = Kit.door(frame, 4, 11.5, {
			parent = doors,
			hinge = hinge,
			swing = 1,
			color = OAK,
			panel = OAK_DARK,
			style = "plank",
			thickness = 0.55,
			gap = 0.12,
			openAngle = 92,
			name = "WestDoor",
		})
		local leaf = door:FindFirstChild("Leaf") :: BasePart?
		if leaf then
			for _, y in { -3.6, 0, 3.6 } do
				for _, face in { -1, 1 } do
					Kit.detail(
						Kit.part(
							"Strap",
							V(3.2, 0.3, 0.08),
							leaf.CFrame * CFrame.new(hinge * 0.35, y, face * 0.31),
							C.IRON,
							M.Metal,
							door
						)
					)
				end
			end
			-- Clawed at from inside, low down by the meeting edge, between the
			-- straps. Parented to the door so they swing with the leaf.
			if s > 0 then
				Decor.scratches(leaf.CFrame * CFrame.new(-hinge * 0.9, -1.8, -0.275), door, 2.4)
			end
		end
	end
	hang("Z", WALL_X, SOUTH_DOOR_Z, L1, 4.4, 8.5, LEFT, FRONT, WALL_T, { name = "SouthDoor" })
	hang("Z", T_X1 - WALL_T / 2, T_CZ, L1, 4, 9, LEFT, FRONT, WALL_T, { name = "TowerDoor" })
	hang("X", EAST_Z, -12.5, L1, 4, 9, BACK, LEFT, EAST_T, { name = "VestryDoor" })
	hang("Z", -CH_WALL, -32, CHOIR_Y, 4, 8.5, LEFT, BACK, CH_T, { name = "VestryDoor" })
	-- Opening out, it stops short of flat so it clears the plinth.
	hang(
		"X",
		V_Z0 + V_T / 2,
		-10,
		L1,
		4,
		8.5,
		BACK,
		RIGHT,
		V_T,
		{ name = "VestryOuterDoor", openAngle = 85 }
	)

	--------------------------------------------------------------------------
	-- The nave's roof timbers
	--------------------------------------------------------------------------

	-- Arch-braced trusses over every column: principal rafters under the
	-- boards, a collar, posts down the walls onto stone corbels carved as
	-- heads, and a curved brace each side from post to collar, laid as short
	-- straight timbers round the curve.
	local timber = rgb(44, 34, 27)
	local collarY = 35.4
	for _, z in COLUMN_ZS do
		for _, sx in { -1, 1 } do
			local foot = V(sx * (CLER_IN - 0.1), naveUnder(CLER_IN) - 1.0, z)
			local top = V(0, NAVE_RIDGE - 1.0, z)
			beam("Rafter", foot, top, 0.8, 1.0, V(0, 1, 0), timber, M.Wood, place, interior)
			beam(
				"WallPost",
				V(sx * (CLER_IN - 0.45), 24.4, z),
				V(sx * (CLER_IN - 0.45), naveUnder(CLER_IN) - 0.9, z),
				0.8,
				0.7,
				V(sx, 0, 0),
				timber,
				M.Wood,
				place,
				interior
			)
			Kit.part(
				"Corbel",
				V(1.3, 1.0, 1.3),
				place(V(sx * (CLER_IN - 0.6), 23.9, z)),
				DRESSED,
				M.Concrete,
				interior
			)
			Kit.detail(
				Kit.ball(
					"CorbelHead",
					place(V(sx * (CLER_IN - 0.9), 23.2, z)).Position,
					1.0,
					DRESSED_DARK,
					M.Concrete,
					interior
				)
			)
			local prev = V(sx * (CLER_IN - 0.8), 26, z)
			for k = 1, 4 do
				local th = math.pi / 2 * k / 4
				local nxt = V(
					sx * (CLER_IN - 0.8) * math.cos(th),
					26 + (collarY - 0.6 - 26) * math.sin(th),
					z
				)
				beam(
					"ArchBrace",
					prev,
					nxt,
					0.7,
					0.6,
					V(0, 0, 1):Cross(nxt - prev),
					timber,
					M.Wood,
					place,
					interior
				)
				prev = nxt
			end
		end
		local reach = (NAVE_RIDGE - 1.0 - collarY) / FALL
		beam(
			"Collar",
			V(-reach, collarY, z),
			V(reach, collarY, z),
			0.8,
			0.8,
			V(0, 1, 0),
			timber,
			M.Wood,
			place,
			interior
		)
	end
	for _, sx in { -1, 1 } do
		local x = sx * 3.8
		local y = NAVE_RIDGE - 1.0 - 3.8 * FALL - 0.7
		beam(
			"Purlin",
			V(x, y, EAST_IN),
			V(x, y, WEST_IN),
			0.7,
			0.9,
			V(sx * math.sin(PITCH), math.cos(PITCH), 0),
			timber,
			M.Wood,
			place,
			interior
		)
	end
	beam(
		"RidgeBeam",
		V(0, NAVE_RIDGE - 1.6, EAST_IN),
		V(0, NAVE_RIDGE - 1.6, WEST_IN),
		0.7,
		1.0,
		V(0, 1, 0),
		timber,
		M.Wood,
		place,
		interior
	)

	-- The chancel's ceiling: a wagon vault of boards on a round arch from
	-- wall top to wall top, with ribs across it and a carved boss where each
	-- rib crosses the crown.
	do
		local rise = 5.2
		local n = 10
		local function arcPoint(k: number): Vector3
			local th = math.pi * k / n
			return V(-CH_IN * math.cos(th), CH_TOP + rise * math.sin(th), 0)
		end
		for k = 0, n - 1 do
			local a, bb = arcPoint(k), arcPoint(k + 1)
			local mid = (a + bb) / 2
			local along = V(0, 0, 1)
			local across = (bb - a).Unit
			Kit.part(
				"WagonBoards",
				V(EAST_OUT - CH_EAST_IN, 0.3, (bb - a).Magnitude + 0.05),
				oriented(
					place,
					V(mid.X, mid.Y, (EAST_OUT + CH_EAST_IN) / 2) + along:Cross(across) * 0.15,
					along,
					along:Cross(across)
				),
				Kit.weathered(rgb(50, 38, 30), 0.05),
				M.WoodPlanks,
				interior
			)
		end
		for _, z in { -31.5, -36.5, -41.5, -46.5 } do
			for k = 0, n - 1 do
				local a, bb = arcPoint(k), arcPoint(k + 1)
				Kit.detail(
					Kit.rod(
						"WagonRib",
						place(V(a.X * 0.97, a.Y - 0.2, z)).Position,
						place(V(bb.X * 0.97, bb.Y - 0.2, z)).Position,
						0.4,
						timber,
						M.Wood,
						interior
					)
				)
			end
			Kit.detail(
				Kit.ball(
					"RoofBoss",
					place(V(0, CH_TOP + rise - 0.35, z)).Position,
					0.8,
					BRONZE,
					M.Metal,
					interior
				)
			)
		end
		-- The triangle of wall under the arch at the chancel's west end,
		-- closing the vault against the nave's east gable.
	end

	--------------------------------------------------------------------------
	-- Furniture
	--------------------------------------------------------------------------

	local function against(m: Model): Model
		return Furnish.backTo(m, 0.3)
	end
	local function wallAt(x: number, y: number, z: number, face: Vector3): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face)
	end
	local function floorAt(x: number, y: number, z: number): CFrame
		return place(V(x, y, z))
	end

	-- A runner down the middle aisle, torn in two, and ledger stones let
	-- into the floor where the old families are buried.
	Decor.rug(spot(0, L1, 13, BACK), dressing, { width = 3, length = 24, color = rgb(62, 24, 22) })
	Decor.rug(
		spot(0.2, L1, -12, BACK),
		dressing,
		{ width = 3, length = 14, color = rgb(58, 24, 22) }
	)
	for _, lz in { 25, -2.5, -22 } do
		Kit.detail(
			Kit.part(
				"Flags",
				V(2.4, 0.06, 4.4),
				place(V(if lz == -2.5 then 0 else -0.2, L1 + 0.03, lz)),
				rgb(42, 40, 38),
				M.Slate,
				dressing
			)
		)
	end

	-- Pews, two blocks down the nave, and a few in each aisle. Some are
	-- knocked askew, one has gone over on its face, one is missing. The
	-- nave pews stop short of the column plinths, 6.5 out from the middle.
	local rows = { 19.5, 16.5, 11.5, 8.5, 3.5, 0.5, -4.5, -7.5, -12.5, -15.5 }
	for i, z in rows do
		for _, sx in { -1, 1 } do
			local x = sx * 4.1
			if i == 6 and sx < 0 then
				-- This one is gone; its pieces are here.
				Decor.rubble(floorAt(x, L1, z), dressing, { radius = 1.4, stone = rgb(52, 40, 30) })
				continue
			end
			if i == #rows and sx > 0 then
				-- Gone over on its face toward the altar.
				Furnish.pew(
					spot(x, L1 + 1.1, z) * CFrame.Angles(math.rad(-88), 0, 0),
					furniture,
					{ length = 4.4 }
				)
				continue
			end
			local skew = if (i == 3 and sx > 0) or (i == 9 and sx < 0) then math.rad(7 * sx) else 0
			Furnish.pew(spot(x, L1, z) * CFrame.Angles(0, skew, 0), furniture, { length = 4.4 })
		end
	end
	for _, z in { 11.5, 8.5, 3.5, 0.5, -4.5 } do
		Furnish.pew(spot(-12.1, L1, z), furniture, { length = 5.0 })
	end
	for _, z in { 8.5, 3.5, 0.5, -4.5 } do
		Furnish.pew(spot(12.1, L1, z), furniture, { length = 5.0 })
	end

	-- The west end: the font by the tower door, the organ in the south
	-- aisle with its door toward the nave.
	Furnish.font(floorAt(-11.8, L1, 27.2), furniture)
	local _, organSpot =
		Furnish.organ(spot(12.0, L1, 26.4, BACK), furniture, { doorSide = -1, hingeFront = true })
	hide(organSpot)

	-- The east end of the nave: pulpit and lectern either side of the
	-- chancel arch, the hymn board at the end of the south aisle, where the
	-- wall is clear of the arch and its respond, candle stands.
	Furnish.pulpit(spot(-3.8, L1, -21.4, FRONT), furniture)
	Furnish.eagleLectern(spot(4.2, L1, -21.6, FRONT), furniture)
	Decor.hymnBoard(wallAt(12, 7, EAST_IN + 0.1, FRONT), dressing)
	Decor.candleStand(floorAt(6.3, L1, -24.6), furniture)
	Decor.candleStand(floorAt(2.1, L1, -24.9), furniture, { stub = true })

	-- The aisles: the tomb in the north, the confessional in the south.
	Furnish.tombChest(floorAt(-12.9, L1, -14), furniture)
	Decor.candleStand(floorAt(-10.4, L1, -19.4), furniture, { stub = true })
	local booth, booths = Furnish.confessional(spot(IN_X, L1, -14, LEFT), furniture)
	against(booth)
	for _, spotOf in booths do
		hide(spotOf)
	end

	-- The chancel: stalls either side, the rail, the altar, candle stands.
	against(Furnish.choirStall(spot(CH_IN, CHOIR_Y, -33.5, LEFT), furniture, { length = 7 }))
	against(Furnish.choirStall(spot(-CH_IN, CHOIR_Y, -38.2, RIGHT), furniture, { length = 6 }))
	-- The gap between the two runs is a player's width and a bit.
	for _, x in { -3.8, 3.8 } do
		Furnish.altarRail(spot(x, CHOIR_Y, SANCT_Z + 0.35, FRONT), furniture, { length = 4.0 })
	end
	local altar, underAltar = Furnish.altar(spot(0, SANCT_Y, CH_EAST_IN, FRONT), furniture)
	against(altar)
	hide(underAltar)
	for _, x in { -4.6, 4.6 } do
		Decor.candleStand(floorAt(x, SANCT_Y, -48.2), furniture, { height = 4.4 })
	end

	-- On the walls: memorials, hatchments high on the arcade.
	Decor.memorial(wallAt(-IN_X + 0.1, 8.2, 6, RIGHT), dressing)
	Decor.memorial(wallAt(-IN_X + 0.1, 8.2, -10, RIGHT), dressing, { width = 2.2, height = 2.4 })
	Decor.memorial(wallAt(IN_X - 0.1, 8.2, -2, LEFT), dressing)
	Decor.memorial(wallAt(IN_X - 0.1, 8.2, 6, LEFT), dressing, { width = 2.0, height = 2.6 })
	Decor.memorial(wallAt(CH_IN - 0.1, 7.4, -40, LEFT), dressing)
	for _, sx in { -1, 1 } do
		for _, z in { 14, -2 } do
			Decor.hatchment(wallAt(sx * CLER_IN, 17.6, z, V(-sx, 0, 0)), dressing)
		end
	end

	-- Coronas on long chains from the ridge beam between the trusses, cold.
	-- Hung from the collars their roses would sit inside the arch braces.
	for _, z in { 18, 2, -14 } do
		Decor.chandelier(
			place(V(0, NAVE_RIDGE - 2.12, z)),
			dressing,
			{ drop = 19, radius = 2.8, arms = 8 }
		)
	end

	-- The tower's ground floor: a coffin on its bier under the stair, a
	-- parish chest in the corner.
	local _, underBier = Furnish.bier(spot(-24, L1, 21.3, BACK), furniture)
	hide(underBier)
	Furnish.trunk(spot(-19.3, L1, 18.0, FRONT), furniture)

	-- The vestry: a wardrobe of vestments, a chest, a coat stand with the
	-- cassock still on it.
	local robe, robeSpot =
		Furnish.wardrobe(spot(V_X0 + V_T, L1, -38.7, RIGHT), furniture, { name = "VestmentPress" })
	against(robe)
	hide(robeSpot)
	Furnish.hallStand(floorAt(-9.4, L1, -28.8), furniture)

	-- The porch: stone benches along both walls, the notice board.
	for _, sz in { -1, 1 } do
		local z = P_CZ + sz * ((P_Z1 - P_Z0) / 2 - P_T - 0.6)
		Kit.part(
			"PorchBench",
			V(P_X1 - P_T - P_X0 - 0.4, 0.4, 1.2),
			place(V((P_X0 + P_X1 - P_T) / 2, 2.0, z)),
			DRESSED,
			M.Concrete,
			shell
		)
		for _, x in { P_X0 + 1, P_X1 - P_T - 1 } do
			Kit.part(
				"PorchBenchLeg",
				V(0.6, 1.8, 1.0),
				place(V(x, 0.9, z)),
				DRESSED_DARK,
				M.Concrete,
				shell
			)
		end
	end
	Decor.noticeBoard(wallAt(OUT_X, 5.4, 17.3, RIGHT), dressing, { width = 1.6, height = 2.2 })

	--------------------------------------------------------------------------
	-- Dirt, damage and worse
	--------------------------------------------------------------------------

	for _, st in
		{
			{ -5, 22, 2.6 },
			{ 9, 2, 2.2 },
			{ -2, -8, 1.8 },
			{ 12, -20, 2.4 },
			{ -24, 26, 2 },
			{ 2, -44, 1.6 },
		}
	do
		Decor.stain(floorAt(st[1], if st[2] < -40 then SANCT_Y else L1, st[2]), dressing, st[3])
	end
	-- Something dragged from the confessional toward the vestry.
	Decor.smear(
		place(V(9.5, L1 + 0.05, -13)).Position,
		place(V(0.5, L1 + 0.05, -24.5)).Position,
		dressing,
		1.2,
		C.BLOOD_OLD
	)
	Decor.stain(floorAt(9.8, L1, -13.4), dressing, 1.2, C.BLOOD_OLD)
	Decor.rubble(floorAt(12.4, L1, -22.6), dressing, { radius = 1.8 })
	Decor.rubble(floorAt(-4.6, L1, -9.7), dressing, { radius = 1.0 })
	Decor.rubble(floorAt(-12.4, L1, 15.8), dressing, { radius = 1.1 })
	type WallMark = { x: number, y: number, z: number, face: Vector3 }
	local drips: { WallMark } = {
		{ x = -IN_X + 0.1, y = 11, z = 2, face = RIGHT },
		{ x = IN_X - 0.1, y = 11, z = -6, face = LEFT },
		{ x = IN_X - 0.1, y = 11, z = -22, face = LEFT },
		{ x = CH_IN - 0.1, y = 20, z = -45, face = LEFT },
	}
	for _, d in drips do
		Decor.drips(wallAt(d.x, d.y, d.z, d.face), dressing, 2.6, 4.5, rgb(46, 42, 34))
	end
	local peels: { WallMark } = {
		{ x = -IN_X + 0.1, y = 11, z = -2.5, face = RIGHT },
		{ x = IN_X - 0.1, y = 10.5, z = 10, face = LEFT },
		{ x = -IN_X + 0.1, y = 10.2, z = -18, face = RIGHT },
	}
	for _, pl in peels do
		Decor.peel(wallAt(pl.x, pl.y, pl.z, pl.face), dressing, PLASTER)
	end
	Decor.scratches(wallAt(-CH_IN + 0.02, 4.6, -44.5, RIGHT), dressing, 2.4)

	--------------------------------------------------------------------------
	-- The churchyard
	--------------------------------------------------------------------------

	-- A frame on the ground at house point `a` with its +X toward `b`, and
	-- how far that is: what the walls, railings and paths are laid along.
	local function run(a: Vector3, b: Vector3): (CFrame, number)
		local d = b - a
		return oriented(place, a, d, Vector3.yAxis), d.Magnitude
	end
	local function ground(x: number, z: number): Vector3
		return V(x, GROUND, z)
	end
	local function wall(a: Vector3, b: Vector3)
		local at, len = run(a, b)
		Yard.stoneWall(at, len, grounds)
	end
	local function railings(a: Vector3, b: Vector3)
		local at, len = run(a, b)
		Yard.railings(at, len, grounds)
	end
	local function path(a: Vector3, b: Vector3, width: number, style: string)
		local at, len = run(a, b)
		Yard.path(at, len, width, grounds, { style = style })
	end
	local function pier(x: number, z: number)
		Yard.pier(place(ground(x, z)), grounds)
	end

	-- The front, on the lane: railings either side of the lych-gate, stone
	-- wall beyond them to the corners.
	local PIER = 1.2 -- half a pier
	for _, x in { YARD_X0, -30, -6.6, 6.6, 30, YARD_X1 } do
		pier(x, YARD_Z1)
	end
	wall(ground(YARD_X0 + PIER, YARD_Z1), ground(-30 - PIER, YARD_Z1))
	railings(ground(-30 + PIER, YARD_Z1), ground(-6.6 - PIER, YARD_Z1))
	railings(ground(6.6 + PIER, YARD_Z1), ground(30 - PIER, YARD_Z1))
	wall(ground(30 + PIER, YARD_Z1), ground(YARD_X1 - PIER, YARD_Z1))
	Yard.lychGate(spot(0, GROUND, YARD_Z1, FRONT), grounds, doors)

	-- The south side, whole.
	pier(YARD_X1, YARD_Z0)
	wall(ground(YARD_X1, YARD_Z1 - PIER), ground(YARD_X1, YARD_Z0 + PIER))

	-- The back, with a wicket gate out to the fields behind the vestry.
	local WICKET_X, WICKET_W = -10, 3.6
	pier(WICKET_X + WICKET_W / 2 + PIER, YARD_Z0)
	pier(WICKET_X - WICKET_W / 2 - PIER, YARD_Z0)
	pier(YARD_X0, YARD_Z0)
	wall(ground(YARD_X1 - PIER, YARD_Z0), ground(WICKET_X + WICKET_W / 2 + 2 * PIER, YARD_Z0))
	wall(ground(WICKET_X - WICKET_W / 2 - 2 * PIER, YARD_Z0), ground(YARD_X0 + PIER, YARD_Z0))
	do
		local centre = place(V(WICKET_X, GROUND + 0.4 + 2.3, YARD_Z0))
		Kit.door(centre * CFrame.new(Vector3.zero, FRONT), WICKET_W, 4.6, {
			parent = doors,
			hinge = 1,
			swing = 1,
			thickness = 0.3,
			color = Kit.weathered(OAK, 0.06),
			panel = OAK_DARK,
			style = "plank",
			gap = 0.1,
			openAngle = 88,
			name = "WicketGate",
		})
	end

	-- The north side, where a length of the wall has come down.
	local GAP0, GAP1 = -31, -23
	wall(ground(YARD_X0, YARD_Z0 + PIER), ground(YARD_X0, GAP0))
	wall(ground(YARD_X0, GAP1), ground(YARD_X0, YARD_Z1 - PIER))
	local WALL_RUBBLE = rgb(72, 70, 64)
	Decor.rubble(
		place(ground(YARD_X0 + 2.2, (GAP0 + GAP1) / 2)),
		yard,
		{ radius = 2.4, stone = WALL_RUBBLE }
	)
	Decor.rubble(
		place(ground(YARD_X0 - 2.0, GAP0 + 2.2)),
		yard,
		{ radius = 1.6, stone = WALL_RUBBLE }
	)

	-- Paths: flagstones from the lych-gate to the west door and round to
	-- the porch; gravel on round the back to the vestry door and the
	-- mausoleum.
	local STEPS_FOOT = WEST_OUT + 3.2
	local SIDE_PATH_X = 31.6
	path(ground(0, YARD_Z1 + 3.4), ground(0, STEPS_FOOT), 5, "flags")
	path(ground(2.5, 46), ground(SIDE_PATH_X + 2, 46), 4, "flags")
	path(ground(SIDE_PATH_X, 44), ground(SIDE_PATH_X, 9), 4, "flags")
	path(ground(SIDE_PATH_X, 9), ground(SIDE_PATH_X, -58.25), 3.5, "gravel")
	path(ground(46, -60), ground(-11.75, -60), 3.5, "gravel")
	path(ground(-10, V_Z0 - 6), ground(-10, -58.25), 3.5, "gravel")
	local MAUSOLEUM_X, MAUSOLEUM_Z = 44, -78
	path(ground(MAUSOLEUM_X, -61.75), ground(MAUSOLEUM_X, MAUSOLEUM_Z + 10.4), 3, "gravel")

	-- The mausoleum at the back, facing the church.
	hide(Yard.mausoleum(spot(MAUSOLEUM_X, GROUND, MAUSOLEUM_Z, FRONT), grounds, doors, yard))

	-- An open grave, dug and left, and two new ones beside it.
	Yard.openGrave(spot(13, GROUND, -71, FRONT), yard)
	for _, x in { 19.2, 23.4 } do
		Yard.grave(
			spot(x, GROUND, -66.5, FRONT),
			yard,
			{ style = "wooden", plot = "fresh", length = 6 }
		)
	end

	-- The trees: an old yew by the gate, three dead ones.
	Yard.yew(place(ground(20, 55)), yard)
	local perches: { CFrame } = {}
	for _, t in
		{
			{ x = -44, z = 50, seed = 3, h = 20 },
			{ x = 48, z = -30, seed = 5, h = 17 },
			{ x = -48, z = -74, seed = 11, h = 22 },
		}
	do
		local _, tips =
			Yard.deadTree(place(ground(t.x, t.z)), yard, { seed = t.seed, height = t.h })
		for i = 1, math.min(2, #tips) do
			table.insert(perches, tips[i])
		end
	end

	-- The rest: the old cross, a sundial, benches by the path, two lamps.
	Yard.churchyardCross(spot(42, GROUND, 18, FRONT), yard)
	Yard.sundial(place(ground(40, 38)), yard)
	Yard.bench(spot(-5.4, GROUND, 52, RIGHT), yard)
	Yard.bench(spot(5.4, GROUND, 52, LEFT), yard)
	Yard.lampPost(place(ground(-3.6, 58)), yard)
	Yard.lampPost(place(ground(3.6, 42)), yard)

	-- The graves, in rows wherever nothing else is. Each plot is the stone
	-- at its west end and its length back toward the east, and it goes in
	-- only if none of it falls on the church, a path, a gate's swing or
	-- anything placed above.
	type Rect = { x0: number, x1: number, z0: number, z1: number }
	local keepOut: { Rect } = {
		{ x0 = -21, x1 = 21, z0 = -31, z1 = STEPS_FOOT + 1.5 }, -- nave, aisles, west steps
		{ x0 = -37, x1 = -12, z0 = 11, z1 = 35 }, -- tower
		{ x0 = 15, x1 = 30, z0 = 5, z1 = 23 }, -- porch and its steps
		{ x0 = -11, x1 = 11, z0 = -56, z1 = -26 }, -- chancel
		{ x0 = -21, x1 = -5, z0 = -53, z1 = -26 }, -- vestry and its steps
		{ x0 = -4.5, x1 = 4.5, z0 = STEPS_FOOT, z1 = YARD_Z1 + 6 }, -- paths
		{ x0 = 0, x1 = SIDE_PATH_X + 4, z0 = 43, z1 = 49 },
		{ x0 = SIDE_PATH_X - 3.5, x1 = SIDE_PATH_X + 3.5, z0 = -63, z1 = 49 },
		{ x0 = -13.5, x1 = 48, z0 = -63.5, z1 = -56.5 },
		{ x0 = -13.5, x1 = -6.5, z0 = -63.5, z1 = V_Z0 },
		{ x0 = MAUSOLEUM_X - 3, x1 = MAUSOLEUM_X + 3, z0 = -69, z1 = -60 },
		{ x0 = -9, x1 = 9, z0 = 58, z1 = YARD_Z1 + 6 }, -- lych-gate
		{ x0 = WICKET_X - 5, x1 = WICKET_X + 5, z0 = YARD_Z0, z1 = YARD_Z0 + 9 }, -- wicket gate
		{ x0 = MAUSOLEUM_X - 8, x1 = MAUSOLEUM_X + 8, z0 = -87, z1 = -66 },
		{ x0 = 6, x1 = 27, z0 = -79, z1 = -64 }, -- the open grave and the new ones
		{ x0 = -48, x1 = -40, z0 = 46, z1 = 54 }, -- tree trunks
		{ x0 = 44, x1 = 52, z0 = -34, z1 = -26 },
		{ x0 = -52, x1 = -44, z0 = -78, z1 = -70 },
		{ x0 = 16, x1 = 24, z0 = 51, z1 = 59 },
		{ x0 = 36, x1 = 47, z0 = 13, z1 = 23 }, -- the old cross
		{ x0 = 37, x1 = 43, z0 = 35, z1 = 41 }, -- sundial
		{ x0 = -8.5, x1 = -3, z0 = 48.5, z1 = 55.5 }, -- benches
		{ x0 = 3, x1 = 8.5, z0 = 48.5, z1 = 55.5 },
		{ x0 = -5.5, x1 = -1.5, z0 = 56, z1 = 60 }, -- lamps
		{ x0 = 1.5, x1 = 5.5, z0 = 40, z1 = 44 },
		{ x0 = YARD_X0 - 1, x1 = YARD_X0 + 6, z0 = GAP0 - 2, z1 = GAP1 + 2 }, -- the fallen wall
	}
	local function free(r: Rect): boolean
		if
			r.x0 < YARD_X0 + 2.5
			or r.x1 > YARD_X1 - 2.5
			or r.z0 < YARD_Z0 + 2.5
			or r.z1 > YARD_Z1 - 2.5
		then
			return false
		end
		for _, k in keepOut do
			if r.x0 < k.x1 and r.x1 > k.x0 and r.z0 < k.z1 and r.z1 > k.z0 then
				return false
			end
		end
		return true
	end

	local wear = Kit.wear()
	local STYLES = {
		"round",
		"round",
		"round",
		"round",
		"gabled",
		"gabled",
		"cross",
		"celtic",
		"obelisk",
		"column",
		"wooden",
		"chest",
	}
	local HEIGHTS: { [string]: { number } } = {
		round = { 2.8, 3.9 },
		gabled = { 2.8, 3.8 },
		cross = { 4.2, 5.6 },
		celtic = { 4.8, 6.0 },
		obelisk = { 6.5, 8.5 },
		column = { 5.0, 6.2 },
		wooden = { 3.0, 3.8 },
		chest = { 0, 0 },
	}
	local stonePerches: { CFrame } = {}
	local graves = 0
	for z = YARD_Z1 - 4.5, YARD_Z0 + 11, -10 do
		for x = YARD_X0 + 4.5, YARD_X1 - 3.5, 5.2 do
			local gx = x + wear:NextNumber(-0.5, 0.5)
			local gz = z + wear:NextNumber(-0.6, 0.6)
			local style = STYLES[wear:NextInteger(1, #STYLES)]
			local slab = style == "round" or style == "gabled"
			local broken = slab and wear:NextNumber() < 0.1
			local plot = {
				x0 = gx - 2.0,
				x1 = gx + 2.0,
				z0 = gz - 8.3,
				z1 = gz + (if broken then 3.4 else 0.9),
			}
			if wear:NextNumber() < 0.62 and free(plot) then
				local range = HEIGHTS[style]
				local kind = wear:NextNumber()
				local plotKind = if kind < 0.5
					then "mound"
					elseif kind < 0.75 then "kerb"
					else "none"
				local lean = 0
				local tip = 0
				if slab and wear:NextNumber() < 0.45 then
					lean = wear:NextNumber(-0.1, 0.28)
					tip = wear:NextNumber(-0.12, 0.12)
				elseif style ~= "chest" then
					lean = wear:NextNumber(-0.03, 0.03)
				end
				if plotKind == "kerb" then
					lean = math.abs(lean) -- a kerb behind it: it can only have gone forward
				end
				local _, top = Yard.grave(spot(gx, GROUND, gz, FRONT), yard, {
					style = style,
					stone = Yard.STONES[wear:NextInteger(1, #Yard.STONES)],
					width = if slab then wear:NextNumber(2.0, 2.8) else nil,
					height = if range[2] > 0 then wear:NextNumber(range[1], range[2]) else nil,
					lean = lean,
					tip = tip,
					broken = broken,
					plot = plotKind,
					footstone = plotKind ~= "none" and wear:NextNumber() < 0.15,
					ajar = style == "chest" and wear:NextNumber() < 0.4,
				})
				graves += 1
				-- A crow on a few of the stones that still stand straight.
				local upright = math.abs(lean) < 0.05 and math.abs(tip) < 0.05 and not broken
				if
					upright
					and style ~= "obelisk"
					and #stonePerches < 4
					and wear:NextNumber() < 0.12
				then
					local along = if style == "chest" then -3.2 else 0
					table.insert(stonePerches, place(V(gx, GROUND + top, gz + along)))
				end
			end
		end
	end

	-- Crows: on stones, in the dead trees, along the lych-gate's ridge and the
	-- wall, and two on the ground by the open grave.
	local function crow(at: CFrame, peck: boolean?)
		Yard.crow(at * CFrame.Angles(0, wear:NextNumber(0, 2 * math.pi), 0), yard, { peck = peck })
	end
	for _, at in stonePerches do
		crow(at)
	end
	for _, at in perches do
		crow(at)
	end
	for _, x in { -2.8, 1.9 } do
		crow(place(V(x, GROUND + 15.15, YARD_Z1)))
	end
	for _, z in { -12, 20 } do
		crow(place(V(YARD_X1, GROUND + 4.55, z)))
	end
	crow(place(ground(8.4, -67.5)), true)
	crow(place(ground(9.6, -69.2)), true)

	print(string.format("[Church] %d graves in the churchyard", graves))

	model.Parent = parent

	print(
		string.format(
			"[Church] %d parts, %d hiding places, spire %d studs above the ground",
			Kit.count(),
			#hidingSpots,
			SPIRE_TOP - GROUND
		)
	)

	return {
		model = model,
		entrance = CFrame.lookAt(
			place(V(0, GROUND + 3, YARD_Z1 + 6)).Position,
			place(V(0, GROUND + 3, WEST_OUT)).Position
		),
		hidingSpots = hidingSpots,
		partCount = Kit.count(),
	}
end

return Church
