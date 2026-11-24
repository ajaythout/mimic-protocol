--!strict
--[[
	FacilityService
	Facility-wide environmental state: lighting modes for the round flow and
	the systems Mimics can sabotage. SabotageService decides who may do what;
	this module only changes the world, and every change has a visible and
	audible tell.

	Discovered through CollectionService tags authored by the map generator:
	  FacilityLight    Light instances; attribute BaseBrightness
	  EmergencyLight   Light instances that are disabled until an emergency
	  EmergencyBeacon  BaseParts that switch to glowing red in an emergency
	  RoomZone         invisible room volumes (DisplayName attribute)
	  LockdownDoor     invisible doorway slabs (Room, LeadsTo attributes)
	  CameraTerminal   anchor for the VIEW CAMERAS prompt (Security Office)

	Sabotage effects
	  blackout(zone, s)    the room's lights flicker, then go dark for s seconds
	  sealDoor(door, s)    a doorway slab drops shut (solid, red) for s seconds
	  camerasOffline(s)    RoundState.CamerasOnline = false for s seconds
	reset() undoes all of them (round end).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local MatchState = require(script.Parent.MatchState)

export type LightingMode = "Normal" | "Emergency"

local FacilityService = {}

local NORMAL_SCALE = 1
local EMERGENCY_SCALE = 0.35
local BEACON_ON = Color3.fromRGB(255, 45, 45)
local BEACON_OFF = Color3.fromRGB(70, 18, 20)

local DOOR_COLOR = Color3.fromRGB(190, 40, 40)
-- Built-in Roblox client sounds (no uploaded assets needed).
local SOUND_SPARK = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_SLAM = "rbxasset://sounds/snap.mp3"

local currentMode: LightingMode = "Normal"

type LightState = { light: Light, fixture: BasePart?, material: Enum.Material }

local zones: { BasePart } = {}
local roomLights: { [BasePart]: { LightState } } = {}
local blackoutToken: { [BasePart]: number } = {}
local doorToken: { [BasePart]: number } = {}
local camerasToken = 0

local function baseBrightness(light: Light): number
	local base = light:GetAttribute("BaseBrightness")
	if type(base) ~= "number" then
		base = light.Brightness
		light:SetAttribute("BaseBrightness", base)
	end
	return base :: number
end

local function applyMode(mode: LightingMode)
	local emergency = mode == "Emergency"
	local scale = if emergency then EMERGENCY_SCALE else NORMAL_SCALE

	for _, instance in CollectionService:GetTagged("FacilityLight") do
		if instance:IsA("Light") then
			instance.Brightness = baseBrightness(instance) * scale
		end
	end

	for _, instance in CollectionService:GetTagged("EmergencyLight") do
		if instance:IsA("Light") then
			instance.Enabled = emergency
		end
	end

	for _, instance in CollectionService:GetTagged("EmergencyBeacon") do
		if instance:IsA("BasePart") then
			instance.Color = if emergency then BEACON_ON else BEACON_OFF
			instance.Material = if emergency then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function inside(zone: BasePart, position: Vector3): boolean
	local relative = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size * 0.5
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Y) <= half.Y
		and math.abs(relative.Z) <= half.Z
end

local function createPrompt()
	for _, anchor in CollectionService:GetTagged("CameraTerminal") do
		if anchor:IsA("BasePart") and not anchor:FindFirstChild("CameraPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "CameraPrompt"
			prompt.ActionText = "VIEW CAMERAS"
			prompt.ObjectText = "SECURITY FEED"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = GameConfig.Cameras.Range
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonL1
			prompt.Parent = anchor
		end
	end
end

function FacilityService.Init()
	-- Cache base brightness before anything modifies a light.
	for _, instance in CollectionService:GetTagged("FacilityLight") do
		if instance:IsA("Light") then
			baseBrightness(instance)
		end
	end
	applyMode("Normal")

	for _, zone in CollectionService:GetTagged("RoomZone") do
		if zone:IsA("BasePart") then
			table.insert(zones, zone)
			roomLights[zone] = {}
		end
	end
	for _, instance in CollectionService:GetTagged("FacilityLight") do
		local fixture = instance.Parent
		if instance:IsA("Light") and fixture and fixture:IsA("BasePart") then
			for _, zone in zones do
				if inside(zone, fixture.Position) then
					table.insert(
						roomLights[zone],
						{ light = instance, fixture = fixture, material = fixture.Material }
					)
					break
				end
			end
		end
	end
	createPrompt()
	MatchState.setPublic("CamerasOnline", true)
end

-- Plays a short sound at `parent` (a part in the world), then cleans it up.
function FacilityService.cue(parent: Instance, soundId: string, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

-- The room volume containing `position`, if any (corridors are not rooms).
function FacilityService.roomAt(position: Vector3): BasePart?
	for _, zone in zones do
		if inside(zone, position) then
			return zone
		end
	end
	return nil
end

local function setRoomLit(zone: BasePart, lit: boolean)
	local lights = roomLights[zone]
	if not lights then
		return
	end
	for _, state in lights do
		state.light.Enabled = lit
		if state.fixture then
			state.fixture.Material = if lit then state.material else Enum.Material.SmoothPlastic
		end
	end
end

-- Flicker, then darkness for `duration` seconds. Returns false if the room has no lights.
function FacilityService.blackout(zone: BasePart, duration: number): boolean
	local lights = roomLights[zone]
	if not lights or #lights == 0 then
		return false
	end
	local token = (blackoutToken[zone] or 0) + 1
	blackoutToken[zone] = token
	local first = lights[1].fixture
	if first then
		FacilityService.cue(first, SOUND_SPARK, 1)
	end
	task.spawn(function()
		for _ = 1, 3 do
			setRoomLit(zone, false)
			task.wait(0.12)
			setRoomLit(zone, true)
			task.wait(0.12)
		end
		if blackoutToken[zone] == token then
			setRoomLit(zone, false)
		end
	end)
	task.delay(duration, function()
		if blackoutToken[zone] == token then
			blackoutToken[zone] = nil
			setRoomLit(zone, true)
		end
	end)
	return true
end

function FacilityService.isBlackedOut(zone: BasePart): boolean
	return blackoutToken[zone] ~= nil
end

function FacilityService.nearestDoor(position: Vector3, range: number): BasePart?
	local best: BasePart? = nil
	local bestDistance = range
	for _, door in CollectionService:GetTagged("LockdownDoor") do
		if door:IsA("BasePart") and not doorToken[door] then
			local distance = (door.Position - position).Magnitude
			if distance <= bestDistance then
				best = door
				bestDistance = distance
			end
		end
	end
	return best
end

local function setDoorSealed(door: BasePart, sealed: boolean)
	door.Transparency = if sealed then 0.05 else 1
	door.Color = DOOR_COLOR
	door.Material = Enum.Material.DiamondPlate
	door.CanCollide = sealed
	door.CanQuery = sealed
end

function FacilityService.sealDoor(door: BasePart, duration: number)
	local token = (doorToken[door] or 0) + 1
	doorToken[door] = token
	setDoorSealed(door, true)
	FacilityService.cue(door, SOUND_SLAM, 1)
	task.delay(duration, function()
		if doorToken[door] == token then
			doorToken[door] = nil
			setDoorSealed(door, false)
		end
	end)
end

function FacilityService.isSealed(door: BasePart): boolean
	return doorToken[door] ~= nil
end

function FacilityService.camerasOnline(): boolean
	return camerasToken == 0
end

function FacilityService.camerasOffline(duration: number)
	camerasToken += 1
	local token = camerasToken
	MatchState.setPublic("CamerasOnline", false)
	for _, anchor in CollectionService:GetTagged("CameraTerminal") do
		FacilityService.cue(anchor, SOUND_SPARK, 1)
	end
	task.delay(duration, function()
		if camerasToken == token then
			camerasToken = 0
			MatchState.setPublic("CamerasOnline", true)
		end
	end)
end

-- Round over: lights back on, doors open, cameras online.
function FacilityService.reset()
	for zone in blackoutToken do
		setRoomLit(zone, true)
	end
	table.clear(blackoutToken)
	for door in doorToken do
		setDoorSealed(door, false)
	end
	table.clear(doorToken)
	camerasToken = 0
	MatchState.setPublic("CamerasOnline", true)
end

function FacilityService.setLightingMode(mode: LightingMode)
	if mode == currentMode then
		return
	end
	currentMode = mode
	applyMode(mode)
end

function FacilityService.getLightingMode(): LightingMode
	return currentMode
end

return FacilityService
