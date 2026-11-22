-- SoloMetrics: GraphRenderer
-- Live graph built from native regions so opaque (secret) values can be drawn:
--   * one vertical StatusBar per sample column - Push(v) passes v straight to
--     SetValue (verified in combat, /sm graphtest);
--   * a dot anchored to the TOP of each column's fill texture;
--   * Line regions anchored between neighbouring fill tops.
-- The engine positions everything; Lua only manages column order (readable
-- indices) and the readable scale. Values are never read, compared or stored.
-- All regions are pooled; nothing is created per sample.

local _, ns = ...
local GR = {}
ns.GraphRenderer = GR

local WHITE = "Interface\\Buttons\\WHITE8X8"
local R = {}
R.__index = R

-- Scale labels are always readable numbers (never combat values), so they
-- can be formatted in Lua: one decimal below 1000 ("5.8", "32"), abbreviated above.
local function FormatAxis(v)
    if type(v) ~= "number" then return "" end
    if v >= 1000 then return AbbreviateNumbers(v) end
    local s = ("%.1f"):format(v)
    return (s:gsub("%.0$", ""))
end

local function PlayerClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

function GR.New(parent)
    local r = setmetatable({
        parent = parent, cols = {}, lines = {}, grid = {},
        head = 0, count = 0, n = 30, max = 100, min = 0, style = "area",
    }, R)
    r.plot = CreateFrame("Frame", nil, parent)
    r.axisTop = r.plot:CreateFontString(nil, "OVERLAY")
    r.axisTop:SetFont(STANDARD_TEXT_FONT, 9, "")
    r.axisZero = r.plot:CreateFontString(nil, "OVERLAY")
    r.axisZero:SetFont(STANDARD_TEXT_FONT, 9, "")
    r.axisZero:SetText("0")
    return r
end

function R:EnsurePool(n)
    for i = #self.cols + 1, n do
        local b = CreateFrame("StatusBar", nil, self.plot)
        b:SetOrientation("VERTICAL")
        b:SetStatusBarTexture(WHITE)
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetPoint("CENTER", b:GetStatusBarTexture(), "TOP", 0, 0)
        b:Hide()
        self.cols[i] = b
    end
    for i = #self.lines + 1, math.max(0, n - 1) do
        local l = self.plot:CreateLine(nil, "OVERLAY")
        l:Hide()
        self.lines[i] = l
    end
end

-- Reads appearance + graph settings of widget record w.
function R:ApplyStyle(w)
    local WS = ns.WidgetSchema
    local get = function(p) return WS.Get(w, p) end
    local n = w.graph.samples
    if n ~= self.n then
        self:Reset()
        self.n = n
    end
    self:EnsurePool(n)
    self.style = w.graph.style
    self.cfg = {
        padding = get("padding"),
        headerH = (get("title.enabled") or get("value.enabled"))
            and (math.max(get("title.size"), get("value.size")) + 6) or 0,
        axis = get("axis.enabled"), axisSize = get("axis.size"), axisColor = get("axis.color"),
        grid = get("grid.enabled"), gridLines = get("grid.lines"), gridColor = get("grid.color"),
        fill = (self.style == "area" or self.style == "bars") and get("fill.enabled"),
        line = (self.style == "area" or self.style == "line") and get("line.enabled"),
        points = (self.style ~= "bars") and get("points.enabled"),
        lineThickness = get("line.thickness"),
        pointSize = get("points.size"),
    }
    local cr, cg, cb = PlayerClassColor()
    local fc = get("fill.color")
    local fr, fg, fb = fc[1], fc[2], fc[3]
    if get("fill.classColor") and cr then fr, fg, fb = cr, cg, cb end
    local lc = get("line.color")
    local lr, lg, lb = lc[1], lc[2], lc[3]
    if get("line.classColor") and cr then lr, lg, lb = cr, cg, cb end
    local pc = get("points.color")
    local c = self.cfg
    for _, b in ipairs(self.cols) do
        -- hidden fill keeps alpha 0 (dots/lines still anchor to it)
        b:SetStatusBarColor(fr, fg, fb, c.fill and fc[4] or 0)
        b.dot:SetSize(c.pointSize, c.pointSize)
        b.dot:SetColorTexture(pc[1], pc[2], pc[3], pc[4])
        b.dot:SetShown(c.points)
    end
    for _, l in ipairs(self.lines) do
        l:SetThickness(c.lineThickness)
        l:SetColorTexture(lr, lg, lb, lc[4])
    end
    local ac = c.axisColor
    self.axisTop:SetFont(STANDARD_TEXT_FONT, c.axisSize, "")
    self.axisZero:SetFont(STANDARD_TEXT_FONT, c.axisSize, "")
    self.axisTop:SetTextColor(ac[1], ac[2], ac[3], ac[4])
    self.axisZero:SetTextColor(ac[1], ac[2], ac[3], ac[4])
    self:Layout()
end

function R:Reset()
    for _, b in ipairs(self.cols) do
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        b:Hide()
    end
    for _, l in ipairs(self.lines) do l:Hide() end
    self.head, self.count = 0, 0
end

-- max/min are always readable numbers (fixed setting or last fight's readable
-- value). Values below min show as empty columns, above max as full (clipped).
function R:SetScale(max, min)
    if type(max) ~= "number" or max <= 0 then return end
    min = (type(min) == "number" and min >= 0 and min < max) and min or 0
    self.max, self.min = max, min
    for _, b in ipairs(self.cols) do b:SetMinMaxValues(min, max) end
    self.axisTop:SetText(FormatAxis(max))
    self.axisZero:SetText(min > 0 and FormatAxis(min) or "0")
end

-- Readable series (one value per completed fight), oldest -> newest.
function R:SetSeries(values, max, min)
    self:Reset()
    self:SetScale(max, min)
    local n = math.min(#values, self.n)
    for i = #values - n + 1, #values do
        self.head = self.head % self.n + 1
        local b = self.cols[self.head]
        b:SetMinMaxValues(self.min, self.max)
        b:SetValue(values[i])
        self.count = self.count + 1
    end
    self:Layout()
end

-- v may be secret: it only goes into SetValue.
function R:Push(v)
    if self.n <= 0 or type(v) ~= "number" then return end
    self.head = self.head % self.n + 1
    local b = self.cols[self.head]
    b:SetMinMaxValues(self.min, self.max)
    b:SetValue(v)
    self.count = self.count + 1
    self:Layout()
end

function R:Layout()
    local c = self.cfg
    if not c then return end
    local pw, ph = self.parent:GetWidth(), self.parent:GetHeight()
    local axisW = c.axis and (c.axisSize * 3 + 4) or 0
    local left, right = c.padding + axisW, c.padding
    local top, bottom = c.padding + c.headerH, c.padding
    local w = math.max(10, pw - left - right)
    local h = math.max(10, ph - top - bottom)
    self.plot:ClearAllPoints()
    self.plot:SetPoint("TOPLEFT", self.parent, "TOPLEFT", left, -top)
    self.plot:SetSize(w, h)

    -- axis labels (readable scale only)
    self.axisTop:ClearAllPoints()
    self.axisTop:SetPoint("TOPRIGHT", self.plot, "TOPLEFT", -3, 0)
    self.axisZero:ClearAllPoints()
    self.axisZero:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMLEFT", -3, 0)
    self.axisTop:SetShown(c.axis)
    self.axisZero:SetShown(c.axis)
    self.axisTop:SetText(FormatAxis(self.max))

    -- grid
    local gl = c.grid and c.gridLines or 0
    for i = 1, math.max(gl, #self.grid) do
        local t = self.grid[i]
        if i <= gl then
            if not t then
                t = self.plot:CreateTexture(nil, "BACKGROUND")
                self.grid[i] = t
            end
            local gc = c.gridColor
            t:SetColorTexture(gc[1], gc[2], gc[3], gc[4])
            t:ClearAllPoints()
            t:SetPoint("LEFT", self.plot, "BOTTOMLEFT", 0, h * i / (gl + 1))
            t:SetPoint("RIGHT", self.plot, "BOTTOMRIGHT", 0, h * i / (gl + 1))
            t:SetHeight(1)
            t:Show()
        elseif t then
            t:Hide()
        end
    end

    -- columns: newest at the right edge
    local n = math.min(self.count, self.n)
    local colW = w / self.n
    local gap = (self.style == "bars") and math.min(2, colW * 0.25) or 0
    local slots = {}
    for s = 1, n do
        local idx = ((self.head - n + s - 1) % self.n) + 1
        local b = self.cols[idx]
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", (self.n - n + s - 1) * colW + gap / 2, 0)
        b:SetSize(math.max(1, colW - gap), h)
        b:Show()
        slots[s] = b
    end
    for i = 1, self.n do
        local b = self.cols[i]
        if b and b:IsShown() then
            local used = false
            for s = 1, n do if slots[s] == b then used = true break end end
            if not used then b:Hide() end
        end
    end

    for i = 1, #self.lines do
        local l = self.lines[i]
        if c.line and i < n then
            l:SetStartPoint("TOP", slots[i]:GetStatusBarTexture(), 0, 0)
            l:SetEndPoint("TOP", slots[i + 1]:GetStatusBarTexture(), 0, 0)
            l:Show()
        else
            l:Hide()
        end
    end
end
