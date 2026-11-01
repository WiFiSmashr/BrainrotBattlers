--!strict
-- Beefy Bat (GDD 9.4): heal for a share of the physical damage dealt by auto attacks.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "beefy_bat",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDamageDealt = function(ctx, event)
			if event.source == ctx.owner and event.isAuto and event.damageType == "Physical" then
				ctx.heal(ctx.owner, event.amount * ctx.params.lifesteal)
			end
		end,
	},
}

return module
