# SoloMetrics — agent operating rules

Full spec: [SOLOMETRICS_CLAUDE_HANDOFF.md](SOLOMETRICS_CLAUDE_HANDOFF.md). Read it before changing code.

- `addon/SoloMetrics/` is the only installable payload and the source of truth. Never edit the installed copy under WoW's AddOns folder.
- Deploy only via `scripts/Deploy-SoloMetrics.ps1` (or `deploy.cmd`). Run `scripts/Validate-SoloMetrics.ps1` first; deploy runs it automatically.
- Never touch WoW's `WTF` folder, SavedVariables, binaries, or other addons.
- Never call `C_DamageMeter.ResetAllCombatSessions` except from an explicit, confirmed user command. Any line referencing it must carry `SM-ALLOW-RESET`.
- Secret values: never compare, add, divide, sort by, index with, serialize, store, or branch on them. Show "pending/unavailable", never a fake 0.
- No combat-log parsing as damage source. No `loadstring`/`RunScript` imports.
- Feature status is decided by in-game tests, recorded in `docs/API_VALIDATION.md` and `docs/FEATURE_MATRIX.md`. Distinguish **observed in-game** from **inferred from code/docs**.
- After each milestone or blocker update `docs/CLAUDE_STATUS.md`; record architecture decisions in `docs/DECISIONS.md`.
- Scripts must stay Windows PowerShell 5.1 compatible and ASCII-only.
- Lua is WoW 5.1 dialect; widgets never call `C_DamageMeter` directly (go through APIAdapter once it exists).
