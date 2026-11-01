--!strict
-- When Prep ends, fills any free board slots from the bench so a player never fights short-handed by
-- accident (D-75). Takes bench units from the left (lowest slot first) until the board holds as many
-- units as the player's level allows. Melee units go to the front rows and ranged units to the back
-- rows, centre columns first.

local Shared = game:GetService("ReplicatedStorage").Shared
local Index = require(Shared.Util.Index)
local BaseStats = require(Shared.Util.BaseStats)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerState = require(script.Parent.PlayerState)
local LevelService = require(script.Parent.Parent.Economy.LevelService)

local ROWS_FRONT_FIRST = { 4, 3, 2, 1 }
local ROWS_BACK_FIRST = { 1, 2, 3, 4 }
local COLUMNS_CENTRE_OUT = { 4, 3, 5, 2, 6, 1, 7 }

local AutoPlace = {}

local function isRanged(unit: PlayerState.Unit): boolean
	local def = Index.unit(unit.defId)
	return def ~= nil and BaseStats.resolve(def.cost, def.archetype, 1).range >= 2
end

local function freeCell(state: PlayerState.State, ranged: boolean): { col: number, row: number }?
	for _, row in (if ranged then ROWS_BACK_FIRST else ROWS_FRONT_FIRST) do
		for _, col in COLUMNS_CENTRE_OUT do
			if not PlayerState.boardOccupant(state, { col = col, row = row }) then
				return { col = col, row = row }
			end
		end
	end
	return nil
end

-- Moves bench units onto the board, leftmost first, until the board is full. Returns how many moved.
function AutoPlace.fill(state: PlayerState.State): number
	local moved = 0
	for index = 1, GameConfig.benchSlots do
		if PlayerState.boardCount(state) >= LevelService.boardCap(state) then
			break
		end
		local unit = PlayerState.benchOccupant(state, index)
		if unit then
			local cell = freeCell(state, isRanged(unit))
			if cell and PlayerState.moveUnit(state, unit.uid, { kind = "board", cell = cell }).ok then
				moved += 1
			end
		end
	end
	return moved
end

return AutoPlace
