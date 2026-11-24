--!strict
-- Runs every tests/*.spec.luau with Lune:  lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")
local T = require("./lib/T")

local specs = {}
for _, name in fs.readDir("tests") do
	if string.sub(name, -10) == ".spec.luau" then
		table.insert(specs, string.sub(name, 1, -6))
	end
end
table.sort(specs)

for _, spec in specs do
	print("• " .. spec)
	require("./" .. spec)
end

local passed, failed, failures = T.summary()
for _, failure in failures do
	print("  ✗ " .. failure)
end
print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
