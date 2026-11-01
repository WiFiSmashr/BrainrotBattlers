--!strict
-- Aura (GDD 8.3, team scope): allies within a radius of an Aura unit gain Armor and MR; when an
-- Aura unit dies every ally gets a shield.

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)

local module: Types.EffectModule = {
	id = "aura",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnTick = function(ctx, _)
			if ctx.state.tick == ctx.sim.tick then
				return -- OnTick fires once per unit; sync once per tick
			end
			ctx.state.tick = ctx.sim.tick
			local p = ctx.params
			for _, ally in ctx.units do
				local near = false
				if ally.alive then
					for _, m in ctx.members do
						if m.alive and Grid.distance(m.cell, ally.cell) <= p.radius then
							near = true
							break
						end
					end
				end
				if near ~= (ctx.state[ally.id] or false) then
					ctx.state[ally.id] = near
					if near then
						ctx.addModifier(ally, "armor", "flat", p.resist, nil, "aura")
						ctx.addModifier(ally, "mr", "flat", p.resist, nil, "aura")
					else
						ctx.removeModifiers(ally, "aura")
					end
				end
			end
		end,
		OnDeath = function(ctx, event)
			if not ctx.isMember(event.victim) then
				return
			end
			for _, ally in ctx.units do
				if ally.alive then
					ctx.queueShield(ally, ctx.params.deathShield, ctx.params.deathShieldDuration)
				end
			end
		end,
	},
}

return module
