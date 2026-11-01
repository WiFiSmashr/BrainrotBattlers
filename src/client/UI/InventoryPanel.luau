--!strict
-- Item inventory: components and combined items that are not on a unit (GDD 12.2, 12.3).
-- Tap an item to select it; tap a unit to equip it. Tap two components and press Combine, or drag
-- one onto the other. Drag an item off a unit and drop it here to unequip it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemData = require(Shared.Data.Items)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local Selection = require(script.Parent.Selection)
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
	Components.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Items", TextSize = 30, Parent = frame })
	local grid = Components.scroll({ Size = UDim2.new(1, -12, 1, -170), Position = UDim2.fromOffset(6, 44), Parent = frame })
	Components.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(TILE, TILE), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
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

	-- Dropping an equipped item here takes it off its unit (UI-04: the tap route is the unit card).
	DragController.registerTarget(frame, {
		accepts = function(payload)
			return payload.kind == "equipped"
		end,
		onDrop = function(payload)
			Actions.unequipItem(payload.uid)
		end,
	})

	local function render(snapshot: { [string]: any })
		local loose = {}
		local ids: { [number]: string } = {}
		for _, item in snapshot.items do
			if not item.e then
				table.insert(loose, item)
				ids[item.u] = item.i
			end
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
