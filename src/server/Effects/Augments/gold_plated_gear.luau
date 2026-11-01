--!strict
-- Gold-Plated Gear (GDD 10.4, Gold, Economy + Items): gold and a random combined item now, and gold
-- every time the player combines two components (OnItemCombined).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "gold_plated_gear",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.addGold(ctx.params.gold)
		ctx.grantRandomCombined(ctx.params.combinedItems)
	end,
	hooks = {
		OnItemCombined = function(ctx, _)
			ctx.addGold(ctx.params.goldPerCombine)
		end,
	},
}

return module
