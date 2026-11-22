-- SoloMetrics: widget schema (records, appearance overrides, validation)
-- Widgets live in SoloMetricsDB.widgets = { nextId, order = {ids}, byId = {id -> record},
-- defaults = { appearance = {graph path -> value}, counter = {counter path -> value} } }.
-- Types: "graph" and "counter". A widget's `appearance` holds ONLY its overrides
-- (flat path -> value), validated against its type's schema.
-- Effective value: widget override -> user defaults for the type -> built-in default.

local _, ns = ...
local WS = {}
ns.WidgetSchema = WS

WS.MAX_WIDGETS = 12
WS.MAX_SAMPLES = 60
WS.TYPES = { graph = "Graph", counter = "Counter" }

-- Live metrics (opaque values during combat)
WS.METRICS = {
    dps = "Average DPS so far",
    damage = "Total damage",
}
WS.METRIC_ORDER = { "dps", "damage" }
-- Per-fight metrics (readable, completed fights)
WS.FIGHT_METRICS = {
    damage = "Damage per fight",
    dps = "DPS per fight",
    share = "Share of your damage per fight",
}
WS.FIGHT_METRIC_ORDER = { "damage", "dps", "share" }
-- Counter labels
WS.COUNTER_LIVE = { dps = "DPS", damage = "Damage" }
WS.COUNTER_FIGHT = { damage = "Damage (last fight)", dps = "DPS (last fight)", share = "Share (last fight)" }
WS.SECONDARY = {
    none = "None", dps = "DPS", damage = "Total damage", time = "Fight time", share = "Share of your damage",
}
WS.MAX_FIGHTS = 30 -- the client keeps the last 30 sessions
WS.STYLES = { area = "Area", bars = "Columns", line = "Line", points = "Points" }
WS.STYLE_ORDER = { "area", "bars", "line", "points" }
WS.VISIBILITY = { always = "Always", combat = "In combat", nocombat = "Out of combat", hidden = "Hidden" }
WS.VIS_ORDER = { "always", "combat", "nocombat", "hidden" }

---------------------------------------------------------------------------
-- Appearance schemas per type (flat paths; types validated by Theme)
---------------------------------------------------------------------------
local GRAPH_DEFAULTS = {
    ["padding"] = 6,
    ["bg.enabled"] = true, ["bg.color"] = { 0.07, 0.07, 0.08, 0.78 }, ["bg.texture"] = "flat",
    ["border.enabled"] = false, ["border.color"] = { 0, 0, 0, 1 }, ["border.size"] = 1,
    ["title.enabled"] = true, ["title.font"] = "default", ["title.size"] = 11,
    ["title.color"] = { 0.75, 0.75, 0.78, 1 },
    ["value.enabled"] = true, ["value.font"] = "default", ["value.size"] = 13,
    ["value.color"] = { 1, 1, 1, 1 },
    ["axis.enabled"] = true, ["axis.size"] = 9, ["axis.color"] = { 0.55, 0.55, 0.6, 1 },
    ["grid.enabled"] = true, ["grid.lines"] = 3, ["grid.color"] = { 1, 1, 1, 0.06 },
    ["fill.enabled"] = true, ["fill.classColor"] = true, ["fill.color"] = { 0.25, 0.78, 0.72, 0.35 },
    ["line.enabled"] = true, ["line.classColor"] = false, ["line.color"] = { 1, 1, 1, 0.9 },
    ["line.thickness"] = 2,
    ["points.enabled"] = true, ["points.size"] = 3, ["points.color"] = { 1, 1, 1, 1 },
}
local GRAPH_SCHEMA = {
    { "padding", "number", 0, 20 },
    { "bg.enabled", "bool" }, { "bg.color", "color" }, { "bg.texture", "texture" },
    { "border.enabled", "bool" }, { "border.color", "color" }, { "border.size", "number", 1, 8 },
    { "title.enabled", "bool" }, { "title.font", "font" }, { "title.size", "number", 6, 24 },
    { "title.color", "color" },
    { "value.enabled", "bool" }, { "value.font", "font" }, { "value.size", "number", 6, 32 },
    { "value.color", "color" },
    { "axis.enabled", "bool" }, { "axis.size", "number", 6, 16 }, { "axis.color", "color" },
    { "grid.enabled", "bool" }, { "grid.lines", "number", 0, 8 }, { "grid.color", "color" },
    { "fill.enabled", "bool" }, { "fill.classColor", "bool" }, { "fill.color", "color" },
    { "line.enabled", "bool" }, { "line.classColor", "bool" }, { "line.color", "color" },
    { "line.thickness", "number", 1, 6 },
    { "points.enabled", "bool" }, { "points.size", "number", 1, 10 }, { "points.color", "color" },
}

-- Counter default = "Compact DPS" look.
local COUNTER_DEFAULTS = {
    ["padding"] = 8, ["spacing"] = 2,
    ["bg.enabled"] = true, ["bg.color"] = { 0.07, 0.07, 0.08, 0.6 }, ["bg.texture"] = "flat",
    ["border.enabled"] = false, ["border.color"] = { 0, 0, 0, 1 }, ["border.size"] = 1,
    ["accent.enabled"] = false, ["accent.classColor"] = true, ["accent.color"] = { 0.25, 0.78, 0.72, 0.9 },
    ["value.font"] = "default", ["value.size"] = 26, ["value.color"] = { 1, 1, 1, 1 },
    ["value.classColor"] = false, ["value.outline"] = "none", ["value.shadow"] = true,
    ["value.align"] = "center", ["value.valign"] = "middle", ["value.x"] = 0, ["value.y"] = -4,
    ["value.format"] = "auto", ["value.suffix"] = "",
    ["title.enabled"] = true, ["title.text"] = "", ["title.font"] = "default", ["title.size"] = 10,
    ["title.color"] = { 0.7, 0.7, 0.75, 1 }, ["title.outline"] = "none", ["title.position"] = "above",
    ["title.align"] = "center", ["title.x"] = 0, ["title.y"] = 0,
    ["secondary.enabled"] = false, ["secondary.font"] = "default", ["secondary.size"] = 11,
    ["secondary.color"] = { 0.75, 0.75, 0.8, 1 }, ["secondary.outline"] = "none",
    ["secondary.position"] = "below", ["secondary.align"] = "center", ["secondary.label"] = true,
    ["secondary.x"] = 0, ["secondary.y"] = 0,
}
local COUNTER_SCHEMA = {
    { "padding", "number", 0, 30 }, { "spacing", "number", 0, 30 },
    { "bg.enabled", "bool" }, { "bg.color", "color" }, { "bg.texture", "texture" },
    { "border.enabled", "bool" }, { "border.color", "color" }, { "border.size", "number", 1, 8 },
    { "accent.enabled", "bool" }, { "accent.classColor", "bool" }, { "accent.color", "color" },
    { "value.font", "font" }, { "value.size", "number", 8, 96 }, { "value.color", "color" },
    { "value.classColor", "bool" }, { "value.outline", "outline" }, { "value.shadow", "bool" },
    { "value.align", "align" }, { "value.valign", "valign" },
    { "value.x", "number", -300, 300 }, { "value.y", "number", -300, 300 },
    { "value.format", "numfmt" }, { "value.suffix", "text" },
    { "title.enabled", "bool" }, { "title.text", "text" }, { "title.font", "font" },
    { "title.size", "number", 6, 40 }, { "title.color", "color" }, { "title.outline", "outline" },
    { "title.position", "place" }, { "title.align", "align" },
    { "title.x", "number", -300, 300 }, { "title.y", "number", -300, 300 },
    { "secondary.enabled", "bool" }, { "secondary.font", "font" }, { "secondary.size", "number", 6, 40 },
    { "secondary.color", "color" }, { "secondary.outline", "outline" }, { "secondary.position", "place" },
    { "secondary.align", "align" }, { "secondary.label", "bool" },
    { "secondary.x", "number", -300, 300 }, { "secondary.y", "number", -300, 300 },
}

local function Index(schema)
    local t = {}
    for _, e in ipairs(schema) do t[e[1]] = e end
    return t
end
local SCHEMAS = {
    graph = { defaults = GRAPH_DEFAULTS, list = GRAPH_SCHEMA, byPath = Index(GRAPH_SCHEMA), dbKey = "appearance" },
    counter = { defaults = COUNTER_DEFAULTS, list = COUNTER_SCHEMA, byPath = Index(COUNTER_SCHEMA), dbKey = "counter" },
}
-- compatibility aliases (graph)
WS.APPEARANCE_DEFAULTS = GRAPH_DEFAULTS
WS.APPEARANCE_SCHEMA = GRAPH_SCHEMA
WS.APPEARANCE_BY_PATH = SCHEMAS.graph.byPath

function WS.SchemaFor(wtype) return SCHEMAS[wtype] or SCHEMAS.graph end

-- Counter presets: override sets (applied as the widget's appearance).
WS.COUNTER_PRESET_ORDER = { "minimal", "compact", "panel" }
WS.COUNTER_PRESETS = {
    minimal = { label = "Minimal number", overrides = {
        ["bg.enabled"] = false, ["border.enabled"] = false, ["accent.enabled"] = false,
        ["title.enabled"] = false, ["secondary.enabled"] = false,
        ["value.outline"] = "outline", ["value.y"] = 0,
    } },
    compact = { label = "Compact DPS", overrides = {} },
    panel = { label = "Modern panel", overrides = {
        ["bg.color"] = { 0.07, 0.07, 0.08, 0.85 }, ["border.enabled"] = true,
        ["border.color"] = { 0.2, 0.2, 0.23, 1 }, ["accent.enabled"] = true,
        ["title.position"] = "top", ["title.size"] = 11, ["value.size"] = 28, ["value.y"] = 0,
        ["secondary.enabled"] = true, ["secondary.position"] = "bottom",
    } },
}

local function CopyValue(v)
    if type(v) == "table" then return { v[1], v[2], v[3], v[4] or 1 } end
    return v
end

function WS.IsValidAppearance(path, v, wtype)
    local e = WS.SchemaFor(wtype).byPath[path]
    return e ~= nil and ns.Theme.IsValidEntry(e, v)
end

-- Keep only known paths with valid values for the type.
function WS.CleanAppearance(map, wtype)
    local out = {}
    if type(map) ~= "table" then return out end
    for path, v in pairs(map) do
        if type(path) == "string" and WS.IsValidAppearance(path, v, wtype) then
            out[path] = CopyValue(v)
        end
    end
    return out
end

function WS.UserDefaults(wtype)
    local s = WS.SchemaFor(wtype)
    return ns.db.widgets.defaults[s.dbKey]
end

function WS.Get(w, path)
    local v = w.appearance[path]
    if v ~= nil then return v end
    local d = WS.UserDefaults(w.type)[path]
    if d ~= nil then return d end
    return WS.SchemaFor(w.type).defaults[path]
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function Num(v, lo, hi, default)
    if type(v) ~= "number" or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end
local function OneOf(v, set, default)
    if type(v) == "string" and set[v] then return v end
    return default
end

-- data: { kind = "live"|"fights", metric, session, spellID?, spellName? }
-- Spell widgets are always "fights" (spell identity is secret in combat).
function WS.ValidateData(d)
    d = type(d) == "table" and d or {}
    local spellID = (type(d.spellID) == "number" and d.spellID > 0 and d.spellID % 1 == 0) and d.spellID or nil
    local kind = OneOf(d.kind, { live = true, fights = true }, "live")
    if spellID then kind = "fights" end
    local metric
    if kind == "live" then
        metric = OneOf(d.metric, WS.METRICS, "dps")
    else
        metric = OneOf(d.metric, WS.FIGHT_METRICS, "damage")
        if metric == "share" and not spellID then metric = "damage" end
    end
    return {
        kind = kind,
        metric = metric,
        session = OneOf(d.session, { current = true, overall = true }, "current"),
        spellID = spellID,
        spellName = (spellID and type(d.spellName) == "string") and d.spellName:sub(1, 64) or nil,
    }
end

-- Valid secondary metrics for a widget's data.
function WS.SecondaryOptions(data)
    local o = { "none", "dps", "damage", "time" }
    if data.kind == "fights" and data.spellID then o[#o + 1] = "share" end
    return o
end

function WS.Label(w)
    local d = w.data
    local spell = d.spellID and ((d.spellName or ("Spell " .. d.spellID)) .. ": ") or ""
    if w.type == "counter" then
        if d.kind == "fights" then return spell .. WS.COUNTER_FIGHT[d.metric] end
        return WS.COUNTER_LIVE[d.metric] .. (d.session == "overall" and " (overall)" or "")
    end
    if d.kind == "fights" then return spell .. WS.FIGHT_METRICS[d.metric] end
    return WS.METRICS[d.metric] .. (d.session == "overall" and " (overall)" or "")
end

function WS.ValidateWidget(raw, id)
    if type(raw) ~= "table" or type(id) ~= "string" then return nil end
    local wtype = (raw.type == "graph" or raw.type == "counter") and raw.type or nil
    if not wtype then return nil end -- unknown types are dropped, never crash load
    local d = type(raw.data) == "table" and raw.data or {}
    local b = type(raw.behavior) == "table" and raw.behavior or {}
    local p = type(raw.position) == "table" and raw.position or {}
    local name = type(raw.name) == "string" and strtrim(raw.name) or ""
    if name == "" or #name > 32 then name = "Widget" end
    local isCounter = wtype == "counter"
    local w = {
        id = id,
        type = wtype,
        name = name,
        data = WS.ValidateData(d),
        behavior = {
            visibility = OneOf(b.visibility, WS.VISIBILITY, "always"),
            locked = b.locked == true,
            clickThrough = b.clickThrough == true,
        },
        position = {
            x = Num(p.x, -10000, 10000, 300),
            y = Num(p.y, -10000, 10000, 500),
            width = Num(p.width, isCounter and 40 or 120, 900, isCounter and 170 or 260),
            height = Num(p.height, isCounter and 20 or 60, 500, isCounter and 70 or 120),
            scale = Num(p.scale, 0.5, 2, 1),
        },
        appearance = WS.CleanAppearance(raw.appearance, wtype),
    }
    if isCounter then
        local c = type(raw.counter) == "table" and raw.counter or {}
        local sec = OneOf(c.secondary, WS.SECONDARY, "none")
        local okSec = false
        for _, k in ipairs(WS.SecondaryOptions(w.data)) do if k == sec then okSec = true end end
        w.counter = {
            interval = Num(c.interval, 0.1, 2, 0.2),
            secondary = okSec and sec or "none",
        }
    else
        local g = type(raw.graph) == "table" and raw.graph or {}
        w.graph = {
            style = OneOf(g.style, WS.STYLES, "area"),
            samples = math.floor(Num(g.samples, 10, WS.MAX_SAMPLES, 30)),
            interval = Num(g.interval, 0.5, 5, 1),
            -- auto: 0..last fight x headroom; fixed: 0..scaleMax;
            -- focus: 50%..150% of last fight's final value (zoomed; clips outside)
            scaleMode = OneOf(g.scaleMode, { auto = true, fixed = true, focus = true }, "auto"),
            scaleMax = Num(g.scaleMax, 1, 1e9, 100),
            autoMax = (type(g.autoMax) == "number" and g.autoMax > 0) and g.autoMax or nil,
            autoBase = (type(g.autoBase) == "number" and g.autoBase > 0) and g.autoBase or nil,
        }
    end
    return w
end

function WS.NewWidget(id, opts)
    opts = opts or {}
    local wtype = (opts.type == "counter") and "counter" or "graph"
    local data = WS.ValidateData({
        kind = opts.kind, metric = opts.metric, session = opts.session,
        spellID = opts.spellID, spellName = opts.spellName,
    })
    local w = WS.ValidateWidget({
        type = wtype,
        name = "Widget",
        data = data,
        graph = { style = opts.style or (data.kind == "fights" and "bars" or nil) },
        counter = { secondary = opts.secondary },
        behavior = {},
        position = opts.position or {},
        appearance = {},
    }, id)
    w.name = (opts.name or WS.Label(w)):sub(1, 32)
    if wtype == "counter" and opts.preset and WS.COUNTER_PRESETS[opts.preset] then
        w.appearance = WS.CleanAppearance(WS.COUNTER_PRESETS[opts.preset].overrides, "counter")
    end
    return w
end

-- Validates SoloMetricsDB.widgets in place (non-destructive for valid data).
function WS.ValidateAll(db)
    local src = type(db.widgets) == "table" and db.widgets or {}
    local sd = type(src.defaults) == "table" and src.defaults or {}
    local out = {
        nextId = math.floor(Num(src.nextId, 1, 1e9, 1)),
        order = {},
        byId = {},
        defaults = {
            appearance = WS.CleanAppearance(sd.appearance, "graph"),
            counter = WS.CleanAppearance(sd.counter, "counter"),
        },
    }
    local seen = {}
    if type(src.order) == "table" and type(src.byId) == "table" then
        for _, id in ipairs(src.order) do
            if type(id) == "string" and not seen[id] and #out.order < WS.MAX_WIDGETS then
                local w = WS.ValidateWidget(src.byId[id], id)
                if w then
                    out.byId[id] = w
                    out.order[#out.order + 1] = id
                    seen[id] = true
                    local n = tonumber(id:match("^w(%d+)$"))
                    if n and n >= out.nextId then out.nextId = n + 1 end
                end
            end
        end
    end
    db.widgets = out
end
