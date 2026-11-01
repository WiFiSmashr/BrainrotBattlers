--!strict
-- Second Wind (GDD 10.4, Gold, Combat): the first time an ally dies each fight, all allies heal and
-- gain attack speed for a while. Tokens do not count as allies dying.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "second_wind",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDeath = function(ctx, event)
			local victim = event.victim
			if victim.team ~= ctx.team or victim.isToken or ctx.state.done then
				return
			end
			ctx.state.done = true
			local p = ctx.params
			for _, ally in ctx.units do
				if ally.alive then
					ctx.heal(ally, StatBlock.get(ally.stats.maxHealth) * p.healPct)
					ctx.addModifier(ally, "attackSpeed", "pct", p.attackSpeedPct, p.duration, "wind")
				end
			end
		end,
	},
}

return module
