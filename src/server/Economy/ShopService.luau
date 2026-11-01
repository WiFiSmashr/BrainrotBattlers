--!strict
-- Shop rolling, buying, rerolling, locking and selling (GDD 6.3, 6.4, 5.6; SHOP-01..07).
-- The server rolls; clients only send slot indices (SHOP-07).

local Shared = game:GetService("ReplicatedStorage").Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Index = require(Shared.Util.Index)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local EconomyService = require(script.Parent.EconomyService)
local UnitPool = require(script.Parent.UnitPool)
local MergeService = require(script.Parent.MergeService)

type Rng = { nextInt: (any, number, number) -> number }

export type BuyResult = { ok: boolean, reason: string?, unitUid: number?, merges: { MergeService.MergeEvent }? }

local ShopService = {}

-- Rolls one cost tier from the level's odds row (SHOP-01).
local function rollTier(rng: Rng, level: number): number
	local row = ShopConfig.odds[math.min(level, GameConfig.maxLevel)]
	local roll = rng:nextInt(1, 100)
	for cost, pct in row do
		roll -= pct
		if roll <= 0 then
			return cost
		end
	end
	return 1
end

-- Rolls one slot and takes the copy from the pool (SHOP-01, SHOP-02, SHOP-05).
-- Falls back to lower tiers when the rolled tier is empty; returns nil for an empty slot.
function ShopService.rollSlot(pool: UnitPool.Pool, rng: Rng, level: number): string?
	for cost = rollTier(rng, level), 1, -1 do
		local defId = UnitPool.pick(pool, cost, rng)
		if defId then
			UnitPool.take(pool, defId)
			return defId
		end
	end
	return nil
end

-- Returns every unbought shop copy to the pool and clears the slots (SHOP-02).
function ShopService.release(state: PlayerState.State, pool: UnitPool.Pool)
	for i, slot in state.shop.slots do
		if type(slot) == "string" then
			UnitPool.put(pool, slot)
		end
		state.shop.slots[i] = false
	end
end

-- Replaces all slots with a fresh roll, releasing the old ones first.
local function rollShop(state: PlayerState.State, pool: UnitPool.Pool, rng: Rng)
	ShopService.release(state, pool)
	for i = 1, ShopConfig.slots do
		state.shop.slots[i] = ShopService.rollSlot(pool, rng, state.level) or false
	end
end

-- Automatic refresh at the start of Prep, after income (SHOP-03). Does nothing while locked.
function ShopService.refresh(state: PlayerState.State, pool: UnitPool.Pool, rng: Rng)
	if state.shop.locked then
		return
	end
	rollShop(state, pool, rng)
end

-- Manual reroll for gold (SHOP-04). The first `freeRerolls` each round cost nothing (Reroll Frenzy).
function ShopService.reroll(state: PlayerState.State, pool: UnitPool.Pool, rng: Rng): PlayerState.Result
	local free = state.rerollsThisRound < PlayerState.cfg(state, "freeRerolls", 0)
	local cost = if free then 0 else PlayerState.cfg(state, "rerollCost", EconomyConfig.rerollCost)
	local paid = EconomyService.spend(state, cost, "Reroll")
	if not paid.ok then
		return paid
	end
	state.rerollsThisRound += 1
	rollShop(state, pool, rng)
	return { ok = true }
end

-- Toggles the shop lock (SHOP-04). Returns the new lock state.
function ShopService.toggleLock(state: PlayerState.State): boolean
	state.shop.locked = not state.shop.locked
	return state.shop.locked
end

-- Buys the unit in a shop slot. The pool copy was already removed at roll time (SHOP-02).
-- TODO(phase 3): the caller fires the OnUnitBought hook with the returned unit.
function ShopService.buy(state: PlayerState.State, slot: number): BuyResult
	local defId = state.shop.slots[slot]
	if type(defId) ~= "string" then
		return { ok = false, reason = "EmptySlot" }
	end
	local def = Index.unit(defId)
	if not def then
		return { ok = false, reason = "UnknownUnit" }
	end
	if state.gold < def.cost then
		return { ok = false, reason = "NotEnoughGold" }
	end

	-- SHOP-06: a full bench rejects the buy unless it completes a merge that frees space.
	local bench = PlayerState.firstOpenBench(state)
	if not bench and not MergeService.wouldMerge(state, defId) then
		return { ok = false, reason = "BenchFull" }
	end

	EconomyService.spend(state, def.cost, "BuyUnit")
	state.shop.slots[slot] = false
	local unit = PlayerState.newUnit(state, defId, 1, bench, nil)
	local merges = MergeService.resolve(state, defId)
	return { ok = true, unitUid = unit.uid, merges = merges }
end

-- Sells a unit: refund = cost * 3^(star-1), copies return to the pool, items return to the
-- inventory (5.6, MRG-05, ITM-06).
function ShopService.sell(state: PlayerState.State, unitUid: number, pool: UnitPool.Pool): PlayerState.Result
	local unit = state.units[unitUid]
	if not unit then
		return { ok = false, reason = "UnknownUnit" }
	end
	local def = Index.unit(unit.defId)
	if not def then
		return { ok = false, reason = "UnknownUnit" }
	end
	EconomyService.add(state, def.cost * MergeService.copyCount(unit.star), "Sell")
	UnitPool.put(pool, unit.defId, MergeService.copyCount(unit.star))
	for _, item in PlayerState.itemsOn(state, unitUid) do
		item.equippedTo = nil
	end
	state.units[unitUid] = nil
	return { ok = true }
end

-- Gives the free random 1-cost starter unit on the bench (LVL-05).
function ShopService.grantStarterUnit(state: PlayerState.State, pool: UnitPool.Pool, rng: Rng): PlayerState.Unit?
	local defId = UnitPool.pick(pool, 1, rng)
	local bench = PlayerState.firstOpenBench(state)
	if not defId or not bench then
		return nil
	end
	UnitPool.take(pool, defId)
	return PlayerState.newUnit(state, defId, 1, bench, nil)
end

return ShopService
