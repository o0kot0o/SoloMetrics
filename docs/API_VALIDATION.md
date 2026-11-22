# API Validation

Evidence log for the native damage meter API on the **installed** client. Every entry states its source:
**OBSERVED** (seen in game), **FILE** (read from install files outside the game), **DOCS** (public documentation), or **UNTESTED**.

## Client

| Item | Value | Source |
| --- | --- | --- |
| Client version / build | 1.60.1.71037 | FILE (`.build.info`, product `wowf`), 2026-11-22 |
| Interface version | 16001 | FILE (inferred: other installed Forever addons declare 16001) — confirm with `/sm debug` |
| Documented reference build | 70790 / interface 16001 (2026-11-05) | DOCS — installed build is newer; shapes may differ |
| `GetBuildInfo()` output | — | UNTESTED (run `/sm debug`) |

## C_DamageMeter functions

| Function | Present | Call shape / returns | Secret in combat? | Readable after combat? |
| --- | --- | --- | --- | --- |
| `IsDamageMeterAvailable()` | UNTESTED | | | |
| `GetAvailableCombatSessions()` | UNTESTED | | | |
| `GetCombatSessionFromID(sessionID, meterType)` | UNTESTED | | | |
| `GetCombatSessionFromType(sessionType, meterType)` | UNTESTED | | | |
| `GetCombatSessionSourceFromID(sessionID, meterType, guid?, creatureID?)` | UNTESTED | | | |
| `GetCombatSessionSourceFromType(sessionType, meterType, guid?, creatureID?)` | UNTESTED | | | |
| `GetSessionDurationSeconds(sessionType)` | UNTESTED | | | |
| `ResetAllCombatSessions()` | UNTESTED (presence only — never called) | | | |

## Events

| Event | Fires? | Payload | When |
| --- | --- | --- | --- |
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` | UNTESTED | | |
| `DAMAGE_METER_CURRENT_SESSION_UPDATED` | UNTESTED | | |
| `DAMAGE_METER_RESET` | UNTESTED | | |

## Enums

| Enum | Values | Source |
| --- | --- | --- |
| `Enum.DamageMeterType` | UNTESTED | |
| `Enum.DamageMeterSessionType` | UNTESTED | |

## Fields (per session / source / spell)

| Field | Out of combat | In combat | After combat (delay?) |
| --- | --- | --- | --- |
| source name | UNTESTED | UNTESTED | UNTESTED |
| source totalAmount | UNTESTED | UNTESTED | UNTESTED |
| source amountPerSecond | UNTESTED | UNTESTED | UNTESTED |
| spell spellID | UNTESTED | UNTESTED | UNTESTED |
| spell totalAmount | UNTESTED | UNTESTED | UNTESTED |
| spell amountPerSecond | UNTESTED | UNTESTED | UNTESTED |

## Secret-value rendering paths

| Path | Accepts secret? | Notes |
| --- | --- | --- |
| `FontString:SetText(secret)` | UNTESTED | |
| `StatusBar:SetValue(secret)` | UNTESTED | |
| `issecretvalue` present | UNTESTED | |

## Log

_(append dated entries: date, build, class/spec, steps, observation, source)_
