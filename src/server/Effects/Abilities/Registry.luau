--!strict
-- Maps Custom ability effect ids to their modules. Injected into CombatSim so the sim itself never
-- needs to look anything up by name (ARCH-03, ARCH-04).

return {
	cleanse = require(script.Parent.cleanse),
	headshot_refund = require(script.Parent.headshot_refund),
	sauce_puddle = require(script.Parent.sauce_puddle),
	mystery_box = require(script.Parent.mystery_box),
	rot_stacks = require(script.Parent.rot_stacks),
	admin_command = require(script.Parent.admin_command),
} :: { [string]: (any) -> () }
