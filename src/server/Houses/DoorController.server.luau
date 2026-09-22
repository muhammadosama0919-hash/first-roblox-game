--!strict
--[[
	Opens and closes every door in a house.

	A door is a Model tagged "Door" with an invisible part named "Hinge" on
	its hinge line and a signed "OpenAngle" attribute in degrees (HouseKit
	builds them that way). This script gives each one a prompt on its knob and
	swings the whole model about the Hinge's own Y axis when the prompt fires.
	Nothing about any particular door is written here, so a door added by hand
	in Studio works too, as long as it follows the same three rules.

	The same file is embedded in every exported house model, and also lives in
	ServerScriptService for houses built at runtime. Inside a house model it
	looks after that house's doors; anywhere else it looks after every door in
	the Workspace. A door already wired by one copy is skipped by the other,
	so having both never swings a door twice.

	The leaf stops colliding while it moves. A door that sweeps through a
	player with collision on is how players get flung across a room.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SWING = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local REACH = 8

local parent = script.Parent
local root: Instance = if parent and parent:IsA("Model") then parent else Workspace

local function wire(door: Instance)
	if not door:IsA("Model") or door:GetAttribute("DoorWired") or not door:IsDescendantOf(root) then
		return
	end

	local hinge = door:FindFirstChild("Hinge")
	if not hinge or not hinge:IsA("BasePart") then
		warn(`[DoorController] {door:GetFullName()} has no Hinge part; it will not open`)
		return
	end
	door:SetAttribute("DoorWired", true)

	local rawOpen = door:GetAttribute("OpenAngle")
	local openAngle: number = if type(rawOpen) == "number" then rawOpen else 90
	local rawAngle = door:GetAttribute("Angle")
	local angle: number = if type(rawAngle) == "number" then rawAngle else 0

	-- The Hinge stays where the door is closed. Every other part is recorded
	-- relative to the hinge turned to wherever the door stands now, and put
	-- back relative to the hinge turned to the new angle on every step.
	local hingePart: BasePart = hinge
	local now = hingePart.CFrame * CFrame.Angles(0, math.rad(angle), 0)
	local offsets: { [BasePart]: CFrame } = {}
	local leaves: { BasePart } = {}
	local handle: BasePart? = nil
	for _, child in door:GetDescendants() do
		if child:IsA("BasePart") and child ~= hinge then
			offsets[child] = now:ToObjectSpace(child.CFrame)
			if child.Name == "Leaf" then
				table.insert(leaves, child)
			elseif child.Name == "Knob" and handle == nil then
				handle = child
			end
		end
	end
	local anchor: BasePart? = handle or leaves[1]
	if not anchor then
		warn(`[DoorController] {door:GetFullName()} has no Leaf or Knob; it will not open`)
		return
	end

	local value = Instance.new("NumberValue")
	value.Name = "Swing"
	value.Value = angle
	value.Parent = hinge
	value.Changed:Connect(function(a: number)
		-- The hinge is read on every step rather than remembered: if the house
		-- is moved after this ran (Groundwork standing it on the ground, or
		-- any PivotTo), a remembered frame would swing the door back to where
		-- the house used to be.
		local frame = hingePart.CFrame * CFrame.Angles(0, math.rad(a), 0)
		for part, offset in offsets do
			part.CFrame = frame * offset
		end
	end)

	local isOpen = math.abs(angle) > 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if isOpen then "Close" else "Open"
	prompt.ObjectText = (door:GetAttribute("Label") :: string?) or "Door"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	local busy = false
	prompt.Triggered:Connect(function()
		if busy then
			return
		end
		busy = true
		isOpen = not isOpen
		local target = if isOpen then openAngle else 0
		prompt.ActionText = if isOpen then "Close" else "Open"

		for _, leaf in leaves do
			leaf.CanCollide = false
		end
		local tween = TweenService:Create(value, SWING, { Value = target })
		tween.Completed:Connect(function()
			for _, leaf in leaves do
				leaf.CanCollide = true
			end
			door:SetAttribute("Angle", target)
			busy = false
		end)
		tween:Play()
	end)
end

for _, door in CollectionService:GetTagged("Door") do
	wire(door)
end
CollectionService:GetInstanceAddedSignal("Door"):Connect(wire)
