--!nonstrict
--[[
	A minimal Roblox server runtime for Lune, sufficient to execute the real
	server modules in src/server and src/shared end-to-end.

	It is NOT a Roblox emulator. It models exactly what the server code uses:
	the instance tree (names, parents, attributes, tags, property signals),
	Players / Player / character loading, Humanoid death, RemoteEvents (with a
	per-player log of everything the server sends), CollectionService,
	TweenService (instant), Workspace time and raycasts (hookable), Teams and
	TextChatService. Scripts are loaded from disk with their own `script`.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Mock = {}

Mock.warnings = {} :: { string }
Mock.raycastHook = nil :: ((Vector3, Vector3) -> any)?
Mock.isStudio = true
Mock.clock0 = os.clock()

-- Signals ---------------------------------------------------------------------------

local function newSignal()
	local signal = { _connections = {} }
	function signal:Connect(fn)
		local connection = { Connected = true }
		function connection.Disconnect(c)
			c.Connected = false
		end
		table.insert(self._connections, { fn = fn, connection = connection })
		return connection
	end
	function signal:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Wait()
		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	function signal:Fire(...)
		local list = table.clone(self._connections)
		for _, entry in list do
			if entry.connection.Connected then
				task.spawn(entry.fn, ...)
			end
		end
		-- Drop disconnected entries.
		local alive = {}
		for _, entry in self._connections do
			if entry.connection.Connected then
				table.insert(alive, entry)
			end
		end
		self._connections = alive
	end
	return signal
end
Mock.newSignal = newSignal

-- Instances -----------------------------------------------------------------------------

local SUPER = {
	Part = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	PointLight = { "Light" },
	SpotLight = { "Light" },
	SurfaceLight = { "Light" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" },
	Frame = { "GuiObject", "GuiBase2d" },
	ScrollingFrame = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
}

local EVENT_NAMES = {
	ChildAdded = true,
	Changed = true,
	CharacterAdded = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Completed = true,
	Activated = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	SelectionGained = true,
	SelectionLost = true,
	LastInputTypeChanged = true,
	DescendantAdded = true,
	Triggered = true,
}

local Methods = {}
local taggedRegistry: { [string]: { any } } = {}
local tagAddedSignals: { [string]: any } = {}

local InstanceMT = {}

local function isMockInstance(value): boolean
	return type(value) == "table" and getmetatable(value) == InstanceMT
end
Mock.isInstance = isMockInstance

local function new(className: string, props: { [string]: any }?)
	local inst = setmetatable({
		_props = { ClassName = className, Name = className },
		_children = {},
		_attributes = {},
		_attrSignals = {},
		_propSignals = {},
		_tags = {},
		_signals = {},
	}, InstanceMT)
	if className == "Humanoid" then
		local props0 = rawget(inst, "_props")
		props0.Health = 100
		props0.MaxHealth = 100
		props0.WalkSpeed = 16
		props0.JumpHeight = 7.2
		props0.HipHeight = 2
		props0.RigType = roblox.Enum.HumanoidRigType.R15
		props0.DisplayDistanceType = roblox.Enum.HumanoidDisplayDistanceType.Viewer
		props0.DisplayName = ""
		rawget(inst, "_signals").Died = newSignal()
	end
	if props then
		local parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				inst[key] = value
			end
		end
		if parent then
			inst.Parent = parent
		end
	end
	return inst
end
Mock.new = new

local function setParent(inst, parent)
	local props = rawget(inst, "_props")
	local old = props.Parent
	if old == parent then
		return
	end
	if old then
		local siblings = rawget(old, "_children")
		local index = table.find(siblings, inst)
		if index then
			table.remove(siblings, index)
		end
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "_children"), inst)
		local added = rawget(parent, "_signals").ChildAdded
		if added then
			added:Fire(inst)
		end
	end
end

InstanceMT.__index = function(self, key)
	local method = Methods[key]
	if method then
		return method
	end
	local signals = rawget(self, "_signals")
	if signals[key] then
		return signals[key]
	end
	local props = rawget(self, "_props")
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	local value = props[key]
	if value ~= nil then
		return value
	end
	if EVENT_NAMES[key] then
		signals[key] = newSignal()
		return signals[key]
	end
	return Methods.FindFirstChild(self, key)
end

InstanceMT.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local props = rawget(self, "_props")
	local old = props[key]
	if key == "Position" and typeof(value) == "Vector3" then
		local cf = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(value) * (cf - cf.Position)
		return
	end
	props[key] = value
	if
		props.ClassName == "Humanoid"
		and key == "Health"
		and type(value) == "number"
		and value <= 0
		and (old or 0) > 0
	then
		rawget(self, "_signals").Died:Fire()
	end
	local signal = rawget(self, "_propSignals")[key]
	if signal and old ~= value then
		signal:Fire()
	end
end

InstanceMT.__tostring = function(self)
	return rawget(self, "_props").Name
end

function Methods.IsA(self, className)
	local own = rawget(self, "_props").ClassName
	if own == className or className == "Instance" then
		return true
	end
	for _, super in SUPER[own] or {} do
		if super == className then
			return true
		end
	end
	return false
end

function Methods.FindFirstChild(self, name, recursive)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local found = Methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.WaitForChild(self, name, timeout)
	local deadline = os.clock() + (timeout or 5)
	while true do
		local child = Methods.FindFirstChild(self, name)
		if child then
			return child
		end
		if os.clock() > deadline then
			return nil
		end
		task.wait(0.01)
	end
end

function Methods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").ClassName == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self, className)
	for _, child in rawget(self, "_children") do
		if Methods.IsA(child, className) then
			return child
		end
	end
	return nil
end

function Methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function Methods.GetDescendants(self)
	local list = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(list, child)
			walk(child)
		end
	end
	walk(self)
	return list
end

function Methods.IsDescendantOf(self, ancestor)
	local node = rawget(self, "_props").Parent
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "_props").Parent
	end
	return false
end

function Methods.GetFullName(self)
	local parts = {}
	local node = self
	while node do
		table.insert(parts, 1, rawget(node, "_props").Name)
		node = rawget(node, "_props").Parent
	end
	return table.concat(parts, ".")
end

function Methods.Destroy(self)
	setParent(self, nil)
end

function Methods.SetAttribute(self, name, value)
	local attributes = rawget(self, "_attributes")
	local old = attributes[name]
	attributes[name] = value
	local signal = rawget(self, "_attrSignals")[name]
	if signal and old ~= value then
		signal:Fire()
	end
end

function Methods.GetAttribute(self, name)
	return rawget(self, "_attributes")[name]
end

function Methods.GetAttributes(self)
	return table.clone(rawget(self, "_attributes"))
end

function Methods.GetAttributeChangedSignal(self, name)
	local signals = rawget(self, "_attrSignals")
	signals[name] = signals[name] or newSignal()
	return signals[name]
end

function Methods.GetPropertyChangedSignal(self, name)
	local signals = rawget(self, "_propSignals")
	signals[name] = signals[name] or newSignal()
	return signals[name]
end

function Methods.AddTag(self, tag)
	local tags = rawget(self, "_tags")
	if tags[tag] then
		return
	end
	tags[tag] = true
	taggedRegistry[tag] = taggedRegistry[tag] or {}
	table.insert(taggedRegistry[tag], self)
	if tagAddedSignals[tag] then
		tagAddedSignals[tag]:Fire(self)
	end
end

function Methods.HasTag(self, tag)
	return rawget(self, "_tags")[tag] == true
end

-- HumanoidDescription stand-in: an instance whose "Look" attribute names the
-- character it was read from, so tests can tell whose appearance is applied.
function Methods.GetAppliedDescription(self)
	local props = rawget(self, "_props")
	if not props.AppliedDescription then
		local description = new("HumanoidDescription", { Name = "HumanoidDescription" })
		description:SetAttribute("Look", if props.Parent then props.Parent.Name else "?")
		props.AppliedDescription = description
	end
	return props.AppliedDescription
end
function Methods.ApplyDescription(self, description)
	task.wait(0.05) -- the real call yields while assets load
	rawget(self, "_props").AppliedDescription = description
end

function Methods.GetPivot(self)
	local props = rawget(self, "_props")
	if props.CFrame then
		return props.CFrame
	end
	local root = Methods.FindFirstChild(self, "HumanoidRootPart") or props.PrimaryPart
	return if root then root.CFrame else CFrame.new()
end

-- Deep copy: properties, attributes and tags; PrimaryPart is remapped.
function Methods.Clone(self)
	local map = {}
	local function copy(node)
		local props = rawget(node, "_props")
		local clone = new(props.ClassName)
		map[node] = clone
		for key, value in props do
			if key ~= "Parent" and key ~= "PrimaryPart" then
				rawget(clone, "_props")[key] = value
			end
		end
		for key, value in rawget(node, "_attributes") do
			rawget(clone, "_attributes")[key] = value
		end
		for _, child in rawget(node, "_children") do
			copy(child).Parent = clone
		end
		return clone
	end
	local result = copy(self)
	for original, clone in map do
		local primary = rawget(original, "_props").PrimaryPart
		if primary and map[primary] then
			rawget(clone, "_props").PrimaryPart = map[primary]
		end
	end
	return result
end

function Methods.PivotTo(self, cframe)
	local root = Methods.FindFirstChild(self, "HumanoidRootPart") or rawget(self, "_props").PrimaryPart
	if root then
		root.CFrame = cframe
	end
end

-- Remote events -------------------------------------------------------------------------

Mock.clientLog = {} :: { [any]: { { remote: string, args: { any } } } }

local function logClient(player, remoteName, ...)
	Mock.clientLog[player] = Mock.clientLog[player] or {}
	table.insert(Mock.clientLog[player], { remote = remoteName, args = table.pack(...) })
end

function Methods.FireClient(self, player, ...)
	assert(isMockInstance(player) and player.ClassName == "Player", "FireClient needs a Player")
	logClient(player, self.Name, ...)
end

Mock.serverLog = {} :: { { remote: string, args: { any } } }
function Methods.FireServer(self, ...)
	table.insert(Mock.serverLog, { remote = self.Name, args = table.pack(...) })
end

function Methods.FireAllClients(self, ...)
	for _, player in Mock.Players:GetPlayers() do
		logClient(player, self.Name, ...)
	end
end

-- Services -------------------------------------------------------------------------------

local game = new("DataModel", { Name = "game" })
Mock.game = game
rawget(game, "_props").PrivateServerId = ""
rawget(game, "_props").PrivateServerOwnerId = 0

local services = {}
local function service(name, className)
	local inst = new(className or name, { Name = name, Parent = game })
	services[name] = inst
	return inst
end

function Methods.GetService(self, name)
	local svc = services[name]
	assert(svc, `Mock has no service {name}`)
	return svc
end

local Players = service("Players")
Mock.Players = Players
rawget(Players, "_signals").PlayerAdded = newSignal()
rawget(Players, "_signals").PlayerRemoving = newSignal()
rawget(Players, "_props").CharacterAutoLoads = true

function Methods.GetPlayers(self)
	local list = {}
	for _, child in rawget(self, "_children") do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end

function Methods.GetPlayerByUserId(self, userId)
	for _, player in Methods.GetPlayers(self) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local Workspace = service("Workspace")
Mock.Workspace = Workspace
function Methods.GetServerTimeNow()
	return os.clock() - Mock.clock0 + 1000
end
function Methods.Raycast(_, origin, direction)
	if Mock.raycastHook then
		return Mock.raycastHook(origin, direction)
	end
	return nil
end

local RunService = service("RunService")
function Methods.IsStudio()
	return Mock.isStudio
end
function Methods.IsServer()
	return true
end
function Methods.IsClient()
	return false
end

local CollectionService = service("CollectionService")
function Methods.GetTagged(self, tag)
	local list = {}
	for _, inst in taggedRegistry[tag] or {} do
		if rawget(inst, "_props").Parent ~= nil then
			table.insert(list, inst)
		end
	end
	return list
end
function Methods.GetInstanceAddedSignal(self, tag)
	tagAddedSignals[tag] = tagAddedSignals[tag] or newSignal()
	return tagAddedSignals[tag]
end

-- Client-side services (used by the client smoke test).
local UserInputService = service("UserInputService")
rawget(UserInputService, "_props").TouchEnabled = false
rawget(UserInputService, "_props").KeyboardEnabled = true
function Methods.GetMouseLocation()
	return roblox.Vector2.new(640, 360)
end
function Methods.ViewportPointToRay(_, _x, _y)
	return { Origin = Vector3.new(0, 10, 0), Direction = Vector3.new(0, 0, -1) }
end
function Methods.GetLastInputType()
	return roblox.Enum.UserInputType.Keyboard
end
local ContextActionService = service("ContextActionService")
Mock.boundActions = {}
function Methods.BindAction(self, name, fn)
	Mock.boundActions[name] = fn
end
function Methods.UnbindAction(self, name)
	Mock.boundActions[name] = nil
end
local StarterGui = service("StarterGui")
Mock.coreState = {}
function Methods.SetCore(self, name, value)
	Mock.coreState[name] = value
end
function Methods.SetCoreGuiEnabled(self, coreType, enabled)
	Mock.coreState[tostring(coreType)] = enabled
end
local Lighting = service("Lighting")
new("ColorCorrectionEffect", { Name = "FacilityGrade", Parent = Lighting })

local TweenService = service("TweenService")
function Methods.Create(self, instance, _info, goal)
	local tween = new("Tween")
	rawget(tween, "_props").Play = function()
		for key, value in goal do
			instance[key] = value
		end
		tween.Completed:Fire(Enum and nil)
	end
	return tween
end

service("ReplicatedStorage")
service("ServerScriptService")
service("ServerStorage")
local Teams = service("Teams")
for _, name in { "Standby", "Operatives", "Observers" } do
	new("Team", { Name = name, Parent = Teams })
end
local TextChatService = service("TextChatService")
local channels = new("Folder", { Name = "TextChannels", Parent = TextChatService })
new("TextChannel", { Name = "RBXGeneral", Parent = channels })

-- Players --------------------------------------------------------------------------------

local function buildCharacter(player)
	local character = new("Model", { Name = player.Name })
	local root = new("Part", {
		Name = "HumanoidRootPart",
		CFrame = CFrame.new(0, 3, -330),
		Size = Vector3.new(2, 2, 1),
		Parent = character,
	})
	rawget(character, "_props").PrimaryPart = root
	local head = new("Part", { Name = "Head", Transparency = 0, Parent = character })
	new("Decal", { Name = "face", Transparency = 0, Parent = head })
	new("Humanoid", { Name = "Humanoid", Parent = character })
	return character
end

local nextUserId = 1000
function Mock.addPlayer(name: string)
	nextUserId += 1
	local player = new("Player", { Name = name, DisplayName = name, UserId = nextUserId })
	rawget(player, "_props").LoadCharacterAsync = function(self)
		task.wait(0.01)
		local old = self.Character
		if old then
			old.Parent = nil
		end
		local character = buildCharacter(self)
		character.Parent = Workspace
		self.Character = character
		self.CharacterAdded:Fire(character)
	end
	player.Parent = Players
	Players.PlayerAdded:Fire(player)
	return player
end

function Mock.removePlayer(player)
	Players.PlayerRemoving:Fire(player)
	task.wait(0.02)
	if player.Character then
		player.Character.Parent = nil
	end
	player.Parent = nil
end

-- Datatypes -------------------------------------------------------------------------------

local RandomMock = {}
RandomMock.__index = RandomMock
function RandomMock.new()
	return setmetatable({}, RandomMock)
end
function RandomMock:NextNumber(min, max)
	min = min or 0
	max = max or 1
	return min + math.random() * (max - min)
end
function RandomMock:NextInteger(min, max)
	return math.random(min, max)
end

local RaycastParamsMock = {
	new = function()
		return {}
	end,
}
local TweenInfoMock = {
	new = function(...)
		return { ... }
	end,
}

local function mockTypeof(value)
	if isMockInstance(value) then
		return "Instance"
	end
	return typeof(value)
end

-- Script loading ------------------------------------------------------------------------------

local moduleCache = {}

local function makeEnv(scriptInstance)
	local env = {
		Instance = {
			new = function(className)
				return new(className)
			end,
		},
		UDim = roblox.UDim,
		Vector2 = roblox.Vector2,
		Font = roblox.Font,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		game = game,
		workspace = Workspace,
		script = scriptInstance,
		task = task,
		typeof = mockTypeof,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		Random = RandomMock,
		RaycastParams = RaycastParamsMock,
		TweenInfo = TweenInfoMock,
		warn = function(...)
			local parts = {}
			for _, v in table.pack(...) do
				table.insert(parts, tostring(v))
			end
			local text = table.concat(parts, " ")
			table.insert(Mock.warnings, text)
			print("  [warn] " .. text)
		end,
		print = function(...)
			if Mock.verbose then
				print(...)
			end
		end,
	}
	env.require = function(target)
		assert(
			isMockInstance(target) and target.ClassName == "ModuleScript",
			"require expects a ModuleScript"
		)
		if moduleCache[target] == nil then
			local path = target:GetAttribute("__source")
			local chunk = luau.load(fs.readFile(path), { debugName = path, environment = makeEnv(target) })
			moduleCache[target] = chunk()
		end
		return moduleCache[target]
	end
	return env
end

-- Mirrors a src directory into the instance tree using Rojo's naming rules.
function Mock.mount(directory: string, parent)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			local folder = new("Folder", { Name = entry, Parent = parent })
			Mock.mount(path, folder)
		elseif string.sub(entry, -12) == ".server.luau" then
			local s = new("Script", { Name = string.sub(entry, 1, -13), Parent = parent })
			s:SetAttribute("__source", path)
		elseif string.sub(entry, -12) == ".client.luau" then
			local s = new("LocalScript", { Name = string.sub(entry, 1, -13), Parent = parent })
			s:SetAttribute("__source", path)
		elseif string.sub(entry, -5) == ".luau" then
			local m = new("ModuleScript", { Name = string.sub(entry, 1, -6), Parent = parent })
			m:SetAttribute("__source", path)
		end
	end
end

function Mock.runScript(scriptInstance)
	local path = scriptInstance:GetAttribute("__source")
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = makeEnv(scriptInstance) })
	task.spawn(chunk)
end

function Mock.requireModule(moduleInstance)
	return makeEnv(moduleInstance).require(moduleInstance)
end

-- Log helpers -----------------------------------------------------------------------------------

function Mock.sent(player, remoteName): { { any } }
	local list = {}
	for _, entry in Mock.clientLog[player] or {} do
		if entry.remote == remoteName then
			table.insert(list, entry.args)
		end
	end
	return list
end

function Mock.lastSent(player, remoteName)
	local list = Mock.sent(player, remoteName)
	return list[#list]
end

-- Makes `player` the LocalPlayer with a PlayerGui and a camera (client tests).
function Mock.becomeClient(player)
	rawget(Players, "_props").LocalPlayer = player
	new("PlayerGui", { Name = "PlayerGui", Parent = player })
	local camera = new(
		"Camera",
		{ Name = "Camera", ViewportSize = roblox.Vector2.new(1280, 720), CFrame = CFrame.new(0, 10, 0) }
	)
	camera.Parent = Workspace
	Workspace.CurrentCamera = camera
end

Mock.CFrame = CFrame
Mock.Vector3 = Vector3

return Mock
