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
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` | yes, 56× in one short solo fight | 2 args, both readable numbers in combat (meaning UNTESTED; likely meterType + sessionID) | throughout combat |
| `DAMAGE_METER_CURRENT_SESSION_UPDATED` | yes, 1× | no args | at combat start (new Current session) |
| `DAMAGE_METER_RESET` | not fired | | |

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

## Data shape (OBSERVED 2026-11-22 via `/sm watch`, DamageDone meter, Current session)

```
GetCombatSessionFromType(Current, DamageDone) ->
  { durationSeconds, maxAmount, totalAmount,
    combatSources = [ { amountPerSecond, classFilename, classification, deathRecapID,
                        deathTimeSeconds, isLocalPlayer, name, sourceDisplayType,
                        sourceGUID, specIconID, totalAmount } ] }
GetCombatSessionSourceFromType(Current, DamageDone, UnitGUID("player")) ->
  { maxAmount, totalAmount,
    combatSpells = [ { amountPerSecond, combatSpellDetails = [], creatureName, isAvoidable,
                       isDeadly, overkillAmount, spellID, totalAmount } ] }
```

Solo fight: `combatSources` had 1 entry. `combatSpells` grew 2 (at +3s) → 6 (end). `combatSpellDetails` was empty.

## Fields: secret status (S = secret, R = readable)

`PLAYER_REGEN_DISABLED` fires before combat lockdown: at that instant a fresh empty Current session exists and fields are R.

| Field | In combat (+3s) | Combat end +0s / +0.5s / +2s / +5s |
| --- | --- | --- |
| `GetSessionDurationSeconds(Current)` | **R** (number) | R |
| session `durationSeconds`, `totalAmount`, `maxAmount` | S | R |
| `#combatSources`, `#combatSpells` (array length) | **R** | R |
| source `isLocalPlayer`, `classFilename`, `classification`, `deathRecapID` | **R** | R |
| source `name`, `sourceGUID`, `totalAmount`, `amountPerSecond`, `sourceDisplayType`, `deathTimeSeconds` | S | R |
| source `specIconID` | S | **S (stays secret)** |
| playerSource `totalAmount`, `maxAmount` | S | R |
| spell `spellID`, `totalAmount`, `amountPerSecond`, `overkillAmount`, `creatureName`, `isAvoidable`, `isDeadly` | S (incl. spellID!) | R |

**No settle delay observed:** everything (except specIconID) readable already at combat end +0s, i.e. inside the `PLAYER_REGEN_ENABLED` handler.

## Secret-value rendering paths

| Path | Accepts secret? | Notes |
| --- | --- | --- |
All OBSERVED 2026-11-22 (`/sm rendertest`, 11 in-combat ticks, 0 errors each). "Accepts" = no Lua error; visual confirmation pending from user.

| Path | Accepts secret in combat? |
| --- | --- |
| `FontString:SetText(source.totalAmount)` | yes |
| `FontString:SetText(source.amountPerSecond)` | yes |
| `FontString:SetFormattedText('%.1f', amountPerSecond)` | yes |
| `AbbreviateNumbers(secret)` → `SetText` | yes |
| `BreakUpLargeNumbers(secret)` | yes |
| `string.format('%.1f', secret)` | yes (result presumably a secret string) |
| `C_Spell.GetSpellTexture(secret spellID)` → `Texture:SetTexture` | yes |
| `C_Spell.GetSpellName(secret spellID)` → `FontString:SetText` | yes |
| `StatusBar:SetMinMaxValues(0, secret maxAmount)` | yes |
| `StatusBar:SetValue(secret spell.totalAmount)` | yes |
| `FontString:SetText(spell.totalAmount)` | yes |

## Bar smoothing (OBSERVED 2026-11-22)

`Enum.StatusBarInterpolation` = Immediate=0, ExponentialEaseOut=1. `StatusBar:SetValue(secret, ExponentialEaseOut)` animates visibly in combat (user confirmed), provided the value is not re-set every poll tick. Perceived jerkiness at low level comes from coarse native update cadence + small damage numbers, not the renderer.

**Range interpolation:** `SetMinMaxValues(0, secretMax, ExponentialEaseOut)` (3rd arg, undocumented) → bars appeared wrong in combat and "shrank" to correct size at combat end (post-combat `/sm bardebug` showed correct readable min/max/value). Likely the range was not applied in combat. Reverted to plain `SetMinMaxValues(0, max)` (verified in rendertest). OBSERVED/INFERRED 2026-11-22.

## DPS recomputation (OBSERVED 2026-11-22)

Source `amountPerSecond` is recomputed at query time: polling during combat shows header DPS ticking down while the player stops attacking. Text polling at 10 Hz therefore gives a continuously live DPS readout (bars unaffected: all spells share the denominator).

## Data semantics (OBSERVED post-combat, Hunter, no pet, 4s fight)

- `combatSpells` arrive **sorted by totalAmount descending** → live rows need no Lua sort.
- `sum(spell.totalAmount) == playerSource.totalAmount == source.totalAmount == session.totalAmount` (solo, no pet).
- `playerSource.maxAmount == combatSpells[1].totalAmount` → live relative bar scaling via `SetMinMaxValues(0, maxAmount)`.
- `session.maxAmount` = top source total (65 = player).
- Source `amountPerSecond` == `totalAmount / session.durationSeconds` exactly (65/4 = 16.25; duration is an integer here).
- Spell `amountPerSecond` uses a **different, fractional denominator** (~4.601 s for both spells: 35/7.607, 30/6.520). Spell DPS values therefore don't sum to source DPS.
- `creatureName` empty for player spells; `combatSpellDetails` empty arrays.

## Log

- **2026-11-22, build 71037** — `/sm debug` out of combat after several Webwood Spider fights. All 8 functions present; enums above; `IsDamageMeterAvailable() → true, ""`; 30 sessions listed (IDs 59, 60, 61… with mob names and durations). Source: OBSERVED (user paste).
- **2026-11-22, build 71037** — `/sm rendertest`, Hunter (no pet), 4s fight, Arcane Shot (3044) 35 + Auto Shot (75) 30 = 65. All 13 native setter paths accepted secrets in combat, 0 errors. Correctness checks above. Source: OBSERVED.
- **2026-11-22, build 71037** — `/sm watch` over one solo fight: secret-status table and events above. Source: OBSERVED.
- **2026-11-22, build 71037** — `/sm debug` again after one fight (Githyiss the Vile, 6s). List still #30: first entry now ID 60, new ID 62 at end → FIFO cap of 30 sessions; new fight readable in list out of combat. Source: OBSERVED.
