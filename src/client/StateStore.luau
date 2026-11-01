--!strict
-- Holds the latest server snapshot and phase (UI-01). UI code reads from here and never mutates
-- gameplay state. TODO(phase 7): panels subscribe to `changed`.

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Signal)

local StateStore = {
	snapshot = nil :: { [string]: any }?,
	phase = { name = "Lobby", roundId = "1-1", endsAt = nil :: number? },
	changed = Signal.new() :: any,
}

-- Replaces the stored snapshot and notifies listeners.
function StateStore.setSnapshot(snapshot: { [string]: any })
	StateStore.snapshot = snapshot
	StateStore.changed:fire()
end

-- Records a phase change; clients compute the timer from endsAt and workspace:GetServerTimeNow().
function StateStore.setPhase(name: string, roundId: string, endsAt: number?)
	StateStore.phase = { name = name, roundId = roundId, endsAt = endsAt }
	StateStore.changed:fire()
end

return StateStore
