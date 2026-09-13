--!strict
--[[
	Client-side presentation.

	Runs in StarterPlayerScripts, once per player, on their own machine. This is
	the right place for anything cosmetic: animation, UI, sound. It is the WRONG
	place for anything that decides score — players can edit their own client.

	What it does:
	  1. Spins the coins locally (free — costs the server nothing).
	  2. Pops up "+1 Coin" when the server says this player picked one up.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- WaitForChild, not direct indexing: this script can start running before
-- ReplicatedStorage has finished replicating to the client.
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local coinCollected = Remotes:WaitForChild("CoinCollected") :: RemoteEvent

local COIN_TAG = "Coin"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build the pickup popup ----------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CoinHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local popup = Instance.new("TextLabel")
popup.Name = "Popup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.3)
popup.Size = UDim2.fromOffset(260, 60)
popup.BackgroundTransparency = 1
popup.Font = Enum.Font.GothamBold
popup.TextSize = 36
popup.TextColor3 = Color3.fromRGB(255, 201, 61)
popup.TextStrokeTransparency = 0.4
popup.TextTransparency = 1
popup.Text = ""
popup.Parent = screenGui

coinCollected.OnClientEvent:Connect(function(amount: number)
	popup.Text = string.format("+%d Coin%s", amount, if amount == 1 then "" else "s")
	popup.TextTransparency = 0
	popup.TextStrokeTransparency = 0.4

	local fade = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, fade, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end)

-- Spin the coins ------------------------------------------------------------

-- One shared angle means every coin spins in sync, and we only do the maths
-- once per frame rather than once per coin.
local spin = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
	spin = (spin + Config.coinSpinSpeed * deltaTime) % (math.pi * 2)

	for _, coin in CollectionService:GetTagged(COIN_TAG) do
		if coin:IsA("BasePart") then
			coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, spin, 0)
		end
	end
end)
