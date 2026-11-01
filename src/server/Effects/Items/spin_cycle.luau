--!strict
-- Spin Cycle (GDD 9.4): ramping attack speed. Every interval the holder gains attack speed, with no
-- upper limit until the fight ends.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "spin_cycle",
	attach = function(ctx)
		ctx.state.elapsed = 0
	end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, event)
			if event.unit ~= ctx.owner then
				return
			end
			local s, p = ctx.state, ctx.params
			s.elapsed += event.dt
			while s.elapsed + 1e-6 >= p.interval do
				s.elapsed -= p.interval
				ctx.addModifier(ctx.owner, "attackSpeed", "pct", p.asPerStep, nil, "ramp")
			end
		end,
	},
}

return module
