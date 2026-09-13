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
local RunService = game:GetService("RunService")

export type Profile = {
	coins: number,
	-- Shop item ids this player has bought, as a set.
	owned: { [string]: boolean },
}

local DEFAULT_PROFILE: Profile = {
	coins = 0,
	owned = {},
}

--[[
	Data stores belong to the whole experience, not to one place — every place
	in a game, and every live server, reads the same database. Studio is no
	exception: once this place is published and Studio API access is on, a
	playtest reads and writes the SAME saves your real players use. A bad save
	routine tested in Studio can therefore corrupt live data.

	Branching the name gives Studio its own sandbox. This is a convention held
	up by this one line, not a guarantee — the stronger version is a separately
	published test experience, which gets different data stores outright. Doing
	both means two things have to fail before real saves are at risk.

	Bump the version suffix if you ever change Profile's shape in a way old
	saves can't be reconciled into; old data is then left untouched under the
	old name rather than corrupted.
]]
local STORE_NAME = if RunService:IsStudio() then "PlayerData_v1_studio" else "PlayerData_v1"

local store = DataStoreService:GetDataStore(STORE_NAME)
local KEY_PREFIX = "Player_"

local MAX_ATTEMPTS = 3
local PROBE_KEY = "__availability_probe__"

--[[
	Whether this server can reach the DataStore at all.

	Decided once at startup rather than per player. Data stores belong to a
	published experience, so in a local unpublished .rbxl every request fails
	the same way — retrying three times on each join would stall every player
	for seconds and bury the console in identical warnings.
]]
local storesAvailable = true

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

		warn(
			string.format(
				"[PlayerData] %s failed (%d/%d): %s",
				label,
				attempt,
				MAX_ATTEMPTS,
				tostring(result)
			)
		)

		-- By far the most common cause in Studio, and the error text is not
		-- obvious about the fix.
		if
			string.find(tostring(result), "403") or string.find(tostring(result), "API Services")
		then
			warn(
				"[PlayerData] In Studio, tick Game Settings -> Security -> Enable Studio Access to API Services."
			)
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
	-- Fresh tables, never shared with DEFAULT_PROFILE — two players must not
	-- end up mutating the same `owned` table.
	local profile: Profile = { coins = DEFAULT_PROFILE.coins, owned = {} }

	if typeof(stored) ~= "table" then
		return profile
	end

	if typeof(stored.coins) == "number" then
		profile.coins = stored.coins
	end

	-- Saves written before the shop existed have no `owned` field and simply
	-- keep the empty default.
	if typeof(stored.owned) == "table" then
		for id, isOwned in stored.owned do
			if typeof(id) == "string" and isOwned == true then
				profile.owned[id] = true
			end
		end
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

	-- Already known to be offline: hand back a fresh profile immediately and
	-- skip the doomed round trip. The game plays normally, it just won't save.
	if not storesAvailable then
		profiles[userId] = reconcile(nil)
		isLoaded[userId] = false
		return
	end

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

	-- Nothing to say here; the reason was already reported once at startup.
	if not storesAvailable then
		return false
	end

	-- THE important guard. If the load failed we do not know what this player
	-- already had, so writing now would replace a real save with a fresh zero.
	-- Losing one session of progress is bad; erasing everything is worse.
	if not isLoaded[userId] then
		warn(
			string.format(
				"[PlayerData] refusing to save %s — their data never loaded.",
				player.Name
			)
		)
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

--[[
	Ask the DataStore one question at server start so the rest of the session
	knows whether persistence is possible. Yields briefly, once, before any
	player can join.
]]
local function probeStores()
	local ok, err = pcall(function()
		return store:GetAsync(PROBE_KEY)
	end)

	if ok then
		return
	end

	storesAvailable = false
	local reason = tostring(err)

	warn("[PlayerData] Data stores unavailable — progress will NOT be saved this session.")
	warn("[PlayerData] Everything else works; coins and purchases just reset when you stop.")

	if
		string.find(reason, "403")
		or string.find(reason, "API Services")
		or string.find(reason, "publish")
	then
		warn(
			"[PlayerData] To enable saving: publish the place once (File > Publish to Roblox As...),"
		)
		warn(
			'[PlayerData] then tick File > Experience Settings > Security > "Enable Studio Access to API Services".'
		)
	else
		warn("[PlayerData] Reason: " .. reason)
	end
end

probeStores()

return PlayerData
