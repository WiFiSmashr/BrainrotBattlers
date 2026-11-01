--!strict
-- Phase 5 tests: every trait tier from GDD 8.3 (numbers written out here, not read from data),
-- trait counting (TRT-01..03), and source removal (13.2).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Traits = require(Shared.Data.Traits)
local TraitCounter = require(Shared.Util.TraitCounter)
local CombatSim = require(Server.Combat.CombatSim)
local CombatRunner = require(Server.Combat.CombatRunner)
local StatBlock = require(Server.Combat.StatBlock)
local Statuses = require(Server.Combat.Statuses)
local EffectRunner = require(Server.Effects.EffectRunner)
local AbilityRegistry = require(Server.Effects.Abilities.Registry)
local EconomyService = require(Server.Economy.EconomyService)
local PlayerState = require(Server.Player.PlayerState)

local function stat(u: any, name: string): number
	return StatBlock.get(u.stats[name])
end

-- A plain fighter: big health, AD 100, AS 1.0 unless overridden. Armor 35, MR 30 from the archetype.
local function fighter(col: number, row: number, o: any?): any
	local opts = o or {}
	return {
		name = opts.name or "F", defId = opts.defId, archetype = opts.archetype or "Fighter", star = 1,
		cell = { col = col, row = row }, health = opts.health or 100000, ad = opts.ad or 100,
		attackSpeed = opts.attackSpeed or 1.0, ability = opts.ability, traits = opts.traits, items = opts.items,
		modifiers = opts.modifiers,
	}
end

-- A slow, sturdy enemy that barely hurts anyone.
local function enemy(col: number, row: number, o: any?): any
	local opts = o or {}
	opts.health = opts.health or 1000000
	opts.ad = opts.ad or 1
	opts.attackSpeed = opts.attackSpeed or 0.1
	return fighter(col, row, opts)
end

-- n units, each a different unit id, all carrying one trait.
local function traitUnits(trait: string, n: number, o: any?): { any }
	local list = {}
	for i = 1, n do
		local opts = table.clone(o or {})
		opts.defId, opts.traits = trait .. i, { trait }
		table.insert(list, fighter(i, 2, opts))
	end
	return list
end

local function newSim(home: { any }, away: { any }, o: any?): any
	local opts = o or {}
	local effects = EffectRunner.attach({ home = { gold = opts.gold or 0 }, away = { gold = 0 } })
	return CombatSim.new({
		seed = opts.seed or 1, home = home, away = away, customAbilities = AbilityRegistry, record = true,
		attach = function(s: any)
			effects(s)
			if opts.after then
				opts.after(s)
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

local function eventsOf(sim: any, kind: string): { any }
	local out = {}
	for _, ev in sim.events do
		if ev.e == kind then
			table.insert(out, ev)
		end
	end
	return out
end

-- Replaces the sim RNG so chance rolls always pass and shuffles keep their order.
local function forceChance(sim: any)
	local real = sim.rng
	local stub = setmetatable({
		chance = function() return true end,
		shuffle = function(_, list: { any }) return table.clone(list) end,
	}, { __index = real })
	stub._random = real._random
	sim.rng = stub
end

return function(t)
	-- Counting ------------------------------------------------------------------------------------
	t.test("trait counting: distinct unit ids only, highest tier only (TRT-01, TRT-02)", function()
		local entries = {
			{ defId = "a", traits = { "brainrot" } }, { defId = "a", traits = { "brainrot" } },
			{ defId = "b", traits = { "brainrot" } }, { defId = "c", traits = { "brainrot", "noob" } },
			{ defId = "d", traits = { "brainrot" } },
		}
		local counted = TraitCounter.count(entries)
		t.eq(counted.brainrot.count, 4)
		t.eq(counted.brainrot.tierIndex, 2) -- breakpoints 2 / 4 / 6: tier 4 is active, not 2 + 4
		t.eq(counted.brainrot.tier.count, 4)
		t.eq(counted.brainrot.nextCount, 6)
		t.eq(counted.noob.tierIndex, 0)
		t.eq(counted.noob.tier, nil)
		t.eq(counted.noob.nextCount, 2)
	end)

	t.test("bench units do not count; board units do (TRT-03)", function()
		local state = PlayerState.new(1, "T")
		PlayerState.newUnit(state, "noodle_nugget", 1, nil, { col = 1, row = 1 })
		PlayerState.newUnit(state, "newbie_knight", 1, 1, nil) -- bench
		EffectRunner.onRoundEnd(state, "win") -- only one Noob on the board: no tier, no growth
		for _, u in state.units do
			t.eq(u.growth, nil)
		end
		PlayerState.newUnit(state, "respawn_rascal", 1, nil, { col = 2, row = 1 })
		EffectRunner.onRoundEnd(state, "win")
		local grown = 0
		for _, u in state.units do
			if u.growth then
				grown += 1
			end
		end
		t.eq(grown, 2)
	end)

	-- Brainrot --------------------------------------------------------------------------------------
	t.test("Brainrot 2 / 4 / 6: stack interval, AS and AP per stack (8.3)", function()
		local cases = { { 2, 2.05, 1.02, 102 }, { 4, 1.55, 1.03, 103 }, { 6, 1.05, 1.04, 104 } }
		for _, c in cases do
			local sim = newSim(traitUnits("brainrot", c[1]), { enemy(4, 4) })
			stepFor(sim, c[2])
			local u = sim.byId[1]
			t.near(stat(u, "attackSpeed"), c[3], 1e-9, "AS tier " .. c[1])
			t.near(stat(u, "ap"), c[4], 1e-9, "AP tier " .. c[1])
			t.eq(u.counters.rot, 1)
		end
	end)

	t.test("Brainrot: max 10 stacks; at 6 units Full Rot gives +25% damage and random targets", function()
		local sim = newSim(traitUnits("brainrot", 6), { enemy(4, 4), enemy(3, 4), enemy(5, 4) })
		stepFor(sim, 10.1)
		local u = sim.byId[1]
		t.eq(u.counters.rot, 10)
		t.near(stat(u, "attackSpeed"), 1.4, 1e-9)
		t.near(stat(u, "ap"), 140, 1e-9)
		t.near(stat(u, "damageAmp"), 0.25, 1e-9)
		t.eq(u.counters.randomTarget, 1)
		local tier2 = newSim(traitUnits("brainrot", 2), { enemy(4, 4) })
		stepFor(tier2, 30)
		t.eq(tier2.byId[1].counters.rot, 10)
		t.near(stat(tier2.byId[1], "damageAmp"), 0)
		t.eq(tier2.byId[1].counters.randomTarget, nil)
	end)

	-- Noob ------------------------------------------------------------------------------------------
	t.test("Noob 2 / 4: +40 Health +4 AD, then +80 / +8 per round, max 25 gains (8.3)", function()
		local function boardOf(ids: { string }): any
			local state = PlayerState.new(1, "T")
			for i, id in ids do
				PlayerState.newUnit(state, id, 1, nil, { col = i, row = 1 })
			end
			return state
		end
		local two = boardOf({ "noodle_nugget", "newbie_knight" })
		EffectRunner.onRoundEnd(two, "win")
		local u2 = two.units[1]
		t.eq(u2.growth.health, 40)
		t.eq(u2.growth.ad, 4)
		EffectRunner.onRoundEnd(two, "loss")
		t.eq(u2.growth.health, 80)

		local four = boardOf({ "noodle_nugget", "newbie_knight", "respawn_rascal", "lootbox_lemur" })
		EffectRunner.onRoundEnd(four, "win")
		t.eq(four.units[1].growth.health, 80)
		t.eq(four.units[1].growth.ad, 8)

		for _ = 1, 40 do
			EffectRunner.onRoundEnd(two, "win")
		end
		t.eq(u2.growth.gains, 25)
		t.eq(u2.growth.health, 25 * 40)
	end)

	t.test("Noob growth is permanent and applied to the sim unit", function()
		local state = PlayerState.new(1, "T")
		local a = PlayerState.newUnit(state, "noodle_nugget", 1, nil, { col = 1, row = 1 })
		PlayerState.newUnit(state, "newbie_knight", 1, nil, { col = 2, row = 1 })
		EffectRunner.onRoundEnd(state, "win")
		state.units[2] = nil -- tier drops to none; growth must remain
		local team = CombatRunner.playerTeam(state)
		local sim = newSim(team, { enemy(4, 4) })
		t.near(stat(sim.byId[1], "maxHealth"), 780 + 40)
		t.near(stat(sim.byId[1], "ad"), 36 + 4)
		t.truthy(a.growth ~= nil)
	end)

	-- Rizzler ---------------------------------------------------------------------------------------
	t.test("Rizzler 2 / 3 / 4: closest 1 / 2 / 3 enemies charmed for 2 / 2.5 / 3s (8.3)", function()
		for _, c in { { 2, 1, 2 }, { 3, 2, 2.5 }, { 4, 3, 3 } } do
			local sim = newSim(traitUnits("rizzler", c[1]), { enemy(1, 4), enemy(2, 4), enemy(3, 4), enemy(4, 4), enemy(5, 4) })
			local charmed, expires = 0, 0
			for _, u in sim.units do
				local s = Statuses.active(u, "Charm", sim.time)
				if u.team == "away" and s then
					charmed += 1
					expires = s.expires
				end
			end
			t.eq(charmed, c[2], "tier " .. c[1])
			t.near(expires, c[3])
		end
	end)

	-- Aura ------------------------------------------------------------------------------------------
	t.test("Aura 2 / 3 / 4: +15 / 30 / 45 Armor and MR within 2 cells; death shield 150 / 250 / 400 (8.3)", function()
		for _, c in { { 2, 15, 150 }, { 3, 30, 250 }, { 4, 45, 400 } } do
			local home = {}
			local cells = { { 4, 4 }, { 5, 4 }, { 4, 3 }, { 5, 3 } }
			for i = 1, c[1] do
				table.insert(home, fighter(cells[i][1], cells[i][2], { defId = "aura" .. i, traits = { "aura" } }))
			end
			table.insert(home, fighter(4, 2, { defId = "near" })) -- 1 cell from an Aura unit
			table.insert(home, fighter(1, 1, { defId = "far" })) -- 3+ cells away
			local sim = newSim(home, { enemy(4, 4) })
			stepFor(sim, 0.1)
			local near, far = sim.byId[c[1] + 1], sim.byId[c[1] + 2]
			t.near(stat(near, "armor"), 35 + c[2])
			t.near(stat(near, "mr"), 30 + c[2])
			t.near(stat(far, "armor"), 35)
			-- Kill an Aura unit: every living ally gets the death shield.
			sim.byId[1].health = 0
			stepFor(sim, 0.1)
			t.near(near.shields[1].amount, c[3], 1e-9, "death shield tier " .. c[1])
			t.near(near.shields[1].expires - sim.time, 4, 0.2)
		end
	end)

	-- Tycoon ----------------------------------------------------------------------------------------
	t.test("Tycoon 2 / 3 / 4: +1 / 2 / 3 gold each Prep via OnIncomeCalc (8.3, ECON-06)", function()
		for _, c in { { { "moo_moo_mogul", "pocket_pharaoh" }, 1 }, { { "moo_moo_mogul", "pocket_pharaoh", "cash_cat" }, 2 },
			{ { "moo_moo_mogul", "pocket_pharaoh", "cash_cat", "lootbox_lemur" }, 3 } } do
			local state = PlayerState.new(1, "T")
			for i, id in c[1] do
				PlayerState.newUnit(state, id, 1, nil, { col = i, row = 1 })
			end
			local breakdown = EconomyService.calcIncome(state, 6, EffectRunner.incomeModifiers(state))
			t.eq(#breakdown.extras, 1)
			t.eq(breakdown.extras[1].amount, c[2])
			t.eq(breakdown.total, 5 + c[2])
		end
		local none = PlayerState.new(1, "T")
		PlayerState.newUnit(none, "moo_moo_mogul", 1, nil, { col = 1, row = 1 })
		t.eq(EconomyService.calcIncome(none, 6, EffectRunner.incomeModifiers(none)).total, 5)
	end)

	t.test("Tycoon 2 / 3 / 4: damage per 10 gold held, capped (8.3)", function()
		for _, c in { { 2, 0.01, 0.05 }, { 3, 0.02, 0.10 }, { 4, 0.03, 0.15 } } do
			local low = newSim(traitUnits("tycoon", c[1]), { enemy(4, 4) }, { gold = 25 })
			t.near(stat(low.byId[1], "damageAmp"), 2 * c[2], 1e-9, "25 gold")
			local high = newSim(traitUnits("tycoon", c[1]), { enemy(4, 4) }, { gold = 100 })
			t.near(stat(high.byId[1], "damageAmp"), c[3], 1e-9, "capped")
		end
	end)

	-- Obby ------------------------------------------------------------------------------------------
	t.test("Obby 2 / 3 / 4: first death respawns at the start cell with 30 / 45 / 60% Health (8.3)", function()
		for _, c in { { 2, 0.30, 0 }, { 3, 0.45, 0 }, { 4, 0.60, 1.5 } } do
			local sim = newSim(traitUnits("obby", c[1]), { enemy(4, 4) })
			local u = sim.byId[1]
			local start = { col = u.startCell.col, row = u.startCell.row }
			u.cell = { col = 7, row = 4 }
			u.health = 0
			CombatSim.step(sim)
			t.truthy(u.alive, "respawned")
			t.near(u.health, 100000 * c[2], 1e-6)
			t.eq(u.cell.col, start.col)
			t.eq(u.cell.row, start.row)
			t.truthy(Statuses.active(u, "Untargetable", sim.time) ~= nil)
			stepFor(sim, 2.1)
			t.eq(Statuses.active(u, "Untargetable", sim.time), nil)
			t.eq(Statuses.active(u, "Immune", sim.time) ~= nil, c[3] > 0, "immunity tier " .. c[1])
			u.health = 0
			CombatSim.step(sim)
			t.eq(u.alive, false, "only one respawn per fight")
		end
	end)

	-- Bouncer ---------------------------------------------------------------------------------------
	t.test("Bouncer 2 / 4 / 5: +20 / 40 / 60 Armor and MR, 10 / 20 / 30% shield, taunt 0 / 2 / 3s (8.3)", function()
		for _, c in { { 2, 20, 0.10, 0 }, { 4, 40, 0.20, 2 }, { 5, 60, 0.30, 3 } } do
			local home = traitUnits("bouncer", c[1])
			home[1].cell = { col = 4, row = 4 } -- front row, adjacent to the enemy at arena (4,5)
			local sim = newSim(home, { enemy(4, 4) })
			stepFor(sim, 0.1)
			local b = sim.byId[1]
			t.near(stat(b, "armor"), 35 + c[2])
			t.near(stat(b, "mr"), 30 + c[2])
			t.near(b.shields[1].amount, 100000 * c[3], 2) -- the enemy opener may chip 1 off
			t.near(b.shields[1].expires - 0.05, 6, 0.01)
			local foe = sim.byId[c[1] + 1]
			local taunt = Statuses.active(foe, "Taunt", 0.05)
			t.eq(taunt ~= nil, c[4] > 0, "taunt tier " .. c[1])
			if taunt then
				t.near(taunt.expires, c[4])
			end
		end
	end)

	-- Glitch ----------------------------------------------------------------------------------------
	t.test("Glitch 2 / 3 / 4: recast at 50 / 60 / 75% power; tier 4 freezes a random enemy 1s (8.3)", function()
		for _, c in { { 2, 0.50, false }, { 3, 0.60, false }, { 4, 0.75, true } } do
			local home = traitUnits("glitch", c[1])
			local caster = home[1]
			caster.archetype, caster.cost = "Marksman", 1
			caster.ability = require(Shared.Data.Units)[2].ability -- Sleepy Sock: 3 bolts of 60 magic
			caster.cell = { col = 4, row = 4 }
			local sim = newSim(home, { enemy(4, 4) }, { after = function(s: any)
				forceChance(s)
				s.byId[1].mana = s.byId[1].maxMana
			end })
			stepFor(sim, 1.2)
			local hits = {}
			for _, ev in eventsOf(sim, "Damage") do
				if ev.source == 1 and ev.dtype == "Magic" then
					table.insert(hits, ev.amount)
				end
			end
			t.eq(#hits, 6, "3 bolts + 3 recast bolts, tier " .. c[1])
			t.near(hits[4] / hits[1], c[2], 1e-9)
			local froze = false
			for _, ev in eventsOf(sim, "Status") do
				froze = froze or ev.status == "Freeze"
			end
			t.eq(froze, c[3])
		end
	end)

	-- Camper ----------------------------------------------------------------------------------------
	t.test("Camper 2 / 3 / 4: +6 / 9 / 12% damage per cell between, max 4; tier 4 +1 Range (8.3)", function()
		for _, c in { { 2, 0.06, 4 }, { 3, 0.09, 4 }, { 4, 0.12, 5 } } do
			local home = traitUnits("camper", c[1], { archetype = "Marksman" })
			home[1].cell = { col = 4, row = 4 }
			-- Enemy at own (4,1) -> arena (4,8): distance 4, so 3 cells lie between.
			local sim = newSim(home, { enemy(4, 1) })
			stepFor(sim, 0.2)
			t.near(stat(sim.byId[1], "damageAmp"), 3 * c[2], 1e-9, "tier " .. c[1])
			t.near(stat(sim.byId[1], "range"), c[3])
		end
	end)

	-- Pet Squad -------------------------------------------------------------------------------------
	t.test("Pet Squad 2 / 3 / 4: 1 / 2 / 3 Pets with 30 / 40 / 50% of the members' average stats (8.3)", function()
		for _, c in { { 2, 1, 0.30 }, { 3, 2, 0.40 }, { 4, 3, 0.50 } } do
			local home = traitUnits("pet_squad", c[1])
			home[1].health, home[1].ad = 2000, 40 -- members average (2000 + 3 x 100000?) is computed below
			local sim = newSim(home, { enemy(4, 4) })
			stepFor(sim, 0.1)
			local health, ad = 0, 0
			for i = 1, c[1] do
				health += stat(sim.byId[i], "maxHealth")
				ad += stat(sim.byId[i], "ad")
			end
			local pets = {}
			for _, u in sim.units do
				if u.counters.pet == 1 then
					table.insert(pets, u)
				end
			end
			t.eq(#pets, c[2], "pets at tier " .. c[1])
			t.near(pets[1].health, health / c[1] * c[3], 1e-6)
			t.near(stat(pets[1], "ad"), ad / c[1] * c[3], 1e-6)
			t.truthy(pets[1].isToken)
		end
	end)

	t.test("Pet Squad 4: Pets explode on death for 150 magic in 1 cell (8.3)", function()
		for _, c in { { 4, 150 * 100 / 130 }, { 3, 0 } } do
			-- Members hold their fire so only the pet explosion hurts the enemy.
			local sim = newSim(traitUnits("pet_squad", c[1], { attackSpeed = 0.05 }), { enemy(4, 4), enemy(7, 4) })
			stepFor(sim, 0.1)
			local pet
			for _, u in sim.units do
				if u.counters.pet == 1 then
					pet = u
					break
				end
			end
			local victim = sim.byId[c[1] + 1] -- first away unit
			victim.cell = { col = pet.cell.col, row = pet.cell.row + 1 }
			pet.health = 0
			stepFor(sim, 0.15)
			-- Only the explosion deals unsourced magic damage; other Pets may still land normal attacks.
			local exploded = 0
			for _, ev in eventsOf(sim, "Damage") do
				if ev.target == victim.id and ev.dtype == "Magic" and ev.source == nil then
					exploded += ev.amount
				end
			end
			t.near(exploded, c[2], 1e-6, "tier " .. c[1])
		end
	end)

	-- Speedrunner -----------------------------------------------------------------------------------
	t.test("Speedrunner 2 / 3 / 4: +20 / 35 / 50% crit chance; tier 4 +30% crit damage (8.3)", function()
		for _, c in { { 2, 0.45, 1.4 }, { 3, 0.60, 1.4 }, { 4, 0.75, 1.7 } } do
			local sim = newSim(traitUnits("speedrunner", c[1]), { enemy(4, 4) })
			t.near(stat(sim.byId[1], "critChance"), c[2], 1e-9, "tier " .. c[1])
			t.near(stat(sim.byId[1], "critDamage"), c[3], 1e-9)
		end
	end)

	t.test("Speedrunner: a kill grants +40% AS for 4s and resets the attack timer (8.3)", function()
		local home = traitUnits("speedrunner", 2)
		local sim = newSim(home, { enemy(4, 4, { health = 1 }), enemy(1, 1) })
		sim.byId[1].cell = { col = 4, row = 4 }
		stepFor(sim, 0.2)
		t.truthy(not sim.byId[3].alive)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.4, 1e-9)
		stepFor(sim, 4.2)
		t.near(stat(sim.byId[1], "attackSpeed"), 1.0, 1e-9)
	end)

	-- Admin -----------------------------------------------------------------------------------------
	t.test("Admin 2 / 3 / 4: a command every 8 / 6 / 4s, 1 / 1 / 2 commands, scaled by AP (8.3)", function()
		for _, c in { { 2, 8, false }, { 3, 6, false }, { 4, 4, true } } do
			local home = traitUnits("admin", c[1], { modifiers = { { stat = "ap", kind = "flat", value = 100, sourceId = "t" } } })
			local sim = newSim(home, { enemy(4, 4) }, { after = function(s: any)
				forceChance(s) -- shuffle keeps order: the first command is !heal, the second !freeze
				s.byId[1].health = 1000
			end })
			stepFor(sim, c[2] - 0.2)
			t.eq(#eventsOf(sim, "Heal"), 0, "nothing before the interval")
			stepFor(sim, 0.4)
			local heals = eventsOf(sim, "Heal")
			t.eq(#heals, 1)
			t.near(heals[1].amount, 100000 * 0.08 * 2, 1e-6, "heal scales with 200 AP")
			t.near(heals[1].t, c[2], 0.06)
			local froze = false
			for _, ev in eventsOf(sim, "Status") do
				froze = froze or ev.status == "Freeze"
			end
			t.eq(froze, c[3], "second command at tier 4")
		end
	end)

	-- Params and removal -----------------------------------------------------------------------------
	t.test("trait data matches GDD 8.3 tier numbers", function()
		local expect: { [string]: { { [string]: number } } } = {
			brainrot = { { interval = 2, asPerStack = 0.02, apPerStack = 2 }, { interval = 1.5, asPerStack = 0.03, apPerStack = 3 }, { interval = 1, asPerStack = 0.04, apPerStack = 4, fullRotDamage = 0.25 } },
			noob = { { health = 40, ad = 4, maxGains = 25 }, { health = 80, ad = 8 } },
			rizzler = { { targets = 1, duration = 2 }, { targets = 2, duration = 2.5 }, { targets = 3, duration = 3 } },
			aura = { { resist = 15, deathShield = 150 }, { resist = 30, deathShield = 250 }, { resist = 45, deathShield = 400 } },
			tycoon = { { gold = 1, damagePerTen = 0.01, damageMax = 0.05 }, { gold = 2, damagePerTen = 0.02, damageMax = 0.10 }, { gold = 3, damagePerTen = 0.03, damageMax = 0.15 } },
			obby = { { respawnHealth = 0.30 }, { respawnHealth = 0.45 }, { respawnHealth = 0.60, immunity = 1.5 } },
			bouncer = { { resist = 20, shieldPct = 0.10 }, { resist = 40, shieldPct = 0.20, tauntRadius = 2, tauntDuration = 2 }, { resist = 60, shieldPct = 0.30, tauntDuration = 3 } },
			glitch = { { recastChance = 0.25, recastPower = 0.50 }, { recastChance = 0.40, recastPower = 0.60 }, { recastChance = 0.50, recastPower = 0.75, freezeDuration = 1 } },
			camper = { { damagePerCell = 0.06, maxCells = 4 }, { damagePerCell = 0.09 }, { damagePerCell = 0.12, range = 1 } },
			pet_squad = { { pets = 1, statPct = 0.30 }, { pets = 2, statPct = 0.40 }, { pets = 3, statPct = 0.50, explosion = 150 } },
			speedrunner = { { critChance = 0.20, killAs = 0.40, killAsDuration = 4 }, { critChance = 0.35 }, { critChance = 0.50, critDamage = 0.30 } },
			admin = { { interval = 8, commands = 1 }, { interval = 6, commands = 1 }, { interval = 4, commands = 2 } },
		}
		for _, trait in Traits do
			local tiers = expect[trait.id]
			t.truthy(tiers, trait.id .. " missing from the expectation table")
			t.eq(#trait.tiers, #tiers, trait.id .. " tier count")
			for i, want in tiers do
				for key, value in want do
					t.near(trait.tiers[i].params[key], value, 1e-9, ("%s tier %d %s"):format(trait.id, i, key))
				end
			end
		end
	end)

	t.test("detaching removes every modifier every source added (13.2)", function()
		local home = {}
		for _, u in traitUnits("brainrot", 6) do
			u.items = { "spin_cycle", "zoom_plating", "fortress_hoodie" }
			table.insert(home, u)
		end
		for _, u in traitUnits("bouncer", 2) do
			u.cell.row = 3 -- keep clear of the Brainrot units on row 2
			table.insert(home, u)
		end
		local sim = newSim(home, { enemy(4, 4), enemy(5, 4) }, { gold = 60 })
		stepFor(sim, 6)
		local before = 0
		for _, u in sim.units do
			for _, block in u.stats do
				before += #block.modifiers
			end
		end
		t.truthy(before > 0, "effects added modifiers")
		EffectRunner.detachAll(sim)
		for _, u in sim.units do
			for name, block in u.stats do
				t.eq(#block.modifiers, 0, ("unit %d stat %s"):format(u.id, name))
			end
			t.eq(u.counters.randomTarget, nil)
		end
	end)

	t.test("every trait has an Effect module and every effect hook name is a real hook (13.4)", function()
		local registry = require(Server.Effects.Registry)
		local valid = { OnPrepStart = 1, OnIncomeCalc = 1, OnUnitBought = 1, OnItemCombined = 1, OnRoundEnd = 1, OnCombatStart = 1,
			OnTick = 1, OnAttack = 1, OnDamageDealt = 1, OnDamageTaken = 1, OnCast = 1, OnKill = 1, OnDeath = 1, OnCombatEnd = 1 }
		for _, trait in Traits do
			local module = registry.traits[trait.id]
			t.truthy(module, "no module for trait " .. trait.id)
			t.eq(module.id, trait.id)
			for hook in module.hooks or {} do
				t.truthy(valid[hook], trait.id .. " uses unknown hook " .. hook)
			end
		end
	end)

	t.test("CombatRunner.simulate with traits and items stays deterministic", function()
		local state = PlayerState.new(1, "T")
		state.gold = 40
		local ids = { "moo_moo_mogul", "pocket_pharaoh", "noodle_nugget", "cash_cat" }
		for i, id in ids do
			PlayerState.newUnit(state, id, 1, nil, { col = i, row = 4 })
		end
		PlayerState.newItem(state, "club").equippedTo = 1
		PlayerState.newItem(state, "giga_chonk").equippedTo = 1
		local fight = { kind = "pve", home = state, away = nil, monsters = 3, globalRound = 6, seed = 12 }
		local a, b = CombatRunner.simulate(fight, true), CombatRunner.simulate(fight, true)
		t.eq(a.winner, b.winner)
		t.near(a.seconds, b.seconds)
		t.eq(#a.replay.events, #b.replay.events)
	end)

end
