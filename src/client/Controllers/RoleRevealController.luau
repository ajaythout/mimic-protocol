--!strict
--[[
	RoleRevealController
	Full-screen, private role reveal at the start of each round (and for a
	Survivor promoted to Mimic if the original Mimic disconnects early).

	Sequence: verification readout types in -> role title scales in ->
	briefing + team intel -> fades out as the RoleReveal phase ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local RoleRevealController = {}

local BRIEFING = {
	Survivor = "Expose the organism hiding in your crew, stay alive, and reach the extraction lift when it opens.",
	Mimic = "You are the organism. Blend in, assimilate the crew one by one, and stop them from reaching extraction.",
}

local ui = {} :: {
	gui: ScreenGui,
	overlay: Frame,
	scan: Frame,
	verify: TextLabel,
	youAre: TextLabel,
	role: TextLabel,
	roleScale: UIScale,
	briefing: TextLabel,
	intel: TextLabel,
}

local sequence = 0

local function build()
	local gui = Components.screen("RoleReveal", Theme.Layers.Reveal, true)
	gui.Enabled = false
	ui.gui = gui

	local overlay = Components.create("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 6, 9),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	ui.overlay = overlay

	local vignette = Components.create("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BorderSizePixel = 0,
		Parent = overlay,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	gradient.Rotation = 90
	gradient.Parent = vignette

	ui.scan = Components.create("Frame", {
		Name = "ScanBeam",
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Theme.Colors.Cyan,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = overlay,
	})

	local center = Components.create("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 360),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	ui.verify = Components.label({
		Name = "Verify",
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "",
		Parent = center,
	}, "Mono")
	ui.youAre = Components.label({
		Name = "YouAre",
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "YOU ARE A",
		Parent = center,
	}, "Display")
	ui.role = Components.label({
		Name = "Role",
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Hero,
		Text = "",
		Parent = center,
	}, "Display")
	ui.roleScale = Instance.new("UIScale")
	ui.roleScale.Parent = ui.role
	ui.briefing = Components.label({
		Name = "Briefing",
		Position = UDim2.fromOffset(60, 196),
		Size = UDim2.new(1, -120, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextSize = 18,
		Text = "",
		Parent = center,
	}, "Body")
	ui.intel = Components.label({
		Name = "Intel",
		Position = UDim2.fromOffset(0, 262),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		Text = "",
		Parent = center,
	}, "Display")
end

local function namesFor(userIds: { number }): string
	local names = {}
	for _, id in userIds do
		local player = Players:GetPlayerByUserId(id)
		table.insert(names, if player then player.DisplayName else "UNKNOWN")
	end
	return table.concat(names, ", ")
end

local function setTextTransparency(value: number)
	for _, label in { ui.youAre, ui.role, ui.briefing, ui.intel } do
		label.TextTransparency = value
	end
end

local function play(payload: Net.RoleRevealPayload)
	sequence += 1
	local token = sequence
	local role = payload.role
	local color = Theme.RoleColors[role] or Theme.Colors.Cyan

	ui.role.Text = string.upper(role)
	ui.role.TextColor3 = color
	ui.scan.BackgroundColor3 = color
	ui.briefing.Text = BRIEFING[role] or ""
	if role == "Mimic" then
		ui.intel.TextColor3 = Theme.Colors.Red
		ui.intel.Text = if #payload.teammates > 0
			then `FELLOW MIMICS: {string.upper(namesFor(payload.teammates))}`
			else "YOU ARE THE ONLY MIMIC"
	else
		ui.intel.TextColor3 = Theme.Colors.Cyan
		local plural = if payload.mimicCount == 1 then "MIMIC HIDES" else "MIMICS HIDE"
		ui.intel.Text = `{payload.mimicCount} {plural} AMONG {payload.playerCount} CREW`
	end

	ui.gui.Enabled = true
	setTextTransparency(1)
	ui.verify.Text = "> VERIFYING IDENTITY . . . SAMPLE ACCEPTED"
	ui.verify.MaxVisibleGraphemes = 0
	ui.overlay.BackgroundTransparency = 1
	ui.scan.Position = UDim2.fromScale(0, 0)
	Components.tween(ui.overlay, Theme.Motion.Medium, { BackgroundTransparency = Theme.Transparency.Overlay })
	Components.tween(ui.verify, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = 44 })
	Components.tween(ui.scan, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Position = UDim2.new(0, 0, 1, -2),
	})

	task.delay(1.0, function()
		if token ~= sequence then
			return
		end
		ui.roleScale.Scale = 1.35
		Components.tween(ui.roleScale, Theme.Motion.Slow, { Scale = 1 })
		for _, label in { ui.youAre, ui.role } do
			Components.tween(label, Theme.Motion.Medium, { TextTransparency = 0 })
		end
		task.delay(0.5, function()
			if token ~= sequence then
				return
			end
			for _, label in { ui.briefing, ui.intel } do
				Components.tween(label, Theme.Motion.Medium, { TextTransparency = 0 })
			end
		end)
	end)

	-- Hold until the reveal phase ends (or ~5s for a mid-round promotion).
	local hold = if StateController.getPhase() == Phases.RoleReveal
		then math.max(StateController.getTimeRemaining() - 0.4, 3.5)
		else 5
	task.delay(hold, function()
		if token ~= sequence then
			return
		end
		RoleRevealController.hide()
	end)
end

function RoleRevealController.hide()
	sequence += 1
	local token = sequence
	Components.tween(ui.overlay, Theme.Motion.Medium, { BackgroundTransparency = 1 })
	setTextTransparency(1)
	ui.verify.MaxVisibleGraphemes = 0
	task.delay(0.35, function()
		if token == sequence then
			ui.gui.Enabled = false
		end
	end)
end

function RoleRevealController.Start()
	build()
	StateController.Revealed:Connect(play)
	StateController.PhaseChanged:Connect(function(phase)
		-- Never leave the overlay up once players are past assignment.
		if
			ui.gui.Enabled
			and (phase == Phases.Active or phase == Phases.Results or phase == Phases.Intermission)
		then
			RoleRevealController.hide()
		end
	end)
end

return RoleRevealController
