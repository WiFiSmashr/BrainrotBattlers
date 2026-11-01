--!strict
-- Plain-table types for the combat simulation (ARCH-04: no Instances anywhere in Combat/ sim code).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Grid = require(game:GetService("ReplicatedStorage").Shared.Util.Grid)
local StatBlock = require(script.Parent.StatBlock)
local Damage = require(script.Parent.Damage)

export type Cell = Grid.Cell
export type Team = "home" | "away"
export type Status = { expires: number, amount: number, source: number? }
export type Modifier = { stat: string, kind: "flat" | "pct" | "mult", value: number, sourceId: string }

-- What callers pass in for each fighter. `cell` is in the fighter's OWN board coordinates (7x4);
-- the sim mirrors the away team (CMB-02).
export type UnitSpec = {
	name: string,
	defId: string?,
	cost: number?, -- stat lookup; omit for monsters and tokens
	archetype: Types.Archetype,
	star: number,
	cell: Cell,
	health: number?, -- explicit overrides (monsters, tokens)
	ad: number?,
	attackSpeed: number?,
	ability: Types.AbilityDef?,
	isToken: boolean?,
	modifiers: { Modifier }?, -- permanent bonuses (e.g. Noob growth)
	uid: number?, -- the player-state unit this came from
	traits: { string }?,
	items: { string }?, -- equipped item ids; EffectRunner turns them into stats and effects
}

export type Unit = {
	id: number,
	team: Team,
	name: string,
	defId: string?,
	star: number,
	isToken: boolean,
	cost: number?, -- unit cost, for effects that rank units (Main Character Energy)
	uid: number?,
	traits: { string },
	items: { string },
	cell: Cell,
	startCell: Cell,
	alive: boolean,
	health: number,
	shields: { { amount: number, expires: number? } },
	mana: number,
	maxMana: number,
	stats: { [string]: StatBlock.StatBlock },
	ability: Types.AbilityDef?,
	target: number?,
	attackReadyAt: number,
	castUntil: number?,
	castTargets: { number }?,
	stepTo: Cell?,
	stepArriveAt: number,
	statuses: { [string]: Status },
	timed: { { sourceId: string, stat: string, expires: number } },
	lastDamager: number?,
	counters: { [string]: number }, -- scratch space for effects (e.g. rot stacks)
	view: Damage.Target,
}

return {}
