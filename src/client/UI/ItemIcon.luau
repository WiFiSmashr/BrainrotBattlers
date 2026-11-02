--!strict
-- Small colored icons for items: the first stat tag sets the color, the second (combined items) the
-- border. Placeholder art; real icons can replace this later via Assets.

local Index = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Index)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local TAG_COLORS: { [string]: Color3 } = {
	AD = Color3.fromRGB(230, 80, 80),
	AP = Color3.fromRGB(180, 100, 240),
	Health = Color3.fromRGB(90, 200, 110),
	AS = Color3.fromRGB(255, 210, 70),
	Armor = Color3.fromRGB(240, 150, 60),
	MR = Color3.fromRGB(80, 200, 230),
}

local ItemIcon = {}

-- Display name for an item id.
function ItemIcon.name(itemId: string): string
	local def = Index.item(itemId)
	return if def then def.name else itemId
end

-- Fills a frame as an item icon of the given size.
local function paint(icon: GuiObject, itemId: string)
	local def = Index.item(itemId)
	local tags = if def then def.tags else {}
	icon.BackgroundColor3 = TAG_COLORS[tags[1] or ""] or Theme.colors.panelLight
	local stroke = Instance.new("UIStroke")
	stroke.Color = TAG_COLORS[tags[2] or tags[1] or ""] or Theme.colors.textDim
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = icon
end

-- A 22 x 22 icon shown on unit tiles.
function ItemIcon.mini(parent: Instance, itemId: string): Frame
	local icon = Components.create("Frame", { Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0, Parent = parent, ZIndex = 7 })
	Components.style(icon, 4)
	paint(icon, itemId)
	Components.label({ Size = UDim2.fromScale(1, 1), Text = string.sub(ItemIcon.name(itemId), 1, 1), TextSize = 14, TextColor3 = Color3.new(0, 0, 0), Parent = icon, ZIndex = 8 })
	return icon
end

-- A larger tappable icon with the item name underneath, for the inventory and the unit card.
function ItemIcon.tile(parent: Instance, itemId: string, size: number): TextButton
	local tile = Components.button({
		Size = UDim2.fromOffset(size, size), Text = "", AutoButtonColor = false, Parent = parent, radius = 8, ZIndex = 3,
	})
	paint(tile, itemId)
	Components.fitText(Components.label({
		Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Text = ItemIcon.name(itemId), TextSize = 16,
		TextWrapped = true, TextColor3 = Color3.new(0, 0, 0), Parent = tile, ZIndex = 4,
	}), 16, 8)
	return tile
end

return ItemIcon
