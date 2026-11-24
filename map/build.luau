--!strict
--[[
	Facility generator.  Run:  lune run map/build

	Outputs (consumed by default.project.json):
	  build/Facility.rbxm       Workspace.Facility
	  build/DeploymentBay.rbxm  Workspace.DeploymentBay
	  build/PropLibrary.rbxm    ReplicatedStorage.Assets.Props (templates)
	  build/mapdata.json        geometry export for automated layout checks

	The generator is the source of truth for the map. To hand-edit the map in
	Studio instead, remove the Facility/DeploymentBay entries from the project
	file after the first build and keep the place file as the source.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Architecture = require("./lib/Architecture")
local B = require("./lib/B")
local Dressing = require("./lib/Dressing")
local Layout = require("./lib/Layout")
local Props = require("./lib/Props")

local CFrame = B.CFrame
local Vector3 = B.Vector3
local S = B.Styles
local C = B.Colors
local rgb = B.rgb
local V = Vector3.new
local CF = CFrame.new

local roblox = B.roblox

-- Facility -------------------------------------------------------------------------

local facility = B.new("Folder", { Name = "Facility" })
local architecture = B.folder(facility, "Architecture")
local roomsFolder = B.folder(architecture, "Rooms")
local corridorsFolder = B.folder(architecture, "Corridors")
local propsFolder = B.folder(facility, "Props")
local spawnsFolder = B.folder(facility, "Spawns")
local zonesFolder = B.folder(facility, "Zones")

local openings, geometries = Architecture.resolve()

for _, room in Layout.Rooms do
	local model = Architecture.buildRoom(roomsFolder, zonesFolder, room, openings[room.id])
	Dressing.build(Dressing.context(room, model, propsFolder))

	for _, spawn in room.spawns do
		local x, z = spawn[1], spawn[2]
		local marker = B.part(
			spawnsFolder,
			`{room.id}Spawn`,
			V(2, 1, 2),
			CF(room.cx + x, 3.2, room.cz + z) * CFrame.Angles(0, B.yawFacing(-x, -z), 0),
			S.Invisible
		)
		B.tag(marker, "FacilitySpawn")
		marker:SetAttribute("Room", room.id)
	end
end

for index, geometry in geometries do
	Architecture.buildCorridor(corridorsFolder, zonesFolder, geometry, index)
end

Dressing.buildLift(facility, Layout.room("Extraction"), propsFolder)

-- Deployment Bay -----------------------------------------------------------------------

local bayInfo = Layout.Bay
local bayRoom: Layout.Room = {
	id = "DeploymentBay",
	name = "DEPLOYMENT BAY",
	code = "STANDBY",
	cx = bayInfo.cx,
	cz = bayInfo.cz,
	sx = bayInfo.sx,
	sz = bayInfo.sz,
	h = bayInfo.h,
	wall = "Wall",
	floor = "Floor",
	lightColor = { 210, 232, 255 },
	lightBrightness = 1.2,
	spawns = {},
}

local bay = B.new("Model", { Name = "DeploymentBay" })
local bayZones = B.folder(bay, "Zones")
local bayShell = Architecture.buildRoom(bay, bayZones, bayRoom, {})
-- The bay is outside the facility: it must not react to facility lighting modes.
for _, descendant in bayShell:GetDescendants() do
	if descendant:HasTag("EmergencyBeacon") then
		descendant.Parent = nil
	elseif descendant:HasTag("FacilityLight") then
		descendant:RemoveTag("FacilityLight")
		descendant:AddTag("BayLight")
	end
end

local bayProps = B.folder(bay, "Props")
local bayCtx = Dressing.context(bayRoom, bay, bayProps)

-- Spawn area: one neutral SpawnLocation plus tagged pads around it.
local spawnCenterZ = 13
local spawnLocation = B.new("SpawnLocation", {
	Name = "BaySpawn",
	Anchored = true,
	Size = V(8, 1, 8),
	CFrame = CF(bayRoom.cx, 0.5, bayRoom.cz + spawnCenterZ),
	Color = rgb(34, 37, 44),
	Material = B.Enum.Material.Metal,
	Neutral = true,
	Duration = 0,
	AllowTeamChangeOnTouch = false,
	TopSurface = B.Enum.SurfaceType.Smooth,
	BottomSurface = B.Enum.SurfaceType.Smooth,
})
spawnLocation.Parent = bay
bayCtx.cylY("SpawnRing", 0.12, 9.2, 0, 0.06, spawnCenterZ, S.NeonCyan)

local pads = B.folder(bay, "LobbySpawns")
for i = 0, 7 do
	local a = 2 * math.pi * i / 8
	local x, z = math.sin(a) * 10, spawnCenterZ - math.cos(a) * 10
	bayCtx.cylY("Pad", 0.1, 3.4, x, 0.05, z, S.NeonCyan)
	bayCtx.cylY("PadBase", 0.12, 3, x, 0.08, z, S.Trim)
	local marker = B.part(
		pads,
		"LobbySpawn",
		V(2, 1, 2),
		CF(bayRoom.cx + x, 3.2, bayRoom.cz + z) * CFrame.Angles(0, B.yawFacing(0, -1), 0),
		S.Invisible
	)
	B.tag(marker, "LobbySpawn")
end

-- Status screen (driven locally by the client's BayScreenController).
local screen = B.part(
	bay,
	"StatusScreen",
	V(30, 10, 0.4),
	B.facing(V(bayRoom.cx, 10.5, bayRoom.cz - bayRoom.sz / 2 + 0.4), 0, 1),
	{
		Color = rgb(12, 14, 18),
		Material = B.Enum.Material.SmoothPlastic,
		CastShadow = false,
	}
)
B.tag(screen, "BayScreen")
local screenGui = B.new("SurfaceGui", {
	Name = "Display",
	Face = B.Enum.NormalId.Front,
	SizingMode = B.Enum.SurfaceGuiSizingMode.PixelsPerStud,
	PixelsPerStud = 40,
	LightInfluence = 0,
	Brightness = 1.3,
})
local UDim2 = roblox.UDim2
local function screenLabel(name: string, text: string, y: number, height: number, font: any, color: any)
	B.new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, y),
		Size = UDim2.fromScale(0.9, height),
		Text = text,
		TextScaled = true,
		FontFace = font,
		TextColor3 = color,
	}, screenGui)
end
screenLabel("Phase", "AWAITING PERSONNEL", 0.08, 0.2, B.Fonts.Display, C.CyanSoft)
screenLabel("Timer", "--:--", 0.32, 0.38, B.Fonts.Mono, rgb(235, 242, 250))
screenLabel("Detail", "Stand by for deployment.", 0.74, 0.16, B.Fonts.Body, rgb(150, 164, 182))
screenGui.Parent = screen
bayCtx.box("ScreenFrame", V(31.4, 11.4, 0.3), 0, 10.5, -bayRoom.sz / 2 + 0.15, S.Trim)

B.sign(
	bay,
	"Title",
	V(34, 2.6, 0.2),
	B.facing(V(bayRoom.cx, 17.4, bayRoom.cz - bayRoom.sz / 2 + 0.3), 0, 1),
	"THE MIMIC PROTOCOL",
	{
		textColor = rgb(235, 242, 250),
		background = S.WallDark,
	}
)

-- Holo-table: a scaled mini-map of the facility so players learn the layout.
local tableZ = -8
bayCtx.box("HoloTable", V(32, 3, 26), 0, 1.5, tableZ, S.Trim)
bayCtx.box("HoloTableTop", V(31, 0.2, 25), 0, 3.1, tableZ, {
	Color = rgb(14, 20, 28),
	Material = B.Enum.Material.Glass,
	Transparency = 0.1,
	CastShadow = false,
})
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, room in Layout.Rooms do
	minX = math.min(minX, room.cx - room.sx / 2)
	maxX = math.max(maxX, room.cx + room.sx / 2)
	minZ = math.min(minZ, room.cz - room.sz / 2)
	maxZ = math.max(maxZ, room.cz + room.sz / 2)
end
local scale = 1 / 14
local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2
local function toTable(x: number, z: number): (number, number)
	return (x - midX) * scale, tableZ + (z - midZ) * scale
end
local mapY = 3.25
for _, room in Layout.Rooms do
	local x, z = toTable(room.cx, room.cz)
	local w, d = room.sx * scale, room.sz * scale
	local isLift = room.id == "Extraction"
	local tile = if isLift then S.NeonRed else S.NeonBlue
	bayCtx.box("MapRoom", V(w, 0.06, d), x, mapY, z, {
		Color = tile.Color,
		Material = B.Enum.Material.Neon,
		Transparency = 0.75,
		CanCollide = false,
		CastShadow = false,
	})
	local edge = if isLift then S.NeonRed else S.NeonCyan
	bayCtx.box("MapEdge", V(w, 0.08, 0.12), x, mapY + 0.02, z - d / 2, edge)
	bayCtx.box("MapEdge", V(w, 0.08, 0.12), x, mapY + 0.02, z + d / 2, edge)
	bayCtx.box("MapEdge", V(0.12, 0.08, d), x - w / 2, mapY + 0.02, z, edge)
	bayCtx.box("MapEdge", V(0.12, 0.08, d), x + w / 2, mapY + 0.02, z, edge)
	local labelWidth = math.max(3, math.min(w * 0.95, 9))
	bayCtx.sign("MapLabel", V(labelWidth, 0.8, 0.05), x, mapY + 0.75, z, 0, 1, room.name, {
		background = S.Invisible,
		textColor = if isLift then rgb(255, 120, 120) else C.CyanSoft,
		pixelsPerStud = 60,
	})
end
for _, geometry in geometries do
	local x0, z0, x1, z1
	if geometry.axis == "x" then
		x0, z0 = toTable(geometry.s0, geometry.at)
		x1, z1 = toTable(geometry.s1, geometry.at)
	else
		x0, z0 = toTable(geometry.at, geometry.s0)
		x1, z1 = toTable(geometry.at, geometry.s1)
	end
	local size = if geometry.axis == "x"
		then V(math.abs(x1 - x0), 0.06, 0.3)
		else V(0.3, 0.06, math.abs(z1 - z0))
	bayCtx.box("MapCorridor", size, (x0 + x1) / 2, mapY + 0.01, (z0 + z1) / 2, S.NeonCyan)
end
local projector = bayCtx.box("HoloProjector", V(2, 0.4, 2), 0, 3.4, tableZ, S.NeonCyan)
B.pointLight(projector, rgb(110, 220, 255), 0.9, 16, { "BayLight" })

-- Seating and dressing.
bayCtx.prop("Bench", -21, tableZ, 90)
bayCtx.prop("Bench", 21, tableZ, -90)
bayCtx.prop("Bench", -24, 22, 0)
bayCtx.prop("Bench", 24, 22, 0)
for i = 0, 4 do
	bayCtx.prop("Locker", -34.5, -18 + i * 3.2, -90)
	bayCtx.prop("Locker", 34.5, -18 + i * 3.2, 90)
end
bayCtx.prop("PottedPlant", -33, 25)
bayCtx.prop("PottedPlant", 33, 25)
bayCtx.prop("PottedPlant", -33, -25)
bayCtx.prop("PottedPlant", 33, -25)
-- Bay props are decoration only; they are never Mimic disguise targets.
for _, descendant in bayProps:GetDescendants() do
	if descendant:HasTag("MimicProp") then
		descendant:RemoveTag("MimicProp")
	end
end

-- Prop library templates -----------------------------------------------------------------

local library = B.new("Folder", { Name = "Props" })
for _, id in Props.order do
	Props.build(id, library, CF(0, 0, 0))
end

-- Serialize ---------------------------------------------------------------------------------

fs.writeDir("build")
fs.writeFile("build/Facility.rbxm", roblox.serializeModel({ facility }))
fs.writeFile("build/DeploymentBay.rbxm", roblox.serializeModel({ bay }))
fs.writeFile("build/PropLibrary.rbxm", roblox.serializeModel({ library }))

-- Geometry export + stats -------------------------------------------------------------------

local function vec(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local collidable = {}
local counts = { parts = 0, lights = 0, activeLights = 0, props = 0, transformable = 0, signs = 0 }
local function scan(root: any, label: string)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			counts.parts += 1
			if d.CanCollide and d.Transparency < 1 then
				local cf = d.CFrame
				table.insert(collidable, {
					name = d.Name,
					group = label,
					pos = vec(cf.Position),
					size = vec(d.Size),
					right = vec(cf.RightVector),
					up = vec(cf.UpVector),
					look = vec(cf.LookVector),
				})
			end
		elseif d:IsA("Light") then
			counts.lights += 1
			if d.Enabled then
				counts.activeLights += 1
			end
		elseif d:IsA("SurfaceGui") then
			counts.signs += 1
		end
	end
end
scan(facility, "facility")
scan(bay, "bay")

local propList = {}
for _, model in propsFolder:GetChildren() do
	counts.props += 1
	if model:HasTag("MimicProp") then
		counts.transformable += 1
	end
	local body = model.PrimaryPart
	table.insert(propList, {
		id = model.Name,
		pos = vec(body.CFrame.Position),
		transformable = model:HasTag("MimicProp"),
	})
end

local spawnList = {}
for _, marker in spawnsFolder:GetChildren() do
	table.insert(spawnList, { room = marker:GetAttribute("Room"), pos = vec(marker.CFrame.Position) })
end
local lobbyList = {}
for _, marker in pads:GetChildren() do
	table.insert(lobbyList, vec(marker.CFrame.Position))
end

local roomList = {}
for _, room in Layout.Rooms do
	table.insert(
		roomList,
		{ id = room.id, name = room.name, cx = room.cx, cz = room.cz, sx = room.sx, sz = room.sz, h = room.h }
	)
end
local corridorList = {}
for _, g in geometries do
	table.insert(
		corridorList,
		{ a = g.a.id, b = g.b.id, axis = g.axis, at = g.at, s0 = g.s0, s1 = g.s1, width = g.width }
	)
end
local openingList = {}
for roomId, list in openings do
	for _, o in list do
		table.insert(openingList, { room = roomId, side = o.side, offset = o.offset, width = o.width })
	end
end

local liftZone = facility:FindFirstChild("Extraction"):FindFirstChild("LiftZone")

fs.writeFile(
	"build/mapdata.json",
	serde.encode("json", {
		rooms = roomList,
		corridors = corridorList,
		openings = openingList,
		props = propList,
		spawns = spawnList,
		lobbySpawns = lobbyList,
		liftZone = { pos = vec(liftZone.CFrame.Position), size = vec(liftZone.Size) },
		collidable = collidable,
		wallThickness = Layout.WallThickness,
		bay = Layout.Bay,
	}, false)
)

print(
	string.format(
		"Facility built: %d parts, %d lights (%d on by default), %d props (%d transformable), %d signs, %d facility spawns, %d lobby spawns, %d prop templates",
		counts.parts,
		counts.lights,
		counts.activeLights,
		counts.props,
		counts.transformable,
		counts.signs,
		#spawnList,
		#lobbyList,
		#Props.order
	)
)
