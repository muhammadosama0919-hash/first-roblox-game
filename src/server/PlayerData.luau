--!strict
--[[
	Saving and loading player progress with DataStoreService.

	Roblox gives every experience a key-value database that survives server
	restarts. It is also the single easiest place in Roblox to lose player data,
	so this module is deliberately paranoid:

	  * Every request is wrapped in pcall. DataStore calls are network calls and
	    they DO fail — treating a failure as "no data" is how saves get wiped.
	  * A profile is only saved if it was successfully loaded first. See the
	    guard in save(); it is the most important line in this file.
	  * Loaded data is reconciled against a default template, so adding a new
	    field later does not break players whose save predates it.
]]

local DataStoreService = game:GetService("DataStoreService")

export type Profile = {
	coins: number,
}

local DEFAULT_PROFILE: Profile = {
	coins = 0,
}

-- Bump the version suffix if you ever change the shape of a Profile in a way
-- old saves can't be reconciled into. Old data is left untouched under the old
-- name rather than being corrupted.
local store = DataStoreService:GetDataStore("PlayerData_v1")
local KEY_PREFIX = "Player_"

local MAX_ATTEMPTS = 3

local profiles: { [number]: Profile } = {}
-- True only once we have actually heard back from the DataStore for this
-- player — including "you have no save yet", which is a valid answer.
local isLoaded: { [number]: boolean } = {}

local PlayerData = {}

local function keyFor(player: Player): string
	return KEY_PREFIX .. tostring(player.UserId)
end

--[[
	Run a DataStore call, retrying with exponential backoff. Returns
	(success, result) — never throws.
]]
local function withRetry(label: string, operation: () -> any): (boolean, any)
	local backoff = 1

	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		warn(string.format("[PlayerData] %s failed (%d/%d): %s", label, attempt, MAX_ATTEMPTS, tostring(result)))

		-- By far the most common cause in Studio, and the error text is not
		-- obvious about the fix.
		if string.find(tostring(result), "403") or string.find(tostring(result), "API Services") then
			warn("[PlayerData] In Studio, tick Game Settings -> Security -> Enable Studio Access to API Services.")
		end

		if attempt < MAX_ATTEMPTS then
			task.wait(backoff)
			backoff *= 2
		end
	end

	return false, nil
end

-- Copy known fields off whatever came back, ignoring anything unexpected. A
-- save written by an older version of the game is missing newer fields, and
-- picks up their defaults here.
local function reconcile(stored: any): Profile
	local profile: Profile = { coins = DEFAULT_PROFILE.coins }

	if typeof(stored) == "table" and typeof(stored.coins) == "number" then
		profile.coins = stored.coins
	end

	return profile
end

--[[
	Fetch this player's save. Yields. Always leaves a usable profile in memory,
	even on failure — but marks an unrecoverable one as unsaveable so a later
	save() cannot clobber real data with defaults.
]]
function PlayerData.load(player: Player)
	local userId = player.UserId

	local ok, stored = withRetry("load " .. player.Name, function()
		return store:GetAsync(keyFor(player))
	end)

	if not ok then
		profiles[userId] = reconcile(nil)
		isLoaded[userId] = false
		warn(string.format("[PlayerData] %s is playing on an unsaved session.", player.Name))
		return
	end

	profiles[userId] = reconcile(stored)
	isLoaded[userId] = true
end

function PlayerData.get(player: Player): Profile?
	return profiles[player.UserId]
end

--[[
	Write this player's profile back. Yields. Returns whether it stuck.
]]
function PlayerData.save(player: Player): boolean
	local userId = player.UserId
	local profile = profiles[userId]

	if not profile then
		return false
	end

	-- THE important guard. If the load failed we do not know what this player
	-- already had, so writing now would replace a real save with a fresh zero.
	-- Losing one session of progress is bad; erasing everything is worse.
	if not isLoaded[userId] then
		warn(string.format("[PlayerData] refusing to save %s — their data never loaded.", player.Name))
		return false
	end

	local ok = withRetry("save " .. player.Name, function()
		-- UpdateAsync rather than SetAsync: it serialises against a concurrent
		-- write from another server, which happens when a player rejoins fast
		-- enough that their old session is still shutting down.
		store:UpdateAsync(keyFor(player), function()
			return profile
		end)
		return nil
	end)

	return ok
end

--[[
	Save and forget a player. Safe to call more than once.
]]
function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player.UserId] = nil
	isLoaded[player.UserId] = nil
end

return PlayerData
