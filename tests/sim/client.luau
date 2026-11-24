--!nonstrict
--[[
	Client smoke test:  lune run tests/sim/client

	Runs the real client bootstrap and controllers against the Mock runtime,
	feeds them the same messages the server sends during a round, and asserts
	on the resulting UI tree (visibility, text, bound input, core GUI state).
	This catches runtime errors and wiring mistakes in UI code; it does not
	judge visual layout, which still needs a look in Studio.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Mock = require("./Mock")

local CFrame, Vector3 = Mock.CFrame, Mock.Vector3
local game = Mock.game
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = Mock.new("Folder", { Name = "Shared", Parent = ReplicatedStorage })
Mock.mount("src/shared", shared)
local remotes = Mock.new("Folder", { Name = "Remotes", Parent = ReplicatedStorage })
for _, name in
	{
		"ClientReady",
		"SetAfk",
		"RequestStrike",
		"RequestAbility",
		"RequestSabotage",
		"PrivateState",
		"RoleReveal",
		"AbilityState",
		"Announcement",
		"EliminationFx",
		"RoundResult",
	}
do
	Mock.new("RemoteEvent", { Name = name, Parent = remotes })
end
local roundState = Mock.new("Folder", { Name = "RoundState", Parent = ReplicatedStorage })
for key, value in
	{
		Phase = "Waiting",
		PhaseEndsAt = 0,
		RoundId = 0,
		RequiredPlayers = 4,
		EligiblePlayers = 1,
		OperativesRemaining = 0,
		SurvivorsExtracted = 0,
		ExtractionRequired = 0,
		ExtractionOpen = false,
		MimicCount = 0,
	}
do
	roundState:SetAttribute(key, value)
end

local zone = Mock.new("Part", {
	Name = "ServerZone",
	CFrame = CFrame.new(0, 9, -96),
	Size = Vector3.new(56, 18, 48),
	Parent = Workspace,
})
zone:SetAttribute("DisplayName", "SERVER VAULT")
zone:SetAttribute("Code", "SECTOR 03")
zone:AddTag("RoomZone")
local bayScreen = Mock.new("Part", { Name = "StatusScreen", Parent = Workspace })
local display = Mock.new("SurfaceGui", { Name = "Display", Parent = bayScreen })
for _, n in { "Phase", "Timer", "Detail" } do
	Mock.new("TextLabel", { Name = n, Text = "", Parent = display })
end
bayScreen:AddTag("BayScreen")

local player = Mock.addPlayer("Tester")
local ally = Mock.addPlayer("Ally")
Mock.becomeClient(player)
player:SetAttribute("Status", "Standby")
player:SetAttribute("AFK", false)
player:LoadCharacterAsync()

local clientFolder = Mock.new(
	"Folder",
	{ Name = "Client", Parent = Mock.new("Folder", { Name = "PlayerScripts", Parent = player }) }
)
Mock.mount("src/client", clientFolder)

local passed, failed = 0, 0
local function check(condition: any, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print("  ✗ " .. message)
	end
end
local function now(): number
	return Workspace:GetServerTimeNow()
end
local function sentToServer(remote: string): number
	local count = 0
	for _, entry in Mock.serverLog do
		if entry.remote == remote then
			count += 1
		end
	end
	return count
end
local function clientEvent(remote: string, payload)
	remotes[remote].OnClientEvent:Fire(payload)
	task.wait(0.05)
end
local function setPhase(phase: string, duration: number?)
	roundState:SetAttribute("PhaseEndsAt", if duration then now() + duration else 0)
	roundState:SetAttribute("Phase", phase)
	task.wait(0.3)
end

local ok, err = pcall(function()
	Mock.runScript(clientFolder.Main)
	task.wait(0.4)
	local gui = player.PlayerGui
	print("• bootstrap")
	check(sentToServer("ClientReady") == 1, "client announces ClientReady once")
	for _, name in { "Hud", "Abilities", "Standby", "Announcements", "RoleReveal", "Results" } do
		check(gui:FindFirstChild(name) ~= nil, `ScreenGui {name} created`)
	end
	check(Mock.coreState[tostring(roblox.Enum.CoreGuiType.Health)] == false, "health bar hidden")

	print("• standby / readiness")
	local standbyPanel = gui.Standby.StandbyPanel
	local standby = standbyPanel.Content
	check(standbyPanel.Visible == true, "Standby panel visible in the bay")
	check(standby.Title.Text == "AWAITING PERSONNEL", `waiting title (got {standby.Title.Text})`)
	check(standby.Info.Text:find("1 of 4") ~= nil, "shows ready count")
	standby.ReadyToggle.Activated:Fire()
	task.wait(0.05)
	local afkSent = nil
	for _, entry in Mock.serverLog do
		if entry.remote == "SetAfk" then
			afkSent = entry.args[1]
		end
	end
	check(afkSent == true, "toggle requests sitting out")
	player:SetAttribute("AFK", true)
	task.wait(0.05)
	check(standby.ReadyToggle.Text:find("SITTING OUT") ~= nil, "toggle reflects server-confirmed AFK")
	player:SetAttribute("AFK", false)

	setPhase("Intermission", 10)
	check(gui.Hud.PhaseBar.Phase.Text == "BRIEFING", "phase bar shows BRIEFING")
	check(
		gui.Hud.PhaseBar.Timer.Text == "0:10" or gui.Hud.PhaseBar.Timer.Text == "0:09",
		`timer counts down (got {gui.Hud.PhaseBar.Timer.Text})`
	)
	check(display.Phase.Text == "BRIEFING" and display.Timer.Text ~= "--:--", "bay screen mirrors the phase")

	print("• role reveal (Mimic)")
	roundState:SetAttribute("RoundId", 1)
	setPhase("RoleReveal", 6)
	clientEvent(
		"RoleReveal",
		{ roundId = 1, role = "Mimic", teammates = { ally.UserId }, mimicCount = 2, playerCount = 8 }
	)
	task.wait(1.2)
	local reveal = gui.RoleReveal
	check(reveal.Enabled == true, "reveal overlay shown")
	check(reveal.Overlay.Center.Role.Text == "MIMIC", "reveal shows MIMIC")
	check(reveal.Overlay.Center.Intel.Text:find("ALLY") ~= nil, "Mimic sees fellow Mimic names")

	print("• deployment / HUD / abilities")
	player:SetAttribute("Status", "Alive")
	roundState:SetAttribute("MimicCount", 2)
	roundState:SetAttribute("OperativesRemaining", 8)
	roundState:SetAttribute("ExtractionRequired", 2)
	setPhase("Deployment", 5)
	check(standbyPanel.Visible == false, "Standby panel hidden in the facility")
	check(gui.Hud.Objective.Visible == true, "objective card visible")
	check(gui.Hud.Identity.Role.Value.Text == "MIMIC", "role chip shows MIMIC")
	check(gui.Hud.Objective.Content.Body.Text:find("Blend in") ~= nil, "Mimic deployment objective")
	check(gui.Hud.Objective.Content.Mimics.Value.Text == "2", "crew counts shown")
	local bar = gui.Abilities.AbilityBar
	check(
		bar.Visible == true and Mock.boundActions.MimicAssimilate ~= nil,
		"ability bar shown and input bound for Mimic"
	)
	check(Mock.coreState.ResetButtonCallback == false, "reset disabled inside the facility")
	local strikes = sentToServer("RequestStrike")
	Mock.boundActions.MimicAssimilate("MimicAssimilate", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	check(sentToServer("RequestStrike") == strikes, "no request sent while abilities are dormant")
	check(bar.Feedback.Text == "ORGANISM DORMANT", "dormant feedback")

	setPhase("Active", 30)
	task.wait(0.35)
	Mock.boundActions.MimicAssimilate("MimicAssimilate", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	check(sentToServer("RequestStrike") == strikes + 1, "F key sends a strike request in Active")
	clientEvent(
		"AbilityState",
		{ ability = "Assimilate", readyAt = now() + 5, cooldown = 22, result = "Hit" }
	)
	task.wait(0.25)
	check(bar.Feedback.Text == "ASSIMILATED", "hit feedback")
	check(
		bar.Assimilate.Countdown.Text == "5" or bar.Assimilate.Countdown.Text == "4",
		`cooldown countdown (got {bar.Assimilate.Countdown.Text})`
	)
	bar.Assimilate.Activated:Fire()
	task.wait(0.05)
	check(sentToServer("RequestStrike") == strikes + 1, "button press during cooldown is not sent")

	check(
		bar.Shift.Visible == true and Mock.boundActions.MimicShift ~= nil,
		"Shift slot shown and bound for Mimic"
	)
	local shiftRequests = sentToServer("RequestAbility")
	Mock.boundActions.MimicShift("MimicShift", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	local lastRequest = Mock.serverLog[#Mock.serverLog]
	check(
		sentToServer("RequestAbility") == shiftRequests + 1 and lastRequest.args[1] == "ObjectShift",
		"Q sends an Object Shift request"
	)
	clientEvent("AbilityState", {
		ability = "ObjectShift",
		readyAt = 0,
		cooldown = 10,
		result = "Shifted",
		detail = "Wooden Crate",
		activeUntil = now() + 20,
	})
	task.wait(0.25)
	check(bar.Feedback.Text == "DISGUISED AS WOODEN CRATE", `disguise feedback (got {bar.Feedback.Text})`)
	check(bar.Shift.KeyHint.Text:find("DROP") ~= nil, "an active disguise offers to drop it")
	task.wait(0.3)
	Mock.boundActions.MimicShift("MimicShift", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	lastRequest = Mock.serverLog[#Mock.serverLog]
	check(
		sentToServer("RequestAbility") == shiftRequests + 2 and lastRequest.args[2] == nil,
		"Q while disguised asks to drop it (no target)"
	)

	check(
		bar.Impersonate.Visible == true and Mock.boundActions.MimicImpersonate ~= nil,
		"Impersonate slot shown"
	)
	Mock.boundActions.MimicImpersonate("MimicImpersonate", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	lastRequest = Mock.serverLog[#Mock.serverLog]
	check(
		lastRequest.remote == "RequestAbility"
			and lastRequest.args[1] == "IdentityTheft"
			and lastRequest.args[2] == nil,
		"R sends an intent-only Identity Theft request"
	)
	clientEvent("AbilityState", {
		ability = "IdentityTheft",
		readyAt = now() + 60,
		cooldown = 60,
		result = "Copied",
		detail = "Ally",
		activeUntil = now() + 45,
	})
	task.wait(0.25)
	check(bar.Feedback.Text == "NOW APPEARING AS ALLY", `impersonation feedback (got {bar.Feedback.Text})`)

	local sabotagePanel = gui.Sabotage.SabotagePanel
	check(bar.Sabotage.Visible == true and sabotagePanel.Visible == false, "Sabotage slot shown, menu closed")
	Mock.boundActions.MimicSabotage("MimicSabotage", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	check(
		sabotagePanel.Visible == true and Mock.boundActions.SabotagePick ~= nil,
		"G opens the sabotage menu"
	)
	Mock.boundActions.SabotagePick(
		"SabotagePick",
		roblox.Enum.UserInputState.Begin,
		{ KeyCode = roblox.Enum.KeyCode.One }
	)
	task.wait(0.05)
	lastRequest = Mock.serverLog[#Mock.serverLog]
	check(
		lastRequest.remote == "RequestSabotage"
			and lastRequest.args[1] == "Lights"
			and sabotagePanel.Visible == false,
		"1 sends a blackout request and closes the menu"
	)
	clientEvent(
		"AbilityState",
		{ ability = "Sabotage", readyAt = now() + 60, cooldown = 60, result = "Done", detail = "Lights" }
	)
	task.wait(0.25)
	check(bar.Feedback.Text == "BLACKOUT TRIGGERED", `sabotage feedback (got {bar.Feedback.Text})`)
	check(bar.Assimilate.Countdown.Text ~= "60", "a sabotage cooldown does not leak onto other slots")

	print("• location readout")
	player.Character.HumanoidRootPart.CFrame = CFrame.new(5, 3, -90)
	task.wait(0.6)
	check(
		gui.Hud.Identity.Location.Value.Text == "SERVER VAULT",
		`location shows the room (got {gui.Hud.Identity.Location.Value.Text})`
	)

	print("• announcements and effects")
	clientEvent(
		"Announcement",
		{ title = "CONTAINMENT BREACH", body = "Test", severity = "Critical", duration = 3 }
	)
	check(#gui.Announcements.Stack:GetChildren() >= 2, "banner added to the stack")
	for i = 1, 5 do
		clientEvent("Announcement", { title = `MSG {i}`, severity = "Info", duration = 3 })
	end
	task.wait(0.1)
	local banners = 0
	for _, child in gui.Announcements.Stack:GetChildren() do
		if child.Name == "Banner" then
			banners += 1
		end
	end
	check(banners <= 3, `at most three banners visible (got {banners})`)
	clientEvent("EliminationFx", { position = Vector3.new(0, 3, -90), victimUserId = ally.UserId })
	check(Workspace:FindFirstChild("LocalEffects") ~= nil, "effects folder exists")

	setPhase("Escalation", 30)
	local grade = game:GetService("Lighting").FacilityGrade
	check(grade.TintColor ~= nil and grade.TintColor.G < 0.95, "alert grade applied during Escalation")

	print("• results")
	setPhase("Results", 10)
	clientEvent("RoundResult", {
		roundId = 1,
		winner = "Mimics",
		reason = "Overrun",
		reasonText = "No survivors remain inside the facility.",
		extracted = 0,
		required = 2,
		durationSeconds = 372,
		roster = {
			{ userId = player.UserId, name = "Tester", role = "Mimic", fate = "Survived", eliminations = 3 },
			{ userId = ally.UserId, name = "Ally", role = "Mimic", fate = "Eliminated", eliminations = 1 },
			{ userId = 5, name = "Crew", role = "Survivor", fate = "Eliminated", eliminations = 0 },
		},
	})
	local results = gui.Results
	local panel = results.Overlay.Debrief
	check(results.Enabled == true, "debrief shown")
	check(
		panel.Title.Text == "FACILITY OVERRUN" and panel.Verdict.Text == "VICTORY",
		"winner title and personal verdict"
	)
	check(panel.Personal.Text:find("3 ASSIMILATIONS") ~= nil, "personal stats line")
	local rows = 0
	for _, child in panel.Roster:GetChildren() do
		if child.Name == "Row" then
			rows += 1
		end
	end
	check(rows == 3, "one roster row per participant")

	player:SetAttribute("Status", "Standby")
	clientEvent("PrivateState", { roundId = 0, role = nil, teammates = {} })
	setPhase("Intermission", 10)
	check(results.Enabled == false, "debrief closes at the next briefing")
	check(
		bar.Visible == false and Mock.boundActions.MimicAssimilate == nil,
		"ability bar hidden and input unbound after the round"
	)
	check(Mock.coreState.ResetButtonCallback == true, "reset re-enabled in the bay")
	check(gui.Hud.Objective.Visible == false, "objective card hidden in the bay")

	print("• survivor perspective")
	clientEvent(
		"RoleReveal",
		{ roundId = 2, role = "Survivor", teammates = {}, mimicCount = 2, playerCount = 8 }
	)
	task.wait(1.2)
	check(gui.RoleReveal.Overlay.Center.Intel.Text == "2 MIMICS HIDE AMONG 8 CREW", "survivor intel line")
	player:SetAttribute("Status", "Alive")
	setPhase("Extraction", 20)
	check(
		bar.Visible == true
			and bar.Scan.Visible == true
			and bar.Assimilate.Visible == false
			and bar.Shift.Visible == false
			and bar.Sabotage.Visible == false,
		"survivors get only the scanner on the ability bar"
	)
	check(
		Mock.boundActions.SurvivorScan ~= nil and Mock.boundActions.MimicAssimilate == nil,
		"F is bound to Scan, not Assimilate"
	)
	clientEvent("AbilityState", { ability = "Scan", readyAt = 0, cooldown = 1, charges = 1 })
	task.wait(0.25)
	check(bar.Scan.KeyHint.Text:find("x1") ~= nil, `scanner shows its charge (got {bar.Scan.KeyHint.Text})`)
	local scans = sentToServer("RequestAbility")
	Mock.boundActions.SurvivorScan("SurvivorScan", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	local scanRequest = Mock.serverLog[#Mock.serverLog]
	check(
		sentToServer("RequestAbility") == scans + 1
			and scanRequest.args[1] == "Scan"
			and scanRequest.args[2] == nil,
		"F sends an intent-only scan"
	)
	clientEvent(
		"AbilityState",
		{ ability = "Scan", readyAt = 0, cooldown = 1, charges = 0, result = "Clear" }
	)
	task.wait(0.25)
	check(
		bar.Feedback.Text == "CREWMATE: FALSE POSITIVE" and bar.Scan.KeyHint.Text == "SPENT",
		"a spent scanner says so"
	)
	task.wait(0.35)
	scans = sentToServer("RequestAbility")
	Mock.boundActions.SurvivorScan("SurvivorScan", roblox.Enum.UserInputState.Begin)
	task.wait(0.05)
	check(sentToServer("RequestAbility") == scans, "a spent scanner sends nothing")
	check(
		gui.Hud.Objective.Content.Body.Text:find("THE LIFT IS OPEN") ~= nil,
		"survivor extraction objective"
	)
end)

if not ok then
	failed += 1
	print("  ✗ harness error: " .. tostring(err))
end
check(#Mock.warnings == 0, `no client warnings ({#Mock.warnings})`)
for _, text in Mock.warnings do
	print("    " .. string.sub(text, 1, 400))
end
print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
