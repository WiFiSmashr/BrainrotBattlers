--!strict
-- Gooey Heart (GDD 9.4): a shield at combat start, and a heal after casting an ability.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)

local module: Types.EffectModule = {
	id = "gooey_heart",
	attach = function(ctx, p)
		ctx.queueShield(ctx.owner, StatBlock.get(ctx.owner.stats.maxHealth) * p.shieldPct, p.shieldDuration)
	end,
	detach = function() end,
	hooks = {
		OnCast = function(ctx, event)
			if event.caster == ctx.owner then
				ctx.heal(ctx.owner, StatBlock.get(ctx.owner.stats.maxHealth) * ctx.params.healPct)
			end
		end,
	},
}

return module
