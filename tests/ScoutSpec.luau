--!strict
-- Scouting another player's board (D-79): the snapshot's public scoreboard carries every player's board.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local MatchService = require(Server.Match.MatchService)
local PlayerState = require(Server.Player.PlayerState)
local Snapshot = require(Server.Player.Snapshot)

return function(t)
	t.test("every player's board and bench, stars, items and seat are in the scoreboard", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 2, seed = 8, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(1, "A")
		match:addPlayer(2, "B")
		match:start()
		local other = match:getPlayer(2) :: PlayerState.State
		local unit = PlayerState.newUnit(other, "noodle_nugget", 2, nil, { col = 3, row = 4 })
		PlayerState.newUnit(other, "noodle_nugget", 1, 1) -- on the bench
		local item = PlayerState.newItem(other, "club")
		item.equippedTo = unit.uid

		local snapshot = Snapshot.build(match, 1)
		local entry
		for _, p in snapshot.players do
			if p.id == 2 then
				entry = p
			end
		end
		t.truthy(entry ~= nil)
		t.eq(entry.seat, other.seat)
		t.eq(#entry.board, 2, "the board unit and the bench unit")
		t.eq(entry.board[1].d, "noodle_nugget")
		t.eq(entry.board[1].s, 2)
		t.eq(entry.board[1].c, 3)
		t.eq(entry.board[1].r, 4)
		t.eq(entry.board[1].i[1], "club")
		t.eq(entry.board[2].b, 1, "the bench unit carries its slot")
	end)
end
