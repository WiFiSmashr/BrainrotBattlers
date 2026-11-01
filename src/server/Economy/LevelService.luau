--!strict
-- Player level and XP (GDD 6.1, 6.2; LVL-01, LVL-02, LVL-03, LVL-04).

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local EconomyService = require(script.Parent.EconomyService)

local LevelService = {}

-- Board size equals player level (LVL-01).
function LevelService.boardCap(state: PlayerState.State): number
	return state.level
end

-- XP needed to go from the current level to the next, or nil at max level.
function LevelService.xpToNext(state: PlayerState.State): number?
	if state.level >= GameConfig.maxLevel then
		return nil
	end
	return GameConfig.xpToNextLevel[state.level]
end

-- Adds XP, levelling up immediately and carrying excess (LVL-03, LVL-04). Returns levels gained.
function LevelService.addXp(state: PlayerState.State, amount: number): number
	local gained = 0
	state.xp += amount
	while state.level < GameConfig.maxLevel and state.xp >= GameConfig.xpToNextLevel[state.level] do
		state.xp -= GameConfig.xpToNextLevel[state.level]
		state.level += 1
		gained += 1
	end
	if state.level >= GameConfig.maxLevel then
		state.xp = 0
	end
	return gained
end

-- Passive XP at the start of every round from global round 2 on (LVL-02).
function LevelService.grantPassive(state: PlayerState.State, globalRound: number): number
	if globalRound < GameConfig.passiveXpFromRound then
		return 0
	end
	return LevelService.addXp(state, GameConfig.passiveXp)
end

-- Buys XP for gold (LVL-03). Rejected at max level or when gold is short.
function LevelService.buyXp(state: PlayerState.State): PlayerState.Result
	if state.level >= GameConfig.maxLevel then
		return { ok = false, reason = "MaxLevel" }
	end
	local paid = EconomyService.spend(state, GameConfig.buyXpCost, "BuyXP")
	if not paid.ok then
		return paid
	end
	LevelService.addXp(state, GameConfig.buyXpAmount)
	return { ok = true }
end

return LevelService
