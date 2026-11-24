--!strict
--[[
	GeneratorService
	The survivors' power objective. Generators (models tagged "Generator"
	under Workspace.Facility) are repaired at their Panel through a REPAIR
	prompt. GameConfig.Generators.Required of them must be online before the
	extraction lift can open (RoundService decides when to open it).

	Repairing
	  Triggering the prompt starts repairing that generator. Triggering it
	  again, walking out of Range, dying, leaving the round or the round
	  ending stops it. A loop runs only while someone is repairing; each
	  generator gains min(survivors on it, MaxRepairers) / RepairSeconds of
	  progress per second.
	  Mimics can "repair" too. It looks identical (the public Repairing
	  attribute is set the same way) but adds nothing, so a progress bar that
	  never moves is how survivors catch them.

	Public state (none of it reveals a role)
	  Generator model attributes: Progress (0..1), Online (boolean)
	  Player attribute Repairing: the GeneratorId being worked on
	  RoundState: GeneratorsOnline, GeneratorsRequired, PowerRestored

	Sabotage hooks: setback(model, fraction) knocks progress back on a
	generator that is still offline.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Phases = require(Shared.Modules.Phases)
local Signal = require(Shared.Util.Signal)

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local GeneratorService = {}

GeneratorService.PowerRestored = Signal.new() -- ()
GeneratorService.Changed = Signal.new() -- (model) progress or online state changed

export type Generator = {
	model: Model,
	panel: BasePart,
	status: BasePart?,
	core: BasePart?,
	light: Light?,
	prompt: ProximityPrompt,
	id: string,
	name: string,
	progress: number,
	online: boolean,
}

local TAG = "Generator"
local OFFLINE_COLOR = Color3.fromRGB(255, 70, 70)
local ONLINE_COLOR = Color3.fromRGB(80, 230, 255)
local CORE_OFF_COLOR = Color3.fromRGB(40, 46, 54)

local generators: { Generator } = {}
local byModel: { [Instance]: Generator } = {}
local repairing: { [Player]: Generator } = {}
local powered = false
local loopRunning = false

local function required(): number
	return math.min(GameConfig.Generators.Required, #generators)
end

local function onlineCount(): number
	local count = 0
	for _, generator in generators do
		if generator.online then
			count += 1
		end
	end
	return count
end

local function publish()
	MatchState.setPublic("GeneratorsOnline", onlineCount())
	MatchState.setPublic("GeneratorsRequired", required())
	MatchState.setPublic("PowerRestored", powered)
end

local function present(generator: Generator)
	generator.model:SetAttribute("Progress", math.floor(generator.progress * 1000 + 0.5) / 1000)
	generator.model:SetAttribute("Online", generator.online)
	generator.prompt.Enabled = not generator.online
	if generator.status then
		generator.status.Color = if generator.online then ONLINE_COLOR else OFFLINE_COLOR
	end
	if generator.core then
		-- A dark core while offline, so only running generators glow.
		generator.core.Color = if generator.online then ONLINE_COLOR else CORE_OFF_COLOR
		generator.core.Material = if generator.online then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if generator.light then
		generator.light.Enabled = generator.online
	end
	GeneratorService.Changed:Fire(generator.model)
end

local function stopRepair(player: Player)
	if repairing[player] then
		repairing[player] = nil
		if player.Parent then
			player:SetAttribute("Repairing", nil)
		end
	end
end

local function setOnline(generator: Generator)
	if generator.online then
		return
	end
	generator.online = true
	generator.progress = 1
	for player, target in repairing do
		if target == generator then
			stopRepair(player)
		end
	end
	present(generator)
	local count, need = onlineCount(), required()
	Announcer.all(
		`{generator.name} ONLINE`,
		`{math.min(count, need)} of {need} generators running.`,
		"Success",
		4
	)
	if not powered and count >= need then
		powered = true
		publish()
		Announcer.all("POWER RESTORED", "The extraction lift has power again.", "Success", 6)
		GeneratorService.PowerRestored:Fire()
	else
		publish()
	end
end

local function inRange(player: Player, generator: Generator): boolean
	local root = CharacterService.getRoot(player)
	-- A little slack over the prompt distance so standing at its edge works.
	return root ~= nil
		and (root.Position - generator.panel.Position).Magnitude <= GameConfig.Generators.Range + 1
end

local function step(dt: number)
	local working: { [Generator]: number } = {}
	local drop: { Player } = {}
	local canRepair = Phases.InFacility[MatchState.getPhase()] == true
	for player, generator in repairing do
		local participant = MatchState.getActiveParticipant(player)
		if not canRepair or not participant or generator.online or not inRange(player, generator) then
			table.insert(drop, player)
		elseif participant.role == "Survivor" then
			working[generator] = (working[generator] or 0) + 1
		end
	end
	for _, player in drop do
		stopRepair(player)
	end
	for generator, hands in working do
		local rate = math.min(hands, GameConfig.Generators.MaxRepairers) / GameConfig.Generators.RepairSeconds
		generator.progress = math.min(1, generator.progress + dt * rate)
		if generator.progress >= 1 then
			setOnline(generator)
		else
			present(generator)
		end
	end
end

local function ensureLoop()
	if loopRunning then
		return
	end
	loopRunning = true
	task.spawn(function()
		local last = os.clock()
		while next(repairing) ~= nil do
			task.wait(GameConfig.Generators.TickInterval)
			local clock = os.clock()
			step(clock - last)
			last = clock
		end
		loopRunning = false
	end)
end

local function onTriggered(player: Player, generator: Generator)
	if repairing[player] == generator then
		stopRepair(player)
		return
	end
	if not Phases.InFacility[MatchState.getPhase()] or generator.online then
		return
	end
	if not MatchState.getActiveParticipant(player) or not inRange(player, generator) then
		return
	end
	stopRepair(player)
	repairing[player] = generator
	player:SetAttribute("Repairing", generator.id)
	ensureLoop()
end

local function register(model: Instance)
	if not model:IsA("Model") or byModel[model] then
		return
	end
	local facility = Workspace:FindFirstChild("Facility")
	if not facility or not model:IsDescendantOf(facility) then
		return
	end
	local panel = model:FindFirstChild("Panel")
	if not panel or not panel:IsA("BasePart") then
		warn(`[GeneratorService] {model:GetFullName()} has no Panel part; skipped`)
		return
	end
	local status = model:FindFirstChild("Status")
	local core = model:FindFirstChild("Core")
	local light = core and core:FindFirstChildWhichIsA("Light")
	local id = model:GetAttribute("GeneratorId")
	local name = model:GetAttribute("DisplayName")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RepairPrompt"
	prompt.ActionText = "REPAIR"
	prompt.ObjectText = if type(name) == "string" then name else "GENERATOR"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.Generators.Range
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- ButtonX/ButtonY/ButtonB are Mimic abilities; keep prompts off them.
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonL1
	prompt.Parent = panel

	local generator: Generator = {
		model = model,
		panel = panel,
		status = if status and status:IsA("BasePart") then status else nil,
		core = if core and core:IsA("BasePart") then core else nil,
		light = light,
		prompt = prompt,
		id = if type(id) == "string" then id else model:GetFullName(),
		name = prompt.ObjectText,
		progress = 0,
		online = false,
	}
	prompt.Triggered:Connect(function(player: Player)
		onTriggered(player, generator)
	end)
	table.insert(generators, generator)
	byModel[model] = generator
	present(generator)
end

function GeneratorService.Init()
	for _, model in CollectionService:GetTagged(TAG) do
		register(model)
	end
	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		repairing[player] = nil
	end)
	CharacterService.Died:Connect(function(player: Player)
		stopRepair(player)
	end)
	GeneratorService.reset()
end

function GeneratorService.isPowered(): boolean
	return powered
end

function GeneratorService.getGenerator(model: Instance): Generator?
	return byModel[model]
end

function GeneratorService.getGenerators(): { Generator }
	return generators
end

-- Knocks progress back on an offline generator. Returns true if it changed.
function GeneratorService.setback(model: Instance, fraction: number): boolean
	local generator = byModel[model]
	if not generator or generator.online or generator.progress <= 0 then
		return false
	end
	generator.progress = math.max(0, generator.progress - fraction)
	present(generator)
	return true
end

-- Every generator offline again; nobody repairing.
function GeneratorService.reset()
	for player in repairing do
		stopRepair(player)
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Repairing") ~= nil then
			player:SetAttribute("Repairing", nil)
		end
	end
	for _, generator in generators do
		generator.progress = 0
		generator.online = false
		present(generator)
	end
	powered = required() <= 0
	publish()
end

return GeneratorService
