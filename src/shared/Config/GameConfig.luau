--!strict
--[[
	GameConfig
	Central tuning values shared by server and client. Server code is the only
	authority that acts on these numbers; clients read them for presentation
	(countdowns, cooldown rings, labels).

	Changing a value here is the supported way to rebalance a round.
]]

local GameConfig = {}

-- Player counts -------------------------------------------------------------
GameConfig.Players = {
	MinPublic = 4, -- minimum ready players to start a public match
	MinPrivateServer = 3, -- private servers can play with a smaller group
	MinStudio = 2, -- Studio "Server & Clients" testing with 2+ clients
	MaxPerRound = 12,
}

-- Phase durations (seconds) -------------------------------------------------
GameConfig.Timings = {
	Intermission = 20,
	RoleReveal = 7,
	Deployment = 20,
	Active = 210,
	Escalation = 90,
	Extraction = 40,
	Results = 12,
}

-- Developer convenience: when true AND running in Studio, every phase
-- duration is multiplied by DevTimingScale. Has no effect on live servers.
GameConfig.Dev = {
	FastRoundsInStudio = false,
	DevTimingScale = 0.25,
}

-- Role distribution ---------------------------------------------------------
-- Brackets are inclusive. The first bracket whose range contains the player
-- count wins. RoleAssignment also guarantees Mimics < Survivors.
GameConfig.Roles = {
	Brackets = {
		{ MinPlayers = 2, MaxPlayers = 5, Mimics = 1 },
		{ MinPlayers = 6, MaxPlayers = 11, Mimics = 2 },
		{ MinPlayers = 12, MaxPlayers = 99, Mimics = 3 },
	},
	-- Selection weighting (session memory only, never purchasable):
	-- a player who was a Mimic last round is much less likely to repeat,
	-- and every round spent as a Survivor slowly raises the odds.
	Weights = {
		Base = 1,
		WasMimicLastRound = 0.35,
		BonusPerSurvivorRound = 0.2,
		Max = 2.5,
	},
}

-- Win conditions ------------------------------------------------------------
GameConfig.Extraction = {
	-- Fraction of the survivor pool that must reach the lift for a
	-- Survivor victory (survivors who disconnect leave the pool).
	RequiredFraction = 0.33,
	MinRequired = 1,
	ZoneCheckInterval = 0.25,
}

-- Mimic basic attack ("Assimilate") ------------------------------------------
GameConfig.Strike = {
	Cooldown = 22,
	-- Applied to every Mimic when the Active phase begins, so Survivors get a
	-- short window to spread out before the first possible attack.
	InitialCooldown = 15,
	Range = 8,
	-- Dot product between the Mimic's facing and the direction to the target.
	FacingDot = 0.2,
	-- Targets closer than this are valid regardless of facing.
	CloseRange = 3.5,
}

-- Generators: the power objective that gates the extraction lift -----------
GameConfig.Generators = {
	-- Online generators needed before the lift can open (capped at however
	-- many the map has; 0 means the lift is always powered).
	Required = 2,
	-- One survivor, from empty to online.
	RepairSeconds = 30,
	-- Extra hands speed a repair up, to at most this many at once.
	MaxRepairers = 2,
	-- Prompt distance; repairers who step further away stop.
	Range = 8,
	TickInterval = 0.25,
}

-- Mimic ability: Object Shift (disguise as a facility prop) -------------------
GameConfig.ObjectShift = {
	-- Max distance from the Mimic's root to the prop being copied.
	Range = 12,
	-- Starts when the disguise ends, however it ends.
	Cooldown = 10,
	-- The disguise drops on its own after this long.
	MaxDuration = 60,
	WalkSpeed = 7,
	JumpHeight = 0,
}

-- Mimic ability: Identity Theft (take another player's look and name) --------
GameConfig.IdentityTheft = {
	-- Target selection, same rules as Strike.
	Range = 10,
	FacingDot = 0.2,
	CloseRange = 3.5,
	Duration = 45,
	-- Counted from activation.
	Cooldown = 60,
}

-- Mimic sabotage ------------------------------------------------------------
-- Cooldowns are per kind and shared by every Mimic.
GameConfig.Sabotage = {
	-- Seconds into the Active phase before anything can be sabotaged.
	InitialDelay = 20,
	Lights = { Cooldown = 60, Duration = 20 },
	Lockdown = { Cooldown = 45, Duration = 12, Range = 30 },
	FalseAlert = { Cooldown = 50 },
	-- Setback is the fraction of a full repair that is lost.
	Generator = { Cooldown = 40, Range = 8, Setback = 0.25 },
	Cameras = { Cooldown = 60, Duration = 30 },
}

-- Survivor counterplay: the Containment Scanner ------------------------------
GameConfig.Scanner = {
	Charges = 1, -- per survivor per round
	-- Target selection (same rules as Strike, but shorter reach).
	Range = 6,
	FacingDot = 0.3,
	CloseRange = 2.5,
	-- A Mimic hit: highlighted for everyone, then briefly frozen.
	ExposeSeconds = 6,
	StunSeconds = 3,
	-- A crewmate hit shortens the team's extraction window by this much...
	FalsePositivePenalty = 10,
	-- ...but never below this fraction of the normal window.
	MinExtractionFraction = 0.25,
}

-- Security camera terminal (Security Office) --------------------------------
GameConfig.Cameras = {
	-- Prompt distance; viewers who step further away leave the feed.
	Range = 8,
}

-- Characters ----------------------------------------------------------------
GameConfig.Characters = {
	WalkSpeed = 16,
	JumpHeight = 6,
	LobbyRespawnDelay = 3,
	EliminatedReturnDelay = 4,
	NameDisplayDistance = 45,
}

-- Remote request budgets (token buckets) --------------------------------------
GameConfig.RateLimits = {
	Default = { Capacity = 6, RefillPerSecond = 2 },
	SetAfk = { Capacity = 3, RefillPerSecond = 0.5 },
	RequestStrike = { Capacity = 4, RefillPerSecond = 2 },
	RequestAbility = { Capacity = 4, RefillPerSecond = 1.5 },
	RequestSabotage = { Capacity = 3, RefillPerSecond = 1 },
}

return GameConfig
