--!strict
--[[
	RateLimiter
	Token-bucket limiter keyed by any value (normally a Player). Used at every
	client->server remote boundary to absorb spam before any expensive work.

	local limiter = RateLimiter.new(6, 2)        -- capacity, refill/sec
	if not limiter:consume(player) then return end
	limiter:forget(player)                        -- on PlayerRemoving

	The clock is injectable for tests; defaults to os.clock.
]]

type Bucket = { tokens: number, updatedAt: number }

export type RateLimiter = {
	capacity: number,
	refillPerSecond: number,
	_buckets: { [any]: Bucket },
	_clock: () -> number,
	consume: (self: RateLimiter, key: any, cost: number?) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter
	local self = setmetatable({}, RateLimiter) :: any
	self.capacity = capacity
	self.refillPerSecond = refillPerSecond
	self._buckets = {}
	self._clock = clock or os.clock
	return self :: RateLimiter
end

function RateLimiter.consume(self: RateLimiter, key: any, cost: number?): boolean
	local amount = cost or 1
	local now = self._clock()
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { tokens = self.capacity, updatedAt = now }
		self._buckets[key] = bucket
	end

	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)
	bucket.updatedAt = now

	if bucket.tokens < amount then
		return false
	end
	bucket.tokens -= amount
	return true
end

function RateLimiter.forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
