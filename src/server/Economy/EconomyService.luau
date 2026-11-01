--!strict
-- Gold rules (GDD 5). ECON-01: gold changes ONLY through add/spend below.

local Shared = game:GetService("ReplicatedStorage").Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

export type Breakdown = {
	base: number,
	interest: number,
	streak: number,
	win: number,
	extras: { { label: string, amount: number } }, -- filled by OnIncomeCalc modifiers (ECON-06)
	total: number,
}

export type Modifier = (breakdown: Breakdown) -> ()

local EconomyService = {}

-- Adds gold. Amount must be a non-negative integer (ECON-01, ECON-05).
function EconomyService.add(state: PlayerState.State, amount: number, reason: string): PlayerState.Result
	if amount < 0 or amount ~= math.floor(amount) then
		return { ok = false, reason = "InvalidAmount" }
	end
	state.gold += amount
	return { ok = true }
end

-- Spends gold; rejects (changing nothing) if the player cannot afford it (ECON-05).
function EconomyService.spend(state: PlayerState.State, amount: number, reason: string): PlayerState.Result
	if amount < 0 or amount ~= math.floor(amount) then
		return { ok = false, reason = "InvalidAmount" }
	end
	if state.gold < amount then
		return { ok = false, reason = "NotEnoughGold" }
	end
	state.gold -= amount
	return { ok = true }
end

-- Streak bonus from the 5.5 table for a streak length.
function EconomyService.streakBonus(length: number): number
	local bonus = 0
	for _, entry in EconomyConfig.streakBonuses do
		if length >= entry[1] then
			bonus = entry[2]
		end
	end
	return bonus
end

-- Computes itemized income for a global round (5.2). Interest uses gold held now (ECON-03).
-- `modifiers` are OnIncomeCalc hook callbacks that may mutate the breakdown (ECON-06).
function EconomyService.calcIncome(state: PlayerState.State, round: number, modifiers: { Modifier }?): Breakdown
	local step = PlayerState.cfg(state, "interestStep", EconomyConfig.interestStep)
	local cap = PlayerState.cfg(state, "interestCap", EconomyConfig.interestCap)
	local streak = if state.streak.kind == "none" then 0 else EconomyService.streakBonus(state.streak.length)

	local breakdown: Breakdown = {
		base = EconomyConfig.baseIncome[round] or EconomyConfig.baseIncomeLate,
		interest = math.min(math.floor(state.gold / step), cap),
		streak = streak,
		win = if state.wonLastPvp then PlayerState.cfg(state, "winBonus", EconomyConfig.winBonus)
			elseif state.lostLastPvp then PlayerState.cfg(state, "lossBonus", 0) -- Winner's Purse
			else 0,
		extras = {},
		total = 0,
	}
	for _, modify in modifiers or {} do
		modify(breakdown)
	end
	local total = breakdown.base + breakdown.interest + breakdown.streak + breakdown.win
	for _, extra in breakdown.extras do
		total += extra.amount
	end
	breakdown.total = total
	return breakdown
end

-- Pays income at the start of Prep, before the shop refreshes (ECON-02). Returns the breakdown.
function EconomyService.payIncome(state: PlayerState.State, round: number, modifiers: { Modifier }?): Breakdown
	local breakdown = EconomyService.calcIncome(state, round, modifiers)
	EconomyService.add(state, breakdown.total, "Income")
	return breakdown
end

-- Records a finished round. Only PvP wins/losses change streaks (ECON-04). `wonLastPvp` is true
-- only when the round just played was a PvP win (D-12).
function EconomyService.recordRound(state: PlayerState.State, kind: "pvp" | "pve" | "carousel", result: "win" | "loss" | "draw")
	state.wonLastPvp = kind == "pvp" and result == "win"
	state.lostLastPvp = kind == "pvp" and result == "loss"
	if kind ~= "pvp" or result == "draw" then
		return
	end
	local streakKind: "win" | "loss" = if result == "win" then "win" else "loss"
	if state.streak.kind == streakKind then
		state.streak.length += 1
	else
		state.streak = { kind = streakKind, length = 1 }
	end
end

return EconomyService
