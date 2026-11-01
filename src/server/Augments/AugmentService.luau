--!strict
-- Augment offers and picks (GDD 10; AUG-01 to AUG-08, rarity per D-59). Offers and follow-up choices are kept in
-- state.augmentOffer. Numbers come from GameConfig and the augments' data params.

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Augments = require(Shared.Data.Augments)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local EconomyService = require(script.Parent.Parent.Economy.EconomyService)
local InventoryService = require(script.Parent.Parent.Items.InventoryService)
local Registry = require(script.Parent.Parent.Effects.Registry)

type Rng = { nextInt: (any, number, number) -> number, pick: (any, { any }) -> any, shuffle: (any, { any }) -> { any } }

local byId: { [string]: Types.AugmentDef } = {}
for _, a in Augments do
	byId[a.id] = a
end

local RARITIES = { "Bronze", "Silver", "Gold" }
local MAX_ATTEMPTS = 200

local AugmentService = {}

-- Rolls the rarity of a whole offer from the configured weights (equal: 1/3 each, D-59).
local function rollRarity(rng: Rng): string
	local weights = GameConfig.augmentRarityWeights
	local total = 0
	for _, rarity in RARITIES do
		total += weights[rarity]
	end
	local roll = rng:nextInt(1, total)
	for _, rarity in RARITIES do
		roll -= weights[rarity]
		if roll <= 0 then
			return rarity
		end
	end
	return RARITIES[1]
end

-- Augments of a rarity that the player does not own and that are not in `avoid` (AUG-04).
local function candidates(state: PlayerState.State, rarity: string, avoid: { string }): { string }
	local list = {}
	for _, a in Augments do
		if a.rarity == rarity and not table.find(state.augments, a.id) and not table.find(avoid, a.id) then
			table.insert(list, a.id)
		end
	end
	return list
end

local function allSamePrimary(choices: { string }): boolean
	for i = 2, #choices do
		if byId[choices[i]].categories[1] ~= byId[choices[1]].categories[1] then
			return false
		end
	end
	return true
end

-- Three distinct choices of one rarity that do not all share a primary category (AUG-04), or nil.
local function pickThree(state: PlayerState.State, rarity: string, rng: Rng, avoid: { string }): { string }?
	local pool = candidates(state, rarity, avoid)
	if #pool < GameConfig.augmentChoices then
		return nil
	end
	for _ = 1, MAX_ATTEMPTS do
		local shuffled = rng:shuffle(pool)
		local choices = {}
		for i = 1, GameConfig.augmentChoices do
			choices[i] = shuffled[i]
		end
		if not allSamePrimary(choices) then
			return choices
		end
	end
	return nil
end

-- Rolls the offer's rarity (or keeps `rarity`) and three choices of it. If that rarity cannot fill an
-- offer it falls through to the next one. `avoid` keeps a reroll from repeating what was just shown
-- when there is any alternative.
local function rollOffer(state: PlayerState.State, rng: Rng, avoid: { string }, rarity: string?): (string, { string })
	local first = rarity or rollRarity(rng)
	local start = table.find(RARITIES, first) :: number
	for step = 0, #RARITIES - 1 do
		local r = RARITIES[(start - 1 + step) % #RARITIES + 1]
		-- Prefer augments never shown to this player, then ones not in `avoid`, then anything unowned.
		local fresh = table.clone(avoid)
		for _, id in state.seenAugments do
			table.insert(fresh, id)
		end
		local choices = pickThree(state, r, rng, fresh) or pickThree(state, r, rng, avoid) or pickThree(state, r, rng, {})
		if choices then
			return r, choices
		end
	end
	error("could not build a valid augment offer") -- the data test guarantees this cannot happen
end

-- Remembers that these augments were shown, so they are not offered to this player again if avoidable.
local function markSeen(state: PlayerState.State, ids: { string })
	for _, id in ids do
		if not table.find(state.seenAugments, id) then
			table.insert(state.seenAugments, id)
		end
	end
end

-- Rolls the rarity for one augment round. The match rolls it once so every player sees the same one.
function AugmentService.rollRarity(rng: Rng): string
	return rollRarity(rng)
end

-- Deals the offer for an augment round to a player (AUG-01). The rarity is rolled first and is the
-- same for all three choices. Pass `rarity` to share the round's rarity; without it this player rolls their own.
function AugmentService.deal(state: PlayerState.State, offer: number, rng: Rng, rarity: string?)
	local dealt, choices = rollOffer(state, rng, {}, rarity)
	state.augmentOffer = { kind = "augment", rarity = dealt, choices = choices, offer = offer, rerolled = false }
	markSeen(state, choices)
end

-- Replaces all 3 choices once per offer, free of charge (AUG-05). The rarity stays the same, so the
-- reroll changes which augments you see, not how rare they are.
function AugmentService.reroll(state: PlayerState.State, rng: Rng): PlayerState.Result
	local offer = state.augmentOffer
	if not offer or offer.kind ~= "augment" then
		return { ok = false, reason = "NoOffer" }
	end
	if offer.rerolled then
		return { ok = false, reason = "AlreadyRerolled" }
	end
	offer.rarity, offer.choices = rollOffer(state, rng, offer.choices, offer.rarity)
	markSeen(state, offer.choices)
	offer.rerolled = true
	return { ok = true }
end

-- Builds the helper table an augment's onPick uses. Gold goes through EconomyService (ECON-01);
-- Config changes go to this player's overrides only (AUG-07).
local function pickContext(state: PlayerState.State, params: { [string]: number }, rng: Rng): any
	local ctx: any = { player = state, params = params, rng = rng }
	ctx.addGold = function(amount: number)
		EconomyService.add(state, amount, "Augment")
	end
	ctx.grantComponent = function(itemId: string)
		InventoryService.addItem(state, itemId)
	end
	ctx.grantRandomComponents = function(count: number)
		InventoryService.dropComponents(state, count, rng)
	end
	ctx.grantRandomCombined = function(count: number)
		InventoryService.grantRandomCombined(state, count, rng)
	end
	ctx.setOverride = function(key: string, value: number)
		state.overrides[key] = value
	end
	ctx.addOverride = function(key: string, amount: number)
		state.overrides[key] = (state.overrides[key] or 0) + amount
	end
	-- Opens a follow-up choice: any one component, or one of `count` random combined items.
	ctx.offerChoice = function(kind: "component" | "combined", count: number?)
		local choices: { string }
		if kind == "component" then
			choices = table.clone(InventoryService.components)
		else
			choices = {}
			for _, id in rng:shuffle(InventoryService.combined) do
				if #choices < (count or 3) then
					table.insert(choices, id)
				end
			end
		end
		state.augmentOffer = { kind = kind, choices = choices, rerolled = true }
	end
	return ctx
end

-- Resolves the pending offer with the player's pick (AUG-02). Returns the chosen id on success.
function AugmentService.pick(state: PlayerState.State, index: number, rng: Rng): (PlayerState.Result, string?)
	local offer = state.augmentOffer
	if not offer then
		return { ok = false, reason = "NoOffer" }, nil
	end
	local id = offer.choices[index]
	if type(index) ~= "number" or not id then
		return { ok = false, reason = "BadArgs" }, nil
	end
	state.augmentOffer = nil
	if offer.kind == "augment" then
		table.insert(state.augments, id)
		local def = byId[id]
		local module = Registry.augments[id]
		if module.onPick then
			module.onPick(pickContext(state, def.params, rng))
		end
	else
		InventoryService.addItem(state, id)
	end
	return { ok = true }, id
end

-- When the timer ends the server picks the first choice (AUG-02), including follow-up choices.
function AugmentService.autoPick(state: PlayerState.State, rng: Rng)
	while state.augmentOffer do
		AugmentService.pick(state, 1, rng)
	end
end

return AugmentService
