--!strict
-- The shared item carousel (GDD 4.8; CAR-02 to CAR-07). Pure state: the match owns one during the
-- Carousel phase and replicates it in snapshots. Time is passed in, so tests use a fake clock.

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local InventoryService = require(script.Parent.InventoryService)

export type Offering = { itemId: string, pickedBy: number? }

export type Carousel = {
	offerings: { Offering },
	order: { number }, -- userIds, lowest health first (CAR-03)
	turn: number, -- index into `order`; 0 once everyone has picked
	turnEndsAt: number,
	finishedAt: number?, -- when the last player picked
	players: { [number]: PlayerState.State },
	rng: any,
}

local CarouselService = {}

-- One random component per living player; all component types appear before any repeats (CAR-02).
local function rollOfferings(count: number, rng: any): { Offering }
	local offerings: { Offering } = {}
	local bag: { string } = {}
	for _ = 1, count do
		if #bag == 0 then
			bag = rng:shuffle(InventoryService.components)
		end
		table.insert(offerings, { itemId = table.remove(bag) :: string })
	end
	return offerings
end

-- Builds a carousel for the living players; the first turn starts after the intro (CAR-03, CAR-05).
function CarouselService.new(players: { PlayerState.State }, rng: any, startsAt: number): Carousel
	local keyed: { [number]: PlayerState.State } = {}
	local order: { number } = {}
	local tiebreak: { [number]: number } = {}
	for _, p in players do
		keyed[p.userId] = p
		table.insert(order, p.userId)
		tiebreak[p.userId] = rng:next()
	end
	table.sort(order, function(a, b)
		if keyed[a].health ~= keyed[b].health then
			return keyed[a].health < keyed[b].health
		end
		return tiebreak[a] < tiebreak[b]
	end)
	return {
		offerings = rollOfferings(#order, rng), order = order, turn = if #order > 0 then 1 else 0,
		turnEndsAt = startsAt + GameConfig.carouselIntroSeconds + GameConfig.carouselPickSeconds,
		players = keyed, rng = rng,
	}
end

-- The userId whose turn it is, or nil when everyone has picked.
function CarouselService.currentPlayer(c: Carousel): number?
	return if c.turn > 0 then c.order[c.turn] else nil
end

-- Gives offering `index` to the player and advances the turn (CAR-04, CAR-06).
local function take(c: Carousel, userId: number, index: number, at: number)
	local offering = c.offerings[index]
	offering.pickedBy = userId
	InventoryService.addItem(c.players[userId], offering.itemId)
	c.turn = if c.turn >= #c.order then 0 else c.turn + 1
	if c.turn == 0 then
		c.finishedAt = at -- everyone has picked; the match may end the phase early (D-86)
	end
	c.turnEndsAt = at + GameConfig.carouselPickSeconds
end

-- Handles PickCarousel: only the player whose turn it is may pick, and only a free offering (CAR-06).
function CarouselService.pick(c: Carousel, userId: number, index: number, at: number): PlayerState.Result
	if CarouselService.currentPlayer(c) ~= userId then
		return { ok = false, reason = "NotYourTurn" }
	end
	local offering = c.offerings[index]
	if type(index) ~= "number" or not offering or offering.pickedBy then
		return { ok = false, reason = "BadArgs" }
	end
	take(c, userId, index, at)
	return { ok = true }
end

-- Auto-picks a random remaining offering for every turn that has timed out (CAR-03).
function CarouselService.update(c: Carousel, now: number)
	while c.turn > 0 and now + 1e-6 >= c.turnEndsAt do
		local free: { number } = {}
		for i, o in c.offerings do
			if not o.pickedBy then
				table.insert(free, i)
			end
		end
		take(c, c.order[c.turn], c.rng:pick(free) :: number, c.turnEndsAt)
	end
end

return CarouselService
