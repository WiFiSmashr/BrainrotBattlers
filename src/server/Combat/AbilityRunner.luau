--!strict
-- Interprets a unit's data-driven ability (GDD 7.4, 13.1). ABL-01: output is
-- (values[star] + adRatio * AD) * (AP / 100). AP never changes durations or counts.
-- ABL-05: the combat loop only calls begin/finish; no ability logic lives there.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local CombatConfig = require(Shared.Config.CombatConfig)
local Grid = require(Shared.Util.Grid)
local StatBlock = require(script.Parent.StatBlock)
local Statuses = require(script.Parent.Statuses)
local Targeting = require(script.Parent.Targeting)
local SimTypes = require(script.Parent.SimTypes)

type Unit = SimTypes.Unit
type Effect = Types.AbilityEffect

local COLUMNS, ROWS = CombatConfig.arenaColumns, CombatConfig.arenaRows

-- Statuses that hurt the target, so a radius on them reaches enemies rather than allies.
local HOSTILE = { Stun = true, Freeze = true, Silence = true, Charm = true, Taunt = true, Slow = true, Wound = true }

-- StatBuff stat ids from ability data -> StatBlock + modifier kind + divisor (percent -> fraction).
local STAT_BUFFS = {
	attackSpeedPct = { stat = "attackSpeed", kind = "pct", divisor = 100 },
	damageReduction = { stat = "damageReduction", kind = "flat", divisor = 100 },
	armor = { stat = "armor", kind = "flat", divisor = 1 },
	mr = { stat = "mr", kind = "flat", divisor = 1 },
	health = { stat = "maxHealth", kind = "flat", divisor = 1 },
	ad = { stat = "ad", kind = "flat", divisor = 1 },
	ap = { stat = "ap", kind = "flat", divisor = 1 },
}

local AbilityRunner = {}

-- Star-indexed value, clamped to the last entry.
local function starValue(list: { number }?, star: number): number
	if not list then
		return 0
	end
	return list[math.min(star, #list)] or 0
end

-- ABL-01 output for an effect.
local function amount(caster: Unit, effect: Effect, scale: number): number
	local base = starValue(effect.values, caster.star) + (effect.adRatio or 0) * StatBlock.get(caster.stats.ad)
	return base * (StatBlock.get(caster.stats.ap) / 100) * scale
end

-- Units an effect applies to, after onSelf and radius expansion (D-04).
local function affected(sim: any, caster: Unit, ability: Types.AbilityDef, effect: Effect, targets: { Unit }): { Unit }
	if effect.onSelf then
		return { caster }
	end
	local mode = ability.targeting
	if effect.radius and mode ~= "EnemiesInRadius" and mode ~= "AlliesInRadius" then
		local hostile = effect.kind == "Damage" or (effect.kind == "Status" and HOSTILE[effect.status or ""] == true)
		local out: { Unit } = {}
		local centers = if mode == "Self" then { caster } else targets
		for _, center in centers do
			local found = if hostile
				then Targeting.enemiesWithin(sim, caster, center.cell, effect.radius)
				else Targeting.alliesWithin(sim, caster, center.cell, effect.radius)
			for _, u in found do
				table.insert(out, u)
			end
		end
		return out
	end
	return targets
end

-- Free cell for a Dash: adjacent to the target, on its far side if `behind`, else nearest the caster.
local function dashCell(sim: any, caster: Unit, target: Unit, behind: boolean): SimTypes.Cell?
	local occupied = sim:occupied(caster)
	if behind then
		local dx = target.cell.col - caster.cell.col
		local dy = target.cell.row - caster.cell.row
		local cell = {
			col = target.cell.col + (if dx > 0 then 1 elseif dx < 0 then -1 else 0),
			row = target.cell.row + (if dy > 0 then 1 elseif dy < 0 then -1 else 0),
		}
		if Grid.inBounds(cell, COLUMNS, ROWS) and not occupied[Grid.key(cell)] then
			return cell
		end
	end
	local best: SimTypes.Cell? = nil
	local bestDist = math.huge
	for _, n in Grid.neighbors(target.cell, COLUMNS, ROWS) do
		if not occupied[Grid.key(n)] then
			local d = Grid.distance(caster.cell, n)
			if d < bestDist then
				best, bestDist = n, d
			end
		end
	end
	return best
end

local runEffects

-- Applies one effect to its affected units.
local function runEffect(sim: any, caster: Unit, ability: Types.AbilityDef, effect: Effect, targets: { Unit }, scale: number)
	local star = caster.star
	local kind = effect.kind

	if kind == "Dash" then
		local target = targets[1]
		if target and Grid.distance(caster.cell, target.cell) > 1 or (target and effect.behind) then
			local cell = dashCell(sim, caster, target, effect.behind == true)
			if cell then
				caster.cell = { col = cell.col, row = cell.row }
				caster.stepTo = nil
				sim:emit("Move", { unit = caster.id, col = cell.col, row = cell.row, over = 0 })
			end
		end
		return
	elseif kind == "Summon" then
		for _ = 1, effect.count or 1 do
			sim:queueSummon(caster, {
				name = if effect.customId == "training_pup" then "Training Pup" else "Token",
				health = starValue(effect.values, star),
				ad = (effect.adRatio or 0) * StatBlock.get(caster.stats.ad),
			})
		end
		return
	elseif kind == "Custom" then
		local module = sim.custom[effect.customId or ""]
		assert(module, "missing Custom ability module: " .. tostring(effect.customId))
		module({
			sim = sim, caster = caster, effect = effect, star = star, scale = scale,
			targets = if effect.onSelf then { caster } else targets, -- raw: Custom modules expand areas themselves
			run = function(effects: { Effect }, subTargets: { Unit })
				runEffects(sim, caster, ability, effects, subTargets, scale)
			end,
		})
		return
	end

	local units = affected(sim, caster, ability, effect, targets)
	local hits = effect.hits or 1
	local value = amount(caster, effect, scale)
	local duration = starValue(effect.duration, star)

	for _, unit in units do
		if kind == "Damage" then
			for _ = 1, hits do
				sim:queueDamage({
					source = caster, target = unit, amount = value, damageType = effect.damageType or "Physical",
					isAuto = false, canCrit = (caster.counters.abilityCrit or 0) > 0, isAbility = true, -- Mega Wand
				})
			end
		elseif kind == "Heal" then
			sim:queueHeal(caster, unit, value)
		elseif kind == "Shield" then
			sim:queueShield(caster, unit, value, duration)
		elseif kind == "Status" then
			local slow = starValue(effect.values, star) / 100
			sim:applyStatus(unit, effect.status or "Stun", duration, slow, caster)
		elseif kind == "Mana" then
			unit.mana = math.clamp(unit.mana + starValue(effect.values, star), 0, unit.maxMana)
		elseif kind == "StatBuff" then
			local map = STAT_BUFFS[effect.stat or ""]
			assert(map, "unknown StatBuff stat: " .. tostring(effect.stat))
			local sourceId = ("buff:%d:%d:%s"):format(caster.id, sim.castSeq, effect.stat :: string)
			sim:addModifier(unit, map.stat, map.kind, starValue(effect.values, star) / map.divisor, sourceId, if duration > 0 then duration else nil)
		end
	end
end

function runEffects(sim: any, caster: Unit, ability: Types.AbilityDef, effects: { Effect }, targets: { Unit }, scale: number)
	for _, effect in effects do
		runEffect(sim, caster, ability, effect, targets, scale)
	end
end

-- Targets the unit's ability would hit now (empty means it cannot cast yet).
function AbilityRunner.targets(sim: any, unit: Unit, current: Unit?): { Unit }
	if not unit.ability then
		return {}
	end
	return Targeting.select(sim, unit, unit.ability, current)
end

-- Starts a cast: mana resets, the unit is busy for the cast time (ABL-02, ABL-03).
function AbilityRunner.begin(sim: any, unit: Unit, targets: { Unit })
	local ability = unit.ability :: Types.AbilityDef
	unit.mana = 0
	unit.castUntil = sim.time + (ability.castTime or CombatConfig.castSeconds)
	local ids = {}
	for _, t in targets do
		table.insert(ids, t.id)
	end
	unit.castTargets = ids
	sim:emit("Cast", { unit = unit.id, name = ability.name, mana = 0 })
end

-- Executes an ability's effects at `scale` of full power (Glitch recasts use scale < 1).
function AbilityRunner.execute(sim: any, caster: Unit, ability: Types.AbilityDef, targets: { Unit }, scale: number)
	sim.castSeq += 1
	runEffects(sim, caster, ability, ability.effects, targets, scale)
end

-- Ends a cast: re-checks targets, runs the effects, fires OnCast (ABL-03).
function AbilityRunner.finish(sim: any, unit: Unit)
	local ability = unit.ability :: Types.AbilityDef
	local ids = unit.castTargets or {}
	unit.castUntil, unit.castTargets = nil, nil

	local targets: { Unit } = {}
	for _, id in ids do
		local t = sim.byId[id]
		if t and t.alive and (t.team == unit.team or Statuses.active(t, "Untargetable", sim.time) == nil) then
			table.insert(targets, t)
		end
	end
	if #targets == 0 and ability.targeting ~= "Self" then
		return -- every target died during the cast
	end
	AbilityRunner.execute(sim, unit, ability, targets, 1)
	sim:fire("OnCast", { caster = unit, ability = ability, targets = targets })
end

return AbilityRunner
