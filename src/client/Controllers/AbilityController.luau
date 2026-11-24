--!strict
--[[
	AbilityController
	Mimic ability bar. Phase 1 ships one ability, ASSIMILATE (the basic
	attack); Object Shift, Identity Theft and Sabotage slot into the same bar
	in Phase 2.

	Input: F (keyboard), ButtonX (gamepad), or tapping the on-screen button.
	The client only sends intent (RequestStrike, no arguments). The cooldown
	shown here comes from the server's AbilityState reply; nothing is trusted
	from local timing.
]]

local ContextActionService = game:GetService("ContextActionService")
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

local ACTION = "MimicAssimilate"
local PRESS_INTERVAL = 0.3
local EDGE_MARGIN = 24
local JUMP_GAP = 10

local strikeRemote: RemoteEvent
local readyAt = 0
local cooldownLength = 1
local lastPress = 0
local bound = false

local ui = {} :: {
	gui: ScreenGui,
	scale: UIScale,
	root: Frame,
	button: TextButton,
	overlay: Frame,
	countdown: TextLabel,
	keyHint: TextLabel,
	feedback: TextLabel,
	stroke: UIStroke,
}

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

local function request()
	local now = os.clock()
	if now - lastPress < PRESS_INTERVAL then
		return
	end
	lastPress = now
	if not hostilePhase() then
		showFeedback("ORGANISM DORMANT", Theme.Colors.TextMuted)
		return
	end
	if Workspace:GetServerTimeNow() < readyAt then
		showFeedback("RECHARGING", Theme.Colors.TextMuted)
		return
	end
	strikeRemote:FireServer()
end

local function onAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		request()
	end
	return Enum.ContextActionResult.Sink
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

--[[
	Bottom-right corner, stacked above the jump button when touch controls are
	up so a thumb never lands on both. The jump button's size and position
	depend on screen size, so measure it instead of guessing an offset.
]]
local function applyLayout()
	local touch = isTouchLayout()
	local size = if touch then 118 else 96
	ui.root.Size = UDim2.fromOffset(size, size + 26)
	ui.button.Size = UDim2.fromOffset(size, size)

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

local function shouldShow(): boolean
	return StateController.isAlive() and StateController.getRole() == "Mimic"
end

local function refreshVisibility()
	local show = shouldShow()
	ui.root.Visible = show
	if show then
		applyLayout() -- touch controls may have appeared since the last layout
	end
	if show and not bound then
		ContextActionService:BindAction(ACTION, onAction, false, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
		bound = true
	elseif not show and bound then
		ContextActionService:UnbindAction(ACTION)
		bound = false
	end
end

local function refreshCooldown()
	if not ui.root.Visible then
		return
	end
	if not hostilePhase() then
		ui.overlay.Size = UDim2.fromScale(1, 1)
		ui.countdown.Text = ""
		ui.keyHint.Text = "DORMANT"
		ui.stroke.Color = Theme.Colors.StrokeMuted
		return
	end
	local remaining = readyAt - Workspace:GetServerTimeNow()
	if remaining > 0 then
		ui.overlay.Size = UDim2.fromScale(1, math.clamp(remaining / cooldownLength, 0, 1))
		ui.countdown.Text = tostring(math.ceil(remaining))
		ui.stroke.Color = Theme.Colors.StrokeMuted
	else
		ui.overlay.Size = UDim2.fromScale(1, 0)
		ui.countdown.Text = ""
		ui.stroke.Color = Theme.Colors.Red
	end
	ui.keyHint.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "TAP"
		else "[F]"
end

local function build()
	local gui, scale = Components.screen("Abilities", Theme.Layers.Hud + 1)
	ui.gui = gui
	ui.scale = scale

	local root = Components.create("Frame", {
		Name = "AbilityBar",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.root = root

	local button, stroke = Components.button({
		Name = "Assimilate",
		Position = UDim2.fromOffset(0, 26),
		Text = "",
		ClipsDescendants = true,
		Parent = root,
	}, { accent = Theme.Colors.Red })
	ui.button = button
	ui.stroke = stroke
	stroke.Thickness = 2

	ui.overlay = Components.create("Frame", {
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
		TextScaled = false,
		TextColor3 = Theme.Colors.Red,
		Text = "ASSIMILATE",
		ZIndex = 3,
		Parent = button,
	}, "Display")
	ui.countdown = Components.label({
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
	ui.keyHint = Components.label({
		Name = "KeyHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -8, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "[F]",
		ZIndex = 3,
		Parent = button,
	}, "Mono")
	ui.feedback = Components.label({
		Name = "Feedback",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(240, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Theme.TextSize.Caption,
		TextTransparency = 1,
		Text = "",
		Parent = root,
	}, "Display")

	button.Activated:Connect(request)
	applyLayout()
end

function AbilityController.Start()
	strikeRemote = Net.event(Net.Names.RequestStrike)
	build()

	Net.event(Net.Names.AbilityState).OnClientEvent:Connect(function(payload: Net.AbilityStatePayload)
		if type(payload) ~= "table" or payload.ability ~= "Assimilate" then
			return
		end
		readyAt = tonumber(payload.readyAt) or 0
		cooldownLength = math.max(1, tonumber(payload.cooldown) or 1)
		if payload.result == "Hit" then
			showFeedback("ASSIMILATED", Theme.Colors.Red)
		elseif payload.result == "NoTarget" then
			showFeedback("NO SURVIVOR IN REACH", Theme.Colors.TextMuted)
		elseif payload.result == "Locked" then
			showFeedback("ORGANISM DORMANT", Theme.Colors.TextMuted)
		end
		refreshCooldown()
	end)

	StateController.RoleChanged:Connect(refreshVisibility)
	StateController.StatusChanged:Connect(refreshVisibility)
	StateController.PhaseChanged:Connect(refreshCooldown)
	StateController.Tick:Connect(refreshCooldown)
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
