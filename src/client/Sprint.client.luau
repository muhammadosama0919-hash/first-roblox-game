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

expect(
	expect(ReplicatedStorage, "Shared", "ReplicatedStorage"),
	"Config",
	"ReplicatedStorage/Shared"
)
local Config = require(ReplicatedStorage.Shared.Config)

--[[
	WaitForChild with a deadline and a real explanation.

	A bare WaitForChild never gives up, so a missing instance does not error —
	the script just stops, silently, forever. That is harder to diagnose than a
	crash, because the Output window stays empty. This turns it into a named
	failure that says which instance and where to add it.
]]
local function expect(parent: Instance, name: string, where: string): Instance
	local found = parent:WaitForChild(name, 10)
	if not found then
		error(
			string.format(
				"[%s] Missing %s.%s after 10s. Declare it under %s in the project file.",
				where,
				parent.Name,
				name,
				where
			),
			0
		)
	end
	return found
end

local Remotes = expect(ReplicatedStorage, "Remotes", "ReplicatedStorage")
local setSprinting = expect(Remotes, "SetSprinting", "ReplicatedStorage/Remotes") :: RemoteEvent

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
