--!strict
-- Winner's Purse (GDD 10.4, Silver, Economy): a bigger PvP win bonus, and a loss pays a little too.
-- Per-player Config overrides read by EconomyService.calcIncome.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "winners_purse",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.setOverride("winBonus", ctx.params.winBonus)
		ctx.setOverride("lossBonus", ctx.params.lossBonus)
	end,
}

return module
