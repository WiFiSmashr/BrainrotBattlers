--!strict
-- Noob (GDD 8.3): after each round fought, board Noobs permanently gain Health and AD (max gains).
-- The growth lives on the player-state unit (unit.growth) and CombatRunner applies it every fight,
-- so it persists even if the trait tier later drops. This module only handles the round-end gain.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "noob",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnRoundEnd = function(ctx, _)
			local p = ctx.params
			for _, unit in ctx.members do
				local growth = unit.growth or { gains = 0, health = 0, ad = 0 }
				if growth.gains < p.maxGains then
					growth.gains += 1
					growth.health += p.health
					growth.ad += p.ad
				end
				unit.growth = growth
			end
		end,
	},
}

return module
