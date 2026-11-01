--!strict
-- Compound Interest (GDD 10.4, Silver, Economy): raises this player's interest cap. A per-player
-- Config override, never a global edit (AUG-07, ECON-06).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "compound_interest",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.setOverride("interestCap", ctx.params.interestCap)
	end,
}

return module
