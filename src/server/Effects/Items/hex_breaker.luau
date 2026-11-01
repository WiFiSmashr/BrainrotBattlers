--!strict
-- Hex Breaker (GDD 9.4): auto attacks apply Wound (healing and shields reduced; no stacking).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "hex_breaker",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDamageDealt = function(ctx, event)
			if event.source == ctx.owner and event.isAuto then
				ctx.applyStatus(event.target, "Wound", ctx.params.duration, 0, ctx.owner)
			end
		end,
	},
}

return module
