--!strict
--[[
	PlayerRegistry
	Owns per-connection player bookkeeping that exists outside of any round:
	  • client readiness (the client's UI has loaded and it can receive state)
	  • the Standby "sit out" toggle (readiness check for the next round)
	  • the public Status attribute and the matching Team

	Status values (public, replicated as Player attribute "Status"):
	  Standby     in the Deployment Bay, not part of the current round
	  Alive       inside the facility as a round participant
	  Eliminated  removed from the current round, spectating from the bay
	  Extracted   escaped via the lift, spectating from the bay

	Roles are NEVER stored here or on any replicated object.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local RateLimiter = require(Shared.Util.RateLimiter)
local Signal = require(Shared.Util.Signal)

export type Status = "Standby" | "Alive" | "Eliminated" | "Extracted"

type PlayerRecord = {
	player: Player,
	status: Status,
	afk: boolean,
	clientReady: boolean,
}

local PlayerRegistry = {}

PlayerRegistry.PlayerAdded = Signal.new() -- (player)
PlayerRegistry.PlayerRemoving = Signal.new() -- (player)
PlayerRegistry.ClientReady = Signal.new() -- (player)
PlayerRegistry.EligibilityChanged = Signal.new() -- ()
PlayerRegistry.StatusChanged = Signal.new() -- (player, newStatus, oldStatus)

local records: { [Player]: PlayerRecord } = {}

local TEAM_FOR_STATUS: { [Status]: string } = {
	Standby = "Standby",
	Alive = "Operatives",
	Eliminated = "Observers",
	Extracted = "Observers",
}

local readyLimiter =
	RateLimiter.new(GameConfig.RateLimits.Default.Capacity, GameConfig.RateLimits.Default.RefillPerSecond)
local afkLimiter =
	RateLimiter.new(GameConfig.RateLimits.SetAfk.Capacity, GameConfig.RateLimits.SetAfk.RefillPerSecond)

local function applyTeam(player: Player, status: Status)
	local team = Teams:FindFirstChild(TEAM_FOR_STATUS[status])
	if team and team:IsA("Team") then
		player.Team = team
	end
end

local function onPlayerAdded(player: Player)
	if records[player] then
		return
	end
	records[player] = {
		player = player,
		status = "Standby",
		afk = false,
		clientReady = false,
	}
	player:SetAttribute("Status", "Standby")
	player:SetAttribute("AFK", false)
	applyTeam(player, "Standby")
	PlayerRegistry.PlayerAdded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	if not records[player] then
		return
	end
	PlayerRegistry.PlayerRemoving:Fire(player)
	records[player] = nil
	readyLimiter:forget(player)
	afkLimiter:forget(player)
	PlayerRegistry.EligibilityChanged:Fire()
end

function PlayerRegistry.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Net.event(Net.Names.ClientReady).OnServerEvent:Connect(function(player: Player)
		if not readyLimiter:consume(player) then
			return
		end
		local record = records[player]
		if not record then
			return
		end
		local wasReady = record.clientReady
		record.clientReady = true
		-- Always answer so a client that reloaded its scripts gets fresh state.
		PlayerRegistry.ClientReady:Fire(player)
		if not wasReady then
			PlayerRegistry.EligibilityChanged:Fire()
		end
	end)

	Net.event(Net.Names.SetAfk).OnServerEvent:Connect(function(player: Player, afk: unknown)
		if type(afk) ~= "boolean" then
			return
		end
		if not afkLimiter:consume(player) then
			return
		end
		local record = records[player]
		if not record or record.afk == afk then
			return
		end
		record.afk = afk
		player:SetAttribute("AFK", afk)
		PlayerRegistry.EligibilityChanged:Fire()
	end)
end

function PlayerRegistry.Start()
	-- Players who joined before this script connected (Studio play solo).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function PlayerRegistry.getStatus(player: Player): Status?
	local record = records[player]
	return record and record.status
end

function PlayerRegistry.setStatus(player: Player, status: Status)
	local record = records[player]
	if not record or record.status == status then
		return
	end
	local old = record.status
	record.status = status
	player:SetAttribute("Status", status)
	applyTeam(player, status)
	PlayerRegistry.StatusChanged:Fire(player, status, old)
end

function PlayerRegistry.isTracked(player: Player): boolean
	return records[player] ~= nil
end

function PlayerRegistry.isEligible(player: Player): boolean
	local record = records[player]
	return record ~= nil and record.clientReady and not record.afk and player.Parent == Players
end

function PlayerRegistry.getEligiblePlayers(): { Player }
	local list = {}
	for player, record in records do
		if record.clientReady and not record.afk and player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

-- Minimum ready players needed to start a round on this server.
function PlayerRegistry.requiredPlayers(): number
	if RunService:IsStudio() then
		return GameConfig.Players.MinStudio
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 then
		return GameConfig.Players.MinPrivateServer
	end
	return GameConfig.Players.MinPublic
end

return PlayerRegistry
