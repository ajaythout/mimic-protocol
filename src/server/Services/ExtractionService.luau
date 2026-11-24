--!strict
--[[
	ExtractionService
	Controls the extraction lift (Workspace.Facility.Extraction).

	Authored map contract (created by map/build.luau):
	  Extraction (Model)
	    LiftZone      Part, invisible; survivors whose root is inside escape
	    GateLeft      Part, attribute OpenOffset: Vector3 (object space)
	    GateRight     Part, attribute OpenOffset: Vector3 (object space)
	    StatusScreen  Part with SurfaceGui > TextLabel "StatusText"
	    LiftLight     Part containing a PointLight (tinted by state)

	While open, a lightweight 4 Hz check runs only for active Survivors (at most
	a dozen distance tests). It stops as soon as the lift closes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local ExtractionService = {}

ExtractionService.PlayerExtracted = Signal.new() -- (participant)

type Gate = { part: BasePart, closed: CFrame, open: CFrame }

local model: Model? = nil
local zone: BasePart? = nil
local gates: { Gate } = {}
local statusText: TextLabel? = nil
local liftLight: Light? = nil

local isOpen = false
local loopThread: thread? = nil

local GATE_TWEEN = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local LOCKED_COLOR = Color3.fromRGB(255, 70, 70)
local OPEN_COLOR = Color3.fromRGB(80, 230, 255)

local function setPresentation(open: boolean)
	if statusText then
		statusText.Text = if open then "LIFT ONLINE — BOARD NOW" else "EXTRACTION LOCKED"
		statusText.TextColor3 = if open then OPEN_COLOR else LOCKED_COLOR
	end
	if liftLight then
		liftLight.Color = if open then OPEN_COLOR else LOCKED_COLOR
	end
	for _, gate in gates do
		TweenService:Create(gate.part, GATE_TWEEN, { CFrame = if open then gate.open else gate.closed })
			:Play()
	end
end

local function isInsideZone(position: Vector3): boolean
	local box = zone
	if not box then
		return false
	end
	local localPos = box.CFrame:PointToObjectSpace(position)
	local half = box.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function extract(participant: MatchState.Participant)
	if participant.fate ~= "Active" or participant.role ~= "Survivor" then
		return
	end
	MatchState.setFate(participant, "Extracted")
	ExtractionService.PlayerExtracted:Fire(participant)
	Announcer.all(`{participant.name} reached the extraction lift`, nil, "Success", 4)
	Announcer.to(
		participant.player,
		"EXTRACTED",
		"You escaped. Watch the rest of the round from the bay.",
		"Success",
		5
	)

	-- This extraction can end the round, so by the time the delay runs the
	-- round may be gone. Key off the character instead: return it to the bay
	-- unless the player has respawned or been redeployed since.
	local player = participant.player
	local character = player.Character
	task.delay(1.2, function()
		if
			player.Parent == Players
			and player.Character == character
			and PlayerRegistry.getStatus(player) ~= "Alive"
		then
			CharacterService.spawnInLobby(player)
		end
	end)
end

local function zoneLoop()
	while isOpen do
		for _, participant in MatchState.getActiveByRole("Survivor") do
			local root = CharacterService.getRoot(participant.player)
			if root and isInsideZone(root.Position) then
				extract(participant)
			end
		end
		task.wait(GameConfig.Extraction.ZoneCheckInterval)
	end
	loopThread = nil
end

function ExtractionService.Init()
	local facility = Workspace:FindFirstChild("Facility")
	local found = facility and facility:FindFirstChild("Extraction")
	if not found or not found:IsA("Model") then
		warn("[ExtractionService] Workspace.Facility.Extraction is missing; extraction disabled")
		return
	end
	model = found

	local zonePart = found:FindFirstChild("LiftZone")
	if zonePart and zonePart:IsA("BasePart") then
		zone = zonePart
	else
		warn("[ExtractionService] Extraction.LiftZone is missing")
	end

	for _, name in { "GateLeft", "GateRight" } do
		local part = found:FindFirstChild(name)
		local offset = part and part:GetAttribute("OpenOffset")
		if part and part:IsA("BasePart") and typeof(offset) == "Vector3" then
			table.insert(
				gates,
				{ part = part, closed = part.CFrame, open = part.CFrame * CFrame.new(offset) }
			)
		else
			warn(`[ExtractionService] Extraction.{name} is missing or has no OpenOffset`)
		end
	end

	local screen = found:FindFirstChild("StatusScreen")
	local label = screen and screen:FindFirstChild("StatusText", true)
	if label and label:IsA("TextLabel") then
		statusText = label
	end
	local lightPart = found:FindFirstChild("LiftLight")
	local light = lightPart and lightPart:FindFirstChildWhichIsA("Light")
	if light then
		liftLight = light
	end

	setPresentation(false)
end

function ExtractionService.isAvailable(): boolean
	return model ~= nil and zone ~= nil
end

function ExtractionService.isOpen(): boolean
	return isOpen
end

function ExtractionService.open()
	if isOpen then
		return
	end
	isOpen = true
	MatchState.setPublic("ExtractionOpen", true)
	setPresentation(true)
	if loopThread == nil then
		loopThread = task.spawn(zoneLoop)
	end
end

function ExtractionService.close()
	if not isOpen then
		return
	end
	isOpen = false
	MatchState.setPublic("ExtractionOpen", false)
	setPresentation(false)
end

return ExtractionService
