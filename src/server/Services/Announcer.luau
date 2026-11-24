--!strict
--[[
	Announcer
	Thin helper over the Announcement remote so every system formats banners
	the same way. Text is always authored on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

export type Severity = "Info" | "Warning" | "Critical" | "Success"

local Announcer = {}

local remote: RemoteEvent

function Announcer.Init()
	remote = Net.event(Net.Names.Announcement)
end

local function payload(
	title: string,
	body: string?,
	severity: Severity?,
	duration: number?
): Net.AnnouncementPayload
	return {
		title = title,
		body = body,
		severity = severity or "Info",
		duration = duration,
	}
end

function Announcer.all(title: string, body: string?, severity: Severity?, duration: number?)
	remote:FireAllClients(payload(title, body, severity, duration))
end

function Announcer.to(player: Player, title: string, body: string?, severity: Severity?, duration: number?)
	if player.Parent == Players then
		remote:FireClient(player, payload(title, body, severity, duration))
	end
end

function Announcer.toList(
	players: { Player },
	title: string,
	body: string?,
	severity: Severity?,
	duration: number?
)
	local message = payload(title, body, severity, duration)
	for _, player in players do
		if player.Parent == Players then
			remote:FireClient(player, message)
		end
	end
end

return Announcer
