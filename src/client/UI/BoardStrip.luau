--!strict
-- "Your board" strip, shown during Combat (D-87). While the fight plays your fielded units are busy
-- fighting, so they cannot be tapped in the world. This strip lists them so you can still open a unit's
-- card (to sell it), equip a selected item on it, or drop an item onto it. Outside Combat the units are
-- tapped in the 3D world as usual and the strip is hidden.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Index = require(Shared.Util.Index)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local Selection = require(script.Parent.Selection)
local DragController = require(script.Parent.DragController)
local UnitPortrait = require(script.Parent.UnitPortrait)
local StateStore = require(script.Parent.Parent.StateStore)

local TILE, GAP, PER_ROW = 50, 6, 5

local BoardStrip = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Builds the strip into `parent`.
function BoardStrip.build(parent: Instance): View
	local frame = Components.panel({
		Name = "BoardStrip", Size = UDim2.fromOffset(PER_ROW * TILE + (PER_ROW - 1) * GAP + 16, 160), AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8), Visible = false, Parent = parent,
	})
	Components.label({ Size = UDim2.new(1, 0, 0, 30), Text = "Your board", TextSize = 22, Parent = frame })
	local grid = Components.create("Frame", { Size = UDim2.new(1, -16, 1, -36), Position = UDim2.fromOffset(8, 34), BackgroundTransparency = 1, Parent = frame })

	local function equipOrSelect(uid: number)
		if #Selection.items > 0 then
			Actions.equipItem(Selection.items[1], uid)
			Selection.clearItems()
		elseif Selection.unit == uid then
			Selection.selectUnit(nil)
		else
			Selection.selectUnit(uid)
		end
	end

	local function render(snapshot: { [string]: any })
		local show = StateStore.phase.name == "Combat" and StateStore.scouting == nil
		frame.Visible = show
		if not show then
			return
		end
		Components.clear(grid)
		local order = 0
		for _, unit in snapshot.units do
			local def = Index.unit(unit.d)
			if unit.c and def then
				order += 1
				local x = ((order - 1) % PER_ROW) * (TILE + GAP)
				local y = ((order - 1) // PER_ROW) * (TILE + GAP)
				local tile = Components.button({
					Size = UDim2.fromOffset(TILE, TILE), Position = UDim2.fromOffset(x, y), Text = "", AutoButtonColor = false,
					BackgroundColor3 = def.tint or Theme.colors.panelLight, radius = 8, Parent = grid,
					onTap = function()
						equipOrSelect(unit.u)
					end,
				})
				if not UnitPortrait.attach(tile, def, 2) then
					Components.label({ Size = UDim2.fromScale(1, 1), Text = string.sub(def.name, 1, 1), TextSize = 26, TextColor3 = Color3.new(0, 0, 0), ZIndex = 2, Parent = tile })
				end
				local stroke = Instance.new("UIStroke")
				stroke.Color = if Selection.unit == unit.u then Color3.new(1, 1, 1) else Theme.costColor(def.cost)
				stroke.Thickness = if Selection.unit == unit.u then 4 else 3
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = tile
				Components.label({
					Size = UDim2.new(1, 0, 0, 16), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Text = string.rep("★", unit.s),
					TextSize = 14, TextColor3 = Theme.colors.accent, TextStrokeTransparency = 0.3, ZIndex = 4, Parent = tile,
				})
				local carried = 0
				for _, item in snapshot.items do
					if item.e == unit.u then
						carried += 1
					end
				end
				if carried > 0 then
					Components.label({
						Size = UDim2.fromOffset(18, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Text = tostring(carried),
						TextSize = 14, TextStrokeTransparency = 0.3, ZIndex = 4, Parent = tile,
					})
				end
				-- An item dragged from the item panel can be dropped straight onto the tile.
				DragController.registerTarget(tile, {
					accepts = function(payload)
						return payload.kind == "item"
					end,
					onDrop = function(payload)
						Actions.equipItem(payload.uid, unit.u)
						Selection.clearItems()
					end,
				})
			end
		end
	end

	return { frame = frame, render = render }
end

return BoardStrip
