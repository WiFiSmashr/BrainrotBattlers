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

local RESYNC_SECONDS = 2

local Replicator = {}
Replicator.__index = Replicator

-- Wires match events to the Remotes. `now` is the server clock in seconds.
-- `watching` (optional) says which players still follow this match; others, such as a player who went
-- back to the menu, are sent nothing.
function Replicator.new(match: any, remotes: Remotes, now: () -> number, watching: ((userId: number) -> boolean)?): any
	local self = setmetatable({
		match = match,
		remotes = remotes,
		now = now,
		watching = watching,
		dirty = {} :: { [number]: boolean },
		lastSent = {} :: { [number]: number },
	}, Replicator)

	match.events.stateChanged:connect(function(userId: number)
		self.dirty[userId] = true
	end)
	match.events.phaseChanged:connect(function(info: any)
		for _, userId in match.order do
			local player = Players:GetPlayerByUserId(userId)
			if player and (not watching or watching(userId)) then
				remotes.PhaseChanged:FireClient(player, info.phase, info.roundId, info.endsAt)
			end
		end
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
	-- A client that connected late, or whose script started after the last change, would otherwise wait
	-- for the next change. Re-send each seated player's state every few seconds as a heartbeat.
	if self.match.phase ~= "Lobby" then
		for _, userId in self.match.order do
			if t - (self.lastSent[userId] or -math.huge) >= RESYNC_SECONDS then
				self.dirty[userId] = true
			end
		end
	end
	for userId in self.dirty do
		if t - (self.lastSent[userId] or -math.huge) >= minGap then
			local player = Players:GetPlayerByUserId(userId)
			if player and self.match:getPlayer(userId) and (not self.watching or self.watching(userId)) then
				self.remotes.StateUpdate:FireClient(player, Snapshot.build(self.match, userId))
			end
			self.dirty[userId] = nil
			self.lastSent[userId] = t
		end
	end
end

return Replicator
