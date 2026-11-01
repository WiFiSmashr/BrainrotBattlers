--!strict
-- Top bar: round label, phase, countdown, and the player list with health bars and augment icons
-- (GDD 12.2, AUG-08). The countdown is computed from the server's endsAt, so it matches the server.

local RunService = game:GetService("RunService")
local AugmentData = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Data.Augments)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local StateStore = require(script.Parent.Parent.StateStore)

local AUGMENT_RARITY: { [string]: string } = {}
for _, a in AugmentData do
	AUGMENT_RARITY[a.id] = a.rarity
end

local PHASE_TEXT: { [string]: string } = {
	Lobby = "Waiting for players", MatchStart = "Get ready", Prep = "Prep", Combat = "Combat",
	Resolve = "Results", Carousel = "Carousel", MatchEnd = "Match over",
}

local PLAYER_WIDTH = 150
local MAX_PLAYERS = 8

local TopBar = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }?) -> () }

-- Builds the bar into `parent`.
function TopBar.build(parent: Instance): View
	local frame = Components.panel({
		Name = "TopBar", Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = Theme.colors.bg, radius = 0, Parent = parent,
	})
	local roundLabel = Components.label({ Size = UDim2.fromOffset(120, 50), Position = UDim2.fromOffset(16, 6), Text = "1-1", TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local phaseLabel = Components.label({ Size = UDim2.fromOffset(250, 34), Position = UDim2.fromOffset(16, 56), Text = "", TextSize = 26, TextColor3 = Theme.colors.textDim, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local timerLabel = Components.label({ Size = UDim2.fromOffset(150, 70), Position = UDim2.fromOffset(150, 12), Text = "", TextSize = 52, TextColor3 = Theme.colors.accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })

	local list = Components.create("Frame", {
		Size = UDim2.fromOffset(PLAYER_WIDTH * MAX_PLAYERS, 86), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5),
		BackgroundTransparency = 1, Parent = frame,
	})
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), Parent = list })

	-- The countdown ticks every frame from the server clock.
	RunService.Heartbeat:Connect(function()
		local left = StateStore.timeLeft()
		timerLabel.Text = if left then ("%d"):format(math.ceil(left)) else ""
	end)

	local function render(snapshot: { [string]: any }?)
		local phase = StateStore.phase
		roundLabel.Text = if phase.name == "Lobby" then "" else phase.roundId
		phaseLabel.Text = PHASE_TEXT[phase.name] or phase.name

		Components.clear(list, { UIListLayout = true })
		if not snapshot then
			return
		end
		for _, p in snapshot.players do
			local out = p.place ~= nil
			local mine = p.id == StateStore.userId
			local card = Components.panel({
				Size = UDim2.fromOffset(PLAYER_WIDTH - 4, 82), BackgroundColor3 = if out then Color3.fromRGB(40, 40, 46) else Theme.colors.panel,
				radius = 8, stroke = if mine then Theme.colors.accent else nil, LayoutOrder = p.id, Parent = list,
			})
			Components.label({
				Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(6, 2), Text = if out then ("#%d %s"):format(p.place, p.n) else p.n,
				TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = if out then Theme.colors.textDim else Theme.colors.text, Parent = card,
			})
			local bar = Components.bar({
				Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 32), fillColor = if p.hp > 30 then Theme.colors.good else Theme.colors.bad,
				Parent = card, TextSize = 14,
			})
			bar.set(math.max(p.hp, 0) / 100, tostring(math.max(p.hp, 0)))
			local icons = Components.create("Frame", { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 55), BackgroundTransparency = 1, Parent = card })
			Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), Parent = icons })
			for _, augmentId in p.aug or {} do
				local icon = Components.panel({
					Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Theme.augmentColors[AUGMENT_RARITY[augmentId]] or Theme.colors.textDim,
					radius = 4, Parent = icons,
				})
				icon.Name = augmentId
			end
		end
	end

	return { frame = frame, render = render }
end

return TopBar
