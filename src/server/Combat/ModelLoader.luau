--!strict
-- Makes sure ReplicatedStorage/UnitModels holds a template for every model that names a Roblox
-- asset id. Models synced from assets/models are already there; for the rest, InsertService loads
-- the asset once at server start. A failed load only logs a warning and that character keeps its
-- placeholder block.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Models = require(ReplicatedStorage.Shared.Data.Models)
local ModelRegistry = require(ReplicatedStorage.Shared.Util.ModelRegistry)
local ModelFactory = require(ReplicatedStorage.Shared.Visual.ModelFactory)

local ModelLoader = {}

-- Returns the UnitModels folder, creating it if the project did not.
local function folder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(ModelFactory.folderName)
	if existing then
		return existing :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = ModelFactory.folderName
	created.Parent = ReplicatedStorage
	return created
end

-- Loads asset-id models that have no template yet. Returns how many were loaded.
function ModelLoader.load(): number
	local templates = folder()
	local loaded = 0
	for _, def in Models.models do
		local name = ModelRegistry.templateName(def.id)
		if def.assetId and not templates:FindFirstChild(name) then
			local ok, container = pcall(function()
				return InsertService:LoadAsset(def.assetId :: number)
			end)
			local model = if ok then container:FindFirstChildWhichIsA("Model") else nil
			if model then
				model.Name = name
				model.Parent = templates
				container:Destroy()
				loaded += 1
			else
				warn(("[ModelLoader] could not load asset %d for model '%s'"):format(def.assetId, def.id))
			end
		end
	end
	return loaded
end

return ModelLoader
