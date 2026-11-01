--!strict
-- Tests for the 3D combat presentation: the camera pose keeps the whole arena inside the free area of
-- the screen, the arena floor lines up with the grid the playback uses, and the HUD roster carries the
-- arena position.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)
local CombatCamera = require(game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client"):WaitForChild("View"):WaitForChild("CombatCamera"))
local ArenaBuilder = require(Server.Combat.ArenaBuilder)
local ArenaLayout = require(Shared.Util.ArenaLayout)
local CombatRunner = require(Server.Combat.CombatRunner)
local CombatPlayback = require(Server.Combat.CombatPlayback)
local MatchService = require(Server.Match.MatchService)
local PveBoards = require(Server.Match.PveBoards)
local Snapshot = require(Server.Player.Snapshot)

-- Where a world point lands on screen as a fraction of the screen height from the top (0 = top).
local function screenY(camera: CFrame, point: Vector3): number
	local local_ = camera:PointToObjectSpace(point)
	local tanHalf = math.tan(math.rad(CameraConfig.fieldOfView / 2))
	return 0.5 - (local_.Y / -local_.Z) / tanHalf / 2
end

return function(t)
	t.test("the home viewer sits behind the home side, the away viewer behind the away side (PAIR-03)", function()
		local origin = Vector3.new(140, 0, 0)
		local home = CombatCamera.pose(origin, true)
		local away = CombatCamera.pose(origin, false)
		t.truthy(home.Position.Z < origin.Z and away.Position.Z > origin.Z)
		t.near(home.Position.X, origin.X, 1e-6)
		t.truthy(home.Position.Y > 20 and away.Position.Y > 20)
		t.truthy(home.LookVector.Y < -0.5, "looking down at the arena")
		t.truthy(home.LookVector.Z > 0 and away.LookVector.Z < 0, "each looks across the arena")
		t.near(home.Position.Y, away.Position.Y, 1e-6)
	end)

	local G = ArenaLayout.groundY
	t.test("the arena and your bench fit between the top bar and the shop for both viewers", function()
		local topBar = 96 / 1080
		local shopTop = 722 / 1080
		for _, viewerIsHome in { true, false } do
			local camera = CombatCamera.pose(Vector3.new(0, 0, 0), viewerIsHome)
			local near = if viewerIsHome then -1 else 1 -- the sign of z on the viewer's own side
			for _, point in {
				Vector3.new(-21, G, -16), Vector3.new(21, G, -16), Vector3.new(-21, G, 16), Vector3.new(21, G, 16),
				Vector3.new(0, G, -16), Vector3.new(0, G, 16), Vector3.new(0, G, 0),
				-- The bench row behind the viewer's back line, and the edge of its platform.
				Vector3.new(-21, G, near * 22), Vector3.new(21, G, near * 22), Vector3.new(0, G, near * 25),
			} do
				local y = screenY(camera, point)
				t.truthy(y > topBar, ("a point is under the top bar: %.3f"):format(y))
				t.truthy(y < shopTop, ("a point is behind the shop: %.3f"):format(y))
			end
			-- Unit heads (about 4 studs up) at the far edge, and units standing on the bench, must be visible.
			local far = screenY(camera, if viewerIsHome then Vector3.new(0, G + 4, 16) else Vector3.new(0, G + 4, -16))
			t.truthy(far > topBar, "far-edge units are visible")
			t.truthy(screenY(camera, Vector3.new(0, G, near * 22)) < shopTop - 0.02, "the bench is clear of the shop")
		end
	end)

	t.test("the arena floor is a 7 x 8 checkerboard aligned with the playback grid", function()
		local folder = Instance.new("Folder")
		local origin = Vector3.new(70, 0, 0)
		ArenaBuilder.build(folder, origin)
		local tiles = folder:FindFirstChild("Tiles") :: Folder
		t.eq(#tiles:GetChildren(), 56)
		local base = folder:FindFirstChild("Floor") :: Part
		t.truthy(base ~= nil)
		t.truthy(base.Position.Y + base.Size.Y / 2 > 0.1 and base.Position.Y + base.Size.Y / 2 < ArenaLayout.groundY, "the base top is clear of y = 0 and below the tiles")
		for col = 1, 7 do
			for row = 1, 8 do
				local tile = tiles:FindFirstChild(("Tile_%d_%d"):format(col, row)) :: Part
				t.truthy(tile ~= nil, ("missing tile %d,%d"):format(col, row))
				-- Same cell centre as ArenaLayout.cellPosition: x = (4 - col) * 6, z = (row - 4.5) * 4.
				t.near(tile.Position.X, origin.X + (4 - col) * 6, 1e-6)
				t.near(tile.Position.Z, origin.Z + (row - 4.5) * 4, 1e-6)
				t.near(tile.Position.Y + tile.Size.Y / 2, ArenaLayout.groundY, 1e-6, "the tile top is at the ground height")
				t.truthy(tile.Size.X < 6, "a gap shows between squares")
			end
		end
		local a = (tiles:FindFirstChild("Tile_1_1") :: Part).Color
		local b = (tiles:FindFirstChild("Tile_2_1") :: Part).Color
		local away = (tiles:FindFirstChild("Tile_1_5") :: Part).Color
		t.truthy(a ~= b, "alternating shades")
		t.truthy(a ~= away, "the two halves differ in colour")
		folder:Destroy()
	end)

	t.test("the bench is a row of 9 slots behind each side, inside the arena width, with slot 1 on the viewer's left", function()
		local origin = Vector3.new(70, 0, 0)
		local homeSlots, awaySlots = {}, {}
		for i = 1, 9 do
			homeSlots[i] = ArenaLayout.benchPosition(origin, i, true)
			awaySlots[i] = ArenaLayout.benchPosition(origin, i, false)
			t.near(homeSlots[i].Z - origin.Z, -22, 1e-6)
			t.near(awaySlots[i].Z - origin.Z, 22, 1e-6)
			t.truthy(math.abs(homeSlots[i].X - origin.X) <= 21, "inside the arena width")
		end
		-- Home viewer looks toward +Z, so their left is +X; the away viewer looks toward -Z, so their left is -X.
		t.truthy(homeSlots[1].X > homeSlots[9].X)
		t.truthy(awaySlots[1].X < awaySlots[9].X)
		-- Board column 1 is on the left too (+X for the home viewer).
		t.truthy(ArenaLayout.cellPosition(origin, 1, 1).X > ArenaLayout.cellPosition(origin, 7, 1).X)
	end)

	t.test("plots are laid out by seat and the seat can be recovered from a position", function()
		for seat = 1, 8 do
			t.eq(ArenaLayout.seatAt(ArenaLayout.plotOrigin(seat)), seat)
		end
		-- Plots form a square grid inside the 2048-stud baseplate, never closer than 600 studs.
		for a = 1, GameConfig.lobbySize do
			local pa = ArenaLayout.plotOrigin(a)
			t.truthy(math.abs(pa.X) <= 900 and math.abs(pa.Z) <= 900, "inside the baseplate")
			for b = a + 1, GameConfig.lobbySize do
				t.truthy((pa - ArenaLayout.plotOrigin(b)).Magnitude >= 600, "plots are far apart")
			end
		end
	end)

	t.test("PvE monsters stand on the same cells in the Prep preview and in the fight (D-68)", function()
		for count = 1, 8 do
			local team = CombatRunner.monsterTeam(count * 2) -- global round g -> min(1 + g/2, 8) monsters
			t.eq(#team, PveBoards.count(count * 2))
			for i, spec in team do
				local cell = ArenaLayout.monsterCell(i)
				t.eq(spec.cell.col, cell.col)
				t.eq(spec.cell.row, cell.row)
				local arena = ArenaLayout.monsterArenaCell(i)
				t.eq(arena.col, 8 - cell.col)
				t.eq(arena.row, 9 - cell.row)
				t.truthy(arena.row >= 5 and arena.row <= 8, "monsters are on the away half")
			end
		end
		local seen: { [string]: boolean } = {}
		for i = 1, 8 do
			local cell = ArenaLayout.monsterCell(i)
			t.truthy(not seen[cell.col .. "," .. cell.row], "two monsters share a cell")
			seen[cell.col .. "," .. cell.row] = true
		end
	end)

	t.test("seats are assigned at match start; snapshots carry the seat and the PvE monster count", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 3, seed = 3, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		for id = 1, 3 do
			match:addPlayer(id * 10, "P" .. id)
		end
		match:start()
		for seat, id in { 10, 20, 30 } do
			t.eq(match:getPlayer(id).seat, seat)
			t.eq(Snapshot.build(match, id).seat, seat)
		end
		clock.t = 3
		match:update() -- 1-1 Prep: a PvE round with one monster
		t.eq(Snapshot.build(match, 10).monsters, 1)
		clock.t = 190 -- into 2-1: a PvP round
		match:update()
		t.eq(match.info.type, "pvp")
		t.eq(Snapshot.build(match, 10).monsters, nil)
	end)

	t.test("every plot is built up front with its tiles and both bench rows", function()
		local clock = { t = 0 }
		local match = MatchService.new({
			lobbySize = 2, seed = 4, now = function() return clock.t end,
			combat = function(): any
				return { winner = "draw", survivors = 0, seconds = 5 }
			end,
		})
		match:addPlayer(901, "A")
		match:addPlayer(902, "B")
		match:start()
		CombatPlayback.preparePlots(match)
		local arenas = workspace:FindFirstChild("Arenas") :: Folder
		for seat, id in { 901, 902 } do
			local arena = arenas:FindFirstChild("Arena_" .. id) :: Folder
			t.truthy(arena ~= nil, "no plot for " .. id)
			t.eq(#(arena:FindFirstChild("Tiles") :: Folder):GetChildren(), 56)
			t.eq(#(arena:FindFirstChild("Bench") :: Folder):GetChildren(), 18)
			local slot = (arena.Bench :: any)["Bench_Home_1"]
			local expected = ArenaLayout.benchPosition(ArenaLayout.plotOrigin(seat), 1, true)
			t.near(slot.Position.X, expected.X, 1e-6)
			t.near(slot.Position.Z, expected.Z, 1e-6)
			t.truthy(slot.CanQuery, "bench slots can be raycast")
			t.truthy((arena.Tiles :: any)["Tile_1_1"].CanQuery, "tiles can be raycast")
			arena:Destroy()
		end
	end)
end
