--!strict
--[[
	RoleAssignment
	Pure, dependency-free role selection. The server calls this; it never runs
	on clients with authority. Kept pure so it can be unit-tested in Lune.

	- mimicCount(playerCount, brackets, extra) -> number of Mimics
	- weightFor(history, weights)              -> selection weight for a player
	- pickMimics(candidates, count, rng)       -> list of chosen ids
	- assign(candidates, count, rng)           -> { [id]: Role }

	`rng` is a function returning a float in [0, 1). On Roblox pass
	`function() return random:NextNumber() end` with a Random.new() object.
]]

export type Role = "Survivor" | "Mimic"

export type Bracket = {
	MinPlayers: number,
	MaxPlayers: number,
	Mimics: number,
}

export type Weights = {
	Base: number,
	WasMimicLastRound: number,
	BonusPerSurvivorRound: number,
	Max: number,
}

export type History = {
	wasMimicLastRound: boolean,
	survivorRoundsSinceMimic: number,
}

export type Candidate = {
	id: number,
	weight: number,
}

local RoleAssignment = {}

RoleAssignment.Survivor = "Survivor" :: Role
RoleAssignment.Mimic = "Mimic" :: Role

--[[
	Number of Mimics for a lobby size. `extraMimics` lets mutators (e.g.
	DOUBLE TROUBLE) add Mimics; the result is always clamped so that Survivors
	strictly outnumber Mimics and at least one Mimic exists when playable.
]]
function RoleAssignment.mimicCount(playerCount: number, brackets: { Bracket }, extraMimics: number?): number
	if playerCount < 2 then
		return 0
	end

	local count = 1
	for _, bracket in brackets do
		if playerCount >= bracket.MinPlayers and playerCount <= bracket.MaxPlayers then
			count = bracket.Mimics
			break
		end
	end

	count += extraMimics or 0

	-- Survivors must strictly outnumber Mimics: mimics <= ceil(n / 2) - 1.
	local maxAllowed = math.max(1, math.ceil(playerCount / 2) - 1)
	return math.clamp(count, 1, maxAllowed)
end

function RoleAssignment.weightFor(history: History?, weights: Weights): number
	if history == nil then
		return weights.Base
	end
	if history.wasMimicLastRound then
		return weights.WasMimicLastRound
	end
	local bonus = history.survivorRoundsSinceMimic * weights.BonusPerSurvivorRound
	return math.min(weights.Base + bonus, weights.Max)
end

--[[
	Weighted sampling without replacement (sequential roulette wheel).
	Candidates with non-positive or non-finite weight are treated as weight 0
	and are only picked when nobody else remains.
]]
function RoleAssignment.pickMimics(candidates: { Candidate }, count: number, rng: () -> number): { number }
	local pool: { Candidate } = table.clone(candidates)
	local chosen: { number } = {}
	count = math.min(count, #pool)

	for _ = 1, count do
		local total = 0
		for _, candidate in pool do
			local weight = candidate.weight
			if weight == weight and weight > 0 and weight < math.huge then
				total += weight
			end
		end

		local index: number
		if total <= 0 then
			index = math.floor(rng() * #pool) + 1
		else
			local roll = rng() * total
			index = #pool
			for i, candidate in pool do
				local weight = candidate.weight
				if weight == weight and weight > 0 and weight < math.huge then
					roll -= weight
					if roll < 0 then
						index = i
						break
					end
				end
			end
		end

		index = math.clamp(index, 1, #pool)
		table.insert(chosen, pool[index].id)
		table.remove(pool, index)
	end

	return chosen
end

function RoleAssignment.assign(
	candidates: { Candidate },
	mimicCount: number,
	rng: () -> number
): { [number]: Role }
	local roles: { [number]: Role } = {}
	for _, candidate in candidates do
		roles[candidate.id] = "Survivor"
	end
	for _, id in RoleAssignment.pickMimics(candidates, mimicCount, rng) do
		roles[id] = "Mimic"
	end
	return roles
end

--[[
	Returns the updated history after a round. Survivors accumulate pity;
	Mimics reset.
]]
function RoleAssignment.nextHistory(previous: History?, role: Role): History
	if role == "Mimic" then
		return { wasMimicLastRound = true, survivorRoundsSinceMimic = 0 }
	end
	local rounds = if previous then previous.survivorRoundsSinceMimic else 0
	return { wasMimicLastRound = false, survivorRoundsSinceMimic = rounds + 1 }
end

return RoleAssignment
