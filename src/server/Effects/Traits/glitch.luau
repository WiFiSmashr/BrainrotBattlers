--!strict
-- Glitch (GDD 8.3): member ability casts sometimes cast again instantly at reduced power; the top
-- tier also freezes a random enemy on each recast. Recasts do not fire OnCast (no chains).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local AbilityRunner = require(script.Parent.Parent.Parent.Combat.AbilityRunner)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local module: Types.EffectModule = {
	id = "glitch",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnCast = function(ctx, event)
			local caster, p, sim = event.caster, ctx.params, ctx.sim
			if not ctx.isMember(caster) or not caster.alive or not sim.rng:chance(p.recastChance) then
				return
			end
			local targets = {}
			for _, t in event.targets do
				if t.alive then
					table.insert(targets, t)
				end
			end
			AbilityRunner.execute(sim, caster, event.ability, targets, p.recastPower)
			if p.freezeDuration > 0 then
				local victim = sim.rng:pick(Targeting.enemies(sim, caster))
				if victim then
					ctx.applyStatus(victim, "Freeze", p.freezeDuration, 0, caster)
				end
			end
		end,
	},
}

return module
