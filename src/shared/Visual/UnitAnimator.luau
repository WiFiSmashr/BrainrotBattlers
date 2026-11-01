--!strict
-- Plays a character's animations: idle, walk while moving, attack, cast, hit, death and victory.
-- Real animations come from the model's animation ids (ModelRegistry.animationsFor). Any state without
-- an animation falls back to a small procedural effect, so a placeholder block or an unfinished model
-- still feels alive (D-62). Presentation only.

local TweenService = game:GetService("TweenService")
local Types = require(script.Parent.Parent.Types)
local ModelFactory = require(script.Parent.ModelFactory)

local PRIORITY: { [string]: Enum.AnimationPriority } = {
	idle = Enum.AnimationPriority.Idle, walk = Enum.AnimationPriority.Movement, attack = Enum.AnimationPriority.Action,
	cast = Enum.AnimationPriority.Action, hit = Enum.AnimationPriority.Action2, death = Enum.AnimationPriority.Action4,
	victory = Enum.AnimationPriority.Action3,
}
local LOOPED: { [string]: boolean } = { idle = true, walk = true }

-- Procedural stand-ins: durations in seconds.
local LUNGE_OUT, LUNGE_BACK = 0.1, 0.14
local CAST_UP, CAST_BACK = 0.15, 0.2
local HIT_FLASH = 0.2
local DEATH_SECONDS = 0.35

local UnitAnimator = {}
UnitAnimator.__index = UnitAnimator

export type UnitAnimator = typeof(setmetatable(
	{} :: {
		visual: ModelFactory.Visual,
		tracks: { [string]: AnimationTrack },
		offsetValue: CFrameValue,
		highlight: Highlight?,
		moving: boolean,
		connection: RBXScriptConnection,
	},
	UnitAnimator
))

-- Loads a track per animation id. Needs a Humanoid or AnimationController; one is added if the model
-- has neither. Returns nothing when no animation ids are given (placeholders never get a controller).
local function loadTracks(model: Model, set: Types.AnimationSet): { [string]: AnimationTrack }
	local tracks: { [string]: AnimationTrack } = {}
	local hasId = false
	for _, id in set :: any do
		hasId = hasId or id ~= ""
	end
	if not hasId then
		return tracks
	end
	local controller: Instance? = model:FindFirstChildWhichIsA("Humanoid", true) or model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		local created = Instance.new("AnimationController")
		created.Parent = model
		controller = created
	end
	local animator = (controller :: Instance):FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	for state, id in set :: any do
		local animation = Instance.new("Animation")
		animation.Name = state
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = PRIORITY[state] or Enum.AnimationPriority.Action
			track.Looped = LOOPED[state] == true
			tracks[state] = track
		else
			warn(("[UnitAnimator] could not load %s animation %s"):format(state, id))
		end
	end
	return tracks
end

-- Creates the animator for a visual and starts the idle animation if there is one.
function UnitAnimator.new(visual: ModelFactory.Visual, animations: Types.AnimationSet): UnitAnimator
	local offsetValue = Instance.new("CFrameValue")
	offsetValue.Parent = visual.model -- lives and dies with the model
	local self = setmetatable({
		visual = visual,
		tracks = loadTracks(visual.model, animations),
		offsetValue = offsetValue,
		highlight = nil,
		moving = false,
		connection = offsetValue.Changed:Connect(function(offset: CFrame)
			visual:setOffset(offset)
		end),
	}, UnitAnimator)
	if self.tracks.idle then
		self.tracks.idle:Play(0)
	end
	return self
end

-- Slides the procedural offset to `goal`.
local function tweenOffset(self: UnitAnimator, goal: CFrame, seconds: number)
	TweenService:Create(self.offsetValue, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = goal }):Play()
end

-- Goes out to `goal` and comes back to rest.
local function pulse(self: UnitAnimator, goal: CFrame, outSeconds: number, backSeconds: number)
	tweenOffset(self, goal, outSeconds)
	task.delay(outSeconds, function()
		if self.connection.Connected then
			tweenOffset(self, CFrame.identity, backSeconds)
		end
	end)
end

-- Switches the walk animation on or off.
function UnitAnimator.setMoving(self: UnitAnimator, moving: boolean)
	if moving == self.moving then
		return
	end
	self.moving = moving
	local walk = self.tracks.walk
	if walk then
		if moving then
			walk:Play(0.1)
		else
			walk:Stop(0.1)
		end
	end
end

-- Plays an action track; returns its length, or nil if the state has no animation.
local function playTrack(self: UnitAnimator, state: string): number?
	local track = self.tracks[state]
	if track then
		track:Play(0.05)
		return track.Length
	end
	return nil
end

-- Attack. Returns how long it takes.
function UnitAnimator.attack(self: UnitAnimator): number
	local length = playTrack(self, "attack")
	if length then
		return length
	end
	pulse(self, CFrame.new(0, 0, -1.2), LUNGE_OUT, LUNGE_BACK) -- lunge forward (a model's front is -Z)
	return LUNGE_OUT + LUNGE_BACK
end

-- Ability cast. Returns how long it takes.
function UnitAnimator.cast(self: UnitAnimator): number
	local length = playTrack(self, "cast")
	if length then
		return length
	end
	pulse(self, CFrame.new(0, 1, 0), CAST_UP, CAST_BACK)
	return CAST_UP + CAST_BACK
end

-- Taking a hit: the hit animation, or a short white flash.
function UnitAnimator.hit(self: UnitAnimator)
	if playTrack(self, "hit") then
		return
	end
	local highlight = self.highlight
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 1
		highlight.FillTransparency = 1
		highlight.Adornee = self.visual.model
		highlight.Parent = self.visual.model
		self.highlight = highlight
	end
	highlight.FillTransparency = 0.35
	TweenService:Create(highlight, TweenInfo.new(HIT_FLASH), { FillTransparency = 1 }):Play()
end

-- Victory pose (nothing happens without a victory animation).
function UnitAnimator.victory(self: UnitAnimator)
	playTrack(self, "victory")
end

-- Death. Returns how long to wait before removing the model.
function UnitAnimator.die(self: UnitAnimator): number
	self.moving = false
	for _, track in self.tracks do
		track:Stop(0.05)
	end
	local length = playTrack(self, "death")
	if length then
		return length
	end
	tweenOffset(self, CFrame.new(0, -2, 0) * CFrame.Angles(math.rad(75), 0, 0), DEATH_SECONDS)
	return DEATH_SECONDS
end

-- Stops everything and cleans up. Call before destroying the visual.
function UnitAnimator.destroy(self: UnitAnimator)
	self.connection:Disconnect()
	for _, track in self.tracks do
		track:Stop(0)
	end
	self.offsetValue:Destroy()
end

return UnitAnimator
