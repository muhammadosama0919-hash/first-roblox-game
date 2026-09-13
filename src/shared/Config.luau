--!strict
--[[
	Tunable values for the game.

	This module lives in ReplicatedStorage, which means both the server and the
	client can read it. Keeping numbers here instead of scattered through the
	code means you tweak gameplay in one place.
]]

export type Config = {
	-- How many coins award per pickup.
	coinValue: number,
	-- How many coins exist in the world at once.
	coinCount: number,
	-- Seconds before a collected coin comes back.
	coinRespawnSeconds: number,
	-- Coins spawn within this many studs of the origin.
	coinSpawnRadius: number,
	-- Height above the baseplate that coins float at.
	coinHeight: number,
	-- Spin speed, in radians per second (client-side visual only).
	coinSpinSpeed: number,
}

local Config: Config = {
	coinValue = 1,
	coinCount = 12,
	coinRespawnSeconds = 5,
	coinSpawnRadius = 60,
	coinHeight = 3,
	coinSpinSpeed = 2,
}

return table.freeze(Config)
