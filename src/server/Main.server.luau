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

local remotes = createRemotes()
local match = MatchService.new({
	lobbySize = GameConfig.lobbySize,
	seed = Random.new():NextInteger(1, 2147483646), -- match seed is chosen once, outside the simulation
	combat = function(fight)
		return CombatRunner.simulate(fight, true)
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
CombatPlayback.init(remotes.CombatEvents)
local router = ActionRouter.new(match, now)
local replicator = Replicator.new(match, remotes, now)

remotes.Action.OnServerInvoke = function(player: Player, name: any, args: any)
	return router:handle(player.UserId, name, args)
end

local function onPlayerAdded(player: Player)
	match:addPlayer(player.UserId, player.Name)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	match:removePlayer(player.UserId)
end)

-- Lobby: start when full, or after the wait with enough players (D-17). Then drive the match.
local lobbyOpenedAt = now()
task.spawn(function()
	while true do
		if match.phase == "Lobby" then
			local seated = #match.order
			local waited = now() - lobbyOpenedAt
			if seated >= GameConfig.lobbySize or (seated >= GameConfig.minPlayersToStart and waited >= GameConfig.lobbyWaitSeconds) then
				match:start()
			end
		else
			match:update()
		end
		replicator:flush()
		task.wait(0.1)
	end
end)

print("[Brainrot Battlers] server booted")
