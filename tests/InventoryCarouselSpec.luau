--!strict
-- Phase 6 tests: inventory rules (ITM-01..03, ITM-10, ITM-11) and the carousel (CAR-01..CAR-07).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Items = require(Shared.Data.Items)
local Rng = require(Shared.Util.Rng)
local PlayerState = require(Server.Player.PlayerState)
local InventoryService = require(Server.Items.InventoryService)
local CarouselService = require(Server.Items.CarouselService)
local MatchService = require(Server.Match.MatchService)
local ActionRouter = require(Server.Player.ActionRouter)

local function itemCount(state: any): number
	local n = 0
	for _ in state.inventory do
		n += 1
	end
	return n
end

local function newPlayer(id: number, health: number?): any
	local s = PlayerState.new(id, "P" .. id)
	s.health = health or 100
	return s
end

-- A match with a fixed 5s draw for every fight, a fake clock, and `count` players.
local function harness(count: number): (any, any)
	local clock = { t = 0 }
	local match = MatchService.new({
		lobbySize = count, seed = 7, now = function() return clock.t end,
		combat = function(): any
			return { winner = "draw", survivors = 0, seconds = 5 }
		end,
	})
	for id = 1, count do
		match:addPlayer(id, "P" .. id)
	end
	match:start()
	return match, clock
end

return function(t)
	-- Inventory -------------------------------------------------------------------------------------
	t.test("equip and unequip: at most 3 items per unit, no double equip (ITM-01, ITM-02)", function()
		local s = newPlayer(1)
		local unit = PlayerState.newUnit(s, "noodle_nugget", 1, 1, nil)
		local other = PlayerState.newUnit(s, "pixel_pup", 1, 2, nil)
		local a, b, c, d = InventoryService.addItem(s, "club"), InventoryService.addItem(s, "wand"), InventoryService.addItem(s, "snack"), InventoryService.addItem(s, "cape")
		t.eq(InventoryService.equip(s, a.uid, unit.uid).ok, true)
		t.eq(InventoryService.equip(s, a.uid, other.uid).reason, "ItemEquipped")
		t.eq(InventoryService.equip(s, b.uid, unit.uid).ok, true)
		t.eq(InventoryService.equip(s, c.uid, unit.uid).ok, true)
		t.eq(InventoryService.equip(s, d.uid, unit.uid).reason, "UnitFull")
		t.eq(InventoryService.equip(s, 999, unit.uid).reason, "UnknownItem")
		t.eq(InventoryService.equip(s, d.uid, 999).reason, "UnknownUnit")
		t.eq(InventoryService.unequip(s, a.uid).ok, true)
		t.eq(a.equippedTo, nil)
		t.eq(InventoryService.unequip(s, a.uid).reason, "NotEquipped")
		t.eq(InventoryService.equip(s, d.uid, unit.uid).ok, true)
	end)

	t.test("all 21 recipes combine in either order and consume both components (ITM-03)", function()
		local ids = InventoryService.components
		local made = 0
		for i = 1, 6 do
			for j = i, 6 do
				for _, order in { { i, j }, { j, i } } do
					local s = newPlayer(1)
					local x, y = InventoryService.addItem(s, ids[order[1]]), InventoryService.addItem(s, ids[order[2]])
					local result, item = InventoryService.combine(s, x.uid, y.uid)
					t.eq(result.ok, true)
					t.eq(itemCount(s), 1)
					t.eq((item :: any).equippedTo, nil)
					local expected
					for _, def in Items do
						if def.recipe and ((def.recipe[1] == ids[i] and def.recipe[2] == ids[j]) or (def.recipe[1] == ids[j] and def.recipe[2] == ids[i])) then
							expected = def.id
						end
					end
					t.eq((item :: any).itemId, expected)
				end
				made += 1
			end
		end
		t.eq(made, 21)
	end)

	t.test("combine rejects combined items, equipped items, the same item twice and strangers (ITM-03)", function()
		local s = newPlayer(1)
		local unit = PlayerState.newUnit(s, "noodle_nugget", 1, 1, nil)
		local a, b, c = InventoryService.addItem(s, "club"), InventoryService.addItem(s, "club"), InventoryService.addItem(s, "wand")
		t.eq(InventoryService.combine(s, a.uid, a.uid).reason, "UnknownItem")
		t.eq(InventoryService.combine(s, a.uid, 999).reason, "UnknownItem")
		InventoryService.equip(s, c.uid, unit.uid)
		t.eq(InventoryService.combine(s, a.uid, c.uid).reason, "ItemEquipped")
		local ok, giga = InventoryService.combine(s, a.uid, b.uid)
		t.eq(ok.ok, true)
		local extra = InventoryService.addItem(s, "snack")
		t.eq(InventoryService.combine(s, (giga :: any).uid, extra.uid).reason, "CannotCombine")
	end)

	t.test("a component never drops 3 times in a row for one player (ITM-11)", function()
		local rng = Rng.new(5)
		local s = newPlayer(1)
		local counts: { [string]: number } = {}
		local last: { string } = {}
		for _ = 1, 20000 do
			local id = InventoryService.randomComponent(s, rng)
			counts[id] = (counts[id] or 0) + 1
			table.insert(last, id)
			if #last >= 3 then
				t.truthy(not (last[#last] == last[#last - 1] and last[#last] == last[#last - 2]), "three in a row")
			end
		end
		for _, id in InventoryService.components do
			t.near(counts[id] / 20000, 1 / 6, 0.02, id)
		end
	end)

	t.test("drops go straight to the inventory; PvE Bounty adds extras (ITM-10, ITM-12)", function()
		local plain, bounty = newPlayer(1), newPlayer(2)
		bounty.overrides.pveExtraDrops = 1
		InventoryService.pveDrop(plain, 2, Rng.new(1))
		InventoryService.pveDrop(bounty, 2, Rng.new(1))
		t.eq(itemCount(plain), 2)
		t.eq(itemCount(bounty), 3)
		InventoryService.pveDrop(bounty, 0, Rng.new(1)) -- even 1-1 pays out the extra
		t.eq(itemCount(bounty), 4)
	end)

	-- Carousel service -----------------------------------------------------------------------------------
	t.test("one offering per living player; all 6 components appear before any repeat (CAR-02)", function()
		local players = {}
		for id = 1, 12 do
			table.insert(players, newPlayer(id))
		end
		local c = CarouselService.new(players, Rng.new(3), 0)
		t.eq(#c.offerings, 12)
		for _, half in { { 1, 6 }, { 7, 12 } } do
			local seen: { [string]: boolean } = {}
			for i = half[1], half[2] do
				seen[c.offerings[i].itemId] = true
			end
			local distinct = 0
			for _ in seen do
				distinct += 1
			end
			t.eq(distinct, 6)
		end
	end)

	t.test("lowest health picks first, ties random (CAR-03)", function()
		local ps = { newPlayer(1, 50), newPlayer(2, 20), newPlayer(3, 80), newPlayer(4, 20) }
		local firstTwo: { [number]: boolean } = {}
		for seed = 1, 20 do
			local c = CarouselService.new(ps, Rng.new(seed), 0)
			t.eq(c.order[3], 1)
			t.eq(c.order[4], 3)
			firstTwo[c.order[1]] = true
		end
		t.truthy(firstTwo[2] and firstTwo[4], "tie order should vary between seeds")
	end)

	t.test("only the player whose turn it is may pick a free offering (CAR-06)", function()
		local ps = { newPlayer(1, 50), newPlayer(2, 20) }
		local c = CarouselService.new(ps, Rng.new(1), 0)
		t.eq(CarouselService.currentPlayer(c), 2)
		t.eq(CarouselService.pick(c, 1, 1, 1).reason, "NotYourTurn")
		t.eq(CarouselService.pick(c, 2, 9, 1).reason, "BadArgs")
		t.eq(CarouselService.pick(c, 2, 1, 1).ok, true)
		t.eq(itemCount(ps[2]), 1)
		t.eq(CarouselService.pick(c, 2, 2, 1).reason, "NotYourTurn")
		t.eq(CarouselService.pick(c, 1, 1, 1).reason, "BadArgs", "taken offering")
		t.eq(CarouselService.pick(c, 1, 2, 1).ok, true)
		t.eq(CarouselService.currentPlayer(c), nil)
		t.eq(CarouselService.pick(c, 1, 2, 1).reason, "NotYourTurn")
	end)

	t.test("each pick has 10s; on timeout the server picks a random remaining offering (CAR-03)", function()
		local ps = { newPlayer(1, 10), newPlayer(2, 20), newPlayer(3, 30) }
		local c = CarouselService.new(ps, Rng.new(2), 100)
		CarouselService.update(c, 112.9) -- intro 3s + first pick 10s ends at 113
		t.eq(itemCount(ps[1]), 0)
		CarouselService.update(c, 113)
		t.eq(itemCount(ps[1]), 1)
		t.eq(CarouselService.currentPlayer(c), 2)
		local free = 1
		while c.offerings[free].pickedBy do
			free += 1
		end
		CarouselService.pick(c, 2, free, 114) -- an early pick restarts the clock at 10s
		t.near(c.turnEndsAt, 124)
		CarouselService.update(c, 300)
		for _, p in ps do
			t.eq(itemCount(p), 1, "exactly one component each")
		end
	end)

	-- Carousel inside a match ------------------------------------------------------------------------------
	t.test("1-3 runs a Carousel phase of 3s + 10s per player, then Prep; no combat or damage (CAR-01, CAR-05)", function()
		local match, clock = harness(4)
		match:getPlayer(1).health, match:getPlayer(2).health, match:getPlayer(3).health, match:getPlayer(4).health = 40, 10, 70, 70
		local log: { string } = {}
		match.events.phaseChanged:connect(function(info: any)
			table.insert(log, info.roundId .. ":" .. info.phase .. ":" .. tostring(info.endsAt))
		end)
		clock.t = 70
		match:update()
		t.eq(match.phase, "Carousel")
		t.truthy(table.find(log, "1-3:Carousel:109") ~= nil, table.concat(log, " ")) -- 66 + 3 + 10 x 4
		t.eq(#match.carousel.offerings, 4)

		local router = ActionRouter.new(match, function() return clock.t end)
		t.eq(router:handle(1, "PickCarousel", { index = 1 }).reason, "NotYourTurn")
		t.eq(router:handle(2, "PickCarousel", { index = 1 }).ok, true)
		t.eq(router:handle(2, "PickCarousel", { index = 2 }).reason, "NotYourTurn")
		t.eq(router:handle(1, "BuyUnit", { slot = 1 }).reason, "WrongPhase")

		clock.t = 110
		match:update()
		t.eq(match.phase, "Prep")
		t.eq(match.carousel, nil)
		t.eq(router:handle(1, "PickCarousel", { index = 1 }).reason, "WrongPhase")
		for id = 1, 4 do
			t.eq(itemCount(match:getPlayer(id)), 1, "player " .. id)
			t.eq(match:getPlayer(id).health, id == 1 and 40 or (id == 2 and 10 or 70))
		end
	end)

	t.test("the carousel is replicated in the snapshot with offerings, turn and picker (CAR-07)", function()
		local Snapshot = require(Server.Player.Snapshot)
		local match, clock = harness(2)
		clock.t = 67 -- 2 players: carousel 66..77
		match:update()
		local snap = Snapshot.build(match, 1)
		t.eq(#snap.carousel.offerings, 2)
		t.truthy(snap.carousel.turn == 1 or snap.carousel.turn == 2)
		local router = ActionRouter.new(match, function() return clock.t end)
		clock.t = 70
		match:update()
		local turn = Snapshot.build(match, 1).carousel.turn
		router:handle(turn, "PickCarousel", { index = 1 })
		t.eq(Snapshot.build(match, 1).carousel.offerings[1].p, turn)
	end)

	-- Router: item actions -----------------------------------------------------------------------------------
	t.test("item actions work in Prep and fire OnItemCombined (ITM-02)", function()
		local match, clock = harness(1)
		clock.t = 3
		match:update()
		local combined = 0
		match.deps.onItemCombined = function()
			combined += 1
		end
		local router = ActionRouter.new(match, function() return clock.t end)
		local s = match:getPlayer(1)
		local unitUid
		for _, u in s.units do
			unitUid = u.uid
		end
		local a, b = InventoryService.addItem(s, "club"), InventoryService.addItem(s, "snack")
		t.eq(router:handle(1, "EquipItem", { itemUid = a.uid, unitUid = unitUid }).ok, true)
		t.eq(router:handle(1, "CombineItems", { itemUidA = a.uid, itemUidB = b.uid }).reason, "ItemEquipped")
		t.eq(router:handle(1, "UnequipItem", { itemUid = a.uid }).ok, true)
		t.eq(router:handle(1, "CombineItems", { itemUidA = a.uid, itemUidB = b.uid }).ok, true)
		t.eq(combined, 1)
		t.eq(itemCount(s), 1)
		t.eq(router:handle(1, "EquipItem", { itemUid = "x" }).reason, "BadArgs")
	end)
end
