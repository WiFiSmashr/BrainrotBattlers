--!strict
-- Phase 7 tests for what the interface depends on from the server: toast text for every rejection
-- reason (UI-05), the income record for the popup (ECON-02), mana in combat events (12.2 overlay)
-- and the touch-target minimum (UI-03). The panels themselves are checked by hand in Studio.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client"):WaitForChild("UI"):WaitForChild("Theme"))
local MatchService = require(Server.Match.MatchService)
local Snapshot = require(Server.Player.Snapshot)
local CombatSim = require(Server.Combat.CombatSim)
local AbilityRegistry = require(Server.Effects.Abilities.Registry)
local Units = require(Shared.Data.Units)

-- Every reason code the server services and ActionRouter can return.
local REASONS = {
	"NotEnoughGold", "BenchFull", "BoardFull", "EmptySlot", "WrongPhase", "UnknownUnit", "UnknownItem", "ItemEquipped",
	"NotEquipped", "UnitFull", "CannotCombine", "MaxLevel", "OutOfBounds", "NotYourTurn", "NoOffer", "AlreadyRerolled",
	"BadArgs", "RateLimited", "NotInMatch", "UnknownAction",
}

return function(t)
	t.test("every server rejection reason has a readable toast message (UI-05)", function()
		for _, code in REASONS do
			t.truthy(Theme.toastText[code], "no toast text for " .. code)
			t.truthy(#Theme.toastText[code] > 3)
		end
		t.truthy(Theme.toastText.NetworkError)
	end)

	t.test("touch targets are at least 44 reference pixels (UI-03)", function()
		t.eq(Theme.minTouch, 44)
		t.eq(Theme.referenceWidth, 1920)
		t.eq(Theme.referenceHeight, 1080)
		t.truthy(Theme.cell >= Theme.minTouch)
	end)

	t.test("unit rarity border colors cover costs 1 to 5 (2.3)", function()
		local seen = {}
		for cost = 1, 5 do
			local color = Theme.costColor(cost)
			t.truthy(color ~= nil)
			seen[tostring(color)] = true
		end
		local distinct = 0
		for _ in seen do
			distinct += 1
		end
		t.eq(distinct, 5)
		t.eq(Theme.rarityOfCost(1), "Common")
		t.eq(Theme.rarityOfCost(5), "Legendary")
	end)

	t.test("the snapshot carries the itemized income for the 2s popup, once per Prep (ECON-02)", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 2, seed = 5, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(1, "P1")
		match:start()
		clock.t = 3
		match:update()
		local first = Snapshot.build(match, 1).income
		t.eq(first.round, "1-1")
		t.eq(first.total, 0)
		clock.t = 33 -- into 1-2 Prep: base 2
		match:update()
		local second = Snapshot.build(match, 1).income
		t.eq(second.round, "1-2")
		t.eq(second.base, 2)
		t.eq(second.total, 2)
		t.eq(#second.extras, 0)
	end)

	t.test("the snapshot shows augments, offers and phase timing for the HUD (AUG-08, 12.2)", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 2, seed = 6, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(1, "P1")
		match:start()
		clock.t = 3
		match:update()
		local snap = Snapshot.build(match, 1)
		t.eq(snap.phase, "Prep")
		t.eq(snap.round, "1-1")
		t.near(snap.endsAt, 23)
		t.eq(snap.offer, nil)
		t.eq(snap.players[1].aug and #snap.players[1].aug, 0)
		match:getPlayer(1).augmentOffer = { kind = "augment", choices = { "piggy_bank", "warm_up", "starter_pack" }, offer = 1, rerolled = false }
		local withOffer = Snapshot.build(match, 1)
		t.eq(#withOffer.offer.choices, 3)
		t.eq(withOffer.offer.rerolled, false)
	end)

	t.test("combat events carry mana for the overlay bars; the roster has max mana", function()
		local units = {}
		for i = 1, 2 do
			local def = Units[i]
			table.insert(units, {
				name = def.name, defId = def.id, cost = def.cost, archetype = def.archetype, star = 1,
				cell = { col = 3 + i, row = 4 }, ability = def.ability,
			})
		end
		local foes = {
			{ name = "F", archetype = "Fighter", star = 1, cell = { col = 4, row = 4 }, health = 5000, ad = 20, attackSpeed = 1 },
		}
		local result = CombatSim.run({ seed = 3, home = units, away = foes, customAbilities = AbilityRegistry, record = true })
		t.truthy(#result.roster == 3)
		for _, desc in result.roster do
			t.truthy(desc.maxMana and desc.maxMana > 0)
			t.truthy(desc.mana ~= nil)
		end
		local attacks, damages = 0, 0
		for _, ev in result.events :: { any } do
			if ev.e == "Attack" then
				attacks += 1
				t.truthy(type(ev.mana) == "number")
			elseif ev.e == "Damage" then
				damages += 1
				t.truthy(type(ev.mana) == "number")
				t.truthy(type(ev.hp) == "number")
			end
		end
		t.truthy(attacks > 0 and damages > 0)
	end)

	t.test("item details list stats, recipe and effect for every item", function()
		local ItemText = require(Shared.Util.ItemText)
		local Index = require(Shared.Util.Index)
		local Items = require(Shared.Data.Items)
		t.eq(table.concat(ItemText.statLines(Index.item("club") :: any), "|"), "+15 Attack Damage")
		t.eq(table.concat(ItemText.statLines(Index.item("boots") :: any), "|"), "+15% Attack Speed")
		t.eq(table.concat(ItemText.statLines(Index.item("gooey_heart") :: any), "|"), "+150 Health|+20 Ability Power")
		t.eq(ItemText.recipe(Index.item("giga_chonk") :: any), "Chonky Club + Chonky Club")
		t.eq(ItemText.recipe(Index.item("club") :: any), nil)
		local giga = ItemText.describe(Index.item("giga_chonk") :: any)
		t.truthy(giga:find("Combined item") and giga:find("Made from") and giga:find("Every 3rd auto attack"))
		t.truthy(ItemText.describe(Index.item("wand") :: any):find("Component"))
		for _, def in Items do
			local text = ItemText.describe(def)
			t.truthy(#text > 10, def.id)
			if def.kind == "Combined" then
				t.truthy(text:find(def.description, 1, true), def.id .. " should show what it does")
			end
		end
	end)
end
