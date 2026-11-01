--!strict
-- Admin (GDD 8.3, team scope): on a timer the team runs random Admin commands, scaled by the
-- members' average AP. Commands are shared with Grand Rizzmaster (AdminCommands).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local AdminCommands = require(script.Parent.Parent.Abilities.AdminCommands)

local module: Types.EffectModule = {
	id = "admin",
	attach = function(ctx, p)
		ctx.state.nextAt = p.interval
	end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, _)
			local sim, p = ctx.sim, ctx.params
			if sim.time + 1e-6 < ctx.state.nextAt then
				return
			end
			ctx.state.nextAt += p.interval
			local ap = 0
			for _, m in ctx.members do
				ap += StatBlock.get(m.stats.ap)
			end
			local source = ctx.members[1]
			if source then
				AdminCommands.run(sim, source, ap / #ctx.members / 100, p.commands)
			end
		end,
	},
}

return module
