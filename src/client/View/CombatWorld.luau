--!strict
-- The 3D combat presentation on the client (GDD 11.8, 12.2): it aims the camera at the fight and puts a
-- health bar, mana bar, name and status icons over every unit in the world, with floating damage
-- numbers. The units themselves (models, movement, animations) are driven by the server and replicate;
-- this only displays what CombatEvents say, and never decides anything. Replaces the old 2D arena view.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local StateStore = require(script.Parent.Parent.StateStore)
local CombatCamera = require(script.Parent.CombatCamera)

local WAIT_FOR_MODEL = 3 -- seconds to wait for a unit model to replicate

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
	Physical = Color3.fromRGB(255, 130, 110),
	Magic = Color3.fromRGB(195, 140, 255),
	True = Color3.new(1, 1, 1),
}

type Hud = {
	gui: BillboardGui,
	hp: Components.Bar,
	mana: Components.Bar,
	tags: Frame,
	maxHp: number,
	maxMana: number,
	height: number,
	part: BasePart,
}

local CombatWorld = {}

export type View = {
	handle: (batch: { any }) -> (),
	setActive: (active: boolean) -> (),
	setSuspended: (suspended: boolean) -> (), -- hide the fight view while the player scouts another board (D-84)
}

-- Builds the controller. Nothing is drawn until a fight starts.
function CombatWorld.build(): View
	local huds: { [number]: Hud } = {}
	local teamOf: { [number]: string } = {}
	local latest: { [number]: { hp: number?, mana: number? } } = {} -- last known values, for bars still loading
	local fightToken = 0 -- changes with each fight so late-loading bars from an old one are dropped
	local origin: Vector3? = nil
	local viewerIsHome = true
	local home = 0
	local active = false
	local suspended = false
	local startedAt = 0
	local warnedMissing = false

	-- A small on-screen fight timer, outside the scaled HUD.
	local overlay = Components.create("ScreenGui", {
		Name = "CombatOverlay", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local timer = Components.label({
		Size = UDim2.fromOffset(300, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Text = "", TextSize = 30,
		TextStrokeTransparency = 0.4, Parent = overlay,
	})
	task.spawn(function()
		while true do
			task.wait(0.25)
			if active and startedAt > 0 then
				local elapsed = StateStore.serverNow() - startedAt
				local overtime = elapsed > GameConfig.combatMaxSeconds
				timer.Text = if overtime then "OVERTIME" else ("Fight  %d:%02d"):format(math.floor(elapsed / 60), math.floor(elapsed % 60))
				timer.TextColor3 = if overtime then Theme.colors.bad else Theme.colors.text
			end
		end
	end)

	local function refreshCamera()
		if active and origin and not suspended then
			CombatCamera.enter(origin, viewerIsHome)
		end
	end

	local function clearHuds()
		for _, hud in huds do
			hud.gui:Destroy()
		end
		table.clear(huds)
	end

	-- Finds a unit model the server has replicated into the current fight. If it never shows up, say
	-- exactly which step is missing; with StreamingEnabled and no avatar, the arena may never stream in.
	local function findModel(unitId: number): Model?
		local arenas = workspace:WaitForChild("Arenas", WAIT_FOR_MODEL)
		local arena = if arenas then arenas:WaitForChild("Arena_" .. home, WAIT_FOR_MODEL) else nil
		local fight = if arena then arena:WaitForChild("Fight", WAIT_FOR_MODEL) else nil
		local model = if fight then fight:WaitForChild("Unit_" .. unitId, WAIT_FOR_MODEL) else nil
		if not model and not warnedMissing then
			warnedMissing = true
			warn(("[CombatWorld] unit %d not found: Arenas=%s Arena=%s Fight=%s (workspace.StreamingEnabled=%s)"):format(
				unitId, tostring(arenas ~= nil), tostring(arena ~= nil), tostring(fight ~= nil), tostring(workspace.StreamingEnabled)))
		end
		return model :: Model?
	end

	-- Floating number over a unit, drifting up and fading.
	local function floatText(hud: Hud, text: string, color: Color3, size: number)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(110, 30)
		gui.AlwaysOnTop = true
		gui.Adornee = hud.part
		local jitter = (math.random() - 0.5) * 1.5
		gui.StudsOffsetWorldSpace = Vector3.new(jitter, hud.height + 1.4, 0)
		gui.Parent = hud.part
		local label = Components.label({ Size = UDim2.fromScale(1, 1), Text = text, TextSize = size, TextColor3 = color, TextStrokeTransparency = 0.25, Parent = gui })
		TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(jitter, hud.height + 3.6, 0) }):Play()
		TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(gui, 1)
	end

	-- Creates the bars over a unit as soon as its model has arrived.
	local function addUnit(desc: any)
		local token = fightToken
		local id = desc.id
		task.spawn(function()
			local model = findModel(id)
			if not model or token ~= fightToken then
				return
			end
			local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if not part then
				return
			end
			local mine = (desc.team == "home") == viewerIsHome
			local height = model:GetExtentsSize().Y
			local gui = Instance.new("BillboardGui")
			gui.Name = "UnitHud"
			gui.Size = UDim2.fromOffset(132, 74)
			gui.StudsOffsetWorldSpace = Vector3.new(0, height + 0.9, 0)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.Adornee = part
			Components.label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 12), Text = desc.name, TextSize = 14, TextStrokeTransparency = 0.3, Parent = gui })
			local hp = Components.bar({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 29), fillColor = if mine then Theme.colors.good else Theme.colors.bad, Parent = gui })
			local mana = Components.bar({ Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 42), fillColor = Theme.colors.mana, Parent = gui })
			local tags = Components.create("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Parent = gui })
			Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = tags })
			-- The items a unit carries stay on show for the whole fight (D-83).
			if desc.items and #desc.items > 0 then
				local row = Components.create("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, Parent = gui })
				Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = row })
				for _, itemId in desc.items do
					ItemIcon.mini(row, itemId)
				end
			end
			gui.Enabled = not suspended
			gui.Parent = part
			local hud: Hud = {
				gui = gui, hp = hp, mana = mana, tags = tags, maxHp = math.max(desc.maxHp or desc.hp or 1, 1), maxMana = math.max(desc.maxMana or 100, 1),
				height = height, part = part,
			}
			local last = latest[id] or {}
			hp.set((last.hp or desc.hp or hud.maxHp) / hud.maxHp)
			mana.set((last.mana or desc.mana or 0) / hud.maxMana)
			huds[id] = hud
		end)
	end

	local function remember(id: number, hp: number?, mana: number?)
		local entry = latest[id] or {}
		entry.hp = hp or entry.hp
		entry.mana = mana or entry.mana
		latest[id] = entry
	end

	local function apply(ev: any)
		if ev.e == "Roster" then
			clearHuds()
			table.clear(teamOf)
			table.clear(latest)
			fightToken += 1
			warnedMissing = false
			home = ev.home
			viewerIsHome = ev.home == StateStore.userId
			origin = Vector3.new(ev.ox, ev.oy, ev.oz)
			startedAt = StateStore.serverNow()
			for _, desc in ev.units do
				teamOf[desc.id] = desc.team
				addUnit(desc)
			end
			refreshCamera()
			return
		end
		if ev.e == "Summon" then
			teamOf[ev.unit] = teamOf[ev.owner] or "home"
			addUnit({ id = ev.unit, team = teamOf[ev.unit], name = ev.name, hp = ev.hp, maxHp = ev.hp })
			return
		end
		local id = ev.unit or ev.target
		if ev.e == "Damage" or ev.e == "Heal" then
			remember(id, ev.hp, ev.mana)
		elseif ev.e == "Attack" or ev.e == "Cast" then
			remember(id, nil, ev.mana)
		end
		local hud = huds[id]
		if not hud then
			return
		end
		if ev.e == "Attack" or ev.e == "Cast" then
			hud.mana.set((ev.mana or 0) / hud.maxMana)
		elseif ev.e == "Damage" then
			hud.hp.set(ev.hp / hud.maxHp)
			hud.mana.set((ev.mana or 0) / hud.maxMana)
			floatText(hud, tostring(math.floor(ev.amount)), if ev.crit then Theme.colors.accent else (DAMAGE_COLORS[ev.dtype] or Color3.new(1, 1, 1)), if ev.crit then 26 else 19)
		elseif ev.e == "Heal" then
			hud.hp.set(ev.hp / hud.maxHp)
			floatText(hud, "+" .. math.floor(ev.amount), Theme.colors.good, 19)
		elseif ev.e == "Shield" then
			floatText(hud, "+" .. math.floor(ev.amount), Theme.colors.shield, 17)
		elseif ev.e == "Status" then
			local tag = STATUS_TAGS[ev.status]
			if tag then
				local icon = Components.label({
					Size = UDim2.fromOffset(22, 12), Text = tag.text, TextSize = 10, TextColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0,
					BackgroundColor3 = tag.color, Name = ev.status, Parent = hud.tags,
				})
				task.delay(math.max(ev.duration or 1, 0.3), function()
					icon:Destroy()
				end)
			end
		elseif ev.e == "Death" then
			huds[id] = nil
			hud.gui:Destroy() -- the model plays its death animation and then disappears
		end
	end

	return {
		handle = function(batch: { any })
			for _, ev in batch do
				apply(ev)
			end
		end,
		setSuspended = function(on: boolean)
			if on == suspended then
				return
			end
			suspended = on
			overlay.Enabled = active and not on
			for _, hud in huds do
				hud.gui.Enabled = not on
			end
			if not on then
				refreshCamera() -- back to the fight
			end
		end,
		setActive = function(on: boolean)
			if on == active then
				return
			end
			active = on
			overlay.Enabled = on and not suspended
			if on then
				refreshCamera()
			else
				clearHuds()
				origin = nil
			end
		end,
	}
end

return CombatWorld
