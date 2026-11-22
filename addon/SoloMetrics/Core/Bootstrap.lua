-- SoloMetrics: Bootstrap
-- M0 scaffold: SavedVariables init, slash commands, minimal status frame.
-- No damage meter data is read here.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "dev"

local DB_SCHEMA = 1
local PREFIX = "|cff4fc3f7SoloMetrics|r: "

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------
local function InitDB()
    if type(SoloMetricsDB) ~= "table" then
        SoloMetricsDB = {}
    end
    local db = SoloMetricsDB
    if type(db.schema) ~= "number" then db.schema = DB_SCHEMA end
    if type(db.loadCount) ~= "number" then db.loadCount = 0 end
    db.loadCount = db.loadCount + 1
    db.lastVersion = ns.VERSION
    if type(db.m0Frame) ~= "table" then db.m0Frame = { shown = true } end
    ns.db = db
end

---------------------------------------------------------------------------
-- M0 status frame (placeholder, replaced by WidgetManager in M2/M3)
---------------------------------------------------------------------------
local statusFrame

local function ApplyStatusPosition()
    local f = statusFrame
    local p = ns.db.m0Frame.point
    f:ClearAllPoints()
    if type(p) == "table" and type(p[1]) == "string" then
        f:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function CreateStatusFrame()
    local f = CreateFrame("Frame", "SoloMetricsM0Frame", UIParent)
    f:SetSize(250, 50)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.db.m0Frame.point = { point, relPoint, x, y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.09, 0.85)

    local accent = f:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(3)
    accent:SetColorTexture(0.31, 0.76, 0.97, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("SoloMetrics " .. ns.VERSION)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("M0 scaffold loaded - /sm help")

    statusFrame = f
    ApplyStatusPosition()
    f:SetShown(ns.db.m0Frame.shown ~= false)
end

local function ToggleStatusFrame()
    local show = not statusFrame:IsShown()
    statusFrame:SetShown(show)
    ns.db.m0Frame.shown = show
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local PLANNED = {
    config = "M3", edit = "M3", lock = "M3", test = "M3",
    training = "M5", history = "M4", profile = "M5",
}

local commands = {}

function commands.help()
    ns.Print("v" .. ns.VERSION .. " commands:")
    ns.Print("  /sm - show/hide the meter frame")
    ns.Print("  /sm debug - client build + C_DamageMeter capability probe")
    ns.Print("  /sm probe [dps] [sessionID] - dump session/source/spell data shapes")
    ns.Print("  /sm watch - toggle secret/readable field report around each fight")
    ns.Print("  /sm rendertest - toggle live secret-rendering test panel")
    ns.Print("  /sm copy - copyable window with the last report")
    ns.Print("  /sm resetui - re-center and show frames (does not touch combat data)")
    ns.Print("  /sm version - print version and load count")
end

function commands.version()
    ns.Print(("v%s, SavedVariables schema %d, load #%d"):format(ns.VERSION, ns.db.schema, ns.db.loadCount))
end

function commands.debug()
    ns.Diagnostics.Run()
end

function commands.probe(rest)
    ns.Diagnostics.Probe(rest)
end

function commands.watch()
    ns.Diagnostics.ToggleWatch()
end

function commands.rendertest()
    ns.Diagnostics.ToggleRenderTest()
end

function commands.copy()
    ns.Diagnostics.ShowCopy()
end

function commands.resetui()
    ns.db.m0Frame.point = nil
    ns.db.m0Frame.shown = true
    ApplyStatusPosition()
    statusFrame:Show()
    ns.Print("UI positions reset.")
end

SLASH_SOLOMETRICS1 = "/sm"
SLASH_SOLOMETRICS2 = "/solometrics"
SlashCmdList["SOLOMETRICS"] = function(msg)
    local cmd, rest = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" then
        ToggleStatusFrame()
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
    CreateStatusFrame()
    ns.Print(("v%s loaded (load #%d). Type /sm help."):format(ns.VERSION, ns.db.loadCount))
end)
