--!strict
--[[
	ChatRules
	Pure delivery policy for text chat. While a round is in progress, players
	who are no longer inside the facility (eliminated / extracted / standby
	spectators) can only talk among themselves, so they cannot reveal who the
	Mimics are to living players. Living players can be heard by everyone.
]]

export type Status = "Standby" | "Alive" | "Eliminated" | "Extracted"

local ChatRules = {}

function ChatRules.canDeliver(
	senderStatus: Status?,
	receiverStatus: Status?,
	roundInProgress: boolean
): boolean
	if not roundInProgress then
		return true
	end
	if senderStatus == "Alive" then
		return true
	end
	-- Sender is outside the facility: only other non-living players may hear.
	return receiverStatus ~= "Alive"
end

return ChatRules
