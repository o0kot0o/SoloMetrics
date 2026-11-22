-- SoloMetrics: right-click menu on a meter spell row -> create a spell widget.
-- Only reachable while the meter is unlocked (a locked meter is click-through).
-- Spell identity is captured as a readable spellID OUT OF COMBAT; in combat the
-- spellID is secret, so the menu only explains why it has to wait.

local _, ns = ...
local SCM = {}
ns.SpellContextMenu = SCM

local MENU_W, ITEM_H = 250, 22
local menu, catcher
local items = {}

local function W() return ns.ConfigWidgets end

local function Close()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
SCM.Close = Close

local function Build()
    local w = W()
    local A = w.ACCENT
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", Close)
    catcher:Hide()

    menu = CreateFrame("Frame", "SoloMetricsSpellMenu", UIParent)
    menu:SetWidth(MENU_W)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    w.Fill(menu, "BACKGROUND", 0.075, 0.075, 0.085, 0.98)
    w.Border(menu, A[1], A[2], A[3], 0.6)
    menu.icon = menu:CreateTexture(nil, "ARTWORK")
    menu.icon:SetSize(20, 20)
    menu.icon:SetPoint("TOPLEFT", 8, -8)
    menu.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    menu.title = w.Text(menu, 13, { 1, 1, 1, 1 })
    menu.title:SetPoint("LEFT", menu.icon, "RIGHT", 6, 0)
    menu.title:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
    menu.title:SetWordWrap(false)
    menu.sub = w.Text(menu, 10, { A[1], A[2], A[3], 1 })
    menu.sub:SetPoint("TOPLEFT", 8, -34)
    menu.note = w.Text(menu, 11, { 0.75, 0.75, 0.8, 1 })
    menu.note:SetPoint("TOPLEFT", 8, -34)
    menu.note:SetWidth(MENU_W - 16)
    menu.note:SetWordWrap(true)
    menu:Hide()
    tinsert(UISpecialFrames, "SoloMetricsSpellMenu")
end

local function Item(i)
    local b = items[i]
    if b then return b end
    local w = W()
    b = CreateFrame("Button", nil, menu)
    b:SetSize(MENU_W - 2, ITEM_H)
    b.hl = w.Fill(b, "BACKGROUND", 1, 1, 1, 0.06)
    b.hl:Hide()
    b.text = w.Text(b, 12)
    b.text:SetPoint("LEFT", 12, 0)
    b:SetScript("OnEnter", function(self)
        if self.enabled then self.hl:Show() end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.text:GetText(), 1, 1, 1)
            GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    items[i] = b
    return b
end

local function PlaceAtCursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, y / s - 4)
end

-- defs: { { label, run = fn } | { label, disabled = true, tip = "why" } }
local function Show(title, icon, sub, note, defs)
    if not menu then Build() end
    menu.title:SetText(title)
    menu.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local y = -34
    menu.sub:SetShown(sub ~= nil)
    menu.note:SetShown(note ~= nil)
    if sub then
        menu.sub:SetText(sub)
        y = y - 16
    end
    if note then
        menu.note:ClearAllPoints()
        menu.note:SetPoint("TOPLEFT", 8, y)
        menu.note:SetText(note)
        y = y - math.ceil(menu.note:GetStringHeight()) - 8
    end
    for i, d in ipairs(defs) do
        local b = Item(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 1, y)
        y = y - ITEM_H
        b.text:SetText(d[1])
        b.enabled = not d.disabled
        b.tip = d.tip
        if d.disabled then
            b.text:SetTextColor(0.45, 0.45, 0.5, 1)
            b:SetScript("OnClick", nil)
        else
            b.text:SetTextColor(0.9, 0.9, 0.92, 1)
            b:SetScript("OnClick", function()
                Close()
                d.run()
            end)
        end
        b:Show()
    end
    for i = #defs + 1, #items do items[i]:Hide() end
    menu:SetHeight(-y + 8)
    PlaceAtCursor()
    catcher:Show()
    menu:Show()
end

local function OpenWidgetList()
    ns.Config.Open("widgets")
end

local function CreateSpellWidget(spellID, spellName, metric, wtype)
    local id, err = ns.WidgetManager.Create({
        type = wtype, kind = "fights", metric = metric, spellID = spellID, spellName = spellName, style = "bars",
    })
    if not id then
        ns.Print(err)
        return
    end
    ns.Print(("Created %s (%s). Drag it into place; its settings window is open."):format(
        id, ns.WidgetSchema.Label(ns.WidgetManager.Get(id))))
    ns.WidgetWindow.Open(id)
end

-- Explanation-only menu (combat, demo, unreadable spell).
function SCM.OpenNotice(title, note)
    Show(title, nil, nil, note, {
        { "Open widget list", run = OpenWidgetList },
    })
end

function SCM.Open(spellID, spellName, icon)
    local full = #ns.WidgetManager.List() >= ns.WidgetSchema.MAX_WIDGETS
    local limitTip = full and ("Widget limit reached (" .. ns.WidgetSchema.MAX_WIDGETS .. ").") or nil
    local name = spellName or ("Spell " .. spellID)
    Show(name, icon, "Create spell widget (completed fights)", nil, {
        { "Graph: damage per fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "damage", "graph") end },
        { "Graph: DPS per fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "dps", "graph") end },
        { "Graph: share of your damage per fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "share", "graph") end },
        { "Counter: damage - last fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "damage", "counter") end },
        { "Counter: DPS - last fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "dps", "counter") end },
        { "Counter: contribution - last fight", disabled = full, tip = limitTip,
          run = function() CreateSpellWidget(spellID, name, "share", "counter") end },
        { "Live graph / counter for this spell", disabled = true,
          tip = "Not possible: spell identities are hidden from addons during combat, so a single spell can't be picked out of the live list. Spell widgets use each fight's readable results instead." },
        { "Open widget list", run = OpenWidgetList },
    })
end
