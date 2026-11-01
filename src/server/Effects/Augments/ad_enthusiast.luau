--!strict
-- AD Enthusiast (GDD 10.4, Silver, Items + Combat): gain a Chonky Club; units holding any AD-tagged
-- item deal more damage (ITM-08 tags).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Index = require(game:GetService("ReplicatedStorage").Shared.Util.Index)

local module: Types.EffectModule = {
	id = "ad_enthusiast",
	attach = function(ctx, p)
		for _, u in ctx.units do
			for _, itemId in u.items do
				local def = Index.item(itemId)
				if def and table.find(def.tags, "AD") then
					ctx.addModifier(u, "damageAmp", "flat", p.damage, nil, "adenthusiast")
					break
				end
			end
		end
	end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantComponent("club")
	end,
}

return module
