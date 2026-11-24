--[[
	Server bootstrap for THE MIMIC PROTOCOL.

	Services are plain ModuleScripts with optional Init() and Start():
	  Init()   wire remotes, signals and look up map content (no yielding loops)
	  Start()  begin long-running work once every service is initialised

	Order matters only for Init (dependencies first). All services live in
	ServerScriptService.Server.Services and never replicate to clients.
]]

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"PlayerRegistry",
	"MatchState",
	"Announcer",
	"CharacterService",
	"FacilityService",
	"RoleService",
	"MimicAbilityService",
	"EliminationService",
	"ExtractionService",
	"ChatService",
	"RoundService",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `Missing service module {name}`)
	loaded[name] = require(module)
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Init) == "function" then
		service.Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if type(service.Start) == "function" then
		task.spawn(service.Start)
	end
end

print(`[MimicProtocol] server ready ({#ORDER} services)`)
