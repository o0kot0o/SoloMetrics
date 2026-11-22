# Decisions

Append-only. Superseding a decision: add a new entry referencing the old one.

## D-001 — Manifest-driven deploy (2026-11-22)
Deploy copies the payload in place and writes `.solometrics-deploy-manifest.txt` in the destination. On the next deploy, only files listed in the previous manifest and no longer in source are deleted (individually, containment-checked). No recursive deletes. An existing `SoloMetrics` folder without a manifest is refused unless `-AdoptExisting`. Chosen over staging+swap because it never deletes the whole folder and leaves unknown files alone.

## D-002 — Interface 16001 (2026-11-22)
TOC declares `## Interface: 16001`. Installed client is 1.60.1.71037; other installed Forever addons use 16001. To be confirmed by `/sm debug` (`GetBuildInfo` 4th return).

## D-003 — Slash aliases (2026-11-22)
`/sm` plus `/solometrics` in case `/sm` collides with another addon.

## D-005 — Two data paths: live opaque rendering + post-combat readable analysis (2026-11-22)
Agreed with ChatGPT review; user requirement: live in-combat DPS is mandatory. Evidence: `/sm rendertest` (API_VALIDATION).

**Live path (in combat):** on `DAMAGE_METER_COMBAT_SESSION_UPDATED` (throttled, 4–10 Hz) the APIAdapter fetches Current session + player source and hands each field *directly* to a native setter in the same call: `SetText` / `SetFormattedText` / `AbbreviateNumbers` for numbers, `C_Spell.GetSpellTexture/GetSpellName(spellID)` → `SetTexture`/`SetText` for rows, `StatusBar:SetMinMaxValues(0, playerSource.maxAmount)` + `SetValue(spell.totalAmount)` for bars. Row order = API order (natively sorted desc). Row count from readable `#combatSpells`. Timer from readable `GetSessionDurationSeconds`. No Lua arithmetic, comparison, sorting, storage or branching on secret values; view models carry an opaque handle valid for one render call only.

**Readable path (out of combat):** at `PLAYER_REGEN_ENABLED` (+0s is sufficient) the same queries return readable numbers → exact totals, shares, history, inspector, training results, custom number formats.

**Consequences:** in-combat formatting is limited to what native functions offer (raw, `%.1f`, `AbbreviateNumbers`); percent-of-total and custom suffixes appear only post-combat. Live rows can't be re-sorted by DPS/name in combat (grayed out per spec 5.5).

## D-006 — Config UI design locked (2026-11-22)
Per `CONFIG_UI_DESIGN.md` (ChatGPT, approved): left nav + right pane + search; instant apply with per-setting/category reset and session revert; native color picker + hex RGBA; all 44 schema settings bound in v1 with Advanced sections. Implementation choices: custom flat widgets (no UIDropDownMenu, to avoid taint); UI metadata in a separate registry rather than inside the style schema, so the schema stays pure data for validation/import; window strata HIGH so the native ColorPickerFrame appears above it.

## D-004 — Lua safety lint (2026-11-22)
`Validate-SoloMetrics.ps1` fails on combat-log event usage, `loadstring`/`RunScript`, and any `ResetAllCombatSessions` reference lacking an `SM-ALLOW-RESET` review marker.
