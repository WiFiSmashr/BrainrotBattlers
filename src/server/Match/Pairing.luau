--!strict
-- PvP pairing (GDD 4.4, PAIR-01..PAIR-03). Pure: ids and counters in, fights out.

export type Fight = {
	home: number, -- userId whose plot hosts the fight (PAIR-03)
	away: number, -- userId of the opponent, or of the ghost's owner
	ghost: boolean, -- true: `away` is a copy of that player's board; its owner takes nothing (PAIR-02)
}

type Rng = {
	shuffle: (any, { any }) -> { any },
	pick: (any, { any }) -> any,
	chance: (any, number) -> boolean,
}

local ATTEMPTS = 50

local Pairing = {}

-- Pairs living players at random. `lastOpponent[id]` is who each player faced last PvP round;
-- repeats are avoided whenever another valid pairing exists (PAIR-01). With an odd count one player
-- fights a ghost of another living player (PAIR-02); a lone player ghosts themself.
function Pairing.pair(
	alive: { number },
	lastOpponent: { [number]: number },
	homeCounts: { [number]: number },
	rng: Rng
): { Fight }
	local bestPairs: { { number } } = {}
	local bestGhost: { fighter: number, owner: number }? = nil
	local bestRepeats = math.huge

	for _ = 1, ATTEMPTS do
		local order = rng:shuffle(alive) :: { number }
		local pairs_: { { number } } = {}
		local repeats = 0
		for i = 1, #order - 1, 2 do
			local a, b = order[i], order[i + 1]
			if lastOpponent[a] == b then
				repeats += 1
			end
			table.insert(pairs_, { a, b })
		end

		local ghost: { fighter: number, owner: number }? = nil
		if #order % 2 == 1 then
			local fighter = order[#order]
			local candidates: { number } = {}
			for i = 1, #order - 1 do
				if order[i] ~= lastOpponent[fighter] then
					table.insert(candidates, order[i])
				end
			end
			local owner: number
			if #order == 1 then
				owner = fighter
			elseif #candidates > 0 then
				owner = rng:pick(candidates) :: number
			else
				owner = lastOpponent[fighter] :: number
				repeats += 1
			end
			ghost = { fighter = fighter, owner = owner }
		end

		if repeats < bestRepeats then
			bestPairs, bestGhost, bestRepeats = pairs_, ghost, repeats
		end
		if repeats == 0 then
			break
		end
	end

	local fights: { Fight } = {}
	for _, p in bestPairs do
		local a, b = p[1], p[2]
		local ca, cb = homeCounts[a] or 0, homeCounts[b] or 0
		local aHome = if ca ~= cb then ca < cb else rng:chance(0.5)
		if aHome then
			table.insert(fights, { home = a, away = b, ghost = false })
		else
			table.insert(fights, { home = b, away = a, ghost = false })
		end
	end
	if bestGhost then
		table.insert(fights, { home = bestGhost.fighter, away = bestGhost.owner, ghost = true })
	end
	return fights
end

return Pairing
