--!strict
-- The match state machine (GDD 4.1; ARCH-05). One per server. Time is driven by update(); every
-- transition is scheduled from the previous phase's end so fake clocks in tests are exact.
-- States: Lobby -> MatchStart -> (Carousel ->) Prep -> Combat -> Resolve -> ... -> MatchEnd.

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Data.Units)
local Signal = require(Shared.Util.Signal)
local Rng = require(Shared.Util.Rng)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local AutoPlace = require(script.Parent.Parent.Player.AutoPlace)
local EconomyService = require(script.Parent.Parent.Economy.EconomyService)
local LevelService = require(script.Parent.Parent.Economy.LevelService)
local ShopService = require(script.Parent.Parent.Economy.ShopService)
local UnitPool = require(script.Parent.Parent.Economy.UnitPool)
local AugmentService = require(script.Parent.Parent.Augments.AugmentService)
local CarouselService = require(script.Parent.Parent.Items.CarouselService)
local RoundSchedule = require(script.Parent.RoundSchedule)
local PveBoards = require(script.Parent.PveBoards)
local Pairing = require(script.Parent.Pairing)
local RoundResolver = require(script.Parent.RoundResolver)
local FightTypes = require(script.Parent.FightTypes)

export type Phase = "Lobby" | "MatchStart" | "Carousel" | "Prep" | "Combat" | "Resolve" | "MatchEnd"

export type Deps = {
	lobbySize: number,
	seed: number,
	now: () -> number,
	-- Runs a fight to completion (CombatRunner.simulate in the live game).
	combat: (FightTypes.Fight) -> FightTypes.Outcome,
	-- Called right after a fight is simulated so the runner can play it back to clients.
	onFight: ((FightTypes.Fight, FightTypes.Outcome) -> ())?,
	-- Called on every PvE win with the round's base drop count (which may be 0); the service adds extras (ITM-10).
	onPveDrop: ((PlayerState.State, number, any) -> ())?,
	-- Player-level hooks (GDD 3.4).
	onPrepStart: ((PlayerState.State) -> ())?,
	onUnitBought: ((PlayerState.State, number) -> ())?,
	onItemCombined: ((PlayerState.State, PlayerState.Item) -> ())?,
	-- OnIncomeCalc modifiers from active traits and augments (ECON-06).
	incomeModifiers: ((PlayerState.State) -> { EconomyService.Modifier })?,
	-- OnRoundEnd hooks (e.g. Noob growth) for each player who fought; result is "win", "loss" or "draw".
	onRoundEnd: ((PlayerState.State, string) -> ())?,
}

type Pending = { fight: Pairing.Fight?, home: PlayerState.State, outcome: FightTypes.Outcome, kind: "pve" | "pvp" }

local Match = {}
Match.__index = Match

-- Creates a match in the Lobby phase.
function Match.new(deps: Deps): any
	local self = {
		deps = deps,
		phase = "Lobby" :: Phase,
		stage = 1,
		round = 1,
		info = RoundSchedule.info(1, 1),
		endsAt = nil :: number?,
		players = {} :: { [number]: PlayerState.State },
		order = {} :: { number },
		placements = {} :: { [number]: number },
		lastOpponent = {} :: { [number]: number },
		homeCounts = {} :: { [number]: number },
		pending = {} :: { Pending },
		startCount = 0,
		pool = UnitPool.new(Units, deps.lobbySize),
		shopRng = Rng.new(deps.seed),
		rng = Rng.new(Rng.hash(deps.seed, 7)),
		events = {
			phaseChanged = Signal.new() :: any, -- { phase, roundId, endsAt }
			stateChanged = Signal.new() :: any, -- userId
			income = Signal.new() :: any, -- userId, breakdown (ECON-02)
			eliminated = Signal.new() :: any, -- userId, place
			matchEnded = Signal.new() :: any,
			toast = Signal.new() :: any, -- userId, reason code (UI-05)
		},
	}
	return setmetatable(self, Match)
end

-- Adds a player during the Lobby phase; nil if full or already started.
function Match.addPlayer(self: any, userId: number, name: string): PlayerState.State?
	if self.phase ~= "Lobby" or #self.order >= self.deps.lobbySize or self.players[userId] then
		return nil
	end
	local state = PlayerState.new(userId, name)
	self.players[userId] = state
	table.insert(self.order, userId)
	return state
end

-- A player's state, or nil.
function Match.getPlayer(self: any, userId: number): PlayerState.State?
	return self.players[userId]
end

-- True while the player is in the match and not eliminated.
function Match.isAlive(self: any, userId: number): boolean
	return self.players[userId] ~= nil and self.placements[userId] == nil
end

-- Living player ids in seat order.
function Match.livingIds(self: any): { number }
	local ids = {}
	for _, id in self.order do
		if self.placements[id] == nil then
			table.insert(ids, id)
		end
	end
	return ids
end

local function setPhase(self: any, phase: Phase, duration: number?, at: number)
	self.phase = phase
	self.endsAt = if duration then at + duration else nil
	self.events.phaseChanged:fire({ phase = phase, roundId = self.info.id, endsAt = self.endsAt })
end

-- Marks every player's snapshot as changed.
function Match.markAllDirty(self: any)
	for _, id in self.order do
		self.events.stateChanged:fire(id)
	end
end

-- Leaves the Lobby: builds the pool, gives starter units (LVL-05) and enters MatchStart.
function Match.start(self: any)
	assert(self.phase == "Lobby" and #self.order >= 1, "cannot start")
	self.startCount = #self.order
	for seat, id in self.order do
		self.players[id].seat = seat -- each player owns the plot for their seat (ArenaLayout.plotOrigin)
	end
	for _, id in self.order do
		ShopService.grantStarterUnit(self.players[id], self.pool, self.shopRng)
	end
	setPhase(self, "MatchStart", GameConfig.matchStartSeconds, self.deps.now())
	Match.markAllDirty(self)
end

-- Ends the match once only the winner remains (solo dev matches never end this way, D-18).
local function endIfDecided(self: any): boolean
	local living = Match.livingIds(self)
	local threshold = if self.startCount > 1 then 1 else 0
	if #living > threshold then
		return false
	end
	for _, id in living do
		self.placements[id] = 1
	end
	return true
end

-- Eliminates players with health <= 0, assigning placements by health (4.5).
local function eliminateDead(self: any)
	local living = Match.livingIds(self)
	local dead = {}
	for _, id in living do
		if self.players[id].health <= 0 then
			table.insert(dead, { userId = id, health = self.players[id].health })
		end
	end
	local places = RoundResolver.rank(dead, #living, self.rng)
	for id, place in places do
		self.placements[id] = place
		ShopService.release(self.players[id], self.pool)
		self.events.eliminated:fire(id, place)
	end
end

-- Removes a player mid-match (disconnect): they are eliminated at the next free placement.
function Match.removePlayer(self: any, userId: number)
	local state = self.players[userId]
	if not state then
		return
	end
	if self.phase == "Lobby" then
		self.players[userId] = nil
		table.remove(self.order, table.find(self.order, userId))
		return
	end
	if self.placements[userId] == nil then
		self.placements[userId] = #Match.livingIds(self)
		ShopService.release(state, self.pool)
		self.events.eliminated:fire(userId, self.placements[userId])
		if self.phase ~= "MatchEnd" and endIfDecided(self) then
			setPhase(self, "MatchEnd", nil, self.deps.now())
			self.events.matchEnded:fire()
		end
	end
end

local beginRound

-- Fires OnUnitBought after a purchase (called by ActionRouter).
function Match.unitBought(self: any, state: PlayerState.State, unitUid: number)
	if self.deps.onUnitBought then
		self.deps.onUnitBought(state, unitUid)
	end
end

-- Fires OnItemCombined after a combine (called by ActionRouter).
function Match.itemCombined(self: any, state: PlayerState.State, item: PlayerState.Item)
	if self.deps.onItemCombined then
		self.deps.onItemCombined(state, item)
	end
end

local function enterPrep(self: any, at: number)
	local info = self.info
	self.carousel = nil
	-- One rarity per augment round, shared by every player (D-59); each player still gets their own choices.
	local roundRarity = if info.augmentOffer then AugmentService.rollRarity(self.rng) else nil
	for _, id in Match.livingIds(self) do
		local state = self.players[id]
		state.rerollsThisRound = 0
		LevelService.grantPassive(state, info.global) -- LVL-02
		local modifiers = if self.deps.incomeModifiers then self.deps.incomeModifiers(state) else nil
		local breakdown = EconomyService.payIncome(state, info.global, modifiers) -- ECON-02
		state.lastIncome = { round = info.id, base = breakdown.base, interest = breakdown.interest, streak = breakdown.streak, win = breakdown.win, extras = breakdown.extras, total = breakdown.total }
		self.events.income:fire(id, breakdown)
		if self.deps.onPrepStart then
			self.deps.onPrepStart(state)
		end
		if info.augmentOffer then
			AugmentService.deal(state, info.augmentOffer, self.rng, roundRarity) -- AUG-01: before the shop refreshes
		end
		ShopService.refresh(state, self.pool, self.shopRng) -- SHOP-03, after income
	end
	setPhase(self, "Prep", RoundSchedule.prepSeconds(info), at)
	Match.markAllDirty(self)
end

-- At the end of Prep the server picks the first choice for anyone still deciding (AUG-02).
local function autoPickOffers(self: any)
	for _, id in Match.livingIds(self) do
		AugmentService.autoPick(self.players[id], self.rng)
	end
end

function beginRound(self: any, at: number)
	self.info = RoundSchedule.info(self.stage, self.round)
	if self.info.type == "carousel" then
		for _, id in Match.livingIds(self) do
			EconomyService.recordRound(self.players[id], "carousel", "draw") -- ECON-04
		end
		local living = {}
		for _, id in Match.livingIds(self) do
			table.insert(living, self.players[id])
		end
		self.carousel = CarouselService.new(living, self.rng, at) -- CAR-02, CAR-07
		setPhase(self, "Carousel", RoundSchedule.carouselSeconds(#living), at)
		Match.markAllDirty(self)
	else
		enterPrep(self, at)
	end
end

-- Simulates one fight and hands it to the runner for playback.
local function runFight(self: any, fight: FightTypes.Fight): FightTypes.Outcome
	local outcome = self.deps.combat(fight)
	if self.deps.onFight then
		self.deps.onFight(fight, outcome)
	end
	return outcome
end

local function enterCombat(self: any, at: number)
	-- Fill free board slots from the bench before anything is simulated (D-75).
	for _, id in Match.livingIds(self) do
		if AutoPlace.fill(self.players[id]) > 0 then
			self.events.stateChanged:fire(id)
		end
	end
	local info = self.info
	local pending: { Pending } = {}
	local longest = 1

	if info.type == "pve" then
		for _, id in Match.livingIds(self) do -- PAIR-04
			local home = self.players[id]
			local outcome = runFight(self, {
				kind = "pve", home = home, away = nil, monsters = PveBoards.count(info.global),
				globalRound = info.global, seed = Rng.hash(self.deps.seed, info.global, id),
			})
			table.insert(pending, { fight = nil, home = home, outcome = outcome, kind = "pve" })
		end
	else
		local fights = Pairing.pair(Match.livingIds(self), self.lastOpponent, self.homeCounts, self.rng)
		for _, fight in fights do
			self.homeCounts[fight.home] = (self.homeCounts[fight.home] or 0) + 1
			self.lastOpponent[fight.home] = fight.away
			if not fight.ghost then
				self.lastOpponent[fight.away] = fight.home
			end
			local home = self.players[fight.home]
			local outcome = runFight(self, {
				kind = if fight.ghost then "ghost" else "pvp", home = home, away = self.players[fight.away],
				monsters = 0, globalRound = info.global, seed = Rng.hash(self.deps.seed, info.global, fight.home),
			})
			table.insert(pending, { fight = fight, home = home, outcome = outcome, kind = "pvp" })
		end
	end

	for _, p in pending do
		longest = math.max(longest, p.outcome.seconds)
	end
	self.pending = pending
	setPhase(self, "Combat", longest, at) -- sim time already includes overtime (CMB-10)
end

local function toResult(winner: string, side: "home" | "away"): "win" | "loss" | "draw"
	if winner == "draw" then
		return "draw"
	end
	return if winner == side then "win" else "loss"
end

-- Fires the OnRoundEnd hooks for a player who fought this round.
local function roundEnd(self: any, state: PlayerState.State, result: string)
	if self.deps.onRoundEnd then
		self.deps.onRoundEnd(state, result)
	end
end

local function enterResolve(self: any, at: number)
	local info = self.info
	for _, p in self.pending do
		local winner = p.outcome.winner
		if p.kind == "pve" then
			EconomyService.recordRound(p.home, "pve", toResult(winner, "home"))
			roundEnd(self, p.home, toResult(winner, "home"))
			if winner == "home" and self.deps.onPveDrop then
				self.deps.onPveDrop(p.home, info.drops, self.rng) -- ITM-10, ITM-11
			end
		else
			local fight = p.fight :: Pairing.Fight
			EconomyService.recordRound(p.home, "pvp", toResult(winner, "home"))
			roundEnd(self, p.home, toResult(winner, "home"))
			local away = self.players[fight.away]
			if not fight.ghost then
				EconomyService.recordRound(away, "pvp", toResult(winner, "away")) -- ghost owner is untouched (PAIR-02)
				roundEnd(self, away, toResult(winner, "away"))
			end
			if winner ~= "draw" then
				local loser = if winner == "home" then (if fight.ghost then nil else away) else p.home
				if loser then
					loser.health -= RoundResolver.damage(info.stage, info.global, p.outcome.survivors)
				end
			end
		end
	end
	self.pending = {}

	eliminateDead(self)
	if endIfDecided(self) then
		setPhase(self, "MatchEnd", nil, at)
		self.events.matchEnded:fire()
	else
		setPhase(self, "Resolve", GameConfig.resolveSeconds, at)
	end
	Match.markAllDirty(self)
end

local function advance(self: any, at: number)
	local phase = self.phase
	if phase == "MatchStart" then
		beginRound(self, at)
	elseif phase == "Carousel" then
		CarouselService.update(self.carousel, at) -- anyone who has not picked gets a random offering (CAR-03)
		enterPrep(self, at)
	elseif phase == "Prep" then
		autoPickOffers(self)
		if self.info.type == "carousel" then
			self.stage, self.round = RoundSchedule.next(self.stage, self.round)
			beginRound(self, at)
		else
			enterCombat(self, at)
		end
	elseif phase == "Combat" then
		enterResolve(self, at)
	elseif phase == "Resolve" then
		self.stage, self.round = RoundSchedule.next(self.stage, self.round)
		beginRound(self, at)
	end
end

-- Runs every transition whose deadline has passed. Call this often (e.g. every 0.1s).
function Match.update(self: any)
	local now = self.deps.now()
	if self.phase == "Carousel" and self.carousel then
		-- Picks that timed out are made for the player (CAR-03); everyone sees them live (CAR-04).
		local before = CarouselService.currentPlayer(self.carousel)
		CarouselService.update(self.carousel, now)
		if CarouselService.currentPlayer(self.carousel) ~= before then
			Match.markAllDirty(self)
		end
		-- Once everyone has picked the carousel ends shortly after, instead of waiting out the clock (D-86).
		local finishedAt = self.carousel.finishedAt
		if finishedAt and self.endsAt and finishedAt + GameConfig.carouselEndSeconds < self.endsAt then
			self.endsAt = finishedAt + GameConfig.carouselEndSeconds
			Match.markAllDirty(self) -- the countdown the clients show changed
		end
	end
	while self.endsAt and now >= self.endsAt and self.phase ~= "MatchEnd" do
		advance(self, self.endsAt)
	end
end

return Match
