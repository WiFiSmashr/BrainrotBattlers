--!strict
-- Mega Wand (GDD 9.4): the holder's abilities can critically strike using its crit stats, and it
-- gains crit chance. AbilityRunner reads counters.abilityCrit.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "mega_wand",
	attach = function(ctx, p)
		ctx.owner.counters.abilityCrit = 1
		ctx.addModifier(ctx.owner, "critChance", "flat", p.critChance, nil, "crit")
	end,
	detach = function(ctx)
		ctx.owner.counters.abilityCrit = nil
	end,
}

return module
