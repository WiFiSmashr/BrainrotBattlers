--!strict
-- Team Spirit (GDD 10.4, Silver, Combat): per distinct active trait, all allies gain damage and
-- damage reduction (capped). teamInfo.traits is filled in by EffectRunner.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "team_spirit",
	attach = function(ctx, p)
		local count = if ctx.teamInfo and ctx.teamInfo.traits then ctx.teamInfo.traits else 0
		local damage = math.min(count * p.damagePerTrait, p.max)
		local reduction = math.min(count * p.reductionPerTrait, p.max)
		for _, u in ctx.units do
			if damage > 0 then
				ctx.addModifier(u, "damageAmp", "flat", damage, nil, "spirit")
				ctx.addModifier(u, "damageReduction", "flat", reduction, nil, "spirit")
			end
		end
	end,
	detach = function() end,
}

return module
