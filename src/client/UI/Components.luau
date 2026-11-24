--!strict
--[[
	Components — small constructors for the UI design system. Controllers
	compose these into named, inspectable Instance trees under PlayerGui.

	Every constructor takes a props table whose keys are applied as Instance
	properties (so callers can override anything) plus a few design-system
	options documented per function.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local Components = {}

type Props = { [string]: any }

local function apply(instance: Instance, props: Props?)
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		if props.Parent then
			instance.Parent = props.Parent
		end
	end
end

function Components.create(className: string, props: Props?): any
	local instance = Instance.new(className)
	apply(instance, props)
	return instance
end

function Components.corner(parent: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.Radius
	corner.Parent = parent
	return corner
end

function Components.stroke(
	parent: Instance,
	color: Color3?,
	transparency: number?,
	thickness: number?
): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Transparency = transparency or Theme.Transparency.Stroke
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Components.padding(parent: Instance, all: number, horizontal: number?): UIPadding
	local padding = Instance.new("UIPadding")
	local h = UDim.new(0, horizontal or all)
	local v = UDim.new(0, all)
	padding.PaddingLeft = h
	padding.PaddingRight = h
	padding.PaddingTop = v
	padding.PaddingBottom = v
	padding.Parent = parent
	return padding
end

function Components.list(
	parent: Instance,
	padding: number,
	direction: Enum.FillDirection?,
	align: Enum.HorizontalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

--[[
	ScreenGui with a UIScale that tracks the viewport so layouts authored at
	1280x720 stay proportional on phones, tablets and large monitors.
]]
function Components.screen(name: string, displayOrder: number, fullscreen: boolean?): (ScreenGui, UIScale)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if fullscreen then
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
	else
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end

	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		local ratio = math.min(size.X / Theme.ReferenceSize.X, size.Y / Theme.ReferenceSize.Y)
		scale.Scale = math.clamp(ratio, Theme.MinScale, Theme.MaxScale)
	end
	update()
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, scale
end

-- Panel: dark glass frame with hairline stroke and sci-fi corner brackets.
function Components.panel(
	props: Props,
	options: { brackets: boolean?, accent: Color3?, stroke: boolean? }?
): Frame
	local frame = Components.create("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
	})
	apply(frame, props)
	Components.corner(frame)
	local opts: { brackets: boolean?, accent: Color3?, stroke: boolean? } = options or {}
	if opts.stroke ~= false then
		Components.stroke(frame, opts.accent or Theme.Colors.StrokeMuted, 0.2)
	end
	if opts.brackets ~= false then
		Components.brackets(frame, opts.accent or Theme.Colors.Stroke)
	end
	return frame
end

-- Four L-shaped corner accents drawn just outside a frame.
function Components.brackets(parent: GuiObject, color: Color3, length: number?, thickness: number?): Frame
	local holder = Components.create("Frame", {
		Name = "Brackets",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = (parent.ZIndex or 1) + 1,
		Parent = parent,
	})
	local len = length or 10
	local thick = thickness or 2
	local corners: { { anchor: Vector2, position: UDim2 } } = {
		{ anchor = Vector2.new(0, 0), position = UDim2.new(0, -1, 0, -1) },
		{ anchor = Vector2.new(1, 0), position = UDim2.new(1, 1, 0, -1) },
		{ anchor = Vector2.new(0, 1), position = UDim2.new(0, -1, 1, 1) },
		{ anchor = Vector2.new(1, 1), position = UDim2.new(1, 1, 1, 1) },
	}
	for _, corner in corners do
		local anchor, position = corner.anchor, corner.position
		for _, horizontal in { true, false } do
			Components.create("Frame", {
				Name = "Bracket",
				AnchorPoint = anchor,
				Position = position,
				Size = if horizontal then UDim2.fromOffset(len, thick) else UDim2.fromOffset(thick, len),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = holder.ZIndex,
				Parent = holder,
			})
		end
	end
	return holder
end

export type LabelStyle = "Display" | "Body" | "BodyBold" | "Mono" | "MonoBold"

function Components.label(props: Props, style: LabelStyle?): TextLabel
	local label = Components.create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts[style or "Body"],
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
	})
	apply(label, props)
	return label
end

--[[
	Button with hover/press feedback. Works with mouse, touch and gamepad
	(Selectable = true so gamepad selection can focus it).
]]
function Components.button(props: Props, options: { accent: Color3? }?): (TextButton, UIStroke)
	local accent = (options and options.accent) or Theme.Colors.Cyan
	local button = Components.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Colors.Text,
		Selectable = true,
	})
	apply(button, props)
	Components.corner(button)
	local stroke = Components.stroke(button, accent, 0.35, 1)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function setHover(on: boolean)
		TweenService:Create(button, Theme.Motion.Fast, {
			BackgroundColor3 = if on then Theme.Colors.PanelHover else Theme.Colors.PanelRaised,
		}):Play()
		TweenService:Create(stroke, Theme.Motion.Fast, { Transparency = if on then 0 else 0.35 }):Play()
	end
	button.MouseEnter:Connect(function()
		setHover(true)
	end)
	button.MouseLeave:Connect(function()
		setHover(false)
	end)
	button.SelectionGained:Connect(function()
		setHover(true)
	end)
	button.SelectionLost:Connect(function()
		setHover(false)
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Theme.Motion.Fast, { Scale = 0.96 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Theme.Motion.Fast, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, Theme.Motion.Fast, { Scale = 1 }):Play()
	end)
	return button, stroke
end

-- Thin horizontal progress bar; returns the frame and its fill.
function Components.progress(props: Props, color: Color3?): (Frame, Frame)
	local track = Components.create("Frame", {
		BackgroundColor3 = Theme.Colors.StrokeMuted,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	})
	apply(track, props)
	local fill = Components.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = color or Theme.Colors.Cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	return track, fill
end

function Components.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- Formats seconds as M:SS.
function Components.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Components
