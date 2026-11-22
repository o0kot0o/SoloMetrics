# SoloMetrics — Claude Status

**Date / build:** 2026-11-22 / client 1.60.1.71037, interface 16001 (OBSERVED via `GetBuildInfo`)
**Milestone:** M0 complete (addon loads in game) → M1 API feasibility spike in progress

## M0 result
- Addon loads from `_forever_\Interface\AddOns\SoloMetrics`; `/sm debug` works. OBSERVED.
- Deploy workflow verified: validate → copy (manifest + SHA-256 verify) → game. Safety gates tested against fake folders (root, `_retail_`, unknown client, wrong parent, project root, foreign existing folder all refused; stale-file removal only touches manifest entries).
- SavedVariables load counter reached 2 → persistence works at least once (reload vs restart not yet distinguished).

## M1 evidence so far (all OBSERVED, out of combat)
- All 8 documented `C_DamageMeter` functions present, no extra members. `issecretvalue` present.
- Enums are richer than docs: `DamageMeterType` has 11 meter types (DamageDone=0, Dps=1, …); `DamageMeterSessionType` = Overall=0, Current=1, Expired=2; also `DamageMeterOverrideType.RedirectSourceToOwner` (pet attribution hint). Full list in `docs/API_VALIDATION.md`.
- `IsDamageMeterAvailable()` → `true, ""`.
- `GetAvailableCombatSessions()` → rolling FIFO window of 30 `{sessionID, name, durationSeconds}` entries, oldest first; readable right after a fight.

## What changed in this step (files)
- `addon/SoloMetrics/Core/Diagnostics.lua` — new commands:
  - `/sm probe [dps] [sessionID]`: recursive shape dump of `GetCombatSessionFromType(Current)`, `GetCombatSessionSourceFromType(Current, player GUID)`, and (out of combat) `FromID`/`SourceFromID` for the latest session. In combat prints types/secret flags only. GUIDs and player name redacted.
  - `/sm watch`: on combat start, +3s, and combat end +0/+0.5/+2/+5s, prints which fields are Secret/Readable (never values) and counts `DAMAGE_METER_*` events with payload secret-status.
  - `/sm copy`: copyable text window of the last report.
- `addon/SoloMetrics/Core/Bootstrap.lua` — slash routing passes arguments; new commands in help.
- TOC unchanged (so `/reload` suffices).

## Tests actually executed
- Static validation PASSED; deploy SUCCESS (2 updated). New commands **not yet run in game**.

## Known limitations
- No luac locally; Lua syntax only verified by loading in game.
- `/sm watch` timers can overlap if a new fight starts <5s after the previous ends (diagnostic only).

## Decision requests for ChatGPT
1. Is `GetCombatSessionSourceFromType(sessionType, meterType, UnitGUID("player"))` the right way to isolate the player, or should we iterate `combatSources` from the session and match a flag (e.g. `isLocalPlayer`)? Probe output will show available fields.
2. `DamageMeterOverrideType.RedirectSourceToOwner` — any documentation on whether pet damage is merged into the owner's source by default?
3. Should the meter use `DamageDone` (0) or `Dps` (1) meter type for the DPS column, or is `amountPerSecond` within DamageDone sufficient?

## Next proposed step
User runs `/reload`, then: `/sm probe` out of combat; `/sm watch`, one fight, wait ~5s; paste both (via `/sm copy`). That determines live-display vs post-combat readability and the spell row shape → exit M1.
