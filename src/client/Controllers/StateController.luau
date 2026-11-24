--!strict
--[[
	StateController
	Client-side read model of the game. Other controllers subscribe to its
	signals instead of listening to remotes directly.

	Sources:
	  • ReplicatedStorage.RoundState attributes  (public phase/timer/counts)
	  • LocalPlayer attributes Status / AFK       (public, server-written)
	  • PrivateState / RoleReveal remotes        (this player's secret role)

	Nothing here is authoritative; it only drives presentation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local Signal = require(Shared.Util.Signal)

local StateController = {}

StateController.PhaseChanged = Signal.new() -- (phase, endsAt)
StateController.CountsChanged = Signal.new() -- ()
StateController.RoleChanged = Signal.new() -- (role?, teammates)
StateController.StatusChanged = Signal.new() -- (status)
StateController.AfkChanged = Signal.new() -- (afk)
StateController.Revealed = Signal.new() -- (RoleRevealPayload)
StateController.Tick = Signal.new() -- () fired 5x per second for countdowns

local localPlayer = Players.LocalPlayer
local roundState: Folder

local state = {
	phase = Phases.Waiting :: Phases.Phase,
	phaseEndsAt = 0,
	roundId = 0,
	role = nil :: Net.RoleName?,
	teammates = {} :: { number },
	status = "Standby",
	afk = false,
}

function StateController.getPhase(): Phases.Phase
	return state.phase
end

function StateController.getTimeRemaining(): number
	if state.phaseEndsAt <= 0 then
		return 0
	end
	return math.max(0, state.phaseEndsAt - Workspace:GetServerTimeNow())
end

function StateController.getRole(): Net.RoleName?
	return state.role
end

function StateController.getTeammates(): { number }
	return state.teammates
end

function StateController.getStatus(): string
	return state.status
end

function StateController.isAfk(): boolean
	return state.afk
end

function StateController.isAlive(): boolean
	return state.status == "Alive"
end

function StateController.getPublic(name: string): any
	return roundState:GetAttribute(name)
end

local function readPhase()
	local phase = roundState:GetAttribute("Phase")
	local endsAt = roundState:GetAttribute("PhaseEndsAt")
	state.phase = if Phases.isPhase(phase) then phase :: Phases.Phase else Phases.Waiting
	state.phaseEndsAt = if type(endsAt) == "number" then endsAt else 0
	StateController.PhaseChanged:Fire(state.phase, state.phaseEndsAt)
end

local function setRole(role: Net.RoleName?, teammates: { number }?)
	if state.role == role and teammates == nil then
		return
	end
	state.role = role
	state.teammates = teammates or {}
	StateController.RoleChanged:Fire(state.role, state.teammates)
end

function StateController.Start()
	roundState = Net.roundState()

	roundState:GetAttributeChangedSignal("Phase"):Connect(readPhase)
	roundState:GetAttributeChangedSignal("PhaseEndsAt"):Connect(readPhase)
	for _, name in
		{
			"OperativesRemaining",
			"SurvivorsExtracted",
			"ExtractionRequired",
			"MimicCount",
			"EligiblePlayers",
			"RequiredPlayers",
			"ExtractionOpen",
			"GeneratorsOnline",
			"GeneratorsRequired",
			"PowerRestored",
			"CamerasOnline",
		}
	do
		roundState:GetAttributeChangedSignal(name):Connect(function()
			StateController.CountsChanged:Fire()
		end)
	end
	readPhase()

	local function readStatus()
		local status = localPlayer:GetAttribute("Status")
		state.status = if type(status) == "string" then status else "Standby"
		StateController.StatusChanged:Fire(state.status)
	end
	local function readAfk()
		state.afk = localPlayer:GetAttribute("AFK") == true
		StateController.AfkChanged:Fire(state.afk)
	end
	localPlayer:GetAttributeChangedSignal("Status"):Connect(readStatus)
	localPlayer:GetAttributeChangedSignal("AFK"):Connect(readAfk)
	readStatus()
	readAfk()

	Net.event(Net.Names.PrivateState).OnClientEvent:Connect(function(payload: Net.PrivateStatePayload)
		if type(payload) ~= "table" then
			return
		end
		state.roundId = payload.roundId or 0
		setRole(payload.role, payload.teammates or {})
	end)

	Net.event(Net.Names.RoleReveal).OnClientEvent:Connect(function(payload: Net.RoleRevealPayload)
		if type(payload) ~= "table" then
			return
		end
		state.roundId = payload.roundId
		setRole(payload.role, payload.teammates or {})
		StateController.Revealed:Fire(payload)
	end)

	task.spawn(function()
		while true do
			StateController.Tick:Fire()
			task.wait(0.2)
		end
	end)
end

return StateController
