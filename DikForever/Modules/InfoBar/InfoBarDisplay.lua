-- 상단 정보바 화면(HUD·메뉴 버튼·정보 항목·배치), dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("infoBar")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme

local BAR_EXTRA_H = 4
local FALLBACK_FONT_H = 12
local BUTTON_V_MARGIN = 2

-- 동작 차단 이벤트는 코어 공통 처리로 이전, dik, 2026-10-02
local EVENT_NAMES = {
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
}

local active = false
local partialShown = false
local inCombat = false
local layouting = false
local hud = nil
local panel = nil
local eventFrame = nil
local buttons = {}
local providerEntries = {}
local clockEntries = {}
local menuMissing = {}
local eventMissing = {}
local Relayout

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting("infoBar", key) == true
end

-- 이벤트 등록 헬퍼, dik, 2026-10-01
local function RegisterEventSafe(frame, name)
    local ok = pcall(frame.RegisterEvent, frame, name)
    if not ok then
        eventMissing[#eventMissing + 1] = name
    end
    return ok
end

-- 바 높이, dik, 2026-10-01
local function GetBarHeight()
    local fontObj = Theme.GetFont("FONT_SMALL")
    local size
    if fontObj and fontObj.GetFont then
        local _, fontSize = fontObj:GetFont()
        size = fontSize
    end
    if type(size) ~= "number" then
        size = FALLBACK_FONT_H
    end
    return math.max(Theme.STATUSBAR_H, math.ceil(size) + BAR_EXTRA_H)
end

-- 정보 항목 켜기/끄기, dik, 2026-10-01
local function SyncItem(entry, on)
    if on then
        if not entry.active then
            entry.supported = entry.item:SetActive(true) == true
            entry.active = true
        end
    else
        if entry.active then
            entry.item:SetActive(false)
        end
        entry.active = false
        entry.supported = true
    end
end

-- 시계 항목 조회(필요 시 생성), dik, 2026-10-01
local function GetClockEntry(providerId)
    local entry = clockEntries[providerId]
    if not entry then
        entry = { provider = providerId, active = false, supported = true }
        entry.item = ns.Display.CreateInfoText(panel, providerId, ns.InfoBar.OWNER, function()
            Relayout()
        end)
        clockEntries[providerId] = entry
    end
    return entry
end

-- 시계 항목 동기화, dik, 2026-10-01
local function SyncClock()
    local target = ns.InfoBar.GetClockProvider(ns.GetSetting("infoBar", "clockMode"))
    local on = IsOn("showClock")
    for id, entry in pairs(clockEntries) do
        if id ~= target or not on then
            SyncItem(entry, false)
        end
    end
    if on then
        SyncItem(GetClockEntry(target), true)
    end
end

-- 현재 시계 항목, dik, 2026-10-01
local function GetCurrentClock()
    local target = ns.InfoBar.GetClockProvider(ns.GetSetting("infoBar", "clockMode"))
    return clockEntries[target]
end

-- 버튼 상태 갱신, dik, 2026-10-01
local function UpdateButtons()
    local enable = not ns.InfoBar.IsBlocked() and not inCombat
    local moveOn = (ns.Display and ns.Display.IsMoveMode and ns.Display.IsMoveMode()) == true
    for _, entry in ipairs(buttons) do
        -- 내부 버튼은 항상 활성·이동 버튼만 ACCENT, dik, 2026-10-01
        if entry.internal then
            entry.btn:Enable()
            local color = "TEXT"
            if entry.key == "move" and moveOn then
                color = "ACCENT"
            elseif inCombat and entry.combatAllowed ~= true then
                color = "TEXT_DIM"
            end
            entry.btn.label:SetTextColor(Theme.GetColor(color))
        elseif enable then
            entry.btn:Enable()
            entry.btn.label:SetTextColor(Theme.GetColor("TEXT"))
        else
            entry.btn:Disable()
            entry.btn.label:SetTextColor(Theme.GetColor("TEXT_DIM"))
        end
    end
end

-- 바 재배치, dik, 2026-10-01
function Relayout()
    if not active or not hud or layouting then
        return
    end
    layouting = true
    local barH = GetBarHeight()
    local frames = {}
    local widths = {}
    local all = {}

    for _, entry in ipairs(buttons) do
        entry.btn:SetSize(math.ceil(entry.btn.label:GetStringWidth()) + Theme.GAP * 2, barH - BUTTON_V_MARGIN)
        all[#all + 1] = entry.btn
    end
    for _, entry in pairs(clockEntries) do
        all[#all + 1] = entry.item
    end
    for _, entry in pairs(providerEntries) do
        all[#all + 1] = entry.item
    end

    for _, def in ipairs(ns.InfoBar.ELEMENTS) do
        if def.kind == "menu" then
            if IsOn(def.key) then
                for _, entry in ipairs(buttons) do
                    frames[#frames + 1] = entry.btn
                    widths[#widths + 1] = entry.btn:GetWidth()
                end
            end
        else
            local entry
            if def.kind == "clock" then
                entry = GetCurrentClock()
            else
                entry = providerEntries[def.key]
            end
            if entry and entry.active and entry.supported then
                frames[#frames + 1] = entry.item
                widths[#widths + 1] = entry.item:GetTextWidth()
            end
        end
    end

    local xs, placed, total = ns.Chat.LayoutInfo(widths, math.floor(UIParent:GetWidth()), Theme.GAP, Theme.PAD / 2)
    local shown = {}
    for i, frame in ipairs(frames) do
        if i <= placed then
            frame:ClearAllPoints()
            frame:SetPoint("LEFT", panel, "LEFT", xs[i], 0)
            frame:Show()
            shown[frame] = true
        end
    end
    for _, frame in ipairs(all) do
        if not shown[frame] then
            frame:Hide()
        end
    end

    if placed > 0 then
        hud:SetSize(total, barH)
        hud:Show()
    else
        hud:Hide()
    end
    layouting = false
end

-- 없는 요소 안내(세션 1회), dik, 2026-10-01
local function ShowPartial()
    if partialShown then
        return
    end
    local list = {}
    local seen = {}
    local function add(name)
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    for _, name in ipairs(menuMissing) do
        add(name)
    end
    local function addUnsupported(entry)
        if entry.active and not entry.supported then
            local _, missing = ns.InfoText.IsSupported(entry.provider)
            for _, name in ipairs(missing or {}) do
                add(name)
            end
        end
    end
    for _, def in ipairs(ns.InfoBar.ELEMENTS) do
        if def.provider then
            addUnsupported(providerEntries[def.key])
        end
    end
    for _, entry in pairs(clockEntries) do
        addUnsupported(entry)
    end
    for _, name in ipairs(eventMissing) do
        add(name)
    end
    if #list > 0 then
        partialShown = true
        ns.Print(L.MSG_INFOBAR_PARTIAL:format(ns.FormatMissingAPIs(list)))
    end
end

-- 메뉴 버튼 생성, dik, 2026-10-01
local function CreateMenuButtons()
    local resolved, missing = ns.InfoBar.ResolveMenu()
    menuMissing = missing or {}
    for _, def in ipairs(resolved) do
        local btn = ns.Widgets.CreateButton(panel, def.label, function()
            ns.InfoBar.OpenMenu(def.key)
        end)
        btn.label:SetFontObject(Theme.GetFont("FONT_SMALL"))
        btn:Hide()
        -- 전투 중 허용 여부 기록 추가, dik, 2026-10-01
        buttons[#buttons + 1] = {
            key = def.key,
            internal = def.internal == true,
            combatAllowed = def.combatAllowed == true,
            btn = btn,
        }
    end
end

-- 이벤트 프레임 생성, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    -- 동작 차단 분기 제거(INFOBAR_BLOCKED 구독으로 이전), dik, 2026-10-02
    eventFrame:SetScript("OnEvent", function(_, event)
        if not active then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            UpdateButtons()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            UpdateButtons()
        else
            Relayout()
        end
    end)
    for _, name in ipairs(EVENT_NAMES) do
        RegisterEventSafe(eventFrame, name)
    end
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled("infoBar") and ns.IsModuleSupported("infoBar")) then
        return
    end
    active = true
    inCombat = ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true

    local hb = ns.InfoBar.HUD_BAR
    hud = ns.Display.CreateHudFrame("infoBar", hb.key, {
        label = L.HUD_LABEL_INFOBAR,
        point = hb.point,
        relativePoint = hb.relativePoint,
        x = hb.x,
        y = hb.y,
        strata = hb.strata,
    })
    hud:SetHudActive(true)
    panel = ns.Widgets.CreatePanel(hud)
    panel:SetAllPoints(hud)
    Theme.ApplyBackdrop(panel, "BG", "BORDER", ns.GetSetting("infoBar", "barAlpha"))

    CreateMenuButtons()

    for _, def in ipairs(ns.InfoBar.ELEMENTS) do
        if def.provider then
            local entry = { key = def.key, provider = def.provider, active = false, supported = true }
            entry.item = ns.Display.CreateInfoText(panel, def.provider, ns.InfoBar.OWNER, function()
                Relayout()
            end)
            providerEntries[def.key] = entry
            SyncItem(entry, IsOn(def.key))
        end
    end
    SyncClock()

    CreateEventFrame()
    UpdateButtons()
    Relayout()
    ShowPartial()
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            Relayout()
        end
        return
    end
    if scope ~= "infoBar" then
        return
    end

    if key == "barAlpha" then
        if type(value) == "number" then
            Theme.ApplyBackdrop(panel, "BG", "BORDER", value)
        end
    elseif key == "showClock" or key == "clockMode" then
        SyncClock()
        ShowPartial()
        Relayout()
    elseif key == "showMenu" then
        Relayout()
    else
        local entry = providerEntries[key]
        if entry then
            SyncItem(entry, IsOn(key))
            ShowPartial()
            Relayout()
        end
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
-- 이동 모드 변경 시 버튼 색 갱신, dik, 2026-10-01
ns.On("HUD_MOVE_MODE", function()
    if active then
        UpdateButtons()
    end
end)
-- 동작 차단 시 버튼 끄기 갱신, dik, 2026-10-02
ns.On("INFOBAR_BLOCKED", function()
    if active then
        UpdateButtons()
    end
end)
