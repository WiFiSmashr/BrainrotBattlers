--!strict
-- Phase 6 tests: augment offers (AUG-01..AUG-06), per-player overrides (AUG-07) and the effect of
-- each of the 24 launch augments (GDD 10.4).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Augments = require(Shared.Data.Augments)
local Units = require(Shared.Data.Units)
local Rng = require(Shared.Util.Rng)
local Index = require(Shared.Util.Index)
local PlayerState = require(Server.Player.PlayerState)
local AugmentService = require(Server.Augments.AugmentService)
local InventoryService = require(Server.Items.InventoryService)
local EconomyService = require(Server.Economy.EconomyService)
local ShopService = require(Server.Economy.ShopService)
local UnitPool = require(Server.Economy.UnitPool)
local MatchService = require(Server.Match.MatchService)
local CombatSim = require(Server.Combat.CombatSim)
local StatBlock = require(Server.Combat.StatBlock)
local EffectRunner = require(Server.Effects.EffectRunner)
local EffectRegistry = require(Server.Effects.Registry)
local AbilityRegistry = require(Server.Effects.Abilities.Registry)

local byId: { [string]: any } = {}
for _, a in Augments do
	byId[a.id] = a
end

local function newPlayer(id: number): any
	return PlayerState.new(id, "P" .. id)
end

local function itemCount(state: any): number
	local n = 0
	for _ in state.inventory do
		n += 1
	end
	return n
end

-- Stands in for choosing an augment from an offer; runs its onPick.
local function take(state: any, id: string, rng: any?)
	state.augmentOffer = { kind = "augment", choices = { id }, offer = 1, rerolled = false }
	local result = AugmentService.pick(state, 1, rng or Rng.new(1))
	assert(result.ok, "pick failed: " .. tostring(result.reason))
end

local function income(state: any, round: number?): any
	return EconomyService.calcIncome(state, round or 6, EffectRunner.incomeModifiers(state))
end

-- Combat helpers ------------------------------------------------------------------------------------
local function fighter(col: number, row: number, o: any?): any
	local opts = o or {}
	return {
		name = "F", defId = opts.defId or ("u" .. col .. row), cost = opts.cost, archetype = "Fighter", star = 1,
		cell = { col = col, row = row }, health = 100000, ad = 100, attackSpeed = 1.0,
		items = opts.items or {}, traits = opts.traits or {},
	}
end

local function foe(col: number, row: number, o: any?): any
	local spec = fighter(col, row, o)
	spec.health, spec.ad, spec.attackSpeed = 1000000, 1, 0.1
	return spec
end

local function newSim(home: { any }, away: { any }, homeInfo: any, awayInfo: any?): any
	local attach = EffectRunner.attach({ home = homeInfo, away = awayInfo or { gold = 0 } })
	return CombatSim.new({ seed = 1, home = home, away = away, customAbilities = AbilityRegistry, record = true, attach = attach })
end

local function stepFor(sim: any, seconds: number)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		if sim.result then
			return
		end
		CombatSim.step(sim)
	end
end

local function stat(u: any, name: string): number
	return StatBlock.get(u.stats[name])
end

local function isPrimaryDiverse(choices: { string }): boolean
	for i = 2, #choices do
		if byId[choices[i]].categories[1] ~= byId[choices[1]].categories[1] then
			return true
		end
	end
	return false
end

return function(t)
	-- Offers ----------------------------------------------------------------------------------------
	t.test("one rarity per offer, rolled first and shared by all 3 choices; 1/3 each at every stage (D-59)", function()
		local rng = Rng.new(11)
		for offer = 1, 3 do
			local counts = { Bronze = 0, Silver = 0, Gold = 0 }
			for _ = 1, 3000 do
				local s = newPlayer(1)
				AugmentService.deal(s, offer, rng)
				local choices = s.augmentOffer.choices
				t.eq(#choices, 3)
				local rarity = s.augmentOffer.rarity
				t.truthy(counts[rarity] ~= nil, "offer carries its rarity")
				for _, id in choices do
					t.eq(byId[id].rarity, rarity, "all choices share the offer's rarity")
				end
				counts[rarity] += 1
			end
			for rarity, n in counts do
				t.near(n / 3000 * 100, 100 / 3, 3.5, ("offer %d %s"):format(offer, rarity))
			end
		end
	end)

	t.test("3 distinct, unowned choices that do not all share a primary category (AUG-04)", function()
		local rng = Rng.new(21)
		for i = 1, 3000 do
			local s = newPlayer(1)
			for _ = 1, rng:nextInt(0, 2) do -- earlier picks must never be offered again
				local id = Augments[rng:nextInt(1, #Augments)].id
				if not table.find(s.augments, id) then
					table.insert(s.augments, id)
				end
			end
			AugmentService.deal(s, i % 3 + 1, rng)
			local choices = s.augmentOffer.choices
			t.eq(#choices, 3)
			t.truthy(choices[1] ~= choices[2] and choices[1] ~= choices[3] and choices[2] ~= choices[3], "distinct")
			for _, id in choices do
				t.truthy(not table.find(s.augments, id), "owned augment offered")
			end
			t.truthy(isPrimaryDiverse(choices), "all share one primary category")
		end
	end)

	t.test("one free reroll per offer replaces all 3 choices (AUG-05)", function()
		local rng = Rng.new(31)
		local s = newPlayer(1)
		AugmentService.deal(s, 2, rng)
		local before = table.clone(s.augmentOffer.choices)
		local rarity = s.augmentOffer.rarity
		t.eq(AugmentService.reroll(s, rng).ok, true)
		local after = s.augmentOffer.choices
		t.eq(#after, 3)
		t.truthy(isPrimaryDiverse(after))
		t.eq(s.augmentOffer.rarity, rarity, "a reroll keeps the offer's rarity")
		for _, id in after do
			t.eq(byId[id].rarity, rarity)
		end
		for _, id in after do
			t.truthy(not table.find(before, id), "reroll should show new augments when possible")
		end
		t.eq(s.gold, 0)
		t.eq(AugmentService.reroll(s, rng).reason, "AlreadyRerolled")
		t.eq(AugmentService.reroll(newPlayer(2), rng).reason, "NoOffer")
	end)

	t.test("picking validates, records the augment and clears the offer", function()
		local rng = Rng.new(41)
		local s = newPlayer(1)
		t.eq(AugmentService.pick(s, 1, rng).reason, "NoOffer")
		AugmentService.deal(s, 1, rng)
		local choices = table.clone(s.augmentOffer.choices)
		t.eq(AugmentService.pick(s, 4, rng).reason, "BadArgs")
		t.truthy(s.augmentOffer ~= nil, "a bad pick keeps the offer")
		local _, chosen = AugmentService.pick(s, 2, rng)
		t.eq(chosen, choices[2])
		t.eq(s.augments[1], choices[2])
		t.eq(s.augmentOffer == nil or s.augmentOffer.kind ~= "augment", true)
	end)

	t.test("when the timer ends the server picks the first choice, including follow-up choices (AUG-02)", function()
		local s = newPlayer(1)
		take(s, "starter_pack", Rng.new(1)) -- gives items, no follow-up
		local rng = Rng.new(51)
		AugmentService.deal(s, 1, rng)
		local first = s.augmentOffer.choices[1]
		AugmentService.autoPick(s, rng)
		t.truthy(table.find(s.augments, first) ~= nil)
		t.eq(s.augmentOffer, nil)
		local coupon = newPlayer(2)
		coupon.augmentOffer = { kind = "augment", choices = { "component_coupon" }, offer = 1, rerolled = false }
		AugmentService.autoPick(coupon, rng)
		t.eq(coupon.augmentOffer, nil)
		t.eq(itemCount(coupon), 1)
	end)

	t.test("offers appear at 2-1, 3-2 and 4-2 only, before the shop refreshes (AUG-01)", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 4, seed = 9, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(1, "P1")
		match:start()
		local offered: { [string]: boolean } = {}
		local choicesAtStart: { [string]: { string } } = {}
		match.events.phaseChanged:connect(function(info: any)
			if info.phase == "Prep" then
				local offer = match:getPlayer(1).augmentOffer
				offered[info.roundId] = offered[info.roundId] or offer ~= nil
				if offer then
					choicesAtStart[info.roundId] = table.clone(offer.choices)
				end
			end
		end)
		clock.t = 4000
		match:update()
		local rounds = 0
		for id, had in offered do
			rounds += 1
			t.eq(had, id == "2-1" or id == "3-2" or id == "4-2", "round " .. id)
		end
		t.truthy(rounds > 20)
		local s = match:getPlayer(1)
		t.eq(#s.augments, 3) -- the first choice was taken at the end of each of the three Preps (AUG-02)
		t.eq(s.augments[1], choicesAtStart["2-1"][1])
		t.eq(s.augments[3], choicesAtStart["4-2"][1])
	end)

	-- Economy augments -----------------------------------------------------------------------------------------
	t.test("Piggy Bank +8 gold; Venture Capital +20 gold and +2 each Prep", function()
		local s = newPlayer(1)
		take(s, "piggy_bank")
		t.eq(s.gold, 8)
		local v = newPlayer(2)
		take(v, "venture_capital")
		t.eq(v.gold, 20)
		local b = income(v)
		t.eq(b.extras[1].amount, 2)
		t.eq(b.total, 5 + 2 + 2) -- base 5, interest 2 on 20 gold, +2
	end)

	t.test("Side Hustle: +1 gold every Prep through the income breakdown (ECON-06)", function()
		local s = newPlayer(1)
		take(s, "side_hustle")
		local b = income(s)
		t.eq(#b.extras, 1)
		t.eq(b.extras[1].label, "Side Hustle")
		t.eq(b.total, 5 + 1)
	end)

	t.test("Compound Interest raises only this player's interest cap to 7 (AUG-07, ECON-06)", function()
		local a, b = newPlayer(1), newPlayer(2)
		take(a, "compound_interest")
		a.gold, b.gold = 80, 80
		t.eq(income(a).interest, 7)
		t.eq(income(b).interest, 5)
		t.eq(b.overrides.interestCap, nil)
		a.gold = 69
		t.eq(income(a).interest, 6)
	end)

	t.test("Winner's Purse: win bonus +3, a loss pays +1; other players unchanged", function()
		local a, b = newPlayer(1), newPlayer(2)
		take(a, "winners_purse")
		for _, p in { a, b } do
			EconomyService.recordRound(p, "pvp", "win")
		end
		t.eq(income(a).win, 3)
		t.eq(income(b).win, 1)
		for _, p in { a, b } do
			EconomyService.recordRound(p, "pvp", "loss")
		end
		t.eq(income(a).win, 1)
		t.eq(income(b).win, 0)
		for _, p in { a, b } do
			EconomyService.recordRound(p, "pve", "win")
		end
		t.eq(income(a).win, 0)
	end)

	t.test("Reroll Frenzy: the first 2 rerolls each round are free", function()
		local units = require(Shared.Data.Units)
		local pool, rng = UnitPool.new(units, 4), Rng.new(7)
		local a, b = newPlayer(1), newPlayer(2)
		take(a, "reroll_frenzy")
		a.gold, b.gold = 5, 5
		ShopService.reroll(a, pool, rng)
		ShopService.reroll(a, pool, rng)
		t.eq(a.gold, 5)
		ShopService.reroll(a, pool, rng)
		t.eq(a.gold, 3)
		a.rerollsThisRound = 0 -- a new Prep
		ShopService.reroll(a, pool, rng)
		t.eq(a.gold, 3)
		ShopService.reroll(b, pool, rng)
		ShopService.reroll(b, pool, rng)
		t.eq(b.gold, 1)
	end)

	t.test("Rich Kid Rampage: +10 gold now", function()
		local s = newPlayer(1)
		take(s, "rich_kid_rampage")
		t.eq(s.gold, 10)
	end)

	t.test("Gold-Plated Gear: +10 gold and a combined item now, +2 gold per combine (OnItemCombined)", function()
		local s = newPlayer(1)
		take(s, "gold_plated_gear", Rng.new(3))
		t.eq(s.gold, 10)
		t.eq(itemCount(s), 1)
		for _, item in s.inventory do
			t.eq(Index.item(item.itemId).kind, "Combined")
		end
		local a, b = InventoryService.addItem(s, "club"), InventoryService.addItem(s, "snack")
		local _, made = InventoryService.combine(s, a.uid, b.uid)
		EffectRunner.onItemCombined(s, made :: any)
		t.eq(s.gold, 12)
		local other = newPlayer(2)
		EffectRunner.onItemCombined(other, made :: any)
		t.eq(other.gold, 0)
	end)

	-- Item augments ---------------------------------------------------------------------------------------------
	t.test("Starter Pack gives 2 random components; Triple Threat gives 1", function()
		local s = newPlayer(1)
		take(s, "starter_pack", Rng.new(2))
		t.eq(itemCount(s), 2)
		for _, item in s.inventory do
			t.eq(Index.item(item.itemId).kind, "Component")
		end
		local u = newPlayer(2)
		take(u, "triple_threat", Rng.new(2))
		t.eq(itemCount(u), 1)
	end)

	t.test("Component Coupon: choose any 1 of the 6 components", function()
		local s = newPlayer(1)
		take(s, "component_coupon")
		t.eq(s.augmentOffer.kind, "component")
		t.eq(#s.augmentOffer.choices, 6)
		t.eq(AugmentService.reroll(s, Rng.new(1)).reason, "NoOffer")
		t.eq(AugmentService.pick(s, 4, Rng.new(1)).ok, true)
		t.eq(itemCount(s), 1)
		for _, item in s.inventory do
			t.eq(item.itemId, InventoryService.components[4])
		end
		t.eq(s.augmentOffer, nil)
	end)

	t.test("Anvil Delivery: choose 1 of 3 distinct random combined items", function()
		local s = newPlayer(1)
		take(s, "anvil_delivery", Rng.new(4))
		t.eq(s.augmentOffer.kind, "combined")
		local choices = s.augmentOffer.choices
		t.eq(#choices, 3)
		t.truthy(choices[1] ~= choices[2] and choices[2] ~= choices[3] and choices[1] ~= choices[3])
		for _, id in choices do
			t.eq(Index.item(id).kind, "Combined")
		end
		AugmentService.pick(s, 2, Rng.new(1))
		for _, item in s.inventory do
			t.eq(item.itemId, choices[2])
		end
	end)

	t.test("PvE Bounty: every PvE win drops 1 extra component, for this player only", function()
		local a, b = newPlayer(1), newPlayer(2)
		take(a, "pve_bounty")
		InventoryService.pveDrop(a, 1, Rng.new(1))
		InventoryService.pveDrop(b, 1, Rng.new(1))
		t.eq(itemCount(a), 2)
		t.eq(itemCount(b), 1)
		take(a, "pve_bounty") -- stacks if it were ever owned twice
		t.eq(a.overrides.pveExtraDrops, 2)
	end)

	t.test("Forge Master gives 2 random combined items", function()
		local s = newPlayer(1)
		take(s, "forge_master", Rng.new(6))
		t.eq(itemCount(s), 2)
		for _, item in s.inventory do
			t.eq(Index.item(item.itemId).kind, "Combined")
		end
	end)

	t.test("AD Enthusiast, Magic Mastery and Tank Trainer each give their component", function()
		for _, c in { { "ad_enthusiast", "club" }, { "magic_mastery", "wand" }, { "tank_trainer", "snack" } } do
			local s = newPlayer(1)
			take(s, c[1])
			t.eq(itemCount(s), 1)
			for _, item in s.inventory do
				t.eq(item.itemId, c[2])
			end
		end
	end)

	-- Combat augments -----------------------------------------------------------------------------------------------
	t.test("Thick Skin +120 Health for all allies only", function()
		local sim = newSim({ fighter(4, 4), fighter(3, 4) }, { foe(4, 4) }, { gold = 0, augments = { "thick_skin" } })
		t.near(stat(sim.byId[1], "maxHealth"), 100120)
		t.near(stat(sim.byId[2], "maxHealth"), 100120)
		t.near(sim.byId[1].health, 100120)
		t.near(stat(sim.byId[3], "maxHealth"), 1000000)
	end)

	t.test("Warm-Up +10% attack speed", function()
		local sim = newSim({ fighter(4, 4) }, { foe(4, 4) }, { gold = 0, augments = { "warm_up" } })
		t.near(stat(sim.byId[1], "attackSpeed"), 1.1, 1e-9)
		t.near(stat(sim.byId[2], "attackSpeed"), 0.1, 1e-9)
	end)

	t.test("Frontline Frenzy: front two rows get +25 Armor, +25 MR, +15% damage (both sides)", function()
		local rows = { fighter(1, 4), fighter(2, 3), fighter(3, 2), fighter(4, 1) }
		local sim = newSim(rows, { foe(4, 4) }, { gold = 0, augments = { "frontline_frenzy" } })
		for i, expected in { true, true, false, false } do
			t.near(stat(sim.byId[i], "armor"), if expected then 60 else 35, 1e-9, "home row " .. i)
			t.near(stat(sim.byId[i], "mr"), if expected then 55 else 30, 1e-9)
			t.near(stat(sim.byId[i], "damageAmp"), if expected then 0.15 else 0, 1e-9)
		end
		local away = newSim({ fighter(4, 4) }, { foe(1, 4), foe(2, 3), foe(3, 2), foe(4, 1) }, { gold = 0 }, { gold = 0, augments = { "frontline_frenzy" } })
		for i, expected in { true, true, false, false } do
			t.near(stat(away.byId[1 + i], "damageAmp"), if expected then 0.15 else 0, 1e-9, "away row " .. i)
		end
		t.near(stat(away.byId[1], "damageAmp"), 0)
	end)

	t.test("Team Spirit: +2% damage and damage reduction per active trait (max 20%)", function()
		local home = {}
		local col = 1
		for _, trait in { "brainrot", "noob", "rizzler" } do
			for k = 1, 2 do
				table.insert(home, fighter(col, 1, { defId = trait .. k, traits = { trait } }))
				col += 1
			end
		end
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "team_spirit" } })
		for i = 1, 6 do
			t.near(stat(sim.byId[i], "damageAmp"), 0.06, 1e-9)
			t.near(stat(sim.byId[i], "damageReduction"), 0.06, 1e-9)
		end
	end)

	t.test("Main Character Energy: highest-cost unit (ties: more items) gets +60% HP, +40% AD, +40 AP, 20% omnivamp", function()
		local home = { fighter(1, 4, { cost = 3 }), fighter(2, 4, { cost = 5 }), fighter(3, 4, { cost = 5, items = { "club" } }) }
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "main_character" } })
		t.near(stat(sim.byId[1], "maxHealth"), 100000)
		t.near(stat(sim.byId[2], "maxHealth"), 100000)
		local star = sim.byId[3]
		t.near(stat(star, "maxHealth"), 160000)
		t.near(stat(star, "ad"), (100 + 15) * 1.4, 1e-9)
		t.near(stat(star, "ap"), 140)
		t.near(stat(star, "omnivamp"), 0.2, 1e-9)
		t.near(star.health, 160000)
	end)

	t.test("Second Wind: first ally death heals all allies 25% and gives +30% AS for 5s, once per fight", function()
		local home = { fighter(1, 4), fighter(2, 4), fighter(3, 4) }
		local sim = newSim(home, { foe(7, 4) }, { gold = 0, augments = { "second_wind" } })
		sim.byId[2].health = 50000
		sim.byId[1].health = 0
		CombatSim.step(sim)
		t.near(sim.byId[2].health, 75000, 5)
		t.near(stat(sim.byId[2], "attackSpeed"), 1.3, 1e-9)
		t.near(stat(sim.byId[3], "attackSpeed"), 1.3, 1e-9)
		sim.byId[2].health = 0
		CombatSim.step(sim)
		t.near(stat(sim.byId[3], "attackSpeed"), 1.3, 1e-9) -- no second burst
		stepFor(sim, 5.2)
		t.near(stat(sim.byId[3], "attackSpeed"), 1.0, 1e-9)
	end)

	t.test("Hot Streak: +10% damage while on a streak of 2 or more", function()
		for _, c in { { 2, 0.10 }, { 5, 0.10 }, { 1, 0 }, { 0, 0 } } do
			local sim = newSim({ fighter(4, 4) }, { foe(4, 4) }, { gold = 0, streak = c[1], augments = { "hot_streak" } })
			t.near(stat(sim.byId[1], "damageAmp"), c[2], 1e-9, "streak " .. c[1])
		end
	end)

	t.test("Rich Kid Rampage: +1% damage per 10 gold held at combat start, max +10%", function()
		for _, c in { { 5, 0 }, { 55, 0.05 }, { 100, 0.10 }, { 900, 0.10 } } do
			local sim = newSim({ fighter(4, 4), fighter(3, 4) }, { foe(4, 4) }, { gold = c[1], augments = { "rich_kid_rampage" } })
			t.near(stat(sim.byId[1], "damageAmp"), c[2], 1e-9, "gold " .. c[1])
			t.near(stat(sim.byId[2], "damageAmp"), c[2], 1e-9)
		end
	end)

	t.test("AD Enthusiast: units holding any AD-tagged item deal +15% damage", function()
		local home = { fighter(1, 4, { items = { "giga_chonk" } }), fighter(2, 4, { items = { "wand" } }), fighter(3, 4, { items = { "chaos_wand" } }) }
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "ad_enthusiast" } })
		t.near(stat(sim.byId[1], "damageAmp"), 0.15, 1e-9)
		t.near(stat(sim.byId[2], "damageAmp"), 0, 1e-9)
		t.near(stat(sim.byId[3], "damageAmp"), 0.15, 1e-9)
	end)

	t.test("Magic Mastery: units holding any AP-tagged item gain +25 AP", function()
		local home = { fighter(1, 4, { items = { "wand" } }), fighter(2, 4, { items = { "club" } }) }
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "magic_mastery" } })
		t.near(stat(sim.byId[1], "ap"), 100 + 20 + 25)
		t.near(stat(sim.byId[2], "ap"), 100)
	end)

	t.test("Tank Trainer: units holding any Health-tagged item gain +10% max Health and +15 Armor", function()
		local home = { fighter(1, 4, { items = { "snack" } }), fighter(2, 4, { items = { "club" } }) }
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "tank_trainer" } })
		t.near(stat(sim.byId[1], "maxHealth"), (100000 + 150) * 1.10, 1e-6)
		t.near(stat(sim.byId[1], "armor"), 35 + 15)
		t.near(stat(sim.byId[2], "maxHealth"), 100000)
		t.near(stat(sim.byId[2], "armor"), 35)
	end)

	t.test("Triple Threat: units holding 3 items gain +20% Health, +15% damage, 15% damage reduction", function()
		local home = { fighter(1, 4, { items = { "club", "wand", "snack" } }), fighter(2, 4, { items = { "club", "wand" } }) }
		local sim = newSim(home, { foe(4, 4) }, { gold = 0, augments = { "triple_threat" } })
		t.near(stat(sim.byId[1], "maxHealth"), (100000 + 150) * 1.20, 1e-6)
		t.near(stat(sim.byId[1], "damageAmp"), 0.15, 1e-9)
		t.near(stat(sim.byId[1], "damageReduction"), 0.15, 1e-9)
		t.near(stat(sim.byId[2], "maxHealth"), 100000)
		t.near(stat(sim.byId[2], "damageAmp"), 0)
	end)

	t.test("augment effects detach cleanly at the end of a fight", function()
		local home = { fighter(1, 4, { items = { "club", "wand", "snack" } }), fighter(2, 4) }
		local ids = {}
		for _, a in Augments do
			table.insert(ids, a.id)
		end
		local sim = newSim(home, { foe(4, 4) }, { gold = 80, streak = 3, augments = ids })
		stepFor(sim, 2)
		EffectRunner.detachAll(sim)
		for _, u in sim.units do
			for name, block in u.stats do
				t.eq(#block.modifiers, 0, ("unit %d %s"):format(u.id, name))
			end
		end
	end)

	-- Registry -----------------------------------------------------------------------------------------------------
	t.test("every augment has an Effect module with its id and valid hooks (13.4)", function()
		local valid = { OnPrepStart = 1, OnIncomeCalc = 1, OnUnitBought = 1, OnItemCombined = 1, OnRoundEnd = 1, OnCombatStart = 1,
			OnTick = 1, OnAttack = 1, OnDamageDealt = 1, OnDamageTaken = 1, OnCast = 1, OnKill = 1, OnDeath = 1, OnCombatEnd = 1 }
		t.eq(#Augments, 24)
		for _, a in Augments do
			local module = EffectRegistry.augments[a.id]
			t.truthy(module, "no module for augment " .. a.id)
			t.eq(module.id, a.id)
			for hook in module.hooks or {} do
				t.truthy(valid[hook], a.id .. " uses unknown hook " .. hook)
			end
		end
		t.eq(#Units, 24)
	end)

	t.test("augment data matches GDD 10.4 numbers", function()
		local expect: { [string]: { [string]: number } } = {
			piggy_bank = { gold = 8 }, side_hustle = { income = 1 }, compound_interest = { interestCap = 7 },
			winners_purse = { winBonus = 3, lossBonus = 1 }, venture_capital = { gold = 20, income = 2 },
			reroll_frenzy = { freeRerolls = 2 }, thick_skin = { health = 120 }, warm_up = { attackSpeedPct = 0.10 },
			frontline_frenzy = { rows = 2, armor = 25, mr = 25, damage = 0.15 },
			team_spirit = { damagePerTrait = 0.02, reductionPerTrait = 0.02, max = 0.20 },
			main_character = { health = 0.60, ad = 0.40, ap = 40, omnivamp = 0.20 },
			second_wind = { healPct = 0.25, attackSpeedPct = 0.30, duration = 5 },
			starter_pack = { components = 2 }, component_coupon = { components = 1 }, anvil_delivery = { choices = 3 },
			pve_bounty = { extraDrops = 1 }, forge_master = { combinedItems = 2 }, ad_enthusiast = { damage = 0.15 },
			magic_mastery = { ap = 25 }, tank_trainer = { healthPct = 0.10, armor = 15 },
			triple_threat = { healthPct = 0.20, damage = 0.15, reduction = 0.15 },
			gold_plated_gear = { gold = 10, combinedItems = 1, goldPerCombine = 2 },
			rich_kid_rampage = { gold = 10, damagePerTen = 0.01, damageMax = 0.10 }, hot_streak = { minStreak = 2, damage = 0.10 },
		}
		local n = 0
		for id, params in expect do
			n += 1
			for key, value in params do
				t.near(byId[id].params[key], value, 1e-9, id .. " " .. key)
			end
		end
		t.eq(n, 24)
	end)

	t.test("every player gets the same rarity in an augment round; rarities vary between rounds (D-59)", function()
		local seen = { Bronze = 0, Silver = 0, Gold = 0 }
		for seed = 1, 12 do
			local clock = { t = 0 }
			local match = MatchService.new({
				lobbySize = 8, seed = seed, now = function() return clock.t end,
				combat = function(): any
					return { winner = "draw", survivors = 0, seconds = 5 }
				end,
			})
			for id = 1, 8 do
				match:addPlayer(id, "P" .. id)
			end
			match:start()
			local perRound: { [string]: { [string]: boolean } } = {}
			match.events.phaseChanged:connect(function(info: any)
				if info.phase == "Prep" then
					for id = 1, 8 do
						local offer = match:getPlayer(id).augmentOffer
						if offer then
							perRound[info.roundId] = perRound[info.roundId] or {}
							perRound[info.roundId][offer.rarity] = true
							for _, augmentId in offer.choices do
								t.eq(byId[augmentId].rarity, offer.rarity, "a choice differs from the offer's rarity")
							end
						end
					end
				end
			end)
			clock.t = 2500
			match:update()
			local rounds = 0
			for roundId, rarities in perRound do
				rounds += 1
				local count = 0
				for rarity in rarities do
					count += 1
					seen[rarity] += 1
				end
				t.eq(count, 1, ("seed %d round %s: players saw different rarities"):format(seed, roundId))
			end
			t.eq(rounds, 3)
		end
		for rarity, n in seen do
			t.truthy(n >= 4, rarity .. " should come up in some rounds: " .. n)
		end
	end)

	t.test("an augment never shows up twice for one player when the pool allows (D-61)", function()
		local rng = Rng.new(61)
		for _ = 1, 200 do
			local s = newPlayer(1)
			local shown: { [string]: boolean } = {}
			-- One Bronze, one Silver and one Gold round, each rerolled: 18 distinct augments fit the pools.
			for round, rarity in { "Bronze", "Silver", "Gold" } do
				AugmentService.deal(s, round, rng, rarity)
				for _, id in s.augmentOffer.choices do
					t.truthy(not shown[id], id .. " was shown twice")
					shown[id] = true
				end
				AugmentService.reroll(s, rng)
				for _, id in s.augmentOffer.choices do
					t.truthy(not shown[id], id .. " was shown twice after a reroll")
					shown[id] = true
				end
				AugmentService.pick(s, 1, rng)
				s.augmentOffer = nil
			end
		end
	end)

	t.test("when a rarity runs short, repeats of unpicked augments are allowed but owned ones never are", function()
		local rng = Rng.new(62)
		for _ = 1, 200 do
			local s = newPlayer(1)
			for round = 1, 3 do -- three Bronze rounds with rerolls need 18 of only 7 Bronze augments
				AugmentService.deal(s, round, rng, "Bronze")
				for _, id in s.augmentOffer.choices do
					t.truthy(not table.find(s.augments, id), "an owned augment was offered")
					t.eq(byId[id].rarity, "Bronze")
				end
				AugmentService.reroll(s, rng)
				for _, id in s.augmentOffer.choices do
					t.truthy(not table.find(s.augments, id), "an owned augment was offered after a reroll")
				end
				take(s, s.augmentOffer.choices[1], rng) -- own the first choice for real
				s.augmentOffer = nil
			end
			t.eq(#s.augments, 3)
		end
	end)

	t.test("players may own the same augment as each other; each still gets any augment only once (AUG-06)", function()
		local a, b = newPlayer(1), newPlayer(2)
		take(a, "piggy_bank")
		take(b, "piggy_bank")
		t.eq(a.augments[1], "piggy_bank")
		t.eq(b.augments[1], "piggy_bank")
		local rng = Rng.new(63)
		for _ = 1, 300 do
			for _, p in { a, b } do
				AugmentService.deal(p, 1, rng, "Bronze")
				t.truthy(not table.find(p.augmentOffer.choices, "piggy_bank"), "an owned augment was offered again")
			end
		end
	end)
end
