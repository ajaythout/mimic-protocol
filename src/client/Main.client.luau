--[[
	Client bootstrap for THE MIMIC PROTOCOL.

	Controllers are ModuleScripts with a Start() function. StateController
	starts first because every other controller reads from it. A failing
	controller is reported but does not stop the rest of the client.
	ClientReady is sent last so the server only counts this player as ready
	once the UI can receive round state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"StateController",
	"HudController",
	"AbilityController",
	"LobbyController",
	"AnnouncementController",
	"RoleRevealController",
	"ResultsController",
	"BayScreenController",
	"EffectsController",
	"CoreGuiController",
}

for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	local ok, err = xpcall(function()
		require(module).Start()
	end, debug.traceback)
	if not ok then
		warn(`[MimicProtocol] {name} failed to start:\n{err}`)
	end
end

Net.event(Net.Names.ClientReady):FireServer()
