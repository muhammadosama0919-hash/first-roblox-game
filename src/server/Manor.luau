--!strict
--[[
	A derelict manor, generated entirely in code.

	Self-contained on purpose: this module requires nothing from the rest of the
	project, reads no Config and touches no existing scenery. Drop it in, call
	`Manor.build`, and nothing that already works can be affected by it — and it
	can be deleted again in one keystroke.

	Three floors you can walk: two storeys of rooms plus an open attic, joined
	by a switchback stair through a double-height hall. Every room has at least
	two ways out, so a chase loops instead of dead-ending, and there are
	built-in cupboards to hide in.

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
	2.6 studs. Flat-shaded Roblox walls read as painted card whatever material
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

-- The porch posts along the front, by X. The pair flanking the steps is what
-- the lanterns hang from, so the list lives here rather than in the porch.
local PORCH_POST_XS = {
	PORCH_X0 + 1.5,
	0,
	STEP_CENTRE - STEP_HALF - 1,
	STEP_CENTRE + STEP_HALF + 1,
	PORCH_OUT_X - 1.5,
}
local STEP_POST_XS = { PORCH_POST_XS[3], PORCH_POST_XS[4] }

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
local FRONT_DOOR_X = 4 -- in the hall, right of the bay
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
local PANEL = Color3.fromRGB(148, 138, 120) -- boarded interior walls, old whitewash
local LANTERN = Color3.fromRGB(255, 176, 88)

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
	style: string, -- "window" | "open" | "door"
	hinge: number?, -- doors only: which jamb the leaf hangs on, -1 left, 1 right, looking out
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
	outward: number?,
	skirtInset: number?
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

		-- Skirting along the foot of every wall that stands on a floor, on the
		-- room side of it. It is the one line that makes a plain wall read as
		-- the inside of a room rather than the inside of a box. Doorways break
		-- it for free, because the wall pieces already stop at them.
		local onFloor = math.abs(y0 - L1) < EPS
			or math.abs(y0 - L2) < EPS
			or math.abs(y0 - L3) < EPS
		-- A wall that runs on through the walls it meets — the side walls run
		-- the full depth, through the front and back — carries no skirting
		-- inside them: `skirtInset` pulls it in from the run's ends, or the
		-- board would come out through the far face as a wooden nub.
		local inset = skirtInset or 0
		local sa = math.max(a, lo + inset)
		local sb = math.min(b, hi - inset)
		if onFloor and sb - sa > 1 then
			local faces: { number } = {}
			if outward ~= nil then
				table.insert(faces, -outward)
			else
				table.insert(faces, -1)
				table.insert(faces, 1)
			end

			-- Where two walls meet, their skirtings run into each other. Boards
			-- along Z are a shade lower than boards along X, so the two never
			-- share a top face where they cross.
			local skirtH = if axis == "X" then 1 else 0.96
			for _, face in faces do
				local off = face * (thickness / 2 + 0.12)
				local skirt = newPart(
					"Skirting",
					if axis == "X"
						then Vector3.new(sb - sa, skirtH, 0.24)
						else Vector3.new(0.24, skirtH, sb - sa),
					place(
						if axis == "X"
							then Vector3.new((sa + sb) / 2, y0 + skirtH / 2, fixed + off)
							else Vector3.new(fixed + off, y0 + skirtH / 2, (sa + sb) / 2)
					),
					TIMBER,
					Enum.Material.Wood,
					parent
				)
				skirt.CanCollide = false
			end
		end

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
	A flight of stairs between two points, with a handrail down each side and
	the invisible ramp that makes it walkable.

	The treads are scenery — they do not collide. What the player actually walks
	on is a smooth slab at the flight's own angle hidden inside them. Roblox
	humanoids climb a ramp under MaxSlopeAngle without hesitating, whereas a
	stack of collidable boxes snags: the character catches on tread nosings,
	loses footing at the top and stutters the whole way up. Faking the collision
	is the standard fix and it costs one part.

	Treads are thicker than the rise between them, so consecutive treads overlap
	and the flight has no gaps to see through. A low string board down each
	side hides the sawtooth of their ends; above it a newel post at each end
	carries a handrail at hand height, with balusters under it. The rail is
	what keeps a player on the flight. A solid panel did the same job and
	looked like a wall.

	Both axes come from the two endpoints rather than from an angle, so a flight
	can point anywhere without a sign convention to get wrong.
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
	local treadT = math.max(1.0, treadRise * 1.3)

	-- Level basis for the treads and posts, which sit plumb; slope basis for
	-- everything that runs with the flight.
	local levelRotation = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis, -ahead)
	local slopeRotation = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
	local mid = (bottom + top) / 2

	for i = 1, steps do
		-- The odd tread has rotted through. Only ever a middle one, and the
		-- ramp underneath still carries the player, so it costs nothing but
		-- the look of it.
		if i > 1 and i < steps and weatherRng:NextNumber() < 0.07 then
			continue
		end

		local topY = bottom.Y + treadRise * i
		local centre = bottom + ahead * (treadRun * (i - 0.5))

		local tread = newPart(
			name .. "Tread",
			Vector3.new(width, treadT, treadRun),
			place(Vector3.new(centre.X, topY - treadT / 2, centre.Z)) * levelRotation,
			FLOORBOARD,
			Enum.Material.WoodPlanks,
			parent
		)
		tread.CanCollide = false
	end

	--[[
		The ramp's top face is the line through the tread backs: the one
		straight line that meets the floor at the first tread's front edge and
		the landing at the last tread's back with no lip at either end, and
		stays inside the treads the whole way, so it never shows. A foot on it
		sinks into each nosing by up to one rise, which is far less visible
		than a slab standing proud of the steps was. Thin enough that its
		underside stays inside the string boards too; collision does not care.
	]]
	local rampT = 0.85
	newPart(
		name .. "Ramp",
		Vector3.new(width, rampT, delta.Magnitude),
		place(mid - up * (rampT / 2)) * slopeRotation,
		FLOORBOARD,
		Enum.Material.WoodPlanks,
		parent
	)

	local railH = 3.6
	local balusters = math.max(2, math.floor(run / 2.2))

	for _, side in { -1, 1 } do
		local edge = right * (side * (width / 2 + 0.3))

		-- String board: hides the tread ends, and is the line the eye reads
		-- the flight by.
		newPart(
			name .. "String",
			Vector3.new(0.4, 1.2, delta.Magnitude + treadRun),
			place(mid + edge - up * 0.3) * slopeRotation,
			TIMBER,
			Enum.Material.Wood,
			parent
		)

		-- Newel posts, footed most of a stud into whatever the flight stands on
		-- — not a whole one, or the post's underside would lie on the ceiling
		-- of the room below and flicker there.
		local postH = railH + 1.6
		for _, post in { { at = bottom, back = -0.4 }, { at = top, back = 0.4 } } do
			newPart(
				name .. "Newel",
				Vector3.new(0.8, postH, 0.8),
				place(post.at + edge + ahead * post.back + Vector3.new(0, postH / 2 - 0.9, 0))
					* levelRotation,
				TIMBER,
				Enum.Material.Wood,
				parent
			)
		end

		-- The rail, parallel to the flight at hand height, run into the posts.
		newPart(
			name .. "Rail",
			Vector3.new(0.5, 0.4, delta.Magnitude + 0.8),
			place(mid + edge + Vector3.new(0, railH, 0)) * slopeRotation,
			TIMBER,
			Enum.Material.Wood,
			parent
		)

		for k = 1, balusters - 1 do
			-- A few gone, as on the porch: same house, same neglect.
			if weatherRng:NextNumber() < 0.15 then
				continue
			end

			local foot = bottom + delta * (k / balusters)
			local baluster = newPart(
				name .. "Baluster",
				Vector3.new(0.25, railH, 0.25),
				place(foot + edge + Vector3.new(0, railH / 2, 0)) * levelRotation,
				TIMBER,
				Enum.Material.Wood,
				parent
			)
			baluster.CanCollide = false
		end
	end
end

--[[
	A window: a cased frame with two mullions and nothing in it. Every window
	in the house is open, so a player inside can look out through any of them,
	and anything outside can look in.

	`frame` looks out of the wall, so every piece is placed in that frame's own
	space and the same call works on all four elevations with no per-wall
	special case. Style "open" is the bare cased opening, used for doorways
	and the way through into the bay; "door" hangs a door in it. Neither gets a
	sill: a sill at floor level is a lip to trip on, and at doorways the floor
	is the threshold.
]]
local function window(
	frame: CFrame,
	width: number,
	height: number,
	style: string,
	thickness: number,
	parent: Instance,
	hinge: number?
)
	local jamb = 0.45
	local d = thickness + 0.3

	-- The frame sits in the wall's end faces around the opening, and a face
	-- that shares a plane with another flickers in the engine. Each piece is
	-- nudged a hair into the opening, so its inner face stands proud of the
	-- wall's edge it covers instead of lying on it.
	local nudge = 0.02

	local function piece(name: string, size: Vector3, offset: Vector3): Part
		return newPart(name, size, frame * CFrame.new(offset), TRIM, Enum.Material.Wood, parent)
	end

	if style == "window" then
		piece(
			"Sill",
			Vector3.new(width + jamb * 2, jamb, d + 0.6),
			Vector3.new(0, -height / 2 - jamb / 2 + nudge, 0)
		)
	end
	piece(
		"Lintel",
		Vector3.new(width + jamb * 2, jamb, d + 0.6),
		Vector3.new(0, height / 2 + jamb / 2 - nudge, 0)
	)
	for _, side in { -1, 1 } do
		piece(
			"Jamb",
			Vector3.new(jamb, height, d),
			Vector3.new(side * (width / 2 + jamb / 2 - nudge), 0, 0)
		)
	end

	if style == "open" then
		return
	end

	if style == "door" then
		-- A real door, hung on one jamb and swung most of the way open into the
		-- house. A closed door would need a prompt and a swing to be passable;
		-- an open one costs one part and reads as "somebody left in a hurry",
		-- which is the right note anyway. The roll is the door hanging off its
		-- top hinge: the far edge has dropped, and the bottom corner has gone
		-- into the floor.
		-- `hinge` picks the jamb, so a door can swing toward whichever side of
		-- the room is clear: the back door opens away from the cupboard under
		-- the stair. Every sign below follows from it, including the roll,
		-- which has to drop the far edge whichever way the leaf faces.
		local h = hinge or -1
		local leafW = width - 0.4
		local leaf = newPart(
			"Door",
			Vector3.new(leafW, height - 0.3, 0.4),
			frame
				* CFrame.new(h * (width / 2 - 0.2), 0, 0)
				* CFrame.Angles(0, h * math.rad(105), h * math.rad(3))
				* CFrame.new(-h * leafW / 2, 0, 0),
			TIMBER,
			Enum.Material.Wood,
			parent
		)
		leaf.CanCollide = false

		-- A knob is the difference between a door and a plank.
		local knob = newPart(
			"Knob",
			Vector3.new(0.5, 0.5, 0.5),
			leaf.CFrame * CFrame.new(-h * (leafW / 2 - 1), 0, -0.35),
			Color3.fromRGB(160, 140, 90),
			Enum.Material.Metal,
			parent
		)
		knob.CanCollide = false
		return
	end

	-- Two thin bars are all it takes for a rectangle to read as a window rather
	-- than as a hole in the wall.
	-- The crossbar is a shade thinner than the upright, so where they cross no
	-- two faces share a plane.
	for _, bar in
		{
			piece("Mullion", Vector3.new(0.3, height, 0.3), Vector3.zero),
			piece("Mullion", Vector3.new(width, 0.28, 0.28), Vector3.zero),
		}
	do
		bar.CanCollide = false
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
		-- Courses lap a little so no seam opens between them, and the top one
		-- stops inside the ground-floor slab: a footing that tops out even a
		-- hair above the floor turns the whole ground floor to stone.
		local bottom = GROUND + courseH * i - 0.05
		local top = math.min(GROUND + courseH * (i + 1), L1 - 0.3)
		for _, rect in footprints do
			newPart(
				"Footing",
				Vector3.new(rect.x1 - rect.x0 + out * 2, top - bottom, rect.z1 - rect.z0 + out * 2),
				place(
					Vector3.new(
						(rect.x0 + rect.x1) / 2,
						(top + bottom) / 2,
						(rect.z0 + rect.z1) / 2
					)
				),
				if i % 2 == 0 then STONE else STONE_DARK,
				Enum.Material.Cobblestone,
				parent
			)
		end
	end

	-- A few stones fallen out of the base and lying at its foot, never at the
	-- front where the porch and bay are. Not many: a ring of loose blocks
	-- round a house reads as rubble in the way of the door, not as age.
	for _ = 1, 22 do
		local edge = rng:NextInteger(2, 4)
		local along = rng:NextNumber(-1, 1)
		local size = rng:NextNumber(1.0, 2.0)
		local out = 1.4 + rng:NextNumber(0, 2.2)

		local position
		if edge == 2 then
			position = Vector3.new(along * (HALF_W - 2), GROUND + size * 0.3, -(HALF_D + out))
		else
			local side = if edge == 3 then 1 else -1
			position = Vector3.new(side * (HALF_W + out), GROUND + size * 0.3, along * (HALF_D - 2))
		end

		local stone = newPart(
			"Rubble",
			Vector3.new(size, size * rng:NextNumber(0.5, 0.75), size * rng:NextNumber(0.7, 1.1)),
			place(position)
				* CFrame.Angles(
					rng:NextNumber(-0.15, 0.15),
					rng:NextNumber(0, math.pi * 2),
					rng:NextNumber(-0.15, 0.15)
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
	parent: Instance,
	skirtInset: number?
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
			sign,
			skirtInset
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
				parent,
				w.hinge
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
	in, and how far out the valley between the two roofs reaches the cut's
	edge, so the caller can carry the main roof out to it. Every Z below is a distance out from the ridge; `side` is applied once,
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
): (number, number)
	local eave = KNEE_TOP + wallH
	local peak = eave + width / 2 -- 45 degrees, matching the reference's steepness
	local stop = (RIDGE - peak) / ROOF_FALL

	local faceZ = side * WALL_Z
	local backZ = stop - 1 -- lap back under the main slope rather than meeting it
	local outZ = HALF_D + EAVE
	local depth = outZ - backZ
	local midZ = side * (backZ + outZ) / 2
	-- The cheeks stop at the back of the face, which runs the full width past
	-- them: only the roof runs on to the eave line. Run to the face's front,
	-- cheek and face would share the corner's outer plane and flicker.
	local cheekDepth = HALF_D - WALL_T - backZ
	local cheekMidZ = side * (backZ + HALF_D - WALL_T) / 2

	local style = "window"
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
			Vector3.new(WALL_T, wallH, cheekDepth),
			place(
				Vector3.new(cx + edge * (width / 2 - WALL_T / 2), KNEE_TOP + wallH / 2, cheekMidZ)
			),
			BOARD,
			Enum.Material.WoodPlanks,
			parent
		)
	end

	-- Two slopes off the dormer ridge at 45 degrees. Each is two studs longer
	-- than its run and shifted down its own slope by one, so its top end lands
	-- exactly on the ridge and the extra hangs at the eave. A lap over the main
	-- slope's cut edge is invisible; a gap lets the sky into the attic.
	local slope = math.rad(45)
	local slabLen = (width / 2) / math.cos(slope) + 2

	for _, edge in { -1, 1 } do
		newPart(
			"DormerRoof",
			Vector3.new(slabLen, ROOF_T, depth + 2),
			place(
				Vector3.new(
					cx + edge * (width / 4 + math.cos(slope)),
					(peak + eave) / 2 + ROOF_T / 2 - math.sin(slope),
					midZ
				)
			) * CFrame.Angles(0, 0, -edge * slope),
			SHINGLE,
			Enum.Material.RoofShingles,
			parent
		)
	end

	return stop, (RIDGE - eave) / ROOF_FALL
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
		return { at = at, sill = sill, width = width, height = height, style = "window" }
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
		parent,
		WALL_T -- runs through both cheeks; no skirting inside them
	)

	for _, side in { -1, 1 } do
		local face = if side < 0 then BAY_X0 + WALL_T / 2 else BAY_X1 - WALL_T / 2
		elevation(
			if side < 0 then "BayLeft" else "BayRight",
			"Z",
			face,
			HALF_D,
			-- To the back of the front wall, not its face: run to the corner,
			-- the two walls would share the corner's faces and flicker there.
			BAY_Z - WALL_T,
			Vector3.new(side, 0, 0),
			{ sash(BAY_Z - 4.5, L1 + 4, 4, 7) },
			{ sash(BAY_Z - 4.5, L2 + 4, 4, 7) },
			{},
			place,
			parent
		)
	end

	for _, y in { L1, L2, L3 } do
		-- Pulled inside the bay walls above the ground floor, as the main slabs
		-- are, and starting where the main slab ends on that floor.
		local out = if y == L1 then 0 else -WALL_T / 2
		slabWithHoles(
			"BayFloor",
			y,
			SLAB,
			BAY_X0 - out,
			BAY_X1 + out,
			HALF_D + out,
			BAY_Z + out,
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
		place(Vector3.new(BAY_MID, BAY_PEAK + 1.0, (backZ + outZ) / 2)),
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
					BAY_MID + side * (BAY_W / 4 + 1.5 * math.cos(slope)),
					(BAY_PEAK + KNEE_TOP) / 2 + ROOF_T / 2 - 1.5 * math.sin(slope),
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

	-- Runs along Z are a shade slimmer than runs along X, so where two meet
	-- at a corner the one sits inside the other instead of sharing its faces.
	for _, height in { 1.1, RAIL_TOP } do
		newPart(
			name .. "Rail",
			if horizontal then Vector3.new(length, 0.35, 0.5) else Vector3.new(0.5, 0.33, length),
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
	-- The decks start at the walls' outer face, where the ground-floor slab
	-- ends: overlapping it, their tops would share its plane and flicker.
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

	-- Where the front roof meets the return, the return has already fallen
	-- while the front's back edge is still at the wall. A triangle in the
	-- plane of that edge closes the notch, from its three corners.
	triangle(
		"PorchHip",
		place(Vector3.new(HALF_W, roofHigh, HALF_D)).Position,
		place(Vector3.new(HALF_W + roofRun, roofHigh, HALF_D)).Position,
		place(Vector3.new(HALF_W + roofRun, roofLow, HALF_D)).Position,
		0.8,
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
	for _, x in PORCH_POST_XS do
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
				-- Dropped half its height along the roof's normal so its top edge
				-- is flush with the shingles rather than standing above them.
				place(
					Vector3.new(side * edge, (RIDGE + KNEE_TOP) / 2, slope * ROOF_RUN / 2)
						- Vector3.new(0, math.cos(ROOF_PITCH), slope * math.sin(ROOF_PITCH))
							* 0.75
				) * CFrame.Angles(slope * ROOF_PITCH, 0, 0),
				TRIM,
				Enum.Material.Wood,
				parent
			)
		end
	end

	-- And down the bay's gable.
	-- The bay roof slabs reach three studs down their slope past the bay's
	-- sides; the rake stops a shade short of that, or its end hangs in the
	-- air past the eave.
	local baySlope = math.atan2(BAY_PITCH * BAY_W / 2, BAY_W / 2)
	local bayHalf = BAY_W / 2 + 3 * math.cos(baySlope) - 0.2
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

	-- From the wall's outer face, where the ground-floor slab ends, for the
	-- same reason the porch decks do.
	local inZ = -HALF_D
	newPart(
		"StoopDeck",
		Vector3.new(halfW * 2, SLAB, inZ - outZ),
		place(Vector3.new(0, L1 - SLAB / 2, (inZ + outZ) / 2)),
		FLOORBOARD,
		Enum.Material.WoodPlanks,
		parent
	)

	for _, side in { -1, 1 } do
		newPart(
			"StoopPier",
			Vector3.new(3, FOUND_H, 3),
			place(Vector3.new(side * (halfW - 2), GROUND + FOUND_H / 2 - SLAB, outZ + 2)),
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
	The boards that have slipped off the walls.

	Non-collidable, and none of it carries the layout, so it can be turned down
	to nothing if part count ever matters. Only a few: a wall bristling with
	planks reads as a pile of parts, not as age. Never on the front, where they
	would hang in the porch and across the bay.
]]
local function decay(rng: Random, place: Place, parent: Instance)
	for _ = 1, 14 do
		local onX = rng:NextNumber() < 0.6
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		if not onX then
			side = -1
		end
		local along = rng:NextNumber(-0.85, 0.85)
		local y = rng:NextNumber(2, KNEE_TOP - 2)
		local length = rng:NextNumber(4, 9)
		local tilt = rng:NextNumber(-0.12, 0.12)

		local position = if onX
			then Vector3.new(side * (HALF_W + 0.3), y, along * (HALF_D - 4))
			else Vector3.new(along * (HALF_W - 4), y, side * (HALF_D + 0.3))

		local board = newPart(
			"LooseBoard",
			if onX then Vector3.new(0.4, 1.2, length) else Vector3.new(length, 1.2, 0.4),
			place(position) * CFrame.Angles(if onX then tilt else 0, 0, if onX then 0 else tilt),
			if rng:NextNumber() < 0.5 then BOARD_DARK else BOARD_PALE,
			Enum.Material.WoodPlanks,
			parent
		)
		board.CanCollide = false
	end
end

type CupboardWall = { axis: string, fixed: number, from: number, to: number, door: number? }

--[[
	A built-in cupboard: the walls that close off a corner of a room or the
	space under a flight, a doorway in one of them, and an invisible tagged
	volume inside for whatever hunts the players to find.

	Walls rather than a box, because a box standing in a room is furniture and
	a cupboard is a room. The doorway is narrow and dark on purpose — it should
	read as somewhere to get into, not as another way through.
]]
local function cupboard(
	name: string,
	level: number,
	height: number,
	walls: { CupboardWall },
	inside: Vector3,
	insideSize: Vector3,
	floor: number,
	place: Place,
	parent: Instance
): HidingSpot
	local doorW = 3.5
	local doorH = math.min(height - 0.5, 9)

	for _, wall in walls do
		local openings: { Opening } = {}
		if wall.door then
			table.insert(
				openings,
				{ at = wall.door, width = doorW, sill = level, head = level + doorH }
			)
		end

		pierced(
			name .. "Wall",
			wall.axis,
			wall.fixed,
			wall.from,
			wall.to,
			level,
			level + height,
			PART_T,
			openings,
			PANEL,
			Enum.Material.WoodPlanks,
			place,
			parent
		)

		if wall.door then
			local centre = if wall.axis == "Z"
				then Vector3.new(wall.fixed, level + doorH / 2, wall.door)
				else Vector3.new(wall.door, level + doorH / 2, wall.fixed)
			local outward = if wall.axis == "Z" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
			window(
				place(centre) * CFrame.new(Vector3.zero, outward),
				doorW,
				doorH,
				"open",
				PART_T,
				parent
			)
		end
	end

	local marker = newPart(
		name .. "HidingVolume",
		insideSize,
		place(inside + Vector3.new(0, insideSize.Y / 2, 0)),
		TIMBER,
		Enum.Material.Plastic,
		parent
	)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	CollectionService:AddTag(marker, "HidingSpot")

	return { part = marker, kind = "cupboard", floor = floor }
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

	--[[
		The one place the pivot is applied. Everything else is house-local, so no
		piece of the layout arithmetic has to know the house can be rotated.

		Two things are folded in here so the pivot means what a caller expects.
		The pivot sits on the ground, so the house's own ground line — GROUND,
		FOUND_H below its floor — is lifted onto it. And the pivot's LookVector
		is the way the house faces, while house-local +Z is the front, so the
		local frame is turned half a turn. The walkability check and the model
		export both build against a pivot chosen to undo exactly this.
	]]
	local function place(offset: Vector3): CFrame
		return pivot
			* CFrame.Angles(0, math.pi, 0)
			* CFrame.new(offset + Vector3.new(0, FOUND_H, 0))
	end

	local rng = Random.new(20240617)
	local hidingSpots: { HidingSpot } = {}

	foundation(rng, place, shell)

	----------------------------------------------------------------------------
	-- Floors
	----------------------------------------------------------------------------

	-- Run the floors out under the walls rather than stopping at their inner
	-- face, so there is no one-stud slot at the bottom of every doorway.
	-- Each void ends exactly where its flight lands, so the landing's edge is
	-- the last tread's back and the top newel stands in the slab. It runs a
	-- stud past the foot, for the headroom.
	local stairVoid1: Hole = { x0 = -HALL_X, x1 = -4, z0 = STAIR_Z_HIGH, z1 = STAIR_Z_LOW + 1 }
	local stairVoid2: Hole = { x0 = 4, x1 = HALL_X, z0 = STAIR_Z_HIGH - 1, z1 = STAIR_Z_LOW }

	-- The walls stand with their outer face on the footprint line. The ground
	-- floor runs out to that face, so the band between the footing's top and
	-- the wall's foot shows its edge rather than a slot. The upper slabs stop
	-- inside the wall: carried to the face, their edges would share a plane
	-- with it and flicker.
	for _, floor in
		{
			{ name = "GroundFloor", y = L1, holes = {} :: { Hole }, out = 0 },
			{ name = "FirstFloor", y = L2, holes = { stairVoid1 }, out = -WALL_T / 2 },
			{ name = "AtticFloor", y = L3, holes = { stairVoid2 }, out = -WALL_T / 2 },
		}
	do
		slabWithHoles(
			floor.name,
			floor.y,
			SLAB,
			-HALF_W - floor.out,
			HALF_W + floor.out,
			-HALF_D - floor.out,
			HALF_D + floor.out,
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

		Each one is also placed against the plan: at least a stud and a half
		clear of every hall wall, cross wall, cupboard wall and the chimney
		breast, so no wall inside meets the outside wall through a window. The
		pantry and the closets have none, as the real ones do not.
	]]
	local function sash(atPos: number, level: number, width: number?, height: number?): Window
		return {
			at = atPos,
			sill = level + 4,
			width = width or 6,
			height = height or 7,
			style = "window",
		}
	end

	local function vent(atPos: number, width: number, height: number): Window
		return { at = atPos, sill = L3 + 1, width = width, height = height, style = "window" }
	end

	local function door(atPos: number, level: number, hinge: number?): Window
		return {
			at = atPos,
			sill = level,
			width = DOOR_W,
			height = DOOR_H,
			style = "door",
			hinge = hinge,
		}
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
		{
			bayOpening(L1, STOREY),
			sash(-6, L1, 5),
			door(FRONT_DOOR_X, L1),
			sash(18, L1),
			sash(26, L1, 5),
		},
		{
			bayOpening(L2, STOREY),
			sash(-6, L2, 5),
			sash(4, L2, 7, 8),
			sash(18, L2),
			sash(26, L2, 5),
		},
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
		{ door(0, L1, 1), sash(-8, L1, 4), sash(8, L1, 4), sash(18, L1), sash(27, L1, 4) },
		{ sash(-8, L2, 4), sash(0, L2, 5, 6), sash(8, L2, 4), sash(18, L2) },
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
		{ sash(-13, L1), sash(-5, L1, 5), sash(8, L1), sash(17, L1, 4, 5) },
		{ sash(-12, L2), sash(-5, L2, 5), sash(8, L2, 7, 8), sash(17, L2, 4) },
		{ vent(-9, 5, 3.5) },
		place,
		shell,
		WALL_T -- runs through the front and back walls; no skirting inside them
	)
	elevation(
		"Right",
		"Z",
		WALL_X,
		-HALF_D,
		HALF_D,
		Vector3.new(1, 0, 0),
		{ sash(-16, L1), sash(-6, L1, 5), sash(8, L1), sash(17, L1) },
		{ sash(-13, L2, 5), sash(-5, L2, 5), sash(11, L2, 7), sash(19, L2, 4) },
		{ vent(6, 4, 3), vent(16, 4, 3) },
		place,
		shell,
		WALL_T
	)

	frontBay(rng, place, shell)

	----------------------------------------------------------------------------
	-- Interior partitions
	----------------------------------------------------------------------------

	local function doorway(atPos: number, level: number): Opening
		return { at = atPos, width = INNER_DOOR_W, sill = level, head = level + INNER_DOOR_H }
	end

	--[[
		Where the doors in the hall walls go, per floor and per side. Downstairs
		the kitchen door sits forward, clear of the cupboard under the stair;
		upstairs the right-hand front door sits back, clear of the cupboard
		under the attic stair. Every interior doorway gets a cased frame.
	]]
	local hallDoors: { [number]: { [number]: { number } } } = {
		[L1] = { [-HALL_X] = { 12, -5 }, [HALL_X] = { 12, -12 } },
		[L2] = { [-HALL_X] = { 12, -18 }, [HALL_X] = { 14, -18 } },
	}

	local function caseDoorway(centre: Vector3, outward: Vector3)
		window(
			place(centre) * CFrame.new(Vector3.zero, outward),
			INNER_DOOR_W,
			INNER_DOOR_H,
			"open",
			PART_T,
			interior
		)
	end

	for _, level in { L1, L2 } do
		for _, x in { -HALL_X, HALL_X } do
			local zs = hallDoors[level][x]
			local openings: { Opening } = {}
			for _, z in zs do
				table.insert(openings, doorway(z, level))
			end

			pierced(
				"HallWall",
				"Z",
				x,
				-IN_Z,
				IN_Z,
				level,
				level + STOREY,
				PART_T,
				openings,
				PANEL,
				Enum.Material.WoodPlanks,
				place,
				interior
			)

			for _, z in zs do
				caseDoorway(Vector3.new(x, level + INNER_DOOR_H / 2, z), Vector3.new(1, 0, 0))
			end
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
				PANEL,
				Enum.Material.WoodPlanks,
				place,
				interior
			)
			caseDoorway(Vector3.new(side * 25, level + INNER_DOOR_H / 2, 0), Vector3.new(0, 0, 1))
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

	-- Railings round each stairwell, so the open hall is a view rather than a
	-- trap: along the inner edge, and across the end that looks down onto the
	-- foot of the flight. The other end is where the flight arrives at floor
	-- level, and the outer edge is the hall partition.
	for _, void in
		{
			{ hole = stairVoid1, level = L2, inner = stairVoid1.x1, dropZ = stairVoid1.z1 },
			{ hole = stairVoid2, level = L3, inner = stairVoid2.x0, dropZ = stairVoid2.z0 },
		}
	do
		-- Both runs sit on the floor side of their edge.
		local innerX = void.inner + (if void.inner < 0 then 0.3 else -0.3)
		local dropZ = void.dropZ + (if void.dropZ > 0 then 0.3 else -0.3)

		railing(
			"Landing",
			void.level,
			{ axis = "Z", fixed = innerX, from = void.hole.z0, to = void.hole.z1 },
			place,
			interior
		)
		railing(
			"Landing",
			void.level,
			{ axis = "X", fixed = dropZ, from = void.hole.x0, to = void.hole.x1 },
			place,
			interior
		)

		-- A post where the two runs meet.
		newPart(
			"LandingNewel",
			Vector3.new(0.8, RAIL_TOP + 0.6, 0.8),
			place(Vector3.new(innerX, void.level + (RAIL_TOP + 0.6) / 2, dropZ)),
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

	type Cut = { from: number, to: number, stop: number, zEdge: number }

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

	--[[
		The main slope under a cut runs from the ridge to where the gable's
		ridge bites it — but the gable's eaves are lower than its ridge, so the
		true line where the two roofs meet (the valley) runs diagonally from
		that bite out to the cut's edges, reaching them further down the slope.
		Past a straight strip end that leaves a triangle of sky on each side.
		This lays that triangle in the main roof's own plane, from its three
		corners: where the strip stops at the edge, where the valley reaches
		the edge, and where the valley crosses the strip's end.
	]]
	local function valleys(cut: Cut, side: number)
		local stripEnd = cut.stop + 2
		if cut.zEdge - stripEnd <= EPS then
			return
		end

		local cx = (cut.from + cut.to) / 2
		local halfW = (cut.to - cut.from) / 2
		local normal = Vector3.new(0, math.cos(ROOF_PITCH), side * math.sin(ROOF_PITCH))
		local drop = -normal * (ROOF_T / 2)

		local function onRoof(x: number, z: number): Vector3
			return place(Vector3.new(x, RIDGE - ROOF_FALL * z, side * z) + drop).Position
		end

		for _, dir in { -1, 1 } do
			local edge = cx + dir * halfW
			local inner = cx + dir * halfW * ((stripEnd - cut.stop) / (cut.zEdge - cut.stop))
			triangle(
				"RoofValley",
				onRoof(edge, stripEnd),
				onRoof(edge, cut.zEdge),
				onRoof(inner, stripEnd),
				ROOF_T,
				weathered(SHINGLE, 0.07),
				Enum.Material.RoofShingles,
				shell
			)
		end
	end

	local function laySlope(side: number, gables: { Gable }, extra: { Cut })
		local cuts: { Cut } = table.clone(extra)
		for _, gable in gables do
			local stop, zEdge = dormer(side, gable.cx, gable.width, gable.wall, rng, place, shell)
			table.insert(cuts, {
				from = gable.cx - gable.width / 2,
				to = gable.cx + gable.width / 2,
				stop = stop,
				zEdge = zEdge,
			})
		end

		table.sort(cuts, function(p: Cut, q: Cut): boolean
			return p.from < q.from
		end)

		local cursor = -HALF_W - EAVE
		for _, cut in cuts do
			roofSlab(cursor, cut.from, 0, ROOF_RUN, side, place, shell)
			bare(cursor, cut.from, side)
			-- Under a gable the slope runs from the ridge to two studs past the
			-- bite, and the valleys carry it out to the edges from there.
			roofSlab(cut.from, cut.to, 0, cut.stop + 2, side, place, shell)
			valleys(cut, side)
			cursor = cut.to
		end
		roofSlab(cursor, HALF_W + EAVE, 0, ROOF_RUN, side, place, shell)
		bare(cursor, HALF_W + EAVE, side)
	end

	-- The bay is cut out of the front slope exactly as a dormer would be, but
	-- its walls and roof were built by frontBay, so only the cut is passed here.
	-- Its eaves are the knee wall, so its valleys run all the way to the main
	-- eave.
	laySlope(1, frontGables, {
		{ from = BAY_X0, to = BAY_X1, stop = BAY_STOP, zEdge = (RIDGE - KNEE_TOP) / ROOF_FALL },
	})
	laySlope(-1, backGables, {})

	--[[
		The eave walls. The front and back walls stop at the knee-wall top, but
		the roof does not come down to that height until the fascia, three studs
		out: at the wall line its underside is two and a half studs higher. This
		band closes that slot, running up into the slab — buried, since the slab
		is thicker than the band reaches into it — and skipping every gable and
		the bay, whose own faces and roofs stand there.
	]]
	local eaveWallTop = RIDGE - ROOF_FALL * IN_Z - ROOF_T / math.cos(ROOF_PITCH)

	local function eaveWall(side: number, gables: { Gable }, extra: { Opening })
		local gaps: { Opening } = table.clone(extra)
		for _, gable in gables do
			table.insert(
				gaps,
				{ at = gable.cx, width = gable.width, sill = KNEE_TOP, head = eaveWallTop }
			)
		end
		pierced(
			"WallEave",
			"X",
			side * WALL_Z,
			-IN_X,
			IN_X,
			KNEE_TOP,
			eaveWallTop,
			WALL_T,
			gaps,
			BOARD,
			Enum.Material.WoodPlanks,
			place,
			shell,
			side
		)
	end

	eaveWall(
		1,
		frontGables,
		{ { at = BAY_MID, width = BAY_W, sill = KNEE_TOP, head = eaveWallTop } }
	)
	eaveWall(-1, backGables, {})

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

	--[[
		The chimney climbs the back wall and past the ridge, so it breaks the
		roof line. It sits left of both back dormers and between two windows,
		half in the kitchen, where it is the chimney breast.

		The breast has a fireplace in it at the kitchen floor, or it is a brick
		box in the corner of the room. There is no way to cut a hole in a part,
		so the bottom of the stack is built from the pieces around the hole: a
		back, a pier each side, a lintel across, and everything above in one.
	]]
	local BRICK = Color3.fromRGB(104, 88, 80)
	local CHIMNEY_X = -19
	local STACK_W, STACK_D = 7, 8
	local stackTop = RIDGE + 8
	local breastIn = -HALF_D + STACK_D / 2 -- the room-side face of the breast

	local function brick(name: string, size: Vector3, centre: Vector3)
		newPart(name, size, place(centre), BRICK, Enum.Material.Brick, shell)
	end

	local function plain(name: string, bottom: number, top: number)
		brick(
			name,
			Vector3.new(STACK_W, top - bottom, STACK_D),
			Vector3.new(CHIMNEY_X, (top + bottom) / 2, -HALF_D)
		)
	end

	-- A fireplace in the breast at `level`, `w` wide and `h` tall. Returns the
	-- top of its lintel, where the plain stack takes over again.
	local function fireplace(level: number, w: number, h: number): number
		local d = 2
		local lintelTop = level + h + 1
		local pierW = (STACK_W - w) / 2

		brick(
			"ChimneyBack",
			Vector3.new(STACK_W, lintelTop - level, STACK_D - d),
			Vector3.new(CHIMNEY_X, (lintelTop + level) / 2, -HALF_D - d / 2)
		)
		brick(
			"ChimneyLintel",
			Vector3.new(STACK_W, lintelTop - level - h, d),
			Vector3.new(CHIMNEY_X, (lintelTop + level + h) / 2, breastIn - d / 2)
		)
		for _, side in { -1, 1 } do
			brick(
				"ChimneyPier",
				Vector3.new(pierW, h, d),
				Vector3.new(CHIMNEY_X + side * (w / 2 + pierW / 2), level + h / 2, breastIn - d / 2)
			)
		end

		-- The back of the firebox is black with old soot: the one thing that
		-- makes a recess in brickwork read as a fireplace and not a niche.
		local soot = newPart(
			"Soot",
			Vector3.new(w, h, 0.1),
			place(Vector3.new(CHIMNEY_X, level + h / 2, breastIn - d + 0.05)),
			Color3.fromRGB(34, 30, 28),
			Enum.Material.Slate,
			shell
		)
		soot.CanCollide = false

		-- A stone hearth, running from the back of the firebox out onto the
		-- floor in front, and a timber mantel above. The hearth also covers
		-- the line where the floor slab and the brick below meet in the same
		-- plane, which would flicker.
		local hearth = newPart(
			"Hearth",
			Vector3.new(w + 2, 0.2, d + 1),
			place(Vector3.new(CHIMNEY_X, level + 0.1, breastIn - d / 2 + 0.5)),
			STONE_DARK,
			Enum.Material.Slate,
			shell
		)
		hearth.CanCollide = false
		local mantel = newPart(
			"Mantel",
			Vector3.new(w + 2.4, 0.35, 1.1),
			place(Vector3.new(CHIMNEY_X, lintelTop + 0.2, breastIn + 0.35)),
			TIMBER,
			Enum.Material.Wood,
			shell
		)
		mantel.CanCollide = false

		return lintelTop
	end

	plain("ChimneyBase", GROUND, L1)
	plain("Chimney", fireplace(L1, 4, 4), L2)
	plain("Chimney", fireplace(L2, 3, 3), stackTop)

	newPart(
		"ChimneyCap",
		Vector3.new(STACK_W + 2, 1.2, STACK_D + 2),
		place(Vector3.new(CHIMNEY_X, stackTop + 0.6, -HALF_D)),
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

	-- Lanterns: one on the inner face of each post flanking the steps, one
	-- beside the front door. Warm, and few, so they are the only warm thing
	-- in frame. The housing is glass, so the flame inside can be seen.
	local function lantern(spot: Vector3)
		local housing = newPart(
			"Lantern",
			Vector3.new(1.6, 2.4, 1.6),
			place(spot),
			TIMBER,
			Enum.Material.Glass,
			dressing
		)
		housing.CanCollide = false
		housing.Transparency = 0.45

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

	for _, x in STEP_POST_XS do
		-- Mounted on the post's inner face, over the deck: half the post and
		-- half the housing in from the post's centre line.
		lantern(Vector3.new(x, L1 + 8, PORCH_OUT_Z - 1.5 - 0.9 - 0.8))
	end
	lantern(Vector3.new(FRONT_DOOR_X + DOOR_W / 2 + 1.6, L1 + 9, HALF_D + 0.9))

	----------------------------------------------------------------------------
	-- Hiding places: built-in cupboards
	--
	-- Every wall is placed so it meets the outside wall between two windows,
	-- never across one. The under-stair cupboards are closed at the top by a
	-- triangle that follows the underside of the flight, so there is no gap to
	-- see the hall through.
	----------------------------------------------------------------------------

	-- The pantry, in the kitchen's back corner.
	table.insert(
		hidingSpots,
		cupboard("Pantry", L1, STOREY, {
			{ axis = "Z", fixed = -27.5, from = -IN_Z, to = -18.5 },
			{ axis = "X", fixed = -18.5, from = -IN_X, to = -27.5, door = -29.75 },
		}, Vector3.new(-29.75, L1, -20.4), Vector3.new(3.6, 8, 3), 1, place, interior)
	)

	-- A closet in the back corner of each rear bedroom.
	table.insert(
		hidingSpots,
		cupboard("Closet", L2, STOREY, {
			{ axis = "Z", fixed = -27.5, from = -IN_Z, to = -17.5 },
			{ axis = "X", fixed = -17.5, from = -IN_X, to = -27.5, door = -29.75 },
		}, Vector3.new(-29.75, L2, -19.9), Vector3.new(3.6, 8, 4), 2, place, interior)
	)
	table.insert(
		hidingSpots,
		cupboard("Closet", L2, STOREY, {
			{ axis = "Z", fixed = 27.5, from = -IN_Z, to = -18 },
			{ axis = "X", fixed = -18, from = 27.5, to = IN_X, door = 29.75 },
		}, Vector3.new(29.75, L2, -20.2), Vector3.new(3.6, 8, 3.6), 2, place, interior)
	)

	--[[
		The space under the top half of each flight, where there is standing
		room. The wall on the open side is as tall as the flight's underside at
		its low end; above that, a triangle on the same plane runs up to the
		underside at the high end. Heights come from the flight's own numbers,
		so the wall cannot poke through the treads.
	]]
	local function underStair(
		name: string,
		level: number,
		openX: number,
		backX: number,
		lowZ: number,
		highZ: number,
		lowHead: number,
		highHead: number,
		floor: number
	)
		local doorZ = (lowZ + highZ) / 2
		local nearX = if math.abs(openX) < math.abs(backX) then openX else backX

		table.insert(
			hidingSpots,
			cupboard(
				name,
				level,
				lowHead,
				{
					{ axis = "Z", fixed = openX, from = lowZ, to = highZ, door = doorZ },
					{ axis = "X", fixed = lowZ, from = openX, to = backX },
				},
				Vector3.new((openX + backX) / 2, level, doorZ),
				Vector3.new(4.5, lowHead - 1, 5),
				floor,
				place,
				interior
			)
		)

		-- The far end goes right up to the floor above.
		pierced(
			name .. "Wall",
			"X",
			highZ,
			openX,
			backX,
			level,
			level + STOREY,
			PART_T,
			{},
			PANEL,
			Enum.Material.WoodPlanks,
			place,
			interior
		)

		triangle(
			name .. "Wall",
			place(Vector3.new(nearX, level + lowHead, lowZ)).Position,
			place(Vector3.new(nearX, level + lowHead, highZ)).Position,
			place(Vector3.new(nearX, level + highHead, highZ)).Position,
			PART_T,
			PANEL,
			Enum.Material.WoodPlanks,
			interior
		)
	end

	-- The underside of a flight at a distance `along` from its foot: the rise
	-- reached there, less the string board hanging below it. A wall topped
	-- here runs a hair into the string, so there is no slot to see through.
	local function underside(along: number): number
		return (along / (STAIR_Z_LOW - STAIR_Z_HIGH)) * (L2 - L1) - 1.0
	end

	-- Grand stair: climbs toward -Z, open side toward the hall centre (+X).
	underStair(
		"UnderStair",
		L1,
		S1_MID + STAIR_W / 2 + 0.3,
		-HALL_X + PART_T / 2,
		-8,
		STAIR_Z_HIGH - 0.5,
		underside(STAIR_Z_LOW - -8),
		underside(STAIR_Z_LOW - STAIR_Z_HIGH),
		1
	)

	-- Attic stair: climbs toward +Z, open side toward the hall centre (-X).
	underStair(
		"UnderStair",
		L2,
		S2_MID - STAIR_W / 2 - 0.3,
		HALL_X - PART_T / 2,
		0,
		STAIR_Z_LOW + 0.5,
		underside(0 - STAIR_Z_HIGH),
		underside(STAIR_Z_LOW - STAIR_Z_HIGH),
		2
	)

	----------------------------------------------------------------------------
	-- Lamps hanging from the ceilings, at a level you can only just see by
	----------------------------------------------------------------------------

	local IRON = Color3.fromRGB(46, 44, 42)

	for _, lamp in
		{
			{ at = Vector3.new(0, L1 + STOREY - 2.5, 0), from = L1 + STOREY },
			{ at = Vector3.new(0, L2 + STOREY - 2.5, -8), from = L2 + STOREY },
			{ at = Vector3.new(0, L3 + 9, 0), from = RIDGE - 1 },
		}
	do
		local drop = lamp.from - lamp.at.Y
		local chain = newPart(
			"LampChain",
			Vector3.new(0.15, drop, 0.15),
			place(lamp.at + Vector3.new(0, drop / 2, 0)),
			IRON,
			Enum.Material.Metal,
			interior
		)
		chain.CanCollide = false

		local shade = newPart(
			"LampShade",
			Vector3.new(2.2, 1.2, 2.2),
			place(lamp.at + Vector3.new(0, 0.3, 0)),
			IRON,
			Enum.Material.Metal,
			interior
		)
		shade.CanCollide = false

		local bulb = newPart(
			"LampBulb",
			Vector3.new(0.9, 0.9, 0.9),
			place(lamp.at - Vector3.new(0, 0.5, 0)),
			Color3.fromRGB(214, 190, 150),
			Enum.Material.Neon,
			interior
		)
		bulb.CanCollide = false

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(196, 178, 140)
		light.Brightness = 1.1
		light.Range = 40
		light.Parent = bulb
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
		-- Built from two points, so there is no sign to get backwards: standing
		-- height above the ground at the foot of the steps, looking at the door.
		entrance = CFrame.lookAt(
			place(Vector3.new(STEP_CENTRE, GROUND + 3, PORCH_OUT_Z + 18)).Position,
			place(Vector3.new(FRONT_DOOR_X, GROUND + 3, WALL_Z)).Position
		),
		hidingSpots = hidingSpots,
		partCount = built,
	}
end

return Manor
