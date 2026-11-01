--!strict
-- Author tool: shows a model in the workspace and cycles through its animations, so you can check a
-- new character without playing a match. From Studio's command bar while a game is running:
--   local P = require(game.ServerScriptService.Server.Combat.ModelPreview)
--   P.show("noodle_nugget")      -- loops idle, walk, attack, cast, hit, death
--   P.clear()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelRegistry = require(ReplicatedStorage.Shared.Util.ModelRegistry)
local ModelFactory = require(ReplicatedStorage.Shared.Visual.ModelFactory)
local UnitAnimator = require(ReplicatedStorage.Shared.Visual.UnitAnimator)

local FOLDER = "ModelPreview"
local STEP_SECONDS = 2

local ModelPreview = {}

local generation = 0

-- Removes the preview.
function ModelPreview.clear()
	generation += 1
	local folder = workspace:FindFirstChild(FOLDER)
	if folder then
		folder:Destroy()
	end
end

-- Shows `modelId` at `position` (default: in front of the origin) and loops its animations.
function ModelPreview.show(modelId: string, position: Vector3?)
	ModelPreview.clear()
	local mine = generation
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = workspace

	local at = position or Vector3.new(0, 0, -30)
	local visual = ModelFactory.create(modelId, {})
	visual.model.Parent = folder
	visual:place(at, at + Vector3.new(0, 0, 10)) -- face +Z, like the home team in a fight
	local animator = UnitAnimator.new(visual, ModelRegistry.animationsFor(modelId))
	print(("[ModelPreview] %s: %s"):format(modelId, if visual.isPlaceholder then "no model found, showing the placeholder block" else "model loaded"))

	task.spawn(function()
		while generation == mine do
			animator:setMoving(false)
			task.wait(STEP_SECONDS)
			animator:setMoving(true)
			task.wait(STEP_SECONDS)
			animator:setMoving(false)
			animator:attack()
			task.wait(STEP_SECONDS)
			animator:cast()
			task.wait(STEP_SECONDS)
			animator:hit()
			task.wait(STEP_SECONDS)
			local wait = animator:die()
			task.wait(wait + 1)
			if generation == mine then
				visual:setOffset(CFrame.identity)
				animator.offsetValue.Value = CFrame.identity
			end
		end
		animator:destroy()
	end)
end

return ModelPreview
