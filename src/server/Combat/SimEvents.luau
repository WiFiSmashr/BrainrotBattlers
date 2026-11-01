--!strict
-- Steps 3 and 4 of the tick (GDD 11.2): resolve queued damage, healing and shields through the
-- single damage pipeline (11.4), then process deaths and summons. Called only by CombatSim.

local Shared = game:GetService("ReplicatedStorage").Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local Grid = require(Shared.Util.Grid)
local StatBlock = require(script.Parent.StatBlock)
local Damage = require(script.Parent.Damage)
local Statuses = require(script.Parent.Statuses)
local SimTypes = require(script.Parent.SimTypes)

type Unit = SimTypes.Unit

local COLUMNS, ROWS = CombatConfig.arenaColumns, CombatConfig.arenaRows

local SimEvents = {}

-- Mana, capped at max; not gained while casting (ABL-03).
function SimEvents.gainMana(unit: Unit, amount: number)
	if unit.castUntil then
		return
	end
	unit.mana = math.min(unit.mana + amount, unit.maxMana)
end

-- Every positive flat modifier on a reduction stat is its own source; sources multiply separately.
local function addReductions(list: { number }, stat: StatBlock.StatBlock)
	for _, m in stat.modifiers do
		if m.kind == "flat" and m.value > 0 then
			table.insert(list, m.value)
		end
	end
end

-- Fills the Damage.Target view for a unit from its current stats. `ev` selects the auto-attack
-- or ability reductions that apply to this particular damage instance (11.4 step 5).
local function refreshView(unit: Unit, now: number, ev: any?)
	local view = unit.view
	view.health = unit.health
	view.armor = StatBlock.get(unit.stats.armor)
	view.mr = StatBlock.get(unit.stats.mr)
	local list: { number } = {}
	addReductions(list, unit.stats.damageReduction)
	if ev and ev.isAuto then
		addReductions(list, unit.stats.autoReduction)
	elseif ev and ev.isAbility then
		addReductions(list, unit.stats.abilityReduction)
	end
	view.reductions = if #list > 0 then list else nil
	view.immune = Statuses.active(unit, "Immune", now) ~= nil
end

-- Heals a unit, applying Wound, and returns the amount healed.
function SimEvents.applyHeal(self: any, unit: Unit, amount: number): number
	refreshView(unit, self.time)
	local wounded = Statuses.active(unit, "Wound", self.time) ~= nil
	local healed = Damage.heal(unit.view, amount, StatBlock.get(unit.stats.maxHealth), wounded)
	unit.health = unit.view.health
	if healed > 0 then
		self:emit("Heal", { target = unit.id, amount = healed, hp = unit.health })
	end
	return healed
end

-- Resolves one queued damage event through the single damage pipeline (11.4).
local function resolveDamage(self: any, ev: any)
	local target: Unit = ev.target
	if not target.alive or target.health <= 0 then
		return
	end
	local source: Unit? = ev.source
	-- A negate charge cancels one ability damage instance outright (Spell Sponge).
	if ev.isAbility and (target.counters.negateAbility or 0) > 0 then
		target.counters.negateAbility -= 1
		return
	end
	refreshView(target, self.time, ev)
	local attacker = nil
	if source then
		attacker = {
			critChance = StatBlock.get(source.stats.critChance),
			critDamage = StatBlock.get(source.stats.critDamage),
			damageAmp = StatBlock.get(source.stats.damageAmp),
		}
	end
	local result = Damage.resolve({
		amount = ev.amount, damageType = ev.damageType, canCrit = ev.canCrit,
		attacker = attacker, target = target.view, rng = self.rng,
	})
	target.health = target.view.health
	if result.dealt <= 0 then
		return
	end
	if source then
		target.lastDamager = source.id
	end
	SimEvents.gainMana(target, CombatConfig.manaPerDamageTaken)
	self:emit("Damage", {
		target = target.id, source = if source then source.id else nil, amount = result.dealt,
		hp = target.health, crit = result.crit, dtype = ev.damageType,
	})
	if source then
		self:fire("OnDamageDealt", {
			source = source, target = target, amount = result.dealt, damageType = ev.damageType,
			isAbility = ev.isAbility, isAuto = ev.isAuto,
		})
		local vamp = StatBlock.get(source.stats.omnivamp)
		if vamp > 0 and source.alive then
			SimEvents.applyHeal(self, source, result.dealt * vamp)
		end
	end
	self:fire("OnDamageTaken", {
		target = target, source = source, amount = result.dealt, damageType = ev.damageType,
		isAbility = ev.isAbility, isAuto = ev.isAuto,
	})
end

-- Step 3: resolve queued damage, healing and shields in queue order.
function SimEvents.resolveQueue(self: any)
	local queue = self.queue
	self.queue = {}
	for _, ev in queue do
		if ev.kind == "damage" then
			resolveDamage(self, ev)
		elseif ev.target.alive then
			if ev.kind == "heal" then
				SimEvents.applyHeal(self, ev.target, ev.amount)
			else
				local amount = ev.amount
				if Statuses.active(ev.target, "Wound", self.time) then
					amount *= 1 - CombatConfig.woundReduction
				end
				table.insert(ev.target.shields, { amount = amount, expires = self.time + ev.duration })
				self:emit("Shield", { target = ev.target.id, amount = amount, duration = ev.duration })
			end
		end
	end
end

-- Step 4: process deaths (OnDeath then OnKill) and spawn queued summons (CMB-04).
function SimEvents.processDeaths(self: any)
	for _, u in self.units do
		if u.alive and u.health <= 0 then
			u.alive = false
			u.castUntil, u.castTargets, u.stepTo = nil, nil, nil
			local killer = if u.lastDamager then self.byId[u.lastDamager] else nil
			self:fire("OnDeath", { victim = u, killer = killer })
			if not u.alive then
				self:emit("Death", { unit = u.id })
				if killer then
					self:fire("OnKill", { killer = killer, victim = u })
				end
			end
		end
	end

	local pending = self.summons
	self.summons = {}
	for _, s in pending do
		local owner: Unit = s.owner
		local cell = Grid.nearestEmpty(owner.cell, COLUMNS, ROWS, self:occupied(nil))
		if cell then
			local def = s.def
			local unit = self:addUnit({
				name = def.name, archetype = "Fighter", star = 1, cell = cell, isToken = true,
				health = def.health, ad = def.ad, attackSpeed = def.attackSpeed or 0.6, modifiers = def.modifiers,
			}, owner.team, cell)
			self:emit("Summon", { unit = unit.id, owner = owner.id, name = unit.name, col = cell.col, row = cell.row, hp = unit.health })
			if def.onSpawn then
				def.onSpawn(self, unit)
			end
		end
	end
end

return SimEvents
