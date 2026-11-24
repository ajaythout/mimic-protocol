--!strict
--[[
	RoundService
	Orchestrates the round lifecycle. It is the only system that advances
	phases, starts rounds and ends rounds.

	Waiting      not enough ready players; re-checks on every readiness change
	Intermission countdown in the Deployment Bay; aborts if players drop
	RoleReveal   secret roles assigned and revealed privately
	Deployment   players teleported to scattered facility spawn points;
	             Mimic abilities still dormant
	Active       main investigation phase; Mimic attacks unlock
	Escalation   emergency lighting, rising tension
	Extraction   lift opens; survivors must board before it departs
	Results      winner + full role reveal, everyone back to the bay

	Robustness rules:
	  • Every wait is bounded by a timer AND interruptible by an outcome.
	  • Win conditions are re-evaluated on every fate change (elimination,
	    extraction, disconnect), not by polling.
	  • A Lua error anywhere inside a round is caught; the round is cancelled,
	    players are returned to the bay, and the loop continues.
	  • Outcomes before the Active phase cancel the round (no winner) because
	    no gameplay has happened yet. If every Mimic leaves before Active, a
	    random Survivor is promoted instead when possible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local Signal = require(Shared.Util.Signal)
local WinConditions = require(Shared.Modules.WinConditions)

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local EliminationService = require(script.Parent.EliminationService)
local ExtractionService = require(script.Parent.ExtractionService)
local FacilityService = require(script.Parent.FacilityService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)
local RoleService = require(script.Parent.RoleService)

local RoundService = {}

local roundInterrupt = Signal.new()
local resultRemote: RemoteEvent
local random = Random.new()

local EXTRACTION_FINAL_WARNING = 10

local function phaseDuration(name: string): number
	local seconds = (GameConfig.Timings :: any)[name] :: number
	if RunService:IsStudio() and GameConfig.Dev.FastRoundsInStudio then
		seconds *= GameConfig.Dev.DevTimingScale
	end
	return math.max(1, seconds)
end

--[[
	Yields until `duration` elapses or one of `triggers` fires while isDone()
	returns true. Returns true when finished early by isDone().
]]
local function waitPhase(duration: number, triggers: { Signal.Signal }, isDone: () -> boolean): boolean
	if isDone() then
		return true
	end

	local thread = coroutine.running()
	local finished = false
	local connections: { Signal.Connection } = {}
	local timer: thread

	local function finish(early: boolean)
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		if coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		task.spawn(thread, early)
	end

	timer = task.delay(duration, finish, false)
	for _, trigger in triggers do
		table.insert(
			connections,
			trigger:Connect(function()
				if isDone() then
					finish(true)
				end
			end)
		)
	end

	return coroutine.yield()
end

local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function cancelledOutcome(required: number): WinConditions.Outcome
	return { winner = "None", reason = "Abandoned", required = required }
end

local function evaluate(round: MatchState.Round)
	if round.outcome then
		return
	end
	local phase = MatchState.getPhase()
	if not Phases.InRound[phase] then
		return
	end
	local beforeActive = phase == Phases.RoleReveal or phase == Phases.Deployment

	local snapshot = MatchState.snapshot(round)
	if snapshot.mimicsActive == 0 and beforeActive then
		local promoted = RoleService.promoteReplacement(round)
		if promoted then
			Announcer.to(
				promoted.player,
				"THE ORGANISM CHOSE YOU",
				"The original Mimic lost contact. You are now a Mimic.",
				"Critical",
				6
			)
			snapshot = MatchState.snapshot(round)
		end
	end

	local required = WinConditions.requiredExtractions(snapshot, GameConfig.Extraction)
	MatchState.publishCounts(round, snapshot, required)

	local outcome = WinConditions.evaluate(snapshot, GameConfig.Extraction)
	if outcome then
		round.outcome = if beforeActive then cancelledOutcome(required) else outcome
		roundInterrupt:Fire()
	end
end

local function deploy(round: MatchState.Round)
	local spawns = shuffle(CharacterService.getFacilitySpawns())
	if #spawns == 0 then
		error("No parts tagged FacilitySpawn exist; cannot deploy players")
	end

	local index = 0
	for _, participant in round.roster do
		local player = participant.player
		if participant.fate == "Active" and player.Parent == Players then
			index += 1
			local spawnPart = spawns[((index - 1) % #spawns) + 1]
			local cframe = spawnPart.CFrame
			if index > #spawns then
				-- More players than spawn points: offset to avoid stacking.
				cframe *= CFrame.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
			end
			PlayerRegistry.setStatus(player, "Alive")
			task.spawn(CharacterService.deployTo, player, cframe)
		end
	end
end

local function runRound(round: MatchState.Round)
	local triggers = { roundInterrupt }
	local function over(): boolean
		return round.outcome ~= nil
	end

	RoleService.assign(round)
	round.janitor:Add(MatchState.FateChanged:Connect(function()
		evaluate(round)
	end))

	-- ROLE REVEAL ---------------------------------------------------------------
	local revealDuration = phaseDuration("RoleReveal")
	MatchState.setPhase(Phases.RoleReveal, revealDuration)
	RoleService.sendReveal(round)
	evaluate(round)
	if waitPhase(revealDuration, triggers, over) then
		return
	end

	-- DEPLOYMENT ----------------------------------------------------------------
	deploy(round)
	local deployDuration = phaseDuration("Deployment")
	MatchState.setPhase(Phases.Deployment, deployDuration)
	Announcer.all("DEPLOYMENT", "Sweep the facility. Stay together. Trust no one.", "Info", 5)
	local mimicPlayers = {}
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		table.insert(mimicPlayers, mimic.player)
	end
	Announcer.toList(
		mimicPlayers,
		"ORGANISM DORMANT",
		"Blend in. Your abilities awaken when deployment ends.",
		"Warning",
		6
	)
	evaluate(round)
	if waitPhase(deployDuration, triggers, over) then
		return
	end

	-- ACTIVE ----------------------------------------------------------------------
	local activeDuration = phaseDuration("Active")
	MatchState.setPhase(Phases.Active, activeDuration)
	EliminationService.primeCooldowns(GameConfig.Strike.InitialCooldown)
	Announcer.all("CONTAINMENT BREACH", "Something in this facility is not what it seems.", "Critical", 5)
	mimicPlayers = {}
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		table.insert(mimicPlayers, mimic.player)
	end
	Announcer.toList(
		mimicPlayers,
		"ABILITIES ONLINE",
		"Get close to a survivor, unseen, and ASSIMILATE.",
		"Critical",
		6
	)
	if waitPhase(activeDuration, triggers, over) then
		return
	end

	-- ESCALATION ------------------------------------------------------------------
	local escalationDuration = phaseDuration("Escalation")
	FacilityService.setLightingMode("Emergency")
	MatchState.setPhase(Phases.Escalation, escalationDuration)
	Announcer.all("ESCALATION", "Emergency power engaged. The extraction lift is on its way.", "Critical", 6)
	if waitPhase(escalationDuration, triggers, over) then
		return
	end

	-- EXTRACTION ------------------------------------------------------------------
	local extractionDuration = phaseDuration("Extraction")
	ExtractionService.open()
	MatchState.setPhase(Phases.Extraction, extractionDuration)
	Announcer.all(
		"EXTRACTION LIFT OPEN",
		"Reach the lift south of the Central Atrium before it departs.",
		"Success",
		6
	)

	local warningAt = math.max(0, extractionDuration - EXTRACTION_FINAL_WARNING)
	if warningAt > 0 then
		if waitPhase(warningAt, triggers, over) then
			return
		end
		Announcer.all(`LIFT DEPARTS IN {EXTRACTION_FINAL_WARNING} SECONDS`, nil, "Critical", 4)
	end
	if waitPhase(extractionDuration - warningAt, triggers, over) then
		return
	end

	round.extractionClosed = true
	evaluate(round)
	if not round.outcome then
		-- Defensive: evaluate() always resolves once extraction has closed.
		round.outcome = cancelledOutcome(0)
	end
end

local function buildResult(round: MatchState.Round, outcome: WinConditions.Outcome): Net.RoundResultPayload
	local roster: { Net.RosterEntry } = {}
	local extracted = 0
	for _, participant in round.roster do
		local fate: any = participant.fate
		if fate == "Active" then
			fate = if outcome.winner == "None" then "Active" else "Survived"
		end
		if participant.fate == "Extracted" then
			extracted += 1
		end
		table.insert(roster, {
			userId = participant.userId,
			name = participant.name,
			role = participant.role,
			fate = fate,
			eliminations = participant.eliminations,
		})
	end

	return {
		roundId = round.id,
		winner = outcome.winner,
		reason = outcome.reason,
		reasonText = WinConditions.ReasonText[outcome.reason] or "",
		extracted = extracted,
		required = outcome.required,
		durationSeconds = math.floor(Workspace:GetServerTimeNow() - round.startedAt),
		roster = roster,
	}
end

local function finishRound(round: MatchState.Round)
	-- Each step is protected so one failure cannot strand players.
	local function step(label: string, fn: () -> ())
		local ok, err = pcall(fn :: any)
		if not ok then
			warn(`[RoundService] finishRound/{label} failed: {err}`)
		end
	end

	local outcome = round.outcome or cancelledOutcome(0)
	local payload: Net.RoundResultPayload? = nil

	step("environment", function()
		ExtractionService.close()
		FacilityService.setLightingMode("Normal")
	end)
	step("result", function()
		payload = buildResult(round, outcome)
	end)
	step("history", function()
		if outcome.winner ~= "None" then
			RoleService.commitHistory(round)
		end
	end)

	local returning: { Player } = {}
	step("return", function()
		for _, participant in round.roster do
			local player = participant.player
			if player.Parent == Players then
				table.insert(returning, player)
				local wasInFacility = PlayerRegistry.getStatus(player) == "Alive"
				PlayerRegistry.setStatus(player, "Standby")
				if wasInFacility then
					task.spawn(CharacterService.spawnInLobby, player)
				end
			end
		end
	end)

	step("cleanup", function()
		RoleService.clearPrivateState(returning)
		EliminationService.reset()
		MatchState.endRound()
	end)

	local resultsDuration = phaseDuration("Results")
	MatchState.setPhase(Phases.Results, resultsDuration)
	if payload then
		resultRemote:FireAllClients(payload)
	end
	task.wait(resultsDuration)
end

local function publishEligible()
	MatchState.setPublic("EligiblePlayers", #PlayerRegistry.getEligiblePlayers())
	MatchState.setPublic("RequiredPlayers", PlayerRegistry.requiredPlayers())
end

local function runCycle()
	local required = PlayerRegistry.requiredPlayers()
	local function enough(): boolean
		return #PlayerRegistry.getEligiblePlayers() >= required
	end
	publishEligible()

	if not enough() then
		MatchState.setPhase(Phases.Waiting)
		while not enough() do
			-- Event-driven; the timeout only guards against a missed signal.
			waitPhase(15, { PlayerRegistry.EligibilityChanged }, enough)
		end
	end

	local intermission = phaseDuration("Intermission")
	MatchState.setPhase(Phases.Intermission, intermission)
	local aborted = waitPhase(intermission, { PlayerRegistry.EligibilityChanged }, function()
		return not enough()
	end)
	if aborted then
		Announcer.all("DEPLOYMENT POSTPONED", "Not enough personnel are ready.", "Warning", 4)
		return
	end

	local players = shuffle(PlayerRegistry.getEligiblePlayers())
	while #players > GameConfig.Players.MaxPerRound do
		table.remove(players)
	end
	if #players < required then
		return
	end

	local round = MatchState.beginRound(players)
	local ok, err = xpcall(runRound :: any, debug.traceback, round)
	if not ok then
		warn(`[RoundService] round {round.id} failed and was cancelled:\n{err}`)
		round.outcome = round.outcome or cancelledOutcome(0)
		Announcer.all("FACILITY RESET", "A system fault ended the round early.", "Warning", 5)
	end
	finishRound(round)
end

function RoundService.Init()
	resultRemote = Net.event(Net.Names.RoundResult)
	PlayerRegistry.EligibilityChanged:Connect(publishEligible)
end

function RoundService.Start()
	task.spawn(function()
		while true do
			local ok, err = xpcall(runCycle :: any, debug.traceback)
			if not ok then
				warn(`[RoundService] cycle error:\n{err}`)
				-- Last-resort recovery: make sure no half-finished round lingers.
				local round = MatchState.getRound()
				if round then
					round.outcome = round.outcome or cancelledOutcome(0)
					pcall(finishRound :: any, round)
				end
				MatchState.setPhase(Phases.Waiting)
				task.wait(3)
			end
		end
	end)
end

return RoundService
