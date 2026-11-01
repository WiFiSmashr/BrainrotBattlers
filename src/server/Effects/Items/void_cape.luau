--!strict
-- Void Cape (GDD 9.4): take less ability damage; when damaged by an ability, deal magic damage back
-- to its caster (with a cooldown).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "void_cape",
	attach = function(ctx, p)
		ctx.addModifier(ctx.owner, "abilityReduction", "flat", p.reduction, nil, "void")
		ctx.state.nextAt = 0
	end,
	detach = function() end,
	hooks = {
		OnDamageTaken = function(ctx, event)
			if event.target ~= ctx.owner or not event.isAbility or not event.source then
				return
			end
			if ctx.sim.time + 1e-6 >= ctx.state.nextAt then
				ctx.state.nextAt = ctx.sim.time + ctx.params.cooldown
				ctx.queueDamage(ctx.owner, event.source, ctx.params.reflect, "Magic")
			end
		end,
	},
}

return module
