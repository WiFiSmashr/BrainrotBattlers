--!strict
-- Economy tests: worked examples A to D (GDD 5.7), ECON-01/04/05/06, levels (LVL-01..04).

local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local PlayerState = require(Server.Player.PlayerState)
local EconomyService = require(Server.Economy.EconomyService)
local LevelService = require(Server.Economy.LevelService)

local function player(gold: number, streakKind: "win" | "loss" | "none", streakLen: number, wonLast: boolean): any
	local s = PlayerState.new(1, "Tester")
	s.gold = gold
	s.streak = { kind = streakKind, length = streakLen }
	s.wonLastPvp = wonLast
	return s
end

return function(t)
	t.test("worked example A: round 8, 37 gold, win streak 3, won last = 10", function()
		t.eq(EconomyService.calcIncome(player(37, "win", 3, true), 8).total, 10)
	end)

	t.test("worked example B: round 12, 62 gold, loss streak 5, lost last = 13", function()
		t.eq(EconomyService.calcIncome(player(62, "loss", 5, false), 12).total, 13)
	end)

	t.test("worked example C: round 3, 9 gold, no streak, last was PvE = 2", function()
		t.eq(EconomyService.calcIncome(player(9, "none", 0, false), 3).total, 2)
	end)

	t.test("worked example D: round 9, 50 gold, win streak 4, won last = 13", function()
		t.eq(EconomyService.calcIncome(player(50, "win", 4, true), 9).total, 13)
	end)

	t.test("base income table: rounds 1 to 6+", function()
		local expected = { 0, 2, 2, 3, 4, 5, 5 }
		for round, base in expected do
			t.eq(EconomyService.calcIncome(player(0, "none", 0, false), round).base, base, "round " .. round)
		end
	end)

	t.test("interest is computed before income is added (ECON-03)", function()
		local s = player(19, "none", 0, false)
		local b = EconomyService.payIncome(s, 6)
		t.eq(b.interest, 1)
		t.eq(s.gold, 19 + 5 + 1)
	end)

	t.test("add/spend: integers only, no negative balance (ECON-01, ECON-05)", function()
		local s = player(5, "none", 0, false)
		t.eq(EconomyService.spend(s, 6, "x").reason, "NotEnoughGold")
		t.eq(s.gold, 5)
		t.eq(EconomyService.add(s, -1, "x").ok, false)
		t.eq(EconomyService.add(s, 1.5, "x").ok, false)
		t.eq(EconomyService.spend(s, 5, "x").ok, true)
		t.eq(s.gold, 0)
	end)

	t.test("streaks count PvP only and draws change nothing (ECON-04)", function()
		local s = player(0, "none", 0, false)
		EconomyService.recordRound(s, "pvp", "win")
		EconomyService.recordRound(s, "pvp", "win")
		t.eq(s.streak.length, 2)
		EconomyService.recordRound(s, "pve", "loss")
		EconomyService.recordRound(s, "carousel", "draw")
		EconomyService.recordRound(s, "pvp", "draw")
		t.eq(s.streak.kind, "win")
		t.eq(s.streak.length, 2)
		t.eq(s.wonLastPvp, false)
		EconomyService.recordRound(s, "pvp", "loss")
		t.eq(s.streak.kind, "loss")
		t.eq(s.streak.length, 1)
	end)

	t.test("per-player overrides change only that player (ECON-06)", function()
		local a, b = player(70, "none", 0, false), player(70, "none", 0, false)
		a.overrides.interestCap = 7
		t.eq(EconomyService.calcIncome(a, 6).interest, 7)
		t.eq(EconomyService.calcIncome(b, 6).interest, 5)
	end)

	t.test("OnIncomeCalc modifiers appear in the breakdown", function()
		local s = player(0, "none", 0, false)
		local b = EconomyService.calcIncome(s, 6, {
			function(bd)
				table.insert(bd.extras, { label = "Tycoon", amount = 2 })
			end,
		})
		t.eq(b.total, 7)
		t.eq(#b.extras, 1)
	end)

	t.test("levels: XP table, carry-over and immediate level-up (LVL-03, LVL-04)", function()
		local s = player(0, "none", 0, false)
		t.eq(LevelService.addXp(s, 5), 2) -- 2 (L1->2) + 2 (L2->3) = 4, 1 carries
		t.eq(s.level, 3)
		t.eq(s.xp, 1)
		t.eq(LevelService.boardCap(s), 3)
	end)

	t.test("passive XP starts at round 2 (LVL-02)", function()
		local s = player(0, "none", 0, false)
		LevelService.grantPassive(s, 1)
		t.eq(s.xp, 0)
		LevelService.grantPassive(s, 2)
		t.eq(s.level, 2)
	end)

	t.test("buy XP costs 4 for 4 XP and is rejected at max level", function()
		local s = player(10, "none", 0, false)
		t.eq(LevelService.buyXp(s).ok, true)
		t.eq(s.gold, 6)
		t.eq(s.level, 3) -- 4 XP: L1->2 (2) and L2->3 (2)
		s.gold = 3
		t.eq(LevelService.buyXp(s).reason, "NotEnoughGold")
		s.level = 10
		s.gold = 100
		t.eq(LevelService.buyXp(s).reason, "MaxLevel")
		t.eq(s.gold, 100)
	end)

	t.test("moveUnit: board cap, swap and bounds (BRD-03, BRD-04)", function()
		local s = player(0, "none", 0, false)
		local a = PlayerState.newUnit(s, "noodle_nugget", 1, 1, nil)
		local b = PlayerState.newUnit(s, "sleepy_sock", 1, 2, nil)
		t.eq(PlayerState.moveUnit(s, a.uid, { kind = "board", cell = { col = 1, row = 1 } }).ok, true)
		t.eq(PlayerState.moveUnit(s, b.uid, { kind = "board", cell = { col = 2, row = 1 } }).reason, "BoardFull")
		t.eq(PlayerState.moveUnit(s, b.uid, { kind = "board", cell = { col = 1, row = 1 } }).ok, true) -- swap
		t.eq(a.bench, 2)
		t.eq(b.board.col, 1)
		t.eq(PlayerState.moveUnit(s, a.uid, { kind = "board", cell = { col = 9, row = 1 } }).reason, "OutOfBounds")
	end)
end
