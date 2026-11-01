--!strict
-- PvE monster teams generated from formulas (GDD 4.6). Plain data; CombatSim consumes it in Phase 4.

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

export type Monster = {
	id: string,
	health: number,
	ad: number,
	attackSpeed: number,
	archetype: "Fighter", -- Fighter movement, no ability
}

local PveBoards = {}

-- Number of monsters at global round g.
function PveBoards.count(g: number): number
	return math.min(1 + math.floor(g / 2), GameConfig.monsterCountCap)
end

-- The monster team for global round g.
function PveBoards.build(g: number): { Monster }
	local team: { Monster } = {}
	for i = 1, PveBoards.count(g) do
		table.insert(team, {
			id = "monster_" .. i,
			health = GameConfig.monsterHealthBase + GameConfig.monsterHealthPerRound * g,
			ad = GameConfig.monsterAdBase + GameConfig.monsterAdPerRound * g,
			attackSpeed = GameConfig.monsterAttackSpeed,
			archetype = "Fighter",
		})
	end
	return team
end

return PveBoards
