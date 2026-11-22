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
