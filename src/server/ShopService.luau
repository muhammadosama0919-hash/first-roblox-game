--!strict
--[[
	Buying things, and the effects of having bought them.

	Every function here treats its arguments as hostile. A RemoteFunction can be
	invoked by an exploiting client with any values it likes — a number where a
	string belongs, an item id that does not exist, a purchase for something
	already owned. The checks in purchase() are the only thing standing between
	that and a free shop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Shop = require(ReplicatedStorage.Shared.Shop)
local PlayerData = require(script.Parent.PlayerData)

local ShopService = {}

--[[
	Attempt a purchase. Returns (succeeded, message-to-show-the-player).

	itemId is typed `unknown` on purpose: it arrives straight off the wire.
]]
function ShopService.purchase(player: Player, itemId: unknown): (boolean, string)
	if typeof(itemId) ~= "string" then
		return false, "Invalid request."
	end

	-- Look the item up in the shared list rather than trusting anything the
	-- client said about it. The price used below is always ours.
	local item = Shop.getItem(itemId)
	if not item then
		return false, "No such item."
	end

	local profile = PlayerData.get(player)
	if not profile then
		return false, "Your data is still loading — try again in a moment."
	end

	if profile.owned[item.id] then
		return false, "You already own that."
	end

	if profile.coins < item.price then
		return false, string.format("You need %d more coins.", item.price - profile.coins)
	end

	profile.coins -= item.price
	profile.owned[item.id] = true

	return true, string.format("Bought %s!", item.name)
end

--[[
	Total coin multiplier from everything this player owns.
]]
function ShopService.coinMultiplier(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 1
	end

	local multiplier = 1
	for _, item in Shop.items do
		if profile.owned[item.id] and item.coinMultiplier then
			multiplier *= item.coinMultiplier
		end
	end

	return multiplier
end

--[[
	Push owned movement bonuses onto the player's current character.

	Called on spawn and after a purchase. Always recomputes from the base values
	rather than adding to whatever the humanoid currently has, so calling it
	twice cannot stack a bonus twice.
]]
-- Players currently holding Shift. Cleared on leave by Main.
local sprinting: { [number]: boolean } = {}

function ShopService.setSprinting(player: Player, isSprinting: boolean)
	sprinting[player.UserId] = isSprinting or nil
	ShopService.applyEffects(player)
end

function ShopService.clearSprinting(player: Player)
	sprinting[player.UserId] = nil
end

function ShopService.applyEffects(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local walkSpeed = Config.baseWalkSpeed
	local jumpPower = Config.baseJumpPower

	for _, item in Shop.items do
		if profile.owned[item.id] then
			walkSpeed += item.walkSpeedBonus or 0
			jumpPower += item.jumpPowerBonus or 0
		end
	end

	-- Sprint multiplies the total, so Swift Boots make running faster too
	-- rather than being cancelled out by it.
	if sprinting[player.UserId] then
		walkSpeed *= Config.sprintMultiplier
	end

	humanoid.WalkSpeed = walkSpeed
	-- New characters default to the JumpHeight model; switch to JumpPower so
	-- the bonus above means what it says.
	humanoid.UseJumpPower = true
	humanoid.JumpPower = jumpPower
end

--[[
	What the client needs to draw the shop: which ids this player owns.
]]
function ShopService.inventoryOf(player: Player): { [string]: boolean }
	local profile = PlayerData.get(player)
	if not profile then
		return {}
	end

	local owned: { [string]: boolean } = {}
	for id, isOwned in profile.owned do
		if isOwned then
			owned[id] = true
		end
	end

	return owned
end

return ShopService
