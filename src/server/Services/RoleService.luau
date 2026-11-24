--!strict
--[[
	RoleService
	Assigns secret roles at the start of a round and delivers them privately.

	• assign(round, extraMimics?)   fills participant.role using RoleAssignment
	• sendReveal(round)             RoleReveal remote, one FireClient per player
	• sendPrivateState(player)      re-sync for a client that (re)loaded
	• promoteReplacement(round)     if every Mimic left before Active, a random
	                                active Survivor becomes the Mimic
	• commitHistory(round)          updates anti-streak weights (session only)

	Fairness: selection is weighted only by recent role history; nothing a
	player can buy or toggle changes their odds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local RoleAssignment = require(Shared.Modules.RoleAssignment)

local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local RoleService = {}

local history: { [number]: RoleAssignment.History } = {}
local random = Random.new()

local revealRemote: RemoteEvent
local privateStateRemote: RemoteEvent

local function rng(): number
	return random:NextNumber()
end

local function mimicUserIds(round: MatchState.Round): { number }
	local ids = {}
	for _, participant in round.roster do
		if participant.role == "Mimic" then
			table.insert(ids, participant.userId)
		end
	end
	return ids
end

local function teammatesFor(round: MatchState.Round, participant: MatchState.Participant): { number }
	if participant.role ~= "Mimic" then
		return {}
	end
	local ids = {}
	for _, id in mimicUserIds(round) do
		if id ~= participant.userId then
			table.insert(ids, id)
		end
	end
	return ids
end

function RoleService.Init()
	revealRemote = Net.event(Net.Names.RoleReveal)
	privateStateRemote = Net.event(Net.Names.PrivateState)

	PlayerRegistry.ClientReady:Connect(function(player: Player)
		RoleService.sendPrivateState(player)
	end)
end

function RoleService.assign(round: MatchState.Round, extraMimics: number?)
	local candidates: { RoleAssignment.Candidate } = {}
	for _, participant in round.roster do
		table.insert(candidates, {
			id = participant.userId,
			weight = RoleAssignment.weightFor(history[participant.userId], GameConfig.Roles.Weights),
		})
	end

	local count = RoleAssignment.mimicCount(#candidates, GameConfig.Roles.Brackets, extraMimics)
	local roles = RoleAssignment.assign(candidates, count, rng)

	local survivors = 0
	for _, participant in round.roster do
		participant.role = roles[participant.userId] or "Survivor"
		if participant.role == "Survivor" then
			survivors += 1
		end
	end
	round.mimicCount = count
	round.startingSurvivors = survivors
end

function RoleService.sendReveal(round: MatchState.Round)
	for _, participant in round.roster do
		if participant.player.Parent == Players then
			local payload: Net.RoleRevealPayload = {
				roundId = round.id,
				role = participant.role,
				teammates = teammatesFor(round, participant),
				mimicCount = round.mimicCount,
				playerCount = #round.roster,
			}
			revealRemote:FireClient(participant.player, payload)
		end
	end
end

function RoleService.sendPrivateState(player: Player)
	if player.Parent ~= Players then
		return
	end
	local round = MatchState.getRound()
	local participant = MatchState.getParticipant(player)
	local payload: Net.PrivateStatePayload = {
		roundId = if round then round.id else 0,
		role = if participant then participant.role else nil,
		teammates = if round and participant then teammatesFor(round, participant) else {},
	}
	privateStateRemote:FireClient(player, payload)
end

function RoleService.clearPrivateState(players: { Player })
	for _, player in players do
		if player.Parent == Players then
			privateStateRemote:FireClient(player, { roundId = 0, role = nil, teammates = {} })
		end
	end
end

--[[
	Used only before the Active phase. Returns the promoted participant, or nil
	when there are not enough Survivors left to make the round meaningful.
]]
function RoleService.promoteReplacement(round: MatchState.Round): MatchState.Participant?
	local pool = MatchState.getActiveByRole("Survivor")
	if #pool < 2 then
		return nil
	end
	local chosen = pool[random:NextInteger(1, #pool)]
	chosen.role = "Mimic"
	round.startingSurvivors -= 1

	local payload: Net.RoleRevealPayload = {
		roundId = round.id,
		role = "Mimic",
		teammates = teammatesFor(round, chosen),
		mimicCount = round.mimicCount,
		playerCount = #round.roster,
	}
	revealRemote:FireClient(chosen.player, payload)
	return chosen
end

function RoleService.commitHistory(round: MatchState.Round)
	for _, participant in round.roster do
		history[participant.userId] =
			RoleAssignment.nextHistory(history[participant.userId], participant.role)
	end
end

return RoleService
