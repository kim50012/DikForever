-- 대상 거리 글자 HUD·이벤트·갱신, dik, 2026-10-02
local addonName, ns = ...

local module = ns.GetModule("range")
if not module then
    return
end

local L = ns.L

local MODULE_ID = "range"
local DEFAULT_SCALE = 1.4

local hud = nil
local fs = nil
local eventFrame = nil
local checkers = {}
local lastLower = nil
local lastUpper = nil
local hasValue = false
local shown = false
local tickAcc = 0
local noCheckerNotified = false
local built = false

-- 배율 설정 조회, dik, 2026-10-02
local function GetScale()
    local value = ns.GetSetting(MODULE_ID, "textScale")
    if type(value) ~= "number" then
        return DEFAULT_SCALE
    end
    return value
end

-- 마지막 표시값 초기화, dik, 2026-10-02
local function ResetLast()
    lastLower = nil
    lastUpper = nil
    hasValue = false
end

-- 글자 숨김(HUD 유지), dik, 2026-10-02
local function HideText()
    fs:Hide()
    shown = false
    ResetLast()
end

-- 거리 갱신(표시 판정 포함), dik, 2026-10-02
local function Refresh()
    local R = ns.Range
    if not R.ShouldShow() then
        HideText()
        return
    end
    if not shown then
        shown = true
        if #checkers == 0 and not noCheckerNotified then
            noCheckerNotified = true
            ns.Print(L.MSG_RANGE_NO_CHECKER)
        end
    end
    fs:Show()
    local probe = R.Probe(checkers, R.InCombat())
    local lower, upper = R.CalcBracket(probe)
    if hasValue and lower == lastLower and upper == lastUpper then
        return
    end
    hasValue = true
    lastLower = lower
    lastUpper = upper
    fs:SetText(R.Text(lower, upper))
    fs:SetTextColor(ns.Theme.GetColor(R.ColorToken(lower, upper)))
end

-- 이벤트 처리, dik, 2026-10-02
local function OnEvent(_, event, arg1)
    if event == "UNIT_FLAGS" then
        if ns.IsSecret(arg1) or arg1 ~= "target" then
            return
        end
    elseif event == "SPELLS_CHANGED" then
        checkers = ns.Range.BuildCheckers()
        ResetLast()
        return
    end
    Refresh()
end

-- 주기 갱신, dik, 2026-10-02
local function OnUpdate(_, elapsed)
    tickAcc = tickAcc + elapsed
    if tickAcc < ns.Range.UPDATE_INTERVAL then
        return
    end
    tickAcc = 0
    Refresh()
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-02
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame", nil, UIParent)
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
    for _, name in ipairs(ns.Range.EVENTS) do
        pcall(eventFrame.RegisterEvent, eventFrame, name)
    end
end

-- READY 초기화, dik, 2026-10-02
local function Initialize()
    if built then
        return
    end
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    built = true

    hud = ns.Display.CreateHudFrame(MODULE_ID, "main", ns.Range.HUD_MAIN)
    hud:SetSize(ns.Range.HUD_WIDTH, ns.Range.HUD_HEIGHT)
    hud:SetScale(GetScale())

    fs = hud:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(ns.Theme.GetFont("FONT_MENU"))
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    fs:SetShadowColor(ns.Theme.GetColor("TEXT_SHADOW"))
    fs:SetShadowOffset(1, -1)
    fs:Hide()

    hud:Show()
    hud:SetHudActive(true)

    checkers = ns.Range.BuildCheckers()
    CreateEventFrame()
    Refresh()
end

-- 설정 변경 처리, dik, 2026-10-02
local function OnSettingChanged(scope, key, value)
    if scope ~= MODULE_ID or key ~= "textScale" or not hud then
        return
    end
    if type(value) == "number" then
        hud:SetScale(value)
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
