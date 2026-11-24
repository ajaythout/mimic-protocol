--!strict
--[[
	GeneratorController
	World-space status for every repairable generator: a small billboard over
	its panel with the name, a progress bar and ONLINE once running. Reads
	only public generator attributes (Progress, Online) and the local
	player's Repairing attribute; repairs themselves go through the server's
	REPAIR prompt.

	While the local player is repairing a generator its prompt reads
	STOP REPAIR (a local-only text change; the server toggles either way).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)

local GeneratorController = {}

local TAG = "Generator"
local localPlayer = Players.LocalPlayer

type Entry = {
	model: Model,
	gui: BillboardGui,
	fill: Frame,
	status: TextLabel,
	prompt: ProximityPrompt?,
}

local entries: { [Instance]: Entry } = {}

local function refresh(entry: Entry)
	local progress = entry.model:GetAttribute("Progress")
	local online = entry.model:GetAttribute("Online") == true
	local fraction = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
	local mine = localPlayer:GetAttribute("Repairing") == entry.model:GetAttribute("GeneratorId")
	entry.fill.Size = UDim2.fromScale(if online then 1 else fraction, 1)
	entry.fill.BackgroundColor3 = if online then Theme.Colors.Teal else Theme.Colors.Cyan
	if online then
		entry.status.Text = "ONLINE"
		entry.status.TextColor3 = Theme.Colors.Teal
	else
		entry.status.Text = if mine
			then `REPAIRING  {math.floor(fraction * 100)}%`
			else `OFFLINE  {math.floor(fraction * 100)}%`
		entry.status.TextColor3 = if mine then Theme.Colors.Cyan else Theme.Colors.RedSoft
	end
	local prompt = entry.prompt
	if prompt then
		prompt.ActionText = if mine then "STOP REPAIR" else "REPAIR"
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local panel = model:WaitForChild("Panel", 10)
	if not panel or not panel:IsA("BasePart") then
		return
	end

	local gui = Components.create("BillboardGui", {
		Name = "GeneratorStatus",
		Adornee = panel,
		Size = UDim2.fromOffset(150, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0),
		MaxDistance = 45,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local name = model:GetAttribute("DisplayName")
	Components.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Caption,
		Text = if type(name) == "string" then name else "GENERATOR",
		Parent = gui,
	}, "Display")
	local track, fill = Components.progress({
		Name = "Progress",
		Position = UDim2.fromOffset(10, 19),
		Size = UDim2.new(1, -20, 0, 5),
		Parent = gui,
	})
	track.Name = "Progress"
	local status = Components.label({
		Name = "Status",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Caption,
		Text = "",
		Parent = gui,
	}, "Mono")

	local prompt = panel:FindFirstChild("RepairPrompt")
	local entry: Entry = {
		model = model,
		gui = gui,
		fill = fill,
		status = status,
		prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
	}
	entries[model] = entry
	for _, attribute in { "Progress", "Online" } do
		model:GetAttributeChangedSignal(attribute):Connect(function()
			refresh(entry)
		end)
	end
	panel.ChildAdded:Connect(function(child)
		if child.Name == "RepairPrompt" and child:IsA("ProximityPrompt") then
			entry.prompt = child
			refresh(entry)
		end
	end)
	refresh(entry)
end

function GeneratorController.Start()
	for _, model in CollectionService:GetTagged(TAG) do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
		task.spawn(track, model)
	end)
	localPlayer:GetAttributeChangedSignal("Repairing"):Connect(function()
		for _, entry in entries do
			refresh(entry)
		end
	end)
end

return GeneratorController
