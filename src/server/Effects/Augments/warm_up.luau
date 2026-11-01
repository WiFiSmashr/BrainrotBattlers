--!strict
-- Warm-Up (GDD 10.4, Bronze, Combat): all allies gain attack speed.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "warm_up",
	attach = function(ctx, p)
		for _, u in ctx.units do
			ctx.addModifier(u, "attackSpeed", "pct", p.attackSpeedPct, nil, "warmup")
		end
	end,
	detach = function() end,
}

return module
