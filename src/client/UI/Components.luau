--!strict
-- Small helpers for building plain Roblox Instances in code (UI-02). No third-party UI libraries.

local Theme = require(script.Parent.Theme)

local Components = {}

-- Creates an Instance, applies `props`, parents the optional children, and parents it last so the
-- engine does not recompute layout after every property.
function Components.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

-- Rounded corners, optional stroke.
function Components.style(inst: GuiObject, radius: number?, stroke: Color3?, thickness: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = inst
	if stroke then
		local line = Instance.new("UIStroke")
		line.Color = stroke
		line.Thickness = thickness or 2
		line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		line.Parent = inst
	end
end

-- A filled panel with rounded corners.
function Components.panel(props: { [string]: any }): Frame
	local p = table.clone(props)
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.colors.panel
	p.BorderSizePixel = 0
	local radius, stroke = p.radius, p.stroke
	p.radius, p.stroke = nil, nil
	local frame = Components.create("Frame", p)
	Components.style(frame, radius, stroke)
	return frame
end

-- A transparent text label.
function Components.label(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.BackgroundTransparency = if p.BackgroundTransparency == nil then 1 else p.BackgroundTransparency
	p.Font = p.Font or Theme.font
	p.TextColor3 = p.TextColor3 or Theme.colors.text
	p.TextScaled = if p.TextScaled == nil then false else p.TextScaled
	p.TextSize = p.TextSize or 28
	p.BorderSizePixel = 0
	return Components.create("TextLabel", p)
end

-- A tappable button. `onTap` runs on tap or click. Touch targets are never smaller than 44 x 44
-- reference pixels (UI-03).
function Components.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	local onTap = p.onTap
	local radius = p.radius
	p.onTap, p.radius = nil, nil
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.colors.panelLight
	p.Font = p.Font or Theme.font
	p.TextColor3 = p.TextColor3 or Theme.colors.text
	p.TextSize = p.TextSize or 28
	p.BorderSizePixel = 0
	p.AutoButtonColor = if p.AutoButtonColor == nil then true else p.AutoButtonColor
	local size: UDim2? = p.Size
	if size then
		p.Size = UDim2.new(size.X.Scale, if size.X.Scale == 0 then math.max(size.X.Offset, Theme.minTouch) else size.X.Offset,
			size.Y.Scale, if size.Y.Scale == 0 then math.max(size.Y.Offset, Theme.minTouch) else size.Y.Offset)
	end
	local button = Components.create("TextButton", p)
	Components.style(button, radius)
	if onTap then
		button.Activated:Connect(onTap)
	end
	return button
end

export type Bar = { frame: Frame, fill: Frame, label: TextLabel, set: (ratio: number, text: string?) -> () }

-- A horizontal progress bar with an optional text overlay.
function Components.bar(props: { [string]: any }): Bar
	local fillColor: Color3 = props.fillColor or Theme.colors.good
	local frame = Components.panel({
		Size = props.Size, Position = props.Position, AnchorPoint = props.AnchorPoint, Parent = props.Parent,
		BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(20, 20, 30), radius = props.radius or 6, ZIndex = props.ZIndex,
	})
	frame.ClipsDescendants = true
	local fill = Components.create("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = fillColor, BorderSizePixel = 0, Parent = frame, ZIndex = (props.ZIndex or 1),
	})
	local label = Components.label({
		Size = UDim2.fromScale(1, 1), Text = "", TextSize = props.TextSize or 18, Parent = frame, ZIndex = (props.ZIndex or 1) + 1,
	})
	local function set(ratio: number, text: string?)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		if text then
			label.Text = text
		end
	end
	return { frame = frame, fill = fill, label = label, set = set }
end

-- Removes every child of `parent` that is a GuiObject or layout helper we created for rendering.
function Components.clear(parent: Instance, keep: { [string]: boolean }?)
	for _, child in parent:GetChildren() do
		if not (keep and keep[child.ClassName]) then
			child:Destroy()
		end
	end
end

-- A scrolling container with a vertical list layout.
function Components.scroll(props: { [string]: any }): ScrollingFrame
	local p = table.clone(props)
	p.BackgroundTransparency = if p.BackgroundTransparency == nil then 1 else p.BackgroundTransparency
	p.BorderSizePixel = 0
	p.ScrollBarThickness = 8
	p.CanvasSize = UDim2.new()
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	return Components.create("ScrollingFrame", p)
end

return Components
