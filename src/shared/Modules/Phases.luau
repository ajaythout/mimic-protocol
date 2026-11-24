--!strict
--[[
	Phases
	Canonical names and metadata for the round state machine. Pure data, safe
	to require from server, client, and Lune tests.

	Flow: Waiting -> Intermission -> RoleReveal -> Deployment -> Active
	      -> Escalation -> Extraction -> Results -> (Intermission | Waiting)
]]

export type Phase =
	"Waiting"
	| "Intermission"
	| "RoleReveal"
	| "Deployment"
	| "Active"
	| "Escalation"
	| "Extraction"
	| "Results"

local Phases = {
	Waiting = "Waiting" :: Phase,
	Intermission = "Intermission" :: Phase,
	RoleReveal = "RoleReveal" :: Phase,
	Deployment = "Deployment" :: Phase,
	Active = "Active" :: Phase,
	Escalation = "Escalation" :: Phase,
	Extraction = "Extraction" :: Phase,
	Results = "Results" :: Phase,
}

-- Ordered sequence of a full round (Waiting/Intermission sit outside it).
Phases.RoundSequence = {
	Phases.RoleReveal,
	Phases.Deployment,
	Phases.Active,
	Phases.Escalation,
	Phases.Extraction,
} :: { Phase }

-- Phases in which a round is in progress (players hold roles).
Phases.InRound = {
	RoleReveal = true,
	Deployment = true,
	Active = true,
	Escalation = true,
	Extraction = true,
} :: { [string]: boolean }

-- Phases in which players are physically inside the facility.
Phases.InFacility = {
	Deployment = true,
	Active = true,
	Escalation = true,
	Extraction = true,
} :: { [string]: boolean }

-- Phases in which Mimic hostile abilities are enabled.
Phases.HostileAbilities = {
	Active = true,
	Escalation = true,
	Extraction = true,
} :: { [string]: boolean }

-- Player-facing labels.
Phases.DisplayName = {
	Waiting = "AWAITING PERSONNEL",
	Intermission = "BRIEFING",
	RoleReveal = "ASSIGNMENT",
	Deployment = "DEPLOYMENT",
	Active = "INVESTIGATION",
	Escalation = "ESCALATION",
	Extraction = "EXTRACTION",
	Results = "DEBRIEF",
} :: { [string]: string }

function Phases.displayName(phase: string): string
	return Phases.DisplayName[phase] or phase
end

function Phases.isPhase(value: unknown): boolean
	return type(value) == "string" and Phases.DisplayName[value] ~= nil
end

return Phases
