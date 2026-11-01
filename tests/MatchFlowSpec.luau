--!strict
-- Phase 3 tests: schedule, monsters, pairing, damage, state machine, ActionRouter.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Rng = require(Shared.Util.Rng)
local Index = require(Shared.Util.Index)
local RoundSchedule = require(Server.Match.RoundSchedule)
local PveBoards = require(Server.Match.PveBoards)
local Pairing = require(Server.Match.Pairing)
local RoundResolver = require(Server.Match.RoundResolver)
local MatchService = require(Server.Match.MatchService)
local ActionRouter = require(Server.Player.ActionRouter)
local PlayerState = require(Server.Player.PlayerState)
local Snapshot = require(Server.Player.Snapshot)

-- Builds a match with a fake clock and a phase log of "round:phase:endsAt".
local function harness(playerCount: number, lobby: number, combat: any?, onDrop: any?)
	local clock = { t = 0 }
	local match = MatchService.new({
		lobbySize = lobby, seed = 42, now = function() return clock.t end,
		combat = combat or function(): any
			return { winner = "draw", survivors = 0, seconds = 5 } -- fixed 5s fights keep the schedule exact
		end,
		onPveDrop = onDrop,
	})
	local log: { string } = {}
	match.events.phaseChanged:connect(function(info: any)
		table.insert(log, ("%s:%s:%s"):format(info.roundId, info.phase, tostring(info.endsAt)))
	end)
	for id = 1, playerCount do
		match:addPlayer(id, "P" .. id)
	end
	match:start()
	return match, clock, log
end

local function advanceTo(match: any, clock: any, t: number)
	clock.t = t
	match:update()
end

return function(t)
	-- RoundSchedule ---------------------------------------------------------------------------
	t.test("global round numbers: 1-4 = 4, 2-1 = 5, 3-1 = 12 (4.2)", function()
		t.eq(RoundSchedule.globalRound(1, 4), 4)
		t.eq(RoundSchedule.globalRound(2, 1), 5)
		t.eq(RoundSchedule.globalRound(2, 7), 11)
		t.eq(RoundSchedule.globalRound(3, 1), 12)
	end)

	t.test("round types, drops and augment offers match 4.2", function()
		local types = {}
		for r = 1, 4 do
			table.insert(types, RoundSchedule.info(1, r).type)
		end
		t.eq(table.concat(types, ","), "pve,pve,carousel,pve")
		types = {}
		for r = 1, 7 do
			table.insert(types, RoundSchedule.info(2, r).type)
		end
		t.eq(table.concat(types, ","), "pvp,pvp,pve,carousel,pvp,pvp,pvp")
		t.eq(RoundSchedule.info(1, 2).drops, 1)
		t.eq(RoundSchedule.info(1, 4).drops, 1)
		t.eq(RoundSchedule.info(3, 3).drops, 2)
		t.eq(RoundSchedule.info(2, 1).augmentOffer, 1)
		t.eq(RoundSchedule.info(3, 2).augmentOffer, 2)
		t.eq(RoundSchedule.info(4, 2).augmentOffer, 3)
		t.eq(RoundSchedule.info(2, 2).augmentOffer, nil)
	end)

	t.test("next round wraps stages: 1-4 -> 2-1, 2-7 -> 3-1", function()
		local s, r = RoundSchedule.next(1, 4)
		t.eq(s * 10 + r, 21)
		s, r = RoundSchedule.next(2, 7)
		t.eq(s * 10 + r, 31)
	end)

	t.test("prep and carousel lengths (4.3, CAR-05)", function()
		t.eq(RoundSchedule.prepSeconds(RoundSchedule.info(1, 1)), 20)
		t.eq(RoundSchedule.prepSeconds(RoundSchedule.info(2, 2)), 25)
		t.eq(RoundSchedule.prepSeconds(RoundSchedule.info(2, 1)), 40)
		t.eq(RoundSchedule.carouselSeconds(8), 35)
	end)

	-- PvE monsters ------------------------------------------------------------------------------
	t.test("monster formulas (4.6)", function()
		t.eq(PveBoards.count(1), 1)
		t.eq(PveBoards.count(2), 2)
		t.eq(PveBoards.count(4), 3)
		t.eq(PveBoards.count(30), 8)
		local m = PveBoards.build(10)[1]
		t.eq(m.health, 250 + 600)
		t.eq(m.ad, 12 + 30)
		t.near(m.attackSpeed, 0.6)
	end)

	-- Player damage and placement ----------------------------------------------------------------
	t.test("player damage = stageBase + survivors; doubles per round after 40 (4.5)", function()
		t.eq(RoundResolver.damage(2, 5, 3), 5)
		t.eq(RoundResolver.damage(3, 12, 1), 5)
		t.eq(RoundResolver.damage(5, 30, 2), 10)
		t.eq(RoundResolver.damage(9, 30, 4), 14)
		t.eq(RoundResolver.damage(9, 40, 4), 14)
		t.eq(RoundResolver.damage(9, 41, 4), 28)
		t.eq(RoundResolver.damage(9, 42, 4), 56)
	end)

	t.test("same-round eliminations: lower health places lower (4.5)", function()
		local places = RoundResolver.rank({ { userId = 1, health = -2 }, { userId = 2, health = -9 }, { userId = 3, health = 0 } }, 5, Rng.new(1))
		t.eq(places[2], 5)
		t.eq(places[1], 4)
		t.eq(places[3], 3)
	end)

	-- Pairing -------------------------------------------------------------------------------------
	t.test("pairing never repeats the last pairing when avoidable (PAIR-01)", function()
		for _, n in { 4, 6, 8 } do
			local ids = {}
			for i = 1, n do
				table.insert(ids, i)
			end
			local rng = Rng.new(n)
			local last: { [number]: number } = {}
			local homes: { [number]: number } = {}
			for _ = 1, 60 do
				local fights = Pairing.pair(ids, last, homes, rng)
				t.eq(#fights, n / 2)
				local seen: { [number]: boolean } = {}
				for _, f in fights do
					t.truthy(last[f.home] ~= f.away, "repeat pairing with " .. n .. " players")
					t.truthy(not seen[f.home] and not seen[f.away], "player paired twice")
					seen[f.home], seen[f.away] = true, true
				end
				for _, f in fights do
					homes[f.home] = (homes[f.home] or 0) + 1
					last[f.home], last[f.away] = f.away, f.home
				end
			end
		end
	end)

	t.test("odd counts: exactly one ghost fight of another living player (PAIR-02)", function()
		for _, n in { 3, 5, 7 } do
			local ids = {}
			for i = 1, n do
				table.insert(ids, i)
			end
			local rng = Rng.new(n)
			local last: { [number]: number } = {}
			local homes: { [number]: number } = {}
			for _ = 1, 30 do
				local fights = Pairing.pair(ids, last, homes, rng)
				local ghosts = 0
				for _, f in fights do
					if f.ghost then
						ghosts += 1
						t.truthy(f.away ~= f.home, "ghost of self with company")
					end
					homes[f.home] = (homes[f.home] or 0) + 1
					last[f.home] = f.away
					if not f.ghost then
						last[f.away] = f.home
					end
				end
				t.eq(ghosts, 1)
				t.eq(#fights, (n + 1) / 2)
			end
		end
	end)

	t.test("home goes to whoever has been home less; ties vary (PAIR-03)", function()
		local rng = Rng.new(3)
		local homes = { [1] = 0, [2] = 0 }
		for _ = 1, 20 do
			local f = Pairing.pair({ 1, 2 }, {}, homes, rng)[1]
			homes[f.home] += 1
			t.truthy(math.abs(homes[1] - homes[2]) <= 1, "home counts drifted")
		end
	end)

	t.test("a lone player ghosts themself", function()
		local f = Pairing.pair({ 7 }, {}, {}, Rng.new(1))
		t.eq(#f, 1)
		t.truthy(f[1].ghost and f[1].away == 7)
	end)

	-- MatchService ---------------------------------------------------------------------------------
	t.test("solo match plays 1-1 through 2-3 on schedule (acceptance)", function()
		local match, clock, log = harness(1, 4)
		advanceTo(match, clock, 215)
		local expected = {
			"1-1:MatchStart:3", "1-1:Prep:23", "1-1:Combat:28", "1-1:Resolve:32",
			"1-2:Prep:57", "1-2:Combat:62", "1-2:Resolve:66",
			"1-3:Carousel:73", "1-3:Prep:98",
			"1-4:Prep:123", "1-4:Combat:128", "1-4:Resolve:132",
			"2-1:Prep:172", "2-1:Combat:177", "2-1:Resolve:181",
			"2-2:Prep:206", "2-2:Combat:211", "2-2:Resolve:215",
			"2-3:Prep:240",
		}
		t.eq(table.concat(log, " "), table.concat(expected, " "))
		t.eq(match.phase, "Prep")
	end)

	t.test("carousel rounds have no Combat or Resolve (CAR-01)", function()
		local match, clock, log = harness(1, 4)
		advanceTo(match, clock, 100)
		local sawCarousel = false
		for _, line in log do
			sawCarousel = sawCarousel or line:find("^1%-3:Carousel") ~= nil
			t.truthy(not line:find("^1%-3:Combat") and not line:find("^1%-3:Resolve"), line)
		end
		t.truthy(sawCarousel)
	end)

	t.test("starter unit, passive XP and income at Prep start (LVL-05, LVL-02, ECON-02)", function()
		local match, clock = harness(1, 4)
		local p = match:getPlayer(1)
		local starter
		for _, u in p.units do
			starter = u
		end
		t.eq(Index.unit(starter.defId).cost, 1)
		local incomes = {}
		match.events.income:connect(function(_id: number, b: any)
			table.insert(incomes, b.total)
		end)
		advanceTo(match, clock, 33) -- into 1-2 Prep
		t.eq(incomes[1], 0) -- 1-1: no income
		t.eq(incomes[2], 2) -- 1-2: base 2
		t.eq(p.level, 2) -- passive XP 2 -> level 2
		t.eq(#p.shop.slots, 5)
	end)

	t.test("PvE wins report base drops 0/1/1/2 at 1-1, 1-2, 1-4, 2-3 (ITM-10)", function()
		local drops = {}
		local function winAll(): any
			return { winner = "home", survivors = 1, seconds = 5 }
		end
		local match, clock = harness(1, 4, winAll, function(_state: any, count: number)
			table.insert(drops, count)
		end)
		advanceTo(match, clock, 240 + 49) -- through 2-3 Prep, Combat, Resolve
		t.eq(table.concat(drops, ","), "0,1,1,2") -- called on every PvE win; the service adds extras
	end)

	t.test("PvP loser takes damage, winner streaks, elimination ends the match (4.5)", function()
		-- Player 1 always wins; player 2 loses every PvP round.
		local function p1Wins(fight: any): any
			local winner = if fight.home.userId == 1 then "home" else "away"
			return { winner = winner, survivors = 3, seconds = 5 }
		end
		local match, clock = harness(2, 2, p1Wins)
		match:getPlayer(2).health = 4
		local ended = false
		match.events.matchEnded:connect(function()
			ended = true
		end)
		advanceTo(match, clock, 200) -- 2-1 Resolve has run; 2-2 Prep is under way
		t.eq(match:getPlayer(1).health, 100)
		t.eq(match:getPlayer(1).streak.kind, "win")
		t.eq(match.placements[2], 2)
		t.eq(match.placements[1], 1)
		t.eq(match.phase, "MatchEnd")
		t.truthy(ended)
	end)

	t.test("draws deal no damage and change no streak (CMB-11)", function()
		local match, clock = harness(2, 2, function(): any
			return { winner = "draw", survivors = 0, seconds = 5 }
		end)
		advanceTo(match, clock, 200)
		t.eq(match:getPlayer(1).health, 100)
		t.eq(match:getPlayer(2).health, 100)
		t.eq(match:getPlayer(1).streak.kind, "none")
	end)

	t.test("ghost fights never damage the ghost's owner (PAIR-02)", function()
		-- Everyone's "home" side loses; with 3 players the ghost fighter is the only home loser
		-- whose opponent is not a real player, but only real fighters take damage.
		local match, clock = harness(3, 3, function(): any
			return { winner = "away", survivors = 2, seconds = 5 }
		end)
		advanceTo(match, clock, 200)
		local damaged = 0
		for id = 1, 3 do
			if match:getPlayer(id).health < 100 then
				damaged += 1
			end
		end
		t.eq(damaged, 2) -- one pair home loser + the ghost fighter; the pair's away player and ghost owner are safe
	end)

	t.test("players leaving are eliminated and the last one standing wins", function()
		local match = harness(3, 3)
		match:removePlayer(2)
		t.eq(match.placements[2], 3)
		match:removePlayer(3)
		t.eq(match.placements[3], 2)
		t.eq(match.placements[1], 1)
		t.eq(match.phase, "MatchEnd")
	end)

	t.test("lobby rejects players beyond lobbySize and after start", function()
		local match = MatchService.new({ lobbySize = 2, seed = 1, now = function() return 0 end })
		t.truthy(match:addPlayer(1, "a"))
		t.truthy(match:addPlayer(2, "b"))
		t.eq(match:addPlayer(3, "c"), nil)
		match:start()
		t.eq(match:addPlayer(4, "d"), nil)
	end)

	-- ActionRouter ---------------------------------------------------------------------------------
	t.test("illegal intents are rejected with reasons (ARCH-01)", function()
		local match, clock = harness(2, 2)
		local router = ActionRouter.new(match, function() return clock.t end)
		local toasts: { string } = {}
		match.events.toast:connect(function(_id: number, reason: string)
			table.insert(toasts, reason)
		end)

		t.eq(router:handle(1, "BuyUnit", { slot = 1 }).reason, "WrongPhase") -- MatchStart
		advanceTo(match, clock, 3) -- 1-1 Prep
		t.eq(router:handle(1, "BuyUnit", { slot = 1 }).reason, "NotEnoughGold")
		t.eq(router:handle(1, "BuyUnit", { slot = 0 }).reason, "BadArgs")
		t.eq(router:handle(1, "BuyUnit", nil).reason, "BadArgs")
		t.eq(router:handle(1, "SellUnit", { unitUid = 9999 }).reason, "UnknownUnit")
		t.eq(router:handle(1, "MoveUnit", { unitUid = 1, dest = { kind = "nope" } }).reason, "BadArgs")
		t.eq(router:handle(1, "EquipItem", {}).reason, "BadArgs")
		t.eq(router:handle(1, "Hack", {}).reason, "UnknownAction")
		t.eq(router:handle(99, "BuyXP", {}).reason, "NotInMatch")
		t.eq(router:handle(1, "BuyXP", {}).reason, "NotEnoughGold")
		t.truthy(#toasts >= 8, "rejections must toast")

		advanceTo(match, clock, 24) -- Combat
		t.eq(router:handle(1, "MoveUnit", { unitUid = 1, dest = { kind = "bench", index = 2 } }).reason, "WrongPhase")
	end)

	t.test("legal intents work and flag state dirty", function()
		local match, clock = harness(1, 4)
		local router = ActionRouter.new(match, function() return clock.t end)
		advanceTo(match, clock, 3)
		local dirty = 0
		match.events.stateChanged:connect(function()
			dirty += 1
		end)
		local p = match:getPlayer(1)
		p.gold = 10
		t.eq(router:handle(1, "BuyUnit", { slot = 1 }).ok, true)
		t.eq(router:handle(1, "BuyXP", {}).ok, true)
		t.eq(router:handle(1, "RerollShop", {}).ok, true)
		t.eq(router:handle(1, "ToggleLock", {}).ok, true)
		t.truthy(p.shop.locked)
		local uid
		for _, u in p.units do
			uid = u.uid
		end
		t.eq(router:handle(1, "MoveUnit", { unitUid = uid, dest = { kind = "board", col = 1, row = 1 } }).ok, true)
		t.eq(router:handle(1, "SellUnit", { unitUid = uid }).ok, true)
		t.eq(dirty, 6)
	end)

	t.test("rate limit: 21st intent in one second is rejected (ARCH-01)", function()
		local match, clock = harness(1, 4)
		local router = ActionRouter.new(match, function() return clock.t end)
		advanceTo(match, clock, 3)
		for _ = 1, 20 do
			t.eq(router:handle(1, "ToggleLock", {}).ok, true)
		end
		t.eq(router:handle(1, "ToggleLock", {}).reason, "RateLimited")
		clock.t += 1.01
		t.eq(router:handle(1, "ToggleLock", {}).ok, true)
	end)

	t.test("locked shop survives the next Prep (SHOP-03, SHOP-04)", function()
		local match, clock = harness(1, 4)
		local router = ActionRouter.new(match, function() return clock.t end)
		advanceTo(match, clock, 3)
		router:handle(1, "ToggleLock", {})
		local before = table.concat(match:getPlayer(1).shop.slots, ",")
		advanceTo(match, clock, 33) -- 1-2 Prep
		t.eq(table.concat(match:getPlayer(1).shop.slots, ","), before)
	end)

	t.test("snapshot stays under 4 KB (3.6)", function()
		local match, clock = harness(8, 8)
		advanceTo(match, clock, 3)
		local snap = Snapshot.build(match, 1)
		local json = game:GetService("HttpService"):JSONEncode(snap)
		t.truthy(#json < 4096, "snapshot is " .. #json .. " bytes")
	end)

	t.test("during Combat players can still buy, reroll, level up and lock; board actions stay locked (D-58)", function()
		local match, clock = harness(1, 4)
		local router = ActionRouter.new(match, function() return clock.t end)
		advanceTo(match, clock, 24) -- 1-1 Combat
		t.eq(match.phase, "Combat")
		local p = match:getPlayer(1)
		p.gold = 20
		local benchBefore, boardBefore = 0, 0
		for _, u in p.units do
			if u.board then
				boardBefore += 1
			else
				benchBefore += 1
			end
		end
		t.eq(router:handle(1, "BuyUnit", { slot = 1 }).ok, true)
		t.eq(router:handle(1, "RerollShop", {}).ok, true)
		t.eq(router:handle(1, "BuyXP", {}).ok, true)
		t.eq(router:handle(1, "ToggleLock", {}).ok, true)
		t.truthy(p.shop.locked)
		local benchAfter, boardAfter = 0, 0
		for _, u in p.units do
			if u.board then
				boardAfter += 1
			else
				benchAfter += 1
			end
		end
		t.eq(benchAfter, benchBefore + 1, "the new unit waits on the bench")
		t.eq(boardAfter, boardBefore, "the board is untouched mid-fight")

		local unitUid
		for _, u in p.units do
			unitUid = u.uid
		end
		for _, case in {
			{ "MoveUnit", { unitUid = unitUid, dest = { kind = "bench", index = 9 } } },
			{ "SellUnit", { unitUid = unitUid } },
			{ "EquipItem", { itemUid = 1, unitUid = unitUid } },
			{ "UnequipItem", { itemUid = 1 } },
			{ "CombineItems", { itemUidA = 1, itemUidB = 2 } },
			{ "PickAugment", { index = 1 } },
			{ "RerollAugment", {} },
		} do
			t.eq(router:handle(1, case[1], case[2]).reason, "WrongPhase", case[1])
		end
	end)

	t.test("the shop actions are rejected once Combat is over and before Prep begins", function()
		local match, clock = harness(1, 4)
		local router = ActionRouter.new(match, function() return clock.t end)
		t.eq(router:handle(1, "BuyXP", {}).reason, "WrongPhase") -- MatchStart
		advanceTo(match, clock, 29) -- 1-1 Resolve
		t.eq(match.phase, "Resolve")
		t.eq(router:handle(1, "BuyXP", {}).reason, "WrongPhase")
	end)
end
