--!strict
--[[
	Spawns one creature near the cabin and cycles it through every animation,
	so all four can be seen without any gameplay wired up yet.

	This is a showcase, not the real thing — when the creature gets AI, this
	script is what gets deleted.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CreatureAnimation = require(ReplicatedStorage.Shared.CreatureAnimation)
local CreatureFactory = require(script.Parent.CreatureFactory)
local World = require(script.Parent.World)

local SPOT = Vector3.new(26, 0, -18)
local ORDER = { "feed", "walk", "run", "attack" }
-- Long enough to watch a few cycles of each.
local HOLD = 5

local ok, err = pcall(function()
	local folder = Instance.new("Folder")
	folder.Name = "Creatures"
	folder.Parent = Workspace

	local ground = World.heightAt(SPOT.X, SPOT.Z)
	local creature = CreatureFactory.spawn(Vector3.new(SPOT.X, ground + 7, SPOT.Z), folder)
	CollectionService:AddTag(creature, "Creature")

	-- A sign, so it is obvious which clip is playing.
	local sign = Instance.new("BillboardGui")
	sign.Name = "ClipLabel"
	sign.Size = UDim2.fromOffset(220, 40)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	sign.AlwaysOnTop = true
	sign.Parent = creature:FindFirstChild("HumanoidRootPart")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 24
	label.TextColor3 = Color3.fromRGB(255, 120, 110)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = sign

	task.spawn(function()
		local index = 0
		while creature.Parent do
			index += 1
			local clipName = ORDER[(index - 1) % #ORDER + 1]
			local clip = CreatureAnimation.clips[clipName]

			creature:SetAttribute("State", clipName)
			label.Text = string.upper(clipName)

			if clip.looping then
				task.wait(HOLD)
			else
				-- Play a one-shot a few times rather than holding its last
				-- frame, which would just look like a freeze.
				for _ = 1, 3 do
					task.wait(clip.length + 0.35)
					creature:SetAttribute("State", "idle")
					task.wait(0.2)
					creature:SetAttribute("State", clipName)
				end
			end
		end
	end)
end)

if not ok then
	warn("[CreatureDemo] failed: " .. tostring(err))
end
