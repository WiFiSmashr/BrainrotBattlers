--!strict
-- Builds the 3D look of a character from its model id (the unit's `modelId` or id). If a Model with
-- that name is in ReplicatedStorage/UnitModels it is cloned, made safe to display (no collisions, no
-- default scripts, anchored root), scaled to a standard height and given a pivot at its feet. If not,
-- a coloured block stands in, so a character without art still works everywhere.
-- Presentation only: nothing here touches gameplay state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelRegistry = require(script.Parent.Parent.Util.ModelRegistry)

local FOLDER_NAME = "UnitModels"
local DEFAULT_HEIGHT = 4 -- studs; one board cell is 4 studs wide
local PLACEHOLDER_COLOR = Color3.fromRGB(150, 150, 165)

export type Options = {
	height: number?, -- standard height in studs, before the model's own scale
	tint: Color3?, -- colour of the placeholder block
}

local Visual = {}
Visual.__index = Visual

export type Visual = typeof(setmetatable(
	{} :: {
		model: Model,
		primary: BasePart,
		modelId: string,
		isPlaceholder: boolean,
		height: number,
		feetOffset: number, -- distance from the model pivot down to the feet
		yaw: number, -- radians; the model's own "front" correction
		upright: CFrame, -- the rotation the model has when standing upright (its authored orientation, plus any `rotation` fix)
		basePivot: CFrame,
		offset: CFrame, -- a temporary offset animations apply on top of the placed pivot
	},
	Visual
))

-- Moves the model so its feet stand at `position`, turned to face `lookAt` (level with the ground).
function Visual.place(self: Visual, position: Vector3, lookAt: Vector3?)
	local target = position + Vector3.new(0, self.feetOffset, 0)
	if lookAt then
		local flat = Vector3.new(lookAt.X, target.Y, lookAt.Z)
		if (flat - target).Magnitude > 0.01 then
			self.basePivot = CFrame.lookAt(target, flat) * CFrame.Angles(0, self.yaw, 0) * self.upright
			self.model:PivotTo(self.basePivot * self.offset)
			return
		end
	end
	self.basePivot = CFrame.new(target) * (self.basePivot - self.basePivot.Position)
	self.model:PivotTo(self.basePivot * self.offset)
end

-- Sets the temporary animation offset (identity to clear it).
function Visual.setOffset(self: Visual, offset: CFrame)
	self.offset = offset
	self.model:PivotTo(self.basePivot * offset)
end

-- Removes the model.
function Visual.destroy(self: Visual)
	self.model:Destroy()
end

local ModelFactory = {}

-- The template Model for a model id, or nil.
local function findTemplate(modelId: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local template = if folder then folder:FindFirstChild(ModelRegistry.templateName(modelId)) else nil
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- True if a real model exists for this id (portraits and previews only use real models).
function ModelFactory.has(modelId: string): boolean
	return findTemplate(modelId) ~= nil
end

-- A clone of the template made safe to display. The root part is anchored; limbs stay free to animate
-- when the model has joints, otherwise every part is anchored so it holds together.
local function dress(template: Model): (Model, BasePart)
	local model = template:Clone()
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
	assert(root and root:IsA("BasePart"), "model has no parts: " .. template.Name)
	model.PrimaryPart = root

	local jointed = false
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- imported characters carry default Animate scripts; we drive animation ourselves
		elseif d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			jointed = true
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = false, false, false, true
			d.Anchored = (not jointed) or d == root
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.BreakJointsOnDeath = false
			pcall(function()
				d.EvaluateStateMachine = false
			end)
		end
	end
	return model, root :: BasePart
end

-- A coloured block standing in for a character without a model.
local function placeholder(height: number, tint: Color3?): (Model, BasePart)
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(height * 0.75, height, height * 0.75)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Color = tint or PLACEHOLDER_COLOR
	local model = Instance.new("Model")
	part.Parent = model
	model.PrimaryPart = part
	return model, part
end

-- Lowest point and height of a model measured on the world axes (the model's own bounding box is
-- aligned to its root part, which is wrong when that part is rotated).
local function worldBounds(model: Model): (number, number)
	local low, high = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local y = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y
						low, high = math.min(low, y), math.max(high, y)
					end
				end
			end
		end
	end
	return low, high - low
end

-- Builds a Visual for a model id. Never fails: a missing model becomes a placeholder block.
function ModelFactory.create(modelId: string, options: Options?): Visual
	local opts = options or {}
	local height = opts.height or DEFAULT_HEIGHT
	local def = ModelRegistry.get(modelId)
	local template = findTemplate(modelId)

	local model, root
	local fitted = height * ((def and def.scale) or 1)
	if template then
		model, root = dress(template)
		-- A model saved lying down is stood up by `rotation` (degrees about the world X, Y, Z axes).
		local tilt = def and def.rotation
		if tilt then
			local authored = model:GetPivot()
			local at = authored.Position
			model:PivotTo(CFrame.new(at) * CFrame.Angles(math.rad(tilt.X), math.rad(tilt.Y), math.rad(tilt.Z)) * (authored - at))
		end
		local _, current = worldBounds(model)
		if current > 0 then
			model:ScaleTo(model:GetScale() * fitted / current)
		end
	else
		model, root = placeholder(fitted, opts.tint)
	end

	-- Measure the pivot-to-feet distance after scaling so models of any pivot stand on the ground.
	local pivot = model:GetPivot()
	local lowest = worldBounds(model)
	local self = setmetatable({
		model = model,
		primary = root,
		modelId = modelId,
		isPlaceholder = template == nil,
		height = fitted,
		feetOffset = pivot.Position.Y - lowest,
		yaw = math.rad((def and def.facing) or 0),
		upright = pivot - pivot.Position,
		basePivot = pivot,
		offset = CFrame.identity,
	}, Visual)
	return self
end

-- The folder name templates live in (ReplicatedStorage/UnitModels).
ModelFactory.folderName = FOLDER_NAME


return ModelFactory
