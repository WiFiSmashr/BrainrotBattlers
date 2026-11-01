--!strict
-- The main menu's server side: who is in the menu, who is queued, and which match (if any) is running.
-- Players press Play to join the queue; a match starts when the queue is full, or after the wait with
-- enough players, and bots fill the empty seats (D-17, BOT-01). One match runs at a time; players who
-- queue meanwhile wait for the next one. A player returns to the menu from the end screen.
--
-- Everything the match needs is created through `deps.newRun`, so this module is plain logic and the
-- tests can drive it with a fake clock.

local SessionService = {}
SessionService.__index = SessionService

export type Status = "Menu" | "Queued" | "InMatch"

-- One running match: its service, the router humans and bots act through, and the bot driver.
export type Run = {
	match: any,
	router: any,
	bots: any?,
	replicator: any?, -- sends this match's snapshots; flushed every tick
}

export type Info = {
	status: Status,
	queued: number, -- players waiting in the queue
	needed: number, -- the lobby size
	startsAt: number?, -- server time the queue will start a match, once enough players are waiting
	matchRunning: boolean, -- a match is in progress, so a queued player waits for it
}

export type Deps = {
	lobbySize: number,
	minPlayers: number,
	waitSeconds: number,
	fillWithBots: boolean,
	now: () -> number,
	newRun: () -> Run,
	fillBots: (match: any) -> (),
	onStart: (run: Run) -> (), -- after match:start(): build the plots
	onCleanup: (run: Run) -> (), -- the match is over and nobody is in it: remove the plots
	notify: (userId: number, info: Info) -> (),
}

local MENU_ACTIONS = { JoinQueue = true, LeaveQueue = true, BackToMenu = true }
local RESEND_SECONDS = 2 -- clients that connected late still learn their status

function SessionService.new(deps: Deps): any
	return setmetatable({
		deps = deps,
		status = {} :: { [number]: Status },
		names = {} :: { [number]: string },
		queue = {} :: { number },
		queueSince = nil :: number?,
		run = nil :: Run?,
		humans = {} :: { [number]: boolean }, -- the humans seated in the running match
		lastSignature = "",
		lastSent = {} :: { [number]: number },
		dirty = {} :: { [number]: boolean },
	}, SessionService)
end

function SessionService.getStatus(self: any, userId: number): Status?
	return self.status[userId]
end

function SessionService.currentRun(self: any): Run?
	return self.run
end

-- True if the player should be sent match snapshots.
function SessionService.isInMatch(self: any, userId: number): boolean
	return self.status[userId] == "InMatch" and self.run ~= nil
end

function SessionService.queueSize(self: any): number
	return #self.queue
end

-- A newly connected player starts in the menu.
function SessionService.addPlayer(self: any, userId: number, name: string)
	if self.status[userId] then
		return
	end
	self.status[userId] = "Menu"
	self.names[userId] = name
	self.dirty[userId] = true
end

local function removeFromQueue(self: any, userId: number)
	local at = table.find(self.queue, userId)
	if at then
		table.remove(self.queue, at)
	end
	if #self.queue == 0 then
		self.queueSince = nil
	end
end

-- A player disconnects: out of the queue, and out of the match if they were in one.
function SessionService.removePlayer(self: any, userId: number)
	removeFromQueue(self, userId)
	local run = self.run
	if run and self.humans[userId] then
		self.humans[userId] = nil
		run.match:removePlayer(userId)
	end
	self.status[userId] = nil
	self.names[userId] = nil
	self.lastSent[userId] = nil
	self.dirty[userId] = nil
end

function SessionService.info(self: any, userId: number): Info
	local startsAt: number? = nil
	if #self.queue >= self.deps.minPlayers and self.queueSince and not self.run then
		startsAt = self.queueSince + self.deps.waitSeconds
	end
	return {
		status = self.status[userId] or "Menu",
		queued = #self.queue,
		needed = self.deps.lobbySize,
		startsAt = startsAt,
		matchRunning = self.run ~= nil,
	}
end

local function result(ok: boolean, reason: string?): { ok: boolean, reason: string? }
	return { ok = ok, reason = reason }
end

function SessionService.join(self: any, userId: number)
	local status = self.status[userId]
	if not status then
		return result(false, "Unknown")
	end
	if status ~= "Menu" then
		return result(false, "AlreadyQueued")
	end
	self.status[userId] = "Queued"
	table.insert(self.queue, userId)
	if not self.queueSince then
		self.queueSince = self.deps.now()
	end
	self.dirty[userId] = true
	return result(true)
end

function SessionService.leave(self: any, userId: number)
	if self.status[userId] ~= "Queued" then
		return result(false, "NotQueued")
	end
	removeFromQueue(self, userId)
	self.status[userId] = "Menu"
	self.dirty[userId] = true
	return result(true)
end

-- Back to the menu from the end screen: allowed once this player is out of the game or the match is over.
function SessionService.backToMenu(self: any, userId: number)
	if self.status[userId] ~= "InMatch" then
		return result(false, "NotInMatch")
	end
	local run = self.run
	if run then
		local finished = run.match.phase == "MatchEnd" or run.match.placements[userId] ~= nil
		if not finished then
			return result(false, "MatchRunning")
		end
	end
	self.humans[userId] = nil
	self.status[userId] = "Menu"
	self.dirty[userId] = true
	return result(true)
end

-- Handles a client action: menu actions here, everything else goes to the running match's router.
function SessionService.handle(self: any, userId: number, name: string, args: any): any
	if MENU_ACTIONS[name] then
		if name == "JoinQueue" then
			return self:join(userId)
		elseif name == "LeaveQueue" then
			return self:leave(userId)
		end
		return self:backToMenu(userId)
	end
	local run = self.run
	if run and self.status[userId] == "InMatch" then
		return run.router:handle(userId, name, args)
	end
	return result(false, "NotInMatch")
end

local function startMatch(self: any)
	local deps = self.deps
	local run = deps.newRun()
	local match = run.match
	local seated = {}
	for _, userId in self.queue do
		if #seated < deps.lobbySize then
			table.insert(seated, userId)
		end
	end
	for _, userId in seated do
		match:addPlayer(userId, self.names[userId] or "Player")
		self.status[userId] = "InMatch"
		self.humans[userId] = true
		self.dirty[userId] = true
		removeFromQueue(self, userId)
	end
	if deps.fillWithBots then
		deps.fillBots(match)
	end
	match:start()
	self.run = run
	deps.onStart(run)
	-- Anyone left in the queue (more than a lobby's worth) waits for the next match.
	self.queueSince = if #self.queue > 0 then deps.now() else nil
end

local function endRun(self: any)
	local run = self.run
	if not run then
		return
	end
	self.run = nil
	self.humans = {}
	self.deps.onCleanup(run)
	if #self.queue > 0 then
		self.queueSince = self.deps.now()
	end
end

local function humanCount(self: any): number
	local count = 0
	for _ in self.humans do
		count += 1
	end
	return count
end

-- Called every server tick: starts matches, drives the running one, retires it when empty, and
-- tells menu clients what changed.
function SessionService.update(self: any)
	local deps = self.deps
	local run = self.run
	if run then
		if humanCount(self) == 0 then
			endRun(self)
		else
			run.match:update()
			if run.bots then
				run.bots:update()
			end
			if run.replicator then
				run.replicator:flush()
			end
		end
	end
	if not self.run and #self.queue > 0 then
		local waited = deps.now() - (self.queueSince or deps.now())
		if #self.queue >= deps.lobbySize or (#self.queue >= deps.minPlayers and waited >= deps.waitSeconds) then
			startMatch(self)
		end
	end

	-- Menu information: sent when the shared picture changes, to a player whose own status changed,
	-- and every few seconds as a heartbeat.
	local info = self:info(0)
	local signature = ("%d|%s|%s"):format(info.queued, tostring(info.startsAt), tostring(info.matchRunning))
	local changed = signature ~= self.lastSignature
	self.lastSignature = signature
	local t = deps.now()
	for userId, status in self.status do
		local send = self.dirty[userId] or t - (self.lastSent[userId] or -math.huge) >= RESEND_SECONDS
		if not send and changed and status ~= "InMatch" then
			send = true
		end
		if send then
			self.dirty[userId] = nil
			self.lastSent[userId] = t
			deps.notify(userId, self:info(userId))
		end
	end
end

return SessionService
