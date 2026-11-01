--!strict
-- Pool, shop and merge tests (GDD 6.3 to 6.6; SHOP-01..07, MRG-01..05, LOBBY-02).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Units = require(Shared.Data.Units)
local ShopConfig = require(Shared.Config.ShopConfig)
local Rng = require(Shared.Util.Rng)
local Index = require(Shared.Util.Index)
local PlayerState = require(Server.Player.PlayerState)
local UnitPool = require(Server.Economy.UnitPool)
local ShopService = require(Server.Economy.ShopService)
local MergeService = require(Server.Economy.MergeService)
local EconomyService = require(Server.Economy.EconomyService)

-- Pool conservation: remaining + shown in shop + owned (1/3/9 per star) == initial.
local function accounted(pool: any, state: any): number
	local total = UnitPool.total(pool)
	for _, slot in state.shop.slots do
		if type(slot) == "string" then
			total += 1
		end
	end
	for _, u in state.units do
		total += MergeService.copyCount(u.star)
	end
	return total
end

-- Puts a shop slot with `defId` in place so buys are deterministic.
local function stock(state: any, pool: any, defId: string, slot: number)
	UnitPool.take(pool, defId)
	state.shop.slots[slot] = defId
end

return function(t)
	local function newGame(lobby: number): (any, any)
		return UnitPool.new(Units, lobby), PlayerState.new(1, "Tester")
	end

	t.test("pool scales with lobby size: 4 players = 11,10,9,5,5 (LOBBY-02)", function()
		local pool = UnitPool.new(Units, 4)
		t.eq(UnitPool.remaining(pool, "noodle_nugget"), 11)
		t.eq(UnitPool.remaining(pool, "pixel_pup"), 11)
		t.eq(UnitPool.remaining(pool, "wobble_banana"), 10)
		t.eq(UnitPool.remaining(pool, "grumpy_gelato"), 9)
		t.eq(UnitPool.remaining(pool, "sir_slaysalot"), 5)
		t.eq(UnitPool.remaining(pool, "rotzilla_prime"), 5)
		local pool8 = UnitPool.new(Units, 8)
		t.eq(UnitPool.remaining(pool8, "noodle_nugget"), 22)
		t.eq(UnitPool.remaining(pool8, "rotzilla_prime"), 9)
	end)

	t.test("10,000 slot rolls per level land within 2 points of the odds (6.3)", function()
		local rng = Rng.new(12345)
		for level = 1, 10 do
			local pool = UnitPool.new(Units, 8)
			local counts = { 0, 0, 0, 0, 0 }
			for _ = 1, 10000 do
				local defId = ShopService.rollSlot(pool, rng, level) :: string
				counts[pool.costOf[defId]] += 1
				UnitPool.put(pool, defId)
			end
			for cost = 1, 5 do
				t.near(counts[cost] / 100, ShopConfig.odds[level][cost], 2, ("level %d cost %d"):format(level, cost))
			end
		end
	end)

	t.test("refresh fills 5 slots, takes from the pool, and a lock holds the shop", function()
		local pool, state = newGame(4)
		local rng = Rng.new(1)
		ShopService.refresh(state, pool, rng)
		t.eq(#state.shop.slots, 5)
		t.eq(accounted(pool, state), pool.initialTotal)
		local before = table.concat(state.shop.slots, ",")
		ShopService.toggleLock(state)
		ShopService.refresh(state, pool, rng)
		t.eq(table.concat(state.shop.slots, ","), before)
		ShopService.toggleLock(state)
		ShopService.refresh(state, pool, rng)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("reroll costs 2 and rejects without gold", function()
		local pool, state = newGame(4)
		local rng = Rng.new(2)
		t.eq(ShopService.reroll(state, pool, rng).reason, "NotEnoughGold")
		state.gold = 5
		t.eq(ShopService.reroll(state, pool, rng).ok, true)
		t.eq(state.gold, 3)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("buy: spends gold, benches the unit, rejects empty slot and no gold", function()
		local pool, state = newGame(4)
		state.shop.slots = { false, false, false, false, false }
		stock(state, pool, "noodle_nugget", 1)
		t.eq(ShopService.buy(state, 1).reason, "NotEnoughGold")
		state.gold = 3
		local r = ShopService.buy(state, 1)
		t.eq(r.ok, true)
		t.eq(state.gold, 2)
		t.eq(state.units[r.unitUid].bench, 1)
		t.eq(ShopService.buy(state, 1).reason, "EmptySlot")
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("buy: full bench is rejected unless it completes a merge (SHOP-06)", function()
		local pool, state = newGame(4)
		state.gold = 100
		state.shop.slots = { false, false, false, false, false }
		-- Two Nuggets plus seven different units fill the 9-slot bench.
		local fillers = { "noodle_nugget", "noodle_nugget", "sleepy_sock", "moo_moo_mogul", "zippy_zucchini", "pixel_pup", "rizz_rabbit", "wobble_banana", "mini_mod" }
		for i, id in fillers do
			UnitPool.take(pool, id)
			PlayerState.newUnit(state, id, 1, i, nil)
		end
		stock(state, pool, "lag_lizard", 1)
		t.eq(ShopService.buy(state, 1).reason, "BenchFull")
		stock(state, pool, "noodle_nugget", 2)
		local r = ShopService.buy(state, 2)
		t.eq(r.ok, true)
		t.eq(#r.merges, 1)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("three copies merge to star 2, nine to star 3 (MRG-01)", function()
		local pool, state = newGame(8)
		state.gold = 1000
		state.shop.slots = { false, false, false, false, false }
		local last
		for _ = 1, 9 do
			stock(state, pool, "noodle_nugget", 1)
			last = ShopService.buy(state, 1)
			t.eq(last.ok, true)
		end
		local star3 = 0
		local others = 0
		for _, u in state.units do
			if u.star == 3 then
				star3 += 1
			else
				others += 1
			end
		end
		t.eq(star3, 1)
		t.eq(others, 0)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("merge takes a board position and transfers items, overflow to inventory (MRG-02, MRG-03)", function()
		local pool, state = newGame(8)
		state.level = 5
		local a = PlayerState.newUnit(state, "noodle_nugget", 1, nil, { col = 4, row = 2 })
		local b = PlayerState.newUnit(state, "noodle_nugget", 1, 3, nil)
		local c = PlayerState.newUnit(state, "noodle_nugget", 1, 5, nil)
		for _, owner in { a, a, b, b, c } do
			PlayerState.newItem(state, "club").equippedTo = owner.uid
		end
		local events = MergeService.resolve(state, "noodle_nugget")
		t.eq(#events, 1)
		local merged = state.units[events[1].uid]
		t.eq(merged.star, 2)
		t.eq(merged.board.col, 4)
		t.eq(merged.board.row, 2)
		t.eq(#PlayerState.itemsOn(state, merged.uid), 3)
		local loose = 0
		for _, item in state.inventory do
			if item.equippedTo == nil then
				loose += 1
			end
		end
		t.eq(loose, 2)
	end)

	t.test("merge with no board copy uses the leftmost bench slot (MRG-02)", function()
		local _, state = newGame(8)
		PlayerState.newUnit(state, "pixel_pup", 1, 6, nil)
		PlayerState.newUnit(state, "pixel_pup", 1, 2, nil)
		PlayerState.newUnit(state, "pixel_pup", 1, 4, nil)
		local events = MergeService.resolve(state, "pixel_pup")
		t.eq(state.units[events[1].uid].bench, 2)
	end)

	t.test("sell refunds cost * 3^(star-1) and returns copies by count (MRG-05)", function()
		local pool, state = newGame(8)
		local before = pool.initialTotal
		for _, star in { 1, 2, 3 } do
			local id = "wobble_banana"
			UnitPool.take(pool, id) -- unit leaves the pool, then is "owned"
			for _ = 2, MergeService.copyCount(star) do
				UnitPool.take(pool, id)
			end
			local u = PlayerState.newUnit(state, id, star, 1, nil)
			local gold = state.gold
			t.eq(ShopService.sell(state, u.uid, pool).ok, true)
			t.eq(state.gold - gold, 2 * MergeService.copyCount(star))
			t.eq(UnitPool.total(pool), before)
		end
	end)

	t.test("sold unit's items return to the inventory (ITM-06)", function()
		local pool, state = newGame(8)
		local u = PlayerState.newUnit(state, "sleepy_sock", 1, 1, nil)
		UnitPool.take(pool, "sleepy_sock")
		local item = PlayerState.newItem(state, "wand")
		item.equippedTo = u.uid
		ShopService.sell(state, u.uid, pool)
		t.eq(item.equippedTo, nil)
		t.truthy(state.inventory[item.uid])
	end)

	t.test("pool conserved through random buy / sell / merge / reroll", function()
		local pool, state = newGame(4)
		local rng = Rng.new(99)
		state.gold = 100000
		for _ = 1, 400 do
			local action = rng:nextInt(1, 4)
			if action == 1 then
				ShopService.reroll(state, pool, rng)
			elseif action == 2 then
				ShopService.buy(state, rng:nextInt(1, 5))
			elseif action == 3 then
				local list = PlayerState.sortedUnits(state)
				if #list > 0 then
					ShopService.sell(state, list[rng:nextInt(1, #list)].uid, pool)
				end
			else
				ShopService.refresh(state, pool, rng)
			end
			t.eq(accounted(pool, state), pool.initialTotal, "conservation")
		end
		ShopService.release(state, pool)
	end)

	t.test("starter unit is a free 1-cost bench unit (LVL-05)", function()
		local pool, state = newGame(4)
		local unit = ShopService.grantStarterUnit(state, pool, Rng.new(5)) :: any
		t.eq(Index.unit(unit.defId).cost, 1)
		t.eq(unit.bench, 1)
		t.eq(state.gold, 0)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("income paid then shop refresh keeps ECON-02 ordering inputs intact", function()
		local _, state = newGame(4)
		state.gold = 10
		local b = EconomyService.payIncome(state, 2)
		t.eq(b.interest, 1)
		t.eq(state.gold, 10 + 2 + 1)
	end)

	-- Buying both copies when the bench is full (D-54) ---------------------------------------------------
	local BENCH_FILLERS = { "noodle_nugget", "sleepy_sock", "moo_moo_mogul", "zippy_zucchini", "pixel_pup", "rizz_rabbit", "wobble_banana", "mini_mod", "lag_lizard" }

	local function fullBench(pool: any, state: any)
		state.shop.slots = { false, false, false, false, false }
		for i, id in BENCH_FILLERS do
			UnitPool.take(pool, id)
			PlayerState.newUnit(state, id, 1, i, nil)
		end
	end

	t.test("full bench, one owned copy, two copies in the shop: one tap buys both and merges", function()
		local pool, state = newGame(4)
		fullBench(pool, state)
		state.gold = 10
		stock(state, pool, "noodle_nugget", 1)
		stock(state, pool, "noodle_nugget", 3)
		local r = ShopService.buy(state, 1)
		t.eq(r.ok, true)
		t.eq(#r.merges, 1)
		t.eq(state.gold, 8, "pays for both copies")
		t.eq(state.shop.slots[1], false)
		t.eq(state.shop.slots[3], false)
		local stars = {}
		for _, u in state.units do
			if u.defId == "noodle_nugget" then
				table.insert(stars, u.star)
			end
		end
		t.eq(table.concat(stars, ","), "2")
		t.eq(PlayerState.firstOpenBench(state), nil, "the bench is still full, nothing needed a free slot")
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("buying both costs twice the price and needs the gold for both", function()
		local pool, state = newGame(4)
		fullBench(pool, state)
		UnitPool.take(pool, "grumpy_gelato")
		PlayerState.newUnit(state, "grumpy_gelato", 1, nil, { col = 1, row = 1 }) -- the owned copy is on the board
		stock(state, pool, "grumpy_gelato", 2)
		stock(state, pool, "grumpy_gelato", 5)
		state.gold = 5
		t.eq(ShopService.buy(state, 2).reason, "NotEnoughGold")
		t.eq(state.gold, 5)
		t.eq(state.shop.slots[2], "grumpy_gelato")
		t.eq(state.shop.slots[5], "grumpy_gelato")
		state.gold = 6
		local r = ShopService.buy(state, 5)
		t.eq(r.ok, true)
		t.eq(state.gold, 0)
		for _, u in state.units do
			if u.defId == "grumpy_gelato" then
				t.eq(u.star, 2)
				t.truthy(u.board and u.board.col == 1, "the merged unit keeps the board cell")
			end
		end
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("no merge possible: a full bench still rejects the buy", function()
		local pool, state = newGame(4)
		fullBench(pool, state)
		state.gold = 50
		-- Only one copy in the shop, one owned.
		stock(state, pool, "noodle_nugget", 1)
		t.eq(ShopService.buy(state, 1).reason, "BenchFull")
		-- Two copies in the shop but none owned: two buys would not complete a merge.
		stock(state, pool, "cash_cat", 2)
		stock(state, pool, "cash_cat", 3)
		t.eq(ShopService.buy(state, 2).reason, "BenchFull")
		t.eq(state.gold, 50)
		t.eq(accounted(pool, state), pool.initialTotal)
	end)

	t.test("with two copies owned and a full bench, one buy completes the merge as before (SHOP-06)", function()
		local pool, state = newGame(4)
		fullBench(pool, state) -- one Noodle Nugget is on the bench
		UnitPool.take(pool, "noodle_nugget")
		PlayerState.newUnit(state, "noodle_nugget", 1, nil, { col = 2, row = 1 }) -- the second copy, on the board
		stock(state, pool, "noodle_nugget", 1)
		stock(state, pool, "noodle_nugget", 2)
		state.gold = 10
		local r = ShopService.buy(state, 1)
		t.eq(r.ok, true)
		t.eq(state.gold, 9, "only one copy was needed")
		t.eq(state.shop.slots[2], "noodle_nugget", "the other shop copy stays")
		t.eq(accounted(pool, state), pool.initialTotal)
	end)
end
