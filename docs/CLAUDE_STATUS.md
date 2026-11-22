# SoloMetrics — Claude Status

**Date / build:** 2026-11-22 / client 1.60.1.71037 (from install files; not yet confirmed in game)
**Milestone / commit:** M0 — project & deployment scaffold (initial commit)

**What changed (files):**
- `addon/SoloMetrics/SoloMetrics.toc` — interface 16001, SavedVariables `SoloMetricsDB`
- `addon/SoloMetrics/Core/Bootstrap.lua` — SV init with load counter, slash commands, small movable status frame
- `addon/SoloMetrics/Core/Diagnostics.lua` — `/sm debug`: build info, `C_DamageMeter` function presence, `*DamageMeter*` enums; out of combat only: `IsDamageMeterAvailable()` and session list shape (secret values shown as `<secret>`)
- `scripts/Validate-SoloMetrics.ps1`, `scripts/Deploy-SoloMetrics.ps1`, `deploy.cmd`
- `docs/API_VALIDATION.md`, `docs/FEATURE_MATRIX.md`, `docs/DECISIONS.md`, this file
- `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `.gitignore`, `dev.local.example.json`

**Deployment path used:** `<WoW>\_forever_\Interface\AddOns\SoloMetrics`

**Commands to reproduce:**
```
deploy.cmd -DryRun
deploy.cmd
```
then restart WoW (first install), enable SoloMetrics, and in game: `/sm help`, `/sm debug`, `/sm version`.

**Tests actually executed / outcomes:**
- Static validation: PASSED (2 TOC entries, 2 Lua files scanned; no luac, so no syntax check).
- Deploy safety gates, tested against fake folders in a temp dir: filesystem root refused; `_retail_` refused; unknown client `_forever2_` refused; parent not `Interface\AddOns` refused; project root as target refused; first deploy 3 NEW; redeploy 3 UNCHANGED; manifest-tracked stale file removed while untracked user file was kept; existing folder without manifest refused. All exit codes correct.
- Real deploy to `_forever_\Interface\AddOns\SoloMetrics`: DEPLOY SUCCESS, 3 files hash-verified.
- In-game: **none yet.**

**Client API evidence:** none observed in game yet. All entries UNTESTED.

**Known bugs and limitations:**
- No luac available locally, so Lua syntax is only checked by loading in game.
- Status frame is a placeholder; real widgets come in M2/M3.

**Decision requests for ChatGPT:**
1. Review the deploy safety gates in `scripts/Deploy-SoloMetrics.ps1` (manifest approach, D-001) — anything missing?
2. For M1: which exact call sequence should identify the player's own source (`sourceGUID = UnitGUID("player")` vs. iterating session sources)?

**Next proposed step:** user runs first deploy + game restart, pastes `/sm debug` output (out of combat, then once after a fight). That fills API_VALIDATION and starts M1.
