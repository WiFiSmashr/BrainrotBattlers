--!strict
-- Starter Pack (GDD 10.4, Bronze, Items): gain random components immediately.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "starter_pack",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantRandomComponents(ctx.params.components)
	end,
}

return module
