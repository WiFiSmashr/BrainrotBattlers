--!strict
-- What a player can do while a fight plays (D-87): rearrange the bench, sell units, equip and combine
-- items; but not field units, pull units off the board, or take items off.

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local MatchService = require(Server.Match.MatchService)
local PlayerState = require(Server.Player.PlayerState)
local ActionRouter = require(Server.Player.ActionRouter)

local function inCombat(): (any, any, any)
	local clock = { t = 0 }
	local match = MatchService.new({
		lobbySize = 1, seed = 6, now = function() return clock.t end,
		combat = function(): any
			return { winner = "draw", survivors = 0, seconds = 5 }
		end,
	})
	match:addPlayer(1, "A")
	match:start()
	clock.t = 3
	match:update() -- Prep
	clock.t = 24
	match:update() -- Combat
	assert(match.phase == "Combat")
	return match, ActionRouter.new(match, function() return clock.t end), clock
end

return function(t)
	t.test("bench units can be swapped and moved mid-fight", function()
		local match, router = inCombat()
		local state = match:getPlayer(1) :: PlayerState.State
		local a = PlayerState.newUnit(state, "noodle_nugget", 1, 3)
		local b = PlayerState.newUnit(state, "sleepy_sock", 1, 4)
		t.truthy(router:handle(1, "MoveUnit", { unitUid = a.uid, dest = { kind = "bench", index = 4 } }).ok)
		t.eq(a.bench, 4)
		t.eq(b.bench, 3, "swapped")
		t.truthy(router:handle(1, "MoveUnit", { unitUid = a.uid, dest = { kind = "bench", index = 9 } }).ok)
		t.eq(a.bench, 9)
	end)

	t.test("nothing is fielded or pulled off the board mid-fight", function()
		local match, router = inCombat()
		local state = match:getPlayer(1) :: PlayerState.State
		local benched = PlayerState.newUnit(state, "noodle_nugget", 1, 3)
		local fielded
		for _, u in state.units do
			if u.board then
				fielded = u
			end
		end
		t.truthy(fielded ~= nil, "the starter was auto-placed when Combat began")
		t.eq(router:handle(1, "MoveUnit", { unitUid = benched.uid, dest = { kind = "board", col = 1, row = 1 } }).reason, "NoFieldInCombat")
		t.eq(router:handle(1, "MoveUnit", { unitUid = fielded.uid, dest = { kind = "bench", index = 8 } }).reason, "NoFieldInCombat")
		t.truthy(benched.bench == 3 and fielded.board ~= nil, "nothing moved")
	end)

	t.test("units can be sold mid-fight", function()
		local match, router = inCombat()
		local state = match:getPlayer(1) :: PlayerState.State
		local unit = PlayerState.newUnit(state, "noodle_nugget", 1, 5)
		local gold = state.gold
		t.truthy(router:handle(1, "SellUnit", { unitUid = unit.uid }).ok)
		t.eq(state.units[unit.uid], nil)
		t.truthy(state.gold > gold)
	end)

	t.test("items can be equipped and combined mid-fight but not taken off", function()
		local match, router = inCombat()
		local state = match:getPlayer(1) :: PlayerState.State
		local unit = PlayerState.newUnit(state, "noodle_nugget", 1, 5)
		local club = PlayerState.newItem(state, "club")
		local wand = PlayerState.newItem(state, "wand")
		local snack = PlayerState.newItem(state, "snack")
		t.truthy(router:handle(1, "EquipItem", { itemUid = snack.uid, unitUid = unit.uid }).ok)
		t.eq(snack.equippedTo, unit.uid)
		t.eq(router:handle(1, "UnequipItem", { itemUid = snack.uid }).reason, "NoUnequipInCombat")
		t.eq(snack.equippedTo, unit.uid, "still equipped")
		t.truthy(router:handle(1, "CombineItems", { itemUidA = club.uid, itemUidB = wand.uid }).ok)
		t.eq(state.inventory[club.uid], nil)
		t.eq(state.inventory[wand.uid], nil)
	end)

	t.test("in Prep all of this still works, including taking items off", function()
		local match, router, clock = inCombat()
		clock.t = 40 -- through Resolve and into the next Prep (1-2)
		match:update()
		t.eq(match.phase, "Prep")
		local state = match:getPlayer(1) :: PlayerState.State
		local unit = PlayerState.newUnit(state, "noodle_nugget", 1, 5)
		local item = PlayerState.newItem(state, "club")
		t.truthy(router:handle(1, "EquipItem", { itemUid = item.uid, unitUid = unit.uid }).ok)
		t.truthy(router:handle(1, "UnequipItem", { itemUid = item.uid }).ok)
	end)
end
