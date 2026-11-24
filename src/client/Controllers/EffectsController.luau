--!strict
--[[
	EffectsController
	Client-only presentation effects:
	  • elimination burst at the position the server reports (no names)
	  • a subtle red grade while the local player is inside the facility
	    during Escalation and Extraction
	Temporary instances live under a local folder and always clean up.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local StateController = require(script.Parent.StateController)

local EffectsController = {}

local FX_RANGE = 220
local NORMAL_TINT = Color3.fromRGB(240, 247, 255)
local ALERT_TINT = Color3.fromRGB(255, 222, 222)

local fxFolder: Folder

local function eliminationBurst(position: Vector3)
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > FX_RANGE then
		return
	end
	local sphere = Instance.new("Part")
	sphere.Name = "AssimilationBurst"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(255, 50, 60)
	sphere.Transparency = 0.25
	sphere.Size = Vector3.one
	sphere.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Color = sphere.Color
	light.Brightness = 3
	light.Range = 18
	light.Parent = sphere
	sphere.Parent = fxFolder

	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(sphere, info, { Size = Vector3.one * 9, Transparency = 1 }):Play()
	local fade = TweenService:Create(light, info, { Brightness = 0 })
	fade.Completed:Once(function()
		sphere:Destroy()
	end)
	fade:Play()
end

local function refreshGrade()
	local grade = Lighting:FindFirstChild("FacilityGrade")
	if not grade or not grade:IsA("ColorCorrectionEffect") then
		return
	end
	local phase = StateController.getPhase()
	local alert = StateController.isAlive() and (phase == Phases.Escalation or phase == Phases.Extraction)
	TweenService:Create(grade, TweenInfo.new(2, Enum.EasingStyle.Sine), {
		TintColor = if alert then ALERT_TINT else NORMAL_TINT,
	}):Play()
end

function EffectsController.Start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalEffects"
	fxFolder.Parent = Workspace

	Net.event(Net.Names.EliminationFx).OnClientEvent:Connect(function(payload: Net.EliminationFxPayload)
		if type(payload) == "table" and typeof(payload.position) == "Vector3" then
			eliminationBurst(payload.position)
		end
	end)

	StateController.PhaseChanged:Connect(refreshGrade)
	StateController.StatusChanged:Connect(refreshGrade)
	refreshGrade()
end

return EffectsController
