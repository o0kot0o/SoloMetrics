# SoloMetrics — Configuration UI Design & Claude Directive

**Approved design:** November 22, 2026  
**Applies to:** M3 Phase 2 onward (repository reviewed at v0.2.0, commit `5be12c5`)  
**Roles:** Claude implements; ChatGPT researches, designs, and reviews.

## Primary product requirement

Build a premium, approachable, modern, fully customizable in-game config interface. Use **EllesmereUI** as the principal visual/UX inspiration and **ElvUI** as inspiration for depth and organization. Do not copy their branding, proprietary visuals or code without verifying licensing.

The user must be able to display **only DPS ability bars and text**, without any window background, border, accent, header, icon, decoration or bar background. Every element has independently adjustable color, texture (where applicable), visibility, opacity, dimensions and alignment (where applicable). Config remains reachable when all meter elements are invisible or click-through.

## Four locked design decisions

1. **Layout:** left vertical category list, right settings pane, optional contextual tabs for large categories, with search.
2. **Editing:** changes apply instantly to actual meter and optional live DEMO preview; no mandatory Apply button. Offer per-setting and category reset, undo where practical, and “Revert changes since opening” from a validated snapshot.
3. **Color editing:** use **both** WoW native color picker and hex input, accepting `#RRGGBB` and `#RRGGBBAA`. Keep fields synchronized; Cancel restores the precise original RGBA. Validate inputs.
4. **Scope:** all **44 existing settings** from `Appearance/Theme.lua` must be represented by working controls in v1 of the config UI; common options visible immediately, Advanced options in collapsible sections. 44 is a baseline, not a maximum.

## Settings categories

- **General:** current/overall session, row count, number formatting, smoothing, meter visibility and locking.
- **Appearance:** overall theme, backdrop, border, accent, opacity, texture presets.
- **Damage Bars:** fill/background color, opacity, texture, height, relative scaling.
- **Text & Fonts:** independent name/damage/DPS columns, font selection, size, outline, shadow, alignment, number formatting.
- **Header:** independent title, DPS total, damage total, timer, session label, typography and background.
- **Layout & Position:** width, scale, padding, row spacing, anchors and reset positions.
- **Visibility:** individually hidden regions and supported conditional show/hide rules.
- **Profiles:** create, duplicate, rename, delete, safe import/export, restore defaults.

Don't add fake active controls for Timeline, Training, Pets, or Widgets until those modules exist.

## Visual design principles

- Modern charcoal surfaces, restrained default teal accent, clean spacing and readable typography.
- Consistent toggle, slider, dropdown, editbox and color swatch patterns.
- Settings search that matches human-readable labels/descriptions and setting keys, exposing matches hidden inside Advanced sections.
- Show exact values beside sliders, with editable numeric inputs.
- Texture choices should show actual sample swatches; fonts should preview representative text.
- Disable dependent controls when their parent element is disabled but preserve values.
- Offer mini preview cards for Modern Dark, Ultra-Minimal, Text-Only and Compact presets.
- Provide a DEMO mode powered by `Analytics/Demo.lua` so edits can be judged outside combat. Clearly label simulated data; do not mix it with real combat data.
- Make window movable and scrollable, clamp to screen, accommodate differing UI scales/resolutions, and remain accessible independent of meter opacity.
- An Edit/Move Widgets control reveals normally hidden meter boundaries and allows position changes; exit/lock restores click-through.
- Show useful tooltips, keyboard/focus affordances where practical, strong visual contrast, and clear errors for invalid settings.

## Schema additions to prioritize after all 44 original controls work

1. Independent bar fill alpha and bar background alpha; do **not** change parent frame alpha to fade unrelated child content.
2. Backdrop texture and more bundled bar textures; optional LibSharedMedia adapter, not a required dependency.
3. Icon size, cropping, offsets and optional border treatment.
4. Per-column text alignment, independent text alpha, richer font shadow controls.
5. Header detail, supported widget anchoring and conditional visibility.
6. Per-ability visual overrides only when safe spell identity handling during combat can be demonstrated; never use secret spell IDs as Lua keys.

Every exposed property must modify an actual rendered element; no dead options.

## Incremental implementation

**M3.2a — Window:** `/sm config` shell, left sidebar, scrollable content, navigation, search, close/reopen, screen clamp.

**M3.2b — Binding:** add UI metadata (label, category, order, tooltip, Advanced flag, dependencies) to theme schema or companion registry; expose and test all existing 44 settings, instant application, reset/revert.

**M3.2c — Editors:** native picker + hex RGBA with exact cancel restoration, slider+number input, functional texture/font previews.

**M3.2d — Preview:** live DEMO, existing visual presets as cards, one-button Move Widgets, proper click-through behavior.

**M3.2e — Profiles:** create/rename/duplicate/delete, validated versioned import/export, migrations, persistence, and UI performance QA. Defer “Graph + Bars” and “Training Focus” presets until their widgets exist.

## Hard engineering constraints

- The source of truth stays in the **external project** `addon/SoloMetrics/`, not in the WoW installation. Deploy only via `deploy.cmd` / `scripts/Deploy-SoloMetrics.ps1`, keeping existing validation and manifest protections. Never touch `WTF`, other addons, or the installed source manually.
- Preserve **live DPS and live per-spell bars**. Current verified design passes secret combat numbers directly to approved WoW native display setters. Never compare, sort, calculate with, branch on, serialize, persist or index by secret values.
- Cosmetics may change live when safe; queue only actual protected structural mutations until combat unlocks.
- Native WoW Lua UI; no external executable or service.
- Config data is schema-validated, versioned and migrated. Profile import is data-only; never use `loadstring` / `RunScript` to evaluate an import.
- Keep the options window separate from meter alpha, hidden state, and click-through, and retain `/sm resetui` as emergency recovery.
- Keep secrets and combat-session correctness completely separate from configuration/UI rendering concerns.

## Mandatory acceptance tests

1. All original 44 settings are available and functionally bound; no dead controls.
2. Ultra-Minimal is truly bars and text only: no border, background, header, accent, icons or bar background. Edit Mode can still find the widget.
3. Text-Only, Modern Dark, Compact and Ultra-Minimal profiles can be switched without corrupting saved customizations.
4. Backdrop alpha at 0% does not fade text/bars; bar fill alpha at 0% does not fade text.
5. Color picker, hex input, alpha, invalid input validation, and exact ColorPicker Cancel restoration all pass.
6. Instant preview, undo/revert, category resets, search, scrolling, font/texture preview, disabled dependent controls all work.
7. `/sm lock` is click-through; `/sm edit` reveals draggable bounds; `/sm config` works even with meter invisible.
8. No clipped/unreachable options across game UI scales and display sizes.
9. Settings persist over `/reload`, relog and restart (record separately).
10. Real combat and chained fights retain accurate live DPS, spell icon/name, damage bars, post-fight values, and secret-value-safe handling.
11. Static validator and deployment scripts pass. Log actual in-game testing, not assumptions.

## Collaboration/reporting

Claude owns code and commits. ChatGPT handles design/research/reviews. After each slice, update `docs/CLAUDE_STATUS.md` with commit, changes, tests actually completed, unresolved issues and next review requests. Record new decisions in `docs/DECISIONS.md`, and any Forever API observations in `docs/API_VALIDATION.md`. Update `docs/FEATURE_MATRIX.md` only with evidence. Request a screenshot/code review after M3.2b.

## References

- EllesmereUI: https://github.com/EllesmereGaming/EllesmereUI
- EllesmereUI listing: https://www.curseforge.com/wow/addons/ellesmereui
- ElvUI options documentation: https://elvui.dev/en/retail/options/

Reference material for UX research is not permission to reuse third-party assets or source code.
