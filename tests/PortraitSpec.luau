--!strict
-- Shop artwork data and the shop's owned / star-up hints (D-80).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Portraits = require(Shared.Data.Portraits)
local Units = require(Shared.Data.Units)
local ShopHints = require(Shared.Util.ShopHints)

local function unit(defId: string, star: number): { [string]: any }
	return { d = defId, s = star }
end

return function(t)
	t.test("portrait entries name real units and use image asset ids", function()
		local known: { [string]: boolean } = {}
		for _, def in Units do
			known[def.id] = true
		end
		for id, image in Portraits do
			t.truthy(known[id], "no such unit: " .. id)
			t.truthy(image:match("^rbxassetid://%d+$") ~= nil, "bad image id for " .. id)
		end
	end)

	t.test("nothing owned: no highlight", function()
		local hint = ShopHints.evaluate({ unit("a", 1) }, "b", false)
		t.eq(hint.owned, 0)
		t.eq(hint.starUp, nil)
	end)

	t.test("owning one or two copies highlights as owned, not as a star up", function()
		t.eq(ShopHints.evaluate({ unit("a", 1) }, "a", false).owned, 1)
		t.eq(ShopHints.evaluate({ unit("a", 1) }, "a", false).starUp, nil)
		local two = ShopHints.evaluate({ unit("a", 1), unit("a", 1), unit("a", 2) }, "a", false)
		t.eq(two.owned, 3, "any star level counts as owned")
		t.eq(two.starUp, 2, "two star-1 copies make the third a merge")
	end)

	t.test("a copy of another star level does not count toward the merge", function()
		t.eq(ShopHints.evaluate({ unit("a", 2), unit("a", 2), unit("a", 1) }, "a", false).starUp, nil)
	end)

	t.test("completing a star 2 with another star 2 owned announces star 3", function()
		local units = { unit("a", 1), unit("a", 1), unit("a", 2), unit("a", 2) }
		t.eq(ShopHints.evaluate(units, "a", false).starUp, 3)
	end)

	t.test("the full-bench double buy counts as a star up with one owned copy", function()
		t.eq(ShopHints.evaluate({ unit("a", 1) }, "a", true).starUp, 2)
		t.eq(ShopHints.evaluate({ unit("a", 1) }, "a", false).starUp, nil)
	end)
end
