--!strict
--[[
	EliminationService
	Everything that removes a participant from play.

	ASSIMILATE (Mimic basic attack)
	  Client sends RequestStrike with NO arguments (intent only). The server:
	    1. rate-limits the request
	    2. checks the sender is an active Mimic in a hostile phase
	    3. checks the server-side cooldown (claimed before any work)
	    4. resolves the target itself: nearest active Survivor within range,
	       roughly in front, with clear line of sight (walls/props block)
	  The cooldown is only consumed on a hit; misses are answered with
	  AbilityState result "NoTarget" so the HUD can give feedback.

	DEATH HANDLING
	  Any death of an active participant while players are in the facility
	  (falling, resetting, future hazards) eliminates them. Mimics who die
	  this way count as neutralized.

	Effects are broadcast as position-only cues; the attacker is never named.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local RateLimiter = require(Shared.Util.RateLimiter)

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

export type Cause = "Assimilated" | "Hazard"

local EliminationService = {}

local STRIKE = "Assimilate"

local strikeLimiter = RateLimiter.new(
	GameConfig.RateLimits.RequestStrike.Capacity,
	GameConfig.RateLimits.RequestStrike.RefillPerSecond
)
local readyAt: { [Player]: number } = {}

local abilityRemote: RemoteEvent
local fxRemote: RemoteEvent

local function sendAbilityState(player: Player, result: string?)
	if player.Parent ~= Players then
		return
	end
	local payload: Net.AbilityStatePayload = {
		ability = STRIKE,
		readyAt = readyAt[player] or 0,
		cooldown = GameConfig.Strike.Cooldown,
		result = result,
	}
	abilityRemote:FireClient(player, payload)
end

local function characterParts(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterParts()
	params.IgnoreWater = true
	local result = Workspace:Raycast(from, to - from, params)
	return result == nil
end

local function findStrikeTarget(attacker: Player): MatchState.Participant?
	local root = CharacterService.getRoot(attacker)
	if not root then
		return nil
	end
	local origin = root.Position
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zAxis

	local best: MatchState.Participant? = nil
	local bestDistance = GameConfig.Strike.Range

	for _, candidate in MatchState.getActiveByRole("Survivor") do
		local targetRoot = CharacterService.getRoot(candidate.player)
		if targetRoot then
			local offset = targetRoot.Position - origin
			local distance = offset.Magnitude
			if distance <= bestDistance then
				local flat = offset * Vector3.new(1, 0, 1)
				local facingOk = distance <= GameConfig.Strike.CloseRange
					or (flat.Magnitude > 1e-3 and facing:Dot(flat.Unit) >= GameConfig.Strike.FacingDot)
				if facingOk and hasLineOfSight(origin, targetRoot.Position) then
					best = candidate
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function onStrikeRequest(player: Player)
	if not strikeLimiter:consume(player) then
		return
	end
	local attacker = MatchState.getActiveParticipant(player)
	if not attacker or attacker.role ~= "Mimic" then
		return
	end
	if not Phases.HostileAbilities[MatchState.getPhase()] then
		sendAbilityState(player, "Locked")
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < (readyAt[player] or 0) then
		sendAbilityState(player, "Cooldown")
		return
	end

	local target = findStrikeTarget(player)
	if not target then
		sendAbilityState(player, "NoTarget")
		return
	end

	-- Claim the cooldown before anything that could yield.
	readyAt[player] = now + GameConfig.Strike.Cooldown
	EliminationService.eliminate(target, "Assimilated", attacker)
	sendAbilityState(player, "Hit")
end

local function onCharacterDied(player: Player, character: Model)
	local participant = MatchState.getActiveParticipant(player)
	if not participant then
		return
	end
	if not Phases.InFacility[MatchState.getPhase()] then
		return
	end
	if PlayerRegistry.getStatus(player) ~= "Alive" then
		return
	end
	EliminationService.eliminate(participant, "Hazard", nil, character)
end

function EliminationService.Init()
	abilityRemote = Net.event(Net.Names.AbilityState)
	fxRemote = Net.event(Net.Names.EliminationFx)

	CharacterService.setDeathHandler(onCharacterDied)
	Net.event(Net.Names.RequestStrike).OnServerEvent:Connect(onStrikeRequest)

	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		strikeLimiter:forget(player)
		readyAt[player] = nil
	end)
end

--[[
	Removes a participant from the round. Synchronous (never yields) so it is
	safe to call from the CharacterService death hook.
]]
function EliminationService.eliminate(
	participant: MatchState.Participant,
	cause: Cause,
	attacker: MatchState.Participant?,
	deadCharacter: Model?
): boolean
	if participant.fate ~= "Active" then
		return false
	end

	local player = participant.player
	local character = deadCharacter or player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil

	-- Credit the attacker before the fate change: FateChanged can end the
	-- round and build the results immediately.
	if attacker then
		attacker.eliminations += 1
	end
	MatchState.setFate(participant, "Eliminated")

	if position then
		local payload: Net.EliminationFxPayload = { position = position, victimUserId = participant.userId }
		fxRemote:FireAllClients(payload)
	end

	Announcer.all(`{participant.name} is no longer responding`, nil, "Warning", 4)
	if cause == "Assimilated" then
		Announcer.to(player, "YOU WERE ASSIMILATED", "Spectating from the Deployment Bay.", "Critical", 5)
	else
		Announcer.to(player, "SIGNAL LOST", "You were removed from the round.", "Critical", 5)
	end

	-- Kill after the status change so the respawn policy sends them to the bay.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
	return true
end

-- Sets every active Mimic's cooldown to `seconds` from now (phase start).
function EliminationService.primeCooldowns(seconds: number)
	local now = Workspace:GetServerTimeNow()
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		readyAt[mimic.player] = now + seconds
		sendAbilityState(mimic.player, nil)
	end
end

function EliminationService.reset()
	table.clear(readyAt)
end

return EliminationService
