--!strict
-- Rich Kid Rampage (GDD 10.4, Silver, Economy + Combat): gold now; allies deal more damage per 10
-- gold held at combat start (capped).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "rich_kid_rampage",
	attach = function(ctx, p)
		local gold = if ctx.teamInfo then ctx.teamInfo.gold else 0
		local bonus = math.min(math.floor(gold / 10) * p.damagePerTen, p.damageMax)
		if bonus > 0 then
			for _, u in ctx.units do
				ctx.addModifier(u, "damageAmp", "flat", bonus, nil, "richkid")
			end
		end
	end,
	detach = function() end,
	onPick = function(ctx)
		ctx.addGold(ctx.params.gold)
	end,
}

return module
