--!strict
-- Match-level tunables (GDD 2.4, 4.x, 6.x, 7.5; LOBBY-01, LOBBY-02, ARCH-01, ARCH-07, BRD-01, LVL-01..05, AUG-01). Every value here is [CONFIG].

local GameConfig = {
	-- LOBBY-01: 4 while building, 8 at launch. No system may assume 8 players.
	lobbySize = 4,
	maxLobbySize = 8,
	playerHealth = 100,

	-- Intent rate limit per player (ARCH-01) and snapshot throttle (ARCH-07).
	maxIntentsPerSecond = 20,
	maxSnapshotsPerSecond = 10,

	-- Board and bench (BRD-01).
	boardColumns = 7,
	boardRows = 4,
	benchSlots = 9,

	-- Levels and XP (6.1, 6.2).
	maxLevel = 10,
	passiveXp = 2,
	passiveXpFromRound = 2,
	buyXpCost = 4,
	buyXpAmount = 4,
	-- xpToNextLevel[level] = XP needed to go from `level` to `level + 1`.
	xpToNextLevel = { 2, 2, 6, 10, 20, 36, 48, 80, 84 },

	-- Phase timers in seconds (4.3, 4.8).
	prepSeconds = 25,
	prepSecondsRound1 = 20,
	augmentPrepBonusSeconds = 15,
	combatMaxSeconds = 30,
	resolveSeconds = 4,
	carouselIntroSeconds = 3,
	carouselPickSeconds = 4,

	-- Lobby start (D-17): start when full, or after the wait with at least minPlayersToStart.
	lobbyWaitSeconds = 10,
	minPlayersToStart = 1,
	matchStartSeconds = 3,

	-- Round layouts (4.2). Index = round number within the stage. `drops` = components on a PvE win.
	stage1Layout = {
		{ type = "pve", drops = 0 }, -- 1-1
		{ type = "pve", drops = 1 }, -- 1-2
		{ type = "carousel", drops = 0 }, -- 1-3
		{ type = "pve", drops = 1 }, -- 1-4
	},
	laterStageLayout = {
		{ type = "pvp", drops = 0 }, -- x-1
		{ type = "pvp", drops = 0 }, -- x-2
		{ type = "pve", drops = 2 }, -- x-3
		{ type = "carousel", drops = 0 }, -- x-4
		{ type = "pvp", drops = 0 }, -- x-5
		{ type = "pvp", drops = 0 }, -- x-6
		{ type = "pvp", drops = 0 }, -- x-7
	},

	-- Player damage (4.5). stageBase[stage]; stages beyond the table use the last entry.
	stageBaseDamage = { [2] = 2, [3] = 4, [4] = 6, [5] = 8, [6] = 10 },
	damageDoublingStartsAfterRound = 40,

	-- Rounds where augment offers occur (AUG-01), keyed by round id.
	augmentRounds = { ["2-1"] = 1, ["3-2"] = 2, ["4-2"] = 3 },

	-- Augment rarity weights per offer (10.3); each row sums to 100. Index = offer number.
	augmentRarityWeights = {
		{ Bronze = 70, Silver = 28, Gold = 2 },
		{ Bronze = 25, Silver = 60, Gold = 15 },
		{ Bronze = 5, Silver = 45, Gold = 50 },
	},
	augmentChoices = 3,

	-- Monster formulas (4.6): count = min(1 + floor(g/2), cap).
	monsterCountCap = 8,
	monsterHealthBase = 250,
	monsterHealthPerRound = 60,
	monsterAdBase = 12,
	monsterAdPerRound = 3,
	monsterAttackSpeed = 0.6,

	-- Shared pool copies per unit for an 8-player lobby, scaled by LOBBY-02. Index = cost.
	poolCopiesAt8 = { 22, 20, 17, 10, 9 },
}

return GameConfig
