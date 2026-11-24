--!strict
--[[
	CharacterService
	Owns every character spawn. Players.CharacterAutoLoads is disabled so the
	round system decides where (and whether) a player respawns.

	• spawnInLobby(player)          LoadCharacterAsync + place on a bay pad
	• deployTo(player, cframe)      move a living character, or spawn if needed
	• setDeathHandler(fn)           single synchronous hook run on any death,
	                                before the respawn policy reads Status
	• Died signal                   (player, character) for listeners/effects

	Respawn policy after a death: anyone whose Status is not "Alive" returns to
	the Deployment Bay after a delay. "Alive" players are round participants;
	the death handler (EliminationService) converts them to Eliminated first.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)

local PlayerRegistry = require(script.Parent.PlayerRegistry)

local CharacterService = {}

CharacterService.Died = Signal.new() -- (player, character)
CharacterService.Spawned = Signal.new() -- (player, character)

local LOBBY_TAG = "LobbySpawn"
local FACILITY_TAG = "FacilitySpawn"

local spawnTokens: { [Player]: number } = {}
local stunnedUntil: { [Player]: number } = {}
local pendingRespawns: { [Player]: thread } = {}
local deathHandler: ((Player, Model) -> ())? = nil
local random = Random.new()

local function cancelPendingRespawn(player: Player)
	local thread = pendingRespawns[player]
	if thread then
		pendingRespawns[player] = nil
		if coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	end
end

local function configureHumanoid(humanoid: Humanoid)
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.NameDisplayDistance = GameConfig.Characters.NameDisplayDistance
	humanoid.WalkSpeed = GameConfig.Characters.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = GameConfig.Characters.JumpHeight
end

local function scheduleLobbyRespawn(player: Player)
	local status = PlayerRegistry.getStatus(player)
	if status == nil or status == "Alive" then
		return
	end
	cancelPendingRespawn(player)
	local delay = if status == "Eliminated"
		then GameConfig.Characters.EliminatedReturnDelay
		else GameConfig.Characters.LobbyRespawnDelay
	pendingRespawns[player] = task.delay(delay, function()
		pendingRespawns[player] = nil
		if player.Parent == Players and PlayerRegistry.getStatus(player) ~= "Alive" then
			CharacterService.spawnInLobby(player)
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(`[CharacterService] {player.Name}'s character has no Humanoid`)
		return
	end
	configureHumanoid(humanoid)
	CharacterService.Spawned:Fire(player, character)

	humanoid.Died:Once(function()
		if player.Character ~= character then
			return
		end
		local handler = deathHandler
		if handler then
			local ok, err = pcall(handler :: any, player, character)
			if not ok then
				warn("[CharacterService] death handler error:", err)
			end
		end
		CharacterService.Died:Fire(player, character)
		scheduleLobbyRespawn(player)
	end)
end

function CharacterService.Init()
	Players.CharacterAutoLoads = false

	PlayerRegistry.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		CharacterService.spawnInLobby(player)
	end)

	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		cancelPendingRespawn(player)
		spawnTokens[player] = nil
		stunnedUntil[player] = nil
	end)
end

function CharacterService.setDeathHandler(handler: (Player, Model) -> ())
	deathHandler = handler
end

local function pickTagged(tag: string): BasePart?
	local candidates = CollectionService:GetTagged(tag)
	if #candidates == 0 then
		return nil
	end
	local chosen = candidates[random:NextInteger(1, #candidates)]
	return if chosen:IsA("BasePart") then chosen else nil
end

function CharacterService.getFacilitySpawns(): { BasePart }
	local list = {}
	for _, instance in CollectionService:GetTagged(FACILITY_TAG) do
		if instance:IsA("BasePart") then
			table.insert(list, instance)
		end
	end
	return list
end

--[[
	Loads a fresh character and places it at `cframe` (the HumanoidRootPart
	position). Superseded calls (a newer spawn started while this one yielded)
	return nil without moving anything.
]]
function CharacterService.spawnAt(player: Player, cframe: CFrame): Model?
	cancelPendingRespawn(player)
	local token = (spawnTokens[player] or 0) + 1
	spawnTokens[player] = token

	local ok, err = pcall(function(): ()
		player:LoadCharacterAsync()
	end :: any)
	if not ok then
		warn(`[CharacterService] LoadCharacterAsync failed for {player.Name}: {err}`)
		return nil
	end
	if spawnTokens[player] ~= token or player.Parent ~= Players then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end
	character:WaitForChild("HumanoidRootPart", 5)
	if spawnTokens[player] ~= token then
		return nil
	end
	character:PivotTo(cframe)
	return character
end

function CharacterService.spawnInLobby(player: Player): Model?
	local pad = pickTagged(LOBBY_TAG)
	local target = if pad then pad.CFrame else CFrame.new(0, 10, 0)
	return CharacterService.spawnAt(player, target)
end

-- Moves a living character without reloading it; spawns one otherwise.
function CharacterService.deployTo(player: Player, cframe: CFrame): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
		cancelPendingRespawn(player)
		spawnTokens[player] = (spawnTokens[player] or 0) + 1
		configureHumanoid(humanoid)
		character:PivotTo(cframe)
		return character
	end
	return CharacterService.spawnAt(player, cframe)
end

--[[
	True when nothing but characters lies between two points. Characters
	(including anything welded into them, like a disguise) never block, so
	walls, doors and props are what count.
]]
function CharacterService.hasLineOfSight(from: Vector3, to: Vector3): boolean
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters
	params.IgnoreWater = true
	return Workspace:Raycast(from, to - from, params) == nil
end

--[[
	Freezes a living character for `seconds` (no walking or jumping). Ability
	services refuse requests while isStunned is true. A respawn clears it.
]]
function CharacterService.stun(player: Player, seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local untilTime = os.clock() + seconds
	stunnedUntil[player] = untilTime
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	task.delay(seconds, function()
		if stunnedUntil[player] ~= untilTime then
			return
		end
		stunnedUntil[player] = nil
		if player.Character == character and humanoid.Health > 0 then
			humanoid.WalkSpeed = GameConfig.Characters.WalkSpeed
			humanoid.JumpHeight = GameConfig.Characters.JumpHeight
		end
	end)
end

function CharacterService.isStunned(player: Player): boolean
	local untilTime = stunnedUntil[player]
	return untilTime ~= nil and os.clock() < untilTime
end

function CharacterService.getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

return CharacterService
