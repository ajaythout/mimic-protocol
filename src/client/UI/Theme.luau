--!strict
--[[
	Theme — design tokens for every screen. Change colours, type and motion
	here rather than in individual controllers.

	Visual language: dark glass terminal panels, hairline cyan strokes, corner
	brackets, wide display type for headings, monospace for live readouts.
]]

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(11, 14, 19),
	PanelRaised = Color3.fromRGB(19, 24, 31),
	PanelHover = Color3.fromRGB(26, 33, 42),
	Stroke = Color3.fromRGB(0, 205, 240),
	StrokeMuted = Color3.fromRGB(58, 72, 88),
	Text = Color3.fromRGB(232, 240, 248),
	TextMuted = Color3.fromRGB(138, 152, 170),
	TextDim = Color3.fromRGB(92, 104, 120),
	Cyan = Color3.fromRGB(0, 205, 240),
	Blue = Color3.fromRGB(45, 115, 255),
	Red = Color3.fromRGB(255, 64, 72),
	RedSoft = Color3.fromRGB(255, 120, 110),
	Teal = Color3.fromRGB(90, 230, 205),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
}

Theme.RoleColors = {
	Survivor = Theme.Colors.Cyan,
	Mimic = Theme.Colors.Red,
}

Theme.SeverityColors = {
	Info = Theme.Colors.Cyan,
	Warning = Theme.Colors.RedSoft,
	Critical = Theme.Colors.Red,
	Success = Theme.Colors.Teal,
}

Theme.Transparency = {
	Panel = 0.16,
	PanelSoft = 0.35,
	Stroke = 0.45,
	Overlay = 0.08,
}

Theme.Fonts = {
	Display = Font.new("rbxasset://fonts/families/Michroma.json"),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	BodyBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium),
	MonoBold = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

Theme.TextSize = {
	Caption = 12,
	Body = 15,
	Label = 13,
	Heading = 17,
	Title = 30,
	Hero = 64,
	Timer = 28,
}

Theme.Radius = UDim.new(0, 4)

Theme.Motion = {
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Medium = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Linear = TweenInfo.new(1, Enum.EasingStyle.Linear),
}

-- Reference resolution the layouts are authored against; UIScale adapts it.
Theme.ReferenceSize = Vector2.new(1280, 720)
Theme.MinScale = 0.62
Theme.MaxScale = 1.2

-- Draw order (ScreenGui.DisplayOrder).
Theme.Layers = {
	World = 0,
	Hud = 10,
	Lobby = 15,
	Announcements = 30,
	Reveal = 50,
	Results = 60,
}

return Theme
