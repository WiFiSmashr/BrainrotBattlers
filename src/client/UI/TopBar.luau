--!strict
-- Top bar: stage, phase and countdown with a round timeline at the top centre, and the player list
-- with health bars and augment icons (GDD 12.2, AUG-08). The countdown is computed from the
-- server's endsAt, so it matches the server. The timeline shows one stage at a time: rounds already
-- played are dimmed, the current round is highlighted, later rounds show their type.

local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AugmentData = require(Shared.Data.Augments)
local GameConfig = require(Shared.Config.GameConfig)
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

-- Timeline cell colour and letter by round type.
local ROUND_COLOR: { [string]: Color3 } = {
	pve = Color3.fromRGB(190, 80, 80), pvp = Color3.fromRGB(80, 120, 200), carousel = Color3.fromRGB(205, 165, 50),
}
local ROUND_LETTER: { [string]: string } = { pve = "PvE", pvp = "PvP", carousel = "Pick" }

local CENTER_WIDTH = 560
local PLAYER_AREA = 640 -- room for the player cards beside the centre block on a 1920-wide screen
local MAX_PLAYER_WIDTH = 150

local TopBar = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }?) -> () }

-- The rounds of a stage, in order.
local function layoutOf(stage: number): { { type: string } }
	return if stage == 1 then GameConfig.stage1Layout else GameConfig.laterStageLayout
end

-- Builds the bar into `parent`.
function TopBar.build(parent: Instance): View
	local frame = Components.panel({
		Name = "TopBar", Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = Theme.colors.bg, radius = 0, Parent = parent,
	})
	local center = Components.create("Frame", {
		Name = "Center", Size = UDim2.fromOffset(CENTER_WIDTH, 92), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2),
		BackgroundTransparency = 1, Parent = frame,
	})
	local stageLabel = Components.label({
		Size = UDim2.fromOffset(190, 44), Text = "", TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, Parent = center,
	})
	local phaseLabel = Components.label({
		Size = UDim2.fromOffset(180, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Text = "", TextSize = 26,
		TextColor3 = Theme.colors.textDim, Parent = center,
	})
	local timerLabel = Components.label({
		Size = UDim2.fromOffset(150, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Text = "", TextSize = 46,
		TextColor3 = Theme.colors.accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = center,
	})
	local timeline = Components.create("Frame", {
		Name = "Timeline", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 48), BackgroundTransparency = 1, Parent = center,
	})
	Components.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), Parent = timeline,
	})

	local list = Components.create("Frame", {
		Size = UDim2.fromOffset(PLAYER_AREA, 86), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5),
		BackgroundTransparency = 1, Parent = frame,
	})
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), Parent = list })

	-- The countdown ticks every frame from the server clock.
	RunService.Heartbeat:Connect(function()
		local left = StateStore.timeLeft()
		timerLabel.Text = if left then ("%d"):format(math.ceil(left)) else ""
	end)

	-- Draws the current stage's rounds: played ones dimmed, the current one lit, later ones by type.
	local function renderTimeline(roundId: string)
		Components.clear(timeline, { UIListLayout = true })
		local stageText, roundText = roundId:match("^(%d+)-(%d+)$")
		if not stageText then
			return
		end
		local stage, current = tonumber(stageText) :: number, tonumber(roundText) :: number
		local rounds = layoutOf(stage)
		local gap = 6
		local width = math.min(76, math.floor((CENTER_WIDTH - gap * (#rounds - 1)) / #rounds))
		for index, entry in rounds do
			local id = stage .. "-" .. index
			local isCurrent = index == current
			local played = index < current
			local cell = Components.panel({
				Size = UDim2.fromOffset(width, if isCurrent then 40 else 32), LayoutOrder = index, radius = 8,
				BackgroundColor3 = ROUND_COLOR[entry.type] or Theme.colors.panelLight, BackgroundTransparency = if played then 0.7 else 0,
				stroke = if isCurrent then Color3.new(1, 1, 1) else nil, Active = false, Parent = timeline,
			})
			Components.label({
				Size = UDim2.fromScale(1, 1), Text = ROUND_LETTER[entry.type] or entry.type, TextSize = if isCurrent then 22 else 18,
				TextTransparency = if played then 0.4 else 0, Parent = cell,
			})
			if GameConfig.augmentRounds[id] then
				-- Augment rounds carry a small marker in the corner.
				Components.panel({
					Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), radius = 6,
					BackgroundColor3 = Theme.colors.accent, Active = false, ZIndex = 3, Parent = cell,
				})
			end
		end
	end

	local lastTimeline = ""
	local function render(snapshot: { [string]: any }?)
		local phase = StateStore.phase
		local inLobby = phase.name == "Lobby"
		stageLabel.Text = if inLobby then "" else "Stage " .. tostring(phase.roundId:match("^(%d+)") or "")
		phaseLabel.Text = PHASE_TEXT[phase.name] or phase.name
		local shown = if inLobby then "" else phase.roundId
		if shown ~= lastTimeline then
			lastTimeline = shown
			renderTimeline(shown)
		end

		Components.clear(list, { UIListLayout = true })
		if not snapshot then
			return
		end
		local cardWidth = math.min(MAX_PLAYER_WIDTH, math.floor(PLAYER_AREA / math.max(#snapshot.players, 1)))
		for _, p in snapshot.players do
			local out = p.place ~= nil
			local mine = p.id == StateStore.userId
			local card = Components.panel({
				Size = UDim2.fromOffset(cardWidth - 4, 82), BackgroundColor3 = if out then Color3.fromRGB(40, 40, 46) else Theme.colors.panel,
				radius = 8, stroke = if mine then Theme.colors.accent else nil, LayoutOrder = p.id, Parent = list,
			})
			Components.label({
				Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(6, 2), Text = if out then ("#%d %s"):format(p.place, p.n) else p.n,
				TextSize = if cardWidth < 110 then 15 else 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
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
