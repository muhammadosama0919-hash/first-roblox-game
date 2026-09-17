--!strict
--[[
	The skeleton of the creature, as data.

	A hunched, long-armed predator: roughly twice a player's height, with arms
	that reach near the ground, digitigrade back legs and an oversized jaw. The
	silhouette does the work — proportion and stance read as "not human" from
	far further away than surface detail ever does.

	Each joint names its parent, the size of the limb hanging off it, and where
	that limb attaches. Motor6D joints are built from this at runtime, so the
	rig is animated by rotating joints rather than by moving parts around.

	Every offset is in studs, measured from the parent part's centre.
]]

export type Limb = {
	name: string,
	parent: string,
	-- Size of this limb's part.
	size: Vector3,
	-- Where the joint sits on the PARENT, and on this limb. A joint rotates
	-- about the parent attachment, so it should sit at the limb's socket —
	-- a shoulder at the top of the upper arm, not at its middle.
	jointOnParent: Vector3,
	jointOnSelf: Vector3,
	-- Baked-in rotation, for limbs that hang at an angle when at rest.
	restAngles: Vector3?,
	color: Color3,
	shape: string?,
	transparency: number?,
}

local HIDE = Color3.fromRGB(96, 84, 78)
local HIDE_DARK = Color3.fromRGB(64, 56, 52)
local MAW = Color3.fromRGB(138, 74, 70)
local CLAW = Color3.fromRGB(196, 190, 176)

local CreatureRig = {}

-- The part everything else hangs from. Not in the limb list because it has no
-- parent joint; the Humanoid drives it directly.
CreatureRig.rootSize = Vector3.new(3.4, 2.6, 2.2)

--[[
	Ordered parent-before-child, so the builder can attach each limb to a parent
	that already exists without sorting.
]]
local LIMBS: { Limb } = {
	-- Spine. The chest sits forward of the hips, which is what produces the
	-- hunch without needing an animation to hold it there.
	{
		name = "Chest",
		parent = "HumanoidRootPart",
		size = Vector3.new(3.8, 2.8, 2.6),
		jointOnParent = Vector3.new(0, 1.3, 0),
		jointOnSelf = Vector3.new(0, -1.4, 0),
		restAngles = Vector3.new(-0.42, 0, 0),
		color = HIDE,
	},
	{
		name = "Neck",
		parent = "Chest",
		size = Vector3.new(1.5, 1.6, 1.5),
		jointOnParent = Vector3.new(0, 1.4, -0.7),
		jointOnSelf = Vector3.new(0, -0.8, 0),
		restAngles = Vector3.new(0.55, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "Head",
		parent = "Neck",
		size = Vector3.new(2.0, 1.7, 2.9),
		jointOnParent = Vector3.new(0, 0.8, 0),
		jointOnSelf = Vector3.new(0, -0.6, 0.5),
		color = HIDE,
	},
	{
		name = "Jaw",
		parent = "Head",
		size = Vector3.new(1.7, 0.7, 2.4),
		jointOnParent = Vector3.new(0, -0.7, 0.4),
		jointOnSelf = Vector3.new(0, 0.2, -1.0),
		color = MAW,
	},

	-- Arms. Long enough that the hands sit near the ground when it crouches,
	-- which is what sells the feeding pose.
	{
		name = "ArmUpperL",
		parent = "Chest",
		size = Vector3.new(1.1, 3.4, 1.1),
		jointOnParent = Vector3.new(-2.1, 0.9, 0),
		jointOnSelf = Vector3.new(0, 1.5, 0),
		restAngles = Vector3.new(0.25, 0, 0.18),
		color = HIDE,
	},
	{
		name = "ArmLowerL",
		parent = "ArmUpperL",
		size = Vector3.new(0.95, 3.2, 0.95),
		jointOnParent = Vector3.new(0, -1.6, 0),
		jointOnSelf = Vector3.new(0, 1.5, 0),
		restAngles = Vector3.new(0.4, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "ClawL",
		parent = "ArmLowerL",
		size = Vector3.new(0.9, 1.4, 1.6),
		jointOnParent = Vector3.new(0, -1.5, 0),
		jointOnSelf = Vector3.new(0, 0.6, 0),
		color = CLAW,
	},
	{
		name = "ArmUpperR",
		parent = "Chest",
		size = Vector3.new(1.1, 3.4, 1.1),
		jointOnParent = Vector3.new(2.1, 0.9, 0),
		jointOnSelf = Vector3.new(0, 1.5, 0),
		restAngles = Vector3.new(0.25, 0, -0.18),
		color = HIDE,
	},
	{
		name = "ArmLowerR",
		parent = "ArmUpperR",
		size = Vector3.new(0.95, 3.2, 0.95),
		jointOnParent = Vector3.new(0, -1.6, 0),
		jointOnSelf = Vector3.new(0, 1.5, 0),
		restAngles = Vector3.new(0.4, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "ClawR",
		parent = "ArmLowerR",
		size = Vector3.new(0.9, 1.4, 1.6),
		jointOnParent = Vector3.new(0, -1.5, 0),
		jointOnSelf = Vector3.new(0, 0.6, 0),
		color = CLAW,
	},

	-- Legs. Digitigrade: thigh forward, shin back, foot forward again. That
	-- double bend is the whole reason it does not walk like a person.
	{
		name = "ThighL",
		parent = "HumanoidRootPart",
		size = Vector3.new(1.4, 2.8, 1.4),
		jointOnParent = Vector3.new(-1.1, -1.2, 0),
		jointOnSelf = Vector3.new(0, 1.2, 0),
		restAngles = Vector3.new(0.5, 0, 0),
		color = HIDE,
	},
	{
		name = "ShinL",
		parent = "ThighL",
		size = Vector3.new(1.15, 3.0, 1.15),
		jointOnParent = Vector3.new(0, -1.3, 0),
		jointOnSelf = Vector3.new(0, 1.4, 0),
		restAngles = Vector3.new(-1.0, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "FootL",
		parent = "ShinL",
		size = Vector3.new(1.2, 0.7, 2.4),
		jointOnParent = Vector3.new(0, -1.4, 0),
		jointOnSelf = Vector3.new(0, 0.3, -0.6),
		restAngles = Vector3.new(0.5, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "ThighR",
		parent = "HumanoidRootPart",
		size = Vector3.new(1.4, 2.8, 1.4),
		jointOnParent = Vector3.new(1.1, -1.2, 0),
		jointOnSelf = Vector3.new(0, 1.2, 0),
		restAngles = Vector3.new(0.5, 0, 0),
		color = HIDE,
	},
	{
		name = "ShinR",
		parent = "ThighR",
		size = Vector3.new(1.15, 3.0, 1.15),
		jointOnParent = Vector3.new(0, -1.3, 0),
		jointOnSelf = Vector3.new(0, 1.4, 0),
		restAngles = Vector3.new(-1.0, 0, 0),
		color = HIDE_DARK,
	},
	{
		name = "FootR",
		parent = "ShinR",
		size = Vector3.new(1.2, 0.7, 2.4),
		jointOnParent = Vector3.new(0, -1.4, 0),
		jointOnSelf = Vector3.new(0, 0.3, -0.6),
		restAngles = Vector3.new(0.5, 0, 0),
		color = HIDE_DARK,
	},
}

CreatureRig.limbs = LIMBS

--[[
	Look up a limb by name. Used by the animator to check a joint exists before
	posing it, so a renamed limb is a no-op rather than an error every frame.
]]
function CreatureRig.find(name: string): Limb?
	for _, limb in CreatureRig.limbs do
		if limb.name == name then
			return limb
		end
	end

	return nil
end

return CreatureRig
