--!strict
-- Forge Master (GDD 10.4, Gold, Items): gain random combined items immediately.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "forge_master",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantRandomCombined(ctx.params.combinedItems)
	end,
}

return module
