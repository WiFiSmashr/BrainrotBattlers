--!strict
-- Barrier Boba (GDD 9.4): the first time the holder drops below a Health threshold each fight, gain
-- a shield that scales with AP (ABL-01).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "barrier_boba",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDamageTaken = function(ctx, event)
			local owner = ctx.owner
			if event.target ~= owner or ctx.state.done then
				return
			end
			if owner.health / StatBlock.get(owner.stats.maxHealth) < ctx.params.threshold then
				ctx.state.done = true
				ctx.queueShield(owner, ctx.params.shield * StatBlock.get(owner.stats.ap) / 100, ctx.params.duration)
			end
		end,
	},
}

return module
