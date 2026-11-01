--!strict
-- Zoomie Gut (GDD 9.4): the first time the holder drops below a Health threshold, gain attack speed
-- for the rest of the fight.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "zoomie_gut",
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
				ctx.addModifier(owner, "attackSpeed", "pct", ctx.params.asBonus, nil, "zoom")
			end
		end,
	},
}

return module
