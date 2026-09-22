--!strict
--[[
	A derelict manor, generated entirely in code.

	Self-contained on purpose: this module requires nothing from the rest of the
	project, reads no Config and touches no existing scenery. Drop it in, call
	`Manor.build`, and nothing that already works can be affected by it — and it
	can be deleted again in one keystroke.

	Three floors you can walk: two storeys of rooms plus an open attic, joined
	by a switchback stair through a double-height hall. Every room has at least
	two ways out, so a chase loops instead of dead-ending, and there are ten
	places to hide.

	Nothing here is a MeshPart. `MeshPart.MeshId` is read-only from a script, so
	a mesh cannot be built or swapped in Luau at all — it has to be imported by
	hand or pushed through AssetService. Everything below is Parts and
	WedgeParts, and the weathering comes from Roblox's built-in PBR materials
	(WoodPlanks, Cobblestone, RoofShingles) rather than uploaded textures, which
	would each need an asset id. That is the whole reason it costs nothing to
	regenerate or reshape.

	Local space runs +X right, +Y up, +Z out toward the front porch. The house is
	built against a caller-supplied pivot, so every offset below is a plain
	number in house space and the rotation happens in exactly one place.
]]

local CollectionService = game:GetService("CollectionService")

local Manor = {}

-- Guards against emitting zero-thickness parts when two cut lines coincide.
local EPS = 1e-3

--[[
	The vertical stack. Y is measured from the ground floor's walking surface,
	so the numbers a player actually experiences — ceiling height, sill height —
	are the ones written here, and the foundation is the only negative.
]]
local STOREY = 13 -- clear floor-to-ceiling
local SLAB = 1 -- floor thickness between storeys
local FOUND_H = 7 -- stone base; the ground sits at -FOUND_H

local L1 = 0
local L2 = L1 + STOREY + SLAB -- 14
local L3 = L2 + STOREY + SLAB -- 28, attic floor
local KNEE = 5 -- attic knee wall, so the eaves are not at head height
local KNEE_TOP = L3 + KNEE -- 33, where the roof springs
local GROUND = -FOUND_H

--[[
	Footprint, measured across the outer faces of the walls.

	Deliberately narrower than it is tall. A 76-wide block with the same storey
	heights read as a lodge rather than a manor: the reference gets its menace
	from being vertical, and width is the one dimension that fights that. 66 by
	46 still leaves four rooms of roughly 20 by 21 studs on each floor, which is
	cavernous next to a five-stud character.
]]
local MAIN_W = 66
local MAIN_D = 46
local HALF_W = MAIN_W / 2 -- 33
local HALF_D = MAIN_D / 2 -- 23

local WALL_T = 1 -- exterior
local PART_T = 0.8 -- interior partitions

--[[
	Clapboard courses: a thin board laid across every outside wall piece every
	2.4 studs. Flat-shaded Roblox walls read as painted card whatever material
	they carry, because nothing on them catches a shadow. These do: each one is
	a real edge, so the walls pick up lines from the lighting in the same way
	the reference's weatherboarding does. They are laid on the wall pieces
	themselves, so they stop at every window and door without any extra logic.
]]
local COURSE_SPACING = 2.6
local COURSE_H = 0.28
local COURSE_DEPTH = 0.22

-- Centre lines, so the outer face lands exactly on the footprint.
local WALL_X = HALF_W - WALL_T / 2 -- 32.5
local WALL_Z = HALF_D - WALL_T / 2 -- 22.5
local IN_X = HALF_W - WALL_T -- 32, inner face
local IN_Z = HALF_D - WALL_T -- 22

-- A 49-degree pitch, so the roof mass is nearly as tall as the walls under it.
-- Anything shallower and the cross gables have nothing to stand out from.
local ROOF_RISE = 30
local EAVE = 3 -- overhang past the walls
local ROOF_RUN = HALF_D + EAVE -- 26
local ROOF_PITCH = math.atan2(ROOF_RISE, ROOF_RUN)
local ROOF_FALL = ROOF_RISE / ROOF_RUN -- studs down per stud out
local RIDGE = KNEE_TOP + ROOF_RISE -- 63
local ROOF_T = 1.2

--[[
	The projecting front bay: the one piece of massing that stops this being a
	symmetrical box.

	A plain rectangle with a centred porch reads as a chapel or a dojo however
	it is detailed, because the eye finds the mirror line immediately. A wing
	thrown forward off one side of the front, with the porch squeezed into what
	is left, gives the house a dominant side and a subordinate one — which is
	what every real house that grew over a century actually looks like.

	It is pitched steeper than the main roof so the two never look like one
	extruded shape, and its peak lands below the main ridge so the main block
	still reads as the tallest thing.
]]
local BAY_X0 = -30
local BAY_X1 = -13
local BAY_W = BAY_X1 - BAY_X0 -- 17
local BAY_MID = (BAY_X0 + BAY_X1) / 2 -- -21.5
local BAY_PITCH = 1.4 -- rise per stud of half span

local PORCH_D = 9
local PORCH_OUT_Z = HALF_D + PORCH_D -- 32, front edge of the deck
local PORCH_OUT_X = HALF_W + PORCH_D -- 42
local PORCH_X0 = BAY_X1 -- the porch starts where the bay stops
local PORCH_RETURN_Z = 4 -- how far the one side wing runs back
local STEP_CENTRE = 20 -- steps off to one side, not on the axis
local STEP_HALF = 7 -- half the gap left in the railing for them
local RAIL_TOP = 3.8

local BAY_Z = PORCH_OUT_Z -- the bay front is flush with the porch
local BAY_PEAK = KNEE_TOP + (BAY_W / 2) * BAY_PITCH
local BAY_STOP = (RIDGE - BAY_PEAK) / ROOF_FALL -- where its ridge bites the main slope

--[[
	The hall is 24 wide because it has to hold two staircases side by side and
	still be walkable between them. Any narrower and the upstairs landing
	pinches to a slot a player cannot pass another player in.
]]
local HALL_X = 12 -- partitions at +/- this
local STAIR_W = 6
local STAIR_STEPS = 18
local STAIR_Z_LOW = 8 -- bottom tread
local STAIR_Z_HIGH = -16 -- top landing edge
local S1_MID = -8 -- grand stair, climbing toward the back
local S2_MID = 8 -- attic stair, climbing back toward the front

local DOOR_W = 8
local DOOR_H = 11
local INNER_DOOR_W = 7
local INNER_DOOR_H = 10

--[[
	Dark, weathered timber with most of the colour gone out of it. Old wood
	does not stay brown; it darkens and greys from the surface in, and a house
	that has stood empty long enough to be worth exploring is well down that
	road. The dressings — corner boards, fascias, window frames — are a dirty
	stone grey, as painted trim that has lost its paint goes. Everything is
	chosen against everything else, so the lanterns are the only warm thing
	in frame.
]]
local BOARD = Color3.fromRGB(86, 70, 54)
local BOARD_DARK = Color3.fromRGB(68, 54, 42)
local BOARD_PALE = Color3.fromRGB(104, 88, 70)
local CLAPBOARD = Color3.fromRGB(74, 60, 46)
local STONE = Color3.fromRGB(118, 112, 102)
local STONE_DARK = Color3.fromRGB(92, 86, 78)
local TRIM = Color3.fromRGB(138, 132, 122)
local TIMBER = Color3.fromRGB(52, 42, 32)
local SHINGLE = Color3.fromRGB(54, 48, 44)
local FLOORBOARD = Color3.fromRGB(74, 58, 44)
local PLASTER = Color3.fromRGB(126, 112, 94)
local LANTERN = Color3.fromRGB(255, 176, 88)
local WEB = Color3.fromRGB(226, 226, 222)

--[[
	Weathering. No two boards on an old house are the same shade, and a wall
	whose every piece is one exact colour is the strongest tell that it was
	generated. Seeded, so a given board is the same shade on every server.
]]
local weatherRng = Random.new(8891)

local function weathered(base: Color3, amount: number?): Color3
	local range = amount or 0.14
	local k = 1 + weatherRng:NextNumber(-range, range)
	return Color3.new(
		math.clamp(base.R * k, 0, 1),
		math.clamp(base.G * k, 0, 1),
		math.clamp(base.B * k, 0, 1)
	)
end

export type HidingSpot = {
	part: BasePart,
	kind: string,
	floor: number,
}

export type Manor = {
	model: Model,
	entrance: CFrame, -- drop a player here and they face the front door
	hidingSpots: { HidingSpot },
	partCount: number,
}

--[[
	How much ground the house takes, in its own space: from the back stoop's
	bottom step to the front steps' bottom step, porch return included. A
	caller placing the house can clear this rectangle of trees without knowing
	anything else about the layout.
]]
Manor.FOOTPRINT = {
	x0 = -HALF_W - 2,
	x1 = HALF_W + PORCH_D + 2,
	z0 = -HALF_D - 20,
	z1 = HALF_D + PORCH_D + 13,
}

type Opening = {
	at: number, -- centre along the wall's length axis
	width: number,
	sill: number,
	head: number,
}

type Window = {
	at: number,
	sill: number,
	width: number,
	height: number,
	style: string, -- "intact" | "broken" | "boarded" | "glow" | "open"
}

type Hole = {
	x0: number,
	x1: number,
	z0: number,
	z1: number,
}

type Place = (Vector3) -> CFrame

type Gable = { cx: number, width: number, wall: number }

--[[
	Everything funnels through here so the build can be counted and so no part
	is ever left unanchored — one unanchored wall falls through the floor on the
	first frame and takes a corner of the house down into the terrain with it.
]]
local built = 0

local function newPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
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
	part.Parent = parent

	built += 1
	return part
end

--[[
	Fill the triangle a-b-c with two WedgeParts.

	Roblox has no triangle primitive. The usual construction drops a
	perpendicular from the corner opposite the longest edge, which splits any
	triangle into two right triangles, and a right triangle is exactly a wedge.
	Relabelling so the longest edge is opposite `a` is what guarantees that
	perpendicular lands inside the triangle rather than off one end.

	Every axis comes from the three points, so — unlike rotating a wedge by a
	guessed angle — there is no orientation convention here to get backwards,
	and the result can be checked with arithmetic instead of by looking at it.
]]
local function triangle(
	name: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): { BasePart }
	local made: { BasePart } = {}

	local ab, ac, bc = b - a, c - a, c - b
	local abSq, acSq, bcSq = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)

	if abSq > acSq and abSq > bcSq then
		a, c = c, a
	elseif acSq > abSq and acSq > bcSq then
		a, b = b, a
	end

	ab, ac, bc = b - a, c - a, c - b

	local normal = ac:Cross(ab)
	if normal.Magnitude < EPS then
		-- Degenerate: the three points are in a line, so there is no triangle to
		-- fill. Returning empty beats dividing by zero and spraying NaN CFrames
		-- into the workspace, which is very hard to trace back to here.
		return made
	end

	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local halves: { { edge: Vector3, centre: Vector3, flip: number } } = {
		{ edge = ab, centre = (a + b) / 2, flip = 1 },
		{ edge = ac, centre = (a + c) / 2, flip = -1 },
	}

	for _, half in halves do
		local span = math.abs(half.edge:Dot(back))
		if span > EPS and height > EPS then
			local wedge = Instance.new("WedgePart")
			wedge.Name = name
			wedge.Size = Vector3.new(thickness, height, span)
			wedge.CFrame = CFrame.fromMatrix(half.centre, right * half.flip, up, back * half.flip)
			wedge.Color = color
			wedge.Material = material
			wedge.Anchored = true
			wedge.TopSurface = Enum.SurfaceType.Smooth
			wedge.BottomSurface = Enum.SurfaceType.Smooth
			wedge.Parent = parent

			built += 1
			table.insert(made, wedge)
		end
	end

	return made
end

--[[
	A wall with holes in it.

	Roblox cannot cut an opening in a Part, so a pierced wall is the solid piers
	between the openings, plus an apron under each opening and a header over it.
	This is the most error-prone shape in the build — every door and window in
	the house comes out of here — so it is one function that can be checked once
	rather than the same arithmetic written forty times.

	`axis` is the direction the wall runs and `fixed` is where it sits on the
	other horizontal axis. Openings are given in the wall's own length
	coordinate. Callers pass one vertical band at a time, which is what keeps
	this a one-dimensional problem: two windows stacked above each other are two
	bands, never one call.
]]
local function pierced(
	name: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	bottom: number,
	top: number,
	thickness: number,
	openings: { Opening },
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance,
	outward: number?
)
	local lo = math.min(from, to)
	local hi = math.max(from, to)

	local function slab(a: number, b: number, y0: number, y1: number)
		if b - a <= EPS or y1 - y0 <= EPS then
			return
		end

		local size, centre
		if axis == "X" then
			size = Vector3.new(b - a, y1 - y0, thickness)
			centre = Vector3.new((a + b) / 2, (y0 + y1) / 2, fixed)
		else
			size = Vector3.new(thickness, y1 - y0, b - a)
			centre = Vector3.new(fixed, (y0 + y1) / 2, (a + b) / 2)
		end

		newPart(
			name,
			size,
			place(centre),
			if outward ~= nil then weathered(color) else color,
			material,
			parent
		)

		if outward == nil then
			return
		end

		-- Courses sit on absolute multiples of the spacing, so the lines run
		-- straight across from one wall piece to the next.
		local faceOffset = outward * (thickness / 2 + COURSE_DEPTH / 2)
		local first = math.ceil((y0 + 0.5) / COURSE_SPACING) * COURSE_SPACING
		for y = first, y1 - 0.5, COURSE_SPACING do
			-- One board in sixteen has come away. A run of clapboards with a
			-- gap in it is the cheapest "nobody has been here for years".
			if weatherRng:NextNumber() < 0.06 then
				continue
			end

			local boardSize, boardCentre
			if axis == "X" then
				boardSize = Vector3.new(b - a, COURSE_H, COURSE_DEPTH)
				boardCentre = Vector3.new((a + b) / 2, y, fixed + faceOffset)
			else
				boardSize = Vector3.new(COURSE_DEPTH, COURSE_H, b - a)
				boardCentre = Vector3.new(fixed + faceOffset, y, (a + b) / 2)
			end

			local board = newPart(
				"Clapboard",
				boardSize,
				place(boardCentre),
				weathered(CLAPBOARD, 0.05),
				material,
				parent
			)
			board.CanCollide = false
		end
	end

	local sorted = table.clone(openings)
	table.sort(sorted, function(p: Opening, q: Opening): boolean
		return p.at < q.at
	end)

	local cursor = lo
	for _, hole in sorted do
		local left = hole.at - hole.width / 2
		local right = hole.at + hole.width / 2

		if right <= cursor + EPS or left >= hi - EPS then
			-- Swallowed by an earlier opening, or off the end of the wall. Warn
			-- rather than throw: a mispositioned window should leave a wall
			-- looking wrong, not take the whole server script down with it.
			warn(string.format("[Manor] %s: opening at %.1f falls outside the wall", name, hole.at))
			continue
		end

		left = math.max(left, cursor)
		right = math.min(right, hi)

		slab(cursor, left, bottom, top)
		slab(left, right, bottom, math.min(hole.sill, top))
		slab(left, right, math.max(hole.head, bottom), top)

		cursor = right
	end

	slab(cursor, hi, bottom, top)
end

--[[
	A floor with rectangular voids cut out of it, for stairwells.

	Cut lines are taken from the hole edges and the floor is emitted as the grid
	cells that survive. That is more parts than a hand-cut arrangement of four
	rectangles would be, but it takes any number of holes without a special case
	for each, and every cell is either wholly inside a hole or wholly outside it
	— so there is no partial-overlap case left to get wrong.
]]
local function slabWithHoles(
	name: string,
	y: number,
	thickness: number,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	holes: { Hole },
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance
)
	local function cuts(lo: number, hi: number, extra: { number }): { number }
		local values = { lo, hi }
		for _, v in extra do
			if v > lo + EPS and v < hi - EPS then
				table.insert(values, v)
			end
		end
		table.sort(values)

		local unique: { number } = {}
		for _, v in values do
			if #unique == 0 or v - unique[#unique] > EPS then
				table.insert(unique, v)
			end
		end
		return unique
	end

	local xEdges, zEdges = {}, {}
	for _, hole in holes do
		table.insert(xEdges, hole.x0)
		table.insert(xEdges, hole.x1)
		table.insert(zEdges, hole.z0)
		table.insert(zEdges, hole.z1)
	end

	local xs = cuts(x0, x1, xEdges)
	local zs = cuts(z0, z1, zEdges)

	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			local ax, bx = xs[i], xs[i + 1]
			local az, bz = zs[j], zs[j + 1]
			local cx, cz = (ax + bx) / 2, (az + bz) / 2

			local void = false
			for _, hole in holes do
				if cx > hole.x0 and cx < hole.x1 and cz > hole.z0 and cz < hole.z1 then
					void = true
					break
				end
			end

			if not void then
				newPart(
					name,
					Vector3.new(bx - ax, thickness, bz - az),
					place(Vector3.new(cx, y - thickness / 2, cz)),
					color,
					material,
					parent
				)
			end
		end
	end
end

--[[
	A flight of stairs between two points, plus the invisible ramp that makes it
	walkable.

	The treads are scenery — they do not collide. What the player actually walks
	on is a smooth slab at the flight's own angle hidden inside them. Roblox
	humanoids climb a ramp under MaxSlopeAngle without hesitating, whereas a
	stack of collidable boxes snags: the character catches on tread nosings,
	loses footing at the top and stutters the whole way up. Faking the collision
	is the standard fix and it costs one part.

	Treads are thicker than the rise between them, so consecutive treads overlap
	and the flight has no gaps to see through — no separate risers needed. Both
	axes come from the two endpoints rather than from an angle, so a flight can
	point anywhere without a sign convention to get wrong.
]]
local function staircase(
	name: string,
	bottom: Vector3,
	top: Vector3,
	width: number,
	steps: number,
	place: Place,
	parent: Instance
)
	local delta = top - bottom
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < EPS or steps < 1 then
		warn("[Manor] " .. name .. ": a staircase needs horizontal run and at least one step")
		return
	end

	local run = flat.Magnitude
	local ahead = flat.Unit
	local forward = delta.Unit
	local right = ahead:Cross(Vector3.yAxis).Unit
	local up = right:Cross(forward).Unit

	local treadRun = run / steps
	local treadRise = delta.Y / steps
	local treadT = math.max(1.4, treadRise * 2)

	-- Level basis for the treads: they sit flat, only the flight is inclined.
	local levelRotation = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis, -ahead)

	for i = 1, steps do
		-- The odd tread has rotted through. Only ever a middle one, and the
		-- ramp underneath still carries the player, so it costs nothing but
		-- the look of it.
		if i > 1 and i < steps and weatherRng:NextNumber() < 0.07 then
			continue
		end

		local topY = bottom.Y + treadRise * i
		local mid = bottom + ahead * (treadRun * (i - 0.5))

		local tread = newPart(
			name .. "Tread",
			Vector3.new(width, treadT, treadRun),
			place(Vector3.new(mid.X, topY - treadT / 2, mid.Z)) * levelRotation,
			FLOORBOARD,
			Enum.Material.WoodPlanks,
			parent
		)
		tread.CanCollide = false
	end

	-- Dropped half its thickness along its own normal so the ramp's TOP face
	-- lands exactly on the line between the two endpoints. Centring it there
	-- instead would raise a lip at the foot of the flight.
	local rampT = 1.6
	local slopeRotation = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
	local rampCentre = (bottom + top) / 2 - up * (rampT / 2)

	local ramp = newPart(
		name .. "Ramp",
		Vector3.new(width, rampT, delta.Magnitude + treadRun),
		place(rampCentre) * slopeRotation,
		FLOORBOARD,
		Enum.Material.WoodPlanks,
		parent
	)
	ramp.CanQuery = false

	-- A stringer down each side, hung just outside the treads so the full
	-- width stays walkable. It closes the open edge of the flight and stops a
	-- player walking off it sideways into the stairwell.
	for _, side in { -1, 1 } do
		newPart(
			name .. "Stringer",
			Vector3.new(0.6, 5, delta.Magnitude + treadRun),
			place((bottom + top) / 2 + right * (side * (width / 2 + 0.3)) + Vector3.new(0, 2, 0))
				* slopeRotation,
			TIMBER,
			Enum.Material.Wood,
			parent
		)
	end
end

--[[
	A window: a frame, mullions, and in some the shards of glass still clinging
	to the corners or a cobweb across one. No panes anywhere. Every window in the house is open, so a
	player inside can look out through any of them, and anything outside can
	look in.

	`frame` looks out of the wall, so every piece is placed in that frame's own
	space and the same call works on all four elevations with no per-wall
	special case. Style "open" is the bare cased opening, used for the way
	through into the bay; "door" hangs a door in it.
]]
local function window(
	frame: CFrame,
	width: number,
	height: number,
	style: string,
	thickness: number,
	parent: Instance
)
	local jamb = 0.45
	local d = thickness + 0.3

	local function piece(name: string, size: Vector3, offset: Vector3): Part
		return newPart(name, size, frame * CFrame.new(offset), TRIM, Enum.Material.Wood, parent)
	end

	piece(
		"Sill",
		Vector3.new(width + jamb * 2, jamb, d + 0.6),
		Vector3.new(0, -height / 2 - jamb / 2, 0)
	)
	piece(
		"Lintel",
		Vector3.new(width + jamb * 2, jamb, d + 0.6),
		Vector3.new(0, height / 2 + jamb / 2, 0)
	)
	for _, side in { -1, 1 } do
		piece(
			"Jamb",
			Vector3.new(jamb, height, d),
			Vector3.new(side * (width / 2 + jamb / 2), 0, 0)
		)
	end

	if style == "open" then
		return
	end

	if style == "door" then
		-- A real door, hung on one jamb and swung most of the way open into the
		-- house. A closed door would need a prompt and a swing to be passable;
		-- an open one costs one part and reads as "somebody left in a hurry",
		-- which is the right note anyway.
		local leafW = width - 0.4
		local leaf = newPart(
			"Door",
			Vector3.new(leafW, height - 0.3, 0.4),
			-- The roll is the door hanging off its top hinge: the far edge has
			-- dropped, and the bottom corner has gone into the floor.
			frame
				* CFrame.new(-width / 2 + 0.2, 0, 0)
				* CFrame.Angles(0, math.rad(-105), math.rad(-3))
				* CFrame.new(leafW / 2, 0, 0),
			TIMBER,
			Enum.Material.Wood,
			parent
		)
		leaf.CanCollide = false

		-- A knob is the difference between a door and a plank.
		local knob = newPart(
			"Knob",
			Vector3.new(0.5, 0.5, 0.5),
			leaf.CFrame * CFrame.new(leafW / 2 - 1, 0, -0.35),
			Color3.fromRGB(160, 140, 90),
			Enum.Material.Metal,
			parent
		)
		knob.CanCollide = false
		return
	end

	-- Two thin bars are all it takes for a rectangle to read as a window rather
	-- than as a hole in the wall.
	for _, bar in
		{
			piece("Mullion", Vector3.new(0.3, height, 0.3), Vector3.zero),
			piece("Mullion", Vector3.new(width, 0.3, 0.3), Vector3.zero),
		}
	do
		bar.CanCollide = false
	end

	if style == "cobweb" then
		-- A web across one top corner, just inside the opening. Translucent
		-- and small enough that the view out is still the view out.
		local webs = triangle(
			"Cobweb",
			(frame * CFrame.new(-width / 2 + 0.2, height / 2 - 0.2, 0.3)).Position,
			(frame * CFrame.new(-width / 2 + 0.2 + width * 0.5, height / 2 - 0.2, 0.3)).Position,
			(frame * CFrame.new(-width / 2 + 0.2, height / 2 - 0.2 - height * 0.55, 0.3)).Position,
			0.08,
			WEB,
			Enum.Material.Fabric,
			parent
		)
		for _, web in webs do
			web.Transparency = 0.6
			web.CanCollide = false
			web.CastShadow = false
		end
		return
	end

	if style == "shards" then
		-- Glass left clinging in the corners, built from corner points so the
		-- jagged edge is real geometry rather than a texture. Never enough to
		-- block the view.
		local corners = {
			{
				Vector3.new(-width / 2, height / 2, 0),
				Vector3.new(-width / 2 + width * 0.42, height / 2, 0),
				Vector3.new(-width / 2, height / 2 - height * 0.38, 0),
			},
			{
				Vector3.new(width / 2, height / 2, 0),
				Vector3.new(width / 2 - width * 0.3, height / 2, 0),
				Vector3.new(width / 2, height / 2 - height * 0.5, 0),
			},
			{
				Vector3.new(width / 2, -height / 2, 0),
				Vector3.new(width / 2 - width * 0.35, -height / 2, 0),
				Vector3.new(width / 2, -height / 2 + height * 0.3, 0),
			},
		}

		for _, corner in corners do
			local shards = triangle(
				"Shard",
				(frame * CFrame.new(corner[1])).Position,
				(frame * CFrame.new(corner[2])).Position,
				(frame * CFrame.new(corner[3])).Position,
				0.15,
				Color3.fromRGB(196, 206, 202),
				Enum.Material.Glass,
				parent
			)
			for _, shard in shards do
				shard.CanCollide = false
				shard.Transparency = 0.35
			end
		end
	end
end

--[[
	Turn a window list into the openings the wall needs. Keeping one list and
	deriving the other is what stops a window drifting away from its hole.
]]
local function openingsFor(windows: { Window }): { Opening }
	local openings: { Opening } = {}
	for _, w in windows do
		table.insert(openings, {
			at = w.at,
			width = w.width,
			sill = w.sill,
			head = w.sill + w.height,
		})
	end
	return openings
end

--[[
	Pick a window's condition from a seeded generator.

	Seeded rather than random, so every server builds the same ruin: a player
	who learns which window still has glass in it is right about it on their
	next join, and a screenshot of a bug is reproducible.
]]
local function styleFor(rng: Random): string
	local roll = rng:NextNumber()
	return if roll < 0.35 then "shards" elseif roll < 0.55 then "cobweb" else "window"
end

--[[
	The stone base.

	Courses in slightly different greys rather than one grey block, with a
	scatter of stones left proud of the face. Flat-shaded rubble needs that
	variation or it reads as a painted box, and this is the cheapest place in
	the build to buy texture, because nothing here has to line up with anything.
]]
local function foundation(rng: Random, place: Place, parent: Instance)
	local courses = 5
	local courseH = FOUND_H / courses

	-- The main block and the bay get the same courses, so the stonework reads
	-- as one base that the whole house stands on.
	local footprints: { Hole } = {
		{ x0 = -HALF_W, x1 = HALF_W, z0 = -HALF_D, z1 = HALF_D },
		{ x0 = BAY_X0, x1 = BAY_X1, z0 = HALF_D - 1, z1 = BAY_Z },
	}

	for i = 0, courses - 1 do
		-- The base course is widest, so the house sits on a plinth rather than
		-- balancing on a wall exactly as wide as itself.
		local out = 1.2 * (1 - i / courses) + 0.4
		for _, rect in footprints do
			newPart(
				"Footing",
				Vector3.new(
					rect.x1 - rect.x0 + out * 2,
					courseH + 0.05,
					rect.z1 - rect.z0 + out * 2
				),
				place(
					Vector3.new(
						(rect.x0 + rect.x1) / 2,
						GROUND + courseH * i + courseH / 2,
						(rect.z0 + rect.z1) / 2
					)
				),
				if i % 2 == 0 then STONE else STONE_DARK,
				Enum.Material.Cobblestone,
				parent
			)
		end
	end

	for _ = 1, 90 do
		local edge = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-1, 1)
		local size = rng:NextNumber(1.6, 3.4)
		local y = rng:NextNumber(GROUND + 0.6, -1.2)

		local position
		if edge <= 2 then
			local side = if edge == 1 then 1 else -1
			position = Vector3.new(along * (HALF_W - 1), y, side * (HALF_D + 0.8))
		else
			local side = if edge == 3 then 1 else -1
			position = Vector3.new(side * (HALF_W + 0.8), y, along * (HALF_D - 1))
		end

		local stone = newPart(
			"Rubble",
			Vector3.new(size, size * rng:NextNumber(0.55, 0.9), size * rng:NextNumber(0.7, 1.1)),
			place(position)
				* CFrame.Angles(
					rng:NextNumber(-0.2, 0.2),
					rng:NextNumber(0, math.pi * 2),
					rng:NextNumber(-0.2, 0.2)
				),
			if rng:NextNumber() < 0.5 then STONE else STONE_DARK,
			Enum.Material.Rock,
			parent
		)
		stone.CanCollide = false
	end
end

--[[
	One elevation, from the ground floor up to the top of the attic knee wall.

	Split into five vertical bands — storey, floor band, storey, floor band,
	knee — because `pierced` works along one axis at a time. Two windows stacked
	above one another belong to two bands, never to one call, and that is what
	keeps the wall arithmetic one-dimensional and checkable.
]]
local function elevation(
	label: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	outward: Vector3,
	lower: { Window },
	upper: { Window },
	attic: { Window },
	place: Place,
	parent: Instance
)
	local bands: { { bottom: number, top: number, windows: { Window } } } = {
		{ bottom = L1, top = L1 + STOREY, windows = lower },
		{ bottom = L1 + STOREY, top = L2, windows = {} },
		{ bottom = L2, top = L2 + STOREY, windows = upper },
		{ bottom = L2 + STOREY, top = L3, windows = {} },
		{ bottom = L3, top = KNEE_TOP, windows = attic },
	}

	local sign = if axis == "X" then outward.Z else outward.X

	for _, band in bands do
		pierced(
			"Wall" .. label,
			axis,
			fixed,
			from,
			to,
			band.bottom,
			band.top,
			WALL_T,
			openingsFor(band.windows),
			BOARD,
			Enum.Material.WoodPlanks,
			place,
			parent,
			sign
		)

		for _, w in band.windows do
			local centre = if axis == "X"
				then Vector3.new(w.at, w.sill + w.height / 2, fixed)
				else Vector3.new(fixed, w.sill + w.height / 2, w.at)

			window(
				place(centre) * CFrame.new(Vector3.zero, outward),
				w.width,
				w.height,
				w.style,
				WALL_T,
				parent
			)
		end
	end
end

--[[
	One strip of the main roof, given as the patch of plan it covers.

	Saying which rectangle of floor needs a roof over it — rather than an angle
	and a length — means the pitch, the position and the slab length all fall
	out of the two Z values. That is what lets the slope be cut into strips
	around the dormers without repeating any trigonometry at the call site.
	`z0` and `z1` are distances out from the ridge; `side` picks which slope.
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

	-- Dropped half a thickness along the slope's own normal, so the slab's top
	-- face lands on the rafter line instead of straddling it — which would sit
	-- the whole roof half a thickness proud of the ridge.
	local normal = Vector3.new(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
	local centre = Vector3.new((xFrom + xTo) / 2, midY, side * (z0 + z1) / 2)
		- normal * (ROOF_T / 2)

	newPart(
		"RoofSlope",
		Vector3.new(xTo - xFrom, ROOF_T, length),
		place(centre) * CFrame.Angles(side * ROOF_PITCH, 0, 0),
		weathered(SHINGLE, 0.07),
		Enum.Material.RoofShingles,
		parent
	)
end

--[[
	A wall dormer: the tall cross gable that makes the silhouette.

	Its face is flush with the wall below rather than set back onto the slope,
	which is both what the reference does and much the easier thing to build —
	the face shares a plane with an elevation that already exists, so there is
	no tilted little box perched on a roof to orient.

	Returns how far out from the ridge its own ridge bites into the main slope,
	so the caller knows where to stop the main roof and leave it a hole to sit
	in. Every Z below is a distance out from the ridge; `side` is applied once,
	at the end, so none of this arithmetic has a sign in it.
]]
local function dormer(
	side: number,
	cx: number,
	width: number,
	wallH: number,
	rng: Random,
	place: Place,
	parent: Instance
): number
	local eave = KNEE_TOP + wallH
	local peak = eave + width / 2 -- 45 degrees, matching the reference's steepness
	local stop = (RIDGE - peak) / ROOF_FALL

	local faceZ = side * WALL_Z
	local backZ = stop - 1 -- lap back under the main slope rather than meeting it
	local outZ = HALF_D + EAVE
	local depth = outZ - backZ
	local midZ = side * (backZ + outZ) / 2

	local style = styleFor(rng)
	local winW = math.min(width * 0.42, 9)
	local winH = math.min(wallH - 2.5, 7)
	local winSill = KNEE_TOP + (wallH - winH) / 2

	pierced(
		"DormerFace",
		"X",
		faceZ,
		cx - width / 2,
		cx + width / 2,
		KNEE_TOP,
		eave,
		WALL_T,
		openingsFor({ { at = cx, sill = winSill, width = winW, height = winH, style = style } }),
		BOARD,
		Enum.Material.WoodPlanks,
		place,
		parent,
		side
	)

	window(
		place(Vector3.new(cx, winSill + winH / 2, faceZ))
			* CFrame.new(Vector3.zero, Vector3.new(0, 0, side)),
		winW,
		winH,
		style,
		WALL_T,
		parent
	)

	triangle(
		"DormerGable",
		place(Vector3.new(cx - width / 2, eave, faceZ)).Position,
		place(Vector3.new(cx + width / 2, eave, faceZ)).Position,
		place(Vector3.new(cx, peak, faceZ)).Position,
		WALL_T,
		BOARD,
		Enum.Material.WoodPlanks,
		parent
	)

	-- Cheeks: the dormer's own side walls, sealing between the attic knee wall
	-- and the underside of the dormer roof. Under the main slope for most of
	-- their length, which is fine — that stretch is inside the attic.
	for _, edge in { -1, 1 } do
		newPart(
			"DormerCheek",
			Vector3.new(WALL_T, wallH, depth),
			place(Vector3.new(cx + edge * (width / 2 - WALL_T / 2), KNEE_TOP + wallH / 2, midZ)),
			BOARD,
			Enum.Material.WoodPlanks,
			parent
		)
	end

	-- Two slopes off the dormer ridge at 45 degrees, run long enough to lap over
	-- both the ridge and the main slope's cut edge. A lap is invisible; a gap
	-- lets the sky into the attic.
	local slope = math.rad(45)
	local slabLen = (width / 2) / math.cos(slope) + 2

	for _, edge in { -1, 1 } do
		newPart(
			"DormerRoof",
			Vector3.new(slabLen, ROOF_T, depth + 2),
			place(Vector3.new(cx + edge * width / 4, (peak + eave) / 2 + ROOF_T / 2, midZ))
				* CFrame.Angles(0, 0, -edge * slope),
			SHINGLE,
			Enum.Material.RoofShingles,
			parent
		)
	end

	return stop
end

--[[
	The projecting front bay, three floors of it, with its own cross gable.

	Built from the same pieces as everything else — `elevation` for its three
	outside walls, `slabWithHoles` for its floors, `triangle` for its gable —
	so it inherits the window and doorway machinery rather than repeating it.

	The two cheek triangles are the fiddly part. Where the bay's roof runs back
	into the main slope, the main slope has been cut away for the bay's width,
	which leaves a triangular hole on each side between the bay's eave and the
	main roof surface. Each cheek's hypotenuse is placed on that surface exactly
	— its two ends are the points where the main roof is at eave height and
	where it meets the bay ridge — so the fill is arithmetic rather than a
	guessed rectangle that would poke through the roof on one side or leave
	daylight on the other.
]]
local function frontBay(rng: Random, place: Place, parent: Instance)
	local function sash(at: number, sill: number, width: number, height: number): Window
		return { at = at, sill = sill, width = width, height = height, style = styleFor(rng) }
	end

	-- The bay front is the widest glazing in the house, which is what makes it
	-- read as the good room rather than as a blank tower.
	elevation(
		"BayFront",
		"X",
		BAY_Z - WALL_T / 2,
		BAY_X0,
		BAY_X1,
		Vector3.new(0, 0, 1),
		{ sash(BAY_MID, L1 + 4, 10, 7) },
		{ sash(BAY_MID - 3, L2 + 4, 5, 7), sash(BAY_MID + 4, L2 + 4, 5, 7) },
		{ sash(BAY_MID, L3 + 1, 4, 3) },
		place,
		parent
	)

	for _, side in { -1, 1 } do
		local face = if side < 0 then BAY_X0 + WALL_T / 2 else BAY_X1 - WALL_T / 2
		elevation(
			if side < 0 then "BayLeft" else "BayRight",
			"Z",
			face,
			HALF_D,
			BAY_Z,
			Vector3.new(side, 0, 0),
			{ sash(BAY_Z - 4.5, L1 + 4, 4, 7) },
			{ sash(BAY_Z - 4.5, L2 + 4, 4, 7) },
			{},
			place,
			parent
		)
	end

	for _, y in { L1, L2, L3 } do
		slabWithHoles(
			"BayFloor",
			y,
			SLAB,
			BAY_X0,
			BAY_X1,
			HALF_D,
			BAY_Z,
			{},
			FLOORBOARD,
			Enum.Material.WoodPlanks,
			place,
			parent
		)
	end

	triangle(
		"BayGable",
		place(Vector3.new(BAY_X0, KNEE_TOP, BAY_Z - WALL_T / 2)).Position,
		place(Vector3.new(BAY_X1, KNEE_TOP, BAY_Z - WALL_T / 2)).Position,
		place(Vector3.new(BAY_MID, BAY_PEAK, BAY_Z - WALL_T / 2)).Position,
		WALL_T,
		BOARD,
		Enum.Material.WoodPlanks,
		parent
	)

	local backZ = BAY_STOP - 1 -- lap back under the main slope
	local outZ = BAY_Z + EAVE
	local slope = math.atan2((BAY_W / 2) * BAY_PITCH, BAY_W / 2)
	local slabLen = (BAY_W / 2) / math.cos(slope) + 3

	newPart(
		"BayRidge",
		Vector3.new(2.2, 1.2, outZ - backZ),
		place(Vector3.new(BAY_MID, BAY_PEAK + 0.5, (backZ + outZ) / 2)),
		SHINGLE,
		Enum.Material.RoofShingles,
		parent
	)

	for _, side in { -1, 1 } do
		newPart(
			"BayRoof",
			Vector3.new(slabLen, ROOF_T, outZ - backZ),
			place(
				Vector3.new(
					BAY_MID + side * BAY_W / 4,
					(BAY_PEAK + KNEE_TOP) / 2 + ROOF_T / 2,
					(backZ + outZ) / 2
				)
			) * CFrame.Angles(0, 0, -side * slope),
			SHINGLE,
			Enum.Material.RoofShingles,
			parent
		)

		local face = if side < 0 then BAY_X0 else BAY_X1
		triangle(
			"BayCheek",
			place(Vector3.new(face, KNEE_TOP, ROOF_RUN)).Position,
			place(Vector3.new(face, KNEE_TOP, backZ)).Position,
			place(Vector3.new(face, RIDGE - ROOF_FALL * backZ, backZ)).Position,
			WALL_T,
			BOARD,
			Enum.Material.WoodPlanks,
			parent
		)
	end
end

type Run = { axis: string, fixed: number, from: number, to: number }

--[[
	One run of railing: two rails and the balusters between them.

	Balusters do not collide. Twelve dozen thin collidable posts around a porch
	is a lot of physics geometry for something whose only job is to look like a
	fence, and the rails themselves already stop anyone walking off the edge.
]]
local function railing(name: string, deck: number, run: Run, place: Place, parent: Instance)
	local horizontal = run.axis == "X"
	local length = run.to - run.from
	if length <= EPS then
		return
	end

	local mid = (run.from + run.to) / 2

	for _, height in { 1.1, RAIL_TOP } do
		newPart(
			name .. "Rail",
			if horizontal then Vector3.new(length, 0.35, 0.5) else Vector3.new(0.5, 0.35, length),
			place(
				if horizontal
					then Vector3.new(mid, deck + height, run.fixed)
					else Vector3.new(run.fixed, deck + height, mid)
			),
			TIMBER,
			Enum.Material.Wood,
			parent
		)
	end

	local count = math.max(2, math.floor(length / 3.2))
	for i = 0, count do
		-- A few gone from the middle of each run. The ends stay: a run that has
		-- lost its end baluster reads as unfinished rather than old.
		if i > 0 and i < count and weatherRng:NextNumber() < 0.24 then
			continue
		end

		local t = run.from + (length * i) / count
		local baluster = newPart(
			name .. "Baluster",
			Vector3.new(0.25, RAIL_TOP, 0.25),
			place(
				if horizontal
					then Vector3.new(t, deck + RAIL_TOP / 2, run.fixed)
					else Vector3.new(run.fixed, deck + RAIL_TOP / 2, t)
			),
			TIMBER,
			Enum.Material.Wood,
			parent
		)
		baluster.CanCollide = false
	end
end

--[[
	The porch: one storey, a shed roof, and no more posts than it needs.

	It runs along the front from the bay to the right corner and returns a
	short way down the right side. Nothing sits on top of it — a balcony over
	a porch doubles every post and every rail, and the result reads as a
	scaffold. Six posts carry the roof: one at each end, one either side of
	the steps, one in the middle of the long run, and one at the far end of
	the return.

	Underneath, a continuous stone skirt rather than open stilts. In the
	reference the house sits ON masonry; piers alone leave it on legs with
	daylight under the middle of it, which is the single thing that most stops
	it reading as heavy.
]]
local function verandah(place: Place, parent: Instance)
	local frontRect: Hole = { x0 = PORCH_X0, x1 = PORCH_OUT_X, z0 = HALF_D, z1 = PORCH_OUT_Z }
	local returnRect: Hole = { x0 = HALF_W, x1 = PORCH_OUT_X, z0 = PORCH_RETURN_Z, z1 = HALF_D }

	local function deck(rect: Hole)
		newPart(
			"PorchDeck",
			Vector3.new(rect.x1 - rect.x0, SLAB, rect.z1 - rect.z0),
			place(Vector3.new((rect.x0 + rect.x1) / 2, L1 - SLAB / 2, (rect.z0 + rect.z1) / 2)),
			FLOORBOARD,
			Enum.Material.WoodPlanks,
			parent
		)
	end

	----------------------------------------------------------------------
	-- Stone skirt, with a gap where the front steps come up
	----------------------------------------------------------------------

	local skirtTop = L1 - SLAB

	pierced(
		"Skirt",
		"X",
		PORCH_OUT_Z - 0.75,
		PORCH_X0,
		PORCH_OUT_X,
		GROUND,
		skirtTop,
		1.5,
		{ { at = STEP_CENTRE, width = STEP_HALF * 2, sill = GROUND, head = L1 } },
		STONE,
		Enum.Material.Cobblestone,
		place,
		parent
	)
	pierced(
		"Skirt",
		"Z",
		PORCH_OUT_X - 0.75,
		PORCH_RETURN_Z,
		PORCH_OUT_Z,
		GROUND,
		skirtTop,
		1.5,
		{},
		STONE,
		Enum.Material.Cobblestone,
		place,
		parent
	)
	pierced(
		"Skirt",
		"X",
		PORCH_RETURN_Z + 0.75,
		HALF_W,
		PORCH_OUT_X,
		GROUND,
		skirtTop,
		1.5,
		{},
		STONE,
		Enum.Material.Cobblestone,
		place,
		parent
	)

	----------------------------------------------------------------------
	-- Deck, roof, posts
	----------------------------------------------------------------------

	deck(frontRect)
	deck(returnRect)

	-- The roof leaves the wall a little above the ground-floor ceiling and
	-- falls to the front edge, so it clears the first-floor sills and sheds
	-- rain the way a lean-to should.
	local roofHigh = L2 + 1.5
	local roofLow = L2 - 2
	local roofRun = PORCH_D + 1.5
	local pitch = math.atan2(roofHigh - roofLow, roofRun)
	local roofLen = math.sqrt(roofRun * roofRun + (roofHigh - roofLow) ^ 2)

	-- Underside of the roof at a given distance out from the wall.
	local function roofAt(out: number): number
		return roofHigh - (roofHigh - roofLow) * (out / roofRun) - 0.4
	end

	newPart(
		"PorchRoof",
		Vector3.new(PORCH_OUT_X - PORCH_X0 + 1.5, 0.8, roofLen),
		place(
			Vector3.new(
				(PORCH_X0 + PORCH_OUT_X) / 2 + 0.75,
				(roofHigh + roofLow) / 2,
				HALF_D + roofRun / 2
			)
		) * CFrame.Angles(pitch, 0, 0),
		SHINGLE,
		Enum.Material.RoofShingles,
		parent
	)
	newPart(
		"PorchRoof",
		Vector3.new(roofLen, 0.8, HALF_D - PORCH_RETURN_Z + 1.5),
		place(
			Vector3.new(
				HALF_W + roofRun / 2,
				(roofHigh + roofLow) / 2,
				(PORCH_RETURN_Z + HALF_D) / 2 - 0.75
			)
		) * CFrame.Angles(0, 0, -pitch),
		SHINGLE,
		Enum.Material.RoofShingles,
		parent
	)

	-- Fascia along the two outside edges: the line the eye follows to read the
	-- porch as a roof rather than as a slab.
	newPart(
		"PorchFascia",
		Vector3.new(PORCH_OUT_X - PORCH_X0 + 2.2, 1.2, 0.5),
		place(Vector3.new((PORCH_X0 + PORCH_OUT_X) / 2 + 0.75, roofLow - 0.3, PORCH_OUT_Z + 1.6)),
		TRIM,
		Enum.Material.Wood,
		parent
	)
	newPart(
		"PorchFascia",
		Vector3.new(0.5, 1.2, HALF_D - PORCH_RETURN_Z + 2.2),
		place(Vector3.new(PORCH_OUT_X + 1.6, roofLow - 0.3, (PORCH_RETURN_Z + HALF_D) / 2 - 0.75)),
		TRIM,
		Enum.Material.Wood,
		parent
	)

	local posts: { Vector3 } = {}
	for _, x in
		{
			PORCH_X0 + 1.5,
			0,
			STEP_CENTRE - STEP_HALF - 1,
			STEP_CENTRE + STEP_HALF + 1,
			PORCH_OUT_X - 1.5,
		}
	do
		table.insert(posts, Vector3.new(x, 0, PORCH_OUT_Z - 1.5))
	end
	table.insert(posts, Vector3.new(PORCH_OUT_X - 1.5, 0, PORCH_RETURN_Z + 1.5))

	for _, base in posts do
		local out = math.max(base.Z - HALF_D, base.X - HALF_W)
		local postH = roofAt(out) - L1
		newPart(
			"PorchPost",
			Vector3.new(1.8, postH, 1.8),
			place(Vector3.new(base.X, L1 + postH / 2, base.Z)),
			TIMBER,
			Enum.Material.Wood,
			parent
		)

		-- A pier standing proud of the skirt under each post, so the stonework
		-- reads as something carrying a load rather than as a plinth.
		newPart(
			"Pier",
			Vector3.new(3.2, FOUND_H, 3.2),
			place(Vector3.new(base.X, GROUND + FOUND_H / 2 - SLAB, base.Z)),
			STONE_DARK,
			Enum.Material.Cobblestone,
			parent
		)
	end

	for _, run in
		{
			{
				axis = "X",
				fixed = PORCH_OUT_Z - 0.4,
				from = PORCH_X0,
				to = STEP_CENTRE - STEP_HALF,
			},
			{
				axis = "X",
				fixed = PORCH_OUT_Z - 0.4,
				from = STEP_CENTRE + STEP_HALF,
				to = PORCH_OUT_X,
			},
			{ axis = "Z", fixed = PORCH_OUT_X - 0.4, from = PORCH_RETURN_Z, to = PORCH_OUT_Z },
			{ axis = "X", fixed = PORCH_RETURN_Z + 0.4, from = HALF_W, to = PORCH_OUT_X },
		}
	do
		railing("Porch", L1, run, place, parent)
	end

	staircase(
		"PorchStep",
		Vector3.new(STEP_CENTRE, GROUND, PORCH_OUT_Z + 11),
		Vector3.new(STEP_CENTRE, L1, PORCH_OUT_Z),
		STEP_HALF * 2 - 2,
		8,
		place,
		parent
	)
end

--[[
	Corner boards, fascias and barge boards.

	None of it is structural and all of it is what makes a clapboard house look
	finished: every edge of the building gets a line along it, so the eye reads
	planes meeting instead of one mass. Kept thin. Heavy trim turns a house into
	a diagram of one.

	The fascia gaps come from the same gable lists the roof was cut around, so
	a dormer moved in one place cannot leave its fascia behind in another.
]]
local function trim(front: { Gable }, back: { Gable }, place: Place, parent: Instance)
	local wallH = KNEE_TOP - L1 + 1

	-- Corner boards: the four main corners and the two outer corners of the bay.
	for _, corner in
		{
			Vector3.new(-HALF_W, 0, -HALF_D),
			Vector3.new(HALF_W, 0, -HALF_D),
			Vector3.new(-HALF_W, 0, HALF_D),
			Vector3.new(HALF_W, 0, HALF_D),
			Vector3.new(BAY_X0, 0, BAY_Z),
			Vector3.new(BAY_X1, 0, BAY_Z),
		}
	do
		local inward = Vector3.new(-math.sign(corner.X) * 0.2, 0, -math.sign(corner.Z) * 0.2)
		newPart(
			"CornerBoard",
			Vector3.new(1.0, wallH, 1.0),
			place(corner + inward + Vector3.new(0, (KNEE_TOP + L1) / 2 - 0.5, 0)),
			TRIM,
			Enum.Material.Wood,
			parent
		)
	end

	local edge = HALF_W + EAVE + 0.3

	local function fascia(x0: number, x1: number, side: number)
		if x1 - x0 <= EPS then
			return
		end
		newPart(
			"Fascia",
			Vector3.new(x1 - x0, 1.3, 0.6),
			place(Vector3.new((x0 + x1) / 2, KNEE_TOP - 0.4, side * (ROOF_RUN + 0.3))),
			TRIM,
			Enum.Material.Wood,
			parent
		)
	end

	-- One eave, broken wherever a gable interrupts it.
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

	eave(1, front, { { BAY_X0, BAY_X1 } })
	eave(-1, back, {})

	-- Barge boards down the two main gables. Same trigonometry as the roof
	-- slabs they run beside, so they land on the same line.
	local rakeLen = ROOF_RUN / math.cos(ROOF_PITCH) + 1
	for _, side in { -1, 1 } do
		for _, slope in { -1, 1 } do
			newPart(
				"Rake",
				Vector3.new(0.6, 1.5, rakeLen),
				place(Vector3.new(side * edge, (RIDGE + KNEE_TOP) / 2, slope * ROOF_RUN / 2))
					* CFrame.Angles(slope * ROOF_PITCH, 0, 0),
				TRIM,
				Enum.Material.Wood,
				parent
			)
		end
	end

	-- And down the bay's gable.
	local bayHalf = BAY_W / 2 + 2
	local baySlope = math.atan2(BAY_PITCH * BAY_W / 2, BAY_W / 2)
	local bayRakeLen = bayHalf / math.cos(baySlope)
	local bayLow = BAY_PEAK - bayHalf * BAY_PITCH
	for _, e in { -1, 1 } do
		newPart(
			"BayRake",
			Vector3.new(bayRakeLen, 1.5, 0.6),
			place(
				Vector3.new(BAY_MID + e * bayHalf / 2, (BAY_PEAK + bayLow) / 2, BAY_Z + EAVE + 0.3)
			) * CFrame.Angles(0, 0, -e * baySlope),
			TRIM,
			Enum.Material.Wood,
			parent
		)
	end
end

--[[
	A back stoop, so the kitchen door is a real second exit rather than an
	eight-stud drop onto the grass. A house you can only leave by the front is a
	house with one escape route, which is the opposite of what a chase wants.
]]
local function backStoop(place: Place, parent: Instance)
	local halfW = 11
	local outZ = -HALF_D - 9

	newPart(
		"StoopDeck",
		Vector3.new(halfW * 2, SLAB, 9),
		place(Vector3.new(0, L1 - SLAB / 2, (-HALF_D + outZ) / 2)),
		FLOORBOARD,
		Enum.Material.WoodPlanks,
		parent
	)

	for _, side in { -1, 1 } do
		newPart(
			"StoopPier",
			Vector3.new(3, FOUND_H + 1, 3),
			place(Vector3.new(side * (halfW - 2), GROUND + (FOUND_H + 1) / 2 - SLAB, outZ + 2)),
			STONE,
			Enum.Material.Cobblestone,
			parent
		)
	end

	staircase(
		"StoopStep",
		Vector3.new(0, GROUND, outZ - 10),
		Vector3.new(0, L1, outZ),
		12,
		8,
		place,
		parent
	)
end

--[[
	Cobwebs and the boards that have slipped off the walls.

	All of it is non-collidable and none of it carries the layout, so it can be
	turned down to nothing if part count ever matters. It is also the only thing
	standing between flat brown walls and something that looks deliberately
	derelict rather than merely unfinished.
]]
local function decay(rng: Random, place: Place, parent: Instance)
	-- Slipped boards hanging off the face. Cheap, and the eye reads a broken
	-- line on an otherwise flat wall as damage. Never on the front: there they
	-- would hang in the porch and across the bay, where a board in mid-air
	-- reads as a mistake rather than as decay.
	for _ = 1, 44 do
		local onX = rng:NextNumber() < 0.6
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		if not onX then
			side = -1
		end
		local along = rng:NextNumber(-0.85, 0.85)
		local y = rng:NextNumber(2, KNEE_TOP - 2)
		local length = rng:NextNumber(5, 12)
		local tilt = rng:NextNumber(-0.25, 0.25)

		local position = if onX
			then Vector3.new(side * (HALF_W + 0.3), y, along * (HALF_D - 4))
			else Vector3.new(along * (HALF_W - 4), y, side * (HALF_D + 0.3))

		local board = newPart(
			"LooseBoard",
			if onX then Vector3.new(0.4, 1.4, length) else Vector3.new(length, 1.4, 0.4),
			place(position) * CFrame.Angles(if onX then tilt else 0, 0, if onX then 0 else tilt),
			if rng:NextNumber() < 0.5 then BOARD_DARK else BOARD_PALE,
			Enum.Material.WoodPlanks,
			parent
		)
		board.CanCollide = false
	end

	-- Cobwebs strung across the porch corners, built from their three points so
	-- each one actually spans the corner it is in.
	local corners: { { at: Vector3, inward: number } } = {
		{ at = Vector3.new(PORCH_X0 + 1.5, L1, PORCH_OUT_Z - 1.5), inward = 1 },
		{ at = Vector3.new(PORCH_OUT_X - 1.5, L1, PORCH_OUT_Z - 1.5), inward = -1 },
	}

	for _, corner in corners do
		local top = corner.at + Vector3.new(0, STOREY - 3, 0)
		local reach = rng:NextNumber(6, 11)

		local webs = triangle(
			"Cobweb",
			place(top).Position,
			place(top + Vector3.new(corner.inward * reach, 0, 0)).Position,
			place(top + Vector3.new(0, -reach * 0.8, 0)).Position,
			0.08,
			WEB,
			Enum.Material.Fabric,
			parent
		)

		for _, web in webs do
			web.Transparency = 0.62
			web.CanCollide = false
			web.CastShadow = false
		end
	end
end

--[[
	A cupboard you can stand inside.

	Three sides and a lid with the front left open, sized so a character fits
	with the doors shut behind them. `floorAt` is the floor it stands on rather
	than its middle, because every call site knows which storey it is furnishing
	and none of them want to add half a height to get there.

	Tagged as well as named, so whatever hunts the players can ask
	CollectionService where the hiding places are instead of hard-coding this
	file's layout.
]]
local function wardrobe(
	floorAt: Vector3,
	facing: Vector3,
	size: Vector3,
	floor: number,
	place: Place,
	parent: Instance
): HidingSpot
	local w, h, d = size.X, size.Y, size.Z
	local frame = place(floorAt + Vector3.new(0, h / 2, 0)) * CFrame.new(Vector3.zero, facing)

	local function piece(name: string, pieceSize: Vector3, offset: Vector3, collide: boolean): Part
		local part =
			newPart(name, pieceSize, frame * CFrame.new(offset), TIMBER, Enum.Material.Wood, parent)
		part.CanCollide = collide
		return part
	end

	piece("WardrobeBack", Vector3.new(w, h, 0.6), Vector3.new(0, 0, d / 2), true)
	piece("WardrobeSide", Vector3.new(0.6, h, d), Vector3.new(-w / 2, 0, 0), true)
	piece("WardrobeSide", Vector3.new(0.6, h, d), Vector3.new(w / 2, 0, 0), true)
	piece("WardrobeTop", Vector3.new(w, 0.6, d), Vector3.new(0, h / 2, 0), true)

	-- One door shut, one swung open: the shut half is what makes the gap read
	-- as somewhere to get into rather than as an alcove.
	local shut = piece(
		"WardrobeDoor",
		Vector3.new(w / 2, h - 0.6, 0.4),
		Vector3.new(w / 4, 0, -d / 2),
		false
	)
	shut.Color = BOARD_DARK

	local ajar = newPart(
		"WardrobeDoor",
		Vector3.new(w / 2, h - 0.6, 0.4),
		frame
			* CFrame.new(-w / 2, 0, -d / 2)
			* CFrame.Angles(0, math.rad(70), 0)
			* CFrame.new(w / 4, 0, 0),
		BOARD_DARK,
		Enum.Material.Wood,
		parent
	)
	ajar.CanCollide = false

	local marker = piece("HidingVolume", Vector3.new(w - 1.6, h - 1, d - 1.2), Vector3.zero, false)
	marker.Transparency = 1
	marker.CanQuery = false
	CollectionService:AddTag(marker, "HidingSpot")

	return { part = marker, kind = "wardrobe", floor = floor }
end

--[[
	Build the manor.

	`pivot` is where the ground meets the middle of the footprint, and the house
	faces along the pivot's LookVector — so a caller can point it down a road
	without knowing anything about the layout inside.
]]
function Manor.build(pivot: CFrame, parent: Instance): Manor
	built = 0
	weatherRng = Random.new(8891)

	local model = Instance.new("Model")
	model.Name = "Manor"

	local shell = Instance.new("Folder")
	shell.Name = "Shell"
	shell.Parent = model

	local interior = Instance.new("Folder")
	interior.Name = "Interior"
	interior.Parent = model

	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"
	dressing.Parent = model

	-- The one place the pivot is applied. Everything else is house-local, so no
	-- piece of the layout arithmetic has to know the house can be rotated.
	local function place(offset: Vector3): CFrame
		return pivot * CFrame.new(offset)
	end

	local rng = Random.new(20240617)
	local hidingSpots: { HidingSpot } = {}

	foundation(rng, place, shell)

	----------------------------------------------------------------------------
	-- Floors
	----------------------------------------------------------------------------

	-- Run the floors out under the walls rather than stopping at their inner
	-- face, so there is no one-stud slot at the bottom of every doorway.
	local stairVoid1: Hole = { x0 = -HALL_X, x1 = -4, z0 = STAIR_Z_HIGH - 1, z1 = STAIR_Z_LOW + 1 }
	local stairVoid2: Hole = { x0 = 4, x1 = HALL_X, z0 = STAIR_Z_HIGH - 1, z1 = STAIR_Z_LOW + 1 }

	for _, floor in
		{
			{ name = "GroundFloor", y = L1, holes = {} :: { Hole } },
			{ name = "FirstFloor", y = L2, holes = { stairVoid1 } },
			{ name = "AtticFloor", y = L3, holes = { stairVoid2 } },
		}
	do
		slabWithHoles(
			floor.name,
			floor.y,
			SLAB,
			-HALF_W,
			HALF_W,
			-HALF_D,
			HALF_D,
			floor.holes,
			FLOORBOARD,
			Enum.Material.WoodPlanks,
			place,
			interior
		)
	end

	----------------------------------------------------------------------------
	-- Elevations
	----------------------------------------------------------------------------

	--[[
		Windows are placed by hand, unevenly, and differ between floors and
		between the two sides of the house. A grid of identical sashes is the
		single strongest cue that a building was generated, and it costs nothing
		to not have one — every window is one line either way.
	]]
	local function sash(atPos: number, level: number, width: number?, height: number?): Window
		return {
			at = atPos,
			sill = level + 4,
			width = width or 6,
			height = height or 7,
			style = styleFor(rng),
		}
	end

	local function vent(atPos: number, width: number, height: number): Window
		return { at = atPos, sill = L3 + 1, width = width, height = height, style = styleFor(rng) }
	end

	local function door(atPos: number, level: number): Window
		return { at = atPos, sill = level, width = DOOR_W, height = DOOR_H, style = "door" }
	end

	-- The front wall opens into the bay on every floor, attic included, so the
	-- bay is part of the rooms behind it rather than a cupboard off them.
	local function bayOpening(level: number, height: number): Window
		return { at = BAY_MID, sill = level, width = BAY_W - 6, height = height, style = "open" }
	end

	elevation(
		"Front",
		"X",
		WALL_Z,
		-IN_X,
		IN_X,
		Vector3.new(0, 0, 1),
		{ bayOpening(L1, STOREY), sash(-6, L1, 5), door(4, L1), sash(15, L1), sash(26, L1, 5) },
		{ bayOpening(L2, STOREY), sash(-6, L2, 5), sash(4, L2, 7, 8), sash(15, L2), sash(25, L2) },
		-- Taller than the knee band it is cut from. The wall pieces clamp to the
		-- band anyway; what this moves is the opening's lintel, which at knee
		-- height would hang at exactly head height across the way into the bay.
		{ bayOpening(L3, KNEE + 2.5) },
		place,
		shell
	)
	elevation(
		"Back",
		"X",
		-WALL_Z,
		-IN_X,
		IN_X,
		Vector3.new(0, 0, -1),
		{ door(0, L1), sash(-25, L1, 4), sash(-12, L1), sash(11, L1, 5), sash(23, L1, 7) },
		{ sash(-25, L2, 4), sash(-12, L2), sash(0, L2, 5, 6), sash(12, L2), sash(24, L2) },
		{},
		place,
		shell
	)
	elevation(
		"Left",
		"Z",
		-WALL_X,
		-HALF_D,
		HALF_D,
		Vector3.new(-1, 0, 0),
		{ sash(-15, L1), sash(-4, L1, 5), sash(9, L1), sash(17, L1, 4, 5) },
		{ sash(-14, L2), sash(-2, L2, 5), sash(10, L2, 7, 8), sash(18, L2, 4) },
		{ vent(-9, 5, 3.5) },
		place,
		shell
	)
	elevation(
		"Right",
		"Z",
		WALL_X,
		-HALF_D,
		HALF_D,
		Vector3.new(1, 0, 0),
		{ sash(-16, L1), sash(-6, L1, 5), sash(8, L1), sash(17, L1) },
		{ sash(-15, L2, 5), sash(-3, L2), sash(11, L2, 7), sash(19, L2, 4) },
		{ vent(6, 4, 3), vent(16, 4, 3) },
		place,
		shell
	)

	frontBay(rng, place, shell)

	----------------------------------------------------------------------------
	-- Interior partitions
	----------------------------------------------------------------------------

	local function doorway(atPos: number, level: number): Opening
		return { at = atPos, width = INNER_DOOR_W, sill = level, head = level + INNER_DOOR_H }
	end

	for _, level in { L1, L2 } do
		-- Upstairs the back door moves to z = -21 on both sides: at z = -14 it
		-- would open onto the stairwell rather than onto floor.
		local backDoorZ = if level == L1 then -12 else -18

		for _, x in { -HALL_X, HALL_X } do
			pierced(
				"HallWall",
				"Z",
				x,
				-IN_Z,
				IN_Z,
				level,
				level + STOREY,
				PART_T,
				{ doorway(12, level), doorway(backDoorZ, level) },
				PLASTER,
				Enum.Material.Plaster,
				place,
				interior
			)
		end

		-- The cross walls splitting each side into a front and a back room.
		-- `pierced` sorts its own ends, so the sign of `side` cannot silently
		-- reverse a wall out of existence here.
		for _, side in { -1, 1 } do
			pierced(
				"CrossWall",
				"X",
				0,
				side * HALL_X,
				side * IN_X,
				level,
				level + STOREY,
				PART_T,
				{ doorway(side * 25, level) },
				PLASTER,
				Enum.Material.Plaster,
				place,
				interior
			)
		end
	end

	----------------------------------------------------------------------------
	-- Stairs
	----------------------------------------------------------------------------

	staircase(
		"GrandStair",
		Vector3.new(S1_MID, L1, STAIR_Z_LOW),
		Vector3.new(S1_MID, L2, STAIR_Z_HIGH),
		STAIR_W,
		STAIR_STEPS,
		place,
		interior
	)
	staircase(
		"AtticStair",
		Vector3.new(S2_MID, L2, STAIR_Z_HIGH),
		Vector3.new(S2_MID, L3, STAIR_Z_LOW),
		STAIR_W,
		STAIR_STEPS,
		place,
		interior
	)

	-- A balustrade along the inner edge of each stairwell, so the open hall is a
	-- view rather than a trap. The outer edge is against the hall partition and
	-- needs nothing.
	for _, void in { { hole = stairVoid1, level = L2 }, { hole = stairVoid2, level = L3 } } do
		local inner = if math.abs(void.hole.x0) < math.abs(void.hole.x1)
			then void.hole.x0
			else void.hole.x1

		newPart(
			"Balustrade",
			Vector3.new(0.5, RAIL_TOP, void.hole.z1 - void.hole.z0),
			place(Vector3.new(inner, void.level + RAIL_TOP / 2, (void.hole.z0 + void.hole.z1) / 2)),
			TIMBER,
			Enum.Material.Wood,
			interior
		)
	end

	----------------------------------------------------------------------------
	-- Roof
	----------------------------------------------------------------------------

	--[[
		Two cross gables at the front and two smaller ones at the back, the rear
		pair kept to the right of the chimney stack so nothing has to be built
		through it.

		The front pair are deliberately unequal. A symmetrical front reads as a
		civic building; one gable clearly dominating the other is what makes the
		reference look like a house that was added to over a century. Each
		reports where its ridge bites into the main slope, and the slope is then
		laid as strips stopping exactly short of those bites.
	]]
	-- No dormer over the bay: the bay's own gable is the big one on that side.
	local frontGables: { Gable } = {
		{ cx = -1, width = 10, wall = 5 },
		{ cx = 17, width = 16, wall = 7 },
	}
	local backGables: { Gable } = {
		{ cx = 6, width = 13, wall = 6 },
		{ cx = 22, width = 13, wall = 6 },
	}

	type Cut = { from: number, to: number, stop: number }

	-- Bare patches where the shingles have gone. Only on the full-height strips,
	-- so none can hang over a dormer's cut, and lying flat on the slope with
	-- their underside on its surface.
	local function bare(x0: number, x1: number, side: number)
		if x1 - x0 < 8 then
			return
		end
		for _ = 1, rng:NextInteger(1, 3) do
			local w = rng:NextNumber(2.5, 6)
			local x = rng:NextNumber(x0 + w / 2 + 0.5, x1 - w / 2 - 0.5)
			local out = rng:NextNumber(3, ROOF_RUN - 4)
			local along = rng:NextNumber(2, 4.5)
			local normal = Vector3.new(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
			local patch = newPart(
				"BarePatch",
				Vector3.new(w, 0.12, along),
				place(Vector3.new(x, RIDGE - ROOF_FALL * out, side * out) + normal * 0.06)
					* CFrame.Angles(side * ROOF_PITCH, 0, 0),
				Color3.fromRGB(52, 46, 42),
				Enum.Material.Wood,
				shell
			)
			patch.CanCollide = false
		end
	end

	local function laySlope(side: number, gables: { Gable }, extra: { Cut })
		local cuts: { Cut } = table.clone(extra)
		for _, gable in gables do
			table.insert(cuts, {
				from = gable.cx - gable.width / 2,
				to = gable.cx + gable.width / 2,
				stop = dormer(side, gable.cx, gable.width, gable.wall, rng, place, shell),
			})
		end

		table.sort(cuts, function(p, q): boolean
			return p.from < q.from
		end)

		local cursor = -HALF_W - EAVE
		for _, cut in cuts do
			roofSlab(cursor, cut.from, 0, ROOF_RUN, side, place, shell)
			bare(cursor, cut.from, side)
			-- Under a dormer the slope runs only from the ridge down to where
			-- the dormer ridge meets it, plus a lap so the two overlap rather
			-- than meeting on a line that would show daylight.
			roofSlab(cut.from, cut.to, 0, cut.stop + 2, side, place, shell)
			cursor = cut.to
		end
		roofSlab(cursor, HALF_W + EAVE, 0, ROOF_RUN, side, place, shell)
		bare(cursor, HALF_W + EAVE, side)
	end

	-- The bay is cut out of the front slope exactly as a dormer would be, but
	-- its walls and roof were built by frontBay, so only the cut is passed here.
	laySlope(1, frontGables, { { from = BAY_X0, to = BAY_X1, stop = BAY_STOP } })
	laySlope(-1, backGables, {})

	-- Ridge cap, hiding the seam where the two slopes meet.
	newPart(
		"Ridge",
		Vector3.new(MAIN_W + EAVE * 2, 1.4, 2.4),
		place(Vector3.new(0, RIDGE + 0.4, 0)),
		SHINGLE,
		Enum.Material.RoofShingles,
		shell
	)

	-- Gable ends, closing the attic off at each end of the ridge.
	for _, side in { -1, 1 } do
		triangle(
			"GableEnd",
			place(Vector3.new(side * WALL_X, KNEE_TOP, -HALF_D)).Position,
			place(Vector3.new(side * WALL_X, KNEE_TOP, HALF_D)).Position,
			place(Vector3.new(side * WALL_X, RIDGE, 0)).Position,
			WALL_T,
			BOARD,
			Enum.Material.WoodPlanks,
			shell
		)
	end

	-- The chimney climbs the back wall and past the ridge, so it breaks the roof
	-- line. It sits left of both back dormers and between two windows.
	local stackTop = RIDGE + 8
	newPart(
		"Chimney",
		Vector3.new(7, stackTop - GROUND, 8),
		place(Vector3.new(-19, (stackTop + GROUND) / 2, -HALF_D)),
		Color3.fromRGB(104, 88, 80),
		Enum.Material.Brick,
		shell
	)
	newPart(
		"ChimneyCap",
		Vector3.new(9, 1.2, 10),
		place(Vector3.new(-19, stackTop + 0.6, -HALF_D)),
		STONE_DARK,
		Enum.Material.Slate,
		shell
	)

	----------------------------------------------------------------------------
	-- Porch, balcony and dressing
	----------------------------------------------------------------------------

	verandah(place, shell)
	backStoop(place, shell)
	trim(frontGables, backGables, place, shell)
	decay(rng, place, dressing)

	-- Lanterns on the porch posts: warm, and few, so the green windows stay the
	-- thing the eye goes to.
	for _, spot in
		{
			Vector3.new(STEP_CENTRE - STEP_HALF - 1, L1 + 8, PORCH_OUT_Z - 1.5),
			Vector3.new(STEP_CENTRE + STEP_HALF + 1, L1 + 8, PORCH_OUT_Z - 1.5),
			Vector3.new(9, L1 + 9, HALF_D + 0.9),
		}
	do
		local housing = newPart(
			"Lantern",
			Vector3.new(1.6, 2.4, 1.6),
			place(spot),
			TIMBER,
			Enum.Material.Metal,
			dressing
		)
		housing.CanCollide = false

		local flame = newPart(
			"Flame",
			Vector3.new(0.9, 1.4, 0.9),
			place(spot),
			LANTERN,
			Enum.Material.Neon,
			dressing
		)
		flame.CanCollide = false

		local light = Instance.new("PointLight")
		light.Color = LANTERN
		light.Brightness = 2.2
		light.Range = 26
		light.Parent = flame
	end

	----------------------------------------------------------------------------
	-- Hiding places
	----------------------------------------------------------------------------

	local cupboard = Vector3.new(9, 10, 5)

	-- One wardrobe in each upstairs room, backs to the outer wall.
	for _, corner in
		{
			Vector3.new(-26, L2, -17),
			Vector3.new(26, L2, -17),
			Vector3.new(-26, L2, 17),
			Vector3.new(26, L2, 17),
		}
	do
		local facing = Vector3.new(0, 0, if corner.Z < 0 then 1 else -1)
		table.insert(hidingSpots, wardrobe(corner, facing, cupboard, 2, place, interior))
	end

	-- A pantry in the kitchen and a coat cupboard in the parlour.
	table.insert(
		hidingSpots,
		wardrobe(Vector3.new(-27, L1, -17), Vector3.new(1, 0, 0), cupboard, 1, place, interior)
	)
	table.insert(
		hidingSpots,
		wardrobe(Vector3.new(-27, L1, 18), Vector3.new(0, 0, -1), cupboard, 1, place, interior)
	)

	-- Crates in the attic, at the ends where the roof is highest.
	for index, spot in
		{
			Vector3.new(-24, L3, -12),
			Vector3.new(-22, L3, 10),
			Vector3.new(23, L3, -9),
			Vector3.new(25, L3, 13),
		}
	do
		local size = 7 + (index % 2) * 1.5
		local crate = newPart(
			"Crate",
			Vector3.new(size, size, size),
			place(spot + Vector3.new(0, size / 2, 0))
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			BOARD_DARK,
			Enum.Material.WoodPlanks,
			interior
		)
		CollectionService:AddTag(crate, "HidingSpot")
		table.insert(hidingSpots, { part = crate, kind = "crate", floor = 3 })
	end

	----------------------------------------------------------------------------
	-- Enough furniture that the rooms read as rooms
	----------------------------------------------------------------------------

	local function block(
		name: string,
		size: Vector3,
		floorAt: Vector3,
		color: Color3,
		material: Enum.Material
	)
		newPart(
			name,
			size,
			place(floorAt + Vector3.new(0, size.Y / 2, 0)),
			color,
			material,
			interior
		)
	end

	-- Dining table and benches, front right.
	block(
		"Table",
		Vector3.new(16, 0.8, 6),
		Vector3.new(22, L1 + 3.6, 11),
		FLOORBOARD,
		Enum.Material.Wood
	)
	for _, side in { -1, 1 } do
		block(
			"Bench",
			Vector3.new(14, 0.6, 2.2),
			Vector3.new(22, L1 + 2, 11 + side * 5),
			TIMBER,
			Enum.Material.Wood
		)
		for _, x in { 15, 22, 29 } do
			block(
				"TableLeg",
				Vector3.new(0.9, 3.6, 0.9),
				Vector3.new(x, L1, 11 + side * 2.5),
				TIMBER,
				Enum.Material.Wood
			)
		end
	end

	-- Bookcases along the back wall of the study.
	for _, x in { 15, 22, 29 } do
		block(
			"Bookcase",
			Vector3.new(6, 11, 2.4),
			Vector3.new(x, L1, -20),
			TIMBER,
			Enum.Material.Wood
		)
	end

	-- Kitchen counters down the left wall, clear of the pantry in the corner.
	block(
		"Counter",
		Vector3.new(4, 5, 10),
		Vector3.new(-29, L1, -6),
		BOARD_DARK,
		Enum.Material.Wood
	)
	block("Stove", Vector3.new(5, 6, 6), Vector3.new(-23, L1, -7), STONE_DARK, Enum.Material.Metal)

	-- Beds upstairs, so the rooms are unmistakably bedrooms.
	for _, spot in
		{
			Vector3.new(-21, L2, -8),
			Vector3.new(21, L2, -8),
			Vector3.new(-21, L2, 8),
			Vector3.new(21, L2, 8),
		}
	do
		block("BedFrame", Vector3.new(8, 2.4, 13), spot, TIMBER, Enum.Material.Wood)
		block(
			"Mattress",
			Vector3.new(7.4, 1.6, 12),
			spot + Vector3.new(0, 2.4, 0),
			Color3.fromRGB(132, 126, 112),
			Enum.Material.Fabric
		)
	end

	-- Dust sheets over shapes in the parlour: the cheapest way to suggest
	-- furniture nobody has touched in thirty years.
	for _, spot in { Vector3.new(-18, L1, 7), Vector3.new(-28, L1, 5) } do
		block(
			"DustSheet",
			Vector3.new(8, 6, 6),
			spot,
			Color3.fromRGB(176, 172, 160),
			Enum.Material.Fabric
		)
	end

	----------------------------------------------------------------------------
	-- Interior light, at a level you can only just see by
	----------------------------------------------------------------------------

	for _, spot in
		{
			Vector3.new(0, L1 + STOREY - 2, 0),
			Vector3.new(0, L2 + STOREY - 2, -8),
			Vector3.new(0, L3 + 8, 0),
		}
	do
		local fixture = newPart(
			"Fixture",
			Vector3.new(1.4, 1.4, 1.4),
			place(spot),
			TIMBER,
			Enum.Material.Metal,
			interior
		)
		fixture.CanCollide = false
		fixture.Transparency = 0.2

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(196, 178, 140)
		light.Brightness = 1.1
		light.Range = 40
		light.Parent = fixture
	end

	model.Parent = parent

	print(
		string.format(
			"[Manor] %d parts, %d hiding places, ridge %d studs above ground",
			built,
			#hidingSpots,
			RIDGE - GROUND
		)
	)

	return {
		model = model,
		entrance = pivot
			* CFrame.new(STEP_CENTRE, GROUND, PORCH_OUT_Z + 18)
			* CFrame.Angles(0, math.pi, 0),
		hidingSpots = hidingSpots,
		partCount = built,
	}
end

return Manor
