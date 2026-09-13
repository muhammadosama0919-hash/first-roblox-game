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
	-- How often to write progress to the DataStore while a player is online,
	-- so a server crash costs at most this much progress.
	autosaveSeconds: number,
	-- Humanoid stats before any shop bonuses. Roblox's own defaults.
	baseWalkSpeed: number,
	baseJumpPower: number,
	-- Hold Shift to run. Multiplies whatever the walk speed currently is, so
	-- it stacks with Swift Boots rather than overriding them.
	sprintMultiplier: number,
	-- Camera field of view, and how far it widens while sprinting. The widening
	-- is most of why running feels fast.
	baseFieldOfView: number,
	sprintFieldOfView: number,

	-- World generation.
	worldSeed: number,
	worldSize: number,
	terrainCell: number,
	terrainDepth: number,
	hillHeight: number,
	clearingRadius: number,
	clearingFalloff: number,
	treeCount: number,
	treeClearRadius: number,

	-- Pond. The basin is carved out of the terrain and then filled with water
	-- up to waterLevel, which sits below the rim so there is a visible bank.
	pondCenterX: number,
	pondCenterZ: number,
	pondRadius: number,
	pondDepth: number,
	pondBankWidth: number,
	waterLevel: number,

	-- Scattered ground detail: rocks, bushes, reeds.
	rockCount: number,
	bushCount: number,
	reedCount: number,
}

local Config: Config = {
	coinValue = 1,
	coinCount = 22,
	coinRespawnSeconds = 5,
	coinSpawnRadius = 145,
	coinHeight = 3,
	coinSpinSpeed = 2,
	autosaveSeconds = 60,
	baseWalkSpeed = 16,
	baseJumpPower = 50,
	sprintMultiplier = 1.65,
	baseFieldOfView = 70,
	sprintFieldOfView = 82,

	worldSeed = 20260913,
	worldSize = 420,
	terrainCell = 6,
	terrainDepth = 24,
	hillHeight = 17,
	clearingRadius = 72,
	clearingFalloff = 70,
	treeCount = 90,
	treeClearRadius = 34,

	pondCenterX = 86,
	pondCenterZ = 62,
	pondRadius = 46,
	pondDepth = 11,
	pondBankWidth = 26,
	waterLevel = -1.5,

	rockCount = 70,
	bushCount = 110,
	reedCount = 90,
}

return table.freeze(Config)
