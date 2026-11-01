--!strict
-- Adapter between the match and the client Remotes. The only server module that fires Remotes.
-- Snapshots are sent only when state changed, at most 10 per second per player (ARCH-07).

local Players = game:GetService("Players")
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Snapshot = require(script.Parent.Snapshot)

export type Remotes = {
	Action: RemoteFunction,
	StateUpdate: RemoteEvent,
	PhaseChanged: RemoteEvent,
	CombatEvents: RemoteEvent,
	Toast: RemoteEvent,
}

local Replicator = {}
Replicator.__index = Replicator

-- Wires match events to the Remotes. `now` is the server clock in seconds.
function Replicator.new(match: any, remotes: Remotes, now: () -> number): any
	local self = setmetatable({
		match = match,
		remotes = remotes,
		now = now,
		dirty = {} :: { [number]: boolean },
		lastSent = {} :: { [number]: number },
	}, Replicator)

	match.events.stateChanged:connect(function(userId: number)
		self.dirty[userId] = true
	end)
	match.events.phaseChanged:connect(function(info: any)
		remotes.PhaseChanged:FireAllClients(info.phase, info.roundId, info.endsAt)
	end)
	match.events.toast:connect(function(userId: number, reason: string)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			remotes.Toast:FireClient(player, reason)
		end
	end)
	return self
end

-- Sends a snapshot to every player whose state changed and whose throttle window has passed.
function Replicator.flush(self: any)
	local t = self.now()
	local minGap = 1 / GameConfig.maxSnapshotsPerSecond
	for userId in self.dirty do
		if t - (self.lastSent[userId] or -math.huge) >= minGap then
			local player = Players:GetPlayerByUserId(userId)
			if player and self.match:getPlayer(userId) then
				self.remotes.StateUpdate:FireClient(player, Snapshot.build(self.match, userId))
			end
			self.dirty[userId] = nil
			self.lastSent[userId] = t
		end
	end
end

return Replicator
