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
-- Native color picker with exact Cancel restoration.
-- onChange(r, g, b, a) is called live while picking; Cancel calls it once
-- more with the precise original RGBA. Returns false if unsupported.
---------------------------------------------------------------------------
function W.PickColor(color, onChange)
    local cpf = ColorPickerFrame
    if not (cpf and cpf.SetupColorPickerAndShow) then return false end
    local orig = { color[1], color[2], color[3], color[4] or 1 }
    local function Current()
        local r, g, b = cpf:GetColorRGB()
        local a = orig[4]
        if cpf.GetColorAlpha then
            a = cpf:GetColorAlpha()
        elseif OpacitySliderFrame then
            a = 1 - OpacitySliderFrame:GetValue()
        end
        return r, g, b, a
    end
    cpf:SetupColorPickerAndShow({
        r = orig[1], g = orig[2], b = orig[3],
        opacity = orig[4], hasOpacity = true,
        swatchFunc = function() onChange(Current()) end,
        opacityFunc = function() onChange(Current()) end,
        cancelFunc = function() onChange(orig[1], orig[2], orig[3], orig[4]) end,
    })
    return true
end
