--!strict
-- Shared/Types.luau (GDD 13.1, 13.2)
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Archetype = "Brawler" | "Fighter" | "Assassin" | "Marksman" | "Mage" | "Support"
export type DamageType = "Physical" | "Magic" | "True"
export type ItemTag = "AD" | "AP" | "Health" | "AS" | "Armor" | "MR"
export type AugmentRarity = "Bronze" | "Silver" | "Gold"
export type AugmentCategory = "Economy" | "Combat" | "Items"
export type StarValues = { number } -- { star1, star2, star3 }

export type Targeting =
	"Self" | "CurrentTarget" | "NearestEnemies" | "RandomEnemies" | "FarthestEnemyInRange"
	| "LowestHealthEnemyInRange" | "HighestHealthEnemyInRange" | "HighestManaEnemyInRange"
	| "LowestHealthAlly" | "AlliesInRadius" | "EnemiesInRadius"

export type AbilityEffect = {
	kind: "Damage" | "Heal" | "Shield" | "Status" | "Dash" | "Summon" | "Mana" | "StatBuff" | "Custom",
	damageType: DamageType?,
	values: StarValues?, -- damage, heal, shield, or buff amount per star
	adRatio: number?, -- fraction of AD added before the AP multiplier (ABL-01)
	duration: StarValues?, -- seconds
	status: string?, -- a status name from Section 11.5
	radius: number?,
	count: number?,
	hits: number?,
	customId: string?, -- Effect module id when kind == "Custom"
	-- Additions beyond GDD 13.1 (see docs/DECISIONS.md D-03):
	stat: string?, -- stat id changed when kind == "StatBuff" (e.g. "armor", "attackSpeedPct")
	onSelf: boolean?, -- apply to the caster instead of the ability's targets
	options: { { AbilityEffect } }?, -- pick ONE list with the combat RNG (Lootbox Lemur)
	behind: boolean?, -- Dash: land on the far side of the target (Lag Lizard)
}

export type AbilityDef = {
	name: string,
	description: string,
	targeting: Targeting,
	range: number?,
	count: number?,
	radius: number?,
	castTime: number?, -- default 0.5
	effects: { AbilityEffect },
}

export type UnitDef = {
	id: string,
	name: string,
	cost: number, -- 1 to 5, also sets Rarity
	traits: { string }, -- Trait ids
	archetype: Archetype,
	ability: AbilityDef,
	modelId: string?,
	tint: Color3?, -- placeholder visuals
}

-- Animation asset ids by state (e.g. "rbxassetid://123456"). Any state may be left out; a missing
-- animation falls back to a simple procedural effect (D-62).
export type AnimationSet = {
	idle: string?, walk: string?, attack: string?, cast: string?, hit: string?, death: string?, victory: string?,
}

-- How one 3D model is found and dressed (Shared/Data/Models). Everything is optional except `id`: a
-- Model named `id` in ReplicatedStorage/UnitModels needs no entry at all.
export type ModelDef = {
	id: string,
	template: string?, -- name of the Model in ReplicatedStorage/UnitModels; defaults to `id`
	assetId: number?, -- Roblox asset id of a Model, loaded into UnitModels at server start when no template exists
	scale: number?, -- size multiplier on top of the standard unit height (default 1)
	facing: number?, -- yaw in degrees to turn the model so its front faces forward (default 0)
	rotation: Vector3?, -- degrees about the world X, Y, Z axes that stand up a model saved lying down (default none)
	animations: AnimationSet?, -- this model's animations; missing states use the shared defaults
}

export type TierDef = { count: number, params: { [string]: number }, description: string }

export type TraitDef = {
	id: string,
	name: string,
	kind: "Origin" | "Class",
	scope: "members" | "team",
	tiers: { TierDef }, -- ascending by count
	description: string,
}

export type StatBonus = {
	health: number?,
	ad: number?,
	ap: number?,
	attackSpeedPct: number?,
	armor: number?,
	mr: number?,
	critChance: number?,
	critDamage: number?,
}

export type ItemDef = {
	id: string,
	name: string,
	kind: "Component" | "Combined",
	tags: { ItemTag },
	stats: StatBonus,
	recipe: { string }?, -- exactly 2 component ids, only for Combined
	params: { [string]: number }?,
	description: string,
}

export type AugmentDef = {
	id: string,
	name: string,
	rarity: AugmentRarity,
	categories: { AugmentCategory }, -- first entry is the primary category
	params: { [string]: number },
	description: string,
}

export type HookName =
	"OnPrepStart" | "OnIncomeCalc" | "OnUnitBought" | "OnItemCombined" | "OnRoundEnd"
	| "OnCombatStart" | "OnTick" | "OnAttack" | "OnDamageDealt" | "OnDamageTaken"
	| "OnCast" | "OnKill" | "OnDeath" | "OnCombatEnd"

-- Helpers an effect may use. Never exposes raw Instances. Built by EffectRunner (D-31).
-- Combat contexts: `owner` is the holder unit (items) or nil (traits); `units` are the units the
-- effect applies to; `members` carry the trait. Economy contexts (income, round end) instead carry
-- `player`, `members` (player-state units) and addIncome.
export type EffectContext = {
	sim: any?,
	sourceId: string,
	owner: any?,
	team: string?,
	units: { any },
	members: { any },
	params: { [string]: number },
	state: { [string]: any }, -- scratch space owned by the module
	rng: any?,
	teamInfo: { gold: number, streak: number?, traits: number?, augments: { string }? }?,
	player: any?,
	isMember: (unit: any) -> boolean,
	addModifier: (unit: any, stat: string, kind: "flat" | "pct" | "mult", value: number, duration: number?, subId: string?) -> (),
	removeModifiers: (unit: any, subId: string?) -> (),
	queueDamage: (source: any?, target: any, amount: number, damageType: DamageType, flags: any?) -> (),
	queueHeal: (target: any, amount: number) -> (),
	heal: (target: any, amount: number) -> (),
	queueShield: (target: any, amount: number, duration: number) -> (),
	applyStatus: (target: any, status: string, duration: number, amount: number?, source: any?) -> (),
	summon: (owner: any, def: any) -> (),
	addIncome: (label: string, amount: number) -> (),
}

export type EffectModule = {
	id: string,
	-- Called when the effect becomes active (trait tier reached, item equipped, augment picked).
	attach: (ctx: EffectContext, params: { [string]: number }) -> (),
	-- Called when it stops being active. MUST remove every modifier it added (by sourceId).
	detach: (ctx: EffectContext) -> (),
	hooks: { [HookName]: (ctx: EffectContext, event: any) -> () }?,
	-- Augments only: runs once when the player picks it (instant gold, items, per-player Config
	-- overrides). ctx is built by AugmentService. See D-37.
	onPick: ((ctx: any) -> ())?,
}

return {}
