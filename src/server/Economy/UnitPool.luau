--!strict
-- Shared unit pool (GDD 6.5, LOBBY-02). One per match; counts are remaining copies per unit.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

export type Pool = {
	counts: { [string]: number },
	costOf: { [string]: number },
	idsByCost: { [number]: { string } },
	initialTotal: number,
}

local UnitPool = {}

-- Builds a pool from unit data; copies = ceil(copies * lobbySize / 8) (LOBBY-02).
function UnitPool.new(units: { Types.UnitDef }, lobbySize: number): Pool
	local pool: Pool = { counts = {}, costOf = {}, idsByCost = {}, initialTotal = 0 }
	for _, unit in units do
		local copies = math.ceil(GameConfig.poolCopiesAt8[unit.cost] * lobbySize / GameConfig.maxLobbySize)
		pool.counts[unit.id] = copies
		pool.costOf[unit.id] = unit.cost
		pool.idsByCost[unit.cost] = pool.idsByCost[unit.cost] or {}
		table.insert(pool.idsByCost[unit.cost], unit.id)
		pool.initialTotal += copies
	end
	return pool
end

-- Copies of a unit left in the pool.
function UnitPool.remaining(pool: Pool, defId: string): number
	return pool.counts[defId] or 0
end

-- Total copies left across a cost tier.
function UnitPool.remainingOfCost(pool: Pool, cost: number): number
	local total = 0
	for _, id in pool.idsByCost[cost] or {} do
		total += pool.counts[id]
	end
	return total
end

-- Total copies left in the pool.
function UnitPool.total(pool: Pool): number
	local total = 0
	for _, n in pool.counts do
		total += n
	end
	return total
end

-- Removes one copy; false if none remain.
function UnitPool.take(pool: Pool, defId: string): boolean
	if (pool.counts[defId] or 0) <= 0 then
		return false
	end
	pool.counts[defId] -= 1
	return true
end

-- Returns `n` copies to the pool (default 1).
function UnitPool.put(pool: Pool, defId: string, n: number?)
	pool.counts[defId] = (pool.counts[defId] or 0) + (n or 1)
end

-- Picks a unit of `cost` weighted by copies remaining; nil if the tier is empty. Does not take it.
function UnitPool.pick(pool: Pool, cost: number, rng: { nextInt: (any, number, number) -> number }): string?
	local total = UnitPool.remainingOfCost(pool, cost)
	if total <= 0 then
		return nil
	end
	local roll = rng:nextInt(1, total)
	for _, id in pool.idsByCost[cost] do
		roll -= pool.counts[id]
		if roll <= 0 then
			return id
		end
	end
	return nil
end

return UnitPool
