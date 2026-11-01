--!strict
-- Combat overlay: a 2D view of the fight with health and mana bars over every unit, damage numbers,
-- status icons and a fight timer (GDD 12.2, 11.8). It only displays CombatEvents batches; it never
-- decides anything. The client renders only its own arena, flipped 180 degrees when the player is
-- the away team so their own units are always at the bottom (CMB-02, PAIR-03).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Index = require(Shared.Util.Index)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local StateStore = require(script.Parent.Parent.StateStore)

local CELL, GAP = 58, 3
local COLUMNS, ROWS = CombatConfig.arenaColumns, CombatConfig.arenaRows

-- Status name -> short tag and color for the little icons over a unit.
local STATUS_TAGS: { [string]: { text: string, color: Color3 } } = {
	Stun = { text = "ST", color = Color3.fromRGB(255, 220, 80) },
	Freeze = { text = "FZ", color = Color3.fromRGB(140, 220, 255) },
	Silence = { text = "SI", color = Color3.fromRGB(190, 190, 200) },
	Charm = { text = "CH", color = Color3.fromRGB(255, 130, 200) },
	Taunt = { text = "TA", color = Color3.fromRGB(255, 130, 70) },
	Slow = { text = "SL", color = Color3.fromRGB(120, 160, 255) },
	Wound = { text = "WD", color = Color3.fromRGB(220, 80, 80) },
}

local DAMAGE_COLORS: { [string]: Color3 } = {
	Physical = Color3.fromRGB(255, 120, 100),
	Magic = Color3.fromRGB(190, 130, 255),
	True = Color3.new(1, 1, 1),
}

type Widget = {
	frame: Frame, hp: Components.Bar, mana: Components.Bar, tags: Frame, team: string, maxHp: number, maxMana: number, alive: boolean,
}

local CombatView = {}

export type View = {
	frame: Frame,
	show: () -> (),
	hide: () -> (),
	handle: (batch: { any }) -> (),
}

-- Builds the view into `parent` (hidden until the Combat phase).
function CombatView.build(parent: Instance): View
	local width = COLUMNS * (CELL + GAP)
	local height = ROWS * (CELL + GAP)
	local frame = Components.create("Frame", {
		Name = "CombatView", Size = UDim2.fromOffset(width, height + 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104),
		BackgroundTransparency = 1, Visible = false, ZIndex = 10, Parent = parent,
	})
	local header = Components.label({ Size = UDim2.new(1, 0, 0, 44), Text = "Combat", TextSize = 34, Parent = frame })
	local arena = Components.panel({
		Size = UDim2.fromOffset(width, height), Position = UDim2.fromOffset(0, 50), BackgroundColor3 = Color3.fromRGB(28, 30, 44), radius = 10, Parent = frame,
	})
	arena.ClipsDescendants = false
	-- A faint line between the two halves.
	Components.create("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromOffset(0, height / 2 - 1), BackgroundColor3 = Theme.colors.panelLight, BorderSizePixel = 0, Parent = arena })

	local widgets: { [number]: Widget } = {}
	local flip = false
	local startedAt = 0
	local running = false

	-- Arena cell -> pixel position, flipped for the away team.
	local function placeAt(col: number, row: number): UDim2
		if flip then
			col, row = COLUMNS + 1 - col, ROWS + 1 - row
		end
		return UDim2.fromOffset((col - 1) * (CELL + GAP) + GAP, (ROWS - row) * (CELL + GAP) + GAP)
	end

	local function floatText(widget: Widget, text: string, color: Color3, size: number)
		local label = Components.label({
			Size = UDim2.fromOffset(CELL + 30, 24), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Text = text, TextSize = size,
			TextColor3 = color, TextStrokeTransparency = 0.2, ZIndex = 30, Parent = widget.frame,
		})
		TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, -44), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.85, function()
			label:Destroy()
		end)
	end

	local function setHp(widget: Widget, hp: number)
		widget.hp.set(hp / widget.maxHp)
	end

	local function addUnit(desc: any)
		local def = if desc.defId then Index.unit(desc.defId) else nil
		local mine = (desc.team == "home") ~= flip
		local unitFrame = Components.panel({
			Size = UDim2.fromOffset(CELL - 4, CELL - 4), Position = placeAt(desc.col, desc.row), ZIndex = 11, Parent = arena, radius = 8,
			BackgroundColor3 = if desc.token then Color3.fromRGB(215, 215, 220) elseif def and def.tint then def.tint else (if mine then Color3.fromRGB(110, 130, 190) else Color3.fromRGB(190, 100, 100)),
			stroke = if mine then Theme.colors.good else Theme.colors.bad,
		})
		Components.label({
			Size = UDim2.new(1, -2, 0, 24), Position = UDim2.fromOffset(1, 8), Text = desc.name, TextSize = 13, TextWrapped = true,
			TextColor3 = Color3.new(0, 0, 0), ZIndex = 12, Parent = unitFrame,
		})
		local hp = Components.bar({ Size = UDim2.new(1, -4, 0, 9), Position = UDim2.new(0, 2, 1, -23), fillColor = if mine then Theme.colors.good else Theme.colors.bad, ZIndex = 12, Parent = unitFrame })
		local mana = Components.bar({ Size = UDim2.new(1, -4, 0, 6), Position = UDim2.new(0, 2, 1, -12), fillColor = Theme.colors.mana, ZIndex = 12, Parent = unitFrame })
		local tags = Components.create("Frame", { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, -14), BackgroundTransparency = 1, ZIndex = 13, Parent = unitFrame })
		Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 1), Parent = tags })
		local widget: Widget = {
			frame = unitFrame, hp = hp, mana = mana, tags = tags, team = desc.team, maxHp = math.max(desc.maxHp or desc.hp, 1),
			maxMana = desc.maxMana or 100, alive = true,
		}
		setHp(widget, desc.hp)
		mana.set((desc.mana or 0) / widget.maxMana)
		widgets[desc.id] = widget
	end

	local function setMana(widget: Widget, mana: number?)
		if mana then
			widget.mana.set(mana / widget.maxMana)
		end
	end

	local function apply(ev: any)
		if ev.e == "Roster" then
			Components.clear(arena, { UICorner = true, UIStroke = true })
			Components.create("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromOffset(0, height / 2 - 1), BackgroundColor3 = Theme.colors.panelLight, BorderSizePixel = 0, Parent = arena })
			table.clear(widgets)
			flip = ev.home ~= StateStore.userId
			startedAt = StateStore.serverNow()
			running = true
			for _, desc in ev.units do
				addUnit(desc)
			end
			return
		end
		local widget = widgets[ev.unit or ev.target]
		if ev.e == "Summon" then
			local owner = widgets[ev.owner]
			addUnit({ id = ev.unit, team = if owner then owner.team else "home", name = ev.name, token = true, col = ev.col, row = ev.row, hp = ev.hp, maxHp = ev.hp })
		elseif not widget then
			return
		elseif ev.e == "Move" then
			local goal = placeAt(ev.col, ev.row)
			if ev.over and ev.over > 0 then
				TweenService:Create(widget.frame, TweenInfo.new(ev.over, Enum.EasingStyle.Linear), { Position = goal }):Play()
			else
				widget.frame.Position = goal
			end
		elseif ev.e == "Attack" then
			setMana(widget, ev.mana)
		elseif ev.e == "Cast" then
			setMana(widget, ev.mana)
			floatText(widget, "✦", Theme.colors.accent, 22)
		elseif ev.e == "Damage" then
			setHp(widget, ev.hp)
			setMana(widget, ev.mana)
			floatText(widget, tostring(math.floor(ev.amount)), if ev.crit then Theme.colors.accent else (DAMAGE_COLORS[ev.dtype] or Color3.new(1, 1, 1)), if ev.crit then 24 else 18)
		elseif ev.e == "Heal" then
			setHp(widget, ev.hp)
			floatText(widget, "+" .. math.floor(ev.amount), Theme.colors.good, 18)
		elseif ev.e == "Shield" then
			floatText(widget, "+" .. math.floor(ev.amount), Theme.colors.shield, 16)
		elseif ev.e == "Status" then
			local tag = STATUS_TAGS[ev.status]
			if tag then
				local icon = Components.label({ Size = UDim2.fromOffset(20, 14), Text = tag.text, TextSize = 11, TextColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BackgroundColor3 = tag.color, Name = ev.status, ZIndex = 14, Parent = widget.tags })
				task.delay(math.max(ev.duration or 1, 0.3), function()
					icon:Destroy()
				end)
			end
		elseif ev.e == "Death" then
			widget.alive = false
			setHp(widget, 0)
			widget.frame.BackgroundTransparency = 0.7
		end
	end

	-- Fight timer, from the moment the roster arrived.
	RunService.Heartbeat:Connect(function()
		if frame.Visible and running then
			local elapsed = StateStore.serverNow() - startedAt
			header.Text = if elapsed > GameConfig.combatMaxSeconds then "OVERTIME" else ("Fight  %d:%02d"):format(math.floor(elapsed / 60), math.floor(elapsed % 60))
			header.TextColor3 = if elapsed > GameConfig.combatMaxSeconds then Theme.colors.bad else Theme.colors.text
		end
	end)

	return {
		frame = frame,
		show = function()
			frame.Visible = true
		end,
		hide = function()
			frame.Visible = false
			running = false
		end,
		handle = function(batch: { any })
			for _, ev in batch do
				apply(ev)
			end
		end,
	}
end

return CombatView
