--!strict
--[[
	Server-side game logic.

	Runs in ServerScriptService, so players can never see or edit it. Anything
	that decides "did you really earn this?" belongs here — never on the client.

	What it does:
	  1. Loads each player's saved progress, then gives them a `leaderstats`
	     folder (this is what makes the scoreboard in the top-right appear).
	  2. Spawns floating coins around the baseplate.
	  3. Awards points when a player touches one, then respawns it.
	  4. Saves progress on a timer, on leave, and on server shutdown.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local coinCollected = Remotes:WaitForChild("CoinCollected") :: RemoteEvent
local inventoryChanged = Remotes:WaitForChild("InventoryChanged") :: RemoteEvent
local purchaseItem = Remotes:WaitForChild("PurchaseItem") :: RemoteFunction

local COIN_TAG = "Coin"

local coinFolder = Instance.new("Folder")
coinFolder.Name = "Coins"
coinFolder.Parent = Workspace

--[[
	Load the player's save, then set up their scoreboard entry. Roblox looks for
	a folder named exactly "leaderstats" inside the Player, and shows each value
	inside it.
]]
local function onPlayerAdded(player: Player)
	-- Load before building leaderstats, so the scoreboard shows the real total
	-- immediately instead of flashing 0 and then jumping.
	PlayerData.load(player)

	-- Loading yields on a network call, so the player may have left while we
	-- waited. Building UI on a departed player leaks the profile.
	if not player:IsDescendantOf(Players) then
		PlayerData.release(player)
		return
	end

	local profile = PlayerData.get(player)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = if profile then profile.coins else 0
	coins.Parent = leaderstats

	leaderstats.Parent = player

	-- Re-apply bonuses on every respawn, not just this one — a new character
	-- starts with default WalkSpeed and JumpPower.
	player.CharacterAdded:Connect(function()
		ShopService.applyEffects(player)
	end)

	if player.Character then
		ShopService.applyEffects(player)
	end

	inventoryChanged:FireClient(player, ShopService.inventoryOf(player))
end

-- The profile is the source of truth; the IntValue is only what the scoreboard
-- reads. Anything that changes coins updates the profile, then calls this.
local function syncLeaderstats(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		coins.Value = profile.coins
	end
end

local function awardCoins(player: Player, amount: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end

	profile.coins += amount
	syncLeaderstats(player)
end

-- A random point in a disc around the origin. Taking the square root of the
-- random number spreads coins evenly instead of bunching them in the middle.
local function randomCoinPosition(): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * Config.coinSpawnRadius

	return Vector3.new(math.cos(angle) * distance, Config.coinHeight, math.sin(angle) * distance)
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

		-- Lucky Charm and friends are applied here, on the server. The client
		-- is only told the result so it can show the right number.
		local amount = math.floor(Config.coinValue * ShopService.coinMultiplier(player))
		awardCoins(player, amount)
		coinCollected:FireClient(player, amount)

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

--[[
	The one entry point a client has into the shop. It returns (ok, message)
	rather than throwing, so a failed purchase is a message on screen instead
	of an error in the client's console.
]]
purchaseItem.OnServerInvoke = function(player: Player, itemId: unknown)
	local ok, message = ShopService.purchase(player, itemId)

	if ok then
		syncLeaderstats(player)
		ShopService.applyEffects(player)
		inventoryChanged:FireClient(player, ShopService.inventoryOf(player))
	end

	return ok, message
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	PlayerData.release(player)
end)

-- In Studio the local player can join before this script runs, so catch anyone
-- who is already here. task.spawn because onPlayerAdded yields.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

for _ = 1, Config.coinCount do
	spawnCoin()
end

-- Autosave, so a server crash costs a minute of progress rather than all of it.
task.spawn(function()
	while true do
		task.wait(Config.autosaveSeconds)

		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player)
		end
	end
end)

--[[
	PlayerRemoving does not reliably finish when the whole server is shutting
	down, so save everyone one last time here. Roblox allows roughly 30 seconds
	before killing the server, and saves run concurrently to stay well inside
	that.
]]
game:BindToClose(function()
	local players = Players:GetPlayers()
	local pending = #players

	if pending == 0 then
		return
	end

	for _, player in players do
		task.spawn(function()
			PlayerData.save(player)
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end
end)
