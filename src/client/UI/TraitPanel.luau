--!strict
-- Trait panel: one row per trait on the board with icon, count, tier pips and the next breakpoint.
-- Active traits sort first. Tapping a row shows its tier text and the portraits of every unit with that trait (GDD 12.2, TRT-07, D-81).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Index = require(Shared.Util.Index)
local TraitCounter = require(Shared.Util.TraitCounter)
local Units = require(Shared.Data.Units)
local UnitPortrait = require(script.Parent.UnitPortrait)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local PORTRAIT_SIZE, PORTRAIT_GAP, PER_ROW = 44, 4, 5

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

-- Every unit that has the trait, cheapest first (D-81).
local function unitsWithTrait(traitId: string): { Types.UnitDef }
	local found = {}
	for _, def in Units do
		if table.find(def.traits, traitId) then
			table.insert(found, def)
		end
	end
	table.sort(found, function(a, b)
		if a.cost ~= b.cost then
			return a.cost < b.cost
		end
		return a.id < b.id
	end)
	return found
end

-- Height of the portrait grid for a trait.
local function gridHeight(count: number): number
	return math.ceil(count / PER_ROW) * (PORTRAIT_SIZE + PORTRAIT_GAP) + 4
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
		local onBoard: { [string]: boolean } = {}
		for _, unit in snapshot.units do
			if unit.c then
				onBoard[unit.d] = true
			end
		end
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
			local members = unitsWithTrait(row.id)
			local card = Components.button({
				Size = UDim2.new(1, -6, 0, if isOpen then 74 + #trait.tiers * 52 + gridHeight(#members) else 74), Text = "", AutoButtonColor = false, LayoutOrder = order,
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
					Components.fitText(Components.label({
						Size = UDim2.new(1, -16, 0, 48), Position = UDim2.fromOffset(8, 72 + (i - 1) * 52), TextWrapped = true, TextSize = 15,
						Text = ("(%d) %s"):format(tier.count, tier.description), Font = Theme.fontBody, TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = if i == row.state.tierIndex then Theme.colors.accent else Theme.colors.textDim,
						Parent = card,
					}), 15, 9)
				end
				-- Who has this trait: small portraits under the effects, dimmed unless on your board.
				local gridTop = 72 + #trait.tiers * 52
				for index, def in members do
					local x = 8 + ((index - 1) % PER_ROW) * (PORTRAIT_SIZE + PORTRAIT_GAP)
					local y = gridTop + ((index - 1) // PER_ROW) * (PORTRAIT_SIZE + PORTRAIT_GAP)
					local tile = Components.panel({
						Name = def.id, Size = UDim2.fromOffset(PORTRAIT_SIZE, PORTRAIT_SIZE), Position = UDim2.fromOffset(x, y), Active = false,
						BackgroundColor3 = def.tint or Theme.colors.panelLight, radius = 8, stroke = Theme.costColor(def.cost), ZIndex = 2, Parent = card,
					})
					tile.ClipsDescendants = true
					if not UnitPortrait.attach(tile, def, 3) then
						Components.label({ Size = UDim2.fromScale(1, 1), Text = string.sub(def.name, 1, 1), TextSize = 24, TextColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = tile })
					end
					if not onBoard[def.id] then
						Components.create("Frame", {
							Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0,
							ZIndex = 4, Active = false, Parent = tile,
						})
					end
				end
			end
		end
	end

	return { frame = frame, render = render }
end

return TraitPanel
