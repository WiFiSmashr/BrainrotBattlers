--!strict
-- Cleanse Flask (GDD 9.4): the first time the holder drops below a Health threshold each fight:
-- cleanse crowd control, heal, and become CC immune for a short time.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local Statuses = require(script.Parent.Parent.Parent.Combat.Statuses)

local module: Types.EffectModule = {
	id = "cleanse_flask",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDamageTaken = function(ctx, event)
			local owner, p = ctx.owner, ctx.params
			if event.target ~= owner or ctx.state.done then
				return
			end
			local max = StatBlock.get(owner.stats.maxHealth)
			if owner.health / max < p.threshold then
				ctx.state.done = true
				Statuses.cleanse(owner)
				ctx.heal(owner, max * p.healPct)
				ctx.applyStatus(owner, "CCImmune", p.immuneDuration, 0, owner)
			end
		end,
	},
}

return module
