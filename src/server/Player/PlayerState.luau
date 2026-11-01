--!strict
-- Plain-table state for one player (ARCH-04/05; BRD-01 to BRD-04, ITM-01). Gold is written ONLY by EconomyService (ECON-01).
-- Unit positions live on the unit; items live in `inventory` with `equippedTo` (single source of truth).

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Grid = require(Shared.Util.Grid)

export type Unit = {
	uid: number,
	defId: string,
	star: number,
	board: Grid.Cell?, -- set when on the board
	bench: number?, -- set when on the bench (1-indexed)
	growth: { gains: number, health: number, ad: number }?, -- permanent Noob growth (8.3)
}

export type Item = { uid: number, itemId: string, equippedTo: number? }

-- A pending choice: an augment offer, or a follow-up pick (component / combined item) from an augment.
export type Offer = { kind: "augment" | "component" | "combined", choices: { string }, offer: number?, rerolled: boolean, rarity: string? }

export type Streak = { kind: "win" | "loss" | "none", length: number }

export type Shop = { slots: { string | boolean }, locked: boolean } -- false = empty slot

export type State = {
	userId: number,
	name: string,
	gold: number,
	xp: number,
	level: number,
	health: number,
	streak: Streak,
	wonLastPvp: boolean, -- true only if the immediately previous round was a PvP win (5.2)
	units: { [number]: Unit },
	inventory: { [number]: Item },
	shop: Shop,
	overrides: { [string]: number }, -- per-player Config overrides (AUG-07, ECON-06)
	augments: { string }, -- chosen augment ids (AUG-08)
	seenAugments: { string }, -- every augment id this player has been shown, picked or not (D-61)
	augmentOffer: Offer?, -- pending offer (AUG-01, AUG-02)
	drops: { string }, -- the last component ids dropped to this player (ITM-11)
	rerollsThisRound: number, -- for free rerolls
	lastIncome: { [string]: any }?, -- the latest itemized income, shown by the UI for 2s (ECON-02)
	lostLastPvp: boolean, -- true only if the round just played was a PvP loss
	nextUid: number,
}

export type MoveDest = { kind: "bench", index: number } | { kind: "board", cell: Grid.Cell }
export type Result = { ok: boolean, reason: string? }

local PlayerState = {}

-- Creates a fresh player at match start (level 1, full health, empty bench).
function PlayerState.new(userId: number, name: string): State
	return {
		userId = userId,
		name = name,
		gold = 0,
		xp = 0,
		level = 1,
		health = GameConfig.playerHealth,
		streak = { kind = "none", length = 0 },
		wonLastPvp = false,
		lostLastPvp = false,
		augments = {},
		seenAugments = {},
		augmentOffer = nil,
		drops = {},
		rerollsThisRound = 0,
		units = {},
		inventory = {},
		shop = { slots = {}, locked = false },
		overrides = {},
		nextUid = 1,
	}
end

-- Reads a config value with this player's override applied (ECON-06).
function PlayerState.cfg(state: State, key: string, default: number): number
	return state.overrides[key] or default
end

-- Returns a fresh id unique within this player's units and items.
function PlayerState.newUid(state: State): number
	local uid = state.nextUid
	state.nextUid += 1
	return uid
end

-- All units sorted by uid, for deterministic iteration.
function PlayerState.sortedUnits(state: State): { Unit }
	local list: { Unit } = {}
	for _, u in state.units do
		table.insert(list, u)
	end
	table.sort(list, function(a, b)
		return a.uid < b.uid
	end)
	return list
end

-- Number of units currently on the board (LVL-01).
function PlayerState.boardCount(state: State): number
	local n = 0
	for _, u in state.units do
		if u.board then
			n += 1
		end
	end
	return n
end

-- Unit on a bench slot, or nil.
function PlayerState.benchOccupant(state: State, index: number): Unit?
	for _, u in state.units do
		if u.bench == index then
			return u
		end
	end
	return nil
end

-- Unit on a board cell, or nil.
function PlayerState.boardOccupant(state: State, cell: Grid.Cell): Unit?
	for _, u in state.units do
		if u.board and u.board.col == cell.col and u.board.row == cell.row then
			return u
		end
	end
	return nil
end

-- Lowest open bench slot, or nil if the bench is full.
function PlayerState.firstOpenBench(state: State): number?
	for i = 1, GameConfig.benchSlots do
		if not PlayerState.benchOccupant(state, i) then
			return i
		end
	end
	return nil
end

-- Registers a new unit. Pass `bench` or `board` to place it; omit both for an unplaced unit.
function PlayerState.newUnit(state: State, defId: string, star: number, bench: number?, board: Grid.Cell?): Unit
	local unit: Unit = { uid = PlayerState.newUid(state), defId = defId, star = star, bench = bench, board = board }
	state.units[unit.uid] = unit
	return unit
end

-- Registers a new item in the inventory (unequipped).
function PlayerState.newItem(state: State, itemId: string): Item
	local item: Item = { uid = PlayerState.newUid(state), itemId = itemId }
	state.inventory[item.uid] = item
	return item
end

-- Items equipped on a unit, sorted by uid.
function PlayerState.itemsOn(state: State, unitUid: number): { Item }
	local list: { Item } = {}
	for _, item in state.inventory do
		if item.equippedTo == unitUid then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.uid < b.uid
	end)
	return list
end

-- Moves a unit to a bench slot or board cell; swaps with an occupant (BRD-03).
-- Rejects a board entry when the board is at the level cap, unless it is a swap (BRD-04).
-- Phase and ownership checks belong to ActionRouter (BRD-02).
function PlayerState.moveUnit(state: State, uid: number, dest: MoveDest): Result
	local unit = state.units[uid]
	if not unit then
		return { ok = false, reason = "UnknownUnit" }
	end

	local occupant: Unit?
	if dest.kind == "bench" then
		if dest.index < 1 or dest.index > GameConfig.benchSlots then
			return { ok = false, reason = "OutOfBounds" }
		end
		occupant = PlayerState.benchOccupant(state, dest.index)
	else
		if not Grid.inBounds(dest.cell, GameConfig.boardColumns, GameConfig.boardRows) then
			return { ok = false, reason = "OutOfBounds" }
		end
		occupant = PlayerState.boardOccupant(state, dest.cell)
	end

	if occupant == unit then
		return { ok = true }
	end
	if occupant == nil and dest.kind == "board" and unit.board == nil and PlayerState.boardCount(state) >= state.level then
		return { ok = false, reason = "BoardFull" } -- BRD-04
	end

	local fromBoard, fromBench = unit.board, unit.bench
	if occupant then
		occupant.board, occupant.bench = fromBoard, fromBench
	end
	if dest.kind == "bench" then
		unit.bench, unit.board = dest.index, nil
	else
		unit.board, unit.bench = { col = dest.cell.col, row = dest.cell.row }, nil
	end
	return { ok = true }
end

return PlayerState
