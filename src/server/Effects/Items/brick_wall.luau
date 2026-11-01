--!strict
-- Brick Wall (GDD 9.4): take less damage from auto attacks (its own reduction source, 11.4 step 5).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "brick_wall",
	attach = function(ctx, p)
		ctx.addModifier(ctx.owner, "autoReduction", "flat", p.reduction, nil, "wall")
	end,
	detach = function() end,
}

return module
