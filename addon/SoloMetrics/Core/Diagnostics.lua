-- SoloMetrics: Diagnostics (/sm debug)
-- Reports client build, C_DamageMeter function presence, related enums and,
-- OUT OF COMBAT ONLY, the shape of available sessions.
-- Secret values are never printed, compared or used in arithmetic: they are
-- reported as <secret>. pcall is used only to survive missing/changed APIs.

local _, ns = ...
local D = {}
ns.Diagnostics = D

local MAX_LINES = 80
local MAX_SESSIONS_SHOWN = 3

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

local function IsSecret(v)
    if issecretvalue then
        return issecretvalue(v) and true or false
    end
    return false
end

local function Describe(v)
    if IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "nil" or t == "boolean" or t == "number" or t == "string" then
        return t .. ":" .. tostring(v)
    end
    return "<" .. t .. ">"
end

local function SortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function D.Run()
    local lines = {}
    local function out(s)
        if #lines < MAX_LINES then
            lines[#lines + 1] = s
        elseif #lines == MAX_LINES then
            lines[#lines + 1] = "(output capped)"
        end
    end
    local function flush()
        ns.Print("---- debug report ----")
        for _, s in ipairs(lines) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. s)
        end
        ns.Print("---- end ----")
    end

    local version, build, date, toc = GetBuildInfo()
    out(("Client: version %s, build %s, date %s, interface %s"):format(
        tostring(version), tostring(build), tostring(date), tostring(toc)))
    out(("Addon: v%s, SV schema %d, load #%d"):format(ns.VERSION, ns.db.schema, ns.db.loadCount))
    out("issecretvalue: " .. type(issecretvalue))

    local inCombat = InCombatLockdown() and true or false
    out("In combat: " .. tostring(inCombat))

    local dm = C_DamageMeter
    if type(dm) ~= "table" then
        out("C_DamageMeter: MISSING")
        flush()
        return
    end
    out("C_DamageMeter functions:")
    for _, name in ipairs(DM_FUNCS) do
        out(("  %s: %s"):format(name, type(dm[name])))
    end
    local extra = {}
    for _, k in ipairs(SortedKeys(dm)) do
        local known = false
        for _, name in ipairs(DM_FUNCS) do
            if name == k then known = true break end
        end
        if not known then extra[#extra + 1] = tostring(k) end
    end
    if #extra > 0 then
        out("  undocumented members: " .. table.concat(extra, ", "))
    end

    -- Enums: list any Enum table whose name mentions DamageMeter.
    if type(Enum) == "table" then
        local found = 0
        for _, enumName in ipairs(SortedKeys(Enum)) do
            if type(enumName) == "string" and enumName:find("DamageMeter", 1, true) then
                found = found + 1
                local e = Enum[enumName]
                if type(e) == "table" then
                    local parts = {}
                    for _, k in ipairs(SortedKeys(e)) do
                        parts[#parts + 1] = tostring(k) .. "=" .. tostring(e[k])
                    end
                    out("Enum." .. enumName .. ": " .. table.concat(parts, ", "))
                end
            end
        end
        if found == 0 then out("Enum: no *DamageMeter* enums found") end
    else
        out("Enum: MISSING")
    end

    if inCombat then
        out("Session queries skipped: in combat (no data dumps in combat).")
        flush()
        return
    end

    if type(dm.IsDamageMeterAvailable) == "function" then
        local ok, a, b = pcall(dm.IsDamageMeterAvailable)
        if ok then
            out(("IsDamageMeterAvailable() -> %s, %s"):format(Describe(a), Describe(b)))
        else
            out("IsDamageMeterAvailable() errored: " .. tostring(a))
        end
    end

    if type(dm.GetAvailableCombatSessions) == "function" then
        local ok, sessions = pcall(dm.GetAvailableCombatSessions)
        if not ok then
            out("GetAvailableCombatSessions() errored: " .. tostring(sessions))
        elseif IsSecret(sessions) then
            out("GetAvailableCombatSessions() -> <secret>")
        elseif type(sessions) ~= "table" then
            out("GetAvailableCombatSessions() -> " .. Describe(sessions))
        else
            out(("GetAvailableCombatSessions() -> table, #=%d"):format(#sessions))
            for i = 1, math.min(#sessions, MAX_SESSIONS_SHOWN) do
                local s = sessions[i]
                if type(s) == "table" and not IsSecret(s) then
                    local parts = {}
                    for _, k in ipairs(SortedKeys(s)) do
                        parts[#parts + 1] = tostring(k) .. "=" .. Describe(s[k])
                    end
                    out(("  [%d] %s"):format(i, table.concat(parts, "  ")))
                else
                    out(("  [%d] %s"):format(i, Describe(s)))
                end
            end
        end
    end

    flush()
end
