--!strict
-- Looks up which model a character uses and which animations it plays (data only, no Instances).
-- A unit's model id is `UnitDef.modelId` if set, otherwise the unit's own id.

local Types = require(script.Parent.Parent.Types)
local Models = require(script.Parent.Parent.Data.Models)

local STATES = { "idle", "walk", "attack", "cast", "hit", "death", "victory" }

local byId: { [string]: Types.ModelDef } = {}
for _, def in Models.models do
	byId[def.id] = def
end

local ModelRegistry = {}

-- Animation states in the order they are loaded.
ModelRegistry.states = STATES

-- The model id a unit uses.
function ModelRegistry.modelIdOf(unit: Types.UnitDef): string
	return unit.modelId or unit.id
end

-- The data entry for a model id, or nil (a template with no entry still works with defaults).
function ModelRegistry.get(modelId: string): Types.ModelDef?
	return byId[modelId]
end

-- The folder name of a model's template.
function ModelRegistry.templateName(modelId: string): string
	local def = byId[modelId]
	return if def and def.template then def.template else modelId
end

-- The animation ids for a model: its own, with the shared defaults filling any gaps.
function ModelRegistry.animationsFor(modelId: string): Types.AnimationSet
	local own = if byId[modelId] and byId[modelId].animations then (byId[modelId].animations :: any) else {}
	local out: { [string]: string } = {}
	for _, state in STATES do
		local id = own[state]
		if not id or id == "" then
			id = (Models.defaults :: any)[state] -- an empty id counts as "not set"
		end
		if id and id ~= "" then
			out[state] = id
		end
	end
	return out :: Types.AnimationSet
end

-- Adds or replaces an entry at runtime (used by tests and live tuning).
function ModelRegistry.register(def: Types.ModelDef)
	byId[def.id] = def
end

-- Removes a runtime entry.
function ModelRegistry.unregister(modelId: string)
	byId[modelId] = nil
end

return ModelRegistry
