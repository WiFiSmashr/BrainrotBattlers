--!strict
-- Phase 5 tests: 6 component stats and all 21 combined item effects (GDD 9.2, 9.4, ITM-04, ITM-05).
-- Expected numbers are written out from the GDD, not read from the data tables.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Items = require(Shared.Data.Items)
local Units = require(Shared.Data.Units)
local CombatSim = require(Server.Combat.CombatSim)
local StatBlock = require(Server.Combat.StatBlock)
local Statuses = require(Server.Combat.Statuses)
local EffectRunner = require(Server.Effects.EffectRunner)
local AbilityRegistry = require(Server.Effects.Abilities.Registry)

local function stat(u: any, name: string): number
	return StatBlock.get(u.stats[name])
end

-- Holder baseline: Health 100000, AD 100, AS 1.0, Armor 35, MR 30, AP 100, crit 0% / 140% (the default
-- 25% is removed so auto-attack numbers are exact).
local NO_CRIT = { stat = "critChance", kind = "flat", value = -0.25, sourceId = "no_crit" }

local function holder(items: { string }, o: any?): any
	local opts = o or {}
	return {
		name = "Holder", archetype = opts.archetype or "Fighter", star = 1, cell = { col = 4, row = 4 },
		health = 100000, ad = opts.ad or 100, attackSpeed = 1.0, items = items, ability = opts.ability,
		traits = {}, defId = "holder", modifiers = { NO_CRIT },
	}
end

-- Sturdy enemy next to the holder (arena cell 4,5). Slow attacker unless overridden.
local function foe(col: number, row: number, o: any?): any
	local opts = o or {}
	return {
		name = "Foe", archetype = "Fighter", star = 1, cell = { col = col, row = row }, health = 1000000,
		ad = opts.ad or 1, attackSpeed = opts.attackSpeed or 0.1, ability = opts.ability, defId = "foe" .. col .. row, traits = {}, modifiers = { NO_CRIT },
	}
end

local function newSim(home: { any }, away: { any }, after: ((any) -> ())?): any
	local effects = EffectRunner.attach({ home = { gold = 0 }, away = { gold = 0 } })
	return CombatSim.new({
		seed = 1, home = home, away = away, customAbilities = AbilityRegistry, record = true,
		attach = function(s: any)
			effects(s)
			if after then
				after(s)
			end
		end,
	})
end

local function stepFor(sim: any, seconds: number)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		if sim.result then
			return
		end
		CombatSim.step(sim)
	end
end

-- Steps until `count` Attack events by unit `id` exist (or `limit` seconds pass).
local function stepUntilAttacks(sim: any, id: number, count: number, limit: number?)
	local function attacks(): number
		local n = 0
		for _, ev in sim.events do
			if ev.e == "Attack" and ev.unit == id then
				n += 1
			end
		end
		return n
	end
	for _ = 1, math.floor((limit or 60) / 0.05) do
		if attacks() >= count or sim.result then
			return
		end
		CombatSim.step(sim)
	end
end

local function eventsOf(sim: any, kind: string): { any }
	local out = {}
	for _, ev in sim.events do
		if ev.e == kind then
			table.insert(out, ev)
		end
	end
	return out
end

local function forceChance(sim: any)
	local real = sim.rng
	local stub = setmetatable({
		chance = function() return true end,
		shuffle = function(_, list: { any }) return table.clone(list) end,
	}, { __index = real })
	stub._random = real._random
	sim.rng = stub
end

local SPARK = Units[2].ability -- Sleepy Sock, Snooze Barrage: 3 bolts of 60 magic

return function(t)
	t.test("component stats (9.2) and combined item stats are the sum of their parts (ITM-04)", function()
		-- stat -> baseline value for the holder above.
		local base = { maxHealth = 100000, ad = 100, ap = 100, attackSpeed = 1.0, armor = 35, mr = 30, critChance = 0, critDamage = 1.4 }
		local component = {
			club = { ad = 15 }, wand = { ap = 20 }, snack = { maxHealth = 150 },
			boots = { attackSpeed = 0.15 }, hoodie = { armor = 20 }, cape = { mr = 20 },
		}
		local function expected(ids: { string }): { [string]: number }
			local out = table.clone(base)
			for _, id in ids do
				for stat_, value in component[id] do
					if stat_ == "attackSpeed" then
						out[stat_] += value * base.attackSpeed -- +15% of the 1.0 baseline
					else
						out[stat_] += value
					end
				end
			end
			return out
		end
		local checked = 0
		for _, def in Items do
			local parts = if def.kind == "Component" then { def.id } else def.recipe :: { string }
			local want = expected(parts)
			if def.id == "mega_wand" then
				want.critChance += 0.10 -- its listed effect also grants +10% crit chance
			end
			local sim = newSim({ holder({ def.id }) }, { foe(4, 4) })
			for name, value in want do
				t.near(stat(sim.byId[1], name), value, 1e-6, def.id .. " " .. name)
			end
			checked += 1
		end
		t.eq(checked, 27)
	end)

	t.test("duplicate combined items stack stats but only one effect is active (ITM-05)", function()
		local sim = newSim({ holder({ "giga_chonk", "giga_chonk" }) }, { foe(4, 4) })
		t.near(stat(sim.byId[1], "ad"), 100 + 60)
		stepFor(sim, 2.2) -- three attacks: exactly one bonus hit, not two
		local fromHolder = 0
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 then
				fromHolder += 1
			end
		end
		t.eq(fromHolder, 3 + 1)
	end)

	t.test("Giga Chonk: every 3rd auto attack adds 100% of AD as physical damage", function()
		local sim = newSim({ holder({ "giga_chonk" }) }, { foe(4, 4) })
		stepFor(sim, 2.2)
		local byTime: { [string]: number } = {}
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 then
				local key = ("%.2f"):format(ev.t)
				byTime[key] = (byTime[key] or 0) + 1
			end
		end
		t.eq(byTime["0.05"], 1)
		t.eq(byTime["1.05"], 1)
		t.eq(byTime["2.05"], 2)
	end)

	t.test("Chaos Wand: auto attacks add magic damage equal to 30% of AP", function()
		local sim = newSim({ holder({ "chaos_wand" }) }, { foe(4, 4) })
		stepFor(sim, 0.1)
		local hits = {}
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 then
				table.insert(hits, ev)
			end
		end
		t.eq(#hits, 2)
		t.near(hits[1].amount, 115 * 100 / 135, 1e-6) -- physical auto: AD 100 + 15
		t.near(hits[2].amount, 0.3 * 120 * 100 / 130, 1e-6) -- AP 120 -> 36 magic vs 30 MR
		t.eq(hits[2].dtype, "Magic")
	end)

	t.test("Beefy Bat: heal 15% of physical auto-attack damage dealt", function()
		local sim = newSim({ holder({ "beefy_bat" }) }, { foe(4, 4) }, function(s)
			s.byId[1].health = 50000
		end)
		stepFor(sim, 0.06)
		-- +15 AD -> 115 vs 35 armor = 85.185 dealt, heal 12.78; the foe's opening hit costs 1.
		t.near(sim.byId[1].health, 50000 + 0.15 * 115 * 100 / 135 - 1, 1e-3)
	end)

	t.test("Turbo Slugger: +5% AS per attack on the same target (max 10); resets on a new target", function()
		local sim = newSim({ holder({ "turbo_slugger" }) }, { foe(4, 4), foe(3, 4) })
		stepUntilAttacks(sim, 1, 3)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.0 + 0.15 + 0.05 * 2, 1e-9)
		sim.byId[1].target = 3 -- switch to the other adjacent foe
		stepUntilAttacks(sim, 1, 4)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.15, 1e-9)
	end)

	t.test("Spike Hoodie: reflect 20% of auto-attack damage taken as magic", function()
		local sim = newSim({ holder({ "spike_hoodie" }) }, { foe(4, 4, { ad = 100 }) })
		stepFor(sim, 0.1)
		local taken = 100 * 100 / (100 + 55) -- armor 35 + 20
		local back
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 and ev.dtype == "Magic" then
				back = ev
			end
		end
		t.near(back.amount, 0.2 * taken * 100 / 130, 1e-6)
	end)

	t.test("Hex Breaker: auto attacks apply Wound for 5s", function()
		local sim = newSim({ holder({ "hex_breaker" }) }, { foe(4, 4) })
		stepFor(sim, 0.1)
		local wound = Statuses.active(sim.byId[2], "Wound", sim.time)
		t.truthy(wound ~= nil)
		t.near((wound :: any).expires - 0.05, 5, 0.01)
	end)

	t.test("Mega Wand: abilities can crit and the holder gains +10% crit chance", function()
		local spec = holder({ "mega_wand" }, { archetype = "Marksman", ability = SPARK })
		local sim = newSim({ spec }, { foe(4, 4) }, function(s)
			forceChance(s)
			s.byId[1].mana = s.byId[1].maxMana
		end)
		t.near(stat(sim.byId[1], "critChance"), 0.10, 1e-9)
		stepFor(sim, 1)
		local crits = 0
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 and ev.dtype == "Magic" and ev.crit then
				crits += 1
			end
		end
		t.eq(crits, 3)
	end)

	t.test("Gooey Heart: 15% max Health shield at start, heal 10% after casting", function()
		local spec = holder({ "gooey_heart" }, { archetype = "Marksman", ability = SPARK })
		local sim = newSim({ spec }, { foe(4, 4) }, function(s)
			s.byId[1].mana = s.byId[1].maxMana
			s.byId[1].health = 50000
		end)
		stepFor(sim, 0.1)
		local shield = eventsOf(sim, "Shield")[1]
		t.near(shield.amount, 100150 * 0.15, 1e-6)
		t.near(shield.duration, 8)
		stepFor(sim, 0.6)
		local heal
		for _, ev in eventsOf(sim, "Heal") do
			heal = ev
		end
		t.near(heal.amount, 100150 * 0.10, 1e-6)
	end)

	t.test("Spin Cycle: +6% AS every 2s, without limit", function()
		local sim = newSim({ holder({ "spin_cycle" }) }, { foe(4, 4) })
		stepFor(sim, 4.05)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.0 + 0.15 + 0.12, 1e-9)
		stepFor(sim, 20)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.0 + 0.15 + 0.06 * 12, 1e-9)
	end)

	t.test("Barrier Boba: first time below 50% Health, 200 shield for 4s scaled by AP", function()
		local sim = newSim({ holder({ "barrier_boba" }) }, { foe(4, 4) }, function(s)
			s.byId[1].health = 0.49 * 100000
		end)
		stepFor(sim, 0.15)
		local found
		for _, s in sim.byId[1].shields do
			found = s
		end
		t.near(found.amount, 200 * 120 / 100, 1.5) -- AP 100 + 20; the foe may chip 1
		t.near(found.expires - sim.time, 4, 0.2)
	end)

	t.test("Spell Sponge: first ability damage negated, then +15 mana per ability hit (1s cooldown)", function()
		local sim = newSim({ holder({ "spell_sponge" }) }, { foe(4, 4, { ability = SPARK }) }, function(s)
			s.byId[2].mana = s.byId[2].maxMana
		end)
		t.eq(sim.byId[1].counters.negateAbility, 1)
		stepFor(sim, 1.2)
		local magicHits = 0
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 2 and ev.dtype == "Magic" then
				magicHits += 1
			end
		end
		t.eq(magicHits, 2) -- 3 bolts, the first negated
		t.eq(sim.byId[1].counters.negateAbility, 0)
		-- 20 start mana + 15 (one ability-hit grant inside the 1s cooldown) + 3 per damaging hit.
		t.truthy(sim.byId[1].mana >= 20 + 15, "mana " .. sim.byId[1].mana)
	end)

	t.test("Titan Snack: regenerate 2% max Health per second", function()
		local sim = newSim({ holder({ "titan_snack" }) }, { foe(4, 4) }, function(s)
			s.byId[1].health = 50000
		end)
		stepFor(sim, 1.05)
		local heals = eventsOf(sim, "Heal")
		t.eq(#heals, 1)
		t.near(heals[1].amount, 100300 * 0.02, 1e-6)
		t.near(heals[1].t, 1.0, 0.06)
	end)

	t.test("Zoomie Gut: first time below 50% Health, +50% AS for the fight", function()
		local sim = newSim({ holder({ "zoomie_gut" }) }, { foe(4, 4) }, function(s)
			s.byId[1].health = 0.49 * 100000
		end)
		stepFor(sim, 0.1)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.0 + 0.15 + 0.5, 1e-9)
	end)

	t.test("Fortress Hoodie: adjacent allies gain +15 Armor and MR; others do not", function()
		local ally = holder({})
		ally.cell, ally.defId = { col = 3, row = 4 }, "ally"
		local distant = holder({})
		distant.cell, distant.defId = { col = 1, row = 1 }, "distant"
		local sim = newSim({ holder({ "fortress_hoodie" }), ally, distant }, { foe(4, 4) })
		stepFor(sim, 0.1)
		t.near(stat(sim.byId[2], "armor"), 35 + 15)
		t.near(stat(sim.byId[2], "mr"), 30 + 15)
		t.near(stat(sim.byId[3], "armor"), 35)
		t.near(stat(sim.byId[1], "armor"), 35 + 20) -- the holder keeps only its own hoodie
	end)

	t.test("Cleanse Flask: below 40% cleanse, heal 20%, 2s CC immunity", function()
		local sim = newSim({ holder({ "cleanse_flask" }) }, { foe(4, 4) }, function(s)
			s.byId[1].health = 0.39 * 100150
		end)
		sim:applyStatus(sim.byId[1], "Stun", 5, 0, sim.byId[2])
		stepFor(sim, 0.1)
		t.eq(Statuses.active(sim.byId[1], "Stun", sim.time), nil)
		local immune = Statuses.active(sim.byId[1], "CCImmune", sim.time)
		t.truthy(immune ~= nil)
		t.near((immune :: any).expires, 0.05 + 2, 0.01)
		t.truthy(sim.byId[1].health > 0.39 * 100150 + 0.19 * 100150)
		sim:applyStatus(sim.byId[1], "Stun", 1, 0, sim.byId[2])
		t.eq(Statuses.active(sim.byId[1], "Stun", sim.time), nil, "immune to new crowd control")
	end)

	t.test("Hyper Hyper: every 4th auto attack triggers 1 extra free attack that does not count", function()
		local sim = newSim({ holder({ "hyper_hyper" }) }, { foe(4, 4) })
		stepUntilAttacks(sim, 1, 8)
		stepFor(sim, 0.06) -- let the 8th attack's damage resolve
		local hits = 0
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 then
				hits += 1
			end
		end
		t.eq(hits, 8 + 2) -- extras after attack 4 and attack 8
	end)

	t.test("Zoom Plating: +3 Armor per auto attack, max 10 stacks", function()
		local sim = newSim({ holder({ "zoom_plating" }) }, { foe(4, 4) })
		stepUntilAttacks(sim, 1, 4)
		t.near(stat(sim.byId[1], "armor"), 35 + 20 + 12, 1e-9)
		stepUntilAttacks(sim, 1, 14, 120)
		t.near(stat(sim.byId[1], "armor"), 35 + 20 + 30, 1e-9)
	end)

	t.test("Sparkle Sneakers: every 4th auto attack chains 50% as magic to the 2 nearest other enemies", function()
		local sim = newSim({ holder({ "sparkle_sneakers" }) }, { foe(4, 4), foe(3, 4), foe(5, 4), foe(1, 1) })
		stepUntilAttacks(sim, 1, 4)
		stepFor(sim, 0.06)
		local chained = {}
		for _, ev in eventsOf(sim, "Damage") do
			if ev.source == 1 and ev.dtype == "Magic" then
				table.insert(chained, ev)
			end
		end
		t.eq(#chained, 2)
		t.near(chained[1].amount, 0.5 * (100 * 100 / 135) * 100 / 130, 1e-6) -- AD 100 vs 35 armor, then 30 MR
		t.truthy(chained[1].target ~= chained[2].target)
	end)

	t.test("Brick Wall: 20% less damage from auto attacks", function()
		local sim = newSim({ holder({ "brick_wall" }) }, { foe(4, 4, { ad = 100 }) })
		stepFor(sim, 0.1)
		local hit
		for _, ev in eventsOf(sim, "Damage") do
			if ev.target == 1 then
				hit = ev
				break
			end
		end
		t.near(hit.amount, 100 * 100 / (100 + 75) * 0.8, 1e-6) -- armor 35 + 40
	end)

	t.test("Drip Armor: 1.5% damage reduction per second of combat, max 30%", function()
		local sim = newSim({ holder({ "drip_armor" }) }, { foe(4, 4) })
		stepFor(sim, 10.1)
		t.near(stat(sim.byId[1], "damageReduction"), 0.15, 1e-9)
		stepFor(sim, 15)
		t.near(stat(sim.byId[1], "damageReduction"), 0.30, 1e-9)
	end)

	t.test("Void Cape: 20% less ability damage; reflect 40 magic to the caster (1s cooldown)", function()
		local sim = newSim({ holder({ "void_cape" }) }, { foe(4, 4, { ability = SPARK }) }, function(s)
			s.byId[2].mana = s.byId[2].maxMana
		end)
		stepFor(sim, 1.2)
		local bolt, reflects = nil, 0
		for _, ev in eventsOf(sim, "Damage") do
			if ev.target == 1 and ev.dtype == "Magic" and not bolt then
				bolt = ev
			end
			if ev.source == 1 and ev.dtype == "Magic" then
				reflects += 1
			end
		end
		t.near(bolt.amount, 60 * 100 / (100 + 70) * 0.8, 1e-6) -- MR 30 + 40
		t.eq(reflects, 1, "three bolts land together; only one reflect inside the cooldown")
	end)

	t.test("item data matches GDD 9.4 numbers", function()
		local byId: { [string]: any } = {}
		for _, def in Items do
			byId[def.id] = def
		end
		local expect: { [string]: { [string]: number } } = {
			giga_chonk = { everyN = 3, adRatio = 1 }, chaos_wand = { apRatio = 0.3 }, beefy_bat = { lifesteal = 0.15 },
			turbo_slugger = { asPerStack = 0.05, maxStacks = 10 }, spike_hoodie = { reflect = 0.2 }, hex_breaker = { duration = 5 },
			mega_wand = { critChance = 0.10 }, gooey_heart = { shieldPct = 0.15, shieldDuration = 8, healPct = 0.10 },
			spin_cycle = { interval = 2, asPerStep = 0.06 }, barrier_boba = { threshold = 0.5, shield = 200, duration = 4 },
			spell_sponge = { mana = 15, cooldown = 1 }, titan_snack = { regenPct = 0.02 }, zoomie_gut = { threshold = 0.5, asBonus = 0.5 },
			fortress_hoodie = { resist = 15 }, cleanse_flask = { threshold = 0.4, healPct = 0.2, immuneDuration = 2 },
			hyper_hyper = { everyN = 4 }, zoom_plating = { armorPerHit = 3, maxStacks = 10 },
			sparkle_sneakers = { everyN = 4, chainTargets = 2, damagePct = 0.5 }, brick_wall = { reduction = 0.2 },
			drip_armor = { perSecond = 0.015, max = 0.30 }, void_cape = { reduction = 0.2, reflect = 40, cooldown = 1 },
		}
		local n = 0
		for id, params in expect do
			n += 1
			for key, value in params do
				t.near(byId[id].params[key], value, 1e-9, id .. " " .. key)
			end
		end
		t.eq(n, 21)
	end)

	t.test("every combined item has an Effect module with matching id (13.4)", function()
		local registry = require(Server.Effects.Registry)
		for _, def in Items do
			if def.kind == "Combined" then
				local module = registry.items[def.id]
				t.truthy(module, "no module for item " .. def.id)
				t.eq(module.id, def.id)
			else
				t.eq(registry.items[def.id], nil, "components have stats only")
			end
		end
	end)
end
