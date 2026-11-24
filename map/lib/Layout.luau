--!strict
--[[
	Layout — the facility floor plan as data.

	Coordinates: X east, Z south, Y up; studs. Room centre + interior size.
	Corridors connect the facing walls of two rooms along an axis at a fixed
	coordinate (`at`). Openings are derived from corridors automatically.

	                [GENERATOR]──[SERVER VAULT]──[SECURITY]
	                     │             │              │
	                 [STORAGE]────[ATRIUM]────────[OFFICES]────[RESEARCH]
	                     │             │              │
	                  [PUMP]      [EXTRACTION]    [MEDICAL]
	                     │             │              │
	                  ═══════════ MAINTENANCE TUNNEL ═══════════
]]

export type Room = {
	id: string,
	name: string,
	code: string,
	cx: number,
	cz: number,
	sx: number,
	sz: number,
	h: number,
	wall: string, -- style key in B.Styles
	floor: string,
	lightColor: { number },
	lightBrightness: number,
	spawns: { { number } }, -- local {x, z}
}

export type Corridor = {
	a: string,
	b: string,
	axis: "x" | "z",
	at: number,
	kind: "Main" | "Service",
}

local Layout = {}

Layout.WallThickness = 2

Layout.CorridorKinds = {
	Main = { width = 12, height = 12, name = "CORRIDOR" },
	Service = { width = 10, height = 10, name = "SERVICE DUCT" },
}

Layout.Rooms = {
	{
		id = "Atrium",
		name = "CENTRAL ATRIUM",
		code = "SECTOR 00",
		cx = 0,
		cz = 0,
		sx = 64,
		sz = 64,
		h = 24,
		wall = "Wall",
		floor = "Floor",
		lightColor = { 200, 232, 255 },
		lightBrightness = 1.1,
		spawns = { { -24, -10 }, { 24, 10 }, { 10, -21 }, { -10, 21 } },
	},
	{
		id = "Server",
		name = "SERVER VAULT",
		code = "SECTOR 03",
		cx = 0,
		cz = -96,
		sx = 56,
		sz = 48,
		h = 18,
		wall = "WallDark",
		floor = "Grate",
		lightColor = { 90, 150, 255 },
		lightBrightness = 1.2,
		spawns = { { -24, 16 }, { 24, -15.5 } },
	},
	{
		id = "Generator",
		name = "GENERATOR HALL",
		code = "SECTOR 01",
		cx = -104,
		cz = -96,
		sx = 56,
		sz = 56,
		h = 24,
		wall = "WallConcrete",
		floor = "FloorDark",
		lightColor = { 255, 206, 170 },
		lightBrightness = 1.0,
		spawns = { { -14, 18 }, { 16, 21 } },
	},
	{
		id = "Security",
		name = "SECURITY OFFICE",
		code = "SECTOR 04",
		cx = 104,
		cz = -96,
		sx = 52,
		sz = 44,
		h = 16,
		wall = "WallDark",
		floor = "FloorDark",
		lightColor = { 120, 220, 255 },
		lightBrightness = 1.0,
		spawns = { { 16, 12 }, { -18, -8 } },
	},
	{
		id = "Storage",
		name = "STORAGE BAY",
		code = "SECTOR 02",
		cx = -104,
		cz = 0,
		sx = 56,
		sz = 56,
		h = 20,
		wall = "WallConcrete",
		floor = "Floor",
		lightColor = { 230, 236, 245 },
		lightBrightness = 0.9,
		spawns = { { -20, -20 }, { 20, 18 } },
	},
	{
		id = "Office",
		name = "ADMIN OFFICES",
		code = "SECTOR 05",
		cx = 104,
		cz = 0,
		sx = 60,
		sz = 56,
		h = 16,
		wall = "Wall",
		floor = "FloorTile",
		lightColor = { 215, 228, 255 },
		lightBrightness = 1.0,
		spawns = { { -27, -25 }, { 27, 25 } },
	},
	{
		id = "Research",
		name = "RESEARCH LAB",
		code = "SECTOR 06",
		cx = 208,
		cz = 0,
		sx = 56,
		sz = 60,
		h = 18,
		wall = "WallPanelLight",
		floor = "FloorTile",
		lightColor = { 190, 245, 255 },
		lightBrightness = 1.0,
		spawns = { { -20, 22 }, { 20, -22 } },
	},
	{
		id = "Medical",
		name = "MEDICAL BAY",
		code = "SECTOR 07",
		cx = 104,
		cz = 100,
		sx = 48,
		sz = 48,
		h = 16,
		wall = "WallPanelLight",
		floor = "FloorTile",
		lightColor = { 240, 248, 255 },
		lightBrightness = 1.1,
		spawns = { { -12, 0 }, { 16, 14 } },
	},
	{
		id = "Extraction",
		name = "EXTRACTION LIFT",
		code = "SECTOR 09",
		cx = 0,
		cz = 100,
		sx = 48,
		sz = 48,
		h = 24,
		wall = "WallDark",
		floor = "Floor",
		lightColor = { 170, 225, 255 },
		lightBrightness = 1.0,
		spawns = {},
	},
	{
		id = "Pump",
		name = "PUMP STATION",
		code = "SECTOR 08-B",
		cx = -104,
		cz = 80,
		sx = 28,
		sz = 28,
		h = 12,
		wall = "WallConcrete",
		floor = "Grate",
		lightColor = { 255, 150, 120 },
		lightBrightness = 0.8,
		spawns = { { 8, 8 } },
	},
	{
		id = "Maintenance",
		name = "MAINTENANCE TUNNEL",
		code = "SECTOR 08",
		cx = 0,
		cz = 150,
		sx = 236,
		sz = 16,
		h = 12,
		wall = "WallConcrete",
		floor = "Grate",
		lightColor = { 255, 170, 140 },
		lightBrightness = 0.75,
		spawns = { { -70, 0 }, { 60, 0 } },
	},
} :: { Room }

Layout.Corridors = {
	{ a = "Atrium", b = "Server", axis = "z", at = 0, kind = "Main" },
	{ a = "Atrium", b = "Storage", axis = "x", at = 0, kind = "Main" },
	{ a = "Atrium", b = "Office", axis = "x", at = 0, kind = "Main" },
	{ a = "Atrium", b = "Extraction", axis = "z", at = 0, kind = "Main" },
	{ a = "Generator", b = "Server", axis = "x", at = -96, kind = "Main" },
	{ a = "Server", b = "Security", axis = "x", at = -96, kind = "Main" },
	{ a = "Generator", b = "Storage", axis = "z", at = -104, kind = "Main" },
	{ a = "Security", b = "Office", axis = "z", at = 104, kind = "Main" },
	{ a = "Office", b = "Research", axis = "x", at = 0, kind = "Main" },
	{ a = "Office", b = "Medical", axis = "z", at = 104, kind = "Main" },
	{ a = "Storage", b = "Pump", axis = "z", at = -104, kind = "Service" },
	{ a = "Pump", b = "Maintenance", axis = "z", at = -104, kind = "Service" },
	{ a = "Extraction", b = "Maintenance", axis = "z", at = -18, kind = "Service" },
	{ a = "Medical", b = "Maintenance", axis = "z", at = 104, kind = "Service" },
} :: { Corridor }

function Layout.room(id: string): Room
	for _, room in Layout.Rooms do
		if room.id == id then
			return room
		end
	end
	error(`Unknown room '{id}'`)
end

-- Deployment Bay (pre-round lobby), isolated north of the facility.
Layout.Bay = { cx = 0, cz = -330, sx = 72, sz = 56, h = 20 }

return Layout
