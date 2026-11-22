# Changelog

## 0.1.0 — 2026-11-22 (M2 live meter)

- Live personal meter: DPS, damage, timer, Current/Overall; spell rows with icon, name, bar, damage, DPS — updating in combat via native rendering of protected values.
- Commands: `/sm edit`, `/sm lock` (click-through), `/sm session`, `/sm format`, `/sm rows`, `/sm resetui`.
- Diagnostics: `/sm probe`, `/sm watch`, `/sm rendertest`, `/sm copy`.

## 0.0.1 — 2026-11-22 (M0 scaffold)

- Repository layout, `.toc` (interface 16001), SavedVariables `SoloMetricsDB`.
- `/sm`, `/sm help`, `/sm version`, `/sm resetui`, `/sm debug` (capability probe; no data dumps in combat).
- `scripts/Validate-SoloMetrics.ps1`, `scripts/Deploy-SoloMetrics.ps1` (manifest-tracked, hash-verified, dry-run).
- Docs: API validation, feature matrix, status, decisions — all entries UNTESTED.
