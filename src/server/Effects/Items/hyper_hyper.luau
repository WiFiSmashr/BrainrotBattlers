--!strict
-- Hyper Hyper (GDD 9.4): every 4th auto attack triggers 1 extra free auto attack. The extra attack
-- is queued directly, so it does not fire OnAttack and does not count toward the 4.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "hyper_hyper",
	attach = function(ctx) ctx.state.attacks = 0 end,
	detach = function() end,
	hooks = {
		OnAttack = function(ctx, event)
			if event.attacker ~= ctx.owner then
				return
			end
			ctx.state.attacks += 1
			if ctx.state.attacks % ctx.params.everyN == 0 then
				ctx.queueDamage(ctx.owner, event.target, StatBlock.get(ctx.owner.stats.ad), "Physical", { isAuto = true, canCrit = true })
			end
		end,
	},
}

return module
