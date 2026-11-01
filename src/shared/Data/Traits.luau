--!strict
-- 12 launch traits (GDD 8.2, 8.3) [EXAMPLE]. All numbers live in tiers[].params (TRT-06).
-- Params use fractions for percentages (0.02 = 2%); durations are seconds.

local Types = require(script.Parent.Parent.Types)

local traits: { Types.TraitDef } = {
	{
		id = "brainrot", name = "Brainrot", kind = "Origin", scope = "members",
		description = "Rot stacks ramp speed and power; at 6 it turns chaotic.",
		tiers = {
			{ count = 2, params = { interval = 2, asPerStack = 0.02, apPerStack = 2, maxStacks = 10, fullRot = 0 }, description = "A Rot stack every 2s: +2% AS and +2 AP each. Max 10." },
			{ count = 4, params = { interval = 1.5, asPerStack = 0.03, apPerStack = 3, maxStacks = 10, fullRot = 0 }, description = "A stack every 1.5s: +3% AS and +3 AP each." },
			{ count = 6, params = { interval = 1, asPerStack = 0.04, apPerStack = 4, maxStacks = 10, fullRot = 1, fullRotDamage = 0.25 }, description = "A stack every 1s: +4% AS and +4 AP each. At 10 stacks: Full Rot, +25% damage but random targets." },
		},
	},
	{
		id = "noob", name = "Noob", kind = "Origin", scope = "members",
		description = "Permanent growth after every round fought.",
		tiers = {
			{ count = 2, params = { health = 40, ad = 4, maxGains = 25 }, description = "After each round, Noobs gain +40 Health and +4 AD for the match. Max 25 gains." },
			{ count = 4, params = { health = 80, ad = 8, maxGains = 25 }, description = "Gain +80 Health and +8 AD per round." },
		},
	},
	{
		id = "rizzler", name = "Rizzler", kind = "Origin", scope = "team",
		description = "Charms enemies at combat start.",
		tiers = {
			{ count = 2, params = { targets = 1, duration = 2 }, description = "The closest enemy is charmed for 2s." },
			{ count = 3, params = { targets = 2, duration = 2.5 }, description = "The 2 closest enemies are charmed for 2.5s." },
			{ count = 4, params = { targets = 3, duration = 3 }, description = "The 3 closest enemies are charmed for 3s." },
		},
	},
	{
		id = "aura", name = "Aura", kind = "Origin", scope = "team",
		description = "Proximity defense, plus a shield burst on Aura death.",
		tiers = {
			{ count = 2, params = { radius = 2, resist = 15, deathShield = 150, deathShieldDuration = 4 }, description = "Allies within 2 cells gain +15 Armor and MR. Aura death: 150 shield for all allies." },
			{ count = 3, params = { radius = 2, resist = 30, deathShield = 250, deathShieldDuration = 4 }, description = "+30 Armor and MR. Death shield 250." },
			{ count = 4, params = { radius = 2, resist = 45, deathShield = 400, deathShieldDuration = 4 }, description = "+45 Armor and MR. Death shield 400." },
		},
	},
	{
		id = "tycoon", name = "Tycoon", kind = "Origin", scope = "members",
		description = "Bonus gold each round, and power that scales with banked gold.",
		tiers = {
			{ count = 2, params = { gold = 1, damagePerTen = 0.01, damageMax = 0.05 }, description = "+1 gold each Prep. +1% damage per 10 gold held, max +5%." },
			{ count = 3, params = { gold = 2, damagePerTen = 0.02, damageMax = 0.10 }, description = "+2 gold. +2% per 10 gold, max +10%." },
			{ count = 4, params = { gold = 3, damagePerTen = 0.03, damageMax = 0.15 }, description = "+3 gold. +3% per 10 gold, max +15%." },
		},
	},
	{
		id = "obby", name = "Obby", kind = "Origin", scope = "members",
		description = "Respawns at the starting cell once per fight.",
		tiers = {
			{ count = 2, params = { untargetable = 2, respawnHealth = 0.30, immunity = 0 }, description = "First death each fight: untargetable 2s, respawn with 30% Health." },
			{ count = 3, params = { untargetable = 2, respawnHealth = 0.45, immunity = 0 }, description = "Respawn with 45% Health." },
			{ count = 4, params = { untargetable = 2, respawnHealth = 0.60, immunity = 1.5 }, description = "Respawn with 60% Health and 1.5s of damage immunity." },
		},
	},
	{
		id = "bouncer", name = "Bouncer", kind = "Class", scope = "members",
		description = "Armor, MR, a shield, and a taunt.",
		tiers = {
			{ count = 2, params = { resist = 20, shieldPct = 0.10, shieldDuration = 6, tauntRadius = 0, tauntDuration = 0 }, description = "+20 Armor and MR and a 10% max Health shield for 6s." },
			{ count = 4, params = { resist = 40, shieldPct = 0.20, shieldDuration = 6, tauntRadius = 2, tauntDuration = 2 }, description = "+40 Armor and MR, 20% shield, and enemies within 2 cells are taunted for 2s." },
			{ count = 5, params = { resist = 60, shieldPct = 0.30, shieldDuration = 6, tauntRadius = 2, tauntDuration = 3 }, description = "+60 Armor and MR, 30% shield, and a 3s taunt." },
		},
	},
	{
		id = "glitch", name = "Glitch", kind = "Class", scope = "members",
		description = "Abilities sometimes cast twice.",
		tiers = {
			{ count = 2, params = { recastChance = 0.25, recastPower = 0.50, freezeDuration = 0 }, description = "25% chance to recast at 50% power." },
			{ count = 3, params = { recastChance = 0.40, recastPower = 0.60, freezeDuration = 0 }, description = "40% chance, recast at 60% power." },
			{ count = 4, params = { recastChance = 0.50, recastPower = 0.75, freezeDuration = 1 }, description = "50% chance, 75% power, and each recast freezes a random enemy 1s." },
		},
	},
	{
		id = "camper", name = "Camper", kind = "Class", scope = "members",
		description = "Damage grows with distance to the target.",
		tiers = {
			{ count = 2, params = { damagePerCell = 0.06, maxCells = 4, range = 0 }, description = "+6% damage per cell to target, max 4 cells." },
			{ count = 3, params = { damagePerCell = 0.09, maxCells = 4, range = 0 }, description = "+9% per cell." },
			{ count = 4, params = { damagePerCell = 0.12, maxCells = 4, range = 1 }, description = "+12% per cell and +1 Range." },
		},
	},
	{
		id = "pet_squad", name = "Pet Squad", kind = "Class", scope = "members",
		description = "Summons pet tokens at combat start.",
		tiers = {
			{ count = 2, params = { pets = 1, statPct = 0.30, explosion = 0 }, description = "Summon 1 Pet with 30% of the average Health and AD of Pet Squad members." },
			{ count = 3, params = { pets = 2, statPct = 0.40, explosion = 0 }, description = "Summon 2 Pets with 40% stats." },
			{ count = 4, params = { pets = 3, statPct = 0.50, explosion = 150 }, description = "Summon 3 Pets with 50% stats. Pets explode on death for 150 magic damage in 1 cell." },
		},
	},
	{
		id = "speedrunner", name = "Speedrunner", kind = "Class", scope = "members",
		description = "Crit, plus attack speed bursts on kills.",
		tiers = {
			{ count = 2, params = { critChance = 0.20, critDamage = 0, killAs = 0.40, killAsDuration = 4 }, description = "+20% crit chance. On kill: +40% AS for 4s and reset the attack timer." },
			{ count = 3, params = { critChance = 0.35, critDamage = 0, killAs = 0.40, killAsDuration = 4 }, description = "+35% crit chance." },
			{ count = 4, params = { critChance = 0.50, critDamage = 0.30, killAs = 0.40, killAsDuration = 4 }, description = "+50% crit chance and +30% crit damage." },
		},
	},
	{
		id = "admin", name = "Admin", kind = "Class", scope = "team",
		description = "Runs random team commands on a timer.",
		tiers = {
			{ count = 2, params = { interval = 8, commands = 1 }, description = "Every 8s the team runs 1 random Admin command." },
			{ count = 3, params = { interval = 6, commands = 1 }, description = "Every 6s." },
			{ count = 4, params = { interval = 4, commands = 2 }, description = "Every 4s, running 2 different commands." },
		},
	},
}

return traits
