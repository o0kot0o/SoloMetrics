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

## D-007 — Custom themed color picker instead of native ColorPickerFrame (2026-11-22)
Supersedes the "native picker" part of D-006 / CONFIG_UI_DESIGN decision 3, at the user's request: the Blizzard picker looked out of place against the flat theme (screenshot). Replacement (`Settings/Widgets.lua`): HSV square, hue strip, opacity strip over a checkerboard, New/Original swatches (click Original to restore), `#RRGGBBAA` hex input with validation, OK/Cancel. Live preview while dragging. Any close other than OK (Cancel, Escape, closing the settings window) restores the exact original RGBA — keeps acceptance test 5 semantics.

## D-008 — Widget engine data paths (2026-11-22, W1)
Per the widget-engine directive and `docs/WIDGETS_DESIGN.md`. Three explicitly labeled source kinds: **live** (opaque value pushed each interval into a native StatusBar column; never stored in Lua; limited to player average-DPS-so-far and cumulative damage; pending `/sm graphtest`), **fights** (one readable value per completed session, out of combat), **demo**. Per-interval DPS and per-spell live graphs are declared unsupported (need arithmetic/comparison on secrets). Spell widgets bind a readable spellID captured out of combat. Widget appearance stores overrides only, resolved over user defaults over built-in defaults. 12-widget cap.

## D-009 — Per-widget windows and reusable Panel (2026-11-22)
User request: each widget's settings in its own window; main config lists widgets with Edit buttons. The control-row system moved from ConfigWindow into `Settings/Panel.lua` (custom item kind with get/set/default/reset) so both windows share one implementation and look identical. Widget appearance edits are overrides; R clears the override.

## D-010 — Spell widgets are per-fight only (2026-11-22)
Right-click → spell widget captures a readable spellID out of combat. Spell graphs plot one value per completed fight (damage, DPS, share of player damage) because the spell can't be identified in the live list (secret spellID). Per-fight scales use exact readable min/max. Menu shows the live option disabled with the reason.

## D-011 — Counter widgets (2026-11-22, v0.9.0)
Second widget type sharing the widget engine. Per-type appearance schemas and user defaults. Counters render with anchors only (no string measurement → safe with secret text); live formats limited to native numeric formatting; last-fight counters (readable) format freely. Spell counters show the last completed fight only (same reason as D-010). No auto-size: it would require measuring secret text.

## D-004 — Lua safety lint (2026-11-22)
`Validate-SoloMetrics.ps1` fails on combat-log event usage, `loadstring`/`RunScript`, and any `ResetAllCombatSessions` reference lacking an `SM-ALLOW-RESET` review marker.
