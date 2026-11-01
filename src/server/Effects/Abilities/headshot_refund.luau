--!strict
-- Custom ability effect: if the caster kills this target within a moment of the shot, refund a
-- share of Max Mana (Sniper Sprout, Headshot.exe: values = refund percent per star).

local REFUND_WINDOW_SECONDS = 0.5

return function(ctx: any)
	local sim, caster = ctx.sim, ctx.caster
	local percent = ctx.effect.values[math.min(ctx.star, #ctx.effect.values)] / 100
	local target = ctx.targets[1]
	if not target then
		return
	end
	-- The shot's damage resolves later this tick, so wait for the matching OnKill.
	local expires = sim.time + REFUND_WINDOW_SECONDS
	local function onKill(_: any, event: any)
		if event.killer == caster and event.victim == target and sim.time <= expires then
			caster.mana = math.min(caster.mana + caster.maxMana * percent, caster.maxMana)
		end
	end
	sim:on("OnKill", onKill)
end
