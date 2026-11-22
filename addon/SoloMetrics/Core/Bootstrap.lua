-- SoloMetrics: Bootstrap
-- SavedVariables init/migration, slash commands, module start-up.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "dev"

local DB_SCHEMA = 3
local PREFIX = "|cff4fc3f7SoloMetrics|r: "

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------
local METER_DEFAULTS = {
    shown = true,
    locked = false,
    session = "current",       -- "current" | "overall"
    numberFormat = "compact",  -- "compact" (AbbreviateNumbers) | "full" (BreakUpLargeNumbers)
    maxRows = 8,
    smoothBars = true,
    grow = "down",             -- "down" (top edge fixed) | "up" (bottom edge fixed)
    minimapShown = true,
    minimapAngle = 225,
    barScale = "top",          -- "top" (relative to top spell) | "total" (share of your total)
}

ns.METER_DEFAULTS = METER_DEFAULTS

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(target[k]) ~= type(v) then target[k] = v end
    end
end

local function InitDB()
    if type(SoloMetricsDB) ~= "table" then
        SoloMetricsDB = {}
    end
    local db = SoloMetricsDB
    if type(db.loadCount) ~= "number" then db.loadCount = 0 end
    db.loadCount = db.loadCount + 1
    db.lastVersion = ns.VERSION

    -- schema 1 -> 2: M0 placeholder frame replaced by the meter
    db.m0Frame = nil
    db.schema = DB_SCHEMA

    if type(db.meter) ~= "table" then db.meter = {} end
    ApplyDefaults(db.meter, METER_DEFAULTS)
    if db.meter.session ~= "current" and db.meter.session ~= "overall" then db.meter.session = "current" end
    db.meter.barOrder = nil -- removed experiment
    db.meter.minimapAngle = db.meter.minimapAngle % 360
    if db.meter.grow ~= "down" and db.meter.grow ~= "up" then db.meter.grow = "down" end
    if db.meter.barScale ~= "top" and db.meter.barScale ~= "total" then db.meter.barScale = "top" end
    if db.meter.numberFormat ~= "compact" and db.meter.numberFormat ~= "full" then db.meter.numberFormat = "compact" end
    db.meter.maxRows = math.max(1, math.min(20, math.floor(db.meter.maxRows)))

    -- schema 3: appearance lives in style profiles (Appearance/Theme.lua)
    local oldWidth = db.meter.width
    db.meter.width = nil
    if type(db.profiles) ~= "table" then
        db.profiles = {}
    end
    if next(db.profiles) == nil then
        local style = ns.Theme.BuildPreset("modern")
        if type(oldWidth) == "number" then style.width = oldWidth end
        db.profiles.Default = style
    end
    for name, style in pairs(db.profiles) do
        if type(name) ~= "string" then
            db.profiles[name] = nil
        else
            db.profiles[name] = ns.Theme.Validate(style)
        end
    end
    -- per-character profile choices: { ["Name - Realm"] = profileName } (local only, never exported)
    if type(db.charProfile) ~= "table" then db.charProfile = {} end
    for k, v in pairs(db.charProfile) do
        if type(k) ~= "string" or type(v) ~= "string" or not db.profiles[v] then db.charProfile[k] = nil end
    end
    -- widgets (validated; malformed/unknown widgets are dropped, never crash load)
    ns.WidgetSchema.ValidateAll(db)

    if type(db.activeProfile) ~= "string" or not db.profiles[db.activeProfile] then
        db.activeProfile = next(db.profiles)
    end
    ns.db = db
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local PLANNED = {
    training = "M5", history = "M4",
}

local commands = {}

function commands.help()
    ns.Print("v" .. ns.VERSION .. " commands:")
    ns.Print("  /sm config - open the settings window")
    ns.Print("  /sm profile - profiles: switch, create, import/export")
    ns.Print("  /sm widget - graph widgets (new, list, edit, ...)")
    ns.Print("  /sm - show/hide the meter")
    ns.Print("  /sm minimap - show/hide the minimap button")
    ns.Print("  /sm edit - unlock: drag to move, right-click switches Current/Overall")
    ns.Print("  /sm lock - lock in place and make click-through")
    ns.Print("  /sm session - switch Current fight / Overall")
    ns.Print("  /sm format - switch compact (12.3K) / full (12,345) numbers")
    ns.Print("  /sm rows <1-20> - max spell rows")
    ns.Print("  /sm preset [name] - list or apply a style preset")
    ns.Print("  /sm get [prefix] - list style settings, e.g. /sm get text")
    ns.Print("  /sm set <setting> <value> - e.g. /sm set backdrop.enabled off")
    ns.Print("  /sm grow - grow direction: down (top fixed) / up (bottom fixed)")
    ns.Print("  /sm bars - bar length: relative to top spell / share of total")
    ns.Print("  /sm smooth - toggle animated bars")
    ns.Print("  /sm test [seconds] [big] - simulated DEMO fight (fake numbers); again to clear")
    ns.Print("  /sm resetui - re-center and unlock the meter (keeps data)")
    ns.Print("  /sm version")
    ns.Print("  diagnostics: /sm debug, /sm probe, /sm watch, /sm rendertest, /sm graphtest, /sm copy")
end

function commands.version()
    ns.Print(("v%s, SavedVariables schema %d, load #%d"):format(ns.VERSION, ns.db.schema, ns.db.loadCount))
end

function commands.config() ns.Config.Toggle() end
function commands.profile() ns.Config.Open("profiles") end
function commands.widget(rest) ns.WidgetManager.Command(rest) end
commands.widgets = commands.widget
function commands.edit() ns.SpellMeter.SetLocked(false) end
function commands.lock() ns.SpellMeter.SetLocked(true) end
function commands.session() ns.SpellMeter.ToggleSession() end

function commands.format()
    local m = ns.db.meter
    m.numberFormat = (m.numberFormat == "compact") and "full" or "compact"
    ns.SpellMeter.MarkDirty()
    ns.Print("Number format: " .. m.numberFormat)
end

function commands.preset(rest)
    local key = strtrim(rest or ""):lower()
    if key == "" or not ns.Theme.PRESETS[key] then
        ns.Print("Presets (apply with /sm preset <name>, replaces the current style):")
        for _, k in ipairs(ns.Theme.PRESET_ORDER) do
            ns.Print(("  %s - %s"):format(k, ns.Theme.PRESETS[k].label))
        end
        return
    end
    ns.db.profiles[ns.Profiles.ActiveName()] = ns.Theme.BuildPreset(key)
    ns.SpellMeter.ApplyStyle()
    ns.Print("Applied preset: " .. ns.Theme.PRESETS[key].label)
end

-- /sm set <path> <value>   e.g. /sm set backdrop.enabled off, /sm set bar.color ff8800cc
function commands.set(rest)
    local input, value = (rest or ""):match("^(%S+)%s+(.+)$")
    if not input then
        ns.Print("Usage: /sm set <setting> <value>  (list settings with /sm get)")
        return
    end
    local path = ns.Theme.ResolvePath(input)
    if not path then
        ns.Print("Not set: unknown setting '" .. input .. "' (see /sm get)")
        return
    end
    local v, err = ns.Theme.ParseValue(path, value)
    if v == nil then
        ns.Print("Not set: " .. err)
        return
    end
    ns.Theme.SetPath(ns.Theme.Active(), path, v)
    ns.SpellMeter.ApplyStyle()
    ns.Print(path .. " = " .. ns.Theme.FormatValue(ns.Theme.SCHEMA_BY_PATH[path], v))
end

-- /sm get [prefix]
function commands.get(rest)
    local prefix = strtrim(rest or ""):lower()
    local st = ns.Theme.Active()
    ns.Print(("Style settings (profile '%s')%s - colors are RRGGBBAA:"):format(
        ns.Profiles.ActiveName(), prefix ~= "" and (" matching '" .. prefix .. "'") or ""))
    for _, e in ipairs(ns.Theme.SCHEMA) do
        if prefix == "" or e[1]:lower():sub(1, #prefix) == prefix then
            local range = (e[2] == "number") and (" [" .. e[3] .. "-" .. e[4] .. "]") or (" (" .. e[2] .. ")")
            DEFAULT_CHAT_FRAME:AddMessage(("  %s = %s%s"):format(
                e[1], ns.Theme.FormatValue(e, ns.Theme.GetPath(st, e[1])), range))
        end
    end
end

function commands.minimap()
    local m = ns.db.meter
    m.minimapShown = not m.minimapShown
    ns.MinimapButton.Update()
    ns.Print("Minimap button " .. (m.minimapShown and "shown." or "hidden. /sm minimap or /sm config to bring it back."))
end

function commands.grow()
    local m = ns.db.meter
    m.grow = (m.grow == "down") and "up" or "down"
    ns.SpellMeter.ApplyMeterSetting("grow")
    ns.Print(m.grow == "up" and "Meter grows upward (bottom edge fixed)." or "Meter grows downward (top edge fixed).")
end

function commands.bars()
    local m = ns.db.meter
    m.barScale = (m.barScale == "top") and "total" or "top"
    ns.SpellMeter.MarkDirty()
    ns.Print(m.barScale == "top" and "Bars: relative to your top spell"
        or "Bars: share of your total damage")
end

function commands.smooth()
    local m = ns.db.meter
    m.smoothBars = not m.smoothBars
    if m.smoothBars and not ns.SpellMeter.SmoothingAvailable() then
        ns.Print("Bar smoothing ON, but this client has no native StatusBar interpolation - bars stay instant.")
    else
        ns.Print("Bar smoothing " .. (m.smoothBars and "ON" or "OFF"))
    end
end

function commands.rows(rest)
    local n = tonumber(rest)
    if not n then
        ns.Print("Usage: /sm rows <1-20> (now " .. ns.db.meter.maxRows .. ")")
        return
    end
    ns.db.meter.maxRows = math.max(1, math.min(20, math.floor(n)))
    ns.SpellMeter.MarkDirty()
    ns.Print("Max rows: " .. ns.db.meter.maxRows)
end

function commands.resetui()
    ns.SpellMeter.ResetPosition()
    ns.Print("Meter re-centered and unlocked.")
end

function commands.debug() ns.Diagnostics.Run() end
function commands.probe(rest) ns.Diagnostics.Probe(rest) end
function commands.watch() ns.Diagnostics.ToggleWatch() end
function commands.rendertest() ns.Diagnostics.ToggleRenderTest() end
function commands.copy() ns.Diagnostics.ShowCopy() end
function commands.test(rest) ns.Demo.Toggle(rest) end
function commands.bardebug() ns.Diagnostics.BarDebug() end
function commands.graphtest(rest) ns.Diagnostics.ToggleGraphTest(rest) end

SLASH_SOLOMETRICS1 = "/sm"
SLASH_SOLOMETRICS2 = "/solometrics"
SlashCmdList["SOLOMETRICS"] = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.SpellMeter.Toggle()
    elseif commands[cmd] then
        commands[cmd](rest)
    elseif PLANNED[cmd] then
        ns.Print("/sm " .. cmd .. " is not implemented yet (planned for " .. PLANNED[cmd] .. ").")
    else
        ns.Print("Unknown command '" .. cmd .. "'. Type /sm help.")
    end
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    InitDB()
    ns.SpellMeter.Init()
    ns.MinimapButton.Init()
    ns.WidgetManager.Init()
    ns.Print(("v%s loaded. Type /sm help."):format(ns.VERSION))
end)
