# API Validation

Evidence log for the native damage meter API on the **installed** client. Every entry states its source:
**OBSERVED** (seen in game), **FILE** (read from install files outside the game), **DOCS** (public documentation), or **UNTESTED**.

## Client

| Item | Value | Source |
| --- | --- | --- |
| `GetBuildInfo()` | version 1.60.1, build 71037, date Nov 18 2026, interface 16001 | OBSERVED 2026-11-22 (`/sm debug`) |
| TOC interface 16001 accepted | addon loads, not flagged out of date | OBSERVED 2026-11-22 |
| Documented reference build | 70790 / interface 16001 (2026-11-05) | DOCS — installed build is newer |
| `issecretvalue` | global function present | OBSERVED 2026-11-22 |
| SavedVariables persist | `loadCount` reached 2 → persisted across at least one load | OBSERVED 2026-11-22 (reload vs restart not distinguished yet) |

## C_DamageMeter functions

| Function | Present | Call shape / returns | Secret in combat? | Readable after combat? |
| --- | --- | --- | --- | --- |
| `IsDamageMeterAvailable()` | yes | out of combat → `true, ""` (2nd return: string, likely reason) | UNTESTED | — |
| `GetAvailableCombatSessions()` | yes | out of combat → array of `{sessionID:number, name:string (mob name), durationSeconds:number}`; ascending sessionID (oldest first). **Rolling window of 30**: after one more fight, ID 59 dropped and 62 appended at the end | UNTESTED | yes (list readable right after a fight) |
| `GetCombatSessionFromID(sessionID, meterType)` | yes | UNTESTED | | |
| `GetCombatSessionFromType(sessionType, meterType)` | yes | UNTESTED | | |
| `GetCombatSessionSourceFromID(sessionID, meterType, guid?, creatureID?)` | yes | UNTESTED | | |
| `GetCombatSessionSourceFromType(sessionType, meterType, guid?, creatureID?)` | yes | UNTESTED | | |
| `GetSessionDurationSeconds(sessionType)` | yes | UNTESTED | | |
| `ResetAllCombatSessions()` | yes (presence only — never called) | — | — | — |

No undocumented members on `C_DamageMeter` (OBSERVED).

## Events

| Event | Fires? | Payload | When |
| --- | --- | --- | --- |
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` | UNTESTED | | |
| `DAMAGE_METER_CURRENT_SESSION_UPDATED` | UNTESTED | | |
| `DAMAGE_METER_RESET` | UNTESTED | | |

## Enums (OBSERVED 2026-11-22, build 71037)

| Enum | Values |
| --- | --- |
| `DamageMeterType` | DamageDone=0, Dps=1, HealingDone=2, Hps=3, Absorbs=4, Interrupts=5, Dispels=6, DamageTaken=7, AvoidableDamageTaken=8, Deaths=9, EnemyDamageTaken=10 |
| `DamageMeterSessionType` | Overall=0, Current=1, Expired=2 |
| `DamageMeterStorageType` | Damage=0, HealingAndAbsorbs=1, Absorbs=2, Interrupts=3, Dispels=4, DamageTaken=5, AvoidableDamageTaken=6, Deaths=7, EnemyDamageTaken=8 |
| `DamageMeterSpellDetailsDisplayType` | SpellCasted=0, UnitSpecificSpellCasted=1, SpellAffected=2, Deaths=3, EnemyDamageTaken=4 |
| `DamageMeterSourceDisplayType` | None=0, Ally=1, Enemy=2 |
| `DamageMeterOverrideType` | Ignore=0, AllowFriendlyFire=1, RedirectSourceToOwner=2, RedirectSourceToAuraCaster=3, IgnoreForAbsorbSpell=4 |
| `DamageMeterCombineSessionType` | None=0, ChallengeMode=1, Arena=2, ArenaMultiRound=3 |
| `DamageMeterNumbers` | Minimal=0, Compact=1, Complete=2 (Blizzard meter display setting) |
| `DamageMeterStyle` | Default=0, Thin=1, Bordered=2, FullBackground=3 (Blizzard meter) |
| `DamageMeterVisibility` | Always=0, InCombat=1, Hidden=2, InGroup=3 (Blizzard meter) |
| `EditModeDamageMeterSetting` | Blizzard meter Edit Mode settings (0–12) |

Notes (inferred, not verified): `OverrideType.RedirectSourceToOwner` suggests the native meter may already fold pet/guardian damage into the owner for some spells — relevant to double-count prevention (M4). Each enum also has a `*Meta` table (MinValue/MaxValue/NumValues).

## Fields (per session / source / spell)

| Field | Out of combat | In combat | After combat (delay?) |
| --- | --- | --- | --- |
| session list `sessionID`, `name`, `durationSeconds` | readable | UNTESTED | — |
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

## Log

- **2026-11-22, build 71037** — `/sm debug` out of combat after several Webwood Spider fights. All 8 functions present; enums above; `IsDamageMeterAvailable() → true, ""`; 30 sessions listed (IDs 59, 60, 61… with mob names and durations). Source: OBSERVED (user paste).
- **2026-11-22, build 71037** — `/sm debug` again after one fight (Githyiss the Vile, 6s). List still #30: first entry now ID 60, new ID 62 at end → FIFO cap of 30 sessions; new fight readable in list out of combat. Source: OBSERVED.
