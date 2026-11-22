# Changelog

## 0.4.0 — 2026-11-22 (M3.2e profiles)

- Profiles: create, duplicate, rename, delete, switch; optional separate profile per character.
- Share codes: export a profile's appearance, import someone else's (validated, data-only, never overwrites existing profiles).
- Settings window (`/sm config`, minimap button, addon compartment) with all appearance settings, themed color picker, search, reset and revert.
- Grow direction (up/down), minimap button, scale keeps position.

## 0.2.0 — 2026-11-22 (M3 phase 1: style system)

- Every visual layer styleable: backdrop, border, accent, header (each item), rows, icons, bar fill/background/texture, text font/size/outline/shadow, per-column colors and toggles.
- Presets: Modern Dark, Ultra-Minimal (bars + text only), Text-Only, Compact (`/sm preset`).
- `/sm get`, `/sm set` for any setting; style profiles in SavedVariables (validated on load).
- Unlocked outline so a fully transparent meter can still be found and moved.
- Fix: bars froze during combat (shared render clock). DEMO fight `/sm test`.

## 0.1.0 — 2026-11-22 (M2 live meter)

- Live personal meter: DPS, damage, timer, Current/Overall; spell rows with icon, name, bar, damage, DPS — updating in combat via native rendering of protected values.
- Commands: `/sm edit`, `/sm lock` (click-through), `/sm session`, `/sm format`, `/sm rows`, `/sm resetui`.
- Diagnostics: `/sm probe`, `/sm watch`, `/sm rendertest`, `/sm copy`.

## 0.0.1 — 2026-11-22 (M0 scaffold)

- Repository layout, `.toc` (interface 16001), SavedVariables `SoloMetricsDB`.
- `/sm`, `/sm help`, `/sm version`, `/sm resetui`, `/sm debug` (capability probe; no data dumps in combat).
- `scripts/Validate-SoloMetrics.ps1`, `scripts/Deploy-SoloMetrics.ps1` (manifest-tracked, hash-verified, dry-run).
- Docs: API validation, feature matrix, status, decisions — all entries UNTESTED.
