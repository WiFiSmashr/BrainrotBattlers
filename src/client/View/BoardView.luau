--!strict
-- The 7x4 board, the 9-slot bench, the sell zone and the "units x / y" counter (GDD 12.2, 12.3).
-- Every move works by tap (select a unit, tap a destination) and by drag (UI-04). The front row is
-- shown at the top, nearest the enemy.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Index = require(Shared.Util.Index)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local Actions = require(script.Parent.Parent.UI.Actions)
local Selection = require(script.Parent.Parent.UI.Selection)
local DragController = require(script.Parent.Parent.UI.DragController)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local UnitPortrait = require(script.Parent.Parent.UI.UnitPortrait)

local CELL, GAP = Theme.cell, 4
local BENCH_DROP = 74 -- extra gap under the board, so the combat arena fits above the bench
local COLUMNS, ROWS, BENCH = GameConfig.boardColumns, GameConfig.boardRows, GameConfig.benchSlots

local BoardView = {}

type Dest = { kind: "bench", index: number } | { kind: "board", col: number, row: number }

-- Sends a move for the selected unit to `dest` and clears the selection.
local function moveSelectedTo(dest: Dest)
	local uid = Selection.unit
	if not uid then
		return
	end
	if dest.kind == "bench" then
		Actions.moveToBench(uid, dest.index)
	else
		Actions.moveToBoard(uid, dest.col, dest.row)
	end
	Selection.selectUnit(nil)
end

-- Builds a unit tile: tint, short name, stars, rarity border and item icons.
local function makeTile(parent: Instance, unit: { [string]: any }, items: { { [string]: any } }): TextButton
	local def = Index.unit(unit.d)
	local selected = Selection.unit == unit.u
	local tile = Components.button({
		Name = "Tile", Size = UDim2.fromScale(1, 1), AutoButtonColor = false, Text = "", Parent = parent,
		BackgroundColor3 = if def and def.tint then def.tint else Theme.colors.panelLight, ZIndex = 5, radius = 8,
	})
	if def then
		UnitPortrait.attach(tile, def, 5) -- shows the 3D model when the unit has one
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = if selected then Color3.new(1, 1, 1) else (if def then Theme.costColor(def.cost) else Theme.colors.textDim)
	stroke.Thickness = if selected then 6 else 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile
	Components.label({
		Size = UDim2.new(1, -6, 0, 40), Position = UDim2.fromOffset(3, 22), Text = if def then def.name else unit.d,
		TextSize = 17, TextWrapped = true, TextColor3 = Color3.new(0, 0, 0), Parent = tile, ZIndex = 6,
	})
	Components.label({
		Size = UDim2.new(1, 0, 0, 22), Text = string.rep("★", unit.s), TextSize = 20, TextColor3 = Theme.colors.accent,
		TextStrokeTransparency = 0.4, Parent = tile, ZIndex = 6,
	})
	local row = Components.create("Frame", {
		Size = UDim2.new(1, -4, 0, 24), Position = UDim2.new(0, 2, 1, -26), BackgroundTransparency = 1, Parent = tile, ZIndex = 6,
	})
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), Parent = row })
	for _, item in items do
		if item.e == unit.u then
			ItemIcon.mini(row, item.i)
		end
	end
	return tile
end

-- Makes a board cell or bench slot. The container is a drop target for units and a tap target.
local function makeSlot(parent: Instance, position: UDim2, dest: Dest, color: Color3): Frame
	local slot = Components.create("TextButton", {
		Size = UDim2.fromOffset(CELL, CELL), Position = position, BackgroundColor3 = color, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, Parent = parent, ZIndex = 2,
	})
	Components.style(slot, 8)
	DragController.registerTarget(slot, {
		accepts = function(payload)
			return payload.kind == "unit"
		end,
		onDrop = function(payload)
			Selection.selectUnit(nil)
			if dest.kind == "bench" then
				Actions.moveToBench(payload.uid, dest.index)
			else
				Actions.moveToBoard(payload.uid, dest.col, dest.row)
			end
		end,
	})
	DragController.attach(slot, nil, function()
		moveSelectedTo(dest)
	end)
	return slot
end

export type View = {
	frame: Frame,
	render: (snapshot: { [string]: any }) -> (),
	setCombat: (inCombat: boolean) -> (), -- during combat only the bench stays visible
}

-- Builds the board area into `parent`.
function BoardView.build(parent: Instance): View
	local boardWidth = COLUMNS * CELL + (COLUMNS - 1) * GAP
	local boardHeight = ROWS * CELL + (ROWS - 1) * GAP
	local benchWidth = BENCH * CELL + (BENCH - 1) * GAP
	local sellWidth = 150

	local frame = Components.create("Frame", {
		Name = "BoardView", Size = UDim2.fromOffset(benchWidth + 16 + sellWidth, 34 + boardHeight + 14 + BENCH_DROP + CELL + 4),
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), BackgroundTransparency = 1, Parent = parent,
	})

	local counter = Components.label({
		Size = UDim2.fromOffset(boardWidth, 30),
		Text = "", TextSize = 24, Parent = frame,
	})
	counter.Position = UDim2.new(0, (benchWidth + 16 + sellWidth - boardWidth) / 2, 0, 0)

	local board = Components.create("Frame", {
		Size = UDim2.fromOffset(boardWidth, boardHeight), Position = UDim2.new(0, (benchWidth + 16 + sellWidth - boardWidth) / 2, 0, 34),
		BackgroundTransparency = 1, Parent = frame,
	})
	local cells: { [string]: Frame } = {}
	for row = 1, ROWS do
		for col = 1, COLUMNS do
			local x, y = (col - 1) * (CELL + GAP), (ROWS - row) * (CELL + GAP) -- row 4 (front) is at the top
			local color = if (col + row) % 2 == 0 then Theme.colors.cellHome else Theme.colors.cellAlt
			cells[col .. "," .. row] = makeSlot(board, UDim2.fromOffset(x, y), { kind = "board", col = col, row = row }, color)
		end
	end

	local benchY = 34 + boardHeight + 14 + BENCH_DROP
	local benchLabel = Components.label({
		Size = UDim2.fromOffset(benchWidth, 24), Position = UDim2.fromOffset(0, benchY - 22), Text = "Bench", TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.colors.textDim, Parent = frame,
	})
	local slots: { Frame } = {}
	for i = 1, BENCH do
		slots[i] = makeSlot(frame, UDim2.fromOffset((i - 1) * (CELL + GAP), benchY), { kind = "bench", index = i }, Theme.colors.panelLight)
	end

	-- Sell zone: drag a unit here, or open its info card and tap Sell (12.3).
	local sell = Components.panel({
		Size = UDim2.fromOffset(sellWidth, CELL), Position = UDim2.fromOffset(benchWidth + 16, benchY),
		BackgroundColor3 = Color3.fromRGB(95, 40, 48), radius = 8, stroke = Theme.colors.bad, Parent = frame,
	})
	Components.label({ Size = UDim2.fromScale(1, 1), Text = "SELL\n(drag here)", TextSize = 22, Parent = sell })
	DragController.registerTarget(sell, {
		accepts = function(payload)
			return payload.kind == "unit"
		end,
		onDrop = function(payload)
			Selection.selectUnit(nil)
			Actions.sellUnit(payload.uid)
		end,
	})

	local function render(snapshot: { [string]: any })
		for _, container in cells do
			Components.clear(container, { UICorner = true })
		end
		for _, container in slots do
			Components.clear(container, { UICorner = true })
		end

		local boardCount, benchCount = 0, 0
		for _, unit in snapshot.units do
			local container: Frame?
			local location: Dest
			if unit.b then
				container, location = slots[unit.b], { kind = "bench", index = unit.b }
				benchCount += 1
			else
				container, location = cells[unit.c .. "," .. unit.r], { kind = "board", col = unit.c, row = unit.r }
				boardCount += 1
			end
			if container then
				local tile = makeTile(container, unit, snapshot.items)
				-- A tile accepts items dropped on it; units dropped on it fall through to the slot (swap).
				DragController.registerTarget(tile, {
					accepts = function(payload)
						return payload.kind == "item"
					end,
					onDrop = function(payload)
						Actions.equipItem(payload.uid, unit.u)
						Selection.clearItems()
					end,
				})
				DragController.attach(tile, { kind = "unit", uid = unit.u }, function()
					local items = Selection.items
					if #items > 0 then
						Actions.equipItem(items[1], unit.u) -- tap an item, then tap the unit
						Selection.clearItems()
					elseif Selection.unit and Selection.unit ~= unit.u then
						moveSelectedTo(location) -- tap a unit, then tap an occupied cell: swap
					elseif Selection.unit == unit.u then
						Selection.selectUnit(nil)
					else
						Selection.selectUnit(unit.u) -- also opens the info card
					end
				end)
			end
		end

		local full = boardCount >= snapshot.level
		counter.Text = ("Units %d / %d%s"):format(boardCount, snapshot.level, if full then "  (board full)" else "")
		counter.TextColor3 = if full then Theme.colors.accent else Theme.colors.text
		benchLabel.Text = ("Bench %d / %d%s"):format(benchCount, BENCH, if benchCount >= BENCH then "  (bench full)" else "")
		benchLabel.TextColor3 = if benchCount >= BENCH then Theme.colors.bad else Theme.colors.textDim
	end

	-- The bench (and the units on it) stays on screen during combat so purchases are visible; the board,
	-- counter and sell zone are only shown while you can use them.
	local function setCombat(inCombat: boolean)
		board.Visible = not inCombat
		counter.Visible = not inCombat
		sell.Visible = not inCombat
	end

	return { frame = frame, render = render, setCombat = setCombat }
end

return BoardView
