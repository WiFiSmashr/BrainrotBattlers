--!strict
-- Speedrunner (GDD 8.3): members gain crit; on a kill they gain attack speed and reset their attack
-- timer.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "speedrunner",
	attach = function(ctx, p)
		for _, u in ctx.members do
			ctx.addModifier(u, "critChance", "flat", p.critChance, nil, "speedrunner")
			if p.critDamage > 0 then
				ctx.addModifier(u, "critDamage", "flat", p.critDamage, nil, "speedrunner")
			end
		end
	end,
	detach = function() end,
	hooks = {
		OnKill = function(ctx, event)
			local killer = event.killer
			if not ctx.isMember(killer) then
				return
			end
			ctx.addModifier(killer, "attackSpeed", "pct", ctx.params.killAs, ctx.params.killAsDuration, "kill" .. ctx.sim.tick)
			killer.attackReadyAt = ctx.sim.time
		end,
	},
}

return module
