--!strict
--[[
	Furniture for the code-built houses.

	Every piece is its own Model tagged "Furniture", with its pivot on the
	floor in the middle of its footprint, so in Studio it can be picked up,
	turned and dropped somewhere else like anything placed by hand.

	Pieces are drawn in their own space: origin on the floor at the centre of
	the footprint, +Y up, and the front — where you sit, or the doors — facing
	-Z, which is the CFrame's LookVector. A caller passes the world CFrame of
	that origin and nothing else about the room.

	The rule for every piece: nothing square that would be turned or rolled in
	the real thing. Legs are turned, with bulbs and collars and ball feet;
	cushions and arms are rolled; rails and posts are round; knobs are balls.
	A room full of boxes reads as a room full of crates, which is exactly what
	this replaces.

	Collision is kept to the parts that should stop a player — seats, tops,
	carcasses, doors. Legs, knobs, rolls and ornaments are `Kit.detail`, so a
	chair is something you bump into rather than something you snag on.

	Sizes are for a five-stud character in rooms with thirteen-stud ceilings:
	a little larger than life, like the rooms.
]]

local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.HouseKit)

local C = Kit.C
local M = Enum.Material
local V = Vector3.new
local fine = Kit.detail
local soft = Kit.soft

local Furnish = {}

export type Builder = {
	model: Model,
	at: CFrame,
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
}

export type Options = { [string]: any }

--[[
	Drawing functions that put parts into `model` at coordinates in the frame
	`at`. `begin` uses it for a new piece; a piece can also call it again
	with a frame of its own for a part of itself that is turned as a whole,
	like a headstone leaning on its foot.
]]
function Furnish.draw(model: Model, at: CFrame): Builder
	local b: Builder = {
		model = model,
		at = at,
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
				model
			)
		end,
		rod = function(
			n: string,
			a: Vector3,
			bb: Vector3,
			d: number,
			color: Color3,
			material: Enum.Material
		): Part
			return Kit.rod(n, at * a, at * bb, d, color, material, model)
		end,
		ball = function(
			n: string,
			p: Vector3,
			d: number,
			color: Color3,
			material: Enum.Material
		): Part
			return Kit.ball(n, at * p, d, color, material, model)
		end,
		disc = function(
			n: string,
			p: Vector3,
			d: number,
			thickness: number,
			color: Color3,
			material: Enum.Material,
			tilt: CFrame?
		): Part
			return Kit.disc(
				n,
				at * CFrame.new(p) * (tilt or CFrame.identity),
				d,
				thickness,
				color,
				material,
				model
			)
		end,
		tri = function(
			n: string,
			a: Vector3,
			bb: Vector3,
			c: Vector3,
			thickness: number,
			color: Color3,
			material: Enum.Material
		)
			Kit.triangle(n, at * a, at * bb, at * c, thickness, color, material, model)
		end,
	}
	return b
end

--[[
	Start a piece: a Model with its pivot on the floor at `at`, and drawing
	functions that take coordinates in the piece's own space.
]]
function Furnish.begin(name: string, at: CFrame, parent: Instance): Builder
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = at
	CollectionService:AddTag(model, "Furniture")
	model.Parent = parent
	return Furnish.draw(model, at)
end

local begin = Furnish.begin

--[[
	Slide a finished piece along its own facing until its rearmost point is
	exactly `clearance` in front of its pivot. Built with the pivot on a
	wall's structural face, a piece then stands clear of the skirting, rail
	and paper, whatever its depth or shape, and nobody has to know how deep
	each piece is to place it. Invisible parts (hiding volumes) move with the
	piece but do not count toward its back.
]]
function Furnish.backTo(model: Model, clearance: number): Model
	local at = model.WorldPivot
	local back = -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = at:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			local reach = math.abs(cf.RightVector.Z) * h.X
				+ math.abs(cf.UpVector.Z) * h.Y
				+ math.abs(cf.LookVector.Z) * h.Z
			back = math.max(back, cf.Position.Z + reach)
		end
	end
	if back == -math.huge then
		return model
	end
	local shift = at.LookVector * (back + clearance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame += shift
		elseif d:IsA("Model") then
			d.WorldPivot += shift
		end
	end
	model.WorldPivot = at + shift
	return model
end

local function opt(o: Options?, key: string, default: any): any
	if o and o[key] ~= nil then
		return o[key]
	end
	return default
end

--[[
	A turned leg from the floor to `top`: a round shaft with a bulb a third of
	the way up, a collar under the top and a ball foot. The shape every
	Victorian table and chair leg is some variation of.
]]
local function turnedLeg(b: Builder, x: number, z: number, top: number, d: number, color: Color3)
	fine(b.rod("Leg", V(x, 0.2, z), V(x, top, z), d, color, M.Wood))
	fine(b.ball("LegBulb", V(x, top * 0.34, z), d * 1.55, color, M.Wood))
	fine(b.disc("LegCollar", V(x, top - 0.55, z), d * 1.45, 0.22, color, M.Wood))
	fine(b.ball("LegFoot", V(x, 0.26, z), d * 1.15, color, M.Wood))
end
Furnish.turnedLeg = turnedLeg

-- A knob: a ball on a short neck, on a face looking along `out` (local).
local function knob(b: Builder, p: Vector3, out: Vector3, color: Color3?)
	local c = color or C.BRASS
	fine(b.rod("KnobNeck", p, p + out * 0.18, 0.12, c, M.Metal))
	fine(b.ball("Knob", p + out * 0.24, 0.26, c, M.Metal))
end
Furnish.knob = knob

----------------------------------------------------------------------------
-- Seating
----------------------------------------------------------------------------

function Furnish.diningChair(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("DiningChair", at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local cloth: Color3 = opt(o, "seat", C.VELVET)
	local W, D, seatY = 2.2, 2.1, 2.4

	b.box("Seat", V(W, 0.3, D), V(0, seatY - 0.15, 0), wood, M.Wood)
	fine(b.box("Cushion", V(W - 0.25, 0.26, D - 0.35), V(0, seatY + 0.12, -0.08), cloth, M.Fabric))
	fine(
		b.rod(
			"CushionRoll",
			V(-(W - 0.25) / 2, seatY + 0.12, -D / 2 + 0.1),
			V((W - 0.25) / 2, seatY + 0.12, -D / 2 + 0.1),
			0.28,
			cloth,
			M.Fabric
		)
	)

	for _, side in { -1, 1 } do
		local x = side * (W / 2 - 0.2)
		fine(
			b.rod("Leg", V(x, 0, -D / 2 + 0.2), V(x, seatY - 0.3, -D / 2 + 0.2), 0.3, wood, M.Wood)
		)
		fine(b.ball("LegKnop", V(x, 1.25, -D / 2 + 0.2), 0.44, wood, M.Wood))
		-- Back posts carry on up from the back legs, raked a little.
		fine(b.rod("Post", V(x, 0, D / 2 - 0.2), V(x, 5.1, D / 2 + 0.14), 0.32, wood, M.Wood))
		fine(b.ball("Finial", V(x, 5.22, D / 2 + 0.15), 0.42, wood, M.Wood))
		fine(
			b.rod("Stretcher", V(x, 0.7, -D / 2 + 0.2), V(x, 0.7, D / 2 - 0.2), 0.18, wood, M.Wood)
		)
	end

	local rake = CFrame.Angles(math.rad(3.6), 0, 0)
	b.box("TopRail", V(W - 0.3, 0.5, 0.18), V(0, 4.75, D / 2 + 0.11), wood, M.Wood, rake)
	fine(b.box("Splat", V(0.75, 1.75, 0.14), V(0, 3.55, D / 2 + 0.03), wood, M.Wood, rake))
	fine(b.box("MidRail", V(W - 0.3, 0.22, 0.16), V(0, 2.75, D / 2 - 0.12), wood, M.Wood))
	return b.model
end

--[[
	A chair knocked over on its back: the same chair, laid down. Somebody left
	the table in a hurry.
]]
function Furnish.toppledChair(at: CFrame, parent: Instance, o: Options?): Model
	-- Tipped backwards about the rear edge of the back feet (z = 1.01, where
	-- the round posts meet the floor behind) until the finials rest on the
	-- floor, at 85.6 degrees: the seat front comes up, the legs stick out
	-- level, and the back lies along the floor behind. Turning about the
	-- feet's centre instead sinks their back edge into the boards.
	local tipped = at
		* CFrame.new(0, 0, 1.01)
		* CFrame.Angles(math.rad(85.6), 0, 0)
		* CFrame.new(0, 0, -1.01)
	local m = Furnish.diningChair(tipped, parent, o)
	m.Name = "ToppledChair"
	m.WorldPivot = at
	return m
end

function Furnish.armchair(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Armchair", at, parent)
	local cover: Color3 = opt(o, "cover", C.LEATHER)
	local mat: Enum.Material = opt(o, "material", M.Leather)
	local wood = C.WALNUT

	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod(
					"Foot",
					V(x * 1.4, 0.1, z * 1.2),
					V(x * 1.4, 0.6, z * 1.2),
					0.34,
					wood,
					M.Wood
				)
			)
			fine(b.ball("BunFoot", V(x * 1.4, 0.2, z * 1.2), 0.42, wood, M.Wood))
		end
	end
	b.box("Base", V(3.4, 1.1, 3.0), V(0, 1.1, 0.1), cover, mat)
	b.box("Cushion", V(2.4, 0.5, 2.3), V(0, 1.9, -0.15), cover, mat)
	fine(b.rod("CushionRoll", V(-1.2, 1.9, -1.3), V(1.2, 1.9, -1.3), 0.5, cover, mat))

	for _, x in { -1, 1 } do
		b.box("Arm", V(0.5, 1.2, 2.7), V(x * 1.45, 2.15, 0.05), cover, mat)
		fine(b.rod("ArmRoll", V(x * 1.5, 2.8, -1.35), V(x * 1.5, 2.8, 1.25), 0.74, cover, mat))
		b.box("Wing", V(0.4, 1.9, 1.3), V(x * 1.5, 4.15, 0.8), cover, mat)
		fine(b.rod("WingRoll", V(x * 1.52, 5.05, 0.15), V(x * 1.52, 5.05, 1.4), 0.5, cover, mat))
	end
	b.box("Back", V(3.2, 3.6, 0.6), V(0, 3.4, 1.3), cover, mat)
	fine(b.rod("BackRoll", V(-1.62, 5.2, 1.3), V(1.62, 5.2, 1.3), 0.72, cover, mat))
	fine(
		b.box(
			"BackCushion",
			V(2.3, 2.2, 0.5),
			V(0, 3.15, 0.8),
			cover,
			mat,
			CFrame.Angles(math.rad(8), 0, 0)
		)
	)
	return b.model
end

function Furnish.sofa(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Sofa", at, parent)
	local cover: Color3 = opt(o, "cover", C.LEATHER)
	local mat: Enum.Material = opt(o, "material", M.Leather)
	local W: number = opt(o, "width", 7.6)
	local wood = C.WALNUT
	local inner = W - 1.6

	for _, x in { -W / 2 + 0.5, 0, W / 2 - 0.5 } do
		for _, z in { -1.2, 1.2 } do
			fine(b.ball("BunFoot", V(x, 0.24, z), 0.5, wood, M.Wood))
		end
	end
	b.box("Base", V(W, 1.1, 3.1), V(0, 1.05, 0.1), cover, mat)
	for i = 0, 2 do
		local x = -inner / 2 + inner * (i + 0.5) / 3
		b.box("Cushion", V(inner / 3 - 0.08, 0.5, 2.3), V(x, 1.85, -0.2), cover, mat)
		fine(
			b.rod(
				"CushionRoll",
				V(x - inner / 6 + 0.04, 1.85, -1.35),
				V(x + inner / 6 - 0.04, 1.85, -1.35),
				0.5,
				cover,
				mat
			)
		)
	end
	-- Chesterfield: the arms roll over at the height of the back.
	for _, x in { -1, 1 } do
		b.box("Arm", V(0.8, 2.3, 3.1), V(x * (W / 2 - 0.4), 2.2, 0.1), cover, mat)
		fine(
			b.rod(
				"ArmRoll",
				V(x * (W / 2 - 0.4), 3.4, -1.45),
				V(x * (W / 2 - 0.4), 3.4, 1.6),
				1.05,
				cover,
				mat
			)
		)
	end
	b.box("Back", V(inner, 2.6, 0.7), V(0, 2.9, 1.25), cover, mat)
	fine(b.rod("BackRoll", V(-W / 2 + 0.4, 4.2, 1.25), V(W / 2 - 0.4, 4.2, 1.25), 0.85, cover, mat))
	-- Deep buttons across the back.
	for row = 0, 1 do
		for col = 0, 5 do
			local x = -inner / 2 + inner * (col + 0.5 + (row % 2) * 0.5) / 6.5
			fine(b.ball("Button", V(x, 2.75 + row * 0.8, 0.88), 0.2, C.LEATHER_DARK, mat))
		end
	end
	return b.model
end

function Furnish.stool(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Stool", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local h: number = opt(o, "height", 2.4)
	b.disc("Seat", V(0, h - 0.15, 0), 1.9, 0.3, wood, M.Wood)
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		local foot = V(math.cos(a) * 0.95, 0, math.sin(a) * 0.95)
		local head = V(math.cos(a) * 0.5, h - 0.3, math.sin(a) * 0.5)
		fine(b.rod("Leg", foot, head, 0.24, wood, M.Wood))
	end
	fine(b.disc("Ring", V(0, 0.8, 0), 1.3, 0.12, wood, M.Wood))
	return b.model
end

function Furnish.bench(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Bench", at, parent)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local L: number = opt(o, "length", 10)
	b.box("Seat", V(L, 0.45, 1.8), V(0, 2.2, 0), wood, M.WoodPlanks)
	fine(b.rod("SeatEdge", V(-L / 2, 2.2, -0.9), V(L / 2, 2.2, -0.9), 0.45, wood, M.Wood))
	for _, x in { -L / 2 + 0.9, L / 2 - 0.9 } do
		-- Splayed round legs, as a log bench has.
		for _, z in { -0.55, 0.55 } do
			fine(
				b.rod(
					"Leg",
					V(x + math.sign(x) * 0.35, 0, z * 1.5),
					V(x, 2.0, z),
					0.42,
					wood,
					M.Wood
				)
			)
		end
	end
	fine(b.rod("Stretcher", V(-L / 2 + 1.1, 0.8, 0), V(L / 2 - 1.1, 0.8, 0), 0.3, wood, M.Wood))
	return b.model
end

--[[
	A rocking chair. Left rocked forward a little, as if someone got out of it
	a moment ago; the rockers are curved, laid as short straight segments
	along an arc.
]]
function Furnish.rockingChair(at: CFrame, parent: Instance, o: Options?): Model
	-- Rocked about the centre of the rockers' arc, which keeps the arc
	-- touching the floor at whatever angle it is left at.
	local tilt: number = opt(o, "tilt", 6)
	local R = 7
	local rocked = at
		* CFrame.new(0, R + 0.15, 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
		* CFrame.new(0, -(R + 0.15), 0)
	local b = begin("RockingChair", rocked, parent)
	b.model.WorldPivot = at
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local seatY = 2.4

	-- Rockers: an arc of radius R under each side.
	for _, x in { -1.05, 1.05 } do
		local prev: Vector3? = nil
		for k = -3, 3 do
			local a = math.rad(k * 5.5)
			local p = V(x, R - R * math.cos(a) + 0.15, R * math.sin(a))
			if prev then
				fine(b.rod("Rocker", prev, p, 0.3, wood, M.Wood))
			end
			prev = p
		end
	end
	b.box("Seat", V(2.3, 0.3, 2.2), V(0, seatY - 0.15, 0), wood, M.Wood)
	for _, x in { -1, 1 } do
		fine(
			b.rod("Leg", V(x * 1.05, 0.2, -0.9), V(x * 1.0, seatY - 0.3, -0.85), 0.28, wood, M.Wood)
		)
		fine(b.rod("Leg", V(x * 1.05, 0.2, 0.9), V(x * 1.0, seatY - 0.3, 0.9), 0.28, wood, M.Wood))
		fine(b.rod("Post", V(x * 1.0, seatY - 0.3, 0.9), V(x * 1.0, 6.2, 1.5), 0.3, wood, M.Wood))
		fine(b.ball("Finial", V(x * 1.0, 6.35, 1.52), 0.4, wood, M.Wood))
		-- Arms, round, from the back post to a front spindle.
		fine(b.rod("Arm", V(x * 1.15, 3.9, 1.1), V(x * 1.2, 3.8, -1.0), 0.3, wood, M.Wood))
		fine(
			b.rod(
				"ArmSpindle",
				V(x * 1.1, seatY, -0.85),
				V(x * 1.2, 3.8, -0.95),
				0.22,
				wood,
				M.Wood
			)
		)
	end
	-- A spindle back.
	for i = -2, 2 do
		fine(b.rod("Spindle", V(i * 0.36, seatY, 0.95), V(i * 0.36, 5.8, 1.42), 0.16, wood, M.Wood))
	end
	b.box(
		"TopRail",
		V(2.2, 0.5, 0.2),
		V(0, 5.9, 1.45),
		wood,
		M.Wood,
		CFrame.Angles(math.rad(6), 0, 0)
	)
	return b.model
end

----------------------------------------------------------------------------
-- Tables
----------------------------------------------------------------------------

--[[
	The long dining table.

	Tall enough (four studs to the top, three and a half clear underneath)
	that a crouching player fits under it, and with a cloth that hangs most of
	the way to the floor on every side, so from across the room a player under
	it is a shape behind a curtain. The space under it is a tagged hiding
	place. The cloth never collides: a player walks in through it.

	The top has rounded edges and rounded corners, the legs are turned, and
	the cloth hangs in folds.
]]
function Furnish.diningTable(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin(opt(o, "name", "DiningTable"), at, parent)
	local L: number = opt(o, "length", 24)
	local W: number = opt(o, "width", 6)
	local H: number = opt(o, "height", 4.0)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local cloth: Color3? = opt(o, "cloth", nil)
	local drop: number = opt(o, "drop", H - 0.8)
	local topT = 0.36

	b.box("Top", V(L - topT, topT, W - topT), V(0, H - topT / 2, 0), wood, M.Wood)
	for _, z in { -1, 1 } do
		fine(
			b.rod(
				"TopEdge",
				V(-(L - topT) / 2, H - topT / 2, z * (W - topT) / 2),
				V((L - topT) / 2, H - topT / 2, z * (W - topT) / 2),
				topT,
				wood,
				M.Wood
			)
		)
	end
	for _, x in { -1, 1 } do
		fine(
			b.rod(
				"TopEdge",
				V(x * (L - topT) / 2, H - topT / 2, -(W - topT) / 2),
				V(x * (L - topT) / 2, H - topT / 2, (W - topT) / 2),
				topT,
				wood,
				M.Wood
			)
		)
		for _, z in { -1, 1 } do
			fine(
				b.ball(
					"TopCorner",
					V(x * (L - topT) / 2, H - topT / 2, z * (W - topT) / 2),
					topT,
					wood,
					M.Wood
				)
			)
		end
	end

	-- Apron under the top.
	local apronY = H - topT - 0.35
	for _, z in { -1, 1 } do
		b.box("Apron", V(L - 1.4, 0.7, 0.2), V(0, apronY, z * (W / 2 - 0.55)), wood, M.Wood)
	end
	for _, x in { -1, 1 } do
		b.box("Apron", V(0.2, 0.7, W - 1.3), V(x * (L / 2 - 0.55), apronY, 0), wood, M.Wood)
	end

	local pairs_ = math.max(2, math.floor(L / 8) + 1)
	for i = 0, pairs_ - 1 do
		local x = -L / 2 + 0.75 + (L - 1.5) * i / (pairs_ - 1)
		for _, z in { -1, 1 } do
			turnedLeg(b, x, z * (W / 2 - 0.62), H - topT, 0.55, wood)
		end
	end

	if cloth then
		local c = cloth :: Color3
		local cw, cl = W + 0.5, L + 0.5
		soft(b.box("Cloth", V(cl, 0.06, cw), V(0, H + 0.03, 0), c, M.Fabric))
		for _, z in { -1, 1 } do
			soft(
				b.box(
					"ClothDrape",
					V(cl, drop, 0.06),
					V(0, H + 0.03 - drop / 2, z * cw / 2),
					c,
					M.Fabric
				)
			)
		end
		for _, x in { -1, 1 } do
			soft(
				b.box(
					"ClothDrape",
					V(0.06, drop, cw),
					V(x * cl / 2, H + 0.03 - drop / 2, 0),
					c,
					M.Fabric
				)
			)
		end
		-- Folds: the cloth gathers into soft ridges where it hangs.
		local wear = Kit.wear()
		local n = math.floor(cl / 2.6)
		for i = 1, n do
			local x = -cl / 2 + cl * (i - 0.5) / n + wear:NextNumber(-0.4, 0.4)
			for _, z in { -1, 1 } do
				fine(
					b.rod(
						"ClothFold",
						V(x, H - 0.2, z * (cw / 2 + 0.03)),
						V(x, H + 0.03 - drop + 0.1, z * (cw / 2 + 0.08)),
						0.26,
						c,
						M.Fabric
					)
				)
			end
		end
		if opt(o, "runner", true) then
			fine(b.box("Runner", V(L - 3, 0.04, 1.7), V(0, H + 0.08, 0), C.VELVET_DARK, M.Fabric))
		end
	end

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		local clear = H - topT - 0.75
		spot = Kit.hideVolume(
			"UnderTableHidingVolume",
			at * CFrame.new(0, clear / 2 + 0.05, 0),
			V(L - 2, clear - 0.1, W - 1.8),
			"UnderTable",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

--[[
	A heavy kitchen work table: thick scrubbed top, square chunky legs, a
	drawer. Tall and bare underneath, so it is another place to hide.
]]
function Furnish.workTable(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin(opt(o, "name", "WorkTable"), at, parent)
	local L: number = opt(o, "length", 9)
	local W: number = opt(o, "width", 4.4)
	local H: number = opt(o, "height", 4.0)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local topT = 0.6

	b.box("Top", V(L, topT, W), V(0, H - topT / 2, 0), wood, M.WoodPlanks)
	for _, z in { -1, 1 } do
		fine(
			b.rod(
				"TopEdge",
				V(-L / 2, H - topT / 2, z * W / 2),
				V(L / 2, H - topT / 2, z * W / 2),
				topT,
				wood,
				M.Wood
			)
		)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b.box(
				"Leg",
				V(0.7, H - topT, 0.7),
				V(x * (L / 2 - 0.6), (H - topT) / 2, z * (W / 2 - 0.6)),
				C.OAK,
				M.Wood
			)
		end
	end
	b.box("Apron", V(L - 1.6, 0.8, 0.2), V(0, H - topT - 0.4, W / 2 - 0.55), C.OAK, M.Wood)
	b.box("Drawer", V(2.6, 0.7, 0.24), V(-L / 4, H - topT - 0.4, -W / 2 + 0.52), C.OAK, M.Wood)
	knob(b, V(-L / 4, H - topT - 0.4, -W / 2 + 0.4), V(0, 0, -1))

	-- What is on it.
	fine(b.box("Board", V(2.4, 0.18, 1.6), V(L / 4, H + 0.09, 0.3), C.OAK, M.Wood))
	-- A cleaver bitten into the board.
	fine(
		b.box(
			"Cleaver",
			V(1.3, 0.8, 0.06),
			V(L / 4 + 0.1, H + 0.45, 0.3),
			C.IRON,
			M.CorrodedMetal,
			CFrame.Angles(0, 0.3, math.rad(-8))
		)
	)
	fine(
		b.rod(
			"CleaverHandle",
			V(L / 4 - 0.55, H + 0.75, 0.12),
			V(L / 4 - 1.35, H + 0.82, -0.12),
			0.22,
			C.WALNUT,
			M.Wood
		)
	)
	fine(b.disc("Bowl", V(-L / 4 - 0.3, H + 0.3, 0.6), 1.4, 0.55, C.TILE_LIGHT, M.Slate))
	fine(
		b.disc("BowlDregs", V(-L / 4 - 0.3, H + 0.56, 0.6), 1.1, 0.06, C.BLOOD_OLD, M.SmoothPlastic)
	)

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		local clear = H - topT - 0.85
		spot = Kit.hideVolume(
			"UnderTableHidingVolume",
			at * CFrame.new(0, clear / 2 + 0.05, 0),
			V(L - 2, clear - 0.1, W - 1.8),
			"UnderTable",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

function Furnish.roundTable(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "RoundTable"), at, parent)
	local d: number = opt(o, "diameter", 4.6)
	local H: number = opt(o, "height", 3.4)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	b.disc("Top", V(0, H - 0.17, 0), d, 0.34, wood, M.Wood)
	fine(b.disc("TopLip", V(0, H - 0.42, 0), d - 0.3, 0.16, wood, M.Wood))
	b.rod("Pedestal", V(0, 0.6, 0), V(0, H - 0.4, 0), 0.75, wood, M.Wood)
	fine(b.ball("PedestalBulb", V(0, 1.3, 0), 1.25, wood, M.Wood))
	fine(b.disc("PedestalCollar", V(0, H - 0.8, 0), 1.0, 0.25, wood, M.Wood))
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local toe = V(math.cos(a) * 1.5, 0.22, math.sin(a) * 1.5)
		fine(b.rod("Foot", V(0, 0.6, 0), toe, 0.4, wood, M.Wood))
		fine(b.ball("Toe", toe, 0.5, wood, M.Wood))
	end
	return b.model
end

function Furnish.sideTable(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "SideTable"), at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local H: number = opt(o, "height", 3.2)
	local w: number = opt(o, "width", 2.4)
	b.box("Top", V(w, 0.24, w), V(0, H - 0.12, 0), wood, M.Wood)
	for _, x in { -1, 1 } do
		fine(
			b.rod(
				"TopEdge",
				V(x * w / 2, H - 0.12, -w / 2),
				V(x * w / 2, H - 0.12, w / 2),
				0.24,
				wood,
				M.Wood
			)
		)
	end
	b.box("Drawer", V(w - 0.5, 0.6, w - 0.5), V(0, H - 0.55, 0), wood, M.Wood)
	knob(b, V(0, H - 0.55, -(w - 0.5) / 2), V(0, 0, -1))
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod(
					"Leg",
					V(x * (w / 2 - 0.3), 0, z * (w / 2 - 0.3)),
					V(x * (w / 2 - 0.3), H - 0.24, z * (w / 2 - 0.3)),
					0.24,
					wood,
					M.Wood
				)
			)
		end
	end
	fine(b.box("Shelf", V(w - 0.5, 0.12, w - 0.5), V(0, 0.9, 0), wood, M.Wood))
	return b.model
end

--[[
	A writing desk: a pedestal of drawers under one end, turned legs under
	the other, a gallery of pigeonholes at the back.
]]
function Furnish.desk(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Desk"), at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local W, D, H = 6.4, 3.0, 3.3
	b.box("Top", V(W, 0.28, D), V(0, H - 0.14, 0), wood, M.Wood)
	fine(
		b.rod(
			"TopEdge",
			V(-W / 2, H - 0.14, -D / 2),
			V(W / 2, H - 0.14, -D / 2),
			0.28,
			wood,
			M.Wood
		)
	)
	fine(
		b.box("Leather", V(W - 1.4, 0.04, D - 1.0), V(0, H + 0.02, -0.2), C.LEATHER_DARK, M.Leather)
	)

	-- Pedestal of drawers at the right-hand end.
	local px = W / 2 - 1.1
	b.box("Pedestal", V(2.0, H - 0.28, D - 0.2), V(px, (H - 0.28) / 2, 0), wood, M.Wood)
	for i = 0, 2 do
		local y = 0.55 + i * 0.9
		fine(b.box("DrawerFront", V(1.7, 0.72, 0.1), V(px, y, -D / 2 + 0.05), C.WALNUT, M.Wood))
		knob(b, V(px, y, -D / 2), V(0, 0, -1))
	end
	for _, z in { -1, 1 } do
		turnedLeg(b, -W / 2 + 0.4, z * (D / 2 - 0.4), H - 0.28, 0.34, wood)
	end
	b.box("Modesty", V(W - 2.4, 1.4, 0.15), V(-0.9, H - 0.95, D / 2 - 0.2), wood, M.Wood)

	-- Gallery at the back.
	b.box("Gallery", V(W - 0.6, 1.3, 0.8), V(0, H + 0.65, D / 2 - 0.5), wood, M.Wood)
	for i = -2, 2 do
		fine(
			b.box("Pigeonhole", V(0.9, 0.9, 0.1), V(i * 1.1, H + 0.6, D / 2 - 0.92), C.SOOT, M.Wood)
		)
	end
	return b.model
end

----------------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------------

local BOOK_COLOURS = {
	Kit.rgb(70, 30, 26),
	Kit.rgb(52, 38, 30),
	Kit.rgb(38, 34, 40),
	Kit.rgb(78, 60, 36),
	Kit.rgb(58, 26, 22),
	Kit.rgb(44, 40, 30),
}

--[[
	A run of books on a shelf, as a few blocks of different heights and
	colours rather than one book to a part: a shelf of forty separate books is
	two hundred parts a bookcase and reads no better from three studs away.
	The odd one leans.
]]
local function books(
	b: Builder,
	x0: number,
	x1: number,
	y: number,
	z: number,
	depth: number,
	maxH: number
)
	local wear = Kit.wear()
	local x = x0
	while x < x1 - 0.4 do
		local w = math.min(x1 - x, wear:NextNumber(0.5, 1.6))
		local h = wear:NextNumber(maxH * 0.62, maxH * 0.92)
		local colour = BOOK_COLOURS[wear:NextInteger(1, #BOOK_COLOURS)]
		if wear:NextNumber() < 0.15 and x1 - x > 1.2 then
			-- A leaning book, and the gap it leans into.
			fine(
				b.box(
					"Book",
					V(0.28, h, depth - 0.2),
					V(x + 0.45, y + h / 2 - 0.05, z),
					colour,
					M.Leather,
					CFrame.Angles(0, 0, math.rad(-22))
				)
			)
			x += 0.9
		else
			fine(
				b.box(
					"Books",
					V(w - 0.04, h, depth - 0.15),
					V(x + w / 2, y + h / 2, z),
					colour,
					M.Leather
				)
			)
			x += w
		end
	end
end

function Furnish.bookcase(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Bookcase"), at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local W: number = opt(o, "width", 5.2)
	local H: number = opt(o, "height", 9.5)
	local D: number = opt(o, "depth", 1.7)
	local shelves: number = opt(o, "shelves", 5)

	for _, x in { -1, 1 } do
		b.box("Side", V(0.3, H, D), V(x * (W / 2 - 0.15), H / 2, 0), wood, M.Wood)
	end
	b.box("Back", V(W - 0.6, H - 0.5, 0.15), V(0, H / 2, D / 2 - 0.08), C.WALNUT, M.WoodPlanks)
	b.box("Plinth", V(W, 0.5, D + 0.1), V(0, 0.25, 0), wood, M.Wood)
	b.box("Crown", V(W + 0.4, 0.45, D + 0.3), V(0, H - 0.2, -0.05), wood, M.Wood)
	fine(
		b.rod(
			"CrownRoll",
			V(-(W + 0.4) / 2, H - 0.5, -(D + 0.3) / 2 + 0.05),
			V((W + 0.4) / 2, H - 0.5, -(D + 0.3) / 2 + 0.05),
			0.3,
			wood,
			M.Wood
		)
	)

	local bottom, top = 0.5, H - 0.45
	local gap = (top - bottom) / shelves
	for i = 0, shelves - 1 do
		local y = bottom + gap * i
		if i > 0 then
			b.box("Shelf", V(W - 0.6, 0.16, D - 0.2), V(0, y, 0), wood, M.Wood)
		end
		if not (opt(o, "sparse", false) and i % 2 == 1) then
			books(b, -W / 2 + 0.35, W / 2 - 0.35, y + 0.08, -0.05, D - 0.1, gap - 0.4)
		end
	end
	return b.model
end

--[[
	A wardrobe you can get inside and shut.

	The doors are real doors (HouseKit), so a player can step in, close them
	behind, and be a shape in the dark between two coats. The inside is wide
	and deep enough for a character standing, and the floor inside is a low
	step up.
]]
function Furnish.wardrobe(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot)
	local b = begin(opt(o, "name", "Wardrobe"), at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local W: number = opt(o, "width", 6.2)
	local D: number = opt(o, "depth", 4.2)
	local H: number = opt(o, "height", 9.6)
	local t = 0.3
	local plinth = 0.45

	for _, x in { -1, 1 } do
		b.box(
			"Side",
			V(t, H - plinth, D),
			V(x * (W / 2 - t / 2), plinth + (H - plinth) / 2, 0),
			wood,
			M.Wood
		)
	end
	b.box(
		"Back",
		V(W - t * 2, H - plinth, 0.2),
		V(0, plinth + (H - plinth) / 2, D / 2 - 0.1),
		wood,
		M.WoodPlanks
	)
	b.box("Floor", V(W, plinth, D), V(0, plinth / 2, 0), wood, M.Wood)
	b.box("Roof", V(W, 0.3, D), V(0, H - 0.15, 0), wood, M.Wood)
	b.box("Crown", V(W + 0.5, 0.5, D + 0.4), V(0, H + 0.25, -0.05), wood, M.Wood)
	fine(
		b.rod(
			"CrownRoll",
			V(-(W + 0.5) / 2, H + 0.02, -(D + 0.4) / 2 + 0.03),
			V((W + 0.5) / 2, H + 0.02, -(D + 0.4) / 2 + 0.03),
			0.35,
			wood,
			M.Wood
		)
	)
	for _, x in { -1, 1 } do
		fine(b.ball("Foot", V(x * (W / 2 - 0.35), 0.18, -D / 2 + 0.35), 0.44, wood, M.Wood))
	end

	-- Inside: a rail and what is still hanging from it.
	local railY = H - 1.1
	fine(
		b.rod(
			"HangingRail",
			V(-W / 2 + t, railY, 0.3),
			V(W / 2 - t, railY, 0.3),
			0.18,
			C.BRASS,
			M.Metal
		)
	)
	local wear = Kit.wear()
	for _, x in { -W / 2 + 0.7, W / 2 - 0.8 } do
		local len = wear:NextNumber(4.2, 5.6)
		fine(
			b.rod(
				"Hanger",
				V(x - 0.8, railY - 0.35, 0.3),
				V(x + 0.8, railY - 0.35, 0.3),
				0.08,
				C.WALNUT,
				M.Wood
			)
		)
		soft(
			b.box(
				"Coat",
				V(1.7, len, 0.5),
				V(x, railY - 0.4 - len / 2, 0.3),
				if x < 0 then C.CLOTH else C.VELVET_DARK,
				M.Fabric
			)
		)
	end

	-- Two doors, hinged on the outer edges, opening out into the room.
	local doorH = H - plinth - 0.6
	local leafW = (W - t * 2) / 2
	for _, side in { -1, 1 } do
		local frame = at * CFrame.new(side * leafW / 2, plinth + 0.05 + doorH / 2, -D / 2 + 0.12)
		Kit.door(frame, leafW, doorH, {
			parent = b.model,
			hinge = side,
			swing = 1,
			thickness = 0.24,
			color = wood,
			panel = C.WALNUT,
			style = "cabinet",
			-- No further than square: a wardrobe usually stands in a corner
			-- or beside something, and a leaf past 90 swings into it.
			openAngle = 90,
			gap = 0.06,
			name = "WardrobeDoor",
		})
	end

	local spot = Kit.hideVolume(
		"WardrobeHidingVolume",
		at * CFrame.new(0, plinth + (H - plinth - 1.4) / 2, 0.1),
		V(W - t * 2 - 0.4, H - plinth - 1.4, D - 0.8),
		"Wardrobe",
		opt(o, "floor", 1),
		b.model
	)
	return b.model, spot
end

function Furnish.chestOfDrawers(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "ChestOfDrawers"), at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local W: number = opt(o, "width", 5)
	local D: number = opt(o, "depth", 2.4)
	local H: number = opt(o, "height", 4.0)
	b.box("Body", V(W, H - 0.6, D), V(0, 0.4 + (H - 0.6) / 2, 0), wood, M.Wood)
	b.box("Top", V(W + 0.3, 0.2, D + 0.2), V(0, H - 0.1, -0.05), wood, M.Wood)
	fine(
		b.rod(
			"TopEdge",
			V(-(W + 0.3) / 2, H - 0.1, -(D + 0.2) / 2 - 0.05),
			V((W + 0.3) / 2, H - 0.1, -(D + 0.2) / 2 - 0.05),
			0.2,
			wood,
			M.Wood
		)
	)
	local rows = 4
	local span = (H - 1.0) / rows
	for i = 0, rows - 1 do
		local y = 0.55 + span * (i + 0.5)
		-- The second drawer from the top has been pulled out and left.
		local out = if i == rows - 2 and opt(o, "open", true) then 0.9 else 0
		fine(
			b.box(
				"DrawerFront",
				V(W - 0.4, span - 0.14, 0.12),
				V(0, y, -D / 2 - 0.02 - out),
				C.OAK,
				M.Wood
			)
		)
		for _, x in { -W / 4, W / 4 } do
			knob(b, V(x, y, -D / 2 - 0.08 - out), V(0, 0, -1))
		end
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.ball(
					"BunFoot",
					V(x * (W / 2 - 0.35), 0.22, z * (D / 2 - 0.35)),
					0.46,
					wood,
					M.Wood
				)
			)
		end
	end
	if opt(o, "mirror", false) then
		-- A swing mirror on posts, the glass gone dark and cracked.
		for _, x in { -1, 1 } do
			fine(
				b.rod(
					"MirrorPost",
					V(x * (W / 2 - 0.5), H, D / 2 - 0.5),
					V(x * (W / 2 - 0.5), H + 3.6, D / 2 - 0.5),
					0.26,
					wood,
					M.Wood
				)
			)
			fine(
				b.ball(
					"MirrorFinial",
					V(x * (W / 2 - 0.5), H + 3.7, D / 2 - 0.5),
					0.36,
					wood,
					M.Wood
				)
			)
		end
		b.box("MirrorFrame", V(W - 1.5, 3.0, 0.2), V(0, H + 1.9, D / 2 - 0.5), wood, M.Wood)
		local glass = fine(
			b.box(
				"Mirror",
				V(W - 2.0, 2.5, 0.06),
				V(0, H + 1.9, D / 2 - 0.62),
				C.GLASS_DARK,
				M.Glass
			)
		)
		glass.Reflectance = 0.12
		for k = 0, 2 do
			fine(
				b.box(
					"Crack",
					V(1.6, 0.05, 0.02),
					V(0.3, H + 1.9 + k * 0.2, D / 2 - 0.66),
					C.SOOT,
					M.SmoothPlastic,
					CFrame.Angles(0, 0, math.rad(-35 + k * 38))
				)
			)
		end
	end
	return b.model
end

--[[
	A long, low sideboard for the dining hall: cupboards at the ends, drawers
	in the middle, a gallery rail along the back.
]]
function Furnish.sideboard(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Sideboard"), at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local W: number = opt(o, "width", 10)
	local D, H = 2.6, 3.8
	b.box("Body", V(W, H - 0.9, D), V(0, 0.7 + (H - 0.9) / 2, 0), wood, M.Wood)
	b.box("Top", V(W + 0.4, 0.22, D + 0.3), V(0, H - 0.09, -0.08), wood, M.Wood)
	fine(
		b.rod(
			"TopEdge",
			V(-(W + 0.4) / 2, H - 0.09, -(D + 0.3) / 2 - 0.08),
			V((W + 0.4) / 2, H - 0.09, -(D + 0.3) / 2 - 0.08),
			0.22,
			wood,
			M.Wood
		)
	)
	for _, x in { -1, 1 } do
		fine(
			b.box(
				"CupboardDoor",
				V(2.6, H - 1.5, 0.12),
				V(x * (W / 2 - 1.6), 0.7 + (H - 0.9) / 2 - 0.15, -D / 2 - 0.02),
				C.OAK,
				M.Wood
			)
		)
		knob(b, V(x * (W / 2 - 2.6), 2.2, -D / 2 - 0.08), V(0, 0, -1))
		turnedLeg(b, x * (W / 2 - 0.4), -D / 2 + 0.4, 0.75, 0.4, wood)
		turnedLeg(b, x * (W / 2 - 0.4), D / 2 - 0.4, 0.75, 0.4, wood)
	end
	for i = 0, 1 do
		local y = 1.4 + i * 1.1
		fine(b.box("DrawerFront", V(W - 6.4, 0.9, 0.12), V(0, y, -D / 2 - 0.02), C.OAK, M.Wood))
		knob(b, V(-0.9, y, -D / 2 - 0.08), V(0, 0, -1))
		knob(b, V(0.9, y, -D / 2 - 0.08), V(0, 0, -1))
	end
	fine(
		b.rod(
			"GalleryRail",
			V(-W / 2 + 0.3, H + 0.9, D / 2 - 0.2),
			V(W / 2 - 0.3, H + 0.9, D / 2 - 0.2),
			0.18,
			C.BRASS,
			M.Metal
		)
	)
	for _, x in { -W / 2 + 0.3, 0, W / 2 - 0.3 } do
		fine(
			b.rod(
				"GalleryPost",
				V(x, H, D / 2 - 0.2),
				V(x, H + 0.95, D / 2 - 0.2),
				0.14,
				C.BRASS,
				M.Metal
			)
		)
	end
	return b.model
end

--[[
	A dresser for a kitchen: cupboards below, open shelves above with plates
	stood on edge along a rail.
]]
function Furnish.hutch(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Hutch"), at, parent)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local W: number = opt(o, "width", 7)
	local D, H, low = 2.4, 10, 3.6
	b.box("Base", V(W, low, D), V(0, low / 2, 0), wood, M.Wood)
	b.box("Worktop", V(W + 0.3, 0.25, D + 0.2), V(0, low + 0.12, -0.05), wood, M.Wood)
	for _, x in { -1, 1 } do
		fine(
			b.box(
				"CupboardDoor",
				V(W / 2 - 0.5, low - 0.9, 0.12),
				V(x * W / 4, low / 2, -D / 2 - 0.02),
				C.OAK,
				M.Wood
			)
		)
		knob(b, V(x * 0.55, low / 2, -D / 2 - 0.08), V(0, 0, -1))
		b.box(
			"Side",
			V(0.25, H - low, 1.2),
			V(x * (W / 2 - 0.125), low + (H - low) / 2, D / 2 - 0.6),
			wood,
			M.Wood
		)
	end
	b.box(
		"Back",
		V(W - 0.5, H - low, 0.15),
		V(0, low + (H - low) / 2, D / 2 - 0.08),
		wood,
		M.WoodPlanks
	)
	b.box("Cornice", V(W + 0.4, 0.4, 1.5), V(0, H + 0.2, D / 2 - 0.65), wood, M.Wood)
	local wear = Kit.wear()
	for i = 1, 3 do
		local y = low + i * 1.75
		b.box("Shelf", V(W - 0.5, 0.14, 1.1), V(0, y, D / 2 - 0.65), wood, M.Wood)
		fine(
			b.rod(
				"PlateRail",
				V(-W / 2 + 0.3, y + 0.5, D / 2 - 1.1),
				V(W / 2 - 0.3, y + 0.5, D / 2 - 1.1),
				0.1,
				wood,
				M.Wood
			)
		)
		-- Plates on edge, a few missing, a jar or two.
		local x = -W / 2 + 0.9
		while x < W / 2 - 0.9 do
			if wear:NextNumber() < 0.75 then
				local plateD = wear:NextNumber(1.0, 1.35)
				fine(
					b.disc(
						"Plate",
						V(x, y + 0.07 + plateD / 2, D / 2 - 0.55),
						plateD,
						0.08,
						Kit.rgb(62, 56, 48),
						M.Slate,
						CFrame.Angles(math.rad(90) - 0.12, 0, 0)
					)
				)
			elseif wear:NextNumber() < 0.5 then
				fine(b.disc("Jar", V(x, y + 0.5, D / 2 - 0.6), 0.6, 0.85, C.GLASS_DARK, M.Glass))
			end
			x += 1.05
		end
	end
	return b.model
end

--[[
	Base cupboards with a worktop: kitchens, sculleries. `sink` puts a stone
	sink and a pump in the middle.
]]
function Furnish.counter(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Counter"), at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local W: number = opt(o, "width", 8)
	local D, H = 2.8, 3.7
	b.box("Base", V(W, H - 0.3 - 0.4, D - 0.2), V(0, 0.4 + (H - 0.7) / 2, 0.1), wood, M.Wood)
	b.box("Kick", V(W - 0.2, 0.4, D - 0.5), V(0, 0.2, 0.25), C.SOOT, M.Wood)
	b.box(
		"Worktop",
		V(W + 0.2, 0.3, D + 0.1),
		V(0, H - 0.15, 0),
		opt(o, "top", C.SLATE),
		opt(o, "topMaterial", M.Slate)
	)
	local doors = math.max(1, math.floor(W / 2.6))
	for i = 0, doors - 1 do
		local x = -W / 2 + W * (i + 0.5) / doors
		fine(
			b.box(
				"CupboardDoor",
				V(W / doors - 0.3, H - 1.4, 0.12),
				V(x, 0.4 + (H - 1.0) / 2, -D / 2 + 0.02),
				C.WALNUT,
				M.Wood
			)
		)
		knob(b, V(x + (W / doors) * 0.3, H - 1.3, -D / 2 - 0.04), V(0, 0, -1))
	end
	if opt(o, "sink", false) then
		fine(b.box("Sink", V(3.2, 0.9, 2.0), V(0, H - 0.3, -0.05), C.STONE_DARK, M.Slate))
		fine(b.box("SinkWater", V(2.7, 0.06, 1.5), V(0, H + 0.1, -0.05), C.GRIME, M.SmoothPlastic))
		-- A hand pump beside the sink: iron body, a spout over the basin, the
		-- lever pointing away from it. All of it inside the worktop's depth,
		-- so the counter can stand under a window without the pump in the sill.
		local px, pz = -2.25, 0.55
		fine(b.rod("Pump", V(px, H, pz), V(px, H + 2.4, pz), 0.45, C.IRON, M.CorrodedMetal))
		fine(
			b.rod(
				"Spout",
				V(px, H + 1.9, pz),
				V(px + 0.95, H + 1.55, pz - 0.35),
				0.2,
				C.IRON,
				M.CorrodedMetal
			)
		)
		fine(
			b.rod(
				"PumpHandle",
				V(px, H + 2.45, pz),
				V(px - 1.1, H + 3.0, pz),
				0.14,
				C.IRON,
				M.CorrodedMetal
			)
		)
		fine(b.ball("PumpCap", V(px, H + 2.5, pz), 0.5, C.IRON, M.CorrodedMetal))
	end
	return b.model
end

--[[
	A cast-iron kitchen range: ovens below, hot plates on top, a rail along
	the front and a stove pipe up into the chimney breast. Cold for years.
]]
function Furnish.range(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin(opt(o, "name", "Range"), at, parent)
	local W: number = opt(o, "width", 5.6)
	local D: number = opt(o, "depth", 2.8)
	local H = 3.6
	local pipeTop: number = opt(o, "pipeTop", 9)
	b.box("Body", V(W, H - 0.6, D), V(0, 0.6 + (H - 0.6) / 2, 0), C.IRON, M.CorrodedMetal)
	b.box("Hob", V(W + 0.2, 0.25, D + 0.2), V(0, H + 0.12, 0), C.SOOT, M.Metal)
	for _, x in { -1, 1 } do
		fine(
			b.box(
				"OvenDoor",
				V(W / 2 - 0.4, 1.9, 0.14),
				V(x * W / 4, 1.8, -D / 2 - 0.05),
				C.RUST,
				M.CorrodedMetal
			)
		)
		fine(
			b.rod(
				"OvenHandle",
				V(x * W / 4 - 0.8, 2.55, -D / 2 - 0.3),
				V(x * W / 4 + 0.8, 2.55, -D / 2 - 0.3),
				0.12,
				C.BRASS,
				M.Metal
			)
		)
		for _, z in { -0.5, 0.6 } do
			fine(b.disc("HotPlate", V(x * W / 4, H + 0.27, z), 1.1, 0.06, C.RUST, M.CorrodedMetal))
		end
		fine(
			b.rod(
				"Leg",
				V(x * (W / 2 - 0.3), 0, -D / 2 + 0.3),
				V(x * (W / 2 - 0.3), 0.6, -D / 2 + 0.3),
				0.4,
				C.IRON,
				M.Metal
			)
		)
		fine(
			b.rod(
				"Leg",
				V(x * (W / 2 - 0.3), 0, D / 2 - 0.3),
				V(x * (W / 2 - 0.3), 0.6, D / 2 - 0.3),
				0.4,
				C.IRON,
				M.Metal
			)
		)
	end
	fine(
		b.rod(
			"Rail",
			V(-W / 2 - 0.1, H - 0.4, -D / 2 - 0.35),
			V(W / 2 + 0.1, H - 0.4, -D / 2 - 0.35),
			0.16,
			C.BRASS,
			M.Metal
		)
	)
	fine(
		b.rod(
			"Pipe",
			V(W / 4, H + 0.2, D / 2 - 0.6),
			V(W / 4, pipeTop, D / 2 - 0.6),
			0.8,
			C.IRON,
			M.CorrodedMetal
		)
	)
	fine(b.disc("PipeCollar", V(W / 4, H + 1.2, D / 2 - 0.6), 1.0, 0.16, C.IRON, M.Metal))
	-- A kettle left on the plate and a pot with a lid.
	fine(b.disc("Kettle", V(-W / 4, H + 0.7, -0.5), 1.0, 0.8, C.RUST, M.CorrodedMetal))
	fine(b.ball("KettleLid", V(-W / 4, H + 1.05, -0.5), 0.6, C.RUST, M.CorrodedMetal))
	fine(
		b.rod(
			"KettleSpout",
			V(-W / 4 - 0.4, H + 0.7, -0.5),
			V(-W / 4 - 0.95, H + 1.1, -0.5),
			0.16,
			C.RUST,
			M.CorrodedMetal
		)
	)
	fine(b.disc("Pot", V(W / 4, H + 0.75, -0.5), 1.3, 0.95, C.IRON, M.Metal))
	fine(
		b.rod(
			"PotHandle",
			V(W / 4 + 0.35, H + 1.0, -0.9),
			V(W / 4 + 0.75, H + 1.05, -1.7),
			0.14,
			C.IRON,
			M.Metal
		)
	)
	return b.model
end

----------------------------------------------------------------------------
-- Bedrooms
----------------------------------------------------------------------------

--[[
	A four-poster bed: round posts with ball finials, a canopy frame with
	what is left of its curtains, a rolled pillow, a blanket over the foot.
	High enough off the floor that the space under it is a hiding place for
	anyone willing to lie down in the dust.
]]
function Furnish.bed(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin(opt(o, "name", "Bed"), at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local sheet: Color3 = opt(o, "sheet", C.LINEN)
	local blanket: Color3 = opt(o, "blanket", C.VELVET_DARK)
	local W: number = opt(o, "width", 6.6)
	local L: number = opt(o, "length", 9.6)
	local posts: boolean = opt(o, "posts", true)
	local postH = if posts then 9.2 else 5.2
	local frameY = 1.9

	-- The head is at +Z (against the wall), the foot faces -Z.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local h = if z > 0 then postH else (if posts then postH else 3.6)
			fine(
				b.rod(
					"Post",
					V(x * W / 2, 0, z * L / 2),
					V(x * W / 2, h, z * L / 2),
					0.55,
					wood,
					M.Wood
				)
			)
			fine(b.ball("PostBulb", V(x * W / 2, 1.4, z * L / 2), 0.8, wood, M.Wood))
			fine(b.ball("Finial", V(x * W / 2, h + 0.3, z * L / 2), 0.62, wood, M.Wood))
		end
	end
	for _, x in { -1, 1 } do
		b.box("SideRail", V(0.25, 0.7, L - 0.5), V(x * (W / 2 - 0.05), frameY, 0), wood, M.Wood)
	end
	b.box("Headboard", V(W - 0.5, 3.4, 0.3), V(0, frameY + 1.9, L / 2 - 0.05), wood, M.Wood)
	fine(
		b.rod(
			"HeadboardRoll",
			V(-W / 2 + 0.25, frameY + 3.6, L / 2 - 0.05),
			V(W / 2 - 0.25, frameY + 3.6, L / 2 - 0.05),
			0.45,
			wood,
			M.Wood
		)
	)
	b.box("Footboard", V(W - 0.5, 1.6, 0.3), V(0, frameY + 0.6, -L / 2 + 0.05), wood, M.Wood)
	fine(
		b.rod(
			"FootboardRoll",
			V(-W / 2 + 0.25, frameY + 1.4, -L / 2 + 0.05),
			V(W / 2 - 0.25, frameY + 1.4, -L / 2 + 0.05),
			0.4,
			wood,
			M.Wood
		)
	)

	-- Mattress with rolled edges, a sheet, a pillow, a blanket half off.
	local mY = frameY + 0.65
	b.box("Mattress", V(W - 1.2, 1.1, L - 1.0), V(0, mY, 0), sheet, M.Fabric)
	for _, x in { -1, 1 } do
		fine(
			b.rod(
				"MattressEdge",
				V(x * (W - 1.2) / 2, mY, -(L - 1.0) / 2),
				V(x * (W - 1.2) / 2, mY, (L - 1.0) / 2),
				1.1,
				sheet,
				M.Fabric
			)
		)
	end
	fine(
		b.rod(
			"Pillow",
			V(-W / 2 + 1.0, mY + 0.85, L / 2 - 1.3),
			V(W / 2 - 1.0, mY + 0.85, L / 2 - 1.3),
			1.0,
			sheet,
			M.Fabric
		)
	)
	soft(
		b.box(
			"Blanket",
			V(W - 0.7, 0.14, L * 0.55),
			V(0, mY + 0.62, -L * 0.2),
			blanket,
			M.Fabric,
			CFrame.Angles(0, math.rad(4), 0)
		)
	)
	soft(
		b.box(
			"BlanketDrop",
			V(W - 0.7, 1.6, 0.12),
			V(0.15, mY - 0.18, -L / 2 + 0.2),
			blanket,
			M.Fabric
		)
	)
	fine(b.disc("Stain", V(0.4, mY + 0.56, 0.5), 1.8, 0.04, C.BLOOD_OLD, M.Fabric))

	if posts then
		for _, x in { -1, 1 } do
			fine(b.box("CanopyRail", V(0.2, 0.3, L), V(x * W / 2, postH - 0.2, 0), wood, M.Wood))
		end
		for _, z in { -1, 1 } do
			fine(b.box("CanopyRail", V(W, 0.3, 0.2), V(0, postH - 0.2, z * L / 2), wood, M.Wood))
		end
		-- Rags of the old bed curtains, hanging at three of the posts.
		local wear = Kit.wear()
		for _, corner in { V(-1, 0, 1), V(1, 0, 1), V(-1, 0, -1) } do
			local len = wear:NextNumber(3.5, 6.5)
			soft(
				b.box(
					"BedCurtain",
					V(0.1, len, 1.6),
					V(corner.X * (W / 2 + 0.12), postH - 0.3 - len / 2, corner.Z * (L / 2 - 0.9)),
					C.VELVET,
					M.Fabric,
					CFrame.Angles(0, 0, corner.X * math.rad(3))
				)
			)
		end
	end

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderBedHidingVolume",
			at * CFrame.new(0, 0.75, 0),
			V(W - 1.0, 1.3, L - 1.2),
			"UnderBed",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

function Furnish.nightstand(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Nightstand", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	b.box("Body", V(2.2, 2.6, 2.0), V(0, 0.4 + 1.3, 0), wood, M.Wood)
	b.box("Top", V(2.4, 0.18, 2.2), V(0, 3.09, 0), wood, M.Wood)
	fine(b.box("DrawerFront", V(1.8, 0.7, 0.1), V(0, 2.55, -1.02), C.OAK, M.Wood))
	knob(b, V(0, 2.55, -1.06), V(0, 0, -1))
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(b.ball("Foot", V(x * 0.85, 0.2, z * 0.75), 0.42, wood, M.Wood))
		end
	end
	-- A candlestick burnt right down, and a book face down.
	fine(b.disc("CandleDish", V(-0.5, 3.24, 0.2), 0.8, 0.1, C.BRASS, M.Metal))
	fine(b.rod("Candle", V(-0.5, 3.28, 0.2), V(-0.5, 3.75, 0.2), 0.26, C.WAX, M.SmoothPlastic))
	fine(
		b.box(
			"Book",
			V(0.9, 0.2, 1.2),
			V(0.45, 3.28, -0.1),
			BOOK_COLOURS[1],
			M.Leather,
			CFrame.Angles(0, 0.4, 0)
		)
	)
	return b.model
end

--[[
	A child's cot with round bars, the kind every haunted nursery has one of.
]]
function Furnish.crib(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Crib", at, parent)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local W, L, H = 3.2, 5.4, 4.2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod(
					"Post",
					V(x * W / 2, 0, z * L / 2),
					V(x * W / 2, H, z * L / 2),
					0.36,
					wood,
					M.Wood
				)
			)
			fine(b.ball("Finial", V(x * W / 2, H + 0.2, z * L / 2), 0.46, wood, M.Wood))
		end
	end
	for _, y in { 1.6, H - 0.2 } do
		for _, x in { -1, 1 } do
			fine(b.rod("Rail", V(x * W / 2, y, -L / 2), V(x * W / 2, y, L / 2), 0.2, wood, M.Wood))
		end
		for _, z in { -1, 1 } do
			fine(b.rod("Rail", V(-W / 2, y, z * L / 2), V(W / 2, y, z * L / 2), 0.2, wood, M.Wood))
		end
	end
	for _, x in { -1, 1 } do
		for k = 1, 7 do
			local z = -L / 2 + L * k / 8
			fine(b.rod("Bar", V(x * W / 2, 1.6, z), V(x * W / 2, H - 0.2, z), 0.12, wood, M.Wood))
		end
	end
	for _, z in { -1, 1 } do
		for k = 1, 3 do
			local x = -W / 2 + W * k / 4
			fine(b.rod("Bar", V(x, 1.6, z * L / 2), V(x, H - 0.2, z * L / 2), 0.12, wood, M.Wood))
		end
	end
	b.box("Base", V(W - 0.2, 0.5, L - 0.2), V(0, 1.5, 0), wood, M.Wood)
	fine(b.box("Mattress", V(W - 0.4, 0.4, L - 0.4), V(0, 1.95, 0), C.LINEN, M.Fabric))
	fine(b.box("Blanket", V(W - 0.5, 0.1, 2.4), V(0, 2.2, -0.9), C.CLOTH, M.Fabric))
	return b.model
end

----------------------------------------------------------------------------
-- Parlour and music room
----------------------------------------------------------------------------

--[[
	An upright piano with its stool. The keys are yellowed ivory, which is the
	palest thing in the house, and still darker than old paper.
]]
function Furnish.piano(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Piano", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local W, D, H = 6.6, 2.4, 5.0
	b.box("Case", V(W, H - 0.4, D - 0.6), V(0, 0.4 + (H - 0.4) / 2, 0.3), wood, M.Wood)
	b.box("Lid", V(W + 0.2, 0.2, D - 0.4), V(0, H + 0.1, 0.25), wood, M.Wood)
	b.box("KeyBed", V(W - 0.4, 0.5, 1.2), V(0, 2.9, -D / 2 + 0.1), wood, M.Wood)
	fine(
		b.box(
			"Keys",
			V(W - 0.9, 0.12, 0.9),
			V(0, 3.2, -D / 2 - 0.05),
			Kit.rgb(70, 64, 52),
			M.SmoothPlastic
		)
	)
	for i = 0, 17 do
		if i % 7 ~= 2 and i % 7 ~= 6 then
			local x = -(W - 0.9) / 2 + (W - 0.9) * (i + 0.8) / 18.5
			fine(
				b.box(
					"BlackKey",
					V(0.14, 0.12, 0.55),
					V(x, 3.3, -D / 2 + 0.12),
					C.SOOT,
					M.SmoothPlastic
				)
			)
		end
	end
	b.box(
		"Fallboard",
		V(W - 0.8, 0.8, 0.14),
		V(0, 3.75, -D / 2 + 0.55),
		wood,
		M.Wood,
		CFrame.Angles(math.rad(-12), 0, 0)
	)
	for _, x in { -1, 1 } do
		turnedLeg(b, x * (W / 2 - 0.35), -D / 2 + 0.25, 2.65, 0.36, wood)
		-- Candle sconces on the front, swung out.
		fine(
			b.rod(
				"SconceArm",
				V(x * (W / 2 - 0.9), 4.2, -0.3),
				V(x * (W / 2 - 0.5), 4.3, -1.0),
				0.1,
				C.BRASS,
				M.Metal
			)
		)
		fine(b.disc("SconceCup", V(x * (W / 2 - 0.5), 4.36, -1.0), 0.45, 0.1, C.BRASS, M.Metal))
		fine(
			b.rod(
				"Candle",
				V(x * (W / 2 - 0.5), 4.4, -1.0),
				V(x * (W / 2 - 0.5), 4.9, -1.0),
				0.2,
				C.WAX,
				M.SmoothPlastic
			)
		)
	end
	fine(
		b.box(
			"Music",
			V(2.2, 1.4, 0.05),
			V(0, 4.55, -D / 2 + 0.72),
			C.LINEN,
			M.SmoothPlastic,
			CFrame.Angles(math.rad(-15), 0, 0)
		)
	)
	fine(b.box("PedalBox", V(1.4, 0.5, 0.5), V(0, 0.25, -D / 2 + 0.5), wood, M.Wood))
	for _, x in { -0.3, 0.3 } do
		fine(
			b.rod(
				"Pedal",
				V(x, 0.3, -D / 2 + 0.3),
				V(x, 0.28, -D / 2 - 0.25),
				0.12,
				C.BRASS,
				M.Metal
			)
		)
	end
	-- The stool, pushed back from the keys.
	local stool = CFrame.new(0.3, 0, -D / 2 - 2.4)
	b.disc("StoolSeat", stool.Position + V(0, 2.2, 0), 1.8, 0.3, C.VELVET, M.Fabric)
	fine(
		b.rod(
			"StoolColumn",
			stool.Position + V(0, 0.5, 0),
			stool.Position + V(0, 2.05, 0),
			0.4,
			wood,
			M.Wood
		)
	)
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		fine(
			b.rod(
				"StoolFoot",
				stool.Position + V(0, 0.5, 0),
				stool.Position + V(math.cos(a) * 1.0, 0.12, math.sin(a) * 1.0),
				0.22,
				wood,
				M.Wood
			)
		)
		fine(
			b.ball(
				"StoolClaw",
				stool.Position + V(math.cos(a) * 1.05, 0.15, math.sin(a) * 1.05),
				0.3,
				C.BRASS,
				M.Metal
			)
		)
	end
	return b.model
end

--[[
	A longcase clock. The hands stopped at a quarter past three, and the
	pendulum hangs still behind a glass that is almost black.
]]
function Furnish.clock(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("GrandfatherClock", at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	b.box("Plinth", V(2.6, 2.0, 1.9), V(0, 1.0, 0), wood, M.Wood)
	b.box("Trunk", V(2.0, 5.2, 1.5), V(0, 4.6, 0), wood, M.Wood)
	b.box("Hood", V(2.6, 2.6, 1.9), V(0, 8.5, 0), wood, M.Wood)
	fine(b.rod("HoodArch", V(0, 9.8, -0.95), V(0, 9.8, 0.95), 2.6, wood, M.Wood))
	fine(b.ball("Finial", V(0, 11.2, 0), 0.45, C.BRASS, M.Metal))
	local face = b.disc(
		"Dial",
		V(0, 8.5, -0.96),
		1.9,
		0.08,
		Kit.rgb(70, 60, 44),
		M.Metal,
		CFrame.Angles(math.pi / 2, 0, 0)
	)
	fine(face)
	fine(
		b.box(
			"HourHand",
			V(0.08, 0.55, 0.03),
			V(0.2, 8.55, -1.02),
			C.SOOT,
			M.Metal,
			CFrame.Angles(0, 0, math.rad(-80))
		)
	)
	fine(
		b.box(
			"MinuteHand",
			V(0.06, 0.85, 0.03),
			V(0.36, 8.55, -1.04),
			C.SOOT,
			M.Metal,
			CFrame.Angles(0, 0, math.rad(-90))
		)
	)
	fine(b.box("TrunkGlass", V(1.2, 3.6, 0.05), V(0, 4.7, -0.77), C.GLASS_DARK, M.Glass))
	fine(b.rod("PendulumRod", V(0, 6.6, -0.6), V(0, 3.6, -0.6), 0.08, C.BRASS, M.Metal))
	fine(
		b.disc(
			"PendulumBob",
			V(0, 3.4, -0.62),
			0.9,
			0.12,
			C.BRASS,
			M.Metal,
			CFrame.Angles(math.pi / 2, 0, 0)
		)
	)
	for _, x in { -1, 1 } do
		fine(b.rod("Column", V(x * 1.05, 7.3, -0.9), V(x * 1.05, 9.7, -0.9), 0.24, wood, M.Wood))
	end
	return b.model
end

function Furnish.gramophone(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Gramophone", at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local base: number = opt(o, "baseHeight", 0)
	b.box("Cabinet", V(1.8, 0.8, 1.8), V(0, base + 0.4, 0), wood, M.Wood)
	fine(b.disc("Platter", V(0, base + 0.84, 0), 1.5, 0.06, C.SOOT, M.SmoothPlastic))
	fine(b.disc("Record", V(0, base + 0.88, 0), 1.3, 0.03, Kit.rgb(24, 22, 22), M.SmoothPlastic))
	fine(b.rod("Crank", V(0.9, base + 0.4, 0), V(1.3, base + 0.4, 0), 0.08, C.BRASS, M.Metal))
	fine(b.ball("CrankKnob", V(1.35, base + 0.4, 0), 0.18, C.WALNUT, M.Wood))
	-- The horn: a flared bell of stacked rings, swept up and forward.
	local prev = V(0.55, base + 1.0, 0.55)
	fine(
		b.rod(
			"ToneArm",
			V(0.55, base + 0.9, 0.55),
			V(0.15, base + 0.95, -0.1),
			0.1,
			C.BRASS,
			M.Metal
		)
	)
	for k = 1, 6 do
		local t = k / 6
		local p = V(0.55 - 0.2 * t, base + 1.0 + 1.6 * t, 0.55 - 1.2 * t * t)
		fine(b.rod("Horn", prev, p, 0.2 + 1.5 * t * t, C.BRASS, M.Metal))
		prev = p
	end
	return b.model
end

----------------------------------------------------------------------------
-- Bathroom
----------------------------------------------------------------------------

--[[
	A roll-top bath on claw feet, full to the rim with something dark.
	Round at both ends: a box between two upright cylinders.
]]
function Furnish.bathtub(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Bathtub", at, parent)
	local enamel = Kit.rgb(64, 58, 50)
	local outside = C.IRON
	local L, W, H = 6.4, 2.8, 2.5
	local lift = 0.55
	b.box("Body", V(L - W, H, W), V(0, lift + H / 2, 0), outside, M.CorrodedMetal)
	for _, x in { -1, 1 } do
		b.rod(
			"End",
			V(x * (L - W) / 2, lift, 0),
			V(x * (L - W) / 2, lift + H, 0),
			W,
			outside,
			M.CorrodedMetal
		)
	end
	-- The rolled rim, and the water inside it.
	for _, z in { -1, 1 } do
		fine(
			b.rod(
				"Rim",
				V(-(L - W) / 2, lift + H, z * (W / 2 - 0.1)),
				V((L - W) / 2, lift + H, z * (W / 2 - 0.1)),
				0.34,
				enamel,
				M.SmoothPlastic
			)
		)
	end
	for _, x in { -1, 1 } do
		fine(
			b.disc(
				"RimEnd",
				V(x * (L - W) / 2, lift + H + 0.02, 0),
				W + 0.05,
				0.2,
				enamel,
				M.SmoothPlastic
			)
		)
	end
	fine(
		b.box(
			"Water",
			V(L - W, 0.1, W - 0.5),
			V(0, lift + H + 0.06, 0),
			Kit.rgb(30, 22, 18),
			M.Glass
		)
	)
	for _, x in { -1, 1 } do
		fine(
			b.disc(
				"WaterEnd",
				V(x * (L - W) / 2, lift + H + 0.06, 0),
				W - 0.5,
				0.1,
				Kit.rgb(30, 22, 18),
				M.Glass
			)
		)
	end
	-- Claw feet.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod(
					"FootLeg",
					V(x * (L / 2 - 1.3), lift + 0.3, z * 0.9),
					V(x * (L / 2 - 1.2), 0.25, z * 1.0),
					0.32,
					C.IRON,
					M.Metal
				)
			)
			fine(b.ball("Claw", V(x * (L / 2 - 1.2), 0.2, z * 1.0), 0.46, C.IRON, M.Metal))
		end
	end
	-- Taps at the head end.
	fine(
		b.rod(
			"TapPipe",
			V(L / 2 - 0.5, lift + H + 0.1, 0),
			V(L / 2 - 0.5, lift + H + 0.9, 0),
			0.22,
			C.BRASS,
			M.Metal
		)
	)
	fine(
		b.rod(
			"TapSpout",
			V(L / 2 - 0.5, lift + H + 0.9, 0),
			V(L / 2 - 1.1, lift + H + 0.9, 0),
			0.18,
			C.BRASS,
			M.Metal
		)
	)
	for _, z in { -0.45, 0.45 } do
		fine(b.ball("TapHead", V(L / 2 - 0.5, lift + H + 1.0, z), 0.3, C.BRASS, M.Metal))
	end
	-- Something has run over the rim and down the side.
	fine(
		b.box(
			"Drip",
			V(0.5, 1.4, 0.04),
			V(-0.6, lift + H - 0.5, -W / 2 - 0.02),
			C.BLOOD_OLD,
			M.SmoothPlastic
		)
	)
	fine(
		b.box(
			"Drip",
			V(0.3, 0.9, 0.04),
			V(0.2, lift + H - 0.35, -W / 2 - 0.02),
			C.BLOOD_OLD,
			M.SmoothPlastic
		)
	)
	return b.model
end

function Furnish.toilet(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Toilet", at, parent)
	local china = Kit.rgb(64, 58, 50)
	b.rod("Pedestal", V(0, 0, 0.1), V(0, 1.4, 0.1), 1.0, china, M.SmoothPlastic)
	b.disc("Bowl", V(0, 1.6, -0.1), 1.8, 0.5, china, M.SmoothPlastic)
	fine(b.disc("Seat", V(0, 1.9, -0.1), 1.9, 0.14, C.WALNUT, M.Wood))
	fine(
		b.box(
			"Lid",
			V(1.8, 1.9, 0.12),
			V(0, 2.9, 0.75),
			C.WALNUT,
			M.Wood,
			CFrame.Angles(math.rad(8), 0, 0)
		)
	)
	-- High cistern on the wall, with a pull chain.
	fine(b.rod("FlushPipe", V(-0.4, 1.6, 0.8), V(-0.4, 7.5, 0.8), 0.24, C.IRON, M.CorrodedMetal))
	b.box("Cistern", V(2.2, 1.2, 1.0), V(-0.4, 8.1, 0.7), C.IRON, M.CorrodedMetal)
	fine(b.rod("Chain", V(0.4, 7.5, 0.4), V(0.4, 4.9, 0.4), 0.06, C.IRON, M.Metal))
	fine(b.ball("Pull", V(0.4, 4.8, 0.4), 0.26, C.WALNUT, M.Wood))
	return b.model
end

function Furnish.washstand(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Washstand", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	b.box("Top", V(3.6, 0.3, 2.0), V(0, 3.3, 0), C.SLATE, M.Slate)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			turnedLeg(b, x * 1.5, z * 0.75, 3.15, 0.3, wood)
		end
	end
	fine(b.box("Splashback", V(3.6, 1.2, 0.2), V(0, 4.0, 0.9), C.SLATE, M.Slate))
	fine(b.disc("Basin", V(0, 3.62, -0.1), 1.8, 0.35, Kit.rgb(64, 58, 50), M.SmoothPlastic))
	fine(b.disc("BasinWater", V(0, 3.8, -0.1), 1.5, 0.04, C.BLOOD_OLD, M.Glass))
	fine(b.disc("Jug", V(1.2, 4.0, 0.3), 0.7, 1.0, Kit.rgb(64, 58, 50), M.SmoothPlastic))
	fine(b.ball("JugBelly", V(1.2, 3.85, 0.3), 0.85, Kit.rgb(64, 58, 50), M.SmoothPlastic))
	-- A mirror above, on the wall behind.
	b.box("MirrorFrame", V(2.6, 3.0, 0.2), V(0, 6.6, 0.98), wood, M.Wood)
	local glass = fine(b.box("Mirror", V(2.1, 2.5, 0.05), V(0, 6.6, 0.86), C.GLASS_DARK, M.Glass))
	glass.Reflectance = 0.12
	return b.model
end

----------------------------------------------------------------------------
-- Attic, nursery, workshop
----------------------------------------------------------------------------

function Furnish.barrel(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Barrel", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local H: number = opt(o, "height", 3.4)
	local d: number = opt(o, "diameter", 2.4)
	-- A barrel bulges: a fat middle between two narrower ends.
	b.disc("Stave", V(0, H * 0.25, 0), d * 0.92, H * 0.5, wood, M.WoodPlanks)
	b.disc("Stave", V(0, H * 0.75, 0), d * 0.92, H * 0.5, wood, M.WoodPlanks)
	fine(b.disc("Belly", V(0, H * 0.5, 0), d, H * 0.45, wood, M.WoodPlanks))
	for _, y in { 0.12, 0.4, 0.6, 0.88 } do
		fine(
			b.disc(
				"Hoop",
				V(0, H * y, 0),
				(if y > 0.3 and y < 0.7 then d else d * 0.92) + 0.06,
				0.16,
				C.IRON,
				M.CorrodedMetal
			)
		)
	end
	fine(b.disc("Lid", V(0, H + 0.02, 0), d * 0.86, 0.06, C.WALNUT, M.Wood))
	return b.model
end

--[[
	A steamer trunk: round-topped lid, iron straps and corners, a hasp.
]]
function Furnish.trunk(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Trunk", at, parent)
	local cover: Color3 = opt(o, "cover", C.LEATHER)
	local W, D, H = 4.2, 2.4, 1.9
	b.box("Body", V(W, H, D), V(0, H / 2, 0), cover, M.Leather)
	-- The lid is a shallow dome: a cylinder narrower than the trunk, sunk so
	-- only its top half-stud shows above the lid's rim.
	b.box("LidBody", V(W, 0.5, D), V(0, H + 0.25, 0), cover, M.Leather)
	b.rod("LidDome", V(-W / 2, H - 0.08, 0), V(W / 2, H - 0.08, 0), D * 0.9, cover, M.Leather)
	for _, x in { -W / 2 + 0.5, -W / 6, W / 6, W / 2 - 0.5 } do
		fine(b.box("Strap", V(0.25, H + 0.05, D + 0.06), V(x, H / 2, 0), C.WALNUT, M.Wood))
		fine(
			b.rod(
				"StrapLid",
				V(x - 0.12, H - 0.08, 0),
				V(x + 0.12, H - 0.08, 0),
				D * 0.9 + 0.08,
				C.WALNUT,
				M.Wood
			)
		)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.box(
					"Corner",
					V(0.4, 0.4, 0.4),
					V(x * (W / 2 - 0.18), 0.2, z * (D / 2 - 0.18)),
					C.IRON,
					M.Metal
				)
			)
		end
	end
	fine(b.box("Hasp", V(0.4, 0.6, 0.08), V(0, H - 0.1, -D / 2 - 0.04), C.BRASS, M.Metal))
	return b.model
end

--[[
	A dressmaker's form on its stand: hips, waist and bust stacked on a pole,
	on three splayed feet. In a dark attic, the one thing that is exactly the
	height of a person.
]]
function Furnish.mannequin(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("DressForm", at, parent)
	local cloth: Color3 = opt(o, "cloth", C.LINEN)
	local wood = C.WALNUT
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		fine(
			b.rod(
				"Foot",
				V(0, 0.9, 0),
				V(math.cos(a) * 1.2, 0.08, math.sin(a) * 1.2),
				0.2,
				wood,
				M.Wood
			)
		)
	end
	b.rod("Pole", V(0, 0.2, 0), V(0, 3.2, 0), 0.26, wood, M.Wood)
	b.ball("Hips", V(0, 3.5, 0), 1.7, cloth, M.Fabric)
	fine(b.rod("Waist", V(0, 3.8, 0), V(0, 4.6, 0), 1.2, cloth, M.Fabric))
	b.ball("Bust", V(0, 4.9, 0), 1.85, cloth, M.Fabric)
	fine(b.rod("Shoulders", V(-0.95, 5.35, 0), V(0.95, 5.35, 0), 0.7, cloth, M.Fabric))
	fine(b.rod("Neck", V(0, 5.5, 0), V(0, 6.0, 0), 0.5, cloth, M.Fabric))
	fine(b.ball("NeckCap", V(0, 6.05, 0), 0.4, wood, M.Wood))
	-- A scrap of dress still pinned to it.
	soft(
		b.box(
			"Drape",
			V(2.0, 2.2, 0.08),
			V(0, 3.6, -0.86),
			opt(o, "dress", C.VELVET_DARK),
			M.Fabric,
			CFrame.Angles(math.rad(-6), 0, 0)
		)
	)
	return b.model
end

function Furnish.rockingHorse(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("RockingHorse", at, parent)
	local paint: Color3 = opt(o, "paint", Kit.rgb(72, 58, 46))
	local R = 5
	for _, x in { -0.8, 0.8 } do
		local prev: Vector3? = nil
		for k = -3, 3 do
			local a = math.rad(k * 9)
			local p = V(x, R - R * math.cos(a) + 0.15, R * math.sin(a))
			if prev then
				fine(b.rod("Rocker", prev, p, 0.26, C.WALNUT, M.Wood))
			end
			prev = p
		end
	end
	for _, x in { -0.35, 0.35 } do
		for _, z in { -1.1, 1.1 } do
			fine(b.rod("Leg", V(x * 2.2, 0.3, z * 1.25), V(x, 1.9, z), 0.24, paint, M.Wood))
		end
	end
	b.rod("Body", V(0, 2.2, -1.3), V(0, 2.2, 1.3), 1.25, paint, M.Wood)
	fine(b.rod("Neck", V(0, 2.4, -1.2), V(0, 3.5, -1.7), 0.7, paint, M.Wood))
	fine(
		b.box(
			"Head",
			V(0.6, 0.7, 1.3),
			V(0, 3.6, -2.05),
			paint,
			M.Wood,
			CFrame.Angles(math.rad(-20), 0, 0)
		)
	)
	for _, x in { -0.34, 0.34 } do
		fine(b.ball("Eye", V(x, 3.75, -2.2), 0.14, C.SOOT, M.SmoothPlastic))
	end
	fine(
		b.box(
			"Mane",
			V(0.2, 1.1, 0.9),
			V(0, 3.4, -1.3),
			C.SOOT,
			M.Fabric,
			CFrame.Angles(math.rad(-40), 0, 0)
		)
	)
	fine(b.rod("Tail", V(0, 2.4, 1.25), V(0, 1.4, 1.75), 0.3, C.SOOT, M.Fabric))
	fine(b.box("Saddle", V(1.3, 0.2, 1.1), V(0, 2.85, 0.05), C.VELVET, M.Leather))
	return b.model
end

--[[
	A doll sitting with its legs out: porcelain head (yellowed), cloth body.
	Put one where a player will turn a corner and find it looking at them.
]]
function Furnish.doll(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Doll", at, parent)
	local dress: Color3 = opt(o, "dress", C.VELVET)
	local s: number = opt(o, "scale", 1)
	local face = Kit.rgb(80, 68, 56)
	b.disc("Skirt", V(0, 0.28 * s, 0), 0.9 * s, 0.5 * s, dress, M.Fabric)
	fine(b.rod("Body", V(0, 0.5 * s, 0.05 * s), V(0, 1.05 * s, 0.08 * s), 0.5 * s, dress, M.Fabric))
	fine(b.ball("Head", V(0, 1.35 * s, 0.06 * s), 0.55 * s, face, M.SmoothPlastic))
	fine(b.ball("Hair", V(0, 1.45 * s, 0.14 * s), 0.52 * s, Kit.rgb(44, 30, 22), M.Fabric))
	for _, x in { -0.1, 0.1 } do
		fine(b.ball("Eye", V(x * s, 1.38 * s, -0.2 * s), 0.1 * s, C.SOOT, M.SmoothPlastic))
		fine(
			b.rod(
				"Leg",
				V(x * 1.4 * s, 0.12 * s, -0.1 * s),
				V(x * 1.6 * s, 0.1 * s, -0.75 * s),
				0.18 * s,
				face,
				M.SmoothPlastic
			)
		)
		fine(
			b.rod(
				"Arm",
				V(x * 2.6 * s, 0.95 * s, 0.05 * s),
				V(x * 3.2 * s, 0.55 * s, -0.15 * s),
				0.14 * s,
				face,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

----------------------------------------------------------------------------
-- Lodge
----------------------------------------------------------------------------

function Furnish.bunkBed(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin("BunkBed", at, parent)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local W, L = 3.8, 8.6
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod(
					"Post",
					V(x * W / 2, 0, z * L / 2),
					V(x * W / 2, 9.6, z * L / 2),
					0.5,
					wood,
					M.Wood
				)
			)
		end
	end
	for _, y in { 1.8, 6.4 } do
		for _, x in { -1, 1 } do
			b.box("SideRail", V(0.3, 0.6, L), V(x * W / 2, y, 0), wood, M.Wood)
		end
		b.box("Slats", V(W - 0.2, 0.2, L - 0.4), V(0, y + 0.1, 0), wood, M.WoodPlanks)
		b.box("Mattress", V(W - 0.5, 0.7, L - 0.6), V(0, y + 0.55, 0), C.CLOTH, M.Fabric)
		fine(
			b.rod(
				"Pillow",
				V(-W / 2 + 0.5, y + 1.1, L / 2 - 0.8),
				V(W / 2 - 0.5, y + 1.1, L / 2 - 0.8),
				0.8,
				C.LINEN,
				M.Fabric
			)
		)
		soft(
			b.box(
				"Blanket",
				V(W - 0.3, 0.12, L * 0.5),
				V(0, y + 0.95, -L * 0.2),
				Kit.rgb(70, 40, 34),
				M.Fabric
			)
		)
	end
	-- Guard rail on the top bunk, and a ladder at the foot.
	for _, y in { 7.6, 8.4 } do
		fine(
			b.rod(
				"GuardRail",
				V(-W / 2, y, -L / 2 + 0.2),
				V(-W / 2, y, L / 2 - 2.4),
				0.24,
				wood,
				M.Wood
			)
		)
	end
	for k = 0, 4 do
		local y = 1.3 + k * 1.3
		fine(
			b.rod(
				"Rung",
				V(-W / 2 + 0.3, y, -L / 2 - 0.05),
				V(W / 2 - 0.3, y, -L / 2 - 0.05),
				0.2,
				wood,
				M.Wood
			)
		)
	end
	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderBedHidingVolume",
			at * CFrame.new(0, 0.7, 0),
			V(W - 0.8, 1.2, L - 0.8),
			"UnderBed",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

--[[
	A pot-bellied wood stove on a stone hearth, its pipe going up through the
	roof. The belly is a ball; nothing about it is square.
]]
function Furnish.woodStove(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("WoodStove", at, parent)
	local pipeTop: number = opt(o, "pipeTop", 12)
	b.box("Hearth", V(5, 0.3, 5), V(0, 0.15, 0), C.STONE_DARK, M.Slate)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		fine(
			b.rod(
				"Leg",
				V(math.cos(a) * 1.1, 0.3, math.sin(a) * 1.1),
				V(math.cos(a) * 0.9, 1.1, math.sin(a) * 0.9),
				0.3,
				C.IRON,
				M.Metal
			)
		)
	end
	b.disc("Base", V(0, 1.3, 0), 2.4, 0.5, C.IRON, M.CorrodedMetal)
	b.ball("Belly", V(0, 2.6, 0), 2.9, C.IRON, M.CorrodedMetal)
	b.disc("Collar", V(0, 3.9, 0), 1.9, 0.4, C.IRON, M.CorrodedMetal)
	fine(b.disc("Top", V(0, 4.15, 0), 2.2, 0.2, C.IRON, M.Metal))
	fine(b.box("FireDoor", V(1.0, 0.9, 0.12), V(0, 2.5, -1.35), C.RUST, M.CorrodedMetal))
	fine(b.ball("DoorKnob", V(0.35, 2.5, -1.48), 0.2, C.BRASS, M.Metal))
	fine(b.rod("Pipe", V(0, 4.2, 0.3), V(0, pipeTop, 0.3), 0.8, C.IRON, M.CorrodedMetal))
	for _, y in { 6, 9 } do
		if y < pipeTop then
			fine(b.disc("PipeJoint", V(0, y, 0.3), 0.95, 0.14, C.IRON, M.Metal))
		end
	end
	return b.model
end

--[[
	A stack of split logs against a wall, the round ends out: the cheapest
	thing in the lodge and the most convincing, because every log is a real
	cylinder.
]]
function Furnish.firewood(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Firewood", at, parent)
	local W: number = opt(o, "width", 5)
	local rows: number = opt(o, "rows", 4)
	local wear = Kit.wear()
	local d = 0.8
	for r = 0, rows - 1 do
		local count = math.floor(W / d) - (r % 2)
		for k = 0, count - 1 do
			if r == rows - 1 and wear:NextNumber() < 0.35 then
				continue
			end
			local x = -W / 2 + d / 2 + k * d + (r % 2) * d / 2
			local y = d / 2 + r * d * 0.86
			local len = wear:NextNumber(2.4, 2.9)
			fine(
				b.rod(
					"Log",
					V(x, y, -len / 2),
					V(x, y, len / 2),
					d * wear:NextNumber(0.85, 1.0),
					Kit.weathered(Kit.rgb(70, 52, 38), 0.15),
					M.Wood
				)
			)
		end
	end
	-- One solid hidden core so the pile is something to bump into.
	local core =
		b.box("Core", V(W - 0.4, rows * d * 0.86, 2.2), V(0, rows * d * 0.43, 0), C.SOOT, M.Wood)
	core.Transparency = 1
	core.CastShadow = false
	return b.model
end

--[[
	A carpenter's bench: thick top, a vice, tools hanging on the wall behind.
	`wallTools` puts a rack of them on the wall behind the bench.
]]
function Furnish.workbench(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Workbench", at, parent)
	local wood: Color3 = opt(o, "wood", C.PINE)
	local L, W, H = 8, 3.2, 3.8
	b.box("Top", V(L, 0.6, W), V(0, H - 0.3, 0), wood, M.WoodPlanks)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b.box(
				"Leg",
				V(0.6, H - 0.6, 0.6),
				V(x * (L / 2 - 0.5), (H - 0.6) / 2, z * (W / 2 - 0.4)),
				C.OAK,
				M.Wood
			)
		end
	end
	b.box("Shelf", V(L - 1.2, 0.2, W - 0.6), V(0, 0.8, 0), wood, M.WoodPlanks)
	-- The vice at the front left.
	fine(b.box("ViceJaw", V(1.0, 0.8, 0.3), V(-L / 2 + 1.2, H - 0.4, -W / 2 - 0.2), C.OAK, M.Wood))
	fine(
		b.rod(
			"ViceScrew",
			V(-L / 2 + 1.2, H - 0.45, -W / 2 - 0.35),
			V(-L / 2 + 1.2, H - 0.45, -W / 2 - 1.0),
			0.14,
			C.IRON,
			M.Metal
		)
	)
	fine(
		b.rod(
			"ViceBar",
			V(-L / 2 + 0.7, H - 0.45, -W / 2 - 1.0),
			V(-L / 2 + 1.7, H - 0.45, -W / 2 - 1.0),
			0.1,
			C.IRON,
			M.Metal
		)
	)
	-- A saw and a hand axe left on the top.
	fine(
		b.box(
			"SawBlade",
			V(2.6, 0.03, 0.8),
			V(1.2, H + 0.02, 0.2),
			C.IRON,
			M.CorrodedMetal,
			CFrame.Angles(0, 0.3, 0)
		)
	)
	fine(
		b.box(
			"SawHandle",
			V(0.7, 0.2, 0.7),
			V(2.5, H + 0.1, 0.65),
			C.WALNUT,
			M.Wood,
			CFrame.Angles(0, 0.3, 0)
		)
	)
	fine(b.rod("AxeHandle", V(-1.2, H + 0.15, -0.2), V(0.6, H + 0.15, -0.6), 0.22, C.OAK, M.Wood))
	fine(
		b.box(
			"AxeHead",
			V(0.3, 0.2, 0.9),
			V(-1.25, H + 0.18, -0.15),
			C.RUST,
			M.CorrodedMetal,
			CFrame.Angles(0, -0.22, 0)
		)
	)
	if opt(o, "wallTools", false) then
		b.box("ToolBoard", V(L - 1, 3.2, 0.2), V(0, H + 2.4, W / 2 + 0.05), wood, M.WoodPlanks)
		for i = -3, 3 do
			local x = i * 0.95
			fine(
				b.rod(
					"Peg",
					V(x, H + 3.4, W / 2 - 0.05),
					V(x, H + 3.4, W / 2 - 0.45),
					0.1,
					C.IRON,
					M.Metal
				)
			)
			if i % 2 == 0 then
				fine(
					b.rod(
						"Handle",
						V(x, H + 3.3, W / 2 - 0.3),
						V(x + 0.05, H + 1.7, W / 2 - 0.3),
						0.16,
						C.OAK,
						M.Wood
					)
				)
			else
				fine(
					b.box(
						"Blade",
						V(0.1, 1.2, 0.6),
						V(x, H + 2.7, W / 2 - 0.3),
						C.IRON,
						M.CorrodedMetal
					)
				)
			end
		end
	end
	return b.model
end

----------------------------------------------------------------------------
-- The villa's pieces
----------------------------------------------------------------------------

--[[
	An iron bedstead: round tube posts with brass knobs, a rail and spindles
	at the head and the foot, a mattress that has sagged in the middle. The
	frame stands high on small casters, so the dark under it is a place to
	hide for anyone willing to lie down in it.
]]
function Furnish.ironBed(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin(opt(o, "name", "IronBed"), at, parent)
	local iron: Color3 = opt(o, "iron", C.IRON)
	local sheet: Color3 = opt(o, "sheet", C.LINEN)
	local blanket: Color3 = opt(o, "blanket", C.CLOTH)
	local W: number = opt(o, "width", 5.2)
	local L: number = opt(o, "length", 9.4)
	local frameY = 2.0

	for _, z in { -1, 1 } do
		local h = if z > 0 then 5.4 else 3.8
		for _, x in { -1, 1 } do
			local px, pz = x * W / 2, z * L / 2
			fine(b.rod("Post", V(px, 0.25, pz), V(px, h, pz), 0.36, iron, M.Metal))
			fine(b.ball("Knob", V(px, h + 0.12, pz), 0.5, C.BRASS, M.Metal))
			fine(b.ball("Caster", V(px, 0.2, pz), 0.4, iron, M.Metal))
		end
		-- Top rail and a lower rail, with round spindles between.
		for _, y in { h - 0.35, frameY + 0.9 } do
			fine(
				b.rod("Rail", V(-W / 2, y, z * L / 2), V(W / 2, y, z * L / 2), 0.24, iron, M.Metal)
			)
		end
		local spindles = if z > 0 then 7 else 5
		for i = 1, spindles do
			local x = -W / 2 + W * i / (spindles + 1)
			fine(
				b.rod(
					"Spindle",
					V(x, frameY + 0.9, z * L / 2),
					V(x, h - 0.35, z * L / 2),
					0.14,
					iron,
					M.Metal
				)
			)
		end
		-- A brass collar on the head's middle spindle, gone green-black.
		fine(
			b.disc("Collar", V(0, (h + frameY) / 2 + 0.6, z * L / 2), 0.32, 0.22, C.BRASS, M.Metal)
		)
	end
	for _, x in { -1, 1 } do
		fine(
			b.rod(
				"SideRail",
				V(x * W / 2, frameY, -L / 2),
				V(x * W / 2, frameY, L / 2),
				0.24,
				iron,
				M.Metal
			)
		)
	end
	-- The mattress, sagging: two halves tipped a little toward the middle.
	local mY = frameY + 0.55
	for _, z in { -1, 1 } do
		b.box(
			"Mattress",
			V(W - 0.5, 0.9, L / 2 - 0.3),
			V(0, mY, z * (L / 4 - 0.1)),
			sheet,
			M.Fabric,
			CFrame.Angles(z * math.rad(-3), 0, 0)
		)
	end
	fine(
		b.rod(
			"Pillow",
			V(-W / 2 + 0.8, mY + 0.75, L / 2 - 1.1),
			V(W / 2 - 0.8, mY + 0.75, L / 2 - 1.1),
			0.9,
			sheet,
			M.Fabric
		)
	)
	soft(
		b.box(
			"Blanket",
			V(W - 0.2, 0.12, L * 0.45),
			V(0.2, mY + 0.5, -L * 0.22),
			blanket,
			M.Fabric,
			CFrame.Angles(0, math.rad(-6), 0)
		)
	)
	soft(
		b.box(
			"BlanketDrop",
			V(0.12, 1.5, L * 0.4),
			V(W / 2 + 0.1, mY - 0.3, -L * 0.2),
			blanket,
			M.Fabric
		)
	)
	fine(b.disc("Stain", V(-0.5, mY + 0.47, 0.8), 1.4, 0.04, C.BLOOD_OLD, M.Fabric))

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderBedHidingVolume",
			at * CFrame.new(0, 0.85, 0),
			V(W - 0.8, 1.5, L - 1.0),
			"UnderBed",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

--[[
	A dressing table: turned legs, a drawer, and a round mirror on two posts
	behind, clouded and cracked. Bottles and a brush left where they were put
	down.
]]
function Furnish.dressingTable(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("DressingTable", at, parent)
	local wood: Color3 = opt(o, "wood", C.MAHOGANY)
	local W, D, H = 4.4, 2.0, 3.0
	b.box("Top", V(W, 0.2, D), V(0, H - 0.1, 0), wood, M.Wood)
	fine(
		b.rod("TopEdge", V(-W / 2, H - 0.1, -D / 2), V(W / 2, H - 0.1, -D / 2), 0.26, wood, M.Wood)
	)
	b.box("Apron", V(W - 0.4, 0.7, D - 0.3), V(0, H - 0.55, 0.1), wood, M.Wood)
	fine(b.box("Drawer", V(1.6, 0.5, 0.1), V(0, H - 0.55, -D / 2 + 0.1), C.WALNUT, M.Wood))
	knob(b, V(0, H - 0.55, -D / 2 + 0.05), V(0, 0, -1))
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			turnedLeg(b, x * (W / 2 - 0.3), z * (D / 2 - 0.3), H - 0.9, 0.28, wood)
		end
	end
	-- Mirror posts and the round mirror between them.
	local my = H + 2.4
	for _, x in { -1, 1 } do
		fine(
			b.rod(
				"MirrorPost",
				V(x * 1.55, H, D / 2 - 0.3),
				V(x * 1.55, my + 0.4, D / 2 - 0.3),
				0.22,
				wood,
				M.Wood
			)
		)
		fine(b.ball("MirrorFinial", V(x * 1.55, my + 0.55, D / 2 - 0.3), 0.3, wood, M.Wood))
		fine(b.ball("MirrorPivot", V(x * 1.42, my, D / 2 - 0.3), 0.22, C.BRASS, M.Metal))
	end
	local face = CFrame.Angles(math.pi / 2 - math.rad(8), 0, 0)
	fine(b.disc("MirrorFrame", V(0, my, D / 2 - 0.3), 2.7, 0.18, wood, M.Wood, face))
	local glass =
		fine(b.disc("Mirror", V(0, my, D / 2 - 0.42), 2.3, 0.05, C.GLASS_DARK, M.Glass, face))
	glass.Reflectance = 0.12
	for k = 0, 2 do
		fine(
			b.box(
				"Crack",
				V(0.04, 1.5, 0.02),
				V(0.2 - k * 0.15, my + 0.1, D / 2 - 0.46),
				C.SOOT,
				M.SmoothPlastic,
				CFrame.Angles(math.rad(-8), 0, math.rad(-30 + k * 35))
			)
		)
	end
	-- What is on top.
	local wear = Kit.wear()
	for i = 1, 4 do
		local x = -1.8 + i * 0.5 + wear:NextNumber(-0.1, 0.1)
		local h = wear:NextNumber(0.35, 0.7)
		fine(b.disc("Bottle", V(x, H + h / 2, -0.2), 0.28, h, Kit.rgb(40, 34, 30), M.Glass))
	end
	fine(
		b.box(
			"BrushBack",
			V(0.9, 0.12, 0.35),
			V(1.2, H + 0.08, -0.4),
			wood,
			M.Wood,
			CFrame.Angles(0, 0.5, 0)
		)
	)
	fine(
		b.box(
			"Bristles",
			V(0.8, 0.1, 0.28),
			V(1.2, H + 0.18, -0.4),
			C.SOOT,
			M.Fabric,
			CFrame.Angles(0, 0.5, 0)
		)
	)
	return b.model
end

--[[
	A hall stand: a turned pole on a round foot, hooks near the top with a
	coat and a hat still on them, and a ring lower down with an umbrella in
	it. From the far end of a dark hall, a figure.
]]
function Furnish.hallStand(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("HallStand", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local H = 6.6
	b.disc("Foot", V(0, 0.12, 0), 2.0, 0.24, wood, M.Wood)
	fine(b.disc("FootStep", V(0, 0.3, 0), 1.3, 0.14, wood, M.Wood))
	b.rod("Pole", V(0, 0.2, 0), V(0, H, 0), 0.36, wood, M.Wood)
	fine(b.ball("PoleKnop", V(0, 1.4, 0), 0.6, wood, M.Wood))
	fine(b.ball("Top", V(0, H + 0.15, 0), 0.55, wood, M.Wood))
	for i = 0, 5 do
		local a = i * math.pi / 3
		local d = V(math.cos(a), 0, math.sin(a))
		fine(b.rod("Hook", V(0, H - 0.6, 0), d * 0.9 + V(0, H - 0.2, 0), 0.12, C.BRASS, M.Metal))
		fine(b.ball("HookEnd", d * 0.95 + V(0, H - 0.15, 0), 0.16, C.BRASS, M.Metal))
	end
	-- The umbrella ring.
	for i = 0, 5 do
		local a0, a1 = i * math.pi / 3, (i + 1) * math.pi / 3
		fine(
			b.rod(
				"Ring",
				V(math.cos(a0) * 0.7, 2.2, math.sin(a0) * 0.7),
				V(math.cos(a1) * 0.7, 2.2, math.sin(a1) * 0.7),
				0.08,
				C.BRASS,
				M.Metal
			)
		)
	end
	fine(b.rod("Umbrella", V(0.55, 0.3, 0.2), V(0.75, 3.4, 0.35), 0.4, C.SOOT, M.Fabric))
	fine(b.rod("UmbrellaHandle", V(0.75, 3.4, 0.35), V(0.8, 3.9, 0.3), 0.12, wood, M.Wood))
	-- A long coat on one hook and a hat on another.
	soft(
		b.box(
			"Coat",
			V(1.5, 4.2, 0.5),
			V(0, H - 2.4, -0.62),
			C.CLOTH,
			M.Fabric,
			CFrame.Angles(math.rad(4), 0, 0)
		)
	)
	fine(
		b.rod(
			"CoatShoulders",
			V(-0.75, H - 0.4, -0.55),
			V(0.75, H - 0.4, -0.55),
			0.5,
			C.CLOTH,
			M.Fabric
		)
	)
	fine(
		b.disc(
			"HatBrim",
			V(0.75, H - 0.05, 0.45),
			1.3,
			0.08,
			C.SOOT,
			M.Fabric,
			CFrame.Angles(0, 0, 0.3)
		)
	)
	fine(
		b.disc(
			"HatCrown",
			V(0.72, H + 0.28, 0.45),
			0.8,
			0.6,
			C.SOOT,
			M.Fabric,
			CFrame.Angles(0, 0, 0.3)
		)
	)
	return b.model
end

--[[
	A brass telescope on a wooden tripod, left pointing out at nothing.
]]
function Furnish.telescope(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Telescope", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local head = V(0, 3.6, 0)
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3 + math.pi / 6
		local foot = V(math.cos(a) * 1.4, 0, math.sin(a) * 1.4)
		fine(b.rod("Leg", foot, head, 0.2, wood, M.Wood))
		fine(b.ball("Foot", foot + V(0, 0.08, 0), 0.24, C.BRASS, M.Metal))
	end
	fine(b.ball("Mount", head + V(0, 0.15, 0), 0.5, C.BRASS, M.Metal))
	local tilt = math.rad(opt(o, "elevation", 18))
	local dir = V(0, math.sin(tilt), -math.cos(tilt))
	local mid = head + V(0, 0.45, 0)
	fine(b.rod("Tube", mid - dir * 1.6, mid + dir * 2.2, 0.55, C.BRASS, M.Metal))
	fine(b.rod("Tube", mid + dir * 2.2, mid + dir * 2.9, 0.68, C.BRASS, M.Metal))
	fine(b.rod("Eyepiece", mid - dir * 1.6, mid - dir * 2.2, 0.28, C.BRASS, M.Metal))
	fine(b.rod("Band", mid + dir * 0.2, mid + dir * 0.4, 0.62, C.SOOT, M.Metal))
	return b.model
end

--[[
	A treadle sewing machine: an iron frame with a wheel and a foot plate, a
	wooden top, and the machine's black arched head with a spool on it.
]]
function Furnish.sewingMachine(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("SewingMachine", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local W, D, H = 3.6, 1.8, 3.1
	b.box("Top", V(W, 0.2, D), V(0, H - 0.1, 0), wood, M.Wood)
	fine(
		b.rod("TopEdge", V(-W / 2, H - 0.1, -D / 2), V(W / 2, H - 0.1, -D / 2), 0.24, wood, M.Wood)
	)
	for _, x in { -1, 1 } do
		local lx = x * (W / 2 - 0.35)
		b.box("Frame", V(0.2, H - 0.2, 0.3), V(lx, (H - 0.2) / 2, 0), C.IRON, M.Metal)
		fine(b.box("Foot", V(0.3, 0.2, D - 0.2), V(lx, 0.1, 0), C.IRON, M.Metal))
		fine(
			b.disc(
				"Scroll",
				V(lx, 1.2, 0),
				0.9,
				0.18,
				C.IRON,
				M.Metal,
				CFrame.Angles(0, 0, math.pi / 2)
			)
		)
	end
	fine(
		b.box(
			"Treadle",
			V(W - 1.2, 0.12, 1.1),
			V(0, 0.5, -0.1),
			C.IRON,
			M.Metal,
			CFrame.Angles(math.rad(-10), 0, 0)
		)
	)
	fine(
		b.disc(
			"Wheel",
			V(W / 2 - 0.65, 1.8, 0),
			1.9,
			0.12,
			C.IRON,
			M.Metal,
			CFrame.Angles(0, 0, math.pi / 2)
		)
	)
	fine(
		b.rod(
			"Belt",
			V(W / 2 - 0.65, 2.7, 0),
			V(W / 2 - 0.65, H + 0.6, 0.2),
			0.05,
			C.LEATHER_DARK,
			M.Leather
		)
	)
	-- The head: bed, pillar, arm, needle bar.
	b.box("MachineBed", V(2.4, 0.3, 1.0), V(-0.2, H + 0.15, 0), C.SOOT, M.Metal)
	b.box("Pillar", V(0.5, 1.3, 0.6), V(0.7, H + 0.95, 0), C.SOOT, M.Metal)
	b.box("Arm", V(1.9, 0.45, 0.55), V(-0.05, H + 1.35, 0), C.SOOT, M.Metal)
	fine(b.rod("HandWheel", V(1.0, H + 1.2, 0), V(1.15, H + 1.2, 0), 0.9, C.SOOT, M.Metal))
	fine(b.rod("NeedleBar", V(-0.9, H + 1.2, 0), V(-0.9, H + 0.4, 0), 0.1, C.IRON, M.Metal))
	fine(b.disc("Spool", V(0.1, H + 1.7, 0), 0.3, 0.35, C.VELVET, M.Fabric))
	-- Cloth still under the needle, hanging off the front.
	soft(b.box("Cloth", V(1.6, 0.05, 1.4), V(-0.9, H + 0.33, -0.3), C.VELVET_DARK, M.Fabric))
	soft(
		b.box(
			"ClothDrop",
			V(1.4, 1.2, 0.05),
			V(-0.9, H - 0.3, -D / 2 - 0.12),
			C.VELVET_DARK,
			M.Fabric
		)
	)
	return b.model
end

--[[
	A stone urn on a foot, with what is left of a shrub in it: bare
	branches, forking twice. The branches do not collide; the urn does.
]]
function Furnish.planter(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Planter", at, parent)
	local stone: Color3 = opt(o, "stone", C.STONE_DARK)
	b.box("Plinth", V(1.8, 0.4, 1.8), V(0, 0.2, 0), stone, M.Concrete)
	b.disc("Foot", V(0, 0.6, 0), 1.0, 0.4, stone, M.Concrete)
	b.disc("Bowl", V(0, 1.3, 0), 2.0, 1.0, stone, M.Concrete)
	fine(b.disc("Rim", V(0, 1.85, 0), 2.3, 0.2, stone, M.Concrete))
	fine(b.disc("Soil", V(0, 1.82, 0), 1.9, 0.06, C.GRIME, M.Ground))
	local wear = Kit.wear()
	local bark = Kit.rgb(40, 32, 26)
	local function branch(from: Vector3, dir: Vector3, len: number, d: number, depth: number)
		local to = from + dir * len
		fine(b.rod("Branch", from, to, d, bark, M.Wood))
		if depth > 0 then
			for _ = 1, 2 do
				local turn = CFrame.Angles(
					wear:NextNumber(-0.7, 0.7),
					wear:NextNumber(0, math.pi * 2),
					wear:NextNumber(-0.7, 0.7)
				)
				local nd = (turn:VectorToWorldSpace(dir) + V(0, 0.35, 0)).Unit
				branch(to, nd, len * 0.62, d * 0.65, depth - 1)
			end
		end
	end
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3 + wear:NextNumber(-0.3, 0.3)
		branch(V(0, 1.8, 0), V(math.cos(a) * 0.45, 1, math.sin(a) * 0.45).Unit, 1.3, 0.16, 2)
	end
	return b.model
end

--[[
	A washing line between two posts, with rags that were sheets once.
	The posts are taller than a jump, and nothing on the line holds weight.
]]
function Furnish.clothesline(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Clothesline", at, parent)
	local span: number = opt(o, "span", 14)
	local wood = Kit.rgb(52, 42, 34)
	local H = 9
	for _, x in { -1, 1 } do
		local px = x * span / 2
		b.rod("Post", V(px, 0, 0), V(px, H, 0), 0.45, wood, M.Wood)
		fine(b.rod("Crossbar", V(px, H - 0.6, -1.2), V(px, H - 0.6, 1.2), 0.24, wood, M.Wood))
		fine(b.box("PostFoot", V(1.0, 0.5, 1.0), V(px, 0.25, 0), C.STONE_DARK, M.Concrete))
	end
	local wear = Kit.wear()
	for _, z in { -1, 1 } do
		local lineZ = z * 1.0
		-- Two straight lengths meeting low in the middle: a line sags.
		local sag = V(0, H - 1.3, lineZ)
		fine(b.rod("Line", V(-span / 2, H - 0.6, lineZ), sag, 0.05, C.SOOT, M.Fabric))
		fine(b.rod("Line", sag, V(span / 2, H - 0.6, lineZ), 0.05, C.SOOT, M.Fabric))
		local x = -span / 2 + 1.5
		while x < span / 2 - 1.5 do
			local w = wear:NextNumber(1.4, 3.0)
			local drop = wear:NextNumber(2.5, 4.5)
			local t = math.abs(x + w / 2) / (span / 2)
			local y = (H - 1.3) + 0.7 * t
			soft(
				b.box(
					"Rag",
					V(w, drop, 0.06),
					V(x + w / 2, y - drop / 2, lineZ),
					Kit.weathered(if wear:NextNumber() < 0.5 then C.CLOTH else C.MOULD, 0.1),
					M.Fabric,
					CFrame.Angles(0, 0, math.rad(wear:NextNumber(-4, 4)))
				)
			)
			x += w + wear:NextNumber(0.4, 1.6)
		end
	end
	return b.model
end

--[[
	A bust on a pedestal: a square base, a round shaft, a cap, and a head and
	shoulders in dark bronze. The eyes are two hollows.
]]
function Furnish.bust(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Bust", at, parent)
	local stone: Color3 = opt(o, "stone", C.STONE_DARK)
	local bronze: Color3 = opt(o, "bronze", Kit.rgb(52, 44, 34))
	b.box("Base", V(1.6, 0.5, 1.6), V(0, 0.25, 0), stone, M.Marble)
	b.rod("Shaft", V(0, 0.5, 0), V(0, 3.2, 0), 1.0, stone, M.Marble)
	fine(b.disc("ShaftRing", V(0, 0.75, 0), 1.25, 0.25, stone, M.Marble))
	b.box("Cap", V(1.5, 0.35, 1.5), V(0, 3.35, 0), stone, M.Marble)
	b.box("Chest", V(1.5, 0.8, 0.8), V(0, 3.95, 0), bronze, M.Metal)
	fine(b.rod("Shoulders", V(-0.75, 4.25, 0), V(0.75, 4.25, 0), 0.7, bronze, M.Metal))
	b.rod("Neck", V(0, 4.3, 0), V(0, 4.8, 0), 0.4, bronze, M.Metal)
	b.ball("Head", V(0, 5.15, -0.02), 0.95, bronze, M.Metal)
	for _, x in { -0.17, 0.17 } do
		fine(b.ball("Eye", V(x, 5.22, -0.43), 0.14, C.SOOT, M.SmoothPlastic))
	end
	return b.model
end

--[[
	A packing crate: a box with planks round its edges and a lid not quite
	on. `size` is its outside size.
]]
function Furnish.crate(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Crate", at, parent)
	local size: Vector3 = opt(o, "size", V(3, 2.6, 3))
	local wood: Color3 = opt(o, "wood", C.PINE)
	local sx, sy, sz = size.X, size.Y, size.Z
	b.box(
		"Body",
		V(sx - 0.2, sy - 0.2, sz - 0.2),
		V(0, sy / 2, 0),
		Kit.weathered(wood, 0.1),
		M.WoodPlanks
	)
	for _, y in { 0.15, sy - 0.15 } do
		for _, z in { -1, 1 } do
			fine(b.box("Batten", V(sx, 0.3, 0.1), V(0, y, z * (sz / 2 - 0.05)), wood, M.Wood))
		end
		for _, x in { -1, 1 } do
			fine(b.box("Batten", V(0.1, 0.3, sz - 0.2), V(x * (sx / 2 - 0.05), y, 0), wood, M.Wood))
		end
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			fine(
				b.box(
					"Post",
					V(0.3, sy, 0.3),
					V(x * (sx / 2 - 0.15), sy / 2, z * (sz / 2 - 0.15)),
					wood,
					M.Wood
				)
			)
		end
	end
	if opt(o, "lid", true) then
		fine(
			b.box(
				"Lid",
				V(sx, 0.16, sz),
				V(0.25, sy + 0.08, -0.2),
				wood,
				M.WoodPlanks,
				CFrame.Angles(0, 0.08, 0)
			)
		)
	end
	return b.model
end

--[[
	A wrought-iron garden chair: a round seat, four legs, a hooped back.
]]
function Furnish.gardenChair(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("GardenChair", at, parent)
	local iron: Color3 = opt(o, "iron", C.IRON)
	local seatY = 2.2
	b.disc("Seat", V(0, seatY, 0), 2.0, 0.14, iron, M.CorrodedMetal)
	fine(b.disc("SeatRing", V(0, seatY - 0.12, 0), 2.1, 0.1, iron, M.CorrodedMetal))
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local top = V(math.cos(a) * 0.75, seatY - 0.1, math.sin(a) * 0.75)
		local foot = V(math.cos(a) * 0.95, 0, math.sin(a) * 0.95)
		fine(b.rod("Leg", foot, top, 0.14, iron, M.CorrodedMetal))
		fine(b.ball("Foot", foot + V(0, 0.07, 0), 0.2, iron, M.CorrodedMetal))
	end
	-- The back: a hoop of short straight bars round the rear half.
	local prev: Vector3? = nil
	for k = 0, 6 do
		local a = math.pi + k * math.pi / 6
		local p = V(
			math.cos(a) * 0.95,
			seatY + 2.2 + math.sin(k * math.pi / 6) * 0.35,
			-math.sin(a) * 0.95
		)
		if prev then
			fine(b.rod("Hoop", prev, p, 0.12, iron, M.CorrodedMetal))
		end
		if k % 2 == 0 then
			fine(b.rod("BackBar", V(p.X * 0.95, seatY, p.Z * 0.95), p, 0.1, iron, M.CorrodedMetal))
		end
		prev = p
	end
	return b.model
end

-- A round wrought-iron garden table on a single stem and three feet.
function Furnish.gardenTable(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("GardenTable", at, parent)
	local iron: Color3 = opt(o, "iron", C.IRON)
	local H = 3.0
	b.disc("Top", V(0, H - 0.08, 0), opt(o, "diameter", 3.2), 0.16, iron, M.CorrodedMetal)
	fine(b.disc("TopRing", V(0, H - 0.22, 0), 1.2, 0.12, iron, M.CorrodedMetal))
	b.rod("Stem", V(0, 0.3, 0), V(0, H - 0.1, 0), 0.3, iron, M.CorrodedMetal)
	fine(b.ball("Knop", V(0, 1.3, 0), 0.5, iron, M.CorrodedMetal))
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		fine(
			b.rod(
				"Foot",
				V(0, 0.45, 0),
				V(math.cos(a) * 1.2, 0.05, math.sin(a) * 1.2),
				0.16,
				iron,
				M.CorrodedMetal
			)
		)
	end
	return b.model
end

--[[
	A weather vane for a roof's peak: a post, two balls, the four arms of the
	compass and an arrow that has rusted pointing the same way for years.
	`at` is on the peak.
]]
function Furnish.weatherVane(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("WeatherVane", at, parent)
	local iron: Color3 = opt(o, "iron", C.RUST)
	fine(b.rod("Post", V(0, 0, 0), V(0, 5.5, 0), 0.16, iron, M.CorrodedMetal))
	fine(b.ball("Ball", V(0, 1.2, 0), 0.6, iron, M.CorrodedMetal))
	fine(b.ball("Ball", V(0, 4.2, 0), 0.4, iron, M.CorrodedMetal))
	for i = 0, 3 do
		local a = i * math.pi / 2
		local d = V(math.cos(a), 0, math.sin(a))
		fine(b.rod("Arm", V(0, 2.4, 0), d * 1.3 + V(0, 2.4, 0), 0.08, iron, M.CorrodedMetal))
		fine(b.ball("ArmEnd", d * 1.35 + V(0, 2.4, 0), 0.18, iron, M.CorrodedMetal))
	end
	local y = 5.0
	fine(b.rod("Arrow", V(-1.8, y, 0), V(1.6, y, 0), 0.1, iron, M.CorrodedMetal))
	b.tri(
		"ArrowHead",
		V(-2.4, y, 0),
		V(-1.6, y + 0.35, 0),
		V(-1.6, y - 0.35, 0),
		0.06,
		iron,
		M.CorrodedMetal
	)
	b.tri("Tail", V(1.0, y, 0), V(1.9, y + 0.9, 0), V(1.9, y - 0.2, 0), 0.06, iron, M.CorrodedMetal)
	return b.model
end

----------------------------------------------------------------------------
-- The lodge's pieces
----------------------------------------------------------------------------

local FUR = Kit.rgb(48, 36, 28)
local FUR_GREY = Kit.rgb(54, 48, 42)
local CLAW = Kit.rgb(40, 34, 28)

--[[
	A bed of whole logs: round posts and rails, peeled spindles at the head,
	a straw mattress under a patchwork quilt and a fur at the foot. High
	enough on its rails to lie under.
]]
function Furnish.logBed(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin(opt(o, "name", "LogBed"), at, parent)
	local log: Color3 = opt(o, "log", Kit.rgb(70, 52, 38))
	local W: number = opt(o, "width", 6.2)
	local L: number = opt(o, "length", 9.8)
	local railY = 1.8
	for _, z in { -1, 1 } do
		local h = if z > 0 then 6.2 else 3.8
		for _, x in { -1, 1 } do
			local px, pz = x * W / 2, z * L / 2
			b.rod("Post", V(px, 0, pz), V(px, h, pz), 0.8, log, M.Wood)
			fine(b.disc("PostEnd", V(px, h + 0.02, pz), 0.66, 0.06, Kit.rgb(88, 70, 50), M.Wood))
		end
		for _, y in
			(if z > 0 then { railY + 0.7, h - 0.7 } else { railY + 0.7, h - 0.5 }) :: { number }
		do
			b.rod("HeadRail", V(-W / 2, y, z * L / 2), V(W / 2, y, z * L / 2), 0.5, log, M.Wood)
		end
		local spindles = if z > 0 then 6 else 4
		local top = if z > 0 then h - 0.7 else h - 0.5
		for i = 1, spindles do
			local x = -W / 2 + W * i / (spindles + 1)
			fine(
				b.rod(
					"Spindle",
					V(x, railY + 0.7, z * L / 2),
					V(x, top, z * L / 2),
					0.28,
					log,
					M.Wood
				)
			)
		end
	end
	for _, x in { -1, 1 } do
		b.rod(
			"SideRail",
			V(x * W / 2, railY, -L / 2),
			V(x * W / 2, railY, L / 2),
			0.55,
			log,
			M.Wood
		)
	end
	local mY = railY + 0.55
	b.box("Mattress", V(W - 0.9, 0.8, L - 1.0), V(0, mY, 0), C.CLOTH, M.Fabric)
	fine(
		b.rod(
			"Pillow",
			V(-W / 2 + 0.9, mY + 0.7, L / 2 - 1.2),
			V(W / 2 - 0.9, mY + 0.7, L / 2 - 1.2),
			0.9,
			C.LINEN,
			M.Fabric
		)
	)
	-- A patchwork quilt: squares in the house's dark colours.
	local patches = { C.VELVET_DARK, C.CLOTH, C.RUG_BORDER, C.LEATHER, C.MOULD, C.VELVET }
	local n = 0
	for i = 0, 2 do
		for j = 0, 3 do
			n += 1
			local w, d = (W - 0.6) / 3, (L * 0.62) / 4
			soft(
				b.box(
					"Quilt",
					V(w - 0.02, 0.1, d - 0.02),
					V(-W / 2 + 0.3 + w * (i + 0.5), mY + 0.46, -L / 2 + 0.6 + d * (j + 0.5)),
					Kit.weathered(patches[(n % #patches) + 1], 0.08),
					M.Fabric
				)
			)
		end
	end
	soft(
		b.box(
			"QuiltDrop",
			V(0.1, 1.4, L * 0.6),
			V(W / 2 - 0.35, mY - 0.25, -L * 0.18),
			C.VELVET_DARK,
			M.Fabric
		)
	)
	soft(
		b.box(
			"Fur",
			V(W - 0.4, 0.2, 2.2),
			V(0, mY + 0.55, -L / 2 + 1.4),
			FUR,
			M.Fabric,
			CFrame.Angles(0, 0.08, 0)
		)
	)
	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderBedHidingVolume",
			at * CFrame.new(0, 0.75, 0),
			V(W - 1.0, 1.3, L - 1.2),
			"UnderBed",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

--[[
	A black bear on its hind legs on a board, forelegs up, mouth open. It was
	shot, stuffed and stood in the corner a long time ago, and it is the
	height of a tall man with its arms raised.
]]
function Furnish.bearMount(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("BearMount", at, parent)
	local fur: Color3 = opt(o, "fur", Kit.rgb(34, 28, 24))
	b.box("Base", V(4.2, 0.6, 3.6), V(0, 0.3, 0), C.WALNUT, M.Wood)
	fine(b.rod("BaseEdge", V(-2.1, 0.6, -1.8), V(2.1, 0.6, -1.8), 0.24, C.WALNUT, M.Wood))
	for _, x in { -0.8, 0.8 } do
		b.rod("Leg", V(x, 0.8, 0.1), V(x, 3.6, 0.2), 1.5, fur, M.Fabric)
		fine(b.ball("Foot", V(x, 0.95, -0.25), 1.2, fur, M.Fabric))
	end
	b.ball("Hips", V(0, 3.7, 0.25), 3.0, fur, M.Fabric)
	b.rod("Body", V(0, 3.8, 0.25), V(0, 6.6, -0.1), 3.0, fur, M.Fabric)
	b.ball("Chest", V(0, 6.5, -0.15), 2.8, fur, M.Fabric)
	b.rod("Neck", V(0, 7.2, -0.2), V(0, 7.8, -0.5), 1.6, fur, M.Fabric)
	b.ball("Head", V(0, 8.2, -0.6), 1.9, fur, M.Fabric)
	fine(b.rod("Snout", V(0, 8.0, -1.2), V(0, 7.85, -2.1), 0.95, Kit.rgb(52, 40, 32), M.Fabric))
	fine(b.ball("Nose", V(0, 7.95, -2.15), 0.42, C.SOOT, M.SmoothPlastic))
	fine(
		b.box(
			"Mouth",
			V(0.7, 0.28, 0.8),
			V(0, 7.55, -1.75),
			Kit.rgb(40, 14, 12),
			M.SmoothPlastic,
			CFrame.Angles(math.rad(-18), 0, 0)
		)
	)
	for _, x in { -0.28, 0.28 } do
		fine(b.rod("Fang", V(x, 7.72, -2.0), V(x, 7.45, -2.0), 0.1, C.BONE, M.SmoothPlastic))
	end
	for _, x in { -0.6, 0.6 } do
		fine(b.ball("Ear", V(x, 9.0, -0.4), 0.6, fur, M.Fabric))
		fine(b.ball("Eye", V(x * 0.62, 8.45, -1.35), 0.2, C.GLASS_DARK, M.Glass))
	end
	for _, x in { -1, 1 } do
		local shoulder = V(x * 1.3, 6.6, -0.3)
		local paw = V(x * 2.3, 8.0, -1.2)
		b.rod("Arm", shoulder, paw, 1.05, fur, M.Fabric)
		fine(b.ball("Paw", paw, 1.1, fur, M.Fabric))
		for k = -1, 1 do
			local root = paw + V(k * 0.28, 0.35, -0.35)
			fine(b.rod("Claw", root, root + V(k * 0.06, -0.15, -0.55), 0.1, CLAW, M.SmoothPlastic))
		end
	end
	return b.model
end

--[[
	A wolf on a log slab, head low, lips back. Four legs, a tail, ears that
	are two small triangles.
]]
function Furnish.wolfMount(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("WolfMount", at, parent)
	local fur: Color3 = opt(o, "fur", FUR_GREY)
	b.disc("Slab", V(0, 0.2, 0), 5.2, 0.4, Kit.rgb(64, 48, 36), M.Wood)
	fine(b.disc("SlabRing", V(0, 0.42, 0), 4.6, 0.04, Kit.rgb(84, 66, 48), M.Wood))
	b.rod("Body", V(0, 2.5, 1.4), V(0, 2.6, -1.1), 1.5, fur, M.Fabric)
	b.ball("Chest", V(0, 2.5, -1.2), 1.6, fur, M.Fabric)
	b.ball("Haunch", V(0, 2.5, 1.35), 1.5, fur, M.Fabric)
	for _, x in { -0.45, 0.45 } do
		for _, z in { -1.2, 1.4 } do
			b.rod("Leg", V(x, 2.2, z), V(x, 0.45, z - 0.15), 0.42, fur, M.Fabric)
			fine(b.ball("Paw", V(x, 0.55, z - 0.3), 0.45, fur, M.Fabric))
		end
	end
	b.rod("Neck", V(0, 2.7, -1.5), V(0, 2.9, -2.2), 1.0, fur, M.Fabric)
	b.ball("Head", V(0, 2.95, -2.45), 1.15, fur, M.Fabric)
	fine(b.rod("Snout", V(0, 2.85, -2.8), V(0, 2.65, -3.55), 0.55, fur, M.Fabric))
	fine(b.ball("Nose", V(0, 2.66, -3.58), 0.24, C.SOOT, M.SmoothPlastic))
	fine(b.rod("Jaw", V(0, 2.55, -2.8), V(0, 2.3, -3.35), 0.34, fur, M.Fabric))
	for _, x in { -0.15, 0.15 } do
		fine(b.rod("Fang", V(x, 2.6, -3.35), V(x, 2.4, -3.35), 0.07, C.BONE, M.SmoothPlastic))
		fine(b.ball("Eye", V(x * 1.9, 3.1, -2.9), 0.13, C.GLASS_DARK, M.Glass))
	end
	for _, x in { -1, 1 } do
		b.tri(
			"Ear",
			V(x * 0.22, 3.35, -2.35),
			V(x * 0.52, 3.35, -2.3),
			V(x * 0.4, 3.85, -2.2),
			0.1,
			fur,
			M.Fabric
		)
	end
	fine(b.rod("Tail", V(0, 2.6, 2.0), V(0, 1.3, 2.9), 0.4, fur, M.Fabric))
	return b.model
end

--[[
	A chopping stump with an axe left standing in it. `at` is on the floor.
]]
function Furnish.chopBlock(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("ChopBlock", at, parent)
	local h: number = opt(o, "height", 2.3)
	b.rod("Stump", V(0, 0, 0), V(0, h, 0), 2.3, Kit.rgb(56, 42, 32), M.Wood)
	fine(b.disc("CutFace", V(0, h + 0.02, 0), 2.1, 0.04, Kit.rgb(88, 70, 50), M.Wood))
	fine(b.disc("Stain", V(0.3, h + 0.05, -0.2), 1.1, 0.02, C.BLOOD_OLD, M.SmoothPlastic))
	-- The axe: head sunk into the top, handle up and away.
	fine(
		b.box(
			"AxeHead",
			V(0.16, 0.8, 1.1),
			V(-0.2, h + 0.15, 0.1),
			C.IRON,
			M.CorrodedMetal,
			CFrame.Angles(math.rad(20), 0, 0)
		)
	)
	fine(b.rod("AxeHandle", V(-0.2, h + 0.3, 0.25), V(-0.2, h + 2.6, 1.3), 0.22, C.OAK, M.Wood))
	return b.model
end

-- A coffee table: a slice of a big trunk on a short stump.
function Furnish.stumpTable(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("StumpTable", at, parent)
	local d: number = opt(o, "diameter", 4.4)
	local h: number = opt(o, "height", 2.2)
	b.rod("Stump", V(0, 0, 0), V(0, h - 0.5, 0), 1.7, Kit.rgb(56, 42, 32), M.Wood)
	b.disc("Top", V(0, h - 0.25, 0), d, 0.5, Kit.rgb(70, 52, 38), M.Wood)
	fine(b.disc("Rings", V(0, h + 0.01, 0), d - 0.5, 0.03, Kit.rgb(86, 66, 48), M.Wood))
	fine(b.disc("Heart", V(0, h + 0.02, 0), 0.9, 0.03, Kit.rgb(58, 42, 30), M.Wood))
	return b.model
end

----------------------------------------------------------------------------
-- The church
----------------------------------------------------------------------------

--[[
	A pew: a plank seat, a panelled back with a book ledge on it for the row
	behind, and a bench end each side standing up past the back with a
	carved poppyhead on top, which here is a ball. Its front, where you sit,
	faces -Z like every piece.
]]
function Furnish.pew(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Pew", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local L: number = opt(o, "length", 5)
	local seatY, seatD, backTop = 1.9, 1.5, 3.7
	local inner = L - 0.56
	local endD = seatD + 1.0
	local endZ = 0.2

	b.box("Seat", V(inner, 0.25, seatD), V(0, seatY - 0.125, -0.05), wood, M.WoodPlanks)
	fine(
		b.rod(
			"SeatEdge",
			V(-inner / 2, seatY - 0.13, -seatD / 2 - 0.05),
			V(inner / 2, seatY - 0.13, -seatD / 2 - 0.05),
			0.3,
			wood,
			M.Wood
		)
	)
	b.box(
		"PewBack",
		V(inner, backTop - seatY + 0.25, 0.22),
		V(0, (seatY + backTop) / 2 - 0.1, seatD / 2 + 0.02),
		wood,
		M.WoodPlanks
	)
	fine(
		b.rod(
			"BackRail",
			V(-inner / 2, backTop + 0.02, seatD / 2 + 0.02),
			V(inner / 2, backTop + 0.02, seatD / 2 + 0.02),
			0.36,
			wood,
			M.Wood
		)
	)
	-- The ledge on the back, where the row behind kept its books.
	b.box("BookLedge", V(inner, 0.14, 0.7), V(0, backTop - 0.5, seatD / 2 + 0.47), wood, M.Wood)
	fine(
		b.rod(
			"LedgeLip",
			V(-inner / 2, backTop - 0.38, seatD / 2 + 0.8),
			V(inner / 2, backTop - 0.38, seatD / 2 + 0.8),
			0.16,
			wood,
			M.Wood
		)
	)
	-- A kneeler rail along the floor behind, for the row behind.
	fine(
		b.rod(
			"Kneeler",
			V(-inner / 2, 0.32, seatD / 2 + 0.72),
			V(inner / 2, 0.32, seatD / 2 + 0.72),
			0.3,
			wood,
			M.Wood
		)
	)
	for _, s in { -1, 1 } do
		local x = s * (L / 2 - 0.14)
		b.box("PewEnd", V(0.28, backTop + 0.2, endD), V(x, (backTop + 0.2) / 2, endZ), wood, M.Wood)
		fine(
			b.rod(
				"PewEndRoll",
				V(x, backTop + 0.2, endZ - endD / 2),
				V(x, backTop + 0.2, endZ + endD / 2),
				0.32,
				wood,
				M.Wood
			)
		)
		fine(b.disc("PoppyNeck", V(x, backTop + 0.4, -seatD / 2 + 0.1), 0.42, 0.3, wood, M.Wood))
		fine(b.ball("Poppyhead", V(x, backTop + 0.72, -seatD / 2 + 0.1), 0.72, wood, M.Wood))
	end
	-- A hymn book or two left behind.
	local wear = Kit.wear()
	if wear:NextNumber() < 0.5 then
		fine(
			b.box(
				"HymnBook",
				V(0.7, 0.18, 0.5),
				V(wear:NextNumber(-inner / 2 + 0.6, inner / 2 - 0.6), seatY + 0.09, -0.2),
				Kit.rgb(40, 26, 24),
				M.Fabric,
				CFrame.Angles(0, wear:NextNumber(-0.6, 0.6), 0)
			)
		)
	end
	return b.model
end

--[[
	The altar: a heavy oak table on turned legs, a frontal of dark velvet
	hanging down its front with a band of tarnished gold braid, the linen
	on its top gone brown. A cross on a stepped base in the middle, a
	candlestick either side, the book open. Open underneath behind the
	frontal: a player can get under it and lie still.
]]
function Furnish.altar(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin("Altar", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local cloth: Color3 = opt(o, "cloth", C.VELVET_DARK)
	local L, W, H = 7.2, 3.0, 3.6
	b.box("AltarTop", V(L, 0.35, W), V(0, H - 0.175, 0), wood, M.Wood)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			turnedLeg(b, x * (L / 2 - 0.4), z * (W / 2 - 0.35), H - 0.35, 0.42, wood)
		end
	end
	fine(b.box("BackRail", V(L - 1.2, 0.5, 0.2), V(0, H - 0.6, W / 2 - 0.35), wood, M.Wood))
	-- The frontal, down the front to a hand's breadth from the floor. It does
	-- not collide: it is cloth.
	soft(
		b.box(
			"Frontal",
			V(L - 0.3, H - 0.55, 0.08),
			V(0, (H - 0.55) / 2 + 0.3, -W / 2 - 0.06),
			cloth,
			M.Fabric
		)
	)
	fine(
		b.box(
			"Orphrey",
			V(0.8, H - 0.55, 0.1),
			V(0, (H - 0.55) / 2 + 0.3, -W / 2 - 0.12),
			C.BRASS,
			M.Fabric
		)
	)
	fine(
		b.rod(
			"Fringe",
			V(-(L - 0.3) / 2, 0.36, -W / 2 - 0.1),
			V((L - 0.3) / 2, 0.36, -W / 2 - 0.1),
			0.2,
			C.BRASS,
			M.Fabric
		)
	)
	soft(b.box("FairLinen", V(L + 0.5, 0.05, W - 0.5), V(0, H + 0.025, 0.15), C.LINEN, M.Fabric))
	for _, x in { -1, 1 } do
		soft(
			b.box(
				"LinenFall",
				V(0.05, 1.2, W - 0.5),
				V(x * (L / 2 + 0.27), H - 0.55, 0.15),
				C.LINEN,
				M.Fabric
			)
		)
	end

	-- The cross on its stepped base.
	local brass = C.BRASS
	fine(b.box("CrossBase", V(1.3, 0.3, 0.9), V(0, H + 0.2, 0.55), brass, M.Metal))
	fine(b.box("CrossStep", V(0.8, 0.3, 0.6), V(0, H + 0.5, 0.55), brass, M.Metal))
	fine(b.box("CrossShaft", V(0.24, 2.6, 0.2), V(0, H + 1.95, 0.55), brass, M.Metal))
	fine(b.box("CrossArm", V(1.3, 0.24, 0.2), V(0, H + 2.55, 0.55), brass, M.Metal))
	-- Candlesticks, one candle burnt low and one snapped.
	for i, x in { -2.5, 2.5 } do
		fine(b.disc("CandleFoot", V(x, H + 0.1, 0.5), 0.9, 0.2, brass, M.Metal))
		fine(b.rod("CandleStem", V(x, H + 0.15, 0.5), V(x, H + 1.9, 0.5), 0.22, brass, M.Metal))
		fine(b.ball("CandleKnop", V(x, H + 0.9, 0.5), 0.42, brass, M.Metal))
		fine(b.disc("DripPan", V(x, H + 1.92, 0.5), 0.6, 0.08, brass, M.Metal))
		local len = if i == 1 then 1.3 else 0.35
		fine(
			b.rod(
				"Candle",
				V(x, H + 1.95, 0.5),
				V(x, H + 1.95 + len, 0.5),
				0.26,
				C.WAX,
				M.SmoothPlastic
			)
		)
	end
	-- The book, open where it was left.
	for _, s in { -1, 1 } do
		fine(
			b.box(
				"BookPage",
				V(0.8, 0.16, 1.1),
				V(s * 0.42 + 1.2, H + 0.1, -0.5),
				Kit.rgb(60, 52, 42),
				M.Fabric,
				CFrame.Angles(0, 0, s * math.rad(-5))
			)
		)
	end

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderAltarHidingVolume",
			at * CFrame.new(0, (H - 0.6) / 2 + 0.05, 0.05),
			V(L - 1.6, H - 0.7, W - 1.1),
			"UnderTable",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

--[[
	A run of altar rail: a round top rail on turned balusters between two
	posts, and a long cushion to kneel on along the front, the velvet
	flattened into two hollows at every place. `length` along X.
]]
function Furnish.altarRail(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("AltarRail", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local L: number = opt(o, "length", 5)
	local H = 2.7
	b.box("RailTop", V(L, 0.22, 0.7), V(0, H - 0.11, 0), wood, M.Wood)
	fine(
		b.rod("RailRoll", V(-L / 2, H + 0.02, -0.12), V(L / 2, H + 0.02, -0.12), 0.36, wood, M.Wood)
	)
	b.box("RailFoot", V(L, 0.3, 0.6), V(0, 0.15, 0), wood, M.Wood)
	for _, x in { -L / 2 + 0.25, L / 2 - 0.25 } do
		b.box("RailPost", V(0.5, H + 0.2, 0.6), V(x, (H + 0.2) / 2, 0), wood, M.Wood)
		fine(b.ball("PostCap", V(x, H + 0.45, 0), 0.55, wood, M.Wood))
	end
	local n = math.max(2, math.floor(L / 0.8))
	for i = 1, n - 1 do
		local x = -L / 2 + L * i / n
		fine(b.rod("Baluster", V(x, 0.3, 0), V(x, H - 0.22, 0), 0.24, wood, M.Wood))
		fine(b.ball("BalusterKnop", V(x, 0.95, 0), 0.4, wood, M.Wood))
	end
	soft(b.box("Kneeler", V(L - 0.3, 0.35, 1.1), V(0, 0.18, -1.05), C.VELVET_DARK, M.Fabric))
	fine(
		b.rod(
			"KneelerRoll",
			V(-(L - 0.3) / 2, 0.3, -1.6),
			V((L - 0.3) / 2, 0.3, -1.6),
			0.32,
			C.VELVET_DARK,
			M.Fabric
		)
	)
	return b.model
end

--[[
	A pulpit: a round drum of boards on a stem and a corbel, a book desk on
	its front, a sounding board hung over it on a post from the back, and a
	short straight stair up its left side into a gap in the drum. The stair
	and the floor inside collide; the preacher's place can be stood in.
]]
function Furnish.pulpit(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Pulpit", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local floorH, drumH, R = 3.6, 3.4, 1.8
	fine(b.disc("PulpitBase", V(0, 0.2, 0), 2.2, 0.4, wood, M.Wood))
	b.rod("PulpitStem", V(0, 0.3, 0), V(0, floorH - 0.7, 0), 1.3, wood, M.Wood)
	fine(b.ball("StemKnop", V(0, 1.4, 0), 1.7, wood, M.Wood))
	b.disc("Corbel", V(0, floorH - 0.55, 0), 2.7, 0.4, wood, M.Wood)
	b.disc("PulpitFloor", V(0, floorH - 0.15, 0), R * 2, 0.3, wood, M.Wood)
	-- The drum: twelve boards round the circle, leaving a gap on the left
	-- where the stair comes in.
	local n = 12
	for k = 0, n - 1 do
		local a = 2 * math.pi * (k + 0.5) / n
		local x, z = R * math.sin(a), R * math.cos(a)
		if x < -1.2 and math.abs(z) < 1.3 then
			continue
		end
		b.box(
			"DrumBoard",
			V(2 * R * math.sin(math.pi / n) + 0.06, drumH, 0.22),
			V(x, floorH + drumH / 2, z),
			wood,
			M.WoodPlanks,
			CFrame.Angles(0, a, 0)
		)
		local a1 = 2 * math.pi * (k + 1.5) / n
		fine(
			b.rod(
				"DrumRail",
				V(x, floorH + drumH + 0.05, z),
				V(R * math.sin(a1), floorH + drumH + 0.05, R * math.cos(a1)),
				0.3,
				wood,
				M.Wood
			)
		)
	end
	-- The book desk and the book.
	fine(
		b.box(
			"BookDesk",
			V(1.6, 0.12, 1.0),
			V(0, floorH + drumH + 0.25, -R + 0.35),
			wood,
			M.Wood,
			CFrame.Angles(math.rad(18), 0, 0)
		)
	)
	fine(
		b.box(
			"PulpitBook",
			V(1.4, 0.14, 0.9),
			V(0, floorH + drumH + 0.38, -R + 0.37),
			Kit.rgb(44, 30, 26),
			M.Fabric,
			CFrame.Angles(math.rad(18), 0, 0)
		)
	)
	-- The sounding board, on a post up the back.
	b.rod("TesterPost", V(0, floorH, R + 0.15), V(0, floorH + 7.6, R + 0.15), 0.4, wood, M.Wood)
	b.disc("SoundingBoard", V(0, floorH + 7.5, 0), 4.6, 0.3, wood, M.Wood)
	fine(b.disc("SoundingCrown", V(0, floorH + 7.8, 0), 3.2, 0.4, wood, M.Wood))
	fine(b.ball("SoundingFinial", V(0, floorH + 8.3, 0), 0.6, wood, M.Wood))
	-- The stair: four steps up the left side, from behind.
	local sx = -(R + 0.1 + 0.9)
	for k = 1, 4 do
		local top = floorH * k / 4
		local z1 = R + 1.8 - 0.7 * (k - 1)
		local z0 = z1 - 0.7
		b.box("PulpitStep", V(1.8, top, z1 - z0), V(sx, top / 2, (z0 + z1) / 2), wood, M.WoodPlanks)
	end
	b.box(
		"PulpitStepTop",
		V(1.8, floorH, 0.9),
		V(sx, floorH / 2, R + 1.8 - 2.8 - 0.45),
		wood,
		M.WoodPlanks
	)
	fine(
		b.rod(
			"StairRail",
			V(sx - 0.9, floorH / 4 + 2.8, R + 1.8),
			V(sx - 0.9, floorH + 2.8, -0.2),
			0.3,
			wood,
			M.Wood
		)
	)
	for _, z in { R + 1.8, -0.2 } do
		local y = if z > 0 then floorH / 4 else floorH
		fine(
			b.rod(
				"StairPost",
				V(sx - 0.9, y - floorH / 4, z),
				V(sx - 0.9, y + 2.9, z),
				0.36,
				wood,
				M.Wood
			)
		)
	end
	return b.model
end

--[[
	A lectern in the shape of an eagle, in brass gone brown: a round foot, a
	column with a knop, a globe, and the eagle standing on it with its wings
	spread back into a sloping desk and the book open on them.
]]
function Furnish.eagleLectern(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Lectern", at, parent)
	local metal: Color3 = opt(o, "metal", C.BRASS)
	fine(b.disc("LecternFoot", V(0, 0.15, 0), 1.9, 0.3, metal, M.Metal))
	for k = 0, 2 do
		local a = 2 * math.pi * k / 3
		fine(
			b.ball("LecternToe", V(1.0 * math.cos(a), 0.2, 1.0 * math.sin(a)), 0.42, metal, M.Metal)
		)
	end
	b.rod("LecternColumn", V(0, 0.3, 0), V(0, 3.4, 0), 0.45, metal, M.Metal)
	fine(b.ball("LecternKnop", V(0, 1.8, 0), 0.75, metal, M.Metal))
	fine(b.ball("LecternGlobe", V(0, 3.7, 0), 1.1, metal, M.Metal))
	local by = 4.45
	b.rod("EagleBody", V(0, by - 0.05, 0.55), V(0, by + 0.2, -0.55), 0.9, metal, M.Metal)
	fine(b.ball("EagleHead", V(0, by + 0.6, -0.8), 0.56, metal, M.Metal))
	fine(b.rod("EagleBeak", V(0, by + 0.6, -1.05), V(0, by + 0.42, -1.35), 0.18, metal, M.Metal))
	for _, s in { -1, 1 } do
		fine(
			b.box(
				"EagleWing",
				V(1.15, 0.12, 1.6),
				V(s * 0.62, by + 0.45, 0.15),
				metal,
				M.Metal,
				CFrame.Angles(math.rad(-24), 0, s * math.rad(-10))
			)
		)
		fine(
			b.box(
				"BookPage",
				V(0.9, 0.12, 1.2),
				V(s * 0.5, by + 0.7, 0.18),
				Kit.rgb(60, 52, 42),
				M.Fabric,
				CFrame.Angles(math.rad(-24), 0, s * math.rad(-6))
			)
		)
	end
	fine(
		b.box(
			"EagleTail",
			V(0.5, 0.1, 0.8),
			V(0, by - 0.1, 0.95),
			metal,
			M.Metal,
			CFrame.Angles(math.rad(22), 0, 0)
		)
	)
	return b.model
end

--[[
	A stone font by the door: a round bowl on a stem, on a step, full to
	the rim with water gone black, and its wooden cover pushed half off.
]]
function Furnish.font(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Font", at, parent)
	local stone: Color3 = opt(o, "stone", Kit.rgb(78, 74, 68))
	local wood: Color3 = opt(o, "wood", C.OAK)
	b.disc("FontStep", V(0, 0.2, 0), 4.4, 0.4, stone, M.Concrete)
	b.disc("FontBase", V(0, 0.6, 0), 2.4, 0.4, stone, M.Concrete)
	b.rod("FontStem", V(0, 0.7, 0), V(0, 2.4, 0), 1.3, stone, M.Concrete)
	b.disc("FontBowl", V(0, 2.95, 0), 3.0, 1.3, stone, M.Concrete)
	b.disc("FontRim", V(0, 3.62, 0), 3.2, 0.2, stone, M.Concrete)
	fine(b.disc("FontWater", V(0, 3.73, 0), 2.5, 0.03, Kit.rgb(22, 26, 24), M.Glass))
	b.disc(
		"FontCover",
		V(1.0, 3.98, 0.35),
		2.9,
		0.25,
		wood,
		M.Wood,
		CFrame.Angles(0, 0, math.rad(7))
	)
	fine(b.rod("CoverSpire", V(1.05, 4.1, 0.35), V(1.2, 5.4, 0.35), 0.35, wood, M.Wood))
	fine(b.ball("CoverFinial", V(1.22, 5.55, 0.35), 0.5, wood, M.Wood))
	return b.model
end

--[[
	A chamber organ: a tall case with a console in front, two keyboards and
	the stop knobs either side, a bench, and the pipes standing in three
	flats above on the impost, the tallest in the middle. The case is hollow
	and there is a door in its side: a player can get in behind the pipes
	and shut it. `doorSide` is which side the door is on, -1 or +1 along X.
]]
function Furnish.organ(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot)
	local b = begin("Organ", at, parent)
	local wood: Color3 = opt(o, "wood", C.WALNUT)
	local pipeColor: Color3 = opt(o, "pipes", Kit.rgb(74, 70, 62))
	local side: number = opt(o, "doorSide", -1)
	local W, D, H = 5.2, 5.2, 12
	local t = 0.3
	local impost = 4.7
	local dz0, dz1 = -1.1, D / 2 - t - 0.05 -- the door's opening along the side
	local doorH = 7.0

	b.box("CaseFloor", V(W, 0.3, D), V(0, 0.15, 0), wood, M.Wood)
	b.box("CaseBack", V(W, H, t), V(0, H / 2, D / 2 - t / 2), wood, M.WoodPlanks)
	-- The top overhangs the front and sides but stops at the back, so the
	-- case stands flush to a wall.
	b.box("CaseTop", V(W + 0.2, 0.5, D + 0.4), V(0, H + 0.25, -0.1), wood, M.Wood)
	fine(
		b.rod(
			"CaseCornice",
			V(-W / 2 - 0.1, H + 0.05, -D / 2 - 0.3),
			V(W / 2 + 0.1, H + 0.05, -D / 2 - 0.3),
			0.45,
			wood,
			M.Wood
		)
	)
	-- Sides: whole on one side, round a door on the other.
	for _, s in { -1, 1 } do
		local x = s * (W / 2 - t / 2)
		if s ~= side then
			b.box("CaseSide", V(t, H, D), V(x, H / 2, 0), wood, M.WoodPlanks)
		else
			local front = dz0 - (-D / 2)
			b.box("CaseSide", V(t, H, front), V(x, H / 2, -D / 2 + front / 2), wood, M.WoodPlanks)
			local back = D / 2 - dz1
			if back > 0.05 then
				b.box("CaseSide", V(t, H, back), V(x, H / 2, dz1 + back / 2), wood, M.WoodPlanks)
			end
			b.box(
				"CaseSide",
				V(t, H - doorH - 0.3, dz1 - dz0),
				V(x, 0.3 + doorH + (H - doorH - 0.3) / 2, (dz0 + dz1) / 2),
				wood,
				M.WoodPlanks
			)
		end
	end
	-- The console: the lower front, the keyboards, the stops, the music desk.
	b.box(
		"ConsoleFront",
		V(W - 2 * t, impost - 0.6, t),
		V(0, 0.3 + (impost - 0.6) / 2, -D / 2 + t / 2),
		wood,
		M.WoodPlanks
	)
	local keys = Kit.rgb(70, 64, 52) -- ivory, yellowed to the colour of old teeth
	for i, k in { { 2.5, -D / 2 - 0.55 }, { 2.95, -D / 2 - 0.2 } } do
		fine(b.box("KeyDesk", V(W - 2.0, 0.25, 0.7), V(0, k[1], k[2]), wood, M.Wood))
		fine(
			b.box(
				"Keys",
				V(W - 2.2, 0.08, 0.55),
				V(0, k[1] + 0.16, k[2] - 0.05),
				keys,
				M.SmoothPlastic
			)
		)
		if i == 1 then
			b.box("KeyCheek", V(W - 1.6, 0.9, 1.2), V(0, 2.0, -D / 2 - 0.35), wood, M.Wood)
		end
	end
	for _, s in { -1, 1 } do
		for k = 0, 3 do
			fine(
				b.ball(
					"StopKnob",
					V(s * (W / 2 - 0.55), 3.0 + k * 0.35, -D / 2 - 0.05),
					0.24,
					keys,
					M.Wood
				)
			)
		end
	end
	fine(
		b.box(
			"MusicDesk",
			V(2.4, 1.2, 0.1),
			V(0, 3.9, -D / 2 - 0.05),
			wood,
			M.Wood,
			CFrame.Angles(math.rad(-12), 0, 0)
		)
	)
	for k = 0, 6 do
		fine(
			b.rod(
				"Pedal",
				V(-1.5 + k * 0.5, 0.2, -D / 2 - 1.5),
				V(-1.5 + k * 0.5, 0.2, -D / 2 - 0.4),
				0.22,
				wood,
				M.Wood
			)
		)
	end
	-- The bench in front of the console.
	b.box("OrganBench", V(3.6, 0.3, 1.1), V(0, 2.0, -D / 2 - 2.3), wood, M.Wood)
	for _, x in { -1.5, 1.5 } do
		fine(b.rod("BenchLeg", V(x, 0, -D / 2 - 2.3), V(x, 1.85, -D / 2 - 2.3), 0.3, wood, M.Wood))
	end
	-- The impost the pipes stand on, and the board behind them that keeps
	-- the inside of the case dark.
	b.box("Impost", V(W - 2 * t, 0.4, 1.2), V(0, impost - 0.2, -D / 2 + 0.6), wood, M.Wood)
	b.box(
		"PipeBoard",
		V(W - 2 * t, H - impost, 0.2),
		V(0, impost + (H - impost) / 2, -D / 2 + 1.3),
		wood,
		M.WoodPlanks
	)
	-- The pipes: a middle flat of seven rising to the centre and a flat of
	-- four either side falling away.
	local function pipe(x: number, len: number, d: number)
		local foot = impost + 0.9
		fine(
			b.rod(
				"PipeFoot",
				V(x, impost, -D / 2 + 0.6),
				V(x, foot, -D / 2 + 0.6),
				d * 0.55,
				pipeColor,
				M.Metal
			)
		)
		b.rod(
			"Pipe",
			V(x, foot, -D / 2 + 0.6),
			V(x, foot + len, -D / 2 + 0.6),
			d,
			pipeColor,
			M.Metal
		)
		fine(
			b.box(
				"PipeMouth",
				V(d * 0.55, 0.3, 0.06),
				V(x, foot + 0.25, -D / 2 + 0.6 - d / 2),
				Kit.rgb(20, 18, 16),
				M.Metal
			)
		)
	end
	for k = -2, 2 do
		pipe(k * 0.62, 5.6 - math.abs(k) * 0.6, 0.52)
	end
	for _, s in { -1, 1 } do
		pipe(s * 1.95, 3.7, 0.42)
		pipe(s * 2.35, 3.1, 0.38)
	end
	-- The door into the case, hung on its back edge and opening out.
	local dx = side * (W / 2 - t / 2)
	local centre = V(dx, 0.3 + doorH / 2, (dz0 + dz1) / 2)
	-- Hung on its back edge unless `hingeFront`, for a case whose back edge
	-- stands too near something for the leaf to clear it.
	Kit.door(at * CFrame.new(centre, centre + V(side, 0, 0)), dz1 - dz0, doorH, {
		parent = b.model,
		hinge = if opt(o, "hingeFront", false) then -side else side,
		swing = 1,
		thickness = 0.22,
		color = wood,
		panel = C.WALNUT,
		style = "cabinet",
		openAngle = 90,
		gap = 0.08,
		name = "OrganDoor",
	})
	return b.model,
		Kit.hideVolume(
			"OrganHidingVolume",
			at * CFrame.new(0, 0.3 + 3.1, (dz0 + dz1) / 2 + 0.1),
			V(W - 1.2, 6.0, dz1 - dz0 - 0.5),
			"Cupboard",
			opt(o, "floor", 1),
			b.model
		)
end

--[[
	A confessional in three parts: the priest's box in the middle behind a
	door, and a curtained booth either side where the penitent kneels at a
	grille in the wall between. A pediment over the door, a smaller one over
	each booth, a cornice and ball finials along the top.

	Only the middle door swings, and it is narrower than the gap between two
	column plinths: a booth standing in an aisle bay has the columns right in
	front of its ends, and any door hung there hits one as it opens. The
	priest's box is the hiding place. A curtain is not a door, so the booths
	either side are not.
]]
function Furnish.confessional(
	at: CFrame,
	parent: Instance,
	o: Options?
): (Model, { Kit.HidingSpot })
	local b = begin("Confessional", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local dark: Color3 = opt(o, "panel", C.WALNUT)
	local cloth: Color3 = opt(o, "curtain", C.VELVET_DARK)
	-- Inside sizes: the priest's box, each penitent's booth, depth, height.
	local cp, pw, cd, ch = 3.6, 2.3, 4.0, 7.6
	local t = 0.3
	local W = cp + pw * 2 + t * 4
	local D = cd + t
	local H = ch + 0.3
	local openH = ch - 0.4 -- the door, and the booths' openings
	local z0 = -D / 2 + t / 2 -- the front
	local zBack = D / 2 + t / 2
	local partition = cp / 2 + t / 2
	-- The grille's opening in each partition, at a kneeling head's height.
	local gy0, gy1, gz = 3.5, 5.1, 0.8

	b.box("BoothFloor", V(W, 0.3, D), V(0, 0.15, t / 2), wood, M.Wood)
	b.box("BoothBack", V(W, H, t), V(0, H / 2, D / 2), wood, M.WoodPlanks)
	for _, s in { -1, 1 } do
		b.box("BoothWall", V(t, H, D), V(s * (W / 2 - t / 2), H / 2, t / 2), wood, M.WoodPlanks)
		-- The partition, whole but for the grille's opening.
		local x = s * partition
		b.box("BoothWall", V(t, gy0, D), V(x, gy0 / 2, t / 2), wood, M.WoodPlanks)
		b.box("BoothWall", V(t, H - gy1, D), V(x, (gy1 + H) / 2, t / 2), wood, M.WoodPlanks)
		b.box(
			"BoothWall",
			V(t, gy1 - gy0, -gz - z0),
			V(x, (gy0 + gy1) / 2, (z0 - gz) / 2),
			wood,
			M.WoodPlanks
		)
		b.box(
			"BoothWall",
			V(t, gy1 - gy0, zBack - gz),
			V(x, (gy0 + gy1) / 2, (gz + zBack) / 2),
			wood,
			M.WoodPlanks
		)
		for k = -2, 2 do
			fine(b.rod("Grille", V(x, gy0, k * 0.3), V(x, gy1, k * 0.3), 0.08, C.IRON, M.Metal))
		end
		for k = 0, 3 do
			fine(
				b.rod(
					"Grille",
					V(x, gy0 + 0.2 + k * 0.4, -gz),
					V(x, gy0 + 0.2 + k * 0.4, gz),
					0.08,
					C.IRON,
					M.Metal
				)
			)
		end
	end
	b.box("BoothRoof", V(W + 0.5, 0.35, D + 0.5), V(0, H + 0.175, t / 2), wood, M.Wood)
	fine(
		b.rod(
			"BoothCornice",
			V(-W / 2 - 0.25, H + 0.05, -D / 2 - 0.1),
			V(W / 2 + 0.25, H + 0.05, -D / 2 - 0.1),
			0.4,
			wood,
			M.Wood
		)
	)
	for _, x in { -W / 2, -partition, partition, W / 2 } do
		fine(b.ball("BoothFinial", V(x, H + 0.65, -D / 2 + 0.2), 0.6, wood, M.Wood))
	end

	-- Headers over the three openings, and a pediment over each: the
	-- middle one, over the priest's door, the tallest.
	local bays = { { x = 0, w = cp, apex = 1.4 } }
	for _, s in { -1, 1 } do
		table.insert(bays, { x = s * (partition + t / 2 + pw / 2), w = pw, apex = 0.9 })
	end
	for _, bay in bays do
		b.box(
			"BoothHeader",
			V(bay.w, H - 0.3 - openH, t),
			V(bay.x, (0.3 + openH + H) / 2, z0),
			wood,
			M.Wood
		)
		b.tri(
			"Pediment",
			V(bay.x - bay.w / 2, H + 0.35, -D / 2 + 0.25),
			V(bay.x + bay.w / 2, H + 0.35, -D / 2 + 0.25),
			V(bay.x, H + 0.35 + bay.apex, -D / 2 + 0.25),
			0.3,
			wood,
			M.Wood
		)
	end

	-- The priest's side: the door, and his seat hinged up flat against the
	-- back, which leaves the box room enough to stand in.
	local backFace = D / 2 - t / 2
	b.box("BoothSeat", V(cp - 0.5, 1.3, 0.12), V(0, 2.65, backFace - 0.07), wood, M.Wood)
	for _, s in { -1, 1 } do
		fine(
			b.box(
				"SeatBracket",
				V(0.12, 0.3, 0.35),
				V(s * (cp / 2 - 0.6), 1.9, backFace - 0.18),
				C.IRON,
				M.Metal
			)
		)
	end
	local centre = V(0, 0.3 + openH / 2, z0)
	Kit.door(at * CFrame.new(centre, centre + V(0, 0, -1)), cp, openH, {
		parent = b.model,
		hinge = -1,
		swing = 1,
		thickness = 0.22,
		color = wood,
		panel = dark,
		style = "cabinet",
		openAngle = opt(o, "openAngle", 85),
		gap = 0.08,
		name = "ConfessionalDoor",
	})

	-- The penitents' sides: a kneeler against the partition facing the
	-- grille, an elbow rest under it, and the curtain half drawn across.
	for _, s in { -1, 1 } do
		local face = s * (partition + t / 2)
		local xc = s * (partition + t / 2 + pw / 2)
		b.box("Kneeler", V(0.8, 0.5, cd - 1.0), V(face + s * 0.45, 0.55, t / 2), dark, M.Wood)
		b.box("ElbowRest", V(0.5, 0.15, 1.8), V(face + s * 0.27, 3.2, 0), wood, M.Wood)
		fine(
			b.rod(
				"ElbowRestEdge",
				V(face + s * 0.52, 3.2, -0.9),
				V(face + s * 0.52, 3.2, 0.9),
				0.2,
				wood,
				M.Wood
			)
		)
		local rodY = 0.3 + openH - 0.15
		local zc = z0 + 0.12
		fine(
			b.rod(
				"CurtainRod",
				V(xc - pw / 2, rodY, zc),
				V(xc + pw / 2, rodY, zc),
				0.1,
				C.IRON,
				M.Metal
			)
		)
		-- Drawn toward the outer wall, in folds: strips turned a little
		-- each way, so the light catches alternate ones.
		local outer = xc + s * pw / 2
		local cover = pw * 0.6
		local folds = 4
		local fw = cover / folds
		for i = 1, folds do
			local x = outer - s * (i - 0.5) * fw
			local turn = if i % 2 == 0 then 0.35 else -0.35
			soft(
				b.box(
					"Curtain",
					V(fw / math.cos(turn), openH - 0.5, 0.08),
					V(x, 0.3 + 0.35 + (openH - 0.5) / 2, zc + 0.08),
					Kit.weathered(cloth, 0.08),
					M.Fabric,
					CFrame.Angles(0, turn, 0)
				)
			)
		end
	end

	local hiding = Kit.hideVolume(
		"ConfessionalHidingVolume",
		at * CFrame.new(0, 0.3 + 3.1, t / 2 + 0.1),
		V(cp - 0.6, 6.0, cd - 0.6),
		"Cupboard",
		opt(o, "floor", 1),
		b.model
	)
	return b.model, { hiding }
end

--[[
	A tomb chest with an effigy on it: a stone chest with round carved
	panels down its sides, a knight lying on the lid with his hands together
	and his head on a cushion, a dog at his feet. The lid has been pushed
	aside a hand's width, and it is dark in the gap. The effigy lies along
	Z, head toward +Z.
]]
function Furnish.tombChest(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("TombChest", at, parent)
	local stone: Color3 = opt(o, "stone", Kit.rgb(74, 70, 64))
	local L, W, H = 7.5, 3.0, 3.0
	b.box("TombPlinth", V(W + 0.5, 0.4, L + 0.5), V(0, 0.2, 0), stone, M.Concrete)
	b.box("TombChest", V(W, H - 0.9, L), V(0, 0.4 + (H - 0.9) / 2, 0), stone, M.Concrete)
	for _, s in { -1, 1 } do
		for k = -1, 1 do
			fine(
				b.disc(
					"TombRoundel",
					V(s * (W / 2 + 0.03), 0.4 + (H - 0.9) / 2, k * 2.3),
					1.4,
					0.1,
					Kit.rgb(60, 57, 52),
					M.Concrete,
					CFrame.Angles(0, 0, math.pi / 2)
				)
			)
			fine(
				b.box(
					"TombShield",
					V(0.14, 0.7, 0.55),
					V(s * (W / 2 + 0.06), 0.4 + (H - 0.9) / 2, k * 2.3),
					Kit.rgb(48, 44, 40),
					M.Concrete
				)
			)
		end
	end
	-- The dark inside, showing where the lid has moved.
	fine(
		b.box(
			"TombVoid",
			V(W - 0.6, 0.1, L - 0.6),
			V(0, H - 0.93, 0),
			Kit.rgb(12, 11, 10),
			M.SmoothPlastic
		)
	)
	local lid = CFrame.new(0.55, 0, 0.2) * CFrame.Angles(0, math.rad(4), 0)
	local function onLid(p: Vector3): Vector3
		return (lid * CFrame.new(p)).Position
	end
	b.box(
		"TombLid",
		V(W + 0.3, 0.5, L + 0.3),
		onLid(V(0, H - 0.65, 0)),
		stone,
		M.Concrete,
		lid.Rotation
	)
	fine(
		b.rod(
			"LidRoll",
			onLid(V(-(W + 0.3) / 2, H - 0.5, -(L + 0.3) / 2)),
			onLid(V(-(W + 0.3) / 2, H - 0.5, (L + 0.3) / 2)),
			0.3,
			stone,
			M.Concrete
		)
	)
	-- The effigy.
	local top = H - 0.4
	fine(
		b.box(
			"EffigyCushion",
			V(1.5, 0.35, 1.0),
			onLid(V(0, top + 0.17, 2.9)),
			stone,
			M.Concrete,
			lid.Rotation
		)
	)
	fine(b.ball("EffigyHead", onLid(V(0, top + 0.72, 2.75)), 0.95, stone, M.Concrete))
	b.rod(
		"EffigyBody",
		onLid(V(0, top + 0.62, 2.1)),
		onLid(V(0, top + 0.5, -2.6)),
		1.3,
		stone,
		M.Concrete
	)
	fine(
		b.rod(
			"EffigyHands",
			onLid(V(0, top + 1.2, 0.9)),
			onLid(V(0, top + 1.75, 1.05)),
			0.3,
			stone,
			M.Concrete
		)
	)
	for _, s in { -1, 1 } do
		fine(b.ball("EffigyFoot", onLid(V(s * 0.3, top + 0.6, -2.95)), 0.55, stone, M.Concrete))
	end
	fine(b.ball("EffigyDog", onLid(V(0, top + 0.45, -3.45)), 0.8, stone, M.Concrete))
	fine(b.ball("EffigyDogHead", onLid(V(0.35, top + 0.75, -3.5)), 0.45, stone, M.Concrete))
	return b.model
end

--[[
	A run of choir stalls: a pew with a higher back and a desk before it,
	the desk's top sloping toward the singer, its front panelled.
]]
function Furnish.choirStall(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("ChoirStall", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local L: number = opt(o, "length", 6)
	local seatY, backTop = 1.9, 5.2
	b.box("Seat", V(L, 0.25, 1.4), V(0, seatY - 0.125, 0.2), wood, M.WoodPlanks)
	fine(
		b.rod(
			"SeatEdge",
			V(-L / 2, seatY - 0.13, -0.5),
			V(L / 2, seatY - 0.13, -0.5),
			0.3,
			wood,
			M.Wood
		)
	)
	b.box("StallBack", V(L, backTop, 0.25), V(0, backTop / 2, 1.0), wood, M.WoodPlanks)
	fine(
		b.rod(
			"StallCornice",
			V(-L / 2, backTop + 0.1, 0.9),
			V(L / 2, backTop + 0.1, 0.9),
			0.45,
			wood,
			M.Wood
		)
	)
	b.box("DeskFront", V(L, 2.9, 0.22), V(0, 1.45, -1.9), wood, M.WoodPlanks)
	b.box(
		"DeskTop",
		V(L, 0.14, 0.9),
		V(0, 3.05, -1.55),
		wood,
		M.Wood,
		CFrame.Angles(math.rad(-14), 0, 0)
	)
	for _, s in { -1, 1 } do
		local x = s * (L / 2 - 0.14)
		b.box("StallEnd", V(0.28, 3.2, 3.2), V(x, 1.6, -0.45), wood, M.Wood)
		fine(b.ball("Poppyhead", V(x, 3.55, -1.8), 0.7, wood, M.Wood))
		fine(b.ball("Poppyhead", V(x, 3.55, 0.6), 0.7, wood, M.Wood))
	end
	-- Books on the desk, and one fallen.
	fine(
		b.box(
			"PsalterBook",
			V(0.8, 0.2, 0.6),
			V(-L / 4, 3.2, -1.55),
			Kit.rgb(40, 26, 24),
			M.Fabric,
			CFrame.Angles(math.rad(-14), 0.2, 0)
		)
	)
	fine(
		b.box(
			"PsalterBook",
			V(0.8, 0.2, 0.6),
			V(L / 3, 0.12, -2.6),
			Kit.rgb(34, 30, 40),
			M.Fabric,
			CFrame.Angles(0, 0.7, 0)
		)
	)
	return b.model
end

--[[
	A bier: two trestles and a pair of rails, with a coffin on it whose lid
	is not quite on. Low enough underneath to crawl into, which is the last
	place anyone would look. The coffin lies along X.
]]
function Furnish.bier(at: CFrame, parent: Instance, o: Options?): (Model, Kit.HidingSpot?)
	local b = begin("Bier", at, parent)
	local wood: Color3 = opt(o, "wood", C.OAK)
	local coffinWood: Color3 = opt(o, "coffin", Kit.rgb(46, 32, 26))
	local H = 2.7
	for _, x in { -2.3, 2.3 } do
		for _, z in { -1, 1 } do
			fine(
				b.rod("TrestleLeg", V(x, 0, z * 1.15), V(x, H - 0.3, z * 0.75), 0.35, wood, M.Wood)
			)
		end
		fine(b.rod("TrestleBar", V(x, 1.0, -1.05), V(x, 1.0, 1.05), 0.25, wood, M.Wood))
	end
	for _, z in { -0.7, 0.7 } do
		b.box("BierRail", V(6.2, 0.3, 0.4), V(0, H - 0.15, z), wood, M.Wood)
	end
	-- The coffin: wider at the shoulders, as they are made: a box and two
	-- wedge-cut ends.
	local cy = H + 0.65
	b.box("Coffin", V(4.0, 1.3, 2.1), V(0.3, cy, 0), coffinWood, M.Wood)
	b.box("CoffinFoot", V(1.6, 1.3, 1.4), V(-2.5, cy, 0), coffinWood, M.Wood)
	b.box("CoffinHead", V(0.8, 1.3, 1.6), V(2.7, cy, 0), coffinWood, M.Wood)
	-- The tapers from the shoulders to the foot and the head: flat triangles
	-- in plan, as thick as the coffin is deep.
	for _, s in { -1, 1 } do
		b.tri(
			"CoffinTaper",
			V(-1.7, cy, s * 1.05),
			V(-3.3, cy, s * 0.7),
			V(-1.7, cy, s * 0.7),
			1.3,
			coffinWood,
			M.Wood
		)
		b.tri(
			"CoffinTaper",
			V(2.3, cy, s * 1.05),
			V(3.1, cy, s * 0.8),
			V(2.3, cy, s * 0.8),
			1.3,
			coffinWood,
			M.Wood
		)
	end
	-- The lid, slid a little off toward the foot.
	b.box(
		"CoffinLid",
		V(6.1, 0.22, 2.0),
		V(-0.35, cy + 0.76, 0.12),
		coffinWood,
		M.Wood,
		CFrame.Angles(0, math.rad(3), 0)
	)
	for _, x in { -1.3, 0.4, 2.0 } do
		for _, s in { -1, 1 } do
			fine(
				b.rod(
					"CoffinHandle",
					V(x - 0.4, cy - 0.1, s * 1.15),
					V(x + 0.4, cy - 0.1, s * 1.15),
					0.14,
					C.BRASS,
					M.Metal
				)
			)
		end
	end
	fine(b.box("CoffinPlate", V(1.0, 0.04, 0.6), V(0.8, cy + 0.89, 0.12), C.BRASS, M.Metal))

	local spot: Kit.HidingSpot? = nil
	if opt(o, "hide", true) then
		spot = Kit.hideVolume(
			"UnderBierHidingVolume",
			at * CFrame.new(0, 1.2, 0),
			V(4.0, 2.2, 1.4),
			"UnderTable",
			opt(o, "floor", 1),
			b.model
		)
	end
	return b.model, spot
end

return Furnish
