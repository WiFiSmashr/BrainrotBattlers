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
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local ArenaLayout = require(Shared.Util.ArenaLayout)

local PLAYBACK_STEP = 0.05
local LINGER_SECONDS = 1.5

local MONSTER_COLOR = Color3.fromRGB(200, 70, 70)
local TOKEN_COLOR = Color3.fromRGB(235, 235, 235)
local AWAY_COLOR = Color3.fromRGB(120, 120, 140)

type Entry = {
	visual: ModelFactory.Visual,
	animator: UnitAnimator.UnitAnimator,
	team: string,
	position: Vector3, -- where its feet are now
	move: { from: Vector3, to: Vector3, start: number, duration: number }?,
}

local CombatPlayback = {}

local combatEvents: RemoteEvent? = nil
local active: { [number]: Folder } = {}

-- Gives the module the CombatEvents remote (created by Main.server).
function CombatPlayback.init(remote: RemoteEvent)
	combatEvents = remote
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
		ArenaBuilder.build(folder, origin)
	end
	return folder :: Folder
end

-- Builds every seated player's plot up front, so the board and bench are in the world from the first
-- Prep, and points each human's replication focus at their own plot (needed with StreamingEnabled
-- because there are no avatars).
function CombatPlayback.preparePlots(match: any)
	for _, userId in match.order do
		local state = match:getPlayer(userId)
		local arena = arenaFolder(userId, ArenaLayout.plotOrigin(state.seat))
		local player = Players:GetPlayerByUserId(userId)
		local floor = arena:FindFirstChild("Floor")
		if player and floor and floor:IsA("BasePart") then
			player.ReplicationFocus = floor
		end
	end
end

-- Removes every plot and fight from the workspace once a match is over, and points the players'
-- replication focus away from them.
function CombatPlayback.clearPlots()
	for userId, folder in active do
		folder:Destroy()
		active[userId] = nil
	end
	local root = workspace:FindFirstChild("Arenas")
	if root then
		root:Destroy()
	end
	for _, player in Players:GetPlayers() do
		player.ReplicationFocus = nil
	end
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

-- Builds a unit visual and animator. Names and bars are drawn by each client from the events.
local function makeUnit(parent: Instance, origin: Vector3, desc: any, team: string): Entry
	local modelId, def = modelIdFor(desc)
	local tint = if desc.token then TOKEN_COLOR elseif def and def.tint then def.tint elseif team == "away" then AWAY_COLOR else MONSTER_COLOR
	local visual = ModelFactory.create(modelId, { tint = tint })
	visual.model.Name = "Unit_" .. desc.id
	local position = ArenaLayout.cellPosition(origin, desc.col, desc.row)
	visual:place(position, frontOf(team, position))
	visual.model.Parent = parent
	local animator = UnitAnimator.new(visual, ModelRegistry.animationsFor(modelId))

	return {
		visual = visual, animator = animator,
		team = team, position = position, move = nil,
	}
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
	local origin = ArenaLayout.plotOrigin(fight.home.seat)
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
	end

	local watchers: { Player } = {}
	for _, state in { fight.home, if fight.kind == "pvp" then fight.away else nil } do
		local player = Players:GetPlayerByUserId(state.userId)
		if player then
			table.insert(watchers, player)
		end
	end
	-- With no avatar and StreamingEnabled, the server only streams what is near a player's replication
	-- focus; point it at this arena so the models and floor reach the people watching.
	local floor = arena:FindFirstChild("Floor")
	for _, player in watchers do
		if floor and floor:IsA("BasePart") then
			player.ReplicationFocus = floor
		end
		task.spawn(pcall, player.RequestStreamAroundAsync, player, origin, 3)
	end
	local function send(batch: { any })
		if combatEvents then
			for _, player in watchers do
				combatEvents:FireClient(player, batch)
			end
		end
	end
	-- The client reads the arena origin to aim its camera and finds the unit models by name.
	send({ { e = "Roster", units = replay.roster, home = homeId, ox = origin.X, oy = origin.Y, oz = origin.Z } })

	-- Applies one event to the models.
	local function apply(ev: any, now: number)
		local entry = entries[ev.unit or ev.target]
		if ev.e == "Summon" then
			teams[ev.unit] = teams[ev.owner]
			entries[ev.unit] = makeUnit(folder, origin, { id = ev.unit, name = ev.name, token = true, col = ev.col, row = ev.row, hp = ev.hp, maxHp = ev.hp }, teams[ev.unit])
		elseif not entry then
			return
		elseif ev.e == "Move" then
			local goal = ArenaLayout.cellPosition(origin, ev.col, ev.row)
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
			entry.animator:hit()
		elseif ev.e == "Death" then
			-- Play the death animation, then remove the unit from the board (never left greyed out).
			entries[ev.unit] = nil
			entry.move = nil
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
