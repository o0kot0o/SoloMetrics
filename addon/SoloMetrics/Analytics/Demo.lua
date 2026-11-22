-- SoloMetrics: Demo fight simulator (/sm test)
-- Feeds explicitly labeled DEMO data into the meter through the same render
-- path as real combat, so layout, smoothing, bar modes and number formats can
-- be watched without fighting. Never mixed with or stored as real results.

local _, ns = ...
local Demo = {}
ns.Demo = Demo

-- Real spell IDs (for icons/names); damage numbers are invented.
local SPELLS = {
    { id = 75,   min = 18, max = 24, interval = 2.0, start = 0.2 }, -- Auto Shot
    { id = 3044, min = 30, max = 38, interval = 6.0, start = 0.8 }, -- Arcane Shot
    { id = 1978, min = 6,  max = 7,  interval = 3.0, start = 1.5 }, -- Serpent Sting (ticks)
    { id = 6603, min = 10, max = 14, interval = 2.4, start = 0.5 }, -- Attack
    { id = 2973, min = 20, max = 26, interval = 7.0, start = 3.0 }, -- Raptor Strike
    { id = 2643, min = 25, max = 32, interval = 10.0, start = 4.0 }, -- Multi-Shot
}

local state = { active = false, running = false, t = 0, length = 30, scale = 1, spells = {} }
local driver = CreateFrame("Frame")

local function Step(elapsed)
    state.t = state.t + elapsed
    local hit = false
    for _, s in ipairs(state.spells) do
        while s.nextHit <= state.t do
            s.total = s.total + math.random(s.def.min, s.def.max) * state.scale
            s.nextHit = s.nextHit + s.def.interval * (0.85 + 0.3 * math.random())
            hit = true
        end
    end
    if hit then ns.SpellMeter.MarkDirty() end
    if state.t >= state.length then
        state.running = false
        driver:SetScript("OnUpdate", nil)
        ns.SpellMeter.MarkDirty()
        ns.Print(("DEMO fight finished (%ds). Showing result; /sm test again to clear."):format(state.length))
    end
end

function Demo.IsActive() return state.active end
function Demo.IsRunning() return state.running end

function Demo.Start(length, scale)
    state.length = length
    state.scale = scale
    state.t = 0
    state.spells = {}
    for _, def in ipairs(SPELLS) do
        state.spells[#state.spells + 1] = { def = def, total = 0, nextHit = def.start }
    end
    state.active = true
    state.running = true
    ns.SpellMeter.ResetBars()
    ns.SpellMeter.Show()
    ns.SpellMeter.MarkDirty()
    if ns.WidgetManager then ns.WidgetManager.OnDemoChanged() end
    driver:SetScript("OnUpdate", function(_, elapsed) Step(elapsed) end)
    ns.Print(("DEMO fight started: %ds%s. Numbers are fake. /sm test to stop."):format(
        length, scale > 1 and ", large numbers" or ""))
end

function Demo.Stop(reason)
    if not state.active then return end
    state.active = false
    state.running = false
    driver:SetScript("OnUpdate", nil)
    ns.SpellMeter.ResetBars()
    ns.SpellMeter.MarkDirty()
    if ns.WidgetManager then ns.WidgetManager.OnDemoChanged() end
    ns.Print("DEMO cleared" .. (reason and (" (" .. reason .. ")") or "") .. ".")
end

-- Same shape as APIAdapter.Snapshot, all readable.
function Demo.Snapshot()
    local t = state.t
    local dur = math.floor(t)
    local list, total = {}, 0
    for _, s in ipairs(state.spells) do
        if s.total > 0 then
            list[#list + 1] = {
                spellID = s.def.id,
                totalAmount = s.total,
                amountPerSecond = s.total / math.max(t, 0.1),
            }
            total = total + s.total
        end
    end
    table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    local _, classFilename = UnitClass("player")
    return {
        demo = true,
        duration = dur,
        hasPlayer = true,
        classFilename = classFilename,
        dps = total / math.max(t, 1),
        total = total,
        max = list[1] and list[1].totalAmount or 0,
        spells = list,
        spellCount = #list,
    }
end

-- /sm test [seconds] [big]
function Demo.Toggle(args)
    if state.active then
        Demo.Stop()
        return
    end
    if InCombatLockdown() then
        ns.Print("Can't start a DEMO fight while in real combat.")
        return
    end
    local length, scale = 30, 1
    for word in (args or ""):gmatch("%S+") do
        if word:lower() == "big" then
            scale = 250
        elseif tonumber(word) then
            length = math.max(5, math.min(300, math.floor(tonumber(word))))
        end
    end
    Demo.Start(length, scale)
end
