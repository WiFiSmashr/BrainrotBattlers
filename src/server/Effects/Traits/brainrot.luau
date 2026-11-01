--!strict
-- Brainrot (GDD 8.3): members gain Rot stacks over time; each stack gives AS and AP. At 6 units,
-- 10 stacks is Full Rot: bonus damage but attacks and abilities pick random enemies.
-- Stacks live in unit.counters.rot so the Rotzilla ability can add to them too.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "brainrot",
	attach = function(ctx, _)
		for _, u in ctx.members do
			u.counters.rotTimer = 0
		end
	end,
	detach = function(ctx)
		for _, u in ctx.members do
			u.counters.rotTimer, u.counters.rotApplied, u.counters.randomTarget = nil, nil, nil
		end
	end,
	hooks = {
		OnTick = function(ctx, event)
			local u = event.unit
			if not ctx.isMember(u) then
				return
			end
			local p = ctx.params
			u.counters.rotTimer += event.dt
			if u.counters.rotTimer + 1e-6 >= p.interval then
				u.counters.rotTimer -= p.interval
				u.counters.rot = math.min((u.counters.rot or 0) + 1, p.maxStacks)
			end
			local stacks = math.min(u.counters.rot or 0, p.maxStacks)
			if stacks == (u.counters.rotApplied or 0) then
				return
			end
			u.counters.rotApplied = stacks
			ctx.removeModifiers(u, "rot")
			ctx.removeModifiers(u, "fullrot")
			u.counters.randomTarget = nil
			if stacks > 0 then
				ctx.addModifier(u, "attackSpeed", "pct", stacks * p.asPerStack, nil, "rot")
				ctx.addModifier(u, "ap", "flat", stacks * p.apPerStack, nil, "rot")
			end
			if p.fullRot == 1 and stacks >= p.maxStacks then
				ctx.addModifier(u, "damageAmp", "flat", p.fullRotDamage, nil, "fullrot")
				u.counters.randomTarget = 1
			end
		end,
	},
}

return module
