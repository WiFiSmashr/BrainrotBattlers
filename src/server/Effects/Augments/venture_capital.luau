--!strict
-- Venture Capital (GDD 10.4, Gold, Economy): gold now, and extra income every Prep.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "venture_capital",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.addGold(ctx.params.gold)
	end,
	hooks = {
		OnIncomeCalc = function(ctx, _)
			ctx.addIncome("Venture Capital", ctx.params.income)
		end,
	},
}

return module
