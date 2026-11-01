--!strict
-- Shop: 5 slots (name, cost, traits, rarity color) plus Reroll, Buy XP and Lock (GDD 12.2, SHOP-01..07).
-- Tapping a slot buys it. Slots grey out when unaffordable; the server decides everything.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ShopConfig = require(Shared.Config.ShopConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Index = require(Shared.Util.Index)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Actions = require(script.Parent.Actions)
local UnitPortrait = require(script.Parent.UnitPortrait)

local SLOT_WIDTH, SLOT_HEIGHT, GAP = 200, 200, 8
local BUTTON_WIDTH = 150

local ShopPanel = {}

export type View = { frame: Frame, render: (snapshot: { [string]: any }) -> () }

-- Display names of a unit's traits, joined for the slot.
local function traitNames(traitIds: { string }): string
	local names = {}
	for _, id in traitIds do
		local trait = Index.trait(id)
		table.insert(names, if trait then trait.name else id)
	end
	return table.concat(names, " / ")
end

-- Builds the shop into `parent`.
function ShopPanel.build(parent: Instance): View
	local width = BUTTON_WIDTH + 12 + ShopConfig.slots * SLOT_WIDTH + (ShopConfig.slots - 1) * GAP
	local frame = Components.create("Frame", {
		Name = "ShopPanel", Size = UDim2.fromOffset(width, SLOT_HEIGHT), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 722),
		BackgroundTransparency = 1, Parent = parent,
	})

	local reroll = Components.button({ Size = UDim2.fromOffset(BUTTON_WIDTH, 60), Position = UDim2.fromOffset(0, 0), Text = "Reroll (" .. EconomyConfig.rerollCost .. ")", TextSize = 26, onTap = Actions.rerollShop, Parent = frame })
	local buyXp = Components.button({ Size = UDim2.fromOffset(BUTTON_WIDTH, 60), Position = UDim2.fromOffset(0, 70), Text = ("Buy XP (%d)"):format(GameConfig.buyXpCost), TextSize = 26, onTap = Actions.buyXp, Parent = frame })
	local lock = Components.button({ Size = UDim2.fromOffset(BUTTON_WIDTH, 60), Position = UDim2.fromOffset(0, 140), Text = "Lock", TextSize = 26, onTap = Actions.toggleLock, Parent = frame })

	local slotsFrame = Components.create("Frame", {
		Size = UDim2.fromOffset(width - BUTTON_WIDTH - 12, SLOT_HEIGHT), Position = UDim2.fromOffset(BUTTON_WIDTH + 12, 0),
		BackgroundTransparency = 1, Parent = frame,
	})

	local function render(snapshot: { [string]: any })
		local gold = snapshot.gold
		reroll.BackgroundColor3 = if gold >= EconomyConfig.rerollCost then Theme.colors.panelLight else Color3.fromRGB(70, 50, 54)
		buyXp.BackgroundColor3 = if gold >= GameConfig.buyXpCost and snapshot.level < GameConfig.maxLevel then Theme.colors.panelLight else Color3.fromRGB(70, 50, 54)
		lock.Text = if snapshot.shop.locked then "Locked" else "Lock"
		lock.BackgroundColor3 = if snapshot.shop.locked then Theme.colors.accent else Theme.colors.panelLight
		lock.TextColor3 = if snapshot.shop.locked then Color3.new(0, 0, 0) else Theme.colors.text

		-- With a full bench, one owned copy and a second copy in the shop, a tap buys both (D-54).
		local benchCount, starOne = 0, {}
		for _, u in snapshot.units do
			if u.b then
				benchCount += 1
			end
			if u.s == 1 then
				starOne[u.d] = (starOne[u.d] or 0) + 1
			end
		end
		Components.clear(slotsFrame)
		for i = 1, ShopConfig.slots do
			local defId = snapshot.shop.slots[i]
			local position = UDim2.fromOffset((i - 1) * (SLOT_WIDTH + GAP), 0)
			local def = if type(defId) == "string" then Index.unit(defId) else nil
			if not def then
				local empty = Components.panel({ Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT), Position = position, BackgroundColor3 = Color3.fromRGB(30, 30, 44), Parent = slotsFrame })
				Components.label({ Size = UDim2.fromScale(1, 1), Text = "Empty", TextSize = 24, TextColor3 = Theme.colors.textDim, Parent = empty })
			else
				local buysBoth = false
				if benchCount >= GameConfig.benchSlots and starOne[defId] == 1 then
					for other, shown in snapshot.shop.slots do
						buysBoth = buysBoth or (other ~= i and shown == defId)
					end
				end
				local price = if buysBoth then def.cost * 2 else def.cost
				local affordable = gold >= price
				local slot = Components.button({
					Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT), Position = position, Text = "", AutoButtonColor = false,
					BackgroundColor3 = if affordable then (def.tint or Theme.colors.panelLight) else Color3.fromRGB(58, 58, 68),
					onTap = function()
						Actions.buyUnit(i)
					end,
					Parent = slotsFrame, radius = 10,
				})
				UnitPortrait.attach(slot, def, 1)
				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.costColor(def.cost)
				stroke.Thickness = 6
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = slot
				local ink = if affordable then Color3.new(0, 0, 0) else Theme.colors.textDim
				Components.label({ Size = UDim2.new(1, -12, 0, 56), Position = UDim2.fromOffset(6, 8), Text = def.name, TextSize = 26, TextWrapped = true, TextColor3 = ink, Parent = slot })
				Components.label({ Size = UDim2.new(1, -12, 0, 60), Position = UDim2.fromOffset(6, 70), Text = traitNames(def.traits), TextSize = 20, TextWrapped = true, TextColor3 = ink, Font = Theme.fontBody, Parent = slot })
				Components.label({ Size = UDim2.new(1, -12, 0, 34), Position = UDim2.fromOffset(6, 132), Text = def.archetype, TextSize = 18, TextColor3 = ink, Font = Theme.fontBody, Parent = slot })
				Components.label({
					Size = UDim2.new(1, -12, 0, 36), Position = UDim2.new(0, 6, 1, -40), Text = if buysBoth then ("buy both: %d gold"):format(price) else ("%d gold"):format(price), TextSize = if buysBoth then 22 else 28,
					TextColor3 = if affordable then Theme.colors.bg else Theme.colors.bad, TextXAlignment = Enum.TextXAlignment.Right, Parent = slot,
				})
			end
		end
	end

	return { frame = frame, render = render }
end

return ShopPanel
