-- SoloMetrics: widget schema (records, appearance overrides, validation)
-- Widgets live in SoloMetricsDB.widgets = { nextId, order = {ids}, byId = {id -> record},
-- defaults = { appearance = {path -> value} } }.
-- A widget's `appearance` holds ONLY its overrides (flat path -> value).
-- Effective value: widget override -> user defaults -> built-in default.

local _, ns = ...
local WS = {}
ns.WidgetSchema = WS

WS.MAX_WIDGETS = 12
WS.MAX_SAMPLES = 60

-- Live metrics (opaque samples during combat)
WS.METRICS = {
    dps = "Average DPS so far",
    damage = "Total damage",
}
WS.METRIC_ORDER = { "dps", "damage" }
-- Per-fight metrics (readable, one point per completed fight)
WS.FIGHT_METRICS = {
    damage = "Damage per fight",
    dps = "DPS per fight",
    share = "Share of your damage per fight",
}
WS.FIGHT_METRIC_ORDER = { "damage", "dps", "share" }
WS.MAX_FIGHTS = 30 -- the client keeps the last 30 sessions
WS.STYLES = { area = "Area", bars = "Columns", line = "Line", points = "Points" }
WS.STYLE_ORDER = { "area", "bars", "line", "points" }
WS.VISIBILITY = { always = "Always", combat = "In combat", nocombat = "Out of combat", hidden = "Hidden" }
WS.VIS_ORDER = { "always", "combat", "nocombat", "hidden" }

---------------------------------------------------------------------------
-- Appearance (flat paths; types shared with Theme validation)
---------------------------------------------------------------------------
WS.APPEARANCE_DEFAULTS = {
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

WS.APPEARANCE_SCHEMA = {
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
local SCHEMA_BY_PATH = {}
for _, e in ipairs(WS.APPEARANCE_SCHEMA) do SCHEMA_BY_PATH[e[1]] = e end
WS.APPEARANCE_BY_PATH = SCHEMA_BY_PATH

local function CopyValue(v)
    if type(v) == "table" then return { v[1], v[2], v[3], v[4] or 1 } end
    return v
end

function WS.IsValidAppearance(path, v)
    local e = SCHEMA_BY_PATH[path]
    return e ~= nil and ns.Theme.IsValidEntry(e, v)
end

-- Keep only known paths with valid values.
function WS.CleanAppearance(map)
    local out = {}
    if type(map) ~= "table" then return out end
    for path, v in pairs(map) do
        if type(path) == "string" and WS.IsValidAppearance(path, v) then
            out[path] = CopyValue(v)
        end
    end
    return out
end

function WS.Get(w, path)
    local v = w.appearance[path]
    if v ~= nil then return v end
    local d = ns.db.widgets.defaults.appearance[path]
    if d ~= nil then return d end
    return WS.APPEARANCE_DEFAULTS[path]
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

function WS.Label(w)
    local d = w.data
    if d.kind == "fights" then
        local s = WS.FIGHT_METRICS[d.metric]
        if d.spellID then s = (d.spellName or ("Spell " .. d.spellID)) .. ": " .. s end
        return s
    end
    local s = WS.METRICS[d.metric]
    if d.session == "overall" then s = s .. " (overall)" end
    return s
end

function WS.ValidateWidget(raw, id)
    if type(raw) ~= "table" or type(id) ~= "string" then return nil end
    if raw.type ~= "graph" then return nil end -- unknown types are dropped, never crash load
    local d = type(raw.data) == "table" and raw.data or {}
    local g = type(raw.graph) == "table" and raw.graph or {}
    local b = type(raw.behavior) == "table" and raw.behavior or {}
    local p = type(raw.position) == "table" and raw.position or {}
    local name = type(raw.name) == "string" and strtrim(raw.name) or ""
    if name == "" or #name > 32 then name = "Widget" end
    return {
        id = id,
        type = "graph",
        name = name,
        data = WS.ValidateData(d),
        graph = {
            style = OneOf(g.style, WS.STYLES, "area"),
            samples = math.floor(Num(g.samples, 10, WS.MAX_SAMPLES, 30)),
            interval = Num(g.interval, 0.5, 5, 1),
            -- auto: 0..last fight x headroom; fixed: 0..scaleMax;
            -- focus: 50%..150% of last fight's final value (zoomed; clips outside)
            scaleMode = OneOf(g.scaleMode, { auto = true, fixed = true, focus = true }, "auto"),
            scaleMax = Num(g.scaleMax, 1, 1e9, 100),
            autoMax = (type(g.autoMax) == "number" and g.autoMax > 0) and g.autoMax or nil,
            autoBase = (type(g.autoBase) == "number" and g.autoBase > 0) and g.autoBase or nil,
        },
        behavior = {
            visibility = OneOf(b.visibility, WS.VISIBILITY, "always"),
            locked = b.locked == true,
            clickThrough = b.clickThrough == true,
        },
        position = {
            x = Num(p.x, -10000, 10000, 300),
            y = Num(p.y, -10000, 10000, 500),
            width = Num(p.width, 120, 900, 260),
            height = Num(p.height, 60, 500, 120),
            scale = Num(p.scale, 0.5, 2, 1),
        },
        appearance = WS.CleanAppearance(raw.appearance),
    }
end

function WS.NewWidget(id, opts)
    opts = opts or {}
    local data = WS.ValidateData({
        kind = opts.kind, metric = opts.metric, session = opts.session,
        spellID = opts.spellID, spellName = opts.spellName,
    })
    local w = WS.ValidateWidget({
        type = "graph",
        name = "Widget",
        data = data,
        graph = { style = opts.style or (data.kind == "fights" and "bars" or nil) },
        behavior = {},
        position = opts.position or {},
        appearance = {},
    }, id)
    w.name = (opts.name or WS.Label(w)):sub(1, 32)
    return w
end

-- Validates SoloMetricsDB.widgets in place (non-destructive for valid data).
function WS.ValidateAll(db)
    local src = type(db.widgets) == "table" and db.widgets or {}
    local out = {
        nextId = math.floor(Num(src.nextId, 1, 1e9, 1)),
        order = {},
        byId = {},
        defaults = { appearance = WS.CleanAppearance(src.defaults and src.defaults.appearance) },
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
