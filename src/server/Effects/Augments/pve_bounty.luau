--!strict
-- PvE Bounty (GDD 10.4, Silver, Items): every PvE win drops extra components. InventoryService.pveDrop
-- reads the per-player `pveExtraDrops` override.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "pve_bounty",
	attach = function() end,
	detach = function() end,
	onPick = function(ctx)
		ctx.addOverride("pveExtraDrops", ctx.params.extraDrops)
	end,
}

return module
