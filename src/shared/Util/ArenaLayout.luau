--!strict
-- Where things stand in the 3D world, shared by the server (floor, fight playback) and the client
-- (Prep board, bench, camera). Pure maths, no Instances.
--
-- Each seated player owns one plot: a 7 x 8 arena. The home team uses arena rows 1 to 4 (at -Z of the
-- centre), the away team rows 5 to 8 (+Z), and the away team is mirrored 180 degrees (CMB-02). The
-- viewer's camera sits behind their own side, so world X is flipped (col 1 is at +X for the home
-- viewer) to put column 1 on the viewer's left. Each side also has a bench row of 9 slots behind its
-- back line.

local Grid = require(script.Parent.Grid)

local CELL_STUDS = 4
local ARENA_SPACING = 500 -- distance between plot centres along X: far enough that no plot is ever in view of another
local COLUMNS, ROWS = 7, 8
local BENCH_SLOTS = 9
local BENCH_SPACING = 3.1 -- 9 slots fit inside the 28-stud arena width
local BENCH_OFFSET = 22 -- studs from the arena centre to the bench row (the arena edge is at 16)
-- The tile tops are one stud above y = 0, so the board never sits level with a baseplate or other floor
-- the place might contain (which hides the squares and makes them flicker).
local GROUND_Y = 1

-- Columns monsters fill from the middle outwards, front row first (own-board coordinates, row 4 = front).
local MONSTER_COLUMNS = { 4, 3, 5, 2, 6, 1, 7 }

local ArenaLayout = {}

ArenaLayout.cellStuds = CELL_STUDS
ArenaLayout.benchSlots = BENCH_SLOTS
ArenaLayout.benchOffset = BENCH_OFFSET
ArenaLayout.groundY = GROUND_Y -- height of the tile tops, where units stand

-- Centre of the plot for the nth seated player (1-indexed).
function ArenaLayout.plotOrigin(seat: number): Vector3
	return Vector3.new((seat - 1) * ARENA_SPACING, 0, 0)
end

-- The seat (1-indexed) whose plot is centred at `origin`.
function ArenaLayout.seatAt(origin: Vector3): number
	return math.floor(origin.X / ARENA_SPACING + 0.5) + 1
end

-- Ground position of an arena cell (col 1 to 7, row 1 to 8) on a plot.
function ArenaLayout.cellPosition(origin: Vector3, col: number, row: number): Vector3
	return origin + Vector3.new((4 - col) * CELL_STUDS, GROUND_Y, (row - 4.5) * CELL_STUDS)
end

-- Ground position of a bench slot on the home side (rows 1 to 4, z < 0) or the away side (z > 0).
function ArenaLayout.benchPosition(origin: Vector3, index: number, homeSide: boolean): Vector3
	if homeSide then
		return origin + Vector3.new((5 - index) * BENCH_SPACING, GROUND_Y, -BENCH_OFFSET)
	end
	return origin + Vector3.new((index - 5) * BENCH_SPACING, GROUND_Y, BENCH_OFFSET)
end

-- The own-board cell (col 1 to 7, row 1 to 4) of the nth PvE monster; row 4 is the front.
function ArenaLayout.monsterCell(index: number): Grid.Cell
	local perRow = #MONSTER_COLUMNS
	return { col = MONSTER_COLUMNS[(index - 1) % perRow + 1], row = 4 - math.floor((index - 1) / perRow) }
end

-- The arena cell a monster stands on: the away team, so its own-board cell is mirrored (CMB-02).
function ArenaLayout.monsterArenaCell(index: number): Grid.Cell
	return Grid.mirror(ArenaLayout.monsterCell(index), COLUMNS, ROWS)
end

return ArenaLayout
