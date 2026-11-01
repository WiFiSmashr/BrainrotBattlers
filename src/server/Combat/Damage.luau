--!strict
-- The only place health is reduced (GDD 11.4; ARCH-04 pure, ABL-01 amounts supplied by caller).
-- Targets are mutated in place (health, shields); the returned result describes what happened.

local CombatConfig = require(game:GetService("ReplicatedStorage").Shared.Config.CombatConfig)

export type Shield = { amount: number }

export type Target = {
	health: number,
	armor: number,
	mr: number,
	shields: { Shield }, -- oldest first
	reductions: { number }?, -- each r in 0..1, applied separately (step 5)
	immune: boolean?, -- takes no damage (Obby tier 4)
}

export type Attacker = {
	critChance: number?,
	critDamage: number?,
	damageAmp: number?, -- sum of amp modifiers (step 3)
}

export type Request = {
	amount: number, -- step 1: AD for an auto attack, ability formula for abilities
	damageType: "Physical" | "Magic" | "True",
	canCrit: boolean, -- step 2: auto attacks only unless an item says otherwise
	attacker: Attacker?,
	target: Target,
	rng: { chance: (any, number) -> boolean }?,
}

export type Result = {
	dealt: number, -- damage after mitigation, before shields
	absorbed: number, -- soaked by shields
	healthLost: number,
	crit: boolean,
	killed: boolean,
}

local Damage = {}

-- Runs the full pipeline for one damage instance and applies it to the target.
function Damage.resolve(req: Request): Result
	local target = req.target
	if target.immune then
		return { dealt = 0, absorbed = 0, healthLost = 0, crit = false, killed = false }
	end

	local amount = req.amount
	local attacker = req.attacker or {}

	-- Step 2: critical strike. Only rolls the RNG when eligible, keeping the stream deterministic.
	local crit = false
	if req.canCrit and req.rng and (attacker.critChance or 0) > 0 then
		if req.rng:chance(math.min(attacker.critChance :: number, CombatConfig.critChanceCap)) then
			crit = true
			amount *= attacker.critDamage or CombatConfig.defaultCritDamage
		end
	end

	-- Step 3: attacker damage amp.
	amount *= 1 + (attacker.damageAmp or 0)

	-- Step 4: mitigation (true damage skips it).
	if req.damageType == "Physical" then
		amount *= 100 / (100 + math.max(target.armor, 0))
	elseif req.damageType == "Magic" then
		amount *= 100 / (100 + math.max(target.mr, 0))
	end

	-- Step 5: each damage-reduction source applies separately.
	for _, r in target.reductions or {} do
		amount *= 1 - r
	end

	-- Step 7 (floor): minimum damage per instance.
	amount = math.max(amount, CombatConfig.minDamage)

	-- Step 6: shields absorb first, oldest first.
	local remaining = amount
	local absorbed = 0
	while remaining > 0 and #target.shields > 0 do
		local shield = target.shields[1]
		local soak = math.min(shield.amount, remaining)
		shield.amount -= soak
		remaining -= soak
		absorbed += soak
		if shield.amount <= 0 then
			table.remove(target.shields, 1)
		end
	end

	target.health -= remaining
	return {
		dealt = amount,
		absorbed = absorbed,
		healthLost = remaining,
		crit = crit,
		killed = target.health <= 0,
	}
end

-- Applies healing after Wound reduction (33%); `maxHealth` clamps the result. Returns amount healed.
function Damage.heal(target: Target, amount: number, maxHealth: number, wounded: boolean): number
	if wounded then
		amount *= 1 - CombatConfig.woundReduction
	end
	local before = target.health
	target.health = math.min(target.health + amount, maxHealth)
	return target.health - before
end

return Damage
