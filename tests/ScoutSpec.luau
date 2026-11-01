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

	t.test("the scoreboard lists a player's loose items but not the ones on units", function()
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
		local unit = PlayerState.newUnit(other, "noodle_nugget", 1, nil, { col = 1, row = 4 })
		local worn = PlayerState.newItem(other, "club")
		worn.equippedTo = unit.uid
		PlayerState.newItem(other, "wand")
		PlayerState.newItem(other, "snack")
		for _, p in Snapshot.build(match, 1).players do
			if p.id == 2 then
				t.eq(#p.inv, 2)
				t.eq(p.inv[1], "wand")
				t.eq(p.inv[2], "snack")
			end
		end
	end)

	t.test("the fight roster carries each unit's items so they stay on show in Combat", function()
		local CombatSim = require(Server.Combat.CombatSim)
		local function spec(items: { string }): any
			return { name = "Nugget", defId = "noodle_nugget", cost = 1, archetype = "Fighter", star = 1, cell = { col = 4, row = 4 }, items = items }
		end
		local sim = CombatSim.new({ seed = 1, home = { spec({ "club" }) }, away = { spec({}) }, record = true })
		local found = false
		for _, desc in sim.roster do
			if desc.items and desc.items[1] == "club" then
				found = true
			end
		end
		t.truthy(found)
	end)
end
