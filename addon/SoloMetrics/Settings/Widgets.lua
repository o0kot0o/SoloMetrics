-- SoloMetrics: config UI primitives (flat, charcoal, teal accent)
-- Plain frames and textures only; no Blizzard dropdown templates (taint-prone).

local _, ns = ...
local W = {}
ns.ConfigWidgets = W

W.ACCENT = { 0.25, 0.78, 0.72 }
local A = W.ACCENT
local WHITE = "Interface\\Buttons\\WHITE8X8"

function W.Font() return STANDARD_TEXT_FONT end

function W.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(W.Font(), size or 12, "")
    local c = color or { 0.88, 0.88, 0.9, 1 }
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function W.Fill(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local BorderMethods = {}
function BorderMethods:SetColor(r, g, b, a)
    for i = 1, 4 do self[i]:SetColorTexture(r, g, b, a) end
end

function W.Border(parent, r, g, b, a)
    local e = setmetatable({}, { __index = BorderMethods })
    local function edge(p1, p2, horizontal)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        e[#e + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
    e:SetColor(r, g, b, a)
    return e
end

function W.Button(parent, w, h, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = W.Fill(b, "BACKGROUND", 0.14, 0.14, 0.16, 1)
    b.border = W.Border(b, 0.26, 0.26, 0.29, 1)
    b.text = W.Text(b, 12, nil, "CENTER")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(label or "")
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.2, 0.2, 0.23, 1) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.14, 0.14, 0.16, 1) end)
    return b
end

function W.Check(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.bg = W.Fill(b, "BACKGROUND", 0.1, 0.1, 0.12, 1)
    b.border = W.Border(b, 0.38, 0.38, 0.42, 1)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetPoint("TOPLEFT", 4, -4)
    b.mark:SetPoint("BOTTOMRIGHT", -4, 4)
    b.mark:SetColorTexture(A[1], A[2], A[3], 1)
    function b:SetOn(v)
        self.on = v and true or false
        self.mark:SetShown(self.on)
    end
    return b
end

function W.Slider(parent, w)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w, 16)
    s:SetHitRectInsets(0, 0, -4, -4)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0.22, 0.22, 0.25, 1)
    s:SetThumbTexture(WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 16)
    th:SetVertexColor(0.88, 0.88, 0.9, 1)
    s.fill = s:CreateTexture(nil, "BORDER")
    s.fill:SetPoint("LEFT")
    s.fill:SetPoint("RIGHT", th, "CENTER")
    s.fill:SetHeight(4)
    s.fill:SetColorTexture(A[1], A[2], A[3], 0.85)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(false)
    return s
end

function W.Edit(parent, w)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetFont(W.Font(), 12, "")
    e:SetTextColor(1, 1, 1, 1)
    e:SetTextInsets(5, 5, 0, 0)
    e.bg = W.Fill(e, "BACKGROUND", 0.08, 0.08, 0.1, 1)
    e.border = W.Border(e, 0.3, 0.3, 0.33, 1)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        if self.onCommit then self.onCommit(self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusGained", function(self)
        self.border:SetColor(A[1], A[2], A[3], 1)
        self:HighlightText()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.border:SetColor(0.3, 0.3, 0.33, 1)
        self:HighlightText(0, 0)
        if self.onRevert then self.onRevert() end
    end)
    return e
end

---------------------------------------------------------------------------
-- Option list popup (shared). options: { {value, label, font?, texture?} }
---------------------------------------------------------------------------
local popup, catcher
local popupButtons = {}
local ITEM_H = 22

function W.CloseList()
    if popup then popup:Hide() end
    if catcher then catcher:Hide() end
end

local function EnsurePopup()
    if popup then return end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetScript("OnClick", W.CloseList)
    catcher:Hide()

    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    W.Fill(popup, "BACKGROUND", 0.09, 0.09, 0.11, 0.98)
    W.Border(popup, A[1], A[2], A[3], 0.6)
    popup:Hide()
end

function W.OpenList(anchor, options, current, onPick)
    EnsurePopup()
    local width = anchor:GetWidth()
    for i, opt in ipairs(options) do
        local b = popupButtons[i]
        if not b then
            b = CreateFrame("Button", nil, popup)
            b:SetHeight(ITEM_H)
            b.sel = W.Fill(b, "BACKGROUND", A[1], A[2], A[3], 0.22)
            b.hl = W.Fill(b, "BORDER", 1, 1, 1, 0.06)
            b.hl:Hide()
            b.swatch = b:CreateTexture(nil, "ARTWORK")
            b.swatch:SetPoint("RIGHT", -6, 0)
            b.swatch:SetSize(60, 12)
            b.text = W.Text(b, 12)
            b.text:SetPoint("LEFT", 8, 0)
            b.text:SetPoint("RIGHT", -70, 0)
            b.text:SetWordWrap(false)
            b:SetScript("OnEnter", function(self) self.hl:Show() end)
            b:SetScript("OnLeave", function(self) self.hl:Hide() end)
            popupButtons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1 - (i - 1) * ITEM_H)
        b:SetWidth(width - 2)
        local fontPath = opt.font or W.Font()
        b.text:SetFont(fontPath, 12, "")
        if not b.text:GetFont() then b.text:SetFont(W.Font(), 12, "") end
        b.text:SetText(opt.label)
        if opt.texture then
            b.swatch:SetTexture(opt.texture)
            b.swatch:SetVertexColor(A[1], A[2], A[3], 1)
            b.swatch:Show()
        else
            b.swatch:Hide()
        end
        b.sel:SetShown(opt.value == current)
        b:SetScript("OnClick", function()
            W.CloseList()
            onPick(opt.value)
        end)
        b:Show()
    end
    for i = #options + 1, #popupButtons do popupButtons[i]:Hide() end
    popup:SetSize(width, #options * ITEM_H + 2)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    popup:Show()
end

---------------------------------------------------------------------------
-- Themed color picker (HSV square + hue strip + opacity strip + hex).
-- onChange(r, g, b, a) fires live while picking. Only OK keeps the result;
-- Cancel, Escape or closing restores the precise original RGBA.
---------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
    if s <= 0 then return v, v, v end
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    end
    return v, p, q
end

local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then
            h = ((g - b) / d) % 6
        elseif mx == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    return h, (mx > 0) and (d / mx) or 0, mx
end

local function Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture(WHITE)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    end
end

local function Checker(parent, w, h, cell)
    local cols, rows = math.ceil(w / cell), math.ceil(h / cell)
    for cy = 0, rows - 1 do
        for cx = 0, cols - 1 do
            local t = parent:CreateTexture(nil, "BACKGROUND")
            t:SetPoint("TOPLEFT", cx * cell, -cy * cell)
            t:SetSize(math.min(cell, w - cx * cell), math.min(cell, h - cy * cell))
            local light = ((cx + cy) % 2 == 0)
            t:SetColorTexture(light and 0.75 or 0.45, light and 0.75 or 0.45, light and 0.75 or 0.45, 1)
        end
    end
end

local function ParseHex(s)
    s = (s or ""):gsub("^%s*#?", ""):gsub("%s+$", "")
    if not (#s == 6 or #s == 8) or s:find("[^%x]") then return nil end
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255,
        tonumber(s:sub(5, 6), 16) / 255, (#s == 8) and (tonumber(s:sub(7, 8), 16) / 255) or 1
end

local function ToHex(r, g, b, a)
    local function c(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5) end
    return ("#%02x%02x%02x%02x"):format(c(r), c(g), c(b), c(a))
end

local picker
local SV, STRIP, PAD = 160, 16, 12

local function CursorFraction(frame)
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    x, y = x / s, y / s
    local fx = (x - frame:GetLeft()) / frame:GetWidth()
    local fy = (y - frame:GetBottom()) / frame:GetHeight()
    return math.max(0, math.min(1, fx)), math.max(0, math.min(1, fy))
end

local function MakeDraggable(frame, fn)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self)
        self.dragging = true
        fn(CursorFraction(self))
    end)
    frame:SetScript("OnMouseUp", function(self) self.dragging = false end)
    frame:SetScript("OnUpdate", function(self)
        if self.dragging then
            if not IsMouseButtonDown("LeftButton") then
                self.dragging = false
                return
            end
            fn(CursorFraction(self))
        end
    end)
end

local function StripMarker(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(STRIP + 6, 4)
    local o = m:CreateTexture(nil, "OVERLAY")
    o:SetAllPoints()
    o:SetColorTexture(0, 0, 0, 0.9)
    local i = m:CreateTexture(nil, "OVERLAY", nil, 1)
    i:SetPoint("TOPLEFT", 1, -1)
    i:SetPoint("BOTTOMRIGHT", -1, 1)
    i:SetColorTexture(1, 1, 1, 1)
    return m
end

local function UpdatePicker(skipHex)
    local p = picker
    local r, g, b = HSVtoRGB(p.h, p.s, p.v)
    local hr, hg, hb = HSVtoRGB(p.h, 1, 1)
    p.sv.base:SetColorTexture(hr, hg, hb, 1)
    p.svMarker:ClearAllPoints()
    p.svMarker:SetPoint("CENTER", p.sv, "BOTTOMLEFT", p.s * SV, p.v * SV)
    p.hueMarker:ClearAllPoints()
    p.hueMarker:SetPoint("CENTER", p.hue, "BOTTOM", 0, p.h * SV)
    p.alphaMarker:ClearAllPoints()
    p.alphaMarker:SetPoint("CENTER", p.alpha, "BOTTOM", 0, p.a * SV)
    Gradient(p.alpha.grad, "VERTICAL", r, g, b, 0, r, g, b, 1)
    p.newSwatch.color:SetColorTexture(r, g, b, p.a)
    if not skipHex and not p.hex:HasFocus() then p.hex:SetText(ToHex(r, g, b, p.a)) end
    p.alphaText:SetText(("%d%%"):format(math.floor(p.a * 100 + 0.5)))
    if p.onChange then p.onChange(r, g, b, p.a) end
end

local function SetPickerRGBA(r, g, b, a)
    local p = picker
    local h, s, v = RGBtoHSV(r, g, b)
    if s > 0 then p.h = h end -- keep hue when color is grey
    p.s, p.v, p.a = s, v, a
    UpdatePicker()
end

local function BuildPicker()
    local f = CreateFrame("Frame", "SoloMetricsColorPicker", UIParent)
    local rightX = PAD + SV + 10 + STRIP + 10 + STRIP + 16
    f:SetSize(rightX + 110 + PAD, PAD + SV + 12 + 26 + PAD)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    W.Fill(f, "BACKGROUND", 0.075, 0.075, 0.085, 0.98)
    W.Border(f, A[1], A[2], A[3], 0.6)
    tinsert(UISpecialFrames, "SoloMetricsColorPicker")

    -- Saturation (x) / value (y) square
    local sv = CreateFrame("Frame", nil, f)
    sv:SetSize(SV, SV)
    sv:SetPoint("TOPLEFT", PAD, -PAD)
    sv.base = sv:CreateTexture(nil, "BACKGROUND")
    sv.base:SetAllPoints()
    local white = sv:CreateTexture(nil, "BORDER")
    white:SetAllPoints()
    Gradient(white, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
    local black = sv:CreateTexture(nil, "ARTWORK")
    black:SetAllPoints()
    Gradient(black, "VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)
    W.Border(sv, 0, 0, 0, 1)
    local m = CreateFrame("Frame", nil, sv)
    m:SetSize(10, 10)
    local mo = m:CreateTexture(nil, "OVERLAY")
    mo:SetAllPoints()
    mo:SetColorTexture(1, 1, 1, 1)
    local mi = m:CreateTexture(nil, "OVERLAY", nil, 1)
    mi:SetPoint("TOPLEFT", 2, -2)
    mi:SetPoint("BOTTOMRIGHT", -2, 2)
    mi:SetColorTexture(0, 0, 0, 1)
    f.svMarker = m
    f.sv = sv
    MakeDraggable(sv, function(x, y)
        picker.s, picker.v = x, y
        UpdatePicker()
    end)

    -- Hue strip (bottom = 0, top = 1)
    local hue = CreateFrame("Frame", nil, f)
    hue:SetSize(STRIP, SV)
    hue:SetPoint("TOPLEFT", sv, "TOPRIGHT", 10, 0)
    local stops = { { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 1 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 } }
    for i = 1, 6 do
        local t = hue:CreateTexture(nil, "BACKGROUND")
        t:SetSize(STRIP, SV / 6)
        t:SetPoint("BOTTOMLEFT", 0, (i - 1) * SV / 6)
        local lo, hi = stops[i], stops[i + 1]
        Gradient(t, "VERTICAL", lo[1], lo[2], lo[3], 1, hi[1], hi[2], hi[3], 1)
    end
    W.Border(hue, 0, 0, 0, 1)
    f.hue = hue
    f.hueMarker = StripMarker(hue)
    MakeDraggable(hue, function(_, y)
        picker.h = math.min(y, 0.9999)
        UpdatePicker()
    end)

    -- Opacity strip (checker behind a gradient of the current color)
    local alpha = CreateFrame("Frame", nil, f)
    alpha:SetSize(STRIP, SV)
    alpha:SetPoint("TOPLEFT", hue, "TOPRIGHT", 10, 0)
    Checker(alpha, STRIP, SV, 8)
    alpha.grad = alpha:CreateTexture(nil, "ARTWORK")
    alpha.grad:SetAllPoints()
    W.Border(alpha, 0, 0, 0, 1)
    f.alpha = alpha
    f.alphaMarker = StripMarker(alpha)
    MakeDraggable(alpha, function(_, y)
        picker.a = y
        UpdatePicker()
    end)

    -- Right column: swatches, hex, opacity readout
    local function Swatch(label, y)
        local s = CreateFrame("Button", nil, f)
        s:SetSize(110, 30)
        s:SetPoint("TOPLEFT", rightX, y)
        Checker(s, 110, 30, 10)
        s.color = s:CreateTexture(nil, "ARTWORK")
        s.color:SetAllPoints()
        W.Border(s, 0.35, 0.35, 0.4, 1)
        local l = W.Text(f, 10, { 0.6, 0.6, 0.65, 1 })
        l:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
        l:SetText(label)
        return s
    end
    f.newSwatch = Swatch("New", -PAD - 12)
    f.oldSwatch = Swatch("Original (click to restore)", -PAD - 12 - 30 - 18)
    f.oldSwatch:SetScript("OnClick", function()
        local o = picker.orig
        SetPickerRGBA(o[1], o[2], o[3], o[4])
    end)

    local hexLabel = W.Text(f, 10, { 0.6, 0.6, 0.65, 1 })
    hexLabel:SetPoint("TOPLEFT", rightX, -PAD - 12 - 60 - 36)
    hexLabel:SetText("Hex  #RRGGBBAA")
    f.hex = W.Edit(f, 110)
    f.hex:SetPoint("TOPLEFT", hexLabel, "BOTTOMLEFT", 0, -3)
    f.hex:SetMaxLetters(9)
    f.hex.onCommit = function(text)
        local r, g, b, a = ParseHex(text)
        if not r then
            ns.Print("Invalid color - use #RRGGBB or #RRGGBBAA.")
            return
        end
        SetPickerRGBA(r, g, b, a)
    end
    f.hex.onRevert = function() UpdatePicker() end

    f.alphaText = W.Text(f, 11, { 0.8, 0.8, 0.85, 1 })
    f.alphaText:SetPoint("TOPLEFT", f.hex, "BOTTOMLEFT", 0, -8)

    -- Buttons
    local ok = W.Button(f, 80, 24, "OK")
    ok:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ok.text:SetTextColor(A[1], A[2], A[3], 1)
    ok:SetScript("OnClick", function()
        picker.committed = true
        f:Hide()
    end)
    local cancel = W.Button(f, 80, 24, "Cancel")
    cancel:SetPoint("RIGHT", ok, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() f:Hide() end)

    -- Any close without OK restores the exact original color.
    f:SetScript("OnHide", function()
        if not picker.committed and picker.onChange and picker.orig then
            local o = picker.orig
            picker.onChange(o[1], o[2], o[3], o[4])
        end
        picker.onChange = nil
    end)

    picker = f
end

-- anchor: frame to position next to; color: {r,g,b,a}
function W.PickColor(anchor, color, onChange)
    if not picker then BuildPicker() end
    if picker:IsShown() then
        picker.committed = true -- switching swatches keeps the previous pick
        picker:Hide()
    end
    picker.orig = { color[1], color[2], color[3], color[4] or 1 }
    picker.committed = false
    picker.onChange = nil
    local h, s, v = RGBtoHSV(color[1], color[2], color[3])
    picker.h, picker.s, picker.v, picker.a = h, s, v, color[4] or 1
    local o = picker.orig
    picker.oldSwatch.color:SetColorTexture(o[1], o[2], o[3], o[4])
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    UpdatePicker()
    picker.onChange = onChange
    picker:Show()
    return true
end

function W.CloseColorPicker()
    if picker and picker:IsShown() then picker:Hide() end
end
