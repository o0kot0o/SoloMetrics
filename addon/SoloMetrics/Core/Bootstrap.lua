-- SoloMetrics: Bootstrap
-- SavedVariables init/migration, slash commands, module start-up.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "dev"

local DB_SCHEMA = 2
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
    width = 280,
    smoothBars = true,
    barScale = "top",          -- "top" (relative to top spell) | "total" (share of your total)
    barOrder = "range",        -- experiment: "range" (range then value) | "value" (value then range)
}

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
    if db.meter.barOrder ~= "range" and db.meter.barOrder ~= "value" then db.meter.barOrder = "range" end
    if db.meter.barScale ~= "top" and db.meter.barScale ~= "total" then db.meter.barScale = "top" end
    if db.meter.numberFormat ~= "compact" and db.meter.numberFormat ~= "full" then db.meter.numberFormat = "compact" end
    db.meter.maxRows = math.max(1, math.min(20, math.floor(db.meter.maxRows)))
    db.meter.width = math.max(180, math.min(600, db.meter.width))
    ns.db = db
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local PLANNED = {
    config = "M3",
    training = "M5", history = "M4", profile = "M5",
}

local commands = {}

function commands.help()
    ns.Print("v" .. ns.VERSION .. " commands:")
    ns.Print("  /sm - show/hide the meter")
    ns.Print("  /sm edit - unlock: drag to move, right-click switches Current/Overall")
    ns.Print("  /sm lock - lock in place and make click-through")
    ns.Print("  /sm session - switch Current fight / Overall")
    ns.Print("  /sm format - switch compact (12.3K) / full (12,345) numbers")
    ns.Print("  /sm rows <1-20> - max spell rows")
    ns.Print("  /sm bars - bar length: relative to top spell / share of total")
    ns.Print("  /sm smooth - toggle animated bars")
    ns.Print("  /sm test [seconds] [big] - simulated DEMO fight (fake numbers); again to clear")
    ns.Print("  /sm resetui - re-center and unlock the meter (keeps data)")
    ns.Print("  /sm version")
    ns.Print("  diagnostics: /sm debug, /sm probe, /sm watch, /sm rendertest, /sm copy")
end

function commands.version()
    ns.Print(("v%s, SavedVariables schema %d, load #%d"):format(ns.VERSION, ns.db.schema, ns.db.loadCount))
end

function commands.edit() ns.SpellMeter.SetLocked(false) end
function commands.lock() ns.SpellMeter.SetLocked(true) end
function commands.session() ns.SpellMeter.ToggleSession() end

function commands.format()
    local m = ns.db.meter
    m.numberFormat = (m.numberFormat == "compact") and "full" or "compact"
    ns.SpellMeter.MarkDirty()
    ns.Print("Number format: " .. m.numberFormat)
end

function commands.bars()
    local m = ns.db.meter
    m.barScale = (m.barScale == "top") and "total" or "top"
    ns.SpellMeter.MarkDirty()
    ns.Print(m.barScale == "top" and "Bars: relative to your top spell"
        or "Bars: share of your total damage")
end

function commands.barorder()
    local m = ns.db.meter
    m.barOrder = (m.barOrder == "range") and "value" or "range"
    ns.SpellMeter.MarkDirty()
    ns.Print("Bar update order (experiment): " .. (m.barOrder == "range" and "range then value" or "value then range"))
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

SLASH_SOLOMETRICS1 = "/sm"
SLASH_SOLOMETRICS2 = "/solometrics"
SlashCmdList["SOLOMETRICS"] = function(msg)
    local cmd, rest = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
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
    ns.Print(("v%s loaded. Type /sm help."):format(ns.VERSION))
end)
