--!strict
-- Piggy Bank (GDD 10.4, Bronze, Economy): gain gold immediately.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "piggy_bank",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.addGold(ctx.params.gold)
	end,
}

return module
