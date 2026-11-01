--!strict
-- Bouncer (GDD 8.3): members gain Armor and MR and an opening shield; higher tiers also taunt the
-- enemies standing near a Bouncer to the nearest Bouncer.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local module: Types.EffectModule = {
	id = "bouncer",
	attach = function(ctx, p)
		for _, u in ctx.members do
			ctx.addModifier(u, "armor", "flat", p.resist, nil, "bouncer")
			ctx.addModifier(u, "mr", "flat", p.resist, nil, "bouncer")
			ctx.queueShield(u, StatBlock.get(u.stats.maxHealth) * p.shieldPct, p.shieldDuration)
		end
		if p.tauntRadius > 0 and ctx.members[1] then
			for _, enemy in Targeting.enemies(ctx.sim, ctx.members[1]) do
				local nearest, nearestDist = nil, math.huge
				for _, m in ctx.members do
					local d = Grid.distance(m.cell, enemy.cell)
					if d < nearestDist then
						nearest, nearestDist = m, d
					end
				end
				if nearest and nearestDist <= p.tauntRadius then
					ctx.applyStatus(enemy, "Taunt", p.tauntDuration, 0, nearest)
				end
			end
		end
	end,
	detach = function() end,
}

return module
