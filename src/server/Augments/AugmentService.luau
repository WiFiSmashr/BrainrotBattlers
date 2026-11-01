--!strict
-- Augment offers and picks (GDD 10; AUG-01 to AUG-08). Offers and follow-up choices are kept in
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

-- Rolls a rarity from an offer's weights (AUG-03).
local function rollRarity(weights: { [string]: number }, rng: Rng): string
	local roll = rng:nextInt(1, 100)
	for _, rarity in RARITIES do
		roll -= weights[rarity]
		if roll <= 0 then
			return rarity
		end
	end
	return "Bronze"
end

-- Augments of a rarity that the player does not own and that are not already in `taken` (AUG-04).
local function candidates(state: PlayerState.State, rarity: string, taken: { string }): { string }
	local list = {}
	for _, a in Augments do
		if a.rarity == rarity and not table.find(state.augments, a.id) and not table.find(taken, a.id) then
			table.insert(list, a.id)
		end
	end
	return list
end

-- One choice: roll the rarity, then pick an augment of that rarity; if that rarity is used up,
-- fall back to the other rarities in order.
local function rollChoice(state: PlayerState.State, weights: { [string]: number }, taken: { string }, rng: Rng): string?
	local rarity = rollRarity(weights, rng)
	local list = candidates(state, rarity, taken)
	if #list == 0 then
		for _, other in RARITIES do
			list = candidates(state, other, taken)
			if #list > 0 then
				break
			end
		end
	end
	return rng:pick(list) :: string?
end

local function allSamePrimary(choices: { string }): boolean
	for i = 2, #choices do
		if byId[choices[i]].categories[1] ~= byId[choices[1]].categories[1] then
			return false
		end
	end
	return true
end

-- Rolls 3 distinct, unowned choices that do not all share a primary category (AUG-03, AUG-04).
local function rollChoices(state: PlayerState.State, offer: number, rng: Rng, avoid: { string }?): { string }
	local weights = GameConfig.augmentRarityWeights[offer]
	for attempt = 1, MAX_ATTEMPTS do
		local choices: { string } = {}
		local taken: { string } = if avoid and attempt < MAX_ATTEMPTS // 2 then table.clone(avoid) else {}
		for _ = 1, GameConfig.augmentChoices do
			local id = rollChoice(state, weights, taken, rng)
			if id then
				table.insert(choices, id)
				table.insert(taken, id)
			end
		end
		if #choices == GameConfig.augmentChoices and not allSamePrimary(choices) then
			return choices
		end
	end
	error("could not build a valid augment offer") -- the data test guarantees this cannot happen
end

-- Deals the offer for an augment round to a player (AUG-01).
function AugmentService.deal(state: PlayerState.State, offer: number, rng: Rng)
	state.augmentOffer = { kind = "augment", choices = rollChoices(state, offer, rng, nil), offer = offer, rerolled = false }
end

-- Replaces all 3 choices once per offer, free of charge (AUG-05).
function AugmentService.reroll(state: PlayerState.State, rng: Rng): PlayerState.Result
	local offer = state.augmentOffer
	if not offer or offer.kind ~= "augment" then
		return { ok = false, reason = "NoOffer" }
	end
	if offer.rerolled then
		return { ok = false, reason = "AlreadyRerolled" }
	end
	offer.choices = rollChoices(state, offer.offer :: number, rng, offer.choices)
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
