--!strict
-- Tests for Grid and Rng (GDD CMB-01, CMB-02, CMB-03, CMB-04, CMB-09).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Grid = require(Shared.Util.Grid)
local Rng = require(Shared.Util.Rng)

return function(t)
	t.test("Grid: Chebyshev distance includes diagonals", function()
		t.eq(Grid.distance({ col = 1, row = 1 }, { col = 2, row = 2 }), 1)
		t.eq(Grid.distance({ col = 1, row = 1 }, { col = 5, row = 3 }), 4)
	end)

	t.test("Grid: mirror maps (c, r) to (8 - c, 9 - r) on a 7x8 arena", function()
		local m = Grid.mirror({ col = 2, row = 3 }, 7, 8)
		t.eq(m.col, 6)
		t.eq(m.row, 6)
	end)

	t.test("Grid: neighbors respect bounds", function()
		t.eq(#Grid.neighbors({ col = 1, row = 1 }, 7, 8), 3)
		t.eq(#Grid.neighbors({ col = 4, row = 4 }, 7, 8), 8)
	end)

	t.test("Grid: nearestEmpty breaks ties by lowest column then row (CMB-04)", function()
		local occupied = { [Grid.key({ col = 3, row = 3 })] = true }
		local cell = Grid.nearestEmpty({ col = 3, row = 3 }, 7, 8, occupied) :: any
		t.eq(cell.col, 2)
		t.eq(cell.row, 2)
	end)

	t.test("Grid: BFS steps toward target and routes around blockers", function()
		local from = { col = 1, row = 1 }
		local target = { col = 4, row = 1 }
		local step = Grid.nextStep(from, target, 1, 7, 8, {}) :: any
		t.eq(step.col, 2)
		local blocked = { [Grid.key({ col = 2, row = 1 })] = true, [Grid.key({ col = 2, row = 2 })] = true }
		local detour = Grid.nextStep(from, target, 1, 7, 8, blocked)
		t.truthy(detour == nil or detour.col ~= 2 or detour.row ~= 1)
	end)

	t.test("Grid: nextStep returns current cell when already in range", function()
		local step = Grid.nextStep({ col = 1, row = 1 }, { col = 2, row = 2 }, 1, 7, 8, {}) :: any
		t.eq(step.col, 1)
		t.eq(step.row, 1)
	end)

	t.test("Grid: greedyStep waits when nothing improves", function()
		local occupied = {}
		for _, n in Grid.neighbors({ col = 1, row = 1 }, 7, 8) do
			occupied[Grid.key(n)] = true
		end
		t.eq(Grid.greedyStep({ col = 1, row = 1 }, { col = 5, row = 5 }, 7, 8, occupied), nil)
	end)

	t.test("Rng: same seed gives the same stream (CMB-01)", function()
		local a, b = Rng.new(Rng.hash(1, 2, 3)), Rng.new(Rng.hash(1, 2, 3))
		for _ = 1, 20 do
			t.eq(a:next(), b:next())
		end
		t.truthy(Rng.hash(1, 2, 3) ~= Rng.hash(3, 2, 1), "hash should be order sensitive")
	end)

	t.test("Rng: shuffle is deterministic and does not mutate the input", function()
		local list = { 1, 2, 3, 4, 5, 6 }
		local s1 = Rng.new(7):shuffle(list)
		local s2 = Rng.new(7):shuffle(list)
		t.eq(table.concat(s1, ","), table.concat(s2, ","))
		t.eq(table.concat(list, ","), "1,2,3,4,5,6")
	end)
end
