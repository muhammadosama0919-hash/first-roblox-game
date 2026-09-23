--!strict
--[[
	Yard: the things that stand outside, for the churchyard and the farm.

	Loose pieces follow Furnish's conventions: each is its own Model tagged
	Furniture with its pivot on the ground in the middle of its footprint,
	drawn in its own space with its front toward -Z, and a caller passes the
	world CFrame of that origin. Outside there is no wall to back a piece
	against, so they are placed by their middle.

	Boundaries and small buildings — walls, railings, paths, a lych-gate, a
	mausoleum — are architecture instead: plain parts put straight into the
	folder a caller gives, so the checks test the loose pieces against them
	the way they test furniture against a house's walls. A run is laid from
	`at` along its +X.

	Ground level is Y = 0. Anything that stands in the ground (a headstone,
	a post, the foot of a wall) goes on down below it, so no gap shows
	wherever the terrain lies a little lower than the pad it stands on.

	Nothing here gives light, and nothing is pale: a churchyard at night is
	grey stones in grey grass, and a white one would be the brightest thing
	in the village.
]]

local Kit = require(script.Parent.HouseKit)
local Furnish = require(script.Parent.Furnish)

local C = Kit.C
local M = Enum.Material
local V = Vector3.new
local rgb = Kit.rgb
local fine = Kit.detail
local soft = Kit.soft
local begin = Furnish.begin
local draw = Furnish.draw

type Builder = Furnish.Builder

local Yard = {}

export type Options = { [string]: any }

local function opt(o: Options?, key: string, default: any): any
	if o and o[key] ~= nil then
		return o[key]
	end
	return default
end

----------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------

-- Headstone stones, every one of them a century in the rain.
Yard.STONES = {
	rgb(86, 84, 79), -- limestone
	rgb(88, 77, 63), -- sandstone
	rgb(52, 52, 56), -- slate
	rgb(72, 70, 69), -- granite
	rgb(92, 90, 86), -- marble, grimed: clean, it would glare
}
local LICHEN = rgb(64, 67, 52)
local CARVED = rgb(38, 36, 34) -- the shadow in a cut letter
local EARTH = rgb(46, 35, 27)
local FRESH_EARTH = rgb(36, 27, 20)
local TURF = rgb(70, 84, 46)
local WALL_STONE = rgb(72, 70, 64)
local COPING = rgb(80, 78, 72)
local FLAGSTONE = rgb(66, 64, 60)
local GRAVEL = rgb(58, 55, 50)
local TIMBER = rgb(62, 56, 50) -- oak left out in the weather goes silver-grey
local ROOF_SLATE = rgb(46, 44, 46)
local BARK = rgb(46, 40, 36)
local YEW_BARK = rgb(64, 40, 32)
local YEW_LEAF = rgb(26, 36, 26)
local FEATHER = rgb(22, 22, 26)
local BRONZE = rgb(58, 60, 46) -- gone dark and green
local COFFIN = rgb(46, 32, 26)
local IRON = C.IRON

-- A disc stood on its edge facing -Z, instead of lying flat.
local UPRIGHT = CFrame.Angles(math.pi / 2, 0, 0)
-- A disc stood on its edge facing X.
local SIDEWAYS = CFrame.Angles(0, 0, math.pi / 2)
-- How far anything standing in the ground goes on down into it.
local SINK = 0.6

----------------------------------------------------------------------------
-- Plain parts, for architecture
----------------------------------------------------------------------------

type Pen = {
	box: (
		name: string,
		size: Vector3,
		pos: Vector3,
		color: Color3,
		material: Enum.Material,
		rot: CFrame?
	) -> Part,
	rod: (
		name: string,
		a: Vector3,
		b: Vector3,
		d: number,
		color: Color3,
		material: Enum.Material
	) -> Part,
	ball: (name: string, p: Vector3, d: number, color: Color3, material: Enum.Material) -> Part,
	disc: (
		name: string,
		p: Vector3,
		d: number,
		thickness: number,
		color: Color3,
		material: Enum.Material,
		tilt: CFrame?
	) -> Part,
	tri: (
		name: string,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		thickness: number,
		color: Color3,
		material: Enum.Material
	) -> (),
	-- A squared timber from `a` to `b`, `w` wide and `h` deep, its depth
	-- turned toward `up` as far as the direction allows.
	beam: (
		name: string,
		a: Vector3,
		b: Vector3,
		w: number,
		h: number,
		up: Vector3,
		color: Color3,
		material: Enum.Material
	) -> Part,
}

-- Parts at coordinates in the frame `at`, straight into `parent`.
local function pen(at: CFrame, parent: Instance): Pen
	local p: Pen = {
		box = function(
			n: string,
			size: Vector3,
			pos: Vector3,
			color: Color3,
			material: Enum.Material,
			rot: CFrame?
		): Part
			return Kit.part(
				n,
				size,
				at * CFrame.new(pos) * (rot or CFrame.identity),
				color,
				material,
				parent
			)
		end,
		rod = function(
			n: string,
			a: Vector3,
			b: Vector3,
			d: number,
			color: Color3,
			material: Enum.Material
		): Part
			return Kit.rod(n, at * a, at * b, d, color, material, parent)
		end,
		ball = function(
			n: string,
			pos: Vector3,
			d: number,
			color: Color3,
			material: Enum.Material
		): Part
			return Kit.ball(n, at * pos, d, color, material, parent)
		end,
		disc = function(
			n: string,
			pos: Vector3,
			d: number,
			thickness: number,
			color: Color3,
			material: Enum.Material,
			tilt: CFrame?
		): Part
			return Kit.disc(
				n,
				at * CFrame.new(pos) * (tilt or CFrame.identity),
				d,
				thickness,
				color,
				material,
				parent
			)
		end,
		tri = function(
			n: string,
			a: Vector3,
			b: Vector3,
			c: Vector3,
			thickness: number,
			color: Color3,
			material: Enum.Material
		)
			Kit.triangle(n, at * a, at * b, at * c, thickness, color, material, parent)
		end,
		beam = function(
			n: string,
			a: Vector3,
			b: Vector3,
			w: number,
			h: number,
			up: Vector3,
			color: Color3,
			material: Enum.Material
		): Part
			local d = b - a
			local along = d.Unit
			local y = up - along * up:Dot(along)
			if y.Magnitude < 1e-6 then
				y = Vector3.xAxis - along * along.X
			end
			return Kit.part(
				n,
				V(d.Magnitude, h, w),
				at * CFrame.fromMatrix((a + b) / 2, along, y.Unit),
				color,
				material,
				parent
			)
		end,
	}
	return p
end

-- A part nobody sees or touches: a volume that only means something.
local function unseen(part: Part): Part
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Seen by nothing but the physics: what stops a player where the thing
-- that should stop them is too fine to rely on, like a row of thin bars.
local function blocker(part: Part): Part
	part.Transparency = 1
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

----------------------------------------------------------------------------
-- Walls, railings, paths
----------------------------------------------------------------------------

--[[
	A churchyard wall of rubble stone with a rounded coping, from `at` along
	its +X for `length`, centred on its line. Laid in lengths of a few studs,
	each a slightly different stone, so a long run is not one flat grey band.
	Low enough to climb, too high to step over.
]]
function Yard.stoneWall(at: CFrame, length: number, parent: Instance, o: Options?)
	local h: number = opt(o, "height", 3.6)
	local t: number = opt(o, "thickness", 1.6)
	local p = pen(at, parent)
	local wear = Kit.wear()
	local x = 0
	while x < length - 1e-3 do
		local seg = math.min(length - x, wear:NextNumber(5, 9))
		if length - (x + seg) < 2.5 then
			seg = length - x -- no sliver at the end
		end
		p.box(
			"YardWall",
			V(seg, h + SINK, t),
			V(x + seg / 2, (h - SINK) / 2, 0),
			Kit.weathered(WALL_STONE, 0.07),
			M.Cobblestone
		)
		p.rod(
			"WallCoping",
			V(x, h, 0),
			V(x + seg, h, 0),
			t + 0.3,
			Kit.weathered(COPING, 0.05),
			M.Concrete
		)
		x += seg
	end
end

--[[
	A stone gate pier: square, capped, with a ball on top. `at` is on the
	ground at its middle.
]]
function Yard.pier(at: CFrame, parent: Instance, o: Options?)
	local w: number = opt(o, "width", 2.4)
	local h: number = opt(o, "height", 5.4)
	local p = pen(at, parent)
	p.box(
		"Pier",
		V(w, h + SINK, w),
		V(0, (h - SINK) / 2, 0),
		Kit.weathered(WALL_STONE, 0.05),
		M.Cobblestone
	)
	p.box("PierCap", V(w + 0.5, 0.45, w + 0.5), V(0, h + 0.225, 0), COPING, M.Concrete)
	p.rod("PierNeck", V(0, h + 0.45, 0), V(0, h + 0.75, 0), w * 0.35, COPING, M.Concrete)
	p.ball("PierBall", V(0, h + 0.75 + w * 0.3, 0), w * 0.6, COPING, M.Concrete)
end

--[[
	Iron railings leaded into a low stone wall: round bars with a ball on
	each, a flat rail near the top and the bottom, a thicker standard every
	few bars. From `at` along its +X for `length`.
]]
function Yard.railings(at: CFrame, length: number, parent: Instance, o: Options?)
	local h: number = opt(o, "height", 5.6)
	local spacing: number = opt(o, "spacing", 0.7)
	local base = 1.2 -- the dwarf wall's top
	local p = pen(at, parent)
	p.box(
		"RailWall",
		V(length, base + SINK, 1.1),
		V(length / 2, (base - SINK) / 2, 0),
		Kit.weathered(WALL_STONE, 0.05),
		M.Cobblestone
	)
	p.box("RailCoping", V(length, 0.3, 1.4), V(length / 2, base + 0.15, 0), COPING, M.Concrete)
	local foot = base + 0.3
	for _, y in { foot + 0.55, h - 0.7 } do
		fine(p.box("Rail", V(length, 0.24, 0.14), V(length / 2, y, 0), IRON, M.Metal))
	end
	local n = math.max(1, math.floor(length / spacing + 0.5))
	for i = 0, n - 1 do
		local x = (i + 0.5) * length / n
		local standard = i % 8 == 4
		p.rod(
			"RailBar",
			V(x, foot - 0.1, 0),
			V(x, h, 0),
			if standard then 0.3 else 0.16,
			IRON,
			M.Metal
		)
		fine(p.ball("RailFinial", V(x, h + 0.1, 0), if standard then 0.5 else 0.3, IRON, M.Metal))
	end
	-- The bars are too fine to count on stopping anyone between them.
	blocker(
		p.box(
			"RailingCore",
			V(length, h - foot, 1.2),
			V(length / 2, (h + foot) / 2, 0),
			IRON,
			M.Metal
		)
	)
end

--[[
	A path from `at` along its +X for `length`, `width` across, flat on the
	ground. "flags" lays it in flagstones of every size, a few of them gone;
	"gravel" is one long bed, of gravel or of whatever `color` and
	`material` say, like a farm track's beaten earth. Its parts are named
	for the checks that leave flat things on the ground alone.
]]
function Yard.path(at: CFrame, length: number, width: number, parent: Instance, o: Options?)
	local style: string = opt(o, "style", "flags")
	local p = pen(at, parent)
	if style == "gravel" then
		p.box(
			"Path",
			V(length, 0.3, width),
			V(length / 2, 0.02, 0),
			Kit.weathered(opt(o, "color", GRAVEL), 0.05),
			opt(o, "material", M.Pebble)
		)
		return
	end
	local wear = Kit.wear()
	local gap = 0.12
	local x = 0
	while x < length - 0.6 do
		local run = math.min(wear:NextNumber(1.4, 2.4), length - x)
		if length - (x + run) < 0.8 then
			run = length - x
		end
		local across = if wear:NextNumber() < 0.5 then 2 else 3
		local z = -width / 2
		for k = 1, across do
			local w = if k == across
				then width / 2 - z
				else width / across * wear:NextNumber(0.8, 1.2)
			if wear:NextNumber() > 0.05 then
				p.box(
					"Flags",
					V(run - gap, 0.3, w - gap),
					V(x + run / 2, 0.02, z + w / 2),
					Kit.weathered(FLAGSTONE, 0.1),
					M.Slate,
					CFrame.Angles(0, wear:NextNumber(-0.02, 0.02), 0)
				)
			end
			z += w
		end
		x += run
	end
end

----------------------------------------------------------------------------
-- Graves
----------------------------------------------------------------------------

-- Lines of lettering worn to shallow marks, on a face at `z`.
local function inscribe(s: Builder, w: number, top: number, lines: number, z: number)
	for k = 0, lines - 1 do
		fine(
			s.box(
				"Inscription",
				V(w * (0.7 - (k % 2) * 0.16), 0.13, 0.03),
				V(0, top - k * 0.36, z),
				CARVED,
				M.Concrete
			)
		)
	end
end

-- A bloom of lichen on a face at `z`, somewhere below `h`, on some stones.
local function lichen(s: Builder, w: number, h: number, z: number)
	local wear = Kit.wear()
	if wear:NextNumber() < 0.5 then
		local pw, ph = wear:NextNumber(0.3, 0.6), wear:NextNumber(0.2, 0.4)
		fine(
			s.box(
				"Lichen",
				V(pw, ph, 0.03),
				V(
					wear:NextNumber(-w / 2 + pw / 2, w / 2 - pw / 2),
					wear:NextNumber(0.3, math.max(0.4, h)),
					z
				),
				Kit.weathered(LICHEN, 0.1),
				M.Concrete
			)
		)
	end
end

--[[
	One headstone, standing at the piece's origin with its inscription to -Z.
	Returns the height of its top, where a crow can stand.
]]
local function drawStone(b: Builder, o: Options?): number
	local style: string = opt(o, "style", "round")
	local color: Color3 = opt(o, "stone", Yard.STONES[1])
	local lean: number = opt(o, "lean", 0)
	local tip: number = opt(o, "tip", 0)
	local c = Kit.weathered(color, 0.06)
	-- Turned about its foot: a positive lean tips it forward, toward -Z.
	local s = draw(b.model, b.at * CFrame.Angles(-lean, 0, tip))

	if style == "round" or style == "gabled" then
		local w: number = opt(o, "width", 2.4)
		local h: number = opt(o, "height", 3.4)
		local t = 0.5
		local body = if style == "round" then h - w / 2 else h - w * 0.28
		local broken: boolean = opt(o, "broken", false)
		local snap = body * 0.45
		local standing = if broken then snap else body
		s.box("Headstone", V(w, standing + SINK, t), V(0, (standing - SINK) / 2, 0), c, M.Concrete)
		lichen(s, w, standing - 0.4, -t / 2 - 0.01)
		-- The head of the stone: where it stands, or where it fell. A broken
		-- one fell forward on its face, pivoting on the break, so its top
		-- lies furthest out and its lettering is in the grass.
		local head = s
		if broken then
			local yaw = Kit.wear():NextNumber(-0.35, 0.35)
			head = draw(
				b.model,
				b.at
					* CFrame.new(0.2, t / 2 + 0.02, -t / 2 - 0.5)
					* CFrame.Angles(0, yaw, 0)
					* CFrame.Angles(-math.pi / 2, 0, 0)
					* CFrame.new(0, -snap, 0)
			)
			head.box("Headstone", V(w, body - snap, t), V(0, (snap + body) / 2, 0), c, M.Concrete)
			fine(
				s.box(
					"Break",
					V(w * 0.4, 0.22, t),
					V(w * 0.2, snap + 0.05, 0),
					c,
					M.Concrete,
					CFrame.Angles(0, 0, 0.3)
				)
			)
		else
			inscribe(s, w, body - 0.35, 4, -t / 2 - 0.01)
		end
		if style == "round" then
			head.disc("Headstone", V(0, body, 0), w, t, c, M.Concrete, UPRIGHT)
			if not broken then
				fine(
					s.disc(
						"Roundel",
						V(0, body + w * 0.2, -t / 2 - 0.01),
						w * 0.28,
						0.04,
						CARVED,
						M.Concrete,
						UPRIGHT
					)
				)
			end
		else
			head.tri(
				"Headstone",
				V(-w / 2, body, 0),
				V(w / 2, body, 0),
				V(0, h, 0),
				t,
				c,
				M.Concrete
			)
		end
		return if broken then snap + 0.1 else h
	elseif style == "cross" or style == "celtic" then
		local h: number = opt(o, "height", 5.2)
		local w: number = opt(o, "width", 2.4)
		s.box("CrossBase", V(2.4, 0.5 + SINK, 1.8), V(0, (0.5 - SINK) / 2, 0), c, M.Concrete)
		s.box("CrossBase", V(1.7, 0.5, 1.2), V(0, 0.75, 0), c, M.Concrete)
		inscribe(s, 1.6, 0.75, 1, -0.61)
		s.box("CrossShaft", V(0.46, h - 1.0, 0.42), V(0, (h + 1.0) / 2, 0), c, M.Concrete)
		local armY = h - 1.25
		s.box("CrossArm", V(w * 0.72, 0.44, 0.42), V(0, armY, 0), c, M.Concrete)
		if style == "celtic" then
			local r, n = 0.62, 10
			for k = 0, n - 1 do
				local a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
				fine(
					s.rod(
						"CrossRing",
						V(r * math.cos(a0), armY + r * math.sin(a0), 0),
						V(r * math.cos(a1), armY + r * math.sin(a1), 0),
						0.26,
						c,
						M.Concrete
					)
				)
			end
		end
		return h
	elseif style == "obelisk" then
		local h: number = opt(o, "height", 7.5)
		s.box("MonumentStep", V(2.8, 0.5 + SINK, 2.8), V(0, (0.5 - SINK) / 2, 0), c, M.Concrete)
		s.box("MonumentStep", V(2.2, 0.5, 2.2), V(0, 0.75, 0), c, M.Concrete)
		s.box("MonumentDie", V(1.7, 1.7, 1.7), V(0, 1.85, 0), c, M.Concrete)
		fine(s.box("MonumentCornice", V(1.95, 0.25, 1.95), V(0, 2.8, 0), c, M.Concrete))
		inscribe(s, 1.4, 2.35, 3, -0.86)
		local s0, s1, half = 2.925, h - 0.9, 0.5
		s.box("Obelisk", V(half * 2, s1 - s0, half * 2), V(0, (s0 + s1) / 2, 0), c, M.Concrete)
		local corners =
			{ V(-half, s1, -half), V(half, s1, -half), V(half, s1, half), V(-half, s1, half) }
		for k = 1, 4 do
			s.tri("Pyramidion", corners[k], corners[k % 4 + 1], V(0, h, 0), 0.1, c, M.Concrete)
		end
		return h
	elseif style == "column" then
		-- A column broken off short, for a life cut short.
		local h: number = opt(o, "height", 5.6)
		s.box("MonumentStep", V(2.3, 0.5 + SINK, 2.3), V(0, (0.5 - SINK) / 2, 0), c, M.Concrete)
		s.box("MonumentDie", V(1.7, 1.8, 1.7), V(0, 1.4, 0), c, M.Concrete)
		fine(s.box("MonumentCornice", V(1.95, 0.22, 1.95), V(0, 2.41, 0), c, M.Concrete))
		inscribe(s, 1.3, 1.95, 3, -0.86)
		fine(s.disc("ColumnBase", V(0, 2.67, 0), 1.45, 0.3, c, M.Concrete))
		s.rod("BrokenColumn", V(0, 2.52, 0), V(0, h - 0.55, 0), 1.1, c, M.Concrete)
		-- What is left above the break stands higher on one side.
		fine(s.rod("BrokenColumn", V(0.2, h - 0.6, 0.1), V(0.2, h, 0.1), 0.6, c, M.Concrete))
		fine(
			s.rod(
				"BrokenColumn",
				V(-0.25, h - 0.6, -0.15),
				V(-0.25, h - 0.3, -0.15),
				0.5,
				c,
				M.Concrete
			)
		)
		return h - 0.5
	elseif style == "wooden" then
		-- Two boards nailed crosswise: what a pauper got.
		local h: number = opt(o, "height", 3.6)
		local wood = Kit.weathered(TIMBER, 0.1)
		s.box("GraveBoard", V(0.32, h + SINK, 0.2), V(0, (h - SINK) / 2, 0), wood, M.WoodPlanks)
		s.box("GraveBoard", V(1.5, 0.3, 0.2), V(0, h * 0.72, -0.2), wood, M.WoodPlanks)
		fine(s.box("NamePlate", V(0.7, 0.3, 0.03), V(0, h * 0.72 - 0.4, -0.115), C.RUST, M.Metal))
		return h
	elseif style == "chest" then
		-- A chest tomb. Its origin is the middle of the chest, not a foot.
		local L: number = opt(o, "length", 6.4)
		local W = 3.0
		s.box("TombBase", V(W + 0.6, 0.4 + SINK, L + 0.6), V(0, (0.4 - SINK) / 2, 0), c, M.Concrete)
		s.box("TombChest", V(W, 2.2, L), V(0, 1.5, 0), c, M.Concrete)
		-- Carved roundels down each side, a shade darker than the stone.
		local panel = Color3.new(c.R * 0.82, c.G * 0.82, c.B * 0.82)
		for _, sx in { -1, 1 } do
			for k = -1, 1 do
				fine(
					s.disc(
						"TombRoundel",
						V(sx * (W / 2 + 0.03), 1.5, k * L * 0.3),
						1.2,
						0.08,
						panel,
						M.Concrete,
						SIDEWAYS
					)
				)
			end
		end
		inscribe(s, W * 0.9, 2.1, 3, -L / 2 - 0.01)
		local ajar: boolean = opt(o, "ajar", false)
		local lid = if ajar
			then CFrame.new(0.55, 2.8, -0.35) * CFrame.Angles(0, math.rad(7), 0)
			else CFrame.new(0, 2.8, 0)
		s.box("TombLid", V(W + 0.5, 0.4, L + 0.5), lid.Position, c, M.Concrete, lid.Rotation)
		if ajar then
			fine(
				s.box(
					"TombVoid",
					V(W - 0.5, 0.05, L - 0.5),
					V(0, 2.58, 0),
					rgb(12, 11, 10),
					M.SmoothPlastic
				)
			)
		end
		return 3.0
	end
	return 0
end

--[[
	A headstone on its own. `style` is one of:
	  round    a slab with a round top, the commonest Victorian stone
	  gabled   a slab with a pointed top
	  cross    a plain cross on a stepped base
	  celtic   a cross with a ring round the crossing
	  obelisk  a square needle on a die, with a pyramid for a point
	  column   a column broken off short
	  wooden   two boards nailed crosswise
	  chest    a chest tomb, centred on the chest
	`lean` tips it forward (+) or back and `tip` over sideways, radians about
	its foot. `broken` snaps a slab off and lays the top on the grass.
	Returns it and the height of its top.
]]
function Yard.headstone(at: CFrame, parent: Instance, o: Options?): (Model, number)
	local b = begin("Headstone", at, parent)
	local top = drawStone(b, o)
	return b.model, top
end

--[[
	A whole grave: the headstone at its head and the plot behind it, toward
	+Z, `length` long. The plot is a turfed mound, a stone kerb round
	chippings, bare heaped earth for a new grave, or nothing, sunk level.
	Its pivot is at the foot of the headstone. Returns it and the height of
	the headstone's top.
]]
function Yard.grave(at: CFrame, parent: Instance, o: Options?): (Model, number)
	local style: string = opt(o, "style", "round")
	if style == "chest" then
		local L: number = opt(o, "length", 6.4)
		local b = begin("ChestTomb", at * CFrame.new(0, 0, L / 2), parent)
		return b.model, drawStone(b, o)
	end
	local b = begin("Grave", at, parent)
	local top = drawStone(b, o)
	local plot: string = opt(o, "plot", "mound")
	local L: number = opt(o, "length", 6.6)
	local stone = Kit.weathered(opt(o, "stone", Yard.STONES[1]), 0.06)
	if plot == "mound" or plot == "fresh" then
		-- A long hump: a buried cylinder with a buried ball at each end.
		local fresh = plot == "fresh"
		local r = 1.5
		local y = (if fresh then 0.7 else 0.4) - r
		local reach = math.sqrt(r * r - y * y) -- how far past its end a ball shows
		local z0, z1 = 0.8 + reach, L - reach
		local color = Kit.weathered(if fresh then FRESH_EARTH else TURF, 0.08)
		local material = if fresh then M.Ground else M.Grass
		b.rod("GraveMound", V(0, y, z0), V(0, y, z1), 2 * r, color, material)
		for _, z in { z0, z1 } do
			b.ball("GraveMound", V(0, y, z), 2 * r, color, material)
		end
	elseif plot == "kerb" then
		local kw, z0, z1 = 1.5, 0.55, L
		for _, sx in { -1, 1 } do
			b.box(
				"Kerb",
				V(0.4, 0.45 + SINK, z1 - z0),
				V(sx * kw, (0.45 - SINK) / 2, (z0 + z1) / 2),
				stone,
				M.Concrete
			)
		end
		for _, z in { z0, z1 } do
			b.box(
				"Kerb",
				V(2 * kw + 0.4, 0.45 + SINK, 0.4),
				V(0, (0.45 - SINK) / 2, z),
				stone,
				M.Concrete
			)
		end
		fine(
			b.box(
				"Chippings",
				V(2 * kw - 0.4, 0.12, z1 - z0 - 0.4),
				V(0, 0.28, (z0 + z1) / 2),
				Kit.weathered(rgb(58, 60, 52), 0.08),
				M.Pebble
			)
		)
	end
	if opt(o, "footstone", false) then
		b.box(
			"Footstone",
			V(1.2, 0.9 + SINK, 0.35),
			V(0, (0.9 - SINK) / 2, L + 0.35),
			stone,
			M.Concrete
		)
	end
	return b.model, top
end

----------------------------------------------------------------------------
-- Coffins and an open grave
----------------------------------------------------------------------------

--[[
	A coffin, wider at the shoulders the way they are made, lying along Z
	with its head toward -Z and its bottom at `y`. `lid` is "on", "ajar"
	or "off" (gone: it is somewhere else).
]]
local function drawCoffin(b: Builder, y: number, lid: string, wood: Color3)
	local H = 1.3
	local cy = y + H / 2
	b.box("Coffin", V(2.1, H, 4.0), V(0, cy, -0.3), wood, M.Wood)
	b.box("CoffinFoot", V(1.4, H, 1.6), V(0, cy, 2.5), wood, M.Wood)
	b.box("CoffinHead", V(1.6, H, 0.8), V(0, cy, -2.7), wood, M.Wood)
	for _, s in { -1, 1 } do
		b.tri(
			"CoffinTaper",
			V(s * 1.05, cy, 1.7),
			V(s * 0.7, cy, 3.3),
			V(s * 0.7, cy, 1.7),
			H,
			wood,
			M.Wood
		)
		b.tri(
			"CoffinTaper",
			V(s * 1.05, cy, -2.3),
			V(s * 0.8, cy, -3.1),
			V(s * 0.8, cy, -2.3),
			H,
			wood,
			M.Wood
		)
	end
	for _, z in { -1.3, 0.4, 2.0 } do
		for _, s in { -1, 1 } do
			fine(
				b.rod(
					"CoffinHandle",
					V(s * 1.15, cy - 0.1, z - 0.4),
					V(s * 1.15, cy - 0.1, z + 0.4),
					0.14,
					BRONZE,
					M.Metal
				)
			)
		end
	end
	if lid == "on" then
		b.box("CoffinLid", V(2.0, 0.22, 6.1), V(0, y + H + 0.11, 0.35), wood, M.Wood)
		fine(b.box("CoffinPlate", V(0.6, 0.04, 1.0), V(0, y + H + 0.24, -0.8), BRONZE, M.Metal))
	else
		-- Nothing inside. The dark is the inside of the box.
		fine(
			b.box(
				"CoffinVoid",
				V(1.7, 0.05, 5.4),
				V(0, y + H - 0.02, 0.2),
				rgb(12, 11, 10),
				M.SmoothPlastic
			)
		)
		if lid == "ajar" then
			b.box(
				"CoffinLid",
				V(2.0, 0.22, 6.1),
				V(0.9, y + H + 0.11, 0.6),
				wood,
				M.Wood,
				CFrame.Angles(0, math.rad(-9), 0)
			)
		end
	end
end

--[[
	A coffin on its own, its pivot under its middle.
]]
function Yard.coffin(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Coffin", at, parent)
	drawCoffin(b, 0, opt(o, "lid", "on"), Kit.weathered(opt(o, "wood", COFFIN), 0.08))
	return b.model
end

--[[
	A grave dug and left open: a pit with its sides of bare earth, a coffin
	at the bottom with its lid gone and nothing in it, the spoil heaped along
	one side with the spade still in it, and planks laid across the foot.

	A model can hold a hole's sides but cannot make a hole: the ground is
	terrain that exists only once the world is built. So the pit is also a
	GroundCut, an unseen part that Groundwork digs the terrain out of after
	it levels the pad. Its pivot is on the ground at the middle of the pit,
	which runs along Z.
]]
function Yard.openGrave(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("OpenGrave", at, parent)
	local W, L, D = 3.2, 7.2, 5.0
	-- Dug wider than the pit, so no terrain is left inside its sides; the lip
	-- round the top covers the difference.
	unseen(
		b.box("GroundCut", V(W + 2.4, D + 1.2, L + 2.4), V(0, (1.2 - D) / 2, 0), EARTH, M.Ground)
	)
	for _, sx in { -1, 1 } do
		b.box("GraveSide", V(0.3, D, L + 0.6), V(sx * (W / 2 + 0.15), -D / 2, 0), EARTH, M.Ground)
		b.box(
			"GraveLip",
			V(1.6, 0.2, L + 3.4),
			V(sx * (W / 2 + 1.1), 0.1, 0),
			Kit.weathered(EARTH, 0.06),
			M.Ground
		)
	end
	for _, sz in { -1, 1 } do
		b.box("GraveSide", V(W, D, 0.3), V(0, -D / 2, sz * (L / 2 + 0.15)), EARTH, M.Ground)
		b.box(
			"GraveLip",
			V(W, 0.2, 1.4),
			V(0, 0.1, sz * (L / 2 + 1.0)),
			Kit.weathered(EARTH, 0.06),
			M.Ground
		)
	end
	b.box("GraveFloor", V(W, 0.3, L), V(0, -D - 0.15, 0), FRESH_EARTH, M.Ground)
	-- Shoring: boards along the long sides, and struts across between them.
	for _, sx in { -1, 1 } do
		for _, y in { -1.2, -3.4 } do
			fine(
				b.box(
					"Shoring",
					V(0.12, 0.9, L - 0.4),
					V(sx * (W / 2 - 0.06), y, 0),
					TIMBER,
					M.WoodPlanks
				)
			)
		end
	end
	for _, z in { -L / 4, L / 4 } do
		b.rod("Strut", V(-W / 2 + 0.12, -1.4, z), V(W / 2 - 0.12, -1.4, z), 0.3, TIMBER, M.Wood)
	end
	-- Down there, empty.
	local deep = draw(b.model, b.at * CFrame.Angles(0, math.rad(4), 0))
	drawCoffin(deep, -D, "off", Kit.weathered(COFFIN, 0.08))
	-- The spoil, heaped along the +X side, and the spade in it.
	local r = 1.7
	local y = 1.1 - r
	local heapX = W / 2 + 0.3 + 1.6 + 0.4
	local reach = math.sqrt(r * r - y * y)
	for _, z in { -L / 2 + reach, L / 2 - reach } do
		b.ball("Spoil", V(heapX, y, z), 2 * r, Kit.weathered(FRESH_EARTH, 0.06), M.Ground)
	end
	b.rod(
		"Spoil",
		V(heapX, y, -L / 2 + reach),
		V(heapX, y, L / 2 - reach),
		2 * r,
		Kit.weathered(FRESH_EARTH, 0.06),
		M.Ground
	)
	local spade = draw(b.model, b.at * CFrame.new(heapX, 0.9, 1.2) * CFrame.Angles(0.15, 0.6, -0.2))
	fine(spade.box("SpadeBlade", V(0.8, 1.0, 0.08), V(0, 0, 0), C.RUST, M.CorrodedMetal))
	fine(spade.rod("SpadeShaft", V(0, 0.5, 0), V(0, 3.6, 0), 0.18, TIMBER, M.Wood))
	fine(spade.rod("SpadeGrip", V(-0.3, 3.6, 0), V(0.3, 3.6, 0), 0.14, TIMBER, M.Wood))
	-- Two planks across the foot, to stand on while lowering.
	for _, z in { L / 2 - 0.7, L / 2 - 1.8 } do
		b.box(
			"Plank",
			V(W + 2.4, 0.18, 0.8),
			V(-0.4, 0.29, z),
			Kit.weathered(TIMBER, 0.1),
			M.WoodPlanks
		)
	end
	-- The lowering straps, left hanging in.
	for _, z in { -1.4, 1.0 } do
		soft(b.box("Strap", V(0.3, 3.4, 0.06), V(-W / 2 + 0.2, -1.5, z), rgb(44, 36, 28), M.Fabric))
	end
	return b.model
end

----------------------------------------------------------------------------
-- Trees
----------------------------------------------------------------------------

-- A direction about `spread` radians off `dir`, at a random bearing round it.
local function turn(dir: Vector3, rng: Random, spread: number): Vector3
	local ref = if math.abs(dir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = dir:Cross(ref).Unit
	local w = dir:Cross(u)
	local bearing = rng:NextNumber(0, 2 * math.pi)
	local a = spread * rng:NextNumber(0.6, 1.2)
	local side = u * math.cos(bearing) + w * math.sin(bearing)
	return (dir * math.cos(a) + side * math.sin(a)).Unit
end

--[[
	A dead tree: a trunk forking into bare limbs, each forking again, all of
	it grey and split. Grown from `seed`, so the same seed is the same tree.
	Returns it and the forks of its big limbs, where crows sit.
]]
function Yard.deadTree(at: CFrame, parent: Instance, o: Options?): (Model, { CFrame })
	local b = begin("DeadTree", at, parent)
	local rng = Random.new(opt(o, "seed", 1))
	local height: number = opt(o, "height", 18)
	local girth: number = opt(o, "girth", 2.2)
	local bark = Kit.weathered(opt(o, "bark", BARK), 0.06)
	local perches: { CFrame } = {}

	-- Roots, spreading into the ground.
	for k = 0, 4 do
		local a = 2 * math.pi * k / 5 + rng:NextNumber(-0.3, 0.3)
		local d = V(math.cos(a), 0, math.sin(a))
		b.rod(
			"Root",
			d * 0.3 + V(0, 1.2, 0),
			d * (girth * 1.4) + V(0, -0.4, 0),
			girth * 0.42,
			bark,
			M.Wood
		)
	end
	-- The trunk, in three lengths, bending a little at each.
	local p = V(0, -SINK, 0)
	local dir = V(rng:NextNumber(-0.12, 0.12), 1, rng:NextNumber(-0.12, 0.12)).Unit
	local d = girth
	local trunkH = height * 0.45
	for _ = 1, 3 do
		local q = p + dir * (trunkH / 3)
		b.rod("Trunk", p, q, d, bark, M.Wood)
		b.ball("Trunk", q, d, bark, M.Wood)
		p = q
		d *= 0.86
		dir = (dir + V(rng:NextNumber(-0.18, 0.18), 0, rng:NextNumber(-0.18, 0.18))).Unit
	end
	-- The limbs, three from the crown, forking twice, then twigs.
	local function limb(from: Vector3, heading: Vector3, len: number, dia: number, depth: number)
		local to = from + heading * len
		local part = b.rod("Branch", from, to, dia, bark, M.Wood)
		if depth > 0 then
			fine(part)
		end
		if depth == 1 then
			table.insert(perches, b.at * CFrame.new(to + V(0, dia / 2, 0)))
		end
		if depth >= 3 then
			return
		end
		local n = if depth == 0 then 2 else (if depth == 2 then 1 else 2)
		for _ = 1, n do
			-- Dead limbs sag: each fork is pulled a little toward the ground.
			local fork = (turn(heading, rng, 0.55) + V(0, -0.12 * depth, 0)).Unit
			limb(to, fork, len * rng:NextNumber(0.55, 0.75), dia * 0.62, depth + 1)
		end
	end
	for k = 0, 2 do
		local a = 2 * math.pi * k / 3 + rng:NextNumber(-0.4, 0.4)
		local heading = (dir * 1.2 + V(math.cos(a), 0, math.sin(a))).Unit
		limb(p, heading, height * 0.3, d * 0.75, 0)
	end
	return b.model, perches
end

--[[
	An old yew, the tree every churchyard has: a short trunk of stems grown
	together, reddish and fluted, under a crown so dark and dense it is
	nearly black, hanging almost to the ground.
]]
function Yard.yew(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Yew", at, parent)
	local rng = Random.new(opt(o, "seed", 7))
	local spread: number = opt(o, "spread", 7)
	local height: number = opt(o, "height", 15)
	for k = 0, 4 do
		local a = 2 * math.pi * k / 5 + rng:NextNumber(-0.2, 0.2)
		local off = V(math.cos(a), 0, math.sin(a)) * 0.9
		b.rod(
			"YewTrunk",
			off + V(0, -SINK, 0),
			off * 0.4 + V(rng:NextNumber(-0.4, 0.4), height * 0.45, rng:NextNumber(-0.4, 0.4)),
			1.6,
			Kit.weathered(YEW_BARK, 0.1),
			M.Wood
		)
	end
	for _ = 1, 14 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(0.2, 1) * spread * 0.6
		local y = rng:NextNumber(0.4, 0.95) * height
		local size = rng:NextNumber(5, 8) * (1.1 - y / height * 0.4)
		soft(
			b.ball(
				"YewCrown",
				V(math.cos(a) * r, y, math.sin(a) * r),
				size,
				Kit.weathered(YEW_LEAF, 0.12),
				M.Grass
			)
		)
	end
	return b.model
end

----------------------------------------------------------------------------
-- Small things
----------------------------------------------------------------------------

--[[
	A crow, standing, facing -Z, its feet at the origin. `peck` has its head
	down at something on the ground.
]]
function Yard.crow(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Crow", at, parent)
	local f = Kit.weathered(FEATHER, 0.1)
	local pitch = if opt(o, "peck", false) then 0.6 else -0.15
	local body = draw(b.model, b.at * CFrame.new(0, 0.3, 0) * CFrame.Angles(-pitch, 0, 0))
	fine(body.ball("CrowBody", V(0, 0.22, 0), 0.62, f, M.Fabric))
	fine(body.ball("CrowBody", V(0, 0.18, 0.34), 0.5, f, M.Fabric))
	fine(body.ball("CrowHead", V(0, 0.5, -0.36), 0.42, f, M.Fabric))
	fine(
		body.rod(
			"CrowBeak",
			V(0, 0.48, -0.52),
			V(0, 0.42, -0.82),
			0.12,
			rgb(30, 30, 32),
			M.SmoothPlastic
		)
	)
	fine(
		body.box(
			"CrowTail",
			V(0.3, 0.06, 0.62),
			V(0, 0.14, 0.78),
			f,
			M.Fabric,
			CFrame.Angles(0.3, 0, 0)
		)
	)
	for _, sx in { -1, 1 } do
		fine(
			body.box(
				"CrowWing",
				V(0.08, 0.32, 0.8),
				V(sx * 0.27, 0.24, 0.14),
				f,
				M.Fabric,
				CFrame.Angles(0.15, 0, 0)
			)
		)
		fine(
			b.rod(
				"CrowLeg",
				V(sx * 0.08, 0.34, 0),
				V(sx * 0.08, 0, -0.02),
				0.05,
				f,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

--[[
	A churchyard bench: slats of silvered oak on cast-iron ends, one slat
	gone from the back.
]]
function Yard.bench(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Bench", at, parent)
	local L: number = opt(o, "length", 5)
	local wood = Kit.weathered(TIMBER, 0.08)
	for _, sx in { -1, 1 } do
		local x = sx * (L / 2 - 0.25)
		b.rod("BenchLeg", V(x, -SINK, -0.75), V(x, 1.85, -0.6), 0.22, IRON, M.Metal)
		b.rod("BenchLeg", V(x, -SINK, 0.75), V(x, 1.85, 0.6), 0.22, IRON, M.Metal)
		b.rod("BenchBack", V(x, 1.85, 0.6), V(x, 4.1, 1.0), 0.2, IRON, M.Metal)
		fine(b.rod("BenchArm", V(x, 1.85, -0.6), V(x, 3.0, -0.8), 0.18, IRON, M.Metal))
		fine(b.rod("BenchArm", V(x, 3.0, -0.8), V(x, 3.0, 0.75), 0.24, IRON, M.Metal))
		fine(b.ball("BenchScroll", V(x, 3.0, -0.85), 0.34, IRON, M.Metal))
	end
	for k = 0, 3 do
		b.box("BenchSlat", V(L, 0.18, 0.34), V(0, 1.95, -0.6 + k * 0.42), wood, M.WoodPlanks)
	end
	local lean = math.atan(0.4 / 2.2)
	for k = 0, 2 do
		if k ~= 1 then
			local y = 2.6 + k * 0.55
			local z = 0.6 + (y - 1.85) / 2.2 * 0.4 + 0.15
			b.box(
				"BenchSlat",
				V(L, 0.36, 0.14),
				V(0, y, z),
				wood,
				M.WoodPlanks,
				CFrame.Angles(lean, 0, 0)
			)
		end
	end
	return b.model
end

--[[
	A sundial on a turned stone pillar, the bronze dial gone green.
]]
function Yard.sundial(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Sundial", at, parent)
	local c = Kit.weathered(opt(o, "stone", Yard.STONES[1]), 0.05)
	b.box("SundialStep", V(2.6, 0.4 + SINK, 2.6), V(0, (0.4 - SINK) / 2, 0), c, M.Concrete)
	b.disc("SundialFoot", V(0, 0.55, 0), 1.5, 0.3, c, M.Concrete)
	b.rod("SundialShaft", V(0, 0.7, 0), V(0, 3.2, 0), 0.8, c, M.Concrete)
	fine(b.ball("SundialKnop", V(0, 1.9, 0), 1.0, c, M.Concrete))
	b.disc("SundialCap", V(0, 3.35, 0), 1.6, 0.3, c, M.Concrete)
	fine(b.disc("SundialDial", V(0, 3.54, 0), 1.4, 0.08, BRONZE, M.Metal))
	b.tri("Gnomon", V(0, 3.58, 0.55), V(0, 3.58, -0.45), V(0, 4.3, 0.5), 0.06, BRONZE, M.Metal)
	for k = 0, 8 do
		local a = math.pi * (k / 8 - 0.5)
		fine(
			b.box(
				"HourMark",
				V(0.05, 0.02, 0.16),
				V(math.sin(a) * 0.56, 3.59, -math.cos(a) * 0.56),
				CARVED,
				M.Metal,
				CFrame.Angles(0, -a, 0)
			)
		)
	end
	return b.model
end

--[[
	A cast-iron lamp post with its lantern dark: no flame, no light, one
	pane broken out.
]]
function Yard.lampPost(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("LampPost", at, parent)
	local h: number = opt(o, "height", 9)
	b.disc("LampBase", V(0, 0.4, 0), 1.1, 0.8, IRON, M.Metal)
	b.rod("LampPost", V(0, -SINK, 0), V(0, h - 1.7, 0), 0.4, IRON, M.Metal)
	fine(b.ball("LampKnop", V(0, 1.6, 0), 0.7, IRON, M.Metal))
	fine(b.rod("LadderBar", V(-0.7, h - 2.3, 0), V(0.7, h - 2.3, 0), 0.14, IRON, M.Metal))
	local y0, y1 = h - 1.7, h - 0.1
	b.box("LanternFloor", V(1.1, 0.14, 1.1), V(0, y0 + 0.07, 0), IRON, M.Metal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			fine(
				b.rod(
					"LanternBar",
					V(sx * 0.5, y0, sz * 0.5),
					V(sx * 0.5, y1, sz * 0.5),
					0.1,
					IRON,
					M.Metal
				)
			)
		end
	end
	for i, face in { V(0, 0, -1), V(1, 0, 0), V(0, 0, 1), V(-1, 0, 0) } do
		if i ~= 2 then
			fine(
				b.box(
					"LanternGlass",
					V(0.9, y1 - y0 - 0.2, 0.04),
					face * 0.5 + V(0, (y0 + y1) / 2, 0),
					C.GLASS_DARK,
					M.Glass,
					CFrame.new(Vector3.zero, face)
				)
			)
		end
	end
	fine(b.ball("Mantle", V(0, y0 + 0.5, 0), 0.3, C.SOOT, M.Fabric))
	b.disc("LanternCap", V(0, y1 + 0.06, 0), 1.4, 0.12, IRON, M.Metal)
	fine(b.disc("LanternCap", V(0, y1 + 0.2, 0), 0.9, 0.16, IRON, M.Metal))
	fine(b.ball("LanternFinial", V(0, y1 + 0.42, 0), 0.3, IRON, M.Metal))
	return b.model
end

--[[
	A churchyard cross of the old kind: three square steps, a socket stone,
	and a round shaft with its head knocked off long ago. The head lies on
	the grass where it fell.
]]
function Yard.churchyardCross(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("ChurchyardCross", at, parent)
	local c = Kit.weathered(opt(o, "stone", rgb(78, 76, 70)), 0.04)
	local y = 0
	for k, w in { 7.0, 5.4, 3.8 } do
		local rise = 0.8
		local sink = if k == 1 then SINK else 0
		b.box(
			"CalvaryStep",
			V(w, rise + sink, w),
			V(0, y + (rise - sink) / 2, 0),
			Kit.weathered(c, 0.03),
			M.Concrete
		)
		y += rise
	end
	b.box("CrossSocket", V(2.4, 1.6, 2.4), V(0, y + 0.8, 0), c, M.Concrete)
	y += 1.6
	b.rod("CrossShaft", V(0, y, 0), V(0, y + 6.5, 0), 1.0, c, M.Concrete)
	fine(b.rod("CrossShaft", V(0.15, y + 6.5, 0.1), V(0.15, y + 7.1, 0.1), 0.55, c, M.Concrete))
	-- The fallen head, flat in the grass where it landed.
	local head = draw(
		b.model,
		b.at
			* CFrame.new(5.0, 0.23, -1.0)
			* CFrame.Angles(0, 0.4, 0)
			* CFrame.Angles(math.pi / 2, 0, 0)
	)
	head.box("CrossHead", V(0.8, 2.6, 0.45), V(0, 0, 0), c, M.Concrete)
	head.box("CrossHead", V(2.2, 0.7, 0.45), V(0, 0.3, 0), c, M.Concrete)
	return b.model
end

----------------------------------------------------------------------------
-- The lych-gate
----------------------------------------------------------------------------

--[[
	A lych-gate: the roofed gateway into a churchyard, where a coffin waited
	for the priest. Oak posts on low stone walls, a steep roof of stone
	slates with its ridge across the path, and a pair of ledged gates hung
	between the walls under it, opening in toward the church.

	`at` is on the ground in the middle of the gateway, looking out of the
	churchyard, so -Z is the lane and +Z the church. The structure goes in
	`parent` and the two gates, Door models, in `doors`. Returns the gates.
]]
function Yard.lychGate(at: CFrame, parent: Instance, doors: Instance, o: Options?): { Model }
	local p = pen(at, parent)
	local oak = opt(o, "wood", TIMBER)
	local PITCH = math.rad(50)
	local FALL = math.tan(PITCH)
	local SIDE_X, POST_Z = 4.6, 2.6
	local WALL_H = 1.8
	-- Side walls, the posts on them, the plates across and the trusses.
	for _, sx in { -1, 1 } do
		p.box(
			"LychWall",
			V(1.2, WALL_H + SINK, 6.2),
			V(sx * SIDE_X, (WALL_H - SINK) / 2, 0),
			Kit.weathered(WALL_STONE, 0.05),
			M.Cobblestone
		)
		p.box(
			"LychCoping",
			V(1.5, 0.25, 6.5),
			V(sx * SIDE_X, WALL_H + 0.125, 0),
			COPING,
			M.Concrete
		)
	end
	local postTop = 7.65
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local foot = WALL_H + 0.25
			p.box(
				"LychPost",
				V(0.8, postTop - foot, 0.8),
				V(sx * SIDE_X, (foot + postTop) / 2, sz * POST_Z),
				Kit.weathered(oak, 0.06),
				M.Wood
			)
			-- A brace from the post up to the plate, on the inside.
			p.beam(
				"LychBrace",
				V(sx * (SIDE_X - 0.4), postTop - 1.5, sz * POST_Z),
				V(sx * (SIDE_X - 1.7), postTop, sz * POST_Z),
				0.4,
				0.4,
				V(0, 0, 1),
				oak,
				M.Wood
			)
		end
	end
	for _, sz in { -1, 1 } do
		p.box("LychPlate", V(11.0, 0.7, 0.8), V(0, postTop + 0.35, sz * POST_Z), oak, M.Wood)
	end
	local tieTop = postTop + 1.4
	local tieZ = 3.9
	-- The roof's underside: rafters 0.5 deep sitting on the ends of the ties.
	local ridgeUnder = tieTop + 0.5 + tieZ * FALL
	local function under(z: number): number
		return ridgeUnder - math.abs(z) * FALL
	end
	for _, sx in { -1, 1 } do
		local x = sx * SIDE_X
		p.box("LychTie", V(0.8, 0.7, tieZ * 2), V(x, tieTop - 0.35, 0), oak, M.Wood)
		p.box(
			"KingPost",
			V(0.6, ridgeUnder - 0.5 - tieTop, 0.6),
			V(x, (tieTop + ridgeUnder - 0.5) / 2, 0),
			oak,
			M.Wood
		)
		for _, sz in { -1, 1 } do
			local n = V(0, math.cos(PITCH), sz * math.sin(PITCH))
			p.beam(
				"LychRafter",
				V(x, under(sz * tieZ), sz * tieZ) - n * 0.25,
				V(x, ridgeUnder, 0) - n * 0.25,
				0.6,
				0.5,
				n,
				oak,
				M.Wood
			)
		end
	end
	p.box("LychRidge", V(12.8, 0.6, 0.45), V(0, ridgeUnder - 0.3, 0), oak, M.Wood)
	-- The roof: a slope of stone slates each side, bargeboards at the ends,
	-- a round ridge tile over the join and a small cross at each gable.
	local eave, halfW, t = 4.9, 6.6, 0.45
	for _, sz in { -1, 1 } do
		local n = V(0, math.cos(PITCH), sz * math.sin(PITCH))
		p.beam(
			"LychRoof",
			V(0, under(sz * eave), sz * eave) + n * t / 2,
			V(0, ridgeUnder, 0) + n * t / 2,
			halfW * 2,
			t,
			n,
			Kit.weathered(ROOF_SLATE, 0.05),
			M.Slate
		)
		for _, sx in { -1, 1 } do
			p.beam(
				"Bargeboard",
				V(sx * (halfW - 0.15), under(sz * eave), sz * eave) - n * 0.4,
				V(sx * (halfW - 0.15), ridgeUnder, 0) - n * 0.4,
				0.25,
				0.8,
				n,
				oak,
				M.Wood
			)
		end
	end
	local ridgeTop = ridgeUnder + t / math.cos(PITCH)
	p.rod(
		"RidgeTile",
		V(-halfW - 0.1, ridgeTop - 0.15, 0),
		V(halfW + 0.1, ridgeTop - 0.15, 0),
		0.8,
		ROOF_SLATE,
		M.Slate
	)
	for _, sx in { -1, 1 } do
		p.box(
			"GableCross",
			V(0.3, 1.5, 0.3),
			V(sx * (halfW - 0.1), ridgeTop + 0.6, 0),
			COPING,
			M.Concrete
		)
		p.box(
			"GableCross",
			V(0.3, 0.3, 1.0),
			V(sx * (halfW - 0.1), ridgeTop + 0.8, 0),
			COPING,
			M.Concrete
		)
	end
	-- The gates, on hanging posts against the walls' inner faces.
	local hang = SIDE_X - 0.6 - 0.35
	local opening = hang - 0.35
	local gates: { Model } = {}
	for _, sx in { -1, 1 } do
		p.box(
			"GatePost",
			V(0.7, 5.4 + SINK, 0.7),
			V(sx * hang, (5.4 - SINK) / 2, 0),
			Kit.weathered(oak, 0.05),
			M.Wood
		)
		fine(p.ball("GatePostCap", V(sx * hang, 5.55, 0), 0.6, oak, M.Wood))
		local h = 4.4
		local centre = V(sx * opening / 2, 0.4 + h / 2, 0)
		table.insert(
			gates,
			Kit.door(at * CFrame.new(centre, centre + V(0, 0, 1)), opening, h, {
				parent = doors,
				hinge = -sx,
				swing = 1,
				thickness = 0.3,
				color = Kit.weathered(oak, 0.05),
				panel = rgb(50, 44, 38),
				style = "plank",
				gap = 0.1,
				openAngle = 88,
				name = "LychGate",
			})
		)
	end
	return gates
end

----------------------------------------------------------------------------
-- The mausoleum
----------------------------------------------------------------------------

--[[
	A family mausoleum: a small stone temple on a plinth, two round columns
	in front under a pediment, a bronze door, and inside, the family on
	stone shelves down both walls. The door opens in and shuts again, and
	the room behind it is a hiding place.

	`at` is on the ground at its middle, looking out of its door (-Z). The
	structure goes in `parent`, the door in `doors`, the coffins and the rest
	of what is inside in `furniture`. Returns the hiding place.
]]
function Yard.mausoleum(
	at: CFrame,
	parent: Instance,
	doors: Instance,
	furniture: Instance,
	o: Options?
): Kit.HidingSpot
	local p = pen(at, parent)
	local stone = opt(o, "stone", rgb(70, 68, 64))
	local function sc(): Color3
		return Kit.weathered(stone, 0.04)
	end
	local FLOOR = 1.2
	local TOP = 10.2 -- the walls' tops
	local WX, WZ, T = 6, 6, 1.2 -- the outside of the walls, and their thickness
	local COL_Z = -8.0
	-- Plinth and step.
	p.box(
		"MausoleumPlinth",
		V(13.0, FLOOR + SINK, 16.2),
		V(0, (FLOOR - SINK) / 2, -1.1),
		sc(),
		M.Concrete
	)
	p.box("MausoleumStep", V(8.0, 0.6 + SINK, 1.2), V(0, (0.6 - SINK) / 2, -9.8), sc(), M.Concrete)
	-- Walls, the front round the door.
	local wallH = TOP - FLOOR
	local wy = (FLOOR + TOP) / 2
	p.box("MausoleumWall", V(WX * 2, wallH, T), V(0, wy, WZ - T / 2), sc(), M.Concrete)
	for _, sx in { -1, 1 } do
		p.box(
			"MausoleumWall",
			V(T, wallH, WZ * 2 - 2 * T),
			V(sx * (WX - T / 2), wy, 0),
			sc(),
			M.Concrete
		)
	end
	local doorW, doorH = 3.6, 7.0
	for _, sx in { -1, 1 } do
		local w = WX - doorW / 2
		p.box(
			"MausoleumWall",
			V(w, wallH, T),
			V(sx * (doorW / 2 + w / 2), wy, -WZ + T / 2),
			sc(),
			M.Concrete
		)
	end
	p.box(
		"MausoleumWall",
		V(doorW, TOP - FLOOR - doorH, T),
		V(0, (FLOOR + doorH + TOP) / 2, -WZ + T / 2),
		sc(),
		M.Concrete
	)
	p.box("MausoleumCeiling", V(WX * 2, 0.6, WZ * 2), V(0, TOP + 0.3, 0), sc(), M.Concrete)
	-- The name, over the door, and a carved wreath.
	for k = 0, 1 do
		fine(
			p.box(
				"Inscription",
				V(if k == 0 then 3.2 else 2.2, 0.26, 0.04),
				V(0, TOP - 0.6 - k * 0.5, -WZ - 0.02),
				CARVED,
				M.Concrete
			)
		)
	end
	-- The portico: columns, the beam over them, the cornice all round.
	for _, sx in { -1, 1 } do
		local x = sx * 3.4
		fine(p.disc("ColumnBase", V(x, FLOOR + 0.15, COL_Z), 1.6, 0.3, sc(), M.Concrete))
		p.rod("MausoleumColumn", V(x, FLOOR, COL_Z), V(x, 9.2, COL_Z), 1.1, sc(), M.Concrete)
		fine(p.disc("ColumnCapital", V(x, 9.05, COL_Z), 1.5, 0.3, sc(), M.Concrete))
		p.box("Abacus", V(1.6, 0.3, 1.6), V(x, 9.35, COL_Z), sc(), M.Concrete)
	end
	p.box("Architrave", V(12.0, 1.3, 1.6), V(0, 10.15, COL_Z), sc(), M.Concrete)
	local corniceTop = 11.5
	local front, back = COL_Z - 1.0, WZ + 0.4
	p.box(
		"MausoleumCornice",
		V(WX * 2 + 1.4, corniceTop - 10.8, back - front),
		V(0, (10.8 + corniceTop) / 2, (front + back) / 2),
		sc(),
		M.Concrete
	)
	-- A low roof of stone, a pediment at each end, urns at the corners.
	local PITCH = math.rad(22)
	local halfX = WX + 0.7
	local ridge = corniceTop + halfX * math.tan(PITCH)
	local midZ = (front + back) / 2
	for _, sx in { -1, 1 } do
		local n = V(sx * math.sin(PITCH), math.cos(PITCH), 0)
		p.beam(
			"MausoleumRoof",
			V(sx * halfX, corniceTop, midZ) + n * 0.3,
			V(0, ridge, midZ) + n * 0.3,
			back - front,
			0.6,
			n,
			Kit.weathered(ROOF_SLATE, 0.04),
			M.Slate
		)
	end
	for _, z in { front + 0.3, back - 0.3 } do
		p.tri(
			"Pediment",
			V(-halfX, corniceTop, z),
			V(halfX, corniceTop, z),
			V(0, ridge, z),
			0.6,
			sc(),
			M.Concrete
		)
	end
	for _, sx in { -1, 1 } do
		fine(
			p.rod(
				"RakingCornice",
				V(sx * (halfX + 0.1), corniceTop + 0.05, front - 0.05),
				V(0, ridge + 0.15, front - 0.05),
				0.35,
				sc(),
				M.Concrete
			)
		)
	end
	-- The corner urns stand on the slope, the middle one on the apex.
	local urns = {
		V(-halfX + 0.4, corniceTop + 0.2, front + 0.5),
		V(halfX - 0.4, corniceTop + 0.2, front + 0.5),
		V(0, ridge + 0.6, front + 0.4),
	}
	for _, pos in urns do
		p.box("UrnPlinth", V(0.8, 0.5, 0.8), pos + V(0, 0.25, 0), sc(), M.Concrete)
		p.ball("Urn", pos + V(0, 0.95, 0), 0.9, sc(), M.Concrete)
		fine(p.disc("UrnLid", pos + V(0, 1.45, 0), 0.5, 0.15, sc(), M.Concrete))
	end
	-- Inside: two stone shelves down each wall on brackets, the family on
	-- them; a marble tablet on the back wall.
	local inner = WX - T
	local shelfD = 2.4
	for _, sx in { -1, 1 } do
		for _, y in { FLOOR + 2.8, FLOOR + 5.8 } do
			p.box(
				"LoculusShelf",
				V(shelfD, 0.35, 2 * (WZ - T) - 0.2),
				V(sx * (inner - shelfD / 2), y, 0.1),
				sc(),
				M.Concrete
			)
			for _, z in { -3.4, 0, 3.4 } do
				fine(
					p.box(
						"ShelfBracket",
						V(0.4, 0.6, 0.4),
						V(sx * (inner - 0.2), y - 0.47, z),
						sc(),
						M.Concrete
					)
				)
			end
		end
	end
	fine(
		p.box(
			"Tablet",
			V(4.0, 2.4, 0.15),
			V(0, FLOOR + 4.6, WZ - T - 0.075),
			rgb(78, 76, 72),
			M.Marble
		)
	)
	for k = 0, 3 do
		fine(
			p.box(
				"Inscription",
				V(if k % 2 == 0 then 2.8 else 2.2, 0.14, 0.03),
				V(0, FLOOR + 5.3 - k * 0.45, WZ - T - 0.17),
				CARVED,
				M.Marble
			)
		)
	end
	local lids = { "on", "ajar", "on", "off" }
	local i = 0
	for _, sx in { -1, 1 } do
		for _, y in { FLOOR + 2.8, FLOOR + 5.8 } do
			i += 1
			Yard.coffin(
				at * CFrame.new(sx * (inner - 1.3), y + 0.175, 0.3),
				furniture,
				{ lid = lids[i] }
			)
		end
	end
	-- The door: bronze, in two panels, opening in.
	local centre = V(0, FLOOR + doorH / 2, -WZ + T / 2)
	Kit.door(at * CFrame.new(centre, centre + V(0, 0, -1)), doorW, doorH, {
		parent = doors,
		hinge = -1,
		swing = -1,
		thickness = 0.3,
		color = BRONZE,
		panel = rgb(48, 50, 40),
		style = "panel",
		gap = 0.1,
		openAngle = 90,
		name = "MausoleumDoor",
	})
	return Kit.hideVolume(
		"MausoleumHidingVolume",
		at * CFrame.new(0, FLOOR + 3, 1.2),
		V(4.4, 6, 6.4),
		"Cupboard",
		1,
		furniture
	)
end

----------------------------------------------------------------------------
-- The farm
----------------------------------------------------------------------------

local HAY = rgb(92, 80, 50) -- a season old, gone from gold to dun
local TWINE = rgb(60, 50, 36)
local BURLAP = rgb(84, 70, 50)
local DRY_STALK = rgb(96, 84, 56)
local DRY_LEAF = rgb(86, 78, 48)
local DARK_WATER = rgb(16, 20, 18)
Yard.HAY = HAY

--[[
	A split-rail fence from `at` along its +X for `length`: round posts every
	few studs and three rails between each pair, sagging and wandering a
	little the way old rails do, the odd one fallen. An unseen board down the
	run is what stops a player, so no gap has to.
]]
function Yard.fence(at: CFrame, length: number, parent: Instance, o: Options?)
	local h: number = opt(o, "height", 4.2)
	local wood: Color3 = opt(o, "wood", TIMBER)
	local p = pen(at, parent)
	local wear = Kit.wear()
	local posts = math.max(1, math.ceil(length / 8))
	local span = length / posts
	for i = 0, posts do
		p.rod(
			"FencePost",
			V(i * span, -SINK, 0),
			V(i * span, h + 0.3, 0),
			0.6,
			Kit.weathered(wood, 0.08),
			M.Wood
		)
	end
	for i = 0, posts - 1 do
		for k, y in { 0.3, 0.58, 0.86 } do
			if wear:NextNumber() < 0.05 then
				continue -- this one has fallen
			end
			local z = if k == 2 then 0.25 else -0.25
			p.rod(
				"FenceRail",
				V(i * span, y * h + wear:NextNumber(-0.15, 0.15), z),
				V((i + 1) * span, y * h + wear:NextNumber(-0.15, 0.15), z),
				0.34,
				Kit.weathered(wood, 0.1),
				M.Wood
			)
		end
	end
	blocker(p.box("FenceCore", V(length, h, 1.2), V(length / 2, h / 2, 0), wood, M.Wood))
end

--[[
	A five-bar field gate that opens like any door: a Door model whose Leaf
	is an unseen board the gate's timbers ride on, so it swings, collides and
	carries its prompt like a door while looking like open timber. `frame` is
	centred in the gateway and looks the way the gate opens.
]]
function Yard.barGate(
	frame: CFrame,
	width: number,
	height: number,
	parent: Instance,
	o: Options?
): Model
	local hinge: number = opt(o, "hinge", 1)
	local wood = Kit.weathered(opt(o, "wood", TIMBER), 0.06)
	local door = Kit.door(frame, width, height, {
		parent = parent,
		hinge = hinge,
		swing = 1,
		thickness = 0.35,
		style = "bare",
		gap = 0.15,
		openAngle = opt(o, "openAngle", 90),
		name = opt(o, "name", "FieldGate"),
		color = wood,
	})
	local leaf = door:FindFirstChild("Leaf") :: BasePart?
	if not leaf then
		return door
	end
	leaf.Transparency = 1
	leaf.CastShadow = false
	local cf, w, h = leaf.CFrame, leaf.Size.X, leaf.Size.Y
	local function timber(name: string, a: Vector3, b: Vector3, d: number)
		fine(Kit.rod(name, cf * a, cf * b, d, wood, M.Wood, door))
	end
	-- The stiles, the heavier one on the hinge side, the bars between them
	-- and the brace from the hinge's foot up to the latch's top.
	local hingeX, headX = hinge * (w / 2 - 0.25), -hinge * (w / 2 - 0.2)
	timber("GateStile", V(hingeX, -h / 2, 0), V(hingeX, h / 2, 0), 0.5)
	timber("GateStile", V(headX, -h / 2, 0), V(headX, h / 2 - 0.2, 0), 0.4)
	for k = 0, 4 do
		local y = -h / 2 + 0.35 + k * (h - 0.8) / 4
		timber("GateBar", V(hingeX, y, 0), V(headX, y, 0), 0.3)
	end
	timber("GateBrace", V(hingeX, -h / 2 + 0.35, 0), V(headX, h / 2 - 0.45, 0), 0.28)
	for _, d in door:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Knob" or d.Name == "Rose") then
			d.Color = IRON
		end
	end
	return door
end

--[[
	A scarecrow on its cross: a sack for a head with the face stitched on and
	tipped to one side, a hat, a coat stuffed with straw that pokes out of
	the cuffs, trousers hanging empty. It looks toward -Z.
]]
function Yard.scarecrow(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Scarecrow", at, parent)
	local wood = Kit.weathered(TIMBER, 0.08)
	local coat = Kit.weathered(rgb(52, 44, 36), 0.06)
	local hat = rgb(36, 30, 26)
	local armY = 7.2
	b.rod("ScarecrowPost", V(0, -SINK - 0.6, 0.2), V(0, 9.2, 0.2), 0.5, wood, M.Wood)
	b.rod("ScarecrowArm", V(-3.4, armY, 0.2), V(3.4, armY, 0.2), 0.4, wood, M.Wood)
	b.box("Coat", V(2.0, 3.0, 1.1), V(0, armY - 1.0, 0), coat, M.Fabric)
	fine(
		b.box(
			"CoatTail",
			V(2.2, 1.4, 0.9),
			V(0, armY - 3.1, 0.05),
			coat,
			M.Fabric,
			CFrame.Angles(0.08, 0, 0)
		)
	)
	local wear = Kit.wear()
	for _, sx in { -1, 1 } do
		fine(b.box("Sleeve", V(2.4, 0.9, 0.9), V(sx * 2.1, armY, 0.1), coat, M.Fabric))
		for k = 1, 4 do
			fine(
				b.box(
					"Straw",
					V(0.9, 0.06, 0.06),
					V(sx * 3.5, armY + wear:NextNumber(-0.3, 0.3), 0.1 + wear:NextNumber(-0.3, 0.3)),
					HAY,
					M.Grass,
					CFrame.Angles(
						0,
						wear:NextNumber(-0.5, 0.5),
						sx * wear:NextNumber(0.2, 0.9) + k * 0.1
					)
				)
			)
		end
		fine(
			b.box(
				"Trouser",
				V(0.8, 2.6, 0.8),
				V(sx * 0.5, armY - 3.6, 0),
				rgb(46, 42, 38),
				M.Fabric
			)
		)
	end
	-- The head, tipped over to one side.
	local head =
		draw(b.model, b.at * CFrame.new(0, armY + 1.7, 0) * CFrame.Angles(0, 0, math.rad(14)))
	head.ball("SackHead", V(0, 0, 0), 1.9, Kit.weathered(BURLAP, 0.05), M.Fabric)
	for _, sx in { -1, 1 } do
		for _, turn in { 0.8, -0.8 } do
			fine(
				head.box(
					"Stitch",
					V(0.36, 0.07, 0.05),
					V(sx * 0.38, 0.18, -0.88),
					CARVED,
					M.Fabric,
					CFrame.Angles(0, 0, turn)
				)
			)
		end
	end
	fine(head.box("Mouth", V(0.9, 0.08, 0.05), V(0, -0.35, -0.9), CARVED, M.Fabric))
	fine(head.disc("Twine", V(0, -0.75, 0), 1.3, 0.15, TWINE, M.Fabric))
	head.disc("HatBrim", V(0, 0.72, 0), 2.8, 0.1, hat, M.Fabric)
	head.rod("HatCrown", V(0, 0.72, 0), V(0, 1.55, 0), 1.3, hat, M.Fabric)
	return b.model
end

--[[
	A milk churn: a tall can with a rounded shoulder, a neck and a lid, two
	handles at the shoulder, a band round its foot.
]]
function Yard.churn(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("MilkChurn", at, parent)
	local metal = Kit.weathered(opt(o, "metal", rgb(66, 64, 60)), 0.06)
	b.disc("ChurnBody", V(0, 1.0, 0), 1.5, 2.0, metal, M.Metal)
	b.ball("ChurnShoulder", V(0, 2.0, 0), 1.5, metal, M.Metal)
	b.rod("ChurnNeck", V(0, 2.3, 0), V(0, 3.2, 0), 0.8, metal, M.Metal)
	fine(b.disc("ChurnLid", V(0, 3.25, 0), 1.0, 0.15, metal, M.Metal))
	fine(b.ball("ChurnKnob", V(0, 3.4, 0), 0.25, metal, M.Metal))
	for _, sx in { -1, 1 } do
		fine(
			b.rod(
				"ChurnHandle",
				V(sx * 0.6, 2.55, -0.2),
				V(sx * 0.6, 2.55, 0.2),
				0.12,
				IRON,
				M.Metal
			)
		)
	end
	fine(b.disc("ChurnBand", V(0, 0.15, 0), 1.6, 0.25, metal, M.Metal))
	return b.model
end

--[[
	A bale of hay: a block tied with two twines, or `round`, a roll lying on
	its side with its axis along X.
]]
function Yard.hayBale(at: CFrame, parent: Instance, o: Options?): Model
	local hay = Kit.weathered(opt(o, "hay", HAY), 0.08)
	if opt(o, "round", false) then
		local b = begin("RoundBale", at, parent)
		local d: number = opt(o, "diameter", 5)
		local w: number = opt(o, "width", 4.6)
		b.rod("RoundBale", V(-w / 2, d / 2, 0), V(w / 2, d / 2, 0), d, hay, M.Grass)
		local face = Color3.new(hay.R * 0.8, hay.G * 0.8, hay.B * 0.8)
		for _, x in { -w / 2 - 0.02, w / 2 + 0.02 } do
			fine(b.disc("BaleEnd", V(x, d / 2, 0), d * 0.8, 0.04, face, M.Grass, SIDEWAYS))
		end
		return b.model
	end
	local b = begin("HayBale", at, parent)
	local L, W, H = 3.4, 1.8, 1.5
	b.box("HayBale", V(L, H, W), V(0, H / 2, 0), hay, M.Grass)
	for _, x in { -L / 4, L / 4 } do
		fine(b.box("Twine", V(0.08, H + 0.04, W + 0.04), V(x, H / 2, 0), TWINE, M.Fabric))
	end
	return b.model
end

--[[
	Bales stacked `cols` along X, `rows` deep and `layers` high, none quite
	square on the one below, the top course short a few. Twine shows only on
	the bales whose faces can be seen.
]]
function Yard.hayStack(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("HayStack", at, parent)
	local cols: number = opt(o, "cols", 3)
	local rows: number = opt(o, "rows", 2)
	local layers: number = opt(o, "layers", 3)
	local L, W, H = 3.4, 1.8, 1.5
	local wear = Kit.wear()
	for k = 0, layers - 1 do
		for i = 0, cols - 1 do
			for j = 0, rows - 1 do
				if k == layers - 1 and k > 0 and wear:NextNumber() < 0.3 then
					continue
				end
				local pos = V((i - (cols - 1) / 2) * L, k * H + H / 2, (j - (rows - 1) / 2) * W)
				local yaw = CFrame.Angles(0, wear:NextNumber(-0.04, 0.04), 0)
				b.box(
					"HayBale",
					V(L - 0.06, H - 0.02, W - 0.06),
					pos,
					Kit.weathered(HAY, 0.08),
					M.Grass,
					yaw
				)
				if j == 0 or k == layers - 1 then
					for _, x in { -L / 4, L / 4 } do
						fine(
							b.box(
								"Twine",
								V(0.08, H, W - 0.02),
								pos + V(x, 0.01, 0),
								TWINE,
								M.Fabric,
								yaw
							)
						)
					end
				end
			end
		end
	end
	return b.model
end

--[[
	A hay wagon: a flat bed on four spoked wheels, big at the back, ladder
	racks at the ends, a tongue down on the ground out front, old hay on it.
	There is room to crawl under the bed between the axles: a hiding place.
	It runs along Z with the tongue toward -Z.
]]
function Yard.wagon(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot)
	local b = begin("HayWagon", at, parent)
	local wood = Kit.weathered(TIMBER, 0.06)
	local L, W, bedY = 11, 5.2, 3.6
	local rearZ, frontZ = L / 2 - 2.2, -L / 2 + 2.0
	local function wheel(x: number, z: number, d: number)
		local hub = V(x, d / 2, z)
		local r = d / 2 - 0.15
		local n = 12
		for k = 0, n - 1 do
			local a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
			fine(
				b.rod(
					"WheelRim",
					hub + V(0, r * math.cos(a0), r * math.sin(a0)),
					hub + V(0, r * math.cos(a1), r * math.sin(a1)),
					0.3,
					wood,
					M.Wood
				)
			)
		end
		for k = 0, 7 do
			local a = 2 * math.pi * k / 8
			fine(
				b.rod(
					"WheelSpoke",
					hub,
					hub + V(0, (r - 0.1) * math.cos(a), (r - 0.1) * math.sin(a)),
					0.16,
					wood,
					M.Wood
				)
			)
		end
		b.disc("WheelHub", hub, 0.8, 0.7, IRON, M.Metal, SIDEWAYS)
	end
	for _, sx in { -1, 1 } do
		wheel(sx * (W / 2 + 0.35), rearZ, 4.4)
		wheel(sx * (W / 2 + 0.35), frontZ, 3.4)
	end
	for _, axle in { { z = rearZ, y = 2.2 }, { z = frontZ, y = 1.7 } } do
		b.rod(
			"Axle",
			V(-W / 2 - 0.35, axle.y, axle.z),
			V(W / 2 + 0.35, axle.y, axle.z),
			0.4,
			IRON,
			M.Metal
		)
		b.box(
			"Bolster",
			V(W - 0.4, bedY - 0.4 - (axle.y + 0.2), 0.6),
			V(0, (axle.y + 0.2 + bedY - 0.4) / 2, axle.z),
			wood,
			M.Wood
		)
	end
	b.box("WagonBed", V(W, 0.4, L), V(0, bedY - 0.2, 0), wood, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		b.box(
			"WagonSide",
			V(0.25, 0.9, L),
			V(sx * (W / 2 - 0.125), bedY + 0.45, 0),
			wood,
			M.WoodPlanks
		)
	end
	for _, sz in { -1, 1 } do
		local z = sz * (L / 2 - 0.2)
		for _, sx in { -1, 1 } do
			fine(
				b.rod(
					"RackPost",
					V(sx * (W / 2 - 0.3), bedY, z),
					V(sx * (W / 2 - 0.1), bedY + 4.2, z),
					0.3,
					wood,
					M.Wood
				)
			)
		end
		for k = 1, 3 do
			fine(
				b.rod(
					"RackRung",
					V(-(W / 2 - 0.2), bedY + k * 1.3, z),
					V(W / 2 - 0.2, bedY + k * 1.3, z),
					0.22,
					wood,
					M.Wood
				)
			)
		end
	end
	b.rod("Tongue", V(0, 1.7, frontZ), V(0, 0.25, -L / 2 - 6), 0.4, wood, M.Wood)
	fine(
		b.rod(
			"Whiffletree",
			V(-1.6, 0.35, -L / 2 - 5.2),
			V(1.6, 0.35, -L / 2 - 5.2),
			0.3,
			wood,
			M.Wood
		)
	)
	-- What is left of the last load.
	local wear = Kit.wear()
	for k, pos in { V(-1.1, bedY + 0.75, 2.6), V(1.1, bedY + 0.75, 2.4), V(0.2, bedY + 2.25, 2.5) } do
		local yaw =
			CFrame.Angles(0, math.pi / 2 + wear:NextNumber(-0.1, 0.1), if k == 3 then 0.08 else 0)
		b.box("HayBale", V(3.4, 1.5, 1.8), pos, Kit.weathered(HAY, 0.08), M.Grass, yaw)
	end
	b.box(
		"LooseHay",
		V(3.8, 0.8, 3.0),
		V(0, bedY + 0.4, -2.4),
		Kit.weathered(HAY, 0.1),
		M.Grass,
		CFrame.Angles(0, 0.3, 0.05)
	)
	local spot = Kit.hideVolume(
		"UnderWagonHidingVolume",
		at * CFrame.new(0, 1.3, (rearZ + frontZ) / 2),
		V(W - 1, 2.2, rearZ - frontZ - 1.4),
		"UnderTable",
		1,
		b.model
	)
	return b.model, spot
end

--[[
	A cast-iron pump behind a stone trough: the barrel and its cap, a spout
	out over the water and the long handle left raised. The water in the
	trough is black and does not move.
]]
function Yard.pumpTrough(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("PumpAndTrough", at, parent)
	local stone = Kit.weathered(rgb(74, 72, 68), 0.05)
	local L, W, H = 7, 2.6, 2.2
	local tz = -1.95
	b.box("TroughBottom", V(L, 0.4 + SINK, W), V(0, (0.4 - SINK) / 2, tz), stone, M.Concrete)
	for _, sx in { -1, 1 } do
		b.box(
			"TroughEnd",
			V(0.4, H + SINK, W),
			V(sx * (L / 2 - 0.2), (H - SINK) / 2, tz),
			stone,
			M.Concrete
		)
	end
	for _, sz in { -1, 1 } do
		b.box(
			"TroughSide",
			V(L - 0.8, H + SINK, 0.4),
			V(0, (H - SINK) / 2, tz + sz * (W / 2 - 0.2)),
			stone,
			M.Concrete
		)
	end
	fine(b.box("TroughWater", V(L - 0.8, 0.05, W - 0.8), V(0, H - 0.5, tz), DARK_WATER, M.Glass))
	local iron = Kit.weathered(IRON, 0.06)
	b.disc("PumpBase", V(0, 0.2, 0), 1.3, 0.4, iron, M.Metal)
	b.rod("PumpBarrel", V(0, 0.2, 0), V(0, 4.4, 0), 0.8, iron, M.Metal)
	fine(b.disc("PumpCap", V(0, 4.5, 0), 1.0, 0.25, iron, M.Metal))
	fine(b.ball("PumpFinial", V(0, 4.75, 0), 0.4, iron, M.Metal))
	fine(b.rod("PumpSpout", V(0, 3.4, -0.3), V(0, 3.0, -1.7), 0.3, iron, M.Metal))
	fine(b.rod("PumpBracket", V(0, 4.3, 0.3), V(0, 4.9, 0.7), 0.2, iron, M.Metal))
	fine(b.rod("PumpHandle", V(0, 4.9, 0.7), V(0, 6.2, 3.2), 0.22, iron, M.Metal))
	fine(b.ball("PumpHandleEnd", V(0, 6.2, 3.2), 0.35, iron, M.Metal))
	return b.model
end

--[[
	A well gone dry: a round stone parapet, the shaft under it lined with the
	same stone down to a floor of mud, and bones on the mud. Two posts carry
	a little roof and the windlass, its rope run out into the shaft to the
	bucket. The shaft is a GroundCut, dug by Groundwork, and shallow enough
	that anyone who climbs in can jump back out.
]]
function Yard.well(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Well", at, parent)
	local stone: Color3 = opt(o, "stone", WALL_STONE)
	local r, n = 2.2, 12
	local top, bottom = 2.4, -3.6
	unseen(b.box("GroundCut", V(6.4, 5.2, 6.4), V(0, -2.0, 0), EARTH, M.Ground))
	local chord = 2 * (r + 0.3) * math.sin(math.pi / n) + 0.1
	for k = 0, n - 1 do
		local a = 2 * math.pi * k / n
		local d = V(math.cos(a), 0, math.sin(a))
		b.box(
			"WellStone",
			V(chord, top - bottom, 0.6),
			d * (r + 0.3) + V(0, (top + bottom) / 2, 0),
			Kit.weathered(stone, 0.06),
			M.Cobblestone,
			CFrame.new(Vector3.zero, d)
		)
	end
	b.box("Mud", V(2 * r, 0.3, 2 * r), V(0, bottom - 0.15, 0), rgb(34, 28, 22), M.Ground)
	fine(b.ball("Skull", V(0.5, bottom + 0.35, -0.3), 0.7, C.BONE, M.SmoothPlastic))
	fine(b.box("Jaw", V(0.45, 0.15, 0.4), V(0.5, bottom + 0.1, -0.62), C.BONE, M.SmoothPlastic))
	fine(
		b.rod(
			"Bone",
			V(-1.0, bottom + 0.1, 0.4),
			V(0.4, bottom + 0.12, 1.1),
			0.2,
			C.BONE,
			M.SmoothPlastic
		)
	)
	fine(
		b.rod(
			"Bone",
			V(-0.6, bottom + 0.12, -1.0),
			V(0.3, bottom + 0.1, -0.2),
			0.2,
			C.BONE,
			M.SmoothPlastic
		)
	)
	-- The posts, the windlass and its crank, the rope and the bucket.
	local postX = r + 0.9
	for _, sx in { -1, 1 } do
		b.rod("WellPost", V(sx * postX, -SINK, 0), V(sx * postX, 6.4, 0), 0.5, TIMBER, M.Wood)
	end
	fine(b.rod("Windlass", V(-postX, 4.4, 0), V(postX, 4.4, 0), 0.5, TIMBER, M.Wood))
	fine(b.rod("Crank", V(postX + 0.3, 4.4, 0), V(postX + 0.3, 3.6, 0.3), 0.14, IRON, M.Metal))
	fine(b.rod("Crank", V(postX + 0.3, 3.6, 0.3), V(postX + 0.9, 3.6, 0.3), 0.18, TIMBER, M.Wood))
	fine(b.rod("WellRope", V(0.3, 4.2, 0), V(0.3, 1.3, 0), 0.1, TWINE, M.Fabric))
	fine(b.disc("Bucket", V(0.3, 0.8, 0), 0.9, 1.0, TIMBER, M.WoodPlanks))
	-- A little roof over it, two slopes of boards.
	local ridge, eave, half = 7.6, 6.1, 2.4
	local slope = math.atan((ridge - eave) / half)
	for _, sz in { -1, 1 } do
		b.box(
			"WellRoof",
			V(2 * postX + 1.4, 0.25, math.sqrt(half * half + (ridge - eave) ^ 2) + 0.2),
			V(0, (ridge + eave) / 2 + 0.12, sz * half / 2),
			Kit.weathered(TIMBER, 0.08),
			M.WoodPlanks,
			CFrame.Angles(sz * slope, 0, 0)
		)
	end
	fine(
		b.rod(
			"WellRidge",
			V(-postX - 0.7, ridge + 0.2, 0),
			V(postX + 0.7, ridge + 0.2, 0),
			0.4,
			TIMBER,
			M.Wood
		)
	)
	return b.model
end

--[[
	A cow's skull, the kind nailed up on a gatepost. Its pivot is where it
	sits on the post top, and it looks toward -Z.
]]
function Yard.cowSkull(at: CFrame, parent: Instance): Model
	local b = begin("CowSkull", at, parent)
	local bone = Kit.weathered(C.BONE, 0.05)
	fine(b.ball("Cranium", V(0, 0.45, 0.1), 0.9, bone, M.SmoothPlastic))
	fine(
		b.box(
			"Snout",
			V(0.5, 0.45, 1.3),
			V(0, 0.3, -0.6),
			bone,
			M.SmoothPlastic,
			CFrame.Angles(-0.25, 0, 0)
		)
	)
	for _, sx in { -1, 1 } do
		fine(
			b.disc(
				"EyeSocket",
				V(sx * 0.28, 0.55, -0.32),
				0.3,
				0.05,
				CARVED,
				M.SmoothPlastic,
				UPRIGHT
			)
		)
		fine(
			b.rod(
				"Horn",
				V(sx * 0.35, 0.7, 0.15),
				V(sx * 1.0, 0.9, 0.1),
				0.22,
				bone,
				M.SmoothPlastic
			)
		)
		fine(
			b.rod(
				"Horn",
				V(sx * 1.0, 0.9, 0.1),
				V(sx * 1.25, 1.35, -0.05),
				0.16,
				bone,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

--[[
	A row of dead corn from `at` along its +X for `length`: tall dry stalks
	in two staggered lines with leaves hanging off them, and an unseen board
	down the row so nobody walks through it. What a maze is made of.
]]
function Yard.cornRow(at: CFrame, length: number, parent: Instance, o: Options?)
	local p = pen(at, parent)
	local rng = Random.new(opt(o, "seed", 1))
	local h: number = opt(o, "height", 9)
	local n = math.max(2, math.floor(length / 1.5))
	for i = 0, n - 1 do
		local x = (i + 0.5) * length / n + rng:NextNumber(-0.2, 0.2)
		local z = (if i % 2 == 0 then -0.35 else 0.35) + rng:NextNumber(-0.1, 0.1)
		local foot = V(x, -0.3, z)
		local tip = V(
			x + rng:NextNumber(-0.4, 0.4),
			h * rng:NextNumber(0.8, 1.1),
			z + rng:NextNumber(-0.4, 0.4)
		)
		fine(p.rod("CornStalk", foot, tip, 0.24, Kit.weathered(DRY_STALK, 0.1), M.Grass))
		-- Two leaves on opposite sides, each out from the stalk and hanging,
		-- the way dead corn leaves do.
		local yaw = rng:NextNumber(0, 2 * math.pi)
		for k = 1, 2 do
			local from = foot:Lerp(
				tip,
				if k == 1 then rng:NextNumber(0.35, 0.5) else rng:NextNumber(0.6, 0.78)
			)
			local a = yaw + (k - 1) * math.pi
			local droop = rng:NextNumber(0.35, 0.85)
			local out =
				V(math.cos(a) * math.cos(droop), -math.sin(droop), math.sin(a) * math.cos(droop))
			local len = rng:NextNumber(2.0, 2.8)
			fine(
				p.box(
					"CornLeaf",
					V(len, 0.05, 0.42),
					from + out * (len / 2),
					Kit.weathered(DRY_LEAF, 0.12),
					M.Grass,
					CFrame.fromMatrix(Vector3.zero, out, (Vector3.yAxis - out * out.Y).Unit)
				)
			)
		end
		-- The tassel on top of every other stalk, and an ear left on some.
		if i % 2 == 0 then
			fine(
				p.rod(
					"CornTassel",
					tip,
					tip + V(rng:NextNumber(-0.3, 0.3), 1.0, rng:NextNumber(-0.3, 0.3)),
					0.1,
					Kit.weathered(DRY_STALK, 0.1),
					M.Grass
				)
			)
		end
		if rng:NextNumber() < 0.3 then
			local from = foot:Lerp(tip, 0.5)
			local a = yaw + math.pi / 2
			fine(
				p.rod(
					"CornEar",
					from,
					from + V(math.cos(a) * 0.5, 0.8, math.sin(a) * 0.5),
					0.36,
					Kit.weathered(rgb(90, 74, 44), 0.1),
					M.Grass
				)
			)
		end
	end
	blocker(p.box("CornCore", V(length, h, 1.3), V(length / 2, h / 2, 0), DRY_STALK, M.Grass))
end

return Yard
