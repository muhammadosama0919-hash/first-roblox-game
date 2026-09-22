--!strict
--[[
	House #1: a derelict Victorian manor, generated entirely in code.

	Three floors you can walk. The ground floor is four rooms round a long
	entrance hall — parlour with its bay, kitchen, drawing room, library — and
	a dog-leg grand stair at the back of the hall that climbs to a half
	landing under a tall window and turns back up into the first floor.

	That first floor is almost all one room: a dining hall the width of the
	house, with a fireplace at each end and a table laid for twenty that
	nobody ever cleared. Behind it are a bedroom, a bathroom and the stair
	hall to the attic, which runs the length of the house under the roof.

	On the ground floor every room has two ways out, so a chase loops instead
	of dead-ending. Every door opens (DoorController). The places to hide are
	real places: cupboards under the stairs, a larder cupboard and a wardrobe
	you can shut yourself inside, tables long enough to lie under, beds.

	Nothing inside is lighter than old tobacco. No lamp is lit.

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

local Manor = {}

----------------------------------------------------------------------------
-- Dimensions
----------------------------------------------------------------------------

local STOREY = 13 -- clear floor to ceiling
local SLAB = 1
local FOUND_H = 7 -- the stone base; the ground is this far below the ground floor
local L1 = 0
local L2 = L1 + STOREY + SLAB -- 14
local L3 = L2 + STOREY + SLAB -- 28, the attic floor
local KNEE_TOP = L3 + 5 -- attic knee walls, so the eaves are not at head height
local GROUND = -FOUND_H

--[[
	84 by 58 across the outer faces: a quarter wider each way than this house
	used to be, which is what turns rooms of twenty studs into rooms of
	twenty-eight and leaves the first floor room for a hall the width of the
	house.
]]
local HALF_W = 42
local HALF_D = 29
local WALL_T = 1
local PART_T = 0.8
local WALL_X = HALF_W - WALL_T / 2
local WALL_Z = HALF_D - WALL_T / 2
local IN_X = HALF_W - WALL_T
local IN_Z = HALF_D - WALL_T
local HALL_X = 13 -- the hall partitions stand at +/- this

-- The same steep pitch as before, over the deeper plan.
local ROOF_RISE = 34
local EAVE = 3
local ROOF_RUN = HALF_D + EAVE
local ROOF_PITCH = math.atan2(ROOF_RISE, ROOF_RUN)
local ROOF_FALL = ROOF_RISE / ROOF_RUN
local RIDGE = KNEE_TOP + ROOF_RISE -- 67
local ROOF_T = 1.2

--[[
	The projecting bay on the front left: the one piece of massing that stops
	this being a symmetrical box, pitched steeper than the main roof so the
	two never read as one extruded shape.
]]
local BAY_X0 = -38
local BAY_X1 = -18
local BAY_W = BAY_X1 - BAY_X0
local BAY_MID = (BAY_X0 + BAY_X1) / 2
local BAY_PITCH = 1.4
local PORCH_D = 10
local BAY_Z = HALF_D + PORCH_D -- the bay front is flush with the porch front
local BAY_PEAK = KNEE_TOP + (BAY_W / 2) * BAY_PITCH
local BAY_STOP = (RIDGE - BAY_PEAK) / ROOF_FALL

local PORCH_OUT_Z = HALF_D + PORCH_D
local PORCH_OUT_X = HALF_W + PORCH_D
local PORCH_X0 = BAY_X1 -- the porch starts where the bay stops
local PORCH_RETURN_Z = 17 -- how far the side wing runs back: clear of the right chimney
local STEP_CENTRE = 22 -- steps off to one side, not on the door's axis
local STEP_HALF = 7
-- One post at each end, one either side of the steps, one left of the door.
local PORCH_POST_XS = {
	PORCH_X0 + 1.5,
	-8,
	STEP_CENTRE - STEP_HALF - 1,
	STEP_CENTRE + STEP_HALF + 1,
	PORCH_OUT_X - 1.5,
}

local DOOR_W = 8
local DOOR_H = 11
local FRONT_DOOR_X = 0
local IN_DOOR_W = 7
local IN_DOOR_H = 10
local BACK_DOOR_X = -31

-- Every flight in the house has the same step: 14/18 up, 4/3 along.
local RISE = (L2 - L1) / 18
local RUN = 4 / 3
local STAIR_W = 6

--[[
	The grand stair: a dog-leg at the back of the hall. Flight A climbs ten
	steps toward the back on the left to a half landing across the whole
	hall; flight B turns and climbs eight steps back toward the front on the
	right, arriving at the first floor where the dining hall begins. The gap
	between the flights is the well, open to the first-floor ceiling.
]]
local GS_A_X = -8
local GS_B_X = 8
local GS_FOOT_Z = -8
local GS_LAND_Z = GS_FOOT_Z - 10 * RUN -- -21.33
local GS_LAND_Y = L1 + 10 * RISE -- 7.78
local GS_TOP_Z = GS_LAND_Z + 8 * RUN -- -10.67
local WELL = GS_B_X - STAIR_W / 2 - 0.3 -- 4.7: the line of the flights' inner strings

-- The attic stair: the same dog-leg, in its own stair hall behind the dining
-- hall on the right, eight steps up the right-hand side and ten back.
local AS_C_X = 37.5
local AS_D_X = 29.5
local AS_FOOT_Z = -11.5
local AS_LAND_Z = AS_FOOT_Z - 8 * RUN -- -22.17
local AS_LAND_Y = L2 + 8 * RISE -- 20.22
local AS_TOP_Z = AS_LAND_Z + 10 * RUN -- -8.83
local AS_WALL_X = 25 -- between the bathroom and the stair hall
local L2_BACK_Z = -8 -- the partition behind the dining hall

local STACK_W = 7 -- a chimney stack's width along its wall
local STACK_D = 8 -- and its depth through it: half inside, half out
local RIGHT_CHIMNEY_Z = 9 -- on the right gable, behind the porch's return
local BACK_CHIMNEY_X = -22 -- the kitchen's, up the back wall

--[[
	Outside: dark, weathered clapboard; the corner boards, fascias and barge
	boards in a dirty dark stone, which is the outline the house is read by;
	the window frames in old oxblood paint gone nearly black (HouseKit's
	FRAME). Nothing pale anywhere.
]]
local CLAPBOARD = rgb(66, 53, 41)
local TRIM = rgb(72, 66, 58)
local SHINGLE = rgb(50, 45, 42)
local BRICK = rgb(74, 50, 42)
local FRONT_DOOR = rgb(66, 28, 24)
local SIDING: Kit.Siding = {
	color = CLAPBOARD,
	material = M.WoodPlanks,
	spacing = 2.6,
	height = 0.28,
	depth = 0.22,
	missing = 0.07,
}

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

local F_HALL = finish(C.PAPER_DAMASK, 4.2, true)
local F_PARLOUR = finish(C.PAPER_OXBLOOD, 3.6, true)
local F_DRAWING = finish(C.PAPER_MAUVE, 3.6, true)
-- The library is panelled most of the way up, with paper only above.
local F_LIBRARY = finish(C.PAPER_UMBER, 7.5, true)
local F_DINING = finish(C.PAPER_OXBLOOD, 4.5, true)
local F_BEDROOM = finish(C.PAPER_OCHRE, 3.4, false)
local F_PLAIN = finish(C.PAPER_SMOKE, 3.4, false)
local F_KITCHEN: Finish = {
	paper = C.PAPER_SMOKE,
	paperMaterial = M.Plaster,
	wainscot = 4.0,
	rail = C.RAIL,
	skirting = C.RAIL,
}
local F_BATH: Finish = {
	paper = rgb(70, 62, 52),
	paperMaterial = M.Plaster,
	wainscot = 4.6,
	rail = C.RAIL,
	dado = C.TILE_DARK,
	dadoMaterial = M.CeramicTiles,
}

--[[
	Every room, as boxes. A wall looks up the room a stud off each of its
	faces and is finished for it. The first box that contains a point wins,
	so the cupboards under the stairs come before the stairwell they sit in.
]]
local ROOMS: { Room } = {
	{
		name = "UnderLanding",
		level = L1,
		height = GS_LAND_Y - SLAB,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = -HALF_D,
		z1 = GS_LAND_Z,
	},
	{
		name = "UnderFlightB",
		level = L1,
		height = STOREY,
		x0 = WELL,
		x1 = HALL_X,
		z0 = GS_LAND_Z,
		z1 = GS_TOP_Z,
	},
	{
		name = "UnderFlightA",
		level = L1,
		height = GS_LAND_Y,
		x0 = -HALL_X,
		x1 = -WELL,
		z0 = GS_LAND_Z,
		z1 = GS_FOOT_Z,
	},
	{
		name = "Landing",
		level = GS_LAND_Y,
		height = L2 + STOREY - GS_LAND_Y,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = -HALF_D,
		z1 = GS_LAND_Z,
		finish = F_HALL,
	},
	{
		name = "Gallery",
		level = L2,
		height = STOREY,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = GS_TOP_Z - 0.5,
		z1 = L2_BACK_Z,
		finish = F_DINING,
	},
	{
		name = "Stairwell",
		level = L1,
		height = L2 + STOREY - L1,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = -HALF_D,
		z1 = L2_BACK_Z,
		finish = F_HALL,
	},
	{
		name = "Hall",
		level = L1,
		height = STOREY,
		x0 = -HALL_X,
		x1 = HALL_X,
		z0 = L2_BACK_Z,
		z1 = HALF_D + 0.5,
		finish = F_HALL,
	},
	{
		name = "Parlour",
		level = L1,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = 0,
		z1 = HALF_D + 0.5,
		finish = F_PARLOUR,
	},
	{
		name = "ParlourBay",
		level = L1,
		height = STOREY,
		x0 = BAY_X0,
		x1 = BAY_X1,
		z0 = HALF_D,
		z1 = BAY_Z,
		finish = F_PARLOUR,
	},
	{
		name = "Kitchen",
		level = L1,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = -HALF_D,
		z1 = 0,
		finish = F_KITCHEN,
	},
	{
		name = "Drawing",
		level = L1,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = 0,
		z1 = HALF_D + 0.5,
		finish = F_DRAWING,
	},
	{
		name = "Library",
		level = L1,
		height = STOREY,
		x0 = HALL_X,
		x1 = HALF_W,
		z0 = -HALF_D,
		z1 = 0,
		finish = F_LIBRARY,
	},
	{
		name = "DiningHall",
		level = L2,
		height = STOREY,
		x0 = -HALF_W,
		x1 = HALF_W,
		z0 = L2_BACK_Z,
		z1 = HALF_D + 0.5,
		finish = F_DINING,
	},
	{
		name = "DiningBay",
		level = L2,
		height = STOREY,
		x0 = BAY_X0,
		x1 = BAY_X1,
		z0 = HALF_D,
		z1 = BAY_Z,
		finish = F_DINING,
	},
	{
		name = "Bedroom",
		level = L2,
		height = STOREY,
		x0 = -HALF_W,
		x1 = -HALL_X,
		z0 = -HALF_D,
		z1 = L2_BACK_Z,
		finish = F_BEDROOM,
	},
	{
		name = "Bathroom",
		level = L2,
		height = STOREY,
		x0 = HALL_X,
		x1 = AS_WALL_X,
		z0 = -HALF_D,
		z1 = L2_BACK_Z,
		finish = F_BATH,
	},
	{
		name = "StairHall",
		level = L2,
		height = STOREY,
		x0 = AS_WALL_X,
		x1 = HALF_W,
		z0 = -HALF_D,
		z1 = L2_BACK_Z,
		finish = F_PLAIN,
	},
}

--[[
	How much ground the house takes, in house space: from the back stoop's
	bottom step to the front steps' bottom step, porch return included.
]]
Manor.FOOTPRINT = {
	x0 = -HALF_W - 3,
	x1 = PORCH_OUT_X + 2,
	z0 = -HALF_D - 22,
	z1 = PORCH_OUT_Z + 14,
}

--[[
	Whether a world position is on the footprint of a manor built at `pivot`.
	The house is turned half a turn inside its pivot (see Kit.placer), so the
	footprint can not be tested in the pivot's own space directly.
]]
function Manor.footprintContains(pivot: CFrame, position: Vector3): boolean
	local rel = (pivot * CFrame.Angles(0, math.pi, 0)):PointToObjectSpace(position)
	local f = Manor.FOOTPRINT
	return rel.X > f.x0 and rel.X < f.x1 and rel.Z > f.z0 and rel.Z < f.z1
end

----------------------------------------------------------------------------
-- Windows
----------------------------------------------------------------------------

type Window = {
	at: number,
	sill: number,
	width: number,
	height: number,
	style: string, -- "window" | "open" | "doorway" (an opening a door is hung in separately)
}

local function sash(at: number, sill: number, width: number?, height: number?): Window
	return { at = at, sill = sill, width = width or 6, height = height or 7, style = "window" }
end

local function opening(at: number, sill: number, width: number, height: number): Window
	return { at = at, sill = sill, width = width, height = height, style = "open" }
end

local function doorway(at: number, sill: number, width: number, height: number): Window
	return { at = at, sill = sill, width = width, height = height, style = "doorway" }
end

local function openingsFor(windows: { Window }): { Opening }
	local out: { Opening } = {}
	for _, w in windows do
		table.insert(out, { at = w.at, width = w.width, sill = w.sill, head = w.sill + w.height })
	end
	return out
end

type Band = { bottom: number, top: number, windows: { Window } }

-- The five horizontal bands of a full-height wall: storey, floor, storey,
-- floor, attic knee. Two windows stacked above each other are two bands.
local function bands(lower: { Window }, upper: { Window }, attic: { Window }): { Band }
	return {
		{ bottom = L1, top = L1 + STOREY, windows = lower },
		{ bottom = L1 + STOREY, top = L2, windows = {} },
		{ bottom = L2, top = L2 + STOREY, windows = upper },
		{ bottom = L2 + STOREY, top = L3, windows = {} },
		{ bottom = L3, top = KNEE_TOP, windows = attic },
	}
end

--[[
	One outside wall, band by band: the wall pieces with clapboard outside and
	each room's finish inside, and a frame in every window.
]]
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
		Kit.wall({
			name = "Wall" .. label,
			axis = axis,
			fixed = fixed,
			from = from,
			to = to,
			bottom = band.bottom,
			top = band.top,
			thickness = WALL_T,
			openings = openingsFor(band.windows),
			color = C.WAINSCOT,
			material = M.WoodPlanks,
			place = place,
			parent = parent,
			outward = outward,
			siding = SIDING,
			rooms = ROOMS,
			insetEnds = insetEnds,
			weather = 0.08,
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
				})
			end
		end
	end
end

----------------------------------------------------------------------------
-- Stone base
----------------------------------------------------------------------------

--[[
	Courses in two greys, each a little narrower than the one below so the
	house sits on a plinth, and the top course stopping inside the ground
	floor slab: a footing that tops out a hair above the boards turns the
	whole ground floor to stone.
]]
local function foundation(place: Place, parent: Instance, rng: Random)
	local courses = 5
	local courseH = FOUND_H / courses
	local footprints: { Hole } = {
		{ x0 = -HALF_W, x1 = HALF_W, z0 = -HALF_D, z1 = HALF_D },
		{ x0 = BAY_X0, x1 = BAY_X1, z0 = HALF_D - 1, z1 = BAY_Z },
	}
	for i = 0, courses - 1 do
		local out = 1.2 * (1 - i / courses) + 0.4
		local bottom = GROUND + courseH * i - 0.05
		local top = math.min(GROUND + courseH * (i + 1), L1 - 0.3)
		for _, r in footprints do
			Kit.part(
				"Footing",
				V(r.x1 - r.x0 + out * 2, top - bottom, r.z1 - r.z0 + out * 2),
				place(V((r.x0 + r.x1) / 2, (top + bottom) / 2, (r.z0 + r.z1) / 2)),
				Kit.weathered(if i % 2 == 0 then C.STONE else C.STONE_DARK, 0.05),
				M.Cobblestone,
				parent
			)
		end
	end

	-- A few stones fallen out of the base, at the back and sides only.
	for _ = 1, 16 do
		local edge = rng:NextInteger(2, 4)
		local along = rng:NextNumber(-1, 1)
		local size = rng:NextNumber(1.0, 2.0)
		local out = 1.6 + rng:NextNumber(0, 2.2)
		local position = if edge == 2
			then V(along * (HALF_W - 4), GROUND + size * 0.3, -(HALF_D + out))
			else V(
				(if edge == 3 then 1 else -1) * (HALF_W + out),
				GROUND + size * 0.3,
				along * (HALF_D - 4)
			)
		Kit.detail(
			Kit.part(
				"Rubble",
				V(size, size * rng:NextNumber(0.5, 0.75), size * rng:NextNumber(0.7, 1.1)),
				place(position)
					* CFrame.Angles(
						rng:NextNumber(-0.15, 0.15),
						rng:NextNumber(0, math.pi * 2),
						rng:NextNumber(-0.15, 0.15)
					),
				if rng:NextNumber() < 0.5 then C.STONE else C.STONE_DARK,
				M.Rock,
				parent
			)
		)
	end
end

----------------------------------------------------------------------------
-- Chimneys
----------------------------------------------------------------------------

type Fireplace = { level: number, w: number, h: number, grate: boolean?, depth: number? }

--[[
	A chimney stack straddling an outside wall, with a fireplace in its
	breast on each floor listed and plain brick between.

	Worked in the wall's own terms — `u` along the wall, `n` in from its outer
	face — and mapped to house space once, so the same arithmetic serves the
	back wall and both gable ends. There is no way to cut a hole in a part,
	so a fireplace is built from the pieces around its opening: a back, a pier
	each side, a lintel across. Then a sooted fireback, a hearth, a mantel
	shelf, and in a grate the remains of the last fire.
]]
local function chimney(
	place: Place,
	parent: Instance,
	wall: string,
	at: number,
	fireplaces: { Fireplace },
	top: number
)
	local function pt(u: number, y: number, n: number): Vector3
		if wall == "back" then
			return V(at + u, y, -HALF_D + n)
		elseif wall == "left" then
			return V(-HALF_W + n, y, at + u)
		end
		return V(HALF_W - n, y, at + u)
	end
	local function sz(su: number, sy: number, sn: number): Vector3
		if wall == "back" then
			return V(su, sy, sn)
		end
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
		-- How far the firebox goes into the breast. No deeper than 2.7: the
		-- outside wall and its paper run through the stack, and the back of
		-- a deeper box would open onto them.
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
		-- The hearth runs from the back of the firebox out onto the floor,
		-- and covers the line where the floor and the brick below meet.
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
		Kit.soft(
			Kit.part(
				"Mantel",
				sz(fp.w + 2.6, 0.35, 1.2),
				place(pt(0, lintelTop + 0.18, face + 0.4)),
				C.WALNUT,
				M.Wood,
				parent
			)
		)
		Kit.detail(
			Kit.rod(
				"MantelEdge",
				place(pt(-(fp.w + 2.6) / 2, lintelTop + 0.18, face + 1.0)).Position,
				place(pt((fp.w + 2.6) / 2, lintelTop + 0.18, face + 1.0)).Position,
				0.35,
				C.WALNUT,
				M.Wood,
				parent
			)
		)

		-- Indoors the breast is papered like the room it stands in, above
		-- the mantel and down both sides; only the surround is left brick.
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

		if fp.grate ~= false then
			-- Andirons and a grate, and the charred ends of the last fire.
			local backN = face - d + 0.3
			for _, u in { -fp.w / 2 + 0.6, fp.w / 2 - 0.6 } do
				local foot = place(pt(u, fp.level + 0.2, face - 0.3)).Position
				Kit.detail(
					Kit.rod("Andiron", foot, foot + V(0, 1.1, 0), 0.14, C.IRON, M.Metal, parent)
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
						C.IRON,
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
			for k, u in { -0.5, 0.4 } do
				local a =
					place(pt(u - 0.9, fp.level + 0.45 + k * 0.15, face - d / 2 - 0.1)).Position
				local b =
					place(pt(u + 0.9, fp.level + 0.45 + k * 0.15, face - d / 2 + 0.2)).Position
				Kit.detail(Kit.rod("CharredLog", a, b, 0.45, rgb(30, 26, 24), M.Wood, parent))
			end
		end
		cursor = lintelTop
	end
	brick("Chimney", -hw, hw, cursor, top, -face, face)
	Kit.part(
		"ChimneyCap",
		sz(STACK_W + 1.6, 0.9, STACK_D + 1.6),
		place(pt(0, top + 0.45, 0)),
		C.STONE_DARK,
		M.Slate,
		parent
	)
	-- Two clay pots on the cap.
	for _, u in { -1.4, 1.4 } do
		local base = place(pt(u, top + 0.9, 0)).Position
		Kit.rod("ChimneyPot", base, base + V(0, 2.2, 0), 1.3, rgb(78, 50, 40), M.Brick, parent)
		Kit.detail(
			Kit.disc(
				"PotRim",
				CFrame.new(base + V(0, 2.2, 0)),
				1.6,
				0.25,
				rgb(70, 46, 38),
				M.Brick,
				parent
			)
		)
	end
end

----------------------------------------------------------------------------
-- Roof
----------------------------------------------------------------------------

type Gable = { cx: number, width: number, wall: number }
type Cut = { from: number, to: number, stop: number, zEdge: number }

--[[
	One strip of the main roof, given as the patch of plan it covers, `z0` to
	`z1` out from the ridge on the `side` slope. Dropped half a thickness
	along its own normal so the top face is the rafter line.
]]
local function roofSlab(
	xFrom: number,
	xTo: number,
	z0: number,
	z1: number,
	side: number,
	place: Place,
	parent: Instance
)
	if xTo - xFrom <= EPS or z1 - z0 <= EPS then
		return
	end
	local length = (z1 - z0) / math.cos(ROOF_PITCH)
	local midY = RIDGE - ROOF_FALL * (z0 + z1) / 2
	local normal = V(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
	local centre = V((xFrom + xTo) / 2, midY, side * (z0 + z1) / 2) - normal * (ROOF_T / 2)
	Kit.part(
		"RoofSlope",
		V(xTo - xFrom, ROOF_T, length),
		place(centre) * CFrame.Angles(side * ROOF_PITCH, 0, 0),
		Kit.weathered(SHINGLE, 0.07),
		M.RoofShingles,
		parent
	)
	-- Boarding under it: seen from the attic, and under the eaves from
	-- outside, the roof is boards rather than the underside of the shingles.
	Kit.detail(
		Kit.part(
			"RoofBoards",
			V(xTo - xFrom, 0.2, length),
			place(centre - normal * (ROOF_T / 2 + 0.1)) * CFrame.Angles(side * ROOF_PITCH, 0, 0),
			C.TIMBER,
			M.WoodPlanks,
			parent
		)
	)
end

--[[
	A wall dormer: a tall cross gable whose face is flush with the wall below.
	Returns how far out from the ridge its own ridge bites the main slope, and
	how far out the valley reaches the edge of the cut, so the caller can lay
	the main roof round it.
]]
local function dormer(
	side: number,
	cx: number,
	width: number,
	wallH: number,
	place: Place,
	parent: Instance
): (number, number)
	local eave = KNEE_TOP + wallH
	local peak = eave + width / 2 -- 45 degrees
	local stop = (RIDGE - peak) / ROOF_FALL
	local faceZ = side * WALL_Z
	local backZ = stop - 1
	local outZ = HALF_D + EAVE
	local depth = outZ - backZ
	local midZ = side * (backZ + outZ) / 2
	local cheekDepth = HALF_D - WALL_T - backZ
	local cheekMidZ = side * (backZ + HALF_D - WALL_T) / 2

	local winW = math.min(width * 0.42, 9)
	local winH = math.min(wallH - 2.5, 7)
	local winSill = KNEE_TOP + (wallH - winH) / 2

	Kit.wall({
		name = "DormerFace",
		axis = "X",
		fixed = faceZ,
		from = cx - width / 2,
		to = cx + width / 2,
		bottom = KNEE_TOP,
		top = eave,
		thickness = WALL_T,
		openings = { { at = cx, width = winW, sill = winSill, head = winSill + winH } },
		color = C.WAINSCOT,
		material = M.WoodPlanks,
		place = place,
		parent = parent,
		outward = side,
		siding = SIDING,
	})
	Kit.window(
		place(V(cx, winSill + winH / 2, faceZ)) * CFrame.new(Vector3.zero, V(0, 0, side)),
		winW,
		winH,
		{
			thickness = WALL_T,
			parent = parent,
		}
	)
	Kit.triangle(
		"DormerGable",
		place(V(cx - width / 2, eave, faceZ)).Position,
		place(V(cx + width / 2, eave, faceZ)).Position,
		place(V(cx, peak, faceZ)).Position,
		WALL_T,
		CLAPBOARD,
		M.WoodPlanks,
		parent
	)
	for _, edge in { -1, 1 } do
		Kit.part(
			"DormerCheek",
			V(WALL_T, wallH, cheekDepth),
			place(V(cx + edge * (width / 2 - WALL_T / 2), KNEE_TOP + wallH / 2, cheekMidZ)),
			CLAPBOARD,
			M.WoodPlanks,
			parent
		)
	end
	local slope = math.rad(45)
	local slabLen = (width / 2) / math.cos(slope) + 2
	for _, edge in { -1, 1 } do
		Kit.part(
			"DormerRoof",
			V(slabLen, ROOF_T, depth + 2),
			place(
				V(
					cx + edge * (width / 4 + math.cos(slope)),
					(peak + eave) / 2 + ROOF_T / 2 - math.sin(slope),
					midZ
				)
			) * CFrame.Angles(0, 0, -edge * slope),
			SHINGLE,
			M.RoofShingles,
			parent
		)
	end
	-- Barge boards down the dormer's own gable.
	local rakeLen = (width / 2 + 0.8) / math.cos(slope)
	for _, edge in { -1, 1 } do
		Kit.part(
			"DormerRake",
			V(rakeLen, 1.1, 0.5),
			place(V(cx + edge * (width / 4 + 0.2), (peak + eave) / 2 - 0.1, side * (outZ + 0.25)))
				* CFrame.Angles(0, 0, -edge * slope),
			TRIM,
			M.Wood,
			parent
		)
	end
	return stop, (RIDGE - eave) / ROOF_FALL
end

local function roof(place: Place, parent: Instance, rng: Random)
	-- No dormer over the bay: its own gable is the big one on that side. The
	-- front pair are unequal on purpose; the back pair stay clear of the
	-- kitchen chimney.
	local frontGables: { Gable } = {
		{ cx = -2, width = 11, wall = 5 },
		{ cx = 22, width = 16, wall = 7 },
	}
	local backGables: { Gable } = {
		{ cx = -4, width = 13, wall = 6 },
		{ cx = 12, width = 13, wall = 6 },
	}

	local function bare(x0: number, x1: number, side: number)
		if x1 - x0 < 8 then
			return
		end
		for _ = 1, rng:NextInteger(1, 3) do
			local w = rng:NextNumber(2.5, 6)
			local x = rng:NextNumber(x0 + w / 2 + 0.5, x1 - w / 2 - 0.5)
			local out = rng:NextNumber(3, ROOF_RUN - 4)
			local along = rng:NextNumber(2, 4.5)
			local normal = V(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
			Kit.detail(
				Kit.part(
					"BarePatch",
					V(w, 0.12, along),
					place(V(x, RIDGE - ROOF_FALL * out, side * out) + normal * 0.06)
						* CFrame.Angles(side * ROOF_PITCH, 0, 0),
					rgb(46, 40, 36),
					M.Wood,
					parent
				)
			)
		end
	end

	-- The valley triangles either side of a cut, in the main roof's plane.
	local function valleys(cut: Cut, side: number)
		local stripEnd = cut.stop + 2
		if cut.zEdge - stripEnd <= EPS then
			return
		end
		local cx = (cut.from + cut.to) / 2
		local halfW = (cut.to - cut.from) / 2
		local normal = V(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
		local drop = -normal * (ROOF_T / 2)
		local function onRoof(x: number, z: number): Vector3
			return place(V(x, RIDGE - ROOF_FALL * z, side * z) + drop).Position
		end
		for _, dir in { -1, 1 } do
			local edge = cx + dir * halfW
			local inner = cx + dir * halfW * ((stripEnd - cut.stop) / (cut.zEdge - cut.stop))
			Kit.triangle(
				"RoofValley",
				onRoof(edge, stripEnd),
				onRoof(edge, cut.zEdge),
				onRoof(inner, stripEnd),
				ROOF_T,
				Kit.weathered(SHINGLE, 0.07),
				M.RoofShingles,
				parent
			)
		end
	end

	local function laySlope(side: number, gables: { Gable }, extra: { Cut }): { Cut }
		local cuts: { Cut } = table.clone(extra)
		for _, g in gables do
			local stop, zEdge = dormer(side, g.cx, g.width, g.wall, place, parent)
			table.insert(
				cuts,
				{ from = g.cx - g.width / 2, to = g.cx + g.width / 2, stop = stop, zEdge = zEdge }
			)
		end
		table.sort(cuts, function(p: Cut, q: Cut): boolean
			return p.from < q.from
		end)
		local cursor = -HALF_W - EAVE
		for _, cut in cuts do
			roofSlab(cursor, cut.from, 0, ROOF_RUN, side, place, parent)
			bare(cursor, cut.from, side)
			roofSlab(cut.from, cut.to, 0, cut.stop + 2, side, place, parent)
			valleys(cut, side)
			cursor = cut.to
		end
		roofSlab(cursor, HALF_W + EAVE, 0, ROOF_RUN, side, place, parent)
		bare(cursor, HALF_W + EAVE, side)
		return cuts
	end

	local frontCuts = laySlope(1, frontGables, {
		{ from = BAY_X0, to = BAY_X1, stop = BAY_STOP, zEdge = (RIDGE - KNEE_TOP) / ROOF_FALL },
	})
	local backCuts = laySlope(-1, backGables, {})

	--[[
		The attic's roof from below: a rafter every four studs down each slope
		under the boarding, a ridge board, and a collar tie across every other
		pair high overhead. A rafter stops short where a dormer or the bay
		opens the slope and where the kitchen chimney comes through, and the
		row stops short of the gable chimneys. None of it collides: it is all
		out of reach, and a sloping beam is nothing a player should be able to
		walk up.
	]]
	local rafterD = 0.9
	local below = ROOF_T + 0.2
	local function rafterEnd(x: number, side: number, cuts: { Cut }): number
		local z = IN_Z - 0.4
		for _, cut in cuts do
			if x > cut.from - 0.6 and x < cut.to + 0.6 then
				z = math.min(z, cut.stop - 1.4)
			end
		end
		if side < 0 and math.abs(x - BACK_CHIMNEY_X) < STACK_W / 2 + 0.6 then
			z = math.min(z, HALF_D - STACK_D / 2 - 0.4)
		end
		return z
	end
	local ridgeUnder = RIDGE - below / math.cos(ROOF_PITCH)
	Kit.soft(
		Kit.part(
			"RidgeBoard",
			V(74, 1.4, 0.6),
			place(V(0, ridgeUnder - 0.7, 0)),
			C.TIMBER,
			M.Wood,
			parent
		)
	)
	local tieY = L3 + 20
	for i = 0, 18 do
		local x = -36 + i * 4
		local ends: { [number]: number } = {}
		for _, side in { -1, 1 } do
			local z1 = rafterEnd(x, side, if side > 0 then frontCuts else backCuts)
			ends[side] = z1
			local z0 = 0.35
			local normal = V(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
			local mid = (z0 + z1) / 2
			local centre = V(x, RIDGE - ROOF_FALL * mid, side * mid)
				- normal * (below + rafterD / 2)
			Kit.soft(
				Kit.part(
					"Rafter",
					V(0.5, rafterD, (z1 - z0) / math.cos(ROOF_PITCH)),
					place(centre) * CFrame.Angles(side * ROOF_PITCH, 0, 0),
					C.TIMBER,
					M.Wood,
					parent
				)
			)
		end
		-- Where the rafters' undersides pass the tie's height.
		local reach = (RIDGE - tieY - (below + rafterD) / math.cos(ROOF_PITCH)) / ROOF_FALL
		if i % 2 == 0 and ends[1] > reach + 1 and ends[-1] > reach + 1 then
			Kit.soft(
				Kit.part(
					"CollarTie",
					V(0.4, 0.7, reach * 2 + 1.2),
					place(V(x + 0.45, tieY, 0)),
					C.TIMBER,
					M.Wood,
					parent
				)
			)
		end
	end

	-- The eave walls: the band between the knee wall's top and the underside
	-- of the roof at the wall line, gapped at every gable and the bay.
	local eaveWallTop = RIDGE - ROOF_FALL * IN_Z - ROOF_T / math.cos(ROOF_PITCH)
	local function eaveWall(side: number, gables: { Gable }, extra: { Opening })
		local gaps: { Opening } = table.clone(extra)
		for _, g in gables do
			table.insert(gaps, { at = g.cx, width = g.width, sill = KNEE_TOP, head = eaveWallTop })
		end
		Kit.wall({
			name = "WallEave",
			axis = "X",
			fixed = side * WALL_Z,
			from = -IN_X,
			to = IN_X,
			bottom = KNEE_TOP,
			top = eaveWallTop,
			thickness = WALL_T,
			openings = gaps,
			color = C.WAINSCOT,
			material = M.WoodPlanks,
			place = place,
			parent = parent,
			outward = side,
			siding = SIDING,
		})
	end
	eaveWall(
		1,
		frontGables,
		{ { at = BAY_MID, width = BAY_W, sill = KNEE_TOP, head = eaveWallTop } }
	)
	eaveWall(-1, backGables, {})

	Kit.part(
		"Ridge",
		V(HALF_W * 2 + EAVE * 2, 1.4, 2.4),
		place(V(0, RIDGE + 0.4, 0)),
		SHINGLE,
		M.RoofShingles,
		parent
	)
	for _, side in { -1, 1 } do
		Kit.triangle(
			"GableEnd",
			place(V(side * WALL_X, KNEE_TOP, -HALF_D)).Position,
			place(V(side * WALL_X, KNEE_TOP, HALF_D)).Position,
			place(V(side * WALL_X, RIDGE, 0)).Position,
			WALL_T,
			CLAPBOARD,
			M.WoodPlanks,
			parent
		)
	end

	-- Corner boards, fascias and barge boards: the lines the house is read by.
	local wallH = KNEE_TOP - L1 + 1
	for _, corner in
		{
			V(-HALF_W, 0, -HALF_D),
			V(HALF_W, 0, -HALF_D),
			V(-HALF_W, 0, HALF_D),
			V(HALF_W, 0, HALF_D),
			V(BAY_X0, 0, BAY_Z),
			V(BAY_X1, 0, BAY_Z),
		}
	do
		local inward = V(-math.sign(corner.X) * 0.2, 0, -math.sign(corner.Z) * 0.2)
		Kit.part(
			"CornerBoard",
			V(1.0, wallH, 1.0),
			place(corner + inward + V(0, (KNEE_TOP + L1) / 2 - 0.5, 0)),
			TRIM,
			M.Wood,
			parent
		)
	end

	local edge = HALF_W + EAVE + 0.3
	local function fascia(x0: number, x1: number, side: number)
		if x1 - x0 <= EPS then
			return
		end
		Kit.part(
			"Fascia",
			V(x1 - x0, 1.3, 0.6),
			place(V((x0 + x1) / 2, KNEE_TOP - 0.4, side * (ROOF_RUN + 0.3))),
			TRIM,
			M.Wood,
			parent
		)
	end
	local function eave(side: number, gables: { Gable }, extra: { { number } })
		local gaps: { { number } } = table.clone(extra)
		for _, g in gables do
			table.insert(gaps, { g.cx - g.width / 2, g.cx + g.width / 2 })
		end
		table.sort(gaps, function(a: { number }, b: { number }): boolean
			return a[1] < b[1]
		end)
		local cursor = -edge
		for _, gap in gaps do
			fascia(cursor, gap[1], side)
			cursor = math.max(cursor, gap[2])
		end
		fascia(cursor, edge, side)
	end
	eave(1, frontGables, { { BAY_X0, BAY_X1 } })
	eave(-1, backGables, {})

	local rakeLen = ROOF_RUN / math.cos(ROOF_PITCH) + 1
	for _, side in { -1, 1 } do
		for _, slope in { -1, 1 } do
			Kit.part(
				"Rake",
				V(0.6, 1.5, rakeLen),
				place(
					V(side * edge, (RIDGE + KNEE_TOP) / 2, slope * ROOF_RUN / 2)
						- V(0, math.cos(ROOF_PITCH), slope * math.sin(ROOF_PITCH)) * 0.75
				) * CFrame.Angles(slope * ROOF_PITCH, 0, 0),
				TRIM,
				M.Wood,
				parent
			)
		end
	end
end

----------------------------------------------------------------------------
-- The bay
----------------------------------------------------------------------------

local function frontBay(place: Place, parent: Instance)
	exterior(
		"BayFront",
		"X",
		BAY_Z - WALL_T / 2,
		BAY_X0,
		BAY_X1,
		1,
		bands(
			{ sash(BAY_MID, L1 + 4, 12, 7) },
			{ sash(BAY_MID - 4, L2 + 4, 5, 7), sash(BAY_MID + 4, L2 + 4, 5, 7) },
			{
				sash(BAY_MID, L3 + 1, 4, 3),
			}
		),
		place,
		parent,
		WALL_T
	)
	for _, side in { -1, 1 } do
		local faceX = if side < 0 then BAY_X0 + WALL_T / 2 else BAY_X1 - WALL_T / 2
		exterior(
			if side < 0 then "BayLeft" else "BayRight",
			"Z",
			faceX,
			HALF_D,
			BAY_Z - WALL_T,
			side,
			bands({ sash(BAY_Z - 5, L1 + 4, 4, 7) }, { sash(BAY_Z - 5, L2 + 4, 4, 7) }, {}),
			place,
			parent
		)
	end

	Kit.triangle(
		"BayGable",
		place(V(BAY_X0, KNEE_TOP, BAY_Z - WALL_T / 2)).Position,
		place(V(BAY_X1, KNEE_TOP, BAY_Z - WALL_T / 2)).Position,
		place(V(BAY_MID, BAY_PEAK, BAY_Z - WALL_T / 2)).Position,
		WALL_T,
		CLAPBOARD,
		M.WoodPlanks,
		parent
	)

	local backZ = BAY_STOP - 1
	local outZ = BAY_Z + EAVE
	local slope = math.atan2((BAY_W / 2) * BAY_PITCH, BAY_W / 2)
	local slabLen = (BAY_W / 2) / math.cos(slope) + 3
	Kit.part(
		"BayRidge",
		V(2.2, 1.2, outZ - backZ),
		place(V(BAY_MID, BAY_PEAK + 1.0, (backZ + outZ) / 2)),
		SHINGLE,
		M.RoofShingles,
		parent
	)
	for _, side in { -1, 1 } do
		Kit.part(
			"BayRoof",
			V(slabLen, ROOF_T, outZ - backZ),
			place(
				V(
					BAY_MID + side * (BAY_W / 4 + 1.5 * math.cos(slope)),
					(BAY_PEAK + KNEE_TOP) / 2 + ROOF_T / 2 - 1.5 * math.sin(slope),
					(backZ + outZ) / 2
				)
			) * CFrame.Angles(0, 0, -side * slope),
			SHINGLE,
			M.RoofShingles,
			parent
		)
		local faceX = if side < 0 then BAY_X0 else BAY_X1
		Kit.triangle(
			"BayCheek",
			place(V(faceX, KNEE_TOP, ROOF_RUN)).Position,
			place(V(faceX, KNEE_TOP, backZ)).Position,
			place(V(faceX, RIDGE - ROOF_FALL * backZ, backZ)).Position,
			WALL_T,
			CLAPBOARD,
			M.WoodPlanks,
			parent
		)
	end

	local bayHalf = BAY_W / 2 + 3 * math.cos(slope) - 0.2
	local bayRakeLen = bayHalf / math.cos(slope)
	local bayLow = BAY_PEAK - bayHalf * BAY_PITCH
	for _, e in { -1, 1 } do
		Kit.part(
			"BayRake",
			V(bayRakeLen, 1.5, 0.6),
			place(V(BAY_MID + e * bayHalf / 2, (BAY_PEAK + bayLow) / 2, BAY_Z + EAVE + 0.3))
				* CFrame.Angles(0, 0, -e * slope),
			TRIM,
			M.Wood,
			parent
		)
	end
end

----------------------------------------------------------------------------
-- Porch and stoop
----------------------------------------------------------------------------

--[[
	A round porch column: square plinth, turned shaft, capital. Six of them
	carry the porch roof; the stone piers under them carry them.
]]
local function column(place: Place, parent: Instance, x: number, z: number, top: number)
	local foot = place(V(x, L1, z)).Position
	local up = V(0, 1, 0)
	Kit.part(
		"ColumnPlinth",
		V(1.9, 1.2, 1.9),
		CFrame.new(foot + up * 0.6),
		C.TIMBER,
		M.Wood,
		parent
	)
	Kit.rod("Column", foot + up * 1.1, foot + up * (top - L1 - 0.7), 1.3, C.TIMBER, M.Wood, parent)
	Kit.detail(Kit.ball("ColumnBulb", foot + up * 2.0, 1.6, C.TIMBER, M.Wood, parent))
	Kit.detail(
		Kit.disc(
			"ColumnNeck",
			CFrame.new(foot + up * (top - L1 - 1.1)),
			1.7,
			0.3,
			C.TIMBER,
			M.Wood,
			parent
		)
	)
	Kit.part(
		"ColumnCap",
		V(2.0, 0.5, 2.0),
		CFrame.new(foot + up * (top - L1 - 0.45)),
		C.TIMBER,
		M.Wood,
		parent
	)
	Kit.part(
		"Pier",
		V(3.2, FOUND_H, 3.2),
		place(V(x, GROUND + FOUND_H / 2 - SLAB, z)),
		C.STONE_DARK,
		M.Cobblestone,
		parent
	)
end

local function verandah(place: Place, parent: Instance)
	local function deck(x0: number, x1: number, z0: number, z1: number)
		Kit.part(
			"PorchDeck",
			V(x1 - x0, SLAB, z1 - z0),
			place(V((x0 + x1) / 2, L1 - SLAB / 2, (z0 + z1) / 2)),
			C.FLOOR,
			M.WoodPlanks,
			parent
		)
	end
	deck(PORCH_X0, PORCH_OUT_X, HALF_D, PORCH_OUT_Z)
	deck(HALF_W, PORCH_OUT_X, PORCH_RETURN_Z, HALF_D)

	-- A continuous stone skirt under the decks, open only for the steps.
	local skirtTop = L1 - SLAB
	local function skirt(
		axis: string,
		fixed: number,
		from: number,
		to: number,
		openings: { Opening }
	)
		Kit.wall({
			name = "Skirt",
			axis = axis,
			fixed = fixed,
			from = from,
			to = to,
			bottom = GROUND,
			top = skirtTop,
			thickness = 1.5,
			openings = openings,
			color = C.STONE,
			material = M.Cobblestone,
			place = place,
			parent = parent,
		})
	end
	skirt(
		"X",
		PORCH_OUT_Z - 0.75,
		PORCH_X0,
		PORCH_OUT_X,
		{ { at = STEP_CENTRE, width = STEP_HALF * 2, sill = GROUND, head = L1 } }
	)
	skirt("Z", PORCH_OUT_X - 0.75, PORCH_RETURN_Z, PORCH_OUT_Z - 1.5, {})
	skirt("X", PORCH_RETURN_Z + 0.75, HALF_W, PORCH_OUT_X - 1.5, {})

	-- The roof: leaves the wall above the ground-floor ceiling and falls to
	-- the front edge.
	local roofHigh = L2 + 1.5
	local roofLow = L2 - 2
	local roofRun = PORCH_D + 1.5
	local pitch = math.atan2(roofHigh - roofLow, roofRun)
	local roofLen = math.sqrt(roofRun * roofRun + (roofHigh - roofLow) ^ 2)
	local function roofAt(out: number): number
		return roofHigh - (roofHigh - roofLow) * (out / roofRun) - 0.4
	end
	Kit.part(
		"PorchRoof",
		V(PORCH_OUT_X - PORCH_X0 + 1.5, 0.8, roofLen),
		place(
			V((PORCH_X0 + PORCH_OUT_X) / 2 + 0.75, (roofHigh + roofLow) / 2, HALF_D + roofRun / 2)
		) * CFrame.Angles(pitch, 0, 0),
		SHINGLE,
		M.RoofShingles,
		parent
	)
	Kit.part(
		"PorchRoof",
		V(roofLen, 0.8, HALF_D - PORCH_RETURN_Z + 1.5),
		place(
			V(HALF_W + roofRun / 2, (roofHigh + roofLow) / 2, (PORCH_RETURN_Z + HALF_D) / 2 - 0.75)
		) * CFrame.Angles(0, 0, -pitch),
		SHINGLE,
		M.RoofShingles,
		parent
	)
	Kit.triangle(
		"PorchHip",
		place(V(HALF_W, roofHigh, HALF_D)).Position,
		place(V(HALF_W + roofRun, roofHigh, HALF_D)).Position,
		place(V(HALF_W + roofRun, roofLow, HALF_D)).Position,
		0.8,
		SHINGLE,
		M.RoofShingles,
		parent
	)
	Kit.part(
		"PorchFascia",
		V(PORCH_OUT_X - PORCH_X0 + 2.2, 1.2, 0.5),
		place(V((PORCH_X0 + PORCH_OUT_X) / 2 + 0.75, roofLow - 0.3, PORCH_OUT_Z + 1.6)),
		TRIM,
		M.Wood,
		parent
	)
	Kit.part(
		"PorchFascia",
		V(0.5, 1.2, HALF_D - PORCH_RETURN_Z + 2.2),
		place(V(PORCH_OUT_X + 1.6, roofLow - 0.3, (PORCH_RETURN_Z + HALF_D) / 2 - 0.75)),
		TRIM,
		M.Wood,
		parent
	)

	local posts: { Vector3 } = {}
	for _, x in PORCH_POST_XS do
		table.insert(posts, V(x, 0, PORCH_OUT_Z - 1.5))
	end
	table.insert(posts, V(PORCH_OUT_X - 1.5, 0, PORCH_RETURN_Z + 1.5))
	for _, base in posts do
		local out = math.max(base.Z - HALF_D, base.X - HALF_W)
		column(place, parent, base.X, base.Z, roofAt(out))
	end

	for _, run in
		{
			{
				axis = "X",
				fixed = PORCH_OUT_Z - 0.4,
				from = PORCH_X0 + 2.4,
				to = STEP_CENTRE - STEP_HALF,
			},
			{
				axis = "X",
				fixed = PORCH_OUT_Z - 0.4,
				from = STEP_CENTRE + STEP_HALF,
				to = PORCH_OUT_X - 2.4,
			},
			{
				axis = "Z",
				fixed = PORCH_OUT_X - 0.4,
				from = PORCH_RETURN_Z + 2.4,
				to = PORCH_OUT_Z - 2.4,
			},
			{ axis = "X", fixed = PORCH_RETURN_Z + 0.4, from = HALF_W, to = PORCH_OUT_X - 2.4 },
		}
	do
		Kit.railing("Porch", L1, run, place, parent)
	end

	Kit.staircase(
		"PorchStep",
		V(STEP_CENTRE, GROUND, PORCH_OUT_Z + 11),
		V(STEP_CENTRE, L1, PORCH_OUT_Z),
		STEP_HALF * 2 - 2,
		8,
		place,
		parent
	)
end

-- A back stoop, so the kitchen door is a real second way out rather than a
-- seven-stud drop onto the grass.
local function backStoop(place: Place, parent: Instance)
	local halfW = 7
	local outZ = -HALF_D - 9
	local cx = BACK_DOOR_X
	Kit.part(
		"StoopDeck",
		V(halfW * 2, SLAB, 9),
		place(V(cx, L1 - SLAB / 2, (-HALF_D + outZ) / 2)),
		C.FLOOR,
		M.WoodPlanks,
		parent
	)
	for _, side in { -1, 1 } do
		Kit.part(
			"StoopPier",
			V(2.6, FOUND_H, 2.6),
			place(V(cx + side * (halfW - 1.5), GROUND + FOUND_H / 2 - SLAB, outZ + 1.5)),
			C.STONE,
			M.Cobblestone,
			parent
		)
		Kit.railing(
			"Stoop",
			L1,
			{ axis = "Z", fixed = cx + side * (halfW - 0.4), from = outZ + 0.2, to = -HALF_D },
			place,
			parent
		)
	end
	Kit.staircase(
		"StoopStep",
		V(cx, GROUND, outZ - 10),
		V(cx, L1, outZ),
		halfW * 2 - 2,
		8,
		place,
		parent
	)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

--[[
	Build the manor. `pivot` is where the ground meets the middle of the
	footprint, and the house faces along the pivot's LookVector.
]]
function Manor.build(pivot: CFrame, parent: Instance): Kit.Built
	Kit.reset(8891)
	local rng = Random.new(20240617)
	local place = Kit.placer(pivot, FOUND_H)

	local model = Instance.new("Model")
	model.Name = "Manor"
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

	-- A world frame at a point in house space, looking along `face` (house
	-- space; default -Z). Furniture and wall ornaments are placed with it.
	local function spot(x: number, y: number, z: number, face: Vector3?): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face or V(0, 0, -1))
	end
	local FRONT, BACK, LEFT, RIGHT = V(0, 0, 1), V(0, 0, -1), V(-1, 0, 0), V(1, 0, 0)

	--[[
		Hang a door in an opening. `into` is the way it swings open (house
		space), `hingeToward` which jamb it hangs on. The casing goes round the
		opening at the same time.
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

	foundation(place, shell, rng)

	--------------------------------------------------------------------------
	-- Floors and landings
	--------------------------------------------------------------------------

	do
		-- The ground floor runs to the walls' outer faces; the upper floors stop
		-- inside the walls, where carried to the face their edges would share
		-- a plane with it and flicker.
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
		local well: Hole =
			{ x0 = -HALL_X + PART_T / 2, x1 = HALL_X - PART_T / 2, z0 = -HALF_D - 1, z1 = GS_TOP_Z }
		Kit.slabWithHoles(
			"FirstFloor",
			L2,
			SLAB,
			-WALL_X,
			WALL_X,
			-WALL_Z,
			WALL_Z,
			{ well },
			C.FLOOR,
			M.WoodPlanks,
			place,
			interior
		)
		local attic: Hole =
			{ x0 = AS_WALL_X + PART_T / 2, x1 = HALF_W + 1, z0 = -HALF_D - 1, z1 = AS_TOP_Z }
		Kit.slabWithHoles(
			"AtticFloor",
			L3,
			SLAB,
			-WALL_X,
			WALL_X,
			-WALL_Z,
			WALL_Z,
			{ attic },
			C.FLOOR,
			M.WoodPlanks,
			place,
			interior
		)
		for _, y in { L1, L2, L3 } do
			local out = if y == L1 then 0 else -WALL_T / 2
			Kit.slabWithHoles(
				"BayFloor",
				y,
				SLAB,
				BAY_X0 - out,
				BAY_X1 + out,
				HALF_D + out,
				BAY_Z + out,
				{},
				C.FLOOR,
				M.WoodPlanks,
				place,
				interior
			)
		end

		local x0, x1 = -HALL_X + PART_T / 2, HALL_X - PART_T / 2
		Kit.part(
			"StairLanding",
			V(x1 - x0, SLAB, GS_LAND_Z + IN_Z),
			place(V(0, GS_LAND_Y - SLAB / 2, (GS_LAND_Z - IN_Z) / 2)),
			C.FLOOR,
			M.WoodPlanks,
			interior
		)
		local ax0 = AS_WALL_X + PART_T / 2
		Kit.part(
			"StairLanding",
			V(IN_X - ax0, SLAB, AS_LAND_Z + IN_Z),
			place(V((ax0 + IN_X) / 2, AS_LAND_Y - SLAB / 2, (AS_LAND_Z - IN_Z) / 2)),
			C.FLOOR,
			M.WoodPlanks,
			interior
		)

		-- Stone flags in the kitchen, tiles in the bathroom.
		Kit.detail(
			Kit.part(
				"Flags",
				V(IN_X - HALL_X - 0.4, 0.06, IN_Z - 0.4),
				place(V(-(IN_X + HALL_X + 0.4) / 2, L1 + 0.03, -(IN_Z + 0.4) / 2)),
				C.SLATE,
				M.Slate,
				interior
			)
		).CastShadow =
			true
		Kit.detail(
			Kit.part(
				"Tiles",
				V(AS_WALL_X - HALL_X - 0.8, 0.06, IN_Z + L2_BACK_Z - 0.4),
				place(V((AS_WALL_X + HALL_X) / 2, L2 + 0.03, (-IN_Z + L2_BACK_Z - 0.4) / 2)),
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

	--[[
		Windows are placed by hand against the plan: unevenly, differing floor
		to floor, and every one at least a stud and a half clear of each
		partition, chimney breast, stair and landing, so nothing inside meets
		an outside wall across a window. The back wall of the stairwell is one
		band two storeys tall, with a stair window over the half landing.
	]]
	exterior(
		"Front",
		"X",
		WALL_Z,
		-IN_X,
		IN_X,
		1,
		bands({
			opening(BAY_MID, L1, BAY_W - 6, STOREY),
			doorway(FRONT_DOOR_X, L1, DOOR_W, DOOR_H),
			sash(-8.5, L1 + 4, 4, 7),
			sash(8.5, L1 + 4, 4, 7),
			sash(20, L1 + 4),
			sash(32, L1 + 4),
		}, {
			opening(BAY_MID, L2, BAY_W - 6, STOREY),
			sash(-16, L2 + 4, 4, 7),
			sash(-5, L2 + 3.5, 6, 8),
			sash(7, L2 + 4),
			sash(20, L2 + 4),
			sash(31, L2 + 4),
		}, { opening(BAY_MID, L3, BAY_W - 6, 7.5) }),
		place,
		shell
	)

	exterior(
		"BackLeft",
		"X",
		-WALL_Z,
		-IN_X,
		-HALL_X,
		-1,
		bands({ doorway(BACK_DOOR_X, L1, IN_DOOR_W, IN_DOOR_H) }, { sash(-32, L2 + 4, 5, 7) }, {}),
		place,
		shell
	)
	exterior("BackMiddle", "X", -WALL_Z, -HALL_X, HALL_X, -1, {
		{ bottom = L1, top = GS_LAND_Y - SLAB, windows = {} },
		{ bottom = GS_LAND_Y - SLAB, top = GS_LAND_Y, windows = {} },
		{ bottom = GS_LAND_Y, top = L2 + STOREY, windows = { sash(0, GS_LAND_Y + 2.8, 6, 13.5) } },
		{ bottom = L2 + STOREY, top = L3, windows = {} },
		{ bottom = L3, top = KNEE_TOP, windows = {} },
	}, place, shell)
	exterior(
		"BackRight",
		"X",
		-WALL_Z,
		HALL_X,
		IN_X,
		-1,
		bands(
			{ sash(20, L1 + 4, 5, 7), sash(33, L1 + 4, 5, 7) },
			{ sash(19, L2 + 6, 4, 5), sash(33, AS_LAND_Y + 2.5, 4, 3.5) },
			{}
		),
		place,
		shell
	)

	exterior(
		"Left",
		"Z",
		-WALL_X,
		-HALF_D,
		HALF_D,
		-1,
		bands({
			-- The kitchen's sills sit clear above the worktops under them.
			sash(-20, L1 + 4.3, 4, 6.7),
			sash(-7, L1 + 4.3, 6, 6.7),
			sash(5.5, L1 + 4, 4, 7),
			sash(24, L1 + 4, 4, 7),
		}, {
			sash(-15, L2 + 4, 5, 7),
			sash(0, L2 + 4),
			sash(23, L2 + 4),
		}, { sash(-10, L3 + 1, 5, 3.5) }),
		place,
		shell,
		WALL_T
	)
	exterior(
		"Right",
		"Z",
		WALL_X,
		-HALF_D,
		HALF_D,
		1,
		bands({
			sash(-20, L1 + 4, 5, 7),
			sash(-8, L1 + 4, 5, 7),
			sash(22, L1 + 4),
		}, {
			sash(-1.5, L2 + 4, 5, 7),
			sash(22, L2 + 4),
		}, { sash(-2, L3 + 1, 4, 3), sash(22, L3 + 1, 4, 3) }),
		place,
		shell,
		WALL_T
	)

	frontBay(place, shell)

	-- The two ways in and out.
	hang("X", WALL_Z, FRONT_DOOR_X, L1, DOOR_W, DOOR_H, BACK, LEFT, WALL_T, {
		outside = true,
		casing = C.FRAME,
		color = FRONT_DOOR,
		panel = rgb(54, 22, 19),
		leaf = 0.45,
		gap = 0.08,
		name = "FrontDoor",
	})
	hang("X", -WALL_Z, BACK_DOOR_X, L1, IN_DOOR_W, IN_DOOR_H, FRONT, LEFT, WALL_T, {
		outside = true,
		casing = C.FRAME,
		style = "plank",
		color = C.OAK,
		panel = C.WALNUT,
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

	-- Ground floor: the two long hall walls, and a cross wall on each side.
	partition(
		"HallWall",
		"Z",
		-HALL_X,
		-IN_Z,
		IN_Z,
		L1,
		L1 + STOREY,
		{ doorHole(14, L1), doorHole(-4, L1) }
	)
	partition(
		"HallWall",
		"Z",
		HALL_X,
		-IN_Z,
		IN_Z,
		L1,
		L1 + STOREY,
		{ doorHole(14, L1), doorHole(-4, L1) }
	)
	partition(
		"CrossWall",
		"X",
		0,
		-IN_X,
		-HALL_X,
		L1,
		L1 + STOREY,
		{ doorHole(-27, L1) },
		PART_T / 2
	)
	partition("CrossWall", "X", 0, HALL_X, IN_X, L1, L1 + STOREY, { doorHole(27, L1) }, PART_T / 2)
	hang("Z", -HALL_X, 14, L1, IN_DOOR_W, IN_DOOR_H, LEFT, FRONT, PART_T, { name = "ParlourDoor" })
	hang(
		"Z",
		-HALL_X,
		-4,
		L1,
		IN_DOOR_W,
		IN_DOOR_H,
		LEFT,
		BACK,
		PART_T,
		{ name = "KitchenDoor", ajar = 35 }
	)
	hang(
		"Z",
		HALL_X,
		14,
		L1,
		IN_DOOR_W,
		IN_DOOR_H,
		RIGHT,
		FRONT,
		PART_T,
		{ name = "DrawingRoomDoor" }
	)
	hang("Z", HALL_X, -4, L1, IN_DOOR_W, IN_DOOR_H, RIGHT, BACK, PART_T, { name = "LibraryDoor" })
	hang("X", 0, -27, L1, IN_DOOR_W, IN_DOOR_H, BACK, RIGHT, PART_T, { name = "PantryDoor" })
	hang("X", 0, 27, L1, IN_DOOR_W, IN_DOOR_H, BACK, LEFT, PART_T, { name = "StudyDoor" })

	-- First floor: the rooms behind the dining hall.
	partition(
		"BackPartition",
		"X",
		L2_BACK_Z,
		-IN_X,
		-HALL_X + PART_T / 2,
		L2,
		L2 + STOREY,
		{ doorHole(-28, L2) },
		PART_T / 2
	)
	partition(
		"BackPartition",
		"X",
		L2_BACK_Z,
		HALL_X - PART_T / 2,
		IN_X,
		L2,
		L2 + STOREY,
		{ doorHole(19, L2), doorHole(30, L2) },
		PART_T / 2
	)
	partition("StairwellWall", "Z", -HALL_X, -IN_Z, L2_BACK_Z - PART_T / 2, L2, L2 + STOREY, {})
	partition("StairwellWall", "Z", HALL_X, -IN_Z, L2_BACK_Z - PART_T / 2, L2, L2 + STOREY, {})
	partition("StairHallWall", "Z", AS_WALL_X, -IN_Z, L2_BACK_Z - PART_T / 2, L2, L2 + STOREY, {})
	hang(
		"X",
		L2_BACK_Z,
		-28,
		L2,
		IN_DOOR_W,
		IN_DOOR_H,
		BACK,
		RIGHT,
		PART_T,
		{ name = "BedroomDoor" }
	)
	hang(
		"X",
		L2_BACK_Z,
		19,
		L2,
		IN_DOOR_W,
		IN_DOOR_H,
		BACK,
		LEFT,
		PART_T,
		{ name = "BathroomDoor", ajar = 20 }
	)
	hang(
		"X",
		L2_BACK_Z,
		30,
		L2,
		IN_DOOR_W,
		IN_DOOR_H,
		-- Into the dining hall: into the stair hall, the leaf would swing up
		-- under the attic flight.
		FRONT,
		RIGHT,
		PART_T,
		{ name = "AtticStairDoor" }
	)

	--------------------------------------------------------------------------
	-- Stairs, and the cupboards under them
	--------------------------------------------------------------------------

	Kit.staircase(
		"GrandStairA",
		V(GS_A_X, L1, GS_FOOT_Z),
		V(GS_A_X, GS_LAND_Y, GS_LAND_Z),
		STAIR_W,
		10,
		place,
		interior,
		{ treadColor = C.OAK, railColor = C.WALNUT }
	)
	Kit.staircase(
		"GrandStairB",
		V(GS_B_X, GS_LAND_Y, GS_LAND_Z),
		V(GS_B_X, L2, GS_TOP_Z),
		STAIR_W,
		8,
		place,
		interior,
		{ treadColor = C.OAK, railColor = C.WALNUT }
	)
	-- Along the half landing, over the well, and along the gallery.
	Kit.railing(
		"Landing",
		GS_LAND_Y,
		{ axis = "X", fixed = GS_LAND_Z - 0.3, from = -WELL - 0.1, to = WELL + 0.1 },
		place,
		interior,
		nil,
		C.WALNUT
	)
	Kit.railing(
		"Gallery",
		L2,
		{ axis = "X", fixed = GS_TOP_Z + 0.3, from = -HALL_X + PART_T / 2, to = WELL - 0.4 },
		place,
		interior,
		nil,
		C.WALNUT
	)
	Kit.newel(
		"GalleryNewel",
		place(V(-HALL_X + PART_T / 2 + 0.5, L2, GS_TOP_Z + 0.3)).Position,
		4.6,
		C.WALNUT,
		interior
	)

	-- The attic stair: flight C up the right, a landing, flight D back.
	Kit.staircase(
		"AtticStairC",
		V(AS_C_X, L2, AS_FOOT_Z),
		V(AS_C_X, AS_LAND_Y, AS_LAND_Z),
		STAIR_W,
		8,
		place,
		interior,
		{ rails = { -1 }, wallRails = { 1 } }
	)
	Kit.staircase(
		"AtticStairD",
		V(AS_D_X, AS_LAND_Y, AS_LAND_Z),
		V(AS_D_X, L3, AS_TOP_Z),
		STAIR_W,
		10,
		place,
		interior
	)
	Kit.railing("AtticLanding", AS_LAND_Y, {
		axis = "X",
		fixed = AS_LAND_Z - 0.3,
		from = AS_D_X + STAIR_W / 2 + 0.3,
		to = AS_C_X - STAIR_W / 2 - 0.3,
	}, place, interior)
	Kit.railing(
		"AtticRail",
		L3,
		{ axis = "Z", fixed = AS_WALL_X + PART_T / 2 - 0.3, from = -IN_Z, to = AS_TOP_Z },
		place,
		interior
	)
	Kit.railing(
		"AtticRail",
		L3,
		{ axis = "X", fixed = AS_TOP_Z + 0.3, from = AS_D_X + STAIR_W / 2 + 0.5, to = IN_X },
		place,
		interior
	)

	-- Under the half landing: a store as wide as the hall, low and dark,
	-- behind a small door from the well.
	local underH = GS_LAND_Y - SLAB
	partition(
		"UnderLandingWall",
		"X",
		GS_LAND_Z,
		-HALL_X + PART_T / 2,
		HALL_X - PART_T / 2,
		L1,
		underH,
		{ doorHole(-2, L1, 3.4, underH - 1.0) }
	)
	hang(
		"X",
		GS_LAND_Z,
		-2,
		L1,
		3.4,
		underH - 1.0,
		BACK,
		LEFT,
		PART_T,
		{ style = "plank", color = C.WALNUT, panel = C.OAK, name = "UnderLandingDoor" }
	)
	hide(
		Kit.hideVolume(
			"UnderLandingHidingVolume",
			place(V(0, L1 + 2.6, (GS_LAND_Z - IN_Z) / 2)),
			V(20, 5, 4.6),
			"Cupboard",
			1,
			interior
		)
	)

	-- Under flight B: a cupboard whose ceiling is the flight, closed on its
	-- open side by a panel that follows the flight's underside.
	partition(
		"UnderStairWall",
		"X",
		GS_TOP_Z,
		WELL,
		HALL_X - PART_T / 2,
		L1,
		L1 + STOREY,
		{ doorHole(8.75, L1, 3.4, 8) }
	)
	hang(
		"X",
		GS_TOP_Z,
		8.75,
		L1,
		3.4,
		8,
		BACK,
		RIGHT,
		PART_T,
		{ style = "cabinet", name = "UnderStairDoor" }
	)
	hide(
		Kit.hideVolume(
			"UnderStairHidingVolume",
			place(V(8.75, L1 + 3.2, -14.5)),
			V(5.4, 6, 4.5),
			"Cupboard",
			1,
			interior
		)
	)
	local function underside(z: number, z0: number, y0: number, z1: number, y1: number): number
		return y0 + (y1 - y0) * (z - z0) / (z1 - z0) - 1.0
	end
	local panelX = WELL + PART_T / 2 - 0.4
	partition("Spandrel", "Z", panelX, GS_LAND_Z, GS_TOP_Z, L1, underH, {})
	Kit.triangle(
		"Spandrel",
		place(V(panelX, underH, GS_LAND_Z)).Position,
		place(V(panelX, underH, GS_TOP_Z)).Position,
		place(V(panelX, L2 - 1.0, GS_TOP_Z)).Position,
		PART_T,
		C.WAINSCOT,
		M.WoodPlanks,
		interior
	)
	-- The same paper as the hall on the panel's well side, up to the flight.
	for _, w in
		Kit.triangle(
			"SpandrelPaper",
			place(V(panelX - PART_T / 2 - 0.05, underH, GS_LAND_Z)).Position,
			place(V(panelX - PART_T / 2 - 0.05, underH, GS_TOP_Z)).Position,
			place(V(panelX - PART_T / 2 - 0.05, L2 - 1.0, GS_TOP_Z)).Position,
			0.1,
			F_HALL.paper,
			M.Fabric,
			interior
		)
	do
		w.CanCollide = false
		w.CanQuery = false
	end
	-- Under flight A: closed dead space, a panel on the well side.
	local zFloorA = GS_FOOT_Z - 1.0 / (GS_LAND_Y / (GS_FOOT_Z - GS_LAND_Z))
	Kit.triangle(
		"Spandrel",
		place(V(-panelX, L1, zFloorA)).Position,
		place(V(-panelX, L1, GS_LAND_Z)).Position,
		place(V(-panelX, underside(GS_LAND_Z, GS_FOOT_Z, L1, GS_LAND_Z, GS_LAND_Y), GS_LAND_Z)).Position,
		PART_T,
		C.WAINSCOT,
		M.WoodPlanks,
		interior
	)
	-- The attic stair's dead spaces: under its landing, and under flight C.
	partition(
		"UnderAtticLanding",
		"X",
		AS_LAND_Z,
		AS_WALL_X + PART_T / 2,
		IN_X,
		L2,
		AS_LAND_Y - SLAB,
		{}
	)
	local zFloorC = AS_FOOT_Z - 1.0 / ((AS_LAND_Y - L2) / (AS_FOOT_Z - AS_LAND_Z))
	local cPanel = AS_C_X - STAIR_W / 2 - 0.3
	Kit.triangle(
		"Spandrel",
		place(V(cPanel, L2, zFloorC)).Position,
		place(V(cPanel, L2, AS_LAND_Z)).Position,
		place(V(cPanel, AS_LAND_Y - SLAB, AS_LAND_Z)).Position,
		PART_T,
		C.WAINSCOT,
		M.WoodPlanks,
		interior
	)

	--------------------------------------------------------------------------
	-- Roof, chimneys, porch
	--------------------------------------------------------------------------

	roof(place, shell, rng)
	chimney(place, shell, "back", BACK_CHIMNEY_X, {
		{ level = L1, w = 5.8, h = 5.2, grate = false, depth = 2.7 },
		{ level = L2, w = 3.6, h = 3.6 },
	}, RIDGE + 5)
	chimney(place, shell, "left", 14, {
		{ level = L1, w = 4.4, h = 4.2 },
		{ level = L2, w = 5.0, h = 4.6 },
	}, RIDGE + 4)
	chimney(place, shell, "right", RIGHT_CHIMNEY_Z, {
		{ level = L1, w = 4.4, h = 4.2 },
		{ level = L2, w = 5.0, h = 4.6 },
	}, RIDGE + 4)
	verandah(place, shell)
	backStoop(place, shell)

	--------------------------------------------------------------------------
	-- Furniture
	--------------------------------------------------------------------------

	-- Furniture against a wall stands this far out from the wall's
	-- structural face: clear of the skirting (0.24 deep) and the chair rail
	-- (0.27), with a little to spare.
	local LINING = 0.3
	-- Build a piece with its pivot on a wall face, then slide it out until
	-- its back clears the linings.
	local function against(m: Model): Model
		return Furnish.backTo(m, LINING)
	end

	-- `fixed` is the wall's structural face.
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

	-- The entrance hall: a long runner to the stair, a table, a mirror, a
	-- clock in the well, a chandelier that has not been lit in years.
	Decor.rug(spot(0, L1, 9, BACK), furniture, { width = 5, length = 32, color = rgb(58, 26, 22) })
	Decor.chandelier(spot(0, L1 + STOREY, 10), furniture, { drop = 3.5, arms = 6 })
	local hallTable = spot(-HALL_X + PART_T / 2 + 1.3, L1, 5, RIGHT)
	Furnish.sideTable(hallTable, furniture, { width = 2.4, height = 3.4 })
	Decor.candelabra(hallTable * CFrame.new(0, 3.4, 0), furniture)
	Decor.mirror(spot(HALL_X - PART_T / 2 - 0.1, L1 + 7.2, 5, LEFT), furniture)
	against(
		Furnish.bench(
			spot(-HALL_X + PART_T / 2, L1, 22.5, RIGHT),
			furniture,
			{ length = 6, wood = C.WALNUT }
		)
	)
	against(Furnish.clock(spot(2.6, L1, GS_LAND_Z + PART_T / 2, FRONT), furniture))
	Decor.painting(
		spot(-HALL_X + PART_T / 2 + 0.1, L1 + 7.8, 5, RIGHT),
		furniture,
		{ width = 3.4, height = 4.4 }
	)
	Decor.painting(
		spot(HALL_X - PART_T / 2 - 0.1, L1 + 7.5, 23, LEFT),
		furniture,
		{ subject = "landscape", width = 5, height = 3.4, tilt = -4 }
	)

	-- The parlour, round the fireplace on the left wall, with the bay as a
	-- sitting nook.
	Decor.rug(spot(-28, L1, 14, BACK), furniture, { width = 12, length = 15 })
	Furnish.sofa(
		spot(-23.5, L1, 14, LEFT),
		furniture,
		{ cover = C.VELVET_DARK, material = M.Fabric }
	)
	Furnish.armchair(spot(-34, L1, 8.2, FRONT), furniture)
	Furnish.armchair(spot(-34, L1, 19.8, BACK), furniture)
	Furnish.roundTable(
		spot(-29.5, L1, 14),
		furniture,
		{ diameter = 3.6, height = 2.4, name = "CoffeeTable" }
	)
	Decor.books(spot(-29.2, L1 + 2.4, 13.6), furniture)
	against(Furnish.bookcase(spot(-HALL_X - PART_T / 2, L1, 5, LEFT), furniture))
	against(
		Furnish.bookcase(spot(-HALL_X - PART_T / 2, L1, 23, LEFT), furniture, { sparse = true })
	)
	Furnish.roundTable(spot(BAY_MID, L1, 34), furniture, { diameter = 4.2, height = 3.4 })
	Furnish.diningChair(spot(BAY_MID - 3, L1, 34, RIGHT), furniture, { seat = C.VELVET_DARK })
	Furnish.diningChair(
		spot(BAY_MID + 3, L1, 33, LEFT) * CFrame.Angles(0, 0.4, 0),
		furniture,
		{ seat = C.VELVET_DARK }
	)
	Decor.birdcage(spot(BAY_MID + 0.4, L1 + 3.4, 34.3), furniture)
	Furnish.doll(spot(-23.5, L1 + 1.95, 12.6, LEFT), furniture, { dress = C.VELVET })
	curtainsAt("Z", -IN_X, 5.5, L1 + 11.4, 4, RIGHT)
	curtainsAt("Z", -IN_X, 24, L1 + 11.4, 4, RIGHT)
	Decor.painting(spot(-15.6, L1 + 7.5, IN_Z - 0.1, BACK), furniture, { width = 3.6, height = 5 })

	-- The kitchen: a range in the cooking hearth, a work table to hide
	-- under, the sink under the window, a dresser full of plates, and a larder
	-- cupboard you can shut yourself into.
	-- In the cooking hearth, its back to the soot and its pipe up into the
	-- flue under the lintel.
	Furnish.backTo(
		Furnish.range(
			spot(BACK_CHIMNEY_X, L1, -HALF_D + STACK_D / 2 - 2.7 + 0.1, FRONT),
			furniture,
			{ width = 5.2, depth = 2.6, pipeTop = 5.2 }
		),
		0.05
	)
	local _, underTable = Furnish.workTable(spot(-27, L1, -13), furniture)
	hide(underTable)
	Furnish.stool(spot(-27, L1, -9.8), furniture)
	Furnish.stool(spot(-23.5, L1, -16.4), furniture)
	against(Furnish.counter(spot(-IN_X, L1, -7, RIGHT), furniture, { width = 8, sink = true }))
	against(Furnish.counter(spot(-IN_X, L1, -20, RIGHT), furniture, { width = 6 }))
	against(Furnish.hutch(spot(-HALL_X - PART_T / 2, L1, -15, LEFT), furniture))
	-- Narrow enough to clear the pantry door's casing, and far enough along
	-- that its left door swings clear of the sink counter.
	local larderCupboard, larder = Furnish.wardrobe(
		spot(-34.3, L1, -PART_T / 2),
		furniture,
		{ name = "LarderCupboard", wood = C.PINE, depth = 4.2, width = 5.4 }
	)
	against(larderCupboard)
	hide(larder)
	Furnish.barrel(spot(-39.2, L1, -26.2), furniture)
	Furnish.barrel(spot(-36.7, L1, -26.6), furniture, { height = 2.8, diameter = 2.1 })
	Decor.wallShelf(spot(-IN_X + 0.1, L1 + 6.2, -13.8, RIGHT), furniture, { width = 4.5 })
	Decor.wallShelf(spot(-16.2, L1 + 6.5, -IN_Z + 0.1, FRONT), furniture, { width = 3.6 })

	-- The drawing room: the piano against the hall wall, a sofa and chairs
	-- round the right-hand fireplace.
	local fz = RIGHT_CHIMNEY_Z
	Decor.rug(
		spot(29, L1, fz, BACK),
		furniture,
		{ width = 13, length = 15, color = rgb(52, 30, 26) }
	)
	against(Furnish.piano(spot(HALL_X + PART_T / 2, L1, 6, RIGHT), furniture))
	Furnish.sofa(spot(28.5, L1, fz, RIGHT), furniture)
	Furnish.armchair(
		spot(33.8, L1, fz - 5.8, FRONT),
		furniture,
		{ cover = C.VELVET, material = M.Fabric }
	)
	Furnish.armchair(
		spot(33.8, L1, fz + 5.8, BACK),
		furniture,
		{ cover = C.VELVET, material = M.Fabric }
	)
	Furnish.sideTable(spot(37.8, L1, 25.2), furniture)
	Furnish.gramophone(spot(37.8, L1 + 3.2, 25.2, LEFT), furniture)
	Furnish.mannequin(spot(17, L1, 25, BACK * -1 + RIGHT * 0.6), furniture, { dress = C.VELVET })
	curtainsAt("Z", IN_X, 22, L1 + 11.4, 6, LEFT, C.VELVET_DARK)
	curtainsAt("X", IN_Z, 20, L1 + 11.4, 6, BACK, C.VELVET_DARK)
	curtainsAt("X", IN_Z, 32, L1 + 11.4, 6, BACK, C.VELVET_DARK)
	Decor.painting(spot(26, L1 + 7.4, IN_Z - 0.1, BACK), furniture, { width = 4, height = 5.2 })

	-- The library: shelves on every wall that has room for them, a desk, a
	-- globe, a chair by the window.
	Decor.rug(
		spot(27, L1, -14, BACK),
		furniture,
		{ width = 12, length = 14, color = rgb(46, 30, 26) }
	)
	against(Furnish.bookcase(spot(HALL_X + PART_T / 2, L1, -12, RIGHT), furniture))
	against(Furnish.bookcase(spot(HALL_X + PART_T / 2, L1, -20, RIGHT), furniture))
	against(Furnish.bookcase(spot(36, L1, -PART_T / 2, BACK), furniture))
	-- Between the swings of the two doors into the library.
	against(
		Furnish.bookcase(
			spot(20.85, L1, -PART_T / 2, BACK),
			furniture,
			{ sparse = true, width = 4.4 }
		)
	)
	against(Furnish.bookcase(spot(26.5, L1, -IN_Z, FRONT), furniture))
	-- Narrower, to fit between the windows on the gable wall.
	against(Furnish.bookcase(spot(IN_X, L1, -14, LEFT), furniture, { width = 4.8 }))
	against(Furnish.bookcase(spot(IN_X, L1, -25.4, LEFT), furniture, { width = 3.6 }))
	Furnish.desk(spot(28, L1, -16, FRONT), furniture)
	Furnish.diningChair(spot(28, L1, -13.2, BACK), furniture, { seat = C.LEATHER })
	Decor.books(spot(26.4, L1 + 3.3, -16.4), furniture, { count = 3 })
	Decor.candelabra(spot(30.4, L1 + 3.3, -15.8), furniture, { height = 1.4 })
	Decor.globe(spot(35.5, L1, -4.5), furniture)
	Furnish.armchair(spot(34, L1, -23.5, FRONT + RIGHT * 0.5), furniture)

	-- The dining hall: one long table laid for twenty, fireplaces at both
	-- ends, sideboards along the back, two chandeliers, and a nook in the
	-- bay. It is the room the house was built around.
	local tableZ = 12
	local tableL, tableW = 32, 7
	Decor.rug(
		spot(0, L2, tableZ, BACK),
		furniture,
		{ width = 42, length = 16, color = rgb(56, 24, 22) }
	)
	local _, underBanquet = Furnish.diningTable(spot(0, L2, tableZ), furniture, {
		name = "BanquetTable",
		length = tableL,
		width = tableW,
		cloth = C.LINEN,
		floor = 2,
	})
	hide(underBanquet)
	local topY = L2 + 4.0 + 0.06
	local seats = 9
	for i = 0, seats - 1 do
		local x = -tableL / 2 + 2.2 + (tableL - 4.4) * i / (seats - 1)
		for _, side in { -1, 1 } do
			local z = tableZ + side * (tableW / 2 + 1.6)
			local face = V(0, 0, -side)
			if i == 6 and side == 1 then
				Furnish.toppledChair(
					spot(x + 0.5, L2, z + 1.2, face),
					furniture,
					{ seat = C.VELVET_DARK }
				)
			else
				local askew = if (i + side) % 4 == 0 then 0.25 else 0
				Furnish.diningChair(
					spot(x, L2, z + side * askew * 2, face) * CFrame.Angles(0, askew * side, 0),
					furniture,
					{ seat = C.VELVET_DARK }
				)
			end
			Decor.placeSetting(
				spot(x, topY, tableZ + side * (tableW / 2 - 0.1), V(0, 0, side)),
				furniture,
				{
					upset = i == 6 and side == 1,
					food = (i + side) % 3 == 0,
				}
			)
		end
	end
	for _, side in { -1, 1 } do
		Furnish.armchair(
			spot(side * (tableL / 2 + 2.6), L2, tableZ, V(-side, 0, 0)),
			furniture,
			{ cover = C.VELVET, material = M.Fabric }
		)
		Decor.placeSetting(spot(side * (tableL / 2 - 0.6), topY, tableZ, V(side, 0, 0)), furniture)
	end
	for _, x in { -9, 0, 9 } do
		Decor.candelabra(spot(x, topY + 0.08, tableZ), furniture, { fallen = x == 9 })
	end
	Decor.platter(spot(-4.5, topY + 0.08, tableZ), furniture)
	Decor.platter(spot(4.5, topY + 0.08, tableZ), furniture)
	for _, x in { -8, 8 } do
		Decor.chandelier(
			spot(x, L2 + STOREY, tableZ),
			furniture,
			{ drop = 4, arms = 8, radius = 2.6 }
		)
	end
	local left = against(
		Furnish.sideboard(spot(-36.5, L2, L2_BACK_Z + PART_T / 2, FRONT), furniture, { width = 8 })
	)
	local right = against(
		Furnish.sideboard(spot(-18.9, L2, L2_BACK_Z + PART_T / 2, FRONT), furniture, { width = 9 })
	)
	Decor.candelabra(left.WorldPivot * CFrame.new(0, 3.8, 0), furniture)
	Decor.vase(right.WorldPivot * CFrame.new(1.9, 3.8, 0.1), furniture)
	against(Furnish.clock(spot(37, L2, L2_BACK_Z + PART_T / 2, FRONT), furniture))
	-- Between the curtains, which hang well out past each window.
	for _, x in { -10.9, 1, 13.5, 25.2 } do
		Decor.painting(
			spot(x, L2 + 7.8, IN_Z - 0.1, BACK),
			furniture,
			{ width = 2.8, height = 4, tilt = if x == 13.5 then 6 else 0 }
		)
	end
	-- One window has lost its curtains altogether.
	for _, w in { { -16, 4 }, { -5, 6 }, { 7, 6 }, { 31, 6 } } do
		curtainsAt("X", IN_Z, w[1], L2 + 11.6, w[2], BACK)
	end
	for _, zw in { { 0, 6 }, { 23, 6 } } do
		curtainsAt("Z", -IN_X, zw[1], L2 + 11.4, zw[2], RIGHT)
	end
	for _, zw in { { -1.5, 5 }, { 22, 6 } } do
		curtainsAt("Z", IN_X, zw[1], L2 + 11.4, zw[2], LEFT)
	end
	-- The bay nook: two chairs by the window and a gramophone, and a doll.
	Furnish.roundTable(spot(BAY_MID, L2, 33.5), furniture, { diameter = 3.4, height = 2.6 })
	Furnish.armchair(
		spot(BAY_MID - 4, L2, 34.5, RIGHT + FRONT * 0.3),
		furniture,
		{ cover = C.VELVET_DARK, material = M.Fabric }
	)
	Furnish.armchair(
		spot(BAY_MID + 4, L2, 34.5, LEFT + FRONT * 0.3),
		furniture,
		{ cover = C.VELVET_DARK, material = M.Fabric }
	)
	Furnish.gramophone(spot(BAY_MID, L2 + 2.6, 33.4, BACK), furniture)
	Furnish.doll(spot(BAY_MID + 4.3, L2 + 1.95, 34.2, LEFT), furniture, { dress = C.CLOTH })

	-- The bedroom: a four-poster against the stairwell wall, a wardrobe, a
	-- chest with a mirror, a rocking chair turned to the window.
	Decor.rug(
		spot(-24, L2, -18, BACK),
		furniture,
		{ width = 12, length = 13, color = rgb(60, 36, 30) }
	)
	local bed, underBed =
		Furnish.bed(spot(-HALL_X - PART_T / 2, L2, -17, LEFT), furniture, { floor = 2 })
	against(bed)
	hide(underBed)
	against(Furnish.nightstand(spot(-HALL_X - PART_T / 2, L2, -21.6, LEFT), furniture))
	against(Furnish.nightstand(spot(-HALL_X - PART_T / 2, L2, -12.4, LEFT), furniture))
	local wardrobe, bedroomWardrobe =
		Furnish.wardrobe(spot(-IN_X, L2, -23.8, RIGHT), furniture, { floor = 2 })
	against(wardrobe)
	hide(bedroomWardrobe)
	against(
		Furnish.chestOfDrawers(
			spot(-37, L2, L2_BACK_Z - PART_T / 2, BACK),
			furniture,
			{ mirror = true }
		)
	)
	Furnish.rockingChair(spot(-34, L2, -15.5, LEFT + BACK * 0.3), furniture)
	Furnish.doll(spot(-34.1, L2 + 2.5, -15.4, LEFT + BACK * 0.3), furniture, { dress = C.LINEN })
	curtainsAt("Z", -IN_X, -15, L2 + 11.4, 5, RIGHT, C.VELVET_DARK)

	-- The bathroom.
	against(Furnish.bathtub(spot(19, L2, -IN_Z, FRONT), furniture))
	against(Furnish.toilet(spot(AS_WALL_X - PART_T / 2, L2, -18, LEFT), furniture))
	against(Furnish.washstand(spot(HALL_X + PART_T / 2, L2, -21, RIGHT), furniture))

	-- The attic: the house's forgotten things, pushed under the eaves.
	Furnish.trunk(spot(-30, L3, -23, FRONT), furniture)
	Furnish.trunk(
		spot(-14, L3, 23.5, BACK) * CFrame.Angles(0, 0.2, 0),
		furniture,
		{ cover = C.LEATHER_DARK }
	)
	Furnish.trunk(spot(10, L3, -24, FRONT), furniture)
	Furnish.mannequin(spot(-8, L3, -18, FRONT), furniture)
	Furnish.mannequin(spot(-12, L3, 20, RIGHT), furniture, { dress = C.CLOTH })
	Furnish.rockingHorse(spot(2, L3, 18, RIGHT), furniture)
	Furnish.crib(spot(-34, L3, 8, RIGHT), furniture)
	Furnish.barrel(spot(-36.5, L3, -22), furniture)
	Furnish.rockingChair(spot(-2, L3, 0, BACK), furniture, { tilt = 0 })
	Furnish.doll(spot(-14.2, L3 + 2.8, 23.4, BACK), furniture, { dress = C.VELVET_DARK })
	Furnish.chestOfDrawers(spot(20, L3, 23, BACK), furniture, { open = true })
	Decor.painting(
		spot(-31, L3 + 2.25, -IN_Z + 0.9, FRONT) * CFrame.Angles(math.rad(15), 0, 0),
		furniture,
		{ width = 3, height = 4 }
	)
	Decor.lantern(spot(4, L3, -4), furniture)

	-- The porch: a rocking chair left facing the road, a bench, dead plants.
	Furnish.rockingChair(spot(40, L1, 34, FRONT), furniture)
	Furnish.bench(spot(12, L1, HALF_D + 1.3, FRONT), furniture, { length = 7, wood = C.WALNUT })
	for _, x in { -6.5, 6.5 } do
		Decor.vase(spot(x, L1, HALF_D + 1.3), furniture, { color = rgb(70, 46, 38) })
	end

	--------------------------------------------------------------------------
	-- Dirt, damage and worse
	--------------------------------------------------------------------------

	local function floorAt(x: number, y: number, z: number): CFrame
		return place(V(x, y, z))
	end
	-- On a wall face, looking into the room: `face` is the way into the room.
	local function wallAt(x: number, y: number, z: number, face: Vector3): CFrame
		return place(V(x, y, z)) * CFrame.new(Vector3.zero, face)
	end

	-- Old stains soaked into the floors.
	for _, s in
		{
			{ -6, L1, 18, 2.2 },
			{ 5, L1, 2, 1.6 },
			{ -30, L1, -8, 2.4 },
			{ 30, L1, 20, 1.8 },
			{ -24, L2, -24, 1.6 },
			{ 16, L2, -22, 1.4 },
			{ -10, L3, 6, 3 },
			{ 18, L3, -6, 2.4 },
		}
	do
		Decor.stain(floorAt(s[1], s[2], s[3]), dressing, s[4])
	end
	-- Something was dragged out from under the banquet table, along the
	-- gallery and down the stairs.
	Decor.stain(floorAt(3, L2, tableZ - 1), dressing, 2.2, C.BLOOD_OLD)
	local trail = { V(3, L2, tableZ - 4.5), V(3.5, L2, 2), V(5.5, L2, -4), V(7.5, L2, -9.9) }
	for i = 1, #trail - 1 do
		Decor.smear(
			place(trail[i]).Position,
			place(trail[i + 1]).Position,
			dressing,
			0.9 - i * 0.12
		)
	end
	Decor.stain(floorAt(-24.5, L1, -10.5), dressing, 1.4, C.BLOOD_OLD)
	Decor.stain(floorAt(19, L2, -21), dressing, 1.2, C.BLOOD_OLD)

	-- Water down the walls under the worst of the roof.
	Decor.drips(wallAt(-38, L2 + 12.6, IN_Z - 0.12, BACK), dressing, 3, 7)
	Decor.drips(wallAt(-IN_X + 0.12, L1 + 12.6, -14, RIGHT), dressing, 2.4, 5.4)
	Decor.drips(wallAt(-6, L2 + 12.6, -IN_Z + 0.12, FRONT), dressing, 2.8, 9)
	Decor.drips(wallAt(37.5, L2 + 12.6, IN_Z - 0.12, BACK), dressing, 2, 5)
	-- Paper coming away.
	Decor.peel(wallAt(-IN_X + 0.1, L2 + 11.8, 8, RIGHT), dressing, C.PAPER_OXBLOOD)
	Decor.peel(
		wallAt(IN_X - 0.1, L2 + 11.6, -5, LEFT),
		dressing,
		C.PAPER_OXBLOOD,
		{ width = 1.8, length = 4.5 }
	)
	Decor.peel(wallAt(-HALL_X + PART_T / 2 + 0.1, L1 + 12.4, 20, RIGHT), dressing, C.PAPER_DAMASK)
	Decor.peel(
		wallAt(-HALL_X - PART_T / 2 - 0.1, L2 + 12.6, -24.5, LEFT),
		dressing,
		C.PAPER_OCHRE,
		{ length = 5 }
	)
	-- Something has clawed at the inside of the larder door's wall, and at
	-- the wall over the bed.
	Decor.scratches(wallAt(-38.5, L1 + 5.5, -0.4 - PART_T / 2 - 0.1, BACK), dressing, 3.4)
	Decor.scratches(wallAt(-HALL_X - PART_T / 2 - 0.12, L2 + 7.5, -17, LEFT), dressing, 2.6)
	Decor.scratches(wallAt(-3, L3 + 3, -IN_Z + 0.12, FRONT), dressing, 2.2)
	-- A place in the attic where the boards have given way, and plaster down
	-- from the dining hall ceiling.
	Decor.brokenBoards(floorAt(14, L3, 8), dressing)
	Decor.fallenPlaster(floorAt(26, L2, 22), dressing, STOREY)

	-- Outside: rot running down from under the eaves.
	Decor.drips(wallAt(-8, KNEE_TOP - 1, -HALF_D - 0.35, BACK), dressing, 4, 12, rgb(36, 30, 24))
	Decor.drips(wallAt(HALF_W + 0.35, L2 + 10, -14, RIGHT), dressing, 3, 9, rgb(36, 30, 24))
	Decor.drips(wallAt(-HALF_W - 0.35, L1 + 11, -24, LEFT), dressing, 3, 8, rgb(36, 30, 24))

	model.Parent = parent

	print(
		string.format(
			"[Manor] %d parts, %d hiding places, ridge %d studs above ground",
			Kit.count(),
			#hidingSpots,
			RIDGE - GROUND
		)
	)

	return {
		model = model,
		-- Standing height at the foot of the front steps, looking at the door.
		entrance = CFrame.lookAt(
			place(V(STEP_CENTRE, GROUND + 3, PORCH_OUT_Z + 18)).Position,
			place(V(FRONT_DOOR_X, GROUND + 3, WALL_Z)).Position
		),
		hidingSpots = hidingSpots,
		partCount = Kit.count(),
	}
end

return Manor
