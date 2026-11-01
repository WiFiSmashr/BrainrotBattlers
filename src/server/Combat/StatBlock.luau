--!strict
-- A stat is (base + sum flat) * (1 + sum pct) * product mult (GDD 11.6).
-- Every modifier carries a sourceId so removing a source removes everything it added.

export type Modifier = { sourceId: string, kind: "flat" | "pct" | "mult", value: number }

export type StatBlock = {
	base: number,
	min: number?,
	max: number?,
	modifiers: { Modifier },
	_dirty: boolean,
	_value: number,
}

local StatBlock = {}

-- Creates a stat with a base value and optional clamp bounds (e.g. AS max 5.0, armor min 0).
function StatBlock.new(base: number, min: number?, max: number?): StatBlock
	return { base = base, min = min, max = max, modifiers = {}, _dirty = true, _value = base }
end

-- Adds one modifier tagged with `sourceId`.
function StatBlock.addModifier(stat: StatBlock, sourceId: string, kind: "flat" | "pct" | "mult", value: number)
	table.insert(stat.modifiers, { sourceId = sourceId, kind = kind, value = value })
	stat._dirty = true
end

-- Removes every modifier added by `sourceId`; returns how many were removed.
function StatBlock.removeSource(stat: StatBlock, sourceId: string): number
	local removed = 0
	for i = #stat.modifiers, 1, -1 do
		if stat.modifiers[i].sourceId == sourceId then
			table.remove(stat.modifiers, i)
			removed += 1
		end
	end
	if removed > 0 then
		stat._dirty = true
	end
	return removed
end

-- Changes the base value (e.g. permanent Noob growth).
function StatBlock.setBase(stat: StatBlock, base: number)
	stat.base = base
	stat._dirty = true
end

-- Current value, recalculated lazily when dirty, then clamped to min/max.
function StatBlock.get(stat: StatBlock): number
	if stat._dirty then
		local flat, pct, mult = 0, 0, 1
		for _, m in stat.modifiers do
			if m.kind == "flat" then
				flat += m.value
			elseif m.kind == "pct" then
				pct += m.value
			else
				mult *= m.value
			end
		end
		local value = (stat.base + flat) * (1 + pct) * mult
		if stat.min and value < stat.min then
			value = stat.min
		end
		if stat.max and value > stat.max then
			value = stat.max
		end
		stat._value = value
		stat._dirty = false
	end
	return stat._value
end

return StatBlock
