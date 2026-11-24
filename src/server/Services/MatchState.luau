--!strict
--[[
	MatchState
	The server's single source of truth for the current phase and the current
	round's participants (including their secret roles). Other services read
	from here; only RoundService advances phases and creates/ends rounds.

	Public projection: phase, timer and anonymous counts are written to
	attributes on ReplicatedStorage.RoundState. Roles never leave the server
	except through RoleService's targeted FireClient calls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Janitor = require(Shared.Util.Janitor)
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local Signal = require(Shared.Util.Signal)
local WinConditions = require(Shared.Modules.WinConditions)

local PlayerRegistry = require(script.Parent.PlayerRegistry)

export type Role = "Survivor" | "Mimic"
export type Fate = "Active" | "Eliminated" | "Extracted" | "Disconnected"

export type Participant = {
	player: Player,
	userId: number,
	name: string,
	role: Role,
	fate: Fate,
	eliminations: number,
	fateChangedAt: number,
}

export type Round = {
	id: number,
	startedAt: number,
	participants: { [Player]: Participant },
	roster: { Participant },
	mimicCount: number,
	startingSurvivors: number,
	extractionClosed: boolean,
	outcome: WinConditions.Outcome?,
	janitor: Janitor.Janitor,
}

local MatchState = {}

MatchState.PhaseChanged = Signal.new() -- (phase, endsAt)
MatchState.FateChanged = Signal.new() -- (participant, oldFate)
MatchState.RoundChanged = Signal.new() -- (round?) fired on begin/end

local currentPhase: Phases.Phase = Phases.Waiting
local phaseEndsAt = 0
local currentRound: Round? = nil
local roundCounter = 0

local roundStateFolder: Folder

function MatchState.Init()
	roundStateFolder = Net.roundState()
	roundStateFolder:SetAttribute("Phase", currentPhase)
	roundStateFolder:SetAttribute("PhaseEndsAt", 0)

	-- A participant who leaves mid-round keeps their roster entry (for the
	-- results screen) but counts as Disconnected for win conditions.
	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		local round = currentRound
		local participant = round and round.participants[player]
		if participant and participant.fate == "Active" then
			MatchState.setFate(participant, "Disconnected")
		end
	end)
end

-- Phase ----------------------------------------------------------------------

function MatchState.getPhase(): Phases.Phase
	return currentPhase
end

function MatchState.getPhaseEndsAt(): number
	return phaseEndsAt
end

function MatchState.setPhase(phase: Phases.Phase, duration: number?)
	currentPhase = phase
	phaseEndsAt = if duration then Workspace:GetServerTimeNow() + duration else 0
	roundStateFolder:SetAttribute("PhaseEndsAt", phaseEndsAt)
	roundStateFolder:SetAttribute("Phase", phase)
	MatchState.PhaseChanged:Fire(phase, phaseEndsAt)
end

function MatchState.setPublic(name: string, value: any)
	roundStateFolder:SetAttribute(name, value)
end

-- Rounds -----------------------------------------------------------------------

function MatchState.beginRound(players: { Player }): Round
	assert(currentRound == nil, "beginRound called while a round is active")
	roundCounter += 1

	local round: Round = {
		id = roundCounter,
		startedAt = Workspace:GetServerTimeNow(),
		participants = {},
		roster = {},
		mimicCount = 0,
		startingSurvivors = 0,
		extractionClosed = false,
		outcome = nil,
		janitor = Janitor.new(),
	}

	for _, player in players do
		local participant: Participant = {
			player = player,
			userId = player.UserId,
			name = player.DisplayName,
			role = "Survivor",
			fate = "Active",
			eliminations = 0,
			fateChangedAt = round.startedAt,
		}
		round.participants[player] = participant
		table.insert(round.roster, participant)
	end

	currentRound = round
	roundStateFolder:SetAttribute("RoundId", round.id)
	MatchState.RoundChanged:Fire(round)
	return round
end

function MatchState.endRound()
	local round = currentRound
	if not round then
		return
	end
	currentRound = nil
	round.janitor:Cleanup()
	MatchState.setPublic("OperativesRemaining", 0)
	MatchState.setPublic("SurvivorsExtracted", 0)
	MatchState.setPublic("ExtractionRequired", 0)
	MatchState.setPublic("ExtractionOpen", false)
	MatchState.setPublic("MimicCount", 0)
	MatchState.RoundChanged:Fire(nil)
end

function MatchState.getRound(): Round?
	return currentRound
end

function MatchState.getParticipant(player: Player): Participant?
	local round = currentRound
	return round and round.participants[player]
end

-- Returns the participant only if they are still playing inside the round.
function MatchState.getActiveParticipant(player: Player): Participant?
	local participant = MatchState.getParticipant(player)
	if participant and participant.fate == "Active" then
		return participant
	end
	return nil
end

function MatchState.getActiveByRole(role: Role): { Participant }
	local list = {}
	local round = currentRound
	if round then
		for _, participant in round.roster do
			if
				participant.fate == "Active"
				and participant.role == role
				and participant.player.Parent ~= nil
			then
				table.insert(list, participant)
			end
		end
	end
	return list
end

function MatchState.setFate(participant: Participant, fate: Fate)
	if participant.fate == fate then
		return
	end
	local old = participant.fate
	participant.fate = fate
	participant.fateChangedAt = Workspace:GetServerTimeNow()

	-- Entering the facility (Status "Alive") is applied by RoundService at
	-- deployment; leaving it is mirrored here.
	if fate == "Eliminated" or fate == "Extracted" then
		PlayerRegistry.setStatus(participant.player, fate)
	end

	MatchState.FateChanged:Fire(participant, old)
end

-- Win-condition snapshot of the current round.
function MatchState.snapshot(round: Round): WinConditions.Snapshot
	local snapshot: WinConditions.Snapshot = {
		mimicsActive = 0,
		survivorsActive = 0,
		survivorsExtracted = 0,
		survivorsEliminated = 0,
		survivorsDisconnected = 0,
		startingSurvivors = round.startingSurvivors,
		extractionClosed = round.extractionClosed,
	}
	for _, participant in round.roster do
		if participant.role == "Mimic" then
			if participant.fate == "Active" then
				snapshot.mimicsActive += 1
			end
		elseif participant.fate == "Active" then
			snapshot.survivorsActive += 1
		elseif participant.fate == "Extracted" then
			snapshot.survivorsExtracted += 1
		elseif participant.fate == "Eliminated" then
			snapshot.survivorsEliminated += 1
		elseif participant.fate == "Disconnected" then
			snapshot.survivorsDisconnected += 1
		end
	end
	return snapshot
end

-- Publishes anonymous counts. Never publishes per-role "alive" numbers, which
-- would let players deduce how many Mimics remain.
function MatchState.publishCounts(round: Round, snapshot: WinConditions.Snapshot, required: number)
	MatchState.setPublic("OperativesRemaining", snapshot.mimicsActive + snapshot.survivorsActive)
	MatchState.setPublic("SurvivorsExtracted", snapshot.survivorsExtracted)
	MatchState.setPublic("ExtractionRequired", required)
	MatchState.setPublic("MimicCount", round.mimicCount)
end

return MatchState
