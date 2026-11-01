--!strict
-- Chaos Wand (GDD 9.4): auto attacks deal bonus magic damage equal to a share of the holder's AP.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "chaos_wand",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnAttack = function(ctx, event)
			if event.attacker == ctx.owner then
				ctx.queueDamage(ctx.owner, event.target, StatBlock.get(ctx.owner.stats.ap) * ctx.params.apRatio, "Magic")
			end
		end,
	},
}

return module
