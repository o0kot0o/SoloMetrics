-- SoloMetrics: WidgetManager
-- Owns widget records (SoloMetricsDB.widgets), their frames, a single shared
-- sampling ticker, lock / click-through / visibility, and /sm widget commands.
-- Graph data: one snapshot per tick per session, pushed opaquely into each
-- widget's GraphRenderer (fixed time window = samples x interval; oldest
-- column drops off). DEMO (/sm test) drives widgets with readable fake data
-- and is cleared when it starts/stops so it never mixes with real samples.

local _, ns = ...
local WM = {}
ns.WidgetManager = WM

local TICK = 0.25
local frames = {}
local editAll = false
local inCombat = false

local function DB() return ns.db.widgets end
local function WS() return ns.WidgetSchema end
local function Rec(id) return DB().byId[id] end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function MakeEdges(parent, layer)
    local e = {}
    for i = 1, 4 do e[i] = parent:CreateTexture(nil, layer) end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT")
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT")
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT")
    return e
end

local function StyleEdges(e, size, c, shown)
    e[1]:SetHeight(size); e[2]:SetHeight(size)
    e[3]:SetWidth(size); e[4]:SetWidth(size)
    for i = 1, 4 do
        e[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        e[i]:SetShown(shown)
    end
end

local function ApplyFont(fs, key, size, c)
    fs:SetFont(ns.Theme.FontPath(key), size, "")
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function IsLocked(w) return w.behavior.locked and not editAll end

local function ShouldShow(w)
    if editAll then return true end
    local v = w.behavior.visibility
    if v == "hidden" then return false end
    if v == "combat" then return inCombat end
    if v == "nocombat" then return not inCombat end
    return true
end

-- Returns max, min (both readable).
local function EffectiveRange(w)
    local g = w.graph
    if g.scaleMode == "fixed" then return g.scaleMax, 0 end
    if g.scaleMode == "focus" and g.autoBase then return g.autoBase * 1.5, g.autoBase * 0.5 end
    return g.autoMax or g.scaleMax, 0
end

local function MetricLabel(w)
    return WS().Label(w)
end

-- v may be secret: native formatting only.
local function SetValueText(f, w, v)
    if type(v) ~= "number" then
        f.value:SetText("-")
    elseif w.data.metric == "share" then
        f.value:SetFormattedText("%.0f%%", v)
    elseif w.data.metric == "damage" then
        f.value:SetText(AbbreviateNumbers(v))
    else
        f.value:SetFormattedText("%.1f", v)
    end
end

---------------------------------------------------------------------------
-- Per-fight provider (readable, out of combat only)
---------------------------------------------------------------------------
local function FightValue(w, sessionId, newest)
    local d = w.data
    if d.spellID then
        local s = ns.API.SessionSpell(sessionId, d.spellID, newest)
        if not s then return nil end
        if d.metric == "share" then
            return (s.sourceTotal > 0) and (s.total / s.sourceTotal * 100) or 0
        end
        return (d.metric == "dps") and s.dps or s.total
    end
    local p = ns.API.SessionPlayer(sessionId, newest)
    if not p then return nil end
    return (d.metric == "dps") and p.dps or p.total
end

-- Rebuilds a per-fight widget from the last N completed fights.
local function RefreshFights(id)
    local w, f = Rec(id), frames[id]
    if not (w and f) then return false, "widget not found" end
    if w.data.kind ~= "fights" then return false, "not a per-fight widget" end
    if InCombatLockdown() then return false, "in combat (updates after the fight)" end
    local list = ns.API.SessionList()
    if not list then return false, "fight list not available" end
    local n = math.min(w.graph.samples, #list, WS().MAX_FIGHTS)
    local values = {}
    for i = #list - n + 1, #list do
        local v = FightValue(w, list[i].id, i == #list)
        if v == nil then -- something unreadable: keep the previous graph
            return false, ("fight %s not readable yet"):format(tostring(list[i].id))
        end
        values[#values + 1] = v
    end
    -- exact scale: these are readable values
    local hi, lo = 0, math.huge
    for _, v in ipairs(values) do
        if v > hi then hi = v end
        if v < lo then lo = v end
    end
    if #values == 0 then lo = 0 end
    local max, min
    local g = w.graph
    if g.scaleMode == "fixed" then
        max, min = g.scaleMax, 0
    elseif g.scaleMode == "focus" and hi > lo then
        local pad = (hi - lo) * 0.1
        max, min = hi + pad, math.max(0, lo - pad)
    else
        max, min = math.max(hi * 1.1, 1), 0
    end
    f.renderer:SetSeries(values, max, min)
    SetValueText(f, w, values[#values])
    return true, ("%d fights, newest #%s"):format(#values, tostring(list[#list] and list[#list].id))
end
WM.RefreshFights = RefreshFights

local function RefreshAllFights()
    for _, id in ipairs(ns.db.widgets.order) do RefreshFights(id) end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function SavePosition(f)
    local w = Rec(f.id)
    if not w then return end
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then
        w.position.x, w.position.y = left, top
    end
    w.position.width = math.floor(f:GetWidth() + 0.5)
    w.position.height = math.floor(f:GetHeight() + 0.5)
end

local function ApplyMouse(f, w)
    local locked = IsLocked(w)
    f:EnableMouse(not (locked and w.behavior.clickThrough))
    f.grip:SetShown(not locked)
    for i = 1, 4 do f.overlay[i]:SetShown(not locked) end
    f.overlayLabel:SetShown(not locked)
end

local function CreateFrameFor(id)
    local f = CreateFrame("Frame", nil, UIParent)
    f.id = id
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(120, 60, 900, 500)
    elseif f.SetMinResize then
        f:SetMinResize(120, 60)
        f:SetMaxResize(900, 500)
    end
    f:SetFrameStrata("MEDIUM")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not IsLocked(Rec(self.id)) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        SavePosition(self)
    end)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.border = MakeEdges(f, "BORDER")
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.value = f:CreateFontString(nil, "OVERLAY")
    f.value:SetJustifyH("RIGHT")

    f.renderer = ns.GraphRenderer.New(f)

    f.overlay = MakeEdges(f, "OVERLAY")
    StyleEdges(f.overlay, 1, { 0.31, 0.76, 0.97, 0.7 }, false)
    f.overlayLabel = f:CreateFontString(nil, "OVERLAY")
    f.overlayLabel:SetFont(STANDARD_TEXT_FONT, 10, "")
    f.overlayLabel:SetTextColor(0.31, 0.76, 0.97, 1)
    f.overlayLabel:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)

    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(14, 14)
    f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SavePosition(f)
        f.renderer:Layout()
    end)

    f:SetScript("OnSizeChanged", function(self) self.renderer:Layout() end)
    frames[id] = f
    return f
end

-- Applies every setting of the record to its frame.
function WM.Apply(id)
    local w = Rec(id)
    if not w then return end
    local f = frames[id] or CreateFrameFor(id)
    w.data = WS().ValidateData(w.data) -- keep kind/metric/spell consistent after edits
    local get = function(p) return WS().Get(w, p) end
    local pos = w.position

    f:SetScale(pos.scale)
    f:SetSize(pos.width, pos.height)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)

    local c = get("bg.color")
    f.bg:SetTexture(ns.Theme.TexturePath(get("bg.texture")))
    f.bg:SetVertexColor(c[1], c[2], c[3], c[4])
    f.bg:SetShown(get("bg.enabled"))
    StyleEdges(f.border, get("border.size"), get("border.color"), get("border.enabled"))

    local pad = get("padding")
    ApplyFont(f.title, get("title.font"), get("title.size"), get("title.color"))
    ApplyFont(f.value, get("value.font"), get("value.size"), get("value.color"))
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", pad, -pad)
    f.title:SetPoint("RIGHT", f.value, "LEFT", -6, 0)
    f.value:ClearAllPoints()
    f.value:SetPoint("TOPRIGHT", -pad, -pad)
    f.title:SetShown(get("title.enabled"))
    f.value:SetShown(get("value.enabled"))
    WM.UpdateTitle(id)

    f.overlayLabel:SetText(("%s [%s] - drag to move, corner to resize"):format(w.name, w.id))
    f.renderer:ApplyStyle(w)
    if w.data.kind == "fights" then
        RefreshFights(id)
    else
        f.renderer:SetScale(EffectiveRange(w))
    end
    ApplyMouse(f, w)
    f:SetShown(ShouldShow(w))
    -- keep open settings UIs in sync (they only refresh, never re-apply)
    if ns.WidgetWindow then ns.WidgetWindow.Refresh(id) end
    if ns.Config and ns.Config.RefreshWidgets then ns.Config.RefreshWidgets(false) end
end

function WM.UpdateTitle(id)
    local w, f = Rec(id), frames[id]
    if not (w and f) then return end
    local demo = ns.Demo.IsActive() and w.data.kind == "live"
    f.title:SetText(w.name .. (demo and "  |cffff9900DEMO|r" or ""))
end

local function ApplyAll()
    for _, id in ipairs(DB().order) do WM.Apply(id) end
end
WM.ApplyAll = ApplyAll

local function UpdateVisibility()
    for _, id in ipairs(DB().order) do
        local w, f = Rec(id), frames[id]
        if w and f then f:SetShown(ShouldShow(w)) end
    end
end

---------------------------------------------------------------------------
-- Sampling (one shared ticker)
---------------------------------------------------------------------------
local function Tick()
    local demo = ns.Demo.IsRunning()
    if not inCombat and not demo then return end
    local snaps = {}
    for _, id in ipairs(DB().order) do
        local w, f = Rec(id), frames[id]
        if w and f and f:IsShown() and w.data.kind == "live" then
            f.acc = (f.acc or 0) + TICK
            if f.acc >= w.graph.interval - 0.01 then
                f.acc = 0
                local key = demo and "demo" or w.data.session
                local snap = snaps[key]
                if not snap then
                    snap = demo and ns.Demo.Snapshot() or ns.API.Snapshot(w.data.session)
                    snaps[key] = snap
                end
                local v = (w.data.metric == "damage") and snap.total or snap.dps
                if type(v) == "number" then
                    f.renderer:Push(v)
                    SetValueText(f, w, v)
                end
            end
        end
    end
end

local function ResetWidgets(filter)
    for _, id in ipairs(DB().order) do
        local w, f = Rec(id), frames[id]
        if w and f and (not filter or filter(w)) then
            f.renderer:Reset()
            f.renderer:SetScale(EffectiveRange(w))
            f.value:SetText("-")
            f.acc = 0
        end
    end
end

-- After combat (values readable): auto scale from this fight's final value.
local function UpdateAutoScale()
    for _, id in ipairs(DB().order) do
        local w, f = Rec(id), frames[id]
        if w and f and w.data.kind == "live" then
            local snap = ns.API.Snapshot(w.data.session)
            local v = (w.data.metric == "damage") and snap.total or snap.dps
            v = ns.SecretSafety.Readable(v)
            if type(v) == "number" and v > 0 then
                local headroom = (w.data.metric == "damage") and 1.1 or 1.5
                w.graph.autoMax = v * headroom
                w.graph.autoBase = v
                if w.graph.scaleMode ~= "fixed" then f.renderer:SetScale(EffectiveRange(w)) end
                SetValueText(f, w, v)
            end
        end
    end
end

-- Called by Demo when a DEMO fight starts or is cleared.
function WM.OnDemoChanged()
    ResetWidgets(function(w) return w.data.kind == "live" end) -- per-fight widgets show real fights only
    for _, id in ipairs(DB().order) do WM.UpdateTitle(id) end
end

---------------------------------------------------------------------------
-- Management
---------------------------------------------------------------------------
local function Count() return #DB().order end

local function NewId()
    local db = DB()
    local id = "w" .. db.nextId
    db.nextId = db.nextId + 1
    return id
end

local function DefaultPosition()
    local m = _G.SoloMetricsMeter
    local x, y = 300, 500
    if m and m:GetLeft() then
        x = m:GetRight() + 12
        y = m:GetTop()
    end
    local n = Count()
    return { x = x + (n % 4) * 16, y = y - (n % 4) * 16 }
end

function WM.Create(opts)
    if InCombatLockdown() then return nil, "Widgets can't be created during combat." end
    if Count() >= WS().MAX_WIDGETS then
        return nil, ("Widget limit reached (%d)."):format(WS().MAX_WIDGETS)
    end
    opts = opts or {}
    opts.position = opts.position or DefaultPosition()
    local id = NewId()
    local w = WS().NewWidget(id, opts)
    w.behavior.locked = false -- new widgets start unlocked so they can be placed
    DB().byId[id] = w
    table.insert(DB().order, id)
    WM.Apply(id)
    if ns.Config and ns.Config.RefreshWidgets then ns.Config.RefreshWidgets(true) end
    return id
end

function WM.Duplicate(id)
    local src = Rec(id)
    if not src then return nil, "No widget " .. tostring(id) end
    if Count() >= WS().MAX_WIDGETS then
        return nil, ("Widget limit reached (%d)."):format(WS().MAX_WIDGETS)
    end
    local nid = NewId()
    local copy = ns.Theme.DeepCopy(src)
    copy.name = (src.name .. " copy"):sub(1, 32)
    copy.position.x = src.position.x + 20
    copy.position.y = src.position.y - 20
    copy.behavior.locked = false
    local w = WS().ValidateWidget(copy, nid)
    DB().byId[nid] = w
    table.insert(DB().order, nid)
    WM.Apply(nid)
    if ns.Config and ns.Config.RefreshWidgets then ns.Config.RefreshWidgets(true) end
    return nid
end

function WM.Delete(id)
    if not Rec(id) then return false end
    DB().byId[id] = nil
    for i, v in ipairs(DB().order) do
        if v == id then table.remove(DB().order, i) break end
    end
    local f = frames[id]
    if f then
        f:Hide()
        f:SetScript("OnUpdate", nil)
        frames[id] = nil -- WoW frames can't be destroyed; it stays hidden
    end
    if ns.WidgetWindow then ns.WidgetWindow.Close(id) end
    if ns.Config and ns.Config.RefreshWidgets then ns.Config.RefreshWidgets(true) end
    return true
end

-- Clears a widget's samples (after its metric/session changed).
function WM.ResetGraph(id)
    ResetWidgets(function(x) return x.id == id end)
end

function WM.ResetPosition(id)
    local w = Rec(id)
    if not w then return end
    local p = DefaultPosition()
    w.position.x, w.position.y = p.x, p.y
    WM.Apply(id)
end

function WM.SetEditAll(on)
    editAll = on and true or false
    for _, id in ipairs(DB().order) do
        local w, f = Rec(id), frames[id]
        if w and f then
            ApplyMouse(f, w)
            f:SetShown(ShouldShow(w))
        end
    end
end

function WM.IsEditAll() return editAll end
function WM.List() return DB().order end
function WM.Get(id) return Rec(id) end

---------------------------------------------------------------------------
-- /sm widget ...
---------------------------------------------------------------------------
local function Resolve(token)
    if not token then return nil end
    token = token:lower()
    if Rec(token) then return token end
    if tonumber(token) and Rec("w" .. token) then return "w" .. token end
    return nil
end

local HELP = {
    "/sm widget new [live|fights] [dps|damage] [current|overall] [area|bars|line|points]",
    "/sm widget list | edit (unlock/lock all)",
    "/sm widget <id> dup | delete | reset | lock | unlock | clickthrough",
    "/sm widget <id> name <text> | style <area|bars|line|points>",
    "/sm widget <id> metric <dps|damage> | session <current|overall>",
    "/sm widget <id> show <always|combat|nocombat|hidden>",
    "/sm widget <id> window <samples 10-60> [interval 0.5-5]",
    "/sm widget <id> scale <auto|focus|number> | size <scale 0.5-2>",
    "/sm widget <id> set <path> <value> | clear <path|all> | paths",
    "/sm widget <id> copyto <id> | makedefault | refresh (per-fight widgets)",
}

function WM.Command(rest)
    local args = {}
    for word in (rest or ""):gmatch("%S+") do args[#args + 1] = word end
    local sub = (args[1] or ""):lower()

    if sub == "" or sub == "help" then
        ns.Print("Widgets (graphs). Commands:")
        for _, l in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
        return
    end
    if sub == "list" then
        if Count() == 0 then ns.Print("No widgets. /sm widget new") return end
        ns.Print(("Widgets (%d/%d):"):format(Count(), WS().MAX_WIDGETS))
        for _, id in ipairs(DB().order) do
            local w = Rec(id)
            DEFAULT_CHAT_FRAME:AddMessage(("  %s  %s - %s, %s, %s%s"):format(id, w.name, MetricLabel(w),
                WS().STYLES[w.graph.style], WS().VISIBILITY[w.behavior.visibility],
                w.behavior.locked and ", locked" or ""))
        end
        return
    end
    if sub == "edit" then
        WM.SetEditAll(not editAll)
        ns.Print(editAll and "All widgets unlocked and shown: drag to move, corner to resize. /sm widget edit again to lock."
            or "Widgets back to their own lock/visibility settings.")
        return
    end
    if sub == "new" then
        local opts = {}
        for i = 2, #args do
            local a = args[i]:lower()
            if WS().METRICS[a] or WS().FIGHT_METRICS[a] then opts.metric = a
            elseif a == "fights" or a == "live" then opts.kind = a
            elseif a == "current" or a == "overall" then opts.session = a
            elseif WS().STYLES[a] then opts.style = a end
        end
        local id, err = WM.Create(opts)
        if not id then ns.Print(err) return end
        ns.Print(("Created %s (%s). It's unlocked: drag to place, corner to resize, then /sm widget %s lock."):format(
            id, MetricLabel(Rec(id)), id))
        return
    end

    local id = Resolve(args[1])
    if not id then ns.Print("Unknown widget '" .. tostring(args[1]) .. "'. /sm widget list") return end
    local w = Rec(id)
    local cmd = (args[2] or ""):lower()
    local val = args[3] and args[3]:lower()

    if cmd == "dup" then
        local nid, err = WM.Duplicate(id)
        ns.Print(nid and ("Duplicated " .. id .. " as " .. nid) or err)
    elseif cmd == "delete" then
        ns.ConfigWidgets.Dialog({
            title = "Delete widget",
            message = ("Delete widget '%s' (%s)? Other widgets are not affected."):format(w.name, id),
            noInput = true, okLabel = "Delete",
            onOK = function() WM.Delete(id) ns.Print("Deleted " .. id) return true end,
        })
    elseif cmd == "reset" then
        local p = DefaultPosition()
        w.position.x, w.position.y = p.x, p.y
        WM.Apply(id)
    elseif cmd == "lock" or cmd == "unlock" then
        w.behavior.locked = (cmd == "lock")
        WM.Apply(id)
        ns.Print(id .. (w.behavior.locked and " locked." or " unlocked."))
    elseif cmd == "clickthrough" then
        w.behavior.clickThrough = not w.behavior.clickThrough
        WM.Apply(id)
        ns.Print(id .. " click-through " .. (w.behavior.clickThrough and "ON (when locked)" or "OFF"))
    elseif cmd == "name" then
        local name = table.concat(args, " ", 3)
        name = strtrim(name)
        if name == "" or #name > 32 then ns.Print("Name must be 1-32 characters.") return end
        w.name = name
        WM.Apply(id)
    elseif cmd == "style" and val and WS().STYLES[val] then
        w.graph.style = val
        WM.Apply(id)
    elseif cmd == "metric" and val and WS().METRICS[val] then
        w.data.metric = val
        w.graph.autoMax = nil
        ResetWidgets(function(x) return x.id == id end)
        WM.Apply(id)
    elseif cmd == "session" and (val == "current" or val == "overall") then
        w.data.session = val
        w.graph.autoMax = nil
        ResetWidgets(function(x) return x.id == id end)
        WM.Apply(id)
    elseif cmd == "show" and val and WS().VISIBILITY[val] then
        w.behavior.visibility = val
        WM.Apply(id)
    elseif cmd == "window" and tonumber(args[3]) then
        w.graph.samples = math.floor(math.max(10, math.min(WS().MAX_SAMPLES, tonumber(args[3]))))
        if tonumber(args[4]) then w.graph.interval = math.max(0.5, math.min(5, tonumber(args[4]))) end
        WM.Apply(id)
        ns.Print(("%s window: %d samples x %.1fs = %ds"):format(id, w.graph.samples, w.graph.interval,
            math.floor(w.graph.samples * w.graph.interval)))
    elseif cmd == "scale" and val then
        if val == "auto" or val == "focus" then
            w.graph.scaleMode = val
            if val == "focus" and not w.graph.autoBase then
                ns.Print("Focus range applies after the next completed fight (it needs that fight's readable result).")
            end
        elseif tonumber(val) and tonumber(val) > 0 then
            w.graph.scaleMode = "fixed"
            w.graph.scaleMax = tonumber(val)
        else
            ns.Print("Usage: /sm widget " .. id .. " scale <auto|number>") return
        end
        WM.Apply(id)
    elseif cmd == "size" and tonumber(val) then
        w.position.scale = math.max(0.5, math.min(2, tonumber(val)))
        WM.Apply(id)
    elseif cmd == "paths" then
        ns.Print(id .. " appearance settings (override / effective):")
        for _, e in ipairs(WS().APPEARANCE_SCHEMA) do
            local o = w.appearance[e[1]]
            DEFAULT_CHAT_FRAME:AddMessage(("  %s = %s%s"):format(e[1],
                ns.Theme.FormatValue(e, WS().Get(w, e[1])), o ~= nil and "  (custom)" or ""))
        end
    elseif cmd == "set" and args[3] and args[4] then
        local path = args[3]
        local e = WS().APPEARANCE_BY_PATH[path]
        if not e then ns.Print("Unknown setting. /sm widget " .. id .. " paths") return end
        -- reuse Theme parsing for the value types
        local v
        local text = table.concat(args, " ", 4)
        if e[2] == "number" then v = tonumber(text)
        elseif e[2] == "bool" then
            local l = text:lower()
            if l == "on" or l == "true" or l == "1" then v = true elseif l == "off" or l == "false" or l == "0" then v = false end
        elseif e[2] == "color" then
            local s = text:gsub("^#", "")
            if (#s == 6 or #s == 8) and not s:find("[^%x]") then
                v = { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255,
                      tonumber(s:sub(5, 6), 16) / 255, #s == 8 and tonumber(s:sub(7, 8), 16) / 255 or 1 }
            end
        else
            v = text:lower()
        end
        if v == nil or not WS().IsValidAppearance(path, v) then ns.Print("Invalid value for " .. path) return end
        w.appearance[path] = v
        WM.Apply(id)
    elseif cmd == "clear" and args[3] then
        if args[3]:lower() == "all" then w.appearance = {} else w.appearance[args[3]] = nil end
        WM.Apply(id)
    elseif cmd == "copyto" and Resolve(args[3]) then
        local t = Rec(Resolve(args[3]))
        t.appearance = ns.Theme.DeepCopy(w.appearance)
        WM.Apply(t.id)
        ns.Print("Copied appearance of " .. id .. " to " .. t.id)
    elseif cmd == "refresh" then
        local ok, info = RefreshFights(id)
        ns.Print(("%s refresh: %s (%s)"):format(id, ok and "updated" or "not updated", tostring(info)))
    elseif cmd == "makedefault" then
        DB().defaults.appearance = ns.Theme.DeepCopy(w.appearance)
        ApplyAll()
        ns.Print("Appearance of " .. id .. " is now the default for widgets without their own overrides.")
    else
        ns.Print("Unknown widget command. /sm widget help")
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function WM.Init()
    inCombat = InCombatLockdown() and true or false
    ApplyAll()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            ResetWidgets(function(w) return w.data.kind == "live" and w.data.session == "current" end)
        else
            inCombat = false
            C_Timer.After(0.3, UpdateAutoScale)
            -- the finished fight may join the session list a little later: retry
            C_Timer.After(0.6, RefreshAllFights)
            C_Timer.After(2.5, RefreshAllFights)
            C_Timer.After(6, RefreshAllFights)
        end
        UpdateVisibility()
    end)
    C_Timer.NewTicker(TICK, Tick)

    -- Blizzard meter reset clears every session: drop cached per-fight data.
    local resetEv = CreateFrame("Frame")
    pcall(resetEv.RegisterEvent, resetEv, "DAMAGE_METER_RESET")
    pcall(resetEv.RegisterEvent, resetEv, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
    local pending = false
    resetEv:SetScript("OnEvent", function(_, event)
        if event == "DAMAGE_METER_RESET" then
            ns.API.ClearCache()
            C_Timer.After(0.5, RefreshAllFights)
        elseif not InCombatLockdown() and not pending then
            -- session data changed out of combat: refresh once, debounced
            pending = true
            C_Timer.After(1, function()
                pending = false
                RefreshAllFights()
            end)
        end
    end)
    C_Timer.After(1, RefreshAllFights)
end
