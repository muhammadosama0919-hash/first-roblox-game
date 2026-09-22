--!strict
--[[
	HouseKit: the building vocabulary the code-built houses share.

	Every house in this folder is Parts and WedgeParts laid by code, and they
	all need the same handful of hard shapes — a wall with holes in it, a
	window frame, a door that swings, a stair a humanoid can climb, a triangle.
	Each of those is written once here and checked once, rather than three
	times with three sets of bugs.

	Nothing here is a MeshPart. `MeshPart.MeshId` is read-only from a script, so
	a mesh cannot be built in Luau at all. Rounded things are Parts with their
	Shape set to Cylinder or Ball, which the engine draws as true curves.

	Conventions every caller relies on:
	  - Local house space runs +X right, +Y up, +Z out of the front door. A
	    `place` function (see `Kit.placer`) turns a local offset into a world
	    CFrame; nothing else in a house knows the house can be rotated.
	  - A cylinder's axis is its part's X axis and its diameter is its Y and Z
	    size, as in the engine. `Kit.rod` derives that axis from two points, so
	    no call site has to know the convention.
	  - Every door is a Model tagged "Door" holding an invisible part named
	    "Hinge" on its hinge line and a signed "OpenAngle" attribute. The door
	    script (DoorController) swings it; nothing about a door is hard-coded
	    there.

	No part is ever left unanchored. One unanchored wall falls through the
	floor on the first frame and takes a corner of a house down with it.
]]

local CollectionService = game:GetService("CollectionService")

local Kit = {}

-- Guards against emitting zero-thickness parts when two cut lines coincide.
Kit.EPS = 1e-3
local EPS = Kit.EPS

export type Place = (Vector3) -> CFrame

export type Opening = {
	at: number, -- centre along the wall's length axis
	width: number,
	sill: number,
	head: number,
}

export type Hole = { x0: number, x1: number, z0: number, z1: number }

--[[
	How the inside of a room is finished. Below `wainscot` studs the wall's own
	dark boarding shows, like panelling; above it a lining of old wallpaper; a
	rounded chair rail on the line between, a skirting board at the floor, and
	in the grand rooms a cornice at the ceiling.
]]
export type Finish = {
	paper: Color3,
	paperMaterial: Enum.Material?,
	wainscot: number,
	rail: Color3,
	skirting: Color3?,
	cornice: boolean?,
	dado: Color3?, -- line below the rail too (tiles in a bathroom), rather than showing the boards
	dadoMaterial: Enum.Material?,
}

export type Room = {
	name: string,
	level: number,
	height: number,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	finish: Finish?,
}

export type Siding = {
	color: Color3,
	material: Enum.Material,
	spacing: number,
	height: number,
	depth: number,
	missing: number, -- chance a board has come away
}

export type WallSpec = {
	name: string,
	axis: string, -- "X": runs along X at z = fixed. "Z": runs along Z at x = fixed
	fixed: number,
	from: number,
	to: number,
	bottom: number,
	top: number,
	thickness: number,
	openings: { Opening }?,
	color: Color3,
	material: Enum.Material,
	place: Place,
	parent: Instance,
	outward: number?, -- which side is outdoors (+1/-1 along the wall's normal); nil inside
	siding: Siding?,
	rooms: { Room }?, -- finish every face that looks into one of these
	insetEnds: number?, -- linings stop this far short of the run's ends
	weather: number?, -- colour jitter on the wall pieces themselves
}

export type HidingSpot = { part: BasePart, kind: string, floor: number }

export type Built = {
	model: Model,
	entrance: CFrame,
	hidingSpots: { HidingSpot },
	partCount: number,
}

export type Run = { axis: string, fixed: number, from: number, to: number }

----------------------------------------------------------------------------
-- Palette
--
-- Chosen against each other, and all of it dark. Nothing inside a house is
-- lighter than old tobacco: the brightest thing in a room should be whatever
-- light a player brings in, and a single pale surface — a white casing, a
-- cream wall — is what the eye lands on instead.
----------------------------------------------------------------------------

local rgb = Color3.fromRGB
Kit.rgb = rgb

Kit.C = {
	-- structural timber
	TIMBER = rgb(46, 36, 28), -- posts, rails, strings, newels
	CASING = rgb(48, 36, 28), -- interior door casings
	FLOOR = rgb(64, 49, 37),
	WAINSCOT = rgb(56, 42, 32), -- the dark boarding below the chair rail
	RAIL = rgb(36, 27, 21),
	-- Old oxblood paint gone almost black: the window frames. Warm enough
	-- to read as painted wood against the brown, dark enough that no frame
	-- is ever the lightest thing in a room.
	FRAME = rgb(62, 36, 31),
	DOOR = rgb(56, 40, 31),
	DOOR_PANEL = rgb(48, 34, 27),
	-- furniture woods
	OAK = rgb(64, 47, 34),
	WALNUT = rgb(50, 37, 29),
	MAHOGANY = rgb(64, 35, 29),
	PINE = rgb(70, 54, 38),
	-- metal
	IRON = rgb(38, 36, 34),
	RUST = rgb(72, 44, 31),
	BRASS = rgb(96, 78, 48), -- tarnished; polished brass would glint like white
	-- cloth and leather
	VELVET = rgb(70, 26, 25),
	VELVET_DARK = rgb(48, 20, 20),
	CLOTH = rgb(74, 60, 48),
	-- Gone brown with age, never white. Warmer than a grey: a long cloth is
	-- the biggest lit surface in a room, and a grey one reads as white there.
	LINEN = rgb(64, 52, 40),
	LEATHER = rgb(56, 35, 25),
	LEATHER_DARK = rgb(40, 26, 20),
	RUG = rgb(64, 28, 24),
	RUG_BORDER = rgb(40, 22, 18),
	-- wallpapers, all faded and browned
	PAPER_DAMASK = rgb(82, 60, 46),
	PAPER_OXBLOOD = rgb(76, 40, 35),
	PAPER_UMBER = rgb(72, 58, 45),
	PAPER_MAUVE = rgb(74, 55, 53),
	PAPER_OCHRE = rgb(72, 57, 40),
	PAPER_SMOKE = rgb(62, 52, 44),
	-- stone and brick
	STONE = rgb(104, 98, 90),
	STONE_DARK = rgb(80, 75, 68),
	BRICK = rgb(92, 56, 46),
	BRICK_DARK = rgb(70, 44, 37),
	SLATE = rgb(50, 47, 46),
	TILE_DARK = rgb(42, 38, 35),
	TILE_LIGHT = rgb(84, 74, 62),
	-- the dirt of a house nobody has lived in
	GRIME = rgb(34, 27, 22),
	SOOT = rgb(28, 25, 23),
	BLOOD = rgb(58, 13, 11),
	BLOOD_OLD = rgb(46, 18, 14),
	MOULD = rgb(44, 40, 32),
	BONE = rgb(84, 74, 58),
	GLASS_DARK = rgb(30, 32, 32),
	WAX = rgb(80, 70, 54),
}

----------------------------------------------------------------------------
-- Build state
----------------------------------------------------------------------------

local state = {
	count = 0,
	-- Weathering. No two boards on an old house are the same shade, and a
	-- surface whose every piece is one exact colour is the strongest tell that
	-- it was generated. Seeded, so a given board is the same on every server.
	wear = Random.new(1),
}

function Kit.reset(seed: number)
	state.count = 0
	state.wear = Random.new(seed)
end

function Kit.count(): number
	return state.count
end

-- The weathering generator, for callers that want their scatter to share it.
function Kit.wear(): Random
	return state.wear
end

function Kit.weathered(base: Color3, amount: number?): Color3
	local range = amount or 0.14
	local k = 1 + state.wear:NextNumber(-range, range)
	return Color3.new(
		math.clamp(base.R * k, 0, 1),
		math.clamp(base.G * k, 0, 1),
		math.clamp(base.B * k, 0, 1)
	)
end

function Kit.chance(p: number): boolean
	return state.wear:NextNumber() < p
end

--[[
	The one place a house's pivot is applied.

	The pivot sits on the ground at the middle of the footprint, facing the
	way the house faces. House-local +Z is the front and a pivot's LookVector
	is -Z of its own frame, so the local frame is turned half a turn; and the
	house's own ground line, `groundDrop` below its floor, is lifted onto the
	pivot. The checks and the model export all build against a pivot chosen to
	undo exactly this.
]]
function Kit.placer(pivot: CFrame, groundDrop: number): Place
	local base = pivot * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, groundDrop, 0)
	return function(offset: Vector3): CFrame
		return base * CFrame.new(offset)
	end
end

----------------------------------------------------------------------------
-- Parts
----------------------------------------------------------------------------

function Kit.part(
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
	state.count += 1
	return part
end

--[[
	A small ornament: nothing collides with it, touches it, ray-casts into it
	or gets its shadow. Knobs, plates, hinge barrels, stains — there are
	thousands, and each of those four costs something per part per frame.
]]
function Kit.detail(part: Part): Part
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Visible and shadow-casting, but nothing to trip on: cloths, curtains.
function Kit.soft(part: Part): Part
	part.CanCollide = false
	part.CanTouch = false
	return part
end

--[[
	A frame whose X axis runs along `dir`, with Y as close to world up as the
	direction allows. What cylinders are placed with: their axis is X.
]]
function Kit.axisFrame(position: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local y = (ref - x * ref:Dot(x)).Unit
	return CFrame.fromMatrix(position, x, y)
end

-- A cylinder from world point `a` to world point `b`.
function Kit.rod(
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local d = b - a
	local length = d.Magnitude
	if length < EPS then
		d = Vector3.yAxis
		length = EPS
	end
	local part = Kit.part(
		name,
		Vector3.new(length, diameter, diameter),
		Kit.axisFrame((a + b) / 2, d),
		color,
		material,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

--[[
	A disc lying in the XZ plane of `frame`: a cylinder whose axis is the
	frame's UpVector. Table tops, plates, rugs, stains.
]]
function Kit.disc(
	name: string,
	frame: CFrame,
	diameter: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Kit.part(
		name,
		Vector3.new(thickness, diameter, diameter),
		frame * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

function Kit.ball(
	name: string,
	position: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Kit.part(
		name,
		Vector3.new(diameter, diameter, diameter),
		CFrame.new(position),
		color,
		material,
		parent
	)
	part.Shape = Enum.PartType.Ball
	return part
end

--[[
	Fill the triangle a-b-c (world points) with two WedgeParts.

	Roblox has no triangle primitive. Drop a perpendicular from the corner
	opposite the longest edge and any triangle splits into two right
	triangles, and a right triangle is exactly a wedge. Relabelling so the
	longest edge is opposite `a` is what guarantees the foot lands inside.
	Every axis comes from the points, so there is no orientation convention
	to get backwards.
]]
function Kit.triangle(
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
		-- Three points in a line: nothing to fill, and dividing by zero here
		-- would spray NaN CFrames into the workspace.
		return made
	end

	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	for _, half in
		{
			{ edge = ab, centre = (a + b) / 2, flip = 1 },
			{ edge = ac, centre = (a + c) / 2, flip = -1 },
		}
	do
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
			state.count += 1
			table.insert(made, wedge)
		end
	end
	return made
end

----------------------------------------------------------------------------
-- Rooms
----------------------------------------------------------------------------

function Kit.roomAt(rooms: { Room }, point: Vector3): Room?
	for _, room in rooms do
		if
			point.X > room.x0
			and point.X < room.x1
			and point.Z > room.z0
			and point.Z < room.z1
			and point.Y > room.level
			and point.Y < room.level + room.height
		then
			return room
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Walls
----------------------------------------------------------------------------

-- One cell of a face: a stretch of wall between two room edges and two
-- heights, finished for the one room it looks into.
local function lineCell(
	s: WallSpec,
	rooms: { Room },
	at: (number, number, number) -> Vector3,
	sized: (number, number, number) -> Vector3,
	dir: Vector3,
	ca: number,
	cb: number,
	y0: number,
	y1: number,
	face: number
)
	local t = s.thickness
	if y1 - y0 < EPS then
		return
	end
	do
		local room = Kit.roomAt(rooms, at((ca + cb) / 2, (y0 + y1) / 2, face * (t / 2 + 1)))
		if not room or not room.finish then
			return
		end
		local f = room.finish :: Finish
		local floorY = room.level
		local ceilY = room.level + room.height
		local railY = floorY + f.wainscot
		local mid = (ca + cb) / 2
		local length = cb - ca

		-- Wallpaper, from the rail (or the piece's foot, if higher) to the
		-- piece's top, clipped to the ceiling.
		local py0, py1 = math.max(y0, railY), math.min(y1, ceilY)
		if py1 - py0 > EPS then
			Kit.detail(
				Kit.part(
					"Wallpaper",
					sized(length, py1 - py0, 0.1),
					s.place(at(mid, (py0 + py1) / 2, face * (t / 2 + 0.05))),
					Kit.weathered(f.paper, 0.05),
					f.paperMaterial or Enum.Material.Fabric,
					s.parent
				)
			).CastShadow =
				true
		end

		-- A dado lining below the rail, where the room has one.
		local dado = f.dado
		if dado then
			local dy0, dy1 = math.max(y0, floorY), math.min(y1, railY)
			if dy1 - dy0 > EPS then
				Kit.detail(
					Kit.part(
						"Dado",
						sized(length, dy1 - dy0, 0.12),
						s.place(at(mid, (dy0 + dy1) / 2, face * (t / 2 + 0.06))),
						Kit.weathered(dado, 0.04),
						f.dadoMaterial or Enum.Material.CeramicTiles,
						s.parent
					)
				).CastShadow =
					true
			end
		end

		-- The chair rail, a rounded moulding on the line where the paper
		-- stops: only where that line actually crosses this piece.
		if railY > y0 + EPS and railY < y1 - EPS then
			local centre = s.place(at(mid, railY, face * (t / 2 + 0.1)))
			local rail = Kit.rod(
				"ChairRail",
				centre * (-dir * length / 2),
				centre * (dir * length / 2),
				0.34,
				f.rail,
				Enum.Material.Wood,
				s.parent
			)
			Kit.detail(rail)
		end

		-- Skirting, on every piece that stands on this room's floor.
		if math.abs(y0 - floorY) < EPS and f.skirting then
			local skirtH = if s.axis == "X" then 1 else 0.96
			Kit.detail(
				Kit.part(
					"Skirting",
					sized(length, skirtH, 0.24),
					s.place(at(mid, floorY + skirtH / 2, face * (t / 2 + 0.12))),
					f.skirting :: Color3,
					Enum.Material.Wood,
					s.parent
				)
			)
		end

		-- A cornice where the piece meets the ceiling, in the rooms that
		-- earn one.
		if f.cornice and math.abs(y1 - ceilY) < EPS then
			local centre = s.place(at(mid, ceilY - 0.25, face * (t / 2 + 0.15)))
			Kit.detail(
				Kit.rod(
					"Cornice",
					centre * (-dir * length / 2),
					centre * (dir * length / 2),
					0.6,
					f.rail,
					Enum.Material.Wood,
					s.parent
				)
			)
		end
	end
end

--[[
	The finish on one face of one wall piece: wallpaper above the chair rail,
	the rail, the skirting and the cornice.

	A wall piece can run past more than one room — an outside wall passes
	behind every partition that meets it — so the piece is cut wherever a room
	boundary crosses it and each stretch is finished for the room it faces.
	Probing a point a stud off the face is what decides the room, so a face
	that looks into nothing (a floor band, the attic) gets nothing.
]]
local function lineFace(s: WallSpec, a: number, b: number, y0: number, y1: number, face: number)
	local rooms = s.rooms
	if not rooms then
		return
	end
	local t = s.thickness
	local lo, hi = math.min(s.from, s.to), math.max(s.from, s.to)
	local inset = s.insetEnds or 0
	local la, lb = math.max(a, lo + inset), math.min(b, hi - inset)
	if lb - la <= 0.2 then
		return
	end

	local function at(along: number, y: number, across: number): Vector3
		if s.axis == "X" then
			return Vector3.new(along, y, s.fixed + across)
		end
		return Vector3.new(s.fixed + across, y, along)
	end
	local function sized(length: number, h: number, depth: number): Vector3
		if s.axis == "X" then
			return Vector3.new(length, h, depth)
		end
		return Vector3.new(depth, h, length)
	end
	local dir = if s.axis == "X" then Vector3.xAxis else Vector3.zAxis

	-- Where a room edge crosses this stretch, cut.
	local cuts = { la, lb }
	for _, room in rooms do
		local edges: { number } = if s.axis == "X"
			then { room.x0, room.x1 }
			else { room.z0, room.z1 }
		for _, edge in edges do
			if edge > la + 0.05 and edge < lb - 0.05 then
				table.insert(cuts, edge)
			end
		end
	end
	table.sort(cuts)

	for i = 1, #cuts - 1 do
		local ca, cb = cuts[i], cuts[i + 1]
		if cb - ca < 0.2 then
			continue
		end
		-- Rooms can stack in one stretch of wall too — a landing above a
		-- cupboard — so the stretch is cut again wherever the floor or
		-- ceiling of a room it faces falls inside it.
		local probe = at((ca + cb) / 2, 0, face * (t / 2 + 1))
		local ycuts = { y0, y1 }
		for _, room in rooms do
			if
				probe.X > room.x0
				and probe.X < room.x1
				and probe.Z > room.z0
				and probe.Z < room.z1
			then
				for _, e in { room.level, room.level + room.height } do
					if e > y0 + 0.05 and e < y1 - 0.05 then
						table.insert(ycuts, e)
					end
				end
			end
		end
		table.sort(ycuts)
		for j = 1, #ycuts - 1 do
			lineCell(s, rooms, at, sized, dir, ca, cb, ycuts[j], ycuts[j + 1], face)
		end
	end
end

--[[
	A wall with holes in it.

	Roblox cannot cut an opening in a Part, so a pierced wall is the solid
	piers between the openings, plus an apron under each opening and a header
	over it. Every door and window in every house comes out of here, so it is
	one function checked once rather than the same arithmetic written a
	hundred times.

	`axis` is the direction the wall runs and `fixed` is where it sits on the
	other horizontal axis. Openings are in the wall's own length coordinate.
	Callers pass one vertical band at a time — two windows stacked above each
	other are two bands, never one call — which keeps this one-dimensional.
]]
function Kit.wall(s: WallSpec)
	local lo, hi = math.min(s.from, s.to), math.max(s.from, s.to)
	local t = s.thickness

	local function at(along: number, y: number, across: number): Vector3
		if s.axis == "X" then
			return Vector3.new(along, y, s.fixed + across)
		end
		return Vector3.new(s.fixed + across, y, along)
	end
	local function sized(length: number, h: number, depth: number): Vector3
		if s.axis == "X" then
			return Vector3.new(length, h, depth)
		end
		return Vector3.new(depth, h, length)
	end

	local function piece(a: number, b: number, y0: number, y1: number)
		if b - a <= EPS or y1 - y0 <= EPS then
			return
		end
		Kit.part(
			s.name,
			sized(b - a, y1 - y0, t),
			s.place(at((a + b) / 2, (y0 + y1) / 2, 0)),
			if s.weather then Kit.weathered(s.color, s.weather) else s.color,
			s.material,
			s.parent
		)

		for _, face in { -1, 1 } do
			if s.outward == nil or face ~= s.outward then
				lineFace(s, a, b, y0, y1, face)
			end
		end

		local siding = s.siding
		local outward = s.outward
		if siding and outward then
			-- Courses sit on absolute multiples of the spacing, so the lines
			-- run straight across from one wall piece to the next.
			local across = outward * (t / 2 + siding.depth / 2)
			local first = math.ceil((y0 + 0.5) / siding.spacing) * siding.spacing
			for y = first, y1 - 0.5, siding.spacing do
				if Kit.chance(siding.missing) then
					continue
				end
				Kit.soft(
					Kit.part(
						"Clapboard",
						sized(b - a, siding.height, siding.depth),
						s.place(at((a + b) / 2, y, across)),
						Kit.weathered(siding.color, 0.07),
						siding.material,
						s.parent
					)
				)
			end
		end
	end

	local sorted = table.clone(s.openings or {})
	table.sort(sorted, function(p: Opening, q: Opening): boolean
		return p.at < q.at
	end)

	local cursor = lo
	for _, hole in sorted do
		local left = hole.at - hole.width / 2
		local right = hole.at + hole.width / 2
		if right <= cursor + EPS or left >= hi - EPS then
			-- Swallowed by an earlier opening, or off the end of the wall. A
			-- mispositioned window should leave a wall looking wrong, not take
			-- the whole server script down.
			warn(
				string.format(
					"[HouseKit] %s: opening at %.1f falls outside the wall",
					s.name,
					hole.at
				)
			)
			continue
		end
		left = math.max(left, cursor)
		right = math.min(right, hi)
		piece(cursor, left, s.bottom, s.top)
		piece(left, right, s.bottom, math.min(hole.sill, s.top))
		piece(left, right, math.max(hole.head, s.bottom), s.top)
		cursor = right
	end
	piece(cursor, hi, s.bottom, s.top)
end

--[[
	A floor with rectangular voids cut out of it, for stairwells.

	Cut lines come from the hole edges and the floor is the grid cells that
	survive. Every cell is wholly inside a hole or wholly outside it, so there
	is no partial-overlap case to get wrong.
]]
function Kit.slabWithHoles(
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
				Kit.part(
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

----------------------------------------------------------------------------
-- Windows and doors
----------------------------------------------------------------------------

export type WindowOptions = {
	style: string?, -- "window" (sill and cross bars) | "open" (a cased opening)
	thickness: number,
	parent: Instance,
	color: Color3?,
	bars: number?, -- iron bars across the opening: this many, evenly spaced
	barColor: Color3?,
}

--[[
	A window or cased opening: sill, lintel and jambs, and for a window a
	cross of bars. `frame` looks out of the wall, so every piece is placed in
	that frame's own space and the same call works on any wall.

	No glass. Every window is open, so anyone inside can look out and anything
	outside can look in. A window meant to stop people — the villa's — gets
	iron bars through it instead, which still lets a player see out.
]]
function Kit.window(frame: CFrame, width: number, height: number, o: WindowOptions)
	local style = o.style or "window"
	local color = o.color or Kit.C.FRAME
	local jamb = 0.45
	-- Proud of the wall on both sides by enough to cover the ends of the
	-- linings, chair rails and skirtings that stop at the opening.
	local d = o.thickness + 0.62
	-- Nudged a hair into the opening so no frame face lies exactly on the
	-- wall face it covers, which would flicker.
	local nudge = 0.02

	local function piece(name: string, size: Vector3, offset: Vector3): Part
		return Kit.part(name, size, frame * CFrame.new(offset), color, Enum.Material.Wood, o.parent)
	end

	if style == "window" then
		piece(
			"Sill",
			Vector3.new(width + jamb * 2 + 0.4, jamb, d + 0.5),
			Vector3.new(0, -height / 2 - jamb / 2 + nudge, 0)
		)
	end
	piece(
		"Lintel",
		Vector3.new(width + jamb * 2, jamb, d + 0.3),
		Vector3.new(0, height / 2 + jamb / 2 - nudge, 0)
	)
	for _, side in { -1, 1 } do
		piece(
			"Jamb",
			Vector3.new(jamb, height, d),
			Vector3.new(side * (width / 2 + jamb / 2 - nudge), 0, 0)
		)
	end

	if style ~= "window" then
		return
	end

	local bars = o.bars
	if bars and bars > 0 then
		-- Iron bars, set into the sill and the lintel, round like the real
		-- thing. They collide: that is their whole job.
		local barColor = o.barColor or Kit.C.IRON
		for i = 1, bars do
			local x = -width / 2 + width * i / (bars + 1)
			Kit.rod(
				"Bar",
				(frame * CFrame.new(x, -height / 2 - 0.1, 0)).Position,
				(frame * CFrame.new(x, height / 2 + 0.1, 0)).Position,
				0.3,
				barColor,
				Enum.Material.CorrodedMetal,
				o.parent
			)
		end
		-- Two flat straps across, so the bars read as a grille.
		for _, y in { -height / 4, height / 4 } do
			Kit.part(
				"BarStrap",
				Vector3.new(width, 0.22, 0.12),
				frame * CFrame.new(0, y, 0),
				barColor,
				Enum.Material.CorrodedMetal,
				o.parent
			)
		end
		return
	end

	-- Two thin bars are all it takes for a rectangle to read as a window
	-- rather than a hole. The crossbar is a shade thinner than the upright so
	-- no two faces share a plane where they cross.
	Kit.detail(piece("Mullion", Vector3.new(0.3, height, 0.3), Vector3.zero))
	Kit.detail(piece("Mullion", Vector3.new(width, 0.28, 0.28), Vector3.zero))
end

export type DoorOptions = {
	parent: Instance,
	hinge: number, -- which jamb it hangs on: -1 left, +1 right, looking out along the frame
	swing: number, -- which way it opens: +1 out along the frame's LookVector, -1 back
	thickness: number?,
	color: Color3?,
	panel: Color3?,
	style: string?, -- "panel" (four raised panels a side) | "cabinet" (one) | "plank" (boards and ledges)
	openAngle: number?, -- how far it swings, degrees
	startAngle: number?, -- how far open it stands when built, degrees
	name: string?,
	knobs: boolean?,
	gap: number?, -- clearance round the leaf
}

--[[
	A door that opens: a Model tagged "Door", with an invisible "Hinge" part
	on the hinge line and a signed "OpenAngle" attribute (and "Angle", how far
	open it stands now). DoorController turns the Hinge's CFrame about its own
	Y axis and carries every other part of the model round with it.

	`frame` is centred in the doorway and looks out. The hinge line is on the
	leaf's face on the side it swings toward, so the leaf clears its own
	jamb as it turns. Which sign of rotation opens it that way follows from
	the right-hand rule: a leaf hung on the right that swings out needs its
	far edge to move out, and a positive turn about +Y moves -X toward +Z.
	Worked through once here and checked by `checks.py`, which swings every
	door and looks for anything in the way.
]]
function Kit.door(frame: CFrame, width: number, height: number, o: DoorOptions): Model
	local model = Instance.new("Model")
	model.Name = o.name or "Door"
	CollectionService:AddTag(model, "Door")

	local gap = o.gap or 0.2
	local t = o.thickness or 0.4
	local h = o.hinge
	local s = o.swing
	local leafW = width - gap * 2
	local leafH = height - gap
	local color = o.color or Kit.C.DOOR
	local panel = o.panel or Kit.C.DOOR_PANEL

	-- In the frame's own space: x along the wall, z back into the frame (so
	-- the LookVector side is -z). The hinge line sits on the leaf's edge at x
	-- = h * leafW/2 and on the face toward the swing, z = -s * t/2.
	local hingeLocal = CFrame.new(h * (width / 2 - gap), 0, -s * t / 2)
	local hinge = Kit.part(
		"Hinge",
		Vector3.new(0.2, leafH, 0.2),
		frame * hingeLocal,
		Kit.C.IRON,
		Enum.Material.Metal,
		model
	)
	hinge.Transparency = 1
	Kit.detail(hinge)

	-- A positive turn about +Y carries -X toward +Z. Opening "out" (s = +1)
	-- means the far edge (at -h relative to the hinge) moves toward -Z.
	local openAngle = -s * h * (o.openAngle or 95)
	local startAngle = -s * h * (o.startAngle or 0)
	model:SetAttribute("OpenAngle", openAngle)
	model:SetAttribute("Angle", startAngle)

	local swung = frame * hingeLocal * CFrame.Angles(0, math.rad(startAngle), 0)
	-- Everything below is laid out relative to the leaf's centre, then
	-- carried round the hinge to wherever the door stands.
	local leafCentre = CFrame.new(-h * leafW / 2, -gap / 2, s * t / 2)
	local function at(offset: Vector3): CFrame
		return swung * leafCentre * CFrame.new(offset)
	end

	local leaf = Kit.part(
		"Leaf",
		Vector3.new(leafW, leafH, t),
		at(Vector3.zero),
		color,
		Enum.Material.Wood,
		model
	)

	local style = o.style or "panel"
	if style == "cabinet" then
		-- One raised panel a side: wardrobes and cupboards, whose leaves are
		-- too narrow for four.
		for _, face in { -1, 1 } do
			Kit.detail(
				Kit.part(
					"Panel",
					Vector3.new(math.max(0.2, leafW - 0.7), math.max(0.2, leafH - 0.8), 0.08),
					at(Vector3.new(0, 0, face * (t / 2 + 0.04))),
					panel,
					Enum.Material.Wood,
					model
				)
			)
		end
	elseif style == "panel" then
		-- Four raised panels a side: two tall above the lock rail, two short
		-- below it. They are what make a slab read as a door.
		local stile = math.max(0.5, leafW * 0.16)
		local pw = (leafW - stile * 3) / 2
		local lockY = -leafH / 2 + leafH * 0.42
		local upperH = leafH / 2 - lockY - stile * 1.1
		local lowerH = lockY - (-leafH / 2) - stile * 1.6
		for _, face in { -1, 1 } do
			for _, col in { -1, 1 } do
				local x = col * (stile / 2 + pw / 2)
				Kit.detail(
					Kit.part(
						"Panel",
						Vector3.new(pw, upperH, 0.08),
						at(Vector3.new(x, lockY + stile * 0.55 + upperH / 2, face * (t / 2 + 0.04))),
						panel,
						Enum.Material.Wood,
						model
					)
				)
				Kit.detail(
					Kit.part(
						"Panel",
						Vector3.new(pw, lowerH, 0.08),
						at(Vector3.new(x, -leafH / 2 + stile + lowerH / 2, face * (t / 2 + 0.04))),
						panel,
						Enum.Material.Wood,
						model
					)
				)
			end
		end
	else
		-- Boards and a Z brace, for sheds, cellars and cupboards.
		local boards = math.max(3, math.floor(leafW / 1.1))
		for i = 1, boards - 1 do
			local x = -leafW / 2 + leafW * i / boards
			Kit.detail(
				Kit.part(
					"Seam",
					Vector3.new(0.08, leafH, t + 0.04),
					at(Vector3.new(x, 0, 0)),
					panel,
					Enum.Material.Wood,
					model
				)
			)
		end
		for _, face in { -1, 1 } do
			for _, y in { -leafH * 0.32, leafH * 0.32 } do
				Kit.detail(
					Kit.part(
						"Ledge",
						Vector3.new(leafW - 0.3, 0.6, 0.16),
						at(Vector3.new(0, y, face * (t / 2 + 0.08))),
						panel,
						Enum.Material.Wood,
						model
					)
				)
			end
		end
	end

	-- Hinge barrels on the hinge edge: round, iron, three of them.
	for _, y in { -leafH * 0.38, 0, leafH * 0.38 } do
		local p = (swung * CFrame.new(0, y - gap / 2, 0)).Position
		Kit.detail(
			Kit.rod(
				"HingeBarrel",
				p - Vector3.yAxis * 0.35,
				p + Vector3.yAxis * 0.35,
				0.22,
				Kit.C.IRON,
				Enum.Material.Metal,
				model
			)
		)
	end

	if o.knobs ~= false then
		-- A knob on each face at hand height, on the edge away from the hinge.
		local knobY = -leafH / 2 + math.min(4.2, leafH * 0.45)
		local knobX = -h * (leafW / 2 - 0.55)
		for _, face in { -1, 1 } do
			local rose = at(Vector3.new(knobX, knobY, face * (t / 2 + 0.05)))
			Kit.detail(
				Kit.disc(
					"Rose",
					rose * CFrame.Angles(math.pi / 2, 0, 0),
					0.5,
					0.1,
					Kit.C.BRASS,
					Enum.Material.Metal,
					model
				)
			)
			local knob = Kit.ball(
				"Knob",
				(at(Vector3.new(knobX, knobY, face * (t / 2 + 0.3)))).Position,
				0.42,
				Kit.C.BRASS,
				Enum.Material.Metal,
				model
			)
			Kit.detail(knob)
			knob.CanQuery = true -- the prompt hangs off a knob
		end
	end

	leaf.CanCollide = true
	model.Parent = o.parent
	return model
end

----------------------------------------------------------------------------
-- Hiding places
----------------------------------------------------------------------------

--[[
	An invisible volume tagged "HidingSpot", for whatever hunts the players
	to find and whatever lets them hide to use. `kind` says what sort of place
	it is — Cupboard, Wardrobe, UnderTable, UnderBed — so a hiding system can
	treat them differently.
]]
function Kit.hideVolume(
	name: string,
	cframe: CFrame,
	size: Vector3,
	kind: string,
	floor: number,
	parent: Instance
): { part: BasePart, kind: string, floor: number }
	local marker = Kit.part(name, size, cframe, Kit.C.TIMBER, Enum.Material.Plastic, parent)
	marker.Transparency = 1
	Kit.detail(marker)
	marker:SetAttribute("Kind", kind)
	CollectionService:AddTag(marker, "HidingSpot")
	return { part = marker, kind = kind, floor = floor }
end

----------------------------------------------------------------------------
-- Stairs and railings
----------------------------------------------------------------------------

export type StairOptions = {
	rails: { number }?, -- which sides get a balustrade: -1 left, +1 right (looking up)
	wallRails: { number }?, -- sides that get a rail on brackets instead
	treadColor: Color3?,
	railColor: Color3?,
	rotten: number?, -- chance a middle tread has gone
	railHeight: number?,
}

--[[
	A newel post: a square foot, a turned shaft, a collar and a ball on top.
	`floor` is the world point on the surface it stands on and `height` how
	far it rises above that. The foot runs most of a stud down into the floor,
	never a whole one, or its underside would lie on the ceiling below and
	flicker there.
]]
function Kit.newel(name: string, floor: Vector3, height: number, color: Color3, parent: Instance)
	local up = Vector3.yAxis
	Kit.part(
		name,
		Vector3.new(0.95, 2.2, 0.95),
		CFrame.new(floor + up * 0.2),
		color,
		Enum.Material.Wood,
		parent
	)
	Kit.rod(
		name,
		floor + up * 1.2,
		floor + up * (height - 0.5),
		0.72,
		color,
		Enum.Material.Wood,
		parent
	)
	Kit.detail(
		Kit.disc(
			name .. "Collar",
			CFrame.new(floor + up * (height - 0.5)),
			1.0,
			0.22,
			color,
			Enum.Material.Wood,
			parent
		)
	)
	Kit.detail(
		Kit.ball(
			name .. "Cap",
			floor + up * (height - 0.1),
			0.85,
			color,
			Enum.Material.Wood,
			parent
		)
	)
end

--[[
	A flight of stairs between two local points, with the invisible ramp that
	makes it walkable and a handrail a player could actually hold.

	The treads are scenery: they do not collide. What a player walks on is a
	slab at the flight's own angle hidden inside them, because a humanoid
	climbs a ramp without hesitating and snags on a stack of boxes. Its top
	face is the line through the tread backs, which meets the floor at the
	first tread and the landing at the last with no lip, and stays inside the
	treads the whole way so it never shows.

	The rail is round, on turned balusters, between newel posts with ball
	caps; each tread has a rounded nosing. Both axes come from the two
	endpoints rather than an angle, so a flight can point anywhere.
]]
function Kit.staircase(
	name: string,
	bottom: Vector3,
	top: Vector3,
	width: number,
	steps: number,
	place: Place,
	parent: Instance,
	o: StairOptions?
)
	local opts: StairOptions = o or {}
	local delta = top - bottom
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < EPS or steps < 1 then
		warn("[HouseKit] " .. name .. ": a staircase needs horizontal run and at least one step")
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
	local treadColor = opts.treadColor or Kit.C.FLOOR
	local railColor = opts.railColor or Kit.C.TIMBER

	local levelRotation = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis, -ahead)
	local slopeRotation = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
	local mid = (bottom + top) / 2

	for i = 1, steps do
		-- The odd tread has rotted through. Only ever a middle one, and the
		-- ramp still carries the player.
		if i > 1 and i < steps and Kit.chance(opts.rotten or 0.06) then
			continue
		end
		local topY = bottom.Y + treadRise * i
		local centre = bottom + ahead * (treadRun * (i - 0.5))
		Kit.soft(
			Kit.part(
				name .. "Tread",
				Vector3.new(width, treadT, treadRun),
				place(Vector3.new(centre.X, topY - treadT / 2, centre.Z)) * levelRotation,
				Kit.weathered(treadColor, 0.08),
				Enum.Material.WoodPlanks,
				parent
			)
		)
		-- A rounded nosing along the front edge of each tread.
		local nose = bottom
			+ ahead * (treadRun * (i - 1))
			+ Vector3.new(0, topY - bottom.Y - 0.2, 0)
		Kit.detail(
			Kit.rod(
				name .. "Nosing",
				place(nose - right * (width / 2)).Position,
				place(nose + right * (width / 2)).Position,
				0.4,
				treadColor,
				Enum.Material.Wood,
				parent
			)
		)
	end

	local rampT = 0.85
	Kit.part(
		name .. "Ramp",
		Vector3.new(width, rampT, delta.Magnitude),
		place(mid - up * (rampT / 2)) * slopeRotation,
		treadColor,
		Enum.Material.WoodPlanks,
		parent
	)

	local railH = opts.railHeight or 3.6
	local balusters = math.max(2, math.floor(run / 1.6))

	for _, side in { -1, 1 } do
		local edge = right * (side * (width / 2 + 0.3))

		-- String board: hides the tread ends, and is the line the eye reads
		-- the flight by.
		Kit.part(
			name .. "String",
			Vector3.new(0.4, 1.2, delta.Magnitude + treadRun),
			place(mid + edge - up * 0.3) * slopeRotation,
			railColor,
			Enum.Material.Wood,
			parent
		)

		if table.find(opts.rails or { -1, 1 }, side) then
			local postH = railH + 1.4
			-- Posts footed most of a stud into what they stand on, not a whole
			-- one, or a post's underside lies on the ceiling below and flickers.
			Kit.newel(
				name .. "Newel",
				place(bottom + edge - ahead * 0.4).Position,
				postH,
				railColor,
				parent
			)
			Kit.newel(
				name .. "Newel",
				place(top + edge + ahead * 0.4).Position,
				postH,
				railColor,
				parent
			)

			-- The handrail, round, parallel to the flight, run into both caps.
			local r0 = place(bottom + edge + Vector3.new(0, railH, 0) - ahead * 0.4).Position
			local r1 = place(top + edge + Vector3.new(0, railH, 0) + ahead * 0.4).Position
			Kit.rod(name .. "Handrail", r0, r1, 0.5, railColor, Enum.Material.Wood, parent)

			for k = 1, balusters - 1 do
				if Kit.chance(0.1) then
					continue -- a few gone, as everywhere in the house
				end
				-- The rail is parallel to the flight, so every baluster is the
				-- same height above its own foot.
				local foot = bottom + delta * (k / balusters)
				local base = place(foot + edge).Position
				local head = place(foot + edge + Vector3.new(0, railH, 0)).Position
				Kit.detail(
					Kit.rod(
						name .. "Baluster",
						base,
						head,
						0.3,
						railColor,
						Enum.Material.Wood,
						parent
					)
				)
				Kit.detail(
					Kit.ball(
						name .. "BalusterKnop",
						base:Lerp(head, 0.3),
						0.42,
						railColor,
						Enum.Material.Wood,
						parent
					)
				)
			end
		elseif table.find(opts.wallRails or {}, side) then
			-- Against a wall: a round rail on iron brackets, the kind you slide
			-- a hand along in the dark.
			local off = right * (side * (width / 2 - 0.1))
			local r0 = place(bottom + off + Vector3.new(0, railH, 0) + ahead * 0.5).Position
			local r1 = place(top + off + Vector3.new(0, railH, 0) - ahead * 0.5).Position
			Kit.detail(
				Kit.rod(name .. "WallRail", r0, r1, 0.42, railColor, Enum.Material.Wood, parent)
			)
			for k = 1, 3 do
				local p = r0:Lerp(r1, k / 4)
				Kit.detail(
					Kit.rod(
						name .. "Bracket",
						p,
						p + (place(off * 1.06).Position - place(off).Position),
						0.14,
						Kit.C.IRON,
						Enum.Material.Metal,
						parent
					)
				)
			end
		end
	end
end

--[[
	One run of railing on a deck or landing: a round top rail, a flat bottom
	rail and turned balusters. The rails collide and stop anyone walking off
	the edge; the balusters are ornament and do not.
]]
function Kit.railing(
	name: string,
	deck: number,
	run: Run,
	place: Place,
	parent: Instance,
	height: number?,
	color: Color3?
)
	local horizontal = run.axis == "X"
	local length = run.to - run.from
	if length <= EPS then
		return
	end
	local top = height or 3.8
	local c = color or Kit.C.TIMBER
	local mid = (run.from + run.to) / 2

	local function at(along: number, y: number): Vector3
		if horizontal then
			return Vector3.new(along, y, run.fixed)
		end
		return Vector3.new(run.fixed, y, along)
	end

	Kit.rod(
		name .. "Rail",
		place(at(run.from, deck + top)).Position,
		place(at(run.to, deck + top)).Position,
		0.48,
		c,
		Enum.Material.Wood,
		parent
	)
	-- Runs along Z are a shade slimmer than runs along X, so where two meet at
	-- a corner the one sits inside the other instead of sharing its faces.
	Kit.part(
		name .. "Rail",
		if horizontal then Vector3.new(length, 0.35, 0.42) else Vector3.new(0.4, 0.33, length),
		place(at(mid, deck + 1.0)),
		c,
		Enum.Material.Wood,
		parent
	)

	local count = math.max(2, math.floor(length / 1.8))
	for i = 1, count - 1 do
		-- A few gone from the middle of each run. The ends stay.
		if Kit.chance(0.14) then
			continue
		end
		local along = run.from + length * i / count
		local foot = place(at(along, deck + 1.0)).Position
		local head = place(at(along, deck + top)).Position
		Kit.detail(Kit.rod(name .. "Baluster", foot, head, 0.28, c, Enum.Material.Wood, parent))
		Kit.detail(
			Kit.ball(
				name .. "BalusterKnop",
				foot:Lerp(head, 0.35),
				0.4,
				c,
				Enum.Material.Wood,
				parent
			)
		)
	end
end

return Kit
