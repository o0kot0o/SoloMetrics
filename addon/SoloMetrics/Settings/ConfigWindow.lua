-- SoloMetrics: configuration window (/sm config)
-- Left category list + search, right settings panel (Settings/Panel.lua),
-- footer actions. Changes apply instantly. "Revert" restores the validated
-- snapshot taken when the window opened. Independent of the meter's
-- visibility, opacity and click-through state.

local _, ns = ...
local C = {}
ns.Config = C

local W -- ns.ConfigWidgets (resolved at build)
local A

local WIN_W, WIN_H = 800, 560
local SIDEBAR_W = 184
local CONTENT_W = WIN_W - SIDEBAR_W - 52

local win, panel, searchBox, footer
local navButtons = {}
local currentCat = "general"
local query = ""
local snapshot
local demoStartedHere = false
local Render -- forward

local function LX() return ns.Panel.LABEL_X end
local function CX() return ns.Panel.CONTROL_X end

local function CategoryById(id)
    for _, cat in ipairs(ns.ConfigRegistry.CATEGORIES) do
        if cat.id == id then return cat end
    end
end

---------------------------------------------------------------------------
-- Special rows (built through Panel "row" items)
---------------------------------------------------------------------------
local function PresetsRow(p)
    local row = CreateFrame("Frame", nil, p.content)
    row:SetSize(p.width, 70)
    row.height = 70
    for i, key in ipairs(ns.Theme.PRESET_ORDER) do
        local pr = ns.Theme.PRESETS[key]
        local b = W.Button(row, 132, 56, "")
        b:SetPoint("TOPLEFT", LX() - 4 + (i - 1) * 138, -6)
        b.text:ClearAllPoints()
        b.text:SetPoint("TOPLEFT", 8, -8)
        b.text:SetPoint("TOPRIGHT", -8, -8)
        b.text:SetJustifyH("LEFT")
        b.text:SetText((pr.label:gsub(" %(.*%)", "")))
        b.sub = W.Text(b, 10, { 0.6, 0.6, 0.65, 1 })
        b.sub:SetPoint("BOTTOMLEFT", 8, 8)
        b.sub:SetText("Apply preset")
        b:SetScript("OnClick", function()
            ns.db.profiles[ns.Profiles.ActiveName()] = ns.Theme.BuildPreset(key)
            ns.SpellMeter.ApplyStyle()
            p:RefreshAll()
            ns.Print("Applied preset: " .. pr.label)
        end)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(pr.label, 1, 1, 1)
            GameTooltip:AddLine("Replaces the current profile's style. Use Revert to undo.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return row
end

local function AfterProfileChange() Render(false) end

local function ProfileActions()
    local P = ns.Profiles
    return {
        new = function()
            W.Dialog({
                title = "New profile",
                message = "Creates a profile with the default Modern Dark style and switches to it.",
                text = P.UniqueName("New profile"), okLabel = "Create",
                onOK = function(t)
                    local n, err = P.Create(t, false)
                    if not n then return false, err end
                    AfterProfileChange()
                    return true
                end,
            })
        end,
        duplicate = function()
            W.Dialog({
                title = "Duplicate profile",
                message = ("Copies '%s' into a new profile and switches to it."):format(P.ActiveName()),
                text = P.UniqueName(P.ActiveName() .. " copy"), okLabel = "Duplicate",
                onOK = function(t)
                    local n, err = P.Duplicate(t)
                    if not n then return false, err end
                    AfterProfileChange()
                    return true
                end,
            })
        end,
        rename = function()
            local old = P.ActiveName()
            W.Dialog({
                title = "Rename profile",
                message = ("New name for '%s':"):format(old),
                text = old, okLabel = "Rename",
                onOK = function(t)
                    local n, err = P.Rename(old, t)
                    if not n then return false, err end
                    AfterProfileChange()
                    return true
                end,
            })
        end,
        delete = function()
            local name = P.ActiveName()
            W.Dialog({
                title = "Delete profile",
                message = ("Delete profile '%s'? This can't be undone once the settings window is closed (Revert changes still works until then)."):format(name),
                noInput = true, okLabel = "Delete",
                onOK = function()
                    local ok, err = P.Delete(name)
                    if not ok then return false, err end
                    AfterProfileChange()
                    return true
                end,
            })
        end,
        export = function()
            W.Dialog({
                title = "Export profile",
                message = ("Share code for '%s'. Press Ctrl+C to copy. It contains only appearance settings - no character, realm or combat data."):format(P.ActiveName()),
                text = P.Export(P.ActiveName()), multiline = true, readOnly = true,
                okLabel = "Done", hideCancel = true,
            })
        end,
        import = function()
            W.Dialog({
                title = "Import profile",
                message = "Paste a SoloMetrics profile code (Ctrl+V). It is added as a new profile; your existing profiles are not changed.",
                text = "", multiline = true, okLabel = "Import",
                onOK = function(t)
                    local n, info = P.Import(t)
                    if not n then return false, info end
                    if info and info > 0 then
                        ns.Print(("Imported '%s' (%d setting(s) from a newer version were skipped)."):format(n, info))
                    else
                        ns.Print(("Imported profile '%s'."):format(n))
                    end
                    AfterProfileChange()
                    return true
                end,
            })
        end,
    }
end

local function ProfilesRow(p)
    local P = ns.Profiles
    local actions = ProfileActions()
    local row = CreateFrame("Frame", nil, p.content)
    row:SetSize(p.width, 128)
    row.height = 128
    row.label = W.Text(row, 12)
    row.label:SetPoint("TOPLEFT", LX(), -12)
    row.label:SetText("Active profile")
    row.select = W.Button(row, 220, 22, "")
    row.select:SetPoint("TOPLEFT", CX(), -8)
    row.select.text:SetJustifyH("LEFT")
    row.select.arrow = W.Text(row.select, 10, { 0.6, 0.6, 0.65, 1 }, "RIGHT")
    row.select.arrow:SetPoint("RIGHT", -6, 0)
    row.select.arrow:SetText("v")
    row.select:SetScript("OnClick", function(self)
        local opts = {}
        for _, n in ipairs(P.List()) do opts[#opts + 1] = { value = n, label = n } end
        W.OpenList(self, opts, P.ActiveName(), function(v)
            P.Switch(v)
            AfterProfileChange()
        end)
    end)
    row.perCharLabel = W.Text(row, 12)
    row.perCharLabel:SetPoint("TOPLEFT", LX(), -44)
    row.perCharLabel:SetText("Separate profile for this character")
    row.perChar = W.Check(row)
    row.perChar:SetPoint("TOPLEFT", CX(), -42)
    row.perChar:SetScript("OnClick", function()
        P.SetPerCharacter(not P.IsPerCharacter())
        AfterProfileChange()
    end)
    row.buttons = {}
    local defs = { { "new", "New" }, { "duplicate", "Duplicate" }, { "rename", "Rename" }, { "delete", "Delete" } }
    for i, def in ipairs(defs) do
        local b = W.Button(row, 120, 24, def[2])
        b:SetPoint("TOPLEFT", LX() - 4 + (i - 1) * 128, -80)
        b:SetScript("OnClick", actions[def[1]])
        row.buttons[def[1]] = b
    end
    function row:Refresh()
        self.select.text:SetText(P.ActiveName())
        self.perChar:SetOn(P.IsPerCharacter())
        local canDelete = #P.List() > 1
        self.buttons.delete:SetAlpha(canDelete and 1 or 0.4)
        self.buttons.delete:EnableMouse(canDelete)
    end
    return row
end

-- One row per widget: name, details, Edit / Show-Hide / Delete.
local function WidgetEntryRow(p)
    local row = CreateFrame("Frame", nil, p.content)
    row:SetSize(p.width, 44)
    row.height = 44
    local bg = W.Fill(row, "BACKGROUND", 1, 1, 1, 0.03)
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", LX() - 4, -2)
    bg:SetPoint("BOTTOMRIGHT", -6, 2)
    row.name = W.Text(row, 13, { 1, 1, 1, 1 })
    row.name:SetPoint("TOPLEFT", LX() + 4, -8)
    row.info = W.Text(row, 10, { 0.6, 0.6, 0.65, 1 })
    row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.edit = W.Button(row, 64, 22, "Edit")
    row.edit.text:SetTextColor(A[1], A[2], A[3], 1)
    row.dup = W.Button(row, 50, 22, "Copy")
    row.toggle = W.Button(row, 56, 22, "")
    row.delete = W.Button(row, 60, 22, "Delete")
    row.delete:SetPoint("RIGHT", -12, 0)
    row.toggle:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
    row.dup:SetPoint("RIGHT", row.toggle, "LEFT", -6, 0)
    row.edit:SetPoint("RIGHT", row.dup, "LEFT", -6, 0)
    function row:Refresh()
        local id = self.item.widgetId
        local w = ns.WidgetManager.Get(id)
        if not w then return end
        local WS = ns.WidgetSchema
        self.name:SetText(w.name .. "  |cff707078" .. id .. "|r")
        local kindText = (w.type == "graph") and (WS.STYLES[w.graph.style] .. " graph") or "Counter"
        self.info:SetText(("%s  -  %s  -  %s%s"):format(kindText, WS.Label(w),
            WS.VISIBILITY[w.behavior.visibility], w.behavior.locked and "  -  locked" or ""))
        self.dup:SetScript("OnClick", function()
            local nid, err = ns.WidgetManager.Duplicate(id)
            if not nid then ns.Print(err) end
        end)
        local hidden = w.behavior.visibility == "hidden"
        self.toggle.text:SetText(hidden and "Show" or "Hide")
        self.edit:SetScript("OnClick", function() ns.WidgetWindow.Open(id) end)
        self.toggle:SetScript("OnClick", function()
            w.behavior.visibility = hidden and "always" or "hidden"
            ns.WidgetManager.Apply(id)
            p:RefreshAll()
        end)
        self.delete:SetScript("OnClick", function()
            W.Dialog({
                title = "Delete widget",
                message = ("Delete widget '%s'? Other widgets are not affected."):format(w.name),
                noInput = true, okLabel = "Delete",
                onOK = function()
                    ns.WidgetManager.Delete(id)
                    Render(false)
                    return true
                end,
            })
        end)
    end
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

local function CreateWidget(metric, style, kind, wtype)
    local id, err = ns.WidgetManager.Create({ metric = metric, style = style, kind = kind, type = wtype })
    if not id then
        ns.Print(err)
        return
    end
    Render(false)
    ns.WidgetWindow.Open(id)
end

-- Expands registry items into Panel items (special kinds -> row/buttons).
local function Expand(items)
    local out = {}
    for _, item in ipairs(items) do
        local k = item.kind
        if k == "presets" then
            out[#out + 1] = { kind = "row", rowKind = "presets", build = PresetsRow }
        elseif k == "profiles" then
            out[#out + 1] = { kind = "row", rowKind = "profiles", build = ProfilesRow }
        elseif k == "share" then
            local actions = ProfileActions()
            out[#out + 1] = { kind = "buttons", buttons = {
                { label = "Export share code", width = 180, onClick = actions.export },
                { label = "Import share code", width = 180, onClick = actions.import },
            } }
        elseif k == "action" then
            local btns = {}
            for _, id in ipairs(item.actions) do
                btns[#btns + 1] = { label = ACTIONS[id].label, width = 170, onClick = ACTIONS[id].run }
            end
            out[#out + 1] = { kind = "buttons", buttons = btns }
        elseif k == "note" and item.profileInfo then
            out[#out + 1] = { kind = "note", textFn = function()
                return ("Presets replace the style of the active profile (|cffffffff%s|r)."):format(ns.Profiles.ActiveName())
            end }
        elseif k == "widgetlist" then
            local WM, WS = ns.WidgetManager, ns.WidgetSchema
            out[#out + 1] = { kind = "buttons", buttons = {
                { label = "+ Live DPS", width = 120, onClick = function() CreateWidget("dps", "area") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
                { label = "+ Live damage", width = 130, onClick = function() CreateWidget("damage", "bars") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
                { label = "+ DPS per fight", width = 130, onClick = function() CreateWidget("dps", "bars", "fights") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
                { label = function() return WM.IsEditAll() and "Lock all" or "Move all" end,
                  width = 110, onClick = function() WM.SetEditAll(not WM.IsEditAll()) end },
            } }
            out[#out + 1] = { kind = "buttons", buttons = {
                { label = "+ DPS counter", width = 120,
                  onClick = function() CreateWidget("dps", nil, nil, "counter") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
                { label = "+ Damage counter", width = 130,
                  onClick = function() CreateWidget("damage", nil, nil, "counter") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
                { label = "+ Last fight DPS", width = 130,
                  onClick = function() CreateWidget("dps", nil, "fights", "counter") end,
                  enabled = function() return #WM.List() < WS.MAX_WIDGETS end },
            } }
            out[#out + 1] = { kind = "section", label = ("Your widgets (%d/%d)"):format(#WM.List(), WS.MAX_WIDGETS) }
            if #WM.List() == 0 then
                out[#out + 1] = { kind = "note", text = "No widgets yet. Create one above." }
            end
            for _, id in ipairs(WM.List()) do
                out[#out + 1] = { kind = "row", rowKind = "widgetentry", build = WidgetEntryRow, widgetId = id }
            end
        else
            out[#out + 1] = item
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
function Render(resetScroll)
    if query ~= "" then
        local items, any = {}, false
        for _, cat in ipairs(ns.ConfigRegistry.CATEGORIES) do
            local header = false
            for _, item in ipairs(cat.items) do
                if ns.Panel.IsBound(item) then
                    local hay = ((item.label or "") .. " " .. (item.tip or "") .. " " .. (item.path or item.key or "")):lower()
                    if hay:find(query, 1, true) then
                        if not header then
                            items[#items + 1] = { kind = "section", label = cat.label }
                            header = true
                        end
                        items[#items + 1] = item
                        any = true
                    end
                end
            end
        end
        if not any then items[#items + 1] = { kind = "note", text = "No settings match \"" .. query .. "\"." } end
        panel:Render(items, resetScroll, nil)
    else
        local cat = CategoryById(currentCat)
        panel:Render(Expand(cat.items), resetScroll, cat.id)
    end
    for _, b in ipairs(navButtons) do b:UpdateState() end
end

---------------------------------------------------------------------------
-- Snapshot / revert / category reset
---------------------------------------------------------------------------
local function TakeSnapshot()
    snapshot = {
        activeProfile = ns.db.activeProfile,
        profiles = ns.Theme.DeepCopy(ns.db.profiles),
        charProfile = ns.Theme.DeepCopy(ns.db.charProfile),
        meter = ns.Theme.DeepCopy(ns.db.meter),
    }
end

-- Restores styles, the profile list, profile selection and meter settings.
-- (Widgets have their own windows and are not part of this snapshot.)
local function Revert()
    if not snapshot then return end
    W.CloseDialog()
    W.CloseColorPicker()
    local profiles = {}
    for name, style in pairs(snapshot.profiles) do
        profiles[name] = ns.Theme.Validate(ns.Theme.DeepCopy(style))
    end
    ns.db.profiles = profiles
    ns.db.activeProfile = snapshot.activeProfile
    ns.db.charProfile = ns.Theme.DeepCopy(snapshot.charProfile)
    ns.db.meter = ns.Theme.DeepCopy(snapshot.meter)
    ns.SpellMeter.ReapplyAll()
    Render(false)
    ns.Print("Reverted all changes made since the settings window was opened.")
end

local function ResetCategory()
    if query ~= "" then return end
    local cat = CategoryById(currentCat)
    for _, item in ipairs(cat.items) do
        if ns.Panel.IsBound(item) then ns.Panel.ResetItem(item) end
    end
    panel:RefreshAll()
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
    -- HIGH so the color picker (DIALOG) and option lists (TOOLTIP) open above it.
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:Hide()
    W.Fill(win, "BACKGROUND", 0.075, 0.075, 0.085, 0.97)
    W.Border(win, 0.22, 0.22, 0.25, 1)
    tinsert(UISpecialFrames, "SoloMetricsConfig")

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

    panel = ns.Panel.New(win, CONTENT_W)
    panel.scroll:SetPoint("TOPLEFT", SIDEBAR_W + 12, -46)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 52)

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
        panel:RefreshAll()
    end)
    local revertBtn = W.Button(footer, 120, 26, "Revert changes")
    revertBtn:SetPoint("RIGHT", -12, 0)
    revertBtn:SetScript("OnClick", Revert)
    revertBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Revert changes")
        GameTooltip:AddLine("Restore meter, appearance and profile settings to how they were when this window was opened.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    revertBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local resetBtn = W.Button(footer, 120, 26, "Reset category")
    resetBtn:SetPoint("RIGHT", revertBtn, "LEFT", -8, 0)
    resetBtn:SetScript("OnClick", ResetCategory)

    function footer:Refresh()
        demoBtn.text:SetText(ns.Demo.IsActive() and "Stop demo preview" or "Start demo preview")
        moveBtn.text:SetText(ns.db.meter.locked and "Unlock / move meter" or "Lock meter")
        resetBtn:SetShown(query == "" and currentCat ~= "widgets" and currentCat ~= "profiles")
    end
    panel.onRefresh = function() footer:Refresh() end

    win:SetScript("OnHide", function()
        W.CloseList()
        W.CloseColorPicker() -- closing without OK restores the original color
        W.CloseDialog()
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
function C.Open(categoryId)
    if not win then Build() end
    if categoryId and CategoryById(categoryId) then
        currentCat = categoryId
        query = ""
        searchBox:SetText("")
    end
    if not win:IsShown() then TakeSnapshot() end
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

-- Called by WidgetManager. full = list changed (create/delete) -> re-render;
-- otherwise just refresh the visible rows.
function C.RefreshWidgets(full)
    if not (win and win:IsShown() and currentCat == "widgets" and query == "") then return end
    if full then Render(false) else panel:RefreshAll() end
end
