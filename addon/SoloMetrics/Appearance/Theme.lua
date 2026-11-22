-- SoloMetrics: Theme (style schema, registries, presets, validation)
-- A style is plain data. Every setting is declared in SCHEMA with its type and
-- bounds; Validate() builds a clean style from defaults + valid input values,
-- dropping anything unknown. The same validation will guard profile import.

local _, ns = ...
local T = {}
ns.Theme = T

---------------------------------------------------------------------------
-- Registries (keys are what styles store; never raw paths)
---------------------------------------------------------------------------
T.FONTS = {
    default  = { label = "Friz Quadrata (default)", path = function() return STANDARD_TEXT_FONT end },
    arialn   = { label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    morpheus = { label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    skurri   = { label = "Skurri", path = "Fonts\\SKURRI.TTF" },
    damage   = { label = "Damage font", path = function() return DAMAGE_TEXT_FONT end },
}

T.TEXTURES = {
    flat     = { label = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
    blizzard = { label = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    raid     = { label = "Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}

-- Bundled textures (Assets/Textures/Custom), listed by the generated
-- Assets/TextureIndex.lua (scripts/Update-TextureIndex.ps1).
T.ASSET_ROOT = "Interface\\AddOns\\SoloMetrics\\Assets\\"
for _, t in ipairs(ns.CUSTOM_TEXTURES or {}) do
    if type(t.key) == "string" and type(t.file) == "string" and not T.TEXTURES[t.key] then
        T.TEXTURES[t.key] = { label = t.label or t.key, path = T.ASSET_ROOT .. "Textures\\Custom\\" .. t.file }
    end
end

T.OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
T.ALIGNS = { left = "LEFT", center = "CENTER", right = "RIGHT" }
-- widget-only value types
T.VALIGNS = { top = true, middle = true, bottom = true }
T.PLACES = { above = true, below = true, top = true, bottom = true }
T.NUMFMTS = { auto = true, compact = true, full = true, decimal1 = true, decimal2 = true }

-- Free text (titles, suffixes): short, no escape/control characters.
local function ValidText(v)
    return type(v) == "string" and #v <= 32 and not v:find("[%c|]")
end
T.ValidText = ValidText

function T.FontPath(key)
    local f = T.FONTS[key] or T.FONTS.default
    local p = f.path
    if type(p) == "function" then p = p() end
    return p or STANDARD_TEXT_FONT
end

function T.TexturePath(key)
    return (T.TEXTURES[key] or T.TEXTURES.flat).path
end

---------------------------------------------------------------------------
-- Defaults (= "modern" preset)
---------------------------------------------------------------------------
local DEFAULT = {
    width = 280,
    scale = 1.0,
    padding = 4,
    backdrop = { enabled = true, texture = "flat", color = { 0.07, 0.07, 0.08, 0.78 } },
    border = { enabled = false, color = { 0, 0, 0, 1 }, size = 1 },
    accent = { enabled = true, classColor = true, color = { 0.31, 0.76, 0.97, 0.9 }, height = 2 },
    header = {
        enabled = true, height = 24,
        font = "default", size = 13, outline = "none",
        labelColor = { 0.6, 0.6, 0.6, 1 }, valueColor = { 1, 1, 1, 1 },
        showDps = true, showTotal = true, showTimer = true, showSession = true,
        bg = { enabled = false, color = { 0, 0, 0, 0.35 } },
    },
    rows = { height = 18, spacing = 1 },
    icon = {
        enabled = true, alpha = 1, matchRow = true, size = 18, crop = 0.08, gap = 2,
        border = false, borderColor = { 0, 0, 0, 1 },
    },
    bar = { enabled = true, texture = "flat", classColor = true, color = { 0.31, 0.76, 0.97, 0.75 } },
    barBg = { enabled = true, texture = "flat", color = { 1, 1, 1, 0.06 } },
    text = {
        font = "default", size = 11, outline = "none", shadow = true, columnWidth = 50,
        shadowColor = { 0, 0, 0, 0.9 }, shadowOffset = 1,
        name = { enabled = true, color = { 1, 1, 1, 1 }, align = "left" },
        amount = { enabled = true, color = { 1, 1, 1, 1 }, align = "right" },
        dps = { enabled = true, color = { 1, 1, 1, 1 }, align = "right" },
    },
}

-- path, type, min, max  (types: number, bool, color, font, texture, outline)
T.SCHEMA = {
    { "width", "number", 120, 800 },
    { "scale", "number", 0.5, 2 },
    { "padding", "number", 0, 20 },
    { "backdrop.enabled", "bool" },
    { "backdrop.color", "color" },
    { "border.enabled", "bool" },
    { "border.color", "color" },
    { "border.size", "number", 1, 8 },
    { "accent.enabled", "bool" },
    { "accent.classColor", "bool" },
    { "accent.color", "color" },
    { "accent.height", "number", 1, 8 },
    { "header.enabled", "bool" },
    { "header.height", "number", 12, 48 },
    { "header.font", "font" },
    { "header.size", "number", 6, 32 },
    { "header.outline", "outline" },
    { "header.labelColor", "color" },
    { "header.valueColor", "color" },
    { "header.showDps", "bool" },
    { "header.showTotal", "bool" },
    { "header.showTimer", "bool" },
    { "header.showSession", "bool" },
    { "rows.height", "number", 8, 40 },
    { "rows.spacing", "number", 0, 10 },
    { "icon.enabled", "bool" },
    { "icon.alpha", "number", 0, 1 },
    { "bar.enabled", "bool" },
    { "bar.texture", "texture" },
    { "bar.classColor", "bool" },
    { "bar.color", "color" },
    { "barBg.enabled", "bool" },
    { "barBg.color", "color" },
    { "text.font", "font" },
    { "text.size", "number", 6, 32 },
    { "text.outline", "outline" },
    { "text.shadow", "bool" },
    { "text.columnWidth", "number", 20, 120 },
    { "text.name.enabled", "bool" },
    { "text.name.color", "color" },
    { "text.amount.enabled", "bool" },
    { "text.amount.color", "color" },
    { "text.dps.enabled", "bool" },
    { "text.dps.color", "color" },
    -- additions (M3 schema extension)
    { "backdrop.texture", "texture" },
    { "header.bg.enabled", "bool" },
    { "header.bg.color", "color" },
    { "barBg.texture", "texture" },
    { "icon.matchRow", "bool" },
    { "icon.size", "number", 8, 48 },
    { "icon.crop", "number", 0, 0.3 },
    { "icon.gap", "number", 0, 12 },
    { "icon.border", "bool" },
    { "icon.borderColor", "color" },
    { "text.name.align", "align" },
    { "text.amount.align", "align" },
    { "text.dps.align", "align" },
    { "text.shadowColor", "color" },
    { "text.shadowOffset", "number", 0, 4 },
}

local SCHEMA_BY_PATH, SCHEMA_BY_LOWER = {}, {}
for _, e in ipairs(T.SCHEMA) do
    SCHEMA_BY_PATH[e[1]] = e
    SCHEMA_BY_LOWER[e[1]:lower()] = e
end

-- Canonical path for user input (case-insensitive), or nil.
function T.ResolvePath(text)
    local e = SCHEMA_BY_LOWER[(text or ""):lower()]
    return e and e[1] or nil
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end
T.DeepCopy = DeepCopy

local function GetPath(tbl, path)
    local node = tbl
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

local function SetPath(tbl, path, value)
    local node = tbl
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
end

local function ValidColor(c)
    if type(c) ~= "table" then return false end
    for i = 1, 4 do
        local x = c[i]
        if i <= 3 and type(x) ~= "number" then return false end
        if x ~= nil and (type(x) ~= "number" or x < 0 or x > 1) then return false end
    end
    return true
end

local function IsValid(entry, v)
    local t = entry[2]
    if t == "number" then return type(v) == "number" and v >= entry[3] and v <= entry[4] end
    if t == "bool" then return type(v) == "boolean" end
    if t == "color" then return ValidColor(v) end
    if t == "font" then return type(v) == "string" and T.FONTS[v] ~= nil end
    if t == "texture" then return type(v) == "string" and T.TEXTURES[v] ~= nil end
    if t == "outline" then return type(v) == "string" and T.OUTLINES[v] ~= nil end
    if t == "align" then return type(v) == "string" and T.ALIGNS[v] ~= nil end
    if t == "valign" then return type(v) == "string" and T.VALIGNS[v] ~= nil end
    if t == "place" then return type(v) == "string" and T.PLACES[v] ~= nil end
    if t == "numfmt" then return type(v) == "string" and T.NUMFMTS[v] ~= nil end
    if t == "text" then return ValidText(v) end
    return false
end

-- Clean style: defaults overlaid with every valid value from `input`.
function T.Validate(input)
    local out = DeepCopy(DEFAULT)
    if type(input) ~= "table" then return out end
    for _, e in ipairs(T.SCHEMA) do
        local v = GetPath(input, e[1])
        if v ~= nil and IsValid(e, v) then
            if e[2] == "color" then
                v = { v[1], v[2], v[3], v[4] or 1 }
            end
            SetPath(out, e[1], v)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Text <-> value (for /sm set and /sm get)
---------------------------------------------------------------------------
local function ParseHexColor(s)
    s = s:gsub("^#", "")
    if not (#s == 6 or #s == 8) or s:find("[^%x]") then return nil end
    local r = tonumber(s:sub(1, 2), 16) / 255
    local g = tonumber(s:sub(3, 4), 16) / 255
    local b = tonumber(s:sub(5, 6), 16) / 255
    local a = (#s == 8) and (tonumber(s:sub(7, 8), 16) / 255) or 1
    return { r, g, b, a }
end

function T.FormatValue(entry, v)
    if entry[2] == "color" and type(v) == "table" then
        return ("%02x%02x%02x%02x"):format(
            math.floor(v[1] * 255 + 0.5), math.floor(v[2] * 255 + 0.5),
            math.floor(v[3] * 255 + 0.5), math.floor((v[4] or 1) * 255 + 0.5))
    end
    return tostring(v)
end

-- Returns value or nil, errorMessage
function T.ParseValue(path, text)
    local e = SCHEMA_BY_PATH[path]
    if not e then return nil, "unknown setting '" .. path .. "' (see /sm get)" end
    text = strtrim(text or "")
    local t, v = e[2], nil
    if t == "number" then
        v = tonumber(text)
        if not v then return nil, "expected a number" end
        if v < e[3] or v > e[4] then return nil, ("must be between %s and %s"):format(e[3], e[4]) end
    elseif t == "bool" then
        local l = text:lower()
        if l == "on" or l == "true" or l == "1" or l == "yes" then v = true
        elseif l == "off" or l == "false" or l == "0" or l == "no" then v = false
        else return nil, "expected on/off" end
    elseif t == "color" then
        v = ParseHexColor(text)
        if not v then return nil, "expected hex color RRGGBB or RRGGBBAA (AA = opacity)" end
    else
        local reg = (t == "font" and T.FONTS) or (t == "texture" and T.TEXTURES)
            or (t == "align" and T.ALIGNS) or T.OUTLINES
        local l = text:lower()
        if not reg[l] then
            local keys = {}
            for k in pairs(reg) do keys[#keys + 1] = k end
            table.sort(keys)
            return nil, "expected one of: " .. table.concat(keys, ", ")
        end
        v = l
    end
    return v
end

T.GetPath = GetPath
T.SetPath = SetPath
T.SCHEMA_BY_PATH = SCHEMA_BY_PATH

function T.GetDefault(path)
    return DeepCopy(GetPath(DEFAULT, path))
end

-- Validate a value against an arbitrary schema entry { path, type, min, max }.
function T.IsValidEntry(entry, v)
    return IsValid(entry, v)
end

function T.IsValidValue(path, v)
    local e = SCHEMA_BY_PATH[path]
    return e ~= nil and IsValid(e, v)
end

---------------------------------------------------------------------------
-- Presets (overrides applied to DEFAULT)
---------------------------------------------------------------------------
T.PRESET_ORDER = { "modern", "minimal", "textonly", "compact" }
T.PRESETS = {
    modern = { label = "Modern Dark", overrides = {} },
    minimal = {
        label = "Ultra-Minimal (bars + text only)",
        overrides = {
            ["backdrop.enabled"] = false, ["border.enabled"] = false, ["accent.enabled"] = false,
            ["header.enabled"] = false, ["icon.enabled"] = false, ["barBg.enabled"] = false,
            ["text.outline"] = "outline", ["text.shadow"] = false,
            ["bar.color"] = { 0.31, 0.76, 0.97, 0.6 },
        },
    },
    textonly = {
        label = "Text-Only",
        overrides = {
            ["backdrop.enabled"] = false, ["border.enabled"] = false, ["accent.enabled"] = false,
            ["icon.enabled"] = false, ["bar.enabled"] = false, ["barBg.enabled"] = false,
            ["header.outline"] = "outline", ["text.outline"] = "outline", ["text.shadow"] = false,
        },
    },
    compact = {
        label = "Compact",
        overrides = {
            ["width"] = 220, ["rows.height"] = 14, ["rows.spacing"] = 1,
            ["text.size"] = 10, ["header.height"] = 20, ["header.size"] = 11, ["text.columnWidth"] = 40,
        },
    },
}

function T.BuildPreset(key)
    local p = T.PRESETS[key]
    if not p then return nil end
    local style = DeepCopy(DEFAULT)
    for path, v in pairs(p.overrides) do SetPath(style, path, DeepCopy(v)) end
    return T.Validate(style)
end

---------------------------------------------------------------------------
-- Active profile access
---------------------------------------------------------------------------
function T.Active()
    return ns.db.profiles[ns.Profiles.ActiveName()]
end
