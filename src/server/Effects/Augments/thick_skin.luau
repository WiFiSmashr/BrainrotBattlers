--!strict
-- Thick Skin (GDD 10.4, Bronze, Combat): all allies gain Health.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "thick_skin",
	attach = function(ctx, p)
		for _, u in ctx.units do
			ctx.addModifier(u, "maxHealth", "flat", p.health, nil, "skin")
		end
	end,
	detach = function() end,
}

return module
