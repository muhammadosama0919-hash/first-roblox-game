--!strict
--[[
	The creature's four animations, written as maths rather than keyframes.

	Roblox's normal animation route — the Animation Editor or an imported FBX —
	produces an asset that must be uploaded to Roblox before it can be played,
	because every AnimationClipProvider method takes an asset id. Driving
	Motor6D.Transform directly needs no upload at all, which is the only route
	that works when the game is delivered as a file.

	Each clip is a pure function of time returning joint name -> rotation. No
	state, no instances: the same inputs always give the same pose, so a clip
	can be evaluated on any machine at any framerate and match.

	Angles are radians, applied as CFrame.Angles(x, y, z) on top of the joint's
	rest pose. Positive X pitches a limb forward.
]]

export type Pose = { [string]: Vector3 }
export type Clip = {
	name: string,
	-- Seconds for one cycle. Attack does not loop; the rest do.
	length: number,
	looping: boolean,
	pose: (t: number) -> Pose,
}

local TAU = math.pi * 2

-- Ease that starts fast and settles, for strikes and snaps.
local function snap(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Smooth 0->1->0, for anything that swells and returns.
local function pulse(t: number): number
	return math.sin(math.clamp(t, 0, 1) * math.pi)
end

local CreatureAnimation = {}

--[[
	A four-beat gait shared by walk and run.

	`stride` scales how far limbs travel, `lean` how far the body tips forward.
	Arms swing opposite the leg on the same side, which is what stops a walk
	reading as a shamble.
]]
local function gait(phase: number, stride: number, lean: number, bob: number): Pose
	local left = math.sin(phase * TAU)
	local right = math.sin(phase * TAU + math.pi)

	-- Knees bend on the recovery half of the stride only. Taking the absolute
	-- value doubles the frequency, which is what gives a knee its two bends
	-- per cycle instead of one.
	local kneeL = math.abs(math.sin(phase * TAU * 0.5 + math.pi * 0.25))
	local kneeR = math.abs(math.sin(phase * TAU * 0.5 + math.pi * 0.75))

	return {
		HumanoidRootPart = Vector3.new(0, 0, 0),
		Chest = Vector3.new(-lean + math.sin(phase * TAU * 2) * bob * 0.5, 0, 0),
		Neck = Vector3.new(lean * 0.7, math.sin(phase * TAU) * 0.06, 0),
		Head = Vector3.new(math.sin(phase * TAU * 2) * bob, 0, 0),

		ThighL = Vector3.new(left * stride, 0, 0),
		ShinL = Vector3.new(-kneeL * stride * 1.1, 0, 0),
		FootL = Vector3.new(kneeL * stride * 0.5, 0, 0),
		ThighR = Vector3.new(right * stride, 0, 0),
		ShinR = Vector3.new(-kneeR * stride * 1.1, 0, 0),
		FootR = Vector3.new(kneeR * stride * 0.5, 0, 0),

		-- Counter-swing: the arm opposite each leg.
		ArmUpperL = Vector3.new(right * stride * 0.75, 0, 0),
		ArmLowerL = Vector3.new(-math.abs(right) * stride * 0.4, 0, 0),
		ArmUpperR = Vector3.new(left * stride * 0.75, 0, 0),
		ArmLowerR = Vector3.new(-math.abs(left) * stride * 0.4, 0, 0),
	}
end

--[[
	WALK — deliberate, weight on each foot, head sweeping as if searching.
]]
local walk: Clip = {
	name = "walk",
	length = 1.25,
	looping = true,
	pose = function(t: number): Pose
		local phase = t % 1
		local p = gait(phase, 0.55, 0.30, 0.08)

		-- A slow head sweep on a different period from the stride, so the two
		-- never lock into an obvious repeating beat.
		p.Neck = Vector3.new(0.25, math.sin(t * TAU * 0.31) * 0.35, 0)
		p.Jaw = Vector3.new(0.06 + math.sin(t * TAU * 0.5) * 0.05, 0, 0)
		return p
	end,
}

--[[
	RUN — lower, faster, arms reaching. Nearly on all fours at full speed.
]]
local run: Clip = {
	name = "run",
	length = 0.52,
	looping = true,
	pose = function(t: number): Pose
		local phase = t % 1
		local p = gait(phase, 1.05, 0.72, 0.16)

		-- Arms drive rather than swing, and reach further forward than the legs.
		local left = math.sin(phase * TAU)
		local right = math.sin(phase * TAU + math.pi)
		p.ArmUpperL = Vector3.new(right * 0.7 + 0.5, 0, 0.1)
		p.ArmUpperR = Vector3.new(left * 0.7 + 0.5, 0, -0.1)
		p.ArmLowerL = Vector3.new(-0.55 - math.abs(right) * 0.35, 0, 0)
		p.ArmLowerR = Vector3.new(-0.55 - math.abs(left) * 0.35, 0, 0)

		p.Neck = Vector3.new(0.62, 0, 0)
		p.Head = Vector3.new(-0.25, 0, 0)
		p.Jaw = Vector3.new(0.3 + math.abs(math.sin(phase * TAU)) * 0.12, 0, 0)
		return p
	end,
}

--[[
	FEED — crouched over something on the ground, tearing at it.

	Two rhythms on purpose: a slow shoulder-and-spine rock, and a faster head
	wrench with the jaw snapping at the bottom of each pull. One rhythm alone
	reads as a machine.
]]
local feed: Clip = {
	name = "feed",
	length = 2.6,
	looping = true,
	pose = function(t: number): Pose
		local slow = math.sin(t * TAU)
		local wrench = math.sin(t * TAU * 3)
		local tear = math.max(0, math.sin(t * TAU * 3 - 0.6))

		return {
			-- Hunched right down, hips low.
			HumanoidRootPart = Vector3.new(0, 0, 0),
			Chest = Vector3.new(-0.95 + slow * 0.10, 0, 0),
			Neck = Vector3.new(1.05 + wrench * 0.22, slow * 0.08, 0),
			Head = Vector3.new(-0.35 - tear * 0.45, 0, wrench * 0.12),
			Jaw = Vector3.new(0.12 + tear * 0.55, 0, 0),

			-- Arms planted on the ground, pinning whatever it is down.
			ArmUpperL = Vector3.new(1.15, 0, 0.22),
			ArmLowerL = Vector3.new(-0.55 + tear * 0.18, 0, 0),
			ClawL = Vector3.new(0.4, 0, 0),
			ArmUpperR = Vector3.new(1.15, 0, -0.22),
			ArmLowerR = Vector3.new(-0.55 + tear * 0.18, 0, 0),
			ClawR = Vector3.new(0.4, 0, 0),

			-- Squatting, knees splayed out around the meal.
			ThighL = Vector3.new(1.25, 0, 0.18),
			ShinL = Vector3.new(-1.65, 0, 0),
			FootL = Vector3.new(0.65, 0, 0),
			ThighR = Vector3.new(1.25, 0, -0.18),
			ShinR = Vector3.new(-1.65, 0, 0),
			FootR = Vector3.new(0.65, 0, 0),
		}
	end,
}

--[[
	ATTACK — one shot, not a loop: coil, lunge, recover.

	The wind-up is the longest part and moves backwards. A strike that begins
	instantly has nothing to read, and a player cannot dodge what they cannot
	see coming.
]]
local attack: Clip = {
	name = "attack",
	length = 1.0,
	looping = false,
	pose = function(t: number): Pose
		local coil = math.clamp(t / 0.35, 0, 1)
		local strike = math.clamp((t - 0.35) / 0.2, 0, 1)
		local recover = math.clamp((t - 0.55) / 0.45, 0, 1)

		-- Rear back, then whip forward, then settle.
		local reach = -coil * 0.45 + snap(strike) * 2.1 - recover * 1.25
		local body = -coil * 0.45 + snap(strike) * 0.95 - recover * 0.5

		return {
			HumanoidRootPart = Vector3.new(0, 0, 0),
			Chest = Vector3.new(body - 0.3, 0, 0),
			Neck = Vector3.new(0.35 + snap(strike) * 0.3 - recover * 0.25, 0, 0),
			Head = Vector3.new(-coil * 0.3 + snap(strike) * 0.2, 0, 0),
			-- Jaw gapes through the wind-up and snaps shut on contact.
			Jaw = Vector3.new(coil * 0.85 - snap(strike) * 0.8 + pulse(recover) * 0.1, 0, 0),

			-- Claws lead, one slightly ahead of the other so it reads as a
			-- swipe rather than a shove.
			ArmUpperL = Vector3.new(reach, 0, 0.3 - coil * 0.25),
			ArmLowerL = Vector3.new(-0.7 + snap(strike) * 0.55, 0, 0),
			ClawL = Vector3.new(-0.3 + snap(strike) * 0.6, 0, 0),
			ArmUpperR = Vector3.new(reach * 0.88, 0, -0.3 + coil * 0.25),
			ArmLowerR = Vector3.new(-0.7 + snap(strike) * 0.4, 0, 0),
			ClawR = Vector3.new(-0.3 + snap(strike) * 0.45, 0, 0),

			-- Legs brace, then drive.
			ThighL = Vector3.new(0.35 + coil * 0.35 - snap(strike) * 0.3, 0, 0),
			ShinL = Vector3.new(-0.75 - coil * 0.3 + snap(strike) * 0.25, 0, 0),
			FootL = Vector3.new(0.4, 0, 0),
			ThighR = Vector3.new(0.35 + coil * 0.35 - snap(strike) * 0.3, 0, 0),
			ShinR = Vector3.new(-0.75 - coil * 0.3 + snap(strike) * 0.25, 0, 0),
			FootR = Vector3.new(0.4, 0, 0),
		}
	end,
}

CreatureAnimation.clips = {
	walk = walk,
	run = run,
	feed = feed,
	attack = attack,
}

-- Fraction through the attack at which the claws are actually out front. The
-- server uses this to decide when a swing can land, so the damage matches what
-- the player sees rather than firing on the wind-up.
CreatureAnimation.attackContact = 0.55

--[[
	Blend two poses. Used to cross-fade between clips so a state change does not
	snap, and to ease into the first frame of a one-shot.
]]
function CreatureAnimation.blend(from: Pose, into: Pose, alpha: number): Pose
	local out: Pose = {}
	local a = math.clamp(alpha, 0, 1)

	for joint, value in from do
		out[joint] = value:Lerp(into[joint] or Vector3.zero, a)
	end
	-- Joints only the target names still need to arrive from rest.
	for joint, value in into do
		if out[joint] == nil then
			out[joint] = Vector3.zero:Lerp(value, a)
		end
	end

	return out
end

return CreatureAnimation
