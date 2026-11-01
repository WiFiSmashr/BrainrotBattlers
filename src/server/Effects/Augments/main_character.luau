--!strict
-- Main Character Energy (GDD 10.4, Gold, Combat): the highest-cost unit on the board gets a big
-- boost. Ties go to the unit with more items, then the lowest unitId.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "main_character",
	attach = function(ctx, p)
		local best: any = nil
		for _, u in ctx.units do
			local better = best == nil
			if best then
				local cu, cb = u.cost or 0, best.cost or 0
				better = cu > cb or (cu == cb and #u.items > #best.items)
			end
			if better then
				best = u
			end
		end
		if best then
			ctx.addModifier(best, "maxHealth", "pct", p.health, nil, "main")
			ctx.addModifier(best, "ad", "pct", p.ad, nil, "main")
			ctx.addModifier(best, "ap", "flat", p.ap, nil, "main")
			ctx.addModifier(best, "omnivamp", "flat", p.omnivamp, nil, "main")
		end
	end,
	detach = function() end,
}

return module
