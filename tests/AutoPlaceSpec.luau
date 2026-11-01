--!strict
-- Auto-placement at the end of Prep (D-75): free board slots are filled from the left of the bench.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local PlayerState = require(Server.Player.PlayerState)
local AutoPlace = require(Server.Player.AutoPlace)
local MatchService = require(Server.Match.MatchService)

return function(t)
	t.test("leftmost bench units fill the board up to the level, and no further", function()
		local state = PlayerState.new(1, "A")
		state.level = 3
		local a = PlayerState.newUnit(state, "noodle_nugget", 1, 2)
		local b = PlayerState.newUnit(state, "noodle_nugget", 1, 1)
		local c = PlayerState.newUnit(state, "noodle_nugget", 1, 5)
		local d = PlayerState.newUnit(state, "noodle_nugget", 1, 7)
		t.eq(AutoPlace.fill(state), 3)
		t.truthy(b.board and a.board and c.board, "slots 1, 2 and 5 are played")
		t.truthy(d.board == nil and d.bench == 7, "the rightmost stays on the bench")
		t.eq(PlayerState.boardCount(state), 3)
		t.eq(AutoPlace.fill(state), 0, "already full")
	end)

	t.test("it tops up a partly filled board and leaves a full one alone", function()
		local state = PlayerState.new(1, "A")
		state.level = 2
		PlayerState.newUnit(state, "noodle_nugget", 1, nil, { col = 4, row = 4 })
		local benched = PlayerState.newUnit(state, "noodle_nugget", 1, 3)
		t.eq(AutoPlace.fill(state), 1)
		t.truthy(benched.board ~= nil)
		state.level = 1
		local extra = PlayerState.newUnit(state, "noodle_nugget", 1, 1)
		t.eq(AutoPlace.fill(state), 0)
		t.truthy(extra.bench == 1)
	end)

	t.test("the match fills the board when Prep ends", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 2, seed = 3, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(1, "A")
		match:addPlayer(2, "B")
		match:start()
		clock.t = 3
		match:update() -- Prep
		local state = match:getPlayer(1) :: PlayerState.State
		local unit = PlayerState.newUnit(state, "noodle_nugget", 1, 1)
		clock.t = 100
		match:update() -- into Combat
		t.truthy(unit.board ~= nil, "benched unit was played")
	end)
end
