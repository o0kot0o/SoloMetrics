-- SoloMetrics: SpellMeter (live personal meter, styled)
-- Every visual layer comes from the active style (Appearance/Theme.lua):
-- backdrop, border, accent, header, rows, icons, bar fill/background, texts.
-- Alpha is applied per region (never via the parent frame), so a hidden
-- backdrop never fades bars or text.
-- Data path: opaque passthrough of secret values to native setters (D-005).

local _, ns = ...
local M = {}
ns.SpellMeter = M

local THROTTLE = 0.2     -- event-driven: max 5 full renders/sec
local COMBAT_POLL = 0.1  -- in combat: refresh text 10x/sec; API recomputes DPS
                         -- continuously (observed: DPS ticks down between hits)

local frame, header, edges, overlay
local rows = {}
local dirty = true
local accum, pollAccum = 0, 0
local lastRowCount = 0

local function Cfg() return ns.db.meter end
local function Style() return ns.Theme.Active() end

---------------------------------------------------------------------------
-- Bars: native smoothing (engine-side, works with secret values)
---------------------------------------------------------------------------
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

-- Plain SetMinMaxValues: verified to accept a secret max in combat (rendertest).
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

-- Rates: one decimal via native SetFormattedText (accepts secrets).
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
    return nil
end

---------------------------------------------------------------------------
-- Style helpers
---------------------------------------------------------------------------
-- shadow: false/nil = none, true = default, or { color = {r,g,b,a}, offset = n }
local function ApplyFont(fs, fontKey, size, outline, shadow, color)
    local flags = ns.Theme.OUTLINES[outline] or ""
    fs:SetFont(ns.Theme.FontPath(fontKey), size, flags)
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
    if shadow then
        local sc = (type(shadow) == "table" and shadow.color) or { 0, 0, 0, 0.9 }
        local off = (type(shadow) == "table" and shadow.offset) or 1
        fs:SetShadowOffset(off, -off)
        fs:SetShadowColor(sc[1], sc[2], sc[3], sc[4] or 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

local function SetTextureColor(tex, path, c)
    tex:SetTexture(path)
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

local function IconWidth(st)
    if not st.icon.enabled then return 0 end
    return st.icon.matchRow and st.rows.height or st.icon.size
end

local function NewText(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function MakeEdges(parent, layer)
    local e = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        e[side] = parent:CreateTexture(nil, layer)
    end
    return e
end

local function LayoutEdges(e, parent, size, r, g, b, a, shown)
    e.top:ClearAllPoints()
    e.top:SetPoint("TOPLEFT", parent, "TOPLEFT")
    e.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    e.top:SetHeight(size)
    e.bottom:ClearAllPoints()
    e.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    e.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    e.bottom:SetHeight(size)
    e.left:ClearAllPoints()
    e.left:SetPoint("TOPLEFT", parent, "TOPLEFT")
    e.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    e.left:SetWidth(size)
    e.right:ClearAllPoints()
    e.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    e.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    e.right:SetWidth(size)
    for _, t in pairs(e) do
        t:SetColorTexture(r, g, b, a)
        t:SetShown(shown)
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function HeaderHeight(st)
    return st.header.enabled and st.header.height or 0
end

local function RowsTop(st)
    local hh = HeaderHeight(st)
    return (hh > 0) and hh or st.padding
end

local function LayoutRow(r, i, st)
    local rh, sp, pad = st.rows.height, st.rows.spacing, st.padding
    local ic = st.icon
    local iconW = IconWidth(st)
    r:ClearAllPoints()
    r:SetHeight(rh)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + (iconW > 0 and iconW + ic.gap or 0), -(RowsTop(st) + (i - 1) * (rh + sp)))
    r:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)

    r:SetStatusBarTexture(ns.Theme.TexturePath(st.bar.texture))
    r.bg:SetShown(st.barBg.enabled)
    SetTextureColor(r.bg, ns.Theme.TexturePath(st.barBg.texture), st.barBg.color)

    r.icon:ClearAllPoints()
    r.icon:SetPoint("RIGHT", r, "LEFT", -ic.gap, 0)
    r.icon:SetSize(iconW > 0 and iconW or 1, iconW > 0 and iconW or 1)
    r.icon:SetShown(ic.enabled)
    r.icon:SetAlpha(ic.alpha)
    r.icon:SetTexCoord(ic.crop, 1 - ic.crop, ic.crop, 1 - ic.crop)
    local bc = ic.borderColor
    LayoutEdges(r.iconBorder, r.icon, 1, bc[1], bc[2], bc[3], bc[4], ic.enabled and ic.border)

    local tx = st.text
    local shadow = tx.shadow and { color = tx.shadowColor, offset = tx.shadowOffset } or false
    ApplyFont(r.name, tx.font, tx.size, tx.outline, shadow, tx.name.color)
    ApplyFont(r.amount, tx.font, tx.size, tx.outline, shadow, tx.amount.color)
    ApplyFont(r.dps, tx.font, tx.size, tx.outline, shadow, tx.dps.color)
    r.name:SetShown(tx.name.enabled)
    r.amount:SetShown(tx.amount.enabled)
    r.dps:SetShown(tx.dps.enabled)
    r.name:SetJustifyH(ns.Theme.ALIGNS[tx.name.align] or "LEFT")
    r.amount:SetJustifyH(ns.Theme.ALIGNS[tx.amount.align] or "RIGHT")
    r.dps:SetJustifyH(ns.Theme.ALIGNS[tx.dps.align] or "RIGHT")

    r.dps:ClearAllPoints()
    r.amount:ClearAllPoints()
    r.name:ClearAllPoints()
    local anchor, point = r, "RIGHT"
    if tx.dps.enabled then
        r.dps:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.dps:SetWidth(tx.columnWidth)
        anchor, point = r.dps, "LEFT"
    end
    if tx.amount.enabled then
        r.amount:SetPoint("RIGHT", anchor, point, -4, 0)
        r.amount:SetWidth(tx.columnWidth)
        anchor, point = r.amount, "LEFT"
    end
    r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name:SetPoint("RIGHT", anchor, point, -4, 0)
end

local function CreateRow(i)
    local r = CreateFrame("StatusBar", nil, frame)
    r:SetMinMaxValues(0, 1)
    r:SetValue(0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.iconBorder = MakeEdges(r, "OVERLAY")
    r.name = NewText(r, "LEFT")
    r.amount = NewText(r, "RIGHT")
    r.dps = NewText(r, "RIGHT")
    rows[i] = r
    LayoutRow(r, i, Style())
    return r
end

local function LayoutHeader(st)
    local h = st.header
    local hh = HeaderHeight(st)
    local pad = st.padding
    local labelSize = math.max(6, math.floor(h.size * 0.8 + 0.5))

    ApplyFont(header.dpsLabel, h.font, labelSize, h.outline, false, h.labelColor)
    ApplyFont(header.totalLabel, h.font, labelSize, h.outline, false, h.labelColor)
    ApplyFont(header.session, h.font, labelSize, h.outline, false, h.labelColor)
    ApplyFont(header.dps, h.font, h.size, h.outline, false, h.valueColor)
    ApplyFont(header.total, h.font, h.size, h.outline, false, h.valueColor)
    ApplyFont(header.timer, h.font, labelSize, h.outline, false, h.valueColor)

    local y = -hh / 2
    for _, fs in pairs({ header.dpsLabel, header.dps, header.totalLabel, header.total, header.session, header.timer }) do
        fs:ClearAllPoints()
    end
    local x = pad + 2
    if h.showDps then
        header.dpsLabel:SetPoint("LEFT", frame, "TOPLEFT", x, y)
        header.dps:SetPoint("LEFT", header.dpsLabel, "RIGHT", 4, 0)
        header.dps:SetWidth(h.size * 4.5)
    end
    if h.showTotal then
        if h.showDps then
            header.totalLabel:SetPoint("LEFT", header.dps, "RIGHT", 6, 0)
        else
            header.totalLabel:SetPoint("LEFT", frame, "TOPLEFT", x, y)
        end
        header.total:SetPoint("LEFT", header.totalLabel, "RIGHT", 4, 0)
        header.total:SetWidth(h.size * 4.5)
    end
    header.timer:SetPoint("RIGHT", frame, "TOPRIGHT", -pad - 2, y)
    if h.showTimer then
        header.session:SetPoint("RIGHT", header.timer, "LEFT", -6, 0)
    else
        header.session:SetPoint("RIGHT", frame, "TOPRIGHT", -pad - 2, y)
    end

    local on = h.enabled
    header.dpsLabel:SetShown(on and h.showDps)
    header.dps:SetShown(on and h.showDps)
    header.totalLabel:SetShown(on and h.showTotal)
    header.total:SetShown(on and h.showTotal)
    header.timer:SetShown(on and h.showTimer)
    header.session:SetShown(on and h.showSession)
end

-- Re-applies the whole style. Cheap; called on style change, not per update.
function M.ApplyStyle()
    if not frame then return end
    local st = Style()
    if math.abs(frame:GetScale() - st.scale) > 0.001 and frame:GetLeft() then
        -- keep the fixed edge at the same screen position across scale changes
        -- (anchor offsets are in the frame's own scaled units)
        local up = Cfg().grow == "up"
        local es = frame:GetEffectiveScale()
        local sx = frame:GetLeft() * es
        local sy = (up and frame:GetBottom() or frame:GetTop()) * es
        frame:SetScale(st.scale)
        local ns2 = frame:GetEffectiveScale()
        local point = up and "BOTTOMLEFT" or "TOPLEFT"
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, "BOTTOMLEFT", sx / ns2, sy / ns2)
        Cfg().point = { point, "BOTTOMLEFT", sx / ns2, sy / ns2 }
    else
        frame:SetScale(st.scale)
    end
    frame:SetWidth(st.width)

    local c = st.backdrop.color
    SetTextureColor(frame.bg, ns.Theme.TexturePath(st.backdrop.texture), c)
    frame.bg:SetShown(st.backdrop.enabled)

    local hb = st.header.bg
    header.bgTex:ClearAllPoints()
    header.bgTex:SetPoint("TOPLEFT")
    header.bgTex:SetPoint("TOPRIGHT")
    header.bgTex:SetHeight(math.max(HeaderHeight(st), 1))
    header.bgTex:SetColorTexture(hb.color[1], hb.color[2], hb.color[3], hb.color[4])
    header.bgTex:SetShown(st.header.enabled and hb.enabled)

    c = st.border.color
    LayoutEdges(edges, frame, st.border.size, c[1], c[2], c[3], c[4], st.border.enabled)

    header.accent:SetHeight(st.accent.height)
    header.accent:SetShown(st.accent.enabled)

    LayoutHeader(st)
    ApplyFont(header.empty, st.text.font, st.text.size, st.text.outline, st.text.shadow, { 0.6, 0.6, 0.6, 1 })
    header.empty:ClearAllPoints()
    header.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", st.padding, -RowsTop(st))
    header.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -st.padding, -RowsTop(st))
    header.empty:SetHeight(st.rows.height)

    for i, r in ipairs(rows) do LayoutRow(r, i, st) end
    M.UpdateOverlay()
    dirty = true
end

---------------------------------------------------------------------------
-- Position, lock, edit overlay
---------------------------------------------------------------------------
-- Anchor the meter by the edge that must stay fixed: TOPLEFT when growing
-- down, BOTTOMLEFT when growing up (so rows extend upward from a meter placed
-- at the bottom of the screen). Keeps the current on-screen position.
local function Reanchor()
    local left = frame:GetLeft()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (left and top and bottom) then return end
    local up = Cfg().grow == "up"
    local point = up and "BOTTOMLEFT" or "TOPLEFT"
    local y = up and bottom or top
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "BOTTOMLEFT", left, y)
    Cfg().point = { point, "BOTTOMLEFT", left, y }
end

local function SavePosition()
    Reanchor()
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

-- Outline shown while unlocked so an invisible (no-backdrop) meter can be found.
function M.UpdateOverlay()
    local show = not Cfg().locked
    for _, t in pairs(overlay.edges) do t:SetShown(show) end
    overlay.label:SetShown(show)
end

local function ApplyLock()
    -- Locked = click-through (no mouse at all). Unlock with /sm edit.
    frame:EnableMouse(not Cfg().locked)
    M.UpdateOverlay()
    dirty = true
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function CreateMeter()
    frame = CreateFrame("Frame", "SoloMetricsMeter", UIParent)
    frame:SetHeight(40)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not Cfg().locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- position is ours (SavedVariables), not the client's layout cache
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        SavePosition()
    end)
    -- Right-click a spell row: spell widget menu. Right-click elsewhere:
    -- switch Current/Overall. (Locked = click-through, so neither fires.)
    frame:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        for i, row in ipairs(rows) do
            if row:IsShown() and row:IsMouseOver() then
                M.OnSpellRightClick(i)
                return
            end
        end
        M.ToggleSession()
    end)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    edges = MakeEdges(frame, "BORDER")

    header = {}
    header.bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    header.accent = frame:CreateTexture(nil, "ARTWORK")
    header.accent:SetPoint("TOPLEFT")
    header.accent:SetPoint("TOPRIGHT")
    header.dpsLabel = NewText(frame)
    header.dpsLabel:SetText("DPS")
    header.dps = NewText(frame)
    header.totalLabel = NewText(frame)
    header.totalLabel:SetText("DMG")
    header.total = NewText(frame)
    header.timer = NewText(frame, "RIGHT")
    header.session = NewText(frame, "RIGHT")
    header.empty = NewText(frame, "CENTER")
    header.empty:SetText("No damage yet")

    overlay = { edges = MakeEdges(frame, "OVERLAY") }
    LayoutEdges(overlay.edges, frame, 1, 0.31, 0.76, 0.97, 0.7, false)
    overlay.label = NewText(frame, "LEFT")
    overlay.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    overlay.label:SetTextColor(0.31, 0.76, 0.97, 1)
    overlay.label:SetText("SoloMetrics (unlocked - drag to move, /sm lock when done)")

    -- Separate clocks: the 10 Hz text poll must not starve the event-driven
    -- full render (a shared accumulator froze bars for the whole fight).
    frame:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        pollAccum = pollAccum + elapsed
        if dirty and accum >= THROTTLE then
            accum = 0
            pollAccum = 0
            M.Render(true)
        elseif pollAccum >= COMBAT_POLL and (InCombatLockdown() or ns.Demo.IsRunning()) then
            -- text/timer only: re-setting bars would restart their animation
            pollAccum = 0
            M.Render(false)
        end
    end)
    frame:SetScript("OnShow", function() dirty = true end)

    ApplyPosition()
    M.ApplyStyle()
    ApplyLock()
end

---------------------------------------------------------------------------
-- Render (single path for in-combat opaque and post-combat readable data)
---------------------------------------------------------------------------
function M.Render(updateBars)
    if updateBars == nil then updateBars = true end
    if updateBars then dirty = false end
    local cfg = Cfg()
    local st = Style()

    local snap
    if ns.Demo.IsActive() then
        snap = ns.Demo.Snapshot()
    else
        snap = ns.API.Snapshot(cfg.session)
    end

    local cr, cg, cb = ClassColor(snap.classFilename)
    local ac = st.accent.color
    if st.accent.classColor and cr then
        header.accent:SetColorTexture(cr, cg, cb, ac[4])
    else
        header.accent:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
    end

    header.timer:SetText(FormatTime(snap.duration))
    if snap.demo then
        header.session:SetText("|cffff9900DEMO|r")
    else
        header.session:SetText(cfg.session == "overall" and "Overall" or "Current")
    end
    if snap.hasPlayer then SetRate(header.dps, snap.dps) else header.dps:SetText("-") end
    SetNumber(header.total, snap.total)

    local bc = st.bar.color
    local br, bg, bb = bc[1], bc[2], bc[3]
    if st.bar.classColor and cr then br, bg, bb = cr, cg, cb end
    local ba = st.bar.enabled and bc[4] or 0

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
            row:SetStatusBarColor(br, bg, bb, ba)
            if hasMax and (updateBars or isNew) then
                -- range first: SetValue clamps to the current range
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

    -- Empty hint only where something else is visible, so a minimal style is
    -- truly invisible when idle (the unlocked outline still shows it).
    local showEmpty = (n == 0) and (st.backdrop.enabled or st.header.enabled or not cfg.locked)
    header.empty:SetShown(showEmpty)

    if n ~= lastRowCount or updateBars then
        lastRowCount = n
        local body = (n > 0) and n * (st.rows.height + st.rows.spacing) or (showEmpty and st.rows.height or 0)
        frame:SetHeight(math.max(RowsTop(st) + body + st.padding, 8))
    end
end

---------------------------------------------------------------------------
-- Public controls
---------------------------------------------------------------------------
function M.MarkDirty() dirty = true end

-- Captures a READABLE spellID for row i (out of combat only) and opens the
-- spell widget menu. Never compares or stores a secret value.
function M.OnSpellRightClick(i)
    local SCM = ns.SpellContextMenu
    if ns.Demo.IsActive() then
        SCM.OpenNotice("Spell widgets", "Stop the DEMO first - spell widgets are built from your real fights.")
        return
    end
    if InCombatLockdown() then
        SCM.OpenNotice("Spell widgets", "Available after combat. During combat the game hides spell identities from addons, so the spell can't be picked yet.")
        return
    end
    local snap = ns.API.Snapshot(Cfg().session)
    local sp = snap.spells and snap.spells[i]
    local id = type(sp) == "table" and ns.SecretSafety.Readable(sp.spellID)
    if type(id) ~= "number" then
        SCM.OpenNotice("Spell widgets", "This spell's identity isn't readable right now. Try again in a moment.")
        return
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    SCM.Open(id, ns.SecretSafety.Readable(name), ns.SecretSafety.Readable(icon))
end
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

function M.SetLocked(locked, quiet)
    Cfg().locked = locked and true or false
    ApplyLock()
    if not quiet then
        ns.Print(locked and "Meter locked (click-through). /sm edit to unlock."
            or "Meter unlocked: drag to move, right-click to switch Current/Overall. /sm lock when done.")
    end
end

-- Called by the config window after a db.meter value changed.
function M.ApplyMeterSetting(key)
    if key == "shown" then
        frame:SetShown(Cfg().shown ~= false)
    elseif key == "locked" then
        ApplyLock()
    elseif key == "grow" then
        Reanchor()
    elseif key == "minimapShown" then
        ns.MinimapButton.Update()
    end
    dirty = true
end

-- Re-apply everything from saved settings (used by config Revert).
function M.ReapplyAll()
    ApplyPosition()
    M.ApplyStyle()
    ApplyLock()
    frame:SetShown(Cfg().shown ~= false)
    dirty = true
end

function M.ResetPosition()
    Cfg().point = nil
    Cfg().shown = true
    Cfg().locked = false
    ApplyPosition()
    ApplyLock()
    frame:Show()
    C_Timer.After(0, Reanchor)
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
    -- convert any older saved anchor to the grow-direction anchor once laid out
    C_Timer.After(0, Reanchor)
    if not ns.API.IsAvailable() then
        ns.Print("Native damage meter reports unavailable; meter may stay empty.")
    end
end
