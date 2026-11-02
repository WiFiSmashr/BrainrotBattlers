--!strict
-- Validates every client (and bot) intent, then dispatches it (GDD 3.5; ARCH-01).
-- Checks, in order: rate, known action, alive, phase, arguments, then ownership/affordability
-- inside the services. Always replies { ok, reason }.

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local PlayerState = require(script.Parent.PlayerState)
local LevelService = require(script.Parent.Parent.Economy.LevelService)
local ShopService = require(script.Parent.Parent.Economy.ShopService)
local InventoryService = require(script.Parent.Parent.Items.InventoryService)
local CarouselService = require(script.Parent.Parent.Items.CarouselService)
local AugmentService = require(script.Parent.Parent.Augments.AugmentService)

type Result = PlayerState.Result

local ActionRouter = {}
ActionRouter.__index = ActionRouter

-- Every action and the phases it is allowed in (BRD-02, ITM-02, CAR-06). The shop actions also work
-- during Combat, so players can keep buying, rerolling, levelling and locking while a fight plays
-- (D-58); the fight is already decided, and new units land on the bench.
local PREP = { Prep = true }
local SHOP_PHASES = { Prep = true, Combat = true }
local ACTION_PHASES: { [string]: { [string]: boolean } } = {
	BuyUnit = SHOP_PHASES, RerollShop = SHOP_PHASES, BuyXP = SHOP_PHASES, ToggleLock = SHOP_PHASES,
	-- During Combat (D-87): bench units can be rearranged and sold, items can be equipped and combined.
	MoveUnit = SHOP_PHASES, SellUnit = SHOP_PHASES,
	EquipItem = SHOP_PHASES, UnequipItem = PREP, CombineItems = SHOP_PHASES, PickAugment = PREP, RerollAugment = PREP,
	PickCarousel = { Carousel = true },
}

-- Creates a router bound to a match. `now` is the server clock in seconds.
function ActionRouter.new(match: any, now: () -> number): any
	return setmetatable({ match = match, now = now, recent = {} :: { [number]: { number } } }, ActionRouter)
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == math.floor(v)
end

-- Sliding one-second window per player (ARCH-01: max 20 intents per second).
local function rateLimited(self: any, userId: number): boolean
	local t = self.now()
	local list = self.recent[userId] or {}
	local kept = {}
	for _, stamp in list do
		if t - stamp < 1 then
			table.insert(kept, stamp)
		end
	end
	self.recent[userId] = kept
	if #kept >= GameConfig.maxIntentsPerSecond then
		return true
	end
	table.insert(kept, t)
	return false
end

-- Parses a MoveUnit destination into a PlayerState.MoveDest, or nil if malformed.
local function parseDest(dest: any): PlayerState.MoveDest?
	if type(dest) ~= "table" then
		return nil
	end
	if dest.kind == "bench" and isInt(dest.index) then
		return { kind = "bench", index = dest.index }
	elseif dest.kind == "board" and isInt(dest.col) and isInt(dest.row) then
		return { kind = "board", cell = { col = dest.col, row = dest.row } }
	end
	return nil
end

local BAD_ARGS: Result = { ok = false, reason = "BadArgs" }

local function dispatch(self: any, userId: number, state: PlayerState.State, name: string, args: any): Result
	local match = self.match
	if name == "BuyUnit" then
		if not isInt(args.slot) or args.slot < 1 or args.slot > ShopConfig.slots then
			return BAD_ARGS
		end
		local result = ShopService.buy(state, args.slot)
		if result.ok and result.unitUid then
			match:unitBought(state, result.unitUid) -- OnUnitBought
		end
		return { ok = result.ok, reason = result.reason }
	elseif name == "RerollShop" then
		return ShopService.reroll(state, match.pool, match.shopRng)
	elseif name == "BuyXP" then
		return LevelService.buyXp(state)
	elseif name == "ToggleLock" then
		ShopService.toggleLock(state)
		return { ok = true }
	elseif name == "MoveUnit" then
		local dest = parseDest(args.dest)
		if not isInt(args.unitUid) or not dest then
			return BAD_ARGS
		end
		if match.phase == "Combat" then
			-- Mid-fight only the bench can be rearranged: nothing is fielded or pulled off the board (D-87).
			local unit = state.units[args.unitUid]
			if dest.kind ~= "bench" or (unit and unit.board) then
				return { ok = false, reason = "NoFieldInCombat" }
			end
		end
		return PlayerState.moveUnit(state, args.unitUid, dest)
	elseif name == "SellUnit" then
		if not isInt(args.unitUid) then
			return BAD_ARGS
		end
		return ShopService.sell(state, args.unitUid, match.pool)
	elseif name == "EquipItem" then
		if not isInt(args.itemUid) or not isInt(args.unitUid) then
			return BAD_ARGS
		end
		return InventoryService.equip(state, args.itemUid, args.unitUid)
	elseif name == "UnequipItem" then
		if not isInt(args.itemUid) then
			return BAD_ARGS
		end
		return InventoryService.unequip(state, args.itemUid)
	elseif name == "CombineItems" then
		if not isInt(args.itemUidA) or not isInt(args.itemUidB) then
			return BAD_ARGS
		end
		local result, item = InventoryService.combine(state, args.itemUidA, args.itemUidB)
		if item then
			match:itemCombined(state, item) -- OnItemCombined
		end
		return result
	elseif name == "PickAugment" then
		if not isInt(args.index) then
			return BAD_ARGS
		end
		return (AugmentService.pick(state, args.index, match.rng))
	elseif name == "RerollAugment" then
		return AugmentService.reroll(state, match.rng)
	elseif name == "PickCarousel" then
		if not isInt(args.index) or not match.carousel then
			return BAD_ARGS
		end
		local result = CarouselService.pick(match.carousel, userId, args.index, self.now())
		return result
	end
	return { ok = false, reason = "UnknownAction" }
end

-- Handles one intent from `userId`. Rejections also raise a Toast event (UI-05).
function ActionRouter.handle(self: any, userId: number, name: any, args: any): Result
	local match = self.match
	local result: Result
	if rateLimited(self, userId) then
		result = { ok = false, reason = "RateLimited" }
	elseif type(name) ~= "string" or not ACTION_PHASES[name] then
		result = { ok = false, reason = "UnknownAction" }
	elseif not match:isAlive(userId) then
		result = { ok = false, reason = "NotInMatch" }
	elseif not ACTION_PHASES[name][match.phase] then
		result = { ok = false, reason = if name == "UnequipItem" and match.phase == "Combat" then "NoUnequipInCombat" else "WrongPhase" }
	else
		result = dispatch(self, userId, match:getPlayer(userId), name, if type(args) == "table" then args else {})
	end

	if result.ok then
		match.events.stateChanged:fire(userId)
		if name == "PickCarousel" then
			match:markAllDirty() -- everyone sees each pick live (CAR-04)
		end
	else
		match.events.toast:fire(userId, result.reason)
	end
	return result
end

return ActionRouter
