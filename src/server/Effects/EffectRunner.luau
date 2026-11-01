--!strict
-- Attaches Effect modules while their source is active, routes hooks to them, and detaches them
-- when the source ends (GDD 3.4, 13.2; ARCH-03, TRT-01..TRT-06, ITM-01, ITM-04, ITM-05).
-- Three entry points:
--   attachCombat   per fight: item stats + effects, then trait tiers, on a CombatSim
--   incomeModifiers / onRoundEnd   economy hooks that run outside the sim (ECON-06)
-- Modules never know about each other; all numbers arrive through params (TRT-06).

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Index = require(Shared.Util.Index)
local TraitData = require(Shared.Data.Traits)
local AugmentData = require(Shared.Data.Augments)
local TraitCounter = require(Shared.Util.TraitCounter)
local StatBlock = require(script.Parent.Parent.Combat.StatBlock)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local EconomyService = require(script.Parent.Parent.Economy.EconomyService)
local Registry = require(script.Parent.Registry)

export type TeamInfo = { gold: number, streak: number?, augments: { string }?, traits: number? }

-- Item stat keys -> StatBlock + modifier kind (ITM-04).
local STAT_MAP = {
	health = { "maxHealth", "flat" }, ad = { "ad", "flat" }, ap = { "ap", "flat" },
	attackSpeedPct = { "attackSpeed", "pct" }, armor = { "armor", "flat" }, mr = { "mr", "flat" },
	critChance = { "critChance", "flat" }, critDamage = { "critDamage", "flat" },
}

-- Applies an item's plain stat bonuses to its holder; one ctx per copy so copies stack.
local statsModule: Types.EffectModule = {
	id = "item_stats",
	attach = function(ctx, params)
		for key, value in params do
			local map = STAT_MAP[key]
			assert(map, "unknown item stat: " .. key)
			ctx.addModifier(ctx.owner, map[1], map[2] :: any, value, nil, key)
		end
	end,
	detach = function() end,
}

local AugmentIndex: { [string]: Types.AugmentDef } = {}
for _, a in AugmentData do
	AugmentIndex[a.id] = a
end

local EffectRunner = {}

-- Builds the helper table modules use inside a sim. Everything a module adds is logged so that
-- removeAll() can take it all back (13.2: detach MUST remove every modifier by sourceId).
local function makeContext(sim: any, base: { [string]: any }): Types.EffectContext
	local log: { [string]: { unit: any, id: string } } = {}
	local members: { any } = base.members or {}
	local memberSet: { [any]: boolean } = {}
	for _, m in members do
		memberSet[m] = true
	end

	local function idFor(subId: string?): string
		return if subId then base.sourceId .. "/" .. subId else base.sourceId
	end

	local ctx: any = {
		sim = sim, sourceId = base.sourceId, owner = base.owner, team = base.team,
		units = base.units or {}, members = members, params = base.params or {}, state = {},
		rng = sim.rng, teamInfo = base.teamInfo,
	}
	ctx.isMember = function(unit: any): boolean
		return memberSet[unit] == true
	end
	ctx.addModifier = function(unit: any, stat: string, kind: string, value: number, duration: number?, subId: string?)
		local id = idFor(subId)
		sim:addModifier(unit, stat, kind, value, id, duration)
		log[unit.id .. ":" .. id] = { unit = unit, id = id }
	end
	ctx.removeModifiers = function(unit: any, subId: string?)
		local id = idFor(subId)
		for _, block in unit.stats do
			StatBlock.removeSource(block, id)
		end
		log[unit.id .. ":" .. id] = nil
	end
	ctx.removeAll = function()
		for _, entry in log do
			for _, block in entry.unit.stats do
				StatBlock.removeSource(block, entry.id)
			end
		end
		log = {}
	end
	ctx.queueDamage = function(source: any?, target: any, amount: number, damageType: string, flags: any?)
		local f = flags or {}
		sim:queueDamage({
			source = source, target = target, amount = amount, damageType = damageType,
			isAuto = f.isAuto == true, canCrit = f.canCrit == true, isAbility = f.isAbility == true,
		})
	end
	ctx.queueHeal = function(target: any, amount: number)
		sim:queueHeal(ctx.owner, target, amount)
	end
	ctx.heal = function(target: any, amount: number)
		sim:heal(target, amount)
	end
	ctx.queueShield = function(target: any, amount: number, duration: number)
		sim:queueShield(ctx.owner, target, amount, duration)
	end
	ctx.applyStatus = function(target: any, status: string, duration: number, amount: number?, source: any?)
		sim:applyStatus(target, status, duration, amount or 0, source)
	end
	ctx.summon = function(owner: any, def: any)
		sim:queueSummon(owner, def)
	end
	ctx.active = true
	return ctx :: Types.EffectContext
end

-- Attaches one module: runs attach, then subscribes its hooks for as long as the ctx is active.
local function attachModule(sim: any, module: Types.EffectModule, ctx: any)
	module.attach(ctx, ctx.params)
	for hook, fn in module.hooks or {} do
		sim:on(hook, function(_, event)
			if ctx.active then
				fn(ctx, event)
			end
		end)
	end
	table.insert(sim.state.effects, { module = module, ctx = ctx })
end

-- Detaches every effect on a sim; removes all of their modifiers (13.2).
function EffectRunner.detachAll(sim: any)
	for _, entry in sim.state.effects or {} do
		entry.ctx.active = false
		entry.module.detach(entry.ctx)
		entry.ctx.removeAll()
	end
	sim.state.effects = {}
end

-- Items: stats for every copy (ITM-04); the effect once per distinct item id (ITM-05).
local function attachItems(sim: any, unit: any, teamInfo: TeamInfo, team: string)
	local seen: { [string]: boolean } = {}
	for i, itemId in unit.items do
		local def = Index.item(itemId)
		assert(def, "unknown item " .. itemId)
		attachModule(sim, statsModule, makeContext(sim, {
			sourceId = ("itemstats:%d:%d"):format(unit.id, i), owner = unit, team = team, params = def.stats, teamInfo = teamInfo,
		}))
		local module = Registry.items[itemId]
		if module and not seen[itemId] then
			seen[itemId] = true
			attachModule(sim, module, makeContext(sim, {
				sourceId = ("item:%s:%d"):format(itemId, unit.id), owner = unit, team = team,
				params = def.params or {}, teamInfo = teamInfo, units = { unit },
			}))
		end
	end
end

-- Traits: count distinct unit ids on the board and attach the highest reached tier (TRT-01..03).
-- Returns how many distinct traits are active (Team Spirit reads it).
local function attachTraits(sim: any, units: { any }, teamInfo: TeamInfo, team: string): number
	local entries: { TraitCounter.Entry } = {}
	for _, u in units do
		table.insert(entries, { defId = u.defId or ("unit" .. u.id), traits = u.traits })
	end
	local counted = TraitCounter.count(entries)
	local active = 0
	for _, trait in TraitData do
		local state = counted[trait.id]
		if state and state.tier then
			active += 1
			local members = {}
			for _, u in units do
				if table.find(u.traits, trait.id) then
					table.insert(members, u)
				end
			end
			local module = Registry.traits[trait.id]
			assert(module, "missing trait module " .. trait.id)
			attachModule(sim, module, makeContext(sim, {
				sourceId = ("trait:%s:%s"):format(trait.id, team), team = team, members = members,
				units = if trait.scope == "members" then members else units,
				params = state.tier.params, teamInfo = teamInfo,
			}))
		end
	end
	return active
end

-- Augments the team's player owns, applied to every unit on the team (AUG-07).
local function attachAugments(sim: any, units: { any }, teamInfo: TeamInfo, team: string)
	for _, augmentId in teamInfo.augments or {} do
		local module = Registry.augments[augmentId]
		local def = AugmentIndex[augmentId]
		assert(module and def, "unknown augment " .. augmentId)
		attachModule(sim, module, makeContext(sim, {
			sourceId = ("augment:%s:%s"):format(augmentId, team), team = team, units = units,
			params = def.params, teamInfo = teamInfo,
		}))
	end
end

-- Returns a CombatSim `attach` callback: items, traits, then augments for both teams, then full
-- health once every bonus is in place.
function EffectRunner.attach(teams: { home: TeamInfo, away: TeamInfo }): (any) -> ()
	return function(sim: any)
		sim.state.effects = {}
		for _, team in { "home", "away" } do
			local units = {}
			for _, u in sim.units do
				if u.team == team and not u.isToken then
					table.insert(units, u)
				end
			end
			local info = table.clone(teams[team])
			for _, u in units do
				attachItems(sim, u, info, team)
			end
			info.traits = attachTraits(sim, units, info, team)
			attachAugments(sim, units, info, team)
		end
		for _, u in sim.units do
			u.health = StatBlock.get(u.stats.maxHealth)
		end
		sim:on("OnCombatEnd", function()
			EffectRunner.detachAll(sim)
		end)
	end
end

-- Everything on a player's side that can react to player-level hooks (income, round end, combine...):
-- active board traits (with their member units) and owned augments.
type Source = { module: Types.EffectModule, params: { [string]: number }, members: { PlayerState.Unit } }

local function playerSources(state: PlayerState.State): { Source }
	local entries: { TraitCounter.Entry } = {}
	local boardUnits: { { unit: PlayerState.Unit, traits: { string } } } = {}
	for _, u in PlayerState.sortedUnits(state) do
		local def = Index.unit(u.defId)
		if u.board and def then
			table.insert(entries, { defId = u.defId, traits = def.traits })
			table.insert(boardUnits, { unit = u, traits = def.traits })
		end
	end
	local out: { Source } = {}
	local counted = TraitCounter.count(entries)
	for _, trait in TraitData do
		local ts = counted[trait.id]
		if ts and ts.tier then
			local members = {}
			for _, b in boardUnits do
				if table.find(b.traits, trait.id) then
					table.insert(members, b.unit)
				end
			end
			table.insert(out, { module = Registry.traits[trait.id], params = ts.tier.params, members = members })
		end
	end
	for _, augmentId in state.augments do
		table.insert(out, { module = Registry.augments[augmentId], params = AugmentIndex[augmentId].params, members = {} })
	end
	return out
end

-- Builds the ctx a player-level hook receives. Gold goes through EconomyService (ECON-01).
local function playerContext(state: PlayerState.State, source: Source): any
	return {
		player = state, members = source.members, params = source.params, state = {},
		addGold = function(amount: number)
			EconomyService.add(state, amount, "Hook")
		end,
	}
end

-- Fires a player-level hook (OnPrepStart, OnUnitBought, OnItemCombined, OnRoundEnd) on every active
-- trait and owned augment that has it.
function EffectRunner.firePlayerHook(state: PlayerState.State, hook: string, event: any)
	for _, source in playerSources(state) do
		local fn = source.module.hooks and (source.module.hooks :: any)[hook]
		if fn then
			fn(playerContext(state, source), event)
		end
	end
end

-- OnIncomeCalc modifiers for EconomyService.calcIncome (ECON-06).
function EffectRunner.incomeModifiers(state: PlayerState.State): { EconomyService.Modifier }
	local mods: { EconomyService.Modifier } = {}
	for _, source in playerSources(state) do
		local fn = source.module.hooks and (source.module.hooks :: any).OnIncomeCalc
		if fn then
			table.insert(mods, function(breakdown)
				local ctx = playerContext(state, source)
				ctx.addIncome = function(label: string, amount: number)
					table.insert(breakdown.extras, { label = label, amount = amount })
				end
				fn(ctx, { breakdown = breakdown })
			end)
		end
	end
	return mods
end

-- Runs OnRoundEnd hooks (e.g. Noob growth) for a player who just fought a round.
function EffectRunner.onRoundEnd(state: PlayerState.State, result: string)
	EffectRunner.firePlayerHook(state, "OnRoundEnd", { result = result })
end

-- Runs OnItemCombined hooks (e.g. Gold-Plated Gear) after a successful combine.
function EffectRunner.onItemCombined(state: PlayerState.State, item: PlayerState.Item)
	EffectRunner.firePlayerHook(state, "OnItemCombined", { item = item })
end

-- Runs OnUnitBought hooks after a purchase.
function EffectRunner.onUnitBought(state: PlayerState.State, unitUid: number)
	EffectRunner.firePlayerHook(state, "OnUnitBought", { unitUid = unitUid })
end

-- Runs OnPrepStart hooks after income is paid.
function EffectRunner.onPrepStart(state: PlayerState.State)
	EffectRunner.firePlayerHook(state, "OnPrepStart", {})
end

return EffectRunner
