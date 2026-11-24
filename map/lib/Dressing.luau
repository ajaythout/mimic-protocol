--!strict
--[[
	Dressing — per-room landmarks, props and signage.

	Every room gets a distinct silhouette so players can navigate by sight:
	  Atrium      holographic core column + reception ring + overhead trusses
	  Server      rack aisles under a cold blue catwalk
	  Generator   twin generator units, exhaust stacks, hazard lines
	  Security    wall of camera monitors and a console row
	  Storage     shelving aisles and crate stacks (prime Mimic territory)
	  Offices     glass-partitioned desk clusters
	  Research    glowing specimen tank, warning hologram, clean room
	  Medical     bed bay with curtains under sterile white light
	  Pump        pumps and valves in red light
	  Maintenance long pipe-lined tunnel with dead ends
	  Extraction  the lift (built separately in build.luau)

	Props never block doorway paths: each room keeps a clear lane from every
	door to the room centre.
]]

local B = require("./B")
local Layout = require("./Layout")
local Props = require("./Props")

local CFrame = B.CFrame
local Vector3 = B.Vector3
local S = B.Styles
local C = B.Colors
local rgb = B.rgb
local M = B.Enum.Material

local V = Vector3.new
local CF = CFrame.new

local Dressing = {}

export type Ctx = {
	room: Layout.Room,
	model: any,
	props: any,
	world: (x: number, y: number, z: number) -> any,
	at: (x: number, z: number, rotDeg: number?, y: number?) -> any,
	prop: (id: string, x: number, z: number, rotDeg: number?, y: number?) -> any,
	propAt: (id: string, cframe: any) -> any,
	box: (name: string, size: any, x: number, y: number, z: number, style: B.Style, rotDeg: number?) -> any,
	boxCF: (name: string, size: any, localCF: any, style: B.Style) -> any,
	cylY: (
		name: string,
		height: number,
		diameter: number,
		x: number,
		y: number,
		z: number,
		style: B.Style
	) -> any,
	cylX: (
		name: string,
		length: number,
		diameter: number,
		x: number,
		y: number,
		z: number,
		style: B.Style,
		rotDeg: number?
	) -> any,
	sign: (
		name: string,
		size: any,
		x: number,
		y: number,
		z: number,
		nx: number,
		nz: number,
		text: string,
		opts: B.SignOptions?
	) -> any,
	workstation: (x: number, z: number, rotDeg: number, lamp: boolean?) -> (),
}

local function style(color: any, material: any, extra: { [string]: any }?): B.Style
	local s: any = { Color = color, Material = material, CastShadow = false }
	if extra then
		for k, v in extra do
			s[k] = v
		end
	end
	return s
end

local Local = {
	Gunmetal = style(rgb(72, 78, 88), M.Metal),
	DarkMetal = style(rgb(40, 43, 50), M.Metal),
	Silver = style(C.Silver, M.Metal),
	Panel = style(C.OffWhite, M.SmoothPlastic),
	Screen = style(rgb(14, 30, 52), M.SmoothPlastic),
	Curtain = style(rgb(176, 196, 208), M.Fabric, { CanCollide = false, Transparency = 0.1 }),
	Fluid = style(C.Specimen, M.Glass, { Transparency = 0.82, CanCollide = false }),
	Shard = style(C.Specimen, M.Neon, { CanCollide = false }),
	WarnRed = style(rgb(255, 70, 40), M.Neon, { CanCollide = false }),
	LiftFloor = style(rgb(120, 128, 138), M.DiamondPlate),
}

function Dressing.context(room: Layout.Room, model: any, props: any): Ctx
	local cx, cz = room.cx, room.cz
	local ctx = {} :: Ctx
	ctx.room = room
	ctx.model = model
	ctx.props = props

	function ctx.world(x: number, y: number, z: number)
		return V(cx + x, y, cz + z)
	end
	function ctx.at(x: number, z: number, rotDeg: number?, y: number?)
		return CF(cx + x, y or 0, cz + z) * CFrame.Angles(0, math.rad(rotDeg or 0), 0)
	end
	function ctx.prop(id: string, x: number, z: number, rotDeg: number?, y: number?)
		return Props.place(id, props, ctx.at(x, z, rotDeg, y))
	end
	function ctx.propAt(id: string, cframe: any)
		return Props.place(id, props, cframe)
	end
	function ctx.box(name: string, size: any, x: number, y: number, z: number, s: B.Style, rotDeg: number?)
		return B.part(model, name, size, ctx.at(x, z, rotDeg, y), s)
	end
	function ctx.boxCF(name: string, size: any, localCF: any, s: B.Style)
		return B.part(model, name, size, CF(cx, 0, cz) * localCF, s)
	end
	function ctx.cylY(
		name: string,
		height: number,
		diameter: number,
		x: number,
		y: number,
		z: number,
		s: B.Style
	)
		return B.cylinderY(model, name, height, diameter, CF(cx + x, y, cz + z), s)
	end
	function ctx.cylX(
		name: string,
		length: number,
		diameter: number,
		x: number,
		y: number,
		z: number,
		s: B.Style,
		rotDeg: number?
	)
		return B.cylinderX(model, name, length, diameter, ctx.at(x, z, rotDeg, y), s)
	end
	function ctx.sign(
		name: string,
		size: any,
		x: number,
		y: number,
		z: number,
		nx: number,
		nz: number,
		text: string,
		opts: B.SignOptions?
	)
		return B.sign(model, name, size, B.facing(V(cx + x, y, cz + z), nx, nz), text, opts)
	end
	-- Desk with monitor and chair; the user sits on the desk's local -Z side.
	function ctx.workstation(x: number, z: number, rotDeg: number, lamp: boolean?)
		local base = ctx.at(x, z, rotDeg)
		ctx.propAt("Desk", base)
		ctx.propAt("ComputerMonitor", base * CF(-0.8, 2.8, 0.4))
		ctx.propAt("OfficeChair", base * CF(0, 0, -2.9) * CFrame.Angles(0, math.pi, 0))
		if lamp then
			ctx.propAt("DeskLamp", base * CF(2.1, 2.8, 0.6))
		end
	end
	return ctx
end

-- Helpers -------------------------------------------------------------------------

local function truss(ctx: Ctx, length: number, z: number, y0: number, alongX: boolean)
	local panel = 4
	local height = 3
	local count = math.floor(length / panel)
	local start = -count * panel / 2
	local function place(name: string, size: any, a: number, y: number, rotZ: number?)
		local localCF = if alongX then CF(a, y, z) else CF(z, y, a) * CFrame.Angles(0, math.pi / 2, 0)
		if rotZ then
			localCF *= CFrame.Angles(0, 0, rotZ)
		end
		return ctx.boxCF(name, size, localCF, S.Trim)
	end
	place("TrussChord", V(count * panel, 0.5, 0.5), 0, y0)
	place("TrussChord", V(count * panel, 0.5, 0.5), 0, y0 + height)
	for i = 0, count do
		place("TrussPost", V(0.35, height, 0.35), start + i * panel, y0 + height / 2)
	end
	local diagonal = math.sqrt(panel * panel + height * height)
	local angle = math.atan2(height, panel)
	for i = 0, count - 1 do
		local sgn = if i % 2 == 0 then 1 else -1
		place("TrussDiagonal", V(diagonal, 0.3, 0.3), start + (i + 0.5) * panel, y0 + height / 2, sgn * angle)
	end
end

local function railing(ctx: Ctx, x0: number, x1: number, z: number, y: number)
	local length = x1 - x0
	ctx.box("Rail", V(length, 0.2, 0.2), (x0 + x1) / 2, y + 1.2, z, S.TrimLight)
	ctx.box("Rail", V(length, 0.15, 0.15), (x0 + x1) / 2, y + 0.6, z, S.Trim)
	local posts = math.floor(length / 4)
	for i = 0, posts do
		ctx.box("RailPost", V(0.2, 1.2, 0.2), x0 + i * (length / posts), y + 0.6, z, S.Trim)
	end
end

local function hazardFrame(ctx: Ctx, x: number, z: number, sx: number, sz: number)
	ctx.box("HazardLine", V(sx + 1, 0.06, 0.5), x, 0.03, z - sz / 2 - 0.25, S.Hazard)
	ctx.box("HazardLine", V(sx + 1, 0.06, 0.5), x, 0.03, z + sz / 2 + 0.25, S.Hazard)
	ctx.box("HazardLine", V(0.5, 0.06, sz), x - sx / 2 - 0.25, 0.03, z, S.Hazard)
	ctx.box("HazardLine", V(0.5, 0.06, sz), x + sx / 2 + 0.25, 0.03, z, S.Hazard)
end

local function titleSign(ctx: Ctx, x: number, y: number, z: number, nx: number, nz: number, width: number)
	ctx.sign("RoomTitle", V(width, 2.4, 0.2), x, y, z, nx, nz, `{ctx.room.code}  //  {ctx.room.name}`, {
		textColor = C.CyanSoft,
		background = S.WallDark,
	})
end

local function glassPartition(ctx: Ctx, x: number, z: number, length: number, alongX: boolean)
	local rot = if alongX then 0 else 90
	ctx.box("PartitionBase", V(length, 3, 0.4), x, 1.5, z, S.Trim, rot)
	ctx.box("PartitionGlass", V(length, 4, 0.2), x, 5, z, S.Glass, rot)
	ctx.box("PartitionCap", V(length, 0.25, 0.45), x, 7.1, z, S.TrimLight, rot)
end

-- Rooms ---------------------------------------------------------------------------

local builders: { [string]: (Ctx) -> () } = {}

builders.Atrium = function(ctx)
	-- Central dais with a holographic core: the facility's main landmark.
	ctx.cylY("DaisGlow", 0.3, 20.8, 0, 0.15, 0, S.NeonCyan)
	ctx.cylY("Dais", 0.6, 20, 0, 0.3, 0, S.Trim)
	for i = 0, 7 do
		if i ~= 0 and i ~= 4 then
			local a = math.rad(i * 45)
			local x, z = math.sin(a) * 6.5, -math.cos(a) * 6.5
			ctx.box("ReceptionDesk", V(4.6, 3, 1.2), x, 2.1, z, Local.Gunmetal, -i * 45)
			ctx.box("ReceptionTop", V(5, 0.25, 1.9), x, 3.72, z, S.TrimLight, -i * 45)
		end
	end
	ctx.cylY("HoloGlass", 21, 3, 0, 11.1, 0, S.Glass)
	local core = ctx.cylY("HoloCore", 21, 0.8, 0, 11.1, 0, S.NeonCyan)
	B.pointLight(core, rgb(90, 220, 255), 1.3, 30, nil, true)
	for _, ring in { { 5, 12 }, { 3.6, 15.5 }, { 5, 19 } } do
		local radius, y = ring[1], ring[2]
		local segments = 16
		local segLength = 2 * math.pi * radius / segments * 0.7
		for i = 0, segments - 1 do
			local a = 2 * math.pi * i / segments
			ctx.box(
				"HoloRing",
				V(segLength, 0.25, 0.25),
				math.sin(a) * radius,
				y,
				-math.cos(a) * radius,
				S.NeonCyan,
				-math.deg(a)
			)
		end
	end

	-- Structural columns.
	for _, p in { { -18, -18 }, { 18, -18 }, { -18, 18 }, { 18, 18 } } do
		local x, z = p[1], p[2]
		ctx.box("Column", V(3, 24, 3), x, 12, z, S.Trim)
		ctx.box("ColumnBase", V(4.2, 1.2, 4.2), x, 0.6, z, S.WallDark)
		ctx.box("ColumnGlow", V(0.3, 16, 0.3), x - math.sign(x) * 1.6, 9, z - math.sign(z) * 1.2, S.NeonCyan)
	end

	truss(ctx, 64, -12, 18, true)
	truss(ctx, 64, 12, 18, true)

	ctx.prop("Bench", -11, -26, 180)
	ctx.prop("Bench", 11, -26, 180)
	ctx.prop("Bench", -11, 26, 0)
	ctx.prop("Bench", 11, 26, 0)
	ctx.prop("PottedPlant", -28, -28)
	ctx.prop("PottedPlant", 28, -28)
	ctx.prop("PottedPlant", -28, 28)
	ctx.prop("PottedPlant", 28, 28)
	ctx.prop("TrashBin", -27, 10)
	ctx.prop("TrashBin", 27, -10)
	ctx.prop("SecurityCamera", 30.6, -30.6, 135, 20)

	titleSign(ctx, 0, 19.5, -31.2, 0, 1, 28)
end

builders.Server = function(ctx)
	local rackXs = { -21, -18, -15, -12, 12, 15, 18, 21 }
	local rows = {
		{ z = -20, rot = 180 },
		{ z = -11, rot = 0 },
		{ z = 12, rot = 180 },
		{ z = 20.5, rot = 0 },
	}
	for _, row in rows do
		for _, x in rackXs do
			ctx.prop("ServerRack", x, row.z, row.rot)
		end
		for _, side in { -1, 1 } do
			ctx.box("CableTray", V(13, 0.4, 2), side * 16.5, 14.5, row.z, Local.DarkMetal)
		end
	end
	for _, aisleZ in { -15.5, 16.2 } do
		for _, side in { -1, 1 } do
			ctx.box("AisleGlow", V(12, 0.08, 0.35), side * 16.5, 0.04, aisleZ, S.NeonBlue)
		end
	end

	-- Decorative overhead catwalk along the north wall.
	ctx.box("Catwalk", V(56, 0.5, 4), 0, 11, -22, S.Grate)
	ctx.box("CatwalkEdge", V(56, 0.6, 0.3), 0, 11, -19.9, S.Trim)
	railing(ctx, -28, 28, -20.1, 11.25)
	for _, x in { -20, 0, 20 } do
		ctx.box("CatwalkStrut", V(0.6, 3, 0.6), x, 9.5, -20.4, S.Trim)
	end

	ctx.workstation(0, -15.5, 0, true)
	ctx.prop("ToolCart", 24.5, 0 + 9, 90)
	ctx.prop("SecurityCamera", -27.4, 23.4, -45, 15)
	titleSign(ctx, 0, 14.5, 23.7, 0, -1, 22)
end

--[[
	Repairable generator contract (GeneratorService):
	  Model tagged "Generator", attributes GeneratorId, DisplayName
	    Panel   the repair point; the REPAIR prompt attaches here
	    Status  neon strip, red while offline and cyan once online
	    Core    glow part whose PointLight is lit only while online
	Generators start offline every round.
]]
local function generatorModel(ctx: Ctx, id: string, displayName: string, parts: { any }): any
	local model = B.model(ctx.model, "Generator")
	B.attrs(model, { GeneratorId = id, DisplayName = displayName })
	B.tag(model, "Generator")
	for _, part in parts do
		part.Parent = model
	end
	model.PrimaryPart = parts[1]
	return model
end

local function generatorUnit(ctx: Ctx, gx: number, gz: number, id: string, displayName: string)
	ctx.box("GenPlatform", V(14, 0.8, 16), gx, 0.4, gz, S.Trim)
	ctx.box("GenHousing", V(10, 8, 12), gx, 4.8, gz, Local.Gunmetal)
	ctx.box("GenVent", V(8, 3.2, 0.2), gx, 4.6, gz + 6.05, S.Grate)
	local status = ctx.box("Status", V(8, 0.3, 0.12), gx, 7.4, gz + 6.07, S.NeonRed)
	local panel = ctx.box("Panel", V(2.4, 2.4, 0.3), gx - 3.4, 2.6, gz + 6.15, Local.Screen)
	ctx.cylX("GenTurbine", 11, 5.6, gx, 11.4, gz, Local.Silver, 90)
	ctx.cylX("GenTurbineCapA", 0.6, 6.2, gx, 11.4, gz - 5.6, Local.DarkMetal, 90)
	ctx.cylX("GenTurbineCapB", 0.6, 6.2, gx, 11.4, gz + 5.6, Local.DarkMetal, 90)
	for _, dx in { -3.2, 3.2 } do
		ctx.cylY("GenExhaust", 10, 1.6, gx + dx, 19, gz - 3, Local.DarkMetal)
	end
	local glow = ctx.box("Core", V(3, 1.2, 0.2), gx, 2.4, gz + 6.07, S.NeonCyan)
	B.pointLight(glow, rgb(120, 220, 255), 1.1, 18, {})
	local beacon = ctx.box("GenBeacon", V(1, 0.8, 1), gx + 4, 9.2, gz + 5, S.Beacon)
	B.tag(beacon, "EmergencyBeacon")
	hazardFrame(ctx, gx, gz, 14, 16)
	generatorModel(ctx, id, displayName, { panel, status, glow })
end

builders.Generator = function(ctx)
	generatorUnit(ctx, -13, -13, "GEN-A", "GENERATOR A")
	generatorUnit(ctx, 13, -13, "GEN-B", "GENERATOR B")
	ctx.cylX("CeilingPipe", 56, 1.6, 0, 20, -25, Local.DarkMetal)
	ctx.cylX("CeilingPipe", 56, 1.0, 0, 21.6, -23.5, Local.Gunmetal)
	truss(ctx, 56, 4, 18, true)

	for _, p in { { -24, 10 }, { -21, 10 }, { -24, 13 }, { -24, 22 }, { -21, 22.5 } } do
		ctx.prop("Barrel", p[1], p[2])
	end
	ctx.prop("MetalCrate", 24, 12, 90)
	ctx.prop("MetalCrate", 24, 24, 90)
	ctx.prop("ToolCart", 10, 25, 0)
	ctx.prop("CleaningSupplies", -10, 25, 0)

	for _, x in { -13, 13 } do
		ctx.sign("WarningSign", V(8, 1.6, 0.2), x, 9, -27.7, 0, 1, "DANGER // HIGH VOLTAGE", {
			textColor = C.Red,
			background = S.WallDark,
		})
	end
	titleSign(ctx, 0, 19.5, 27.7, 0, -1, 24)
end

builders.Security = function(ctx)
	-- Monitor wall: future security-camera terminal surface.
	ctx.box("MonitorFrame", V(25, 8.4, 0.4), 0, 8.2, -21.8, Local.DarkMetal)
	local labels = {
		"CAM 01  ATRIUM",
		"CAM 02  STORAGE",
		"CAM 03  GENERATOR",
		"CAM 04  SERVERS",
		"CAM 05  OFFICES",
		"CAM 06  RESEARCH",
		"CAM 07  MEDICAL",
		"CAM 08  LIFT",
	}
	local index = 0
	for _, y in { 10.1, 6.4 } do
		for _, x in { -8.9, -2.95, 2.95, 8.9 } do
			index += 1
			ctx.sign("Monitor", V(5.5, 3.3, 0.2), x, y, -21.5, 0, 1, labels[index], {
				textColor = C.CyanSoft,
				background = Local.Screen,
				font = B.Fonts.Mono,
				alignLeft = true,
			})
		end
	end
	for _, x in { -7, 0, 7 } do
		ctx.workstation(x, -14, 180, x == 0)
	end
	ctx.prop("FilingCabinet", 24.5, -16, 90)
	ctx.prop("FilingCabinet", 24.5, -12.8, 90)
	ctx.prop("Locker", 24.5, 14, 90)
	ctx.prop("Locker", 24.5, 17.2, 90)
	ctx.prop("PottedPlant", -22, -18)
	ctx.prop("TrashBin", 14, -10)
	ctx.prop("TrashBin", -22, 16)
	ctx.prop("SmallTable", -16, 16, 90)
	ctx.prop("OfficeChair", -16, 13, 0)
	ctx.prop("OfficeChair", -16, 19, 180)
	ctx.prop("SecurityCamera", -25.4, 21.4, -45, 13)
	titleSign(ctx, 25.7, 12, 0, -1, 0, 22)
end

builders.Storage = function(ctx)
	-- North-west shelving aisles with boxes on the shelves.
	for _, z in { -24, -15 } do
		for _, x in { -21, -12 } do
			ctx.prop("ShelfUnit", x, z, 0)
		end
	end
	ctx.prop("StorageBox", -23, -24, 0, 2.9)
	ctx.prop("StorageBox", -19, -24, 0, 5.4)
	ctx.prop("StorageBox", -13.5, -24, 0, 2.9)
	ctx.prop("StorageBox", -10.5, -15, 0, 5.4)
	ctx.prop("StorageBox", -22, -15, 0, 2.9)
	ctx.prop("StorageBox", -19, -15, 0, 0.45)

	-- South-west crate stacks.
	ctx.prop("WoodenCrate", -22, 12, 0)
	ctx.prop("WoodenCrate", -18, 12, 0)
	ctx.prop("WoodenCrate", -22, 12, 0, 4)
	ctx.prop("WoodenCrate", -22, 16, 0)
	ctx.prop("WoodenCrate", -14, 23, 15)
	ctx.prop("WoodenCrate", -10, 23.5, 0)
	ctx.prop("WoodenCrate", -24.5, 24, 0)
	ctx.prop("WoodenCrate", -24.5, 24, 0, 4)

	-- North-east metal crates.
	for _, x in { 12, 18, 24 } do
		ctx.prop("MetalCrate", x, -24, 0)
	end
	ctx.prop("MetalCrate", 12, -24, 0, 3.6)
	ctx.prop("MetalCrate", 15, -17, 0)
	ctx.prop("MetalCrate", 22, -17, 0)
	ctx.prop("ToolCart", 23, -10.5, 0)

	-- South-east barrels and supplies.
	ctx.prop("Barrel", 24, 24)
	ctx.prop("Barrel", 21, 24)
	ctx.prop("Barrel", 24, 21)
	ctx.prop("CleaningSupplies", 10, 25, 0)
	ctx.prop("StorageBox", 14, 12, 0)
	ctx.prop("StorageBox", 17.5, 12, 0)
	ctx.prop("StorageBox", 14, 12, 0, 2.1)
	ctx.prop("TrashBin", 8.5, -8.5)

	truss(ctx, 56, 0, 15, false)
	ctx.prop("SecurityCamera", 27.4, 27.4, 45, 17)
	titleSign(ctx, -27.7, 14, 0, 1, 0, 24)
end

builders.Office = function(ctx)
	for _, q in { { -18, -16 }, { 18, -16 }, { -18, 16 }, { 18, 16 } } do
		local qx, qz = q[1], q[2]
		ctx.workstation(qx - 3.1, qz - 1.6, 0, true)
		ctx.workstation(qx + 3.1, qz - 1.6, 0, false)
		ctx.workstation(qx - 3.1, qz + 1.6, 180, false)
		ctx.workstation(qx + 3.1, qz + 1.6, 180, true)
		local sx, sz = math.sign(qx), math.sign(qz)
		glassPartition(ctx, sx * 8, sz * 14, 12, false)
		glassPartition(ctx, sx * 14, sz * 8, 12, true)
	end
	ctx.prop("FilingCabinet", -28.5, -10, -90)
	ctx.prop("FilingCabinet", -28.5, 10, -90)
	ctx.prop("FilingCabinet", 28.5, -10, 90)
	ctx.prop("FilingCabinet", 28.5, 10, 90)
	ctx.prop("PottedPlant", -9, -25.5)
	ctx.prop("PottedPlant", 9, 25.5)
	ctx.prop("PottedPlant", 27, -25)
	ctx.prop("TrashBin", -12, -10)
	ctx.prop("TrashBin", 12, 10)
	ctx.prop("SmallTable", -26, 24, 0)
	ctx.prop("SecurityCamera", -29.4, 25.4, -45, 13)
	titleSign(ctx, -18, 12.5, -27.7, 0, 1, 20)
end

builders.Research = function(ctx)
	-- Specimen containment tank (landmark).
	local tx, tz = 6, 0
	ctx.cylY("TankBase", 1.2, 14, tx, 0.6, tz, S.Trim)
	ctx.cylY("TankGlow", 0.2, 14.6, tx, 1.1, tz, B.Styles.NeonCyan)
	ctx.cylY("TankGlass", 12, 10, tx, 7.2, tz, S.Glass)
	ctx.cylY("TankFluid", 11.6, 9.4, tx, 7.2, tz, Local.Fluid)
	ctx.cylY("TankCap", 1.6, 11.5, tx, 14, tz, S.Trim)
	for _, dx in { -3, 3 } do
		ctx.cylY("TankPipe", 3.4, 1.4, tx + dx, 16.5, tz, Local.DarkMetal)
	end
	local shards = {
		{ 0, 4.5, 0, 0, 0, 10, 4.5 },
		{ 1.2, 5.5, 0.8, 25, 40, -20, 3.4 },
		{ -1.1, 6.2, -0.6, -30, 10, 25, 3.8 },
		{ 0.4, 8, -1.2, 15, 70, 35, 3 },
		{ -0.8, 3.6, 1.4, -20, -30, -40, 2.6 },
		{ 0.9, 7.2, 0.2, 40, 0, 15, 2.2 },
	}
	for i, s in shards do
		local shard = ctx.boxCF(
			"Specimen",
			V(1.1, s[7], 1.1),
			CF(tx + s[1], s[2], tz + s[3]) * CFrame.Angles(math.rad(s[4]), math.rad(s[5]), math.rad(s[6])),
			Local.Shard
		)
		if i == 1 then
			B.pointLight(shard, C.Specimen, 1.8, 28, nil, true)
		end
	end
	for _, a in { 200, 250, 290, 340 } do
		local r = math.rad(a)
		local x, z = tx + math.sin(r) * 9.5, tz - math.cos(r) * 9.5
		ctx.box("Console", V(1.6, 3.2, 1.2), x, 1.6, z, S.Trim, -a)
		ctx.box("ConsoleScreen", V(1.4, 0.9, 0.08), x, 3.2, z, B.Styles.NeonBlue, -a)
	end

	-- Warning hologram between the door and the tank.
	local hx, hy, hz = -6, 6.5, -11
	ctx.box("HoloBarTop", V(0.35, 0.35, 5), hx, hy + 1.44, hz, Local.WarnRed)
	ctx.boxCF(
		"HoloBarL",
		V(0.35, 0.35, 5),
		CF(hx, hy - 0.72, hz - 1.25) * CFrame.Angles(math.rad(60), 0, 0),
		Local.WarnRed
	)
	ctx.boxCF(
		"HoloBarR",
		V(0.35, 0.35, 5),
		CF(hx, hy - 0.72, hz + 1.25) * CFrame.Angles(math.rad(-60), 0, 0),
		Local.WarnRed
	)
	ctx.box("HoloMark", V(0.35, 1.5, 0.35), hx, hy + 0.15, hz, Local.WarnRed)
	ctx.box("HoloDot", V(0.35, 0.35, 0.35), hx, hy - 1.25, hz, Local.WarnRed)
	local ring = ctx.cylY("HoloPad", 0.12, 5, hx, 0.06, hz, Local.WarnRed)
	B.pointLight(ring, rgb(255, 80, 60), 1.0, 12)

	-- Benches with analysers along the long walls.
	for _, x in { -18, -8 } do
		ctx.prop("LabBench", x, -27.8, 180)
		ctx.prop("LabEquipment", x - 2, -27.8, 180, 3.0)
		ctx.prop("ComputerMonitor", x + 2, -27.4, 180, 3.0)
		ctx.prop("OfficeChair", x, -24, 0)
		ctx.prop("LabBench", x, 27.8, 0)
		ctx.prop("LabEquipment", x + 1.5, 27.8, 0, 3.0)
	end
	ctx.prop("LabBench", 4, -27.8, 180)
	ctx.prop("LabEquipment", 4, -27.8, 180, 3.0)

	-- Clean room behind a glass wall at the east end.
	glassPartition(ctx, 16, -16.5, 27, false)
	glassPartition(ctx, 16, 16.5, 27, false)
	ctx.prop("SmallTable", 22, -10, 90)
	ctx.prop("LabEquipment", 22, -10, 90, 2.7)
	ctx.prop("SmallTable", 22, 10, 90)
	ctx.prop("LabEquipment", 22, 10, 90, 2.7)
	ctx.prop("FilingCabinet", 26.5, -26, 90)
	ctx.prop("StorageBox", 25.5, 25.5, 0)
	ctx.prop("TrashBin", 18.5, 26)
	ctx.prop("SecurityCamera", -27.4, -29.4, -135, 15)
	titleSign(ctx, -6, 13.5, -29.7, 0, 1, 18)
end

builders.Medical = function(ctx)
	for _, z in { -15, -5, 5, 15 } do
		ctx.prop("MedicalBed", -20, z, -90)
	end
	for _, z in { -10, 0, 10 } do
		ctx.box("Curtain", V(7.5, 7, 0.12), -19.5, 4.6, z, Local.Curtain)
		ctx.box("CurtainRail", V(8, 0.15, 0.15), -19.5, 8.2, z, S.TrimLight)
	end
	ctx.prop("FilingCabinet", 22.5, -18, 90)
	ctx.prop("FilingCabinet", 22.5, -14.8, 90)
	ctx.prop("Locker", 22.3, -9, 90)
	ctx.prop("SmallTable", 16, -2, 90)
	ctx.prop("LabEquipment", 16, -2, 90, 2.7)
	ctx.prop("OfficeChair", 13, -2, -90)
	ctx.prop("CleaningSupplies", 20, 19, 0)
	ctx.prop("TrashBin", 9, 20)
	ctx.prop("PottedPlant", -9, -21)
	ctx.prop("StorageBox", 21.5, 6, 90)
	ctx.prop("SecurityCamera", 21.4, 21.4, 45, 13)
	titleSign(ctx, -15, 12.5, -23.7, 0, 1, 14)
end

builders.Pump = function(ctx)
	for _, z in { -5, 6 } do
		ctx.box("PumpBase", V(7, 1, 5), -8, 0.5, z, S.Trim)
		ctx.cylX("PumpBody", 6, 3.6, -8, 3.0, z, Local.Gunmetal)
		ctx.cylX("PumpPipe", 5, 1.2, -12, 3.0, z, Local.DarkMetal)
		ctx.cylY("PumpRiser", 7, 1.2, -6, 8.3, z, Local.DarkMetal)
		ctx.cylX("Valve", 0.3, 2, -4.6, 3.0, z, B.Styles.Hazard)
	end
	ctx.prop("Barrel", 9, -9)
	ctx.prop("Barrel", 11, -5.5)
	ctx.prop("ToolCart", 9.5, 1, 90)

	-- Auxiliary generator against the north wall: the third repair site, so
	-- the crew has to split up.
	ctx.box("AuxGenHousing", V(5, 4.4, 3), 0, 2.2, -11.5, Local.Gunmetal)
	ctx.box("AuxGenVent", V(3.6, 1.2, 0.12), 0, 3.6, -9.94, S.Grate)
	local auxStatus = ctx.box("Status", V(4, 0.25, 0.12), 0, 4.5, -9.94, S.NeonRed)
	local auxCore = ctx.box("Core", V(1.4, 0.8, 0.12), 1.3, 1.4, -9.94, S.NeonCyan)
	B.pointLight(auxCore, rgb(120, 220, 255), 0.9, 12, {})
	local auxPanel = ctx.box("Panel", V(1.8, 1.8, 0.25), -1.2, 1.9, -9.88, Local.Screen)
	generatorModel(ctx, "GEN-C", "AUX GENERATOR", { auxPanel, auxStatus, auxCore })
	ctx.sign("WarningSign", V(7, 1.4, 0.2), 0, 9, -13.7, 0, 1, "PRESSURE HAZARD", {
		textColor = C.Red,
	})
end

builders.Maintenance = function(ctx)
	ctx.cylX("Pipe", 232, 1.4, 0, 2.2, 6.6, Local.DarkMetal)
	ctx.cylX("Pipe", 232, 0.9, 0, 4.0, 7.0, Local.Gunmetal)
	ctx.cylX("Pipe", 232, 1.2, 0, 10.6, -6.9, Local.DarkMetal)
	for x = -112, 112, 16 do
		ctx.box("PipeBracket", V(0.4, 3.6, 0.5), x, 3.0, 7.6, S.Trim)
	end
	-- Dead ends at both extremities.
	ctx.prop("WoodenCrate", -114, -4, 0)
	ctx.prop("WoodenCrate", -114, -4, 0, 4)
	ctx.prop("Barrel", -114.5, 3.5)
	ctx.prop("StorageBox", -110, 4.5, 90)
	ctx.prop("ToolCart", 113, -4, 90)
	ctx.prop("CleaningSupplies", 114.5, 4, 0)
	ctx.prop("MetalCrate", 109, 4.6, 0)
	-- Scattered along the run (south side, away from doorways).
	ctx.prop("Barrel", 40, 4.5)
	ctx.prop("StorageBox", -50, 5)
	ctx.prop("MetalCrate", -80, 4.6, 0)
	ctx.prop("TrashBin", 70, 5)
	ctx.sign("WarningSign", V(10, 1.4, 0.2), 0, 9, 7.7, 0, -1, "AUTHORISED PERSONNEL ONLY", {
		textColor = C.Red,
	})
end

function Dressing.build(ctx: Ctx)
	local builder = builders[ctx.room.id]
	if builder then
		builder(ctx)
	end
end

-- Extraction lift ---------------------------------------------------------------------

--[[
	Builds the Extraction model used by ExtractionService:
	  LiftZone, GateLeft, GateRight (OpenOffset), StatusScreen (StatusText), LiftLight
]]
function Dressing.buildLift(parent: any, room: Layout.Room, props: any): any
	local lift = B.model(parent, "Extraction")
	local ctx = Dressing.context(room, lift, props)

	-- Facade with a tall header that hides the gate when it rises.
	for _, x in { -11, 11 } do
		ctx.box("FacadePillar", V(2, 24, 2), x, 12, 3, S.TrimLight)
		ctx.box("FacadeGlow", V(0.3, 12, 0.2), x - math.sign(x) * 0.8, 6, 1.95, S.NeonCyan)
	end
	ctx.box("FacadeHeader", V(20, 12, 2), 0, 18, 3, S.WallDark)

	-- Car.
	for _, x in { -10.5, 10.5 } do
		ctx.box("CarWall", V(1, 12, 20), x, 6, 14, S.Trim)
	end
	ctx.box("CarCeiling", V(20, 1, 19), 0, 12.5, 14.5, S.Ceiling)
	ctx.box("CarFloor", V(20, 0.3, 20), 0, 0.15, 14, Local.LiftFloor)
	for i = 0, 9 do
		ctx.box(
			"Threshold",
			V(2, 0.1, 1.2),
			-9 + i * 2,
			0.32,
			4.6,
			if i % 2 == 0 then S.Hazard else S.HazardWhite
		)
	end
	for _, x in { -9.9, 9.9 } do
		ctx.box("CarRail", V(0.25, 0.25, 16), x, 3.6, 14, S.TrimLight)
	end

	local gateStyle = style(rgb(64, 70, 80), M.DiamondPlate, { CastShadow = true })
	for _, info in { { "GateLeft", -5 }, { "GateRight", 5 } } do
		local gate = ctx.box(info[1] :: string, V(10, 12, 0.6), info[2] :: number, 6, 4.5, gateStyle)
		gate:SetAttribute("OpenOffset", V(0, 12.4, 0))
		local gui = B.new("SurfaceGui", {
			Name = "Marking",
			Face = B.Enum.NormalId.Front,
			SizingMode = B.Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 30,
			LightInfluence = 0,
			Brightness = 1.2,
		})
		B.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = B.roblox.UDim2.fromScale(1, 0.18),
			Position = B.roblox.UDim2.fromScale(0, 0.41),
			Text = "E-1",
			TextScaled = true,
			FontFace = B.Fonts.Display,
			TextColor3 = rgb(255, 90, 90),
		}, gui)
		gui.Parent = gate
	end

	local zone = ctx.box("LiftZone", V(18, 10, 17), 0, 5, 14.5, S.Invisible)
	zone.CanCollide = false

	local lightPart = ctx.box("LiftLight", V(4, 0.3, 4), 0, 11.85, 14, S.NeonWhite)
	B.pointLight(lightPart, rgb(255, 70, 70), 2.2, 20)

	B.sign(
		lift,
		"StatusScreen",
		V(16, 2.6, 0.2),
		B.facing(ctx.world(0, 14.6, 1.9), 0, -1),
		"EXTRACTION LOCKED",
		{
			label = "StatusText",
			textColor = rgb(255, 70, 70),
			background = style(rgb(14, 16, 20), M.SmoothPlastic),
			font = B.Fonts.Display,
		}
	)
	B.sign(
		lift,
		"LiftTitle",
		V(18, 3, 0.2),
		B.facing(ctx.world(0, 19.8, 1.9), 0, -1),
		"EXTRACTION LIFT  E-1",
		{
			textColor = C.CyanSoft,
		}
	)

	-- Approach: floor guide toward the gate, benches and lockers, east nook.
	ctx.box("GuideStrip", V(0.6, 0.08, 18), 0, 0.04, -12, S.NeonCyan)
	for i = 0, 3 do
		local z = -18 + i * 5
		ctx.boxCF(
			"GuideChevron",
			V(2.2, 0.08, 0.4),
			CF(-0.75, 0.04, z) * CFrame.Angles(0, math.rad(-35), 0),
			S.NeonCyan
		)
		ctx.boxCF(
			"GuideChevron",
			V(2.2, 0.08, 0.4),
			CF(0.75, 0.04, z) * CFrame.Angles(0, math.rad(35), 0),
			S.NeonCyan
		)
	end
	ctx.propAt("Bench", ctx.at(-16, -12, 90))
	ctx.propAt("Bench", ctx.at(16, -12, -90))
	ctx.propAt("Locker", ctx.at(-16, -22.5, 180))
	ctx.propAt("Locker", ctx.at(16, -22.5, 180))
	ctx.propAt("MetalCrate", ctx.at(18, 20, 0))
	ctx.propAt("StorageBox", ctx.at(20, 12, 90))
	ctx.propAt("SecurityCamera", ctx.at(-23.4, -23.4, -135, 21))
	return lift
end

return Dressing
