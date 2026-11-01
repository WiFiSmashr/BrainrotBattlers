--!strict
-- Client entry point: feeds the StateStore from the Remotes and mounts the interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateStore = require(script.Parent.StateStore)
local Actions = require(script.Parent.UI.Actions)
local Root = require(script.Parent.UI.Root)

print("[Brainrot Battlers] client booted")

local remotes = ReplicatedStorage:WaitForChild("BattlersNet")
local stateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local phaseChanged = remotes:WaitForChild("PhaseChanged") :: RemoteEvent
local combatEvents = remotes:WaitForChild("CombatEvents") :: RemoteEvent
local toast = remotes:WaitForChild("Toast") :: RemoteEvent
local menu = remotes:WaitForChild("Menu") :: RemoteEvent

Actions.init(remotes:WaitForChild("Action") :: RemoteFunction)

menu.OnClientEvent:Connect(function(info)
	StateStore.setMenu(info)
end)

stateUpdate.OnClientEvent:Connect(function(snapshot)
	StateStore.setSnapshot(snapshot)
end)

phaseChanged.OnClientEvent:Connect(function(phase, roundId, endsAt)
	StateStore.setPhase(phase, roundId, endsAt)
end)

combatEvents.OnClientEvent:Connect(function(batch)
	StateStore.combat:fire(batch)
end)

toast.OnClientEvent:Connect(function(reason)
	StateStore.toast:fire(reason)
end)

Root.build()
