--!strict
-- Carousel panel: the shared offerings, whose turn it is and the pick timer; picked offerings are
-- greyed out with the picker's name (GDD 12.2, CAR-03, CAR-04, CAR-06).

local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local StateStore = require(script.Parent.Parent.StateStore)
local ItemIcon = require(script.Parent.ItemIcon)

local CarouselPanel = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

local function playerName(snapshot: { [string]: any }, userId: number?): string
	for _, p in snapshot.players do
		if p.id == userId then
			return p.n
		end
	end
	return "?"
end

-- Builds the panel into `parent` (hidden outside the Carousel phase).
function CarouselPanel.build(parent: Instance): View
	local frame = Components.panel({
		Name = "CarouselPanel", Size = UDim2.fromOffset(1080, 470), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150),
		Visible = false, ZIndex = 30, Parent = parent, stroke = Theme.colors.accent,
	})
	local title = Components.label({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 8), TextSize = 38, Text = "Carousel", ZIndex = 31, Parent = frame })
	local turn = Components.label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 64), TextSize = 28, Text = "", TextColor3 = Theme.colors.accent, ZIndex = 31, Parent = frame })
	local timer = Components.label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 104), TextSize = 28, Text = "", ZIndex = 31, Parent = frame })
	local grid = Components.create("Frame", {
		Size = UDim2.new(1, -40, 0, 310), Position = UDim2.fromOffset(20, 150), BackgroundTransparency = 1, ZIndex = 31, Parent = frame,
	})
	Components.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 150), CellPadding = UDim2.fromOffset(14, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = grid,
	})

	local current: { [string]: any }? = nil
	RunService.Heartbeat:Connect(function()
		local snapshot = current
		if frame.Visible and snapshot and snapshot.carousel then
			local left = math.max(0, snapshot.carousel.endsAt - StateStore.serverNow())
			timer.Text = if snapshot.carousel.turn then ("Pick time: %d"):format(math.ceil(left)) else "All picks made"
		end
	end)

	local function render(snapshot: { [string]: any })
		current = snapshot
		local carousel = snapshot.carousel
		frame.Visible = StateStore.phase.name == "Carousel" and carousel ~= nil
		if not frame.Visible then
			return
		end
		local mine = carousel.turn == StateStore.userId
		title.Text = if mine then "Your pick!" else "Carousel"
		turn.Text = if carousel.turn then ("Turn: %s"):format(playerName(snapshot, carousel.turn)) else "Waiting for the round to start"
		Components.clear(grid, { UIGridLayout = true })
		for i, offering in carousel.offerings do
			local picked = offering.p ~= nil
			local tile = ItemIcon.tile(grid, offering.i, 150)
			tile.ZIndex = 32
			tile.LayoutOrder = i
			if picked then
				tile.BackgroundTransparency = 0.7
				Components.label({
					Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Text = playerName(snapshot, offering.p),
					TextSize = 22, BackgroundTransparency = 0.2, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 36, Parent = tile,
				})
			elseif mine then
				local ring = Instance.new("UIStroke")
				ring.Color = Theme.colors.accent
				ring.Thickness = 6
				ring.Parent = tile
			end
			tile.Activated:Connect(function()
				Actions.pickCarousel(i)
			end)
		end
	end

	return { frame = frame, render = render }
end

return CarouselPanel
