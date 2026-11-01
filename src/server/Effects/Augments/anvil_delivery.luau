--!strict
-- Anvil Delivery (GDD 10.4, Silver, Items): choose 1 of 3 random combined items. Opens a follow-up
-- choice the player resolves with PickAugment.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "anvil_delivery",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.offerChoice("combined", ctx.params.choices)
	end,
}

return module
