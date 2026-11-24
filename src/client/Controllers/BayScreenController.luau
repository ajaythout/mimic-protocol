--!strict
--[[
	BayScreenController
	Drives the large status screen in the Deployment Bay (tagged BayScreen).
	Updates are local to this client; nothing is sent over the network.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local StateController = require(script.Parent.StateController)

local BayScreenController = {}

type Screen = { phase: TextLabel, timer: TextLabel, detail: TextLabel }
local screens: { [Instance]: Screen } = {}

local function bind(part: Instance)
	local display = part:FindFirstChild("Display")
	if not display then
		return
	end
	local phase = display:FindFirstChild("Phase")
	local timer = display:FindFirstChild("Timer")
	local detail = display:FindFirstChild("Detail")
	if
		phase
		and phase:IsA("TextLabel")
		and timer
		and timer:IsA("TextLabel")
		and detail
		and detail:IsA("TextLabel")
	then
		screens[part] = { phase = phase, timer = timer, detail = detail }
	end
end

local function detailText(phase: string): string
	local get = StateController.getPublic
	if phase == Phases.Waiting then
		return `{get("EligiblePlayers") or 0} / {get("RequiredPlayers") or 0} OPERATIVES READY`
	elseif phase == Phases.Intermission then
		return `{get("EligiblePlayers") or 0} OPERATIVES READY FOR DEPLOYMENT`
	elseif Phases.InFacility[phase] then
		return `{get("OperativesRemaining") or 0} IN FACILITY  ·  EXTRACTED {get("SurvivorsExtracted") or 0}/{get(
			"ExtractionRequired"
		) or 0}`
	elseif phase == Phases.RoleReveal then
		return "ASSIGNING ROLES"
	elseif phase == Phases.Results then
		return "DEBRIEF IN PROGRESS"
	end
	return ""
end

local function refresh()
	local phase = StateController.getPhase()
	local hasTimer = phase ~= Phases.Waiting
	for part, screen in screens do
		if part.Parent == nil then
			screens[part] = nil
			continue
		end
		screen.phase.Text = Phases.displayName(phase)
		screen.timer.Text = if hasTimer
			then Components.formatTime(StateController.getTimeRemaining())
			else "--:--"
		screen.detail.Text = detailText(phase)
	end
end

function BayScreenController.Start()
	for _, part in CollectionService:GetTagged("BayScreen") do
		bind(part)
	end
	CollectionService:GetInstanceAddedSignal("BayScreen"):Connect(bind)
	StateController.Tick:Connect(refresh)
	StateController.PhaseChanged:Connect(refresh)
	refresh()
end

return BayScreenController
