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

-- Rolls one cost tier from the level's odds row (SHOP-01). Tiers with no copies left in the pool are
-- left out of the roll and the remaining odds are used as they are, so a drained tier never leaves an
-- empty slot while the pool still has units (D-82). If every tier the level can roll is drained, the
-- nearest tier that still has copies is used, lower tiers first. Returns nil only when the pool is empty.
local function rollTier(pool: UnitPool.Pool, rng: Rng, level: number): number?
	local row = ShopConfig.odds[math.min(level, GameConfig.maxLevel)]
	local weights: { [number]: number } = {}
	local total = 0
	for cost, pct in row do
		if pct > 0 and UnitPool.remainingOfCost(pool, cost) > 0 then
			weights[cost] = pct
			total += pct
		end
	end
	if total > 0 then
		local roll = rng:nextInt(1, total)
		for cost = 1, #row do
			local pct = weights[cost]
			if pct then
				roll -= pct
				if roll <= 0 then
					return cost
				end
			end
		end
	end
	-- Nothing the odds allow is left: take the closest tier with copies.
	local top = 1
	for cost, pct in row do
		if pct > 0 then
			top = math.max(top, cost)
		end
	end
	for distance = 0, #row do
		for _, cost in { top - distance, top + distance } do
			if cost >= 1 and cost <= #row and UnitPool.remainingOfCost(pool, cost) > 0 then
				return cost
			end
		end
	end
	return nil
end

-- Rolls one slot and takes the copy from the pool (SHOP-01, SHOP-02, SHOP-05): first the cost tier,
-- then a unit of that tier weighted by the copies remaining. Returns nil for an empty slot, which only
-- happens when the whole pool is empty.
function ShopService.rollSlot(pool: UnitPool.Pool, rng: Rng, level: number): string?
	local cost = rollTier(pool, rng, level)
	if not cost then
		return nil
	end
	local defId = UnitPool.pick(pool, cost, rng)
	if defId then
		UnitPool.take(pool, defId)
	end
	return defId
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
-- Full bench: normally rejected (SHOP-06) unless the buy completes a merge. If the player owns exactly
-- one star-1 copy and the shop shows another copy of the same unit, tapping either buys BOTH (paying
-- for both) and the merge happens at once, so no bench slot is needed (D-54).
function ShopService.buy(state: PlayerState.State, slot: number): BuyResult
	local defId = state.shop.slots[slot]
	if type(defId) ~= "string" then
		return { ok = false, reason = "EmptySlot" }
	end
	local def = Index.unit(defId)
	if not def then
		return { ok = false, reason = "UnknownUnit" }
	end

	local bench = PlayerState.firstOpenBench(state)
	local partner: number? = nil
	if not bench and not MergeService.wouldMerge(state, defId) then
		if MergeService.starOneCopies(state, defId) == 1 then
			for other, shown in state.shop.slots do
				if other ~= slot and shown == defId then
					partner = other
					break
				end
			end
		end
		if not partner then
			return { ok = false, reason = "BenchFull" }
		end
	end

	local price = if partner then def.cost * 2 else def.cost
	if state.gold < price then
		return { ok = false, reason = "NotEnoughGold" }
	end
	EconomyService.spend(state, price, "BuyUnit")
	state.shop.slots[slot] = false
	local first = PlayerState.newUnit(state, defId, 1, bench, nil)
	if partner then
		state.shop.slots[partner] = false
		PlayerState.newUnit(state, defId, 1, nil, nil) -- unplaced; the merge consumes it at once
	end
	local merges = MergeService.resolve(state, defId)
	return { ok = true, unitUid = first.uid, merges = merges }
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
