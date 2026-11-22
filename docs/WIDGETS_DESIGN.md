# SoloMetrics — Widget Engine Design (W1)

Status: **W1 — architecture and feasibility.** Written 2026-11-22 against v0.5.0 / client 1.60.1.71037.
Source directive: ChatGPT "Widget Engine & Custom Graphs" handoff. Evidence: `docs/API_VALIDATION.md`.

## 1. Feasibility findings

| # | Question (directive §3) | Finding | Basis |
| --- | --- | --- | --- |
| 1 | Native APIs exposing non-secret historical samples? | **None.** The 8 `C_DamageMeter` functions return current aggregates per session (totals, `amountPerSecond`, per-spell rows). No time series, no per-interval data. | OBSERVED (API surface, `/sm debug`) |
| 2 | Do damage-meter events carry useful readable data? | `DAMAGE_METER_COMBAT_SESSION_UPDATED` fires often (56× in a short fight) with 2 readable numbers (meaning unverified — likely meter type + session ID). No damage values. Useful only as an "update now" signal. | OBSERVED; payload meaning → `/sm graphtest` logs first payloads |
| 3 | Native graph/UI APIs accepting secrets for rendering? | No graph API. But `StatusBar:SetValue/SetMinMaxValues` accept secrets (OBSERVED). Hypothesis under test: a row of **vertical StatusBars** (one per sample) + dots anchored to each bar's fill-texture TOP + `Line` regions anchored between dots gives a live line/area/bar graph positioned entirely by the engine. | rendertest OBSERVED; anchoring **UNTESTED → `/sm graphtest`** |
| 4 | Spell identity during combat? | **Not possible.** `spellID` is secret in combat; rows are rank-ordered and re-rank; finding "my spell" needs a comparison on a secret → forbidden. Spell widgets can only be created/bound **out of combat** (spellID readable), and a spell's value can't be picked out of the live list in combat. | OBSERVED (`/sm watch`) |
| 5 | Current vs Overall sampleable? | Both session types return the same shape; both secret in combat, readable after. `GetSessionDurationSeconds` readable in combat. | OBSERVED |
| 6 | Interval damage / rate history? | **No.** `amountPerSecond` is a running average (total ÷ elapsed, recomputed per query — OBSERVED ticking down when idle). Interval DPS = Δtotal/Δt needs arithmetic on secrets → impossible. | OBSERVED |

### Consequences

- **Live graph (if graphtest passes):** metrics limited to what can be passed opaquely each sample: player **average DPS so far**, player **cumulative damage** (Current or Overall). Labeled exactly so — never "DPS per second". Y-scale can't be computed from secret samples → fixed user range or **auto = last completed fight's readable peak × headroom** (values above the scale clip visibly at the top; honest).
- **Per-spell live graphs: unsupported** (finding 4). Spell widgets use readable post-combat data.
- **Completed-fight trends (readable, always available):** the client keeps 30 sessions; out of combat each session's player DPS/damage and each spell's damage/DPS are readable via `GetCombatSessionFromID` / `GetCombatSessionSourceFromID`. Graph = one point per fight, labeled "per fight", never presented as a timeline.
- **DEMO:** readable synthetic samples, labeled DEMO, never stored with real data.

## 2. Data-source taxonomy (shown in UI as distinct kinds)

| Kind | Meaning | When | Example label |
| --- | --- | --- | --- |
| `live` | Opaque value sampled into native regions each interval | in combat (and out, readable) | "Average DPS so far · live" |
| `fights` | One readable value per completed session | out of combat | "DPS per fight · last 30" |
| `demo` | Synthetic | preview only | "DEMO" |

Samples of kind `live` are **never stored in Lua** (the StatusBar holds the value, as the meter does today). They are not persisted and are lost on reload — by design.

## 3. Widget configuration schema (SavedVariables `SoloMetricsDB.widgets`)

```lua
widgets = {
  nextId = 4,
  order  = { "w1", "w3" },            -- display/list order (ids)
  byId   = {
    w1 = {
      id = "w1", type = "graph",      -- registered types: graph, counter (later: gauge, timer, ...)
      name = "Average DPS",
      data = { kind = "live", metric = "dps", session = "current", spellID = nil },
      graph = { style = "area", samples = 30, interval = 1, scaleMode = "auto", scaleMax = 100 },
      behavior = { visibility = "always", locked = false, clickThrough = false },
      position = { point = "TOPLEFT", x = 100, y = 600, width = 260, height = 120, scale = 1 },
      appearance = { ["line.color"] = {1,1,1,1}, ["grid.enabled"] = false },  -- OVERRIDES ONLY
    },
  },
  defaults = { appearance = { } },    -- user "default for new widgets" overrides
}
```

- IDs: monotonic `"w" .. nextId`, never reused, never array indices.
- `appearance` holds **only overrides** (flat `path → value`). Effective value = widget override → `widgets.defaults.appearance` → built-in widget theme default. Changing defaults updates every widget that hasn't overridden that path.
- Every appearance path is declared in a widget schema (type + bounds, like `Theme.SCHEMA`) and validated on load; unknown types/paths dropped, malformed widgets skipped (never crash load).
- Limit: 12 widgets (constant, enforced on create).
- Spell widgets store a readable `spellID` captured out of combat; if the spell isn't in a session it shows "no data", never another spell.

## 4. Module boundaries

```
Core/APIAdapter.lua        single gateway (adds: SessionList, SessionPlayer(id), SessionSpell(id, spellID))
Analytics/DataCoordinator  one shared ticker; builds one snapshot per tick and hands it to providers
Analytics/MetricProviders  live: dps/damage (opaque);  fights: per-session readable values (cached per session id)
Analytics/SampleRing       fixed-size ring of readable samples (fights/demo only)
UI/WidgetManager.lua       create/duplicate/rename/delete, ids, limits, persistence, lock/click-through
UI/WidgetFrame.lua         movable/resizable frame shell, edit overlay, visibility rules
UI/GraphRenderer.lua       pooled StatusBar columns + dots + Lines; area/bar/line/points; grid/axes
UI/CounterWidget.lua       big-number widget (opaque SetText path) — framework smoke test
UI/SpellContextMenu.lua    right-click a meter row (unlocked only; out of combat for spell binding)
Settings/WidgetSchema.lua  appearance schema + defaults + validation
Settings/WidgetConfig.lua  Widgets page in /sm config (list left, tabs right)
```

### Provider contract

```lua
provider = {
  kind = "live" | "fights" | "demo",
  -- live: called once per tick; must call sink(value) with an opaque value or not at all
  Sample = function(self, snapshot, sink) end,
  -- fights: returns array of { t = sessionID, v = number, label = "Mob 0:23" } (readable)
  Series = function(self) end,
  Label  = function(self) return "Average DPS so far · live" end,
}
```

Renderer contract: `renderer:Push(value)` (opaque OK; places into next column) or `renderer:SetSeries(points)` (readable; full redraw). Renderer owns all regions; pooled and capped at `samples` (≤ 60).

## 5. Combat restrictions (summary)

- No arithmetic/compare/sort/store on secrets; samples go straight into `StatusBar:SetValue`.
- No spell selection in combat; the context menu explains and offers creation after combat.
- Locked meter stays click-through; spell context menu only when the meter is unlocked.
- Widget frames are our own (not protected); still, structural changes (create/delete) are avoided in combat.

## 6. Next

W2 (manager + frames, DEMO data) can proceed regardless of the graphtest result. The live provider (W6) depends on graphtest; the fights provider does not.
