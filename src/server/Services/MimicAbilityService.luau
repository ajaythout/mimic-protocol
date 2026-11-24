--!strict
--[[
	MimicAbilityService
	Mimic disguise abilities, requested with RequestAbility(ability, target?).

	OBJECT SHIFT  RequestAbility("ObjectShift", prop?)
	  `prop` is the placed MimicProp the client is aiming at. It is only a
	  hint: without one (or with an invalid one) the server picks the nearest
	  valid prop in range. Sending the request while disguised reverts.
	  Validation: active Mimic, hostile phase, off cooldown, rate limit; the
	  prop is tagged MimicProp, lives under Workspace.Facility, is in range,
	  and its PropId has a Transformable template in Assets.Props.
	  Effect: every character part and decal goes invisible, the name plate
	  hides, a clone of the template is welded at the feet, and movement
	  slows. The disguise drops when the Mimic asks, after MaxDuration, when
	  they land an assimilation, and at round end; death or a respawn simply
	  discards it with the old character.

	Every state change is mirrored to the Mimic with an AbilityState message.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local RateLimiter = require(Shared.Util.RateLimiter)

local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local MimicAbilityService = {}

local SHIFT = Net.Abilities.ObjectShift
local PROP_TAG = "MimicProp"
local DISGUISE_NAME = "Disguise"

type Shift = {
	character: Model,
	humanoid: Humanoid,
	disguise: Model,
	propId: string,
	endsAt: number,
	-- Original transparency of every part/decal we hid.
	hidden: { [Instance]: number },
	walkSpeed: number,
	jumpHeight: number,
	displayType: Enum.HumanoidDisplayDistanceType,
	connections: { RBXScriptConnection },
}

local limiter = RateLimiter.new(
	GameConfig.RateLimits.RequestAbility.Capacity,
	GameConfig.RateLimits.RequestAbility.RefillPerSecond
)
local shifts: { [Player]: Shift } = {}
local readyAt: { [Player]: number } = {}

local abilityRemote: RemoteEvent
local templates: Instance? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(player: Player, result: string?, detail: string?)
	if player.Parent ~= Players then
		return
	end
	local shift = shifts[player]
	local payload: Net.AbilityStatePayload = {
		ability = SHIFT,
		readyAt = readyAt[player] or 0,
		cooldown = GameConfig.ObjectShift.Cooldown,
		result = result,
		activeUntil = if shift then shift.endsAt else nil,
		detail = detail,
	}
	abilityRemote:FireClient(player, payload)
end

local function template(propId: string): Model?
	local folder = templates
	local found = folder and folder:FindFirstChild(propId)
	if found and found:IsA("Model") and found:GetAttribute("Transformable") == true then
		return found
	end
	return nil
end

-- A placed, transformable prop in the facility within range of `origin`.
local function isValidProp(instance: Instance, origin: Vector3): boolean
	if not instance:IsA("Model") or not instance:HasTag(PROP_TAG) then
		return false
	end
	local facility = Workspace:FindFirstChild("Facility")
	if not facility or not instance:IsDescendantOf(facility) then
		return false
	end
	local propId = instance:GetAttribute("PropId")
	if type(propId) ~= "string" or template(propId) == nil then
		return false
	end
	return (instance:GetPivot().Position - origin).Magnitude <= GameConfig.ObjectShift.Range
end

local function nearestProp(origin: Vector3): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(PROP_TAG) do
		if isValidProp(instance, origin) then
			local distance = ((instance :: Model):GetPivot().Position - origin).Magnitude
			if distance < bestDistance then
				best = instance :: Model
				bestDistance = distance
			end
		end
	end
	return best
end

local function hide(shift: Shift, instance: Instance)
	if shift.hidden[instance] ~= nil or instance:IsDescendantOf(shift.disguise) then
		return
	end
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		local item = instance :: any -- both classes have Transparency
		shift.hidden[instance] = item.Transparency
		item.Transparency = 1
	end
end

-- Builds the disguise model and welds it so its floor origin sits at the feet.
local function buildDisguise(source: Model, root: BasePart, humanoid: Humanoid): Model
	local propId = source:GetAttribute("PropId") :: string
	local base = template(propId) :: Model
	local disguise = base:Clone()
	disguise.Name = DISGUISE_NAME
	for _, descendant in disguise:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + legs, 0)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	-- Templates are built around a floor-level origin at the world origin, so
	-- their pivot is already expressed relative to that origin.
	disguise:PivotTo(CFrame.lookAt(feet, feet + look) * base:GetPivot())

	for _, descendant in disguise:GetDescendants() do
		if descendant:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	return disguise
end

--[[
	Ends a disguise. `restore` puts the character back the way it was; it is
	false when the character is dead or being replaced anyway.
]]
local function endShift(player: Player, restore: boolean, result: string?)
	local shift = shifts[player]
	if not shift then
		return
	end
	shifts[player] = nil
	for _, connection in shift.connections do
		connection:Disconnect()
	end
	if restore then
		for instance, transparency in shift.hidden do
			if instance.Parent then
				(instance :: any).Transparency = transparency
			end
		end
		shift.humanoid.WalkSpeed = shift.walkSpeed
		shift.humanoid.JumpHeight = shift.jumpHeight
		shift.humanoid.DisplayDistanceType = shift.displayType
	end
	shift.disguise:Destroy()
	readyAt[player] = now() + GameConfig.ObjectShift.Cooldown
	send(player, result)
end

local function startShift(player: Player, prop: Model)
	local character = player.Character
	local root = CharacterService.getRoot(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end

	local disguise = buildDisguise(prop, root, humanoid)
	local shift: Shift = {
		character = character,
		humanoid = humanoid,
		disguise = disguise,
		propId = prop:GetAttribute("PropId") :: string,
		endsAt = now() + GameConfig.ObjectShift.MaxDuration,
		hidden = {},
		walkSpeed = humanoid.WalkSpeed,
		jumpHeight = humanoid.JumpHeight,
		displayType = humanoid.DisplayDistanceType,
		connections = {},
	}
	shifts[player] = shift

	for _, descendant in character:GetDescendants() do
		hide(shift, descendant)
	end
	-- Accessories can still be streaming in; hide those as they arrive.
	table.insert(
		shift.connections,
		character.DescendantAdded:Connect(function(descendant)
			hide(shift, descendant)
		end)
	)
	disguise.Parent = character
	humanoid.WalkSpeed = GameConfig.ObjectShift.WalkSpeed
	humanoid.JumpHeight = GameConfig.ObjectShift.JumpHeight
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local endsAt = shift.endsAt
	task.delay(GameConfig.ObjectShift.MaxDuration, function()
		local current = shifts[player]
		if current == shift and current.endsAt == endsAt then
			endShift(player, true, "Expired")
		end
	end)

	send(player, "Shifted", prop:GetAttribute("DisplayName") :: string?)
end

local function onObjectShift(player: Player, target: unknown)
	if shifts[player] then
		endShift(player, true, "Reverted")
		return
	end
	local participant = MatchState.getActiveParticipant(player)
	if not participant or participant.role ~= "Mimic" then
		return
	end
	if not Phases.HostileAbilities[MatchState.getPhase()] then
		send(player, "Locked")
		return
	end
	if now() < (readyAt[player] or 0) then
		send(player, "Cooldown")
		return
	end
	local root = CharacterService.getRoot(player)
	if not root then
		return
	end

	local prop: Model? = nil
	if typeof(target) == "Instance" and isValidProp(target :: Instance, root.Position) then
		prop = target :: Model
	else
		prop = nearestProp(root.Position)
	end
	if not prop then
		send(player, "NoTarget")
		return
	end
	startShift(player, prop)
end

local function onRequest(player: Player, ability: unknown, target: unknown)
	if not limiter:consume(player) then
		return
	end
	if ability == SHIFT then
		onObjectShift(player, target)
	end
end

function MimicAbilityService.Init()
	abilityRemote = Net.event(Net.Names.AbilityState)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	templates = assets and assets:FindFirstChild("Props")
	if not templates then
		warn("[MimicAbilityService] ReplicatedStorage.Assets.Props is missing; Object Shift disabled")
	end

	Net.event(Net.Names.RequestAbility).OnServerEvent:Connect(onRequest)

	-- A new character (respawn, return to the bay) or a death means the old
	-- disguise went with the old character.
	CharacterService.Spawned:Connect(function(player: Player, character: Model)
		local shift = shifts[player]
		if shift and shift.character ~= character then
			endShift(player, false, nil)
		end
	end)
	CharacterService.Died:Connect(function(player: Player)
		endShift(player, false, nil)
	end)
	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		local shift = shifts[player]
		if shift then
			for _, connection in shift.connections do
				connection:Disconnect()
			end
			shifts[player] = nil
		end
		readyAt[player] = nil
		limiter:forget(player)
	end)
end

function MimicAbilityService.isShifted(player: Player): boolean
	return shifts[player] ~= nil
end

-- Drops any disguise this player is wearing (e.g. they just struck).
function MimicAbilityService.reveal(player: Player, result: string?)
	endShift(player, true, result)
end

-- Gives Mimics their initial cooldown state when abilities wake up.
function MimicAbilityService.primeCooldowns()
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		readyAt[mimic.player] = 0
		send(mimic.player, nil)
	end
end

-- Round over: drop every disguise and clear cooldowns.
function MimicAbilityService.reset()
	for player in shifts do
		endShift(player, true, nil)
	end
	table.clear(readyAt)
end

return MimicAbilityService
