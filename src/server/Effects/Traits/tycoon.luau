--!strict
-- Tycoon (GDD 8.3): bonus gold each Prep via OnIncomeCalc (ECON-06), and members deal more damage
-- per 10 gold held at combat start.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "tycoon",
	attach = function(ctx, p)
		local gold = if ctx.teamInfo then ctx.teamInfo.gold else 0
		local bonus = math.min(math.floor(gold / 10) * p.damagePerTen, p.damageMax)
		if bonus > 0 then
			for _, u in ctx.members do
				ctx.addModifier(u, "damageAmp", "flat", bonus, nil, "tycoon")
			end
		end
	end,
	detach = function() end,
	hooks = {
		OnIncomeCalc = function(ctx, _)
			ctx.addIncome("Tycoon", ctx.params.gold)
		end,
	},
}

return module
