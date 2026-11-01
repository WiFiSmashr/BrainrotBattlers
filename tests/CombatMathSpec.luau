--!strict
-- Tests for BaseStats, StatBlock, Damage (GDD 7.3, 11.4, 11.6).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local BaseStats = require(Shared.Util.BaseStats)
local StatBlock = require(Server.Combat.StatBlock)
local Damage = require(Server.Combat.Damage)

local function target(health: number, armor: number?, mr: number?): any
	return { health = health, armor = armor or 0, mr = mr or 0, shields = {} }
end

-- Fake RNG so crit rolls are fixed.
local function rng(result: boolean): any
	return { chance = function(_self: any, _p: number): boolean return result end }
end

return function(t)
	t.test("Noodle Nugget check value (7.3)", function()
		local s = BaseStats.resolve(1, "Brawler", 1)
		t.near(s.health, 780)
		t.near(s.ad, 36)
		t.eq(s.armor, 45)
		t.eq(s.mr, 45)
		t.near(s.attackSpeed, 0.60)
		t.eq(s.range, 1)
		t.eq(s.startMana, 30)
		t.eq(s.maxMana, 80)
	end)

	t.test("star multiplier is 1.8 per star above 1 (MRG-04)", function()
		t.near(BaseStats.resolve(1, "Fighter", 2).health, 600 * 1.8)
		t.near(BaseStats.resolve(1, "Fighter", 3).ad, 45 * 3.24, 1e-6)
	end)

	t.test("StatBlock: flat, pct, mult order", function()
		local s = StatBlock.new(100)
		StatBlock.addModifier(s, "a", "flat", 20)
		StatBlock.addModifier(s, "b", "pct", 0.5)
		StatBlock.addModifier(s, "c", "mult", 2)
		t.near(StatBlock.get(s), (100 + 20) * 1.5 * 2)
	end)

	t.test("StatBlock: removeSource removes every modifier from that source", function()
		local s = StatBlock.new(100)
		StatBlock.addModifier(s, "x", "flat", 10)
		StatBlock.addModifier(s, "x", "pct", 0.1)
		StatBlock.addModifier(s, "y", "flat", 5)
		t.eq(StatBlock.removeSource(s, "x"), 2)
		t.near(StatBlock.get(s), 105)
	end)

	t.test("StatBlock: attack speed cap and armor floor", function()
		local as = StatBlock.new(1, nil, 5)
		StatBlock.addModifier(as, "s", "pct", 10)
		t.near(StatBlock.get(as), 5)
		local armor = StatBlock.new(10, 0, nil)
		StatBlock.addModifier(armor, "s", "flat", -50)
		t.near(StatBlock.get(armor), 0)
	end)

	t.test("Damage: armor mitigation", function()
		local tgt = target(1000, 100)
		local r = Damage.resolve({ amount = 100, damageType = "Physical", canCrit = false, target = tgt })
		t.near(r.dealt, 50)
		t.near(tgt.health, 950)
	end)

	t.test("Damage: magic resist mitigation", function()
		local tgt = target(1000, 0, 100)
		local r = Damage.resolve({ amount = 100, damageType = "Magic", canCrit = false, target = tgt })
		t.near(r.dealt, 50)
	end)

	t.test("Damage: true damage skips mitigation", function()
		local tgt = target(1000, 500, 500)
		local r = Damage.resolve({ amount = 100, damageType = "True", canCrit = false, target = tgt })
		t.near(r.dealt, 100)
	end)

	t.test("Damage: crit multiplies by crit damage", function()
		local tgt = target(1000)
		local r = Damage.resolve({
			amount = 100, damageType = "True", canCrit = true,
			attacker = { critChance = 0.5, critDamage = 1.4 }, target = tgt, rng = rng(true),
		})
		t.truthy(r.crit)
		t.near(r.dealt, 140)
	end)

	t.test("Damage: no crit when not eligible or roll fails", function()
		local a = Damage.resolve({
			amount = 100, damageType = "True", canCrit = false,
			attacker = { critChance = 1, critDamage = 2 }, target = target(1000), rng = rng(true),
		})
		t.near(a.dealt, 100)
		local b = Damage.resolve({
			amount = 100, damageType = "True", canCrit = true,
			attacker = { critChance = 0.5, critDamage = 2 }, target = target(1000), rng = rng(false),
		})
		t.near(b.dealt, 100)
	end)

	t.test("Damage: amp then separate reductions", function()
		local tgt: any = target(1000)
		tgt.reductions = { 0.2, 0.5 }
		local r = Damage.resolve({
			amount = 100, damageType = "True", canCrit = false, attacker = { damageAmp = 0.5 }, target = tgt,
		})
		t.near(r.dealt, 100 * 1.5 * 0.8 * 0.5)
	end)

	t.test("Damage: shields absorb oldest first, remainder hits health", function()
		local tgt: any = target(500)
		tgt.shields = { { amount = 30 }, { amount = 50 } }
		local r = Damage.resolve({ amount = 100, damageType = "True", canCrit = false, target = tgt })
		t.near(r.absorbed, 80)
		t.near(r.healthLost, 20)
		t.eq(#tgt.shields, 0)
		t.near(tgt.health, 480)
	end)

	t.test("Damage: partial shield keeps remainder", function()
		local tgt: any = target(500)
		tgt.shields = { { amount = 30 }, { amount = 50 } }
		Damage.resolve({ amount = 40, damageType = "True", canCrit = false, target = tgt })
		t.eq(#tgt.shields, 1)
		t.near(tgt.shields[1].amount, 40)
		t.near(tgt.health, 500)
	end)

	t.test("Damage: minimum damage is 1", function()
		local tgt = target(100, 1e6)
		local r = Damage.resolve({ amount = 1, damageType = "Physical", canCrit = false, target = tgt })
		t.near(r.dealt, 1)
		t.near(tgt.health, 99)
	end)

	t.test("Damage: kill is reported; immune takes nothing", function()
		local r = Damage.resolve({ amount = 500, damageType = "True", canCrit = false, target = target(100) })
		t.truthy(r.killed)
		local imm: any = target(100)
		imm.immune = true
		Damage.resolve({ amount = 500, damageType = "True", canCrit = false, target = imm })
		t.near(imm.health, 100)
	end)

	t.test("Damage.heal: Wound reduces by 33% and max health clamps", function()
		local tgt = target(100)
		t.near(Damage.heal(tgt, 100, 1000, true), 67)
		t.near(Damage.heal(tgt, 5000, 200, false), 33)
	end)
end
