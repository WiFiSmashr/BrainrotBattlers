--!strict
-- Camper (GDD 8.3): members deal more damage per cell between them and their target (adjacent = 0
-- cells between), up to a maximum; the top tier adds +1 Range.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)

local module: Types.EffectModule = {
	id = "camper",
	attach = function(ctx, p)
		if p.range > 0 then
			for _, u in ctx.members do
				ctx.addModifier(u, "range", "flat", p.range, nil, "camper_range")
			end
		end
	end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, event)
			local u = event.unit
			if not ctx.isMember(u) then
				return
			end
			local target = if u.target then ctx.sim.byId[u.target] else nil
			local cells = 0
			if target then
				cells = math.clamp(Grid.distance(u.cell, target.cell) - 1, 0, ctx.params.maxCells)
			end
			if cells ~= (ctx.state[u.id] or 0) then
				ctx.state[u.id] = cells
				ctx.removeModifiers(u, "camper")
				if cells > 0 then
					ctx.addModifier(u, "damageAmp", "flat", cells * ctx.params.damagePerCell, nil, "camper")
				end
			end
		end,
	},
}

return module
