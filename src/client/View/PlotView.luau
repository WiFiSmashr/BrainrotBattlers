--!strict
-- Your units in the 3D world: the board and the bench stand on your plot as models, you tap or drag
-- them directly, and PvE monsters are previewed on the far half (D-67, D-68). It renders from the
-- snapshot like every panel and sends intents through Actions; the server decides everything (UI-01).
-- Models here are local to this client. Fights are played by server-made models (CombatPlayback), so
-- the board is hidden during Combat and the bench follows the camera to whichever plot is on screen.
--
--   tap a unit            select it and open its card; tap it again to deselect
--   tap a tile or slot    move the selected unit there; tap another unit to swap with it
--   tap a unit with an item selected    equip the item
--   drag a unit           onto a tile or slot to move it, onto another unit to swap, onto the shop to sell
--   drag an item (HUD)    onto a unit to equip it

local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Index = require(Shared.Util.Index)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ArenaLayout = require(Shared.Util.ArenaLayout)
local ModelFactory = require(Shared.Visual.ModelFactory)
local UnitAnimator = require(Shared.Visual.UnitAnimator)
local Signal = require(Shared.Util.Signal)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local Actions = require(script.Parent.Parent.UI.Actions)
local Selection = require(script.Parent.Parent.UI.Selection)
local DragController = require(script.Parent.Parent.UI.DragController)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local StateStore = require(script.Parent.Parent.StateStore)
local CombatCamera = require(script.Parent.CombatCamera)

local DRAG_THRESHOLD = 12 -- pixels before a press becomes a drag
local HITBOX = Vector3.new(3.4, 5, 3.4)
local RESOLVE_HIDE_SECONDS = 1.7 -- the fight's own models linger this long after Combat ends
local LIFT = 1.4 -- studs a dragged unit floats above the ground

type Slot = { kind: "board", col: number, row: number } | { kind: "bench", index: number }

local PlotView = {}

export type View = {
	render: (snapshot: { [string]: any }) -> (),
	dragging: () -> boolean,
	dragFinished: any, -- fired when a unit in the world is released
}

-- Builds the view. Everything it creates lives in one folder in the workspace (client only).
function PlotView.build(): View
	local folder = Instance.new("Folder")
	folder.Name = "PlotView"
	folder.Parent = workspace
	local hitboxes = Instance.new("Folder")
	hitboxes.Name = "Hitboxes"
	hitboxes.Parent = folder
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.78
	highlight.OutlineColor = Theme.colors.accent
	highlight.Parent = folder

	local entries: { [number]: any } = {} -- unit uid -> entry
	local monsters: { any } = {}
	local latest: { [string]: any }? = nil
	local pressed: any = nil -- a press on a unit or tile that may still become a tap or a drag
	local dragEntry: any = nil
	local dragFinished = Signal.new()
	local view = { origin = nil :: Vector3?, homeSide = true, atOwnPlot = false }

	-- Where a unit's slot is, for swaps and moves.
	local function slotOf(unit: { [string]: any }): Slot
		if unit.b then
			return { kind = "bench", index = unit.b }
		end
		return { kind = "board", col = unit.c, row = unit.r }
	end

	local function sendMove(uid: number, slot: Slot)
		if slot.kind == "bench" then
			Actions.moveToBench(uid, slot.index)
		else
			Actions.moveToBoard(uid, slot.col, slot.row)
		end
	end

	-- The arena folder of the plot on screen, found from its position (plots are laid out by seat).
	local function arenaFolder(): Instance?
		local snapshot = latest
		if not snapshot or not view.origin then
			return nil
		end
		local seat = ArenaLayout.seatAt(view.origin)
		local owner = snapshot.players[seat]
		local arenas = workspace:FindFirstChild("Arenas")
		return if owner and arenas then arenas:FindFirstChild("Arena_" .. owner.id) else nil
	end

	-- Casts a ray from the camera through a screen position at units and tiles.
	local function castAt(position: Vector2): RaycastResult?
		local camera = workspace.CurrentCamera
		local arena = arenaFolder()
		if not camera or not arena then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local include = { hitboxes }
		for _, name in { "Tiles", "Bench" } do
			local child = arena:FindFirstChild(name)
			if child then
				table.insert(include, child)
			end
		end
		params.FilterDescendantsInstances = include
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		return workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	end

	-- What a ray hit is: a unit (uid), a board tile or one of your bench slots.
	local function classify(hit: RaycastResult?): (number?, Slot?)
		if not hit then
			return nil, nil
		end
		local uid = hit.Instance:GetAttribute("Uid")
		if uid then
			return uid, nil
		end
		local colText, rowText = hit.Instance.Name:match("^Tile_(%d+)_(%d+)$")
		if colText and rowText and view.atOwnPlot and view.homeSide then
			local col, row = tonumber(colText) or 0, tonumber(rowText) or 0
			if row <= 4 then
				return nil, { kind = "board", col = col, row = row }
			end
			StateStore.toast:fire("OutOfBounds") -- the far half is the enemy's
			return nil, nil
		end
		local side, indexText = hit.Instance.Name:match("^Bench_(%a+)_(%d+)$")
		if side and indexText and (side == "Home") == view.homeSide then
			return nil, { kind = "bench", index = tonumber(indexText) or 1 }
		end
		return nil, nil
	end

	local function unitByUid(uid: number): { [string]: any }?
		for _, unit in (latest :: any).units do
			if unit.u == uid then
				return unit
			end
		end
		return nil
	end

	-- Tap on a unit: equip a selected item, swap with the selected unit, or select / deselect.
	local function tapUnit(uid: number)
		local unit = unitByUid(uid)
		if not unit then
			return
		end
		if #Selection.items > 0 then
			Actions.equipItem(Selection.items[1], uid)
			Selection.clearItems()
		elseif Selection.unit and Selection.unit ~= uid then
			sendMove(Selection.unit, slotOf(unit))
			Selection.selectUnit(nil)
		elseif Selection.unit == uid then
			Selection.selectUnit(nil)
		else
			Selection.selectUnit(uid)
		end
	end

	local function tapSlot(slot: Slot)
		if Selection.unit then
			sendMove(Selection.unit, slot)
			Selection.selectUnit(nil)
		end
	end

	-- A unit model with its hitbox and the stars / items label above it.
	local function createEntry(unit: { [string]: any }, position: Vector3, homeSide: boolean): any
		local def = Index.unit(unit.d) :: any
		local modelId = ModelRegistry.modelIdOf(def)
		local visual = ModelFactory.create(modelId, { tint = def.tint })
		visual.model.Name = "PlotUnit_" .. unit.u
		visual.model.Parent = folder
		local forward = Vector3.new(0, 0, if homeSide then 10 else -10)
		visual:place(position, position + forward)
		local animator = UnitAnimator.new(visual, ModelRegistry.animationsFor(modelId))

		local hitbox = Instance.new("Part")
		hitbox.Name = "Hit_" .. unit.u
		hitbox.Anchored, hitbox.CanCollide, hitbox.CanQuery, hitbox.CanTouch = true, false, true, false
		hitbox.Transparency = 1
		hitbox.Size = HITBOX
		hitbox.Position = position + Vector3.new(0, HITBOX.Y / 2, 0)
		hitbox:SetAttribute("Uid", unit.u)
		hitbox.Parent = hitboxes

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(110, 40)
		gui.StudsOffsetWorldSpace = Vector3.new(0, visual.height + 0.8, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = visual.primary
		gui.Parent = visual.primary
		return { visual = visual, animator = animator, hitbox = hitbox, gui = gui, position = position, signature = "", forward = forward }
	end

	local function destroyEntry(entry: any)
		entry.animator:destroy()
		entry.visual:destroy()
		if entry.hitbox then
			entry.hitbox:Destroy()
		end
	end

	-- Stars and equipped items over a unit.
	local function paintLabel(entry: any, unit: { [string]: any }, items: { any })
		Components.clear(entry.gui)
		local stars = Components.label({
			Size = UDim2.new(1, 0, 0, 20), Text = string.rep("★", unit.s), TextSize = 20, TextColor3 = Theme.colors.accent,
			TextStrokeTransparency = 0.3, Parent = entry.gui,
		})
		stars.Name = "Stars"
		local row = Components.create("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 20), BackgroundTransparency = 1, Parent = entry.gui })
		Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 2), Parent = row })
		for _, item in items do
			if item.e == unit.u then
				ItemIcon.mini(row, item.i)
			end
		end
	end

	local function moveEntry(entry: any, position: Vector3)
		entry.position = position
		entry.visual:place(position, position + entry.forward)
		entry.hitbox.Position = position + Vector3.new(0, HITBOX.Y / 2, 0)
	end

	-- Brings the world in line with the snapshot: add, move, restyle and remove only what changed.
	local function render(snapshot: { [string]: any })
		latest = snapshot
		local origin, homeSide = CombatCamera.view()
		view.origin, view.homeSide = origin, homeSide
		if not origin then
			for uid, entry in entries do
				destroyEntry(entry)
				entries[uid] = nil
			end
			return
		end
		view.atOwnPlot = origin == ArenaLayout.plotOrigin(snapshot.seat) and homeSide
		if dragEntry then
			return -- never rebuild under a unit that is being dragged
		end

		local phase = StateStore.phase
		local boardVisible = view.atOwnPlot and phase.name ~= "Combat"
			and not (phase.name == "Resolve" and StateStore.serverNow() - phase.receivedAt < RESOLVE_HIDE_SECONDS)

		local wanted: { [number]: { unit: any, position: Vector3 } } = {}
		for _, unit in snapshot.units do
			if unit.b then
				wanted[unit.u] = { unit = unit, position = ArenaLayout.benchPosition(origin, unit.b, homeSide) }
			elseif boardVisible then
				wanted[unit.u] = { unit = unit, position = ArenaLayout.cellPosition(origin, unit.c, unit.r) }
			end
		end

		for uid, entry in entries do
			local want = wanted[uid]
			if not want or want.unit.d ~= entry.defId then
				destroyEntry(entry)
				entries[uid] = nil
			end
		end
		for uid, want in wanted do
			local entry = entries[uid]
			if not entry then
				entry = createEntry(want.unit, want.position, homeSide)
				entry.defId = want.unit.d
				entries[uid] = entry
			elseif (entry.position - want.position).Magnitude > 0.01 then
				moveEntry(entry, want.position)
			end
			local parts = { want.unit.d, want.unit.s }
			for _, item in snapshot.items do
				if item.e == uid then
					table.insert(parts, item.i)
				end
			end
			local signature = table.concat(parts, "|")
			if entry.signature ~= signature then
				entry.signature = signature
				paintLabel(entry, want.unit, snapshot.items)
			end
		end

		local selected = if Selection.unit then entries[Selection.unit] else nil
		highlight.Adornee = if selected then selected.visual.model else nil

		-- PvE monsters on the far half during Prep (their count comes from the server's formula).
		local count = if snapshot.monsters and boardVisible and phase.name == "Prep" then snapshot.monsters else 0
		if #monsters ~= count then
			for _, entry in monsters do
				destroyEntry(entry)
			end
			table.clear(monsters)
			for i = 1, count do
				local cell = ArenaLayout.monsterArenaCell(i)
				local position = ArenaLayout.cellPosition(origin, cell.col, cell.row)

				local visual = ModelFactory.create("monster", { tint = Color3.fromRGB(200, 70, 70) })
				visual.model.Name = "PlotMonster_" .. i
				visual.model.Parent = folder
				visual:place(position, position + Vector3.new(0, 0, -10)) -- facing your side
				table.insert(monsters, {
					visual = visual, animator = UnitAnimator.new(visual, ModelRegistry.animationsFor("monster")),

				})
			end
		end
	end

	-- Turns a screen position into a point on the ground under it.
	local function groundAt(position: Vector2): Vector3?
		local camera = workspace.CurrentCamera
		if not camera or not view.origin then
			return nil
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local t = (ArenaLayout.groundY - ray.Origin.Y) / ray.Direction.Y
		return if t > 0 then ray.Origin + ray.Direction * t else nil
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or pressed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		local uid, slot = classify(castAt(at))
		pressed = { input = input, start = at, uid = uid, slot = slot, dragging = false }
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local press = pressed
		if not press then
			return
		end
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		if not isMouse and input ~= press.input then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if not press.dragging then
			if not press.uid or (at - press.start).Magnitude < DRAG_THRESHOLD then
				return
			end
			local entry = entries[press.uid]
			if not entry then
				return
			end
			press.dragging, dragEntry = true, entry
			entry.hitbox.CanQuery = false -- so the ray under the pointer reaches the tile below
			Selection.selectUnit(nil)
		end
		local ground = groundAt(at)
		if ground and dragEntry then
			dragEntry.visual:place(ground + Vector3.new(0, LIFT, 0), ground + dragEntry.forward)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local press = pressed
		if not press or input.UserInputType ~= press.input.UserInputType then
			return
		end
		pressed = nil
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if press.dragging and dragEntry then
			local entry = dragEntry
			dragEntry = nil
			entry.hitbox.CanQuery = true
			-- Over the shop: sell. Otherwise a tile, a slot or another unit.
			local payload = { kind = "unit", uid = press.uid }
			if not DragController.dropAt(at, payload) then
				local targetUid, slot = classify(castAt(at))
				if targetUid and targetUid ~= press.uid then
					local target = unitByUid(targetUid)
					if target then
						sendMove(press.uid, slotOf(target))
					end
				elseif slot then
					sendMove(press.uid, slot)
				end
			end
			moveEntry(entry, entry.position) -- snap back; the next snapshot moves it if the server agreed
			dragFinished:fire()
		elseif press.uid then
			tapUnit(press.uid)
		elseif press.slot then
			tapSlot(press.slot)
		elseif Selection.unit then
			Selection.selectUnit(nil) -- a tap on empty ground deselects
		end
	end)

	-- Items dragged from the HUD are dropped onto a unit in the world.
	DragController.worldDrop = function(payload, position)
		if payload.kind == "item" then
			local uid = classify(castAt(position))
			if uid then
				Actions.equipItem(payload.uid, uid)
				Selection.clearItems()
			end
		end
	end

	Selection.changed:connect(function()
		local selected = if Selection.unit then entries[Selection.unit] else nil
		highlight.Adornee = if selected then selected.visual.model else nil
	end)

	return { render = render, dragging = function()
		return dragEntry ~= nil
	end, dragFinished = dragFinished }
end

return PlotView
