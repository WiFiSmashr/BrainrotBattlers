--!strict
-- Plays a finished fight back in the workspace and streams CombatEvents (GDD 11.8).
-- The sim is already decided; this only displays it. Each unit is a Visual from ModelFactory (its 3D
-- model if it has one, otherwise a coloured block) driven by a UnitAnimator: units walk between
-- cells, face their target, attack, cast, flinch and, when they die, play their death animation and
-- are removed. The only Combat module that touches Instances.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Index = require(Shared.Util.Index)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ModelFactory = require(Shared.Visual.ModelFactory)
local UnitAnimator = require(Shared.Visual.UnitAnimator)
local FightTypes = require(script.Parent.Parent.Match.FightTypes)

local CELL_STUDS = 4
local ARENA_SPACING = 70
local PLAYBACK_STEP = 0.05
local LINGER_SECONDS = 1.5
local LABEL_LIFT = 0.8 -- studs above the head

local MONSTER_COLOR = Color3.fromRGB(200, 70, 70)
local TOKEN_COLOR = Color3.fromRGB(235, 235, 235)
local AWAY_COLOR = Color3.fromRGB(120, 120, 140)

type Entry = {
	visual: ModelFactory.Visual,
	animator: UnitAnimator.UnitAnimator,
	label: TextLabel,
	gui: BillboardGui,
	name: string,
	maxHp: number,
	team: string,
	position: Vector3, -- where its feet are now
	move: { from: Vector3, to: Vector3, start: number, duration: number }?,
}

local CombatPlayback = {}

local combatEvents: RemoteEvent? = nil
local slots: { [number]: number } = {}
local active: { [number]: Folder } = {}

-- Gives the module the CombatEvents remote (created by Main.server).
function CombatPlayback.init(remote: RemoteEvent)
	combatEvents = remote
end

-- World position of the ground at an arena cell for a home player's plot (the floor top is y = 0).
local function cellPosition(origin: Vector3, col: number, row: number): Vector3
	return origin + Vector3.new((col - 4) * CELL_STUDS, 0, (row - 4.5) * CELL_STUDS)
end

-- Arena origin per home player; each player keeps one plot (PAIR-03).
local function originFor(userId: number): Vector3
	if not slots[userId] then
		local n = 0
		for _ in slots do
			n += 1
		end
		slots[userId] = n
	end
	return Vector3.new(slots[userId] * ARENA_SPACING, 0, 0)
end

-- Creates the floor for a plot once and returns the arena folder.
local function arenaFolder(userId: number, origin: Vector3): Folder
	local root = workspace:FindFirstChild("Arenas") or Instance.new("Folder")
	root.Name = "Arenas"
	root.Parent = workspace
	local name = "Arena_" .. userId
	local folder = root:FindFirstChild(name) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		local floor = Instance.new("Part")
		floor.Name = "Floor"
		floor.Anchored = true
		floor.Size = Vector3.new(7 * CELL_STUDS + 4, 1, 8 * CELL_STUDS + 4)
		floor.Position = origin + Vector3.new(0, -0.5, 0)
		floor.Color = Color3.fromRGB(70, 70, 80)
		floor.Parent = folder
	end
	return folder :: Folder
end

-- The model id for a fight participant: the unit's own, or a generic one for monsters and tokens.
local function modelIdFor(desc: any): (string, any)
	local def = if desc.defId then Index.unit(desc.defId) else nil
	if def then
		return ModelRegistry.modelIdOf(def), def
	end
	return if desc.token then "token" else "monster", nil
end

-- Which way a team faces: home toward +Z, away toward -Z (the other side of the arena).
local function frontOf(team: string, position: Vector3): Vector3
	return position + Vector3.new(0, 0, if team == "home" then 10 else -10)
end

-- Builds a unit's visual, animator and name / health label.
local function makeUnit(parent: Instance, origin: Vector3, desc: any, team: string): Entry
	local modelId, def = modelIdFor(desc)
	local tint = if desc.token then TOKEN_COLOR elseif def and def.tint then def.tint elseif team == "away" then AWAY_COLOR else MONSTER_COLOR
	local visual = ModelFactory.create(modelId, { tint = tint })
	visual.model.Name = "Unit_" .. desc.id
	local position = cellPosition(origin, desc.col, desc.row)
	visual:place(position, frontOf(team, position))
	visual.model.Parent = parent
	local animator = UnitAnimator.new(visual, ModelRegistry.animationsFor(modelId))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, visual.height + LABEL_LIFT, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = visual.primary
	gui.Parent = visual.primary
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = gui
	return {
		visual = visual, animator = animator, label = label, gui = gui, name = desc.name, maxHp = desc.maxHp or desc.hp,
		team = team, position = position, move = nil,
	}
end

local function setHp(entry: Entry, hp: number)
	entry.label.Text = ("%s  %d/%d"):format(entry.name, math.max(0, math.floor(hp)), math.floor(entry.maxHp))
end

-- Turns a unit toward a point without moving it.
local function face(entry: Entry, point: Vector3)
	entry.visual:place(entry.position, point)
end

-- Advances every walking unit along its step.
local function updateMoves(entries: { [number]: Entry }, now: number)
	for _, entry in entries do
		local move = entry.move
		if move then
			local alpha = math.clamp((now - move.start) / move.duration, 0, 1)
			entry.position = move.from:Lerp(move.to, alpha)
			entry.visual:place(entry.position, move.to)
			if alpha >= 1 then
				entry.move = nil
				entry.animator:setMoving(false)
			end
		end
	end
end

-- Starts playback of a fight. Returns immediately; a background task drives the models.
function CombatPlayback.play(fight: FightTypes.Fight, outcome: FightTypes.Outcome)
	local replay = outcome.replay
	if not replay then
		return
	end
	local awayPlayer = if fight.kind == "pvp" and fight.away then Players:GetPlayerByUserId(fight.away.userId) else nil
	if not Players:GetPlayerByUserId(fight.home.userId) and not awayPlayer then
		return -- bot-vs-bot fights are simulated but not drawn
	end
	local homeId = fight.home.userId
	local origin = originFor(homeId)
	local arena = arenaFolder(homeId, origin)

	if active[homeId] then
		active[homeId]:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Fight"
	folder.Parent = arena
	active[homeId] = folder

	local entries: { [number]: Entry } = {}
	local teams: { [number]: string } = {}
	for _, desc in replay.roster do
		entries[desc.id] = makeUnit(folder, origin, desc, desc.team)
		teams[desc.id] = desc.team
		setHp(entries[desc.id], desc.hp)
	end

	local watchers: { Player } = {}
	for _, state in { fight.home, if fight.kind == "pvp" then fight.away else nil } do
		local player = Players:GetPlayerByUserId(state.userId)
		if player then
			table.insert(watchers, player)
		end
	end
	local function send(batch: { any })
		if combatEvents then
			for _, player in watchers do
				combatEvents:FireClient(player, batch)
			end
		end
	end
	send({ { e = "Roster", units = replay.roster, home = homeId } })

	-- Applies one event to the models.
	local function apply(ev: any, now: number)
		local entry = entries[ev.unit or ev.target]
		if ev.e == "Summon" then
			teams[ev.unit] = teams[ev.owner]
			entries[ev.unit] = makeUnit(folder, origin, { id = ev.unit, name = ev.name, token = true, col = ev.col, row = ev.row, hp = ev.hp, maxHp = ev.hp }, teams[ev.unit])
			setHp(entries[ev.unit], ev.hp)
		elseif not entry then
			return
		elseif ev.e == "Move" then
			local goal = cellPosition(origin, ev.col, ev.row)
			if ev.over and ev.over > 0 then
				entry.move = { from = entry.position, to = goal, start = now, duration = ev.over }
				entry.animator:setMoving(true)
			else
				entry.move = nil -- a dash or respawn: jump straight there
				entry.position = goal
				entry.visual:place(goal, frontOf(entry.team, goal))
				entry.animator:setMoving(false)
			end
		elseif ev.e == "Attack" then
			local target = entries[ev.target]
			if target then
				face(entry, target.position)
			end
			entry.animator:attack()
		elseif ev.e == "Cast" then
			entry.animator:cast()
		elseif ev.e == "Damage" then
			setHp(entry, ev.hp)
			entry.animator:hit()
		elseif ev.e == "Heal" then
			setHp(entry, ev.hp)
		elseif ev.e == "Death" then
			-- Play the death animation, then remove the unit from the board (never left greyed out).
			entries[ev.unit] = nil
			entry.move = nil
			entry.gui.Enabled = false
			local seconds = entry.animator:die()
			task.delay(seconds + 0.1, function()
				entry.animator:destroy()
				entry.visual:destroy()
			end)
		end
	end

	local events = replay.events or {}
	task.spawn(function()
		local startedAt = workspace:GetServerTimeNow()
		local i = 1
		while active[homeId] == folder and (i <= #events or workspace:GetServerTimeNow() - startedAt < outcome.seconds) do
			local now = workspace:GetServerTimeNow()
			local elapsed = now - startedAt
			local batch = {}
			while events[i] and events[i].t <= elapsed do
				apply(events[i], now)
				table.insert(batch, events[i])
				i += 1
			end
			updateMoves(entries, now)
			if #batch > 0 then
				send(batch)
			end
			task.wait(PLAYBACK_STEP)
		end
		task.wait(LINGER_SECONDS)
		if active[homeId] == folder then
			active[homeId] = nil
		end
		folder:Destroy()
	end)
end

return CombatPlayback
