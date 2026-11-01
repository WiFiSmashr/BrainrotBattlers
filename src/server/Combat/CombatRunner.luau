--!strict
-- Adapts match state to CombatSim and back (GDD ARCH-04): builds both teams from plain player
-- state, runs the sim, and hands the recorded events to CombatPlayback for the placeholder models.

local Shared = game:GetService("ReplicatedStorage").Shared
local Index = require(Shared.Util.Index)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local PveBoards = require(script.Parent.Parent.Match.PveBoards)
local ArenaLayout = require(Shared.Util.ArenaLayout)
local FightTypes = require(script.Parent.Parent.Match.FightTypes)
local Registry = require(script.Parent.Parent.Effects.Abilities.Registry)
local EffectRunner = require(script.Parent.Parent.Effects.EffectRunner)
local CombatSim = require(script.Parent.CombatSim)
local SimTypes = require(script.Parent.SimTypes)


local CombatRunner = {}

-- The board units of a player as sim specs, ordered by uid (CMB-01). Item ids and traits ride along
-- for EffectRunner; Noob growth is permanent so it is applied here as static modifiers.
function CombatRunner.playerTeam(state: PlayerState.State): { SimTypes.UnitSpec }
	local team: { SimTypes.UnitSpec } = {}
	for _, u in PlayerState.sortedUnits(state) do
		local def = Index.unit(u.defId)
		if u.board and def then
			local items = {}
			for _, item in PlayerState.itemsOn(state, u.uid) do
				table.insert(items, item.itemId)
			end
			local modifiers: { SimTypes.Modifier } = {}
			if u.growth then
				table.insert(modifiers, { stat = "maxHealth", kind = "flat", value = u.growth.health, sourceId = "noob_growth" })
				table.insert(modifiers, { stat = "ad", kind = "flat", value = u.growth.ad, sourceId = "noob_growth" })
			end
			table.insert(team, {
				name = def.name, defId = def.id, cost = def.cost, archetype = def.archetype,
				star = u.star, cell = { col = u.board.col, row = u.board.row }, ability = def.ability,
				uid = u.uid, traits = def.traits, items = items, modifiers = modifiers,
			})
		end
	end
	return team
end

-- The PvE monster team for a global round (4.6): plain Fighters with no ability.
function CombatRunner.monsterTeam(globalRound: number): { SimTypes.UnitSpec }
	local team: { SimTypes.UnitSpec } = {}
	for i, m in PveBoards.build(globalRound) do
		table.insert(team, {
			name = "Monster", archetype = m.archetype, star = 1,
			cell = ArenaLayout.monsterCell(i), -- the same cells the Prep preview shows
			health = m.health, ad = m.ad, attackSpeed = m.attackSpeed,
		})
	end
	return team
end

-- What effects need to know about a side outside the sim: gold, streak and owned augments.
local function teamInfo(state: PlayerState.State): EffectRunner.TeamInfo
	return {
		gold = state.gold, streak = if state.streak.kind == "none" then 0 else state.streak.length,
		augments = state.augments,
	}
end

-- Runs a fight to completion. With `record`, the result carries a replay for playback.
function CombatRunner.simulate(fight: FightTypes.Fight, record: boolean?): FightTypes.Outcome
	local result = CombatSim.run({
		seed = fight.seed,
		home = CombatRunner.playerTeam(fight.home),
		away = if fight.away then CombatRunner.playerTeam(fight.away) else CombatRunner.monsterTeam(fight.globalRound),
		customAbilities = Registry,
		record = record,
		attach = EffectRunner.attach({ home = teamInfo(fight.home), away = if fight.away then teamInfo(fight.away) else { gold = 0 } }),
	})
	return {
		winner = result.winner, survivors = result.survivors, seconds = result.seconds,
		replay = if record then { roster = result.roster, events = result.events } else nil,
	}
end

return CombatRunner
