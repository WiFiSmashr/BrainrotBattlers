--!strict
-- One input path for tap and drag, for mouse and touch (UI-04). A press that barely moves is a tap;
-- a press that moves becomes a drag with a ghost, and on release the drop target under the pointer
-- gets the payload. Hit testing uses GetGuiObjectsAtPosition, so UIScale and insets need no maths.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Signal)

local DRAG_THRESHOLD = 14 -- pixels of movement before a press becomes a drag

export type Payload = { kind: string, [string]: any }
export type TargetOptions = { accepts: (Payload) -> boolean, onDrop: (Payload) -> () }

local DragController = {
	-- Set by the 3D Prep view: called when something dragged from the HUD (an item) is released over no
	-- HUD target, so it can be dropped onto a unit standing in the world.
	worldDrop = nil :: ((payload: Payload, position: Vector2) -> ())?,
	dragging = false,
	finished = Signal.new() :: any, -- fired after a drag ends, so panels can re-render
}

local targets: { [GuiObject]: TargetOptions } = {}
local active: any = nil -- the press in progress: object, input, payload, onTap, start, ghost, makeGhost, screen

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Registers a drop target; it is forgotten when the object is destroyed.
function DragController.registerTarget(object: GuiObject, options: TargetOptions)
	targets[object] = options
	object.Destroying:Connect(function()
		targets[object] = nil
	end)
end

-- The registered target under a screen position that accepts the payload, or nil.
local function targetAt(position: Vector2, payload: Payload, ghost: GuiObject?): TargetOptions?
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, object in gui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if object ~= ghost and not (ghost and object:IsDescendantOf(ghost)) then
			local cursor: Instance? = object
			while cursor and cursor ~= gui do
				local options = targets[cursor :: GuiObject]
				if options and options.accepts(payload) then
					return options
				end
				cursor = cursor.Parent
			end
		end
	end
	return nil
end

-- Drops `payload` on whichever HUD target is under `position` (for example the shop). Returns true if a
-- target took it. Used by the 3D Prep view when a unit in the world is released.
function DragController.dropAt(position: Vector2, payload: Payload): boolean
	local target = targetAt(position, payload, nil)
	if target then
		target.onDrop(payload)
		return true
	end
	return false
end

local function finish()
	if active and active.ghost then
		active.ghost:Destroy()
	end
	active = nil
	DragController.dragging = false
	DragController.finished:fire()
end

-- Makes `object` tappable and, when `payload` is given, draggable. `onTap` runs for a tap; the
-- payload goes to the drop target on release. `makeGhost` builds the drag preview (default: a clone).
function DragController.attach(object: GuiObject, payload: Payload?, onTap: (() -> ())?, makeGhost: (() -> GuiObject)?)
	object.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or active then
			return
		end
		local screen = object:FindFirstAncestorOfClass("ScreenGui")
		if not screen then
			return
		end
		active = {
			object = object, input = input, payload = payload, onTap = onTap, screen = screen,
			start = Vector2.new(input.Position.X, input.Position.Y), ghost = nil,
			makeGhost = makeGhost or function()
				local ghost = object:Clone()
				ghost.Size = UDim2.fromOffset(object.AbsoluteSize.X, object.AbsoluteSize.Y)
				ghost.BackgroundTransparency = 0.25
				return ghost
			end,
		}
	end)
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	local a = active
	if not a or not a.payload then
		return
	end
	local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
	if not isMouse and input ~= a.input then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if not DragController.dragging then
		if (position - a.start).Magnitude < DRAG_THRESHOLD then
			return
		end
		DragController.dragging = true
		local ghost: GuiObject = a.makeGhost()
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Active = false
		ghost.ZIndex = 1000
		ghost.Parent = a.screen
		a.ghost = ghost
	end
	a.ghost.Position = UDim2.fromOffset(position.X, position.Y)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local a = active
	if not a or not isPress(input) then
		return
	end
	if input.UserInputType ~= a.input.UserInputType then
		return
	end
	if DragController.dragging then
		local target = targetAt(Vector2.new(input.Position.X, input.Position.Y), a.payload, a.ghost)
		if target then
			target.onDrop(a.payload)
		elseif DragController.worldDrop then
			DragController.worldDrop(a.payload, Vector2.new(input.Position.X, input.Position.Y))
		end
		finish()
	else
		local onTap = a.onTap
		active = nil
		if onTap then
			onTap()
		end
	end
end)

return DragController
