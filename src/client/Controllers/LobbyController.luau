--!strict
--[[
	LobbyController
	The Standby panel shown whenever the player is not inside the facility
	(waiting, eliminated, extracted, or joined mid-round).

	It is also the readiness check: the toggle sends SetAfk to the server,
	which excludes "sitting out" players from the next role assignment. The
	button reflects the server-confirmed AFK attribute, never a local guess.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local LobbyController = {}

local ui = {} :: {
	panel: Frame,
	title: TextLabel,
	info: TextLabel,
	toggle: TextButton,
	toggleStroke: UIStroke,
}

local setAfkRemote: RemoteEvent
local pending = false

local function infoText(): (string, string)
	local phase = StateController.getPhase()
	local status = StateController.getStatus()
	local eligible = StateController.getPublic("EligiblePlayers") or 0
	local required = StateController.getPublic("RequiredPlayers") or 0

	if status == "Eliminated" then
		return "SIGNAL LOST", "You were removed from the round. You will deploy again next round."
	elseif status == "Extracted" then
		return "EXTRACTED", "You escaped the facility. Wait here for the debrief."
	end
	if phase == Phases.Waiting then
		return "AWAITING PERSONNEL",
			`{eligible} of {required} operatives ready. The round starts automatically.`
	elseif phase == Phases.Intermission then
		return "DEPLOYMENT IMMINENT",
			`{eligible} operatives ready. Deploying in {Components.formatTime(
				StateController.getTimeRemaining()
			)}.`
	elseif phase == Phases.Results then
		return "DEBRIEF", "Next briefing begins shortly."
	elseif Phases.InRound[phase] then
		return "ROUND IN PROGRESS", "You will be deployed in the next round."
	end
	return "STANDBY", ""
end

local function refresh()
	local visible = not StateController.isAlive()
	ui.panel.Visible = visible
	if not visible then
		return
	end
	local title, info = infoText()
	ui.title.Text = title
	ui.info.Text = info

	local afk = StateController.isAfk()
	ui.toggle.Text = if afk then "SITTING OUT  ·  TAP TO JOIN" else "READY FOR DEPLOYMENT"
	ui.toggle.TextColor3 = if afk then Theme.Colors.TextMuted else Theme.Colors.Text
	ui.toggleStroke.Color = if afk then Theme.Colors.StrokeMuted else Theme.Colors.Cyan
	ui.toggle.AutoButtonColor = false
	ui.toggle.Active = not pending
end

local function build()
	local gui = Components.screen("Standby", Theme.Layers.Lobby)
	local panel = Components.panel({
		Name = "StandbyPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	})
	local content = Components.panelContent(panel, 14, 18)
	Components.list(content, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	ui.panel = panel

	ui.title = Components.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Colors.Cyan,
		LayoutOrder = 1,
		Parent = content,
	}, "Display")
	ui.info = Components.label({
		Name = "Info",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.TextMuted,
		LayoutOrder = 2,
		Parent = content,
	}, "Body")
	local toggle, stroke = Components.button({
		Name = "ReadyToggle",
		Size = UDim2.fromOffset(300, 40),
		LayoutOrder = 3,
		Text = "",
		Parent = content,
	})
	ui.toggle = toggle
	ui.toggleStroke = stroke

	toggle.Activated:Connect(function()
		if pending then
			return
		end
		pending = true
		setAfkRemote:FireServer(not StateController.isAfk())
		-- Re-enable after the server answers (attribute change) or a timeout.
		task.delay(1.5, function()
			pending = false
			refresh()
		end)
		refresh()
	end)
end

function LobbyController.Start()
	setAfkRemote = Net.event(Net.Names.SetAfk)
	build()
	StateController.AfkChanged:Connect(function()
		pending = false
		refresh()
	end)
	StateController.StatusChanged:Connect(refresh)
	StateController.PhaseChanged:Connect(refresh)
	StateController.CountsChanged:Connect(refresh)
	StateController.Tick:Connect(function()
		if StateController.getPhase() == Phases.Intermission then
			refresh()
		end
	end)
	refresh()
end

return LobbyController
