-- SoloMetrics: reusable settings panel (scrolling list of pooled control rows)
-- Used by the main settings window and by each widget's own settings window.
--
-- Item kinds:
--   style   : Theme.SCHEMA path of the active profile
--   meter   : db.meter key (item.type/min/max/values)
--   alpha   : opacity component of a style color path (slider, percent)
--   custom  : any value via functions: get(), set(v) -> bool, default(), reset()?,
--             type ("bool"|"number"|"color"|"font"|"texture"|"outline"|"align"|"enum"),
--             min/max/values, depFn() -> bool, isCustom() -> bool (shows a dot)
--   section : heading            note : text (item.text or item.textFn())
--   buttons : item.buttons = { { label = str|fn, onClick = fn, enabled = fn? }, ... }
--   row     : item.rowKind + item.build(panel) -> row (pooled by rowKind)
-- Optional on bound items: tip, adv, dep/depOff (style paths), step.

local _, ns = ...
local Panel = {}
ns.Panel = Panel

local LABEL_X, CONTROL_X = 12, 250
Panel.LABEL_X, Panel.CONTROL_X = LABEL_X, CONTROL_X

local P = {}
P.__index = P

local function W() return ns.ConfigWidgets end
local function Active() return ns.Theme.Active() end

---------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------
local function IsBound(item)
    local k = item.kind
    return k == "style" or k == "meter" or k == "alpha" or k == "custom"
end
Panel.IsBound = IsBound

local function TypeOf(item)
    if item.kind == "style" then
        local e = ns.Theme.SCHEMA_BY_PATH[item.path]
        return e[2], e[3], e[4]
    elseif item.kind == "alpha" then
        return "number", 0, 1
    end
    return item.type, item.min, item.max
end

local function GetValue(item)
    local k = item.kind
    if k == "style" then return ns.Theme.GetPath(Active(), item.path) end
    if k == "alpha" then
        local c = ns.Theme.GetPath(Active(), item.path)
        return c and (c[4] or 1) or 1
    end
    if k == "custom" then return item.get() end
    return ns.db.meter[item.key]
end

local function DefaultOf(item)
    local k = item.kind
    if k == "style" then return ns.Theme.GetDefault(item.path) end
    if k == "alpha" then
        local c = ns.Theme.GetDefault(item.path)
        return c and (c[4] or 1) or 1
    end
    if k == "custom" then return item.default and item.default() end
    return ns.METER_DEFAULTS[item.key]
end

local function DepOK(item)
    if item.depFn then return item.depFn() and true or false end
    local st = Active()
    local deps = item.dep
    if type(deps) == "string" then deps = { deps } end
    for _, d in ipairs(deps or {}) do
        if ns.Theme.GetPath(st, d) ~= true then return false end
    end
    if item.depOff and ns.Theme.GetPath(st, item.depOff) == true then return false end
    return true
end
Panel.DepOK = DepOK

local function ApplyValue(item, v)
    local k = item.kind
    if k == "custom" then
        return item.set(v) ~= false
    end
    if k == "alpha" then
        if type(v) ~= "number" then return false end
        local c = ns.Theme.GetPath(Active(), item.path)
        local nv = { c[1], c[2], c[3], math.max(0, math.min(1, v)) }
        if not ns.Theme.IsValidValue(item.path, nv) then return false end
        ns.Theme.SetPath(Active(), item.path, nv)
        ns.SpellMeter.ApplyStyle()
        return true
    end
    if k == "style" then
        if type(v) == "table" then v = { v[1], v[2], v[3], v[4] or 1 } end
        if not ns.Theme.IsValidValue(item.path, v) then return false end
        ns.Theme.SetPath(Active(), item.path, v)
        ns.SpellMeter.ApplyStyle()
        return true
    end
    local t, mn, mx = TypeOf(item)
    if t == "number" and (type(v) ~= "number" or v < mn or v > mx) then return false end
    ns.db.meter[item.key] = v
    ns.SpellMeter.ApplyMeterSetting(item.key)
    return true
end
Panel.ApplyValue = ApplyValue
Panel.DefaultOf = DefaultOf

-- Reset to default (custom items may define reset(), e.g. "clear override").
local function ResetItem(item)
    if item.kind == "custom" and item.reset then
        item.reset()
        return true
    end
    return ApplyValue(item, DefaultOf(item))
end
Panel.ResetItem = ResetItem

local function RoundStep(v, step)
    step = step or 1
    return math.floor(v / step + 0.5) * step
end

local function FormatNumber(v, step, percent)
    if type(v) ~= "number" then return "" end
    if percent then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
    if (step or 1) < 1 then return ("%.2f"):format(v) end
    return tostring(math.floor(v + 0.5))
end

local COLOR_ENTRY = { "color", "color" }

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function ShowTip(row)
    local item = row.item
    if not item or not item.label then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(item.label, 1, 1, 1)
    if item.tip then GameTooltip:AddLine(item.tip, 0.8, 0.8, 0.8, true) end
    if not DepOK(item) then
        GameTooltip:AddLine("Disabled: turn on its parent element first. Value is kept.", 1, 0.6, 0.3, true)
    end
    if item.kind == "custom" and item.isCustom then
        GameTooltip:AddLine(item.isCustom() and "Customized for this widget (R resets to the default)."
            or "Using the default value.", 0.55, 0.75, 0.72, true)
    end
    local key = item.path or (item.key and ("meter." .. item.key))
    if key and item.kind == "alpha" then key = key .. " (opacity)" end
    if key then GameTooltip:AddLine(key, 0.45, 0.45, 0.5) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function BaseRow(panel, kind, height)
    local row = CreateFrame("Frame", nil, panel.content)
    row:SetSize(panel.width, height)
    row.kind = kind
    row.height = height
    row.panel = panel
    return row
end

local function SettingRow(panel, kind, height)
    local w = W()
    local A = w.ACCENT
    local row = BaseRow(panel, kind, height)
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.hl = w.Fill(row, "BACKGROUND", 1, 1, 1, 0.03)
    row.hl:Hide()
    row:HookScript("OnEnter", function(self) self.hl:Show() end)
    row:HookScript("OnLeave", function(self) self.hl:Hide() end)
    row.label = w.Text(row, 12)
    row.label:SetPoint("LEFT", LABEL_X, 0)
    row.label:SetWidth(CONTROL_X - LABEL_X - 8)
    row.label:SetWordWrap(false)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("RIGHT", row.label, "LEFT", -3, 0)
    row.dot:SetColorTexture(A[1], A[2], A[3], 1)
    row.dot:Hide()

    local reset = CreateFrame("Button", nil, row)
    reset:SetSize(16, 16)
    reset:SetPoint("RIGHT", -6, 0)
    reset.icon = w.Text(reset, 11, { 0.55, 0.55, 0.6, 1 }, "CENTER")
    reset.icon:SetPoint("CENTER")
    reset.icon:SetText("R")
    reset:SetScript("OnEnter", function(self)
        self.icon:SetTextColor(A[1], A[2], A[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset to default")
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function(self)
        self.icon:SetTextColor(0.55, 0.55, 0.6, 1)
        GameTooltip:Hide()
    end)
    reset:SetScript("OnClick", function()
        ResetItem(row.item)
        panel:RefreshAll()
    end)
    row.reset = reset
    row.inputs = {}

    function row:SetEnabledState(on)
        self:SetAlpha(on and 1 or 0.4)
        for _, f in ipairs(self.inputs) do
            f:EnableMouse(on)
            if not on and f.ClearFocus then f:ClearFocus() end
        end
        self.dot:SetShown(self.item.kind == "custom" and self.item.isCustom and self.item.isCustom() or false)
    end
    return row
end

local C = {}

C.toggle = function(panel)
    local row = SettingRow(panel, "toggle", 28)
    row.check = W().Check(row)
    row.check:SetPoint("LEFT", CONTROL_X, 0)
    row.check:SetScript("OnClick", function() panel:Set(row.item, not row.check.on) end)
    row.inputs = { row.check }
    function row:Refresh()
        self.check:SetOn(GetValue(self.item))
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

C.slider = function(panel)
    local row = SettingRow(panel, "slider", 28)
    row.slider = W().Slider(row, 200)
    row.slider:SetPoint("LEFT", CONTROL_X, 0)
    row.edit = W().Edit(row, 54)
    row.edit:SetPoint("LEFT", row.slider, "RIGHT", 12, 0)
    row.slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        local _, mn, mx = TypeOf(row.item)
        local v = math.max(mn, math.min(mx, RoundStep(value, row.item.step)))
        if v ~= GetValue(row.item) then panel:Set(row.item, v) end
    end)
    row.edit.onCommit = function(text)
        local v = tonumber((text:gsub("%%", "")))
        if not v then return end
        if row.item.kind == "alpha" then v = v / 100 end -- typed as percent
        local _, mn, mx = TypeOf(row.item)
        v = math.max(mn, math.min(mx, RoundStep(v, row.item.step)))
        panel:Set(row.item, v)
    end
    row.edit.onRevert = function() row:Refresh() end
    row.inputs = { row.slider, row.edit }
    function row:Refresh()
        local _, mn, mx = TypeOf(self.item)
        local v = GetValue(self.item)
        self.slider.updating = true
        self.slider:SetMinMaxValues(mn, mx)
        self.slider:SetValueStep(self.item.step or 1)
        self.slider:SetValue(v)
        self.slider.updating = false
        if not self.edit:HasFocus() then
            self.edit:SetText(FormatNumber(v, self.item.step, self.item.kind == "alpha"))
        end
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

local OUTLINE_LABELS = { none = "None", outline = "Outline", thick = "Thick outline" }

local function OptionsFor(item)
    local t = TypeOf(item)
    local opts = {}
    if t == "font" then
        for key, f in pairs(ns.Theme.FONTS) do
            opts[#opts + 1] = { value = key, label = f.label, font = ns.Theme.FontPath(key) }
        end
    elseif t == "texture" then
        for key, tx in pairs(ns.Theme.TEXTURES) do
            opts[#opts + 1] = { value = key, label = tx.label, texture = tx.path }
        end
    elseif t == "outline" then
        for _, key in ipairs({ "none", "outline", "thick" }) do
            opts[#opts + 1] = { value = key, label = OUTLINE_LABELS[key] }
        end
        return opts
    elseif t == "align" then
        for _, kv in ipairs({ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }) do
            opts[#opts + 1] = { value = kv[1], label = kv[2] }
        end
        return opts
    elseif t == "enum" then
        local values = type(item.values) == "function" and item.values() or item.values
        for _, v in ipairs(values) do
            opts[#opts + 1] = { value = v[1], label = v[2] }
        end
        return opts
    end
    table.sort(opts, function(a, b) return a.label < b.label end)
    return opts
end

local function LabelFor(item, value)
    for _, o in ipairs(OptionsFor(item)) do
        if o.value == value then return o.label, o end
    end
    return tostring(value)
end

C.dropdown = function(panel)
    local row = SettingRow(panel, "dropdown", 28)
    local w = W()
    row.button = w.Button(row, 220, 22, "")
    row.button:SetPoint("LEFT", CONTROL_X, 0)
    row.button.text:SetJustifyH("LEFT")
    row.button.arrow = w.Text(row.button, 10, { 0.6, 0.6, 0.65, 1 }, "RIGHT")
    row.button.arrow:SetPoint("RIGHT", -6, 0)
    row.button.arrow:SetText("v")
    row.button:SetScript("OnClick", function(self)
        W().OpenList(self, OptionsFor(row.item), GetValue(row.item), function(v) panel:Set(row.item, v) end)
    end)
    row.inputs = { row.button }
    function row:Refresh()
        local label, opt = LabelFor(self.item, GetValue(self.item))
        self.button.text:SetText(label)
        local font = opt and opt.font or W().Font()
        self.button.text:SetFont(font, 12, "")
        if not self.button.text:GetFont() then self.button.text:SetFont(W().Font(), 12, "") end
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

C.color = function(panel)
    local w = W()
    local row = SettingRow(panel, "color", 28)
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(26, 18)
    sw:SetPoint("LEFT", CONTROL_X, 0)
    w.Fill(sw, "BACKGROUND", 0.55, 0.55, 0.55, 1)
    local half = sw:CreateTexture(nil, "BORDER")
    half:SetPoint("TOPLEFT")
    half:SetPoint("BOTTOMRIGHT", sw, "CENTER")
    half:SetColorTexture(0.85, 0.85, 0.85, 1)
    local half2 = sw:CreateTexture(nil, "BORDER")
    half2:SetPoint("TOPLEFT", sw, "CENTER")
    half2:SetPoint("BOTTOMRIGHT")
    half2:SetColorTexture(0.85, 0.85, 0.85, 1)
    sw.color = sw:CreateTexture(nil, "ARTWORK")
    sw.color:SetAllPoints()
    w.Border(sw, 0.4, 0.4, 0.45, 1)
    sw:SetScript("OnClick", function()
        W().PickColor(sw, GetValue(row.item), function(r, g, b, a)
            panel:Set(row.item, { r, g, b, a })
        end)
    end)
    row.swatch = sw
    row.edit = w.Edit(row, 96)
    row.edit:SetPoint("LEFT", sw, "RIGHT", 10, 0)
    row.edit:SetMaxLetters(9)
    row.edit.onCommit = function(text)
        local r, g, b, a = W().ParseHex(text)
        if not r then
            ns.Print("Invalid color - use #RRGGBB or #RRGGBBAA.")
            return
        end
        panel:Set(row.item, { r, g, b, a })
    end
    row.edit.onRevert = function() row:Refresh() end
    row.hint = w.Text(row, 10, { 0.5, 0.5, 0.55, 1 })
    row.hint:SetPoint("LEFT", row.edit, "RIGHT", 8, 0)
    row.hint:SetText("#RRGGBBAA")
    row.inputs = { sw, row.edit }
    function row:Refresh()
        local c = GetValue(self.item)
        self.swatch.color:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        if not self.edit:HasFocus() then
            self.edit:SetText("#" .. ns.Theme.FormatValue(COLOR_ENTRY, c))
        end
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

C.section = function(panel)
    local w = W()
    local A = w.ACCENT
    local row = BaseRow(panel, "section", 34)
    row.label = w.Text(row, 13, { A[1], A[2], A[3], 1 })
    row.label:SetPoint("BOTTOMLEFT", LABEL_X - 4, 8)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", LABEL_X - 4, 3)
    line:SetPoint("BOTTOMRIGHT", -6, 3)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)
    return row
end

C.note = function(panel)
    local row = BaseRow(panel, "note", 30)
    row.label = W().Text(row, 12, { 0.7, 0.7, 0.74, 1 })
    row.label:SetPoint("TOPLEFT", LABEL_X, -6)
    row.label:SetWidth(panel.width - 2 * LABEL_X)
    row.label:SetWordWrap(true)
    function row:SetNote(text)
        self.label:SetText(text)
        self.height = math.ceil(self.label:GetStringHeight()) + 14
        self:SetHeight(self.height)
    end
    return row
end

C.advanced = function(panel)
    local row = BaseRow(panel, "advanced", 32)
    row.button = W().Button(row, 220, 22, "")
    row.button:SetPoint("LEFT", LABEL_X - 4, -2)
    return row
end

C.buttons = function(panel)
    local row = BaseRow(panel, "buttons", 34)
    row.buttons = {}
    for i = 1, 4 do
        local b = W().Button(row, 128, 24, "")
        row.buttons[i] = b
    end
    function row:Refresh()
        local defs = self.item.buttons
        local x = LABEL_X - 4
        for i, b in ipairs(self.buttons) do
            local d = defs[i]
            if d then
                local label = type(d.label) == "function" and d.label() or d.label
                b.text:SetText(label)
                b:SetWidth(d.width or 128)
                b:ClearAllPoints()
                b:SetPoint("LEFT", x, 0)
                x = x + (d.width or 128) + 8
                local enabled = not d.enabled or d.enabled()
                b:SetAlpha(enabled and 1 or 0.4)
                b:EnableMouse(enabled)
                b:SetScript("OnClick", function(btn)
                    d.onClick(btn)
                    panel:RefreshAll()
                end)
                b:Show()
            else
                b:Hide()
            end
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Panel object
---------------------------------------------------------------------------
-- parent: frame the scroll area belongs to. Caller anchors panel.scroll.
function Panel.New(parent, width)
    local w = W()
    local A = w.ACCENT
    local self = setmetatable({
        width = width, active = {}, advOpen = {},
        pools = setmetatable({}, { __index = function(t, k) t[k] = {}; return t[k] end }),
    }, P)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 10)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 12, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 12, 0)
    bar:SetWidth(6)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    bar.thumb = bar:GetThumbTexture()
    bar.thumb:SetVertexColor(0.45, 0.45, 0.5, 0.9)
    bar.thumb:SetSize(6, 40)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    bar:SetScript("OnEnter", function(b) b.thumb:SetVertexColor(A[1], A[2], A[3], 1) end)
    bar:SetScript("OnLeave", function(b) b.thumb:SetVertexColor(0.45, 0.45, 0.5, 0.9) end)
    self.bar = bar

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local _, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(0, math.min(mx, bar:GetValue() - delta * 40)))
    end)
    return self
end

function P:UpdateBar(resetToTop)
    local view = self.scroll:GetHeight()
    local total = self.content:GetHeight()
    local maxV = math.max(0, total - view)
    self.bar:SetMinMaxValues(0, maxV)
    if resetToTop then self.bar:SetValue(0) else self.bar:SetValue(math.min(self.bar:GetValue(), maxV)) end
    self.bar:SetShown(maxV > 0)
    if total > 0 then self.bar.thumb:SetHeight(math.max(24, view * view / total)) end
    if maxV <= 0 then self.scroll:SetVerticalScroll(0) end
end

function P:RefreshAll()
    for _, row in ipairs(self.active) do
        if row.Refresh then row:Refresh() end
    end
    if self.onRefresh then self.onRefresh() end
end

function P:Set(item, v)
    local ok = ApplyValue(item, v)
    self:RefreshAll()
    return ok
end

function P:Release()
    for _, row in ipairs(self.active) do
        row:Hide()
        row:ClearAllPoints()
        table.insert(self.pools[row.poolKey or row.kind], row)
    end
    wipe(self.active)
end

function P:Acquire(kind, builder)
    local row = table.remove(self.pools[kind])
    if not row then
        row = builder and builder(self) or C[kind](self)
        row.poolKey = kind
    end
    row:Show()
    self.active[#self.active + 1] = row
    return row
end

local function ControlKind(item)
    local t = TypeOf(item)
    if t == "bool" then return "toggle" end
    if t == "number" then return "slider" end
    if t == "color" then return "color" end
    return "dropdown"
end

-- items: list; advKey: key for the Advanced expand state (nil = show all)
function P:Render(items, resetScroll, advKey)
    W().CloseList()
    self:Release()
    local y = 4
    local function place(row)
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        y = y + row.height
    end
    local function add(item)
        local k = item.kind
        if IsBound(item) then
            local row = self:Acquire(ControlKind(item))
            row.item = item
            row.label:SetText(item.label)
            row:Refresh()
            place(row)
        elseif k == "section" then
            local row = self:Acquire("section")
            row.label:SetText(item.label)
            place(row)
        elseif k == "note" then
            local row = self:Acquire("note")
            row:SetNote(item.textFn and item.textFn() or item.text or "")
            place(row)
        elseif k == "buttons" then
            local row = self:Acquire("buttons")
            row.item = item
            row:Refresh()
            place(row)
        elseif k == "row" then
            local row = self:Acquire(item.rowKind, item.build)
            row.item = item
            if row.Refresh then row:Refresh() end
            place(row)
        end
    end

    local advCount = 0
    for _, item in ipairs(items) do
        if item.adv and advKey then
            advCount = advCount + 1
            if self.advOpen[advKey] then add(item) end
        else
            add(item)
        end
    end
    if advCount > 0 then
        local row = self:Acquire("advanced")
        row.button.text:SetText((self.advOpen[advKey] and "Hide advanced settings" or "Show advanced settings")
            .. " (" .. advCount .. ")")
        row.button:SetScript("OnClick", function()
            self.advOpen[advKey] = not self.advOpen[advKey]
            self:Render(self.lastItems, false, advKey)
        end)
        place(row)
    end
    self.lastItems = items
    self.content:SetHeight(math.max(y + 8, 1))
    self:UpdateBar(resetScroll)
    if self.onRefresh then self.onRefresh() end
end
