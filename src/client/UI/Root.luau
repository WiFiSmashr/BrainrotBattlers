--!strict
-- Builds the ScreenGui, scales it to the screen against a 1920 x 1080 reference (UI-03), mounts every
-- panel and re-renders them all from the StateStore (UI-01). Panels never talk to each other; they
-- read the snapshot and the local Selection, and send intents through Actions.

local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local StateStore = require(script.Parent.Parent.StateStore)
local Selection = require(script.Parent.Selection)
local DragController = require(script.Parent.DragController)
local Feedback = require(script.Parent.Feedback)
local TopBar = require(script.Parent.TopBar)
local EconomyBar = require(script.Parent.EconomyBar)
local ShopPanel = require(script.Parent.ShopPanel)
local TraitPanel = require(script.Parent.TraitPanel)
local InventoryPanel = require(script.Parent.InventoryPanel)
local UnitCard = require(script.Parent.UnitCard)
local AugmentPicker = require(script.Parent.AugmentPicker)
local CarouselPanel = require(script.Parent.CarouselPanel)
local IncomePopup = require(script.Parent.IncomePopup)
local EndScreen = require(script.Parent.EndScreen)
local ToastLayer = require(script.Parent.ToastLayer)
local BoardView = require(script.Parent.Parent.View.BoardView)
local CombatView = require(script.Parent.Parent.View.CombatView)

local Root = {}

-- Creates the interface under the local player's PlayerGui and wires it to the store.
function Root.build()
	local screen = Components.create("ScreenGui", {
		Name = "BrainrotBattlers", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	pcall(function()
		screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- keep clear of notches and home bars
	end)

	local root = Components.create("Frame", { Name = "Root", BackgroundColor3 = Theme.colors.bg, BorderSizePixel = 0, Parent = screen })
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	-- The reference frame is 1920 x 1080; the other axis grows to fill the screen, and panels anchor to edges.
	local function relayout()
		local size = screen.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = math.min(size.X / Theme.referenceWidth, size.Y / Theme.referenceHeight)
		uiScale.Scale = scale
		root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	relayout()

	Feedback.init(root)
	local waiting = Components.label({
		Size = UDim2.fromScale(1, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextSize = 56,
		Text = "Waiting for players...", Parent = root,
	})

	local board = BoardView.build(root)
	local combat = CombatView.build(root)
	local panels = {
		TopBar.build(root), EconomyBar.build(root), ShopPanel.build(root), TraitPanel.build(root), InventoryPanel.build(root),
		UnitCard.build(root), CarouselPanel.build(root), IncomePopup.build(root), AugmentPicker.build(root), EndScreen.build(root),
	}
	local topBar = panels[1]
	local always = { panels[1], panels[2], panels[3], panels[4], panels[5] } -- panels that are always on screen once the match runs
	ToastLayer.build(root)

	local lastSnapshot: { [string]: any }? = nil
	local lastPhase = "Lobby"
	local pending = false

	local function renderAll()
		if DragController.dragging then
			pending = true -- re-rendering would destroy the thing being dragged
			return
		end
		pending = false
		local snapshot = StateStore.snapshot
		local phase = StateStore.phase.name

		if snapshot ~= lastSnapshot then
			Feedback.observe(lastSnapshot, snapshot :: any, StateStore.userId)
			lastSnapshot = snapshot
		end
		if phase ~= lastPhase then
			local old = lastPhase
			lastPhase = phase -- set first: clearing the selection re-enters renderAll
			Feedback.phaseChanged(old, phase)
			if phase ~= "Prep" then
				Selection.clear() -- nothing can be moved outside Prep
			end
		end

		waiting.Visible = snapshot == nil
		topBar.render(snapshot)
		for _, panel in always do
			panel.frame.Visible = snapshot ~= nil
		end
		if not snapshot then
			board.frame.Visible = false
			combat.hide()
			return
		end
		for _, panel in panels do
			if panel ~= topBar then
				panel.render(snapshot)
			end
		end
		-- The 3D playback lives in the workspace; this 2D view is the player-facing combat overlay. The
		-- bench stays on screen during combat so purchases are visible.
		local inCombat = phase == "Combat"
		board.frame.Visible = true
		board.setCombat(inCombat)
		board.render(snapshot)
		if inCombat then
			combat.show()
		else
			combat.hide()
		end
	end

	StateStore.changed:connect(renderAll)
	Selection.changed:connect(renderAll)
	DragController.finished:connect(function()
		if pending then
			renderAll()
		end
	end)
	StateStore.combat:connect(combat.handle)
	renderAll()
	return screen
end

return Root
