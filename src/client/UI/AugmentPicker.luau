--!strict
-- Augment picker: a modal with 3 rarity-colored cards, a free Reroll button and a countdown. It
-- cannot be dismissed without choosing (GDD 12.2, AUG-01..AUG-05). Also used for the follow-up
-- choices (a component, or one of three combined items) that some augments open.

local RunService = game:GetService("RunService")
local AugmentData = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Data.Augments)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local StateStore = require(script.Parent.Parent.StateStore)
local ItemIcon = require(script.Parent.ItemIcon)

local byId: { [string]: any } = {}
for _, a in AugmentData do
	byId[a.id] = a
end

local AugmentPicker = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

local TITLES = { augment = "Choose an augment", component = "Choose a component", combined = "Choose a combined item" }

-- Builds the modal into `parent` (hidden until the server sends an offer).
function AugmentPicker.build(parent: Instance): View
	local dim = Components.create("TextButton", {
		Name = "AugmentPicker", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		Text = "", AutoButtonColor = false, Visible = false, ZIndex = 50, Active = true, Parent = parent, -- swallows taps behind it
	})
	local title = Components.label({ Size = UDim2.new(1, 0, 0, 60), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), TextSize = 48, ZIndex = 51, Parent = dim })
	local timer = Components.label({ Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), TextSize = 30, TextColor3 = Theme.colors.accent, ZIndex = 51, Parent = dim })
	local cards = Components.create("Frame", {
		Size = UDim2.fromOffset(1260, 540), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 210), BackgroundTransparency = 1, ZIndex = 51, Parent = dim,
	})
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 30), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = cards })
	local reroll = Components.button({
		Size = UDim2.fromOffset(300, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 780), Text = "Reroll (free)", TextSize = 30,
		ZIndex = 51, Parent = dim, onTap = Actions.rerollAugment,
	})

	RunService.Heartbeat:Connect(function()
		if dim.Visible then
			local left = StateStore.timeLeft()
			timer.Text = if left then ("Time left: %d  (the first choice is taken if time runs out)"):format(math.ceil(left)) else ""
		end
	end)

	local function render(snapshot: { [string]: any })
		local offer = snapshot.offer
		dim.Visible = offer ~= nil
		if not offer then
			return
		end
		title.Text = if offer.kind == "augment" and offer.rarity then ("Choose a %s augment"):format(offer.rarity) else (TITLES[offer.kind] or "Choose")
		title.TextColor3 = if offer.rarity then Theme.augmentColors[offer.rarity] else Theme.colors.text
		reroll.Visible = offer.kind == "augment" and not offer.rerolled
		Components.clear(cards, { UIListLayout = true })

		for i, id in offer.choices do
			if offer.kind == "augment" then
				local def = byId[id]
				local color = Theme.augmentColors[def.rarity]
				local card = Components.button({
					Size = UDim2.fromOffset(380, 520), Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.colors.panel, ZIndex = 52,
					LayoutOrder = i, Parent = cards, radius = 14, onTap = function()
						Actions.pickAugment(i)
					end,
				})
				local stroke = Instance.new("UIStroke")
				stroke.Color = color
				stroke.Thickness = 8
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = card
				Components.panel({ Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = color, radius = 6, ZIndex = 53, Parent = card })
				Components.label({ Size = UDim2.new(1, -24, 0, 80), Position = UDim2.fromOffset(12, 34), Text = def.name, TextSize = 36, TextWrapped = true, ZIndex = 53, Parent = card })
				Components.label({ Size = UDim2.new(1, -24, 0, 36), Position = UDim2.fromOffset(12, 118), Text = ("%s  -  %s"):format(def.rarity, table.concat(def.categories, " + ")), TextSize = 22, TextColor3 = color, ZIndex = 53, Parent = card })
				Components.label({
					Size = UDim2.new(1, -28, 0, 300), Position = UDim2.fromOffset(14, 170), Text = def.description, TextSize = 26, TextWrapped = true, Font = Theme.fontBody,
					TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 53, Parent = card,
				})
			else
				local tile = ItemIcon.tile(cards, id, 190)
				tile.ZIndex = 52
				tile.LayoutOrder = i
				tile.Activated:Connect(function()
					Actions.pickAugment(i)
				end)
			end
		end
	end

	return { frame = dim, render = render }
end

return AugmentPicker
