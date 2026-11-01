--!strict
-- The main menu: Play joins the queue, and the queue starts a match when it fills or the wait ends.
-- Shown whenever the player is not in a match. It reads StateStore.menu and sends JoinQueue /
-- LeaveQueue through Actions.

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local StateStore = require(script.Parent.Parent.StateStore)

local MainMenu = {}

export type View = { frame: Frame, render: () -> () }

-- Builds the menu into `parent`; call `render` when the store changes. It also ticks the countdown itself.
function MainMenu.build(parent: Instance): View
	local frame = Components.create("Frame", {
		Name = "MainMenu", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 50, Parent = parent,
	})
	Components.label({
		Size = UDim2.new(1, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.16, 0),
		Text = "BRAINROT BATTLERS", TextSize = 96, TextColor3 = Theme.colors.accent, ZIndex = 51, Parent = frame,
	})
	Components.label({
		Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.16, 120),
		Text = "Build a team. Outlast the lobby.", TextSize = 32, TextColor3 = Theme.colors.textDim, Font = Theme.fontBody, ZIndex = 51, Parent = frame,
	})
	local panel = Components.panel({
		Size = UDim2.fromOffset(620, 340), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), ZIndex = 51,
		stroke = Theme.colors.accent, radius = 18, Parent = frame,
	})
	local status = Components.label({
		Size = UDim2.new(1, -40, 0, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), TextSize = 40, ZIndex = 52, Parent = panel,
	})
	local detail = Components.label({
		Size = UDim2.new(1, -60, 0, 90), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), TextSize = 28,
		Font = Theme.fontBody, TextColor3 = Theme.colors.textDim, TextWrapped = true, ZIndex = 52, Parent = panel,
	})
	local play = Components.button({
		Size = UDim2.fromOffset(360, 84), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), TextSize = 44,
		Text = "PLAY", BackgroundColor3 = Theme.colors.good, TextColor3 = Color3.new(0, 0, 0), ZIndex = 52, Parent = panel,
		onTap = function()
			if StateStore.menu.status == "Queued" then
				Actions.leaveQueue()
			else
				Actions.joinQueue()
			end
		end,
	})

	local function render()
		local menu = StateStore.menu
		frame.Visible = menu.status ~= "InMatch"
		if not frame.Visible then
			return
		end
		if menu.status == "Queued" then
			status.Text = ("In queue  %d / %d"):format(menu.queued, menu.needed)
			local left = if menu.startsAt then math.max(0, math.ceil(menu.startsAt - StateStore.serverNow())) else nil
			if menu.matchRunning then
				detail.Text = "A match is in progress. You will start in the next one."
			elseif left then
				detail.Text = ("Starting in %d s. Empty seats are filled with bots."):format(left)
			else
				detail.Text = "Waiting for players..."
			end
			play.Text = "CANCEL"
			play.BackgroundColor3 = Theme.colors.bad
		else
			status.Text = "Ready to play?"
			detail.Text = if menu.matchRunning then "A match is in progress. Press Play to queue for the next one." else "Press Play to find a match."
			play.Text = "PLAY"
			play.BackgroundColor3 = Theme.colors.good
		end
	end

	-- The countdown changes every second without any server message.
	task.spawn(function()
		while frame.Parent do
			if frame.Visible and StateStore.menu.status == "Queued" then
				render()
			end
			task.wait(0.25)
		end
	end)

	return { frame = frame, render = render }
end

return MainMenu
