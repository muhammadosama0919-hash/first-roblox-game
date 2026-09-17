--!strict
--[[
	Poses every creature in the world, on the client.

	The server decides which clip a creature is in and writes it to the model's
	`State` attribute, which replicates for free. Each client then evaluates the
	clip locally and writes the result into the Motor6D transforms.

	Doing it this way means the joint rotations never cross the network. Posing
	on the server would replicate fifteen CFrames per creature per frame; this
	replicates one string when the state changes. It is the same split as the
	spinning coins: the server owns what is true, the client owns what it looks
	like.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CreatureAnimation")
local CreatureAnimation = require(ReplicatedStorage.Shared.CreatureAnimation)

local CREATURE_TAG = "Creature"
-- Seconds to cross-fade when the state changes. Long enough to read as a
-- transition, short enough that a lunge still feels sudden.
local BLEND_TIME = 0.18

type Playback = {
	clock: number,
	current: string,
	-- The pose held at the moment the state changed, faded out of over
	-- BLEND_TIME so a switch does not snap.
	fadeFrom: CreatureAnimation.Pose?,
	fadeClock: number,
}

local playback: { [Model]: Playback } = {}

local function clipFor(name: string): CreatureAnimation.Clip
	return CreatureAnimation.clips[name] or CreatureAnimation.clips.feed
end

local function evaluate(state: Playback): CreatureAnimation.Pose
	local clip = clipFor(state.current)
	-- One-shot clips hold their last frame; looping clips wrap.
	local t = if clip.looping
		then (state.clock / clip.length) % 1
		else math.min(state.clock / clip.length, 1)

	local pose = clip.pose(t)

	if state.fadeFrom and state.fadeClock < BLEND_TIME then
		return CreatureAnimation.blend(state.fadeFrom, pose, state.fadeClock / BLEND_TIME)
	end

	return pose
end

local function apply(model: Model, pose: CreatureAnimation.Pose)
	for jointName, angles in pose do
		-- Joints are named after the limb they drive and parented to the limb
		-- above, so a plain descendant search finds them wherever they sit.
		local joint = model:FindFirstChild(jointName, true)
		if joint and joint:IsA("Motor6D") then
			joint.Transform = CFrame.Angles(angles.X, angles.Y, angles.Z)
		end
	end
end

local function track(model: Model)
	if playback[model] then
		return
	end

	local state: Playback = {
		clock = 0,
		current = model:GetAttribute("State") :: string or "feed",
		fadeFrom = nil,
		fadeClock = math.huge,
	}
	playback[model] = state

	model:GetAttributeChangedSignal("State"):Connect(function()
		local next = model:GetAttribute("State")
		if typeof(next) ~= "string" or next == state.current then
			return
		end

		-- Capture the pose we are leaving so the blend has something to come
		-- from, rather than snapping through the rest pose.
		state.fadeFrom = evaluate(state)
		state.fadeClock = 0
		state.current = next
		state.clock = 0
	end)
end

for _, model in CollectionService:GetTagged(CREATURE_TAG) do
	if model:IsA("Model") then
		track(model)
	end
end

CollectionService:GetInstanceAddedSignal(CREATURE_TAG):Connect(function(instance)
	if instance:IsA("Model") then
		track(instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(CREATURE_TAG):Connect(function(instance)
	if instance:IsA("Model") then
		playback[instance :: Model] = nil
	end
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	for model, state in playback do
		-- A creature can be destroyed between frames; drop it rather than
		-- posing a model that is no longer in the world.
		if not model.Parent then
			playback[model] = nil
			continue
		end

		state.clock += deltaTime
		state.fadeClock += deltaTime
		apply(model, evaluate(state))
	end
end)
