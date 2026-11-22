-- SoloMetrics: CounterRenderer (numeric counter widgets)
-- Renders one prominent number plus optional title, suffix, secondary value
-- and accent line. Live values may be secret: they only reach native setters
-- (SetText(AbbreviateNumbers/BreakUpLargeNumbers(v)), SetFormattedText) and
-- are never read, compared or kept. Readable values (last completed fight)
-- may be formatted in Lua.
-- Layout uses anchors only (no text measurement), so it works with secret text.

local _, ns = ...
local CR = {}
ns.CounterRenderer = CR

local R = {}
R.__index = R

local function ClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

local function ApplyFont(fs, key, size, outline, shadow, c)
    local flags = ns.Theme.OUTLINES[outline] or ""
    fs:SetFont(ns.Theme.FontPath(key), size, flags)
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
    if shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    else
        fs:SetShadowOffset(0, 0)
    end
    if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function FormatTime(d)
    if type(d) ~= "number" then return "-" end
    return ("%d:%02d"):format(math.floor(d / 60), math.floor(d % 60))
end

-- Readable formatting (Lua is allowed here).
local function FormatReadable(v, fmt, metric)
    if metric == "share" then return ("%.0f%%"):format(v) end
    if fmt == "decimal2" then return ("%.2f"):format(v) end
    if fmt == "decimal1" then return ("%.1f"):format(v) end
    if fmt == "full" then return BreakUpLargeNumbers(math.floor(v + 0.5)) end
    if v < 1000 then
        if metric == "dps" then return ("%.1f"):format(v) end
        return tostring(math.floor(v + 0.5))
    end
    return AbbreviateNumbers(v)
end

-- Opaque-safe: v may be secret. Only native functions touch it.
local function SetOpaque(fs, v, fmt, metric)
    if fmt == "auto" then fmt = (metric == "dps") and "decimal1" or "compact" end
    if fmt == "decimal1" then
        fs:SetFormattedText("%.1f", v)
    elseif fmt == "decimal2" then
        fs:SetFormattedText("%.2f", v)
    elseif fmt == "full" then
        fs:SetText(BreakUpLargeNumbers(v))
    else
        fs:SetText(AbbreviateNumbers(v))
    end
end

function CR.New(parent)
    local r = setmetatable({ parent = parent }, R)
    r.accent = parent:CreateTexture(nil, "ARTWORK")
    r.title = parent:CreateFontString(nil, "OVERLAY")
    r.title:SetWordWrap(false)
    r.value = parent:CreateFontString(nil, "OVERLAY")
    r.value:SetWordWrap(false)
    r.suffix = parent:CreateFontString(nil, "OVERLAY")
    r.secondary = parent:CreateFontString(nil, "OVERLAY")
    r.secondary:SetWordWrap(false)
    for _, fs in ipairs({ r.title, r.value, r.suffix, r.secondary }) do
        fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    end
    r.value:SetText("-")
    return r
end

-- Anchor point name for a horizontal + vertical alignment.
local function Point(align, valign)
    local v = (valign == "top" and "TOP") or (valign == "bottom" and "BOTTOM") or ""
    local h = (align == "left" and "LEFT") or (align == "right" and "RIGHT") or ""
    local p = v .. h
    return p == "" and "CENTER" or p
end

-- Places a label (title / secondary) relative to the value or a window edge.
local function PlaceLabel(fs, place, align, x, y, parent, value, valueAlign, pad, spacing)
    fs:ClearAllPoints()
    fs:SetJustifyH(ns.Theme.ALIGNS[align] or "CENTER")
    if place == "top" or place == "bottom" then
        -- spans the window width at the top/bottom edge, own alignment
        local edge = (place == "top") and "TOP" or "BOTTOM"
        local dy = (place == "top") and -pad or pad
        fs:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", pad + x, dy + y)
        fs:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", -pad + x, dy + y)
    else
        -- attached above/below the value, following the value's alignment
        local h = (valueAlign == "left" and "LEFT") or (valueAlign == "right" and "RIGHT") or ""
        if place == "above" then
            fs:SetPoint("BOTTOM" .. h, value, "TOP" .. h, x, spacing + y)
        else
            fs:SetPoint("TOP" .. h, value, "BOTTOM" .. h, x, -spacing + y)
        end
        fs:SetJustifyH(ns.Theme.ALIGNS[valueAlign] or "CENTER")
    end
end

function R:ApplyStyle(w)
    local WS = ns.WidgetSchema
    local g = function(p) return WS.Get(w, p) end
    self.w = w
    local p = self.parent
    local pad, spacing = g("padding"), g("spacing")

    -- accent line along the top edge
    local cr, cg, cb = ClassColor()
    local ac = g("accent.color")
    self.accent:ClearAllPoints()
    self.accent:SetPoint("TOPLEFT")
    self.accent:SetPoint("TOPRIGHT")
    self.accent:SetHeight(2)
    if g("accent.classColor") and cr then
        self.accent:SetColorTexture(cr, cg, cb, ac[4])
    else
        self.accent:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
    end
    self.accent:SetShown(g("accent.enabled"))

    -- primary value
    local vc = g("value.color")
    if g("value.classColor") and cr then vc = { cr, cg, cb, vc[4] } end
    ApplyFont(self.value, g("value.font"), g("value.size"), g("value.outline"), g("value.shadow"), vc)
    local align, valign = g("value.align"), g("value.valign")
    local pt = Point(align, valign)
    local dx = (align == "left" and pad) or (align == "right" and -pad) or 0
    local dy = (valign == "top" and -pad) or (valign == "bottom" and pad) or 0
    self.value:ClearAllPoints()
    self.value:SetPoint(pt, p, pt, dx + g("value.x"), dy + g("value.y"))
    self.value:SetJustifyH(ns.Theme.ALIGNS[align] or "CENTER")

    -- suffix (e.g. "DPS") right of the value, same font, smaller
    local suffix = g("value.suffix")
    ApplyFont(self.suffix, g("value.font"), math.max(6, math.floor(g("value.size") * 0.45 + 0.5)),
        g("value.outline"), g("value.shadow"), vc)
    self.suffix:ClearAllPoints()
    self.suffix:SetPoint("BOTTOMLEFT", self.value, "BOTTOMRIGHT", 3, 2)
    self.suffix:SetText(suffix)
    self.suffix:SetShown(suffix ~= "")

    -- title
    ApplyFont(self.title, g("title.font"), g("title.size"), g("title.outline"), false, g("title.color"))
    PlaceLabel(self.title, g("title.position"), g("title.align"), g("title.x"), g("title.y"),
        p, self.value, align, pad, spacing)
    local t = g("title.text")
    self.title:SetText(t ~= "" and t or WS.Label(w))
    self.title:SetShown(g("title.enabled"))

    -- secondary value
    ApplyFont(self.secondary, g("secondary.font"), g("secondary.size"), g("secondary.outline"), false,
        g("secondary.color"))
    PlaceLabel(self.secondary, g("secondary.position"), g("secondary.align"), g("secondary.x"),
        g("secondary.y"), p, self.value, align, pad, spacing)
    self.showSecondary = g("secondary.enabled") and w.counter.secondary ~= "none"
    self.secondaryLabel = g("secondary.label")
    self.format = g("value.format")
    self.secondary:SetShown(self.showSecondary)
end

function R:Layout() end -- anchors handle resizing

function R:Reset()
    self.value:SetText("-")
    self.secondary:SetText("")
end

local SEC_LABEL = { dps = "DPS: ", damage = "Total: ", time = "Time: ", share = "Share: " }

-- Live values (may be secret): primary v, secondary sv (opaque or readable time).
function R:SetLive(v, metric, sv, secKind)
    if type(v) == "number" then
        SetOpaque(self.value, v, self.format, metric)
    else
        self.value:SetText("-")
    end
    if self.showSecondary then
        local prefix = self.secondaryLabel and SEC_LABEL[secKind] or ""
        if secKind == "time" then
            self.secondary:SetText(prefix .. FormatTime(sv))
        elseif type(sv) == "number" then
            -- prefix is a plain literal in the native format string; only
            -- numeric conversions (verified with secrets) are used
            local fmt = (secKind == "dps") and "%.1f" or "%.0f"
            self.secondary:SetFormattedText(prefix:gsub("%%", "%%%%") .. fmt, sv)
        else
            self.secondary:SetText(prefix .. "-")
        end
    end
end

-- Readable values (last completed fight). v == nil -> "no data".
function R:SetReadable(v, metric, sv, secKind, note)
    if type(v) == "number" then
        self.value:SetText(FormatReadable(v, self.format, metric))
    else
        self.value:SetText("-")
    end
    if self.showSecondary then
        local prefix = self.secondaryLabel and SEC_LABEL[secKind] or ""
        if note then
            self.secondary:SetText(note)
        elseif secKind == "time" then
            self.secondary:SetText(prefix .. FormatTime(sv))
        elseif type(sv) == "number" then
            self.secondary:SetText(prefix .. FormatReadable(sv, "auto", secKind))
        else
            self.secondary:SetText(prefix .. "-")
        end
    end
end
