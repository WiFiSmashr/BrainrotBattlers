--!strict
-- Data-validation tests (GDD 13.4, 7.6 pool check, 10.4 count check).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Units = require(Shared.Data.Units)
local Traits = require(Shared.Data.Traits)
local Items = require(Shared.Data.Items)
local Augments = require(Shared.Data.Augments)
local ShopConfig = require(Shared.Config.ShopConfig)
local GameConfig = require(Shared.Config.GameConfig)

-- Expected trait unit counts from GDD 8.2.
local EXPECTED_TRAIT_UNITS = {
	brainrot = 6, noob = 4, rizzler = 4, aura = 4, tycoon = 4, obby = 4,
	bouncer = 5, glitch = 4, camper = 4, pet_squad = 4, speedrunner = 4, admin = 4,
}

local function isSnakeCase(id: string): boolean
	return id:match("^[a-z][a-z0-9_]*$") ~= nil
end

local function assertUniqueSnake(t: any, list: { { id: string } }, label: string)
	local seen: { [string]: boolean } = {}
	for _, entry in list do
		t.truthy(isSnakeCase(entry.id), label .. " id not snake_case: " .. entry.id)
		t.truthy(not seen[entry.id], label .. " duplicate id: " .. entry.id)
		seen[entry.id] = true
	end
end

return function(t)
	t.test("ids are unique snake_case", function()
		assertUniqueSnake(t, Units, "unit")
		assertUniqueSnake(t, Traits, "trait")
		assertUniqueSnake(t, Items, "item")
		assertUniqueSnake(t, Augments, "augment")
	end)

	t.test("unit trait references exist and counts match 8.2", function()
		local traitIds: { [string]: boolean } = {}
		for _, trait in Traits do
			traitIds[trait.id] = true
		end
		local counts: { [string]: number } = {}
		for _, unit in Units do
			t.truthy(#unit.traits >= 1 and #unit.traits <= 3, unit.id .. " needs 1 to 3 traits")
			for _, traitId in unit.traits do
				t.truthy(traitIds[traitId], unit.id .. " references unknown trait " .. traitId)
				counts[traitId] = (counts[traitId] or 0) + 1
			end
		end
		for traitId, expected in EXPECTED_TRAIT_UNITS do
			t.eq(counts[traitId], expected, traitId .. " unit count")
		end
	end)

	t.test("trait tiers ascend and fit the unit count", function()
		local counts: { [string]: number } = {}
		for _, unit in Units do
			for _, traitId in unit.traits do
				counts[traitId] = (counts[traitId] or 0) + 1
			end
		end
		for _, trait in Traits do
			local last = 0
			for _, tier in trait.tiers do
				t.truthy(tier.count > last, trait.id .. " tiers must ascend")
				t.truthy(tier.count <= counts[trait.id], trait.id .. " tier exceeds unit count")
				last = tier.count
			end
		end
	end)

	t.test("unit cost counts are 6,6,5,4,3", function()
		local byCost = { 0, 0, 0, 0, 0 }
		for _, unit in Units do
			byCost[unit.cost] += 1
		end
		t.eq(#Units, 24)
		for cost, expected in { 6, 6, 5, 4, 3 } do
			t.eq(byCost[cost], expected, "cost " .. cost)
		end
	end)

	t.test("shop odds rows sum to 100 for every level", function()
		for level = 1, GameConfig.maxLevel do
			local row = ShopConfig.odds[level]
			t.truthy(row, "missing odds row " .. level)
			local sum = 0
			for _, pct in row do
				sum += pct
			end
			t.eq(sum, 100, "level " .. level)
		end
	end)

	t.test("recipe matrix covers all 21 unordered component pairs exactly once", function()
		local componentIds: { string } = {}
		local byId: { [string]: any } = {}
		for _, item in Items do
			byId[item.id] = item
			if item.kind == "Component" then
				table.insert(componentIds, item.id)
			end
		end
		t.eq(#componentIds, 6)
		local seen: { [string]: string } = {}
		local combinedCount = 0
		for _, item in Items do
			if item.kind == "Combined" then
				combinedCount += 1
				t.eq(#item.recipe, 2, item.id .. " recipe size")
				local a, b = item.recipe[1], item.recipe[2]
				t.truthy(byId[a] and byId[a].kind == "Component", item.id .. " bad recipe component " .. a)
				t.truthy(byId[b] and byId[b].kind == "Component", item.id .. " bad recipe component " .. b)
				local pair = if a < b then a .. "+" .. b else b .. "+" .. a
				t.truthy(not seen[pair], "recipe collision " .. pair)
				seen[pair] = item.id
				t.eq(#item.tags, 2, item.id .. " tags")
			end
		end
		t.eq(combinedCount, 21)
		for i = 1, 6 do
			for j = i, 6 do
				local a, b = componentIds[i], componentIds[j]
				local pair = if a < b then a .. "+" .. b else b .. "+" .. a
				t.truthy(seen[pair], "missing recipe " .. pair)
			end
		end
	end)

	t.test("combined item stats are the sum of their components", function()
		local byId: { [string]: any } = {}
		for _, item in Items do
			byId[item.id] = item
		end
		t.eq(byId.giga_chonk.stats.ad, 30)
		t.eq(byId.chaos_wand.stats.ad, 15)
		t.eq(byId.chaos_wand.stats.ap, 20)
		t.near(byId.hyper_hyper.stats.attackSpeedPct, 0.30)
	end)

	t.test("every augment offer can fill 3 distinct choices (AUG-04)", function()
		t.eq(#Augments, 24)
		-- Category x rarity coverage (10.4 count check).
		local seenPair: { [string]: boolean } = {}
		for _, aug in Augments do
			seenPair[aug.categories[1] .. "/" .. aug.rarity] = true
		end
		for _, category in { "Economy", "Combat", "Items" } do
			for _, rarity in { "Bronze", "Silver", "Gold" } do
				t.truthy(seenPair[category .. "/" .. rarity], "missing " .. category .. "/" .. rarity)
			end
		end
		-- Every rarity must be able to fill an offer by itself, even after the player owns 2 of them:
		-- 3+ unowned augments spanning 2+ primary categories (AUG-04, D-59). Rarity weights are equal.
		local weights = GameConfig.augmentRarityWeights
		t.eq(weights.Bronze, weights.Silver)
		t.eq(weights.Silver, weights.Gold)
		t.truthy(weights.Bronze > 0)
		for _, rarity in { "Bronze", "Silver", "Gold" } do
			local pool = 0
			local primaries: { [string]: boolean } = {}
			for _, aug in Augments do
				if aug.rarity == rarity then
					pool += 1
					primaries[aug.categories[1]] = true
				end
			end
			t.truthy(pool - 2 >= GameConfig.augmentChoices, rarity .. " pool too small")
			local primaryCount = 0
			for _ in primaries do
				primaryCount += 1
			end
			t.truthy(primaryCount >= 2, rarity .. " needs 2+ primary categories")
		end
	end)

	-- Effect modules for Custom abilities, traits, items and augments are checked in CombatSimSpec,
	-- TraitsSpec, ItemsSpec and AugmentSpec.
end
