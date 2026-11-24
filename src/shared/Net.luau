--!strict
--[[
	Net
	Single access point for the authored RemoteEvents in
	ReplicatedStorage.Remotes and the replicated RoundState folder.

	Protocol (direction · payload · authority):
	  ClientReady    C->S  ()                       client UI is loaded
	  SetAfk         C->S  (afk: boolean)           readiness toggle in Standby
	  RequestStrike  C->S  ()                       intent only; server picks target
	  RequestAbility C->S  (ability, target?)       Mimic/Survivor abilities; target is
	                                              a hint the server re-validates
	  RequestSabotage C->S (kind)                   intent only; server picks the room,
	                                              door or generator
	  PrivateState   S->C  PrivateStatePayload      the receiving player's role
	  RoleReveal     S->C  RoleRevealPayload        start-of-round reveal
	  AbilityState   S->C  AbilityStatePayload      server-confirmed cooldowns
	  Announcement   S->C  AnnouncementPayload      banners (targeted or broadcast)
	  EliminationFx  S->C  EliminationFxPayload     position-only effect cue
	  RoundResult    S->C  RoundResultPayload       winner + role reveal roster

	Public round state lives in attributes on ReplicatedStorage.RoundState
	(Phase, PhaseEndsAt, RoundId, ...). Private facts (roles) are only ever sent
	with FireClient to the player they belong to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type RoleName = "Survivor" | "Mimic"

export type PrivateStatePayload = {
	roundId: number,
	role: RoleName?,
	teammates: { number }, -- UserIds of fellow Mimics (Mimics only)
}

export type RoleRevealPayload = {
	roundId: number,
	role: RoleName,
	teammates: { number },
	mimicCount: number,
	playerCount: number,
}

export type AbilityStatePayload = {
	ability: string, -- one of Net.Abilities
	readyAt: number, -- Workspace:GetServerTimeNow() timestamp
	cooldown: number,
	result: string?, -- "Hit" | "NoTarget" | "Locked" | "Cooldown" | "Shifted" | "Reverted" | nil
	activeUntil: number?, -- set while a lasting effect (a disguise) is running
	detail: string?, -- display text for the result, e.g. the prop's name
}

export type AnnouncementPayload = {
	title: string,
	body: string?,
	severity: "Info" | "Warning" | "Critical" | "Success",
	duration: number?,
}

export type EliminationFxPayload = {
	position: Vector3,
	victimUserId: number,
}

export type RosterEntry = {
	userId: number,
	name: string,
	role: RoleName,
	fate: "Extracted" | "Eliminated" | "Survived" | "Disconnected" | "Active",
	eliminations: number,
}

export type RoundResultPayload = {
	roundId: number,
	winner: "Survivors" | "Mimics" | "None",
	reason: string,
	reasonText: string,
	extracted: number,
	required: number,
	durationSeconds: number,
	roster: { RosterEntry },
}

local Net = {}

Net.Names = {
	ClientReady = "ClientReady",
	SetAfk = "SetAfk",
	RequestStrike = "RequestStrike",
	RequestAbility = "RequestAbility",
	RequestSabotage = "RequestSabotage",
	PrivateState = "PrivateState",
	RoleReveal = "RoleReveal",
	AbilityState = "AbilityState",
	Announcement = "Announcement",
	EliminationFx = "EliminationFx",
	RoundResult = "RoundResult",
}

-- Ability ids used by RequestAbility and AbilityState.
Net.Abilities = {
	Assimilate = "Assimilate",
	ObjectShift = "ObjectShift",
	IdentityTheft = "IdentityTheft",
	Sabotage = "Sabotage", -- AbilityState.detail names the kind
}

-- Sabotage kinds accepted by RequestSabotage (see SabotageService).
Net.SabotageKinds = { "Lights", "Lockdown", "FalseAlert", "Generator", "Cameras" }

local remotesFolder: Folder? = nil

local function getFolder(): Folder
	if remotesFolder == nil then
		remotesFolder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return remotesFolder :: Folder
end

function Net.event(name: string): RemoteEvent
	assert(Net.Names[name] ~= nil, `Unknown remote '{name}'`)
	local remote = getFolder():WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), `Remote '{name}' is missing from ReplicatedStorage.Remotes`)
	return remote
end

function Net.roundState(): Folder
	return ReplicatedStorage:WaitForChild("RoundState") :: Folder
end

return Net
