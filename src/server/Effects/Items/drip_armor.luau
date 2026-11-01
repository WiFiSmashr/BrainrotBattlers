--!strict
-- Drip Armor (GDD 9.4): damage reduction that grows with each second of combat, up to a maximum.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "drip_armor",
	attach = function(ctx)
		ctx.state.seconds = 0
	end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, event)
			if event.unit ~= ctx.owner then
				return
			end
			local seconds = math.floor(ctx.sim.time + 1e-6)
			if seconds == ctx.state.seconds then
				return
			end
			ctx.state.seconds = seconds
			ctx.removeModifiers(ctx.owner, "drip")
			ctx.addModifier(ctx.owner, "damageReduction", "flat", math.min(ctx.params.max, seconds * ctx.params.perSecond), nil, "drip")
		end,
	},
}

return module
