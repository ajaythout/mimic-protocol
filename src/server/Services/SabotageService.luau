--!strict
--[[
	SabotageService
	Mimic sabotage, requested with RequestSabotage(kind). Intent only: the
	server works out the room, door or generator from where the Mimic stands.

	  Lights      the Mimic's room flickers and goes dark for a while
	  Lockdown    the nearest doorway (within Range) slams shut for a while
	  FalseAlert  a fake "<survivor> is no longer responding" banner; the tell
	              is that the public operatives count does not drop
	  Generator   knocks progress back on a damaged, still-offline generator
	              the Mimic stands at
	  Cameras     the security camera feed goes dark for a while

	Validation: active Mimic, hostile phase, rate limit, known kind, kind off
	cooldown, and a valid target for the kind. Cooldowns are per kind and
	shared by every Mimic (the facility system needs time to recover), and are
	claimed before the effect runs. Every Mimic hears about cooldown changes
	through AbilityState (ability "Sabotage", detail = kind); nobody else does.

	Each effect comes with a world tell from FacilityService or GeneratorService
	and, for the louder ones, a facility-wide banner.
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
local FacilityService = require(script.Parent.FacilityService)
local GeneratorService = require(script.Parent.GeneratorService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local SabotageService = {}

local SABOTAGE = Net.Abilities.Sabotage
local SOUND_SPARK = "rbxasset://sounds/electronicpingshort.wav"

local limiter = RateLimiter.new(
	GameConfig.RateLimits.RequestSabotage.Capacity,
	GameConfig.RateLimits.RequestSabotage.RefillPerSecond
)
local readyAt: { [string]: number } = {}
local abilityRemote: RemoteEvent
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function settings(kind: string): { Cooldown: number }
	return (GameConfig.Sabotage :: any)[kind]
end

local function send(player: Player, kind: string, result: string?)
	if player.Parent ~= Players then
		return
	end
	local payload: Net.AbilityStatePayload = {
		ability = SABOTAGE,
		readyAt = readyAt[kind] or 0,
		cooldown = settings(kind).Cooldown,
		result = result,
		detail = kind,
	}
	abilityRemote:FireClient(player, payload)
end

-- Cooldowns are team-wide, so every Mimic's panel updates together.
local function broadcastKind(kind: string)
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		send(mimic.player, kind, nil)
	end
end

-- Each resolver checks the target without side effects and returns the
-- action to run once the cooldown is claimed, or nil if there is no target.
type Action = () -> ()
local resolvers: { [string]: (player: Player, root: BasePart) -> Action? } = {}

resolvers.Lights = function(_, root)
	local zone = FacilityService.roomAt(root.Position)
	if not zone or FacilityService.isBlackedOut(zone) then
		return nil
	end
	return function()
		FacilityService.blackout(zone, GameConfig.Sabotage.Lights.Duration)
	end
end

resolvers.Lockdown = function(_, root)
	local door = FacilityService.nearestDoor(root.Position, GameConfig.Sabotage.Lockdown.Range)
	if not door then
		return nil
	end
	return function()
		FacilityService.sealDoor(door, GameConfig.Sabotage.Lockdown.Duration)
		local room = door:GetAttribute("Room")
		Announcer.all(
			"LOCKDOWN",
			`A doorway in {if type(room) == "string" then room else "the facility"} has sealed itself.`,
			"Warning",
			4
		)
	end
end

resolvers.FalseAlert = function(player)
	local candidates = {}
	for _, survivor in MatchState.getActiveByRole("Survivor") do
		if survivor.player ~= player then
			table.insert(candidates, survivor)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local victim = candidates[random:NextInteger(1, #candidates)]
	return function()
		-- Word for word the real elimination banner. Only the operatives count
		-- (which does not drop) gives it away.
		Announcer.all(`{victim.name} is no longer responding`, nil, "Warning", 4)
	end
end

resolvers.Generator = function(_, root)
	local best: GeneratorService.Generator? = nil
	local bestDistance = GameConfig.Sabotage.Generator.Range
	for _, generator in GeneratorService.getGenerators() do
		local distance = (generator.panel.Position - root.Position).Magnitude
		if not generator.online and generator.progress > 0 and distance <= bestDistance then
			best = generator
			bestDistance = distance
		end
	end
	local target = best
	if not target then
		return nil
	end
	return function()
		GeneratorService.setback(target.model, GameConfig.Sabotage.Generator.Setback)
		FacilityService.cue(target.panel, SOUND_SPARK, 1)
		Announcer.all(`{target.name} FAULT`, "Something set the repairs back.", "Warning", 4)
	end
end

resolvers.Cameras = function()
	if not FacilityService.camerasOnline() then
		return nil
	end
	return function()
		FacilityService.camerasOffline(GameConfig.Sabotage.Cameras.Duration)
		Announcer.all("CAMERAS OFFLINE", "The security feed lost its signal.", "Warning", 4)
	end
end

local function onRequest(player: Player, kind: unknown)
	if not limiter:consume(player) then
		return
	end
	if type(kind) ~= "string" or resolvers[kind] == nil then
		return
	end
	local participant = MatchState.getActiveParticipant(player)
	if not participant or participant.role ~= "Mimic" then
		return
	end
	if not Phases.HostileAbilities[MatchState.getPhase()] then
		send(player, kind, "Locked")
		return
	end
	if CharacterService.isStunned(player) then
		send(player, kind, "Stunned")
		return
	end
	if now() < (readyAt[kind] or 0) then
		send(player, kind, "Cooldown")
		return
	end
	local root = CharacterService.getRoot(player)
	if not root then
		return
	end
	local action = resolvers[kind](player, root)
	if not action then
		send(player, kind, "NoTarget")
		return
	end
	-- Claim the cooldown before the effect runs.
	readyAt[kind] = now() + settings(kind).Cooldown
	action()
	send(player, kind, "Done")
	broadcastKind(kind)
end

function SabotageService.Init()
	abilityRemote = Net.event(Net.Names.AbilityState)
	Net.event(Net.Names.RequestSabotage).OnServerEvent:Connect(onRequest)
	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		limiter:forget(player)
	end)
end

-- Abilities wake up: every kind waits InitialDelay, so the round has a calm start.
function SabotageService.primeCooldowns()
	local start = now() + GameConfig.Sabotage.InitialDelay
	for kind in resolvers do
		readyAt[kind] = start
		broadcastKind(kind)
	end
end

function SabotageService.reset()
	table.clear(readyAt)
	FacilityService.reset()
end

return SabotageService
