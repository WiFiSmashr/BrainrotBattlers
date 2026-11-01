--!strict
-- End screen: placement, a few stats and a Back to Menu button (GDD 12.2 asked for Play Again; the menu replaces it, D-70). It appears as soon as the
-- server gives this player a placement, whether they won or were eliminated.

local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)

local EndScreen = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

local function ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ [1] = "st", [2] = "nd", [3] = "rd" })[n % 10] or "th"
	end
	return n .. suffix
end

-- Builds the screen into `parent` (hidden until the player has a placement).
function EndScreen.build(parent: Instance): View
	local dim = Components.create("TextButton", {
		Name = "EndScreen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25,
		Text = "", AutoButtonColor = false, Visible = false, ZIndex = 100, Parent = parent,
	})
	local panel = Components.panel({
		Size = UDim2.fromOffset(700, 560), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 101, Parent = dim,
		stroke = Theme.colors.accent, radius = 18,
	})
	local title = Components.label({ Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 24), TextSize = 64, ZIndex = 102, Parent = panel })
	local place = Components.label({ Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 118), TextSize = 44, TextColor3 = Theme.colors.accent, ZIndex = 102, Parent = panel })
	local stats = Components.label({
		Size = UDim2.new(1, -80, 0, 200), Position = UDim2.fromOffset(40, 190), TextSize = 30, TextWrapped = true, Font = Theme.fontBody, ZIndex = 102,
		TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel,
	})
	Components.button({
		Size = UDim2.fromOffset(320, 76), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Text = "Back to Menu", TextSize = 36,
		BackgroundColor3 = Theme.colors.good, TextColor3 = Color3.new(0, 0, 0), ZIndex = 102, Parent = panel,
		onTap = function()
			Actions.backToMenu()
		end,
	})

	local function render(snapshot: { [string]: any })
		local finishedAs = snapshot.place
		dim.Visible = finishedAs ~= nil
		if not finishedAs then
			return
		end
		title.Text = if finishedAs == 1 then "VICTORY!" else "Eliminated"
		place.Text = ("%s place"):format(ordinal(finishedAs))
		local board = 0
		for _, u in snapshot.units do
			if u.c then
				board += 1
			end
		end
		local augments = 0
		for _, p in snapshot.players do
			if p.id == Players.LocalPlayer.UserId then
				augments = #(p.aug or {})
			end
		end
		stats.Text = ("Reached round %s\nLevel %d\nUnits on board: %d\nAugments: %d\nGold left: %d"):format(snapshot.round, snapshot.level, board, augments, snapshot.gold)
	end

	return { frame = dim, render = render }
end

return EndScreen
