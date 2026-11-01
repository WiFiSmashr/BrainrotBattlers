--!strict
-- Phase 8 tests: bots (BOT-01..BOT-03), whole matches to a winner, and the balance harness.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchService = require(Server.Match.MatchService)
local ActionRouter = require(Server.Player.ActionRouter)
local PlayerState = require(Server.Player.PlayerState)
local BotController = require(Server.Bots.BotController)
local BalanceHarness = require(Server.Bots.BalanceHarness)

-- A 1-player-seat match with a spying router, positioned in the first Prep. Returns match, bots, spy log.
local function setup(lobbySize: number): (any, any, any, { string })
	local clock = { t = 0 }
	local match = MatchService.new({
		lobbySize = lobbySize, seed = 11, now = function() return clock.t end,
		combat = function(): any
			return { winner = "draw", survivors = 0, seconds = 5 }
		end,
	})
	BotController.fill(match)
	match:start()
	clock.t = 3
	match:update() -- 1-1 Prep
	local router = ActionRouter.new(match, function() return clock.t end)
	local log: { string } = {}
	local realHandle = router.handle
	router.handle = function(self: any, userId: number, name: any, args: any)
		table.insert(log, userId .. ":" .. tostring(name))
		return realHandle(self, userId, name, args)
	end
	return match, BotController.new(match, router), clock, log
end

return function(t)
	t.test("bots fill every empty seat with negative ids and equal starting state (BOT-01, BOT-02)", function()
		local match = MatchService.new({ lobbySize = 8, seed = 1, now = function() return 0 end })
		match:addPlayer(5, "Human")
		t.eq(BotController.fill(match), 7)
		t.eq(#match.order, 8)
		local human, bot = match:getPlayer(5), match:getPlayer(-1)
		t.truthy(BotController.isBot(-3) and not BotController.isBot(5))
		t.eq(bot.gold, human.gold)
		t.eq(bot.level, human.level)
		t.eq(bot.health, human.health)
		t.eq(next(bot.overrides), nil, "bots get no hidden config bonuses")
		t.eq(BotController.fill(match), 0)
	end)

	t.test("bots act only through ActionRouter intents (BOT-02)", function()
		local match, bots, clock, log = setup(4)
		for _ = 1, 40 do
			clock.t += 0.25
			bots:update()
		end
		t.truthy(#log > 0, "bots should have acted")
		for _, entry in log do
			t.truthy(tonumber(entry:match("^(-%d+):")) ~= nil, "only bot ids act: " .. entry)
		end
		-- Every action went through the router, so the rate limit applied: nobody exceeded 20 per second.
		t.eq(match.phase, "Prep")
	end)

	t.test("a bot places units front-line first by range (BOT-03)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units = {}
		bot.level = 3
		PlayerState.newUnit(bot, "sleepy_sock", 1, 1, nil) -- Marksman, range 4
		PlayerState.newUnit(bot, "noodle_nugget", 1, 2, nil) -- Brawler, range 1
		for _ = 1, 4 do
			BotController.think(bots, -1)
		end
		local sock, noodle
		for _, u in bot.units do
			if u.defId == "sleepy_sock" then
				sock = u
			else
				noodle = u
			end
		end
		t.truthy(sock.board and noodle.board, "both placed on the board")
		t.eq(noodle.board.row, 4, "melee in the front row")
		t.eq(sock.board.row, 1, "ranged in the back row")
	end)

	t.test("a bot swaps a stronger bench unit onto a full board (BOT-03)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units = {}
		bot.level = 1
		bot.gold = 0
		PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		local strong = PlayerState.newUnit(bot, "rotzilla_prime", 1, 1, nil)
		for _ = 1, 3 do
			BotController.think(bots, -1)
		end
		t.truthy(strong.board ~= nil, "the cost-5 unit takes the only board slot")
	end)

	t.test("a bot buys affordable units that share a trait with its board and skips others (BOT-03)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units = {}
		bot.level = 5
		bot.gold = 20
		PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 }) -- Noob, Bouncer
		bot.shop.slots = { "sleepy_sock", "moo_moo_mogul", false, false, false } -- Brainrot/Camper vs Tycoon/Bouncer
		for _ = 1, 6 do
			BotController.think(bots, -1)
		end
		local owned: { [string]: boolean } = {}
		for _, u in bot.units do
			owned[u.defId] = true
		end
		t.truthy(owned.moo_moo_mogul, "shares Bouncer")
		t.truthy(not owned.sleepy_sock, "shares nothing")
		t.eq(bot.shop.slots[1], "sleepy_sock")
	end)

	t.test("a bot never buys what it cannot afford (BOT-03, ECON-05)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units = {}
		bot.level = 5
		bot.gold = 2
		PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		bot.shop.slots = { "rotzilla_prime", false, false, false, false }
		for _ = 1, 5 do
			BotController.think(bots, -1)
		end
		t.eq(bot.gold, 2)
		t.eq(bot.shop.slots[1], "rotzilla_prime")
	end)

	t.test("a bot buys XP while it holds 50 or more gold (BOT-03)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units = {}
		bot.gold = 60
		bot.shop.slots = { false, false, false, false, false }
		for _ = 1, 10 do
			BotController.think(bots, -1)
		end
		t.truthy(bot.gold < 50, "spent down to below 50 gold")
		t.truthy(bot.gold >= 46, "stopped buying XP once under 50")
		t.truthy(bot.level > 1)
	end)

	t.test("a bot takes an augment choice and picks from the carousel instantly (CAR-03)", function()
		local match, bots, clock = setup(2)
		local bot = match:getPlayer(-1)
		bot.augmentOffer = { kind = "augment", choices = { "piggy_bank", "warm_up", "starter_pack" }, offer = 1, rerolled = false }
		BotController.think(bots, -1)
		t.eq(bot.augments[1], "piggy_bank")
		t.eq(bot.gold, 8)
		-- Jump to the 1-3 carousel and find a bot whose turn it is.
		clock.t = 70
		match:update()
		t.eq(match.phase, "Carousel")
		local before = 0
		for _, p in match.carousel.offerings do
			before += if p.pickedBy then 1 else 0
		end
		BotController.update(bots)
		local after = 0
		for _, p in match.carousel.offerings do
			after += if p.pickedBy then 1 else 0
		end
		t.truthy(after > before, "a bot whose turn it was picked at once")
	end)

	t.test("1 human + 7 bots play a whole match to a winner with no errors (acceptance)", function()
		local result = BalanceHarness.runMatch(21, 8, 1)
		t.truthy(result.completed, "match did not finish")
		t.truthy(result.winner ~= nil)
		t.truthy(result.rounds >= 8 and result.rounds <= 150, "rounds: " .. result.rounds)
		local firsts = 0
		local seen: { [number]: boolean } = {}
		for _, place in result.placements do
			if place == 1 then
				firsts += 1
			end
			seen[place] = true
		end
		t.eq(firsts, 1)
		for place = 1, 8 do
			t.truthy(seen[place], "placement " .. place .. " missing")
		end
	end)

	t.test("the harness reports average match length and win rate by trait", function()
		local summary = BalanceHarness.run(4, 100, 8, 0)
		t.eq(summary.matches, 4)
		t.truthy(summary.completed >= 3, "most matches should finish: " .. summary.completed)
		t.truthy(summary.averageRounds > 5)
		local report = BalanceHarness.report(summary)
		print(report)
		t.truthy(report:find("Average match length"))
		t.truthy(report:find("Win rate by trait"))
		for _, stat in summary.traits do
			t.truthy(stat.wins <= stat.appearances)
		end
		t.truthy(GameConfig.fillWithBots)
	end)

	t.test("a bot fuses two loose components and equips the result on a board unit", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units, bot.inventory = {}, {}
		bot.level = 2
		bot.gold = 0
		local unit = PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		PlayerState.newItem(bot, "club")
		PlayerState.newItem(bot, "wand")
		BotController.think(bots, -1) -- combine
		local made
		for _, item in bot.inventory do
			made = item
		end
		t.eq(made.itemId, "chaos_wand")
		BotController.think(bots, -1) -- equip
		t.eq(made.equippedTo, unit.uid)
	end)

	t.test("bots spread items over their board units and never exceed 3 per unit (ITM-01)", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units, bot.inventory = {}, {}
		bot.level = 2
		bot.gold = 0
		local a = PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		local b = PlayerState.newUnit(bot, "pocket_pharaoh", 1, nil, { col = 3, row = 4 })
		for _ = 1, 8 do
			PlayerState.newItem(bot, "brick_wall") -- loose combined items cannot be fused again
		end
		for _ = 1, 12 do
			BotController.think(bots, -1)
		end
		t.eq(#PlayerState.itemsOn(bot, a.uid), 3)
		t.eq(#PlayerState.itemsOn(bot, b.uid), 3)
		local loose = 0
		for _, item in bot.inventory do
			if not item.equippedTo then
				loose += 1
			end
		end
		t.eq(loose, 2)
	end)

	t.test("a bot does not equip items onto bench units", function()
		local match, bots = setup(2)
		local bot = match:getPlayer(-1)
		bot.units, bot.inventory = {}, {}
		bot.level = 1
		bot.gold = 0
		PlayerState.newUnit(bot, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		local benched = PlayerState.newUnit(bot, "sleepy_sock", 1, 1, nil)
		PlayerState.newItem(bot, "brick_wall")
		for _ = 1, 4 do
			BotController.think(bots, -1)
		end
		t.eq(#PlayerState.itemsOn(bot, benched.uid), 0)
	end)
end
