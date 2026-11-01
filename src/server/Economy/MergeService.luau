--!strict
-- Star-up merging (GDD 6.6, MRG-01..MRG-05).

local Shared = game:GetService("ReplicatedStorage").Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local MAX_ITEMS_PER_UNIT = 3 -- ITM-01

export type MergeEvent = { defId: string, star: number, uid: number }

local MergeService = {}

-- Copies of `defId` at exactly `star` owned anywhere (board or bench), sorted by uid.
local function copiesOf(state: PlayerState.State, defId: string, star: number): { PlayerState.Unit }
	local list = {}
	for _, u in PlayerState.sortedUnits(state) do
		if u.defId == defId and u.star == star then
			table.insert(list, u)
		end
	end
	return list
end

-- True if adding one more star-1 copy of `defId` would trigger a merge (SHOP-06).
function MergeService.wouldMerge(state: PlayerState.State, defId: string): boolean
	return #copiesOf(state, defId, 1) >= 2
end

-- Merges three same-star copies into one unit of the next star (MRG-01, MRG-02, MRG-03).
local function mergeThree(state: PlayerState.State, copies: { PlayerState.Unit }): MergeEvent
	local chosen = { copies[1], copies[2], copies[3] }

	-- MRG-02: take a consumed copy's board cell if any (lowest col, then row), else lowest bench slot.
	local cell: { col: number, row: number }? = nil
	local bench: number? = nil
	for _, u in chosen do
		if u.board then
			if not cell or u.board.col < cell.col or (u.board.col == cell.col and u.board.row < cell.row) then
				cell = u.board
			end
		elseif u.bench and (not bench or u.bench < bench) then
			bench = u.bench
		end
	end

	-- Gather items from the consumed copies, in item-uid order, before removing them.
	local carried: { PlayerState.Item } = {}
	for _, u in chosen do
		for _, item in PlayerState.itemsOn(state, u.uid) do
			table.insert(carried, item)
		end
	end
	table.sort(carried, function(a, b)
		return a.uid < b.uid
	end)

	local defId, star = chosen[1].defId, chosen[1].star + 1
	for _, u in chosen do
		state.units[u.uid] = nil
	end
	local merged = if cell then PlayerState.newUnit(state, defId, star, nil, cell) else PlayerState.newUnit(state, defId, star, bench, nil)

	-- Permanent Noob growth is kept by the best-grown consumed copy (D-32).
	for _, u in chosen do
		if u.growth and (not merged.growth or u.growth.gains > merged.growth.gains) then
			merged.growth = u.growth
		end
	end
	-- MRG-03: transfer up to 3 items; overflow returns to the inventory.
	for i, item in carried do
		item.equippedTo = if i <= MAX_ITEMS_PER_UNIT then merged.uid else nil
	end
	return { defId = defId, star = star, uid = merged.uid }
end

-- Merges every complete triple of `defId`, cascading star 1 -> 2 -> 3. Returns the merges done.
function MergeService.resolve(state: PlayerState.State, defId: string): { MergeEvent }
	local events: { MergeEvent } = {}
	for star = 1, CombatConfig.maxStar - 1 do
		while true do
			local copies = copiesOf(state, defId, star)
			if #copies < 3 then
				break
			end
			table.insert(events, mergeThree(state, copies))
		end
	end
	return events
end

-- Pool copies a unit stands for: 1, 3 or 9 (MRG-05).
function MergeService.copyCount(star: number): number
	return EconomyConfig.sellStarMultiplier ^ (star - 1)
end

return MergeService
