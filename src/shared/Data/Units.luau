--!strict
-- Launch roster, 24 units (GDD 7.6) [EXAMPLE]. Star values are { star1, star2, star3 }.
-- Conventions (docs/DECISIONS.md D-04): effect.radius with targeting CurrentTarget splashes around
-- the target; Slow/stat "values" are percents; Mana "values" are signed amounts.

local Types = require(script.Parent.Parent.Types)

local units: { Types.UnitDef } = {
	{
		id = "noodle_nugget", name = "Noodle Nugget", cost = 1,
		traits = { "noob", "bouncer" }, archetype = "Brawler",
		ability = {
			name = "Slurp Shield",
			description = "Gain a shield and taunt adjacent enemies.",
			targeting = "Self",
			effects = {
				{ kind = "Shield", values = { 200, 300, 450 }, duration = { 4, 4, 4 } },
				{ kind = "Status", status = "Taunt", duration = { 1.5, 1.5, 1.5 }, radius = 1 },
			},
		},
		tint = Color3.fromRGB(255, 196, 61),
	},
	{
		id = "sleepy_sock", name = "Sleepy Sock", cost = 1,
		traits = { "brainrot", "camper" }, archetype = "Marksman",
		ability = {
			name = "Snooze Barrage",
			description = "Fire 3 bolts at the target.",
			targeting = "CurrentTarget",
			effects = { { kind = "Damage", damageType = "Magic", values = { 60, 90, 135 }, hits = 3 } },
		},
		tint = Color3.fromRGB(140, 120, 255),
	},
	{
		id = "moo_moo_mogul", name = "Moo Moo Mogul", cost = 1,
		traits = { "tycoon", "bouncer" }, archetype = "Brawler",
		ability = {
			name = "Cash Cow Stomp",
			description = "Damage and stun adjacent enemies.",
			targeting = "EnemiesInRadius", radius = 1,
			effects = {
				{ kind = "Damage", damageType = "Magic", values = { 100, 150, 225 } },
				{ kind = "Status", status = "Stun", duration = { 1, 1.25, 1.5 } },
			},
		},
		tint = Color3.fromRGB(255, 255, 255),
	},
	{
		id = "zippy_zucchini", name = "Zippy Zucchini", cost = 1,
		traits = { "speedrunner", "obby" }, archetype = "Assassin",
		ability = {
			name = "Zoom Slash",
			description = "Dash to the lowest-health enemy within 4 cells and slash it.",
			targeting = "LowestHealthEnemyInRange", range = 4,
			effects = {
				{ kind = "Dash" },
				{ kind = "Damage", damageType = "Physical", values = { 150, 225, 340 } },
			},
		},
		tint = Color3.fromRGB(80, 200, 90),
	},
	{
		id = "pixel_pup", name = "Pixel Pup", cost = 1,
		traits = { "pet_squad", "glitch" }, archetype = "Support",
		ability = {
			name = "Bark.exe",
			description = "Heal the lowest-health ally and speed it up.",
			targeting = "LowestHealthAlly",
			effects = {
				{ kind = "Heal", values = { 150, 225, 340 } },
				{ kind = "StatBuff", stat = "attackSpeedPct", values = { 20, 20, 20 }, duration = { 3, 3, 3 } },
			},
		},
		tint = Color3.fromRGB(70, 200, 255),
	},
	{
		id = "rizz_rabbit", name = "Rizz Rabbit", cost = 1,
		traits = { "rizzler", "brainrot" }, archetype = "Fighter",
		ability = {
			name = "Wink Blast",
			description = "Damage the target and charm it.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Damage", damageType = "Magic", values = { 80, 120, 180 } },
				{ kind = "Status", status = "Charm", duration = { 1.5, 2, 2.5 } },
			},
		},
		tint = Color3.fromRGB(255, 120, 190),
	},
	{
		id = "wobble_banana", name = "Wobble Banana", cost = 2,
		traits = { "brainrot", "bouncer" }, archetype = "Brawler",
		ability = {
			name = "Banana Slip",
			description = "The 3 nearest enemies lose 40% attack speed.",
			targeting = "NearestEnemies", count = 3,
			effects = { { kind = "Status", status = "Slow", values = { 40, 40, 40 }, duration = { 3, 4, 5 } } },
		},
		tint = Color3.fromRGB(255, 230, 60),
	},
	{
		id = "mini_mod", name = "Mini Mod", cost = 2,
		traits = { "admin", "aura" }, archetype = "Support",
		ability = {
			name = "Moderate",
			description = "Silence the highest-mana enemy within 5 cells and drain 30 mana.",
			targeting = "HighestManaEnemyInRange", range = 5,
			effects = {
				{ kind = "Status", status = "Silence", duration = { 2, 3, 4 } },
				{ kind = "Mana", values = { -30, -30, -30 } },
			},
		},
		tint = Color3.fromRGB(90, 90, 110),
	},
	{
		id = "lag_lizard", name = "Lag Lizard", cost = 2,
		traits = { "glitch", "speedrunner" }, archetype = "Assassin",
		ability = {
			name = "Teleport Lag",
			description = "Blink behind the target and strike it.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Dash", behind = true },
				{ kind = "Damage", damageType = "Magic", values = { 140, 210, 315 } },
			},
		},
		tint = Color3.fromRGB(0, 230, 160),
	},
	{
		id = "pocket_pharaoh", name = "Pocket Pharaoh", cost = 2,
		traits = { "tycoon", "obby" }, archetype = "Fighter",
		ability = {
			name = "Gilded Slam",
			description = "Slam the target and gain Armor for 5s.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Damage", damageType = "Physical", values = { 120, 180, 270 } },
				{ kind = "StatBuff", stat = "armor", onSelf = true, values = { 20, 30, 45 }, duration = { 5, 5, 5 } },
			},
		},
		tint = Color3.fromRGB(230, 180, 40),
	},
	{
		id = "smooch_snail", name = "Smooch Snail", cost = 2,
		traits = { "rizzler", "camper" }, archetype = "Mage",
		ability = {
			name = "Slime Kiss",
			description = "Damage the target and slow it 30% for 3s.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Damage", damageType = "Magic", values = { 130, 195, 290 } },
				{ kind = "Status", status = "Slow", values = { 30, 30, 30 }, duration = { 3, 3, 3 } },
			},
		},
		tint = Color3.fromRGB(190, 120, 220),
	},
	{
		id = "newbie_knight", name = "Newbie Knight", cost = 2,
		traits = { "noob", "pet_squad" }, archetype = "Fighter",
		ability = {
			name = "Learn the Ropes",
			description = "Gain attack speed for the fight and summon a Training Pup.",
			targeting = "Self",
			effects = {
				{ kind = "StatBuff", stat = "attackSpeedPct", values = { 15, 25, 35 } },
				{ kind = "Summon", customId = "training_pup", count = 1, values = { 200, 300, 450 }, adRatio = 0.25 },
			},
		},
		tint = Color3.fromRGB(240, 200, 150),
	},
	{
		id = "grumpy_gelato", name = "Grumpy Gelato", cost = 3,
		traits = { "brainrot", "bouncer" }, archetype = "Brawler",
		ability = {
			name = "Brain Freeze",
			description = "Damage and freeze the target and adjacent enemies.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Damage", damageType = "Magic", values = { 100, 150, 225 }, radius = 1 },
				{ kind = "Status", status = "Freeze", duration = { 1, 1.5, 2 }, radius = 1 },
			},
		},
		tint = Color3.fromRGB(150, 220, 255),
	},
	{
		id = "auntie_aura", name = "Auntie Aura", cost = 3,
		traits = { "aura", "admin" }, archetype = "Support",
		ability = {
			name = "Good Vibes",
			description = "Shield nearby allies and cleanse their crowd control.",
			targeting = "AlliesInRadius", radius = 2,
			effects = {
				{ kind = "Shield", values = { 150, 225, 340 }, duration = { 4, 4, 4 } },
				{ kind = "Custom", customId = "cleanse" },
			},
		},
		tint = Color3.fromRGB(255, 170, 255),
	},
	{
		id = "respawn_rascal", name = "Respawn Rascal", cost = 3,
		traits = { "obby", "noob" }, archetype = "Fighter",
		ability = {
			name = "Checkpoint Dash",
			description = "Leap to the farthest enemy within 5 cells, hit it, and take 20% less damage for 3s.",
			targeting = "FarthestEnemyInRange", range = 5,
			effects = {
				{ kind = "Dash" },
				{ kind = "Damage", damageType = "Physical", values = { 150, 225, 340 } },
				{ kind = "StatBuff", stat = "damageReduction", onSelf = true, values = { 20, 20, 20 }, duration = { 3, 3, 3 } },
			},
		},
		tint = Color3.fromRGB(255, 120, 60),
	},
	{
		id = "sniper_sprout", name = "Sniper Sprout", cost = 3,
		traits = { "camper", "glitch" }, archetype = "Marksman",
		ability = {
			name = "Headshot.exe",
			description = "Big hit on the lowest-health enemy in range. A kill refunds 50% mana.",
			targeting = "LowestHealthEnemyInRange",
			effects = {
				{ kind = "Damage", damageType = "Physical", values = { 300, 450, 700 } },
				{ kind = "Custom", customId = "headshot_refund", values = { 50, 50, 50 } },
			},
		},
		tint = Color3.fromRGB(120, 220, 60),
	},
	{
		id = "cash_cat", name = "Cash Cat", cost = 3,
		traits = { "tycoon", "pet_squad" }, archetype = "Mage",
		ability = {
			name = "Make It Rain",
			description = "Coins hit 3 random enemies.",
			targeting = "RandomEnemies", count = 3,
			effects = { { kind = "Damage", damageType = "Magic", values = { 90, 135, 200 } } },
		},
		tint = Color3.fromRGB(255, 215, 0),
	},
	{
		id = "sir_slaysalot", name = "Sir Slaysalot", cost = 4,
		traits = { "speedrunner", "rizzler" }, archetype = "Assassin",
		ability = {
			name = "Flurry",
			description = "Strike the target 4 times.",
			targeting = "CurrentTarget",
			effects = { { kind = "Damage", damageType = "Physical", values = { 40, 60, 90 }, adRatio = 0.6, hits = 4 } },
		},
		tint = Color3.fromRGB(220, 40, 80),
	},
	{
		id = "ban_hammer_bear", name = "Ban Hammer Bear", cost = 4,
		traits = { "admin", "bouncer" }, archetype = "Brawler",
		ability = {
			name = "Ban Hammer",
			description = "Smash the highest-health enemy within 2 cells and stun it.",
			targeting = "HighestHealthEnemyInRange", range = 2,
			effects = {
				{ kind = "Damage", damageType = "Physical", values = { 250, 375, 560 } },
				{ kind = "Status", status = "Stun", duration = { 1.5, 2, 2.5 } },
			},
		},
		tint = Color3.fromRGB(160, 100, 60),
	},
	{
		id = "spoiled_spaghetti", name = "Spoiled Spaghetti", cost = 4,
		traits = { "brainrot", "aura" }, archetype = "Mage",
		ability = {
			name = "Carbonara Chaos",
			description = "Blast a 1-cell radius and leave sauce that slows enemies.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Damage", damageType = "Magic", values = { 200, 300, 450 }, radius = 1 },
				{ kind = "Custom", customId = "sauce_puddle", radius = 1, values = { 35, 35, 35 }, duration = { 4, 4, 4 } },
			},
		},
		tint = Color3.fromRGB(230, 90, 50),
	},
	{
		id = "lootbox_lemur", name = "Lootbox Lemur", cost = 4,
		traits = { "tycoon", "noob" }, archetype = "Fighter",
		ability = {
			name = "Mystery Box",
			description = "Roll once: damage the target, OR gain a shield, OR gain attack speed.",
			targeting = "CurrentTarget",
			effects = {
				{
					kind = "Custom", customId = "mystery_box",
					options = {
						{ { kind = "Damage", damageType = "Magic", values = { 200, 300, 450 } } },
						{ { kind = "Shield", onSelf = true, values = { 250, 375, 560 }, duration = { 4, 4, 4 } } },
						{ { kind = "StatBuff", stat = "attackSpeedPct", onSelf = true, values = { 30, 30, 30 }, duration = { 4, 4, 4 } } },
					},
				},
			},
		},
		tint = Color3.fromRGB(180, 80, 255),
	},
	{
		id = "rotzilla_prime", name = "Rotzilla Prime", cost = 5,
		traits = { "brainrot", "obby", "speedrunner" }, archetype = "Fighter",
		ability = {
			name = "Maximum Rot",
			description = "Leap to the target, blast a 2-cell radius, and gain 3 Rot stacks.",
			targeting = "CurrentTarget",
			effects = {
				{ kind = "Dash" },
				{ kind = "Damage", damageType = "Magic", values = { 300, 500, 1200 }, radius = 2 },
				{ kind = "Custom", customId = "rot_stacks", onSelf = true, count = 3 },
			},
		},
		tint = Color3.fromRGB(110, 140, 30),
	},
	{
		id = "grand_rizzmaster", name = "Grand Rizzmaster", cost = 5,
		traits = { "rizzler", "aura", "admin" }, archetype = "Support",
		ability = {
			name = "Admin Override",
			description = "Charm all enemies within 3 cells and run one Admin command.",
			targeting = "EnemiesInRadius", radius = 3,
			effects = {
				{ kind = "Status", status = "Charm", duration = { 1.5, 2, 3 } },
				{ kind = "Custom", customId = "admin_command", onSelf = true, count = 1 },
			},
		},
		tint = Color3.fromRGB(255, 80, 200),
	},
	{
		id = "granny_glitchgun", name = "Granny Glitchgun", cost = 5,
		traits = { "glitch", "camper", "pet_squad" }, archetype = "Marksman",
		ability = {
			name = "Mega Bark Barrage",
			description = "Fire 10 rockets at random enemies.",
			targeting = "RandomEnemies", count = 10,
			effects = { { kind = "Damage", damageType = "Magic", values = { 60, 90, 270 }, radius = 1 } },
		},
		tint = Color3.fromRGB(255, 160, 40),
	},
}

return units
