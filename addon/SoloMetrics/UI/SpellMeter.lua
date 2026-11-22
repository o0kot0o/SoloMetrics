-- SoloMetrics: SpellMeter (M2 live personal meter)
-- Header: DPS, total damage, session label, timer. Rows: spell icon, name,
-- bar (relative to top spell), damage, DPS - live in combat via opaque
-- passthrough to native setters (D-005). Rows are pooled.

local _, ns = ...
local M = {}
ns.SpellMeter = M

local WHITE = "Interface\\Buttons\\WHITE8X8"
local HEADER_H = 24
local ROW_H = 18
local ROW_GAP = 1
local ICON = 18
local PAD = 4
local THROTTLE = 0.2     -- event-driven: max 5 full renders/sec
local COMBAT_POLL = 0.1  -- in combat: refresh text 10x/sec; API recomputes DPS
                         -- continuously (observed: DPS ticks down between hits)

local frame, header
local rows = {}
local dirty = true
local accum = 0

local function Cfg() return ns.db.meter end

-- Native bar smoothing: the engine animates toward the new value itself, so it
-- works with secret values (no Lua interpolation of protected numbers).
-- Disabled automatically if the client rejects the argument.
local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function SetBarValue(bar, v)
    if smoothing and Cfg().smoothBars then
        local ok = pcall(bar.SetValue, bar, v, smoothing)
        if ok then return end
        smoothing = nil
        ns.Print("Bar smoothing not supported by this client; using instant bars.")
    end
    bar:SetValue(v)
end

-- Plain SetMinMaxValues: verified to accept secret max in combat (rendertest).
-- An interpolation 3rd argument was tried and caused ranges not to apply in
-- combat (bars then shrank at combat end) - do not reintroduce untested.
local function SetBarRange(bar, maxV)
    bar:SetMinMaxValues(0, maxV)
end

function M.SmoothingAvailable()
    return smoothing ~= nil
end

---------------------------------------------------------------------------
-- Formatting (v may be secret: only native functions touch it)
---------------------------------------------------------------------------
local function SetNumber(fs, v)
    if type(v) ~= "number" then
        fs:SetText("-")
    elseif Cfg().numberFormat == "full" then
        fs:SetText(BreakUpLargeNumbers(v))
    else
        fs:SetText(AbbreviateNumbers(v))
    end
end

-- Rates (DPS): one decimal via native SetFormattedText (accepts secrets).
-- AbbreviateNumbers leaves small floats at full precision ("5.0270...").
local function SetRate(fs, v)
    if type(v) ~= "number" then
        fs:SetText("-")
    else
        fs:SetFormattedText("%.1f", v)
    end
end

local function FormatTime(d)
    if type(d) ~= "number" then return "0:00" end
    return ("%d:%02d"):format(math.floor(d / 60), math.floor(d % 60))
end

local function ClassColor(classFilename)
    local c = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if c then return c.r, c.g, c.b end
    return 0.31, 0.76, 0.97
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
local function NewText(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function CreateRow(i)
    local r = CreateFrame("StatusBar", nil, frame)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + ICON + 2, -(HEADER_H + (i - 1) * (ROW_H + ROW_GAP)))
    r:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    r:SetStatusBarTexture(WHITE)
    r:SetMinMaxValues(0, 1)
    r:SetValue(0)

    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("RIGHT", r, "LEFT", -2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.dps = NewText(r, "GameFontHighlightSmall", "RIGHT")
    r.dps:SetPoint("RIGHT", -4, 0)
    r.dps:SetWidth(50)

    r.amount = NewText(r, "GameFontHighlightSmall", "RIGHT")
    r.amount:SetPoint("RIGHT", r.dps, "LEFT", -4, 0)
    r.amount:SetWidth(46)

    r.name = NewText(r, "GameFontHighlightSmall", "LEFT")
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetPoint("RIGHT", r.amount, "LEFT", -4, 0)

    rows[i] = r
    return r
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    Cfg().point = { point, relPoint, x, y }
end

local function ApplyPosition()
    local p = Cfg().point
    frame:ClearAllPoints()
    if type(p) == "table" and type(p[1]) == "string" then
        frame:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

local function ApplyLock()
    -- Locked = click-through (no mouse at all). Unlock with /sm edit.
    frame:EnableMouse(not Cfg().locked)
end

local function CreateMeter()
    frame = CreateFrame("Frame", "SoloMetricsMeter", UIParent)
    frame:SetWidth(Cfg().width)
    frame:SetHeight(HEADER_H + PAD)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not Cfg().locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then M.ToggleSession() end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.07, 0.08, 0.78)

    header = {}
    local accent = frame:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    header.accent = accent

    local dpsLabel = NewText(frame, "GameFontDisableSmall")
    dpsLabel:SetPoint("TOPLEFT", PAD + 2, -8)
    dpsLabel:SetText("DPS")
    header.dps = NewText(frame, "GameFontHighlight")
    header.dps:SetPoint("LEFT", dpsLabel, "RIGHT", 4, 0)
    header.dps:SetWidth(60)

    local totalLabel = NewText(frame, "GameFontDisableSmall")
    totalLabel:SetPoint("LEFT", dpsLabel, "LEFT", 96, 0)
    totalLabel:SetText("DMG")
    header.total = NewText(frame, "GameFontHighlight")
    header.total:SetPoint("LEFT", totalLabel, "RIGHT", 4, 0)
    header.total:SetWidth(60)

    header.timer = NewText(frame, "GameFontHighlightSmall", "RIGHT")
    header.timer:SetPoint("TOPRIGHT", -PAD - 2, -8)

    header.session = NewText(frame, "GameFontDisableSmall", "RIGHT")
    header.session:SetPoint("RIGHT", header.timer, "LEFT", -6, 0)

    header.empty = NewText(frame, "GameFontDisableSmall", "CENTER")
    header.empty:SetPoint("TOPLEFT", PAD, -HEADER_H)
    header.empty:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    header.empty:SetText("No damage yet")

    frame:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if dirty and accum >= THROTTLE then
            accum = 0
            M.Render(true)
        elseif accum >= COMBAT_POLL and (InCombatLockdown() or ns.Demo.IsRunning()) then
            -- text/timer only: re-setting bars would restart their animation
            accum = 0
            M.Render(false)
        end
    end)
    frame:SetScript("OnShow", function() dirty = true end)

    ApplyPosition()
    ApplyLock()
end

---------------------------------------------------------------------------
-- Render (single path for in-combat opaque and post-combat readable data)
---------------------------------------------------------------------------
function M.Render(updateBars)
    if updateBars == nil then updateBars = true end
    if updateBars then dirty = false end
    local cfg = Cfg()
    local snap
    if ns.Demo.IsActive() then
        snap = ns.Demo.Snapshot()
    else
        snap = ns.API.Snapshot(cfg.session)
    end

    local r, g, b = ClassColor(snap.classFilename)
    header.accent:SetColorTexture(r, g, b, 0.9)
    header.timer:SetText(FormatTime(snap.duration))
    if snap.demo then
        header.session:SetText("|cffff9900DEMO|r")
    else
        header.session:SetText(cfg.session == "overall" and "Overall" or "Current")
    end
    if snap.hasPlayer then SetRate(header.dps, snap.dps) else header.dps:SetText("-") end
    SetNumber(header.total, snap.total)

    local n = math.min(snap.spellCount, cfg.maxRows)
    local getTex = C_Spell and C_Spell.GetSpellTexture
    local getName = C_Spell and C_Spell.GetSpellName
    -- Bar scale: "top" = relative to top spell; "total" = share of player total.
    local maxV = (cfg.barScale == "total") and snap.total or snap.max
    local hasMax = type(maxV) == "number"
    for i = 1, n do
        local isNew = not rows[i] or not rows[i]:IsShown()
        local row = rows[i] or CreateRow(i)
        local sp = snap.spells[i]
        if type(sp) == "table" then
            row:SetStatusBarColor(r, g, b, 0.75)
            if hasMax and (updateBars or isNew) then
                SetBarRange(row, maxV)
                SetBarValue(row, sp.totalAmount)
            end
            if getTex then row.icon:SetTexture(getTex(sp.spellID)) end
            if getName then row.name:SetText(getName(sp.spellID)) end
            SetNumber(row.amount, sp.totalAmount)
            SetRate(row.dps, sp.amountPerSecond)
            row:Show()
        else
            row:Hide()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end

    header.empty:SetShown(n == 0)
    local bodyRows = (n > 0) and n or 1
    frame:SetHeight(HEADER_H + bodyRows * (ROW_H + ROW_GAP) + PAD)
end

---------------------------------------------------------------------------
-- Public controls
---------------------------------------------------------------------------
function M.MarkDirty() dirty = true end

function M.GetRows() return rows end

-- New fight: empty all bars instantly so reused rows don't show stale values.
function M.ResetBars()
    for _, row in ipairs(rows) do
        row:SetMinMaxValues(0, 1)
        row:SetValue(0)
    end
end

function M.Show()
    frame:Show()
    Cfg().shown = true
end

function M.Toggle()
    local show = not frame:IsShown()
    frame:SetShown(show)
    Cfg().shown = show
end

function M.ToggleSession()
    Cfg().session = (Cfg().session == "overall") and "current" or "overall"
    dirty = true
    ns.Print("Showing " .. Cfg().session .. " session.")
end

function M.SetLocked(locked)
    Cfg().locked = locked and true or false
    ApplyLock()
    ns.Print(locked and "Meter locked (click-through). /sm edit to unlock."
        or "Meter unlocked: drag to move, right-click to switch Current/Overall. /sm lock when done.")
end

function M.ResetPosition()
    Cfg().point = nil
    Cfg().shown = true
    Cfg().locked = false
    ApplyPosition()
    ApplyLock()
    frame:Show()
    dirty = true
end

function M.Init()
    CreateMeter()
    local ev = CreateFrame("Frame")
    for _, e in ipairs(ns.API.EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ns.Demo.Stop("real combat started")
            if Cfg().session == "current" then M.ResetBars() end
        end
        dirty = true
    end)
    frame:SetShown(Cfg().shown ~= false)
    if not ns.API.IsAvailable() then
        ns.Print("Native damage meter reports unavailable; meter may stay empty.")
    end
end
