--!strict
-- Combat tunables (GDD 6.6, 7.x, 11.x; CMB-02 arena, CMB-10 overtime, ABL-02/03 mana). Every value here is [CONFIG].

local CombatConfig = {
	tickSeconds = 0.05,
	moveSpeedCellsPerSecond = 2,
	starStatMultiplier = 1.8, -- MRG-04
	maxStar = 3,

	-- Default stats (7.1).
	defaultAp = 100,
	baseArmor = 25,
	baseMr = 25,
	attackSpeedCap = 5.0,
	defaultCritChance = 0.25,
	defaultCritDamage = 1.40,
	critChanceCap = 1.0,

	-- Mana (ABL-02, ABL-03).
	manaPerAttack = 10,
	manaPerDamageTaken = 3,
	castSeconds = 0.5,

	-- Wound (11.5).
	woundReduction = 0.33,
	woundSeconds = 5,

	-- Overtime (CMB-10).
	overtimeStartPercent = 0.02,
	overtimeStepPercent = 0.01,
	overtimeStepSeconds = 2,

	minDamage = 1,
	hardCapSeconds = 90, -- safety: a fight still running here is a draw

	-- Admin commands (8.3 list). Strength scales with AP (ABL-01).
	adminCommands = {
		healPct = 0.08, freezeSeconds = 1.5, speedPct = 0.25, speedSeconds = 4,
		shield = 100, shieldSeconds = 4, kickDamage = 150,
	},

	-- Base stats by cost tier, index = cost (7.2).
	costHealth = { 600, 700, 800, 900, 1000 },
	costAd = { 45, 55, 65, 80, 100 },

	-- Archetypes (7.3).
	archetypes = {
		Brawler = { health = 1.30, ad = 0.80, armor = 20, mr = 20, attackSpeed = 0.60, range = 1, startMana = 30, maxMana = 80 },
		Fighter = { health = 1.00, ad = 1.00, armor = 10, mr = 5, attackSpeed = 0.75, range = 1, startMana = 20, maxMana = 90 },
		Assassin = { health = 0.85, ad = 1.10, armor = 0, mr = 0, attackSpeed = 0.85, range = 1, startMana = 30, maxMana = 70 },
		Marksman = { health = 0.80, ad = 1.15, armor = 0, mr = 0, attackSpeed = 0.80, range = 4, startMana = 0, maxMana = 80 },
		Mage = { health = 0.80, ad = 0.60, armor = 0, mr = 10, attackSpeed = 0.65, range = 3, startMana = 20, maxMana = 60 },
		Support = { health = 0.90, ad = 0.70, armor = 5, mr = 10, attackSpeed = 0.65, range = 2, startMana = 30, maxMana = 70 },
	},

	-- Arena (CMB-02). Home team rows 1 to 4, away rows 5 to 8.
	arenaColumns = 7,
	arenaRows = 8,
}

return CombatConfig
