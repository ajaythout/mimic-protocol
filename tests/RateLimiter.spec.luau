--!strict
local T = require("./lib/T")
local RateLimiter = require("../src/shared/Util/RateLimiter")

T.describe("RateLimiter", function()
	T.it("allows a burst up to capacity then blocks", function()
		local now = 0
		local limiter = RateLimiter.new(3, 1, function()
			return now
		end)
		T.expectTrue(limiter:consume("a"))
		T.expectTrue(limiter:consume("a"))
		T.expectTrue(limiter:consume("a"))
		T.expectEq(limiter:consume("a"), false, "4th request")
	end)
	T.it("refills over time and keeps keys independent", function()
		local now = 0
		local limiter = RateLimiter.new(2, 2, function()
			return now
		end)
		limiter:consume("a")
		limiter:consume("a")
		T.expectEq(limiter:consume("a"), false)
		T.expectTrue(limiter:consume("b"), "other key unaffected")
		now = 0.5
		T.expectTrue(limiter:consume("a"), "refilled one token")
		T.expectEq(limiter:consume("a"), false)
	end)
	T.it("forget resets a key", function()
		local limiter = RateLimiter.new(1, 0, function()
			return 0
		end)
		limiter:consume("a")
		T.expectEq(limiter:consume("a"), false)
		limiter:forget("a")
		T.expectTrue(limiter:consume("a"))
	end)
end)
