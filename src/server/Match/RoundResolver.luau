--!strict
-- Resolve-phase math (GDD 4.5): player damage and elimination placement. Pure.

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

export type Eliminated = { userId: number, health: number }

local RoundResolver = {}

-- Damage a losing player takes: stageBase(stage) + surviving enemy units, doubling every round
-- after the cutoff so matches always end (4.5).
function RoundResolver.damage(stage: number, globalRound: number, survivingUnits: number): number
	local bases = GameConfig.stageBaseDamage
	local lastStage = 0
	for s in bases do
		lastStage = math.max(lastStage, s)
	end
	local base = bases[math.min(stage, lastStage)] or 0
	local damage = base + survivingUnits
	local cutoff = GameConfig.damageDoublingStartsAfterRound
	if globalRound > cutoff then
		damage *= 2 ^ (globalRound - cutoff)
	end
	return damage
end

-- Assigns placements to players eliminated in the same round. `aliveBefore` players were alive at
-- the start of Resolve, so the worst finisher takes place `aliveBefore`. Lower final health places
-- lower; ties are broken randomly. Returns { [userId] = place }.
function RoundResolver.rank(eliminated: { Eliminated }, aliveBefore: number, rng: { next: (any) -> number }): { [number]: number }
	local tiebreak: { [number]: number } = {}
	local order = table.clone(eliminated)
	for _, e in order do
		tiebreak[e.userId] = rng:next()
	end
	table.sort(order, function(a, b)
		if a.health ~= b.health then
			return a.health < b.health
		end
		return tiebreak[a.userId] < tiebreak[b.userId]
	end)
	local places: { [number]: number } = {}
	for i, e in order do
		places[e.userId] = aliveBefore - i + 1
	end
	return places
end

return RoundResolver
