--!strict
-- Spike Hoodie (GDD 9.4): when hit by an auto attack, deal magic damage back to the attacker equal
-- to a share of the damage taken.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "spike_hoodie",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDamageTaken = function(ctx, event)
			if event.target == ctx.owner and event.isAuto and event.source then
				ctx.queueDamage(ctx.owner, event.source, event.amount * ctx.params.reflect, "Magic")
			end
		end,
	},
}

return module
