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

## M1 evidence: `/sm watch` over one solo fight (OBSERVED)
- **In combat everything numeric is secret**, including `spellID`, source `name`, `sourceGUID`, totals, DPS. Readable in combat: `GetSessionDurationSeconds(Current)`, array lengths (`#combatSources`, `#combatSpells`), source `isLocalPlayer`, `classFilename`, `classification`.
- **At combat end +0s everything is readable** (no settle delay), except `specIconID` which stays secret.
- `DAMAGE_METER_COMBAT_SESSION_UPDATED` fired 56× in one short fight (2 readable number args); `DAMAGE_METER_CURRENT_SESSION_UPDATED` 1× at combat start.
- Player isolation works both ways: `isLocalPlayer` (readable in combat) and `SourceFromType(..., UnitGUID("player"))`.
- Implication: post-combat meter is fully feasible with exact data. Live meter depends on whether native setters accept secrets → `/sm rendertest` (below).

## RESULT: live meter is feasible (OBSERVED `/sm rendertest`, Hunter, 4s fight)
- All 13 native setter paths accepted secret values in combat, 0 errors (11 ticks each): SetText, SetFormattedText, AbbreviateNumbers, BreakUpLargeNumbers, string.format, GetSpellTexture/GetSpellName with secret spellID, SetTexture, StatusBar SetMinMaxValues/SetValue. Visual confirmation from user pending.
- Spells arrive pre-sorted desc; spell sum == source total; `playerSource.maxAmount` == top spell → live bars scale with no Lua math.
- Source DPS = total / integer session duration. Spell DPS uses a different fractional denominator (~4.6s vs 4s) → spell DPS do not sum to source DPS.
- **User requirement: live in-combat DPS is mandatory.** Proposed design: opaque passthrough of secret values to native setters during combat, driven by `DAMAGE_METER_COMBAT_SESSION_UPDATED` (throttled); exact readable data post-combat for history/inspector/training.

## Step 3: `/sm rendertest`
Live panel that, every 0.25s in combat, passes secret values straight into native setters via pcall and counts ok/err per call: `FontString:SetText`, `SetFormattedText`, `AbbreviateNumbers`, `BreakUpLargeNumbers`, `string.format`, `C_Spell.GetSpellTexture/GetSpellName(secret spellID)`, `Texture:SetTexture`, `StatusBar:SetMinMaxValues/SetValue`. After combat it prints a correctness report: spell sort order, sum of spells vs totals, `maxAmount` meaning, apiDPS vs total/duration ratio, spells with `creatureName` (pet attribution), full spell list.

## What changed in step 2 (files)
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

4. If native setters accept secrets, is relying on that (live text/bars from opaque values, no Lua arithmetic) considered compliant/intended usage? It is how Blizzard's own meter must work.

5. Spell `amountPerSecond` denominator differs from source DPS denominator. Display API values as-is (spec: don't recompute), or show a note?
6. Abbreviation of secrets works only via Blizzard's `AbbreviateNumbers`; custom formats (precise "12.34K", custom suffix) can't be computed in combat. OK to limit in-combat formats to what native functions offer?

## Next proposed step
Remaining M1 checks: user's visual confirmation of the panel; Hunter pet test (pet out) to see whether pet damage is a separate source, merged into the player, or tagged via `creatureName`. Then M2: live personal meter (header DPS/total/timer + pre-sorted spell rows with icon, name, bar, amount, DPS) via opaque passthrough.
