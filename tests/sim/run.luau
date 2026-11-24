--!nonstrict
--[[
	End-to-end server simulation:  lune run tests/sim/run

	Loads the real src/server and src/shared modules into the Mock runtime,
	connects simulated players, and drives several consecutive rounds on one
	server, asserting on the authoritative state and on every message the
	server sends to each client.

	Requires build/mapdata.json (lune run map/build) for real spawn and lift
	geometry.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Mock = require("./Mock")

local CFrame, Vector3 = Mock.CFrame, Mock.Vector3
local game = Mock.game

-- Mount the project ---------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local shared = Mock.new("Folder", { Name = "Shared", Parent = ReplicatedStorage })
Mock.mount("src/shared", shared)

local remotes = Mock.new("Folder", { Name = "Remotes", Parent = ReplicatedStorage })
for _, name in
	{
		"ClientReady",
		"SetAfk",
		"RequestStrike",
		"RequestAbility",
		"RequestSabotage",
		"PrivateState",
		"RoleReveal",
		"AbilityState",
		"Announcement",
		"EliminationFx",
		"RoundResult",
	}
do
	Mock.new("RemoteEvent", { Name = name, Parent = remotes })
end
local roundState = Mock.new("Folder", { Name = "RoundState", Parent = ReplicatedStorage })
roundState:SetAttribute("Phase", "Waiting")

local serverFolder = Mock.new("Folder", { Name = "Server", Parent = game:GetService("ServerScriptService") })
Mock.mount("src/server", serverFolder)

-- Map content from the generator's export ---------------------------------------------------

local data = serde.decode("json", fs.readFile("build/mapdata.json"))
local facility = Mock.new("Folder", { Name = "Facility", Parent = Workspace })
local extraction = Mock.new("Model", { Name = "Extraction", Parent = facility })
local lz = data.liftZone
local liftZone = Mock.new("Part", {
	Name = "LiftZone",
	CFrame = CFrame.new(lz.pos[1], lz.pos[2], lz.pos[3]),
	Size = Vector3.new(lz.size[1], lz.size[2], lz.size[3]),
	Parent = extraction,
})
for _, gateName in { "GateLeft", "GateRight" } do
	local gate = Mock.new(
		"Part",
		{ Name = gateName, CFrame = CFrame.new(lz.pos[1], 6, lz.pos[3] - 9), Parent = extraction }
	)
	gate:SetAttribute("OpenOffset", Vector3.new(0, 12.4, 0))
end
local statusScreen = Mock.new("Part", { Name = "StatusScreen", Parent = extraction })
local gui = Mock.new("SurfaceGui", { Name = "Display", Parent = statusScreen })
local statusText = Mock.new("TextLabel", { Name = "StatusText", Text = "", Parent = gui })
local liftLightPart = Mock.new("Part", { Name = "LiftLight", Parent = extraction })
Mock.new("PointLight", { Name = "PointLight", Parent = liftLightPart })

local spawnParts = {}
for _, s in data.spawns do
	local part = Mock.new(
		"Part",
		{ Name = "Spawn", CFrame = CFrame.new(s.pos[1], s.pos[2], s.pos[3]), Parent = facility }
	)
	part:AddTag("FacilitySpawn")
	table.insert(spawnParts, part)
end
local bay = Mock.new("Model", { Name = "DeploymentBay", Parent = Workspace })
for _, p in data.lobbySpawns do
	Mock.new("Part", { Name = "LobbySpawn", CFrame = CFrame.new(p[1], p[2], p[3]), Parent = bay })
		:AddTag("LobbySpawn")
end
local facilityLight = Mock.new("PointLight", { Name = "Light", Brightness = 1, Parent = facility })
facilityLight:AddTag("FacilityLight")
local emergencyLight =
	Mock.new("PointLight", { Name = "Emergency", Brightness = 2, Enabled = false, Parent = facility })
emergencyLight:AddTag("EmergencyLight")

-- Prop library and placed props (Object Shift) ---------------------------------------------

local assets = Mock.new("Folder", { Name = "Assets", Parent = ReplicatedStorage })
local templates = Mock.new("Folder", { Name = "Props", Parent = assets })
local function propModel(propId: string, displayName: string, transformable: boolean, at: Vector3, parent)
	local model = Mock.new("Model", { Name = propId, Parent = parent })
	local body =
		Mock.new("Part", { Name = "Body", CFrame = CFrame.new(at + Vector3.new(0, 2, 0)), Parent = model })
	Mock.new("Part", { Name = "Lid", CFrame = CFrame.new(at + Vector3.new(0, 4, 0)), Parent = model })
	rawget(model, "_props").PrimaryPart = body
	model:SetAttribute("PropId", propId)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("Transformable", transformable)
	return model
end
propModel("WoodenCrate", "Wooden Crate", true, Vector3.zero, templates)
propModel("Desk", "Desk", false, Vector3.zero, templates)
local propsFolder = Mock.new("Folder", { Name = "Props", Parent = facility })
local nearCrate = propModel("WoodenCrate", "Wooden Crate", true, Vector3.new(6, 0, 0), propsFolder)
nearCrate:AddTag("MimicProp")
local farCrate = propModel("WoodenCrate", "Wooden Crate", true, Vector3.new(100, 0, 0), propsFolder)
farCrate:AddTag("MimicProp")
-- Tagged by mistake but not transformable: the allowlist must reject it.
local desk = propModel("Desk", "Desk", true, Vector3.new(-60, 0, 0), propsFolder)
desk:AddTag("MimicProp")

-- Generators (power objective) ---------------------------------------------------------------

local generatorModels = {}
for index, id in { "GEN-A", "GEN-B", "GEN-C" } do
	local model = Mock.new("Model", { Name = "Generator", Parent = facility })
	model:SetAttribute("GeneratorId", id)
	model:SetAttribute("DisplayName", `GENERATOR {string.sub(id, -1)}`)
	Mock.new("Part", { Name = "Panel", CFrame = CFrame.new(200 + index * 40, 3, 0), Parent = model })
	Mock.new("Part", { Name = "Status", Parent = model })
	local core = Mock.new("Part", { Name = "Core", Parent = model })
	Mock.new("PointLight", { Name = "PointLight", Enabled = true, Parent = core })
	model:AddTag("Generator")
	generatorModels[id] = model
end

-- A room for sabotage: zone, one ceiling light, one doorway slab, the camera console --------

local labZone = Mock.new("Part", {
	Name = "Lab",
	CFrame = CFrame.new(400, 6, 0),
	Size = Vector3.new(40, 12, 40),
	Parent = facility,
})
labZone:SetAttribute("DisplayName", "TEST LAB")
labZone:AddTag("RoomZone")
local labFixture = Mock.new("Part", {
	Name = "Fixture",
	CFrame = CFrame.new(400, 11, 0),
	Material = roblox.Enum.Material.Neon,
	Parent = facility,
})
local labLight =
	Mock.new("PointLight", { Name = "PointLight", Enabled = true, Brightness = 1, Parent = labFixture })
labLight:AddTag("FacilityLight")
local labDoor = Mock.new("Part", {
	Name = "LockdownDoor",
	CFrame = CFrame.new(420, 3, 0),
	Transparency = 1,
	CanCollide = false,
	Parent = facility,
})
labDoor:SetAttribute("Room", "TEST LAB")
labDoor:AddTag("LockdownDoor")
local cameraConsole =
	Mock.new("Part", { Name = "CameraConsole", CFrame = CFrame.new(380, 3, 0), Parent = facility })
cameraConsole:AddTag("CameraTerminal")

-- Fast timings (every phase is clamped to >= 1 s by the server) -------------------------------

local GameConfig = Mock.requireModule(shared.Config.GameConfig)
GameConfig.Timings.Intermission = 1
GameConfig.Timings.RoleReveal = 1
GameConfig.Timings.Deployment = 1
GameConfig.Timings.Active = 5
GameConfig.Timings.Escalation = 1
GameConfig.Timings.Extraction = 3
GameConfig.Timings.Results = 1
GameConfig.Characters.EliminatedReturnDelay = 0.2
GameConfig.Characters.LobbyRespawnDelay = 0.2
GameConfig.Strike.InitialCooldown = 0
GameConfig.Strike.Cooldown = 1
GameConfig.Players.MinStudio = 2
-- The harness sets its own timings; a developer's Studio speed-up must not rescale them.
GameConfig.Dev.FastRoundsInStudio = false
GameConfig.ObjectShift.Cooldown = 0.5
GameConfig.IdentityTheft.Cooldown = 0.5
-- Earlier rounds predate the power objective; Round 9 switches it on.
GameConfig.Generators.Required = 0
GameConfig.Generators.RepairSeconds = 1
GameConfig.Generators.TickInterval = 0.05
GameConfig.Sabotage.InitialDelay = 0.3
for _, kind in { "Lights", "Lockdown", "FalseAlert", "Generator", "Cameras" } do
	GameConfig.Sabotage[kind].Cooldown = 0.3
end
GameConfig.Sabotage.Lights.Duration = 1.5
-- The sabotage scenario fires faster than a player could; the limiter is not under test here.
GameConfig.RateLimits.RequestSabotage = { Capacity = 50, RefillPerSecond = 50 }
GameConfig.Sabotage.Lockdown.Duration = 0.5
GameConfig.Sabotage.Cameras.Duration = 0.5
GameConfig.Scanner.StunSeconds = 0.4
GameConfig.Scanner.ExposeSeconds = 0.6

-- Harness helpers ------------------------------------------------------------------------------

local passed, failed = 0, 0
local function check(condition: any, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print("  ✗ " .. message)
	end
end

local function section(title: string)
	print("• " .. title)
end

local function phase(): string
	return roundState:GetAttribute("Phase")
end

local function waitForPhase(target: string, timeout: number?)
	local deadline = os.clock() + (timeout or 20)
	while phase() ~= target do
		if os.clock() > deadline then
			error(`timed out waiting for phase {target} (currently {phase()})`)
		end
		task.wait(0.02)
	end
end

local function waitUntil(predicate: () -> boolean, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)
	while not predicate() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.02)
	end
	return true
end

local function fire(remoteName: string, player, ...)
	remotes[remoteName].OnServerEvent:Fire(player, ...)
end

local function join(name: string)
	local player = Mock.addPlayer(name)
	task.wait(0.05)
	fire("ClientReady", player)
	return player
end

local function status(player): string
	return player:GetAttribute("Status")
end

local function root(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function inBay(player): boolean
	local r = root(player)
	if not r then
		return false
	end
	for _, p in data.lobbySpawns do
		if (r.Position - Vector3.new(p[1], p[2], p[3])).Magnitude < 1 then
			return true
		end
	end
	return false
end

-- Returns { [player] = payload } for this round's RoleReveal messages.
local function reveals(players)
	local roundId = roundState:GetAttribute("RoundId")
	local map = {}
	for _, player in players do
		for _, args in Mock.sent(player, "RoleReveal") do
			if args[1].roundId == roundId then
				map[player] = args[1]
			end
		end
	end
	return map
end

local function split(players)
	local mimics, survivors = {}, {}
	for player, payload in reveals(players) do
		if payload.role == "Mimic" then
			table.insert(mimics, player)
		else
			table.insert(survivors, player)
		end
	end
	return mimics, survivors
end

local function lastResult(player)
	local args = Mock.lastSent(player, "RoundResult")
	return args and args[1]
end

local function abilityCount(player): number
	return #Mock.sent(player, "AbilityState")
end

local function lastAbility(player)
	local args = Mock.lastSent(player, "AbilityState")
	return args and args[1]
end

-- Places `target` `distance` studs in front of `attacker` (attacker faces +Z).
local function placeInFront(attacker, target, distance: number)
	local base = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.pi, 0) -- LookVector = +Z
	root(attacker).CFrame = base
	root(target).CFrame = CFrame.new(0, 3, distance)
end

-- Boot -------------------------------------------------------------------------------------------

Mock.runScript(serverFolder.Main)
task.wait(0.1)

local players = {}
for i = 1, 6 do
	table.insert(players, join(`Player{i}`))
end

local ok, err = pcall(function()
	-- ===================================================================================
	section("Round 1: role assignment, secrecy, deployment, survivors extract")
	waitForPhase("RoleReveal")
	local mimics, survivors = split(players)
	check(
		#mimics == 2 and #survivors == 4,
		`6 players -> 2 Mimics / 4 Survivors (got {#mimics}/{#survivors})`
	)
	local revealMap = reveals(players)
	for _, player in players do
		check(revealMap[player] ~= nil, `{player.Name} received a RoleReveal`)
		for key, value in player:GetAttributes() do
			check(value ~= "Mimic" and value ~= "Survivor", `role leaked via Player attribute {key}`)
		end
	end
	for key, value in roundState:GetAttributes() do
		check(value ~= "Mimic" and value ~= "Survivor", `role leaked via RoundState attribute {key}`)
	end
	for _, s in survivors do
		check(#revealMap[s].teammates == 0, "survivors are not told who the Mimics are")
	end
	check(revealMap[mimics[1]].teammates[1] == mimics[2].UserId, "Mimics learn their fellow Mimic")
	check(roundState:GetAttribute("MimicCount") == 2, "public MimicCount published")

	waitForPhase("Deployment")
	check(
		waitUntil(function()
			for _, p in players do
				if status(p) ~= "Alive" or not root(p) or root(p).Position.Z < -200 then
					return false
				end
			end
			return true
		end),
		"every participant is Alive and inside the facility"
	)
	local positions = {}
	for _, p in players do
		positions[tostring(root(p).Position)] = true
	end
	local distinct = 0
	for _ in positions do
		distinct += 1
	end
	check(distinct == #players, "players deploy to distinct spawn points")
	check(
		players[1].Team and players[1].Team.Name == "Operatives",
		"in-round players share the neutral Operatives team"
	)

	local before = abilityCount(mimics[1])
	fire("RequestStrike", mimics[1])
	check(waitUntil(function()
		return abilityCount(mimics[1]) > before
	end) and lastAbility(mimics[1]).result == "Locked", "strike during Deployment is rejected as Locked")

	waitForPhase("Escalation", 12)
	check(
		facilityLight.Brightness < 1 and emergencyLight.Enabled == true,
		"Escalation switches facility to emergency lighting"
	)

	waitForPhase("Extraction")
	check(
		roundState:GetAttribute("ExtractionOpen") == true and statusText.Text:find("ONLINE") ~= nil,
		"lift opens at Extraction"
	)
	for _, s in survivors do
		root(s).CFrame = liftZone.CFrame
	end
	check(
		waitUntil(function()
			for _, s in survivors do
				if status(s) ~= "Extracted" and status(s) ~= "Standby" then
					return false
				end
			end
			return true
		end),
		"survivors inside the lift are extracted"
	)
	waitForPhase("Results")
	local result = lastResult(players[1])
	check(
		result and result.winner == "Survivors" and result.reason == "Extracted",
		`survivors win by extraction (got {result and result.winner}/{result and result.reason})`
	)
	check(result and result.extracted == 4 and #result.roster == 6, "result roster and extraction tally")
	check(
		waitUntil(function()
			for _, p in players do
				if status(p) ~= "Standby" then
					return false
				end
			end
			return true
		end),
		"everyone returns to Standby after the round"
	)
	-- The last extraction decides the round; those survivors must still be
	-- sent to the bay rather than left standing in the closed lift.
	check(
		waitUntil(function()
			for _, s in survivors do
				if not inBay(s) then
					return false
				end
			end
			return true
		end, 3),
		"extracted survivors are returned to the Deployment Bay"
	)
	check(
		facilityLight.Brightness == 1 and emergencyLight.Enabled == false,
		"lighting restored after the round"
	)
	check(roundState:GetAttribute("ExtractionOpen") == false, "lift closed after the round")

	-- ===================================================================================
	section("Round 2: strike validation and Mimic victory")
	waitForPhase("RoleReveal", 15)
	mimics, survivors = split(players)
	waitForPhase("Active", 10)
	local a, b = mimics[1], mimics[2]

	before = abilityCount(survivors[1])
	fire("RequestStrike", survivors[1])
	task.wait(0.1)
	check(abilityCount(survivors[1]) == before, "a Survivor's strike request is ignored")

	placeInFront(a, survivors[1], 20)
	before = abilityCount(a)
	fire("RequestStrike", a)
	check(waitUntil(function()
		return abilityCount(a) > before
	end) and lastAbility(a).result == "NoTarget", "out-of-range strike finds no target")

	Mock.raycastHook = function()
		return { Instance = facility }
	end
	placeInFront(a, survivors[1], 2.5)
	before = abilityCount(a)
	fire("RequestStrike", a)
	check(
		waitUntil(function()
			return abilityCount(a) > before
		end)
			and lastAbility(a).result == "NoTarget"
			and status(survivors[1]) == "Alive",
		"a wall between Mimic and target blocks the strike"
	)
	Mock.raycastHook = nil

	root(survivors[1]).CFrame = CFrame.new(60, 3, 60)
	before = abilityCount(a)
	for _ = 1, 12 do
		fire("RequestStrike", a)
	end
	task.wait(0.2)
	local answered = abilityCount(a) - before
	check(answered <= 5, `strike spam is rate limited ({answered} of 12 answered)`)
	task.wait(2.1) -- let the token bucket refill

	placeInFront(a, survivors[1], 2.5)
	fire("RequestStrike", a)
	check(
		waitUntil(function()
			return status(survivors[1]) == "Eliminated"
		end),
		"valid strike eliminates the survivor"
	)
	check(#Mock.sent(players[1], "EliminationFx") > 0, "elimination effect broadcast")
	local fx = Mock.lastSent(players[1], "EliminationFx")[1]
	check(fx.position ~= nil and fx.attacker == nil, "effect carries a position and no attacker identity")

	placeInFront(a, survivors[2], 2.5)
	before = abilityCount(a)
	fire("RequestStrike", a)
	check(
		waitUntil(function()
			return abilityCount(a) > before
		end)
			and lastAbility(a).result == "Cooldown"
			and status(survivors[2]) == "Alive",
		"cooldown blocks an immediate second strike"
	)

	placeInFront(b, survivors[2], 2.5)
	fire("RequestStrike", b)
	check(
		waitUntil(function()
			return status(survivors[2]) == "Eliminated"
		end),
		"second Mimic eliminates a survivor"
	)

	task.wait(1.1)
	placeInFront(a, survivors[3], 2)
	fire("RequestStrike", a)
	waitForPhase("Results", 8)
	result = lastResult(players[1])
	check(
		result and result.winner == "Mimics" and result.reason == "Outnumbered",
		`Mimics win once extraction is unreachable (got {result and result.winner}/{result and result.reason})`
	)
	local tally = 0
	for _, entry in result.roster do
		if entry.role == "Mimic" then
			tally += entry.eliminations
		end
	end
	check(tally == 3, `assimilations credited to Mimics (got {tally})`)
	check(
		waitUntil(function()
			return root(survivors[1]) ~= nil and root(survivors[1]).Position.Z < -200
		end),
		"eliminated players respawn in the Deployment Bay"
	)

	-- ===================================================================================
	section("Round 3: Mimics disconnect mid-round")
	waitForPhase("RoleReveal", 15)
	mimics, survivors = split(players)
	waitForPhase("Active", 10)
	for _, m in mimics do
		Mock.removePlayer(m)
		table.remove(players, table.find(players, m))
	end
	waitForPhase("Results", 6)
	result = lastResult(players[1])
	check(
		result and result.winner == "Survivors" and result.reason == "MimicsGone",
		`survivors win when every Mimic leaves (got {result and result.reason})`
	)
	local disconnected = 0
	for _, entry in result.roster do
		if entry.fate == "Disconnected" then
			disconnected += 1
		end
	end
	check(disconnected == 2, "disconnected Mimics are shown as Disconnected")

	-- ===================================================================================
	section("Round 4: Mimic leaves during assignment -> replacement Mimic, timer ending")
	waitForPhase("RoleReveal", 15)
	mimics, survivors = split(players)
	check(#mimics == 1 and #survivors == 3, "4 players -> 1 Mimic")
	local leaver = mimics[1]
	Mock.removePlayer(leaver)
	table.remove(players, table.find(players, leaver))
	check(
		waitUntil(function()
			local m = split(players)
			return #m == 1
		end),
		"a remaining Survivor is promoted to Mimic"
	)
	local promoted = split(players)[1]
	local chosenNotice = false
	for _, args in Mock.sent(promoted, "Announcement") do
		if args[1].title == "THE ORGANISM CHOSE YOU" then
			chosenNotice = true
		end
	end
	check(chosenNotice, "promoted player is told privately")
	waitForPhase("Deployment", 5)
	check(status(promoted) == "Alive", "round continues after promotion")
	waitForPhase("Results", 20)
	result = lastResult(players[1])
	check(
		result and result.winner == "Mimics" and result.reason == "ExtractionFailed",
		`nobody boards -> Mimics win when the lift departs (got {result and result.reason})`
	)

	-- ===================================================================================
	section("Round 5: readiness check, intermission abort, late joiner")
	-- 3 players left. Two sit out -> only one eligible -> intermission aborts.
	waitForPhase("Intermission", 10)
	fire("SetAfk", players[2], true)
	fire("SetAfk", players[3], true)
	fire("SetAfk", players[3], "not a boolean")
	waitForPhase("Waiting", 5)
	check(players[2]:GetAttribute("AFK") == true, "AFK toggle is reflected as a public attribute")
	local postponed = false
	for _, args in Mock.sent(players[1], "Announcement") do
		if args[1].title == "DEPLOYMENT POSTPONED" then
			postponed = true
		end
	end
	check(postponed, "players are told when deployment is postponed")
	check(roundState:GetAttribute("EligiblePlayers") == 1, "eligible count published")
	fire("SetAfk", players[2], false)
	waitForPhase("RoleReveal", 10)
	check(
		#Mock.sent(players[3], "RoleReveal") == 0 or reveals({ players[3] })[players[3]] == nil,
		"sitting-out player is not assigned a role"
	)
	check(status(players[3]) == "Standby", "sitting-out player stays in Standby")
	local late = join("LatePlayer")
	task.wait(0.2)
	check(status(late) == "Standby", "late joiner waits in Standby")
	local lateState = Mock.lastSent(late, "PrivateState")
	check(lateState and lateState[1].role == nil, "late joiner receives no role")
	table.insert(players, late)

	local channel = game:GetService("TextChatService").TextChannels.RBXGeneral
	check(type(channel.ShouldDeliverCallback) == "function", "chat delivery rule attached")
	waitForPhase("Active", 6)
	local alive = nil
	for _, p in players do
		if status(p) == "Alive" then
			alive = p
		end
	end
	local message = { TextSource = { UserId = late.UserId } }
	check(
		channel.ShouldDeliverCallback(message, { UserId = alive.UserId }) == false,
		"spectators cannot message living players mid-round"
	)
	local fromAlive = { TextSource = { UserId = alive.UserId } }
	check(
		channel.ShouldDeliverCallback(fromAlive, { UserId = late.UserId }) == true,
		"living players are heard by spectators"
	)
	waitForPhase("Results", 20)
	fire("SetAfk", players[3], false)

	-- ===================================================================================
	section("Round 6: a fault inside a round cancels it and the server recovers")
	for _, part in spawnParts do
		part.Parent = nil
	end
	waitForPhase("RoleReveal", 15)
	waitForPhase("Results", 10)
	result = lastResult(players[1])
	check(result and result.winner == "None", "faulted round is cancelled with no winner")
	local reset = false
	for _, args in Mock.sent(players[1], "Announcement") do
		if args[1].title == "FACILITY RESET" then
			reset = true
		end
	end
	check(reset, "players are told the facility reset")
	check(
		waitUntil(function()
			for _, p in players do
				if status(p) ~= "Standby" then
					return false
				end
			end
			return true
		end),
		"everyone is back in Standby after the fault"
	)
	for _, part in spawnParts do
		part.Parent = facility
	end
	waitForPhase("Deployment", 15)
	check(true, "next round deploys normally after recovery")
	-- The ability rounds run many steps inside Active; give them room so a
	-- loaded machine cannot push a step past the end of the phase.
	GameConfig.Timings.Active = 10

	-- ===================================================================================
	section("Round 7: Object Shift")
	local Shifts = Mock.requireModule(serverFolder.Services.MimicAbilityService)
	local everyone = Players:GetPlayers()
	mimics, survivors = split(everyone)
	local mimic = mimics[1]
	local function lastShift(player)
		local found = nil
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "ObjectShift" then
				found = args[1]
			end
		end
		return found
	end
	local function shiftCount(player): number
		local n = 0
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "ObjectShift" then
				n += 1
			end
		end
		return n
	end
	local function requestShift(player, target)
		local before = shiftCount(player)
		fire("RequestAbility", player, "ObjectShift", target)
		waitUntil(function()
			return shiftCount(player) > before
		end, 1)
		return lastShift(player)
	end
	local function head(player)
		return player.Character:FindFirstChild("Head")
	end

	check(requestShift(mimic, nearCrate).result == "Locked", "Object Shift is dormant during Deployment")
	waitForPhase("Active", 10)
	root(mimic).CFrame = CFrame.new(0, 3, 0)

	local before = shiftCount(survivors[1])
	fire("RequestAbility", survivors[1], "ObjectShift", nearCrate)
	task.wait(0.1)
	check(shiftCount(survivors[1]) == before and not Shifts.isShifted(survivors[1]), "Survivors cannot shift")

	local state = requestShift(mimic, nearCrate)
	local humanoid = mimic.Character:FindFirstChildOfClass("Humanoid")
	check(
		state.result == "Shifted" and state.detail == "Wooden Crate" and (state.activeUntil or 0) > 0,
		`Mimic shifts into the aimed prop (got {state.result})`
	)
	check(
		mimic.Character:FindFirstChild("Disguise") ~= nil
			and head(mimic).Transparency == 1
			and head(mimic).face.Transparency == 1,
		"character hidden and the prop clone attached"
	)
	check(
		humanoid.WalkSpeed == GameConfig.ObjectShift.WalkSpeed
			and humanoid.JumpHeight == 0
			and humanoid.DisplayDistanceType == roblox.Enum.HumanoidDisplayDistanceType.None,
		"movement restricted and name plate hidden while disguised"
	)

	state = requestShift(mimic, nil)
	check(state.result == "Reverted", `asking again drops the disguise (got {state.result})`)
	check(
		mimic.Character:FindFirstChild("Disguise") == nil
			and head(mimic).Transparency == 0
			and head(mimic).face.Transparency == 0
			and humanoid.WalkSpeed == GameConfig.Characters.WalkSpeed
			and humanoid.DisplayDistanceType == roblox.Enum.HumanoidDisplayDistanceType.Viewer,
		"appearance, movement and name plate restored"
	)
	check(requestShift(mimic, nearCrate).result == "Cooldown", "cooldown starts when the disguise ends")
	task.wait(GameConfig.ObjectShift.Cooldown + 0.1)

	root(mimic).CFrame = CFrame.new(-60, 3, 5)
	check(
		requestShift(mimic, desk).result == "NoTarget",
		"a prop without a transformable template is rejected"
	)
	check(requestShift(mimic, farCrate).result == "NoTarget", "a prop out of range is rejected")

	root(mimic).CFrame = CFrame.new(0, 3, 0)
	GameConfig.ObjectShift.MaxDuration = 0.4
	check(requestShift(mimic, nil).result == "Shifted", "without a hint the server picks the nearest prop")
	check(waitUntil(function()
		local last = lastShift(mimic)
		return last.result == "Expired"
	end, 2) and head(mimic).Transparency == 0, "the disguise drops on its own after MaxDuration")
	GameConfig.ObjectShift.MaxDuration = 30
	task.wait(GameConfig.ObjectShift.Cooldown + 0.1)

	check(requestShift(mimic, nearCrate).result == "Shifted", "shifted again")
	placeInFront(mimic, survivors[1], 2.5)
	fire("RequestStrike", mimic)
	check(
		waitUntil(function()
			return status(survivors[1]) == "Eliminated"
		end)
			and lastShift(mimic).result == "Revealed"
			and mimic.Character:FindFirstChild("Disguise") == nil,
		"assimilating from a disguise breaks it"
	)

	task.wait(GameConfig.ObjectShift.Cooldown + 0.1)
	root(mimic).CFrame = CFrame.new(0, 3, 0)
	check(requestShift(mimic, nearCrate).result == "Shifted", "shifted before the round ends")
	waitForPhase("Results", 15)
	check(
		not Shifts.isShifted(mimic)
			and (mimic.Character == nil or mimic.Character:FindFirstChild("Disguise") == nil),
		"round end clears every disguise"
	)

	-- ===================================================================================
	section("Round 8: Identity Theft")
	local function lastTheft(player)
		local found = nil
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "IdentityTheft" then
				found = args[1]
			end
		end
		return found
	end
	local function theftCount(player): number
		local n = 0
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "IdentityTheft" then
				n += 1
			end
		end
		return n
	end
	local function requestTheft(player)
		local before = theftCount(player)
		fire("RequestAbility", player, "IdentityTheft")
		waitUntil(function()
			return theftCount(player) > before
		end, 1)
		return lastTheft(player)
	end
	local function look(player): string?
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return h and h:GetAppliedDescription():GetAttribute("Look")
	end

	waitForPhase("Deployment", 15)
	everyone = Players:GetPlayers()
	mimics, survivors = split(everyone)
	mimic = mimics[1]
	check(requestTheft(mimic).result == "Locked", "Identity Theft is dormant during Deployment")
	waitForPhase("Active", 10)

	before = theftCount(survivors[1])
	fire("RequestAbility", survivors[1], "IdentityTheft")
	task.wait(0.1)
	check(theftCount(survivors[1]) == before, "Survivors cannot impersonate")

	root(mimic).CFrame = CFrame.new(300, 3, 300)
	check(requestTheft(mimic).result == "NoTarget", "nobody in reach: no target")

	local ownLook = look(mimic)
	placeInFront(mimic, survivors[1], 4)
	state = requestTheft(mimic)
	humanoid = mimic.Character:FindFirstChildOfClass("Humanoid")
	check(
		state.result == "Copied" and state.detail == survivors[1].DisplayName and (state.activeUntil or 0) > 0,
		`Mimic copies the survivor in front (got {state.result})`
	)
	check(
		look(mimic) == survivors[1].Name and humanoid.DisplayName == survivors[1].DisplayName,
		"appearance and display name both copied"
	)
	check(Shifts.isImpersonating(mimic), "server tracks the impersonation")

	state = requestTheft(mimic)
	check(state.result == "Restored", `asking again ends it early (got {state.result})`)
	check(waitUntil(function()
		return look(mimic) == ownLook
	end, 1) and humanoid.DisplayName == "", "own appearance and name restored")
	check(requestTheft(mimic).result == "Cooldown", "cooldown runs from activation")
	task.wait(GameConfig.IdentityTheft.Cooldown + 0.1)

	root(mimic).CFrame = CFrame.new(0, 3, 0)
	task.wait(GameConfig.ObjectShift.Cooldown + 0.1)
	check(requestShift(mimic, nearCrate).result == "Shifted", "disguised as a prop first")
	placeInFront(mimic, survivors[1], 4)
	GameConfig.IdentityTheft.Duration = 0.4
	check(requestTheft(mimic).result == "Copied", "impersonating from a prop disguise works")
	check(
		not Shifts.isShifted(mimic) and mimic.Character:FindFirstChild("Disguise") == nil,
		"taking a new identity drops the prop disguise"
	)
	check(waitUntil(function()
		return lastTheft(mimic).result == "Expired"
	end, 2) and waitUntil(function()
		return look(mimic) == ownLook
	end, 1), "the impersonation fades after Duration")
	GameConfig.IdentityTheft.Duration = 30
	task.wait(GameConfig.IdentityTheft.Cooldown + 0.1)

	placeInFront(mimic, survivors[1], 4)
	check(requestTheft(mimic).result == "Copied", "impersonating when the round ends")
	waitForPhase("Results", 15)
	check(not Shifts.isImpersonating(mimic), "round end clears every impersonation")
	GameConfig.Generators.Required = 2
	GameConfig.Timings.Active = 5

	-- ===================================================================================
	section("Round 9: generator repair gates the lift")
	local genA, genB, genC = generatorModels["GEN-A"], generatorModels["GEN-B"], generatorModels["GEN-C"]
	local function prompt(model)
		return model.Panel:FindFirstChild("RepairPrompt")
	end
	local function standAt(player, model)
		root(player).CFrame = model.Panel.CFrame * CFrame.new(0, 0, 3)
	end
	local function progress(model): number
		return model:GetAttribute("Progress") or 0
	end
	local function announced(player, title: string): boolean
		for _, args in Mock.sent(player, "Announcement") do
			if args[1].title == title then
				return true
			end
		end
		return false
	end

	waitForPhase("Deployment", 15)
	everyone = Players:GetPlayers()
	mimics, survivors = split(everyone)
	mimic = mimics[1]
	check(
		roundState:GetAttribute("GeneratorsRequired") == 2
			and roundState:GetAttribute("GeneratorsOnline") == 0
			and roundState:GetAttribute("PowerRestored") == false,
		"round starts with every generator offline and power required"
	)
	check(
		prompt(genA) ~= nil and prompt(genA).ActionText == "REPAIR",
		"each generator panel has a REPAIR prompt"
	)

	standAt(survivors[1], genA)
	prompt(genA).Triggered:Fire(survivors[1])
	standAt(mimic, genB)
	prompt(genB).Triggered:Fire(mimic)
	task.wait(0.1)
	check(
		survivors[1]:GetAttribute("Repairing") == "GEN-A" and mimic:GetAttribute("Repairing") == "GEN-B",
		"survivors and Mimics both show as repairing (no role tell)"
	)
	check(
		waitUntil(function()
			return genA:GetAttribute("Online") == true
		end, 3),
		"a survivor brings a generator online"
	)
	check(
		roundState:GetAttribute("GeneratorsOnline") == 1
			and survivors[1]:GetAttribute("Repairing") == nil
			and prompt(genA).Enabled == false,
		"online generator counted, its repairer released and its prompt disabled"
	)
	check(
		progress(genB) == 0 and mimic:GetAttribute("Repairing") == "GEN-B",
		"a Mimic's fake repair adds nothing"
	)

	standAt(survivors[2], genC)
	prompt(genC).Triggered:Fire(survivors[2])
	task.wait(0.2)
	root(survivors[2]).CFrame = CFrame.new(-300, 3, 0)
	check(
		waitUntil(function()
			return survivors[2]:GetAttribute("Repairing") == nil
		end, 1),
		"walking away stops a repair"
	)
	local kept = progress(genC)
	task.wait(0.2)
	check(kept > 0 and progress(genC) == kept, "progress is kept but stops when nobody works on it")
	prompt(genB).Triggered:Fire(mimic)
	task.wait(0.1)
	check(mimic:GetAttribute("Repairing") == nil, "triggering again stops repairing")

	waitForPhase("Extraction", 15)
	task.wait(0.1)
	check(roundState:GetAttribute("ExtractionOpen") == false, "the lift stays shut without power")
	check(announced(survivors[1], "LIFT WITHOUT POWER"), "players are told the lift needs power")

	standAt(survivors[2], genC)
	standAt(survivors[3] or survivors[1], genC)
	prompt(genC).Triggered:Fire(survivors[2])
	prompt(genC).Triggered:Fire(survivors[3] or survivors[1])
	check(
		waitUntil(function()
			return roundState:GetAttribute("PowerRestored") == true
		end, 2),
		"the second generator restores power"
	)
	check(
		waitUntil(function()
			return roundState:GetAttribute("ExtractionOpen") == true
		end, 1),
		"restoring power mid-Extraction opens the lift at once"
	)
	for _, s in survivors do
		if status(s) == "Alive" then
			root(s).CFrame = liftZone.CFrame
		end
	end
	waitForPhase("Results", 10)
	result = lastResult(players[1])
	check(
		result and result.winner == "Survivors",
		`survivors escape once power is back (got {result and result.reason})`
	)

	-- ===================================================================================
	section("Round 10: the lift never gets power")
	waitForPhase("Deployment", 15)
	check(
		roundState:GetAttribute("GeneratorsOnline") == 0
			and progress(genA) == 0
			and genA:GetAttribute("Online") == false,
		"generators reset between rounds"
	)
	waitForPhase("Results", 20)
	result = lastResult(players[1])
	check(
		result and result.winner == "Mimics" and result.reason == "PowerFailure",
		`no power means Mimics win by PowerFailure (got {result and result.reason})`
	)
	GameConfig.Generators.Required = 0
	GameConfig.Timings.Active = 10

	-- ===================================================================================
	section("Round 11: System Sabotage")
	local function sabotageStates(player, kind)
		local list = {}
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "Sabotage" and args[1].detail == kind then
				table.insert(list, args[1])
			end
		end
		return list
	end
	local function requestSabotage(player, kind)
		local before = #sabotageStates(player, kind)
		fire("RequestSabotage", player, kind)
		waitUntil(function()
			return #sabotageStates(player, kind) > before
		end, 1)
		local list = sabotageStates(player, kind)
		return list[#list] or {}
	end
	local function lastSabotageResult(player, kind)
		-- The requester's reply (with a result) can be followed by the team-wide broadcast.
		local list = sabotageStates(player, kind)
		for i = #list, 1, -1 do
			if list[i].result then
				return list[i].result
			end
		end
		return nil
	end
	local function sabotage(player, kind)
		requestSabotage(player, kind)
		task.wait(0.05)
		return lastSabotageResult(player, kind)
	end
	local function bannerFor(player, title: string): boolean
		for _, args in Mock.sent(player, "Announcement") do
			if args[1].title == title then
				return true
			end
		end
		return false
	end
	local cooldown = GameConfig.Sabotage.Lights.Cooldown + 0.05

	waitForPhase("Deployment", 15)
	everyone = Players:GetPlayers()
	mimics, survivors = split(everyone)
	mimic = mimics[1]
	check(sabotage(mimic, "Lights") == "Locked", "sabotage is dormant during Deployment")
	waitForPhase("Active", 10)
	task.wait(GameConfig.Sabotage.InitialDelay + 0.05)

	before = #sabotageStates(survivors[1], "Lights")
	fire("RequestSabotage", survivors[1], "Lights")
	fire("RequestSabotage", mimic, "Nuke")
	task.wait(0.1)
	check(#sabotageStates(survivors[1], "Lights") == before, "Survivors cannot sabotage")
	check(#sabotageStates(mimic, "Nuke") == 0, "unknown sabotage kinds are ignored")

	-- Blackout
	root(mimic).CFrame = CFrame.new(600, 3, 0)
	check(sabotage(mimic, "Lights") == "NoTarget", "a blackout needs the Mimic inside a room")
	root(mimic).CFrame = CFrame.new(400, 3, 5)
	check(sabotage(mimic, "Lights") == "Done", "blackout accepted inside a room")
	check(sabotage(mimic, "Lights") == "Cooldown", "the blackout cooldown is claimed")
	if mimics[2] then
		local shared = sabotageStates(mimics[2], "Lights")
		check(#shared > 0 and shared[#shared].readyAt > 0, "sabotage cooldowns are shared with fellow Mimics")
	end
	task.wait(0.85)
	check(
		labLight.Enabled == false and labFixture.Material == roblox.Enum.Material.SmoothPlastic,
		"the room's lights flicker and go dark"
	)
	check(waitUntil(function()
		return labLight.Enabled == true
	end, 1) and labFixture.Material == roblox.Enum.Material.Neon, "the lights come back after the blackout")

	-- Lockdown
	root(mimic).CFrame = CFrame.new(600, 3, 0)
	task.wait(cooldown)
	check(sabotage(mimic, "Lockdown") == "NoTarget", "a lockdown needs a doorway within range")
	root(mimic).CFrame = CFrame.new(410, 3, 0)
	task.wait(cooldown)
	check(sabotage(mimic, "Lockdown") == "Done", "lockdown accepted near a doorway")
	check(
		labDoor.CanCollide == true and labDoor.Transparency < 1,
		"the doorway is sealed (solid and visible)"
	)
	check(bannerFor(survivors[1], "LOCKDOWN"), "everyone is told about the lockdown")
	check(waitUntil(function()
		return labDoor.CanCollide == false
	end, 1) and labDoor.Transparency == 1, "the doorway reopens after the lockdown")

	-- False alert
	local operatives = roundState:GetAttribute("OperativesRemaining")
	local fxBefore = #Mock.sent(survivors[1], "EliminationFx")
	task.wait(cooldown)
	check(sabotage(mimic, "FalseAlert") == "Done", "false alert accepted")
	local faked = nil
	for _, args in Mock.sent(survivors[1], "Announcement") do
		local title = args[1].title
		if string.find(title, "is no longer responding", 1, true) then
			faked = title
		end
	end
	local namesSurvivor = false
	for _, s in survivors do
		if faked == `{s.DisplayName} is no longer responding` and status(s) == "Alive" then
			namesSurvivor = true
		end
	end
	check(namesSurvivor, `the fake alert names a living survivor (got {faked})`)
	check(
		roundState:GetAttribute("OperativesRemaining") == operatives
			and #Mock.sent(survivors[1], "EliminationFx") == fxBefore,
		"the tell: the operatives count does not drop and there is no elimination effect"
	)

	-- Generator fault
	local genA = generatorModels["GEN-A"]
	local panel = genA.Panel
	root(survivors[1]).CFrame = panel.CFrame * CFrame.new(0, 0, 3)
	panel.RepairPrompt.Triggered:Fire(survivors[1])
	waitUntil(function()
		return (genA:GetAttribute("Progress") or 0) >= 0.4
	end, 2)
	panel.RepairPrompt.Triggered:Fire(survivors[1])
	task.wait(0.1)
	local damaged = genA:GetAttribute("Progress")
	root(mimic).CFrame = CFrame.new(0, 3, 300)
	task.wait(cooldown)
	check(
		sabotage(mimic, "Generator") == "NoTarget",
		"a generator fault needs the Mimic at a damaged generator"
	)
	root(mimic).CFrame = panel.CFrame * CFrame.new(0, 0, 4)
	check(sabotage(mimic, "Generator") == "Done", "generator fault accepted at the panel")
	check(
		math.abs(genA:GetAttribute("Progress") - (damaged - GameConfig.Sabotage.Generator.Setback)) < 0.01,
		`repairs set back by {GameConfig.Sabotage.Generator.Setback} (from {damaged} to {genA:GetAttribute(
			"Progress"
		)})`
	)
	check(bannerFor(survivors[1], "GENERATOR A FAULT"), "the fault is announced")

	-- Cameras
	task.wait(cooldown)
	check(sabotage(mimic, "Cameras") == "Done", "camera cut accepted")
	check(roundState:GetAttribute("CamerasOnline") == false, "the camera feed goes dark")
	task.wait(cooldown)
	check(sabotage(mimic, "Cameras") == "NoTarget", "cameras that are already down cannot be cut again")
	check(
		waitUntil(function()
			return roundState:GetAttribute("CamerasOnline") == true
		end, 1),
		"cameras come back after the outage"
	)

	-- Everything still active is undone at round end.
	task.wait(cooldown)
	root(mimic).CFrame = CFrame.new(400, 3, 5)
	GameConfig.Sabotage.Lights.Duration = 30
	GameConfig.Sabotage.Cameras.Duration = 30
	check(
		sabotage(mimic, "Lights") == "Done" and sabotage(mimic, "Cameras") == "Done",
		"long sabotages started"
	)
	waitForPhase("Results", 15)
	task.wait(0.1)
	check(
		labLight.Enabled == true and roundState:GetAttribute("CamerasOnline") == true,
		"round end restores lights and cameras"
	)

	-- ===================================================================================
	section("Round 12: Containment Scanner")
	local function scanStates(player)
		local list = {}
		for _, args in Mock.sent(player, "AbilityState") do
			if args[1].ability == "Scan" then
				table.insert(list, args[1])
			end
		end
		return list
	end
	local function lastScan(player)
		local list = scanStates(player)
		return list[#list] or {}
	end
	local function requestScan(player)
		local before = #scanStates(player)
		fire("RequestAbility", player, "Scan")
		waitUntil(function()
			return #scanStates(player) > before
		end, 1)
		return lastScan(player)
	end

	waitForPhase("Deployment", 15)
	everyone = Players:GetPlayers()
	mimics, survivors = split(everyone)
	mimic = mimics[1]
	local scannerA, scannerB = survivors[1], survivors[2]
	local mimicScansBefore = #scanStates(mimic) -- from rounds where this player was a survivor
	check(requestScan(scannerA).result == "Locked", "the scanner is offline during Deployment")
	waitForPhase("Active", 10)
	task.wait(0.1)
	check(
		lastScan(scannerA).charges == GameConfig.Scanner.Charges,
		"each survivor gets their charge when Active starts"
	)
	check(#scanStates(mimic) == mimicScansBefore, "Mimics never get a scanner")

	root(scannerA).CFrame = CFrame.new(300, 3, 300)
	state = requestScan(scannerA)
	check(state.result == "NoTarget" and state.charges == 1, "a scan that finds nobody costs nothing")

	placeInFront(scannerA, scannerB, 3)
	state = requestScan(scannerA)
	check(state.result == "Clear" and state.charges == 0, "scanning a crewmate spends the charge")
	check(bannerFor(scannerB, "FALSE POSITIVE"), "everyone hears about the false positive")
	check(requestScan(scannerA).result == "Spent", "no charge, no scan")

	root(mimic).CFrame = CFrame.new(0, 3, 0)
	task.wait(GameConfig.ObjectShift.Cooldown + 0.1)
	check(requestShift(mimic, nearCrate).result == "Shifted", "the Mimic hides as a prop")
	root(scannerA).CFrame = CFrame.new(-300, 3, 300) -- out of the way
	placeInFront(scannerB, mimic, 3)
	state = requestScan(scannerB)
	humanoid = mimic.Character:FindFirstChildOfClass("Humanoid")
	check(state.result == "Mimic", `a disguised Mimic can be scanned (got {state.result})`)
	check(
		not Shifts.isShifted(mimic) and mimic.Character:FindFirstChild("Disguise") == nil,
		"the scan strips the disguise"
	)
	check(mimic.Character:FindFirstChild("Exposed") ~= nil, "the Mimic is highlighted for everyone")
	check(humanoid.WalkSpeed == 0, "the Mimic is stunned")
	check(bannerFor(scannerA, "ORGANISM EXPOSED"), "the exposure is announced")
	placeInFront(mimic, scannerA, 2.5)
	fire("RequestStrike", mimic)
	check(waitUntil(function()
		local last = lastAbility(mimic)
		return last ~= nil and last.ability == "Assimilate" and last.result == "Stunned"
	end, 1) and status(scannerA) == "Alive", "a stunned Mimic cannot assimilate")
	check(
		waitUntil(function()
			return humanoid.WalkSpeed == GameConfig.Characters.WalkSpeed
		end, 1),
		"the stun wears off"
	)
	check(
		waitUntil(function()
			return mimic.Character:FindFirstChild("Exposed") == nil
		end, 1),
		"the highlight fades"
	)

	waitForPhase("Extraction", 20)
	local window = roundState:GetAttribute("PhaseEndsAt") - Workspace:GetServerTimeNow()
	local shortest = GameConfig.Timings.Extraction * GameConfig.Scanner.MinExtractionFraction
	check(
		window <= shortest + 0.2,
		`the false positive shortened the lift window (got {string.format("%.2f", window)} s, floor {shortest} s)`
	)
end)

if not ok then
	failed += 1
	print("  ✗ harness error: " .. tostring(err))
end

-- Only the deliberately injected fault (round 6) may produce a warning.
local unexpected = {}
for _, text in Mock.warnings do
	if not (text:find("No parts tagged FacilitySpawn") or text:find("SetCore")) then
		table.insert(unexpected, text)
	end
end
check(#unexpected == 0, `no unexpected server warnings ({#unexpected})`)
for _, text in unexpected do
	print("    " .. string.sub(text, 1, 300))
end

print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
