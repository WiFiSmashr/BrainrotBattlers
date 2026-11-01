--!strict
-- Zoom Plating (GDD 9.4): each auto attack grants Armor, up to a maximum number of stacks.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "zoom_plating",
	attach = function(ctx) ctx.state.stacks = 0 end,
	detach = function() end,
	hooks = {
		OnAttack = function(ctx, event)
			if event.attacker == ctx.owner and ctx.state.stacks < ctx.params.maxStacks then
				ctx.state.stacks += 1
				ctx.addModifier(ctx.owner, "armor", "flat", ctx.params.armorPerHit, nil, "plating")
			end
		end,
	},
}

return module
