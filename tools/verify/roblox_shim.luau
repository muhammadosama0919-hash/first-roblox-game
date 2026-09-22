--!nocheck
--[[
	Just enough of the Roblox API to execute a geometry module outside Roblox.

	The point is NOT to emulate Roblox. It is to run the real Manor.luau — the
	same file that ships — and capture every part it creates, so the geometry can
	be rendered and measured here. Anything the module does not touch is absent
	on purpose: an unimplemented call fails loudly rather than quietly returning
	nil and making the capture silently wrong.
]]

local M = {}

----------------------------------------------------------------------
-- Vector3
----------------------------------------------------------------------

local Vector3 = {}

local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3)
end

local methods = {}

function methods:Dot(o)
	return self.X * o.X + self.Y * o.Y + self.Z * o.Z
end

function methods:Cross(o)
	return v3(
		self.Y * o.Z - self.Z * o.Y,
		self.Z * o.X - self.X * o.Z,
		self.X * o.Y - self.Y * o.X
	)
end

Vector3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			error("Vector3.Unit on a zero vector", 2)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return methods[key]
end

Vector3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3.__tostring = function(a)
	return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z)
end

local V3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

----------------------------------------------------------------------
-- CFrame, stored as three basis columns plus a position.
--
-- Columns are (RightVector, UpVector, BackVector). Roblox's LookVector is
-- -BackVector, which is the one convention worth getting exactly right here,
-- because the module under test builds window frames with CFrame.new(pos, lookAt).
----------------------------------------------------------------------

local CFrame = {}

local function cf(p, r, u, b)
	return setmetatable({ p = p, r = r, u = u, b = b }, CFrame)
end

local function rotate(self, v)
	return v3(
		self.r.X * v.X + self.u.X * v.Y + self.b.X * v.Z,
		self.r.Y * v.X + self.u.Y * v.Y + self.b.Y * v.Z,
		self.r.Z * v.X + self.u.Z * v.Y + self.b.Z * v.Z
	)
end

local cframeMethods = {}

function cframeMethods:Inverse()
	local r = v3(self.r.X, self.u.X, self.b.X)
	local u = v3(self.r.Y, self.u.Y, self.b.Y)
	local b = v3(self.r.Z, self.u.Z, self.b.Z)
	local inv = cf(V3.zero, r, u, b)
	return cf(-rotate(inv, self.p), r, u, b)
end

function cframeMethods:ToWorldSpace(o)
	return self * o
end

-- Raw fields p/r/u/b resolve before this runs, so only the derived names below
-- ever reach it.
CFrame.__index = function(self, key)
	if key == "Position" then
		return rawget(self, "p")
	elseif key == "LookVector" then
		return -rawget(self, "b")
	elseif key == "RightVector" then
		return rawget(self, "r")
	elseif key == "UpVector" then
		return rawget(self, "u")
	elseif key == "X" then
		return rawget(self, "p").X
	elseif key == "Y" then
		return rawget(self, "p").Y
	elseif key == "Z" then
		return rawget(self, "p").Z
	end
	return cframeMethods[key]
end

CFrame.__mul = function(a, b)
	if getmetatable(b) == Vector3 then
		return rotate(a, b) + a.p
	end
	return cf(rotate(a, b.p) + a.p, rotate(a, b.r), rotate(a, b.u), rotate(a, b.b))
end

CFrame.__add = function(a, v)
	return cf(a.p + v, a.r, a.u, a.b)
end

CFrame.__tostring = function(self)
	return tostring(self.p)
end

local CF
CF = {
	new = function(a, b, c)
		if a == nil then
			return cf(V3.zero, V3.xAxis, V3.yAxis, V3.zAxis)
		end
		if type(a) == "number" then
			return cf(v3(a, b or 0, c or 0), V3.xAxis, V3.yAxis, V3.zAxis)
		end
		if b == nil then
			return cf(a, V3.xAxis, V3.yAxis, V3.zAxis)
		end

		-- CFrame.new(position, lookAt). Roblox takes the back vector from
		-- (position - lookAt) and derives the rest against world up.
		local back = (a - b).Unit
		local right = V3.yAxis:Cross(back)
		if right.Magnitude < 1e-9 then
			error("CFrame.new(pos, lookAt) is degenerate looking straight up or down", 2)
		end
		right = right.Unit
		return cf(a, right, back:Cross(right), back)
	end,

	fromMatrix = function(p, vx, vy, vz)
		return cf(p, vx, vy, if vz == nil then vx:Cross(vy).Unit else vz)
	end,

	Angles = function(rx, ry, rz)
		local cx, sx = math.cos(rx), math.sin(rx)
		local cy, sy = math.cos(ry), math.sin(ry)
		local cz, sz = math.cos(rz), math.sin(rz)

		-- Rx * Ry * Rz, which is the order Roblox composes them in.
		return cf(
			V3.zero,
			v3(cy * cz, cx * sz + sx * sy * cz, sx * sz - cx * sy * cz),
			v3(-cy * sz, cx * cz - sx * sy * sz, sx * cz + cx * sy * sz),
			v3(sy, -sx * cy, cx * cy)
		)
	end,
}
CF.fromEulerAnglesXYZ = CF.Angles
CF.identity = cf(V3.zero, V3.xAxis, V3.yAxis, V3.zAxis)

----------------------------------------------------------------------
-- Color3
----------------------------------------------------------------------

local Color3MT = { __index = {} }

local C3 = {
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3MT)
	end,
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3MT)
	end,
}

----------------------------------------------------------------------
-- Enum. Every member is a self-describing stub, so a typo in the module under
-- test shows up as a wrong name in the capture rather than as a nil.
----------------------------------------------------------------------

local Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, itemName)
				return { EnumType = enumName, Name = itemName }
			end,
		})
	end,
})

----------------------------------------------------------------------
-- Instance
----------------------------------------------------------------------

local captured = {}

local InstanceMT = {}

InstanceMT.__index = function(self, key)
	local props = rawget(self, "_props")
	if props[key] ~= nil then
		return props[key]
	end
	return InstanceMT[key]
end

InstanceMT.__newindex = function(self, key, value)
	rawget(self, "_props")[key] = value
	if key == "Parent" and value ~= nil then
		table.insert(rawget(value, "_children"), self)
	end
end

function InstanceMT:GetChildren()
	return rawget(self, "_children")
end

function InstanceMT:GetDescendants()
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function InstanceMT:IsA(className)
	local c = rawget(self, "_props").ClassName
	if c == className then
		return true
	end
	if className == "BasePart" then
		return c == "Part" or c == "WedgePart"
	end
	if className == "PVInstance" then
		return c == "Part" or c == "WedgePart" or c == "Model"
	end
	return false
end

function InstanceMT:FindFirstChild(name)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	return nil
end

function InstanceMT:Destroy()
	rawget(self, "_props").Parent = nil
end

function InstanceMT:SetAttribute(k, v)
	rawget(self, "_attrs")[k] = v
end

function InstanceMT:GetAttribute(k)
	return rawget(self, "_attrs")[k]
end

local ALLOWED = {
	Part = true,
	WedgePart = true,
	Model = true,
	Folder = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
}

local Instance = {
	new = function(className)
		if not ALLOWED[className] then
			error("shim: Instance.new(" .. tostring(className) .. ") is not implemented", 2)
		end

		local self = setmetatable({
			_props = { ClassName = className, Name = className },
			_children = {},
			_attrs = {},
			_tags = {},
		}, InstanceMT)

		table.insert(captured, self)
		return self
	end,
}

----------------------------------------------------------------------
-- Random. Roblox's generator is not reproduced, only its interface: the
-- structural geometry does not depend on it, but the decorative scatter does,
-- so ivy and rubble land differently here than on a real server. That is a
-- known and deliberate difference, not a bug in the module under test.
----------------------------------------------------------------------

local RandomMT = {}
RandomMT.__index = RandomMT

function RandomMT:_next()
	-- Lehmer / MINSTD: small, deterministic, entirely adequate for scatter.
	self.state = (self.state * 16807) % 2147483647
	return self.state / 2147483647
end

function RandomMT:NextNumber(a, b)
	if a == nil then
		return self:_next()
	end
	return a + (b - a) * self:_next()
end

function RandomMT:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local RandomClass = {
	new = function(seed)
		local state = (seed or 0) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		return setmetatable({ state = state }, RandomMT)
	end,
}

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------

local tagged = {}

local services = {
	CollectionService = {
		AddTag = function(_, instance, tag)
			table.insert(tagged, { instance = instance, tag = tag })
			table.insert(rawget(instance, "_tags"), tag)
		end,
	},
}

local game = {
	GetService = function(_, name)
		local svc = services[name]
		if not svc then
			error("shim: GetService(" .. name .. ") is not implemented", 2)
		end
		return svc
	end,
}

M.Vector3 = V3
M.Vector3MT = Vector3
M.CFrame = CF
M.Color3 = C3
M.Enum = Enum
M.Instance = Instance
M.Random = RandomClass
M.game = game
M.captured = captured
M.tagged = tagged

return M
