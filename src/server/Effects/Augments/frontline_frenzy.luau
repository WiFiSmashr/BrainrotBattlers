--!strict
-- Frontline Frenzy (GDD 10.4, Silver, Combat): allies in the front rows at combat start gain Armor,
-- MR and damage. The home team's front is arena row 4 going up; the away team's is row 5 going down.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local HOME_FRONT_ROW, AWAY_FRONT_ROW = 4, 5

local module: Types.EffectModule = {
	id = "frontline_frenzy",
	attach = function(ctx, p)
		for _, u in ctx.units do
			local depth = if ctx.team == "home" then HOME_FRONT_ROW - u.startCell.row else u.startCell.row - AWAY_FRONT_ROW
			if depth < p.rows then
				ctx.addModifier(u, "armor", "flat", p.armor, nil, "frontline")
				ctx.addModifier(u, "mr", "flat", p.mr, nil, "frontline")
				ctx.addModifier(u, "damageAmp", "flat", p.damage, nil, "frontline")
			end
		end
	end,
	detach = function() end,
}

return module
