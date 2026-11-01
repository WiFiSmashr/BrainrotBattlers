--!strict
-- Component Coupon (GDD 10.4, Bronze, Items): choose any one component. Opens a follow-up choice
-- the player resolves with PickAugment.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "component_coupon",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.offerChoice("component")
	end,
}

return module
