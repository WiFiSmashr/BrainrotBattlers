--!strict
-- Moves the player's camera to their fight. In your own fight (and ghost and monster fights) the
-- camera is behind the home side; as the away player in PvP it is behind the away side, so your own
-- team is always nearest the camera (CMB-02, PAIR-03). While a fight is on, the camera is held in
-- place every frame, so nothing else (Roblox's own camera scripts included) can pull it away.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CameraConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.CameraConfig)

local CombatCamera = {}

local goal: CFrame? = nil
local viewOrigin: Vector3? = nil
local viewHome = true
local holdFrom = 0 -- os.clock() time after which the pose is simply held
local watchdog: RBXScriptConnection? = nil

-- Where the camera should sit and look for an arena centred at `origin`.
function CombatCamera.pose(origin: Vector3, viewerIsHome: boolean): CFrame
	local pitch = math.rad(CameraConfig.pitchDegrees)
	local behind = if viewerIsHome then -1 else 1 -- home units are at -Z of the centre, away units at +Z
	local position = origin + Vector3.new(0, CameraConfig.distance * math.sin(pitch), behind * CameraConfig.distance * math.cos(pitch))
	local aim = origin + Vector3.new(0, CameraConfig.lookHeight, 0)
	return CFrame.lookAt(position, aim) * CFrame.Angles(-math.rad(CameraConfig.uiShiftDegrees), 0, 0)
end

-- Takes over the camera and glides to the fight.
function CombatCamera.enter(origin: Vector3, viewerIsHome: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if viewOrigin == origin and viewHome == viewerIsHome and goal then
		return -- already there
	end
	local target = CombatCamera.pose(origin, viewerIsHome)
	local first = goal == nil
	goal = target
	viewOrigin, viewHome = origin, viewerIsHome
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CameraConfig.fieldOfView
	if first then
		camera.CFrame = target * CFrame.new(0, 14, 0) -- start a little high and settle down
	end
	TweenService:Create(camera, TweenInfo.new(CameraConfig.transitionSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
	holdFrom = os.clock() + CameraConfig.transitionSeconds + 0.1

	if not watchdog then
		watchdog = RunService.RenderStepped:Connect(function()
			local current = workspace.CurrentCamera
			if not current or not goal then
				return
			end
			if current.CameraType ~= Enum.CameraType.Scriptable then
				current.CameraType = Enum.CameraType.Scriptable
			end
			if os.clock() >= holdFrom then
				current.CFrame = goal
			end
		end)
	end
end

-- The arena the camera is on (its centre and whether it sits behind the home side), or nil.
function CombatCamera.view(): (Vector3?, boolean)
	return viewOrigin, viewHome
end

-- Gives the camera back to Roblox.
function CombatCamera.exit()
	goal = nil
	viewOrigin = nil
	if watchdog then
		watchdog:Disconnect()
		watchdog = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

return CombatCamera
