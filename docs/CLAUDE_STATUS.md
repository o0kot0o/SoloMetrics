# SoloMetrics — Claude Status

## UPDATE 2026-11-22: Widget Engine W1 — architecture & feasibility (findings delivered; graphtest pending)

**Deliverable:** `docs/WIDGETS_DESIGN.md` (feasibility answers to directive §3 Q1–6, data-source taxonomy live/fights/demo, widget SavedVariables schema with id-keyed widgets and override-only appearance, module boundaries, provider/renderer contracts, combat restrictions). Decision **D-008**.
**Key findings:** no time-series API; `amountPerSecond` is a running average, so live series = "average DPS so far" (never labeled per-second); per-interval DPS and per-spell live graphs unsupported (secret arithmetic / spellID comparison); spell widgets bind spellID out of combat; completed-fight trends (30 sessions) fully readable out of combat.
**Feasibility test deployed:** `/sm graphtest [scaleMax]` — vertical StatusBar columns fed opaque DPS each second, dots anchored to fill-texture tops, `Line` regions anchored between dots; reports ok/err per call and first event payloads after combat. Needs in-game run + visual confirmation.
**Next:** W2 (widget manager + frames on DEMO data) proceeds in parallel; live provider depends on graphtest.
**Review request for ChatGPT:** WIDGETS_DESIGN.md §1 findings and §3 schema.

---

## UPDATE 2026-11-22: v0.5.0 — schema additions (CONFIG_UI_DESIGN list items 1-5) — user-verified working

Schema 44 → 59 settings (defaults preserve the previous look; old share codes still import):
- `backdrop.texture`, `barBg.texture` (any registered texture, tinted via vertex color)
- `header.bg.enabled` / `header.bg.color` (separate band behind the header)
- `icon.matchRow`, `icon.size`, `icon.crop`, `icon.gap`, `icon.border`, `icon.borderColor`
- `text.name|amount|dps.align` (new `align` type: left/center/right), `text.shadowColor`, `text.shadowOffset`
Config: new `alpha` item kind = opacity slider (percent) editing the alpha component of an existing color setting (backdrop, bar fill, bar background) — no duplicated stored values; `dep` accepts a list; new `depOff` (enabled only when a toggle is off, e.g. icon size vs. "match row height"). Item 1 (independent fill/background alpha) was already true in the renderer — alpha lives in each element's own color; now also exposed as sliders. Item 6 (per-ability overrides) intentionally not done (needs safe in-combat spell identity; spellID is secret in combat).

---

## UPDATE 2026-11-22: v0.4.1 — branding + custom texture pack integrated (user-verified)

User confirmed: custom color picker works (live + Cancel); Advanced sections work. Profile acceptance tests (round trip, malformed import, persistence) deliberately deferred by the user.
User confirmed: new icon shows correctly (also inside EllesmereUI's minimap button bar); all custom textures load. Fine detail is hard to see on small bars (expected at low row heights).

- Icon: `Assets/Icons/SoloMetrics_Minimap_64.tga` on the minimap button (drawn full-size, no tracking-border ring since the art has its own ring; additive highlight); `SoloMetrics_AddonIcon.tga` as TOC `IconTexture` (addon list / compartment).
- Textures: the 6 SMTex textures arrived as 2172x724 24-bit TGA (4.7 MB each, not power-of-two). Converted from the included PNGs to **512x128** 24-bit TGA (~197 KB each) with high-quality bicubic resampling; originals kept out of the repo (zips are git-ignored).
- `scripts/Update-TextureIndex.ps1` generates `Assets/TextureIndex.lua` from `Assets/Textures/Custom/*.tga` (checks TGA type + power-of-two). Theme merges them into the bar texture list with friendly labels. Validator now fails on a stale index or any non-power-of-two TGA in the payload. Deploy still never modifies source.
- `branding/` (repo root, not deployed): logo 512/1024 + 256 icon for README/release art.
- Not changed: live C_DamageMeter handling, appearance system behaviour.

---

## UPDATE 2026-11-22: M3.2e profiles deployed as v0.4.0 — awaiting in-game test

**Files:**
- `Settings/Profiles.lua` — create / duplicate / rename / delete (not the last) / switch; optional per-character profile (`db.charProfile["Name - Realm"]`, local only, never exported); share codes `SM1:<name>:<path=value;...>:<checksum>` containing only non-default appearance values. Import: size cap 6000, prefix/version check, Adler-style checksum, every value parsed with `Theme.ParseValue` and the result passed through `Theme.Validate`; malformed → rejected with a message and nothing changed; unknown setting keys (newer versions) skipped and counted; always imported as a NEW profile (unique name). No `loadstring`. Separator is `:` because WoW edit boxes treat `|` as an escape character.
- `Settings/Widgets.lua` — themed dialog (single-line / multi-line read-only or editable / confirm-only), inline error text, Enter = OK, Escape = close.
- `Settings/ConfigWindow.lua` — Profiles page: active-profile dropdown, per-character toggle, New / Duplicate / Rename / Delete, Export / Import share code, presets. Revert now restores the whole profile set (created/deleted/renamed profiles, selection, per-character choice). `Config.Open(category)`; `/sm profile` opens Profiles.
- `Appearance/Theme.lua` — `Active()` resolves through `Profiles.ActiveName()` (per-character override, else account default).
- SV: `charProfile` table (validated on load).

**Acceptance tests to run:** export → import round trip gives identical visuals; damaged/garbage code rejected with existing profiles unchanged; switching presets/profiles doesn't corrupt saved customizations; persistence over /reload, relog, restart.

---

## UPDATE 2026-11-22: M3.2a + M3.2b (+ core of M3.2c) v0.3.0 — loaded and working in game

Implements `CONFIG_UI_DESIGN.md` slices a/b.

**In-game results (user screenshots):** `/sm config` opens and renders correctly (Layout & Position page shown: sliders with numeric boxes, grow-direction dropdown, action buttons, footer). No Lua errors reported. Ultra-Minimal preset renders truly bars + text only (acceptance test 2 visual pass). Modern and Compact render correctly. Scale changes keep the meter's fixed edge in place. Grow direction Up/Down works.
**Added after v0.3.0:** grow direction (`meter.grow`, anchor by top or bottom edge; `/sm grow`; config Layout & Position); scale change preserves on-screen position; slim custom scrollbar (template scrollbar with gold arrows replaced; hidden when page fits).
**v0.3.1 (user-verified):** minimap button (drag, left = settings, right = toggle meter) and Addon Compartment entry work. Icon is a placeholder (`Ability_Marksmanship`); user will supply custom textures later.
**Custom color picker (D-007):** renders correctly in game (user screenshot); right-column crowding fixed and confirmed. Live update / exact Cancel restore not yet explicitly confirmed.
**Still to verify in game:** custom color picker + exact Cancel restore, hex validation, search, Advanced toggles, dependent-control dimming, Revert, Reset category, persistence across reload/relog/restart.
**Review request for ChatGPT:** screenshot review of the config window (attached by user) — layout, spacing, visual style vs. EllesmereUI inspiration.

**Files:**
- `Settings/ConfigRegistry.lua` — UI metadata: 8 categories (General, Appearance, Damage Bars, Text & Fonts, Header, Layout & Position, Visibility, Profiles), labels, tooltips, Advanced flags, dependencies, slider steps. `CoverageCheck()` asserts every `Theme.SCHEMA` path has a control (44/44 by inspection; warns in chat on open if not).
- `Settings/Widgets.lua` — flat charcoal/teal primitives: button, checkbox, slider (+fill), edit box, shared option-list popup (font names rendered in their own font; texture options show a swatch; click-outside closes), native `ColorPickerFrame:SetupColorPickerAndShow` wrapper with exact original-RGBA restore on Cancel.
- `Settings/ConfigWindow.lua` — `/sm config`: movable, screen-clamped, ESC-closable window (strata HIGH so the native color picker opens above it); left nav + search (matches label, tooltip and setting key; shows Advanced matches); scrollable pooled rows; instant apply; per-setting reset; "Reset category"; "Revert changes" to a validated snapshot taken on open; dependent controls dimmed + non-interactive with values preserved; slider + numeric input; color swatch (checker behind for alpha) + `#RRGGBBAA` input with validation; preset cards; demo preview button (stops on close if started there); move/lock button; independent of meter visibility/click-through.
- `UI/SpellMeter.lua` — `ApplyMeterSetting`, `ReapplyAll`, quiet `SetLocked`.
- `Core/Bootstrap.lua` — `/sm config`; exports `METER_DEFAULTS`.

**Not yet (per plan):** undo stack (Revert covers session), mini preview art on preset cards (M3.2d), profile management + import/export (M3.2e), schema additions list.

**Review request (per directive, after M3.2b):** screenshot/code review of the config window once the user has run it.

---

## UPDATE 2026-11-22: M2 COMPLETE → M3 phase 1 (style system) deployed as v0.2.0, awaiting in-game test

**M2 exit gate met (user-verified in real combat):** live bars move during combat and stay correct after; chained fights clean; `/sm lock` click-through; `/sm resetui`; both bar modes.

**M3 phase 1 — what changed:**
- `Appearance/Theme.lua` — style schema (44 settings: path, type, bounds), font/texture/outline registries (styles store keys, never raw paths), `Validate()` (defaults + only valid known values; unknown dropped — reused later for safe import), hex color parsing, presets: `modern`, `minimal` (bars + text only: no backdrop/border/accent/header/icons/bar bg), `textonly`, `compact`.
- `UI/SpellMeter.lua` — rewritten to render every layer from the active style; alpha applied per region (backdrop alpha never fades text/bars); text columns re-anchor when name/amount/dps toggled; unlocked outline + label so an invisible meter can be found; minimal style is fully invisible when idle and locked.
- `Core/Bootstrap.lua` — SV schema 3: `profiles` (validated on load) + `activeProfile`; `meter.width` migrated into style. Commands: `/sm preset [name]`, `/sm get [prefix]`, `/sm set <setting> <value>`. Slash args keep case; setting names case-insensitive.
- Next (phase 2): `/sm config` window with live DEMO preview; profile save/copy/rename/delete; safe export/import.

**Decision requests for ChatGPT:** (1) Review the schema coverage vs. spec 5.2 table — anything missing for phase 1? (2) Spec presets "Graph + Bars" and "Training Focus" deferred until those widgets exist (M5) — OK?

---

## Earlier history

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

## Tests actually executed (in game, user-reported)
- Meter loads and updates live in real combat (screenshots). Spell rows, icons, names, damage, DPS correct vs. post-combat data.
- DPS column fixed to one decimal (AbbreviateNumbers printed full float precision).
- Native bar smoothing (`SetValue(v, ExponentialEaseOut)`) visible in combat.
- Header and row DPS tick down between hits (API recomputes per query) → 10 Hz text poll.
- `/sm bars` total/top modes; `/sm test` DEMO fight simulator works.
- Bug found & fixed via DEMO: shared render clock froze bars during combat ("shrink after combat"). Confirmed fixed in DEMO: bars correct during and after.
- `/sm bars` top mode: top bar full width (correct). `/sm lock` click-through works. `/sm resetui` works.
- Still to verify: real-combat bars after the clock fix, chained fights (no stale/duplicate rows).

## Added since M2 start
- `/sm bars` (bar scale: top spell / share of total), `/sm smooth`, `/sm test [sec] [big]` (Analytics/Demo.lua, clearly labeled DEMO), `/sm bardebug`.

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
