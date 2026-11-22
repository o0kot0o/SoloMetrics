# SoloMetrics — Claude Status

**Date / build:** 2026-11-22 / client 1.60.1.71037, interface 16001
**Milestone:** M1 exit gate MET (live + post-combat data path confirmed) → **M2 live personal meter: v0.1.0 deployed, awaiting in-game test**

## M1 summary (all OBSERVED in game)
- In combat all damage numbers, names, GUIDs and spellIDs are secret; readable: session duration, array lengths, `isLocalPlayer`, `classFilename`. Everything readable at combat end +0s (except `specIconID`).
- `/sm rendertest`: 13/13 native setter paths accept secrets in combat, 0 errors. **User visually confirmed the panel updated live** (numbers, spell icon/name, bar).
- `combatSpells` natively sorted desc; spell sum == player total; `maxAmount` == top spell; source DPS = total / integer duration; spell DPS uses a different fractional denominator.
- Pet attribution: **UNTESTED** — user's Hunter is too low level for a pet. Revisit at pet level (M4).
- Full evidence: `docs/API_VALIDATION.md`; design: `docs/DECISIONS.md` D-005.

## M2: what changed (files)
- `Core/SecretSafety.lua` — `IsSecret`, `Readable`, `IsNumber` (only `issecretvalue`/`type` on possibly-secret values).
- `Core/APIAdapter.lua` — single runtime gateway to `C_DamageMeter`; `Snapshot(session)` returns a transient render model (readable: duration, hasPlayer, classFilename, spellCount; opaque: dps, total, max, spells).
- `UI/SpellMeter.lua` — live meter: header (DPS, DMG, Current/Overall label, timer), pooled spell rows (icon, name, class-colored bar relative to top spell, damage, DPS). Event-driven (`DAMAGE_METER_*`, regen) with 0.2s render throttle; timer-only refresh 2Hz in combat; no work while hidden (OnUpdate stops).
- `Core/Bootstrap.lua` — SV schema 2 (meter settings with validation; M0 frame removed), commands: `/sm`, `edit`, `lock` (locked = click-through), `session`, `format` (compact via `AbbreviateNumbers` / full via `BreakUpLargeNumbers`), `rows`, `resetui`.
- TOC: v0.1.0, new files → **game restart required**.
- Not built yet (spec modules deferred, no need so far): Events bus, CombatSessions, PlayerTracker, WidgetManager.

## Tests actually executed
- Static validation PASSED; deploy SUCCESS (3 new, 2 updated). **Not yet loaded in game.**

## Known limitations
- In-combat number formats limited to native `AbbreviateNumbers` / `BreakUpLargeNumbers`.
- Rows can't be re-sorted in combat (API order only).
- Single meter type (DamageDone); pets untested.

## Decision requests for ChatGPT
1. Spell DPS denominator differs from source DPS (≈4.6s vs 4s observed). Display API values as-is (current choice, per spec "don't recompute"), or add a note in the inspector?
2. In-combat formats are limited to native functions. Acceptable to offer custom formats (precise "12.34K", suffixes) only post-combat?
3. Review M2 header/row layout before the M3 appearance engine generalizes it.

## Next proposed step
User restarts WoW, fights a few mobs, checks: live header + rows during combat, final values after, Current/Overall switch, multiple chained fights (no duplicate/stale rows), `/sm lock` click-through, `/sm resetui`. Then M2 exit → M3 appearance engine.
