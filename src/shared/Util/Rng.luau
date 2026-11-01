--!strict
-- Seeded random source (CMB-01). All simulation chance goes through one Rng per combat.

export type Rng = {
	next: (self: Rng) -> number,
	nextInt: (self: Rng, min: number, max: number) -> number,
	chance: (self: Rng, probability: number) -> boolean,
	shuffle: <T>(self: Rng, list: { T }) -> { T },
	pick: <T>(self: Rng, list: { T }) -> T?,
}

local Rng = {}
Rng.__index = Rng

local MODULUS = 2147483647

-- Creates an Rng from an integer seed.
function Rng.new(seed: number): Rng
	return (setmetatable({ _random = Random.new(seed) }, Rng) :: any) :: Rng
end

-- Deterministically mixes numbers into one positive integer seed (CMB-01).
function Rng.hash(...: number): number
	local h = 17
	for _, n in { ... } do
		h = (h * 31 + math.floor(n)) % MODULUS
		h = (h * 16807 + 12345) % MODULUS
	end
	return h
end

-- Uniform float in [0, 1).
function Rng.next(self: any): number
	return self._random:NextNumber()
end

-- Uniform integer in [min, max].
function Rng.nextInt(self: any, min: number, max: number): number
	return self._random:NextInteger(min, max)
end

-- True with the given probability (0 to 1).
function Rng.chance(self: any, probability: number): boolean
	return self._random:NextNumber() < probability
end

-- Returns a shuffled copy of `list` (Fisher-Yates); the input is untouched.
function Rng.shuffle(self: any, list: { any }): { any }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = self._random:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Returns a random element, or nil for an empty list.
function Rng.pick(self: any, list: { any }): any?
	if #list == 0 then
		return nil
	end
	return list[self._random:NextInteger(1, #list)]
end

return Rng
