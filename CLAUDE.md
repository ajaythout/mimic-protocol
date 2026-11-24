# THE MIMIC PROTOCOL: project context for Claude

Roblox social-deduction survival game. The full design brief lives with the owner; `README.md` covers the architecture, round flow, win conditions, security model and test pipeline. Read it before changing systems.

## Status
- **Phase 1 (Playable Foundation): done.** It has been verified with static checks and Lune simulations, but has **not yet been playtested in Roblox Studio**.
- First job in a Studio-connected session: run the README's *Studio checklist* through the Studio MCP tools (Server & Clients playtest, assimilate, extraction, phone emulator, MicroProfiler). Fix real-engine issues before starting Phase 2.

## Source of truth
- The repo is authoritative, and Rojo syncs it into Studio. Do not make Studio-only edits to anything under a Rojo-mapped path; they are lost on the next sync.
- The map is **generated**. `map/build.luau` writes `build/*.rbxm`, which is git-ignored, so run `lune run map/build` before `rojo serve` or `rojo build`.
- `TheMimicProtocol.rbxl` is a committed convenience build. Regenerate it with `scripts/check.sh` after changes.

## Commands
```bash
rokit install                      # tools pinned in rokit.toml (rojo, lune, luau-lsp, stylua, selene)
lune run map/build                 # generate map → build/*.rbxm (+ build/mapdata.json)
rojo serve                         # live sync to Studio (Rojo plugin)
scripts/check.sh                   # everything: map build, layout check, rojo build, luau-lsp, tests, sims
SKIP_SIM=1 scripts/check.sh        # skip the ~70 s multi-round server simulation
stylua src map                     # format
```
`luau-lsp` needs Roblox definitions: download `scripts/globalTypes.None.d.luau` from the luau-lsp repo for the pinned version and set `ROBLOX_DEFS=<path>`, or put it in the project root. Selene's Roblox std downloads on first run.

## Conventions
- Server services: `src/server/Services/*`, plain modules with `Init()` (wiring, no long work) then `Start()`. `RoundService` is the only module that advances phases. `MatchState` is the only place roles live.
- Pure, testable logic goes in `src/shared/Modules` with no Roblox calls, so it can be unit-tested with Lune (`tests/*.spec.luau`).
- Remotes are authored in `default.project.json` and accessed via `Shared/Net`. Client→server remotes send **intent only**; the server derives targets and outcomes, validates role, phase, range and line of sight, and claims cooldowns before any yield. Every handler is rate-limited (`Shared/Util/RateLimiter`).
- Never replicate roles: no attributes and no public folders. Private facts go out with `FireClient` only.
- In-process `Signal` handlers are deferred (`task.defer`). Mutate all state before firing.
- All tunables live in `Shared/Config/GameConfig`. The UI uses `client/UI/Theme` tokens and `Components`; no ad-hoc styling.
- Props: one builder per prop in `map/lib/Props.luau`, used for both templates (`ReplicatedStorage.Assets.Props`) and placed copies (tagged `MimicProp`), so disguises match exactly.
- When adding a feature, extend `tests/sim/run.luau` (server) or `tests/sim/client.luau` (UI) with scenarios for it.

## Phase 2 plan (core gameplay)
1. **Object Shift:** Mimic picks a nearby `MimicProp`. The server validates it (tag, distance, cooldown, prop allowlist), hides the character, welds a clone of the `Assets/Props` template, and restricts movement. Restoring must work across death and round end.
2. **Identity Theft:** apply the target's `HumanoidDescription` and `Humanoid.DisplayName` for a set duration, then restore the Mimic's own appearance (watch out for avatar loading on respawn).
3. **System Sabotage:** lights, cameras, generator progress, false alerts, lockdown doors. Each has a cooldown, server validation, and a clear audio/visual tell. Extend `FacilityService`.
4. **Generator repair** objective that gates opening the extraction lift (`ExtractionService.open`).
5. **Containment Scanner** (survivor counterplay; recommended, **pending owner confirmation**): one charge per survivor per round, used at close range with line of sight. A Mimic hit is exposed to all for a few seconds and briefly stunned. A Survivor hit shortens the lift window for the whole team by about 10 s. Disguised Mimics can be scanned.
