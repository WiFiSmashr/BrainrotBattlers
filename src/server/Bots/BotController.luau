--!strict
-- Bots (GDD 4.7, BOT-01..BOT-03). Bots fill empty seats and act ONLY through the same ActionRouter
-- intents as humans, so they get no hidden bonuses (BOT-02): same rate limit, same phase checks.
-- BOT-03, first version: each Prep a bot places units front-line first by range, buys affordable
-- units that share a trait with its board, and buys XP when it holds 50 or more gold. It also takes
-- augment choices (the first one) and picks from the carousel instantly (CAR-03).
-- One intent per update() keeps a bot well under the 20-intents-per-second limit.

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Index = require(Shared.Util.Index)
local BaseStats = require(Shared.Util.BaseStats)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local CarouselService = require(script.Parent.Parent.Items.CarouselService)

local XP_THRESHOLD = 50 -- BOT-03: buy XP at this much gold or more
local BOARD_ROWS_FRONT_FIRST = { 4, 3, 2, 1 }
local BOARD_ROWS_BACK_FIRST = { 1, 2, 3, 4 }
local COLUMNS_CENTER_OUT = { 4, 3, 5, 2, 6, 1, 7 }

local BotController = {}
BotController.__index = BotController

-- True for bot user ids (humans have positive ids).
function BotController.isBot(userId: number): boolean
	return userId < 0
end

-- Fills every empty seat with a bot (BOT-01). Returns how many were added.
function BotController.fill(match: any): number
	local added = 0
	while #match.order < match.deps.lobbySize do
		added += 1
		match:addPlayer(-added, "Bot " .. added)
	end
	return added
end

-- Creates the controller for one match; `router` is the same ActionRouter humans use.
function BotController.new(match: any, router: any): any
	return setmetatable({ match = match, router = router, failed = {} :: { [number]: { [string]: boolean } }, stamp = {} :: { [number]: string } }, BotController)
end

-- Unit strength used to decide who plays: stars first, then cost.
local function score(unit: PlayerState.Unit): number
	local def = Index.unit(unit.defId)
	return unit.star * 10 + (if def then def.cost else 0)
end

-- Attack range of a unit, from its archetype (ranged units go to the back, melee to the front).
local function rangeOf(unit: PlayerState.Unit): number
	local def = Index.unit(unit.defId)
	return if def then BaseStats.resolve(def.cost, def.archetype, 1).range else 1
end

-- First free board cell, front rows first for melee units and back rows first for ranged ones.
local function freeCell(state: PlayerState.State, ranged: boolean): { col: number, row: number }?
	for _, row in (if ranged then BOARD_ROWS_BACK_FIRST else BOARD_ROWS_FRONT_FIRST) do
		for _, col in COLUMNS_CENTER_OUT do
			if not PlayerState.boardOccupant(state, { col = col, row = row }) then
				return { col = col, row = row }
			end
		end
	end
	return nil
end

-- Trait ids carried by units on the board.
local function boardTraits(state: PlayerState.State): { [string]: boolean }
	local set = {}
	for _, unit in state.units do
		local def = Index.unit(unit.defId)
		if unit.board and def then
			for _, id in def.traits do
				set[id] = true
			end
		end
	end
	return set
end

-- Sends one intent through the router. A rejected intent is remembered so it is not retried this Prep.
local function send(self: any, userId: number, name: string, args: any, key: string): boolean
	local result = self.router:handle(userId, name, args)
	if not result.ok then
		self.failed[userId][key] = true
	end
	return result.ok
end

-- Prep thinking: place, then buy, then maybe buy XP. Returns true if it sent an intent.
local function thinkPrep(self: any, userId: number, state: PlayerState.State): boolean
	local failed = self.failed[userId]
	local benchUnits, boardUnits = {}, {}
	for _, unit in PlayerState.sortedUnits(state) do
		table.insert(if unit.board then boardUnits else benchUnits, unit)
	end
	table.sort(benchUnits, function(a, b)
		return score(a) > score(b)
	end)

	-- Place: fill the board up to the level cap, then swap a better bench unit for the worst on board.
	if #benchUnits > 0 then
		local best = benchUnits[1]
		local key = "place" .. best.uid
		if #boardUnits < state.level and not failed[key] then
			local cell = freeCell(state, rangeOf(best) >= 2)
			if cell and send(self, userId, "MoveUnit", { unitUid = best.uid, dest = { kind = "board", col = cell.col, row = cell.row } }, key) then
				return true
			end
		elseif #boardUnits >= state.level and #boardUnits > 0 and not failed[key] then
			local worst = boardUnits[1]
			for _, unit in boardUnits do
				if score(unit) < score(worst) then
					worst = unit
				end
			end
			if score(best) > score(worst) then
				local board = worst.board :: { col: number, row: number }
				if send(self, userId, "MoveUnit", { unitUid = best.uid, dest = { kind = "board", col = board.col, row = board.row } }, key) then
					return true
				end
			end
		end
	end

	-- Buy affordable units that share a trait with the board (BOT-03).
	local traits = boardTraits(state)
	for slot = 1, #state.shop.slots do
		local defId = state.shop.slots[slot]
		local def = if type(defId) == "string" then Index.unit(defId) else nil
		local key = "buy" .. slot .. (defId or "")
		if def and state.gold >= def.cost and not failed[key] then
			local shares = next(traits) == nil
			for _, id in def.traits do
				shares = shares or traits[id] == true
			end
			if shares and send(self, userId, "BuyUnit", { slot = slot }, key) then
				return true
			end
		end
	end

	-- Buy XP when holding 50 or more gold (BOT-03).
	if state.gold >= XP_THRESHOLD and state.level < GameConfig.maxLevel and not failed.xp then
		return send(self, userId, "BuyXP", {}, "xp")
	end
	return false
end

-- Lets one bot take at most one action. Exposed so tests can drive a single bot.
function BotController.think(self: any, userId: number): boolean
	local match = self.match
	if not match:isAlive(userId) then
		return false
	end
	local state: PlayerState.State = match:getPlayer(userId)
	local stamp = match.info.id .. "|" .. match.phase
	if self.stamp[userId] ~= stamp then
		self.stamp[userId] = stamp
		self.failed[userId] = {} -- a new phase: forget earlier rejections
	end

	if match.phase == "Carousel" and match.carousel and CarouselService.currentPlayer(match.carousel) == userId then
		for index, offering in match.carousel.offerings do
			if not offering.pickedBy then
				return send(self, userId, "PickCarousel", { index = index }, "carousel")
			end
		end
	elseif match.phase == "Prep" then
		if state.augmentOffer then
			return send(self, userId, "PickAugment", { index = 1 }, "augment")
		end
		return thinkPrep(self, userId, state)
	end
	return false
end

-- Gives every living bot one chance to act. Call this every ~0.1 to 0.25 seconds.
function BotController.update(self: any)
	for _, userId in self.match:livingIds() do
		if BotController.isBot(userId) then
			BotController.think(self, userId)
		end
	end
end

return BotController
