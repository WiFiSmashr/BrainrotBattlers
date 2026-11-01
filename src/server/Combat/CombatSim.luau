--!strict
-- Fixed-step combat simulation (GDD 11; CMB-02, CMB-04, CMB-06 to CMB-12). Pure Luau, no Instances, deterministic (CMB-01).
-- Tick order (11.2): 1 time/expiry/OnTick, 2 unit actions, 3 resolve queued events, 4 deaths and
-- summons, 5 end check. All chance comes from one seeded Rng; units act in ascending unitId.

local Shared = game:GetService("ReplicatedStorage").Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Grid = require(Shared.Util.Grid)
local Rng = require(Shared.Util.Rng)
local StatBlock = require(script.Parent.StatBlock)
local Statuses = require(script.Parent.Statuses)
local Targeting = require(script.Parent.Targeting)
local SimUnit = require(script.Parent.SimUnit)
local AbilityRunner = require(script.Parent.AbilityRunner)
local SimEvents = require(script.Parent.SimEvents)
local SimTypes = require(script.Parent.SimTypes)

type Unit = SimTypes.Unit

export type Setup = {
	seed: number, -- CMB-01
	home: { SimTypes.UnitSpec },
	away: { SimTypes.UnitSpec }, -- own-board coordinates; mirrored here (CMB-02)
	customAbilities: { [string]: (any) -> () }?, -- Custom ability effect modules by id
	attach: ((sim: any) -> ())?, -- TODO(phase 5): EffectRunner registers trait/item/augment hooks here
	record: boolean?, -- keep an event log for CombatRunner playback (11.8)
}

export type Result = {
	winner: "home" | "away" | "draw",
	survivors: number, -- living non-token units on the winning side (CMB-12)
	seconds: number,
	events: { any }?,
	roster: { any }, -- initial unit descriptions for playback
}

local EPS = 1e-6
local COLUMNS, ROWS = CombatConfig.arenaColumns, CombatConfig.arenaRows
local TICKS_PER_SECOND = math.floor(1 / CombatConfig.tickSeconds + 0.5)

local CombatSim = {}
CombatSim.__index = CombatSim

-- Builds a sim with both teams placed on the 7x8 arena and OnCombatStart fired.
function CombatSim.new(setup: Setup): any
	local sim = setmetatable({
		rng = Rng.new(setup.seed), time = 0, tick = 0, units = {} :: { Unit }, byId = {} :: { [number]: Unit },
		nextId = 1, queue = {} :: { any }, summons = {} :: { any }, zones = {} :: { any },
		hooks = {} :: { [string]: { (any, any) -> () } }, events = if setup.record then {} else nil,
		state = {} :: { [string]: any }, custom = setup.customAbilities or {}, castSeq = 0, result = nil,
		roster = {} :: { any },
	}, CombatSim)

	for _, spec in setup.home do
		sim:addUnit(spec, "home", spec.cell)
	end
	for _, spec in setup.away do
		sim:addUnit(spec, "away", Grid.mirror(spec.cell, COLUMNS, ROWS))
	end
	if setup.attach then
		setup.attach(sim)
	end

	for _, u in sim.units do
		table.insert(sim.roster, {
			id = u.id, team = u.team, name = u.name, defId = u.defId, token = u.isToken,
			col = u.cell.col, row = u.cell.row, hp = u.health, maxHp = StatBlock.get(u.stats.maxHealth),
		})
	end
	for _, u in sim.units do
		sim:fire("OnCombatStart", { unit = u })
	end
	return sim
end

-- Adds a unit at an arena cell and returns it.
function CombatSim.addUnit(self: any, spec: SimTypes.UnitSpec, team: SimTypes.Team, arenaCell: SimTypes.Cell): Unit
	local unit = SimUnit.create(spec, self.nextId, team, arenaCell)
	self.nextId += 1
	table.insert(self.units, unit)
	self.byId[unit.id] = unit
	return unit
end

-- Registers a hook listener (GDD 3.4). Listeners run in registration order.
function CombatSim.on(self: any, hook: string, fn: (any, any) -> ())
	self.hooks[hook] = self.hooks[hook] or {}
	table.insert(self.hooks[hook], fn)
end

-- Calls every listener of a hook with a plain payload table.
function CombatSim.fire(self: any, hook: string, payload: any)
	for _, fn in self.hooks[hook] or {} do
		fn(self, payload)
	end
end

-- Appends a visual event (11.8) when recording.
function CombatSim.emit(self: any, kind: string, data: { [string]: any })
	if self.events then
		data.e = kind
		data.t = self.time
		table.insert(self.events, data)
	end
end

-- Set of occupied cells (living units and reserved step destinations), optionally excluding a unit.
function CombatSim.occupied(self: any, exclude: Unit?): { [string]: boolean }
	local set = {}
	for _, u in self.units do
		if u.alive and u ~= exclude then
			set[Grid.key(u.cell)] = true
			if u.stepTo then
				set[Grid.key(u.stepTo)] = true
			end
		end
	end
	return set
end

-- Queues damage for step 3. Fields: source?, target, amount, damageType, isAuto, canCrit, isAbility.
function CombatSim.queueDamage(self: any, ev: any)
	ev.kind = "damage"
	table.insert(self.queue, ev)
end

-- Queues healing for step 3.
function CombatSim.queueHeal(self: any, source: Unit?, target: Unit, amount: number)
	table.insert(self.queue, { kind = "heal", source = source, target = target, amount = amount })
end

-- Queues a shield for step 3.
function CombatSim.queueShield(self: any, source: Unit?, target: Unit, amount: number, duration: number)
	table.insert(self.queue, { kind = "shield", source = source, target = target, amount = amount, duration = duration })
end

-- Queues a summon for step 4. `def`: name, health, ad, attackSpeed?, modifiers?, onSpawn?.
function CombatSim.queueSummon(self: any, owner: Unit, def: any)
	table.insert(self.summons, { owner = owner, def = def })
end

-- Applies a status now. Stun and Freeze cancel a cast in progress (11.5). Returns true if applied.
function CombatSim.applyStatus(self: any, target: Unit, name: string, duration: number, amount: number, source: Unit?): boolean
	local applied = Statuses.apply(target, name, self.time, duration, amount, if source then source.id else nil)
	if applied then
		if (name == "Stun" or name == "Freeze") and target.castUntil then
			target.castUntil, target.castTargets = nil, nil
		end
		self:emit("Status", { target = target.id, status = name, duration = duration })
	end
	return applied
end

-- Adds a stat modifier tagged with `sourceId`; if `duration` is given it is removed when it expires.
function CombatSim.addModifier(self: any, unit: Unit, stat: string, kind: "flat" | "pct" | "mult", value: number, sourceId: string, duration: number?)
	StatBlock.addModifier(unit.stats[stat], sourceId, kind, value)
	if duration then
		table.insert(unit.timed, { sourceId = sourceId, stat = stat, expires = self.time + duration })
	end
end

-- Adds an area that keeps applying a status to enemies of `team` standing in it (e.g. sauce).
function CombatSim.addZone(self: any, zone: any)
	table.insert(self.zones, zone)
end

-- Heals a unit now (Wound applies); returns the amount healed.
function CombatSim.heal(self: any, unit: Unit, amount: number): number
	return SimEvents.applyHeal(self, unit, amount)
end

-- Revives a unit that an effect saved from death (e.g. Obby respawn).
function CombatSim.revive(self: any, unit: Unit, health: number, cell: SimTypes.Cell)
	unit.alive, unit.health, unit.cell = true, health, { col = cell.col, row = cell.row }
	unit.stepTo, unit.castUntil, unit.castTargets = nil, nil, nil
	self:emit("Move", { unit = unit.id, col = cell.col, row = cell.row, over = 0 })
	self:emit("Heal", { target = unit.id, amount = health, hp = health })
end

-- Effective attack speed after slows.
local function attackSpeed(unit: Unit, now: number): number
	return StatBlock.get(unit.stats.attackSpeed) * (1 - Statuses.slowAmount(unit, now))
end

-- Step 1: time, expiries, zones, overtime, OnTick (11.2 step 1).
local function stepOne(self: any)
	self.tick += 1
	self.time = self.tick * CombatConfig.tickSeconds
	local now = self.time

	for _, u in self.units do
		if u.alive then
			Statuses.purge(u, now)
			for i = #u.timed, 1, -1 do
				local t = u.timed[i]
				if t.expires - EPS <= now then
					StatBlock.removeSource(u.stats[t.stat], t.sourceId)
					table.remove(u.timed, i)
				end
			end
			for i = #u.shields, 1, -1 do
				local s = u.shields[i]
				if s.expires and s.expires - EPS <= now then
					table.remove(u.shields, i)
				end
			end
		end
	end

	for i = #self.zones, 1, -1 do
		local z = self.zones[i]
		if z.expires - EPS <= now then
			table.remove(self.zones, i)
		else
			for _, u in self.units do
				if u.alive and u.team ~= z.team and Grid.distance(u.cell, z.cell) <= z.radius then
					Statuses.apply(u, z.status, now, CombatConfig.tickSeconds * 2, z.amount, nil)
				end
			end
		end
	end

	-- CMB-10: overtime true damage once per second, rising 1 percentage point every 2 seconds.
	local overtime = now - GameConfig.combatMaxSeconds
	if overtime > EPS and self.tick % TICKS_PER_SECOND == 0 then
		local rate = CombatConfig.overtimeStartPercent
			+ CombatConfig.overtimeStepPercent * math.floor((overtime + EPS) / CombatConfig.overtimeStepSeconds)
		for _, u in self.units do
			if u.alive then
				self:queueDamage({
					source = nil, target = u, amount = StatBlock.get(u.stats.maxHealth) * rate,
					damageType = "True", isAuto = false, canCrit = false,
				})
			end
		end
	end

	for _, u in self.units do
		if u.alive then
			self:fire("OnTick", { unit = u, dt = CombatConfig.tickSeconds })
		end
	end
end

-- Begins one movement step toward `target`; the destination cell is reserved immediately (CMB-08).
local function startStep(self: any, unit: Unit, target: Unit, range: number)
	local occupied = self:occupied(unit)
	local step = Grid.nextStep(unit.cell, target.cell, range, COLUMNS, ROWS, occupied)
		or Grid.greedyStep(unit.cell, target.cell, COLUMNS, ROWS, occupied) -- CMB-09 fallback
	if not step or (step.col == unit.cell.col and step.row == unit.cell.row) then
		return
	end
	local seconds = (1 / CombatConfig.moveSpeedCellsPerSecond) / (1 - Statuses.slowAmount(unit, self.time))
	unit.stepTo = step
	unit.stepArriveAt = self.time + seconds
	self:emit("Move", { unit = unit.id, col = step.col, row = step.row, over = seconds })
end

-- Step 2: one unit decides its action: cast, attack, or move (11.2 step 2).
local function act(self: any, unit: Unit)
	local now = self.time
	if unit.stepTo then
		if now + EPS < unit.stepArriveAt then
			return
		end
		unit.cell, unit.stepTo = unit.stepTo, nil
	end
	if Statuses.stunned(unit, now) then
		return
	end
	if unit.castUntil then
		if now + EPS >= unit.castUntil then
			AbilityRunner.finish(self, unit)
		end
		return
	end

	local target = Targeting.acquire(self, unit)
	if not target then
		return
	end

	-- ABL-02: a full-mana unit casts at its next tick unless silenced or nothing can be targeted.
	if unit.ability and unit.mana >= unit.maxMana and not Statuses.active(unit, "Silence", now) then
		local targets = AbilityRunner.targets(self, unit, target)
		if #targets > 0 then
			AbilityRunner.begin(self, unit, targets)
			if (unit.counters.randomTarget or 0) > 0 then
				unit.target = nil
			end
			return
		end
	end

	local charmed = Targeting.forcedBy(self, unit, "Charm") ~= nil
	local range = StatBlock.get(unit.stats.range)
	if not charmed and Targeting.distance(unit, target) <= range then
		if now + EPS >= unit.attackReadyAt then
			unit.attackReadyAt = now + 1 / attackSpeed(unit, now)
			SimEvents.gainMana(unit, CombatConfig.manaPerAttack)
			self:emit("Attack", { unit = unit.id, target = target.id })
			self:queueDamage({
				source = unit, target = target, amount = StatBlock.get(unit.stats.ad),
				damageType = "Physical", isAuto = true, canCrit = true,
			})
			self:fire("OnAttack", { attacker = unit, target = target })
			if (unit.counters.randomTarget or 0) > 0 then
				unit.target = nil -- Full Rot: pick a new random enemy for the next action
			end
		end
		return
	end
	if charmed and Targeting.distance(unit, target) <= 1 then
		return
	end
	startStep(self, unit, target, if charmed then 1 else range)
end

-- Living non-token units per team (tokens never keep a team in the fight, D-25).
local function countLiving(self: any): (number, number)
	local home, away = 0, 0
	for _, u in self.units do
		if u.alive and not u.isToken then
			if u.team == "home" then
				home += 1
			else
				away += 1
			end
		end
	end
	return home, away
end

-- Step 5: decides whether the fight is over; stores and returns the result (CMB-11, CMB-12).
local function checkEnd(self: any): Result?
	local home, away = countLiving(self)
	local winner: string? = nil
	if home == 0 and away == 0 then
		winner = "draw"
	elseif home == 0 then
		winner = "away"
	elseif away == 0 then
		winner = "home"
	elseif self.time >= CombatConfig.hardCapSeconds then
		winner = "draw"
	end
	if not winner then
		return nil
	end
	local survivors = if winner == "home" then home elseif winner == "away" then away else 0
	local result: Result = {
		winner = winner :: any, survivors = survivors, seconds = self.time,
		events = self.events, roster = self.roster,
	}
	self.result = result
	self:fire("OnCombatEnd", { result = result })
	return result
end

-- Advances the sim by one tick; returns the result once the fight is over.
function CombatSim.step(self: any): Result?
	stepOne(self)
	for _, u in self.units do -- units summoned this tick act from the next tick; ascending id (CMB-01)
		if u.alive then
			act(self, u)
		end
	end
	SimEvents.resolveQueue(self)
	SimEvents.processDeaths(self)
	return checkEnd(self)
end

-- Runs a whole fight and returns its result.
function CombatSim.run(setup: Setup): Result
	local sim = CombatSim.new(setup)
	local result = checkEnd(sim)
	while not result do
		result = CombatSim.step(sim)
	end
	return result
end

return CombatSim
