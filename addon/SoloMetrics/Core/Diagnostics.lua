-- SoloMetrics: Diagnostics (M1 feasibility tools)
--   /sm debug  - client build, C_DamageMeter presence, enums, session list
--   /sm probe  - full shape dump of current/last session, sources and the
--                player's spell rows (values only out of combat)
--   /sm watch  - toggle: around each fight, report which fields are secret
--                (S) or readable (R), plus DAMAGE_METER_* event counts
--   /sm copy   - copyable window with the last report
--
-- Secret-value rules: secret values are never printed, compared, converted,
-- stored or used in arithmetic. Only type() and issecretvalue() are applied
-- to them. In combat, even readable values are not printed (types only).
-- GUIDs and the player's own name are redacted. pcall is used only to
-- survive missing or changed APIs.

local _, ns = ...
local D = {}
ns.Diagnostics = D

local MAX_LINES = 200
local MAX_ARRAY = 3
local MAX_DEPTH = 4

local DM_FUNCS = {
    "IsDamageMeterAvailable",
    "GetAvailableCombatSessions",
    "GetCombatSessionFromID",
    "GetCombatSessionFromType",
    "GetCombatSessionSourceFromID",
    "GetCombatSessionSourceFromType",
    "GetSessionDurationSeconds",
    "ResetAllCombatSessions", -- SM-ALLOW-RESET: presence check only, never called
}

local DM_EVENTS = {
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    if issecretvalue then
        return issecretvalue(v) and true or false
    end
    return false
end

local function KeyLabel(k)
    if IsSecret(k) then return "<secret key>" end
    return tostring(k)
end

local function SortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return KeyLabel(a) < KeyLabel(b) end)
    return keys
end

local function InCombat()
    return InCombatLockdown() and true or false
end

-- Readable scalar -> printable text, with privacy redaction by key name.
local function DescribeScalar(key, v, inCombat)
    if IsSecret(v) then return "<secret>" end
    local t = type(v)
    if inCombat then return "<" .. t .. ">" end
    if t == "string" then
        local k = type(key) == "string" and key:lower() or ""
        if k:find("guid", 1, true) then
            return (v == UnitGUID("player")) and "<guid:player>" or "<guid:other>"
        end
        if v == UnitName("player") then return "<player name>" end
        return "string:" .. v
    end
    if t == "nil" or t == "boolean" or t == "number" then
        return t .. ":" .. tostring(v)
    end
    return "<" .. t .. ">"
end

local function NewReport(title)
    local r = { title = title, lines = {} }
    function r.out(s)
        local n = #r.lines
        if n < MAX_LINES then
            r.lines[n + 1] = s
        elseif n == MAX_LINES then
            r.lines[n + 1] = "(output capped)"
        end
    end
    function r.finish(toChat)
        local buf = { "SoloMetrics " .. ns.VERSION .. " - " .. r.title }
        for _, s in ipairs(r.lines) do buf[#buf + 1] = s end
        ns.lastReport = buf
        if toChat then
            ns.Print("---- " .. r.title .. " ----")
            for _, s in ipairs(r.lines) do
                DEFAULT_CHAT_FRAME:AddMessage("  " .. s)
            end
            ns.Print("---- end (type /sm copy to copy) ----")
        end
    end
    return r
end

-- Recursive shape dump. Arrays show the first MAX_ARRAY elements.
local function Dump(out, label, v, depth, inCombat, key)
    if IsSecret(v) then
        out(label .. " = <secret>")
        return
    end
    if type(v) ~= "table" then
        out(label .. " = " .. DescribeScalar(key, v, inCombat))
        return
    end
    local keys = SortedKeys(v)
    local n = #v
    if depth <= 0 then
        out(("%s = <table: %d keys, #%d>"):format(label, #keys, n))
        return
    end
    out(("%s = {table: %d keys, #%d}"):format(label, #keys, n))
    for _, k in ipairs(keys) do
        local isIndex = type(k) == "number" and k >= 1 and k <= n and k % 1 == 0
        if isIndex then
            if k <= MAX_ARRAY then
                Dump(out, label .. "[" .. k .. "]", v[k], depth - 1, inCombat, nil)
            end
        else
            Dump(out, label .. "." .. KeyLabel(k), v[k], depth - 1, inCombat, k)
        end
    end
    if n > MAX_ARRAY then
        out(("%s[%d..%d] (not shown)"):format(label, MAX_ARRAY + 1, n))
    end
end

-- One-line R/S/T flags for every field of a table (never prints values).
local function Flags(tbl)
    local parts = {}
    for _, k in ipairs(SortedKeys(tbl)) do
        local v = tbl[k]
        local f
        if IsSecret(v) then
            f = "S"
        elseif type(v) == "table" then
            f = "T#" .. #v
        else
            f = "R"
        end
        parts[#parts + 1] = KeyLabel(k) .. "=" .. f
    end
    return table.concat(parts, " ")
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false, "missing" end
    return pcall(fn, ...)
end

local function MeterEnums()
    local mt = Enum and Enum.DamageMeterType
    local st = Enum and Enum.DamageMeterSessionType
    if type(mt) ~= "table" or type(st) ~= "table" then return nil end
    return mt, st
end

---------------------------------------------------------------------------
-- /sm debug
---------------------------------------------------------------------------
function D.Run()
    local r = NewReport("debug report")
    local out = r.out

    local version, build, date, toc = GetBuildInfo()
    out(("Client: version %s, build %s, date %s, interface %s"):format(
        tostring(version), tostring(build), tostring(date), tostring(toc)))
    out(("Addon: v%s, SV schema %d, load #%d"):format(ns.VERSION, ns.db.schema, ns.db.loadCount))
    out("issecretvalue: " .. type(issecretvalue))

    local inCombat = InCombat()
    out("In combat: " .. tostring(inCombat))

    local dm = C_DamageMeter
    if type(dm) ~= "table" then
        out("C_DamageMeter: MISSING")
        r.finish(true)
        return
    end
    out("C_DamageMeter functions:")
    for _, name in ipairs(DM_FUNCS) do
        out(("  %s: %s"):format(name, type(dm[name])))
    end

    if type(Enum) == "table" then
        for _, enumName in ipairs(SortedKeys(Enum)) do
            if type(enumName) == "string" and enumName:find("DamageMeter", 1, true)
                and not enumName:find("Meta", 1, true) then
                local e = Enum[enumName]
                if type(e) == "table" then
                    local parts = {}
                    for _, k in ipairs(SortedKeys(e)) do
                        parts[#parts + 1] = KeyLabel(k) .. "=" .. tostring(e[k])
                    end
                    out("Enum." .. enumName .. ": " .. table.concat(parts, ", "))
                end
            end
        end
    end

    if inCombat then
        out("Session queries skipped: in combat.")
        r.finish(true)
        return
    end

    local ok, a, b = SafeCall(dm.IsDamageMeterAvailable)
    out(("IsDamageMeterAvailable() -> %s, %s"):format(
        ok and DescribeScalar(nil, a) or "error", ok and DescribeScalar(nil, b) or tostring(a)))

    local ok2, sessions = SafeCall(dm.GetAvailableCombatSessions)
    if ok2 and type(sessions) == "table" and not IsSecret(sessions) then
        local n = #sessions
        out(("GetAvailableCombatSessions() -> #%d (showing last 3)"):format(n))
        for i = math.max(1, n - 2), n do
            Dump(out, "  [" .. i .. "]", sessions[i], 1, false, nil)
        end
    else
        out("GetAvailableCombatSessions() -> " .. (ok2 and DescribeScalar(nil, sessions) or ("error " .. tostring(sessions))))
    end

    r.finish(true)
end

---------------------------------------------------------------------------
-- /sm probe [dps] [sessionID]
---------------------------------------------------------------------------
function D.Probe(args)
    local dm = C_DamageMeter
    local MT, ST = MeterEnums()
    if type(dm) ~= "table" or not MT then
        ns.Print("C_DamageMeter or its enums are missing.")
        return
    end

    local meterName, meterType = "DamageDone", MT.DamageDone
    local wantID
    for word in (args or ""):gmatch("%S+") do
        if word == "dps" then
            meterName, meterType = "Dps", MT.Dps
        elseif tonumber(word) then
            wantID = tonumber(word)
        end
    end

    local inCombat = InCombat()
    local r = NewReport("probe (" .. meterName .. (inCombat and ", IN COMBAT: types only" or "") .. ")")
    local out = r.out
    local guid = UnitGUID("player")
    out("player GUID available: " .. tostring(type(guid) == "string"))

    -- Durations by session type
    for _, stName in ipairs({ "Current", "Overall" }) do
        local ok, d = SafeCall(dm.GetSessionDurationSeconds, ST[stName])
        out(("GetSessionDurationSeconds(%s) -> %s"):format(stName,
            ok and DescribeScalar(nil, d, inCombat) or ("error " .. tostring(d))))
    end

    -- Current session (type-based)
    local ok, s = SafeCall(dm.GetCombatSessionFromType, ST.Current, meterType)
    if ok then
        Dump(out, "FromType(Current)", s, MAX_DEPTH, inCombat, nil)
    else
        out("GetCombatSessionFromType(Current) error: " .. tostring(s))
    end

    -- Player's source in current session
    ok, s = SafeCall(dm.GetCombatSessionSourceFromType, ST.Current, meterType, guid)
    if ok then
        Dump(out, "SourceFromType(Current, player)", s, MAX_DEPTH, inCombat, nil)
    else
        out("GetCombatSessionSourceFromType(Current, player) error: " .. tostring(s))
    end

    -- Last completed session by ID (out of combat only: needs a readable ID)
    if not inCombat then
        local id = wantID
        if not id then
            local okS, sessions = SafeCall(dm.GetAvailableCombatSessions)
            if okS and type(sessions) == "table" and #sessions > 0 then
                local last = sessions[#sessions]
                if type(last) == "table" and not IsSecret(last.sessionID) then
                    id = last.sessionID
                end
            end
        end
        if id then
            out("Using sessionID " .. tostring(id))
            ok, s = SafeCall(dm.GetCombatSessionFromID, id, meterType)
            if ok then
                Dump(out, "FromID(" .. id .. ")", s, MAX_DEPTH, false, nil)
            else
                out("GetCombatSessionFromID error: " .. tostring(s))
            end
            ok, s = SafeCall(dm.GetCombatSessionSourceFromID, id, meterType, guid)
            if ok then
                Dump(out, "SourceFromID(" .. id .. ", player)", s, MAX_DEPTH, false, nil)
            else
                out("GetCombatSessionSourceFromID error: " .. tostring(s))
            end
        else
            out("No readable sessionID found.")
        end
    end

    r.finish(true)
end

---------------------------------------------------------------------------
-- /sm watch: secret-status timeline around combat + event counts
---------------------------------------------------------------------------
local watch = { enabled = false, counts = {}, firstPayload = {}, report = nil }
local watchFrame = CreateFrame("Frame")

local function FlagsCheck(tag)
    local dm = C_DamageMeter
    local MT, ST = MeterEnums()
    if not MT then return end
    local r = watch.report
    if not r then return end
    local out = r.out
    local guid = UnitGUID("player")
    local inCombat = InCombat()
    out(("[%s] inCombat=%s"):format(tag, tostring(inCombat)))

    local ok, d = SafeCall(dm.GetSessionDurationSeconds, ST.Current)
    out("  duration(Current): " .. (ok and (IsSecret(d) and "S" or ("R " .. type(d))) or "error"))

    local function show(name, okCall, tbl)
        if not okCall then
            out("  " .. name .. ": error " .. tostring(tbl))
        elseif IsSecret(tbl) then
            out("  " .. name .. ": S")
        elseif type(tbl) ~= "table" then
            out("  " .. name .. ": " .. type(tbl))
        else
            out("  " .. name .. ": " .. Flags(tbl))
            for _, k in ipairs(SortedKeys(tbl)) do
                local child = tbl[k]
                if not IsSecret(child) and type(child) == "table" and #child > 0 then
                    local first = child[1]
                    if type(first) == "table" and not IsSecret(first) then
                        out("    ." .. KeyLabel(k) .. "[1]: " .. Flags(first))
                    end
                end
            end
        end
    end

    show("session", SafeCall(dm.GetCombatSessionFromType, ST.Current, MT.DamageDone))
    show("playerSource", SafeCall(dm.GetCombatSessionSourceFromType, ST.Current, MT.DamageDone, guid))
end

local function FinishWatchReport()
    local r = watch.report
    if not r then return end
    r.out("DAMAGE_METER_* events since combat start:")
    for _, ev in ipairs(DM_EVENTS) do
        r.out(("  %s x%d  first payload: %s"):format(ev, watch.counts[ev] or 0, watch.firstPayload[ev] or "-"))
    end
    r.finish(true)
    watch.report = nil
end

local function DescribePayload(...)
    local n = select("#", ...)
    if n == 0 then return "(none)" end
    local parts = {}
    for i = 1, math.min(n, 4) do
        local v = select(i, ...)
        parts[#parts + 1] = IsSecret(v) and "S" or (type(v) .. "(R)")
    end
    return table.concat(parts, ", ")
end

watchFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        watch.counts = {}
        watch.firstPayload = {}
        watch.report = NewReport("watch: field status around fight (S=secret, R=readable, T#n=table)")
        FlagsCheck("combat start")
        C_Timer.After(3, function()
            if watch.report and InCombat() then FlagsCheck("combat +3s") end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not watch.report then return end
        FlagsCheck("combat end +0s")
        C_Timer.After(0.5, function() FlagsCheck("combat end +0.5s") end)
        C_Timer.After(2, function() FlagsCheck("combat end +2s") end)
        C_Timer.After(5, function()
            FlagsCheck("combat end +5s")
            FinishWatchReport()
        end)
    else
        watch.counts[event] = (watch.counts[event] or 0) + 1
        if not watch.firstPayload[event] then
            watch.firstPayload[event] = DescribePayload(...)
        end
    end
end)

function D.ToggleWatch()
    watch.enabled = not watch.enabled
    if watch.enabled then
        watchFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        watchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        for _, ev in ipairs(DM_EVENTS) do
            pcall(watchFrame.RegisterEvent, watchFrame, ev)
        end
        ns.Print("Watch ON: start a fight; a report prints ~5s after combat ends.")
    else
        watchFrame:UnregisterAllEvents()
        watch.report = nil
        ns.Print("Watch OFF.")
    end
end

---------------------------------------------------------------------------
-- /sm copy: copyable text window
---------------------------------------------------------------------------
local copyFrame

local function CreateCopyFrame()
    local f = CreateFrame("Frame", "SoloMetricsCopyFrame", UIParent)
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("SoloMetrics report - Ctrl+A, Ctrl+C to copy")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    f.edit = edit
    f:Hide()
    return f
end

function D.ShowCopy()
    if not ns.lastReport then
        ns.Print("No report yet. Run /sm debug, /sm probe, or wait for a /sm watch report.")
        return
    end
    copyFrame = copyFrame or CreateCopyFrame()
    copyFrame.edit:SetText(table.concat(ns.lastReport, "\n"))
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end
