--!strict
-- Plays a finished fight back on anchored placeholder models and streams CombatEvents (GDD 11.8).
-- The sim is already decided; this only displays it. The only Combat module that touches Instances.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Index = require(Shared.Util.Index)
local FightTypes = require(script.Parent.Parent.Match.FightTypes)

local CELL_STUDS = 4
local ARENA_SPACING = 70
local PLAYBACK_STEP = 0.05
local LINGER_SECONDS = 1.5

local MONSTER_COLOR = Color3.fromRGB(200, 70, 70)
local TOKEN_COLOR = Color3.fromRGB(235, 235, 235)
local AWAY_COLOR = Color3.fromRGB(120, 120, 140)

type Entry = { part: Part, label: TextLabel, name: string, maxHp: number }

local CombatPlayback = {}

local combatEvents: RemoteEvent? = nil
local slots: { [number]: number } = {}
local active: { [number]: Folder } = {}

-- Gives the module the CombatEvents remote (created by Main.server).
function CombatPlayback.init(remote: RemoteEvent)
	combatEvents = remote
end

-- World position of an arena cell for a home player's plot.
local function cellPosition(origin: Vector3, col: number, row: number): Vector3
	return origin + Vector3.new((col - 4) * CELL_STUDS, 2.5, (row - 4.5) * CELL_STUDS)
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

-- Builds the placeholder block with a name + health label.
local function makeUnit(parent: Instance, origin: Vector3, desc: any, team: string): Entry
	local part = Instance.new("Part")
	part.Name = "Unit_" .. desc.id
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(3, 4, 3)
	local def = if desc.defId then Index.unit(desc.defId) else nil
	part.Color = if desc.token then TOKEN_COLOR elseif def and def.tint then def.tint elseif team == "away" then AWAY_COLOR else MONSTER_COLOR
	part.Position = cellPosition(origin, desc.col, desc.row)
	part.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 40)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = gui
	return { part = part, label = label, name = desc.name, maxHp = desc.maxHp or desc.hp }
end

local function setHp(entry: Entry, hp: number)
	entry.label.Text = ("%s  %d/%d"):format(entry.name, math.max(0, math.floor(hp)), math.floor(entry.maxHp))
end

-- Starts playback of a fight. Returns immediately; a background task drives the models.
function CombatPlayback.play(fight: FightTypes.Fight, outcome: FightTypes.Outcome)
	local replay = outcome.replay
	if not replay then
		return
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

	local events = replay.events or {}
	task.spawn(function()
		local startedAt = workspace:GetServerTimeNow()
		local i = 1
		while active[homeId] == folder and (i <= #events or workspace:GetServerTimeNow() - startedAt < outcome.seconds) do
			local elapsed = workspace:GetServerTimeNow() - startedAt
			local batch = {}
			while events[i] and events[i].t <= elapsed do
				local ev = events[i]
				local entry = entries[ev.unit or ev.target]
				if ev.e == "Move" and entry then
					entry.part.Position = cellPosition(origin, ev.col, ev.row)
				elseif (ev.e == "Damage" or ev.e == "Heal") and entry then
					setHp(entry, ev.hp)
				elseif ev.e == "Death" and entry then
					entry.part.Transparency = 0.8
					entry.label.Text = entry.name .. " (out)"
				elseif ev.e == "Summon" then
					teams[ev.unit] = teams[ev.owner]
					entries[ev.unit] = makeUnit(folder, origin, { id = ev.unit, name = ev.name, token = true, col = ev.col, row = ev.row, hp = ev.hp, maxHp = ev.hp }, teams[ev.unit])
					setHp(entries[ev.unit], ev.hp)
				end
				table.insert(batch, ev)
				i += 1
			end
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
