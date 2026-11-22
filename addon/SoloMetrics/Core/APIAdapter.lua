-- SoloMetrics: APIAdapter
-- Sole gateway to C_DamageMeter for runtime features (Diagnostics excepted).
--
-- Snapshot() returns a TRANSIENT render model. Fields marked (opaque) may be
-- secret in combat: they may only be handed to native setters during the same
-- render call. Never store, compare, sort, do arithmetic or branch on them.
-- See docs/DECISIONS.md D-005.

local _, ns = ...
local A = {}
ns.API = A
local S = ns.SecretSafety

A.EVENTS = {
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}

local function Enums()
    local MT = Enum and Enum.DamageMeterType
    local ST = Enum and Enum.DamageMeterSessionType
    if type(MT) ~= "table" or type(ST) ~= "table" then return nil end
    return MT, ST
end

function A.IsAvailable()
    if type(C_DamageMeter) ~= "table" or not Enums() then return false end
    local ok, avail = pcall(C_DamageMeter.IsDamageMeterAvailable)
    return ok and S.Readable(avail) == true
end

-- sessionKey: "current" | "overall"
-- Returns {
--   duration     readable number or nil (readable even in combat)
--   hasPlayer    readable boolean: local player has a source entry
--   classFilename readable string or nil
--   dps          (opaque) player amountPerSecond
--   total        (opaque) player totalAmount
--   max          (opaque) largest spell totalAmount (bar scale)
--   spells       array of (opaque) spell records, API order (native: desc by total)
--   spellCount   readable number
-- }
function A.Snapshot(sessionKey)
    local snap = { hasPlayer = false, spellCount = 0, spells = nil }
    local MT, ST = Enums()
    if not MT then return snap end
    local st = (sessionKey == "overall") and ST.Overall or ST.Current
    local dm = C_DamageMeter

    local okD, d = pcall(dm.GetSessionDurationSeconds, st)
    if okD then snap.duration = S.Readable(d) end

    local okS, session = pcall(dm.GetCombatSessionFromType, st, MT.DamageDone)
    if okS and type(session) == "table" and type(session.combatSources) == "table" then
        local list = session.combatSources
        for i = 1, #list do
            local src = list[i]
            if type(src) == "table" and S.Readable(src.isLocalPlayer) == true then
                snap.hasPlayer = true
                snap.dps = src.amountPerSecond
                snap.classFilename = S.Readable(src.classFilename)
                break
            end
        end
    end

    local okP, ps = pcall(dm.GetCombatSessionSourceFromType, st, MT.DamageDone, UnitGUID("player"))
    if okP and type(ps) == "table" then
        snap.total = ps.totalAmount
        snap.max = ps.maxAmount
        if type(ps.combatSpells) == "table" then
            snap.spells = ps.combatSpells
            snap.spellCount = #ps.combatSpells
        end
    end
    return snap
end

---------------------------------------------------------------------------
-- Completed-fight (readable) queries - OUT OF COMBAT ONLY.
-- Every field passes SecretSafety.Readable before any Lua logic; if anything
-- is still secret the query returns nil (no partial or invented data).
-- Results for finished sessions are cached; the newest session is never
-- cached (a chained pull can still extend it).
---------------------------------------------------------------------------
local cache = {}

function A.ClearCache()
    wipe(cache)
end

-- Oldest -> newest: { { id, name, duration }, ... } or nil (in combat / error)
function A.SessionList()
    if InCombatLockdown() or not A.IsAvailable() then return nil end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" or S.IsSecret(sessions) then return nil end
    local out = {}
    for i = 1, #sessions do
        local s = sessions[i]
        if type(s) == "table" then
            local id = S.Readable(s.sessionID)
            if type(id) == "number" then
                out[#out + 1] = { id = id, name = S.Readable(s.name), duration = S.Readable(s.durationSeconds) }
            end
        end
    end
    return out
end

-- Player totals for one finished session: { total, dps } or nil.
function A.SessionPlayer(id, noCache)
    if InCombatLockdown() then return nil end
    local key = "p:" .. id
    if cache[key] then return cache[key] end
    local MT = Enum.DamageMeterType
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, id, MT.DamageDone)
    if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
    local r = { total = 0, dps = 0 } -- player did no damage in this session
    local list = session.combatSources
    for i = 1, #list do
        local src = list[i]
        if type(src) == "table" and S.Readable(src.isLocalPlayer) == true then
            local t, d = S.Readable(src.totalAmount), S.Readable(src.amountPerSecond)
            if type(t) ~= "number" or type(d) ~= "number" then return nil end
            r = { total = t, dps = d }
            break
        end
    end
    if not noCache then cache[key] = r end
    return r
end

-- One spell's totals in a finished session: { total, dps, sourceTotal } or nil.
-- spellID must be a readable number captured out of combat.
function A.SessionSpell(id, spellID, noCache)
    if InCombatLockdown() or type(spellID) ~= "number" then return nil end
    local key = "s:" .. id .. ":" .. spellID
    if cache[key] then return cache[key] end
    local MT = Enum.DamageMeterType
    local ok, ps = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, MT.DamageDone, UnitGUID("player"))
    if not ok then return nil end
    local r = { total = 0, dps = 0, sourceTotal = 0, found = false }
    if type(ps) == "table" then
        local st = S.Readable(ps.totalAmount)
        if type(st) ~= "number" then return nil end
        r.sourceTotal = st
        local spells = ps.combatSpells
        if type(spells) == "table" then
            for i = 1, #spells do
                local sp = spells[i]
                local sid = type(sp) == "table" and S.Readable(sp.spellID)
                if type(sid) ~= "number" then return nil end -- never compare a secret
                if sid == spellID then
                    local t, d = S.Readable(sp.totalAmount), S.Readable(sp.amountPerSecond)
                    if type(t) ~= "number" or type(d) ~= "number" then return nil end
                    r.total, r.dps, r.found = t, d, true
                    break
                end
            end
        end
    end
    if not noCache then cache[key] = r end
    return r
end
