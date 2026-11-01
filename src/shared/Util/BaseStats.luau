--!strict
-- Resolves base stats from cost tier + archetype (GDD 7.2, 7.3; MRG-04 star scaling).

local Types = require(script.Parent.Parent.Types)
local CombatConfig = require(script.Parent.Parent.Config.CombatConfig)

export type BaseStats = {
	health: number,
	ad: number,
	ap: number,
	armor: number,
	mr: number,
	attackSpeed: number,
	range: number,
	startMana: number,
	maxMana: number,
	critChance: number,
	critDamage: number,
}

local BaseStats = {}

-- Returns the resolved base stats for a cost (1-5), archetype and star (1-3).
function BaseStats.resolve(cost: number, archetype: Types.Archetype, star: number): BaseStats
	local a = CombatConfig.archetypes[archetype]
	local starMult = CombatConfig.starStatMultiplier ^ (star - 1)
	return {
		health = CombatConfig.costHealth[cost] * a.health * starMult,
		ad = CombatConfig.costAd[cost] * a.ad * starMult,
		ap = CombatConfig.defaultAp,
		armor = CombatConfig.baseArmor + a.armor,
		mr = CombatConfig.baseMr + a.mr,
		attackSpeed = a.attackSpeed,
		range = a.range,
		startMana = a.startMana,
		maxMana = a.maxMana,
		critChance = CombatConfig.defaultCritChance,
		critDamage = CombatConfig.defaultCritDamage,
	}
end

return BaseStats
