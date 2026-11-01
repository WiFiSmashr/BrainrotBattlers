--!strict
-- Titan Snack (GDD 9.4): regenerate a share of max Health every second.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "titan_snack",
	attach = function(ctx)
		ctx.state.elapsed = 0
	end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, event)
			if event.unit ~= ctx.owner then
				return
			end
			ctx.state.elapsed += event.dt
			if ctx.state.elapsed + 1e-6 >= 1 then
				ctx.state.elapsed -= 1
				ctx.heal(ctx.owner, StatBlock.get(ctx.owner.stats.maxHealth) * ctx.params.regenPct)
			end
		end,
	},
}

return module
