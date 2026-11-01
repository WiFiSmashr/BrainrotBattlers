--!strict
-- Client entry point: feeds the StateStore from the Remotes. TODO(phase 7): mount the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateStore = require(script.Parent.StateStore)

print("[Brainrot Battlers] client booted")

local remotes = ReplicatedStorage:WaitForChild("BattlersNet")
local stateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local phaseChanged = remotes:WaitForChild("PhaseChanged") :: RemoteEvent
local toast = remotes:WaitForChild("Toast") :: RemoteEvent

stateUpdate.OnClientEvent:Connect(function(snapshot)
	StateStore.setSnapshot(snapshot)
end)

phaseChanged.OnClientEvent:Connect(function(phase, roundId, endsAt)
	StateStore.setPhase(phase, roundId, endsAt)
	print(("[Brainrot Battlers] %s %s"):format(roundId, phase))
end)

toast.OnClientEvent:Connect(function(reason)
	warn("[Brainrot Battlers] " .. tostring(reason)) -- TODO(phase 7): show as an on-screen toast (UI-05)
end)
