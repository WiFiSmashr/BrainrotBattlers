--!strict
-- Id lookups over the data tables (ARCH-02). Built once on first use.

local Types = require(script.Parent.Parent.Types)
local Units = require(script.Parent.Parent.Data.Units)
local Items = require(script.Parent.Parent.Data.Items)
local Traits = require(script.Parent.Parent.Data.Traits)

local unitById: { [string]: Types.UnitDef } = {}
for _, u in Units do
	unitById[u.id] = u
end

local itemById: { [string]: Types.ItemDef } = {}
for _, i in Items do
	itemById[i.id] = i
end

local traitById: { [string]: Types.TraitDef } = {}
for _, t in Traits do
	traitById[t.id] = t
end

local Index = {}

-- Returns the trait definition for an id, or nil.
function Index.trait(id: string): Types.TraitDef?
	return traitById[id]
end

-- Returns the unit definition for an id, or nil.
function Index.unit(id: string): Types.UnitDef?
	return unitById[id]
end

-- Returns the item definition for an id, or nil.
function Index.item(id: string): Types.ItemDef?
	return itemById[id]
end

return Index
