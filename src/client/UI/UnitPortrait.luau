--!strict
-- A character's picture for the shop and the unit card. If the character has artwork
-- (Shared/Data/Portraits, docs/PORTRAITS.md) that image is shown. Otherwise, if it has a real model, a small
-- 3D portrait is shown; otherwise the caller keeps its coloured tile, so nothing changes until art exists.
-- Model portraits are a still pose: the HUD rebuilds its tiles on every snapshot, so animating them would
-- load animation tracks over and over (D-62).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Portraits = require(Shared.Data.Portraits)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ModelFactory = require(Shared.Visual.ModelFactory)

local CAMERA_BACK = 7.5 -- studs in front of the model
local CAMERA_HEIGHT = 2.4

local UnitPortrait = {}

-- True if the character has custom artwork.
function UnitPortrait.hasArt(unit: Types.UnitDef): boolean
	return Portraits[unit.id] ~= nil
end

-- Fills `parent` with the character's artwork or model portrait. Returns the new instance, or nil if the
-- character has neither. `zIndex` keeps it under the text drawn over it; `fit` shows the whole image
-- instead of cropping it to fill (the unit card).
function UnitPortrait.attach(parent: GuiObject, unit: Types.UnitDef, zIndex: number, fit: boolean?): GuiObject?
	local art = Portraits[unit.id]
	if art then
		local image = Instance.new("ImageLabel")
		image.Name = "Art"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = art
		image.ScaleType = if fit then Enum.ScaleType.Fit else Enum.ScaleType.Crop
		image.ZIndex = zIndex
		image.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = image
		image.Parent = parent
		return image
	end

	local modelId = ModelRegistry.modelIdOf(unit)
	if not ModelFactory.has(modelId) then
		return nil
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.ZIndex = zIndex
	viewport.Active = false

	local visual = ModelFactory.create(modelId, {})
	visual:place(Vector3.zero, Vector3.new(0, 0, CAMERA_BACK)) -- turn toward the camera
	visual.model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, CAMERA_HEIGHT, CAMERA_BACK), Vector3.new(0, visual.height / 2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	viewport.Parent = parent
	return viewport
end

return UnitPortrait
