--!strict
-- The five Admin commands (GDD 8.3 list), shared by Grand Rizzmaster now and the Admin trait in
-- Phase 5. Strength scales with `power` = average AP / 100 (ABL-01). Commands are picked with the
-- combat RNG (CMB-01).

local Shared = game:GetService("ReplicatedStorage").Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local COMMANDS = { "heal", "freeze", "speed", "shield", "kick" }
local cfg = CombatConfig.adminCommands

local AdminCommands = {}

-- Runs one named command for `source`'s team.
local function run(sim: any, source: any, command: string, power: number)
	local allies = Targeting.allies(sim, source)
	local enemies = Targeting.enemies(sim, source)
	if command == "heal" then
		for _, u in allies do
			sim:queueHeal(source, u, StatBlock.get(u.stats.maxHealth) * cfg.healPct * power)
		end
	elseif command == "freeze" then
		local pick = nil
		for _, u in enemies do
			if not pick or StatBlock.get(u.stats.ad) > StatBlock.get(pick.stats.ad) then
				pick = u
			end
		end
		if pick then
			sim:applyStatus(pick, "Freeze", cfg.freezeSeconds, 0, source)
		end
	elseif command == "speed" then
		for _, u in allies do
			sim:addModifier(u, "attackSpeed", "pct", cfg.speedPct, ("admin_speed:%d:%d"):format(source.id, sim.tick), cfg.speedSeconds)
		end
	elseif command == "shield" then
		for _, u in allies do
			sim:queueShield(source, u, cfg.shield * power, cfg.shieldSeconds)
		end
	elseif command == "kick" then
		local pick = nil
		for _, u in enemies do
			if not pick or u.health < pick.health then
				pick = u
			end
		end
		if pick then
			sim:queueDamage({ source = source, target = pick, amount = cfg.kickDamage * power, damageType = "True",
				isAuto = false, canCrit = false, isAbility = true })
		end
	end
end

-- Runs `count` different random commands for the source's team.
function AdminCommands.run(sim: any, source: any, power: number, count: number)
	local order = sim.rng:shuffle(COMMANDS)
	for i = 1, math.min(count, #order) do
		run(sim, source, order[i], power)
	end
end

return AdminCommands
