# Decisions

Append-only. Superseding a decision: add a new entry referencing the old one.

## D-001 — Manifest-driven deploy (2026-11-22)
Deploy copies the payload in place and writes `.solometrics-deploy-manifest.txt` in the destination. On the next deploy, only files listed in the previous manifest and no longer in source are deleted (individually, containment-checked). No recursive deletes. An existing `SoloMetrics` folder without a manifest is refused unless `-AdoptExisting`. Chosen over staging+swap because it never deletes the whole folder and leaves unknown files alone.

## D-002 — Interface 16001 (2026-11-22)
TOC declares `## Interface: 16001`. Installed client is 1.60.1.71037; other installed Forever addons use 16001. To be confirmed by `/sm debug` (`GetBuildInfo` 4th return).

## D-003 — Slash aliases (2026-11-22)
`/sm` plus `/solometrics` in case `/sm` collides with another addon.

## D-004 — Lua safety lint (2026-11-22)
`Validate-SoloMetrics.ps1` fails on combat-log event usage, `loadstring`/`RunScript`, and any `ResetAllCombatSessions` reference lacking an `SM-ALLOW-RESET` review marker.
