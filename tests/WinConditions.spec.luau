--!strict
local T = require("./lib/T")
local WinConditions = require("../src/shared/Modules/WinConditions")

local RULES = { RequiredFraction = 0.34, MinRequired = 1 }

local function snap(overrides: { [string]: any }): WinConditions.Snapshot
	local s = {
		mimicsActive = 2,
		survivorsActive = 6,
		survivorsExtracted = 0,
		survivorsEliminated = 0,
		survivorsDisconnected = 0,
		startingSurvivors = 6,
		extractionClosed = false,
	}
	for k, v in overrides do
		(s :: any)[k] = v
	end
	return s
end

T.describe("WinConditions.requiredExtractions", function()
	T.it("scales with the survivor pool", function()
		T.expectEq(WinConditions.requiredExtractions(snap({ startingSurvivors = 3 }), RULES), 2) -- ceil(1.02)
		T.expectEq(WinConditions.requiredExtractions(snap({ startingSurvivors = 6 }), RULES), 3) -- ceil(2.04)
		T.expectEq(WinConditions.requiredExtractions(snap({ startingSurvivors = 9 }), RULES), 4)
		T.expectEq(WinConditions.requiredExtractions(snap({ startingSurvivors = 1 }), RULES), 1)
	end)
	T.it("shrinks when survivors disconnect", function()
		T.expectEq(
			WinConditions.requiredExtractions(
				snap({ startingSurvivors = 6, survivorsDisconnected = 3 }),
				RULES
			),
			2
		)
		T.expectEq(
			WinConditions.requiredExtractions(
				snap({ startingSurvivors = 2, survivorsDisconnected = 2 }),
				RULES
			),
			0
		)
	end)
end)

T.describe("WinConditions.evaluate", function()
	T.it("continues a normal round", function()
		T.expectEq(WinConditions.evaluate(snap({}), RULES), nil)
	end)
	T.it("survivors win when all mimics are gone", function()
		local o = WinConditions.evaluate(snap({ mimicsActive = 0 }), RULES)
		T.expectEq(o and o.winner, "Survivors")
		T.expectEq(o and o.reason, "MimicsGone")
	end)
	T.it("mimics win when the facility is overrun", function()
		local o = WinConditions.evaluate(snap({ survivorsActive = 0, survivorsEliminated = 6 }), RULES)
		T.expectEq(o and o.winner, "Mimics")
		T.expectEq(o and o.reason, "Overrun")
	end)
	T.it("survivors win once everyone left is extracted and the quota is met", function()
		local o = WinConditions.evaluate(
			snap({ survivorsActive = 0, survivorsExtracted = 3, survivorsEliminated = 3 }),
			RULES
		)
		T.expectEq(o and o.winner, "Survivors")
		T.expectEq(o and o.reason, "Extracted")
	end)
	T.it("ends early when the quota becomes unreachable", function()
		local o = WinConditions.evaluate(snap({ survivorsActive = 2, survivorsEliminated = 4 }), RULES)
		T.expectEq(o and o.winner, "Mimics")
		T.expectEq(o and o.reason, "Outnumbered")
	end)
	T.it("does not end early while the quota is still reachable", function()
		T.expectEq(WinConditions.evaluate(snap({ survivorsActive = 3, survivorsEliminated = 3 }), RULES), nil)
		T.expectEq(
			WinConditions.evaluate(
				snap({ survivorsActive = 1, survivorsExtracted = 2, survivorsEliminated = 3 }),
				RULES
			),
			nil
		)
	end)
	T.it("resolves when the extraction window closes", function()
		local win = WinConditions.evaluate(
			snap({
				survivorsActive = 2,
				survivorsExtracted = 3,
				survivorsEliminated = 1,
				extractionClosed = true,
			}),
			RULES
		)
		T.expectEq(win and win.winner, "Survivors")
		local lose = WinConditions.evaluate(
			snap({
				survivorsActive = 4,
				survivorsExtracted = 1,
				survivorsEliminated = 1,
				extractionClosed = true,
			}),
			RULES
		)
		T.expectEq(lose and lose.winner, "Mimics")
		T.expectEq(lose and lose.reason, "ExtractionFailed")
	end)
	T.it("treats an empty round as abandoned", function()
		local o = WinConditions.evaluate(
			snap({ mimicsActive = 0, survivorsActive = 0, survivorsDisconnected = 6 }),
			RULES
		)
		T.expectEq(o and o.winner, "None")
		local o2 = WinConditions.evaluate(snap({ survivorsActive = 0, survivorsDisconnected = 6 }), RULES)
		T.expectEq(o2 and o2.winner, "None")
	end)
	T.it("a lone survivor disconnecting does not hand mimics a free win if others extracted", function()
		local o = WinConditions.evaluate(
			snap({
				startingSurvivors = 3,
				survivorsActive = 0,
				survivorsExtracted = 2,
				survivorsDisconnected = 1,
			}),
			RULES
		)
		T.expectEq(o and o.winner, "Survivors")
	end)
end)
