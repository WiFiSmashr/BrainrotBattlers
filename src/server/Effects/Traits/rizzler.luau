--!strict
-- Rizzler (GDD 8.3, team scope): at combat start the enemies closest to a Rizzler are charmed.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local module: Types.EffectModule = {
	id = "rizzler",
	attach = function(ctx, p)
		local anchor = ctx.members[1]
		if not anchor then
			return
		end
		-- Rank every enemy by its distance to the nearest Rizzler (ties: lowest unitId).
		local ranked = {}
		for _, enemy in Targeting.enemies(ctx.sim, anchor) do
			local best, bestDist = nil, math.huge
			for _, m in ctx.members do
				local d = Grid.distance(m.cell, enemy.cell)
				if d < bestDist then
					best, bestDist = m, d
				end
			end
			table.insert(ranked, { enemy = enemy, dist = bestDist, source = best })
		end
		table.sort(ranked, function(a, b)
			if a.dist ~= b.dist then
				return a.dist < b.dist
			end
			return a.enemy.id < b.enemy.id
		end)
		for i = 1, math.min(p.targets, #ranked) do
			ctx.applyStatus(ranked[i].enemy, "Charm", p.duration, 0, ranked[i].source)
		end
	end,
	detach = function() end,
}

return module
