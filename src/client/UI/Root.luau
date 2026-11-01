--!strict
-- Builds the ScreenGui, scales it to the screen against a 1920 x 1080 reference (UI-03), mounts every
-- panel and re-renders them all from the StateStore (UI-01). Panels never talk to each other; they
-- read the snapshot and the local Selection, and send intents through Actions.

local Players = game:GetService("Players")
local ArenaLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.ArenaLayout)
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
local MainMenu = require(script.Parent.MainMenu)
local ToastLayer = require(script.Parent.ToastLayer)
local PlotView = require(script.Parent.Parent.View.PlotView)
local CombatCamera = require(script.Parent.Parent.View.CombatCamera)
local CombatWorld = require(script.Parent.Parent.View.CombatWorld)

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
	local menu = MainMenu.build(root)

	local plot = PlotView.build()
	local combat = CombatWorld.build()
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
		if DragController.dragging or plot.dragging() then
			pending = true -- re-rendering would destroy the thing being dragged
			return
		end
		pending = false
		local snapshot = StateStore.snapshot
		local phase = StateStore.phase.name

		if snapshot ~= lastSnapshot then
			local previous = lastSnapshot
			lastSnapshot = snapshot -- set first: clearing the selection re-enters renderAll
			if snapshot then
				Feedback.observe(previous, snapshot, StateStore.userId)
			else
				lastPhase = "Lobby"
				Selection.clear() -- back at the menu: nothing stays selected
			end
		end
		if phase ~= lastPhase then
			local old = lastPhase
			lastPhase = phase -- set first: clearing the selection re-enters renderAll
			Feedback.phaseChanged(old, phase)
			if phase ~= "Prep" then
				Selection.clear() -- nothing can be moved outside Prep
			end
		end

		menu.render()
		topBar.render(snapshot)
		for _, panel in always do
			panel.frame.Visible = snapshot ~= nil
		end
		if not snapshot then
			root.BackgroundTransparency = 0
			combat.setActive(false)
			CombatCamera.exit()
			plot.render({ units = {}, items = {}, players = {}, seat = 1 })
			return
		end
		for _, panel in panels do
			if panel ~= topBar then
				panel.render(snapshot)
			end
		end
		-- The world is always on screen once the match runs. Outside your own fight the camera sits over
		-- your plot (Prep, bench, board, monsters); in Combat CombatWorld moves it to the fight arena.
		local inCombat = phase == "Combat"
		root.BackgroundTransparency = 1
		if not inCombat then
			CombatCamera.enter(ArenaLayout.plotOrigin(snapshot.seat), true)
		end
		plot.render(snapshot)
		combat.setActive(inCombat)
	end

	StateStore.changed:connect(renderAll)
	Selection.changed:connect(renderAll)
	plot.dragFinished:connect(function()
		if pending then
			renderAll()
		end
	end)
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
