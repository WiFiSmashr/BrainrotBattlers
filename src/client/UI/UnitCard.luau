--!strict
-- Unit info card: stats, ability text for the unit's current star, traits and items, with Sell
-- (the tap route for selling) and its items: tap one to read what it does, then Take off in the item
-- panel (GDD 12.2, 12.3). Shown while a unit is selected.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Index = require(Shared.Util.Index)
local BaseStats = require(Shared.Util.BaseStats)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local UnitPortrait = require(script.Parent.UnitPortrait)
local Selection = require(script.Parent.Selection)
local DragController = require(script.Parent.DragController)
local ItemIcon = require(script.Parent.ItemIcon)

local UnitCard = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- One line per ability effect, with the numbers for this star level.
local function effectLines(def: any, star: number): string
	local lines = {}
	for _, effect in def.ability.effects do
		local value = if effect.values then effect.values[math.min(star, #effect.values)] else nil
		local duration = if effect.duration then effect.duration[math.min(star, #effect.duration)] else nil
		local parts = { effect.kind }
		if effect.damageType then
			table.insert(parts, effect.damageType)
		end
		if effect.status then
			table.insert(parts, effect.status)
		end
		if value then
			table.insert(parts, tostring(value))
		end
		if duration then
			table.insert(parts, ("for %ss"):format(duration))
		end
		if effect.hits then
			table.insert(parts, ("x%d"):format(effect.hits))
		end
		table.insert(lines, "- " .. table.concat(parts, " "))
	end
	return table.concat(lines, "\n")
end

-- Builds the card into `parent` (hidden until a unit is selected).
function UnitCard.build(parent: Instance): View
	local frame = Components.panel({
		Name = "UnitCard", Size = UDim2.fromOffset(290, 740), Position = UDim2.fromOffset(8, 108), Visible = false, ZIndex = 20,
		BackgroundColor3 = Color3.fromRGB(44, 46, 70), Parent = parent,
	})
	local body = Components.scroll({ Size = UDim2.new(1, -8, 1, -140), Position = UDim2.fromOffset(4, 4), ZIndex = 21, Parent = frame })
	Components.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local itemsRow = Components.create("Frame", { Size = UDim2.new(1, -8, 0, 80), Position = UDim2.new(0, 4, 1, -134), BackgroundTransparency = 1, ZIndex = 21, Parent = frame })
	Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = itemsRow })
	local shownUid: number? = nil -- the unit the card currently shows; Sell acts on it
	local sell = Components.button({
		Size = UDim2.new(0.62, -8, 0, 52), Position = UDim2.new(0, 6, 1, -56), Text = "Sell", TextSize = 24,
		BackgroundColor3 = Color3.fromRGB(150, 58, 66), ZIndex = 22, Parent = frame,
		onTap = function()
			if shownUid then
				local uid = shownUid
				Selection.selectUnit(nil)
				Actions.sellUnit(uid)
			end
		end,
	})
	local close = Components.button({
		Size = UDim2.new(0.38, -8, 0, 52), Position = UDim2.new(0.62, 2, 1, -56), Text = "Close", TextSize = 24, ZIndex = 22, Parent = frame,
		onTap = function()
			Selection.selectUnit(nil)
		end,
	})

	local function line(text: string, size: number, order: number, color: Color3?): TextLabel
		local height = math.ceil(#text / 24) * (size + 4) + 6
		return Components.label({
			Size = UDim2.new(1, -8, 0, math.max(height, size + 8)), Text = text, TextSize = size, TextWrapped = true, LayoutOrder = order,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = color or Theme.colors.text,
			Font = if size <= 18 then Theme.fontBody else Theme.font, Parent = body, ZIndex = 22,
		})
	end

	local function render(snapshot: { [string]: any })
		local unit
		for _, u in snapshot.units do
			if u.u == Selection.unit then
				unit = u
			end
		end
		local def = if unit then Index.unit(unit.d) else nil
		if not unit or not def then
			frame.Visible = false
			shownUid = nil
			if Selection.unit then
				Selection.selectUnit(nil) -- the unit was sold or merged away
			end
			return
		end
		frame.Visible = true
		Components.clear(body, { UIListLayout = true })
		Components.clear(itemsRow, { UIListLayout = true })

		local portrait = Components.create("Frame", { Size = UDim2.new(1, -8, 0, 150), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 22, Parent = body })
		if not UnitPortrait.attach(portrait, def, 22) then
			portrait:Destroy() -- no model yet: the card is just text
		end
		local stats = BaseStats.resolve(def.cost, def.archetype, unit.s)
		local traits = {}
		for _, id in def.traits do
			local trait = Index.trait(id)
			table.insert(traits, if trait then trait.name else id)
		end
		line(("%s  %s"):format(def.name, string.rep("★", unit.s)), 26, 1, Theme.costColor(def.cost))
		line(("Cost %d - %s"):format(def.cost, def.archetype), 18, 2, Theme.colors.textDim)
		line("Traits: " .. table.concat(traits, ", "), 18, 3)
		line(("Health %d   AD %d   AP %d\nArmor %d   MR %d   AS %.2f\nRange %d   Mana %d / %d"):format(
			stats.health, stats.ad, stats.ap, stats.armor, stats.mr, stats.attackSpeed, stats.range, stats.startMana, stats.maxMana), 18, 4)
		line(def.ability.name, 22, 5, Theme.colors.accent)
		line(def.ability.description, 18, 6)
		line(effectLines(def, unit.s), 16, 7, Theme.colors.textDim)

		-- Equipped items: tap one to unequip it, or drag it onto the item panel.
		for _, item in snapshot.items do
			if item.e == unit.u then
				local icon = ItemIcon.tile(itemsRow, item.i, 76)
				DragController.attach(icon, { kind = "equipped", uid = item.u }, function()
					Selection.inspectItem(item.u) -- shows its effects; "Take off" is in the item panel
				end)
			end
		end

		local refund = def.cost * EconomyConfig.sellStarMultiplier ^ (unit.s - 1)
		sell.Text = ("Sell (+%d gold)"):format(refund)
		shownUid = unit.u
	end

	return { frame = frame, render = render }
end

return UnitCard
