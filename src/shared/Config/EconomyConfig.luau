--!strict
-- Gold tunables (GDD 5.2 to 5.6; ECON-01..06). Every value here is [CONFIG].

local EconomyConfig = {
	-- Base income by global round (5.3). Rounds past the table use `baseIncomeLate`.
	baseIncome = { 0, 2, 2, 3, 4 },
	baseIncomeLate = 5,

	-- Interest (5.4): 1 gold per `interestStep` held, capped at `interestCap`.
	interestStep = 10,
	interestCap = 5,

	-- Streak bonus (5.5): list of { minStreak, bonus }, ascending.
	streakBonuses = { { 2, 1 }, { 4, 2 }, { 5, 3 } },

	winBonus = 1,
	rerollCost = 2,
	-- Sell refund = cost * 3^(star - 1) (5.6).
	sellStarMultiplier = 3,
}

return EconomyConfig
