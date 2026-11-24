--!strict
--[[
	AbilityController
	The role ability bar (bottom right). Each slot is one ability with a key,
	a gamepad button, an on-screen button, a cooldown and, for lasting effects
	such as a disguise, an "active" timer. Only the local player's role's
	slots are shown and bound.

	  Mimic   ASSIMILATE [F / ButtonX]   SHIFT [Q / ButtonY]   IMPERSONATE [R / ButtonB]

	The client only sends intent. Cooldowns and active timers come from the
	server's AbilityState messages; nothing is trusted from local timing. For
	Object Shift the client also names the prop under the crosshair, which
	the server re-validates.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local AbilityController = {}

local PRESS_INTERVAL = 0.3
local EDGE_MARGIN = 24
local JUMP_GAP = 10
local SLOT_GAP = 10
local FEEDBACK_HEIGHT = 26
local AIM_DISTANCE = 60

type Slot = {
	id: string, -- ability id (Net.Abilities)
	name: string, -- button instance name
	title: string,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	action: string, -- ContextActionService action name
	accent: Color3,
	role: string,
	order: number, -- 1 = rightmost
	activate: (active: boolean) -> (),
	readyAt: number,
	cooldown: number,
	activeUntil: number,
	lastPress: number,
	bound: boolean,
	button: TextButton,
	overlay: Frame,
	countdown: TextLabel,
	keyHint: TextLabel,
	stroke: UIStroke,
}

type Feedback = { text: string | (string?) -> string, color: Color3 }

local strikeRemote: RemoteEvent
local abilityRemote: RemoteEvent
local slots: { Slot } = {}
local slotsById: { [string]: Slot } = {}

local ui = {} :: {
	gui: ScreenGui,
	scale: UIScale,
	root: Frame,
	feedback: TextLabel,
}

local MUTED = Theme.Colors.TextMuted
local FEEDBACK: { [string]: { [string]: Feedback } } = {
	[Net.Abilities.Assimilate] = {
		Hit = { text = "ASSIMILATED", color = Theme.Colors.Red },
		NoTarget = { text = "NO SURVIVOR IN REACH", color = MUTED },
		Locked = { text = "ORGANISM DORMANT", color = MUTED },
	},
	[Net.Abilities.ObjectShift] = {
		Shifted = {
			text = function(detail: string?): string
				return `DISGUISED AS {string.upper(detail or "A PROP")}`
			end,
			color = Theme.Colors.Cyan,
		},
		Reverted = { text = "DISGUISE DROPPED", color = MUTED },
		Expired = { text = "DISGUISE FADED", color = MUTED },
		Revealed = { text = "DISGUISE BROKEN", color = Theme.Colors.Red },
		NoTarget = { text = "NO PROP IN REACH", color = MUTED },
		Cooldown = { text = "RECHARGING", color = MUTED },
		Locked = { text = "ORGANISM DORMANT", color = MUTED },
	},
	[Net.Abilities.IdentityTheft] = {
		Copied = {
			text = function(detail: string?): string
				return `NOW APPEARING AS {string.upper(detail or "SOMEONE")}`
			end,
			color = Theme.Colors.RedSoft,
		},
		Restored = { text = "OWN FORM RESTORED", color = MUTED },
		Expired = { text = "IMPERSONATION FADED", color = MUTED },
		NoTarget = { text = "NO ONE IN REACH", color = MUTED },
		Failed = { text = "IMPERSONATION FAILED", color = MUTED },
		Cooldown = { text = "RECHARGING", color = MUTED },
		Locked = { text = "ORGANISM DORMANT", color = MUTED },
	},
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function hostilePhase(): boolean
	return Phases.HostileAbilities[StateController.getPhase()] == true
end

local function showFeedback(text: string, color: Color3)
	ui.feedback.Text = text
	ui.feedback.TextColor3 = color
	ui.feedback.TextTransparency = 0
	Components.tween(ui.feedback, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	})
end

-- Touch layout whenever the player is actually using touch, which can change
-- mid-session (touchscreen laptops, tablets with keyboards, the emulator).
local function isTouchLayout(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	return not UserInputService.KeyboardEnabled
		or UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- The placed prop under the crosshair (mouse on desktop, screen centre otherwise).
local function aimedProp(): Instance?
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	if not camera or not character then
		return nil
	end
	local point = camera.ViewportSize / 2
	if not isTouchLayout() and UserInputService.MouseEnabled then
		point = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
	local node: Instance? = result and result.Instance
	while node and node ~= Workspace do
		if node:IsA("Model") and node:HasTag("MimicProp") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function press(slot: Slot)
	local clock = os.clock()
	if clock - slot.lastPress < PRESS_INTERVAL then
		return
	end
	slot.lastPress = clock
	local active = slot.activeUntil > now()
	if not active then
		if not hostilePhase() then
			showFeedback("ORGANISM DORMANT", MUTED)
			return
		end
		if now() < slot.readyAt then
			showFeedback("RECHARGING", MUTED)
			return
		end
	end
	slot.activate(active)
end

-- Roblox's on-screen jump button, if touch controls are showing.
local function findJumpButton(): GuiObject?
	local touchGui = ui.gui.Parent and ui.gui.Parent:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if
		touchGui
		and touchGui:IsA("ScreenGui")
		and touchGui.Enabled
		and jump
		and jump:IsA("GuiObject")
		and jump.Visible
	then
		return jump
	end
	return nil
end

local function visibleSlots(): { Slot }
	local role = StateController.getRole()
	local list = {}
	for _, slot in slots do
		if slot.role == role then
			table.insert(list, slot)
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

--[[
	Bottom-right corner, stacked above the jump button when touch controls are
	up so a thumb never lands on both. The jump button's size and position
	depend on screen size, so measure it instead of guessing an offset.
]]
local function applyLayout()
	local touch = isTouchLayout()
	local size = if touch then 118 else 96
	local shown = visibleSlots()
	local count = math.max(1, #shown)
	ui.root.Size = UDim2.fromOffset(count * size + (count - 1) * SLOT_GAP, size + FEEDBACK_HEIGHT)
	for _, slot in slots do
		slot.button.Visible = false
	end
	for index, slot in shown do
		slot.button.Visible = true
		slot.button.Size = UDim2.fromOffset(size, size)
		slot.button.AnchorPoint = Vector2.new(1, 0)
		slot.button.Position = UDim2.new(1, -(index - 1) * (size + SLOT_GAP), 0, FEEDBACK_HEIGHT)
	end

	local lift = EDGE_MARGIN
	local jump = if touch then findJumpButton() else nil
	if jump then
		-- AbsolutePosition shares one coordinate space across ScreenGuis; offsets
		-- in this gui are multiplied by its UIScale, so convert pixels back.
		local guiBottom = ui.gui.AbsolutePosition.Y + ui.gui.AbsoluteSize.Y
		local pixelsAbove = guiBottom - jump.AbsolutePosition.Y
		lift = math.max(EDGE_MARGIN, pixelsAbove / math.max(ui.scale.Scale, 0.01) + JUMP_GAP)
	end
	ui.root.Position = UDim2.new(1, -EDGE_MARGIN, 1, -lift)
end

local function onAction(name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		for _, slot in slots do
			if slot.action == name and slot.bound then
				press(slot)
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local function refreshVisibility()
	local show = StateController.isAlive() and #visibleSlots() > 0
	ui.root.Visible = show
	if show then
		applyLayout() -- touch controls may have appeared since the last layout
	end
	local role = StateController.getRole()
	for _, slot in slots do
		local want = show and slot.role == role
		if want and not slot.bound then
			ContextActionService:BindAction(slot.action, onAction, false, slot.key, slot.pad)
			slot.bound = true
		elseif not want and slot.bound then
			ContextActionService:UnbindAction(slot.action)
			slot.bound = false
		end
	end
end

local function refreshSlot(slot: Slot)
	local t = now()
	local hint = if isTouchLayout() then "TAP" else `[{slot.key.Name}]`
	if slot.activeUntil > t then
		slot.overlay.Size = UDim2.fromScale(1, 0)
		slot.countdown.Text = tostring(math.ceil(slot.activeUntil - t))
		slot.stroke.Color = Theme.Colors.Cyan
		slot.keyHint.Text = if isTouchLayout() then "TAP TO DROP" else `{hint} DROP`
		return
	end
	if not hostilePhase() then
		slot.overlay.Size = UDim2.fromScale(1, 1)
		slot.countdown.Text = ""
		slot.keyHint.Text = "DORMANT"
		slot.stroke.Color = Theme.Colors.StrokeMuted
		return
	end
	local remaining = slot.readyAt - t
	if remaining > 0 then
		slot.overlay.Size = UDim2.fromScale(1, math.clamp(remaining / slot.cooldown, 0, 1))
		slot.countdown.Text = tostring(math.ceil(remaining))
		slot.stroke.Color = Theme.Colors.StrokeMuted
	else
		slot.overlay.Size = UDim2.fromScale(1, 0)
		slot.countdown.Text = ""
		slot.stroke.Color = slot.accent
	end
	slot.keyHint.Text = hint
end

local function refreshCooldowns()
	if not ui.root.Visible then
		return
	end
	for _, slot in slots do
		if slot.button.Visible then
			refreshSlot(slot)
		end
	end
end

local function buildSlot(def: {
	id: string,
	name: string,
	title: string,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	action: string,
	accent: Color3,
	role: string,
	order: number,
	activate: (active: boolean) -> (),
}): Slot
	local button, stroke = Components.button({
		Name = def.name,
		Text = "",
		ClipsDescendants = true,
		Visible = false,
		Parent = ui.root,
	}, { accent = def.accent })
	stroke.Thickness = 2

	local overlay = Components.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = button,
	})
	Components.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -8, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 10,
		TextColor3 = def.accent,
		Text = def.title,
		ZIndex = 3,
		Parent = button,
	}, "Display")
	local countdown = Components.label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 28,
		Text = "",
		ZIndex = 3,
		Parent = button,
	}, "MonoBold")
	local keyHint = Components.label({
		Name = "KeyHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -8, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = MUTED,
		Text = `[{def.key.Name}]`,
		ZIndex = 3,
		Parent = button,
	}, "Mono")

	local slot: Slot = {
		id = def.id,
		name = def.name,
		title = def.title,
		key = def.key,
		pad = def.pad,
		action = def.action,
		accent = def.accent,
		role = def.role,
		order = def.order,
		activate = def.activate,
		readyAt = 0,
		cooldown = 1,
		activeUntil = 0,
		lastPress = 0,
		bound = false,
		button = button,
		overlay = overlay,
		countdown = countdown,
		keyHint = keyHint,
		stroke = stroke,
	}
	button.Activated:Connect(function()
		press(slot)
	end)
	table.insert(slots, slot)
	slotsById[def.id] = slot
	return slot
end

local function build()
	local gui, scale = Components.screen("Abilities", Theme.Layers.Hud + 1)
	ui.gui = gui
	ui.scale = scale
	ui.root = Components.create("Frame", {
		Name = "AbilityBar",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.feedback = Components.label({
		Name = "Feedback",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(320, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Theme.TextSize.Caption,
		TextTransparency = 1,
		Text = "",
		Parent = ui.root,
	}, "Display")

	buildSlot({
		id = Net.Abilities.Assimilate,
		name = "Assimilate",
		title = "ASSIMILATE",
		key = Enum.KeyCode.F,
		pad = Enum.KeyCode.ButtonX,
		action = "MimicAssimilate",
		accent = Theme.Colors.Red,
		role = "Mimic",
		order = 1,
		activate = function()
			strikeRemote:FireServer()
		end,
	})
	buildSlot({
		id = Net.Abilities.ObjectShift,
		name = "Shift",
		title = "SHIFT",
		key = Enum.KeyCode.Q,
		pad = Enum.KeyCode.ButtonY,
		action = "MimicShift",
		accent = Theme.Colors.Cyan,
		role = "Mimic",
		order = 2,
		activate = function(active: boolean)
			-- While disguised the same input drops the disguise.
			abilityRemote:FireServer(Net.Abilities.ObjectShift, if active then nil else aimedProp())
		end,
	})
	buildSlot({
		id = Net.Abilities.IdentityTheft,
		name = "Impersonate",
		title = "IMPERSONATE",
		key = Enum.KeyCode.R,
		pad = Enum.KeyCode.ButtonB,
		action = "MimicImpersonate",
		accent = Theme.Colors.RedSoft,
		role = "Mimic",
		order = 3,
		activate = function()
			-- Intent only; pressing while active asks to end it early.
			abilityRemote:FireServer(Net.Abilities.IdentityTheft)
		end,
	})
	applyLayout()
end

local function onAbilityState(payload: Net.AbilityStatePayload)
	if type(payload) ~= "table" then
		return
	end
	local slot = slotsById[payload.ability]
	if not slot then
		return
	end
	slot.readyAt = tonumber(payload.readyAt) or 0
	slot.cooldown = math.max(1, tonumber(payload.cooldown) or 1)
	slot.activeUntil = tonumber(payload.activeUntil) or 0
	local messages = FEEDBACK[slot.id]
	local entry = messages and payload.result and messages[payload.result]
	if entry then
		local text = entry.text
		showFeedback(if type(text) == "function" then text(payload.detail) else text, entry.color)
	end
	refreshCooldowns()
end

function AbilityController.Start()
	strikeRemote = Net.event(Net.Names.RequestStrike)
	abilityRemote = Net.event(Net.Names.RequestAbility)
	build()

	Net.event(Net.Names.AbilityState).OnClientEvent:Connect(onAbilityState)

	-- A new round starts every slot fresh until the server says otherwise.
	StateController.RoleChanged:Connect(function()
		for _, slot in slots do
			slot.readyAt = 0
			slot.activeUntil = 0
		end
		refreshVisibility()
	end)
	StateController.StatusChanged:Connect(refreshVisibility)
	StateController.PhaseChanged:Connect(refreshCooldowns)
	StateController.Tick:Connect(refreshCooldowns)
	UserInputService.LastInputTypeChanged:Connect(applyLayout)
	ui.scale:GetPropertyChangedSignal("Scale"):Connect(applyLayout)
	-- Touch controls are created (and resized) by Roblox on its own schedule.
	local function watchJumpButton(instance: Instance)
		if instance.Name == "JumpButton" and instance:IsA("GuiObject") then
			for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
				instance:GetPropertyChangedSignal(property):Connect(applyLayout)
			end
			task.defer(applyLayout)
		end
	end
	local playerGui = ui.gui.Parent :: Instance
	playerGui.DescendantAdded:Connect(watchJumpButton)
	for _, descendant in playerGui:GetDescendants() do
		watchJumpButton(descendant)
	end
	refreshVisibility()
end

return AbilityController
