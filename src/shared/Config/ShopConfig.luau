--!strict
-- Shop tunables (GDD 6.3, 6.4; SHOP-01). Every value here is [CONFIG].

local ShopConfig = {
	slots = 5,

	-- Percent chance per cost tier (1 to 5), by player level. Every row sums to 100.
	odds = {
		[1] = { 100, 0, 0, 0, 0 },
		[2] = { 100, 0, 0, 0, 0 },
		[3] = { 75, 25, 0, 0, 0 },
		[4] = { 55, 30, 15, 0, 0 },
		[5] = { 45, 33, 20, 2, 0 },
		[6] = { 30, 40, 25, 5, 0 },
		[7] = { 19, 30, 35, 15, 1 },
		[8] = { 16, 20, 35, 25, 4 },
		[9] = { 12, 18, 28, 28, 14 },
		[10] = { 5, 10, 20, 40, 25 },
	},
}

return ShopConfig
