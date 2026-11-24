--!strict
--[[
	Props — the reusable prop library.

	Every prop is built by exactly one function, used both for the template in
	ReplicatedStorage.Assets.Props and for every copy placed in the facility, so
	a Mimic disguised as a prop is visually identical to the real ones.

	Model contract (relied on by the Object Shift system in Phase 2):
	  • Model.Name == PropId, PrimaryPart "Body" (the main collision volume)
	  • Attributes: PropId (string), DisplayName (string),
	    Transformable (boolean), Height (number, studs)
	  • Placed transformable props are tagged "MimicProp"
	  • Builders take an origin CFrame at floor level; local -Z is the front.
]]

local B = require("./B")

local CFrame = B.CFrame
local Vector3 = B.Vector3
local C = B.Colors
local S = B.Styles
local rgb = B.rgb
local M = B.Enum.Material

local Props = {}

export type Definition = {
	id: string,
	displayName: string,
	transformable: boolean,
	height: number,
	build: (parent: any, origin: any) -> any,
}

local function style(color: any, material: any, extra: { [string]: any }?): B.Style
	local s: any = { Color = color, Material = material, CastShadow = true }
	if extra then
		for k, v in extra do
			s[k] = v
		end
	end
	return s
end

local function detail(base: B.Style): B.Style
	local copy: any = table.clone(base :: any)
	copy.CanCollide = false
	return copy
end

local V = Vector3.new
local CF = CFrame.new
local function rot(x: number, y: number, z: number)
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Shared materials for props.
local P = {
	DarkMetal = style(rgb(52, 56, 64), M.Metal),
	Gunmetal = style(rgb(72, 78, 88), M.Metal),
	SilverMetal = style(C.Silver, M.Metal),
	LightPanel = style(C.OffWhite, M.SmoothPlastic),
	Fabric = style(rgb(48, 52, 60), M.Fabric),
	Plastic = style(rgb(78, 92, 110), M.SmoothPlastic),
	PlasticDark = style(rgb(46, 54, 66), M.SmoothPlastic),
	Wood = style(C.Wood, M.WoodPlanks),
	WoodFrame = style(C.WoodDark, M.Wood),
	Screen = style(rgb(196, 226, 244), M.Neon, { Transparency = 0.2, CastShadow = false }),
	ScreenBlue = style(rgb(60, 140, 255), M.Neon, { CastShadow = false }),
	LedCyan = style(C.Cyan, M.Neon, { CastShadow = false }),
	LedBlue = style(C.Blue, M.Neon, { CastShadow = false }),
	LedRed = style(C.Red, M.Neon, { CastShadow = false }),
	Glass = style(C.Glass, M.Glass, { Transparency = 0.55, CastShadow = false }),
	Leaf = style(C.Leaf, M.Grass),
	Soil = style(rgb(58, 44, 34), M.Slate),
	BarrelBlue = style(rgb(58, 82, 112), M.Metal),
	Rubber = style(rgb(28, 29, 32), M.Rubber),
	Toolbox = style(rgb(140, 40, 44), M.SmoothPlastic),
	BucketBlue = style(rgb(70, 108, 140), M.SmoothPlastic),
	Mop = style(rgb(200, 202, 196), M.Fabric),
	Sheet = style(rgb(225, 230, 236), M.Fabric),
}

-- Starts a prop model; returns the model and a local-space part helper.
local function begin(parent: any, id: string, origin: any)
	local model = B.model(parent, id)
	local function add(name: string, size: any, localCF: any, s: B.Style): any
		return B.part(model, name, size, origin * localCF, s)
	end
	local function cylY(name: string, height: number, diameter: number, localCF: any, s: B.Style): any
		return B.cylinderY(model, name, height, diameter, origin * localCF, s)
	end
	local function cylX(name: string, length: number, diameter: number, localCF: any, s: B.Style): any
		return B.cylinderX(model, name, length, diameter, origin * localCF, s)
	end
	local function ball(name: string, diameter: number, localCF: any, s: B.Style): any
		return B.ball(model, name, diameter, origin * localCF, s)
	end
	return model, add, cylY, cylX, ball
end

local definitions: { [string]: Definition } = {}
local order: { string } = {}

local function define(
	id: string,
	displayName: string,
	transformable: boolean,
	height: number,
	build: (any, any, any) -> any
)
	definitions[id] = {
		id = id,
		displayName = displayName,
		transformable = transformable,
		height = height,
		build = function(parent: any, origin: any): any
			local model, body = build(parent, origin, id)
			model.PrimaryPart = body
			B.attrs(model, {
				PropId = id,
				DisplayName = displayName,
				Transformable = transformable,
				Height = height,
			})
			return model
		end,
	}
	table.insert(order, id)
end

-- ===========================================================================
-- Transformable props (Object Shift disguises)
-- ===========================================================================

define("OfficeChair", "Office Chair", true, 4.6, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	cylY("Hub", 0.4, 0.7, CF(0, 0.45, 0), detail(P.DarkMetal))
	for i = 0, 4 do
		add("Leg", V(0.25, 0.2, 1.3), rot(0, i * 72, 0) * CF(0, 0.3, -0.65), detail(P.DarkMetal))
		add("Caster", V(0.3, 0.3, 0.3), rot(0, i * 72, 0) * CF(0, 0.15, -1.25), detail(P.Rubber))
	end
	cylY("Column", 1.4, 0.3, CF(0, 1.3, 0), detail(P.SilverMetal))
	local body = add("Body", V(2.2, 0.45, 2.2), CF(0, 2.15, 0), P.Fabric)
	add("Back", V(2.0, 2.3, 0.35), CF(0, 3.45, 1.0) * rot(-8, 0, 0), detail(P.Fabric))
	add("ArmL", V(0.25, 0.7, 1.6), CF(-1.1, 2.6, 0.1), detail(P.DarkMetal))
	add("ArmR", V(0.25, 0.7, 1.6), CF(1.1, 2.6, 0.1), detail(P.DarkMetal))
	return m, body
end)

define("WoodenCrate", "Wooden Crate", true, 4, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(3.8, 3.8, 3.8), CF(0, 2, 0), P.Wood)
	for _, x in { -1.8, 1.8 } do
		for _, z in { -1.8, 1.8 } do
			add("Post", V(0.45, 4, 0.45), CF(x, 2, z), detail(P.WoodFrame))
		end
	end
	for _, y in { 0.25, 3.75 } do
		add("RimF", V(4, 0.45, 0.45), CF(0, y, -1.8), detail(P.WoodFrame))
		add("RimB", V(4, 0.45, 0.45), CF(0, y, 1.8), detail(P.WoodFrame))
	end
	add("BraceF", V(0.4, 4.9, 0.3), CF(0, 2, -1.95) * rot(0, 0, 45), detail(P.WoodFrame))
	add("BraceB", V(0.4, 4.9, 0.3), CF(0, 2, 1.95) * rot(0, 0, -45), detail(P.WoodFrame))
	return m, body
end)

define("MetalCrate", "Metal Crate", true, 3.6, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(5, 3.2, 3.4), CF(0, 1.7, 0), P.Gunmetal)
	add("Lid", V(5.2, 0.35, 3.6), CF(0, 3.45, 0), detail(P.DarkMetal))
	add("Skid", V(5.2, 0.3, 3.6), CF(0, 0.15, 0), detail(P.DarkMetal))
	for _, x in { -2.45, 2.45 } do
		for _, z in { -1.65, 1.65 } do
			add("Bumper", V(0.4, 3.5, 0.4), CF(x, 1.75, z), detail(P.DarkMetal))
		end
	end
	add("Panel", V(2.2, 1.5, 0.12), CF(0, 1.8, -1.74), detail(P.SilverMetal))
	add("Label", V(1.2, 0.28, 0.06), CF(0, 2.75, -1.79), detail(P.LedCyan))
	add("HandleL", V(0.15, 0.3, 1.4), CF(-2.62, 2.2, 0), detail(P.SilverMetal))
	add("HandleR", V(0.15, 0.3, 1.4), CF(2.62, 2.2, 0), detail(P.SilverMetal))
	return m, body
end)

define("TrashBin", "Trash Bin", true, 3, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	local body = cylY("Body", 2.6, 2, CF(0, 1.3, 0), P.Gunmetal)
	cylY("Rim", 0.25, 2.15, CF(0, 2.6, 0), detail(P.DarkMetal))
	cylY("Lid", 0.3, 1.9, CF(0, 2.85, 0), detail(P.DarkMetal))
	add("Slot", V(1.0, 0.1, 0.4), CF(0, 3.02, 0), detail(P.Rubber))
	cylY("Base", 0.2, 2.05, CF(0, 0.1, 0), detail(P.Rubber))
	return m, body
end)

define("DeskLamp", "Desk Lamp", true, 2.2, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	local body = cylY("Body", 0.25, 1.2, CF(0, 0.125, 0), P.DarkMetal)
	add("ArmLower", V(0.18, 1.3, 0.18), CF(0, 0.85, 0.15) * rot(-18, 0, 0), detail(P.SilverMetal))
	add("ArmUpper", V(0.18, 1.0, 0.18), CF(0, 1.65, -0.05) * rot(55, 0, 0), detail(P.SilverMetal))
	add("Head", V(0.8, 0.45, 0.6), CF(0, 1.85, -0.55) * rot(-25, 0, 0), detail(P.DarkMetal))
	add("Bulb", V(0.55, 0.06, 0.4), CF(0, 1.62, -0.62) * rot(-25, 0, 0), detail(P.Screen))
	return m, body
end)

define("ComputerMonitor", "Computer Monitor", true, 3, function(parent, o, id)
	local m, add = begin(parent, id, o)
	add("Foot", V(1.3, 0.12, 0.9), CF(0, 0.06, 0.1), detail(P.DarkMetal))
	add("Neck", V(0.25, 1.0, 0.2), CF(0, 0.6, 0.25), detail(P.DarkMetal))
	local body = add("Body", V(3.2, 2.0, 0.25), CF(0, 1.9, 0), P.DarkMetal)
	add("Screen", V(3.0, 1.8, 0.05), CF(0, 1.9, -0.14), detail(P.Screen))
	return m, body
end)

define("SmallTable", "Small Table", true, 2.7, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(4, 0.3, 3), CF(0, 2.55, 0), P.LightPanel)
	for _, x in { -1.75, 1.75 } do
		for _, z in { -1.25, 1.25 } do
			add("Leg", V(0.25, 2.4, 0.25), CF(x, 1.2, z), detail(P.SilverMetal))
		end
	end
	add("Brace", V(3.5, 0.15, 0.15), CF(0, 0.6, 0), detail(P.SilverMetal))
	return m, body
end)

define("FilingCabinet", "Filing Cabinet", true, 4.4, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(2.4, 4.4, 2.6), CF(0, 2.2, 0), P.SilverMetal)
	for i = 0, 2 do
		local y = 0.85 + i * 1.4
		add("Drawer", V(2.2, 1.25, 0.1), CF(0, y, -1.33), detail(style(C.SilverLight, M.Metal)))
		add("Handle", V(0.8, 0.14, 0.14), CF(0, y + 0.25, -1.42), detail(P.DarkMetal))
		add("Tag", V(0.5, 0.25, 0.05), CF(0, y - 0.2, -1.4), detail(P.LightPanel))
	end
	return m, body
end)

define("Barrel", "Barrel", true, 3.7, function(parent, o, id)
	local m, _, cylY = begin(parent, id, o)
	local body = cylY("Body", 3.6, 2.6, CF(0, 1.8, 0), P.BarrelBlue)
	cylY("RingTop", 0.25, 2.72, CF(0, 2.8, 0), detail(P.DarkMetal))
	cylY("RingBottom", 0.25, 2.72, CF(0, 0.8, 0), detail(P.DarkMetal))
	cylY("Lid", 0.12, 2.4, CF(0, 3.62, 0), detail(P.DarkMetal))
	cylY("Cap", 0.15, 0.45, CF(0.6, 3.72, 0.3), detail(P.SilverMetal))
	return m, body
end)

define("LabEquipment", "Lab Analyzer", true, 3.2, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	local body = add("Body", V(3, 1.4, 2.2), CF(0, 0.7, 0), P.LightPanel)
	cylY("Dome", 1.4, 1.6, CF(0.4, 2.1, 0.1), detail(P.Glass))
	cylY("Sample", 0.9, 0.5, CF(0.4, 1.9, 0.1), detail(P.LedCyan))
	cylY("DomeCap", 0.15, 1.7, CF(0.4, 2.85, 0.1), detail(P.SilverMetal))
	add("Display", V(1.0, 0.55, 0.06), CF(-0.8, 0.85, -1.12), detail(P.ScreenBlue))
	for i = 0, 2 do
		add("Knob", V(0.18, 0.18, 0.12), CF(0.3 + i * 0.35, 0.5, -1.12), detail(P.DarkMetal))
	end
	add("Trim", V(3.05, 0.12, 2.25), CF(0, 1.42, 0), detail(P.SilverMetal))
	return m, body
end)

define("StorageBox", "Storage Box", true, 2.1, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(3, 1.8, 2.2), CF(0, 0.9, 0), P.Plastic)
	add("Lid", V(3.15, 0.3, 2.35), CF(0, 1.95, 0), detail(P.PlasticDark))
	add("GripL", V(0.06, 0.3, 0.9), CF(-1.52, 1.4, 0), detail(P.Rubber))
	add("GripR", V(0.06, 0.3, 0.9), CF(1.52, 1.4, 0), detail(P.Rubber))
	add("Label", V(1.0, 0.5, 0.05), CF(0, 1.0, -1.12), detail(P.LightPanel))
	return m, body
end)

define("PottedPlant", "Potted Plant", true, 4.2, function(parent, o, id)
	local m, _, cylY, _, ball = begin(parent, id, o)
	local body = cylY("Body", 1.6, 1.8, CF(0, 0.8, 0), P.PlasticDark)
	cylY("Soil", 0.12, 1.6, CF(0, 1.58, 0), detail(P.Soil))
	cylY("Stem", 1.0, 0.2, CF(0, 2.0, 0), detail(P.WoodFrame))
	ball("LeavesA", 2.2, CF(0, 2.9, 0), detail(P.Leaf))
	ball("LeavesB", 1.7, CF(0.5, 3.4, -0.3), detail(P.Leaf))
	ball("LeavesC", 1.5, CF(-0.5, 3.5, 0.4), detail(P.Leaf))
	return m, body
end)

define("ToolCart", "Tool Cart", true, 3.4, function(parent, o, id)
	local m, add, _, cylX = begin(parent, id, o)
	local body = add("Body", V(3.4, 0.2, 1.8), CF(0, 2.9, 0), P.Gunmetal)
	add("Shelf", V(3.4, 0.2, 1.8), CF(0, 1.2, 0), detail(P.Gunmetal))
	for _, x in { -1.6, 1.6 } do
		for _, z in { -0.8, 0.8 } do
			add("Post", V(0.18, 2.7, 0.18), CF(x, 1.75, z), detail(P.DarkMetal))
			cylX("Wheel", 0.2, 0.45, CF(x, 0.22, z) * rot(0, 90, 0), detail(P.Rubber))
		end
	end
	add("Handle", V(0.15, 0.15, 1.6), CF(1.95, 3.0, 0), detail(P.SilverMetal))
	add("Toolbox", V(1.3, 0.6, 0.7), CF(-0.6, 3.3, 0), detail(P.Toolbox))
	add("Wrench", V(1.0, 0.08, 0.2), CF(0.8, 3.04, -0.3) * rot(0, 30, 0), detail(P.SilverMetal))
	add("Parts", V(0.9, 0.5, 0.8), CF(0.2, 1.55, 0.2), detail(P.Plastic))
	return m, body
end)

define("ServerRack", "Server Rack", true, 7, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(3, 7, 3.4), CF(0, 3.5, 0), style(rgb(26, 28, 33), M.Metal))
	add("Door", V(2.7, 6.6, 0.1), CF(0, 3.5, -1.72), detail(style(rgb(38, 42, 50), M.DiamondPlate)))
	add("Vent", V(2.8, 0.1, 3.1), CF(0, 7.02, 0), detail(P.DarkMetal))
	for i = 0, 3 do
		local led = if i % 2 == 0 then P.LedBlue else P.LedCyan
		add("Led", V(0.9, 0.08, 0.05), CF(-0.6, 1.2 + i * 1.5, -1.79), detail(led))
		add("Dot", V(0.12, 0.12, 0.05), CF(0.9, 1.2 + i * 1.5, -1.79), detail(P.LedCyan))
	end
	return m, body
end)

define("CleaningSupplies", "Cleaning Cart", true, 4.6, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	local body = cylY("Body", 1.4, 1.9, CF(0, 0.75, 0), P.BucketBlue)
	add("Wringer", V(1.2, 0.6, 0.8), CF(0, 1.7, 0.3), detail(P.PlasticDark))
	add("Handle", V(0.15, 4.4, 0.15), CF(-0.3, 2.4, -0.2) * rot(-8, 0, 10), detail(P.SilverMetal))
	add("MopHead", V(0.9, 0.5, 0.9), CF(-0.25, 0.55, -0.35), detail(P.Mop))
	add("Bottle", V(0.4, 0.8, 0.4), CF(0.55, 1.85, -0.35), detail(P.LedCyan))
	add(
		"Sign",
		V(0.9, 1.3, 0.08),
		CF(0.9, 0.65, -0.2) * rot(0, 0, 8),
		detail(style(C.OffWhite, M.SmoothPlastic))
	)
	return m, body
end)

-- ===========================================================================
-- Decor (not transformable; furniture and structural dressing)
-- ===========================================================================

define("Desk", "Desk", false, 2.8, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(6, 0.3, 3), CF(0, 2.65, 0), style(rgb(168, 174, 182), M.SmoothPlastic))
	add("SideL", V(0.3, 2.5, 2.9), CF(-2.8, 1.25, 0), style(rgb(120, 126, 136), M.SmoothPlastic))
	add("SideR", V(0.3, 2.5, 2.9), CF(2.8, 1.25, 0), style(rgb(120, 126, 136), M.SmoothPlastic))
	add("Modesty", V(5.3, 1.5, 0.15), CF(0, 1.6, 1.3), detail(style(rgb(120, 126, 136), M.SmoothPlastic)))
	add("Drawers", V(1.4, 1.8, 2.6), CF(1.9, 1.4, 0), detail(style(rgb(140, 146, 156), M.SmoothPlastic)))
	return m, body
end)

define("Locker", "Locker", false, 7, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(3, 7, 2.4), CF(0, 3.5, 0), style(rgb(70, 84, 100), M.Metal))
	add("Seam", V(0.08, 6.6, 0.05), CF(0, 3.5, -1.22), detail(P.DarkMetal))
	for _, x in { -0.75, 0.75 } do
		for i = 0, 3 do
			add("Vent", V(0.9, 0.08, 0.05), CF(x, 5.6 + i * 0.25, -1.22), detail(P.DarkMetal))
		end
		add("Handle", V(0.1, 0.6, 0.1), CF(x * 0.2, 3.6, -1.26), detail(P.SilverMetal))
	end
	return m, body
end)

define("ShelfUnit", "Shelving", false, 8, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(8, 0.25, 3), CF(0, 0.3, 0), P.Gunmetal)
	for _, x in { -3.9, 3.9 } do
		for _, z in { -1.4, 1.4 } do
			add("Post", V(0.2, 8, 0.2), CF(x, 4, z), P.DarkMetal)
		end
	end
	for _, y in { 2.8, 5.3, 7.8 } do
		add("Shelf", V(8, 0.2, 3), CF(0, y, 0), P.Gunmetal)
	end
	add("Back", V(8, 7.5, 0.1), CF(0, 4.05, 1.45), detail(style(rgb(40, 44, 50), M.DiamondPlate)))
	return m, body
end)

define("MedicalBed", "Medical Bed", false, 3.4, function(parent, o, id)
	local m, add, cylY = begin(parent, id, o)
	local body = add("Body", V(3.2, 1.4, 7), CF(0, 1.3, 0), P.SilverMetal)
	add("Mattress", V(3, 0.6, 6.6), CF(0, 2.3, 0), detail(P.Sheet))
	add("Pillow", V(2.4, 0.4, 1.2), CF(0, 2.75, 2.6), detail(P.Sheet))
	add("Head", V(3.2, 2.4, 0.3), CF(0, 2.6, 3.4), P.LightPanel)
	add("Rail", V(0.15, 0.6, 3), CF(-1.65, 2.6, -0.5), detail(P.SilverMetal))
	cylY("IVPole", 6, 0.15, CF(2.2, 3, 2.8), detail(P.SilverMetal))
	add(
		"IVBag",
		V(0.6, 0.9, 0.2),
		CF(2.2, 5.6, 2.8),
		detail(style(rgb(200, 235, 245), M.Glass, { Transparency = 0.3 }))
	)
	return m, body
end)

define("Bench", "Bench", false, 1.8, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(6, 0.4, 1.8), CF(0, 1.6, 0), P.Gunmetal)
	add("LegL", V(0.4, 1.4, 1.6), CF(-2.5, 0.7, 0), P.DarkMetal)
	add("LegR", V(0.4, 1.4, 1.6), CF(2.5, 0.7, 0), P.DarkMetal)
	add("Strip", V(5.8, 0.06, 0.12), CF(0, 1.42, -0.85), detail(P.LedCyan))
	return m, body
end)

define("LabBench", "Lab Bench", false, 3, function(parent, o, id)
	local m, add = begin(parent, id, o)
	local body = add("Body", V(8, 0.3, 3), CF(0, 2.85, 0), style(C.OffWhite, M.SmoothPlastic))
	add("Cabinet", V(7.6, 2.7, 2.6), CF(0, 1.35, 0.1), style(rgb(70, 76, 86), M.Metal))
	add("Kick", V(7.4, 0.3, 0.1), CF(0, 0.15, -1.22), detail(P.LedCyan))
	for i = -1, 1 do
		add("Door", V(2.3, 2.1, 0.06), CF(i * 2.5, 1.45, -1.22), detail(style(rgb(86, 92, 104), M.Metal)))
	end
	return m, body
end)

define("SecurityCamera", "Security Camera", false, 1.2, function(parent, o, id)
	local m, add, _, cylX = begin(parent, id, o)
	local body =
		add("Body", V(0.9, 0.8, 1.6), CF(0, 0, -0.6) * rot(-20, 0, 0), style(C.OffWhite, M.SmoothPlastic))
	add("Mount", V(0.4, 0.4, 0.9), CF(0, 0.35, 0.2), detail(P.DarkMetal))
	cylX("Lens", 0.2, 0.55, CF(0, -0.25, -1.4) * rot(-20, 90, 0), detail(P.Rubber))
	add("Led", V(0.12, 0.12, 0.05), CF(0.3, 0.1, -1.42) * rot(-20, 0, 0), detail(P.LedRed))
	return m, body
end)

-- ===========================================================================

Props.order = order
Props.definitions = definitions

function Props.build(id: string, parent: any, origin: any): any
	local definition = definitions[id]
	assert(definition, `Unknown prop '{id}'`)
	return definition.build(parent, origin)
end

-- Places a prop; transformable props are tagged for the Object Shift system.
function Props.place(id: string, parent: any, origin: any): any
	local model = Props.build(id, parent, origin)
	if definitions[id].transformable then
		model:AddTag("MimicProp")
	end
	return model
end

function Props.isTransformable(id: string): boolean
	local definition = definitions[id]
	return definition ~= nil and definition.transformable
end

return Props
