--!strict
-- A small 3D portrait of a character for the shop, bench, board and unit card. It only appears when the
-- character has a real model; otherwise the caller keeps its coloured tile, so nothing changes until
-- art exists. Portraits are a still pose: the HUD rebuilds its tiles on every snapshot, so animating them
-- would load animation tracks over and over (D-62).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ModelFactory = require(Shared.Visual.ModelFactory)

local CAMERA_BACK = 7.5 -- studs in front of the model
local CAMERA_HEIGHT = 2.4

local UnitPortrait = {}

-- Fills `parent` with a ViewportFrame showing the unit's model, facing the camera. Returns the frame,
-- or nil if the unit has no model. `zIndex` keeps it under the text drawn over it.
function UnitPortrait.attach(parent: GuiObject, unit: Types.UnitDef, zIndex: number): ViewportFrame?
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
