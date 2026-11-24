--!strict
--[[
	Architecture — room shells and corridors generated from Layout.

	Rooms: floor + ceiling (extended under the walls so doorways have a floor),
	four walls split around corridor openings, lintels, pilasters, trim,
	ceiling light fixtures, emergency beacons, door frames with destination
	signs, and an invisible RoomZone volume used by the HUD location readout.

	Corridors: floor, ceiling, side walls, chamfered portal ribs (the facility's
	signature silhouette), floor light strips, alternating ceiling lights,
	hanging wayfinding signs and a zone volume.
]]

local B = require("./B")
local Layout = require("./Layout")

local CFrame = B.CFrame
local Vector3 = B.Vector3
local S = B.Styles
local C = B.Colors

local V = Vector3.new
local CF = CFrame.new

local T = Layout.WallThickness

local Architecture = {}

export type Side = "N" | "S" | "E" | "W"

export type Opening = {
	side: Side,
	offset: number,
	width: number,
	height: number,
	leadsTo: Layout.Room,
}

export type CorridorGeometry = {
	corridor: Layout.Corridor,
	a: Layout.Room,
	b: Layout.Room,
	axis: "x" | "z",
	at: number,
	s0: number, -- interior edge of room a along the axis
	s1: number, -- interior edge of room b along the axis
	width: number,
	height: number,
}

local function color(rgbList: { number })
	return B.rgb(rgbList[1], rgbList[2], rgbList[3])
end

-- Side frame: which axis the wall runs along, the interior face coordinate,
-- and the inward normal.
local function sideFrame(room: Layout.Room, side: Side): ("x" | "z", number, number, number)
	if side == "N" then
		return "x", room.cz - room.sz / 2, 0, 1
	elseif side == "S" then
		return "x", room.cz + room.sz / 2, 0, -1
	elseif side == "E" then
		return "z", room.cx + room.sx / 2, -1, 0
	else
		return "z", room.cx - room.sx / 2, 1, 0
	end
end

local function sideLength(room: Layout.Room, side: Side): number
	return if side == "N" or side == "S" then room.sx else room.sz
end

-- World position for a point described relative to a wall:
-- `along` from the room centre, `d` inward from the interior face, height y.
function Architecture.sidePoint(room: Layout.Room, side: Side, along: number, d: number, y: number)
	local axis, face, nx, nz = sideFrame(room, side)
	if axis == "x" then
		return V(room.cx + along, y, face + nz * d)
	end
	return V(face + nx * d, y, room.cz + along)
end

-- Box aligned to a wall. d0..d1 is inward distance (negative = inside wall).
local function sideBox(
	parent: any,
	name: string,
	room: Layout.Room,
	side: Side,
	along: number,
	length: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
	style: B.Style
): any
	local axis, face, nx, nz = sideFrame(room, side)
	local dMid = (d0 + d1) / 2
	local depth = d1 - d0
	local height = y1 - y0
	local yMid = (y0 + y1) / 2
	if axis == "x" then
		return B.part(
			parent,
			name,
			V(length, height, depth),
			CF(room.cx + along, yMid, face + nz * dMid),
			style
		)
	end
	return B.part(parent, name, V(depth, height, length), CF(face + nx * dMid, yMid, room.cz + along), style)
end
Architecture.sideBox = sideBox

function Architecture.inwardNormal(room: Layout.Room, side: Side): (number, number)
	local _, _, nx, nz = sideFrame(room, side)
	return nx, nz
end

-- Corridor geometry + openings ------------------------------------------------------

function Architecture.resolve(): ({ [string]: { Opening } }, { CorridorGeometry })
	local openings: { [string]: { Opening } } = {}
	local geometries: { CorridorGeometry } = {}
	for _, room in Layout.Rooms do
		openings[room.id] = {}
	end

	for _, corridor in Layout.Corridors do
		local a = Layout.room(corridor.a)
		local b = Layout.room(corridor.b)
		local kind = Layout.CorridorKinds[corridor.kind]
		local sideA: Side, sideB: Side, s0: number, s1: number, offA: number, offB: number

		if corridor.axis == "x" then
			local east = b.cx > a.cx
			sideA = if east then "E" else "W"
			sideB = if east then "W" else "E"
			s0 = if east then a.cx + a.sx / 2 else a.cx - a.sx / 2
			s1 = if east then b.cx - b.sx / 2 else b.cx + b.sx / 2
			offA = corridor.at - a.cz
			offB = corridor.at - b.cz
		else
			local south = b.cz > a.cz
			sideA = if south then "S" else "N"
			sideB = if south then "N" else "S"
			s0 = if south then a.cz + a.sz / 2 else a.cz - a.sz / 2
			s1 = if south then b.cz - b.sz / 2 else b.cz + b.sz / 2
			offA = corridor.at - a.cx
			offB = corridor.at - b.cx
		end

		for _, check in { { a, sideA, offA }, { b, sideB, offB } } do
			local room, side, off = check[1] :: Layout.Room, check[2] :: Side, check[3] :: number
			local half = sideLength(room, side) / 2
			assert(
				math.abs(off) + kind.width / 2 <= half,
				`Corridor {corridor.a}->{corridor.b} misses {room.id}'s {side} wall`
			)
			assert(kind.height < room.h, `Corridor taller than {room.id}`)
		end
		assert(math.abs(s1 - s0) > 2 * T + 4, `Corridor {corridor.a}->{corridor.b} is too short`)

		table.insert(
			openings[a.id],
			{ side = sideA, offset = offA, width = kind.width, height = kind.height, leadsTo = b }
		)
		table.insert(
			openings[b.id],
			{ side = sideB, offset = offB, width = kind.width, height = kind.height, leadsTo = a }
		)
		table.insert(geometries, {
			corridor = corridor,
			a = a,
			b = b,
			axis = corridor.axis,
			at = corridor.at,
			s0 = s0,
			s1 = s1,
			width = kind.width,
			height = kind.height,
		})
	end

	return openings, geometries
end

-- Rooms -----------------------------------------------------------------------------

local function nearOpening(list: { Opening }, side: Side, along: number, margin: number): boolean
	for _, opening in list do
		if opening.side == side and math.abs(along - opening.offset) < opening.width / 2 + margin then
			return true
		end
	end
	return false
end

local function buildWallSide(
	model: any,
	room: Layout.Room,
	side: Side,
	openings: { Opening },
	wallStyle: B.Style
)
	local isNS = side == "N" or side == "S"
	-- N/S walls also cover the corners.
	local half = if isNS then room.sx / 2 + T else room.sz / 2
	local onSide = {}
	for _, opening in openings do
		if opening.side == side then
			table.insert(onSide, opening)
		end
	end
	table.sort(onSide, function(x, y)
		return x.offset < y.offset
	end)

	local cursor = -half
	local segments: { { number } } = {}
	for _, opening in onSide do
		local left = opening.offset - opening.width / 2
		local right = opening.offset + opening.width / 2
		if left > cursor then
			table.insert(segments, { cursor, left })
		end
		-- Lintel above the doorway.
		sideBox(
			model,
			"Lintel",
			room,
			side,
			opening.offset,
			opening.width,
			opening.height,
			room.h,
			-T,
			0,
			wallStyle
		)
		cursor = right
	end
	if cursor < half then
		table.insert(segments, { cursor, half })
	end

	for _, seg in segments do
		local length = seg[2] - seg[1]
		local mid = (seg[1] + seg[2]) / 2
		sideBox(model, "Wall", room, side, mid, length, 0, room.h, -T, 0, wallStyle)
		-- Interior trim only along the interior span.
		local innerHalf = sideLength(room, side) / 2
		local a0 = math.max(seg[1], -innerHalf)
		local a1 = math.min(seg[2], innerHalf)
		if a1 - a0 > 0.5 then
			sideBox(model, "Baseboard", room, side, (a0 + a1) / 2, a1 - a0, 0, 0.8, 0, 0.3, S.WallDark)
			sideBox(
				model,
				"Cornice",
				room,
				side,
				(a0 + a1) / 2,
				a1 - a0,
				room.h - 0.8,
				room.h,
				0,
				0.5,
				S.Trim
			)
		end
	end

	-- Pilasters for rhythm, skipping doorways.
	local innerHalf = sideLength(room, side) / 2
	local spacing = 12
	local count = math.floor((innerHalf * 2 - 8) / spacing)
	for i = 0, count do
		local along = -innerHalf + 4 + i * spacing
		if along < innerHalf - 3 and not nearOpening(openings, side, along, 2.5) then
			sideBox(model, "Pilaster", room, side, along, 1.4, 0, room.h - 0.8, 0, 0.7, S.Trim)
		end
	end
end

local function buildDoorFrames(model: any, room: Layout.Room, openings: { Opening })
	for _, opening in openings do
		local w, h, off, side = opening.width, opening.height, opening.offset, opening.side
		sideBox(model, "Jamb", room, side, off - w / 2 - 0.5, 1, 0, h + 1, 0, 0.9, S.TrimLight)
		sideBox(model, "Jamb", room, side, off + w / 2 + 0.5, 1, 0, h + 1, 0, 0.9, S.TrimLight)
		sideBox(model, "Header", room, side, off, w, h, h + 1, 0, 0.9, S.TrimLight)
		sideBox(model, "HeaderGlow", room, side, off, w - 1, h + 0.35, h + 0.65, 0.9, 1.0, S.NeonCyan)
		-- Threshold plate
		sideBox(model, "Threshold", room, side, off, w, 0, 0.08, -T, 0.6, S.Trim)
		-- Lockdown slab (FacilityService): invisible and non-colliding until a
		-- sabotage seals this doorway for a few seconds.
		local slab = sideBox(model, "LockdownDoor", room, side, off, w, 0.08, h, 0.15, 0.55, S.Invisible)
		B.tag(slab, "LockdownDoor")
		B.attrs(slab, { Room = room.name, LeadsTo = opening.leadsTo.name })

		-- Destination sign above the door, facing into the room.
		local nx, nz = Architecture.inwardNormal(room, side)
		local signHeight = 1.6
		local signY = h + 1 + 0.25 + signHeight / 2
		if signY + signHeight / 2 < room.h - 0.9 then
			local pos = Architecture.sidePoint(room, side, off, 0.75, signY)
			local width = math.min(w + 2, 16)
			B.sign(
				model,
				"DoorSign",
				V(width, signHeight, 0.2),
				B.facing(pos, nx, nz),
				opening.leadsTo.name,
				{
					textColor = C.CyanSoft,
					background = S.WallDark,
				}
			)
		end
	end
end

local function buildCeilingLights(model: any, room: Layout.Room)
	local nx = math.max(1, math.ceil(room.sx / 24))
	local nz = math.max(1, math.ceil(room.sz / 24))
	local range = math.clamp(room.h + 10, 18, 32)
	local lightColor = color(room.lightColor)
	for ix = 1, nx do
		for iz = 1, nz do
			local x = room.cx - room.sx / 2 + room.sx * (ix - 0.5) / nx
			local z = room.cz - room.sz / 2 + room.sz * (iz - 0.5) / nz
			B.part(model, "FixtureHousing", V(6.8, 0.4, 2), CF(x, room.h - 0.2, z), S.Trim)
			local panel = B.part(model, "Fixture", V(6, 0.2, 1.3), CF(x, room.h - 0.45, z), S.NeonWhite)
			B.pointLight(panel, lightColor, room.lightBrightness, range)
		end
	end
end

local function buildEmergencyBeacons(model: any, room: Layout.Room)
	local corners = {
		{ "N", -room.sx / 2 + 3 },
		{ "S", room.sx / 2 - 3 },
	}
	for _, corner in corners do
		local side = corner[1] :: Side
		local beacon = sideBox(
			model,
			"EmergencyBeacon",
			room,
			side,
			corner[2] :: number,
			1.4,
			room.h - 3,
			room.h - 2.3,
			0,
			0.6,
			S.Beacon
		)
		B.tag(beacon, "EmergencyBeacon")
		local light = B.pointLight(beacon, C.Red, 1.8, 26, { "EmergencyLight" })
		light.Enabled = false
	end
end

function Architecture.buildRoom(parent: any, zonesFolder: any, room: Layout.Room, openings: { Opening }): any
	local model = B.model(parent, room.id)
	B.attrs(model, { DisplayName = room.name, Code = room.code })
	local wallStyle = (S :: any)[room.wall] :: B.Style
	local floorStyle = (S :: any)[room.floor] :: B.Style

	B.part(model, "Floor", V(room.sx + 2 * T, 1, room.sz + 2 * T), CF(room.cx, -0.5, room.cz), floorStyle)
	B.part(
		model,
		"Ceiling",
		V(room.sx + 2 * T, 1, room.sz + 2 * T),
		CF(room.cx, room.h + 0.5, room.cz),
		S.Ceiling
	)

	for _, side in { "N", "S", "E", "W" } :: { Side } do
		buildWallSide(model, room, side, openings, wallStyle)
	end
	buildDoorFrames(model, room, openings)
	buildCeilingLights(model, room)
	buildEmergencyBeacons(model, room)

	-- Invisible volume used by the client HUD to show the player's location.
	local zone = B.part(
		zonesFolder,
		room.id,
		V(room.sx, room.h, room.sz),
		CF(room.cx, room.h / 2, room.cz),
		S.Invisible
	)
	B.tag(zone, "RoomZone")
	B.attrs(zone, { DisplayName = room.name, Code = room.code })
	return model
end

-- Corridors ---------------------------------------------------------------------------

function Architecture.buildCorridor(parent: any, zonesFolder: any, geo: CorridorGeometry, index: number): any
	local name = `{geo.a.id}_{geo.b.id}`
	local model = B.model(parent, name)
	local kindInfo = Layout.CorridorKinds[geo.corridor.kind]
	local w, h = geo.width, geo.height
	local dir = if geo.s1 > geo.s0 then 1 else -1
	local inner0 = geo.s0 + dir * T
	local inner1 = geo.s1 - dir * T
	local length = math.abs(inner1 - inner0)
	local center = (inner0 + inner1) / 2

	-- Local frame: +X runs along the corridor from room a toward room b.
	local origin: any
	if geo.axis == "x" then
		origin = CF(center, 0, geo.at) * CFrame.Angles(0, if dir > 0 then 0 else math.pi, 0)
	else
		-- Yaw -90° maps local +X to world +Z.
		origin = CF(geo.at, 0, center) * CFrame.Angles(0, if dir > 0 then -math.pi / 2 else math.pi / 2, 0)
	end
	local function box(
		partName: string,
		size: any,
		x: number,
		y: number,
		z: number,
		style: B.Style,
		extra: any?
	): any
		local cf = origin * CF(x, y, z)
		if extra then
			cf *= extra
		end
		return B.part(model, partName, size, cf, style)
	end

	local isService = geo.corridor.kind == "Service"
	local floorStyle = if isService then S.Grate else S.Floor
	local wallStyle = if isService then S.WallConcrete else S.Wall

	box("Floor", V(length, 1, w + 2 * T), 0, -0.5, 0, floorStyle)
	box("Ceiling", V(length, 1, w + 2 * T), 0, h + 0.5, 0, S.Ceiling)
	box("WallL", V(length, h, T), 0, h / 2, -(w / 2 + T / 2), wallStyle)
	box("WallR", V(length, h, T), 0, h / 2, w / 2 + T / 2, wallStyle)
	box("StripL", V(length, 0.1, 0.3), 0, 0.05, -(w / 2 - 0.45), S.NeonCyan)
	box("StripR", V(length, 0.1, 0.3), 0, 0.05, w / 2 - 0.45, S.NeonCyan)

	-- Portal ribs.
	local lightColor = if isService then B.rgb(255, 176, 150) else B.rgb(200, 230, 255)
	local ribSpacing = 10
	local ribCount = math.max(1, math.floor((length - 10) / ribSpacing) + 1)
	local firstRib = -((ribCount - 1) * ribSpacing) / 2
	for i = 0, ribCount - 1 do
		local x = firstRib + i * ribSpacing
		for _, sgn in { -1, 1 } do
			box("RibPillar", V(1, h, 0.7), x, h / 2, sgn * (w / 2 - 0.35), S.Trim)
			box(
				"RibBrace",
				V(1, 0.7, 2.6),
				x,
				h - 1.65,
				sgn * (w / 2 - 1.55),
				S.Trim,
				CFrame.Angles(math.rad(sgn * 45), 0, 0)
			)
		end
		box("RibBeam", V(1, 0.8, w), x, h - 0.4, 0, S.Trim)
		if i % 2 == 0 then
			local fixture = box("Fixture", V(0.5, 0.2, w * 0.45), x, h - 0.9, 0, S.NeonWhite)
			B.pointLight(fixture, lightColor, if isService then 0.8 else 1.0, 16)
		end
	end

	-- Emergency beacon mid-corridor.
	local beacon =
		box("EmergencyBeacon", V(1.4, 0.6, 0.5), firstRib + ribSpacing / 2, h - 2.4, w / 2 - 0.25, S.Beacon)
	B.tag(beacon, "EmergencyBeacon")
	local red = B.pointLight(beacon, C.Red, 1.6, 20, { "EmergencyLight" })
	red.Enabled = false

	-- Hanging wayfinding signs: near each end, facing the approaching player.
	local signWidth = w * 0.7
	local signY = h - 2.2
	for _, endInfo in { { -1, geo.a }, { 1, geo.b } } do
		local endSign = endInfo[1] :: number
		local room = endInfo[2] :: Layout.Room
		local x = endSign * (length / 2 - 2.5)
		-- Face toward the corridor interior (-endSign along local X).
		local cf = origin
			* CF(x, signY, 0)
			* CFrame.Angles(0, if endSign > 0 then math.pi / 2 else -math.pi / 2, 0)
		B.sign(model, "WaySign", V(signWidth, 1.4, 0.2), cf, `{room.code}  //  {room.name}`, {
			textColor = if room.id == "Extraction" then C.Red else C.CyanSoft,
		})
		for _, rodZ in { -signWidth / 2 + 0.6, signWidth / 2 - 0.6 } do
			box("SignRod", V(0.15, 1.4, 0.15), x, h - 0.75, rodZ, S.Trim)
		end
	end

	local zone = box("Zone", V(length + 2 * T, h, w), 0, h / 2, 0, S.Invisible)
	zone.Name = name
	zone.Parent = zonesFolder
	B.tag(zone, "RoomZone")
	B.attrs(zone, {
		DisplayName = kindInfo.name,
		Code = string.format("C-%02d", index),
	})

	return model
end

return Architecture
