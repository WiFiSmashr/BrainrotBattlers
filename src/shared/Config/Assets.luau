--!strict
-- Placeholder asset IDs (GDD 12.4). Swap values later; code references keys only.
-- Sounds use built-in Roblox content so they work without uploading anything; an empty or missing id
-- simply plays nothing. Each feedback moment has its own key so the sounds can differ.

local Assets = {
	sounds = {
		merge = "rbxasset://sounds/electronicpingshort.wav", -- a star-up merge
		traitTier = "rbxasset://sounds/button-3.mp3", -- a trait reached a new tier
		levelUp = "rbxasset://sounds/bass.wav", -- the player levelled up
		augmentPick = "rbxasset://sounds/snap.mp3", -- an augment was chosen
		combatStart = "rbxasset://sounds/impact_water.mp3", -- Prep -> Combat banner
		buy = "rbxasset://sounds/switch.wav", -- unit bought
		toast = "rbxasset://sounds/uuhhh.mp3", -- a rejected action
	} :: { [string]: string },
	effects = {} :: { [string]: string },
	icons = {} :: { [string]: string },
}

return Assets
