--!strict
-- Custom ability effect: leaves a zone that slows enemies standing in it
-- (Spoiled Spaghetti, Carbonara Chaos: values = slow percent, duration = seconds per star).

return function(ctx: any)
	local effect, star = ctx.effect, ctx.star
	local target = ctx.targets[1]
	if not target then
		return
	end
	ctx.sim:addZone({
		team = ctx.caster.team, -- the zone harms the other team
		cell = { col = target.cell.col, row = target.cell.row },
		radius = effect.radius or 1,
		expires = ctx.sim.time + effect.duration[math.min(star, #effect.duration)],
		status = "Slow",
		amount = effect.values[math.min(star, #effect.values)] / 100,
	})
end
