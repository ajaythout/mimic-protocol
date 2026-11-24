--!strict
--[[
	CameraController
	The Security Office camera terminal. Triggering its VIEW CAMERAS prompt
	switches this client's view to the facility's security cameras (the
	SecurityCamera props). Cycle feeds with Q/E, the arrow keys, the D-pad or
	the on-screen arrows; leave with Backspace, ButtonB or the X button.
	Walking away from the console, leaving the facility or the round moving
	on also leaves the feed. While the cameras are sabotaged
	(RoundState.CamerasOnline == false) every feed shows NO SIGNAL.

	All of this is local presentation: camera positions are public map data
	and the feed shows only what is already replicated to this client.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local CameraController = {}

local ACTION = "CameraFeed"
local localPlayer = Players.LocalPlayer

type Feed = { cframe: CFrame, label: string }

local feeds: { Feed } = {}
local viewing = false
local index = 1
local console: BasePart? = nil
local saved = { cameraType = Enum.CameraType.Custom, fieldOfView = 70 }

local ui = {} :: {
	gui: ScreenGui,
	label: TextLabel,
	noSignal: Frame,
}

local function roomName(position: Vector3): string
	for _, zone in CollectionService:GetTagged("RoomZone") do
		if zone:IsA("BasePart") then
			local relative = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size * 0.5
			if
				math.abs(relative.X) <= half.X
				and math.abs(relative.Y) <= half.Y
				and math.abs(relative.Z) <= half.Z
			then
				local name = zone:GetAttribute("DisplayName")
				return if type(name) == "string" then name else zone.Name
			end
		end
	end
	return "CORRIDOR"
end

local function collectFeeds()
	table.clear(feeds)
	local facility = Workspace:FindFirstChild("Facility")
	local props = facility and facility:FindFirstChild("Props")
	if not props then
		return
	end
	for _, model in props:GetChildren() do
		if model:IsA("Model") and model.Name == "SecurityCamera" then
			-- Just in front of the lens, looking where the camera looks.
			local cframe = model:GetPivot() * CFrame.new(0, -0.35, -1.8)
			table.insert(feeds, { cframe = cframe, label = roomName(cframe.Position) })
		end
	end
	table.sort(feeds, function(a, b)
		return a.label < b.label
	end)
end

local function show()
	local camera = Workspace.CurrentCamera
	local feed = feeds[index]
	if not camera or not feed then
		return
	end
	camera.CFrame = feed.cframe
	ui.label.Text = string.format("CAM %02d  %s", index, feed.label)
	ui.noSignal.Visible = StateController.getPublic("CamerasOnline") == false
end

function CameraController.close()
	if not viewing then
		return
	end
	viewing = false
	ContextActionService:UnbindAction(ACTION)
	ProximityPromptService.Enabled = true
	ui.gui.Enabled = false
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = saved.cameraType
		camera.FieldOfView = saved.fieldOfView
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function step(delta: number)
	if #feeds == 0 then
		return
	end
	index = ((index - 1 + delta) % #feeds) + 1
	show()
end

local function onAction(
	_: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Q or key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then
		step(-1)
	elseif key == Enum.KeyCode.E or key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then
		step(1)
	elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
		CameraController.close()
	end
	return Enum.ContextActionResult.Sink
end

function CameraController.open(anchor: BasePart)
	if viewing or not StateController.isAlive() then
		return
	end
	collectFeeds()
	if #feeds == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	viewing = true
	console = anchor
	saved.cameraType = camera.CameraType
	saved.fieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 75
	ui.gui.Enabled = true
	-- Prompts also listen for E; hide them so E cycles the feed.
	ProximityPromptService.Enabled = false
	ContextActionService:BindAction(
		ACTION,
		onAction,
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Backspace,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.ButtonB
	)
	show()
end

function CameraController.isViewing(): boolean
	return viewing
end

local function build()
	local gui = Components.screen("CameraFeed", Theme.Layers.Hud + 3, true)
	gui.Enabled = false
	ui.gui = gui

	local bar = Components.panel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(420, 44),
		Parent = gui,
	})
	ui.label = Components.label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		Text = "",
		Parent = bar,
	}, "Mono")

	local controls = Components.create("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(300, 48),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Components.list(controls, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	local function control(name: string, text: string, order: number, fn: () -> ())
		local button = Components.button({
			Name = name,
			Size = UDim2.fromOffset(88, 48),
			Text = text,
			LayoutOrder = order,
			Parent = controls,
		})
		button.Activated:Connect(fn)
	end
	control("Previous", "◀  Q", 1, function()
		step(-1)
	end)
	control("Exit", "EXIT", 2, CameraController.close)
	control("Next", "E  ▶", 3, function()
		step(1)
	end)

	ui.noSignal = Components.create("Frame", {
		Name = "NoSignal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	Components.label({
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 28,
		TextColor3 = Theme.Colors.Red,
		Text = "NO SIGNAL",
		Parent = ui.noSignal,
	}, "MonoBold")
end

local function watchTerminal(anchor: Instance)
	if not anchor:IsA("BasePart") then
		return
	end
	local prompt = anchor:WaitForChild("CameraPrompt", 15)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			if player == localPlayer then
				CameraController.open(anchor)
			end
		end)
	end
end

function CameraController.Start()
	build()
	for _, anchor in CollectionService:GetTagged("CameraTerminal") do
		task.spawn(watchTerminal, anchor)
	end
	CollectionService:GetInstanceAddedSignal("CameraTerminal"):Connect(function(anchor)
		task.spawn(watchTerminal, anchor)
	end)
	StateController.Tick:Connect(function()
		if not viewing then
			return
		end
		local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
		local anchor = console
		local tooFar = not root
			or not root:IsA("BasePart")
			or not anchor
			or (root.Position - anchor.Position).Magnitude > GameConfig.Cameras.Range + 2
		if tooFar or not StateController.isAlive() or not Phases.InFacility[StateController.getPhase()] then
			CameraController.close()
			return
		end
		ui.noSignal.Visible = StateController.getPublic("CamerasOnline") == false
	end)
	StateController.StatusChanged:Connect(function()
		if not StateController.isAlive() then
			CameraController.close()
		end
	end)
end

return CameraController
