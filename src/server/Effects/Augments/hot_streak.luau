--!strict
-- Hot Streak (GDD 10.4, Bronze, Economy + Combat): while on a win or loss streak, allies deal more
-- damage. teamInfo.streak is the player's current streak length.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "hot_streak",
	attach = function(ctx, p)
		local streak = if ctx.teamInfo and ctx.teamInfo.streak then ctx.teamInfo.streak else 0
		if streak >= p.minStreak then
			for _, u in ctx.units do
				ctx.addModifier(u, "damageAmp", "flat", p.damage, nil, "hotstreak")
			end
		end
	end,
	detach = function() end,
}

return module
