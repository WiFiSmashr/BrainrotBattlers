--!strict
-- Holds the latest server snapshot and phase (UI-01). UI code reads from here and never mutates
-- gameplay state. Signals carry everything else the server pushes: toasts and combat events.

local Players = game:GetService("Players")
local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Signal)

local StateStore = {
	snapshot = nil :: { [string]: any }?,
	phase = { name = "Lobby", roundId = "1-1", endsAt = nil :: number?, receivedAt = 0 },
	changed = Signal.new() :: any, -- fired after every snapshot or phase change
	toast = Signal.new() :: any, -- reason code
	combat = Signal.new() :: any, -- a batch of combat events
	menu = { status = "Menu", queued = 0, needed = 8, startsAt = nil :: number?, matchRunning = false } :: { [string]: any },
	userId = Players.LocalPlayer.UserId,
}

-- Server time in seconds; clients compute timers from this and `endsAt` (3.5).
function StateStore.serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Seconds left in the current phase, or nil if it has no timer.
function StateStore.timeLeft(): number?
	local endsAt = StateStore.phase.endsAt
	if not endsAt then
		return nil
	end
	return math.max(0, endsAt - StateStore.serverNow())
end

-- Records a phase change from PhaseChanged or from a snapshot.
function StateStore.setPhase(name: string, roundId: string, endsAt: number?)
	local old = StateStore.phase
	if old.name ~= name or old.roundId ~= roundId then
		StateStore.phase = { name = name, roundId = roundId, endsAt = endsAt, receivedAt = StateStore.serverNow() }
	else
		old.endsAt = endsAt
	end
	StateStore.changed:fire()
end

-- Replaces the stored snapshot; the snapshot is authoritative for the phase too, so a client that
-- connects late still shows the right round and timer.
function StateStore.setSnapshot(snapshot: { [string]: any })
	StateStore.snapshot = snapshot
	StateStore.menu.status = "InMatch" -- a snapshot means the server has this player in a match
	local phase = StateStore.phase
	if phase.name ~= snapshot.phase or phase.roundId ~= snapshot.round then
		StateStore.phase = { name = snapshot.phase, roundId = snapshot.round, endsAt = snapshot.endsAt, receivedAt = StateStore.serverNow() }
	else
		phase.endsAt = snapshot.endsAt
	end
	StateStore.changed:fire()
end

-- Records the menu status from the server (Menu, Queued or InMatch). Leaving a match drops its
-- snapshot, so the interface falls back to the menu.
function StateStore.setMenu(info: { [string]: any })
	local wasInMatch = StateStore.menu.status == "InMatch"
	if wasInMatch and info.status ~= "InMatch" then
		StateStore.snapshot = nil
		StateStore.phase = { name = "Lobby", roundId = "1-1", endsAt = nil, receivedAt = StateStore.serverNow() }
	elseif info.status == "InMatch" and StateStore.snapshot == nil then
		-- Nothing to draw until the first snapshot; the heartbeat delivers it within a moment.
	end
	StateStore.menu = info
	StateStore.changed:fire()
end

return StateStore
