--!strict
-- Colors, sizes and display names shared by every panel (GDD 2.3, 12.1).
-- Layout is designed against a 1920 x 1080 reference (UI-03).

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local Theme = {
	colors = {
		bg = Color3.fromRGB(22, 22, 34),
		panel = Color3.fromRGB(36, 38, 58),
		panelLight = Color3.fromRGB(56, 60, 88),
		text = Color3.fromRGB(245, 245, 250),
		textDim = Color3.fromRGB(175, 180, 205),
		accent = Color3.fromRGB(255, 196, 61),
		good = Color3.fromRGB(90, 205, 115),
		bad = Color3.fromRGB(235, 85, 85),
		mana = Color3.fromRGB(85, 145, 255),
		gold = Color3.fromRGB(255, 214, 70),
		cellHome = Color3.fromRGB(46, 50, 76),
		cellAlt = Color3.fromRGB(52, 56, 84),
		shield = Color3.fromRGB(200, 220, 255),
	},
	-- Unit rarity border by cost 1 to 5 (2.3).
	rarityColors = {
		Common = Color3.fromRGB(150, 152, 160),
		Uncommon = Color3.fromRGB(80, 200, 100),
		Rare = Color3.fromRGB(70, 140, 255),
		Epic = Color3.fromRGB(170, 90, 230),
		Legendary = Color3.fromRGB(255, 200, 50),
	} :: { [string]: Color3 },
	augmentColors = {
		Bronze = Color3.fromRGB(176, 112, 64),
		Silver = Color3.fromRGB(200, 205, 218),
		Gold = Color3.fromRGB(255, 205, 60),
	} :: { [string]: Color3 },
	font = Enum.Font.GothamBold,
	fontBody = Enum.Font.Gotham,
	-- UI-03: the smallest allowed touch target at the 1920 x 1080 reference scale.
	minTouch = 44,
	referenceWidth = 1920,
	referenceHeight = 1080,
	cell = 92, -- board / bench tile size in reference pixels
}

local COST_RARITY: { Types.Rarity } = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Rarity name for a unit cost (1 to 5).
function Theme.rarityOfCost(cost: number): Types.Rarity
	return COST_RARITY[cost]
end

-- Border color for a unit cost.
function Theme.costColor(cost: number): Color3
	return Theme.rarityColors[COST_RARITY[cost]]
end

-- Short display text for a rejected-action reason code from the server (UI-05).
Theme.toastText = {
	NotEnoughGold = "Not enough gold",
	BenchFull = "Bench full",
	BoardFull = "Board full - level up or sell a unit",
	EmptySlot = "That shop slot is empty",
	WrongPhase = "You can't do that right now",
	NoUnequipInCombat = "Items can't be taken off during combat",
	NoFieldInCombat = "Units can't be moved on or off the board during combat",
	UnknownUnit = "Unit not found",
	UnknownItem = "Item not found",
	ItemEquipped = "Take that item off its unit first",
	NotEquipped = "That item is not equipped",
	UnitFull = "That unit already holds 3 items",
	CannotCombine = "Those items can't be combined",
	MaxLevel = "Already at max level",
	OutOfBounds = "You can't place a unit there",
	NotYourTurn = "Not your turn to pick",
	NoOffer = "No augment offer right now",
	AlreadyRerolled = "You already used the free reroll",
	BadArgs = "That didn't work - try again",
	RateLimited = "Slow down a little",
	NotInMatch = "You're not in the match",
	UnknownAction = "That action isn't available",
	NetworkError = "Connection problem - try again",
} :: { [string]: string }

return Theme
