--!strict
-- Magic Mastery (GDD 10.4, Silver, Items + Combat): gain a Glitter Wand; units holding any AP-tagged
-- item gain AP.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Index = require(game:GetService("ReplicatedStorage").Shared.Util.Index)

local module: Types.EffectModule = {
	id = "magic_mastery",
	attach = function(ctx, p)
		for _, u in ctx.units do
			for _, itemId in u.items do
				local def = Index.item(itemId)
				if def and table.find(def.tags, "AP") then
					ctx.addModifier(u, "ap", "flat", p.ap, nil, "magicmastery")
					break
				end
			end
		end
	end,
	detach = function() end,
	onPick = function(ctx)
		ctx.grantComponent("wand")
	end,
}

return module
