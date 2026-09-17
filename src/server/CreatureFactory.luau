--!strict
--[[
	Builds a creature from the rig spec.

	Every limb is a Part joined to its parent by a Motor6D. Motor6D is the joint
	Roblox's own characters use: it holds a C0 and C1 offset, and a Transform
	that animation writes to. Posing the creature means writing rotations into
	those Transforms — the parts never move on their own, so a limb cannot drift
	out of its socket however hard the animation pushes it.

	Only HumanoidRootPart is unanchored and collidable. The limbs are massless
	and pass through everything, so a fifteen-part creature costs the physics
	engine about as much as a single block.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureRig = require(ReplicatedStorage.Shared.CreatureRig)

local CreatureFactory = {}

local function newLimb(limb: CreatureRig.Limb): BasePart
	local part = Instance.new("Part")
	part.Name = limb.name
	part.Size = limb.size
	part.Color = limb.color
	part.Material = Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = limb.transparency or 0

	if limb.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	end

	-- Limbs are along for the ride: no collision, no mass, no self-interference.
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true

	return part
end

--[[
	Assemble one creature at `position`. Returns the model.

	The Humanoid gives us walking, gravity and a death state for free. Its
	RigType is Custom because this is not an R6 or R15 body and Roblox should
	not try to apply its own animations to it.
]]
function CreatureFactory.spawn(position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Creature"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = CreatureRig.rootSize
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(position)
	root.Parent = model

	local built: { [string]: BasePart } = { HumanoidRootPart = root }

	for _, limb in CreatureRig.limbs do
		local parentPart = built[limb.parent]
		if not parentPart then
			warn(
				string.format(
					"[CreatureFactory] %s has no parent %s — skipped",
					limb.name,
					limb.parent
				)
			)
			continue
		end

		local part = newLimb(limb)
		-- Position it roughly before jointing. Motor6D takes over immediately,
		-- but starting near the right place avoids a visible snap on the first
		-- frame.
		part.CFrame = parentPart.CFrame * CFrame.new(limb.jointOnParent)
		part.Parent = model

		local rest = limb.restAngles or Vector3.zero

		local joint = Instance.new("Motor6D")
		joint.Name = limb.name
		joint.Part0 = parentPart
		joint.Part1 = part
		-- C0 is where the joint sits on the parent, C1 where it sits on the
		-- child. The rest rotation goes into C0 so animation can work from
		-- zero and still land on the intended stance.
		joint.C0 = CFrame.new(limb.jointOnParent) * CFrame.Angles(rest.X, rest.Y, rest.Z)
		joint.C1 = CFrame.new(limb.jointOnSelf)
		joint.Parent = parentPart

		built[limb.name] = part
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = true
	-- Nothing here should try to climb, sit or use Roblox's own state machine
	-- animations — the rig is not a Roblox character and would be posed twice.
	humanoid.Parent = model

	for _, state in
		{
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.PlatformStanding,
			Enum.HumanoidStateType.Ragdoll,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end

	--[[
		Stand it on the ground.

		A Humanoid holds its root part `HipHeight` above the floor, plus half the
		root's own height. This rig's feet hang 6.5 studs below the root, so with
		the default HipHeight of 0 the creature spawns buried to its chest.

		Measured from the assembled rig rather than hardcoded, so changing the
		leg proportions in CreatureRig cannot silently sink it again.
	]]
	local boxCFrame, boxSize = model:GetBoundingBox()
	local lowestPoint = boxCFrame.Position.Y - boxSize.Y / 2
	humanoid.HipHeight = (root.Position.Y - lowestPoint) - root.Size.Y / 2

	model.PrimaryPart = root
	-- The animator reads this to know which clip to play. An attribute rather
	-- than a Value object because attributes replicate to clients for free.
	model:SetAttribute("State", "feed")
	model.Parent = parent

	return model
end

return CreatureFactory
