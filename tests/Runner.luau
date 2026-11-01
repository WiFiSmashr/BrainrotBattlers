--!strict
-- Plain-assert test runner. In Studio's command bar run:
--   require(game.ServerScriptService.Tests.Runner).runAll()
-- Every sibling ModuleScript named "*Spec" returns function(t) that registers tests via t.test.

local Runner = {}

type TestFn = () -> ()

-- Runs all specs, prints one line per test plus a summary; returns true if everything passed.
function Runner.runAll(): boolean
	local passed, failed, skipped = 0, 0, 0
	local failures: { string } = {}

	local t = {}
	local currentSpec = ""

	function t.test(name: string, fn: TestFn)
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print(("  PASS  %s :: %s"):format(currentSpec, name))
		else
			failed += 1
			table.insert(failures, ("%s :: %s -> %s"):format(currentSpec, name, tostring(err)))
			warn(("  FAIL  %s :: %s -> %s"):format(currentSpec, name, tostring(err)))
		end
	end

	-- Marks a test as deliberately skipped, with the phase that will enable it.
	function t.skip(name: string, phase: number)
		skipped += 1
		print(("  SKIP  %s :: %s (TODO phase %d)"):format(currentSpec, name, phase))
	end

	function t.eq(actual: any, expected: any, label: string?)
		if actual ~= expected then
			error(("%sexpected %s, got %s"):format(label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
		end
	end

	function t.near(actual: number, expected: number, tolerance: number?, label: string?)
		if math.abs(actual - expected) > (tolerance or 1e-6) then
			error(("%sexpected ~%s, got %s"):format(label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
		end
	end

	function t.truthy(value: any, label: string?)
		if not value then
			error(label or "expected a truthy value", 2)
		end
	end

	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and child.Name:match("Spec$") then
			currentSpec = child.Name
			local ok, spec = pcall(require, child)
			if ok and type(spec) == "function" then
				spec(t)
			else
				failed += 1
				table.insert(failures, child.Name .. " failed to load: " .. tostring(spec))
				warn("  FAIL  " .. child.Name .. " failed to load: " .. tostring(spec))
			end
		end
	end

	print(("TESTS: %d passed, %d failed, %d skipped"):format(passed, failed, skipped))
	return failed == 0
end

return Runner
