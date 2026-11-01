--!strict
-- 6 components (9.2) + 21 combined items (9.3, 9.4) [EXAMPLE].
-- Combined items are built from their recipe so stats are always the exact sum of the two
-- components (ITM-04) and tags are the two component tags (ITM-08). Effect numbers are params.

local Types = require(script.Parent.Parent.Types)

local components: { Types.ItemDef } = {
	{ id = "club", name = "Chonky Club", kind = "Component", tags = { "AD" }, stats = { ad = 15 }, description = "+15 Attack Damage" },
	{ id = "wand", name = "Glitter Wand", kind = "Component", tags = { "AP" }, stats = { ap = 20 }, description = "+20 Ability Power" },
	{ id = "snack", name = "Jumbo Snack", kind = "Component", tags = { "Health" }, stats = { health = 150 }, description = "+150 Health" },
	{ id = "boots", name = "Hyper Boots", kind = "Component", tags = { "AS" }, stats = { attackSpeedPct = 0.15 }, description = "+15% Attack Speed" },
	{ id = "hoodie", name = "Plate Hoodie", kind = "Component", tags = { "Armor" }, stats = { armor = 20 }, description = "+20 Armor" },
	{ id = "cape", name = "Mystic Cape", kind = "Component", tags = { "MR" }, stats = { mr = 20 }, description = "+20 Magic Resist" },
}

local byId: { [string]: Types.ItemDef } = {}
for _, c in components do
	byId[c.id] = c
end

-- Builds a combined item from two component ids.
local function combined(id: string, name: string, a: string, b: string, params: { [string]: number }, description: string): Types.ItemDef
	local ca, cb = byId[a], byId[b]
	local stats: Types.StatBonus = {}
	for _, source in { ca.stats, cb.stats } do
		for stat, value in source :: { [string]: number } do
			(stats :: any)[stat] = ((stats :: any)[stat] or 0) + value
		end
	end
	return {
		id = id, name = name, kind = "Combined",
		tags = { ca.tags[1], cb.tags[1] },
		stats = stats, recipe = { a, b }, params = params, description = description,
	}
end

local items: { Types.ItemDef } = table.clone(components)

local combinedItems: { Types.ItemDef } = {
	combined("giga_chonk", "Giga Chonk", "club", "club", { everyN = 3, adRatio = 1 }, "Every 3rd auto attack deals bonus physical damage equal to 100% of AD."),
	combined("chaos_wand", "Chaos Wand", "club", "wand", { apRatio = 0.3 }, "Auto attacks deal bonus magic damage equal to 30% of AP."),
	combined("beefy_bat", "Beefy Bat", "club", "snack", { lifesteal = 0.15 }, "Heal for 15% of physical damage dealt by auto attacks."),
	combined("turbo_slugger", "Turbo Slugger", "club", "boots", { asPerStack = 0.05, maxStacks = 10 }, "Attacking the same target stacks +5% AS, max 10."),
	combined("spike_hoodie", "Spike Hoodie", "club", "hoodie", { reflect = 0.2 }, "When hit by an auto attack, deal 20% of the damage taken back as magic damage."),
	combined("hex_breaker", "Hex Breaker", "club", "cape", { duration = 5 }, "Auto attacks apply Wound for 5s."),
	combined("mega_wand", "Mega Wand", "wand", "wand", { critChance = 0.10 }, "Abilities can crit. +10% crit chance."),
	combined("gooey_heart", "Gooey Heart", "wand", "snack", { shieldPct = 0.15, shieldDuration = 8, healPct = 0.10 }, "15% max Health shield at combat start; heal 10% max Health after casting."),
	combined("spin_cycle", "Spin Cycle", "wand", "boots", { interval = 2, asPerStep = 0.06 }, "Every 2s gain +6% AS, without limit."),
	combined("barrier_boba", "Barrier Boba", "wand", "hoodie", { threshold = 0.5, shield = 200, duration = 4 }, "First time below 50% Health, gain a 200 shield for 4s (scales with AP)."),
	combined("spell_sponge", "Spell Sponge", "wand", "cape", { mana = 15, cooldown = 1 }, "Negate the first ability damage taken; then gain 15 mana per ability hit."),
	combined("titan_snack", "Titan Snack", "snack", "snack", { regenPct = 0.02 }, "Regenerate 2% max Health per second."),
	combined("zoomie_gut", "Zoomie Gut", "snack", "boots", { threshold = 0.5, asBonus = 0.5 }, "First time below 50% Health, gain +50% AS for the fight."),
	combined("fortress_hoodie", "Fortress Hoodie", "snack", "hoodie", { resist = 15 }, "Adjacent allies gain +15 Armor and MR."),
	combined("cleanse_flask", "Cleanse Flask", "snack", "cape", { threshold = 0.4, healPct = 0.2, immuneDuration = 2 }, "Below 40% Health once: cleanse, heal 20%, and become CC immune for 2s."),
	combined("hyper_hyper", "Hyper Hyper", "boots", "boots", { everyN = 4 }, "Every 4th auto attack triggers 1 extra free auto attack."),
	combined("zoom_plating", "Zoom Plating", "boots", "hoodie", { armorPerHit = 3, maxStacks = 10 }, "Each auto attack grants +3 Armor, max 10 stacks."),
	combined("sparkle_sneakers", "Sparkle Sneakers", "boots", "cape", { everyN = 4, chainTargets = 2, damagePct = 0.5 }, "Every 4th auto attack chains to 2 nearby enemies for 50% as magic."),
	combined("brick_wall", "Brick Wall", "hoodie", "hoodie", { reduction = 0.2 }, "Take 20% less damage from auto attacks."),
	combined("drip_armor", "Drip Armor", "hoodie", "cape", { perSecond = 0.015, max = 0.30 }, "Gain 1.5% damage reduction per second of combat, max 30%."),
	combined("void_cape", "Void Cape", "cape", "cape", { reduction = 0.2, reflect = 40, cooldown = 1 }, "Take 20% less ability damage; reflect 40 magic damage to the caster (1s cooldown)."),
}

for _, item in combinedItems do
	table.insert(items, item)
end

return items
