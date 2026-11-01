--!strict
-- Status effects (GDD 11.5; ABL-04, CMB-07). A status is { expires, amount, source }; "active" means not yet expired.

local SimTypes = require(script.Parent.SimTypes)

local EPS = 1e-6

local CROWD_CONTROL = { Stun = true, Freeze = true, Silence = true, Charm = true, Taunt = true }

local Statuses = {}

-- True for statuses that CC immunity blocks.
function Statuses.isCrowdControl(name: string): boolean
	return CROWD_CONTROL[name] == true
end

-- The active status of that name, or nil.
function Statuses.active(unit: SimTypes.Unit, name: string, now: number): SimTypes.Status?
	local s = unit.statuses[name]
	if s and s.expires - EPS > now then
		return s
	end
	return nil
end

-- True while stunned or frozen (they cannot move, attack or cast).
function Statuses.stunned(unit: SimTypes.Unit, now: number): boolean
	return Statuses.active(unit, "Stun", now) ~= nil or Statuses.active(unit, "Freeze", now) ~= nil
end

-- Slow fraction (0 to 1); the strongest slow wins and slows never stack.
function Statuses.slowAmount(unit: SimTypes.Unit, now: number): number
	local s = Statuses.active(unit, "Slow", now)
	return if s then s.amount else 0
end

-- Applies a status. Returns false if blocked (CC immunity) or a stronger slow is already active.
function Statuses.apply(unit: SimTypes.Unit, name: string, now: number, duration: number, amount: number, source: number?): boolean
	if CROWD_CONTROL[name] and Statuses.active(unit, "CCImmune", now) then
		return false
	end
	local existing = Statuses.active(unit, name, now)
	if name == "Slow" and existing and existing.amount > amount then
		return false
	end
	unit.statuses[name] = { expires = now + duration, amount = amount, source = source }
	return true
end

-- Removes all crowd control (Cleanse effects).
function Statuses.cleanse(unit: SimTypes.Unit)
	for name in CROWD_CONTROL do
		unit.statuses[name] = nil
	end
end

-- Drops expired statuses so tables stay small.
function Statuses.purge(unit: SimTypes.Unit, now: number)
	for name, s in unit.statuses do
		if s.expires - EPS <= now then
			unit.statuses[name] = nil
		end
	end
end

return Statuses
