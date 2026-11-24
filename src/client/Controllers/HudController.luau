--!strict
--[[
	HudController
	The always-on heads-up display:
	  • PhaseBar      (top centre)  phase name, countdown, phase progress
	  • Identity      (top left)    secret role chip + current location
	  • Objective     (left)        role- and phase-specific instructions
	                                and anonymous crew counts
	Location comes from invisible RoomZone volumes authored in the map.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local HudController = {}

local localPlayer = Players.LocalPlayer

local ui = {} :: {
	gui: ScreenGui,
	phaseBar: Frame,
	phaseLabel: TextLabel,
	timerLabel: TextLabel,
	progressFill: Frame,
	identity: Frame,
	roleRow: Frame,
	roleValue: TextLabel,
	locationValue: TextLabel,
	locationCode: TextLabel,
	objective: Frame,
	objectiveHeader: TextLabel,
	objectiveBody: TextLabel,
	statsOperatives: TextLabel,
	statsExtracted: TextLabel,
	statsGenerators: TextLabel,
	statsMimics: TextLabel,
}

-- Total length of a phase, mirroring the server's timing rules.
local function phaseLength(phase: string): number?
	local seconds = (GameConfig.Timings :: any)[phase]
	if type(seconds) ~= "number" then
		return nil
	end
	if RunService:IsStudio() and GameConfig.Dev.FastRoundsInStudio then
		seconds *= GameConfig.Dev.DevTimingScale
	end
	return math.max(1, seconds)
end

local function build()
	local gui = Components.screen("Hud", Theme.Layers.Hud)
	ui.gui = gui

	-- Phase bar ----------------------------------------------------------------
	local bar = Components.panel({
		Name = "PhaseBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(300, 64),
		Parent = gui,
	})
	ui.phaseBar = bar
	ui.phaseLabel = Components.label({
		Name = "Phase",
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.Cyan,
		Text = "",
		Parent = bar,
	}, "Display")
	ui.timerLabel = Components.label({
		Name = "Timer",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Timer,
		Text = "--:--",
		Parent = bar,
	}, "MonoBold")
	local track, fill = Components.progress({
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -28, 0, 2),
		Parent = bar,
	})
	ui.progressFill = fill
	track.Name = "Progress"

	-- Identity (role + location) ----------------------------------------------------
	local identity = Components.create("Frame", {
		Name = "Identity",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	Components.list(identity, 6)
	ui.identity = identity

	local roleRow = Components.panel({
		Name = "Role",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Visible = false,
		Parent = identity,
	}, { brackets = false })
	Components.padding(roleRow, 0, 12)
	Components.list(roleRow, 8, Enum.FillDirection.Horizontal).VerticalAlignment =
		Enum.VerticalAlignment.Center
	Components.label({
		Name = "Caption",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "ROLE",
		LayoutOrder = 1,
		Parent = roleRow,
	}, "Display")
	ui.roleValue = Components.label({
		Name = "Value",
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Theme.TextSize.Label,
		Text = "",
		LayoutOrder = 2,
		Parent = roleRow,
	}, "Display")
	ui.roleRow = roleRow

	local locationRow = Components.create("Frame", {
		Name = "Location",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 34),
		LayoutOrder = 2,
		Parent = identity,
	})
	ui.locationValue = Components.label({
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TextSize.Label,
		Text = "",
		Parent = locationRow,
	}, "Display")
	ui.locationCode = Components.label({
		Name = "Code",
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "",
		Parent = locationRow,
	}, "Mono")

	-- Objective card ---------------------------------------------------------------
	local objective = Components.panel({
		Name = "Objective",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.45, 0),
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	})
	local objectiveContent = Components.panelContent(objective, 12, 14)
	Components.list(objectiveContent, 8)
	ui.objective = objective
	ui.objectiveHeader = Components.label({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.Cyan,
		Text = "OBJECTIVE",
		LayoutOrder = 1,
		Parent = objectiveContent,
	}, "Display")
	ui.objectiveBody = Components.label({
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Theme.TextSize.Body,
		Text = "",
		LayoutOrder = 2,
		Parent = objectiveContent,
	}, "Body")
	Components.create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Colors.StrokeMuted,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = objectiveContent,
	})
	local function statRow(name: string, caption: string, order: number): TextLabel
		local row = Components.create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = order,
			Parent = objectiveContent,
		})
		Components.label({
			Name = "Caption",
			Size = UDim2.fromScale(0.6, 1),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextMuted,
			Text = caption,
			Parent = row,
		}, "Display")
		return Components.label({
			Name = "Value",
			Position = UDim2.fromScale(0.6, 0),
			Size = UDim2.fromScale(0.4, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Theme.TextSize.Body,
			Text = "-",
			Parent = row,
		}, "MonoBold")
	end
	ui.statsOperatives = statRow("Operatives", "OPERATIVES", 4)
	ui.statsGenerators = statRow("Generators", "GENERATORS", 5)
	ui.statsExtracted = statRow("Extracted", "EXTRACTED", 6)
	ui.statsMimics = statRow("Mimics", "MIMICS AT START", 7)
end

-- Generators still needed before the lift has power (0 once restored).
local function generatorsNeeded(): number
	if StateController.getPublic("PowerRestored") == true then
		return 0
	end
	local need = StateController.getPublic("GeneratorsRequired") or 0
	local online = StateController.getPublic("GeneratorsOnline") or 0
	return math.max(0, need - online)
end

local function objectiveText(): string
	local role = StateController.getRole()
	local phase = StateController.getPhase()
	local required = StateController.getPublic("ExtractionRequired") or 0
	local needed = generatorsNeeded()
	if role == "Mimic" then
		if phase == Phases.Deployment then
			return "Blend in with the crew. Your abilities awaken when deployment ends."
		elseif phase == Phases.Extraction then
			return `The lift is open. Stop them there: fewer than {required} survivors may escape.`
		end
		return "Isolate survivors and ASSIMILATE them where nobody can see. Keep the crew from reaching extraction."
	end
	if phase == Phases.Deployment then
		return "Spread out and learn the facility. Something is dormant inside your crew."
	elseif phase == Phases.Active and needed > 0 then
		return `Repair {needed} more generator(s) to power the lift. Watch who drifts away, and whose repairs never move the bar.`
	elseif phase == Phases.Active then
		return "Watch the crew. Notice who drifts away, who lingers near the missing, who never seems to be anywhere. Stay in pairs."
	elseif phase == Phases.Escalation and needed > 0 then
		return `Emergency power engaged. Restore {needed} more generator(s) or the lift never comes.`
	elseif phase == Phases.Escalation then
		return "Emergency power engaged. Regroup and make for the EXTRACTION LIFT south of the Central Atrium."
	elseif phase == Phases.Extraction and needed > 0 then
		return `The lift has no power. Restore {needed} more generator(s) and it opens at once.`
	elseif phase == Phases.Extraction then
		return `THE LIFT IS OPEN. Board it before it departs. {required} survivor(s) must escape.`
	end
	return "Stand by."
end

local function phaseAccent(phase: string): Color3
	if phase == Phases.Escalation or phase == Phases.Extraction then
		return Theme.Colors.Red
	end
	return Theme.Colors.Cyan
end

local function refreshPhase()
	local phase = StateController.getPhase()
	ui.phaseLabel.Text = Phases.displayName(phase)
	ui.phaseLabel.TextColor3 = phaseAccent(phase)
	ui.progressFill.BackgroundColor3 = phaseAccent(phase)
end

local function refreshTimer()
	local phase = StateController.getPhase()
	local remaining = StateController.getTimeRemaining()
	if StateController.getPublic("PhaseEndsAt") == 0 or phase == Phases.Waiting then
		ui.timerLabel.Text = "--:--"
		ui.progressFill.Size = UDim2.fromScale(0, 1)
		return
	end
	ui.timerLabel.Text = Components.formatTime(remaining)
	local total = phaseLength(phase) or remaining
	local fraction = if total > 0 then math.clamp(remaining / total, 0, 1) else 0
	ui.progressFill.Size = UDim2.fromScale(fraction, 1)
	ui.timerLabel.TextColor3 = if remaining <= 10 and Phases.InFacility[phase]
		then Theme.Colors.Red
		else Theme.Colors.Text
end

local function refreshObjective()
	local inRound = StateController.isAlive() and StateController.getRole() ~= nil
	ui.objective.Visible = inRound
	ui.roleRow.Visible = inRound
	if not inRound then
		return
	end
	local role = StateController.getRole()
	ui.roleValue.Text = string.upper(role or "")
	ui.roleValue.TextColor3 = Theme.RoleColors[role or "Survivor"]
	ui.objectiveHeader.TextColor3 = Theme.RoleColors[role or "Survivor"]
	ui.objectiveBody.Text = objectiveText()
	local extracted = StateController.getPublic("SurvivorsExtracted") or 0
	local required = StateController.getPublic("ExtractionRequired") or 0
	ui.statsOperatives.Text = tostring(StateController.getPublic("OperativesRemaining") or 0)
	ui.statsExtracted.Text = `{extracted} / {required}`
	local generatorsRequired = StateController.getPublic("GeneratorsRequired") or 0
	local generatorRow = ui.statsGenerators.Parent :: GuiObject
	generatorRow.Visible = generatorsRequired > 0
	ui.statsGenerators.Text = `{math.min(
		StateController.getPublic("GeneratorsOnline") or 0,
		generatorsRequired
	)} / {generatorsRequired}`
	ui.statsGenerators.TextColor3 = if StateController.getPublic("PowerRestored") == true
		then Theme.Colors.Teal
		else Theme.Colors.Text
	ui.statsMimics.Text = tostring(StateController.getPublic("MimicCount") or 0)
end

-- Location ---------------------------------------------------------------------------

local function zoneContaining(position: Vector3): BasePart?
	for _, zone in CollectionService:GetTagged("RoomZone") do
		if zone:IsA("BasePart") then
			local offset = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size * 0.5
			if
				math.abs(offset.X) <= half.X
				and math.abs(offset.Y) <= half.Y
				and math.abs(offset.Z) <= half.Z
			then
				return zone
			end
		end
	end
	return nil
end

local lastZone: BasePart? = nil
local function refreshLocation()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zone = if root and root:IsA("BasePart") then zoneContaining(root.Position) else nil
	if zone == lastZone then
		return
	end
	lastZone = zone
	if zone then
		ui.locationValue.Text = tostring(zone:GetAttribute("DisplayName") or "")
		ui.locationCode.Text = tostring(zone:GetAttribute("Code") or "")
	else
		ui.locationValue.Text = ""
		ui.locationCode.Text = ""
	end
end

function HudController.Start()
	build()
	StateController.PhaseChanged:Connect(function()
		refreshPhase()
		refreshTimer()
		refreshObjective()
	end)
	StateController.CountsChanged:Connect(refreshObjective)
	StateController.RoleChanged:Connect(refreshObjective)
	StateController.StatusChanged:Connect(refreshObjective)

	local tickCount = 0
	StateController.Tick:Connect(function()
		refreshTimer()
		tickCount += 1
		if tickCount % 2 == 0 then
			refreshLocation()
		end
	end)

	refreshPhase()
	refreshTimer()
	refreshObjective()
end

return HudController
