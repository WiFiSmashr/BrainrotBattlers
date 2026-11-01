--!strict
-- Player-facing text for items: stat lines, recipe and the full "what does it do" description.
-- Pure data formatting, so the UI and tests share it.

local Types = require(script.Parent.Parent.Types)
local Index = require(script.Parent.Index)

local ItemText = {}

-- Stat keys in display order with their label and whether the value is a percentage.
local STAT_ORDER = {
	{ "health", "Health", false },
	{ "ad", "Attack Damage", false },
	{ "ap", "Ability Power", false },
	{ "armor", "Armor", false },
	{ "mr", "Magic Resist", false },
	{ "attackSpeedPct", "Attack Speed", true },
	{ "critChance", "Crit Chance", true },
	{ "critDamage", "Crit Damage", true },
}

-- One line per stat bonus, e.g. "+150 Health" or "+15% Attack Speed".
function ItemText.statLines(def: Types.ItemDef): { string }
	local lines = {}
	for _, entry in STAT_ORDER do
		local value = (def.stats :: any)[entry[1]]
		if value then
			local number = if entry[3] then math.floor(value * 100 + 0.5) .. "%" else tostring(value)
			table.insert(lines, ("+%s %s"):format(number, entry[2]))
		end
	end
	return lines
end

-- "Chonky Club + Glitter Wand" for a combined item, nil for a component.
function ItemText.recipe(def: Types.ItemDef): string?
	if not def.recipe then
		return nil
	end
	local a, b = Index.item(def.recipe[1]), Index.item(def.recipe[2])
	return ("%s + %s"):format(if a then a.name else def.recipe[1], if b then b.name else def.recipe[2])
end

-- The full description: kind, recipe, stats and what the item does.
function ItemText.describe(def: Types.ItemDef): string
	local parts = { if def.kind == "Component" then "Component" else "Combined item" }
	local recipe = ItemText.recipe(def)
	if recipe then
		table.insert(parts, "Made from " .. recipe)
	end
	local stats = ItemText.statLines(def)
	if #stats > 0 then
		table.insert(parts, table.concat(stats, "\n"))
	end
	if def.kind == "Combined" then
		table.insert(parts, def.description)
	end
	return table.concat(parts, "\n\n")
end

return ItemText
