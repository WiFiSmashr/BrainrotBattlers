--!strict
-- 3D models and animations (ARCH-02). See docs/MODELS.md for the full guide.
--
-- Giving a character a model, the quick way: save its Model as assets/models/<unit id>.rbxm (for
-- example assets/models/noodle_nugget.rbxm) and sync. No entry here is needed; the shared default
-- animations below are used. Add an entry only to change the scale, turn the model, or give it its
-- own animations or a Roblox asset id:
--
--   { id = "noodle_nugget", scale = 1.2, facing = 180, animations = { attack = "rbxassetid://1234567" } },
--
-- A unit can share another unit's model with `modelId` in Shared/Data/Units. The ids "monster", "token"
-- and "pet" are used for PvE monsters, summoned tokens and Pets.

local Types = require(script.Parent.Parent.Types)

local Models: {
	defaults: Types.AnimationSet, -- animations used for any state a model does not define itself
	models: { Types.ModelDef },
} = {
	defaults = {
		-- idle = "rbxassetid://...",
		-- walk = "rbxassetid://...",
		-- attack = "rbxassetid://...",
		-- cast = "rbxassetid://...",
		-- hit = "rbxassetid://...",
		-- death = "rbxassetid://...",
		-- victory = "rbxassetid://...",
	},
	models = {},
}

return Models
