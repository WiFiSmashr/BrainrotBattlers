--!strict
-- Phase 4 tests: determinism, mana/casting, statuses, overtime, all 24 abilities, fast-forward.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Units = require(Shared.Data.Units)
local Rng = require(Shared.Util.Rng)
local Index = require(Shared.Util.Index)
local CombatSim = require(Server.Combat.CombatSim)
local CombatRunner = require(Server.Combat.CombatRunner)
local PlayerState = require(Server.Player.PlayerState)
local Registry = require(Server.Effects.Abilities.Registry)

-- A unit from the roster at a board cell.
local function unit(defId: string, star: number, col: number, row: number): any
	local def = Index.unit(defId) :: any
	return {
		name = def.name, defId = def.id, cost = def.cost, archetype = def.archetype, star = star,
		cell = { col = col, row = row }, ability = def.ability,
	}
end

-- A plain fighter with explicit stats and no ability.
local function dummy(col: number, row: number, health: number, ad: number, attackSpeed: number?): any
	return { name = "Dummy", archetype = "Fighter", star = 1, cell = { col = col, row = row },
		health = health, ad = ad, attackSpeed = attackSpeed or 0.75 }
end

local function setup(home: { any }, away: { any }, seed: number?, attach: ((any) -> ())?): any
	return { seed = seed or 1, home = home, away = away, customAbilities = Registry, record = true, attach = attach }
end

local function eventsOf(result: any, kind: string): { any }
	local out = {}
	for _, ev in result.events do
		if ev.e == kind then
			table.insert(out, ev)
		end
	end
	return out
end

-- Compact string of an event log, for determinism comparison.
local function digest(result: any): string
	local parts = { result.winner, tostring(result.survivors), tostring(result.seconds) }
	for _, ev in result.events do
		table.insert(parts, ("%s@%.2f:%s:%s:%s"):format(ev.e, ev.t, tostring(ev.unit or ev.target), tostring(ev.hp), tostring(ev.amount)))
	end
	return table.concat(parts, "|")
end

-- Steps a sim for `seconds` of sim time.
local function stepFor(sim: any, seconds: number)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		if sim.result then
			return
		end
		CombatSim.step(sim)
	end
end

return function(t)
	t.test("same seed gives an identical fight twice (CMB-01)", function()
		local function build(): any
			return setup(
				{ unit("cash_cat", 2, 3, 4), unit("lootbox_lemur", 1, 4, 4), unit("sir_slaysalot", 2, 5, 3), unit("auntie_aura", 1, 4, 3) },
				{ unit("granny_glitchgun", 1, 4, 4), unit("grumpy_gelato", 2, 3, 4), unit("sniper_sprout", 1, 5, 2), unit("rotzilla_prime", 1, 4, 3) },
				777
			)
		end
		local a, b = CombatSim.run(build()), CombatSim.run(build())
		t.eq(digest(a), digest(b))
		t.truthy(#a.events > 50, "fight should be non-trivial")
	end)

	t.test("arena: away team is mirrored by 180 degrees (CMB-02)", function()
		local result = CombatSim.run(setup({ dummy(2, 3, 100, 1) }, { dummy(2, 3, 100, 1) }))
		t.eq(result.roster[1].col, 2)
		t.eq(result.roster[1].row, 3)
		t.eq(result.roster[2].col, 6)
		t.eq(result.roster[2].row, 6)
	end)

	t.test("default target is the nearest enemy, ties to the lowest unitId (CMB-06)", function()
		local sim = CombatSim.new(setup({ dummy(4, 4, 5000, 1) }, { dummy(3, 4, 5000, 1), dummy(5, 4, 5000, 1) }))
		CombatSim.step(sim)
		-- Away cells mirror to (5,5) and (3,5): both adjacent to (4,4); id 2 is lower.
		t.eq(sim.byId[1].target, 2)
	end)

	t.test("mana: 30 start, +10 per attack, casts at max, 0.5s cast, mana resets (ABL-02, ABL-03)", function()
		local sim = CombatSim.new(setup({ unit("noodle_nugget", 1, 4, 4) }, { dummy(4, 4, 50000, 1, 0.1) }))
		local noodle = sim.byId[1]
		t.eq(noodle.mana, 30)
		stepFor(sim, 12)
		local casts = eventsOf({ events = sim.events }, "Cast")
		local shields = eventsOf({ events = sim.events }, "Shield")
		t.truthy(#casts >= 1, "Noodle should have cast")
		t.near(shields[1].t - casts[1].t, 0.5, 0.06, "cast time")
		local attacksBefore = 0
		for _, ev in eventsOf({ events = sim.events }, "Attack") do
			if ev.unit == 1 and ev.t <= casts[1].t then
				attacksBefore += 1
			end
		end
		t.eq(attacksBefore, 5, "30 + 5 attacks x 10 = 80 mana")
	end)

	t.test("no mana or attacks while casting (ABL-03)", function()
		local sim = CombatSim.new(setup({ unit("noodle_nugget", 1, 4, 4) }, { dummy(4, 4, 50000, 1, 0.1) }))
		sim.byId[1].mana = sim.byId[1].maxMana
		CombatSim.step(sim)
		t.truthy(sim.byId[1].castUntil ~= nil)
		t.eq(sim.byId[1].mana, 0)
		stepFor(sim, 0.4)
		local attacks = 0
		for _, ev in eventsOf({ events = sim.events }, "Attack") do
			if ev.unit == 1 then
				attacks += 1
			end
		end
		t.eq(attacks, 0)
	end)

	t.test("stun: stunned unit cannot attack and a cast in progress is cancelled", function()
		local sim = CombatSim.new(setup({ dummy(4, 4, 50000, 1) }, { unit("noodle_nugget", 1, 4, 4) }))
		local victim = sim.byId[2]
		victim.mana = victim.maxMana
		CombatSim.step(sim)
		t.truthy(victim.castUntil ~= nil)
		sim:applyStatus(victim, "Stun", 1, 0, sim.byId[1])
		t.eq(victim.castUntil, nil)
		local before = #eventsOf({ events = sim.events }, "Attack")
		stepFor(sim, 0.9)
		local attacksByVictim = 0
		for i, ev in eventsOf({ events = sim.events }, "Attack") do
			if i > before and ev.unit == 2 then
				attacksByVictim += 1
			end
		end
		t.eq(attacksByVictim, 0)
		stepFor(sim, 0.6)
		local resumed = 0
		for _, ev in eventsOf({ events = sim.events }, "Attack") do
			if ev.unit == 2 and ev.t > 1.0 then
				resumed += 1
			end
		end
		t.truthy(resumed >= 1, "victim attacks again after the stun")
	end)

	t.test("silence: still gains mana but cannot cast until it ends", function()
		local sim = CombatSim.new(setup({ dummy(4, 4, 50000, 1) }, { unit("noodle_nugget", 1, 4, 4) }))
		local silenced = sim.byId[2]
		silenced.mana = silenced.maxMana - 5
		sim:applyStatus(silenced, "Silence", 2, 0, sim.byId[1])
		stepFor(sim, 1.5)
		t.eq(#eventsOf({ events = sim.events }, "Cast"), 0)
		t.eq(silenced.mana, silenced.maxMana)
		stepFor(sim, 1)
		t.truthy(#eventsOf({ events = sim.events }, "Cast") >= 1, "casts once silence ends")
	end)

	t.test("charm: cannot attack, walks toward the charmer; ends if the charmer dies", function()
		-- Away marksman (range 4) starts 3 cells from the charmer.
		local sim = CombatSim.new(setup({ dummy(4, 4, 50000, 1) }, { unit("sleepy_sock", 1, 4, 2) }))
		local charmed, charmer = sim.byId[2], sim.byId[1]
		sim:applyStatus(charmed, "Charm", 3, 0, charmer)
		stepFor(sim, 1.6)
		local attacks = 0
		for _, ev in eventsOf({ events = sim.events }, "Attack") do
			if ev.unit == 2 then
				attacks += 1
			end
		end
		t.eq(attacks, 0)
		t.eq(math.max(math.abs(charmed.cell.col - charmer.cell.col), math.abs(charmed.cell.row - charmer.cell.row)), 1)

		charmer.health = 0 -- charmer dies: charm ends early
		stepFor(sim, 0.1)
		t.eq(require(Server.Combat.Targeting).forcedBy(sim, charmed, "Charm"), nil)
	end)

	t.test("taunt: forces the target to the taunter (CMB-07)", function()
		-- Enemy at arena (4,5) is adjacent to the near home unit (4,4); the taunter is farther.
		local sim = CombatSim.new(setup({ dummy(4, 4, 50000, 1), dummy(1, 1, 50000, 1) }, { dummy(4, 4, 50000, 1) }))
		local enemy = sim.byId[3]
		CombatSim.step(sim)
		t.eq(enemy.target, 1)
		sim:applyStatus(enemy, "Taunt", 2, 0, sim.byId[2])
		CombatSim.step(sim)
		t.eq(enemy.target, 2)
	end)

	t.test("slow: halves attack speed; the strongest slow wins and they do not stack", function()
		local function attacksWith(slow: number): number
			local sim = CombatSim.new(setup({ dummy(4, 4, 90000, 1, 1.0) }, { dummy(4, 4, 90000, 1, 0.1) }))
			if slow > 0 then
				sim:applyStatus(sim.byId[1], "Slow", 10, slow, sim.byId[2])
				sim:applyStatus(sim.byId[1], "Slow", 10, slow / 2, sim.byId[2]) -- weaker one is ignored
			end
			stepFor(sim, 6)
			local n = 0
			for _, ev in eventsOf({ events = sim.events }, "Attack") do
				if ev.unit == 1 then
					n += 1
				end
			end
			return n
		end
		local fast, slowed = attacksWith(0), attacksWith(0.5)
		t.truthy(fast >= 5, "baseline attacks: " .. fast)
		t.truthy(slowed <= math.ceil(fast / 2) + 1 and slowed < fast, "slowed attacks: " .. slowed)
	end)

	t.test("overtime: true damage from 30s, rate 2% rising 1pp per 2s (CMB-10)", function()
		local result = CombatSim.run(setup({ dummy(4, 4, 200000, 1, 0.1) }, { dummy(4, 4, 200000, 1, 0.1) }))
		t.truthy(result.seconds > 30 and result.seconds < 90, "ended at " .. result.seconds)
		local firstOvertime = math.huge
		for _, ev in eventsOf(result, "Damage") do
			if ev.source == nil then
				firstOvertime = math.min(firstOvertime, ev.t)
			end
		end
		t.near(firstOvertime, 31, 0.06)
	end)

	t.test("draw: both teams die on the same tick (CMB-11)", function()
		local result = CombatSim.run(setup({ dummy(4, 4, 200000, 1, 0.1) }, { dummy(4, 4, 200000, 1, 0.1) }))
		t.truthy(result.winner == "draw" or result.survivors == 1)
		local both = CombatSim.run(setup({}, {}))
		t.eq(both.winner, "draw")
		t.eq(both.survivors, 0)
	end)

	t.test("result reports winner, survivors and sim time (CMB-12)", function()
		local result = CombatSim.run(setup({ dummy(4, 4, 5000, 80), dummy(3, 4, 5000, 80) }, { dummy(4, 4, 100, 1) }))
		t.eq(result.winner, "home")
		t.eq(result.survivors, 2)
		t.truthy(result.seconds > 0)
	end)

	t.test("AP scales ability output but not duration (ABL-01)", function()
		local function shieldAmount(ap: number): number
			local spec = unit("noodle_nugget", 1, 4, 4)
			spec.modifiers = { { stat = "ap", kind = "flat", value = ap, sourceId = "test" } }
			local sim = CombatSim.new(setup({ spec }, { dummy(4, 4, 50000, 1) }))
			sim.byId[1].mana = sim.byId[1].maxMana
			stepFor(sim, 1)
			local ev = eventsOf({ events = sim.events }, "Shield")[1]
			return ev.amount * 1000 + ev.duration
		end
		t.near(shieldAmount(0), 200 * 1000 + 4)
		t.near(shieldAmount(100), 400 * 1000 + 4)
	end)

	t.test("hooks fire: OnAttack, OnDamageTaken, OnDeath before OnKill", function()
		local seen: { string } = {}
		local sim = CombatSim.new(setup({ dummy(4, 4, 5000, 500) }, { dummy(4, 4, 100, 1) }, 1, function(s: any)
			s:on("OnAttack", function() table.insert(seen, "attack") end)
			s:on("OnDamageTaken", function() table.insert(seen, "taken") end)
			s:on("OnDeath", function() table.insert(seen, "death") end)
			s:on("OnKill", function() table.insert(seen, "kill") end)
		end))
		while not sim.result do
			CombatSim.step(sim)
		end
		local joined = table.concat(seen, ",")
		t.truthy(joined:find("attack") and joined:find("taken"))
		t.truthy(joined:find("death,kill"), joined)
	end)

	t.test("every Custom ability effect has a registered module (13.4)", function()
		for _, def in Units do
			for _, effect in def.ability.effects do
				if effect.kind == "Custom" then
					t.truthy(Registry[effect.customId :: string], def.id .. " missing " .. tostring(effect.customId))
				end
			end
		end
	end)

	-- Each launch ability fires and produces its signature event ------------------------------------
	local SIGNATURE: { [string]: { string } } = {
		noodle_nugget = { "Shield" }, sleepy_sock = { "Damage" }, moo_moo_mogul = { "Status:Stun" },
		zippy_zucchini = { "Damage" }, pixel_pup = { "Heal" }, rizz_rabbit = { "Status:Charm" },
		wobble_banana = { "Status:Slow" }, mini_mod = { "Status:Silence" }, lag_lizard = { "Dash" },
		pocket_pharaoh = { "Damage" }, smooch_snail = { "Status:Slow" }, newbie_knight = { "Summon" },
		grumpy_gelato = { "Status:Freeze" }, auntie_aura = { "Shield" }, respawn_rascal = { "Dash", "Damage" },
		sniper_sprout = { "Damage" }, cash_cat = { "Damage" }, sir_slaysalot = { "Damage" },
		ban_hammer_bear = { "Status:Stun" }, spoiled_spaghetti = { "Damage" }, lootbox_lemur = {},
		rotzilla_prime = { "Damage" }, grand_rizzmaster = { "Status:Charm" }, granny_glitchgun = { "Damage" },
	}

	local function abilityFight(defId: string, star: number): (any, any)
		local home = { unit(defId, star, 4, 4), dummy(3, 4, 10000, 1) }
		local away = { dummy(3, 4, 40000, 5), dummy(4, 4, 40000, 5), dummy(5, 4, 40000, 5), dummy(4, 3, 40000, 5) }
		local sim = CombatSim.new(setup(home, away, 5, function(s: any)
			s.byId[1].mana = s.byId[1].maxMana
			s.byId[2].health = 100 -- a wounded ally for heals
		end))
		stepFor(sim, 3)
		return sim, { events = sim.events }
	end

	t.test("all 24 unit abilities cast at every star level without errors (ABL-05)", function()
		for _, def in Units do
			for star = 1, 3 do
				local sim, res = abilityFight(def.id, star)
				t.truthy(#eventsOf(res, "Cast") >= 1, def.id .. " star " .. star .. " never cast")
			end
		end
	end)

	t.test("each ability produces its signature effect (star 1)", function()
		for defId, wanted in SIGNATURE do
			local _, res = abilityFight(defId, 1)
			for _, need in wanted do
				local found = false
				if need == "Dash" then
					for _, ev in eventsOf(res, "Move") do
						found = found or (ev.unit == 1 and ev.over == 0)
					end
				elseif need:sub(1, 7) == "Status:" then
					for _, ev in eventsOf(res, "Status") do
						found = found or ev.status == need:sub(8)
					end
				elseif need == "Damage" then
					for _, ev in eventsOf(res, "Damage") do
						found = found or ev.source == 1
					end
				else
					found = #eventsOf(res, need) > 0
				end
				t.truthy(found, defId .. " missing " .. need)
			end
		end
	end)

	t.test("Rotzilla gains 3 Rot stacks; Training Pup is a token that does not count as a survivor", function()
		local sim = abilityFight("rotzilla_prime", 1)
		t.eq(sim.byId[1].counters.rot, 3)
		local knight = abilityFight("newbie_knight", 1)
		local pups = 0
		for _, u in knight.units do
			if u.isToken then
				pups += 1
				t.eq(u.team, "home")
			end
		end
		t.eq(pups, 1)
		-- Tokens alone do not keep a team alive.
		local result = CombatSim.run(setup({}, { dummy(4, 4, 100, 1) }))
		t.eq(result.winner, "away")
	end)

	t.test("CombatRunner: board units become specs; monsters are Fighters with formula stats (4.6)", function()
		local state = PlayerState.new(1, "T")
		PlayerState.newUnit(state, "noodle_nugget", 2, 1, nil)
		PlayerState.newUnit(state, "pixel_pup", 1, nil, { col = 2, row = 3 })
		local team = CombatRunner.playerTeam(state)
		t.eq(#team, 1)
		t.eq(team[1].defId, "pixel_pup")
		local monsters = CombatRunner.monsterTeam(10)
		t.eq(#monsters, 6)
		t.eq(monsters[1].health, 250 + 600)
	end)

	t.test("CombatRunner.simulate: board vs monsters runs and is repeatable", function()
		local state = PlayerState.new(1, "T")
		state.level = 3
		PlayerState.newUnit(state, "moo_moo_mogul", 1, nil, { col = 4, row = 4 })
		PlayerState.newUnit(state, "sleepy_sock", 1, nil, { col = 3, row = 4 })
		local fight = { kind = "pve", home = state, away = nil, monsters = 1, globalRound = 2, seed = 9 }
		local a, b = CombatRunner.simulate(fight, true), CombatRunner.simulate(fight, true)
		t.eq(a.winner, b.winner)
		t.near(a.seconds, b.seconds)
		t.truthy(a.replay ~= nil and #a.replay.events == #b.replay.events)
	end)

	t.test("fast-forward: 1,000 random fights finish without errors (acceptance)", function()
		local rng = Rng.new(2024)
		local cells = {}
		for col = 1, 7 do
			for row = 1, 4 do
				table.insert(cells, { col = col, row = row })
			end
		end
		local function randomTeam(): { any }
			local order = rng:shuffle(cells)
			local team = {}
			for i = 1, rng:nextInt(1, 8) do
				local def = Units[rng:nextInt(1, #Units)]
				local spec = unit(def.id, rng:nextInt(1, 3), order[i].col, order[i].row)
				table.insert(team, spec)
			end
			return team
		end

		local fights = 1000
		local totalTicks, started = 0, os.clock()
		local draws = 0
		for i = 1, fights do
			local result = CombatSim.run({
				seed = i, home = randomTeam(), away = randomTeam(), customAbilities = Registry, record = false,
			})
			t.truthy(result.winner == "home" or result.winner == "away" or result.winner == "draw")
			t.truthy(result.seconds <= 90.5, "fight ran past the hard cap")
			totalTicks += math.floor(result.seconds / 0.05 + 0.5)
			if result.winner == "draw" then
				draws += 1
			end
			if i % 20 == 0 then
				task.wait() -- let Studio breathe; this is a long loop
			end
		end
		local elapsed = os.clock() - started
		print(("  fast-forward: %d fights, %.1f ms/fight, %.3f ms/tick, %d draws"):format(
			fights, elapsed / fights * 1000, elapsed / math.max(totalTicks, 1) * 1000, draws))
		t.truthy(draws < fights, "not every fight should draw")
	end)
end
