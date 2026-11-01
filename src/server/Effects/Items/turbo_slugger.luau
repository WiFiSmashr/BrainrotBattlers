--!strict
-- Turbo Slugger (GDD 9.4): attacking the same target stacks attack speed; stacks reset when the
-- target changes.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "turbo_slugger",
	attach = function(ctx)
		ctx.state.stacks = 0
	end,
	detach = function() end,
	hooks = {
		OnAttack = function(ctx, event)
			if event.attacker ~= ctx.owner then
				return
			end
			local s, p = ctx.state, ctx.params
			if s.target == event.target then
				s.stacks = math.min(s.stacks + 1, p.maxStacks)
			else
				s.target, s.stacks = event.target, 0
			end
			ctx.removeModifiers(ctx.owner, "stacks")
			if s.stacks > 0 then
				ctx.addModifier(ctx.owner, "attackSpeed", "pct", s.stacks * p.asPerStack, nil, "stacks")
			end
		end,
	},
}

return module
