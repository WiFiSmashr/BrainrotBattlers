--!strict
-- Main menu tests: queueing, starting a match, bot fill, one match at a time, returning to the menu
-- and cleanup (D-70 to D-73). Runs the SessionService on a fake clock with a real MatchService.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local MatchService = require(Server.Match.MatchService)
local SessionService = require(Server.Match.SessionService)
local ActionRouter = require(Server.Player.ActionRouter)
local BotController = require(Server.Bots.BotController)

local LOBBY = 4
local WAIT = 10

type Rig = { session: any, clock: { t: number }, started: number, cleaned: number, sent: { [number]: { any } }, focus: { { number } } }

local function rig(): Rig
	local clock = { t = 0 }
	local r: Rig = { session = nil, clock = clock, started = 0, cleaned = 0, sent = {}, focus = {} }
	r.session = SessionService.new({
		lobbySize = LOBBY, minPlayers = 1, waitSeconds = WAIT, fillWithBots = true,
		now = function() return clock.t end,
		newRun = function()
			local match = MatchService.new({
				lobbySize = LOBBY, seed = 5, now = function() return clock.t end,
				combat = function(): any
					return { winner = "draw", survivors = 0, seconds = 5 }
				end,
			})
			local router = ActionRouter.new(match, function() return clock.t end)
			return { match = match, router = router, bots = BotController.new(match, router) }
		end,
		fillBots = BotController.fill,
		onStart = function() r.started += 1 end,
		onCleanup = function() r.cleaned += 1 end,
		focusPlot = function(userId, seat) table.insert(r.focus, { userId, seat or 0 }) end,
		notify = function(userId, info)
			r.sent[userId] = r.sent[userId] or {}
			table.insert(r.sent[userId], info)
		end,
	})
	return r
end

return function(t)
	t.test("a new player is in the menu and nothing starts without a queue", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		t.eq(r.session:getStatus(1), "Menu")
		r.clock.t = 100
		r.session:update()
		t.eq(r.started, 0)
		t.eq(r.session:info(1).queued, 0)
	end)

	t.test("joining and leaving the queue, with no double joins", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		t.truthy(r.session:handle(1, "JoinQueue", {}).ok)
		t.eq(r.session:getStatus(1), "Queued")
		t.eq(r.session:handle(1, "JoinQueue", {}).reason, "AlreadyQueued")
		t.eq(r.session:queueSize(), 1)
		t.truthy(r.session:handle(1, "LeaveQueue", {}).ok)
		t.eq(r.session:getStatus(1), "Menu")
		t.eq(r.session:handle(1, "LeaveQueue", {}).reason, "NotQueued")
		t.eq(r.session:queueSize(), 0)
	end)

	t.test("the match starts only after the wait, and bots fill the empty seats", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:handle(1, "JoinQueue", {})
		t.near(r.session:info(1).startsAt :: number, WAIT, 1e-9)
		r.clock.t = WAIT - 1
		r.session:update()
		t.eq(r.started, 0, "no early start")
		r.clock.t = WAIT
		r.session:update()
		t.eq(r.started, 1)
		t.eq(r.session:getStatus(1), "InMatch")
		local run = r.session:currentRun()
		t.eq(#run.match.order, LOBBY)
		t.truthy(run.match.phase ~= "Lobby")
		t.eq(r.session:queueSize(), 0)
	end)

	t.test("a full queue starts at once", function()
		local r = rig()
		for id = 1, LOBBY do
			r.session:addPlayer(id, "P" .. id)
			r.session:handle(id, "JoinQueue", {})
		end
		r.session:update()
		t.eq(r.started, 1)
		local run = r.session:currentRun()
		for id = 1, LOBBY do
			t.eq(r.session:getStatus(id), "InMatch")
			t.truthy(run.match:getPlayer(id) ~= nil)
		end
	end)

	t.test("game actions go to the match only for players in it", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:addPlayer(2, "B")
		r.session:handle(1, "JoinQueue", {})
		t.eq(r.session:handle(1, "BuyUnit", { slot = 1 }).reason, "NotInMatch", "queued, not playing yet")
		r.clock.t = WAIT
		r.session:update()
		local reply = r.session:handle(1, "BuyUnit", { slot = 1 })
		t.truthy(reply.reason ~= "NotInMatch", "forwarded to the router")
		t.eq(r.session:handle(2, "BuyUnit", { slot = 1 }).reason, "NotInMatch", "in the menu")
	end)

	t.test("a player who queues during a match waits for the next one", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:addPlayer(2, "B")
		r.session:handle(1, "JoinQueue", {})
		r.clock.t = WAIT
		r.session:update()
		local first = r.session:currentRun()
		r.session:handle(2, "JoinQueue", {})
		t.truthy(r.session:info(2).matchRunning)
		r.clock.t = WAIT * 5
		r.session:update()
		t.eq(r.started, 1, "no second match while one is running")
		t.eq(r.session:getStatus(2), "Queued")
		t.truthy(r.session:currentRun() == first)
	end)

	t.test("Back to Menu only once eliminated or the match is over, then the next match can start", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:addPlayer(2, "B")
		r.session:handle(1, "JoinQueue", {})
		r.clock.t = WAIT
		r.session:update()
		t.eq(r.session:handle(1, "BackToMenu", {}).reason, "MatchRunning")
		t.eq(r.session:handle(2, "BackToMenu", {}).reason, "NotInMatch")

		r.session:handle(2, "JoinQueue", {})
		local run = r.session:currentRun()
		run.match.phase = "MatchEnd"
		t.truthy(r.session:handle(1, "BackToMenu", {}).ok)
		t.eq(r.session:getStatus(1), "Menu")
		r.clock.t += 0.1
		r.session:update() -- nobody left in the match: cleaned up, and the queued player's wait restarts
		t.eq(r.cleaned, 1)
		t.truthy(r.session:currentRun() == nil)
		r.clock.t += WAIT + 1
		r.session:update()
		t.eq(r.started, 2)
		t.eq(r.session:getStatus(2), "InMatch")
		t.truthy(r.session:currentRun() ~= run, "a fresh match")
	end)

	t.test("an eliminated player may go back to the menu while the match continues", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:addPlayer(2, "B")
		r.session:handle(1, "JoinQueue", {})
		r.session:handle(2, "JoinQueue", {})
		r.clock.t = WAIT
		r.session:update()
		local run = r.session:currentRun()
		run.match.placements[1] = LOBBY
		t.truthy(r.session:handle(1, "BackToMenu", {}).ok)
		r.session:update()
		t.truthy(r.session:currentRun() == run, "player 2 is still playing")
		t.eq(r.cleaned, 0)
		t.truthy(not r.session:isInMatch(1))
		t.truthy(r.session:isInMatch(2))
	end)

	t.test("a disconnect leaves the queue, or the match, and an empty match is cleaned up", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:addPlayer(2, "B")
		r.session:handle(2, "JoinQueue", {})
		r.session:removePlayer(2)
		t.eq(r.session:queueSize(), 0)
		t.eq(r.session:getStatus(2), nil)

		r.session:handle(1, "JoinQueue", {})
		r.clock.t = WAIT
		r.session:update()
		t.eq(r.started, 1)
		r.session:removePlayer(1)
		r.session:update()
		t.eq(r.cleaned, 1)
		t.truthy(r.session:currentRun() == nil)
	end)

	t.test("the menu is told about status, queue size and the start time", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		r.session:update()
		local first = r.sent[1][#r.sent[1]]
		t.eq(first.status, "Menu")
		t.eq(first.needed, LOBBY)
		r.session:handle(1, "JoinQueue", {})
		r.session:update()
		local queued = r.sent[1][#r.sent[1]]
		t.eq(queued.status, "Queued")
		t.eq(queued.queued, 1)
		t.truthy(queued.startsAt ~= nil)
		r.clock.t = WAIT
		r.session:update()
		t.eq(r.sent[1][#r.sent[1]].status, "InMatch")
	end)

	t.test("ScoutPlot points a player's streaming at a plot, only while they are in a match (D-89)", function()
		local r = rig()
		r.session:addPlayer(1, "A")
		t.eq(r.session:handle(1, "ScoutPlot", { seat = 2 }).reason, "NotInMatch", "in the menu")
		r.session:handle(1, "JoinQueue", {})
		r.clock.t = WAIT
		r.session:update()
		t.truthy(r.session:handle(1, "ScoutPlot", { seat = 2 }).ok)
		t.eq(r.focus[1][1], 1)
		t.eq(r.focus[1][2], 2)
		t.truthy(r.session:handle(1, "ScoutPlot", {}).ok, "no seat goes back to their own plot")
		t.eq(r.focus[2][2], 0)
		t.eq(r.session:handle(1, "ScoutPlot", { seat = 0 }).reason, "BadArgs")
		t.eq(r.session:handle(1, "ScoutPlot", { seat = 1.5 }).reason, "BadArgs")
		t.eq(r.session:handle(1, "ScoutPlot", { seat = "x" }).reason, "BadArgs")
	end)
end
