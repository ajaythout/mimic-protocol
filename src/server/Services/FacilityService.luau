--!strict
--[[
	FacilityService
	Facility-wide environmental state. Phase 1 implements lighting modes used
	by the round flow; later phases (sabotage, mutators) extend the same API.

	Lighting is discovered through CollectionService tags authored by the map
	generator:
	  FacilityLight    Light instances; attribute BaseBrightness
	  EmergencyLight   Light instances that are disabled until an emergency
	  EmergencyBeacon  BaseParts that switch to glowing red in an emergency
]]

local CollectionService = game:GetService("CollectionService")

export type LightingMode = "Normal" | "Emergency"

local FacilityService = {}

local NORMAL_SCALE = 1
local EMERGENCY_SCALE = 0.35
local BEACON_ON = Color3.fromRGB(255, 45, 45)
local BEACON_OFF = Color3.fromRGB(70, 18, 20)

local currentMode: LightingMode = "Normal"

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

function FacilityService.Init()
	-- Cache base brightness before anything modifies a light.
	for _, instance in CollectionService:GetTagged("FacilityLight") do
		if instance:IsA("Light") then
			baseBrightness(instance)
		end
	end
	applyMode("Normal")
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
