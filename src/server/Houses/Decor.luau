--!strict
--[[
	Decor: the small things that make a room look lived in and then left.

	Lamps and candles, all dead: nothing here gives light. The houses are
	meant to be walked with whatever light a player carries, and a single lit
	bulb would be the brightest thing in every room it is in.

	Then the dirt, which is most of what makes a room horrible rather than
	merely old: stains that have soaked into a floor, water that has run down
	a wall, paper coming away in strips, scratches, a hole where the boards
	have given way. Each is a handful of thin parts laid on a surface, a few
	hundredths of a stud proud of it and never exactly on it, so nothing
	flickers.

	Same conventions as Furnish: a piece is drawn in its own space, origin on
	the surface it belongs to, and the caller passes the world CFrame of that
	origin. For things on a wall the CFrame's LookVector points out of the
	wall into the room; for things on a floor or a table it is level.
]]

local Kit = require(script.Parent.HouseKit)
local Furnish = require(script.Parent.Furnish)

local C = Kit.C
local M = Enum.Material
local V = Vector3.new
local fine = Kit.detail
local soft = Kit.soft
local begin = Furnish.begin

local Decor = {}

type Options = Furnish.Options

local function opt(o: Options?, key: string, default: any): any
	if o and o[key] ~= nil then
		return o[key]
	end
	return default
end

-- Turn a wall frame (LookVector out of the wall) into one whose Up is out of
-- the wall, so a disc or a flat patch lies on the wall's face.
local ON_WALL = CFrame.Angles(math.pi / 2, 0, 0)

----------------------------------------------------------------------------
-- Dead lights
----------------------------------------------------------------------------

--[[
	A chandelier hanging from the ceiling point `at`: a rose, a chain, a turned
	column and a ring of arms, each with a cup and what is left of a candle.
	One candle gone, one burnt to a stub. No light.
]]
function Decor.chandelier(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Chandelier", at, parent)
	local metal: Color3 = opt(o, "metal", C.IRON)
	local drop: number = opt(o, "drop", 3)
	local arms: number = opt(o, "arms", 6)
	local r: number = opt(o, "radius", 2.2)
	local wear = Kit.wear()

	fine(b.disc("CeilingRose", V(0, -0.08, 0), 1.6, 0.16, C.RAIL, M.Wood))
	fine(b.rod("Chain", V(0, 0, 0), V(0, -drop, 0), 0.14, metal, M.Metal))
	local y = -drop
	fine(b.ball("Knop", V(0, y - 0.2, 0), 0.5, metal, M.Metal))
	b.rod("Column", V(0, y - 0.3, 0), V(0, y - 1.8, 0), 0.42, metal, M.Metal)
	fine(b.ball("Bowl", V(0, y - 1.6, 0), 0.9, metal, M.Metal))
	fine(b.ball("Drop", V(0, y - 2.2, 0), 0.34, metal, M.Metal))

	local armY = y - 1.5
	local tips: { Vector3 } = {}
	for i = 0, arms - 1 do
		local a = i * 2 * math.pi / arms
		local dir = V(math.cos(a), 0, math.sin(a))
		local elbow = dir * (r * 0.6) + V(0, armY - 0.45, 0)
		local tip = dir * r + V(0, armY + 0.05, 0)
		fine(b.rod("Arm", V(0, armY, 0), elbow, 0.16, metal, M.Metal))
		fine(b.rod("Arm", elbow, tip, 0.16, metal, M.Metal))
		fine(b.disc("Cup", tip + V(0, 0.08, 0), 0.5, 0.12, metal, M.Metal))
		table.insert(tips, tip)
		if i ~= 2 then
			local h = if i == 4 then 0.25 else wear:NextNumber(0.6, 1.1)
			fine(
				b.rod(
					"Candle",
					tip + V(0, 0.14, 0),
					tip + V(0, 0.14 + h, 0),
					0.22,
					C.WAX,
					M.SmoothPlastic
				)
			)
			fine(
				b.rod(
					"Drip",
					tip + V(0.1, 0.1, 0),
					tip + V(0.1, -0.3, 0),
					0.07,
					C.WAX,
					M.SmoothPlastic
				)
			)
		end
	end
	-- A ring joining the arm tips.
	for i = 1, #tips do
		fine(
			b.rod(
				"Ring",
				tips[i] + V(0, -0.05, 0),
				tips[i % #tips + 1] + V(0, -0.05, 0),
				0.1,
				metal,
				M.Metal
			)
		)
	end
	return b.model
end

-- A plain pendant lamp: chain, a dome of a shade, a dead bulb.
function Decor.pendant(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("PendantLamp", at, parent)
	local drop: number = opt(o, "drop", 3)
	local metal: Color3 = opt(o, "metal", C.IRON)
	fine(b.disc("CeilingRose", V(0, -0.06, 0), 1.0, 0.12, C.RAIL, M.Wood))
	fine(b.rod("Chain", V(0, 0, 0), V(0, -drop, 0), 0.12, metal, M.Metal))
	fine(b.disc("ShadeTop", V(0, -drop - 0.2, 0), 1.0, 0.4, metal, M.Metal))
	b.disc("Shade", V(0, -drop - 0.55, 0), 2.2, 0.35, metal, M.Metal)
	fine(b.ball("Bulb", V(0, -drop - 0.85, 0), 0.6, C.GLASS_DARK, M.Glass))
	return b.model
end

-- A candle sconce on a wall. `at` is on the wall face, looking into the room.
function Decor.sconce(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Sconce", at, parent)
	local metal: Color3 = opt(o, "metal", C.BRASS)
	fine(b.disc("Backplate", V(0, 0, -0.05), 0.8, 0.1, metal, M.Metal, ON_WALL))
	fine(b.rod("Arm", V(0, -0.1, -0.05), V(0, 0.1, -0.7), 0.12, metal, M.Metal))
	fine(b.disc("Cup", V(0, 0.15, -0.75), 0.45, 0.1, metal, M.Metal))
	fine(
		b.rod(
			"Candle",
			V(0, 0.2, -0.75),
			V(0, 0.2 + opt(o, "candle", 0.5), -0.75),
			0.2,
			C.WAX,
			M.SmoothPlastic
		)
	)
	return b.model
end

-- A candelabrum standing on a table top at `at`.
function Decor.candelabra(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Candelabra", at, parent)
	local metal: Color3 = opt(o, "metal", C.BRASS)
	local h: number = opt(o, "height", 2.2)
	local wear = Kit.wear()
	fine(b.disc("Base", V(0, 0.08, 0), 0.9, 0.16, metal, M.Metal))
	fine(b.rod("Stem", V(0, 0.1, 0), V(0, h, 0), 0.16, metal, M.Metal))
	fine(b.ball("Knop", V(0, h * 0.35, 0), 0.32, metal, M.Metal))
	local cups = { V(0, h + 0.05, 0) }
	for _, x in { -0.75, 0.75 } do
		fine(b.rod("Arm", V(0, h * 0.72, 0), V(x, h * 0.72 + 0.1, 0), 0.1, metal, M.Metal))
		fine(b.rod("Arm", V(x, h * 0.72 + 0.1, 0), V(x, h - 0.2, 0), 0.1, metal, M.Metal))
		table.insert(cups, V(x, h - 0.15, 0))
	end
	for i, p in cups do
		fine(b.disc("Cup", p, 0.36, 0.1, metal, M.Metal))
		if i ~= 3 or not opt(o, "fallen", true) then
			fine(
				b.rod(
					"Candle",
					p + V(0, 0.05, 0),
					p + V(0, 0.05 + wear:NextNumber(0.3, 0.8), 0),
					0.17,
					C.WAX,
					M.SmoothPlastic
				)
			)
		end
	end
	if opt(o, "fallen", true) then
		-- The third candle has fallen out and rolled.
		fine(
			b.rod(
				"FallenCandle",
				V(0.9, 0.09, -0.5),
				V(1.4, 0.09, -0.8),
				0.17,
				C.WAX,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

-- A hurricane lantern, cold, standing on whatever `at` is on.
function Decor.lantern(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Lantern", at, parent)
	local metal: Color3 = opt(o, "metal", C.RUST)
	fine(b.disc("Fount", V(0, 0.2, 0), 0.9, 0.4, metal, M.CorrodedMetal))
	local glass = fine(b.rod("Chimney", V(0, 0.4, 0), V(0, 1.4, 0), 0.6, C.GLASS_DARK, M.Glass))
	glass.Transparency = 0.35
	fine(b.disc("Cap", V(0, 1.45, 0), 0.8, 0.14, metal, M.CorrodedMetal))
	for _, x in { -1, 1 } do
		fine(b.rod("Guard", V(x * 0.42, 0.4, 0), V(x * 0.42, 1.45, 0), 0.06, metal, M.Metal))
	end
	local prev = V(-0.45, 1.5, 0)
	for k = 1, 4 do
		local a = math.pi * k / 4
		local p = V(-0.45 * math.cos(a), 1.5 + 0.5 * math.sin(a), 0)
		fine(b.rod("Bail", prev, p, 0.06, metal, M.Metal))
		prev = p
	end
	return b.model
end

----------------------------------------------------------------------------
-- Cloth
----------------------------------------------------------------------------

--[[
	A rug on the floor at `at`: the field, a darker border, a worn patch.
	Laid a few hundredths above the floor and never colliding, so it can not
	trip anyone or flicker.
]]
function Decor.rug(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Rug", at, parent)
	local W: number = opt(o, "width", 10)
	local L: number = opt(o, "length", 14)
	local field: Color3 = opt(o, "color", C.RUG)
	local border: Color3 = opt(o, "border", C.RUG_BORDER)
	fine(b.box("Rug", V(W, 0.05, L), V(0, 0.045, 0), field, M.Carpet))
	for _, z in { -1, 1 } do
		fine(b.box("RugBorder", V(W, 0.06, 0.8), V(0, 0.05, z * (L / 2 - 0.4)), border, M.Carpet))
	end
	for _, x in { -1, 1 } do
		fine(
			b.box(
				"RugBorder",
				V(0.8, 0.061, L - 1.6),
				V(x * (W / 2 - 0.4), 0.05, 0),
				border,
				M.Carpet
			)
		)
	end
	fine(b.disc("RugMedallion", V(0, 0.07, 0), math.min(W, L) * 0.42, 0.02, border, M.Carpet))
	fine(
		b.disc(
			"Worn",
			V(W * 0.18, 0.072, -L * 0.2),
			math.min(W, L) * 0.3,
			0.02,
			Kit.weathered(field, 0.2),
			M.Carpet
		)
	)
	return b.model
end

--[[
	Curtains either side of a window, hanging from a round pole with ball
	finials. `at` is on the wall's structural face at the middle of the
	window's head, looking into the room. Each curtain is a few soft folds;
	one has been torn shorter than the other. The pole stands out on its
	brackets far enough that the folds hang in front of the window's sill
	and lintel, which are proud of the wall, rather than through them.
]]
function Decor.curtains(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Curtains", at, parent)
	local w: number = opt(o, "width", 6)
	local drop: number = opt(o, "drop", 9)
	local cloth: Color3 = opt(o, "color", C.VELVET)
	local out: number = opt(o, "standoff", 0.95)
	local wear = Kit.wear()
	local poleY = 0.8
	fine(
		b.rod(
			"Pole",
			V(-w / 2 - 1.4, poleY, -out),
			V(w / 2 + 1.4, poleY, -out),
			0.2,
			C.BRASS,
			M.Metal
		)
	)
	for _, x in { -1, 1 } do
		fine(b.ball("Finial", V(x * (w / 2 + 1.5), poleY, -out), 0.36, C.BRASS, M.Metal))
		fine(
			b.rod(
				"Bracket",
				V(x * (w / 2 + 1.1), poleY, -out),
				V(x * (w / 2 + 1.1), poleY, -0.12),
				0.1,
				C.BRASS,
				M.Metal
			)
		)
		local len = if x > 0 then drop * wear:NextNumber(0.55, 0.75) else drop
		for k = 0, 3 do
			local fx = x * (w / 2 - 0.2 + k * 0.42)
			soft(
				b.rod(
					"Fold",
					V(fx, poleY - 0.1, -out - 0.05),
					V(fx + x * 0.1, poleY - len, -out - 0.1 - (k % 2) * 0.12),
					0.5,
					Kit.weathered(cloth, 0.08),
					M.Fabric
				)
			)
		end
	end
	return b.model
end

----------------------------------------------------------------------------
-- On the walls
----------------------------------------------------------------------------

--[[
	A framed painting on a wall. `subject` "portrait" is a figure against the
	dark, face too dim to make out; "landscape" a horizon and a dead tree.
	`tilt` hangs it crooked, in degrees.
]]
function Decor.painting(at: CFrame, parent: Instance, o: Options?): Model
	local tilt: number = opt(o, "tilt", 0)
	local b = begin("Painting", at * CFrame.Angles(0, 0, math.rad(tilt)), parent)
	b.model.WorldPivot = at
	local w: number = opt(o, "width", 3.2)
	local h: number = opt(o, "height", 4.2)
	local frameColor: Color3 = opt(o, "frame", Kit.rgb(74, 58, 34))
	local subject: string = opt(o, "subject", "portrait")
	local ground = Kit.rgb(30, 24, 20)

	b.box("Frame", V(w + 0.6, h + 0.6, 0.22), V(0, 0, -0.11), frameColor, M.Wood)
	fine(b.box("Canvas", V(w, h, 0.05), V(0, 0, -0.245), ground, M.Fabric))
	if subject == "portrait" then
		-- A bust: round shoulders on a square body, standing on the bottom
		-- of the canvas so nothing of it hangs out past the frame. Each layer
		-- a little further out than the one behind, so no two faces share a
		-- plane.
		local dark = Kit.rgb(26, 20, 18)
		local bust = math.min(w * 0.62, h * 0.44)
		fine(
			b.disc("Shoulders", V(0, -h / 2 + bust / 2, -0.29), bust, 0.04, dark, M.Fabric, ON_WALL)
		)
		fine(
			b.box("Body", V(bust, bust / 2, 0.04), V(0, -h / 2 + bust / 4, -0.285), dark, M.Fabric)
		)
		fine(
			b.disc(
				"Head",
				V(0, h * 0.08, -0.33),
				w * 0.34,
				0.04,
				Kit.rgb(60, 48, 40),
				M.Fabric,
				ON_WALL
			)
		)
		-- Where the eyes should be, two darker smudges.
		for _, x in { -0.18, 0.18 } do
			fine(
				b.disc(
					"Eye",
					V(x * w * 0.5, h * 0.12, -0.36),
					w * 0.07,
					0.03,
					C.SOOT,
					M.Fabric,
					ON_WALL
				)
			)
		end
	else
		fine(
			b.box(
				"Sky",
				V(w, h * 0.55, 0.04),
				V(0, h * 0.225, -0.27),
				Kit.rgb(52, 46, 42),
				M.Fabric
			)
		)
		fine(
			b.box(
				"Land",
				V(w, h * 0.12, 0.04),
				V(0, -h * 0.1, -0.28),
				Kit.rgb(36, 30, 24),
				M.Fabric
			)
		)
		fine(
			b.rod(
				"Tree",
				V(w * 0.2, -h * 0.1, -0.3),
				V(w * 0.22, h * 0.3, -0.3),
				0.12,
				Kit.rgb(22, 18, 16),
				M.Fabric
			)
		)
		fine(
			b.rod(
				"Branch",
				V(w * 0.21, h * 0.15, -0.3),
				V(w * 0.36, h * 0.28, -0.3),
				0.07,
				Kit.rgb(22, 18, 16),
				M.Fabric
			)
		)
	end
	return b.model
end

function Decor.mirror(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Mirror", at, parent)
	local w: number = opt(o, "width", 3)
	local h: number = opt(o, "height", 4.4)
	b.box("Frame", V(w + 0.5, h + 0.5, 0.2), V(0, 0, -0.1), Kit.rgb(70, 56, 34), M.Wood)
	fine(b.ball("Crest", V(0, h / 2 + 0.4, -0.32), 0.6, Kit.rgb(70, 56, 34), M.Wood))
	local glass = fine(b.box("Glass", V(w, h, 0.05), V(0, 0, -0.23), C.GLASS_DARK, M.Glass))
	glass.Reflectance = 0.15
	for k = 0, 3 do
		fine(
			b.box(
				"Crack",
				V(0.05, h * 0.6, 0.02),
				V(-0.2 + k * 0.1, 0.2, -0.265),
				C.SOOT,
				M.SmoothPlastic,
				CFrame.Angles(0, 0, math.rad(-40 + k * 27))
			)
		)
	end
	return b.model
end

--[[
	A wall shelf on two brackets with jars and bottles along it. `at` is on
	the wall at the shelf's middle, at shelf height.
]]
function Decor.wallShelf(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("WallShelf", at, parent)
	local w: number = opt(o, "width", 5)
	local wear = Kit.wear()
	b.box("Shelf", V(w, 0.2, 1.1), V(0, 0, -0.55), C.OAK, M.Wood)
	for _, x in { -w / 2 + 0.6, w / 2 - 0.6 } do
		fine(b.box("Bracket", V(0.18, 0.9, 0.9), V(x, -0.5, -0.45), C.IRON, M.Metal))
	end
	local x = -w / 2 + 0.5
	while x < w / 2 - 0.4 do
		local kind = wear:NextInteger(1, 3)
		if kind == 1 then
			local hgt = wear:NextNumber(0.7, 1.2)
			fine(b.disc("Jar", V(x, 0.1 + hgt / 2, -0.55), 0.6, hgt, C.GLASS_DARK, M.Glass))
			fine(b.disc("JarLid", V(x, 0.14 + hgt, -0.55), 0.62, 0.08, C.RUST, M.CorrodedMetal))
		elseif kind == 2 then
			local hgt = wear:NextNumber(0.9, 1.3)
			fine(
				b.disc(
					"Bottle",
					V(x, 0.1 + hgt / 2, -0.55),
					0.42,
					hgt,
					Kit.rgb(40, 34, 24),
					M.Glass
				)
			)
			fine(
				b.rod(
					"BottleNeck",
					V(x, 0.1 + hgt, -0.55),
					V(x, 0.45 + hgt, -0.55),
					0.16,
					Kit.rgb(40, 34, 24),
					M.Glass
				)
			)
		end
		x += wear:NextNumber(0.6, 0.9)
	end
	return b.model
end

-- Antlers on a wooden shield, for the lodge.
function Decor.antlers(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Antlers", at, parent)
	local s: number = opt(o, "scale", 1)
	local bone = C.BONE
	fine(b.disc("Shield", V(0, 0, -0.1), 1.8 * s, 0.2, C.WALNUT, M.Wood, ON_WALL))
	fine(
		b.box(
			"Skull",
			V(0.7 * s, 0.6 * s, 0.9 * s),
			V(0, 0.1 * s, -0.55 * s),
			bone,
			M.SmoothPlastic,
			CFrame.Angles(math.rad(-25), 0, 0)
		)
	)
	for _, x in { -1, 1 } do
		local base = V(x * 0.25 * s, 0.35 * s, -0.5 * s)
		local mid = V(x * 1.2 * s, 1.3 * s, -0.7 * s)
		local tip = V(x * 1.5 * s, 2.5 * s, -0.4 * s)
		fine(b.rod("Beam", base, mid, 0.2 * s, bone, M.SmoothPlastic))
		fine(b.rod("Beam", mid, tip, 0.16 * s, bone, M.SmoothPlastic))
		for k, t in { 0.3, 0.6, 0.9 } do
			local p = base:Lerp(mid, t)
			if k == 3 then
				p = mid:Lerp(tip, 0.5)
			end
			fine(
				b.rod(
					"Tine",
					p,
					p + V(x * 0.1 * s, 0.8 * s, -0.35 * s),
					0.1 * s,
					bone,
					M.SmoothPlastic
				)
			)
		end
	end
	return b.model
end

----------------------------------------------------------------------------
-- On tables
----------------------------------------------------------------------------

--[[
	One place at a table, at the table's edge, looking at the diner: a plate
	on a charger, a knife and fork, a goblet. `upset` knocks the goblet over
	and leaves what was in it across the cloth.
]]
function Decor.placeSetting(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("PlaceSetting", at, parent)
	local china = Kit.rgb(62, 56, 48)
	fine(b.disc("Charger", V(0, 0.03, 1.1), 1.7, 0.05, C.BRASS, M.Metal))
	fine(b.disc("Plate", V(0, 0.08, 1.1), 1.3, 0.06, china, M.SmoothPlastic))
	fine(b.box("Knife", V(0.1, 0.03, 1.0), V(0.95, 0.03, 1.1), C.IRON, M.Metal))
	fine(b.box("Fork", V(0.12, 0.03, 0.9), V(-0.95, 0.03, 1.1), C.IRON, M.Metal))
	if opt(o, "upset", false) then
		fine(b.rod("Goblet", V(0.95, 0.12, 0.2), V(1.55, 0.12, 0.05), 0.32, C.BRASS, M.Metal))
		fine(b.disc("Spill", V(1.6, 0.05, -0.2), 1.1, 0.02, C.BLOOD_OLD, M.SmoothPlastic))
	else
		fine(b.disc("GobletFoot", V(0.9, 0.04, 0.35), 0.34, 0.05, C.BRASS, M.Metal))
		fine(b.rod("GobletStem", V(0.9, 0.05, 0.35), V(0.9, 0.5, 0.35), 0.08, C.BRASS, M.Metal))
		fine(b.disc("GobletCup", V(0.9, 0.7, 0.35), 0.38, 0.42, C.BRASS, M.Metal))
	end
	if opt(o, "food", false) then
		-- Whatever was served, a long time ago.
		fine(b.ball("Food", V(0.1, 0.2, 1.15), 0.5, Kit.rgb(40, 30, 22), M.SmoothPlastic))
		fine(b.ball("Food", V(-0.2, 0.18, 1.0), 0.36, Kit.rgb(34, 26, 20), M.SmoothPlastic))
	end
	return b.model
end

-- A great platter and what was on it.
function Decor.platter(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Platter", at, parent)
	fine(b.disc("Platter", V(0, 0.05, 0), 2.8, 0.1, C.BRASS, M.Metal))
	fine(b.ball("Roast", V(0, 0.45, 0), 1.3, Kit.rgb(44, 26, 20), M.SmoothPlastic))
	fine(b.ball("Roast", V(0.5, 0.35, 0.3), 0.8, Kit.rgb(40, 24, 18), M.SmoothPlastic))
	fine(b.rod("Bone", V(-0.3, 0.6, -0.2), V(-1.0, 0.95, -0.6), 0.16, C.BONE, M.SmoothPlastic))
	fine(b.disc("Juice", V(0.2, 0.11, 0.2), 2.1, 0.02, C.BLOOD_OLD, M.SmoothPlastic))
	return b.model
end

function Decor.books(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Books", at, parent)
	local wear = Kit.wear()
	local y = 0
	for i = 1, opt(o, "count", 4) do
		local t = wear:NextNumber(0.25, 0.4)
		fine(
			b.box(
				"Book",
				V(wear:NextNumber(1.1, 1.5), t, wear:NextNumber(0.8, 1.1)),
				V(0, y + t / 2, 0),
				Kit.weathered(C.LEATHER, 0.25),
				M.Leather,
				CFrame.Angles(0, wear:NextNumber(-0.4, 0.4), 0)
			)
		)
		y += t
	end
	return b.model
end

function Decor.vase(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Vase", at, parent)
	local glaze: Color3 = opt(o, "color", Kit.rgb(60, 44, 40))
	local wear = Kit.wear()
	fine(b.disc("Foot", V(0, 0.08, 0), 0.6, 0.16, glaze, M.SmoothPlastic))
	b.ball("Belly", V(0, 0.6, 0), 1.0, glaze, M.SmoothPlastic)
	fine(b.disc("Neck", V(0, 1.2, 0), 0.44, 0.5, glaze, M.SmoothPlastic))
	fine(b.disc("Lip", V(0, 1.46, 0), 0.62, 0.08, glaze, M.SmoothPlastic))
	-- Dead flowers: dry stems, heads dropped.
	for i = 1, 5 do
		local a = i * 1.26
		local tip = V(math.cos(a) * 0.6, 2.4 + wear:NextNumber(0, 0.8), math.sin(a) * 0.6)
		fine(b.rod("Stem", V(0, 1.3, 0), tip, 0.06, Kit.rgb(58, 48, 32), M.Wood))
		fine(b.ball("DeadHead", tip - V(0, 0.15, 0), 0.26, Kit.rgb(52, 32, 28), M.Fabric))
	end
	return b.model
end

function Decor.birdcage(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Birdcage", at, parent)
	local metal = C.BRASS
	local r, h = 0.8, 1.8
	fine(b.disc("Base", V(0, 0.08, 0), r * 2 + 0.2, 0.16, metal, M.Metal))
	for i = 0, 11 do
		local a = i * math.pi / 6
		fine(
			b.rod(
				"Wire",
				V(math.cos(a) * r, 0.1, math.sin(a) * r),
				V(math.cos(a) * r * 0.9, h, math.sin(a) * r * 0.9),
				0.05,
				metal,
				M.Metal
			)
		)
	end
	fine(b.ball("Dome", V(0, h, 0), r * 1.8, metal, M.Metal)).Transparency = 0.5
	fine(b.rod("Hook", V(0, h + 0.8, 0), V(0, h + 1.2, 0), 0.07, metal, M.Metal))
	-- Something small lying on the floor of it.
	fine(b.ball("Bird", V(0.2, 0.3, 0.1), 0.34, Kit.rgb(40, 34, 30), M.Fabric))
	return b.model
end

function Decor.globe(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("Globe", at, parent)
	local wood = C.WALNUT
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		fine(
			b.rod(
				"Leg",
				V(math.cos(a) * 0.9, 0, math.sin(a) * 0.9),
				V(0, 2.2, 0),
				0.18,
				wood,
				M.Wood
			)
		)
	end
	b.ball("Globe", V(0, 3.1, 0), 1.8, Kit.rgb(52, 50, 44), M.SmoothPlastic)
	fine(b.ball("Land", V(0.35, 3.3, -0.3), 1.3, Kit.rgb(70, 58, 40), M.SmoothPlastic))
	local prev: Vector3? = nil
	for k = 0, 8 do
		local a = math.pi * k / 8 - math.pi / 2
		local p = V(0, 3.1 + math.sin(a) * 1.05, math.cos(a) * 1.05)
		if prev then
			fine(b.rod("Meridian", prev, p, 0.08, C.BRASS, M.Metal))
		end
		prev = p
	end
	return b.model
end

----------------------------------------------------------------------------
-- Dirt, damage and worse
----------------------------------------------------------------------------

--[[
	A stain soaked into a surface: a few overlapping discs of different sizes,
	each a hair higher than the last so no two tops share a plane. `at` lies
	on the surface with its UpVector out of it.
]]
function Decor.stain(at: CFrame, parent: Instance, size: number, color: Color3?)
	local wear = Kit.wear()
	local c = color or C.GRIME
	for i = 1, wear:NextInteger(3, 5) do
		local r = size * wear:NextNumber(0.35, 0.7)
		local off = V(
			wear:NextNumber(-size, size) * 0.45,
			0.04 + i * 0.006,
			wear:NextNumber(-size, size) * 0.45
		)
		fine(
			Kit.disc(
				"Stain",
				at * CFrame.new(off),
				r * 2,
				0.02,
				Kit.weathered(c, 0.12),
				M.SmoothPlastic,
				parent
			)
		)
	end
end

--[[
	A smear from `a` to `b` (world points on a floor): something dragged. A
	flat strip with rounded ends, narrowing as it goes.
]]
function Decor.smear(a: Vector3, b: Vector3, parent: Instance, width: number, color: Color3?)
	local c = color or C.BLOOD_OLD
	local d = b - a
	local flat = V(d.X, 0, d.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	local mid = (a + b) / 2 + V(0, 0.045, 0)
	local frame = CFrame.lookAt(mid, mid + flat)
	fine(Kit.part("Smear", V(width * 0.8, 0.02, flat.Magnitude), frame, c, M.SmoothPlastic, parent))
	fine(Kit.disc("Smear", CFrame.new(a + V(0, 0.05, 0)), width, 0.02, c, M.SmoothPlastic, parent))
	fine(
		Kit.disc(
			"Smear",
			CFrame.new(b + V(0, 0.052, 0)),
			width * 0.6,
			0.02,
			c,
			M.SmoothPlastic,
			parent
		)
	)
end

--[[
	Water that has run down a wall from a leak: streaks of different lengths
	hanging from a line. `at` is on the wall face where the leak starts,
	looking into the room.
]]
function Decor.drips(at: CFrame, parent: Instance, width: number, length: number, color: Color3?)
	local wear = Kit.wear()
	local c = color or C.GRIME
	fine(
		Kit.part(
			"WaterMark",
			V(width, length * 0.25, 0.03),
			at * CFrame.new(0, -length * 0.1, -0.04),
			c,
			M.SmoothPlastic,
			parent
		)
	)
	local n = math.max(2, math.floor(width / 0.45))
	for i = 1, n do
		local x = -width / 2 + width * (i - 0.5) / n + wear:NextNumber(-0.15, 0.15)
		local len = length * wear:NextNumber(0.35, 1.0)
		fine(
			Kit.part(
				"Drip",
				V(wear:NextNumber(0.1, 0.25), len, 0.03),
				at * CFrame.new(x, -len / 2, -0.05),
				Kit.weathered(c, 0.15),
				M.SmoothPlastic,
				parent
			)
		)
		fine(
			Kit.ball(
				"DripEnd",
				(at * CFrame.new(x, -len, -0.05)).Position,
				0.2,
				c,
				M.SmoothPlastic,
				parent
			)
		)
	end
end

--[[
	A strip of wallpaper coming away: hinged at its top, hanging out from the
	wall, its bottom edge curled. `at` is on the wall face at the top of the
	strip, looking into the room.
]]
function Decor.peel(at: CFrame, parent: Instance, paper: Color3, o: Options?)
	local wear = Kit.wear()
	local w: number = opt(o, "width", 1.4)
	local len: number = opt(o, "length", 3.5)
	local lean = math.rad(wear:NextNumber(12, 28))
	local strip = at
		* CFrame.new(0, 0, -0.12)
		* CFrame.Angles(-lean, 0, math.rad(wear:NextNumber(-6, 6)))
	fine(
		Kit.part(
			"PeelingPaper",
			V(w, len, 0.05),
			strip * CFrame.new(0, -len / 2, 0),
			paper,
			M.Fabric,
			parent
		)
	)
	-- The back of the paper, where it has come away, is paler and stained.
	fine(
		Kit.part(
			"PeelingBack",
			V(w - 0.1, len - 0.1, 0.02),
			strip * CFrame.new(0, -len / 2, 0.035),
			Kit.rgb(70, 60, 46),
			M.Fabric,
			parent
		)
	)
	local curlAt = (strip * CFrame.new(0, -len, 0)).Position
	local side = (strip.RightVector * (w / 2))
	fine(Kit.rod("PeelCurl", curlAt - side, curlAt + side, 0.3, paper, M.Fabric, parent))
	-- The bare plaster left behind, darker.
	fine(
		Kit.part(
			"BarePlaster",
			V(w + 0.2, len * 0.9, 0.03),
			at * CFrame.new(0, -len * 0.45, -0.1),
			Kit.rgb(62, 54, 44),
			M.Plaster,
			parent
		)
	)
end

--[[
	Four long scratches in a surface, as if something clawed at it. `at` is on
	the surface looking out of it.
]]
function Decor.scratches(at: CFrame, parent: Instance, length: number?, color: Color3?)
	local len = length or 3
	local c = color or C.SOOT
	for i = 0, 3 do
		fine(
			Kit.part(
				"Scratch",
				V(0.07, len * (0.8 + 0.07 * i), 0.03),
				at
					* CFrame.new(-0.45 + i * 0.3, -0.1 * i, -0.04)
					* CFrame.Angles(0, 0, math.rad(-14)),
				c,
				M.SmoothPlastic,
				parent
			)
		)
	end
end

--[[
	A hole where the floorboards have given way: a black gap and the broken
	ends of three boards sagging into it. `at` is on the floor, level. The
	hole is a dark patch, not a real opening — the floor underneath still
	holds, so nobody falls through into a room they cannot get out of.
]]
function Decor.brokenBoards(at: CFrame, parent: Instance, o: Options?)
	local w: number = opt(o, "width", 2.6)
	local l: number = opt(o, "length", 3.4)
	fine(
		Kit.part(
			"Hole",
			V(w, 0.02, l),
			at * CFrame.new(0, 0.03, 0),
			Kit.rgb(12, 10, 9),
			M.SmoothPlastic,
			parent
		)
	)
	for i = -1, 1 do
		local x = i * (w / 3)
		fine(
			Kit.part(
				"BrokenBoard",
				V(w / 3 - 0.1, 0.25, l * 0.45),
				at * CFrame.new(x, -0.05, -l * 0.3) * CFrame.Angles(math.rad(-16 - 6 * i), 0, 0),
				C.FLOOR,
				M.WoodPlanks,
				parent
			)
		)
	end
	fine(
		Kit.part(
			"BrokenBoard",
			V(w / 3 - 0.1, 0.25, l * 0.35),
			at * CFrame.new(w / 3, -0.1, l * 0.3) * CFrame.Angles(math.rad(20), 0, 0),
			C.FLOOR,
			M.WoodPlanks,
			parent
		)
	)
end

--[[
	A little heap of plaster and lath come down from a ceiling, and the scar
	it left above. `at` is on the floor under the damage.
]]
function Decor.fallenPlaster(at: CFrame, parent: Instance, ceiling: number)
	local wear = Kit.wear()
	for _ = 1, 7 do
		local s = wear:NextNumber(0.3, 0.8)
		fine(
			Kit.part(
				"Plaster",
				V(s, s * 0.35, s * 0.8),
				at
					* CFrame.new(
						wear:NextNumber(-1.2, 1.2),
						s * 0.18 + 0.02,
						wear:NextNumber(-1.2, 1.2)
					)
					* CFrame.Angles(0, wear:NextNumber(0, 3), 0),
				Kit.rgb(64, 56, 46),
				M.Plaster,
				parent
			)
		)
	end
	for i = -1, 1 do
		fine(
			Kit.part(
				"Lath",
				V(0.25, 0.12, 2.6),
				at * CFrame.new(i * 0.6, 0.12, 0) * CFrame.Angles(0, 0.5 + i * 0.3, 0),
				C.WALNUT,
				M.Wood,
				parent
			)
		)
	end
	fine(
		Kit.part(
			"CeilingScar",
			V(3.4, 0.03, 3.0),
			at * CFrame.new(0, ceiling - 0.04, 0),
			Kit.rgb(40, 32, 26),
			M.Plaster,
			parent
		)
	)
end

--[[
	A talking board on a table: two arcs of letters, a row of numbers, a sun
	and a moon in the top corners, and the planchette left halfway through a
	word. None of it is text; at this distance and in this dark, the marks
	are enough. `at` is on the table top.
]]
function Decor.spiritBoard(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("SpiritBoard", at, parent)
	local W, D = 2.6, 1.7
	b.box("Board", V(W, 0.08, D), V(0, 0.04, 0), Kit.rgb(60, 46, 32), M.Wood)
	local ink = Kit.rgb(24, 18, 14)
	for row, r in { 1.15, 0.85 } do
		local marks = 13
		for k = 0, marks - 1 do
			local a = math.rad(-54 + k * 108 / (marks - 1))
			local p =
				V(math.sin(a) * r, 0.085, 0.55 - (row - 1) * 0.28 - (1 - math.cos(a)) * r * 0.5)
			fine(
				b.box(
					"Letter",
					V(0.07, 0.02, 0.13),
					p,
					ink,
					M.SmoothPlastic,
					CFrame.Angles(0, -a, 0)
				)
			)
		end
	end
	for k = 0, 9 do
		fine(
			b.box(
				"Number",
				V(0.07, 0.02, 0.1),
				V(-0.8 + k * 0.18, 0.085, -0.3),
				ink,
				M.SmoothPlastic
			)
		)
	end
	fine(b.disc("Sun", V(-1.05, 0.085, 0.62), 0.28, 0.02, ink, M.SmoothPlastic))
	fine(b.disc("Moon", V(1.05, 0.085, 0.62), 0.28, 0.02, ink, M.SmoothPlastic))
	fine(b.box("Goodbye", V(0.9, 0.02, 0.08), V(0, 0.085, -0.6), ink, M.SmoothPlastic))
	-- The planchette: a pointed wooden heart on three small feet, with a
	-- glass eye through it.
	local pc = V(0.35, 0.14, 0.3)
	local turn = CFrame.Angles(0, math.rad(opt(o, "turn", 25)), 0)
	fine(b.disc("Planchette", pc, 0.62, 0.05, Kit.rgb(70, 56, 40), M.Wood, turn))
	fine(b.disc("Lens", pc + V(0, 0.03, 0), 0.2, 0.03, C.GLASS_DARK, M.Glass, turn))
	return b.model
end

--[[
	A cellar hatch in a floor: a frame of boards round a square of planks
	with an iron ring to lift it. It lifts on nothing: there is no cellar.
	`at` is on the floor at the hatch's middle.
]]
function Decor.hatch(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("CellarHatch", at, parent)
	local s: number = opt(o, "size", 3.6)
	local wood = Kit.weathered(C.WALNUT, 0.1)
	b.box("Lid", V(s, 0.1, s), V(0, 0.05, 0), wood, M.WoodPlanks)
	for _, z in { -1, 1 } do
		fine(b.box("Frame", V(s + 0.4, 0.12, 0.3), V(0, 0.06, z * (s / 2 + 0.05)), C.RAIL, M.Wood))
		fine(b.box("Frame", V(0.3, 0.12, s + 0.4), V(z * (s / 2 + 0.05), 0.06, 0), C.RAIL, M.Wood))
		fine(b.box("Strap", V(s - 0.4, 0.04, 0.25), V(0, 0.12, z * s * 0.28), C.IRON, M.Metal))
	end
	-- The ring: a hoop of short bars lying flat, and its staple.
	local prev: Vector3? = nil
	for k = 0, 8 do
		local a = k * math.pi * 2 / 8
		local p = V(math.cos(a) * 0.35, 0.14, math.sin(a) * 0.35 - 0.3)
		if prev then
			fine(b.rod("Ring", prev, p, 0.08, C.IRON, M.Metal))
		end
		prev = p
	end
	fine(b.box("Staple", V(0.3, 0.1, 0.2), V(0, 0.14, 0.1), C.IRON, M.Metal))
	return b.model
end

----------------------------------------------------------------------------
-- The lodge's walls, floors and ceilings
----------------------------------------------------------------------------

local FUR = Kit.rgb(48, 36, 28)

--[[
	A bearskin on the floor, head toward -Z: the hide spread flat, four legs
	splayed with their claws, and the head still on it, mouth open.
]]
function Decor.bearRug(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("BearRug", at, parent)
	local fur: Color3 = opt(o, "fur", FUR)
	fine(b.disc("Hide", V(0, 0.05, 0.2), 4.6, 0.1, fur, M.Fabric))
	fine(b.disc("Hide", V(0, 0.06, 1.8), 3.8, 0.1, fur, M.Fabric))
	fine(b.disc("Hide", V(0, 0.055, -1.4), 3.4, 0.1, fur, M.Fabric))
	for _, x in { -1, 1 } do
		for _, z in { -1.3, 1.7 } do
			local dir = V(x * 1.0, 0, if z < 0 then -0.55 else 0.6).Unit
			local root = V(x * 1.4, 0.05, z)
			local tip = root + dir * 2.4
			-- Flat, so a box turned to run along `dir`, not a squashed rod: a
			-- cylinder is always as round as its thinner side.
			fine(
				b.box(
					"Leg",
					V(2.4, 0.1, 0.9),
					(root + tip) / 2,
					fur,
					M.Fabric,
					CFrame.Angles(0, math.atan2(-dir.Z, dir.X), 0)
				)
			)
			for k = -1, 1 do
				local c = tip + dir * 0.35 + dir:Cross(V(0, 1, 0)) * (k * 0.2)
				fine(b.rod("Claw", c, c + dir * 0.3, 0.08, Kit.rgb(40, 34, 28), M.SmoothPlastic))
			end
		end
	end
	fine(b.box("Tail", V(0.5, 0.1, 0.8), V(0, 0.06, 3.9), fur, M.Fabric))
	-- The head, raised a little on its own neck.
	b.rod("Head", V(0, 0.7, -3.3), V(0, 0.68, -4.3), 1.3, fur, M.Fabric)
	fine(b.rod("Snout", V(0, 0.45, -4.3), V(0, 0.38, -5.0), 0.75, Kit.rgb(56, 42, 32), M.Fabric))
	fine(b.ball("Nose", V(0, 0.42, -5.05), 0.32, C.SOOT, M.SmoothPlastic))
	fine(b.box("Mouth", V(0.55, 0.2, 0.6), V(0, 0.18, -4.7), Kit.rgb(40, 14, 12), M.SmoothPlastic))
	for _, x in { -0.45, 0.45 } do
		fine(b.ball("Ear", V(x, 1.15, -3.3), 0.45, fur, M.Fabric))
		fine(b.ball("Eye", V(x * 0.7, 0.85, -4.1), 0.16, C.GLASS_DARK, M.Glass))
		fine(
			b.rod(
				"Fang",
				V(x * 0.4, 0.34, -4.9),
				V(x * 0.4, 0.14, -4.9),
				0.08,
				C.BONE,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

-- One antler: a curved beam and tines, rooted at `base` and spreading
-- toward `out` (a unit vector), in piece space.
local function antler(b: any, base: Vector3, out: Vector3, s: number, colour: Color3)
	local up = V(0, 1, 0)
	local mid = base + out * (1.1 * s) + up * (0.9 * s)
	local tip = mid + out * (0.5 * s) + up * (1.3 * s)
	fine(b.rod("Beam", base, mid, 0.22 * s, colour, M.SmoothPlastic))
	fine(b.rod("Beam", mid, tip, 0.17 * s, colour, M.SmoothPlastic))
	for k, t in { 0.35, 0.8, 0.5 } do
		local p = if k < 3 then base:Lerp(mid, t) else mid:Lerp(tip, t)
		fine(
			b.rod(
				"Tine",
				p,
				p + up * (0.75 * s) - out * (0.2 * s),
				0.1 * s,
				colour,
				M.SmoothPlastic
			)
		)
	end
end

--[[
	A chandelier made of antlers: a hoop on a chain with antlers set round
	it pointing out and up, and cups with candles that will not be lit.
	`at` is the point it hangs from.
]]
function Decor.antlerChandelier(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("AntlerChandelier", at, parent)
	local drop: number = opt(o, "drop", 3)
	local r: number = opt(o, "radius", 2.2)
	local n: number = opt(o, "antlers", 6)
	fine(b.rod("Chain", V(0, 0, 0), V(0, -drop, 0), 0.14, C.IRON, M.Metal))
	for k = 0, 3 do
		local a = k * math.pi / 2
		fine(
			b.rod(
				"Chain",
				V(0, -drop, 0),
				V(math.cos(a) * r, -drop - 1.1, math.sin(a) * r),
				0.08,
				C.IRON,
				M.Metal
			)
		)
	end
	local y = -drop - 1.1
	local prev: Vector3? = nil
	for k = 0, 12 do
		local a = k * math.pi * 2 / 12
		local p = V(math.cos(a) * r, y, math.sin(a) * r)
		if prev then
			fine(b.rod("Hoop", prev, p, 0.3, C.IRON, M.Metal))
		end
		prev = p
	end
	local wear = Kit.wear()
	for k = 0, n - 1 do
		local a = k * math.pi * 2 / n
		local out = V(math.cos(a), 0, math.sin(a))
		antler(b, out * r + V(0, y, 0), out, 0.9, C.BONE)
		local cup = out * r + V(0, y + 0.2, 0) + V(-out.Z, 0, out.X) * 0.9
		fine(b.disc("Cup", cup, 0.42, 0.12, C.IRON, M.Metal))
		fine(
			b.rod(
				"Candle",
				cup + V(0, 0.05, 0),
				cup + V(0, 0.05 + wear:NextNumber(0.2, 0.7), 0),
				0.2,
				C.WAX,
				M.SmoothPlastic
			)
		)
	end
	return b.model
end

--[[
	A head mounted on a wall shield. `kind`: "elk" (a great spread of
	antlers), "deer", "boar" (tusks) or "wolf" (ears, a snarl). `at` is on
	the wall face, looking into the room.
]]
function Decor.mountedHead(at: CFrame, parent: Instance, o: Options?): Model
	local kind: string = opt(o, "kind", "elk")
	local s: number = opt(o, "scale", 1)
	local b = begin("MountedHead", at, parent)
	local fur: Color3 = if kind == "wolf"
		then Kit.rgb(54, 48, 42)
		elseif kind == "boar" then Kit.rgb(40, 32, 28)
		else Kit.rgb(62, 46, 34)
	b.disc("Shield", V(0, 0, -0.1), 2.2 * s, 0.2, C.WALNUT, M.Wood, ON_WALL)
	fine(b.disc("ShieldRim", V(0, 0, -0.18), 1.9 * s, 0.06, C.OAK, M.Wood, ON_WALL))
	-- Neck out from the shield, the head at its end, pointing down a little.
	local neckEnd = V(0, -0.2 * s, -1.3 * s)
	b.rod("Neck", V(0, 0.1 * s, -0.15), neckEnd, 1.3 * s, fur, M.Fabric)
	local headEnd = neckEnd + V(0, -0.45 * s, -1.2 * s)
	local headD = if kind == "wolf" then 0.95 else 1.05
	b.rod("Head", neckEnd, headEnd, headD * s, fur, M.Fabric)
	fine(b.ball("Brow", neckEnd + V(0, 0.15 * s, -0.2 * s), 1.15 * headD * s, fur, M.Fabric))
	for _, x in { -1, 1 } do
		fine(
			b.ball(
				"Eye",
				neckEnd + V(x * 0.42 * s, 0.2 * s, -0.45 * s),
				0.16 * s,
				C.GLASS_DARK,
				M.Glass
			)
		)
	end
	if kind == "boar" then
		fine(
			b.disc(
				"Snout",
				headEnd + V(0, 0, -0.05),
				0.7 * s,
				0.2 * s,
				Kit.rgb(52, 40, 36),
				M.Fabric,
				CFrame.Angles(math.pi / 2, 0, 0)
			)
		)
		for _, x in { -1, 1 } do
			local root = headEnd + V(x * 0.3 * s, -0.25 * s, 0.35 * s)
			fine(
				b.rod(
					"Tusk",
					root,
					root + V(x * 0.25 * s, 0.35 * s, -0.25 * s),
					0.12 * s,
					C.BONE,
					M.SmoothPlastic
				)
			)
			fine(b.ball("Ear", neckEnd + V(x * 0.55 * s, 0.6 * s, 0), 0.45 * s, fur, M.Fabric))
		end
	elseif kind == "wolf" then
		fine(b.ball("Nose", headEnd + V(0, 0.05, -0.1), 0.26 * s, C.SOOT, M.SmoothPlastic))
		fine(
			b.rod(
				"Jaw",
				neckEnd + V(0, -0.45 * s, -0.4 * s),
				headEnd + V(0, -0.5 * s, 0.1 * s),
				0.3 * s,
				fur,
				M.Fabric
			)
		)
		for _, x in { -1, 1 } do
			b.tri(
				"Ear",
				neckEnd + V(x * 0.2 * s, 0.45 * s, 0),
				neckEnd + V(x * 0.55 * s, 0.4 * s, 0.05 * s),
				neckEnd + V(x * 0.4 * s, 1.0 * s, 0.1 * s),
				0.1 * s,
				fur,
				M.Fabric
			)
			fine(
				b.rod(
					"Fang",
					headEnd + V(x * 0.14 * s, -0.2 * s, 0.25 * s),
					headEnd + V(x * 0.14 * s, -0.42 * s, 0.25 * s),
					0.07 * s,
					C.BONE,
					M.SmoothPlastic
				)
			)
		end
	else
		fine(
			b.ball("Nose", headEnd + V(0, 0, -0.05), 0.5 * s, Kit.rgb(34, 28, 24), M.SmoothPlastic)
		)
		local spread = if kind == "elk" then 1.5 else 0.95
		for _, x in { -1, 1 } do
			fine(b.ball("Ear", neckEnd + V(x * 0.7 * s, 0.35 * s, 0.1 * s), 0.4 * s, fur, M.Fabric))
			antler(
				b,
				neckEnd + V(x * 0.3 * s, 0.5 * s, 0.05 * s),
				V(x, 0, 0.3).Unit,
				spread * s,
				C.BONE
			)
		end
	end
	return b.model
end

--[[
	A rack on a wall with three long guns across its pegs, stocks to the
	left. `at` is on the wall face.
]]
function Decor.gunRack(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("GunRack", at, parent)
	b.box("Board", V(5.4, 3.6, 0.3), V(0, 0, -0.15), C.WALNUT, M.Wood)
	for _, x in { -2.2, 2.2 } do
		for k = 0, 2 do
			fine(
				b.rod(
					"Peg",
					V(x, 1.1 - k * 1.1, -0.3),
					V(x, 1.15 - k * 1.1, -0.75),
					0.16,
					C.OAK,
					M.Wood
				)
			)
		end
	end
	for k = 0, 2 do
		if k == 1 and opt(o, "missing", true) then
			continue -- one is gone from its pegs
		end
		local y = 1.3 - k * 1.1
		fine(b.rod("Barrel", V(-1.0, y, -0.6), V(2.8, y + 0.02, -0.6), 0.16, C.IRON, M.Metal))
		fine(
			b.box(
				"Stock",
				V(1.9, 0.36, 0.24),
				V(-1.8, y - 0.08, -0.6),
				C.WALNUT,
				M.Wood,
				CFrame.Angles(0, 0, math.rad(-6))
			)
		)
		fine(b.box("Action", V(0.8, 0.28, 0.2), V(-0.5, y, -0.6), C.IRON, M.Metal))
		fine(
			b.rod("Guard", V(-0.55, y - 0.2, -0.6), V(-0.2, y - 0.25, -0.6), 0.06, C.IRON, M.Metal)
		)
	end
	return b.model
end

--[[
	A rail of butcher's hooks hanging from the ceiling at `at`, and what is
	still hanging on some of them.
]]
function Decor.meatHooks(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("MeatHooks", at, parent)
	local w: number = opt(o, "width", 7)
	local drop: number = opt(o, "drop", 1.4)
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		fine(b.rod("Hanger", V(x, 0, 0), V(x, -drop, 0), 0.14, C.IRON, M.Metal))
	end
	fine(b.rod("Rail", V(-w / 2, -drop, 0), V(w / 2, -drop, 0), 0.22, C.IRON, M.CorrodedMetal))
	local meat = Kit.rgb(60, 26, 22)
	local fat = Kit.rgb(78, 66, 52)
	local wear = Kit.wear()
	local x = -w / 2 + 0.8
	local k = 0
	while x < w / 2 - 0.6 do
		k += 1
		local top = V(x, -drop - 0.1, 0)
		fine(b.rod("Hook", top, top + V(0, -0.7, 0), 0.08, C.IRON, M.Metal))
		fine(
			b.rod("HookCurl", top + V(0, -0.7, 0), top + V(0, -0.55, -0.25), 0.08, C.IRON, M.Metal)
		)
		if k % 2 == 1 then
			local len = wear:NextNumber(2.2, 3.4)
			local hang = top + V(0, -0.75, 0)
			fine(
				b.rod(
					"Carcass",
					hang,
					hang + V(0.05, -len, 0.1),
					wear:NextNumber(0.9, 1.3),
					meat,
					M.SmoothPlastic
				)
			)
			fine(
				b.rod(
					"Carcass",
					hang + V(0, -len * 0.3, 0),
					hang + V(0.1, -len * 0.75, 0.2),
					0.7,
					fat,
					M.SmoothPlastic
				)
			)
			fine(b.ball("Joint", hang + V(0, -0.15, 0), 0.6, fat, M.SmoothPlastic))
		end
		x += 1.2
	end
	return b.model
end

-- An open bear trap on a floor: two jaws in a ring with their teeth up,
-- the springs either side and a length of chain.
function Decor.bearTrap(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("BearTrap", at, parent)
	local r = 1.0
	local prev: Vector3? = nil
	for k = 0, 14 do
		local a = k * math.pi * 2 / 14
		local p = V(math.cos(a) * r, 0.12, math.sin(a) * r)
		if prev then
			fine(b.rod("Jaw", prev, p, 0.12, C.IRON, M.CorrodedMetal))
			fine(b.rod("Tooth", p, p + V(0, 0.3, 0) - p.Unit * 0.08, 0.07, C.IRON, M.CorrodedMetal))
		end
		prev = p
	end
	fine(b.disc("Pan", V(0, 0.08, 0), 0.8, 0.06, C.IRON, M.CorrodedMetal))
	for _, x in { -1, 1 } do
		fine(
			b.rod("Spring", V(x * 1.1, 0.12, 0), V(x * 2.2, 0.12, 0), 0.3, C.IRON, M.CorrodedMetal)
		)
	end
	local p = V(2.2, 0.06, 0)
	for k = 1, 5 do
		local q = p + V(0.35, 0, (k % 2 == 0) and 0.1 or -0.1)
		fine(b.rod("Chain", p, q, 0.1, C.IRON, M.Metal))
		p = q
	end
	return b.model
end

-- A rack hanging from a ceiling with pots and ladles on hooks.
function Decor.potRack(at: CFrame, parent: Instance, o: Options?): Model
	local b = begin("PotRack", at, parent)
	local w: number = opt(o, "width", 5)
	local drop: number = opt(o, "drop", 2.4)
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		fine(b.rod("Chain", V(x, 0, 0), V(x, -drop, 0), 0.1, C.IRON, M.Metal))
	end
	for _, z in { -0.5, 0.5 } do
		fine(b.rod("Rail", V(-w / 2, -drop, z), V(w / 2, -drop, z), 0.2, C.WALNUT, M.Wood))
	end
	local x = -w / 2 + 0.6
	local k = 0
	while x < w / 2 - 0.4 do
		k += 1
		local z = if k % 2 == 0 then 0.5 else -0.5
		local top = V(x, -drop - 0.1, z)
		fine(b.rod("Hook", top, top + V(0, -0.4, 0), 0.07, C.IRON, M.Metal))
		if k % 3 == 0 then
			fine(b.rod("Ladle", top + V(0, -0.4, 0), top + V(0, -1.8, 0), 0.08, C.IRON, M.Metal))
			fine(b.ball("LadleBowl", top + V(0, -1.9, 0), 0.4, C.IRON, M.Metal))
		else
			local d = if k % 2 == 0 then 1.1 else 0.85
			fine(
				b.rod("PotHandle", top + V(0, -0.4, 0), top + V(0, -0.8, 0), 0.07, C.IRON, M.Metal)
			)
			fine(
				b.disc(
					"Pot",
					top + V(0, -0.8 - d / 2, 0),
					d,
					0.25,
					C.RUST,
					M.CorrodedMetal,
					CFrame.Angles(math.pi / 2, 0, 0)
				)
			)
		end
		x += 0.8
	end
	return b.model
end

return Decor
