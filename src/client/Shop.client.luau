--!strict
--[[
	The shop menu.

	Purely presentation. Clicking Buy asks the server to make the purchase and
	shows whatever it says back — this script never changes a coin count or
	decides whether something is affordable, because a player can edit it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Wait for replication, then require by direct path: Luau's type solver can
-- follow `ReplicatedStorage.Shared.Shop` but not a WaitForChild result, and we
-- want `Shop.Item` below to actually mean something.
expect(expect(ReplicatedStorage, "Shared", "ReplicatedStorage"), "Shop", "ReplicatedStorage/Shared")
local Shop = require(ReplicatedStorage.Shared.Shop)

local Remotes = expect(ReplicatedStorage, "Remotes", "ReplicatedStorage")
local purchaseItem = expect(Remotes, "PurchaseItem", "ReplicatedStorage/Remotes") :: RemoteFunction
local inventoryChanged =
	expect(Remotes, "InventoryChanged", "ReplicatedStorage/Remotes") :: RemoteEvent

local BACKDROP = Color3.fromRGB(24, 26, 33)
local PANEL = Color3.fromRGB(36, 39, 48)
local ACCENT = Color3.fromRGB(255, 201, 61)
local OWNED = Color3.fromRGB(86, 176, 108)
local TEXT = Color3.fromRGB(236, 238, 244)
local MUTED = Color3.fromRGB(150, 156, 170)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local owned: { [string]: boolean } = {}
-- itemId -> the row's Buy button, so we can restyle rows as things are bought.
local buyButtons: { [string]: TextButton } = {}

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Toggle button ------------------------------------------------------------

local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.AnchorPoint = Vector2.new(1, 1)
toggle.Position = UDim2.new(1, -16, 1, -16)
toggle.Size = UDim2.fromOffset(120, 44)
toggle.BackgroundColor3 = ACCENT
toggle.Font = Enum.Font.GothamBold
toggle.Text = "Shop"
toggle.TextSize = 20
toggle.TextColor3 = BACKDROP
toggle.AutoButtonColor = true
toggle.Parent = screenGui
corner(toggle, 10)

-- Panel --------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
-- Offset width with a scale cap so it still fits a phone screen.
panel.Size = UDim2.new(0.9, 0, 0, 380)
panel.SizeConstraint = Enum.SizeConstraint.RelativeXY
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = screenGui
corner(panel, 14)

local sizeCap = Instance.new("UISizeConstraint")
sizeCap.MaxSize = Vector2.new(460, 380)
sizeCap.Parent = panel

local padding = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
	(padding :: any)[side] = UDim.new(0, 16)
end
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Shop"
title.TextSize = 24
title.TextColor3 = TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local status = Instance.new("TextLabel")
status.Name = "Status"
status.LayoutOrder = 100
status.Size = UDim2.new(1, 0, 0, 20)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.Text = ""
status.TextSize = 14
status.TextColor3 = MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Parent = panel

-- Item rows ----------------------------------------------------------------

local function refreshRow(item: Shop.Item)
	local button = buyButtons[item.id]
	if not button then
		return
	end

	if owned[item.id] then
		button.Text = "Owned"
		button.BackgroundColor3 = OWNED
		button.TextColor3 = TEXT
		button.AutoButtonColor = false
	else
		button.Text = tostring(item.price)
		button.BackgroundColor3 = ACCENT
		button.TextColor3 = BACKDROP
		button.AutoButtonColor = true
	end
end

local function buildRow(item: Shop.Item, order: number)
	local row = Instance.new("Frame")
	row.Name = item.id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 62)
	row.BackgroundColor3 = BACKDROP
	row.Parent = panel
	corner(row, 10)

	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, 12)
	rowPadding.PaddingRight = UDim.new(0, 12)
	rowPadding.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -96, 0, 22)
	name.Position = UDim2.fromOffset(0, 10)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.Text = item.name
	name.TextSize = 17
	name.TextColor3 = TEXT
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local description = Instance.new("TextLabel")
	description.Size = UDim2.new(1, -96, 0, 18)
	description.Position = UDim2.fromOffset(0, 32)
	description.BackgroundTransparency = 1
	description.Font = Enum.Font.Gotham
	description.Text = item.description
	description.TextSize = 13
	description.TextColor3 = MUTED
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Parent = row

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, 0, 0.5, 0)
	buy.Size = UDim2.fromOffset(76, 36)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 16
	buy.Parent = row
	corner(buy, 8)

	buyButtons[item.id] = buy
	refreshRow(item)

	buy.Activated:Connect(function()
		if owned[item.id] then
			return
		end

		-- Guard against double-clicks while the round trip is in flight.
		buy.AutoButtonColor = false
		buy.Text = "..."

		-- InvokeServer yields and can throw if the server errors or the player
		-- leaves mid-call, so it goes through pcall. The server returns two
		-- values, which arrive here after pcall's own success boolean.
		local reached, _purchased, message = pcall(function()
			return purchaseItem:InvokeServer(item.id)
		end)

		status.Text = if reached then tostring(message) else "Purchase failed — try again."

		refreshRow(item)
	end)
end

for order, item in Shop.items do
	buildRow(item, order)
end

-- Wiring -------------------------------------------------------------------

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		status.Text = ""
	end
end)

inventoryChanged.OnClientEvent:Connect(function(nextOwned: { [string]: boolean })
	owned = nextOwned or {}
	for _, item in Shop.items do
		refreshRow(item)
	end
end)
