--!strict
--[[
	Server-side game logic.

	Runs in ServerScriptService, so players can never see or edit it. Anything
	that decides "did you really earn this?" belongs here — never on the client.

	What it does:
	  1. Gives every player a `leaderstats` folder (this is what makes the
	     scoreboard in the top-right corner appear).
	  2. Spawns floating coins around the baseplate.
	  3. Awards points when a player touches one, then respawns it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local coinCollected = Remotes:WaitForChild("CoinCollected") :: RemoteEvent

local COIN_TAG = "Coin"

local coinFolder = Instance.new("Folder")
coinFolder.Name = "Coins"
coinFolder.Parent = Workspace

--[[
	Set up the player's scoreboard entry. Roblox looks for a folder named
	exactly "leaderstats" inside the Player, and shows each value inside it.
]]
local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats

	leaderstats.Parent = player
end

local function awardCoins(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("Coins")
	if not coins or not coins:IsA("IntValue") then
		return
	end

	coins.Value += amount
end

-- A random point in a disc around the origin. Taking the square root of the
-- random number spreads coins evenly instead of bunching them in the middle.
local function randomCoinPosition(): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * Config.coinSpawnRadius

	return Vector3.new(
		math.cos(angle) * distance,
		Config.coinHeight,
		math.sin(angle) * distance
	)
end

local function spawnCoin()
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 3, 3)
	coin.Color = Color3.fromRGB(255, 201, 61)
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CFrame = CFrame.new(randomCoinPosition())

	-- Touched can fire many times per contact, so guard against double-awards.
	local collected = false

	coin.Touched:Connect(function(hit: BasePart)
		if collected then
			return
		end

		local character = hit.Parent
		if not character or not character:FindFirstChildOfClass("Humanoid") then
			return
		end

		local player = Players:GetPlayerFromCharacter(character :: Model)
		if not player then
			return
		end

		collected = true
		coin.CanTouch = false
		coin.Transparency = 1

		awardCoins(player, Config.coinValue)
		-- Tell just this player's client so it can show a pickup popup.
		coinCollected:FireClient(player, Config.coinValue)

		task.delay(Config.coinRespawnSeconds, function()
			coin.CFrame = CFrame.new(randomCoinPosition())
			coin.Transparency = 0
			coin.CanTouch = true
			collected = false
		end)
	end)

	-- Tagging lets the client find every coin without hardcoding paths.
	CollectionService:AddTag(coin, COIN_TAG)
	coin.Parent = coinFolder
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- In Studio the local player can join before this script runs, so catch anyone
-- who is already here.
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

for _ = 1, Config.coinCount do
	spawnCoin()
end
