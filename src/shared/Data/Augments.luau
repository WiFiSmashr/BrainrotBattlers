--!strict
-- 24 launch augments (GDD 10.4) [EXAMPLE]. Values are params; percentages are fractions.
-- Categories: first entry is the primary category (AUG-04). "Hybrid" = two categories (D-02).

local Types = require(script.Parent.Parent.Types)

local augments: { Types.AugmentDef } = {
	{ id = "piggy_bank", name = "Piggy Bank", rarity = "Bronze", categories = { "Economy" }, params = { gold = 8 }, description = "Gain 8 gold immediately." },
	{ id = "side_hustle", name = "Side Hustle", rarity = "Bronze", categories = { "Economy" }, params = { income = 1 }, description = "Gain +1 gold at the start of every Prep." },
	{ id = "compound_interest", name = "Compound Interest", rarity = "Silver", categories = { "Economy" }, params = { interestCap = 7 }, description = "Your interest cap rises from 5 to 7 gold." },
	{ id = "winners_purse", name = "Winner's Purse", rarity = "Silver", categories = { "Economy" }, params = { winBonus = 3, lossBonus = 1 }, description = "PvP win bonus is +3 gold instead of +1, and a loss pays +1 gold." },
	{ id = "venture_capital", name = "Venture Capital", rarity = "Gold", categories = { "Economy" }, params = { gold = 20, income = 2 }, description = "Gain 20 gold immediately and +2 gold every Prep." },
	{ id = "reroll_frenzy", name = "Reroll Frenzy", rarity = "Gold", categories = { "Economy" }, params = { freeRerolls = 2 }, description = "Your first 2 shop rerolls each round are free." },
	{ id = "thick_skin", name = "Thick Skin", rarity = "Bronze", categories = { "Combat" }, params = { health = 120 }, description = "All allies gain +120 Health." },
	{ id = "warm_up", name = "Warm-Up", rarity = "Bronze", categories = { "Combat" }, params = { attackSpeedPct = 0.10 }, description = "All allies gain +10% attack speed." },
	{ id = "frontline_frenzy", name = "Frontline Frenzy", rarity = "Silver", categories = { "Combat" }, params = { rows = 2, armor = 25, mr = 25, damage = 0.15 }, description = "Allies in the front two rows gain +25 Armor, +25 MR and +15% damage." },
	{ id = "team_spirit", name = "Team Spirit", rarity = "Silver", categories = { "Combat" }, params = { damagePerTrait = 0.02, reductionPerTrait = 0.02, max = 0.20 }, description = "Per distinct active trait: +2% damage and +2% damage reduction, max 20% each." },
	{ id = "main_character", name = "Main Character Energy", rarity = "Gold", categories = { "Combat" }, params = { health = 0.60, ad = 0.40, ap = 40, omnivamp = 0.20 }, description = "Your highest-cost unit gains +60% Health, +40% AD, +40 AP and 20% omnivamp." },
	{ id = "second_wind", name = "Second Wind", rarity = "Gold", categories = { "Combat" }, params = { healPct = 0.25, attackSpeedPct = 0.30, duration = 5 }, description = "First ally death each fight: all allies heal 25% max Health and gain +30% AS for 5s." },
	{ id = "starter_pack", name = "Starter Pack", rarity = "Bronze", categories = { "Items" }, params = { components = 2 }, description = "Gain 2 random components immediately." },
	{ id = "component_coupon", name = "Component Coupon", rarity = "Bronze", categories = { "Items" }, params = { components = 1 }, description = "Choose and gain 1 component." },
	{ id = "anvil_delivery", name = "Anvil Delivery", rarity = "Silver", categories = { "Items" }, params = { choices = 3 }, description = "Choose 1 of 3 random combined items." },
	{ id = "pve_bounty", name = "PvE Bounty", rarity = "Silver", categories = { "Items" }, params = { extraDrops = 1 }, description = "Every PvE round drops 1 extra component." },
	{ id = "forge_master", name = "Forge Master", rarity = "Gold", categories = { "Items" }, params = { combinedItems = 2 }, description = "Gain 2 random combined items immediately." },
	{ id = "ad_enthusiast", name = "AD Enthusiast", rarity = "Silver", categories = { "Items", "Combat" }, params = { damage = 0.15 }, description = "Gain a Chonky Club. Units holding any AD item gain +15% damage." },
	{ id = "magic_mastery", name = "Magic Mastery", rarity = "Silver", categories = { "Items", "Combat" }, params = { ap = 25 }, description = "Gain a Glitter Wand. Units holding any AP item gain +25 AP." },
	{ id = "tank_trainer", name = "Tank Trainer", rarity = "Silver", categories = { "Items", "Combat" }, params = { healthPct = 0.10, armor = 15 }, description = "Gain a Jumbo Snack. Units holding any Health item gain +10% max Health and +15 Armor." },
	{ id = "triple_threat", name = "Triple Threat", rarity = "Gold", categories = { "Items", "Combat" }, params = { healthPct = 0.20, damage = 0.15, reduction = 0.15 }, description = "Gain 1 random component. Units holding 3 items gain +20% Health, +15% damage and 15% damage reduction." },
	{ id = "gold_plated_gear", name = "Gold-Plated Gear", rarity = "Gold", categories = { "Economy", "Items" }, params = { gold = 10, combinedItems = 1, goldPerCombine = 2 }, description = "Gain 10 gold and 1 random combined item. Each component combine grants 2 gold." },
	{ id = "rich_kid_rampage", name = "Rich Kid Rampage", rarity = "Silver", categories = { "Economy", "Combat" }, params = { gold = 10, damagePerTen = 0.01, damageMax = 0.10 }, description = "Gain 10 gold. +1% damage per 10 gold held at combat start, max +10%." },
	{ id = "hot_streak", name = "Hot Streak", rarity = "Bronze", categories = { "Economy", "Combat" }, params = { minStreak = 2, damage = 0.10 }, description = "On a win or loss streak of 2+, allies gain +10% damage." },
}

return augments
