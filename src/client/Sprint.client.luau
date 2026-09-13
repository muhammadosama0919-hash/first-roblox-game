--!strict
--[[
	Hold Shift to run.

	The key is watched here but the speed change happens on the server, so shop
	bonuses and sprint are combined in exactly one place. What this script does
	own is the *feel*: the camera widens slightly while running, which is most
	of why running reads as fast rather than just as a bigger number.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local setSprinting = Remotes:WaitForChild("SetSprinting") :: RemoteEvent

local SPRINT_ACTION = "Sprint"

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local isSprinting = false

local function setSprint(active: boolean)
	if active == isSprinting then
		return
	end

	isSprinting = active
	setSprinting:FireServer(active)
end

--[[
	ContextActionService rather than UserInputService: it binds both Shift keys
	and gives mobile and gamepad a button for free, instead of leaving them with
	no way to run at all.
]]
ContextActionService:BindAction(SPRINT_ACTION, function(_actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		setSprint(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprint(false)
	end

	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

ContextActionService:SetTitle(SPRINT_ACTION, "Run")

-- Ease the field of view toward its target rather than snapping. The lerp is
-- framerate-corrected so it feels the same at 30fps and 144fps.
RunService.RenderStepped:Connect(function(deltaTime: number)
	if not camera then
		camera = Workspace.CurrentCamera
		return
	end

	local target = if isSprinting then Config.sprintFieldOfView else Config.baseFieldOfView
	local alpha = 1 - math.exp(-8 * deltaTime)

	camera.FieldOfView += (target - camera.FieldOfView) * alpha
end)

-- Dying while holding Shift would otherwise leave the server thinking we are
-- still sprinting after we respawn.
local function onCharacterAdded()
	setSprint(false)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded()
end
