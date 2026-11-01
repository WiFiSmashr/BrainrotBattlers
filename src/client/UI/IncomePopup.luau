--!strict
-- Income popup: the itemized income breakdown for 2 seconds at the start of Prep (GDD 12.2, ECON-02).
-- It appears once per new income record (the round id changes).

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local SHOW_SECONDS = 2

local IncomePopup = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Builds the popup into `parent`.
function IncomePopup.build(parent: Instance): View
	local frame = Components.panel({
		Name = "IncomePopup", Size = UDim2.fromOffset(380, 100), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 230),
		Visible = false, ZIndex = 40, Parent = parent, stroke = Theme.colors.gold,
	})
	local text = Components.label({ Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8), TextSize = 28, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 41, Parent = frame })
	local lastRound: string? = nil
	local shownAt = 0

	local function render(snapshot: { [string]: any })
		local income = snapshot.income
		if income and income.round ~= lastRound then
			lastRound = income.round
			shownAt = os.clock()
			local lines = { "Income" }
			local function add(label: string, amount: number)
				if amount ~= 0 then
					table.insert(lines, ("%s  +%d"):format(label, amount))
				end
			end
			add("Base", income.base)
			add("Interest", income.interest)
			add("Streak", income.streak)
			add(if snapshot.streak.k == "loss" then "Loss bonus" else "Win bonus", income.win)
			for _, extra in income.extras do
				add(extra.label, extra.amount)
			end
			table.insert(lines, ("Total  +%d gold"):format(income.total))
			text.Text = table.concat(lines, "\n")
			frame.Size = UDim2.fromOffset(380, 36 + #lines * 34)
			frame.Visible = true
			task.delay(SHOW_SECONDS, function()
				if os.clock() - shownAt >= SHOW_SECONDS - 0.05 then
					frame.Visible = false
				end
			end)
		end
	end

	return { frame = frame, render = render }
end

return IncomePopup
