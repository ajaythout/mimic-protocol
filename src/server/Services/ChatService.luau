--!strict
--[[
	ChatService
	Applies ChatRules to every TextChatService channel: during a round, players
	outside the facility (eliminated, extracted, standby) can only be heard by
	other players outside the facility. Voice chat is not required by any
	mechanic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChatRules = require(Shared.Modules.ChatRules)
local Phases = require(Shared.Modules.Phases)

local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local ChatService = {}

local function shouldDeliver(message: TextChatMessage, target: TextSource): boolean
	local source = message.TextSource
	if not source then
		return true -- system messages
	end
	local sender = Players:GetPlayerByUserId(source.UserId)
	local receiver = Players:GetPlayerByUserId(target.UserId)
	if not sender or not receiver or sender == receiver then
		return true
	end
	local roundInProgress = Phases.InFacility[MatchState.getPhase()] == true
	return ChatRules.canDeliver(
		PlayerRegistry.getStatus(sender),
		PlayerRegistry.getStatus(receiver),
		roundInProgress
	)
end

local function attach(channel: Instance)
	if channel:IsA("TextChannel") then
		channel.ShouldDeliverCallback = shouldDeliver
	end
end

function ChatService.Start()
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if not channels then
			warn("[ChatService] TextChatService.TextChannels not found; chat isolation disabled")
			return
		end
		for _, channel in channels:GetChildren() do
			attach(channel)
		end
		channels.ChildAdded:Connect(attach)
	end)
end

return ChatService
