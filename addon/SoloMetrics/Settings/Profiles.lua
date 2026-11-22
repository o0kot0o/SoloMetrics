-- SoloMetrics: style profiles (create/switch/rename/duplicate/delete,
-- optional per-character profile, safe data-only export/import)
--
-- Share code format (data only, never executed):
--   SM1:<profile name>:<path=value;path=value;...>:<checksum>
-- (":" not "|": WoW edit boxes treat "|" as an escape-code character.)
-- Only values that differ from the defaults are included. Values are parsed
-- with Theme.ParseValue and the result passes Theme.Validate, exactly like
-- /sm set. No character names, GUIDs or combat data are ever included.

local _, ns = ...
local P = {}
ns.Profiles = P

local MAX_NAME = 32
local CODE_PREFIX = "SM1"
local MAX_CODE = 6000

local function DB() return ns.db end

local function CharKey()
    local n = UnitName("player") or "?"
    local r = (GetRealmName and GetRealmName()) or "?"
    return n .. " - " .. r
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
function P.CleanName(s)
    s = strtrim(((s or ""):gsub("[%c|;=:]", "")))
    if s == "" then return nil, "Name can't be empty." end
    if #s > MAX_NAME then return nil, "Name is too long (max " .. MAX_NAME .. " characters)." end
    return s
end

local function Exists(name)
    local l = name:lower()
    for n in pairs(DB().profiles) do
        if n:lower() == l then return n end
    end
end

function P.UniqueName(base)
    base = P.CleanName(base) or "Profile"
    if not Exists(base) then return base end
    for i = 2, 99 do
        local suffix = " " .. i
        local c = base:sub(1, MAX_NAME - #suffix) .. suffix
        if not Exists(c) then return c end
    end
    return base .. " " .. time()
end

function P.List()
    local names = {}
    for n in pairs(DB().profiles) do names[#names + 1] = n end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

---------------------------------------------------------------------------
-- Active profile resolution
---------------------------------------------------------------------------
function P.ActiveName()
    local db = DB()
    local o = db.charProfile[CharKey()]
    if o and db.profiles[o] then return o end
    return db.activeProfile
end

function P.IsPerCharacter()
    local db = DB()
    local o = db.charProfile[CharKey()]
    return o ~= nil and db.profiles[o] ~= nil
end

function P.SetPerCharacter(on)
    local db = DB()
    if on then
        db.charProfile[CharKey()] = P.ActiveName()
    else
        db.charProfile[CharKey()] = nil
    end
    ns.SpellMeter.ApplyStyle()
end

function P.Switch(name)
    local db = DB()
    if not db.profiles[name] then return false end
    if P.IsPerCharacter() then
        db.charProfile[CharKey()] = name
    else
        db.activeProfile = name
    end
    ns.SpellMeter.ApplyStyle()
    return true
end

---------------------------------------------------------------------------
-- Management
---------------------------------------------------------------------------
function P.Create(rawName, fromCurrent)
    local name, err = P.CleanName(rawName)
    if not name then return nil, err end
    if Exists(name) then return nil, "A profile with that name already exists." end
    local style = fromCurrent and ns.Theme.DeepCopy(ns.Theme.Active()) or ns.Theme.BuildPreset("modern")
    DB().profiles[name] = ns.Theme.Validate(style)
    P.Switch(name)
    return name
end

function P.Duplicate(rawName)
    return P.Create(rawName, true)
end

function P.Rename(old, rawNew)
    local db = DB()
    if not db.profiles[old] then return nil, "Profile not found." end
    local name, err = P.CleanName(rawNew)
    if not name then return nil, err end
    local existing = Exists(name)
    if existing and existing ~= old then return nil, "A profile with that name already exists." end
    if name ~= old then
        db.profiles[name] = db.profiles[old]
        db.profiles[old] = nil
        if db.activeProfile == old then db.activeProfile = name end
        for k, v in pairs(db.charProfile) do
            if v == old then db.charProfile[k] = name end
        end
    end
    return name
end

function P.Delete(name)
    local db = DB()
    if not db.profiles[name] then return nil, "Profile not found." end
    if #P.List() <= 1 then return nil, "You can't delete the only profile." end
    db.profiles[name] = nil
    local fallback = P.List()[1]
    if db.activeProfile == name then db.activeProfile = fallback end
    for k, v in pairs(db.charProfile) do
        if v == name then db.charProfile[k] = nil end
    end
    ns.SpellMeter.ApplyStyle()
    return true
end

---------------------------------------------------------------------------
-- Export / import
---------------------------------------------------------------------------
local function Checksum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b % 65536, a % 65536)
end

local function EncodeValue(entry, v)
    local t = entry[2]
    if t == "bool" then return v and "1" or "0" end
    if t == "number" then
        local s = ("%.3f"):format(v)
        s = s:gsub("0+$", "")
        s = s:gsub("%.$", "")
        return s
    end
    if t == "color" then return ns.Theme.FormatValue(entry, v) end
    return tostring(v)
end

function P.Export(name)
    local style = DB().profiles[name]
    if not style then return nil end
    local parts = {}
    for _, e in ipairs(ns.Theme.SCHEMA) do
        local v = EncodeValue(e, ns.Theme.GetPath(style, e[1]))
        local d = EncodeValue(e, ns.Theme.GetDefault(e[1]))
        if v ~= d then parts[#parts + 1] = e[1] .. "=" .. v end
    end
    local body = CODE_PREFIX .. ":" .. (P.CleanName(name) or "Profile") .. ":" .. table.concat(parts, ";")
    return body .. ":" .. Checksum(body)
end

-- Returns newProfileName, ignoredCount  or  nil, errorMessage.
-- Never modifies existing profiles; on any error nothing is changed.
function P.Import(code)
    if type(code) ~= "string" then return nil, "Nothing to import." end
    code = strtrim((code:gsub("[\r\n]", "")))
    if code == "" then return nil, "Paste a SoloMetrics profile code first." end
    if #code > MAX_CODE then return nil, "That code is too long to be a SoloMetrics profile." end
    local prefix, name, body, sum = code:match("^(SM%d+):([^:]*):([^:]*):(%x+)$")
    if not prefix then return nil, "That isn't a SoloMetrics profile code." end
    if prefix ~= CODE_PREFIX then
        return nil, "This code is from an unsupported SoloMetrics version (" .. prefix .. ")."
    end
    if Checksum(prefix .. ":" .. name .. ":" .. body) ~= sum:lower() then
        return nil, "The code is damaged or incomplete (checksum mismatch). Copy it again."
    end

    local style = ns.Theme.BuildPreset("modern")
    local ignored = 0
    for pair in body:gmatch("[^;]+") do
        local k, v = pair:match("^([%w%.]+)=(.+)$")
        if not k then return nil, "The code contains a malformed entry." end
        local path = ns.Theme.ResolvePath(k)
        if not path then
            ignored = ignored + 1 -- setting from a newer version: skip safely
        else
            local val, err = ns.Theme.ParseValue(path, v)
            if val == nil then return nil, ("Invalid value for %s: %s"):format(path, err) end
            ns.Theme.SetPath(style, path, val)
        end
    end

    local final = P.UniqueName(P.CleanName(name) or "Imported")
    DB().profiles[final] = ns.Theme.Validate(style)
    P.Switch(final)
    return final, ignored
end
