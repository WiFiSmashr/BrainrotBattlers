--!strict
-- Sparkle Sneakers (GDD 9.4): every 4th auto attack chains to the enemies nearest the target for a
-- share of the attack's damage as magic damage.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local module: Types.EffectModule = {
	id = "sparkle_sneakers",
	attach = function(ctx) ctx.state.hits = 0 end,
	detach = function() end,
	hooks = {
		OnDamageDealt = function(ctx, event)
			if event.source ~= ctx.owner or not event.isAuto then
				return
			end
			ctx.state.hits += 1
			if ctx.state.hits % ctx.params.everyN ~= 0 then
				return
			end
			local origin = event.target
			local others = {}
			for _, e in Targeting.enemies(ctx.sim, ctx.owner) do
				if e ~= origin then
					table.insert(others, e)
				end
			end
			table.sort(others, function(a, b)
				local da, db = Grid.distance(origin.cell, a.cell), Grid.distance(origin.cell, b.cell)
				if da ~= db then
					return da < db
				end
				return a.id < b.id
			end)
			for i = 1, math.min(ctx.params.chainTargets, #others) do
				ctx.queueDamage(ctx.owner, others[i], event.amount * ctx.params.damagePct, "Magic")
			end
		end,
	},
}

return module
