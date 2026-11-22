-- SoloMetrics: configuration window (/sm config)
-- Left category list + search, right scrollable settings pane, footer actions.
-- Changes apply instantly to the real meter. "Revert" restores the validated
-- snapshot taken when the window opened. The window is independent of the
-- meter's visibility, opacity and click-through state.

local _, ns = ...
local C = {}
ns.Config = C

local W -- ns.ConfigWidgets (resolved at build)
local A

local WIN_W, WIN_H = 800, 560
local SIDEBAR_W = 184
local CONTENT_W = WIN_W - SIDEBAR_W - 52
local LABEL_X, CONTROL_X = 12, 250

local win, scroll, content, searchBox, footer
local navButtons = {}
local currentCat = "general"
local query = ""
local advOpen = {}
local active = {}
local pools = setmetatable({}, { __index = function(t, k) t[k] = {}; return t[k] end })
local constructors = {}
local snapshot
local demoStartedHere = false

---------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------
local function Active() return ns.Theme.Active() end

local function TypeOf(item)
    if item.kind == "style" then
        local e = ns.Theme.SCHEMA_BY_PATH[item.path]
        return e[2], e[3], e[4]
    end
    return item.type, item.min, item.max
end

local function GetValue(item)
    if item.kind == "style" then return ns.Theme.GetPath(Active(), item.path) end
    return ns.db.meter[item.key]
end

local function DefaultOf(item)
    if item.kind == "style" then return ns.Theme.GetDefault(item.path) end
    return ns.METER_DEFAULTS[item.key]
end

local function DepOK(item)
    if not item.dep then return true end
    return ns.Theme.GetPath(Active(), item.dep) == true
end

local function ApplyValue(item, v)
    if item.kind == "style" then
        if type(v) == "table" then v = { v[1], v[2], v[3], v[4] or 1 } end
        if not ns.Theme.IsValidValue(item.path, v) then return false end
        ns.Theme.SetPath(Active(), item.path, v)
        ns.SpellMeter.ApplyStyle()
    else
        local t, mn, mx = TypeOf(item)
        if t == "number" and (type(v) ~= "number" or v < mn or v > mx) then return false end
        ns.db.meter[item.key] = v
        ns.SpellMeter.ApplyMeterSetting(item.key)
    end
    return true
end

local function RefreshAll()
    for _, row in ipairs(active) do
        if row.Refresh then row:Refresh() end
    end
    if footer then footer:Refresh() end
end

local function SetValue(item, v)
    local ok = ApplyValue(item, v)
    RefreshAll()
    return ok
end

local function RoundStep(v, step)
    step = step or 1
    return math.floor(v / step + 0.5) * step
end

local function FormatNumber(v, step)
    if type(v) ~= "number" then return "" end
    if (step or 1) < 1 then return ("%.2f"):format(v) end
    return tostring(math.floor(v + 0.5))
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function ShowTip(row)
    local item = row.item
    if not item or not item.label then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(item.label, 1, 1, 1)
    if item.tip then GameTooltip:AddLine(item.tip, 0.8, 0.8, 0.8, true) end
    if item.dep and not DepOK(item) then
        GameTooltip:AddLine("Disabled: turn on its parent element first. Value is kept.", 1, 0.6, 0.3, true)
    end
    local key = item.path or (item.key and ("meter." .. item.key))
    if key then GameTooltip:AddLine(key, 0.45, 0.45, 0.5) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Row constructors (pooled by kind)
---------------------------------------------------------------------------
local function BaseRow(kind, height)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_W, height)
    row.kind = kind
    row.height = height
    return row
end

local function SettingRow(kind, height)
    local row = BaseRow(kind, height)
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.hl = W.Fill(row, "BACKGROUND", 1, 1, 1, 0.03)
    row.hl:Hide()
    row:HookScript("OnEnter", function(self) self.hl:Show() end)
    row:HookScript("OnLeave", function(self) self.hl:Hide() end)
    row.label = W.Text(row, 12)
    row.label:SetPoint("LEFT", LABEL_X, 0)
    row.label:SetWidth(CONTROL_X - LABEL_X - 8)
    row.label:SetWordWrap(false)

    local reset = CreateFrame("Button", nil, row)
    reset:SetSize(16, 16)
    reset:SetPoint("RIGHT", -6, 0)
    reset.icon = W.Text(reset, 11, { 0.55, 0.55, 0.6, 1 }, "CENTER")
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
        SetValue(row.item, DefaultOf(row.item))
    end)
    row.reset = reset
    row.inputs = {}

    function row:SetEnabledState(on)
        self:SetAlpha(on and 1 or 0.4)
        for _, f in ipairs(self.inputs) do
            f:EnableMouse(on)
            if not on and f.ClearFocus then f:ClearFocus() end
        end
    end
    return row
end

constructors.toggle = function()
    local row = SettingRow("toggle", 28)
    row.check = W.Check(row)
    row.check:SetPoint("LEFT", CONTROL_X, 0)
    row.check:SetScript("OnClick", function() SetValue(row.item, not row.check.on) end)
    row.inputs = { row.check }
    function row:Refresh()
        self.check:SetOn(GetValue(self.item))
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

constructors.slider = function()
    local row = SettingRow("slider", 28)
    row.slider = W.Slider(row, 200)
    row.slider:SetPoint("LEFT", CONTROL_X, 0)
    row.edit = W.Edit(row, 54)
    row.edit:SetPoint("LEFT", row.slider, "RIGHT", 12, 0)
    row.slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        local _, mn, mx = TypeOf(row.item)
        local v = math.max(mn, math.min(mx, RoundStep(value, row.item.step)))
        if v ~= GetValue(row.item) then SetValue(row.item, v) end
    end)
    row.edit.onCommit = function(text)
        local v = tonumber(text)
        if not v then return end
        local _, mn, mx = TypeOf(row.item)
        v = math.max(mn, math.min(mx, RoundStep(v, row.item.step)))
        SetValue(row.item, v)
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
        if not self.edit:HasFocus() then self.edit:SetText(FormatNumber(v, self.item.step)) end
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
    elseif t == "enum" then
        for _, v in ipairs(item.values) do
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

constructors.dropdown = function()
    local row = SettingRow("dropdown", 28)
    row.button = W.Button(row, 220, 22, "")
    row.button:SetPoint("LEFT", CONTROL_X, 0)
    row.button.text:SetJustifyH("LEFT")
    row.button.arrow = W.Text(row.button, 10, { 0.6, 0.6, 0.65, 1 }, "RIGHT")
    row.button.arrow:SetPoint("RIGHT", -6, 0)
    row.button.arrow:SetText("v")
    row.button:SetScript("OnClick", function(self)
        W.OpenList(self, OptionsFor(row.item), GetValue(row.item), function(v) SetValue(row.item, v) end)
    end)
    row.inputs = { row.button }
    function row:Refresh()
        local label, opt = LabelFor(self.item, GetValue(self.item))
        self.button.text:SetText(label)
        local font = opt and opt.font or W.Font()
        self.button.text:SetFont(font, 12, "")
        if not self.button.text:GetFont() then self.button.text:SetFont(W.Font(), 12, "") end
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

constructors.color = function()
    local row = SettingRow("color", 28)
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(26, 18)
    sw:SetPoint("LEFT", CONTROL_X, 0)
    -- checker hint behind the swatch so opacity is visible
    local back = W.Fill(sw, "BACKGROUND", 0.55, 0.55, 0.55, 1)
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
    sw.border = W.Border(sw, 0.4, 0.4, 0.45, 1)
    sw:SetScript("OnClick", function()
        local ok = W.PickColor(GetValue(row.item), function(r, g, b, a)
            SetValue(row.item, { r, g, b, a })
        end)
        if not ok then ns.Print("Color picker unavailable on this client - type a hex value instead.") end
    end)
    row.swatch = sw
    row.swatchBack = back
    row.edit = W.Edit(row, 96)
    row.edit:SetPoint("LEFT", sw, "RIGHT", 10, 0)
    row.edit:SetMaxLetters(9)
    row.edit.onCommit = function(text)
        local v, err = ns.Theme.ParseValue(row.item.path, text)
        if v == nil then
            ns.Print("Invalid color: " .. err)
            return
        end
        SetValue(row.item, v)
    end
    row.edit.onRevert = function() row:Refresh() end
    row.hint = W.Text(row, 10, { 0.5, 0.5, 0.55, 1 })
    row.hint:SetPoint("LEFT", row.edit, "RIGHT", 8, 0)
    row.hint:SetText("#RRGGBBAA")
    row.inputs = { sw, row.edit }
    function row:Refresh()
        local c = GetValue(self.item)
        self.swatch.color:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        if not self.edit:HasFocus() then
            self.edit:SetText("#" .. ns.Theme.FormatValue(ns.Theme.SCHEMA_BY_PATH[self.item.path], c))
        end
        self:SetEnabledState(DepOK(self.item))
    end
    return row
end

constructors.section = function()
    local row = BaseRow("section", 34)
    row.label = W.Text(row, 13, { A[1], A[2], A[3], 1 })
    row.label:SetPoint("BOTTOMLEFT", LABEL_X - 4, 8)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", LABEL_X - 4, 3)
    line:SetPoint("BOTTOMRIGHT", -6, 3)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)
    return row
end

constructors.note = function()
    local row = BaseRow("note", 30)
    row.label = W.Text(row, 12, { 0.7, 0.7, 0.74, 1 })
    row.label:SetPoint("TOPLEFT", LABEL_X, -6)
    row.label:SetWidth(CONTENT_W - 2 * LABEL_X)
    row.label:SetWordWrap(true)
    function row:SetNote(text)
        self.label:SetText(text)
        self.height = math.ceil(self.label:GetStringHeight()) + 14
        self:SetHeight(self.height)
    end
    return row
end

constructors.advanced = function()
    local row = BaseRow("advanced", 32)
    row.button = W.Button(row, 220, 22, "")
    row.button:SetPoint("LEFT", LABEL_X - 4, -2)
    return row
end

local ACTIONS = {
    move = {
        label = function() return ns.db.meter.locked and "Unlock / move meter" or "Lock meter" end,
        run = function() ns.SpellMeter.SetLocked(not ns.db.meter.locked) end,
    },
    resetpos = {
        label = function() return "Reset position" end,
        run = function() ns.SpellMeter.ResetPosition() end,
    },
}

constructors.action = function()
    local row = BaseRow("action", 34)
    row.buttons = {}
    for i = 1, 3 do
        local b = W.Button(row, 170, 24, "")
        b:SetPoint("LEFT", LABEL_X - 4 + (i - 1) * 180, 0)
        row.buttons[i] = b
    end
    function row:Refresh()
        for i, b in ipairs(self.buttons) do
            local id = self.item.actions[i]
            if id then
                b.text:SetText(ACTIONS[id].label())
                b:SetScript("OnClick", function() ACTIONS[id].run(); RefreshAll() end)
                b:Show()
            else
                b:Hide()
            end
        end
    end
    return row
end

constructors.presets = function()
    local row = BaseRow("presets", 70)
    row.cards = {}
    for i, key in ipairs(ns.Theme.PRESET_ORDER) do
        local p = ns.Theme.PRESETS[key]
        local b = W.Button(row, 132, 56, "")
        b:SetPoint("TOPLEFT", LABEL_X - 4 + (i - 1) * 138, -6)
        b.text:ClearAllPoints()
        b.text:SetPoint("TOPLEFT", 8, -8)
        b.text:SetPoint("TOPRIGHT", -8, -8)
        b.text:SetJustifyH("LEFT")
        b.text:SetText((p.label:gsub(" %(.*%)", "")))
        b.sub = W.Text(b, 10, { 0.6, 0.6, 0.65, 1 })
        b.sub:SetPoint("BOTTOMLEFT", 8, 8)
        b.sub:SetText("Apply preset")
        b:SetScript("OnClick", function()
            ns.db.profiles[ns.db.activeProfile] = ns.Theme.BuildPreset(key)
            ns.SpellMeter.ApplyStyle()
            RefreshAll()
            ns.Print("Applied preset: " .. p.label)
        end)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(p.label, 1, 1, 1)
            GameTooltip:AddLine("Replaces the current profile's style. Use Revert to undo.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        row.cards[i] = b
    end
    return row
end

---------------------------------------------------------------------------
-- Page rendering
---------------------------------------------------------------------------
local function ReleaseAll()
    for _, row in ipairs(active) do
        row:Hide()
        row:ClearAllPoints()
        table.insert(pools[row.kind], row)
    end
    wipe(active)
end

local function Acquire(kind)
    local row = table.remove(pools[kind]) or constructors[kind]()
    row:Show()
    active[#active + 1] = row
    return row
end

local function ControlKind(item)
    local t = TypeOf(item)
    if t == "bool" then return "toggle" end
    if t == "number" then return "slider" end
    if t == "color" then return "color" end
    return "dropdown"
end

local function CategoryById(id)
    for _, cat in ipairs(ns.ConfigRegistry.CATEGORIES) do
        if cat.id == id then return cat end
    end
end

local function Render(resetScroll)
    W.CloseList()
    ReleaseAll()
    local y = 4
    local function place(row)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + row.height
    end
    local function addItem(item)
        local k = item.kind
        if k == "style" or k == "meter" then
            local row = Acquire(ControlKind(item))
            row.item = item
            row.label:SetText(item.label)
            row:Refresh()
            place(row)
        elseif k == "section" then
            local row = Acquire("section")
            row.label:SetText(item.label)
            place(row)
        elseif k == "note" then
            local row = Acquire("note")
            if item.profileInfo then
                row:SetNote(("Active profile: |cffffffff%s|r. Presets below replace this profile's style."):format(ns.db.activeProfile))
            else
                row:SetNote(item.text)
            end
            place(row)
        elseif k == "presets" then
            place(Acquire("presets"))
        elseif k == "action" then
            local row = Acquire("action")
            row.item = item
            row:Refresh()
            place(row)
        end
    end

    if query ~= "" then
        local any = false
        for _, cat in ipairs(ns.ConfigRegistry.CATEGORIES) do
            local header = false
            for _, item in ipairs(cat.items) do
                if (item.kind == "style" or item.kind == "meter") then
                    local hay = ((item.label or "") .. " " .. (item.tip or "") .. " " .. (item.path or item.key or "")):lower()
                    if hay:find(query, 1, true) then
                        if not header then
                            addItem({ kind = "section", label = cat.label })
                            header = true
                        end
                        addItem(item)
                        any = true
                    end
                end
            end
        end
        if not any then addItem({ kind = "note", text = "No settings match \"" .. query .. "\"." }) end
    else
        local cat = CategoryById(currentCat)
        local advCount = 0
        for _, item in ipairs(cat.items) do
            if item.adv then
                advCount = advCount + 1
                if advOpen[cat.id] then addItem(item) end
            else
                addItem(item)
            end
        end
        if advCount > 0 then
            local row = Acquire("advanced")
            row.button.text:SetText((advOpen[cat.id] and "Hide advanced settings" or "Show advanced settings") .. " (" .. advCount .. ")")
            row.button:SetScript("OnClick", function()
                advOpen[cat.id] = not advOpen[cat.id]
                Render(false)
            end)
            place(row)
        end
    end

    content:SetHeight(math.max(y + 8, 1))
    scroll:UpdateBar(resetScroll)
    for _, b in ipairs(navButtons) do b:UpdateState() end
    footer:Refresh()
end

---------------------------------------------------------------------------
-- Snapshot / revert / category reset
---------------------------------------------------------------------------
local function TakeSnapshot()
    snapshot = {
        profile = ns.db.activeProfile,
        style = ns.Theme.DeepCopy(Active()),
        meter = ns.Theme.DeepCopy(ns.db.meter),
    }
end

local function Revert()
    if not snapshot then return end
    ns.db.activeProfile = snapshot.profile
    ns.db.profiles[snapshot.profile] = ns.Theme.Validate(ns.Theme.DeepCopy(snapshot.style))
    ns.db.meter = ns.Theme.DeepCopy(snapshot.meter)
    ns.SpellMeter.ReapplyAll()
    Render(false)
    ns.Print("Reverted all changes made since the settings window was opened.")
end

local function ResetCategory()
    if query ~= "" then return end
    local cat = CategoryById(currentCat)
    for _, item in ipairs(cat.items) do
        if item.kind == "style" or item.kind == "meter" then
            ApplyValue(item, DefaultOf(item))
        end
    end
    RefreshAll()
    ns.Print("Reset " .. cat.label .. " to defaults.")
end

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------
local function Build()
    W = ns.ConfigWidgets
    A = W.ACCENT

    win = CreateFrame("Frame", "SoloMetricsConfig", UIParent)
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER")
    -- HIGH (not DIALOG) so the native ColorPickerFrame (DIALOG) opens above it.
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:Hide()
    W.Fill(win, "BACKGROUND", 0.075, 0.075, 0.085, 0.97)
    W.Border(win, 0.22, 0.22, 0.25, 1)
    tinsert(UISpecialFrames, "SoloMetricsConfig")

    -- Title bar
    local title = CreateFrame("Frame", nil, win)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(38)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() win:StartMoving() end)
    title:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    W.Fill(title, "BACKGROUND", 0.055, 0.055, 0.065, 1)
    local accent = title:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")
    accent:SetHeight(1)
    accent:SetColorTexture(A[1], A[2], A[3], 0.6)
    local name = W.Text(title, 15, { 1, 1, 1, 1 })
    name:SetPoint("LEFT", 16, 0)
    name:SetText("Solo|cff40c7b8Metrics|r")
    local ver = W.Text(title, 11, { 0.5, 0.5, 0.55, 1 })
    ver:SetPoint("LEFT", name, "RIGHT", 8, -1)
    ver:SetText("v" .. ns.VERSION .. "  -  settings")

    local close = CreateFrame("Button", nil, title)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -6, 0)
    close.text = W.Text(close, 16, { 0.7, 0.7, 0.75, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("x")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.4, 0.4, 1) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.7, 0.75, 1) end)
    close:SetScript("OnClick", function() win:Hide() end)

    -- Sidebar
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 0, -38)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDEBAR_W)
    W.Fill(side, "BACKGROUND", 0.06, 0.06, 0.07, 1)
    local sep = side:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    sep:SetColorTexture(1, 1, 1, 0.06)

    searchBox = W.Edit(side, SIDEBAR_W - 24)
    searchBox:SetHeight(24)
    searchBox:SetPoint("TOPLEFT", 12, -12)
    searchBox.placeholder = W.Text(searchBox, 12, { 0.45, 0.45, 0.5, 1 })
    searchBox.placeholder:SetPoint("LEFT", 6, 0)
    searchBox.placeholder:SetText("Search settings")
    searchBox:SetScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        self.placeholder:SetShown(text == "")
        local q = text:lower()
        if q ~= query then
            query = q
            Render(true)
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox.onRevert = nil

    for i, cat in ipairs(ns.ConfigRegistry.CATEGORIES) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDEBAR_W, 30)
        b:SetPoint("TOPLEFT", 0, -50 - (i - 1) * 30)
        b.sel = W.Fill(b, "BACKGROUND", A[1], A[2], A[3], 0.14)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.bar:SetWidth(3)
        b.bar:SetColorTexture(A[1], A[2], A[3], 1)
        b.hl = W.Fill(b, "BORDER", 1, 1, 1, 0.04)
        b.hl:Hide()
        b.text = W.Text(b, 13)
        b.text:SetPoint("LEFT", 18, 0)
        b.text:SetText(cat.label)
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function()
            currentCat = cat.id
            if query ~= "" then
                searchBox:SetText("")
                query = ""
            end
            Render(true)
        end)
        function b:UpdateState()
            local on = (query == "" and currentCat == cat.id)
            self.sel:SetShown(on)
            self.bar:SetShown(on)
            self.text:SetTextColor(on and 1 or 0.75, on and 1 or 0.75, on and 1 or 0.78, 1)
        end
        navButtons[i] = b
    end

    -- Content scroll area: plain ScrollFrame + slim custom scrollbar that only
    -- shows when the page is taller than the view.
    scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", SIDEBAR_W + 12, -46)
    scroll:SetPoint("BOTTOMRIGHT", -30, 52)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(content)

    local bar = CreateFrame("Slider", nil, win)
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
    bar:SetScript("OnEnter", function(self) self.thumb:SetVertexColor(A[1], A[2], A[3], 1) end)
    bar:SetScript("OnLeave", function(self) self.thumb:SetVertexColor(0.45, 0.45, 0.5, 0.9) end)
    scroll.bar = bar

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local _, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(0, math.min(mx, bar:GetValue() - delta * 40)))
    end)

    function scroll:UpdateBar(resetToTop)
        local view = self:GetHeight()
        local total = content:GetHeight()
        local maxV = math.max(0, total - view)
        bar:SetMinMaxValues(0, maxV)
        if resetToTop then bar:SetValue(0) else bar:SetValue(math.min(bar:GetValue(), maxV)) end
        bar:SetShown(maxV > 0)
        if total > 0 then
            bar.thumb:SetHeight(math.max(24, view * view / total))
        end
        if maxV <= 0 then self:SetVerticalScroll(0) end
    end

    -- Footer
    footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", SIDEBAR_W, 0)
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(46)
    local fl = footer:CreateTexture(nil, "ARTWORK")
    fl:SetPoint("TOPLEFT")
    fl:SetPoint("TOPRIGHT")
    fl:SetHeight(1)
    fl:SetColorTexture(1, 1, 1, 0.06)

    local demoBtn = W.Button(footer, 150, 26, "")
    demoBtn:SetPoint("LEFT", 12, 0)
    demoBtn:SetScript("OnClick", function()
        if ns.Demo.IsActive() then
            ns.Demo.Stop()
            demoStartedHere = false
        elseif InCombatLockdown() then
            ns.Print("Demo preview is unavailable in combat.")
        else
            ns.Demo.Toggle("60")
            demoStartedHere = true
        end
        footer:Refresh()
    end)
    local moveBtn = W.Button(footer, 150, 26, "")
    moveBtn:SetPoint("LEFT", demoBtn, "RIGHT", 8, 0)
    moveBtn:SetScript("OnClick", function()
        ns.SpellMeter.SetLocked(not ns.db.meter.locked)
        RefreshAll()
    end)
    local revertBtn = W.Button(footer, 120, 26, "Revert changes")
    revertBtn:SetPoint("RIGHT", -12, 0)
    revertBtn:SetScript("OnClick", Revert)
    revertBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Revert changes")
        GameTooltip:AddLine("Restore every setting to how it was when this window was opened.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    revertBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local resetBtn = W.Button(footer, 120, 26, "Reset category")
    resetBtn:SetPoint("RIGHT", revertBtn, "LEFT", -8, 0)
    resetBtn:SetScript("OnClick", ResetCategory)

    function footer:Refresh()
        demoBtn.text:SetText(ns.Demo.IsActive() and "Stop demo preview" or "Start demo preview")
        moveBtn.text:SetText(ns.db.meter.locked and "Unlock / move meter" or "Lock meter")
        resetBtn:SetShown(query == "")
    end

    win:SetScript("OnHide", function()
        W.CloseList()
        if demoStartedHere and ns.Demo.IsActive() then ns.Demo.Stop() end
        demoStartedHere = false
    end)

    local missing, total = ns.ConfigRegistry.CoverageCheck()
    if #missing > 0 then
        ns.Print(("Config coverage: %d of %d settings have no control: %s"):format(
            #missing, total, table.concat(missing, ", ")))
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function C.Open()
    if not win then Build() end
    TakeSnapshot()
    win:Show()
    Render(true)
end

function C.Toggle()
    if win and win:IsShown() then
        win:Hide()
    else
        C.Open()
    end
end
