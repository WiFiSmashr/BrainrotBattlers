--!strict
-- Giga Chonk (GDD 9.4): every 3rd auto attack deals bonus physical damage equal to a share of AD.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "giga_chonk",
	attach = function(ctx) ctx.state.attacks = 0 end,
	detach = function() end,
	hooks = {
		OnAttack = function(ctx, event)
			if event.attacker ~= ctx.owner then
				return
			end
			ctx.state.attacks += 1
			if ctx.state.attacks % ctx.params.everyN == 0 then
				ctx.queueDamage(ctx.owner, event.target, StatBlock.get(ctx.owner.stats.ad) * ctx.params.adRatio, "Physical")
			end
		end,
	},
}

return module
