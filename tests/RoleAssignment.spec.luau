--!strict
local T = require("./lib/T")
local RoleAssignment = require("../src/shared/Modules/RoleAssignment")

local BRACKETS = {
	{ MinPlayers = 2, MaxPlayers = 5, Mimics = 1 },
	{ MinPlayers = 6, MaxPlayers = 11, Mimics = 2 },
	{ MinPlayers = 12, MaxPlayers = 99, Mimics = 3 },
}
local WEIGHTS = { Base = 1, WasMimicLastRound = 0.35, BonusPerSurvivorRound = 0.2, Max = 2.5 }

-- Deterministic LCG so the suite is reproducible.
local function makeRng(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function candidates(n: number, weight: number?): { RoleAssignment.Candidate }
	local list = {}
	for i = 1, n do
		table.insert(list, { id = i, weight = weight or 1 })
	end
	return list
end

T.describe("RoleAssignment.mimicCount", function()
	T.it("matches the design table", function()
		local expected = {
			[2] = 1,
			[3] = 1,
			[4] = 1,
			[5] = 1,
			[6] = 2,
			[7] = 2,
			[8] = 2,
			[9] = 2,
			[10] = 2,
			[11] = 2,
			[12] = 3,
		}
		for players, mimics in expected do
			T.expectEq(RoleAssignment.mimicCount(players, BRACKETS), mimics, `{players} players`)
		end
	end)
	T.it("returns 0 when unplayable", function()
		T.expectEq(RoleAssignment.mimicCount(1, BRACKETS), 0)
		T.expectEq(RoleAssignment.mimicCount(0, BRACKETS), 0)
	end)
	T.it("adds mutator mimics but keeps survivors in the majority", function()
		T.expectEq(RoleAssignment.mimicCount(8, BRACKETS, 1), 3)
		T.expectEq(RoleAssignment.mimicCount(4, BRACKETS, 1), 1) -- 2v2 would not be a majority
		T.expectEq(RoleAssignment.mimicCount(6, BRACKETS, 5), 2)
	end)
end)

T.describe("RoleAssignment.assign", function()
	T.it("assigns exactly the requested number of mimics with no duplicates", function()
		local rng = makeRng(7)
		for n = 2, 12 do
			for _ = 1, 50 do
				local count = RoleAssignment.mimicCount(n, BRACKETS)
				local roles = RoleAssignment.assign(candidates(n), count, rng)
				local mimics, total = 0, 0
				for _, role in roles do
					total += 1
					if role == "Mimic" then
						mimics += 1
					end
				end
				T.expectEq(total, n, "every player gets a role")
				T.expectEq(mimics, count, `mimics for {n}`)
			end
		end
	end)

	T.it("is fair with equal weights (chi-square style spread check)", function()
		local rng = makeRng(42)
		local n, trials = 8, 20000
		local hits = table.create(n, 0)
		for _ = 1, trials do
			for _, id in RoleAssignment.pickMimics(candidates(n), 2, rng) do
				hits[id] += 1
			end
		end
		local expected = trials * 2 / n
		for id = 1, n do
			T.expectNear(hits[id], expected, expected * 0.06, `player {id} selection count`)
		end
	end)

	T.it("respects weights (repeat mimic is rarer)", function()
		local rng = makeRng(99)
		local list = candidates(6)
		list[1].weight = WEIGHTS.WasMimicLastRound
		local first, trials = 0, 20000
		for _ = 1, trials do
			for _, id in RoleAssignment.pickMimics(list, 1, rng) do
				if id == 1 then
					first += 1
				end
			end
		end
		-- Expected share: 0.35 / 5.35 ≈ 6.5%
		T.expectNear(first / trials, 0.35 / 5.35, 0.01, "weighted share")
	end)

	T.it("still picks when every weight is zero", function()
		local picked = RoleAssignment.pickMimics(candidates(3, 0), 1, makeRng(3))
		T.expectEq(#picked, 1)
	end)
end)

T.describe("RoleAssignment.weightFor / nextHistory", function()
	T.it("defaults new players to base weight", function()
		T.expectEq(RoleAssignment.weightFor(nil, WEIGHTS), 1)
	end)
	T.it("penalises last-round mimics and caps pity", function()
		T.expectEq(
			RoleAssignment.weightFor({ wasMimicLastRound = true, survivorRoundsSinceMimic = 0 }, WEIGHTS),
			0.35
		)
		T.expectNear(
			RoleAssignment.weightFor({ wasMimicLastRound = false, survivorRoundsSinceMimic = 3 }, WEIGHTS),
			1.6,
			1e-9
		)
		T.expectEq(
			RoleAssignment.weightFor({ wasMimicLastRound = false, survivorRoundsSinceMimic = 50 }, WEIGHTS),
			2.5
		)
	end)
	T.it("updates history", function()
		local h = RoleAssignment.nextHistory(nil, "Survivor")
		T.expectEq(h.survivorRoundsSinceMimic, 1)
		h = RoleAssignment.nextHistory(h, "Survivor")
		T.expectEq(h.survivorRoundsSinceMimic, 2)
		h = RoleAssignment.nextHistory(h, "Mimic")
		T.expectTrue(h.wasMimicLastRound)
		T.expectEq(h.survivorRoundsSinceMimic, 0)
	end)
end)
