--!strict
-- Tank Trainer (GDD 10.4, Silver, Items + Combat): gain a Jumbo Snack; units holding any Health-tagged
-- item gain max Health and Armor.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Index = require(game:GetService("ReplicatedStorage").Shared.Util.Index)

local module: Types.EffectModule = {
	id = "tank_trainer",
	attach = function(ctx, p)
		for _, u in ctx.units do
			for _, itemId in u.items do
				local def = Index.item(itemId)
				if def and table.find(def.tags, "Health") then
					ctx.addModifier(u, "maxHealth", "pct", p.healthPct, nil, "tanktrainer")
					ctx.addModifier(u, "armor", "flat", p.armor, nil, "tanktrainer")
					break
				end
			end
		end
	end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantComponent("snack")
	end,
}

return module
