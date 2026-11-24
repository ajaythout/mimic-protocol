--!strict
-- Tiny test harness for Lune. Specs call T.describe / T.it / T.expect*.
local T = {}

local state = { passed = 0, failed = 0, failures = {} :: { string }, prefix = "" }

function T.describe(name: string, body: () -> ())
	local previous = state.prefix
	state.prefix = previous .. name .. " > "
	body()
	state.prefix = previous
end

function T.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		state.passed += 1
	else
		state.failed += 1
		table.insert(state.failures, state.prefix .. name .. "\n      " .. tostring(err))
	end
end

local function fmt(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function T.expectEq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {fmt(expected)}, got {fmt(actual)}`, 2)
	end
end

function T.expectTrue(value: any, label: string?)
	if not value then
		error(`{label or "condition"} was not truthy`, 2)
	end
end

function T.expectNear(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(`{label or "value"}: expected {expected} ± {tolerance}, got {actual}`, 2)
	end
end

function T.summary(): (number, number, { string })
	return state.passed, state.failed, state.failures
end

return T
