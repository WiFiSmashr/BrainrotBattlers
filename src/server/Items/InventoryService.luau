--!strict
-- Item inventory rules (GDD 9.1, 9.5; ITM-01, ITM-02, ITM-03, ITM-06, ITM-09, ITM-10, ITM-11).
-- Phase checks belong to ActionRouter (ITM-02). Items live in state.inventory; `equippedTo` says
-- which unit holds one, so the inventory has no cap and selling returns items for free (ITM-06).

local Shared = game:GetService("ReplicatedStorage").Shared
local ItemData = require(Shared.Data.Items)
local Index = require(Shared.Util.Index)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local MAX_ITEMS_PER_UNIT = 3 -- ITM-01
local MAX_SAME_DROPS_IN_A_ROW = 2 -- ITM-11: a component cannot drop 3 times in a row

type Rng = { pick: (any, { any }) -> any }

local components: { string } = {}
local combined: { string } = {}
local recipes: { [string]: string } = {}
for _, def in ItemData do
	if def.kind == "Component" then
		table.insert(components, def.id)
	else
		table.insert(combined, def.id)
		local a, b = (def.recipe :: { string })[1], (def.recipe :: { string })[2]
		recipes[if a < b then a .. "+" .. b else b .. "+" .. a] = def.id
	end
end

local InventoryService = {}

-- Component ids in data order.
InventoryService.components = components
-- Combined item ids in data order.
InventoryService.combined = combined

-- The combined item made from two components, or nil. Order does not matter (ITM-03).
function InventoryService.recipeFor(a: string, b: string): string?
	return recipes[if a < b then a .. "+" .. b else b .. "+" .. a]
end

-- Adds an unequipped item to the inventory.
function InventoryService.addItem(state: PlayerState.State, itemId: string): PlayerState.Item
	return PlayerState.newItem(state, itemId)
end

-- Picks a random component, never the same one three times in a row for this player (ITM-11).
function InventoryService.randomComponent(state: PlayerState.State, rng: Rng): string
	local pool = components
	local n = #state.drops
	if n >= MAX_SAME_DROPS_IN_A_ROW and state.drops[n] == state.drops[n - 1] then
		pool = {}
		for _, id in components do
			if id ~= state.drops[n] then
				table.insert(pool, id)
			end
		end
	end
	local pick = rng:pick(pool) :: string
	table.insert(state.drops, pick)
	if #state.drops > MAX_SAME_DROPS_IN_A_ROW then
		table.remove(state.drops, 1)
	end
	return pick
end

-- Drops `count` random components straight into the inventory (ITM-10, ITM-12).
function InventoryService.dropComponents(state: PlayerState.State, count: number, rng: Rng): { PlayerState.Item }
	local items = {}
	for _ = 1, count do
		table.insert(items, InventoryService.addItem(state, InventoryService.randomComponent(state, rng)))
	end
	return items
end

-- PvE win reward: the round's drops plus the player's extra drops (PvE Bounty).
function InventoryService.pveDrop(state: PlayerState.State, base: number, rng: Rng)
	InventoryService.dropComponents(state, base + PlayerState.cfg(state, "pveExtraDrops", 0), rng)
end

-- Grants `count` random combined items.
function InventoryService.grantRandomCombined(state: PlayerState.State, count: number, rng: Rng): { PlayerState.Item }
	local items = {}
	for _ = 1, count do
		table.insert(items, InventoryService.addItem(state, rng:pick(combined) :: string))
	end
	return items
end

-- Equips an unequipped item on a unit (ITM-01: at most 3 items per unit).
function InventoryService.equip(state: PlayerState.State, itemUid: number, unitUid: number): PlayerState.Result
	local item, unit = state.inventory[itemUid], state.units[unitUid]
	if not item then
		return { ok = false, reason = "UnknownItem" }
	end
	if not unit then
		return { ok = false, reason = "UnknownUnit" }
	end
	if item.equippedTo then
		return { ok = false, reason = "ItemEquipped" }
	end
	if #PlayerState.itemsOn(state, unitUid) >= MAX_ITEMS_PER_UNIT then
		return { ok = false, reason = "UnitFull" }
	end
	item.equippedTo = unitUid
	return { ok = true }
end

-- Returns an equipped item to the inventory (ITM-02).
function InventoryService.unequip(state: PlayerState.State, itemUid: number): PlayerState.Result
	local item = state.inventory[itemUid]
	if not item then
		return { ok = false, reason = "UnknownItem" }
	end
	if not item.equippedTo then
		return { ok = false, reason = "NotEquipped" }
	end
	item.equippedTo = nil
	return { ok = true }
end

-- Fuses two loose components into one combined item; both are consumed. A combined item cannot be
-- combined again (ITM-03). Returns the new item.
function InventoryService.combine(state: PlayerState.State, uidA: number, uidB: number): (PlayerState.Result, PlayerState.Item?)
	local a, b = state.inventory[uidA], state.inventory[uidB]
	if uidA == uidB or not a or not b then
		return { ok = false, reason = "UnknownItem" }, nil
	end
	if a.equippedTo or b.equippedTo then
		return { ok = false, reason = "ItemEquipped" }, nil
	end
	local result = InventoryService.recipeFor(a.itemId, b.itemId)
	local defA, defB = Index.item(a.itemId), Index.item(b.itemId)
	if not result or not defA or not defB or defA.kind ~= "Component" or defB.kind ~= "Component" then
		return { ok = false, reason = "CannotCombine" }, nil
	end
	state.inventory[uidA], state.inventory[uidB] = nil, nil
	return { ok = true }, InventoryService.addItem(state, result)
end

return InventoryService
