--!strict
-- Custom ability effect: adds Rot stacks to the caster (Rotzilla Prime, Maximum Rot).
-- Stacks are stored in unit.counters.rot, capped at the Brainrot maximum.
-- TODO(phase 5): the Brainrot trait module converts stacks into AS and AP modifiers.

local MAX_ROT_STACKS = 10

return function(ctx: any)
	local caster = ctx.caster
	caster.counters.rot = math.min((caster.counters.rot or 0) + (ctx.effect.count or 1), MAX_ROT_STACKS)
end
