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

	IDENTITY THEFT  RequestAbility("IdentityTheft")
	  Intent only: the server picks the nearest other active participant in
	  front, in range and in line of sight (Shared/Modules/Targeting). The
	  Mimic takes on that player's HumanoidDescription and Humanoid.DisplayName
	  for Duration, then gets their own back. The cooldown is claimed before
	  ApplyDescription yields. If the character dies, respawns or the round
	  ends while the new look is loading, nothing is left half-applied: a new
	  character loads the player's own avatar, and a surviving one is put
	  back. Sending the request again ends the impersonation early.

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
local Targeting = require(Shared.Modules.Targeting)

local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local MimicAbilityService = {}

local SHIFT = Net.Abilities.ObjectShift
local THEFT = Net.Abilities.IdentityTheft
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
type Theft = {
	character: Model,
	humanoid: Humanoid,
	original: HumanoidDescription,
	displayName: string,
	endsAt: number,
}

local shifts: { [Player]: Shift } = {}
local readyAt: { [Player]: number } = {}
local thefts: { [Player]: Theft } = {}
local theftReadyAt: { [Player]: number } = {}
local theftPending: { [Player]: boolean } = {}

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

local function sendTheft(player: Player, result: string?, detail: string?)
	if player.Parent ~= Players then
		return
	end
	local theft = thefts[player]
	local payload: Net.AbilityStatePayload = {
		ability = THEFT,
		readyAt = theftReadyAt[player] or 0,
		cooldown = GameConfig.IdentityTheft.Cooldown,
		result = result,
		activeUntil = if theft then theft.endsAt else nil,
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
	if CharacterService.isStunned(player) then
		send(player, "Stunned")
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

-- Identity Theft --------------------------------------------------------------

local function applyDescription(humanoid: Humanoid, description: HumanoidDescription): boolean
	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not ok then
		warn(`[MimicAbilityService] ApplyDescription failed: {err}`)
	end
	return ok
end

local function endTheft(player: Player, restore: boolean, result: string?)
	local theft = thefts[player]
	if not theft then
		return
	end
	thefts[player] = nil
	local alive = player.Character == theft.character and theft.humanoid.Health > 0
	if restore and alive then
		theft.humanoid.DisplayName = theft.displayName
		task.spawn(applyDescription, theft.humanoid, theft.original)
	end
	sendTheft(player, result)
end

local function pickVictim(player: Player, root: BasePart): MatchState.Participant?
	local round = MatchState.getRound()
	if not round then
		return nil
	end
	local candidates: { Targeting.Candidate<MatchState.Participant> } = {}
	for _, participant in round.roster do
		if participant.player ~= player and participant.fate == "Active" then
			local targetRoot = CharacterService.getRoot(participant.player)
			if targetRoot then
				table.insert(candidates, { position = targetRoot.Position, item = participant })
			end
		end
	end
	return Targeting.pick(
		root.Position,
		root.CFrame.LookVector,
		candidates,
		GameConfig.IdentityTheft,
		CharacterService.hasLineOfSight
	)
end

local function onIdentityTheft(player: Player)
	if thefts[player] then
		endTheft(player, true, "Restored")
		return
	end
	if theftPending[player] then
		return
	end
	local participant = MatchState.getActiveParticipant(player)
	if not participant or participant.role ~= "Mimic" then
		return
	end
	if not Phases.HostileAbilities[MatchState.getPhase()] then
		sendTheft(player, "Locked")
		return
	end
	if CharacterService.isStunned(player) then
		sendTheft(player, "Stunned")
		return
	end
	if now() < (theftReadyAt[player] or 0) then
		sendTheft(player, "Cooldown")
		return
	end
	local character = player.Character
	local root = CharacterService.getRoot(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	local victim = pickVictim(player, root)
	local victimCharacter = victim and victim.player.Character
	local victimHumanoid = victimCharacter and victimCharacter:FindFirstChildOfClass("Humanoid")
	if not victim or not victimHumanoid then
		sendTheft(player, "NoTarget")
		return
	end

	local okOriginal, original = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	local okStolen, stolen = pcall(function()
		return victimHumanoid:GetAppliedDescription()
	end)
	if not okOriginal or not okStolen then
		sendTheft(player, "Failed")
		return
	end

	-- Claim the cooldown before ApplyDescription yields.
	theftReadyAt[player] = now() + GameConfig.IdentityTheft.Cooldown
	theftPending[player] = true
	-- Changing shape drops a prop disguise.
	endShift(player, true, "Reverted")
	local round = MatchState.getRound()
	local applied = applyDescription(humanoid, stolen)
	theftPending[player] = nil

	local stillValid = player.Parent == Players
		and player.Character == character
		and humanoid.Health > 0
		and MatchState.getRound() == round
		and MatchState.getActiveParticipant(player) == participant
	if not stillValid then
		-- The round ended or the character changed while the look loaded. A new
		-- character already has the player's own avatar; a surviving one is put back.
		if applied and player.Character == character and humanoid.Health > 0 then
			task.spawn(applyDescription, humanoid, original)
		end
		return
	end
	if not applied then
		sendTheft(player, "Failed")
		return
	end

	local theft: Theft = {
		character = character,
		humanoid = humanoid,
		original = original,
		displayName = humanoid.DisplayName,
		endsAt = now() + GameConfig.IdentityTheft.Duration,
	}
	thefts[player] = theft
	humanoid.DisplayName = victim.player.DisplayName
	task.delay(GameConfig.IdentityTheft.Duration, function()
		if thefts[player] == theft then
			endTheft(player, true, "Expired")
		end
	end)
	sendTheft(player, "Copied", victim.player.DisplayName)
end

local function onRequest(player: Player, ability: unknown, target: unknown)
	if not limiter:consume(player) then
		return
	end
	if ability == SHIFT then
		onObjectShift(player, target)
	elseif ability == THEFT then
		onIdentityTheft(player)
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
		local theft = thefts[player]
		if theft and theft.character ~= character then
			endTheft(player, false, nil)
		end
	end)
	CharacterService.Died:Connect(function(player: Player)
		endShift(player, false, nil)
		endTheft(player, false, nil)
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
		thefts[player] = nil
		theftReadyAt[player] = nil
		theftPending[player] = nil
		limiter:forget(player)
	end)
end

function MimicAbilityService.isShifted(player: Player): boolean
	return shifts[player] ~= nil
end

function MimicAbilityService.isImpersonating(player: Player): boolean
	return thefts[player] ~= nil
end

-- Drops the prop disguise this player is wearing (e.g. they just struck).
function MimicAbilityService.reveal(player: Player, result: string?)
	endShift(player, true, result)
end

-- Drops every disguise, prop and identity (e.g. a scanner exposed them).
function MimicAbilityService.unmask(player: Player, result: string?)
	endShift(player, true, result)
	endTheft(player, true, result)
end

-- Gives Mimics their initial cooldown state when abilities wake up.
function MimicAbilityService.primeCooldowns()
	for _, mimic in MatchState.getActiveByRole("Mimic") do
		readyAt[mimic.player] = 0
		theftReadyAt[mimic.player] = 0
		send(mimic.player, nil)
		sendTheft(mimic.player, nil)
	end
end

-- Round over: drop every disguise and clear cooldowns.
function MimicAbilityService.reset()
	for player in shifts do
		endShift(player, true, nil)
	end
	for player in thefts do
		endTheft(player, true, nil)
	end
	table.clear(readyAt)
	table.clear(theftReadyAt)
end

return MimicAbilityService
