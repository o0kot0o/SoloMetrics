# SoloMetrics

A lightweight, fully customizable **personal** damage meter for World of Warcraft: Forever.
It shows your own damage, DPS and per-ability breakdown using the client's native `C_DamageMeter` API.

> Status: **M0 scaffold**. The addon loads, has `/sm` commands and a capability probe (`/sm debug`). No meter yet.
> See [docs/CLAUDE_STATUS.md](docs/CLAUDE_STATUS.md) for current progress.

## Install (end users)

Copy the `addon/SoloMetrics` folder into `World of Warcraft\_forever_\Interface\AddOns\` so that
`AddOns\SoloMetrics\SoloMetrics.toc` exists. Restart the game.

## Development

Source lives in this repo; the game folder only receives copies.

1. Copy `dev.local.example.json` to `dev.local.json` and set `wowAddonsDir` to your
   `...\_forever_\Interface\AddOns` path (this file is git-ignored).
2. Preview: `deploy.cmd -DryRun`
3. Deploy: `deploy.cmd` (or `powershell -ExecutionPolicy Bypass -File scripts\Deploy-SoloMetrics.ps1`)
4. In game: `/reload` for Lua changes; restart the game after first install or any `.toc` change.

The deploy script refuses non-Forever clients, any destination not named `AddOns\SoloMetrics`,
and an existing `SoloMetrics` folder it did not create. It only removes files it previously deployed
(tracked in a manifest) and verifies every copied file by SHA-256.

## Layout

```
addon/SoloMetrics/   installable payload (only this goes into WoW)
scripts/             validate / deploy
docs/                API findings, feature matrix, status, decisions
```

## Commands

| Command | Status |
| --- | --- |
| `/sm` | show/hide frame |
| `/sm debug` | client build, `C_DamageMeter` function/enum probe |
| `/sm resetui` | re-center frames |
| `/sm version` | version and SavedVariables load count |
| `/sm config`, `edit`, `lock`, `test`, `training`, `history`, `profile` | planned |
