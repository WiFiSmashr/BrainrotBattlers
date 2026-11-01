--!strict
-- Triple Threat (GDD 10.4, Gold, Items + Combat): gain a random component; units holding 3 items get
-- more Health, damage and damage reduction.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "triple_threat",
	attach = function(ctx, p)
		for _, u in ctx.units do
			if #u.items >= 3 then
				ctx.addModifier(u, "maxHealth", "pct", p.healthPct, nil, "triple")
				ctx.addModifier(u, "damageAmp", "flat", p.damage, nil, "triple")
				ctx.addModifier(u, "damageReduction", "flat", p.reduction, nil, "triple")
			end
		end
	end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantRandomComponents(1)
	end,
}

return module
