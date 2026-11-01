--!strict
-- Side Hustle (GDD 10.4, Bronze, Economy): +gold at the start of every Prep, through OnIncomeCalc
-- so it shows in the income breakdown (ECON-06).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "side_hustle",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnIncomeCalc = function(ctx, _)
			ctx.addIncome("Side Hustle", ctx.params.income)
		end,
	},
}

return module
