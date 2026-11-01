--!strict
-- Toasts: a short message for every rejected action, built from the server's reason code (UI-05).
-- Nothing fails silently.

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local StateStore = require(script.Parent.Parent.StateStore)
local Feedback = require(script.Parent.Feedback)

local SHOW_SECONDS = 2.2
local MAX_TOASTS = 3

local ToastLayer = {}

-- Builds the layer into `parent` and listens for toasts.
function ToastLayer.build(parent: Instance): Frame
	local layer = Components.create("Frame", {
		Name = "ToastLayer", Size = UDim2.fromOffset(700, 200), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
		BackgroundTransparency = 1, ZIndex = 80, Parent = parent,
	})
	Components.create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = layer,
	})
	local counter = 0

	StateStore.toast:connect(function(reason: string)
		counter += 1
		local message = Theme.toastText[reason] or reason
		local toast = Components.panel({
			Size = UDim2.fromOffset(560, 54), BackgroundColor3 = Color3.fromRGB(110, 40, 48), stroke = Theme.colors.bad, LayoutOrder = counter,
			ZIndex = 80, Parent = layer,
		})
		Components.label({ Size = UDim2.fromScale(1, 1), Text = message, TextSize = 26, ZIndex = 81, Parent = toast })
		Feedback.sound("toast")
		local live = {}
		for _, child in layer:GetChildren() do
			if child:IsA("Frame") then
				table.insert(live, child)
			end
		end
		while #live > MAX_TOASTS do
			table.remove(live, 1):Destroy()
		end
		task.delay(SHOW_SECONDS, function()
			toast:Destroy()
		end)
	end)

	return layer
end

return ToastLayer
