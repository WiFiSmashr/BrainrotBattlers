--!strict
-- Builds a simulation unit from a UnitSpec (GDD 7.1 stats, 11.6 StatBlocks).

local Shared = game:GetService("ReplicatedStorage").Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local BaseStats = require(Shared.Util.BaseStats)
local StatBlock = require(script.Parent.StatBlock)
local SimTypes = require(script.Parent.SimTypes)

local SimUnit = {}

-- Creates a unit at an ARENA cell (already mirrored for the away team).
function SimUnit.create(spec: SimTypes.UnitSpec, id: number, team: SimTypes.Team, arenaCell: SimTypes.Cell): SimTypes.Unit
	local base = BaseStats.resolve(spec.cost or 1, spec.archetype, spec.star)
	local stats = {
		maxHealth = StatBlock.new(spec.health or base.health, 1, nil),
		ad = StatBlock.new(spec.ad or base.ad, 0, nil),
		ap = StatBlock.new(base.ap, 0, nil),
		armor = StatBlock.new(base.armor, 0, nil),
		mr = StatBlock.new(base.mr, 0, nil),
		attackSpeed = StatBlock.new(spec.attackSpeed or base.attackSpeed, 0.05, CombatConfig.attackSpeedCap),
		critChance = StatBlock.new(base.critChance, 0, CombatConfig.critChanceCap),
		critDamage = StatBlock.new(base.critDamage, 1, nil),
		damageAmp = StatBlock.new(0, 0, nil),
		damageReduction = StatBlock.new(0, 0, nil), -- each positive flat modifier is its own source (11.4 step 5)
		autoReduction = StatBlock.new(0, 0, nil), -- only vs auto attacks (Brick Wall)
		abilityReduction = StatBlock.new(0, 0, nil), -- only vs abilities (Void Cape)
		omnivamp = StatBlock.new(0, 0, nil),
		range = StatBlock.new(base.range, 1, nil),
	}
	for _, m in spec.modifiers or {} do
		StatBlock.addModifier(stats[m.stat], m.sourceId, m.kind, m.value)
	end

	local shields: { { amount: number, expires: number? } } = {}
	local health = StatBlock.get(stats.maxHealth)
	return {
		id = id, team = team, name = spec.name, defId = spec.defId, star = spec.star,
		isToken = spec.isToken == true, uid = spec.uid, cost = spec.cost, traits = spec.traits or {}, items = spec.items or {},
		cell = { col = arenaCell.col, row = arenaCell.row },
		startCell = { col = arenaCell.col, row = arenaCell.row },
		alive = true, health = health, shields = shields,
		mana = base.startMana, maxMana = base.maxMana,
		stats = stats, ability = spec.ability,
		target = nil, attackReadyAt = 0, castUntil = nil, castTargets = nil,
		stepTo = nil, stepArriveAt = 0, statuses = {}, timed = {}, lastDamager = nil, counters = {},
		view = { health = health, armor = 0, mr = 0, shields = shields, reductions = nil, immune = false },
	}
end

return SimUnit
