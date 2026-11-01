--!strict
-- Reroll Frenzy (GDD 10.4, Gold, Economy): the first rerolls each round are free. ShopService reads
-- the per-player `freeRerolls` override.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "reroll_frenzy",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.setOverride("freeRerolls", ctx.params.freeRerolls)
	end,
}

return module
