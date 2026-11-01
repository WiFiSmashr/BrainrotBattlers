--!strict
-- What buying a shop slot would mean for the player: how many copies they already own, and whether the
-- purchase completes a star-up merge (MRG-01, D-54). Pure, so the shop panel only draws it.

local ShopHints = {}

export type Hint = {
	owned: number, -- copies of this character on the board and bench, at any star level
	starUp: number?, -- the star level a merge would reach (2 or 3), if buying completes one
}

-- `units` are the snapshot's unit entries ({ d = unit id, s = stars }). `buysBoth` is true when a full
-- bench makes the purchase buy two copies at once (D-54), which completes a merge with one owned copy.
function ShopHints.evaluate(units: { { [string]: any } }, defId: string, buysBoth: boolean): Hint
	local owned, byStar = 0, { 0, 0, 0 }
	for _, unit in units do
		if unit.d == defId then
			owned += 1
			byStar[unit.s] = (byStar[unit.s] or 0) + 1
		end
	end
	local merges = byStar[1] >= 2 or (buysBoth and byStar[1] == 1)
	if not merges then
		return { owned = owned, starUp = nil }
	end
	-- A new star 2 unit joins any existing ones; two already owned make a third and merge again.
	return { owned = owned, starUp = if byStar[2] >= 2 then 3 else 2 }
end

return ShopHints
