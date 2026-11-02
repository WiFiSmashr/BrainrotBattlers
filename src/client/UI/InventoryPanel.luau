--!strict
-- Item inventory: components and combined items that are not on a unit (GDD 12.2, 12.3).
-- Tap an item to select it; tap a unit to equip it. Tap two components and press Combine, or drag
-- one onto the other. Drag an item off a unit and drop it here to unequip it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemData = require(Shared.Data.Items)
local Index = require(Shared.Util.Index)
local ItemText = require(Shared.Util.ItemText)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local Selection = require(script.Parent.Selection)
local StateStore = require(script.Parent.Parent.StateStore)
local DragController = require(script.Parent.DragController)
local ItemIcon = require(script.Parent.ItemIcon)

local TILE = 88

-- Recipe lookup by the two component ids, in either order.
local recipes: { [string]: string } = {}
for _, def in ItemData do
	if def.recipe then
		local a, b = def.recipe[1], def.recipe[2]
		recipes[if a < b then a .. "+" .. b else b .. "+" .. a] = def.id
	end
end

local InventoryPanel = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Builds the panel into `parent`.
function InventoryPanel.build(parent: Instance): View
	local frame = Components.panel({
		Name = "InventoryPanel", Size = UDim2.fromOffset(300, 740), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 108),
		Parent = parent,
	})
	local title = Components.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Items", TextSize = 30, Parent = frame })
	local grid = Components.scroll({ Size = UDim2.new(1, -12, 0, 288), Position = UDim2.fromOffset(6, 44), Parent = frame })
	Components.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(TILE, TILE), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
	})
	-- Details of the item last tapped (loose or on a unit): stats, recipe and what it does.
	local detail = Components.panel({
		Size = UDim2.new(1, -12, 0, 258), Position = UDim2.fromOffset(6, 338), BackgroundColor3 = Color3.fromRGB(46, 48, 72), radius = 8, Parent = frame,
	})
	local detailName = Components.label({
		Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(8, 4), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.colors.accent, Parent = detail,
	})
	-- The text shrinks to fit this box (never below 11 points) instead of being cut off or needing a scroll (D-85).
	local detailText = Components.fitText(Components.label({
		Size = UDim2.new(1, -16, 1, -94), Position = UDim2.fromOffset(8, 38), TextSize = 18, Font = Theme.fontBody,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail,
	}), 18, 11)
	local takeOff = Components.button({
		Size = UDim2.new(1, -12, 0, 48), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6), Text = "Take off", TextSize = 22,
		Visible = false, Parent = detail,
		onTap = function()
			if Selection.inspected then
				Actions.unequipItem(Selection.inspected) -- the tap route for 12.3 "unequip"
			end
		end,
	})
	local hint = Components.label({
		Size = UDim2.new(1, -16, 0, 50), Position = UDim2.new(0, 8, 1, -120), TextSize = 16, TextWrapped = true, Font = Theme.fontBody,
		TextColor3 = Theme.colors.textDim, Text = "Tap an item, then a unit to equip. Tap two components, then Combine.", Parent = frame,
	})
	local combine = Components.button({
		Size = UDim2.new(1, -16, 0, 56), Position = UDim2.new(0, 8, 1, -64), Text = "Combine", TextSize = 24,
		BackgroundColor3 = Color3.fromRGB(60, 60, 78), Parent = frame,
		onTap = function()
			local items = Selection.items
			if #items == 2 then
				Actions.combineItems(items[1], items[2])
				Selection.clearItems()
			end
		end,
	})

	-- Dropping an equipped item here takes it off its unit (the tap route is "Take off" in the details box).
	DragController.registerTarget(frame, {
		accepts = function(payload)
			return payload.kind == "equipped"
		end,
		onDrop = function(payload)
			Actions.unequipItem(payload.uid)
		end,
	})

	local scoutShown: string? = nil -- the item whose details show while scouting (UI-local)

	-- Scouting (D-83): shows the other player's loose items, read-only. Returns true if it drew them.
	local function renderScouted(snapshot: { [string]: any }): boolean
		local who = nil
		for _, p in snapshot.players do
			if p.id == StateStore.scouting then
				who = p
			end
		end
		combine.Visible = who == nil
		if not who then
			title.Text = "Items"
			return false
		end
		title.Text = who.n .. "'s items"
		hint.Text = if #who.inv == 0 then "No loose items." else "Items on their units show over the units."
		takeOff.Visible = false
		local def = if scoutShown then Index.item(scoutShown) else nil
		detailName.Text = if def then def.name else "Item details"
		detailText.Text = if def then ItemText.describe(def) else "Tap an item to see what it does."
		Components.clear(grid, { UIGridLayout = true })
		for order, itemId in who.inv do
			local tile = ItemIcon.tile(grid, itemId, TILE)
			tile.LayoutOrder = order
			tile.Activated:Connect(function()
				scoutShown = itemId
				detailName.Text = ItemIcon.name(itemId)
				local shown = Index.item(itemId)
				detailText.Text = if shown then ItemText.describe(shown) else ""
			end)
		end
		return true
	end

	local function render(snapshot: { [string]: any })
		if renderScouted(snapshot) then
			return
		end
		local loose = {}
		local ids: { [number]: string } = {}
		for _, item in snapshot.items do
			if not item.e then
				table.insert(loose, item)
				ids[item.u] = item.i
			end
		end
		-- Item details: the last tapped item, whether it is loose or on a unit.
		local inspected = nil
		for _, item in snapshot.items do
			if item.u == Selection.inspected then
				inspected = item
			end
		end
		local inspectedDef = if inspected then Index.item(inspected.i) else nil
		-- Two components selected: show what the fused item would be before Combine is pressed.
		local previewDef, previewUses = nil, ""
		if #Selection.items == 2 then
			local a, b = ids[Selection.items[1]], ids[Selection.items[2]]
			local resultId = if a and b then recipes[if a < b then a .. "+" .. b else b .. "+" .. a] else nil
			previewDef = if resultId then Index.item(resultId) else nil
			if a and b then
				previewUses = ItemIcon.name(a) .. " + " .. ItemIcon.name(b)
			end
		end
		if previewDef then
			detailName.Text = "Makes: " .. previewDef.name
			detailText.Text = ItemText.describe(previewDef) .. "\n\nFuses " .. previewUses
			takeOff.Visible = false
		elseif inspected and inspectedDef then
			local text = ItemText.describe(inspectedDef)
			if inspected.e then
				for _, unit in snapshot.units do
					local unitDef = if unit.u == inspected.e then Index.unit(unit.d) else nil
					if unitDef then
						text = ("Equipped on %s\n\n%s"):format(unitDef.name, text)
					end
				end
			end
			detailName.Text = inspectedDef.name
			detailText.Text = text
			takeOff.Visible = inspected.e ~= nil
		else
			Selection.inspected = nil -- the item was combined or sold away
			detailName.Text = "Item details"
			detailText.Text = "Tap an item to see what it does."
			takeOff.Visible = false
		end

		table.sort(loose, function(a, b)
			return a.u < b.u
		end)
		-- Forget selected items that no longer exist (combined, equipped or sold).
		for i = #Selection.items, 1, -1 do
			if not ids[Selection.items[i]] then
				table.remove(Selection.items, i)
			end
		end

		Components.clear(grid, { UIGridLayout = true })
		for order, item in loose do
			local tile = ItemIcon.tile(grid, item.i, TILE)
			tile.LayoutOrder = order
			if Selection.hasItem(item.u) then
				local ring = Instance.new("UIStroke")
				ring.Color = Color3.new(1, 1, 1)
				ring.Thickness = 6
				ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				ring.Parent = tile
			end
			DragController.registerTarget(tile, {
				accepts = function(payload)
					return payload.kind == "item" and payload.uid ~= item.u
				end,
				onDrop = function(payload)
					Actions.combineItems(payload.uid, item.u)
					Selection.clearItems()
				end,
			})
			DragController.attach(tile, { kind = "item", uid = item.u }, function()
				Selection.toggleItem(item.u)
			end)
		end

		local picks = Selection.items
		if #picks == 2 then
			local a, b = ids[picks[1]], ids[picks[2]]
			local key = if a < b then a .. "+" .. b else b .. "+" .. a
			local result = recipes[key]
			combine.Text = if result then ("Combine -> " .. ItemIcon.name(result)) else "Can't combine these"
			combine.BackgroundColor3 = if result then Theme.colors.good else Theme.colors.bad
			hint.Text = ""
		else
			combine.Text = "Combine"
			combine.BackgroundColor3 = Color3.fromRGB(60, 60, 78)
			hint.Text = if #loose == 0 then "No items yet. They drop from monsters, the carousel and augments."
				else "Tap an item, then a unit to equip. Tap two components, then Combine."
		end
	end

	return { frame = frame, render = render }
end


return InventoryPanel
