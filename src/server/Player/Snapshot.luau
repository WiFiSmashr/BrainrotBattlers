--!strict
-- Builds the per-player StateUpdate snapshot (GDD 3.5, ARCH-07). Plain tables only, kept compact
-- to stay under the 4 KB budget (3.6). Keys are short on purpose.

local PlayerState = require(script.Parent.PlayerState)
local CarouselService = require(script.Parent.Parent.Items.CarouselService)

local Snapshot = {}

-- Snapshot of one player's own state plus the public scoreboard.
function Snapshot.build(match: any, userId: number): { [string]: any }
	local state: PlayerState.State = match:getPlayer(userId)

	local units = {}
	for _, u in PlayerState.sortedUnits(state) do
		local entry: { [string]: any } = { u = u.uid, d = u.defId, s = u.star }
		if u.bench then
			entry.b = u.bench
		elseif u.board then
			entry.c = u.board.col
			entry.r = u.board.row
		end
		table.insert(units, entry)
	end

	local items = {}
	for uid, item in state.inventory do
		table.insert(items, { u = uid, i = item.itemId, e = item.equippedTo })
	end

	local scoreboard = {}
	for _, id in match.order do
		local p = match:getPlayer(id)
		-- Chosen augments are public: shown beside each portrait (AUG-08).
		table.insert(scoreboard, { id = id, n = p.name, hp = p.health, place = match.placements[id], aug = p.augments })
	end

	local offer = state.augmentOffer
	local carousel = nil
	if match.carousel then -- offerings, whose turn it is and the pick timer are replicated (CAR-07)
		local offerings = {}
		for _, o in match.carousel.offerings do
			table.insert(offerings, { i = o.itemId, p = o.pickedBy })
		end
		carousel = { offerings = offerings, turn = CarouselService.currentPlayer(match.carousel), endsAt = match.carousel.turnEndsAt }
	end

	return {
		phase = match.phase,
		round = match.info.id,
		endsAt = match.endsAt,
		gold = state.gold,
		xp = state.xp,
		level = state.level,
		hp = state.health,
		streak = { k = state.streak.kind, n = state.streak.length },
		shop = { slots = state.shop.slots, locked = state.shop.locked },
		units = units,
		items = items,
		players = scoreboard,
		place = match.placements[userId],
		offer = if offer then { kind = offer.kind, choices = offer.choices, rerolled = offer.rerolled } else nil,
		carousel = carousel,
		income = state.lastIncome,
	}
end

return Snapshot
