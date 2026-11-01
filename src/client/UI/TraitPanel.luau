--!strict
-- Trait panel: one row per trait on the board with icon, count, tier pips and the next breakpoint.
-- Active traits sort first. Tapping a row shows its tier text (GDD 12.2, TRT-07).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Index = require(Shared.Util.Index)
local TraitCounter = require(Shared.Util.TraitCounter)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local TraitPanel = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Entries (unit id + trait ids) for the units standing on the board.
local function boardEntries(snapshot: { [string]: any }): { TraitCounter.Entry }
	local entries = {}
	for _, unit in snapshot.units do
		local def = Index.unit(unit.d)
		if unit.c and def then
			table.insert(entries, { defId = unit.d, traits = def.traits })
		end
	end
	return entries
end

-- Builds the panel into `parent`.
function TraitPanel.build(parent: Instance): View
	local frame = Components.panel({
		Name = "TraitPanel", Size = UDim2.fromOffset(290, 740), Position = UDim2.fromOffset(8, 108), Parent = parent,
	})
	Components.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Traits", TextSize = 30, Parent = frame })
	local list = Components.scroll({ Size = UDim2.new(1, -12, 1, -48), Position = UDim2.fromOffset(6, 44), Parent = frame })
	Components.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local expanded: { [string]: boolean } = {} -- UI-local: which rows show their tier text

	local latest: { [string]: any }? = nil
	local render

	function render(snapshot: { [string]: any })
		latest = snapshot
		Components.clear(list, { UIListLayout = true })
		local counted = TraitCounter.count(boardEntries(snapshot))
		local rows = {}
		for traitId, state in counted do
			table.insert(rows, { id = traitId, state = state })
		end
		table.sort(rows, function(a, b)
			local activeA, activeB = a.state.tierIndex > 0, b.state.tierIndex > 0
			if activeA ~= activeB then
				return activeA
			end
			if a.state.count ~= b.state.count then
				return a.state.count > b.state.count
			end
			return a.id < b.id
		end)
		if #rows == 0 then
			Components.label({ Size = UDim2.new(1, 0, 0, 80), Text = "Put units on the board to build traits", TextSize = 20, TextWrapped = true, TextColor3 = Theme.colors.textDim, Parent = list })
		end

		for order, row in rows do
			local trait = Index.trait(row.id) :: any
			local active = row.state.tierIndex > 0
			local isOpen = expanded[row.id] == true
			local card = Components.button({
				Size = UDim2.new(1, -6, 0, if isOpen then 74 + #trait.tiers * 52 else 74), Text = "", AutoButtonColor = false, LayoutOrder = order,
				BackgroundColor3 = if active then Theme.colors.panelLight else Color3.fromRGB(44, 46, 66), Parent = list, radius = 8,
				onTap = function()
					expanded[row.id] = not expanded[row.id]
					if latest then
						render(latest)
					end
				end,
			})
			local icon = Components.panel({
				Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(8, 8), radius = 8, Parent = card,
				BackgroundColor3 = if trait.kind == "Origin" then Color3.fromRGB(230, 130, 80) else Color3.fromRGB(90, 150, 230),
			})
			Components.label({ Size = UDim2.fromScale(1, 1), Text = string.sub(trait.name, 1, 1), TextSize = 28, TextColor3 = Color3.new(0, 0, 0), Parent = icon })
			Components.label({
				Size = UDim2.new(1, -118, 0, 28), Position = UDim2.fromOffset(62, 4), Text = trait.name, TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if active then Theme.colors.text else Theme.colors.textDim, Parent = card,
			})
			Components.label({
				Size = UDim2.fromOffset(52, 40), Position = UDim2.new(1, -58, 0, 4), Text = tostring(row.state.count), TextSize = 32,
				TextColor3 = if active then Theme.colors.accent else Theme.colors.textDim, Parent = card,
			})
			-- One pip per tier; filled up to the active tier.
			local pips = Components.create("Frame", { Size = UDim2.new(1, -70, 0, 14), Position = UDim2.fromOffset(62, 34), BackgroundTransparency = 1, Parent = card })
			Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = pips })
			for i = 1, #trait.tiers do
				Components.panel({
					Size = UDim2.fromOffset(28, 12), radius = 4, Parent = pips,
					BackgroundColor3 = if i <= row.state.tierIndex then Theme.colors.accent else Color3.fromRGB(70, 72, 96),
				})
			end
			local nextText = if row.state.nextCount then ("%d / %d"):format(row.state.count, row.state.nextCount) else "max tier"
			Components.label({
				Size = UDim2.new(1, -70, 0, 20), Position = UDim2.fromOffset(62, 50), Text = "next: " .. nextText, TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.colors.textDim, Parent = card,
			})
			if isOpen then
				for i, tier in trait.tiers do
					Components.label({
						Size = UDim2.new(1, -16, 0, 48), Position = UDim2.fromOffset(8, 72 + (i - 1) * 52), TextWrapped = true, TextSize = 15,
						Text = ("(%d) %s"):format(tier.count, tier.description), Font = Theme.fontBody, TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = if i == row.state.tierIndex then Theme.colors.accent else Theme.colors.textDim,
						Parent = card,
					})
				end
			end
		end
	end

	return { frame = frame, render = render }
end

return TraitPanel
