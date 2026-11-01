--!strict
-- Round schedule (GDD 4.2). Round ids read "stage-round"; global round g is `round` in stage 1
-- and 4 + 7 * (stage - 2) + round from stage 2 on.

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

export type RoundType = "pve" | "pvp" | "carousel"

export type RoundInfo = {
	id: string,
	stage: number,
	round: number,
	global: number,
	type: RoundType,
	drops: number, -- components dropped on a PvE win (ITM-10)
	augmentOffer: number?, -- offer number if this round has one (AUG-01)
	givesStarter: boolean, -- round 1-1 (LVL-05)
}

local RoundSchedule = {}

-- Number of rounds in a stage.
function RoundSchedule.roundsInStage(stage: number): number
	return if stage == 1 then #GameConfig.stage1Layout else #GameConfig.laterStageLayout
end

-- Global round number for a stage and round.
function RoundSchedule.globalRound(stage: number, round: number): number
	if stage == 1 then
		return round
	end
	return #GameConfig.stage1Layout + #GameConfig.laterStageLayout * (stage - 2) + round
end

-- Full description of a round.
function RoundSchedule.info(stage: number, round: number): RoundInfo
	local layout = if stage == 1 then GameConfig.stage1Layout else GameConfig.laterStageLayout
	local entry = layout[round]
	local id = stage .. "-" .. round
	return {
		id = id,
		stage = stage,
		round = round,
		global = RoundSchedule.globalRound(stage, round),
		type = entry.type,
		drops = entry.drops,
		augmentOffer = GameConfig.augmentRounds[id],
		givesStarter = stage == 1 and round == 1,
	}
end

-- The round after (stage, round); the stage ends after its last round.
function RoundSchedule.next(stage: number, round: number): (number, number)
	if round >= RoundSchedule.roundsInStage(stage) then
		return stage + 1, 1
	end
	return stage, round + 1
end

-- Prep length in seconds: 20s in round 1-1, 25s otherwise, +15s in augment rounds (4.3, AUG-01).
function RoundSchedule.prepSeconds(info: RoundInfo): number
	local seconds = if info.givesStarter then GameConfig.prepSecondsRound1 else GameConfig.prepSeconds
	if info.augmentOffer then
		seconds += GameConfig.augmentPrepBonusSeconds
	end
	return seconds
end

-- Carousel phase length: intro + pick time per living player (CAR-05).
function RoundSchedule.carouselSeconds(livingPlayers: number): number
	return GameConfig.carouselIntroSeconds + GameConfig.carouselPickSeconds * livingPlayers
end

return RoundSchedule
