--!strict
-- Tests for the 3D model framework: data rules, lookup conventions, the model factory (real and
-- placeholder), and the animator fallbacks. No art is needed; the tests build their own models.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Models = require(Shared.Data.Models)
local Units = require(Shared.Data.Units)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ModelFactory = require(Shared.Visual.ModelFactory)
local UnitAnimator = require(Shared.Visual.UnitAnimator)
local ModelLoader = require(Server.Combat.ModelLoader)

local function templates(): Folder
	local folder = ReplicatedStorage:FindFirstChild(ModelFactory.folderName) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ModelFactory.folderName
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

-- A simple upright template: a root 2x8x2, an arm joined by a Motor6D, and a stray Script.
local function jointedTemplate(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 8, 2)
	root.Anchored = false
	root.Parent = model
	local arm = Instance.new("Part")
	arm.Name = "Arm"
	arm.Size = Vector3.new(1, 3, 1)
	arm.CFrame = CFrame.new(1.5, 0, 0)
	arm.Parent = model
	local joint = Instance.new("Motor6D")
	joint.Part0, joint.Part1 = root, arm
	joint.Parent = root
	Instance.new("Script").Parent = model
	model.PrimaryPart = root
	model.Parent = templates()
	return model
end

local function isSnake(id: string): boolean
	return id:match("^[a-z][a-z0-9_]*$") ~= nil
end

local function validAnimationId(id: string?): boolean
	return id == nil or id == "" or id:match("^rbxassetid://%d+$") ~= nil
end

return function(t)
	t.test("model data: unique snake_case ids, valid animation ids, sane numbers", function()
		local seen: { [string]: boolean } = {}
		for _, def in Models.models do
			t.truthy(isSnake(def.id), "bad model id " .. def.id)
			t.truthy(not seen[def.id], "duplicate model id " .. def.id)
			seen[def.id] = true
			t.truthy(def.scale == nil or def.scale > 0, def.id .. " scale")
			t.truthy(def.assetId == nil or def.assetId > 0, def.id .. " assetId")
			for _, state in ModelRegistry.states do
				t.truthy(validAnimationId(((def.animations or {}) :: any)[state]), def.id .. " animation " .. state)
			end
		end
		for _, state in ModelRegistry.states do
			t.truthy(validAnimationId((Models.defaults :: any)[state]), "default animation " .. state)
		end
	end)

	t.test("a unit modelId, when set, is a snake_case model id; otherwise the unit id is used", function()
		for _, unit in Units do
			if unit.modelId then
				t.truthy(isSnake(unit.modelId), unit.id .. " modelId")
			end
			t.eq(ModelRegistry.modelIdOf(unit), unit.modelId or unit.id)
		end
	end)

	t.test("animations fall back to the shared defaults state by state", function()
		local old = Models.defaults.idle
		Models.defaults.idle = "rbxassetid://111"
		ModelRegistry.register({ id = "zz_anim_test", animations = { attack = "rbxassetid://222", idle = "" } })
		local own = ModelRegistry.animationsFor("zz_anim_test")
		t.eq(own.attack, "rbxassetid://222")
		t.eq(own.idle, "rbxassetid://111", "an empty id falls back to the default")
		t.eq(own.walk, nil)
		t.eq(ModelRegistry.animationsFor("zz_no_entry").idle, "rbxassetid://111", "a template with no entry gets defaults")
		ModelRegistry.unregister("zz_anim_test")
		Models.defaults.idle = old
		t.eq(ModelRegistry.get("zz_anim_test"), nil)
	end)

	t.test("no model: the factory returns a coloured placeholder block that stands on its feet", function()
		t.eq(ModelFactory.has("zz_missing_model"), false)
		local visual = ModelFactory.create("zz_missing_model", { height = 6, tint = Color3.fromRGB(255, 0, 0) })
		t.truthy(visual.isPlaceholder)
		t.near(visual.primary.Size.Y, 6, 1e-6)
		t.near(visual.feetOffset, 3, 1e-6)
		t.eq(visual.primary.Color, Color3.fromRGB(255, 0, 0))
		visual:place(Vector3.new(10, 0, 5), Vector3.new(10, 0, 15))
		local pivot = visual.model:GetPivot()
		t.near(pivot.Position.X, 10, 1e-3)
		t.near(pivot.Position.Y, 3, 1e-3, "feet on the ground")
		t.near(pivot.Position.Z, 5, 1e-3)
		t.near(pivot.LookVector.Z, 1, 1e-3, "faces the look-at point")
		visual:destroy()
	end)

	t.test("a template in UnitModels is cloned, dressed, scaled to height and set on the ground", function()
		local template = jointedTemplate("zz_test_model")
		t.truthy(ModelFactory.has("zz_test_model"))
		local visual = ModelFactory.create("zz_test_model", { height = 4 })
		t.eq(visual.isPlaceholder, false)
		t.truthy(visual.model ~= template, "a clone, never the template")
		t.near(visual.model:GetExtentsSize().Y, 4, 0.05)
		t.eq(visual.primary.Anchored, true)
		t.eq((visual.model :: any).Arm.Anchored, false, "limbs stay free to animate")
		t.eq((visual.model :: any).Arm.CanCollide, false)
		t.eq(visual.model:FindFirstChildWhichIsA("Script"), nil, "default scripts are stripped")
		visual:place(Vector3.zero, nil)
		local box, size = visual.model:GetBoundingBox()
		t.near(box.Position.Y - size.Y / 2, 0, 0.05, "the feet touch y = 0")
		visual:destroy()
		template:Destroy()
	end)

	t.test("scale and facing from the model entry apply", function()
		local template = jointedTemplate("zz_scaled_model")
		ModelRegistry.register({ id = "zz_scaled_model", scale = 2, facing = 90 })
		local visual = ModelFactory.create("zz_scaled_model", { height = 4 })
		t.near(visual.model:GetExtentsSize().Y, 8, 0.1)
		t.near(visual.yaw, math.rad(90), 1e-9)
		visual:destroy()
		ModelRegistry.unregister("zz_scaled_model")
		template:Destroy()
	end)

	t.test("a model saved lying down is stood up by its rotation entry and stands on the ground", function()
		local model = Instance.new("Model")
		model.Name = "zz_lying_model"
		local body = Instance.new("Part") -- 6 studs long along Z: lying on its face
		body.Size = Vector3.new(2, 1, 6)
		body.Parent = model
		model.PrimaryPart = body
		model.Parent = templates()
		ModelRegistry.register({ id = "zz_lying_model", rotation = Vector3.new(90, 0, 0) })
		local visual = ModelFactory.create("zz_lying_model", { height = 4 })
		visual:place(Vector3.new(10, 0, 5), Vector3.new(10, 0, 50))
		local part = visual.model:FindFirstChildWhichIsA("BasePart") :: BasePart
		-- Upright: the long side is now vertical, the part is 4 studs tall in the world and rests on y = 0.
		t.near(part.Position.Y - part.Size.Z / 2, 0, 0.05, "the feet touch y = 0")
		t.near(part.Size.Z, 4, 0.05, "scaled to the standard height")
		t.truthy(math.abs(part.CFrame.UpVector:Dot(Vector3.new(0, 1, 0))) < 0.01, "the part's own up axis is horizontal")
		visual:destroy()
		ModelRegistry.unregister("zz_lying_model")
		model:Destroy()
	end)

	t.test("a model of unjoined parts is fully anchored so it holds together", function()
		local model = Instance.new("Model")
		model.Name = "zz_static_model"
		for i = 1, 3 do
			local part = Instance.new("Part")
			part.Size = Vector3.new(1, 2, 1)
			part.Position = Vector3.new(0, i * 2, 0)
			part.Parent = model
		end
		model.Parent = templates()
		local visual = ModelFactory.create("zz_static_model", {})
		for _, part in visual.model:GetChildren() do
			t.eq((part :: BasePart).Anchored, true)
		end
		visual:destroy()
		model:Destroy()
	end)

	t.test("the animator works with no animation ids: every state has a fallback", function()
		local visual = ModelFactory.create("zz_missing_model", {})
		local animator = UnitAnimator.new(visual, {})
		animator:setMoving(true)
		animator:setMoving(false)
		t.truthy(animator:attack() > 0)
		t.truthy(animator:cast() > 0)
		animator:hit()
		animator:victory()
		t.truthy(animator:die() > 0)
		animator:destroy()
		visual:destroy()
	end)

	t.test("a rigged model only gets an AnimationController when it has animation ids", function()
		local template = jointedTemplate("zz_rigged_model")
		local plain = ModelFactory.create("zz_rigged_model", {})
		local a = UnitAnimator.new(plain, {})
		t.eq(plain.model:FindFirstChildWhichIsA("AnimationController", true), nil)
		a:destroy()
		plain:destroy()
		local rigged = ModelFactory.create("zz_rigged_model", {})
		local b = UnitAnimator.new(rigged, { idle = "rbxassetid://1" })
		t.truthy(rigged.model:FindFirstChildWhichIsA("AnimationController", true) ~= nil)
		b:attack() -- no attack track, so the procedural lunge runs
		b:destroy()
		rigged:destroy()
		template:Destroy()
	end)

	t.test("the loader leaves models without an asset id alone and always provides the folder", function()
		t.eq(ModelLoader.load(), 0)
		t.truthy(ReplicatedStorage:FindFirstChild(ModelFactory.folderName) ~= nil)
	end)
end
