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
    local interp = Enum and Enum.StatusBarInterpolation
    if type(interp) == "table" then
        local parts = {}
        for _, k in ipairs(SortedKeys(interp)) do parts[#parts + 1] = KeyLabel(k) .. "=" .. tostring(interp[k]) end
        out("Enum.StatusBarInterpolation: " .. table.concat(parts, ", "))
    else
        out("Enum.StatusBarInterpolation: MISSING")
    end
    out("Bar smoothing active: " .. tostring(ns.SpellMeter and ns.SpellMeter.SmoothingAvailable() and ns.db.meter.smoothBars))

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
-- /sm rendertest: can native display setters accept secret values?
-- Each in-combat call is attempted through pcall purely to detect whether the
-- documented setter accepts the value; nothing is computed from secrets and
-- no secret is retained beyond the update call. After combat (data readable)
-- a correctness report checks sorting, sums and pet attribution.
---------------------------------------------------------------------------
local RT = { results = {}, order = {}, active = false, elapsed = 0, hadCombat = false }

local function RTRecord(name, ok, err)
    local r = RT.results[name]
    if not r then
        r = { ok = 0, err = 0 }
        RT.results[name] = r
        RT.order[#RT.order + 1] = name
    end
    if ok then
        r.ok = r.ok + 1
    else
        r.err = r.err + 1
        r.lastErr = tostring(err):sub(1, 160)
    end
end

local function RTCreate()
    local f = CreateFrame("Frame", "SoloMetricsRenderTest", UIParent)
    f:SetSize(320, 152)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.09, 0.85)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("SoloMetrics RENDER TEST (diagnostic)")

    local function row(y, label)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        l:SetPoint("TOPLEFT", 10, y)
        l:SetText(label)
        local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPLEFT", 120, y)
        v:SetText("-")
        return v
    end
    f.timer = row(-26, "Timer (readable)")
    f.total = row(-42, "Total raw")
    f.totalAbbr = row(-58, "Total abbreviated")
    f.dps = row(-74, "DPS raw")
    f.dpsFmt = row(-90, "DPS formatted")
    f.spellCount = row(-106, "# spells")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("TOPLEFT", 10, -126)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    bar:SetSize(280, 18)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0.31, 0.76, 0.97, 0.8)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(1, 1, 1, 0.08)
    f.bar = bar
    f.spellName = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.spellName:SetPoint("LEFT", 4, 0)
    f.spellName:SetText("spell 1")
    f.spellAmt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.spellAmt:SetPoint("RIGHT", -4, 0)
    f.spellAmt:SetText("-")

    f:Hide()
    return f
end

local function RTUpdate()
    local f = RT.frame
    local dm = C_DamageMeter
    local MT, ST = MeterEnums()
    if not MT or type(dm) ~= "table" then return end
    local counting = InCombat()
    if counting then RT.hadCombat = true end

    local function T(name, fn, ...)
        if type(fn) ~= "function" then
            if counting then RTRecord(name, false, "function missing") end
            return false
        end
        local ok, a = pcall(fn, ...)
        if counting then RTRecord(name, ok, a) end
        return ok, a
    end

    local okD, dur = pcall(dm.GetSessionDurationSeconds, ST.Current)
    if okD and not IsSecret(dur) and type(dur) == "number" then
        f.timer:SetText(("%.0fs"):format(dur))
    end

    local okS, session = pcall(dm.GetCombatSessionFromType, ST.Current, MT.DamageDone)
    local me
    if okS and type(session) == "table" and not IsSecret(session) and type(session.combatSources) == "table" then
        local list = session.combatSources
        for i = 1, #list do
            local s = list[i]
            if type(s) == "table" and not IsSecret(s.isLocalPlayer) and s.isLocalPlayer == true then
                me = s
                break
            end
        end
    end
    if me then
        T("FontString:SetText(source.totalAmount)", f.total.SetText, f.total, me.totalAmount)
        T("AbbreviateNumbers(totalAmount) -> SetText", function()
            f.totalAbbr:SetText(AbbreviateNumbers(me.totalAmount))
        end)
        T("BreakUpLargeNumbers(totalAmount)", BreakUpLargeNumbers, me.totalAmount)
        T("FontString:SetText(source.amountPerSecond)", f.dps.SetText, f.dps, me.amountPerSecond)
        T("FontString:SetFormattedText('%.1f', amountPerSecond)", f.dpsFmt.SetFormattedText, f.dpsFmt, "%.1f", me.amountPerSecond)
        T("string.format('%.1f', amountPerSecond)", string.format, "%.1f", me.amountPerSecond)
    end

    local okP, src = pcall(dm.GetCombatSessionSourceFromType, ST.Current, MT.DamageDone, UnitGUID("player"))
    if okP and type(src) == "table" and not IsSecret(src) and type(src.combatSpells) == "table" then
        local spells = src.combatSpells
        f.spellCount:SetText(tostring(#spells))
        local sp = spells[1]
        if type(sp) == "table" and not IsSecret(sp) then
            local getTex = C_Spell and C_Spell.GetSpellTexture
            local getName = C_Spell and C_Spell.GetSpellName
            local okT, tex = T("C_Spell.GetSpellTexture(spellID)", getTex, sp.spellID)
            if okT then T("Texture:SetTexture(texture result)", f.icon.SetTexture, f.icon, tex) end
            local okN, name = T("C_Spell.GetSpellName(spellID)", getName, sp.spellID)
            if okN then T("FontString:SetText(name result)", f.spellName.SetText, f.spellName, name) end
            T("StatusBar:SetMinMaxValues(0, source.maxAmount)", f.bar.SetMinMaxValues, f.bar, 0, src.maxAmount)
            T("StatusBar:SetValue(spell.totalAmount)", f.bar.SetValue, f.bar, sp.totalAmount)
            T("FontString:SetText(spell.totalAmount)", f.spellAmt.SetText, f.spellAmt, sp.totalAmount)
        end
    end
end

-- Returns v only if readable; otherwise nil.
local function R(v)
    if IsSecret(v) then return nil end
    return v
end

local function RTCorrectness(out)
    local dm = C_DamageMeter
    local MT, ST = MeterEnums()
    local okS, session = pcall(dm.GetCombatSessionFromType, ST.Current, MT.DamageDone)
    local okP, src = pcall(dm.GetCombatSessionSourceFromType, ST.Current, MT.DamageDone, UnitGUID("player"))
    if not (okS and okP and type(session) == "table" and type(src) == "table") then
        out("Correctness: session/source query failed")
        return
    end
    local me
    for i = 1, #(session.combatSources or {}) do
        local s = session.combatSources[i]
        if type(s) == "table" and R(s.isLocalPlayer) == true then me = s break end
    end
    local sTotal, sDur, sMax = R(session.totalAmount), R(session.durationSeconds), R(session.maxAmount)
    local pTotal, pMax = R(src.totalAmount), R(src.maxAmount)
    if not (me and sTotal and sDur and pTotal and pMax) then
        out("Correctness: some fields still secret or player source missing - skipped")
        return
    end
    local meTotal, meDps = R(me.totalAmount), R(me.amountPerSecond)
    out(("Sources in session: %d; session total=%s duration=%s max=%s"):format(
        #session.combatSources, tostring(sTotal), tostring(sDur), tostring(sMax)))
    out(("Player source: total=%s apiDPS=%s; playerSource total=%s max=%s"):format(
        tostring(meTotal), tostring(meDps), tostring(pTotal), tostring(pMax)))
    if meTotal and meDps and sDur and sDur > 0 then
        out(("apiDPS / (total / session duration) = %.3f"):format(meDps / (meTotal / sDur)))
    end
    out("session.total == player source total: " .. tostring(sTotal == meTotal))
    out("playerSource.total == player source total: " .. tostring(pTotal == meTotal))

    local spells = src.combatSpells or {}
    local sum, sorted, anyCreature = 0, true, 0
    local prev
    for i = 1, #spells do
        local sp = spells[i]
        local amt = R(sp.totalAmount)
        if amt then
            sum = sum + amt
            if prev and prev < amt then sorted = false end
            prev = amt
        end
        local cn = R(sp.creatureName)
        if type(cn) == "string" and cn ~= "" then anyCreature = anyCreature + 1 end
    end
    out(("#spells=%d, sorted by totalAmount desc: %s, sum=%s (== playerSource.total: %s)"):format(
        #spells, tostring(sorted), tostring(sum), tostring(sum == pTotal)))
    out("playerSource.maxAmount == spells[1].totalAmount: " .. tostring(spells[1] and R(spells[1].totalAmount) == pMax))
    out("spells with creatureName set (pet/guardian?): " .. anyCreature)
    local getName = C_Spell and C_Spell.GetSpellName
    for i = 1, math.min(#spells, 12) do
        local sp = spells[i]
        local id = R(sp.spellID)
        local name = (id and getName and getName(id)) or "?"
        out(("  %d. id=%s %s total=%s aps=%s overkill=%s creature=%s details#%d"):format(
            i, tostring(id), tostring(name), tostring(R(sp.totalAmount)), tostring(R(sp.amountPerSecond)),
            tostring(R(sp.overkillAmount)), tostring(R(sp.creatureName)),
            type(sp.combatSpellDetails) == "table" and #sp.combatSpellDetails or -1))
    end
end

local function RTReport()
    local r = NewReport("render test: in-combat secret rendering + post-combat correctness")
    r.out("In-combat native calls (ok / err counts):")
    if #RT.order == 0 then r.out("  (no in-combat attempts recorded)") end
    for _, name in ipairs(RT.order) do
        local x = RT.results[name]
        r.out(("  %s: ok=%d err=%d%s"):format(name, x.ok, x.err, x.lastErr and ("  last error: " .. x.lastErr) or ""))
    end
    RTCorrectness(r.out)
    r.finish(true)
    RT.results, RT.order, RT.hadCombat = {}, {}, false
end

local rtEvents = CreateFrame("Frame")
rtEvents:SetScript("OnEvent", function()
    if RT.active and RT.hadCombat then
        C_Timer.After(0.3, function()
            RTUpdate() -- one readable refresh so the panel shows final values
            RTReport()
        end)
    end
end)

function D.ToggleRenderTest()
    RT.frame = RT.frame or RTCreate()
    RT.active = not RT.active
    if RT.active then
        RT.results, RT.order, RT.hadCombat = {}, {}, false
        RT.frame:Show()
        RT.frame:SetScript("OnUpdate", function(_, elapsed)
            RT.elapsed = RT.elapsed + elapsed
            if RT.elapsed >= 0.25 then
                RT.elapsed = 0
                RTUpdate()
            end
        end)
        rtEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.Print("Render test ON: fight something and WATCH the panel during combat. Report prints after combat.")
    else
        RT.frame:SetScript("OnUpdate", nil)
        RT.frame:Hide()
        rtEvents:UnregisterAllEvents()
        ns.Print("Render test OFF.")
    end
end

---------------------------------------------------------------------------
-- /sm bardebug: what the meter's bars actually hold vs. the data (out of combat)
---------------------------------------------------------------------------
function D.BarDebug()
    local r = NewReport("bar debug")
    local out = r.out
    local demo = ns.Demo.IsActive()
    if InCombat() and not demo then
        out("Run this out of combat (values are secret in combat).")
        r.finish(true)
        return
    end
    local cfg = ns.db.meter
    out(("barScale=%s barOrder=%s smoothBars=%s session=%s smoothingAvailable=%s demo=%s"):format(
        tostring(cfg.barScale), tostring(cfg.barOrder), tostring(cfg.smoothBars), tostring(cfg.session),
        tostring(ns.SpellMeter.SmoothingAvailable()), tostring(demo)))
    out(("GetTime=%.1f"):format(GetTime()))
    local snap = demo and ns.Demo.Snapshot() or ns.API.Snapshot(cfg.session)
    local R = function(v) if IsSecret(v) then return "<secret>" end return tostring(v) end
    out(("snapshot: duration=%s total=%s max=%s dps=%s spellCount=%s"):format(
        R(snap.duration), R(snap.total), R(snap.max), R(snap.dps), R(snap.spellCount)))
    local rows = ns.SpellMeter.GetRows()
    for i, row in ipairs(rows) do
        if row:IsShown() then
            local mn, mx = row:GetMinMaxValues()
            local v = row:GetValue()
            local sp = snap.spells and snap.spells[i]
            local name = row.name:GetText()
            out(("row %d [%s]: bar min=%s max=%s value=%s | data total=%s aps=%s id=%s"):format(
                i, R(name), R(mn), R(mx), R(v),
                sp and R(sp.totalAmount) or "-", sp and R(sp.amountPerSecond) or "-", sp and R(sp.spellID) or "-"))
        end
    end
    r.finish(true)
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
