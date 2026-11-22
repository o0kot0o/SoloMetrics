# SoloMetrics — Claude Code Master Handoff

**Project:** SoloMetrics — professional, fully customizable personal DPS meter for World of Warcraft: Forever  
**Document version:** 1.0  
**Prepared:** 2026-11-22  
**Team responsibilities:** ChatGPT = research, specification, design review, technical investigation; Claude Code = implementation, local code changes, builds, deployment, test iteration. User = runs WoW client, observes behavior, makes design decisions.  
**Primary goal:** A beautiful, lightweight SOLO-only damage meter showing the player's abilities, per-ability damage and DPS, with optional advanced analysis, training tools and completely configurable presentation.

> **Instructions to Claude:** Treat this file as the project's working specification. Read it before touching code. Do NOT assume every API or statistic works merely because it appears in a community example. First probe the installed WoW Forever client, log measured results, and implement capability-checked fallbacks. Keep source outside the game's AddOns directory and DEPLOY copies into that directory. Never develop by editing the installed copy.

---

## 1. Product vision and boundaries

SoloMetrics is NOT a party/raid rankings meter. Its main purpose is the local character's performance. It must display player damage, DPS, and a breakdown by spell/skill whenever supported by the client's native damage meter API. Include pet/guardian attribution when verified. A user must be able to strip away EVERYTHING except floating damage bars and text: no backdrop, no window border, no title, no footer, no icons unless wanted.

**Must-have capabilities:**

1. Personal damage and DPS, fight length and encounter/session selection.
2. Per-spell/ability damage and DPS; percent contribution only where safely computable.
3. Fully modular UI with detachable and independently positioned widgets.
4. Complete appearance customization (colors, textures, fonts, positions, opacity per element, spacing, borders, shadows, bar layout, text alignment, icon styling, animations as applicable).
5. True bars-and-text-only transparent preset, not a translucent opaque window.
6. Appearance editor with live preview/sample data, Edit Mode and a safe way to recover hidden/offscreen widgets.
7. Advanced spell inspector; graceful indication when hits, crits, max hit, etc. are unsupported.
8. DPS timeline, *only to the level permitted by available, readable data*; do not fake live samples.
9. Training dummy mode with fixed-duration tests and careful interval validity; do not show an incorrect result as a valid benchmark.
10. Advanced pet tracking: player / pet / combined modes with no double-counting and explicit unknown attribution.
11. Shareable style profiles via **safe** text import/export, schema versioning, profiles/presets, SavedVariables.
12. Click-through overlay, with edit mode and recovery command to get control back.
13. No external runtime executable, server, registration or network requirement for end users. Drop-in folder only.
14. Low CPU/memory use, unobtrusive during ordinary solo leveling.

**Nice-to-have later:** post-combat fight comparison, personal bests, profile switching by context, snap-to-grid, per-spell appearance overrides, detailed accessibility options, session history retention limits, localization.

**Non-goals:** combat automation, rotation bot, protected UI/secret bypasses, party leaderboard, hypothetical unavailable statistics, dynamically pulling arbitrary local files from inside WoW.

---

## 2. CRITICAL: developer workspace and deploy workflow

The **source/project is outside WoW's AddOns directory**. Claude operates there. For tests, a local deployment step COPIES *only the installable addon payload* into WoW's addon folder. The running WoW client then uses `/reload` to reload existing addon files.

### 2.1 Paths: configurable, never hardcoded guesses

Ask user for actual paths only if they cannot be detected safely. Example placeholders (NOT assumptions about user's install):

```text
PROJECT_ROOT = D:\\Projects\\SoloMetrics
WOW_ADDONS_DIR = C:\\Program Files (x86)\\World of Warcraft\\_forever_\\Interface\\AddOns
SOURCE_ADDON = <PROJECT_ROOT>\\addon\\SoloMetrics
DEPLOY_ADDON = <WOW_ADDONS_DIR>\\SoloMetrics
```

The user can create PROJECT_ROOT anywhere and supply the exact install path. Store local environment settings in ignored `dev.local.json` or a user environment variable, never in the public addon or committed secrets. Use Windows PowerShell deploy support as a first-class path. Optionally add Bash for development on other systems.

### 2.2 Recommended repository layout

```text
SoloMetrics-Project/                    <-- Git root, Claude's ONLY working source
  CLAUDE.md                             <-- brief agent operating rules
  SOLOMETRICS_CLAUDE_HANDOFF.md         <-- this document
  README.md
  CHANGELOG.md
  docs/
    API_VALIDATION.md                   <-- verified findings (client build/date)
    FEATURE_MATRIX.md
    ARCHITECTURE.md
    DESIGN_SYSTEM.md
    TEST_PLAN.md
    DECISIONS.md
    CLAUDE_STATUS.md                    <-- updates for ChatGPT review
  addon/
    SoloMetrics/                        <-- ONLY installable payload
      SoloMetrics.toc
      Core/
      Analytics/
      UI/
      Appearance/
      Settings/
      Assets/Textures/
      Assets/Fonts/
      Assets/Icons/
  scripts/
    Deploy-SoloMetrics.ps1
    Validate-SoloMetrics.ps1
    Package-SoloMetrics.ps1
  tests/
    mock/
    profiles/
  dev.local.example.json
  .gitignore
```

Keep docs, diagnostics, version-control files, node_modules, build intermediates, test fixtures and PowerShell scripts **out of the installable `addon/SoloMetrics` tree**. If test assets must load in the game, package only intentional Lua files. No external library dependency is required for release. Optional integrations should degrade gracefully.

### 2.3 Deployment script contract

Create `scripts/Deploy-SoloMetrics.ps1` supporting:

```powershell
./scripts/Deploy-SoloMetrics.ps1 -WowAddonsDir 'C:\path\to\_forever_\Interface\AddOns'
./scripts/Deploy-SoloMetrics.ps1 -WowAddonsDir 'C:\path\to\_forever_\Interface\AddOns' -DryRun
```

Required behavior:

1. Resolve and canonicalize PROJECT_ROOT, SOURCE_ADDON and destination; print paths before touching anything.
2. Verify source `.toc` exists and that the destination's parent directory exists and ends in `Interface\\AddOns` (case-insensitive; support forward/back slashes).
3. Reject blank paths, filesystem roots, project root as destination, source/destination overlap, or a destination not directly named `SoloMetrics`.
4. Reject paths pointing to `_retail_`, `_classic_`, or other clients when targeting Forever; optionally accept a consciously configured beta path after explicit user approval.
5. Verify each TOC-referenced local Lua/XML file exists and ensure the folder layout is exactly `AddOns\\SoloMetrics\\SoloMetrics.toc` — no double nesting.
6. `-DryRun` shows planned file operations without writes.
7. Create the destination addon folder if missing, then copy payload recursively (PowerShell `Copy-Item` or a carefully constrained `robocopy` command). No source modification.
8. On subsequent deploys, replace outdated addon payload files. Prefer staging + backed-up replacement or a manifest-driven targeted clean to prevent deleted source Lua files from lingering. Do NOT issue broad `Remove-Item -Recurse` against unchecked paths.
9. Never touch the WoW `WTF` directory or SavedVariables, game binaries, or other addons. Do NOT sync target back to source.
10. Preserve original error/exit codes, fail visibly and print `DEPLOY SUCCESS` only after verifying the deployed `.toc` and expected payload files.
11. Optional `-Verbose` log, file counts and hash checks. Exit nonzero on failure.
12. Provide a user-friendly shortcut/batch wrapper if helpful, but PowerShell must be sufficient.

**Testing cadence:** edit source -> run validation -> deploy -> enter `/reload` -> test in game -> report results -> fix source -> repeat. On a first install, enabling a previously disabled addon, or changing `.toc` file membership/load order/metadata, restart game (or return to character selection when sufficient) rather than promising `/reload` will discover changes. Simple modifications to previously loaded Lua/texture files normally require only `/reload`.

**Source of truth:** `addon/SoloMetrics` in project is canonical. The installed copy is disposable. Never inspect installed output and silently use it as new source unless explicitly diagnosing divergence. Do NOT modify installed addon directly.

**Version control:** initialize Git, ignore `dev.local.json`, generated release zips, temporary logs and deployment backups. Commit only after tests. Avoid overwriting uncommitted user changes; inspect status first.

---

## 3. Verified API basis and caution areas

Forever uses a modern addon API and `C_DamageMeter` rather than classic combat-log-based third-party damage parsing. Published documentation for **Forever client build 70790, interface 16001, dated 2026-11-05** enumerates 8 functions and 3 events for this namespace. The exact installed build can differ: verify in-client and record `GetBuildInfo()` output (including interface version) and capability probes.

**Documented functions (check for presence / shape):**

- `C_DamageMeter.GetAvailableCombatSessions()`
- `C_DamageMeter.GetCombatSessionFromID(sessionID, meterType)`
- `C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)`
- `C_DamageMeter.GetCombatSessionSourceFromID(sessionID, meterType, sourceGUID?, sourceCreatureID?)`
- `C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID?, sourceCreatureID?)`
- `C_DamageMeter.GetSessionDurationSeconds(sessionType)`
- `C_DamageMeter.IsDamageMeterAvailable()`
- `C_DamageMeter.ResetAllCombatSessions()` **DO NOT CALL** except by an explicit separate user-facing command with confirmation; never on test start, deploy or UI reset.

**Events:** `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET`.

Inspect client enum values (e.g. `Enum.DamageMeterType`, `Enum.DamageMeterSessionType`) and actual structures. Do NOT assume numeric values. Some documentation uses `type` to denote the meter enum and `sessionType` for the session selector. A source lookup may accept `sourceGUID` and/or `sourceCreatureID`; confirm how to isolate *the player's* source and its pets in the live environment. Check data order and identity handling.

References:

- Forever API dump: https://github.com/Atraeau/WoW-Addons/blob/main/docs/api/Items-Inventory/C_DamageMeter.md
- Warcraft Wiki API: https://warcraft.wiki.gg/wiki/API:C_DamageMeter.GetCombatSessionSourceFromType
- Secret values: https://warcraft.wiki.gg/wiki/Secret_Values
- Working implementation for study (do not blindly copy): https://github.com/tomoaniki93/TomoDamageMeter
- Another Forever meter for behavior comparison: https://www.curseforge.com/wow/addons/forever-dps-meter
- Forever addon toolkit: https://github.com/Thunderz96/forever-addon-kit

### 3.1 Secret-value safety — non-negotiable

During combat, many damage-meter fields may be **secret** to addon Lua. Examples from modern add-on development reports include source name, total damage and amount per second. They may be displayable by specific native UI functions but not arithmetic operands or control-flow inputs. The `issecretvalue` predicate can be used for safe eligibility checks (verify behavior on installed client).

- Never compare, add, divide, index tables with, sort by, serialize, iterate numerically over, or branch on a secret field.
- Never store protected numeric values in retained historical samples or compare them with previous runs.
- Prefer passing a value to a documented secret-compatible rendering setter only if tested safe. `StatusBar:SetValue`, `FontString:SetText` or native formatting behavior MUST be tested independently; do not assume every formatting API is safe.
- Safely display a live value via a supported path without pretending it is readable for calculations.
- Do per-spell sorting by returned order if available/validated; post-combat compute accurate sorting, shares, history and breakdowns from readable data.
- Confirm which fields are valid after leaving combat, and whether a short settling delay is required. Do not assume `PLAYER_REGEN_ENABLED` means all records instantly become readable.
- `pcall` does not automatically make prohibited secret manipulation compliant. Do not build exploits/workarounds to bypass restrictions.
- Never silently report `0` when a value is unavailable or secret; indicate pending/unavailable.
- Never use combat-log events (`COMBAT_LOG_EVENT_UNFILTERED`) as the core damage source. Existing reports indicate access is blocked/restricted for this client.

### 3.2 Feature capability flags

Create `Capabilities.lua` to report, at minimum:

```text
native_meter_available
player_totals_live_display
player_totals_postcombat_readable
spell_data_live_display
spell_data_postcombat_readable
source_owner_attribution
pet_breakdown_reliable
guardian_breakdown_reliable
sampleable_numeric_dps_live
postcombat_session_history
session_duration_available
savedvariables_persist
```

Feature gates must be determined via actual tests, not inferred because a function exists. Distinguish `SUPPORTED`, `PARTIAL`, `UNSUPPORTED`, and `UNTESTED`. In settings, present actionable explanations rather than blank broken widgets.

### 3.3 Statistics and data correctness

Prioritize fields documented for spell entries, including `spellID`, `totalAmount`, `amountPerSecond`, and other source-returned spell metadata. **Do not promise crit counts, hit counts, average hit, largest hit, miss events, DoT tick counts or damage school statistics** unless an actual permitted and readable source is found and verified. An optional empty field in the inspector is better than a made-up statistic.

`amountPerSecond` is an API-provided rate; do not recompute with an invented denominator. Damage percentages must divide *a validated per-spell total* by a *validated compatible overall total*, and only when safely readable. Carefully handle cases where spell totals do not sum perfectly to source totals.

---

## 4. Core architectural layering

```text
WoW API / WoW events
  -> APIAdapter (all game-specific queries and client-build capability handling)
  -> SecretSafety / RecordNormalizer (validated fields; safe display handles versus readable numbers)
  -> CombatSessions + PlayerTracker + PetTracker (logical session/source identity)
  -> Analytics (post-combat stats, comparison, timeline when valid, training)
  -> Internal Events / Read-Only View Models
  -> WidgetManager & widgets (presentational only)
  -> Appearance system / Editor / SavedVariables
```

**Discipline:** Widgets never call `C_DamageMeter` directly. Their inputs are normalized view models, with explicit `readable`, `displayOnly`, `pending` and `unavailable` states. Do not retain secret values in long-lived models. Any live opaque display value must have a narrowly defined one-frame safe transfer to renderer if supported.

Modules:

- `Bootstrap.lua`: initialization, safe default profile, slash commands, module loading.
- `Events.lua`: event bus with unsubscribe, throttling and protected callbacks where warranted.
- `APIAdapter.lua`: only game API gateway; centralize enum mappings, availability, queries.
- `SecretSafety.lua`: safe detection and guarded operations, no insecure tricks.
- `CombatSessions.lua`: current / previous / identified history; session identity/epoch changes.
- `PlayerTracker.lua`: own character source association and totals.
- `PetTracker.lua`: owned unit/guardian source association, double-count prevention.
- `Analytics/SpellAnalysis.lua`: spell metadata & readable post-combat stats.
- `Analytics/Timeline.lua`: bounded sampling from readable data only; post-combat fallback.
- `Analytics/TrainingMode.lua`: timer, start/end semantics, data validity and comparisons.
- `Analytics/History.lua`: capped verified results, versioned persistence.
- `UI/WidgetManager.lua`: root independent widgets, registry, anchors, lifecycle.
- `UI/SpellMeter.lua`: spell rows, icons, names, damage/DPS text, bar fills.
- `UI/SpellInspector.lua`: click-for-detail panel and availability indicators.
- `UI/TimelineWidget.lua`: optional graph if supported.
- `UI/TrainingWidget.lua`: benchmark UI with invalid/partial markers.
- `UI/PetWidget.lua`: separate/combined view.
- `UI/EditMode.lua`: drag handles, snapping, placeholders for invisible frames.
- `Appearance/ThemeEngine.lua`: cascading style resolution and state-sensitive updates.
- `Appearance/TextureRegistry.lua`, `FontRegistry.lua`, `LayoutEngine.lua`.
- `Settings/*`: editor, saved variables, versioned validation, safe import/export.

All public module interfaces should be documented; prefer small dependency-injected services and explicit update reasons to globally coupled frame code.

---

## 5. Detailed interface requirements

### 5.1 Design direction

Professional, clean, premium-quality game UI; default dark charcoal styling with tasteful class-color accents. Avoid generic clunky default-frame appearance. Typography sharp, consistent spacing, aligned columns, purposeful hover states and responsive resizing. Do not require heavy animation or external technologies. Default compact footprint appropriate for solo questing.

**IMPORTANT:** default aesthetics are NOT limitations. Every decoration is optional and should be separately customizable.

### 5.2 Independently adjustable layers

For each widget expose relevant controls:

| Layer | Controls |
| --- | --- |
| Root widget | position, width, height, scale, lock, click-through, visibility rules, strata where safe |
| Backdrop | enabled, texture, RGBA, gradient if supported, opacity independent of children |
| Border / shadow | enabled, texture, color, thickness, radius-like look via assets, offsets, opacity |
| Header | enabled, height, label, font, alpha, buttons, drag region |
| Rows | height, spacing, padding, sort mode, max visible, order, scroll |
| Spell icon | enabled, crop, size, margin, overlay, border, alpha, tooltip |
| Bar background | enabled, texture, opacity, color |
| Bar fill | enabled, width rule, texture, RGBA, gradient/color overrides, direction, animation, independent opacity |
| Text overlays | DPS, damage, percent, spell name independently enabled; fonts, sizes, shadow, outline, RGBA, alpha, anchors, alignment, abbreviation |
| Footer | enabled, timer, summaries, separator, alpha |
| Tooltip | enabled, delay if supported, contents and interaction policy |

No parent-alpha shortcut that inadvertently makes text transparent when only background should fade. Set alpha at appropriate individual UI region level. A completely invisible background still permits visible text and bars.

**Minimum default presets:** Modern Dark, Ultra-Minimal (bars+text only), Text-Only, Graph + Bars, Training Focus. Users can save/rename/duplicate/delete profiles and assign independent style to individual widgets.

### 5.3 Editor

- `/sm config` opens the configuration window with category nav, consistent labels, searchable settings (optional), reset per section, preview/apply and cancel where feasible.
- `/sm edit` exposes outlines/drag handles even if a widget is invisible; users can resize/dock/snap; optional grid.
- `/sm lock` exits editor and restores configured click-through.
- `/sm test` feeds **explicitly labeled DEMO data** to widgets without claiming real combat results.
- `/sm resetui` safely re-centers/re-enables reachable widgets without resetting combat data or corrupting styles.
- Context menu may show `Open Inspector`, `Appearance`, `Detach`, `Lock`, `Click-through`, but right-click is disabled in click-through mode unless edit mode is active.
- If changes are blocked in combat, queue until safe and mark them as pending. Never try to manipulate protected Blizzard frames to bypass restrictions.

### 5.4 Independent widgets

`SpellMeter`, `DPSCounter`, `DamageCounter`, `CombatTimer`, `SpellInspector`, `TimelineWidget`, `TrainingWidget`, `PetBreakdown`. Each root frame has its own identity and SavedVariables layout. No ghost mouse blockers: test ALL child regions and backdrop elements when click-through is enabled. Support frame recovery after UI scale/resolution changes.

### 5.5 Bar/text formatting

- Values: raw (`12,345`), compact (`12.3K`), precise (`12.34K`), custom suffix if safely calculated.
- Each data element can be positioned left/right/inside bar/outside bar or hidden.
- Bar scaling: relative to top personal spell (post-combat if readable); during combat use only verified secret-safe mechanisms or a fixed validated range. No invented normalization.
- Sort options: total damage, DPS, percent, spell name, fixed, API order. Unsupported sorts grayed out during combat; avoid visible row shuffle if requested.
- Optional per-spell styling override by spell ID, with fallback if unknown.

---

## 6. Feature-level implementation and validation

### 6.1 Primary personal meter

- Display self only, not a roster of raid members.
- Header optional: DPS, total damage, duration.
- Spell list with verified ability source, icons and name; fallback for unknown spell IDs.
- Group/ungroup duplicate spell variants according to clearly documented behavior; don't merge pet spells with player spells unintentionally.
- Current / last combat / overall where supported; don't confuse session type and session ID.
- Optimize for a handful of bars; pool reused row frames; avoid reconstructing on every update.

### 6.2 Spell inspector

- On row click (when mouse enabled), show per-ability source, name, icon, total and rate, share if readable, metadata supported by API.
- Show precise field availability and encounter/session context.
- Any future `crit %`, `max hit`, `average hit`, `tick count` must be capability gated and never derived from missing data.

### 6.3 DPS timeline

- Separate graph panel and sampler.
- **Important finding:** a Forever DPS Meter author explicitly states its protected live values prevent live curves; it computes graph data after fights. Do not assume 0.5s live numeric sampling is available.
- Test whether any safe, documented numeric DPS history is available to addons. If not: do not show a fake line chart. Provide session-level post-fight trend/comparison charts from real readable end-of-session DPS. This is **not** a second-by-second timeline, and must be labeled accordingly.
- If genuine interval data becomes available, bounded sampling (default at most 1 sample/sec), ring buffer, timestamp semantics, chart scale, pauses and missing data handling.
- Allow graph completely disabled and avoid polling when not needed.

### 6.4 Training dummy mode

- Manual arming (don't depend on reliably recognizing every dummy NPC), configurable 30/60/120/180s tests.
- Start on verified signal; use monotonic game elapsed time when safe; record duration target, session identity and validity.
- **Hard gate:** If ability to capture accurate interval-specific damage at time T cannot be proven, DO NOT use entire encounter DPS as a stand-in. Mark test `INCOMPLETE` or `NON-COMPARABLE` with reason.
- Optional post-combat full-fight comparison can be supported as a separate labeled mode.
- Compare only consistent metrics/duration definitions; annotate test label, timestamp, build/talent notes when manually supplied.
- Do NOT call global damage meter reset to start a test.

### 6.5 Pet & guardian tracking

- Detect local player identity and active pet GUID by supported APIs; explore whether native `C_DamageMeter` aggregates sources or lists independent pet contributions.
- Record who owns which source ONLY when verified; never use creature name alone as proof of ownership.
- Source mapping may change on pet swaps, re-summons and temporary guardians; guard against stale identities.
- Provide Player Only / Pet Only / Combined (and Optional Unknown) views when trustworthy.
- Detect if total already includes pet damage before combining; avoid double-counting.
- Test Hunter pet basic attacks, Warlock pet direct damage, temporary summons, no-pet case; document any limitations.

### 6.6 Profiles and persistence

- SavedVariables account scope and optional per-character override, with explicit default preference.
- Versioned config schema; robust defaults, validation, migration, backup/rollback to safe preset when corrupted.
- Export **data only** using a compact safe representation; no `loadstring`, no executable Lua imports. Include schema version, optional checksum, size limits, allowed texture/font identifiers and strict numeric/color bounds.
- All share codes exclude character name, combat logs, GUIDs and other private data by default.
- Test `/reload`, logout/login and full client restart. Some Forever versions have reportedly had SavedVariables persistence issues; document tested build and fallback.
- Provide profile export backup in settings if persistence is affected.

---

## 7. Performance, safety and compatibility

- Native WoW Lua frames, textures, `StatusBar` where applicable and `FontString`; no embedded browser or external program.
- Prefer native events: `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET`; throttle polling fallback.
- Budget targets: visible meter refresh 4–10Hz max where useful; timeline at most 1Hz default; zero work for hidden disabled widgets. Measure actual frame time with client tools; targets are NOT measured guarantees.
- Cache spell names/icons after safe resolution; support pending spell info rather than Nil errors.
- Pool frames for rows; cap visible rows and retained fights; do not create frames inside tight `OnUpdate` loops.
- Avoid `print` spam; optional diagnostic mode with sanitized logs. Never log untrusted/secret values via unsafe formatting.
- Keep all protected/restricted operations compliant and degrade without Lua errors.
- Deliver correctly ordered `.toc` for installed Forever interface (currently documented `16001` as of 2026-11-22; validate current client). Keep optional icon/textures local to addon.
- License all original assets appropriately. If referring to other public addons, record licenses and do not copy proprietary code/art without authorization.

---

## 8. Milestones and acceptance gates

### M0 — Project & deployment scaffold (FIRST)

- Generate repository tree, initial `.toc`, minimal visible addon, `dev.local.example.json`, safe PowerShell deploy script, validation and test scripts, Git ignore, README.
- User supplies local destination configuration once. Validate dry-run. Deploy to correct `...\\_forever_\\Interface\\AddOns\\SoloMetrics` target.
- Confirm addon loads, `/sm` works, and repeated source changes followed by deploy + `/reload` are reflected in game.
- Document when restarting WoW is necessary after TOC modifications or fresh install.
- **Exit gate:** verified copy-only workflow; no editing directly under AddOns.

### M1 — Native API feasibility spike

- Diagnostic commands showing function presence, build/interface, enums, session existence and field safety statuses (no untrusted numbers dumped in combat).
- Test no-combat, during combat, after combat, player spell rows, Hunter/Warlock pets, session transitions, saved setting persistence.
- Populate `docs/API_VALIDATION.md` and `docs/FEATURE_MATRIX.md` with supported/partial/unsupported/untested evidence.
- **Exit gate:** real player ability damage and DPS display confirmed or a clearly documented blocker.

### M2 — Minimal fully functional personal meter

- Personal DPS, damage, spell rows, spells icon/name, segments, reset on session changes, basic display-safe fallback, errors tested.
- **Exit gate:** multiple successive fights, no duplicate rows/totals, no secret-value errors.

### M3 — Appearance engine + advanced editor (major deliverable)

- All independently configurable layers, opacity/texture/font/color controls, bar/text-only profile, Edit Mode, detached widget scaffolding, click-through, recovery.
- **Exit gate:** build full and completely transparent designs through settings; restore after reload and resize.

### M4 — Enhanced analysis and pets

- Spell inspector, post-fight stats, verified pet modes, comparison/history; feature flags for unavailable metrics.
- **Exit gate:** correct player/pet/combined totals without double count.

### M5 — Training and timeline

- Dummy workflow with strict validity requirements. Real interval timeline only if verified; otherwise accurately labeled post-fight trend view. Profiles import/export, persistence, bounded history.
- **Exit gate:** never present invented time-series or interval DPS.

### M6 — Release polish

- Accessibility, default theme polish, tooltip and overflow testing, localization readiness, no combat taint/Lua errors, performance, installable package, release notes and clean upgrade testing.
- **Exit gate:** professional release quality and documented restrictions.

---

## 9. Test matrix (actual WoW client required)

| Test | Expected result |
| --- | --- |
| New install / game restart | Addon appears and loads from `.../AddOns/SoloMetrics/SoloMetrics.toc` |
| Edit source, deploy, `/reload` | Updated existing Lua/texture changes appear |
| `.toc` membership change | Restart/character-selection step tested; don't claim `/reload` sufficient |
| Before combat | Valid idle view, no stale broken rows |
| Fighting a normal mob | Personal damage and per-skill DPS display if supported |
| After fight | Correct finalized stats, spell inspection |
| Multiple mobs / chained fights | Correct session switching and cleanup |
| Pet active / pet dismissed / pet swapped | No attributed-to-wrong-pet or duplicate damage |
| Combat with protected data | No Lua secret-value arithmetic errors |
| Training dummy 60s | Validated interval-only result, else labeled non-comparable |
| Graph | No fabricated samples or mislabeled trends |
| Minimal style | Zero visible backdrop/border/header, bars and text remain |
| Opacity | Independent alpha per element (text stays 100% while bar 60%) |
| Click-through | Doesn't swallow mouse; edit command restores controls |
| Offscreen widget | `/sm resetui` restores visible reachable positions |
| UI scale change | Stable anchors and good layout |
| Import malformed profile | Rejected safely; existing profile unchanged |
| Profile export/import roundtrip | Visual settings identical |
| `/reload` / logout / restart | Persistence validated and documented |
| Disable widget | Removes update burden; no dangling frames |

Enable Lua errors during tests where supported (e.g. `/console scriptErrors 1` then `/reload`). After each test, record build, reproduction steps, observations and Lua stack traces as provided by user; never claim a run/test occurred if it did not.

---

## 10. Commands and in-game operation

- `/sm` — open/close primary meter (choose stable behavior).
- `/sm config` — appearance and functionality settings.
- `/sm edit` — unlock all configurable regions, including invisible widgets.
- `/sm lock` — lock widgets and restore click-through preferences.
- `/sm test` — toggle visibly labeled mock values for styling.
- `/sm training` — training workflow.
- `/sm history` — post-fight history.
- `/sm profile` — import/export/profile manager.
- `/sm resetui` — recover positions/visibility, not delete data.
- `/sm debug` — opt-in capped diagnostic messages and API capability summary.

A first-run welcome panel can help discover the editor, but must be skippable. All core features accessible from UI without slash commands.

---

## 11. Communication protocol: Claude ↔ user ↔ ChatGPT

**ChatGPT is design and research reviewer; Claude is implementer.** The user will bring Claude's handoff notes here for analysis, and bring my feedback back to Claude. Avoid silently taking major architecture decisions without documenting them.

After EACH milestone or meaningful blocker, update `docs/CLAUDE_STATUS.md` using:

```markdown
# SoloMetrics — Claude Status
Date / build:
Milestone / commit:
What changed (files):
Deployment path used (non-sensitive, if useful):
Commands to reproduce:
Tests actually executed / outcomes:
Client API evidence (readable / secret / unsupported):
Known bugs and limitations:
Decision requests for ChatGPT (clear numbered questions):
Next proposed step:
```

Also maintain `docs/DECISIONS.md` for agreed architectural changes; do not overwrite prior findings without indicating why. In a handoff to ChatGPT, provide exact relevant excerpts, screenshots or diagnostics (not entire unrelated logs), and distinguish **observed in-game** from **inferred by code inspection**.

### If stuck

1. Identify the smallest failure in client or build.
2. Gather function signatures and minimal reproduction; do not invent an alternative API.
3. Write evidence to `docs/API_VALIDATION.md` or `CLAUDE_STATUS.md`.
4. Ask ChatGPT to research the blocker using the findings.
5. Apply the researched change in source, deploy and retest.

---

## 12. FIRST TASK FOR CLAUDE (do this before implementing features)

1. Read this entire handoff.
2. Inspect the current project folder; preserve any existing work or Git changes.
3. Create source/project scaffolding and minimally functional `/sm` addon within `addon/SoloMetrics`.
4. Implement and validate `Deploy-SoloMetrics.ps1` with strict safety gates, `-DryRun`, and source→WoW destination copying. Do not guess the target path or touch another addon.
5. Create the Forever `.toc`, check current client interface, avoid claiming untested metadata works.
6. Generate `docs/API_VALIDATION.md`, `docs/FEATURE_MATRIX.md`, `docs/CLAUDE_STATUS.md` with explicit `UNTESTED` entries.
7. Report exactly what the user needs to set locally and the commands for first deployment and `/reload`.
8. Once loaded in client, proceed to M1 API testing. Do not build beautiful UI before the real per-spell API path is established.

**Success metric:** user edits or asks Claude to edit in the external PROJECT_ROOT, executes one deployment command, enters `/reload` in WoW, and immediately sees the updated addon, without editing game directories by hand.

---

## 13. Research grounding and caution

Research checked 2026-11-22, based on publicly available client/API dumps, addon descriptions and engineering notes—not testing in user's installed game. Revalidate any current-client-dependent statements locally.

- API dump reports build 70790/interface 16001 (2026-11-05): https://github.com/Atraeau/WoW-Addons/blob/main/docs/api/Items-Inventory/C_DamageMeter.md
- Forever addon installation path: https://www.wofwforever.com/en/guides/wow-forever-addons-guide/
- Modern secret-value behavior: https://warcraft.wiki.gg/wiki/Secret_Values
- Forever-compatible open-source meter: https://github.com/tomoaniki93/TomoDamageMeter
- Forever meter reporting post-combat graphs rather than live curves: https://www.curseforge.com/wow/addons/forever-dps-meter
- Community addon kit; beta details may be outdated: https://github.com/Thunderz96/forever-addon-kit

**Caution:** A published addon demonstrating a feature does not prove the exact same data path works on the user's current build, class, pet or encounter. Treat the native API and end-user gameplay tests as the ultimate source of truth.
