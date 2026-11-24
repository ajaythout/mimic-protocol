--!strict
--[[
	SabotageController
	The Mimic's sabotage menu, opened from the SABOTAGE slot on the ability
	bar. Lists every sabotage with its cooldown (shared by all Mimics). Pick
	one with 1-5 or by tapping its row. The client sends intent only,
	RequestSabotage(kind); the server works out the room, door or generator.

	Cooldowns arrive through AbilityState (ability "Sabotage", detail = kind),
	routed here by AbilityController. The menu closes itself after a pick,
	outside hostile phases, and when the player is no longer an active Mimic.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local SabotageController = {}

export type KindInfo = { kind: string, title: string, hint: string, noTarget: string }

SabotageController.Kinds = {
	{
		kind = "Lights",
		title = "BLACKOUT",
		hint = "Kill the lights in this room",
		noTarget = "STAND INSIDE A LIT ROOM",
	},
	{
		kind = "Lockdown",
		title = "LOCKDOWN",
		hint = "Seal the nearest doorway",
		noTarget = "NO DOORWAY NEARBY",
	},
	{
		kind = "FalseAlert",
		title = "FALSE ALERT",
		hint = "Report a fake casualty",
		noTarget = "NO ONE TO REPORT",
	},
	{
		kind = "Generator",
		title = "GENERATOR FAULT",
		hint = "Set back a damaged generator here",
		noTarget = "NO DAMAGED GENERATOR HERE",
	},
	{
		kind = "Cameras",
		title = "CUT CAMERAS",
		hint = "Black out the security feed",
		noTarget = "CAMERAS ALREADY DOWN",
	},
} :: { KindInfo }

local ACTION = "SabotagePick"
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

type Row = { info: KindInfo, button: TextButton, status: TextLabel }

local sabotageRemote: RemoteEvent
local readyAt: { [string]: number } = {}
local rows: { Row } = {}
local isOpen = false
local panel: Frame

function SabotageController.info(kind: string?): KindInfo?
	for _, info in SabotageController.Kinds do
		if info.kind == kind then
			return info
		end
	end
	return nil
end

local function refresh()
	if not isOpen then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, row in rows do
		local remaining = (readyAt[row.info.kind] or 0) - now
		if remaining > 0 then
			row.status.Text = Components.formatTime(remaining)
			row.status.TextColor3 = Theme.Colors.TextMuted
		else
			row.status.Text = "READY"
			row.status.TextColor3 = Theme.Colors.Red
		end
	end
end

function SabotageController.close()
	if not isOpen then
		return
	end
	isOpen = false
	panel.Visible = false
	ContextActionService:UnbindAction(ACTION)
end

local function pick(index: number)
	local row = rows[index]
	if not row then
		return
	end
	sabotageRemote:FireServer(row.info.kind)
	SabotageController.close()
end

local function onAction(
	_: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		for index, key in KEYS do
			if input.KeyCode == key then
				pick(index)
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

function SabotageController.open()
	if isOpen then
		return
	end
	isOpen = true
	panel.Visible = true
	ContextActionService:BindAction(ACTION, onAction, false, table.unpack(KEYS))
	refresh()
end

function SabotageController.toggle()
	if isOpen then
		SabotageController.close()
	else
		SabotageController.open()
	end
end

function SabotageController.isOpen(): boolean
	return isOpen
end

function SabotageController.onState(payload: Net.AbilityStatePayload)
	if type(payload.detail) == "string" then
		readyAt[payload.detail] = tonumber(payload.readyAt) or 0
	end
	refresh()
end

local function build()
	local gui = Components.screen("Sabotage", Theme.Layers.Hud + 2)
	panel = Components.panel({
		Name = "SabotagePanel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -190),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	}, { accent = Theme.Colors.Red })
	local content = Components.panelContent(panel, 10, 12)
	Components.list(content, 6)
	Components.label({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.Red,
		Text = "SABOTAGE",
		LayoutOrder = 0,
		Parent = content,
	}, "Display")
	for index, info in SabotageController.Kinds do
		local button = Components.button({
			Name = info.kind,
			Size = UDim2.new(1, 0, 0, 40),
			Text = "",
			LayoutOrder = index,
			Parent = content,
		}, { accent = Theme.Colors.Red })
		Components.label({
			Name = "Title",
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -90, 0, 16),
			TextSize = Theme.TextSize.Label,
			Text = `{index}  {info.title}`,
			Parent = button,
		}, "Display")
		Components.label({
			Name = "Hint",
			Position = UDim2.fromOffset(10, 21),
			Size = UDim2.new(1, -90, 0, 14),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextMuted,
			Text = info.hint,
			Parent = button,
		}, "Body")
		local status = Components.label({
			Name = "Status",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(70, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Theme.TextSize.Caption,
			Text = "",
			Parent = button,
		}, "MonoBold")
		button.Activated:Connect(function()
			pick(index)
		end)
		table.insert(rows, { info = info, button = button, status = status })
	end
end

local function shouldStayOpen(): boolean
	return StateController.isAlive()
		and StateController.getRole() == "Mimic"
		and Phases.HostileAbilities[StateController.getPhase()] == true
end

function SabotageController.Start()
	sabotageRemote = Net.event(Net.Names.RequestSabotage)
	build()
	local function check()
		if not shouldStayOpen() then
			SabotageController.close()
		end
	end
	StateController.PhaseChanged:Connect(check)
	StateController.StatusChanged:Connect(check)
	StateController.RoleChanged:Connect(function()
		table.clear(readyAt)
		check()
	end)
	StateController.Tick:Connect(refresh)
end

return SabotageController
