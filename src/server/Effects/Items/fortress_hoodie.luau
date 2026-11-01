--!strict
-- Fortress Hoodie (GDD 9.4): adjacent allies (8 neighbors) gain Armor and MR while they stay next
-- to the holder. Re-synced every tick because units move.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

-- Adds or removes the buff on every ally so it matches adjacency to the holder.
local function sync(ctx: any, holderAlive: boolean)
	for _, ally in Targeting.allies(ctx.sim, ctx.owner) do
		local near = holderAlive and ally ~= ctx.owner and Grid.distance(ally.cell, ctx.owner.cell) <= 1
		if near ~= (ctx.state[ally.id] or false) then
			ctx.state[ally.id] = near
			if near then
				ctx.addModifier(ally, "armor", "flat", ctx.params.resist, nil, "fortress")
				ctx.addModifier(ally, "mr", "flat", ctx.params.resist, nil, "fortress")
			else
				ctx.removeModifiers(ally, "fortress")
			end
		end
	end
end

local module: Types.EffectModule = {
	id = "fortress_hoodie",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, event)
			if event.unit == ctx.owner then
				sync(ctx, true)
			end
		end,
		OnDeath = function(ctx, event)
			if event.victim == ctx.owner then
				sync(ctx, false)
			end
		end,
	},
}

return module
