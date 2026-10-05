-- 편집 모드 영역별 설정 창, dik, 2026-10-05
local addonName, ns = ...

local L = ns.L

ns.EditPanel = {}

-- 설정 창 크기·하단 영역 높이 상수, dik, 2026-10-05
local PANEL_W = 300
local PANEL_H = 380
local BOTTOM_H = 40
local CLOSE_BUTTON_W = 28

local panel
local bodyHost
local titleText
local moduleText
local resetButton
local currentId, currentKey
local bodies = {}
local activeBody

-- 설정 창 프레임 1회 생성, dik, 2026-10-05
local function BuildPanel()
    local theme = ns.Theme
    local widgets = ns.Widgets
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_W, PANEL_H)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    theme.ApplyBackdrop(frame, "BG", "BORDER")
    frame:Hide()

    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetHeight(theme.TITLEBAR_H)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    theme.ApplyBackdrop(bar, "PANEL", "PANEL")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local close = CreateFrame("Button", nil, bar)
    close:SetSize(CLOSE_BUTTON_W, theme.TITLEBAR_H - 1)
    close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    local hover = close:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(theme.GetColor("HOVER"))
    local mark = widgets.CreateLabel(close, "FONT_MENU", "TEXT_DIM")
    mark:SetPoint("CENTER", close, "CENTER", 0, 0)
    mark:SetText("X")
    close:SetScript("OnClick", function()
        ns.EditPanel.Close()
    end)

    titleText = widgets.CreateLabel(bar, "FONT_MENU", "TEXT")
    titleText:SetPoint("LEFT", bar, "LEFT", theme.PAD, 0)
    titleText:SetPoint("RIGHT", close, "LEFT", -theme.GAP, 0)
    titleText:SetWordWrap(false)

    moduleText = widgets.CreateLabel(frame, "FONT_SMALL", "TEXT_DIM")
    moduleText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", theme.PAD, -theme.GAP)
    moduleText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -theme.PAD, -theme.GAP)
    moduleText:SetWordWrap(false)

    local bottom = CreateFrame("Frame", nil, frame)
    bottom:SetHeight(BOTTOM_H)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    local line = bottom:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(theme.GetColor("BORDER"))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", bottom, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", bottom, "TOPRIGHT", 0, 0)

    resetButton = widgets.CreateButton(bottom, L.BUTTON_EDIT_RESET, function()
        local hud = currentId and ns.Display.GetHud(currentId, currentKey)
        if hud then
            hud:ResetPosition()
        end
    end)
    resetButton:SetPoint("LEFT", bottom, "LEFT", theme.PAD, 0)
    widgets.SetTooltip(resetButton, L.BUTTON_EDIT_RESET, L.TIP_EDIT_RESET)

    local closeButton = widgets.CreateButton(bottom, L.BUTTON_EDIT_CLOSE, function()
        ns.EditPanel.Close()
    end)
    closeButton:SetPoint("RIGHT", bottom, "RIGHT", -theme.PAD, 0)

    bodyHost = CreateFrame("Frame", nil, frame)
    bodyHost:SetPoint("TOPLEFT", moduleText, "BOTTOMLEFT", -theme.PAD, -theme.GAP)
    bodyHost:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)

    panel = frame
end

-- HUD 옆 위치 지정(오른쪽 우선·자리 없으면 왼쪽), dik, 2026-10-05
local function PlaceBeside(hud)
    local gap = ns.Theme.GAP
    local hudRight = hud:GetRight()
    local limit = UIParent:GetRight()
    local onRight = true
    if hudRight and limit then
        local rightEdge = hudRight * hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
        onRight = rightEdge + gap + PANEL_W <= limit
    end
    panel:ClearAllPoints()
    if onRight then
        panel:SetPoint("TOPLEFT", hud, "TOPRIGHT", gap, 0)
    else
        panel:SetPoint("TOPRIGHT", hud, "TOPLEFT", -gap, 0)
    end
    local left, bottom = panel:GetLeft(), panel:GetBottom()
    if left and bottom then
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    end
end

-- 설정 창 열기, dik, 2026-10-05
function ns.EditPanel.Open(moduleId, key)
    local hud, label = ns.Display.GetHud(moduleId, key)
    if not hud then
        return
    end
    if not panel then
        BuildPanel()
    end
    local cacheKey = moduleId .. ":" .. key
    local body = bodies[cacheKey]
    if not body then
        body = ns.SettingsUI.RenderHudSettings(bodyHost, moduleId, key)
        body:SetAllPoints(bodyHost)
        bodies[cacheKey] = body
    end
    if activeBody and activeBody ~= body then
        activeBody:Hide()
    end
    body:Show()
    activeBody = body
    currentId, currentKey = moduleId, key

    titleText:SetText(L.FMT_EDIT_PANEL_TITLE:format(label or key))
    local module = ns.GetModule(moduleId)
    moduleText:SetText(module and module.title or "")
    panel:Show()
    PlaceBeside(hud)
end

-- 설정 창 닫기, dik, 2026-10-05
function ns.EditPanel.Close()
    if panel then
        panel:Hide()
    end
end

-- 설정 창 표시 여부, dik, 2026-10-05
function ns.EditPanel.IsShown()
    return panel ~= nil and panel:IsShown()
end

-- 편집 영역 설정 창 열기 요청 처리, dik, 2026-10-05
ns.On("HUD_EDIT_OPEN", function(moduleId, key)
    ns.EditPanel.Open(moduleId, key)
end)

-- 편집 모드 종료 시 설정 창 닫기, dik, 2026-10-05
ns.On("HUD_MOVE_MODE", function(on)
    if not on then
        ns.EditPanel.Close()
    end
end)
