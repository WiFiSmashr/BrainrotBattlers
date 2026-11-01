--!strict
-- Obby (GDD 8.3): the first time an Obby would die each fight it respawns at its starting cell with
-- part of its Health after a short untargetable, inactive spell (tier 4 adds damage immunity).

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Grid = require(Shared.Util.Grid)
local CombatConfig = require(Shared.Config.CombatConfig)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local Statuses = require(script.Parent.Parent.Parent.Combat.Statuses)

local module: Types.EffectModule = {
	id = "obby",
	attach = function() end,
	detach = function() end,
	hooks = {
		OnDeath = function(ctx, event)
			local victim = event.victim
			if not ctx.isMember(victim) or ctx.state[victim.id] then
				return
			end
			ctx.state[victim.id] = true
			local p, sim = ctx.params, ctx.sim
			local cell = Grid.nearestEmpty(victim.startCell, CombatConfig.arenaColumns, CombatConfig.arenaRows, sim:occupied(nil))
			sim:revive(victim, StatBlock.get(victim.stats.maxHealth) * p.respawnHealth, cell or victim.startCell)
			-- Untargetable and inactive while respawning; applied directly so CC immunity cannot skip it.
			Statuses.apply(victim, "Untargetable", sim.time, p.untargetable, 0, nil)
			Statuses.apply(victim, "Stun", sim.time, p.untargetable, 0, nil)
			if p.immunity > 0 then
				Statuses.apply(victim, "Immune", sim.time, p.untargetable + p.immunity, 0, nil)
			end
		end,
	},
}

return module
