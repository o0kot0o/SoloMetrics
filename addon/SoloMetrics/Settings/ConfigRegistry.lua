-- SoloMetrics: Config registry (UI metadata for every setting)
-- Categories -> ordered items. Item kinds:
--   style   : a Theme.SCHEMA path (type/bounds come from the schema)
--   meter   : a db.meter behaviour key (type/bounds declared here)
--   section : sub-heading        note : explanatory text
--   presets : preset buttons     action : buttons (id list)
-- Optional item fields: tip, adv (Advanced section), dep (bool style path
-- that must be on for the control to be enabled), step (slider step).
-- Every Theme.SCHEMA path must appear at least once (CoverageCheck).

local _, ns = ...
local R = {}
ns.ConfigRegistry = R

local function S(path, label, extra)
    local it = { kind = "style", path = path, label = label }
    if extra then for k, v in pairs(extra) do it[k] = v end end
    return it
end
local function SEC(label) return { kind = "section", label = label } end

R.CATEGORIES = {
    {
        id = "general", label = "General",
        items = {
            { kind = "meter", key = "shown", type = "bool", label = "Show meter",
              tip = "Show or hide the damage meter. /sm also toggles it." },
            { kind = "meter", key = "locked", type = "bool", label = "Lock meter (click-through)",
              tip = "A locked meter ignores the mouse completely, so it never blocks clicks. Unlock to drag it." },
            { kind = "meter", key = "session", type = "enum", label = "Session",
              values = { { "current", "Current fight" }, { "overall", "Overall" } },
              tip = "Current fight resets when a new fight starts. Overall accumulates." },
            { kind = "meter", key = "maxRows", type = "number", min = 1, max = 20, step = 1,
              label = "Maximum spell rows" },
            { kind = "meter", key = "numberFormat", type = "enum", label = "Damage number format",
              values = { { "compact", "Compact (12.3K)" }, { "full", "Full (12,345)" } },
              tip = "Formatting done natively by the game, so it works live in combat. DPS always shows one decimal." },
            { kind = "meter", key = "barScale", type = "enum", label = "Bar length",
              values = { { "top", "Relative to top spell" }, { "total", "Share of total damage" } },
              tip = "Top spell: your best ability is always a full bar. Share of total: all bars add up to 100%." },
            { kind = "meter", key = "smoothBars", type = "bool", label = "Smooth bar animation",
              tip = "Bars glide to new values (engine-side animation, safe with protected combat values)." },
            { kind = "meter", key = "minimapShown", type = "bool", label = "Show minimap button",
              tip = "Left-click opens settings, right-click shows/hides the meter. SoloMetrics is also in the addon compartment menu where supported." },
        },
    },
    {
        id = "appearance", label = "Appearance",
        items = {
            { kind = "presets" },
            SEC("Background"),
            S("backdrop.enabled", "Show background"),
            S("backdrop.color", "Background color", { dep = "backdrop.enabled",
              tip = "Opacity only affects the background, never bars or text." }),
            SEC("Border"),
            S("border.enabled", "Show border"),
            S("border.color", "Border color", { dep = "border.enabled" }),
            S("border.size", "Border thickness", { dep = "border.enabled", step = 1, adv = true }),
            SEC("Accent line"),
            S("accent.enabled", "Show accent line", { tip = "Thin colored line along the top edge." }),
            S("accent.classColor", "Use class color", { dep = "accent.enabled" }),
            S("accent.color", "Accent color", { dep = "accent.enabled",
              tip = "Used when class color is off. Its opacity always applies." }),
            S("accent.height", "Accent thickness", { dep = "accent.enabled", step = 1, adv = true }),
        },
    },
    {
        id = "bars", label = "Damage Bars",
        items = {
            SEC("Bar fill"),
            S("bar.enabled", "Show bar fill", { tip = "Off: rows show text only (bar length still tracked)." }),
            S("bar.texture", "Bar texture", { dep = "bar.enabled" }),
            S("bar.classColor", "Use class color", { dep = "bar.enabled" }),
            S("bar.color", "Bar color", { dep = "bar.enabled",
              tip = "Used when class color is off. Its opacity always applies to the fill only." }),
            SEC("Bar background"),
            S("barBg.enabled", "Show bar background", { tip = "The track behind each bar." }),
            S("barBg.color", "Bar background color", { dep = "barBg.enabled" }),
            SEC("Rows"),
            S("rows.height", "Row height", { step = 1 }),
            SEC("Spell icons"),
            S("icon.enabled", "Show spell icons"),
            S("icon.alpha", "Icon opacity", { dep = "icon.enabled", step = 0.05, adv = true }),
        },
    },
    {
        id = "text", label = "Text & Fonts",
        items = {
            SEC("Font"),
            S("text.font", "Font"),
            S("text.size", "Font size", { step = 1 }),
            S("text.outline", "Outline"),
            S("text.shadow", "Drop shadow"),
            SEC("Columns"),
            S("text.name.enabled", "Show spell name"),
            S("text.name.color", "Spell name color", { dep = "text.name.enabled" }),
            S("text.amount.enabled", "Show damage"),
            S("text.amount.color", "Damage color", { dep = "text.amount.enabled" }),
            S("text.dps.enabled", "Show DPS"),
            S("text.dps.color", "DPS color", { dep = "text.dps.enabled" }),
            S("text.columnWidth", "Number column width", { step = 1, adv = true }),
        },
    },
    {
        id = "header", label = "Header",
        items = {
            S("header.enabled", "Show header"),
            SEC("Contents"),
            S("header.showDps", "Show DPS", { dep = "header.enabled" }),
            S("header.showTotal", "Show total damage", { dep = "header.enabled" }),
            S("header.showSession", "Show session label", { dep = "header.enabled" }),
            S("header.showTimer", "Show fight timer", { dep = "header.enabled" }),
            SEC("Typography"),
            S("header.font", "Header font", { dep = "header.enabled" }),
            S("header.size", "Header font size", { dep = "header.enabled", step = 1 }),
            S("header.outline", "Header outline", { dep = "header.enabled" }),
            S("header.labelColor", "Label color", { dep = "header.enabled", tip = "DPS / DMG labels and session text." }),
            S("header.valueColor", "Value color", { dep = "header.enabled", tip = "DPS, damage and timer numbers." }),
            S("header.height", "Header height", { dep = "header.enabled", step = 1, adv = true }),
        },
    },
    {
        id = "layout", label = "Layout & Position",
        items = {
            S("width", "Meter width", { step = 1 }),
            S("scale", "Scale", { step = 0.05 }),
            S("padding", "Inner padding", { step = 1 }),
            S("rows.spacing", "Row spacing", { step = 1 }),
            SEC("Position"),
            { kind = "meter", key = "grow", type = "enum", label = "Grow direction",
              values = { { "down", "Down (top edge fixed)" }, { "up", "Up (bottom edge fixed)" } },
              tip = "Which edge stays in place as rows are added. Use Up for a meter placed at the bottom of the screen." },
            { kind = "action", actions = { "move", "resetpos" } },
        },
    },
    {
        id = "visibility", label = "Visibility",
        items = {
            { kind = "note", text = "Every visual element can be hidden on its own. Turn all of these off except bar fill and the text columns for a bars-and-text-only meter. While unlocked, an outline shows where an invisible meter is." },
            S("backdrop.enabled", "Background"),
            S("border.enabled", "Border"),
            S("accent.enabled", "Accent line"),
            S("header.enabled", "Header"),
            S("icon.enabled", "Spell icons"),
            S("bar.enabled", "Bar fill"),
            S("barBg.enabled", "Bar background"),
            S("text.name.enabled", "Spell name"),
            S("text.amount.enabled", "Damage"),
            S("text.dps.enabled", "DPS"),
        },
    },
    {
        id = "profiles", label = "Profiles",
        items = {
            { kind = "note", text = "A profile is a complete saved appearance. Switch between them any time; meter behaviour (General) is shared." },
            { kind = "profiles" },
            SEC("Share"),
            { kind = "note", text = "Share codes contain only appearance settings - never character names, realms or combat data. Imports are checked setting by setting and rejected safely if damaged." },
            { kind = "share" },
            SEC("Presets"),
            { kind = "note", profileInfo = true },
            { kind = "presets" },
        },
    },
}

-- Returns list of Theme.SCHEMA paths with no control (should be empty).
function R.CoverageCheck()
    local seen = {}
    for _, cat in ipairs(R.CATEGORIES) do
        for _, it in ipairs(cat.items) do
            if it.kind == "style" then seen[it.path] = true end
        end
    end
    local missing = {}
    for _, e in ipairs(ns.Theme.SCHEMA) do
        if not seen[e[1]] then missing[#missing + 1] = e[1] end
    end
    return missing, #ns.Theme.SCHEMA
end
