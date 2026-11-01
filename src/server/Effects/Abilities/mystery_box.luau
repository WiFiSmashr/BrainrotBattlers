--!strict
-- Custom ability effect: roll once with the combat RNG and run exactly one of the listed option
-- effect lists (Lootbox Lemur, Mystery Box; CMB-01).

return function(ctx: any)
	local options = ctx.effect.options
	local roll = ctx.sim.rng:nextInt(1, #options)
	ctx.run(options[roll], ctx.targets)
end
