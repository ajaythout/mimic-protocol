--!strict
--[[
	WinConditions
	Pure evaluation of a round snapshot. The server's RoundService builds a
	Snapshot from authoritative state after every event that can change the
	outcome (elimination, extraction, disconnect, timer) and calls evaluate().

	Rules (first match wins):
	  1. Nobody left in the round at all          -> None     ("Abandoned")
	  2. No active Mimics remain                  -> Survivors ("MimicsGone")
	  3. No survivors left inside the facility:
	       enough extracted                       -> Survivors ("Extracted")
	       otherwise                              -> Mimics    ("Overrun")
	  4. Too few survivors left to ever reach the
	     extraction requirement                   -> Mimics    ("Outnumbered")
	  5. Extraction window closed:
	       enough extracted                       -> Survivors ("Extracted")
	       otherwise                              -> Mimics    ("ExtractionFailed")
	  6. Otherwise the round continues            -> nil
]]

export type Winner = "Survivors" | "Mimics" | "None"

export type Reason = "Abandoned" | "MimicsGone" | "Extracted" | "Overrun" | "Outnumbered" | "ExtractionFailed"

export type Snapshot = {
	mimicsActive: number, -- connected, not eliminated
	survivorsActive: number, -- alive inside the facility
	survivorsExtracted: number,
	survivorsEliminated: number,
	survivorsDisconnected: number, -- left the server while still active
	startingSurvivors: number,
	extractionClosed: boolean,
}

export type Rules = {
	RequiredFraction: number,
	MinRequired: number,
}

export type Outcome = {
	winner: Winner,
	reason: Reason,
	required: number,
}

local WinConditions = {}

WinConditions.ReasonText = {
	Abandoned = "All personnel lost contact. The round was abandoned.",
	MimicsGone = "Every Mimic has been neutralized or has fled the facility.",
	Extracted = "Enough survivors reached the extraction lift.",
	Overrun = "No survivors remain inside the facility.",
	Outnumbered = "Too few survivors remain to complete extraction.",
	ExtractionFailed = "The extraction window closed before enough survivors escaped.",
} :: { [string]: string }

--[[
	Survivors who disconnect while still active leave the pool, so one player
	quitting never makes the objective mathematically impossible on its own.
]]
function WinConditions.requiredExtractions(snapshot: Snapshot, rules: Rules): number
	local pool = math.max(0, snapshot.startingSurvivors - snapshot.survivorsDisconnected)
	if pool == 0 then
		return 0
	end
	local required = math.max(rules.MinRequired, math.ceil(pool * rules.RequiredFraction - 1e-9))
	return math.min(required, pool)
end

local function outcome(winner: Winner, reason: Reason, required: number): Outcome
	return { winner = winner, reason = reason, required = required }
end

function WinConditions.evaluate(snapshot: Snapshot, rules: Rules): Outcome?
	local required = WinConditions.requiredExtractions(snapshot, rules)
	local anySurvivorPresence = snapshot.survivorsActive
		+ snapshot.survivorsExtracted
		+ snapshot.survivorsEliminated

	if snapshot.mimicsActive <= 0 and anySurvivorPresence <= 0 then
		return outcome("None", "Abandoned", required)
	end

	if snapshot.mimicsActive <= 0 then
		return outcome("Survivors", "MimicsGone", required)
	end

	if snapshot.survivorsActive <= 0 then
		if required > 0 and snapshot.survivorsExtracted >= required then
			return outcome("Survivors", "Extracted", required)
		end
		if snapshot.survivorsExtracted + snapshot.survivorsEliminated <= 0 then
			-- Every survivor disconnected without being eliminated.
			return outcome("None", "Abandoned", required)
		end
		return outcome("Mimics", "Overrun", required)
	end

	if snapshot.survivorsExtracted + snapshot.survivorsActive < required then
		return outcome("Mimics", "Outnumbered", required)
	end

	if snapshot.extractionClosed then
		if snapshot.survivorsExtracted >= required then
			return outcome("Survivors", "Extracted", required)
		end
		return outcome("Mimics", "ExtractionFailed", required)
	end

	return nil
end

return WinConditions
