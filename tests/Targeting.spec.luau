--!strict
local roblox = require("@lune/roblox")
local T = require("./lib/T")
local Targeting = require("../src/shared/Modules/Targeting")

local V = roblox.Vector3.new
local RULES = { Range = 8, FacingDot = 0.2, CloseRange = 3.5 }
local ORIGIN = V(0, 3, 0)
local FORWARD = V(0, 0, 1)

local function clear(): boolean
	return true
end

local function pick(candidates, look: any?, los: any?): string?
	return Targeting.pick(ORIGIN, look or FORWARD, candidates, RULES, los or clear)
end

T.describe("Targeting.pick", function()
	T.it("picks the nearest candidate in front", function()
		T.expectEq(
			pick({ { position = V(0, 3, 6), item = "far" }, { position = V(0, 3, 4), item = "near" } }),
			"near"
		)
	end)
	T.it("ignores candidates out of range", function()
		T.expectEq(pick({ { position = V(0, 3, 8.5), item = "far" } }), nil)
	end)
	T.it("ignores candidates behind unless they are very close", function()
		T.expectEq(pick({ { position = V(0, 3, -6), item = "behind" } }), nil)
		T.expectEq(pick({ { position = V(0, 3, -3), item = "close" } }), "close")
	end)
	T.it("respects the facing cone", function()
		-- 45 degrees off forward: cos = 0.707 >= 0.2
		T.expectEq(pick({ { position = V(4, 3, 4), item = "diagonal" } }), "diagonal")
		-- straight sideways beyond close range: cos = 0
		T.expectEq(pick({ { position = V(6, 3, 0), item = "side" } }), nil)
	end)
	T.it("skips candidates without line of sight and falls back to the next", function()
		local blocked = function(_, to)
			return to.Z ~= 4
		end
		T.expectEq(
			pick(
				{ { position = V(0, 3, 4), item = "walled" }, { position = V(0, 3, 6), item = "open" } },
				nil,
				blocked
			),
			"open"
		)
	end)
	T.it("treats a vertical look as facing +Z", function()
		T.expectEq(pick({ { position = V(0, 3, 6), item = "ahead" } }, V(0, 1, 0)), "ahead")
	end)
end)
