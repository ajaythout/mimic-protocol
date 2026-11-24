--!strict
--[[
	B — map building helpers for the Lune generator.

	All geometry is anchored. Every helper parents last so property writes do
	not trigger extra work. Orientation helpers avoid CFrame.lookAt (Lune's
	implementation differs from Roblox) and use explicit yaw angles instead.
]]

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Font = roblox.Font
local UDim2 = roblox.UDim2
local UDim = roblox.UDim

local B = {}

B.roblox = roblox
B.Vector3 = Vector3
B.CFrame = CFrame
B.Color3 = Color3
B.Enum = Enum

export type Style = {
	Color: any,
	Material: any,
	Transparency: number?,
	Reflectance: number?,
	CastShadow: boolean?,
	CanCollide: boolean?,
}

local function rgb(r: number, g: number, b: number)
	return Color3.fromRGB(r, g, b)
end
B.rgb = rgb

-- Palette -------------------------------------------------------------------
-- Charcoal, desaturated silver, cyan, electric blue, emergency red, a little
-- white. Accent colours are used sparingly; most surfaces are neutral metal.
B.Colors = {
	Charcoal = rgb(44, 47, 54),
	CharcoalDark = rgb(31, 33, 39),
	CharcoalDeep = rgb(22, 24, 29),
	Steel = rgb(84, 90, 100),
	Silver = rgb(132, 139, 150),
	SilverLight = rgb(176, 182, 191),
	OffWhite = rgb(206, 211, 218),
	Floor = rgb(62, 66, 74),
	FloorDark = rgb(46, 49, 56),
	Cyan = rgb(0, 205, 240),
	CyanSoft = rgb(120, 220, 245),
	Blue = rgb(45, 115, 255),
	Red = rgb(255, 48, 48),
	RedDim = rgb(70, 18, 20),
	Warm = rgb(255, 214, 170),
	FixtureWhite = rgb(225, 238, 255),
	Wood = rgb(128, 96, 66),
	WoodDark = rgb(92, 68, 46),
	Leaf = rgb(62, 104, 74),
	Glass = rgb(150, 196, 220),
	Specimen = rgb(80, 255, 190),
}

local C = B.Colors
local M = Enum.Material

B.Styles = {
	Wall = { Color = C.Charcoal, Material = M.Metal, CastShadow = false } :: Style,
	WallDark = { Color = C.CharcoalDark, Material = M.Metal, CastShadow = false } :: Style,
	WallConcrete = { Color = rgb(58, 60, 66), Material = M.Concrete, CastShadow = false } :: Style,
	WallPanelLight = { Color = C.SilverLight, Material = M.SmoothPlastic, CastShadow = false } :: Style,
	Trim = { Color = C.Steel, Material = M.Metal, CastShadow = false } :: Style,
	TrimLight = { Color = C.Silver, Material = M.Metal, CastShadow = false } :: Style,
	Floor = { Color = C.Floor, Material = M.DiamondPlate, CastShadow = false } :: Style,
	FloorDark = { Color = C.FloorDark, Material = M.Metal, CastShadow = false } :: Style,
	FloorTile = { Color = rgb(150, 156, 165), Material = M.SmoothPlastic, CastShadow = false } :: Style,
	Grate = { Color = rgb(40, 43, 49), Material = M.DiamondPlate, CastShadow = false } :: Style,
	Ceiling = { Color = C.CharcoalDeep, Material = M.Metal, CastShadow = false } :: Style,
	Glass = { Color = C.Glass, Material = M.Glass, Transparency = 0.65, CastShadow = false } :: Style,
	NeonCyan = { Color = C.Cyan, Material = M.Neon, CastShadow = false, CanCollide = false } :: Style,
	NeonBlue = { Color = C.Blue, Material = M.Neon, CastShadow = false, CanCollide = false } :: Style,
	NeonRed = { Color = C.Red, Material = M.Neon, CastShadow = false, CanCollide = false } :: Style,
	NeonWhite = { Color = C.FixtureWhite, Material = M.Neon, CastShadow = false, CanCollide = false } :: Style,
	Beacon = { Color = C.RedDim, Material = M.SmoothPlastic, CastShadow = false, CanCollide = false } :: Style,
	Hazard = { Color = rgb(190, 40, 40), Material = M.SmoothPlastic, CastShadow = false } :: Style,
	HazardWhite = { Color = C.OffWhite, Material = M.SmoothPlastic, CastShadow = false } :: Style,
	Invisible = {
		Color = C.Cyan,
		Material = M.SmoothPlastic,
		Transparency = 1,
		CastShadow = false,
		CanCollide = false,
	} :: Style,
}

-- Instances ---------------------------------------------------------------------

function B.new(className: string, props: { [string]: any }?, parent: any?): any
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function B.folder(parent: any, name: string): any
	return B.new("Folder", { Name = name }, parent)
end

function B.model(parent: any, name: string): any
	return B.new("Model", { Name = name }, parent)
end

local function applyStyle(part: any, style: Style)
	part.Color = style.Color
	part.Material = style.Material
	part.Transparency = style.Transparency or 0
	part.Reflectance = style.Reflectance or 0
	part.CastShadow = if style.CastShadow == nil then true else style.CastShadow
	part.CanCollide = if style.CanCollide == nil then true else style.CanCollide
end

local function basePart(
	className: string,
	parent: any,
	name: string,
	size: any,
	cframe: any,
	style: Style
): any
	local part = Instance.new(className)
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	applyStyle(part, style)
	if style.CanCollide == false then
		part.CanTouch = false
		part.CanQuery = false
	end
	part.Parent = parent
	return part
end

function B.part(parent: any, name: string, size: any, cframe: any, style: Style): any
	return basePart("Part", parent, name, size, cframe, style)
end

function B.wedge(parent: any, name: string, size: any, cframe: any, style: Style): any
	return basePart("WedgePart", parent, name, size, cframe, style)
end

-- Cylinder standing upright (Roblox cylinders run along the part's X axis).
function B.cylinderY(
	parent: any,
	name: string,
	height: number,
	diameter: number,
	cframe: any,
	style: Style
): any
	local part = basePart(
		"Part",
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		style
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Cylinder lying along the given CFrame's X axis.
function B.cylinderX(
	parent: any,
	name: string,
	length: number,
	diameter: number,
	cframe: any,
	style: Style
): any
	local part = basePart("Part", parent, name, Vector3.new(length, diameter, diameter), cframe, style)
	part.Shape = Enum.PartType.Cylinder
	return part
end

function B.ball(parent: any, name: string, diameter: number, cframe: any, style: Style): any
	local part = basePart("Part", parent, name, Vector3.new(diameter, diameter, diameter), cframe, style)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Lights ----------------------------------------------------------------------

function B.pointLight(
	parent: any,
	color: any,
	brightness: number,
	range: number,
	tags: { string }?,
	shadows: boolean?
): any
	local light = B.new("PointLight", {
		Color = color,
		Brightness = brightness,
		Range = range,
		Shadows = shadows == true,
	})
	light:SetAttribute("BaseBrightness", brightness)
	for _, tag in tags or { "FacilityLight" } do
		light:AddTag(tag)
	end
	light.Parent = parent
	return light
end

function B.spotLight(
	parent: any,
	color: any,
	brightness: number,
	range: number,
	angle: number,
	face: any
): any
	local light = B.new("SpotLight", {
		Color = color,
		Brightness = brightness,
		Range = range,
		Angle = angle,
		Face = face,
		Shadows = false,
	})
	light:SetAttribute("BaseBrightness", brightness)
	light:AddTag("FacilityLight")
	light.Parent = parent
	return light
end

-- Orientation -----------------------------------------------------------------

-- Yaw so that a part's Front face (-Z) points along the horizontal normal.
function B.yawFacing(nx: number, nz: number): number
	return math.atan2(-nx, -nz)
end

function B.facing(position: any, nx: number, nz: number): any
	return CFrame.new(position) * CFrame.Angles(0, B.yawFacing(nx, nz), 0)
end

-- Text ------------------------------------------------------------------------

B.Fonts = {
	Display = Font.new("rbxasset://fonts/families/Michroma.json"),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium),
}

export type SignOptions = {
	textColor: any?,
	background: Style?,
	font: any?,
	pixelsPerStud: number?,
	face: any?,
	label: string?,
	glow: boolean?,
	alignLeft: boolean?,
}

--[[
	A flat sign: a thin plate whose Front face carries a SurfaceGui. `cframe`
	should face the viewer (use B.facing).
]]
function B.sign(parent: any, name: string, size: any, cframe: any, text: string, options: SignOptions?): any
	local opts: SignOptions = options or {}
	local plate = B.part(parent, name, size, cframe, opts.background or B.Styles.WallDark)
	plate.CanCollide = false

	local gui = B.new("SurfaceGui", {
		Name = "Display",
		Face = opts.face or Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = opts.pixelsPerStud or 40,
		LightInfluence = if opts.glow == false then 1 else 0,
		Brightness = 1.4,
		ClipsDescendants = true,
		AlwaysOnTop = false,
	})
	local label = B.new("TextLabel", {
		Name = opts.label or "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextScaled = true,
		TextWrapped = true,
		FontFace = opts.font or B.Fonts.Display,
		TextColor3 = opts.textColor or C.CyanSoft,
		TextXAlignment = if opts.alignLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
	})
	B.new("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.12, 0),
		PaddingBottom = UDim.new(0.12, 0),
	}, label)
	label.Parent = gui
	gui.Parent = plate
	return plate
end

-- Utility -----------------------------------------------------------------------

function B.tag(instance: any, ...: string)
	for _, tag in { ... } do
		instance:AddTag(tag)
	end
	return instance
end

function B.attrs(instance: any, attributes: { [string]: any })
	for key, value in attributes do
		instance:SetAttribute(key, value)
	end
	return instance
end

return B
