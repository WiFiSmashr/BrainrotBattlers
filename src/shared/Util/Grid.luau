--!strict
-- The only module that knows the grid shape (CMB-03). Square grid, Chebyshev distance.

export type Cell = { col: number, row: number }

local Grid = {}

local NEIGHBORS = {
	{ -1, -1 }, { 0, -1 }, { 1, -1 },
	{ -1, 0 }, { 1, 0 },
	{ -1, 1 }, { 0, 1 }, { 1, 1 },
}

-- Chebyshev distance between two cells (CMB-03).
function Grid.distance(a: Cell, b: Cell): number
	return math.max(math.abs(a.col - b.col), math.abs(a.row - b.row))
end

-- True if the cell lies inside a columns x rows grid (1-indexed).
function Grid.inBounds(cell: Cell, columns: number, rows: number): boolean
	return cell.col >= 1 and cell.col <= columns and cell.row >= 1 and cell.row <= rows
end

-- Key string for using a cell as a table key.
function Grid.key(cell: Cell): string
	return cell.col .. "," .. cell.row
end

-- Mirrors a cell by 180 degrees onto the away side: (c, r) -> (columns+1-c, rows+1-r) (CMB-02).
function Grid.mirror(cell: Cell, columns: number, rows: number): Cell
	return { col = columns + 1 - cell.col, row = rows + 1 - cell.row }
end

-- In-bounds 8-neighbors of a cell, in a fixed order.
function Grid.neighbors(cell: Cell, columns: number, rows: number): { Cell }
	local out = {}
	for _, d in NEIGHBORS do
		local n = { col = cell.col + d[1], row = cell.row + d[2] }
		if Grid.inBounds(n, columns, rows) then
			table.insert(out, n)
		end
	end
	return out
end

-- Nearest empty cell to `origin`; ties go to lowest column, then lowest row (CMB-04).
-- `occupied` is a set keyed by Grid.key. Returns nil if the grid is full.
function Grid.nearestEmpty(origin: Cell, columns: number, rows: number, occupied: { [string]: boolean }): Cell?
	local best: Cell? = nil
	local bestDist = math.huge
	for col = 1, columns do
		for row = 1, rows do
			local cell = { col = col, row = row }
			if not occupied[Grid.key(cell)] then
				local d = Grid.distance(origin, cell)
				-- Scan order is column-major ascending, so a strict `<` keeps the lowest col/row on ties.
				if d < bestDist then
					best, bestDist = cell, d
				end
			end
		end
	end
	return best
end

-- BFS (CMB-09): returns the first step of a shortest 8-neighbor path from `from` to any cell
-- within `range` of `target`, or nil when unreachable. Occupied cells block; `target` cell itself
-- is never entered. Returns `from` when already within range.
function Grid.nextStep(
	from: Cell,
	target: Cell,
	range: number,
	columns: number,
	rows: number,
	occupied: { [string]: boolean }
): Cell?
	if Grid.distance(from, target) <= range then
		return from
	end
	local startKey = Grid.key(from)
	local firstStep: { [string]: Cell } = {}
	local visited: { [string]: boolean } = { [startKey] = true }
	local queue: { Cell } = { from }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, n in Grid.neighbors(current, columns, rows) do
			local k = Grid.key(n)
			if not visited[k] and not occupied[k] then
				visited[k] = true
				firstStep[k] = if current.col == from.col and current.row == from.row then n else firstStep[Grid.key(current)]
				if Grid.distance(n, target) <= range then
					return firstStep[k]
				end
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- Fallback when no path exists (CMB-09): the free adjacent cell that most reduces distance to
-- `target`, or nil to wait.
function Grid.greedyStep(from: Cell, target: Cell, columns: number, rows: number, occupied: { [string]: boolean }): Cell?
	local best: Cell? = nil
	local bestDist = Grid.distance(from, target)
	for _, n in Grid.neighbors(from, columns, rows) do
		if not occupied[Grid.key(n)] then
			local d = Grid.distance(n, target)
			if d < bestDist then
				best, bestDist = n, d
			end
		end
	end
	return best
end

return Grid
