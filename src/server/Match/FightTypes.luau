--!strict
-- Types shared by MatchService and the combat adapter.

local PlayerState = require(script.Parent.Parent.Player.PlayerState)

export type Fight = {
	kind: "pve" | "pvp" | "ghost",
	home: PlayerState.State,
	away: PlayerState.State?, -- opponent (or ghost owner) for PvP; nil for PvE
	monsters: number, -- monster count for PvE
	globalRound: number,
	seed: number, -- CMB-01: hash(matchSeed, globalRound, homePlayerId)
}

export type Outcome = {
	winner: "home" | "away" | "draw",
	survivors: number, -- living non-token units on the winning side (CMB-12)
	seconds: number, -- sim time
	replay: any?, -- recorded events for CombatRunner playback (nil in tests)
}

return {}
