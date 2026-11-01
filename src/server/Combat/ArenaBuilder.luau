--!strict
-- Builds the physical plot a player owns: a 7 x 8 checkerboard (the home half cool, the away half
-- warm), a bench row of 9 slots behind each side, a low rim, and the scene lighting. Purely visual;
-- positions come from ArenaLayout so they match the fight playback and the client's Prep view
-- (CMB-02: the home team on rows 1 to 4, the away team on rows 5 to 8).

local Lighting = game:GetService("Lighting")
local ArenaLayout = require(game:GetService("ReplicatedStorage").Shared.Util.ArenaLayout)

local CELL_WIDTH, CELL_DEPTH = ArenaLayout.cellWidth, ArenaLayout.cellDepth
local COLUMNS, ROWS = 7, 8

local HOME_COLORS = { Color3.fromRGB(62, 98, 140), Color3.fromRGB(90, 130, 172) }
local AWAY_COLORS = { Color3.fromRGB(140, 72, 90), Color3.fromRGB(170, 96, 114) }
local BENCH_COLOR = Color3.fromRGB(96, 102, 140)
local RIM_COLOR = Color3.fromRGB(26, 28, 40) -- also the base the tiles sit on, so the gaps between squares read as dark lines
local BASE_HEIGHT, BASE_CENTRE_Y = 2.4, -0.8 -- spans y -2.0 to 0.4: its top never matches a baseplate at y = 0
local TILE_GAP = 0.3

local ArenaBuilder = {}

-- A flat anchored block. `clickable` lets the client raycast onto it (tiles and bench slots).
local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, clickable: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = clickable == true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Fills `folder` with the plot centred on `origin` (the floor top is y = 0).
function ArenaBuilder.build(folder: Folder, origin: Vector3)
	local width, depth = COLUMNS * CELL_WIDTH, ROWS * CELL_DEPTH
	part(folder, "Floor", Vector3.new(width + 6, BASE_HEIGHT, depth + 6), origin + Vector3.new(0, BASE_CENTRE_Y, 0), RIM_COLOR)

	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = folder
	for col = 1, COLUMNS do
		for row = 1, ROWS do
			local palette = if row <= ROWS / 2 then HOME_COLORS else AWAY_COLORS
			local at = ArenaLayout.cellPosition(origin, col, row)
			part(tiles, ("Tile_%d_%d"):format(col, row), Vector3.new(CELL_WIDTH - TILE_GAP, 1, CELL_DEPTH - TILE_GAP),
				at + Vector3.new(0, -0.5, 0), palette[(col + row) % 2 + 1], true)
		end
	end

	-- A bench row behind each side's back line: Bench_Home_1..9 and Bench_Away_1..9.
	local bench = Instance.new("Folder")
	bench.Name = "Bench"
	bench.Parent = folder
	for _, side in { { "Home", true }, { "Away", false } } do
		local middle = ArenaLayout.benchPosition(origin, 5, side[2] :: boolean)
		part(folder, "BenchPlatform" .. side[1], Vector3.new(width + 6, BASE_HEIGHT, 6), Vector3.new(middle.X, BASE_CENTRE_Y, middle.Z), RIM_COLOR)
		for index = 1, ArenaLayout.benchSlots do
			part(bench, ("Bench_%s_%d"):format(side[1], index), Vector3.new(4.2, 1, 2.9),
				ArenaLayout.benchPosition(origin, index, side[2] :: boolean) + Vector3.new(0, -0.5, 0), BENCH_COLOR, true)
		end
	end

	-- A low rim along the sides so the arena reads as a place.
	part(folder, "RimLeft", Vector3.new(1.5, 1.8, depth + 3), origin + Vector3.new(-width / 2 - 1.5, 1, 0), RIM_COLOR)
	part(folder, "RimRight", Vector3.new(1.5, 1.8, depth + 3), origin + Vector3.new(width / 2 + 1.5, 1, 0), RIM_COLOR)
end

-- Soft daylight so models and animations read clearly from the angled camera.
function ArenaBuilder.setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 124, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 134, 160)
	Lighting.GlobalShadows = true
end

return ArenaBuilder
