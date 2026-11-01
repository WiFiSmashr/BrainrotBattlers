--!strict
-- Phase 0 sample test: proves the runner and the Shared mapping work.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

return function(t)
	t.test("runner works and Shared is mapped", function()
		t.truthy(Shared:FindFirstChild("Types"), "Shared/Types missing")
		t.eq(1 + 1, 2)
	end)
end
