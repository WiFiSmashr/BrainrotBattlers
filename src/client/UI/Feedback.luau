--!strict
-- Feedback moments (GDD 12.4): star-up merges, trait tier changes, level-ups, augment picks and the
-- Prep -> Combat change each get their own sound and a short on-screen banner. Sound ids come from
-- Shared/Config/Assets (placeholders); an empty id just plays nothing.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Index = require(Shared.Util.Index)
local TraitCounter = require(Shared.Util.TraitCounter)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local BANNER_SECONDS = 1.6

local Feedback = {}

local layer: Instance? = nil
local bannerToken = 0

-- Gives the module the Instance that banners are drawn into.
function Feedback.init(parent: Instance)
	layer = parent
end

-- Plays the sound registered under `key` in Assets.sounds.
function Feedback.sound(key: string)
	local id = Assets.sounds[key]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.6
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Shows a big centered message that fades out.
function Feedback.banner(text: string, color: Color3?)
	if not layer then
		return
	end
	bannerToken += 1
	local token = bannerToken
	local old = (layer :: Instance):FindFirstChild("Banner")
	if old then
		old:Destroy()
	end
	local banner = Components.label({
		Name = "Banner", Size = UDim2.fromOffset(900, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 380),
		Text = text, TextSize = 64, TextColor3 = color or Theme.colors.accent, TextStrokeTransparency = 0.3, ZIndex = 90, Parent = layer,
	})
	TweenService:Create(banner, TweenInfo.new(BANNER_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0, 340),
	}):Play()
	task.delay(BANNER_SECONDS, function()
		if token == bannerToken then
			banner:Destroy()
		end
	end)
end

-- Highest star of each unit id owned.
local function maxStars(snapshot: { [string]: any }): { [string]: number }
	local best: { [string]: number } = {}
	for _, u in snapshot.units do
		best[u.d] = math.max(best[u.d] or 0, u.s)
	end
	return best
end

-- Active tier index of each trait on the board.
local function tiers(snapshot: { [string]: any }): { [string]: number }
	local entries = {}
	for _, u in snapshot.units do
		local def = Index.unit(u.d)
		if u.c and def then
			table.insert(entries, { defId = u.d, traits = def.traits })
		end
	end
	local out = {}
	for id, state in TraitCounter.count(entries) do
		out[id] = state.tierIndex
	end
	return out
end

local function augmentCount(snapshot: { [string]: any }, userId: number): number
	for _, p in snapshot.players do
		if p.id == userId then
			return #(p.aug or {})
		end
	end
	return 0
end

-- Compares two snapshots and fires the matching feedback.
function Feedback.observe(old: { [string]: any }?, new: { [string]: any }, userId: number)
	if not old then
		return
	end
	local oldStars, newStars = maxStars(old), maxStars(new)
	for defId, star in newStars do
		if star > (oldStars[defId] or 0) and oldStars[defId] ~= nil then
			local def = Index.unit(defId)
			Feedback.banner(("%s ★%d!"):format(if def then def.name else defId, star))
			Feedback.sound("merge")
			break
		end
	end
	local oldTiers, newTiers = tiers(old), tiers(new)
	for id, tier in newTiers do
		if tier > 0 and tier > (oldTiers[id] or 0) then
			local trait = Index.trait(id)
			Feedback.banner(("%s tier %d"):format(if trait then trait.name else id, tier), Theme.colors.mana)
			Feedback.sound("traitTier")
			break
		end
	end
	if new.level > old.level then
		Feedback.banner(("Level %d!"):format(new.level), Theme.colors.good)
		Feedback.sound("levelUp")
	end
	if augmentCount(new, userId) > augmentCount(old, userId) then
		Feedback.banner("Augment chosen!", Theme.colors.gold)
		Feedback.sound("augmentPick")
	end
end

-- Fires when the phase changes; Prep -> Combat gets a clear banner and sound.
function Feedback.phaseChanged(oldName: string, newName: string)
	if newName == "Combat" then
		Feedback.banner("COMBAT!", Theme.colors.bad)
		Feedback.sound("combatStart")
	elseif newName == "Prep" and oldName ~= "Prep" then
		Feedback.banner("Prep", Theme.colors.good)
	end
end

return Feedback
