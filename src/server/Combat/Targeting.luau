--!strict
-- Target selection (GDD 11.3, CMB-06, CMB-07, ability targeting modes in 13.1). Pure.
-- `sim` provides: units (ascending id), byId, time, rng.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Grid = require(game:GetService("ReplicatedStorage").Shared.Util.Grid)
local StatBlock = require(script.Parent.StatBlock)
local Statuses = require(script.Parent.Statuses)
local SimTypes = require(script.Parent.SimTypes)

type Unit = SimTypes.Unit

local Targeting = {}

-- Living and not untargetable.
local function targetable(sim: any, u: Unit): boolean
	return u.alive and Statuses.active(u, "Untargetable", sim.time) == nil
end

-- Chebyshev distance between two units (CMB-03).
function Targeting.distance(a: Unit, b: Unit): number
	return Grid.distance(a.cell, b.cell)
end

-- Targetable enemies, ascending unitId.
function Targeting.enemies(sim: any, unit: Unit): { Unit }
	local list = {}
	for _, u in sim.units do
		if u.team ~= unit.team and targetable(sim, u) then
			table.insert(list, u)
		end
	end
	return list
end

-- Living allies including the unit itself, ascending unitId.
function Targeting.allies(sim: any, unit: Unit): { Unit }
	local list = {}
	for _, u in sim.units do
		if u.team == unit.team and u.alive then
			table.insert(list, u)
		end
	end
	return list
end

-- Targetable enemies within `radius` of a cell.
function Targeting.enemiesWithin(sim: any, unit: Unit, center: SimTypes.Cell, radius: number): { Unit }
	local list = {}
	for _, u in Targeting.enemies(sim, unit) do
		if Grid.distance(center, u.cell) <= radius then
			table.insert(list, u)
		end
	end
	return list
end

-- Living allies (including self) within `radius` of a cell.
function Targeting.alliesWithin(sim: any, unit: Unit, center: SimTypes.Cell, radius: number): { Unit }
	local list = {}
	for _, u in Targeting.allies(sim, unit) do
		if Grid.distance(center, u.cell) <= radius then
			table.insert(list, u)
		end
	end
	return list
end

-- Unit minimizing `score` (lower wins); ties go to the lowest unitId because input is id-ordered.
local function best(list: { Unit }, score: (Unit) -> number): Unit?
	local pick: Unit? = nil
	local pickScore = math.huge
	for _, u in list do
		local s = score(u)
		if s < pickScore then
			pick, pickScore = u, s
		end
	end
	return pick
end

-- Nearest targetable enemy; ties to the lowest unitId.
function Targeting.nearest(sim: any, unit: Unit): Unit?
	return best(Targeting.enemies(sim, unit), function(u)
		return Targeting.distance(unit, u)
	end)
end

-- The unit that currently forces this unit's target through Charm or Taunt, or nil.
-- Both end early when the source dies (11.5).
function Targeting.forcedBy(sim: any, unit: Unit, status: string): Unit?
	local s = Statuses.active(unit, status, sim.time)
	if not s or not s.source then
		return nil
	end
	local source = sim.byId[s.source]
	if source and source.alive then
		return source
	end
	return nil
end

-- Picks the unit's target this tick (CMB-06, CMB-07) and stores it on the unit.
function Targeting.acquire(sim: any, unit: Unit): Unit?
	local forced = Targeting.forcedBy(sim, unit, "Taunt") or Targeting.forcedBy(sim, unit, "Charm")
	if forced then
		unit.target = forced.id
		return forced
	end

	local range = StatBlock.get(unit.stats.range)
	local current = if unit.target then sim.byId[unit.target] else nil
	if current and targetable(sim, current) and current.team ~= unit.team then
		if Targeting.distance(unit, current) <= range then
			return current
		end
		-- Out of range: switch to the nearest enemy that IS in range, if any.
		local inRange = best(Targeting.enemiesWithin(sim, unit, unit.cell, range), function(u)
			return Targeting.distance(unit, u)
		end)
		if inRange then
			unit.target = inRange.id
			return inRange
		end
		return current
	end

	if (unit.counters.randomTarget or 0) > 0 then -- Full Rot: attacks and abilities pick a random enemy
		local pick = sim.rng:pick(Targeting.enemies(sim, unit)) :: Unit?
		unit.target = if pick then pick.id else nil
		return pick
	end
	local nearest = Targeting.nearest(sim, unit)
	unit.target = if nearest then nearest.id else nil
	return nearest
end

-- Resolves an ability's targeting mode to a list of units (13.1). May be empty.
function Targeting.select(sim: any, caster: Unit, ability: Types.AbilityDef, current: Unit?): { Unit }
	local mode = ability.targeting
	local range = ability.range or StatBlock.get(caster.stats.range)
	local enemies = Targeting.enemies(sim, caster)

	local function inRange(): { Unit }
		local list = {}
		for _, u in enemies do
			if Targeting.distance(caster, u) <= range then
				table.insert(list, u)
			end
		end
		return list
	end

	if mode == "Self" then
		return { caster }
	elseif mode == "CurrentTarget" then
		return if current then { current } else {}
	elseif mode == "NearestEnemies" then
		local sorted = table.clone(enemies)
		table.sort(sorted, function(a, b)
			local da, db = Targeting.distance(caster, a), Targeting.distance(caster, b)
			if da ~= db then
				return da < db
			end
			return a.id < b.id
		end)
		local out = {}
		for i = 1, math.min(ability.count or 1, #sorted) do
			out[i] = sorted[i]
		end
		return out
	elseif mode == "RandomEnemies" then
		-- Distinct picks first; if more picks than enemies, the extras are random repeats.
		if #enemies == 0 then
			return {}
		end
		local count = ability.count or 1
		local out = {}
		local shuffled = sim.rng:shuffle(enemies)
		for i = 1, count do
			out[i] = if i <= #shuffled then shuffled[i] else sim.rng:pick(enemies)
		end
		return out
	elseif mode == "FarthestEnemyInRange" then
		local pick = best(inRange(), function(u)
			return -Targeting.distance(caster, u)
		end)
		return if pick then { pick } else {}
	elseif mode == "LowestHealthEnemyInRange" then
		local pick = best(inRange(), function(u)
			return u.health
		end)
		return if pick then { pick } else {}
	elseif mode == "HighestHealthEnemyInRange" then
		local pick = best(inRange(), function(u)
			return -u.health
		end)
		return if pick then { pick } else {}
	elseif mode == "HighestManaEnemyInRange" then
		local pick = best(inRange(), function(u)
			return -u.mana
		end)
		return if pick then { pick } else {}
	elseif mode == "LowestHealthAlly" then
		local pick = best(Targeting.allies(sim, caster), function(u)
			return u.health
		end)
		return if pick then { pick } else {}
	elseif mode == "AlliesInRadius" then
		return Targeting.alliesWithin(sim, caster, caster.cell, ability.radius or 1)
	elseif mode == "EnemiesInRadius" then
		return Targeting.enemiesWithin(sim, caster, caster.cell, ability.radius or 1)
	end
	return {}
end

return Targeting
