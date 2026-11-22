-- SoloMetrics: minimap button + Addon Compartment entry
-- Left-click: settings. Right-click: show/hide meter. Drag: move around the
-- minimap edge (angle saved). No external library required.

local _, ns = ...
local MB = {}
ns.MinimapButton = MB

MB.ICON = "Interface\\AddOns\\SoloMetrics\\Assets\\Icons\\SoloMetrics_Minimap_64"

local btn

local function Cfg() return ns.db.meter end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Solo|cff40c7b8Metrics|r  v" .. ns.VERSION)
    GameTooltip:AddLine("Left-click: open settings", 0.85, 0.85, 0.85)
    GameTooltip:AddLine("Right-click: show / hide meter", 0.85, 0.85, 0.85)
    if owner == btn then
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function OnClick(button)
    if button == "RightButton" then
        ns.SpellMeter.Toggle()
    else
        ns.Config.Toggle()
    end
end

local function UpdatePosition()
    local angle = math.rad(Cfg().minimapAngle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local r = (Minimap:GetWidth() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- push onto the square's edge
        x = math.max(-1, math.min(1, x * 1.414))
        y = math.max(-1, math.min(1, y * 1.414))
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    px, py = px / s, py / s
    Cfg().minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function Create()
    btn = CreateFrame("Button", "SoloMetricsMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    -- The SoloMetrics icon is round with its own metal ring, so it is drawn
    -- full-size without the standard tracking border.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(MB.ICON)
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(MB.ICON)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)

    btn:SetScript("OnClick", function(_, button) OnClick(button) end)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
end

function MB.Update()
    if not btn then Create() end
    UpdatePosition()
    btn:SetShown(Cfg().minimapShown ~= false)
end

function MB.Init()
    if not Minimap then return end
    MB.Update()
end

---------------------------------------------------------------------------
-- Addon Compartment (TOC: AddonCompartmentFunc*). Harmless if unsupported.
---------------------------------------------------------------------------
function SoloMetrics_OnAddonCompartmentClick(_, buttonName)
    OnClick(buttonName)
end

function SoloMetrics_OnAddonCompartmentEnter(_, menuButtonFrame)
    if menuButtonFrame then ShowTooltip(menuButtonFrame) end
end

function SoloMetrics_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
