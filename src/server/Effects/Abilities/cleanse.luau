--!strict
-- Custom ability effect: removes crowd control from every target (Auntie Aura, Good Vibes).

local Statuses = require(script.Parent.Parent.Parent.Combat.Statuses)

return function(ctx: any)
	for _, unit in ctx.targets do
		Statuses.cleanse(unit)
	end
end
