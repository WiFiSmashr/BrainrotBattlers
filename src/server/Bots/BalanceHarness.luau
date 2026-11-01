--!strict
-- Balance harness (GDD 14.1 phase 8): plays whole matches with bots on a fake clock, using the real
-- services and the real combat sim, then reports average match length and win rate by trait.
-- From Studio's command bar:
--   local H = require(game.ServerScriptService.Server.Bots.BalanceHarness)
--   print(H.report(H.run(20, 1)))

local Shared = game:GetService("ReplicatedStorage").Shared
local Index = require(Shared.Util.Index)
local TraitCounter = require(Shared.Util.TraitCounter)
local TraitData = require(Shared.Data.Traits)
local MatchService = require(script.Parent.Parent.Match.MatchService)
local ActionRouter = require(script.Parent.Parent.Player.ActionRouter)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local CombatRunner = require(script.Parent.Parent.Combat.CombatRunner)
local EffectRunner = require(script.Parent.Parent.Effects.EffectRunner)
local InventoryService = require(script.Parent.Parent.Items.InventoryService)
local BotController = require(script.Parent.BotController)

local STEP_SECONDS = 0.25 -- one bot action per step, far below the 20 intents/second limit
local MAX_ROUNDS = 150 -- a match still running here is reported as unfinished

export type MatchResult = {
	completed: boolean,
	rounds: number,
	winner: number?,
	placements: { [number]: number },
	finalTraits: { [number]: { string } }, -- active trait ids on each player's last fought board
}

export type Summary = {
	matches: number,
	completed: number,
	averageRounds: number,
	traits: { [string]: { appearances: number, wins: number, topFour: number } },
}

local BalanceHarness = {}

-- Active trait ids on a player's board right now.
local function activeTraits(state: PlayerState.State): { string }
	local entries: { TraitCounter.Entry } = {}
	for _, unit in state.units do
		local def = Index.unit(unit.defId)
		if unit.board and def then
			table.insert(entries, { defId = unit.defId, traits = def.traits })
		end
	end
	local out = {}
	for id, ts in TraitCounter.count(entries) do
		if ts.tier then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- Plays one match to its end. `humans` seats are idle stand-ins for human players; the rest are bots.
function BalanceHarness.runMatch(seed: number, lobbySize: number, humans: number?): MatchResult
	local clock = { t = 0 }
	local finalTraits: { [number]: { string } } = {}
	local match = MatchService.new({
		lobbySize = lobbySize, seed = seed, now = function() return clock.t end,
		combat = function(fight)
			return CombatRunner.simulate(fight, false)
		end,
		incomeModifiers = EffectRunner.incomeModifiers,
		onPveDrop = InventoryService.pveDrop,
		onPrepStart = EffectRunner.onPrepStart,
		onUnitBought = EffectRunner.onUnitBought,
		onItemCombined = EffectRunner.onItemCombined,
		onRoundEnd = function(state, result)
			finalTraits[state.userId] = activeTraits(state)
			EffectRunner.onRoundEnd(state, result)
		end,
	})
	for id = 1, humans or 0 do
		match:addPlayer(id, "Human " .. id)
	end
	BotController.fill(match)
	match:start()
	local router = ActionRouter.new(match, function() return clock.t end)
	local bots = BotController.new(match, router)

	while match.phase ~= "MatchEnd" and match.info.global <= MAX_ROUNDS do
		clock.t += STEP_SECONDS
		bots:update()
		match:update()
		if math.floor(clock.t / STEP_SECONDS) % 4000 == 0 then
			task.wait() -- let Studio breathe during long runs
		end
	end

	local winner: number? = nil
	for id, place in match.placements do
		if place == 1 then
			winner = id
		end
	end
	return {
		completed = match.phase == "MatchEnd" and winner ~= nil, rounds = match.info.global, winner = winner,
		placements = table.clone(match.placements), finalTraits = finalTraits,
	}
end

-- Plays `count` matches (seeds firstSeed, firstSeed + 1, ...) and aggregates them.
function BalanceHarness.run(count: number, firstSeed: number?, lobbySize: number?, humans: number?): Summary
	local summary: Summary = { matches = count, completed = 0, averageRounds = 0, traits = {} }
	local totalRounds = 0
	for i = 1, count do
		local result = BalanceHarness.runMatch((firstSeed or 1) + i - 1, lobbySize or 8, humans)
		if result.completed then
			summary.completed += 1
			totalRounds += result.rounds
			for userId, traitIds in result.finalTraits do
				local place = result.placements[userId]
				for _, traitId in traitIds do
					local stat = summary.traits[traitId] or { appearances = 0, wins = 0, topFour = 0 }
					summary.traits[traitId] = stat
					stat.appearances += 1
					if place == 1 then
						stat.wins += 1
					end
					if place and place <= 4 then
						stat.topFour += 1
					end
				end
			end
		end
	end
	summary.averageRounds = if summary.completed > 0 then totalRounds / summary.completed else 0
	return summary
end

-- A printable report: average match length and win rate by trait (appearances = final boards with the
-- trait active). With 8 players an even trait wins 12.5% of the time.
function BalanceHarness.report(summary: Summary): string
	local lines = {
		("Matches: %d played, %d finished"):format(summary.matches, summary.completed),
		("Average match length: %.1f rounds"):format(summary.averageRounds),
		"Win rate by trait (final board):",
	}
	for _, trait in TraitData do
		local stat = summary.traits[trait.id]
		if stat and stat.appearances > 0 then
			table.insert(lines, ("  %-12s boards %3d   win %5.1f%%   top4 %5.1f%%"):format(
				trait.name, stat.appearances, stat.wins / stat.appearances * 100, stat.topFour / stat.appearances * 100))
		else
			table.insert(lines, ("  %-12s never active"):format(trait.name))
		end
	end
	return table.concat(lines, "\n")
end

return BalanceHarness
