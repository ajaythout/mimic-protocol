--!strict
--[[
	ResultsController
	End-of-round debrief: winner, reason, extraction tally, duration, the
	player's own outcome and the full role reveal roster.

	Progression rewards (XP, currency, achievements) are Phase 5; this screen
	only shows facts the server actually sent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local ResultsController = {}

local localPlayer = Players.LocalPlayer

local WINNER_TITLE = {
	Survivors = "SURVIVORS ESCAPED",
	Mimics = "FACILITY OVERRUN",
	None = "ROUND CANCELLED",
}

local WINNER_COLOR = {
	Survivors = Theme.Colors.Cyan,
	Mimics = Theme.Colors.Red,
	None = Theme.Colors.TextMuted,
}

local function fateText(entry: Net.RosterEntry): string
	if entry.fate == "Survived" then
		return if entry.role == "Mimic" then "UNDETECTED" else "LEFT BEHIND"
	elseif entry.fate == "Eliminated" then
		return if entry.role == "Mimic" then "NEUTRALIZED" else "ASSIMILATED"
	end
	return string.upper(entry.fate)
end

local ui = {} :: {
	gui: ScreenGui,
	overlay: Frame,
	panel: Frame,
	verdict: TextLabel,
	title: TextLabel,
	reason: TextLabel,
	stats: TextLabel,
	personal: TextLabel,
	roster: ScrollingFrame,
	continue: TextButton,
}

local function build()
	local gui = Components.screen("Results", Theme.Layers.Results, true)
	gui.Enabled = false
	ui.gui = gui

	ui.overlay = Components.create("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 6, 9),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = gui,
	})

	local panel = Components.panel({
		Name = "Debrief",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 560),
		Parent = ui.overlay,
	})
	Components.padding(panel, 22, 28)
	ui.panel = panel
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(700, 560)
	constraint.Parent = panel

	ui.verdict = Components.label({
		Name = "Verdict",
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		Text = "",
		Parent = panel,
	}, "Display")
	ui.title = Components.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Title,
		Text = "",
		Parent = panel,
	}, "Display")
	ui.reason = Components.label({
		Name = "Reason",
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "",
		Parent = panel,
	}, "Body")
	ui.stats = Components.label({
		Name = "Stats",
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		Text = "",
		Parent = panel,
	}, "Mono")
	ui.personal = Components.label({
		Name = "Personal",
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		Text = "",
		Parent = panel,
	}, "Display")

	ui.roster = Components.create("ScrollingFrame", {
		Name = "Roster",
		Position = UDim2.fromOffset(0, 158),
		Size = UDim2.new(1, 0, 1, -158 - 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.Cyan,
		Parent = panel,
	})
	Components.list(ui.roster, 4)

	local continue = Components.button({
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(220, 40),
		Text = "CONTINUE",
		Parent = panel,
	})
	ui.continue = continue
	continue.Activated:Connect(function()
		ResultsController.hide()
	end)
end

local function addRow(entry: Net.RosterEntry, index: number)
	local isMe = entry.userId == localPlayer.UserId
	local roleColor = Theme.RoleColors[entry.role] or Theme.Colors.Text
	local row = Components.create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, -8, 0, 30),
		BackgroundColor3 = if isMe then Theme.Colors.PanelHover else Theme.Colors.PanelRaised,
		BackgroundTransparency = if isMe then 0.1 else 0.45,
		BorderSizePixel = 0,
		LayoutOrder = index,
		Parent = ui.roster,
	})
	Components.corner(row)
	Components.label({
		Name = "Name",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.42, -12, 1, 0),
		TextSize = Theme.TextSize.Body,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = entry.name,
		Parent = row,
	}, if isMe then "BodyBold" else "Body")
	Components.label({
		Name = "Role",
		Position = UDim2.fromScale(0.42, 0),
		Size = UDim2.fromScale(0.2, 1),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = roleColor,
		Text = string.upper(entry.role),
		Parent = row,
	}, "Display")
	Components.label({
		Name = "Fate",
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.fromScale(0.24, 1),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.TextMuted,
		Text = fateText(entry),
		Parent = row,
	}, "Mono")
	if entry.role == "Mimic" then
		Components.label({
			Name = "Eliminations",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromScale(0.14, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Theme.TextSize.Label,
			TextColor3 = Theme.Colors.Red,
			Text = `{entry.eliminations} ×`,
			Parent = row,
		}, "MonoBold")
	end
end

function ResultsController.show(payload: Net.RoundResultPayload)
	for _, child in ui.roster:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local color = WINNER_COLOR[payload.winner] or Theme.Colors.Text
	ui.title.Text = WINNER_TITLE[payload.winner] or ""
	ui.title.TextColor3 = color
	ui.reason.Text = payload.reasonText or ""
	ui.stats.Text = `EXTRACTED {payload.extracted}/{payload.required}   ·   DURATION {Components.formatTime(
		payload.durationSeconds
	)}`

	local mine: Net.RosterEntry? = nil
	-- Mimics first, then survivors, preserving roster order within each.
	local ordered = table.clone(payload.roster)
	table.sort(ordered, function(a, b)
		if a.role ~= b.role then
			return a.role == "Mimic"
		end
		return a.name < b.name
	end)
	for index, entry in ordered do
		addRow(entry, index)
		if entry.userId == localPlayer.UserId then
			mine = entry
		end
	end

	if mine and payload.winner ~= "None" then
		local won = (payload.winner == "Survivors" and mine.role == "Survivor")
			or (payload.winner == "Mimics" and mine.role == "Mimic")
		ui.verdict.Text = if won then "VICTORY" else "DEFEAT"
		ui.verdict.TextColor3 = if won then Theme.Colors.Teal else Theme.Colors.Red
		local detail = fateText(mine)
		if mine.role == "Mimic" then
			detail ..= `  ·  {mine.eliminations} ASSIMILATION{if mine.eliminations == 1 then "" else "S"}`
		end
		ui.personal.Text = `YOU: {string.upper(mine.role)}  ·  {detail}`
		ui.personal.TextColor3 = Theme.RoleColors[mine.role] or Theme.Colors.Text
	else
		ui.verdict.Text = if payload.winner == "None" then "NO CONTEST" else "SPECTATOR"
		ui.verdict.TextColor3 = Theme.Colors.TextMuted
		ui.personal.Text = ""
	end

	ui.gui.Enabled = true
	ui.overlay.BackgroundTransparency = 1
	Components.tween(ui.overlay, Theme.Motion.Medium, { BackgroundTransparency = 0.25 })
	local scale = ui.panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = ui.panel
	Components.tween(scale, Theme.Motion.Slow, { Scale = 1 })
end

function ResultsController.hide()
	ui.gui.Enabled = false
end

function ResultsController.Start()
	build()
	Net.event(Net.Names.RoundResult).OnClientEvent:Connect(function(payload: Net.RoundResultPayload)
		if type(payload) == "table" and type(payload.roster) == "table" then
			ResultsController.show(payload)
		end
	end)
	StateController.PhaseChanged:Connect(function(phase)
		if phase == Phases.Intermission or phase == Phases.RoleReveal or phase == Phases.Waiting then
			ResultsController.hide()
		end
	end)
end

return ResultsController
