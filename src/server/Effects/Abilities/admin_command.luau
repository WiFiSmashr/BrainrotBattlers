--!strict
-- Custom ability effect: runs Admin commands immediately (Grand Rizzmaster, Admin Override).

local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local AdminCommands = require(script.Parent.AdminCommands)

return function(ctx: any)
	local power = StatBlock.get(ctx.caster.stats.ap) / 100 * ctx.scale
	AdminCommands.run(ctx.sim, ctx.caster, power, ctx.effect.count or 1)
end
