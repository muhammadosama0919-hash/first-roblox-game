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
local World = require(script.Parent.World)

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
local coinCollected = expect(Remotes, "CoinCollected", "ReplicatedStorage/Remotes") :: RemoteEvent
local inventoryChanged =
	expect(Remotes, "InventoryChanged", "ReplicatedStorage/Remotes") :: RemoteEvent
local purchaseItem = expect(Remotes, "PurchaseItem", "ReplicatedStorage/Remotes") :: RemoteFunction
local setSprinting = expect(Remotes, "SetSprinting", "ReplicatedStorage/Remotes") :: RemoteEvent

local COIN_TAG = "Coin"

--[[
	Build terrain and scenery first: coins are placed relative to the ground, so
	the ground has to exist and its shape has to be known.

	Wrapped, because scenery is the least important thing in this script and was
	briefly the only thing that mattered — a missing Terrain instance threw, and
	took leaderstats, coins, saving and the shop down with it. A world that
	fails to generate should cost you the world, not the game.
]]
local housePosition = Vector3.new(0, 0, -Config.clearingRadius * 0.55)

local worldOk, worldErr = pcall(function()
	housePosition = World.build()
end)

if not worldOk then
	warn("[Main] World generation failed: " .. tostring(worldErr))
	warn("[Main] Everything else still runs. Check the Output window for the error above.")
end

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

--[[
	A random point in a disc around the origin, floating just above the ground.

	Taking the square root of the random number spreads coins evenly instead of
	bunching them in the middle. Height comes from the same noise function the
	terrain was built from, so a coin on a hillside floats at the same height
	above the slope as one on flat ground.

	Points landing inside the cabin footprint are retried rather than nudged —
	nudging would pile coins against its walls.
]]
local function randomCoinPosition(): Vector3
	for _ = 1, 30 do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * Config.coinSpawnRadius

		local x = math.cos(angle) * distance
		local z = math.sin(angle) * distance

		local insideCabin = math.abs(x - housePosition.X) < 18
			and math.abs(z - housePosition.Z) < 16
		if not insideCabin then
			return Vector3.new(x, World.heightAt(x, z) + Config.coinHeight, z)
		end
	end

	-- Every attempt hit the cabin, which should not happen with these numbers.
	-- Fall back to somewhere valid rather than looping forever.
	return Vector3.new(0, World.heightAt(0, 0) + Config.coinHeight, Config.coinSpawnRadius * 0.8)
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

--[[
	The client tells us when Shift goes down and up. Sprint state lives on the
	server so it composes with shop bonuses in one place — the client cannot
	pick its own speed, only say which of two states it is in.
]]
setSprinting.OnServerEvent:Connect(function(player: Player, isSprinting: unknown)
	ShopService.setSprinting(player, isSprinting == true)
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	ShopService.clearSprinting(player)
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
