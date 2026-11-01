--!strict
-- Server entry point: creates the Remotes, builds the one MatchService, and runs the update loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MatchService = require(script.Parent.Match.MatchService)
local ActionRouter = require(script.Parent.Player.ActionRouter)
local Replicator = require(script.Parent.Player.Replicator)
local CombatRunner = require(script.Parent.Combat.CombatRunner)
local CombatPlayback = require(script.Parent.Combat.CombatPlayback)
local EffectRunner = require(script.Parent.Effects.EffectRunner)
local InventoryService = require(script.Parent.Items.InventoryService)
local BotController = require(script.Parent.Bots.BotController)
local ModelLoader = require(script.Parent.Combat.ModelLoader)
local ArenaBuilder = require(script.Parent.Combat.ArenaBuilder)
local SessionService = require(script.Parent.Match.SessionService)

-- Creates the Remotes folder (GDD 3.5). Clients wait for it by name.
local function createRemotes(): Replicator.Remotes
	local folder = Instance.new("Folder")
	folder.Name = "BattlersNet" -- not "Remotes": avoids clashing with leftover instances in old place files
	local function make(className: string, name: string): any
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	local remotes = {
		Action = make("RemoteFunction", "Action"),
		StateUpdate = make("RemoteEvent", "StateUpdate"),
		PhaseChanged = make("RemoteEvent", "PhaseChanged"),
		CombatEvents = make("RemoteEvent", "CombatEvents"),
		Toast = make("RemoteEvent", "Toast"),
	}
	folder.Parent = ReplicatedStorage
	return remotes
end

local function now(): number
	return workspace:GetServerTimeNow()
end

ModelLoader.load() -- models that name a Roblox asset id are loaded into ReplicatedStorage/UnitModels
ArenaBuilder.setupLighting()
Players.CharacterAutoLoads = false -- the game is played from a fixed camera; no avatars
local remotes = createRemotes()
local menuRemote = Instance.new("RemoteEvent")
menuRemote.Name = "Menu"
menuRemote.Parent = ReplicatedStorage:WaitForChild("BattlersNet")
CombatPlayback.init(remotes.CombatEvents)

local session: any = nil

-- Builds everything one match needs: the service, the router humans and bots act through, the bots and
-- the replicator that sends only to players still in this match.
local function newRun(): SessionService.Run
	local match = MatchService.new({
		lobbySize = GameConfig.lobbySize,
		seed = Random.new():NextInteger(1, 2147483646), -- match seed is chosen once, outside the simulation
		combat = function(fight)
			-- Only fights with a human in them are recorded for playback; bot-vs-bot fights are just simulated.
			return CombatRunner.simulate(fight, fight.home.userId > 0 or (fight.away ~= nil and fight.away.userId > 0))
		end,
		onFight = CombatPlayback.play,
		incomeModifiers = EffectRunner.incomeModifiers,
		onPveDrop = InventoryService.pveDrop,
		onPrepStart = EffectRunner.onPrepStart,
		onUnitBought = EffectRunner.onUnitBought,
		onItemCombined = EffectRunner.onItemCombined,
		onRoundEnd = EffectRunner.onRoundEnd,
		now = now,
	})
	local router = ActionRouter.new(match, now)
	return {
		match = match,
		router = router,
		bots = BotController.new(match, router),
		replicator = Replicator.new(match, remotes, now, function(userId: number)
			return session:isInMatch(userId)
		end),
	}
end

session = SessionService.new({
	lobbySize = GameConfig.lobbySize,
	minPlayers = GameConfig.minPlayersToStart,
	waitSeconds = GameConfig.lobbyWaitSeconds,
	fillWithBots = GameConfig.fillWithBots,
	now = now,
	newRun = newRun,
	fillBots = BotController.fill, -- BOT-01: bots take every empty seat
	onStart = function(run)
		CombatPlayback.preparePlots(run.match) -- every plot, with its bench, exists before the first Prep
	end,
	onCleanup = function()
		CombatPlayback.clearPlots()
	end,
	notify = function(userId, info)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			menuRemote:FireClient(player, info)
		end
	end,
})

remotes.Action.OnServerInvoke = function(player: Player, name: any, args: any)
	if type(name) ~= "string" then
		return { ok = false, reason = "BadArgs" }
	end
	return session:handle(player.UserId, name, args)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		player.Character:Destroy()
	end
	session:addPlayer(player.UserId, player.Name)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	session:removePlayer(player.UserId)
end)

task.spawn(function()
	while true do
		session:update()
		task.wait(0.1)
	end
end)

print("[Brainrot Battlers] server booted")
