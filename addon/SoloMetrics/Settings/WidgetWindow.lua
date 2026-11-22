-- SoloMetrics: per-widget settings window
-- Each widget gets its own window containing only that widget's settings.
-- Appearance controls edit the widget's OVERRIDES; "R" clears an override so
-- the value falls back to the widget defaults (a teal dot marks customized
-- settings). Data / graph / behaviour / position edit the widget record.

local _, ns = ...
local WW = {}
ns.WidgetWindow = WW

local WIN_W, WIN_H = 600, 560
local windows = {}
local openCount = 0

local function W() return ns.ConfigWidgets end
local function WS() return ns.WidgetSchema end
local function WM() return ns.WidgetManager end

local function Enum(map, order)
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = { k, map[k] } end
    return out
end

---------------------------------------------------------------------------
-- Item builders bound to one widget id
---------------------------------------------------------------------------
local function Items(id)
    local function rec() return WM().Get(id) end
    local function apply() WM().Apply(id) end

    -- record field (data/graph/behavior/position)
    local function F(group, key, label, typ, extra)
        local it = {
            kind = "custom", type = typ, label = label,
            get = function() return rec()[group][key] end,
            set = function(v)
                rec()[group][key] = v
                if extra and extra.after then extra.after(v) end
                apply()
                return true
            end,
        }
        if extra then for k, v in pairs(extra) do if k ~= "after" then it[k] = v end end end
        return it
    end

    -- appearance override
    local function AP(path, label, extra)
        local e = WS().APPEARANCE_BY_PATH[path]
        local it = {
            kind = "custom", type = e[2], min = e[3], max = e[4], label = label, path = path,
            get = function() return WS().Get(rec(), path) end,
            set = function(v)
                if type(v) == "table" then v = { v[1], v[2], v[3], v[4] or 1 } end
                if not WS().IsValidAppearance(path, v) then return false end
                rec().appearance[path] = v
                apply()
                return true
            end,
            reset = function()
                rec().appearance[path] = nil
                apply()
            end,
            isCustom = function() return rec().appearance[path] ~= nil end,
        }
        if extra then for k, v in pairs(extra) do it[k] = v end end
        return it
    end
    local function On(path) return function() return WS().Get(rec(), path) == true end end
    local function Sec(label) return { kind = "section", label = label } end

    local function resetData()
        rec().graph.autoMax = nil
        rec().graph.autoBase = nil
        WM().ResetGraph(id)
    end

    return {
        Sec("Data"),
        { kind = "note", textFn = function()
            local d = rec().data
            if d.spellID then
                return ("Spell: |cffffffff%s|r (%d). One column per completed fight, from the last %d fights the game keeps. Updates after each fight."):format(
                    d.spellName or "?", d.spellID, WS().MAX_FIGHTS)
            elseif d.kind == "fights" then
                return "One column per completed fight (readable results). Updates after each fight."
            end
            return "Live: sampled during combat from the game's running values (hidden from addons, drawn by the game)."
        end },
        F("data", "kind", "Source", "enum", {
            values = { { "live", "Live (during combat)" }, { "fights", "Per fight (last fights)" } },
            depFn = function() return not rec().data.spellID end,
            tip = "Spell widgets are always per fight: spell identities are hidden during combat.",
            after = resetData }),
        F("data", "metric", "Metric", "enum", {
            values = function()
                local d = rec().data
                if d.kind == "fights" then
                    local o = {}
                    for _, k in ipairs(WS().FIGHT_METRIC_ORDER) do
                        if k ~= "share" or d.spellID then o[#o + 1] = { k, WS().FIGHT_METRICS[k] } end
                    end
                    return o
                end
                return Enum(WS().METRICS, WS().METRIC_ORDER)
            end,
            tip = "Average DPS so far = the game's running average (total / time). Total damage only rises during a fight.",
            after = resetData }),
        F("data", "session", "Session", "enum", { values = { { "current", "Current fight" }, { "overall", "Overall" } },
            tip = "Current resets at the start of each fight. Overall keeps adding samples across fights.",
            depFn = function() return rec().data.kind == "live" end,
            after = resetData }),

        Sec("Graph"),
        F("graph", "style", "Graph style", "enum", { values = Enum(WS().STYLES, WS().STYLE_ORDER) }),
        F("graph", "samples", "Columns shown", "number", { min = 10, max = WS().MAX_SAMPLES, step = 1,
            tip = "Live: number of samples (time window = columns x interval; the oldest drops off). Per fight: up to the last 30 fights." }),
        F("graph", "interval", "Seconds per sample", "number", { min = 0.5, max = 5, step = 0.5,
            depFn = function() return rec().data.kind == "live" end }),
        F("graph", "scaleMode", "Scale", "enum", { values = {
            { "auto", "Auto (0 to last fight x 1.5)" },
            { "focus", "Focus (50-150% of last fight)" },
            { "fixed", "Fixed maximum" },
        }, tip = "Live values are hidden from addons during combat, so scale limits come from the last finished fight or a fixed number." }),
        F("graph", "scaleMax", "Fixed maximum", "number", { min = 1, max = 5000, step = 1,
            depFn = function() return rec().graph.scaleMode == "fixed" end }),

        Sec("Behaviour"),
        F("behavior", "visibility", "Show", "enum", { values = Enum(WS().VISIBILITY, WS().VIS_ORDER) }),
        F("behavior", "locked", "Locked", "bool", { tip = "Locked widgets can't be moved or resized." }),
        F("behavior", "clickThrough", "Click-through when locked", "bool",
            { depFn = function() return rec().behavior.locked end }),

        Sec("Position & size"),
        F("position", "width", "Width", "number", { min = 120, max = 900, step = 1 }),
        F("position", "height", "Height", "number", { min = 60, max = 500, step = 1 }),
        F("position", "scale", "Scale", "number", { min = 0.5, max = 2, step = 0.05 }),
        { kind = "buttons", buttons = {
            { label = "Reset position", width = 140, onClick = function() WM().ResetPosition(id) end },
        } },

        Sec("Window"),
        AP("bg.enabled", "Show background"),
        AP("bg.color", "Background color", { depFn = On("bg.enabled") }),
        AP("bg.texture", "Background texture", { depFn = On("bg.enabled") }),
        AP("border.enabled", "Show border"),
        AP("border.color", "Border color", { depFn = On("border.enabled") }),
        AP("border.size", "Border thickness", { depFn = On("border.enabled"), step = 1, adv = true }),
        AP("padding", "Inner padding", { step = 1, adv = true }),

        Sec("Title & value"),
        AP("title.enabled", "Show title"),
        AP("title.font", "Title font", { depFn = On("title.enabled") }),
        AP("title.size", "Title size", { depFn = On("title.enabled"), step = 1 }),
        AP("title.color", "Title color", { depFn = On("title.enabled") }),
        AP("value.enabled", "Show current value"),
        AP("value.font", "Value font", { depFn = On("value.enabled") }),
        AP("value.size", "Value size", { depFn = On("value.enabled"), step = 1 }),
        AP("value.color", "Value color", { depFn = On("value.enabled") }),

        Sec("Fill / columns"),
        AP("fill.enabled", "Show fill", { tip = "Used by the Area and Columns styles." }),
        AP("fill.classColor", "Use class color", { depFn = On("fill.enabled") }),
        AP("fill.color", "Fill color", { depFn = On("fill.enabled"),
            tip = "Used when class color is off. Its opacity always applies." }),

        Sec("Line & points"),
        AP("line.enabled", "Show line", { tip = "Used by the Area and Line styles." }),
        AP("line.classColor", "Line uses class color", { depFn = On("line.enabled") }),
        AP("line.color", "Line color", { depFn = On("line.enabled") }),
        AP("line.thickness", "Line thickness", { depFn = On("line.enabled"), step = 1 }),
        AP("points.enabled", "Show points", { tip = "Not used by the Columns style." }),
        AP("points.size", "Point size", { depFn = On("points.enabled"), step = 1 }),
        AP("points.color", "Point color", { depFn = On("points.enabled") }),

        Sec("Axis & grid"),
        AP("axis.enabled", "Show scale labels"),
        AP("axis.size", "Scale label size", { depFn = On("axis.enabled"), step = 1, adv = true }),
        AP("axis.color", "Scale label color", { depFn = On("axis.enabled"), adv = true }),
        AP("grid.enabled", "Show grid lines"),
        AP("grid.lines", "Grid lines", { depFn = On("grid.enabled"), step = 1 }),
        AP("grid.color", "Grid color", { depFn = On("grid.enabled") }),
    }
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Build(id)
    local w = W()
    local A = w.ACCENT
    local f = CreateFrame("Frame", "SoloMetricsWidgetWindow_" .. id, UIParent)
    f.id = id
    f:SetSize(WIN_W, WIN_H)
    openCount = openCount + 1
    f:SetPoint("CENTER", UIParent, "CENTER", 60 + (openCount % 5) * 24, -(openCount % 5) * 24)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    w.Fill(f, "BACKGROUND", 0.075, 0.075, 0.085, 0.97)
    w.Border(f, 0.22, 0.22, 0.25, 1)
    tinsert(UISpecialFrames, f:GetName())

    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(38)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    w.Fill(title, "BACKGROUND", 0.055, 0.055, 0.065, 1)
    local accent = title:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")
    accent:SetHeight(1)
    accent:SetColorTexture(A[1], A[2], A[3], 0.6)
    f.titleText = w.Text(title, 14, { 1, 1, 1, 1 })
    f.titleText:SetPoint("LEFT", 16, 0)
    local close = CreateFrame("Button", nil, title)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -6, 0)
    close.text = w.Text(close, 16, { 0.7, 0.7, 0.75, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("x")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.4, 0.4, 1) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.7, 0.75, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.panel = ns.Panel.New(f, WIN_W - 52)
    f.panel.scroll:SetPoint("TOPLEFT", 12, -46)
    f.panel.scroll:SetPoint("BOTTOMRIGHT", -30, 88)

    -- Footer: two rows of actions
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(84)
    local fl = footer:CreateTexture(nil, "ARTWORK")
    fl:SetPoint("TOPLEFT")
    fl:SetPoint("TOPRIGHT")
    fl:SetHeight(1)
    fl:SetColorTexture(1, 1, 1, 0.06)

    local function Btn(label, width, x, y, onClick)
        local b = w.Button(footer, width, 24, label)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", onClick)
        return b
    end
    Btn("Rename", 100, 12, -10, function()
        local rec = WM().Get(id)
        w.Dialog({
            title = "Rename widget", message = "New name (1-32 characters):", text = rec.name, okLabel = "Rename",
            onOK = function(t)
                t = strtrim(t or "")
                if t == "" or #t > 32 then return false, "Name must be 1-32 characters." end
                rec.name = t
                WM().Apply(id)
                return true
            end,
        })
    end)
    Btn("Duplicate", 100, 120, -10, function()
        local nid, err = WM().Duplicate(id)
        if not nid then ns.Print(err) return end
        WW.Open(nid)
    end)
    f.moveBtn = Btn("", 130, 228, -10, function()
        local rec = WM().Get(id)
        rec.behavior.locked = not rec.behavior.locked
        WM().Apply(id)
    end)
    local del = Btn("Delete", 100, WIN_W - 112, -10, function()
        local rec = WM().Get(id)
        w.Dialog({
            title = "Delete widget",
            message = ("Delete widget '%s'? Other widgets are not affected."):format(rec.name),
            noInput = true, okLabel = "Delete",
            onOK = function()
                WM().Delete(id)
                return true
            end,
        })
    end)
    del.text:SetTextColor(1, 0.5, 0.5, 1)

    f.copyBtn = Btn("Copy appearance from...", 180, 12, -46, function(self)
        local opts = {}
        for _, oid in ipairs(WM().List()) do
            if oid ~= id then
                local o = WM().Get(oid)
                opts[#opts + 1] = { value = oid, label = o.name .. "  (" .. oid .. ")" }
            end
        end
        if #opts == 0 then ns.Print("No other widgets to copy from.") return end
        w.OpenList(self, opts, nil, function(src)
            WM().Get(id).appearance = ns.Theme.DeepCopy(WM().Get(src).appearance)
            WM().Apply(id)
        end)
    end)
    Btn("Use as default for new widgets", 210, 200, -46, function()
        ns.db.widgets.defaults.appearance = ns.Theme.DeepCopy(WM().Get(id).appearance)
        WM().ApplyAll()
        ns.Print("This widget's appearance is now the default for widgets without their own overrides.")
    end)
    Btn("Reset appearance", 140, WIN_W - 152, -46, function()
        WM().Get(id).appearance = {}
        WM().Apply(id)
    end)

    f.panel.onRefresh = function()
        local rec = WM().Get(id)
        if not rec then return end
        f.titleText:SetText(rec.name .. "  |cff707078" .. id .. " settings|r")
        f.moveBtn.text:SetText(rec.behavior.locked and "Unlock (move)" or "Lock in place")
    end

    f:SetScript("OnHide", function()
        w.CloseList()
        w.CloseColorPicker()
    end)
    windows[id] = f
    return f
end

function WW.Open(id)
    if not WM().Get(id) then return end
    local f = windows[id] or Build(id)
    f:Show()
    f:Raise()
    f.panel:Render(Items(id), true, "widget")
end

-- Called after a widget changed elsewhere (commands, list buttons).
function WW.Refresh(id)
    local f = windows[id]
    if f and f:IsShown() then
        if WM().Get(id) then f.panel:RefreshAll() else f:Hide() end
    end
end

function WW.Close(id)
    local f = windows[id]
    if f then f:Hide() end
end
