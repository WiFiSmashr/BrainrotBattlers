--!strict
-- Economy bar: gold with an interest meter, level, XP bar and streak (GDD 12.2). Low gold shows red
-- so it is visible at a glance.

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.GameConfig)
local EconomyConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.EconomyConfig)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local EconomyBar = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Builds the bar into `parent`.
function EconomyBar.build(parent: Instance): View
	local frame = Components.panel({
		Name = "EconomyBar", Size = UDim2.fromOffset(1254, 96), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Parent = parent,
	})
	local gold = Components.label({ Size = UDim2.fromOffset(190, 52), Position = UDim2.fromOffset(16, 6), Text = "0", TextSize = 46, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.colors.gold, Parent = frame })
	local pips = Components.create("Frame", { Size = UDim2.fromOffset(190, 22), Position = UDim2.fromOffset(16, 62), BackgroundTransparency = 1, Parent = frame })
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = pips })
	local pipFrames: { Frame } = {}
	for i = 1, EconomyConfig.interestCap do
		pipFrames[i] = Components.panel({ Size = UDim2.fromOffset(30, 18), BackgroundColor3 = Color3.fromRGB(60, 60, 78), radius = 5, Parent = pips })
	end
	local interestLabel = Components.label({ Size = UDim2.fromOffset(190, 20), Position = UDim2.fromOffset(16, 40), Text = "", TextSize = 16, TextColor3 = Theme.colors.textDim, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	interestLabel.Position = UDim2.fromOffset(100, 12)
	interestLabel.TextXAlignment = Enum.TextXAlignment.Right
	interestLabel.Size = UDim2.fromOffset(100, 20)

	local level = Components.label({ Size = UDim2.fromOffset(150, 44), Position = UDim2.fromOffset(240, 6), Text = "Lv 1", TextSize = 38, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local xp = Components.bar({ Size = UDim2.fromOffset(520, 30), Position = UDim2.fromOffset(240, 54), fillColor = Theme.colors.mana, Parent = frame, TextSize = 20 })
	local streak = Components.label({ Size = UDim2.fromOffset(300, 60), Position = UDim2.new(1, -316, 0, 18), Text = "", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
	local counters = Components.label({ Size = UDim2.fromOffset(330, 30), Position = UDim2.new(1, -346, 0, 58), Text = "", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })

	local function render(snapshot: { [string]: any })
		gold.Text = tostring(snapshot.gold)
		gold.TextColor3 = if snapshot.gold < EconomyConfig.rerollCost then Theme.colors.bad else Theme.colors.gold
		local filled = math.min(math.floor(snapshot.gold / EconomyConfig.interestStep), EconomyConfig.interestCap)
		for i, pip in pipFrames do
			pip.BackgroundColor3 = if i <= filled then Theme.colors.gold else Color3.fromRGB(60, 60, 78)
		end
		interestLabel.Text = ("+%d interest"):format(filled)

		level.Text = "Lv " .. snapshot.level
		local needed = GameConfig.xpToNextLevel[snapshot.level]
		if needed then
			xp.set(snapshot.xp / needed, ("XP %d / %d"):format(snapshot.xp, needed))
		else
			xp.set(1, "MAX LEVEL")
		end

		-- Board and bench fill, always visible at a glance (12.4).
		local onBoard, onBench = 0, 0
		for _, unit in snapshot.units do
			if unit.b then
				onBench += 1
			else
				onBoard += 1
			end
		end
		local boardFull, benchFull = onBoard >= snapshot.level, onBench >= GameConfig.benchSlots
		counters.Text = ("Units %d/%d%s   Bench %d/%d%s"):format(onBoard, snapshot.level, if boardFull then " FULL" else "", onBench, GameConfig.benchSlots, if benchFull then " FULL" else "")
		counters.TextColor3 = if boardFull or benchFull then Theme.colors.accent else Theme.colors.text

		local s = snapshot.streak
		if s.k == "none" or s.n < 2 then
			streak.Text = ""
		else
			streak.Text = ("%s streak %d"):format(if s.k == "win" then "Win" else "Loss", s.n)
			streak.TextColor3 = if s.k == "win" then Theme.colors.good else Theme.colors.bad
		end
	end

	return { frame = frame, render = render }
end

return EconomyBar
