--!strict
--[[
	CoreGuiController
	Adjusts Roblox core UI for this game:
	  • the health bar is hidden (eliminations are one-hit; health is noise)
	  • the Reset Character option is disabled while the player is inside the
	    facility, so an accidental reset cannot eliminate a player
	SetCore can fail while core scripts are still loading, so calls retry.
]]

local StarterGui = game:GetService("StarterGui")

local StateController = require(script.Parent.StateController)

local CoreGuiController = {}

local function setCoreWithRetry(name: string, value: any)
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCore(name, value)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
		warn(`[CoreGuiController] SetCore({name}) did not succeed`)
	end)
end

local function refreshReset()
	setCoreWithRetry("ResetButtonCallback", not StateController.isAlive())
end

function CoreGuiController.Start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	StateController.StatusChanged:Connect(refreshReset)
	refreshReset()
end

return CoreGuiController
