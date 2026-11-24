--!strict
--[[
	AnnouncementController
	Stacked banners under the phase bar for server announcements. At most
	three are visible; older ones are dismissed early when new ones arrive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)

local AnnouncementController = {}

local MAX_VISIBLE = 3
local DEFAULT_DURATION = 4

local container: Frame
local active: { Frame } = {}
local order = 0

local function dismiss(banner: Frame)
	local index = table.find(active, banner)
	if not index then
		return
	end
	table.remove(active, index)
	-- Connect before playing so a zero-length tween still cleans up.
	local fade = TweenService:Create(banner, Theme.Motion.Medium, { BackgroundTransparency = 1 })
	fade.Completed:Once(function()
		banner:Destroy()
	end)
	for _, descendant in banner:GetDescendants() do
		if descendant:IsA("TextLabel") then
			Components.tween(descendant, Theme.Motion.Medium, { TextTransparency = 1 })
		elseif descendant:IsA("Frame") then
			Components.tween(descendant, Theme.Motion.Medium, { BackgroundTransparency = 1 })
		elseif descendant:IsA("UIStroke") then
			Components.tween(descendant, Theme.Motion.Medium, { Transparency = 1 })
		end
	end
	fade:Play()
end

function AnnouncementController.show(payload: Net.AnnouncementPayload)
	if type(payload.title) ~= "string" then
		return
	end
	order += 1
	local color = Theme.SeverityColors[payload.severity] or Theme.Colors.Cyan

	local banner = Components.panel({
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = container,
	}, { brackets = false, accent = color })
	Components.create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = banner,
	})
	local content = Components.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = banner,
	})
	Components.padding(content, 9, 16)
	Components.list(content, 3)
	Components.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Label,
		TextColor3 = color,
		TextWrapped = true,
		Text = payload.title,
		LayoutOrder = 1,
		Parent = content,
	}, "Display")
	if type(payload.body) == "string" and payload.body ~= "" then
		Components.label({
			Name = "Body",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Colors.Text,
			Text = payload.body,
			LayoutOrder = 2,
			Parent = content,
		}, "Body")
	end

	-- Entrance: slide in from slightly above.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = banner
	Components.tween(scale, Theme.Motion.Medium, { Scale = 1 })

	table.insert(active, banner)
	while #active > MAX_VISIBLE do
		dismiss(active[1])
	end

	local duration = tonumber(payload.duration) or DEFAULT_DURATION
	task.delay(math.clamp(duration, 1.5, 12), function()
		dismiss(banner)
	end)
end

function AnnouncementController.Start()
	local gui = Components.screen("Announcements", Theme.Layers.Announcements)
	container = Components.create("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 82),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Components.list(container, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)

	Net.event(Net.Names.Announcement).OnClientEvent:Connect(function(payload: Net.AnnouncementPayload)
		if type(payload) == "table" then
			AnnouncementController.show(payload)
		end
	end)
end

return AnnouncementController
