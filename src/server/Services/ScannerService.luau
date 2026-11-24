--!strict
--[[
	ScannerService
	The Containment Scanner, the survivors' way to act on a suspicion.
	RequestAbility("Scan") is intent only: the server picks the nearest other
	active participant in front, in range and in line of sight (the same
	Targeting rules as Assimilate). Disguised Mimics can be scanned; their
	character is still there inside the prop.

	  Charges   GameConfig.Scanner.Charges per survivor per round. The charge is
	            spent before any effect; a scan that finds nobody costs nothing.
	  Mimic     every disguise drops, a red highlight shows them to everyone
	            (through walls) for ExposeSeconds, and they are stunned for
	            StunSeconds: no movement, no abilities.
	  Survivor  a false positive: the team's extraction window shrinks by
	            FalsePositivePenalty seconds (RoundService applies it, even
	            mid-Extraction, never below MinExtractionFraction of normal).

	Results go privately to the scanner through AbilityState: "Mimic",
	"Clear", "NoTarget", "Spent" or "Locked". The public sees only what the
	world shows: the highlight, or the shorter lift timer and a banner.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Phases = require(Shared.Modules.Phases)
local RateLimiter = require(Shared.Util.RateLimiter)
local Signal = require(Shared.Util.Signal)
local Targeting = require(Shared.Modules.Targeting)

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local MatchState = require(script.Parent.MatchState)
local MimicAbilityService = require(script.Parent.MimicAbilityService)
local PlayerRegistry = require(script.Parent.PlayerRegistry)

local ScannerService = {}

ScannerService.PenaltyChanged = Signal.new() -- () a false positive shortened the lift window

local SCAN = Net.Abilities.Scan
local EXPOSE_COLOR = Color3.fromRGB(255, 50, 60)

local limiter = RateLimiter.new(
	GameConfig.RateLimits.RequestAbility.Capacity,
	GameConfig.RateLimits.RequestAbility.RefillPerSecond
)
local charges: { [Player]: number } = {}
local abilityRemote: RemoteEvent

local function send(player: Player, result: string?)
	if player.Parent ~= Players then
		return
	end
	local payload: Net.AbilityStatePayload = {
		ability = SCAN,
		readyAt = 0,
		cooldown = 1,
		result = result,
		charges = charges[player] or 0,
	}
	abilityRemote:FireClient(player, payload)
end

local function expose(mimic: MatchState.Participant)
	local character = mimic.player.Character
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "Exposed"
	highlight.FillColor = EXPOSE_COLOR
	highlight.OutlineColor = EXPOSE_COLOR
	highlight.FillTransparency = 0.45
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	task.delay(GameConfig.Scanner.ExposeSeconds, function()
		highlight:Destroy()
	end)
end

local function onScan(player: Player)
	local scanner = MatchState.getActiveParticipant(player)
	if not scanner or scanner.role ~= "Survivor" then
		return
	end
	if not Phases.HostileAbilities[MatchState.getPhase()] then
		send(player, "Locked")
		return
	end
	if (charges[player] or 0) <= 0 then
		send(player, "Spent")
		return
	end
	local root = CharacterService.getRoot(player)
	local round = MatchState.getRound()
	if not root or not round then
		return
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
	local target = Targeting.pick(
		root.Position,
		root.CFrame.LookVector,
		candidates,
		GameConfig.Scanner,
		CharacterService.hasLineOfSight
	)
	if not target then
		send(player, "NoTarget")
		return
	end

	-- Spend the charge before anything else happens.
	charges[player] -= 1

	if target.role == "Mimic" then
		MimicAbilityService.unmask(target.player, "Scanned")
		CharacterService.stun(target.player, GameConfig.Scanner.StunSeconds)
		expose(target)
		send(player, "Mimic")
		Announcer.all(
			"ORGANISM EXPOSED",
			`{scanner.name}'s scan caught {target.name}. They glow red for a few seconds.`,
			"Critical",
			6
		)
		Announcer.to(target.player, "YOU WERE EXPOSED", "Everyone can see you. Get away.", "Critical", 4)
	else
		round.extractionPenalty += GameConfig.Scanner.FalsePositivePenalty
		send(player, "Clear")
		Announcer.all(
			"FALSE POSITIVE",
			`A scan flagged a crewmate. The lift window is {GameConfig.Scanner.FalsePositivePenalty} seconds shorter.`,
			"Warning",
			5
		)
		ScannerService.PenaltyChanged:Fire()
	end
end

function ScannerService.Init()
	abilityRemote = Net.event(Net.Names.AbilityState)
	Net.event(Net.Names.RequestAbility).OnServerEvent:Connect(function(player: Player, ability: unknown)
		if ability ~= SCAN or not limiter:consume(player) then
			return
		end
		onScan(player)
	end)
	PlayerRegistry.PlayerRemoving:Connect(function(player: Player)
		charges[player] = nil
		limiter:forget(player)
	end)
end

-- Abilities wake up: every survivor gets their charges.
function ScannerService.primeCharges()
	table.clear(charges)
	for _, survivor in MatchState.getActiveByRole("Survivor") do
		charges[survivor.player] = GameConfig.Scanner.Charges
		send(survivor.player, nil)
	end
end

function ScannerService.reset()
	table.clear(charges)
end

return ScannerService
