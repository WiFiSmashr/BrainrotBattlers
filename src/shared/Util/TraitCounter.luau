--!strict
-- Trait counting and tier lookup (GDD 8.1, TRT-01 to TRT-03, TRT-07). Used by the server and the UI.

local Types = require(script.Parent.Parent.Types)
local Traits = require(script.Parent.Parent.Data.Traits)

-- One board unit's contribution: its unit id and trait ids. Bench units and tokens are never passed in.
export type Entry = { defId: string, traits: { string } }

export type TraitState = {
	count: number, -- distinct unit ids with the trait (TRT-01)
	tierIndex: number, -- highest reached tier, 0 if none (TRT-02)
	tier: Types.TierDef?,
	nextCount: number?, -- unit count of the next breakpoint, nil at the top tier
}

local TraitCounter = {}

-- Counts every trait over the given board entries. Two copies of the same unit count once.
function TraitCounter.count(entries: { Entry }): { [string]: TraitState }
	local seen: { [string]: { [string]: boolean } } = {}
	for _, entry in entries do
		for _, traitId in entry.traits do
			seen[traitId] = seen[traitId] or {}
			seen[traitId][entry.defId] = true
		end
	end

	local result: { [string]: TraitState } = {}
	for _, trait in Traits do
		local count = 0
		for _ in seen[trait.id] or {} do
			count += 1
		end
		if count > 0 then
			local tierIndex = 0
			for i, tier in trait.tiers do
				if count >= tier.count then
					tierIndex = i
				end
			end
			local nextTier = trait.tiers[tierIndex + 1]
			result[trait.id] = {
				count = count,
				tierIndex = tierIndex,
				tier = if tierIndex > 0 then trait.tiers[tierIndex] else nil,
				nextCount = if nextTier then nextTier.count else nil,
			}
		end
	end
	return result
end

return TraitCounter
