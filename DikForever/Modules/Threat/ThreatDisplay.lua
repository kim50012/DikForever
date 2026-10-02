-- 위협 표시 창·행·이벤트·갱신·설정 반영, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("threat")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local MODULE_ID = "threat"
local REFRESH_MIN = 0.1
local POLL_TICK = 0.5

local ROW_H = 16
local ROW_GAP = 2
local PCT_W = 40
local STATUS_W = 76
local DEFAULT_HEADER_H = 14
local DEFAULT_WIDTH = 200
local DEFAULT_BG_ALPHA = 0.8
local MAX_ROWS = 5

local active = false
local support = {}
local hud = nil
local body = nil
local header = nil
local measure = nil
local eventFrame = nil
local rows = {}
local rowCount = 1
local dirty = true
local inCombat = false
local hiddenStreak = 0
local unavailableNotified = false
local secretPercentFailed = false
local partialNotified = false
local missingList = {}
local sinceRefresh = REFRESH_MIN
local pollAcc = 0

-- 숫자 설정 조회, dik, 2026-10-01
local function GetNumber(key, default)
    local value = ns.GetSetting(MODULE_ID, key)
    if type(value) ~= "number" then
        return default
    end
    return value
end

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting(MODULE_ID, key) == true
end

-- 위협 % 칸 표시 여부, dik, 2026-10-01
local function IsPercentShown()
    return IsOn("showPercent") and support.percent == true
end

-- 부분 안내 목록에 이름 추가(중복 제외), dik, 2026-10-01
local function AddMissing(name)
    if type(name) ~= "string" then
        return
    end
    for i = 1, #missingList do
        if missingList[i] == name then
            return
        end
    end
    missingList[#missingList + 1] = name
end

-- 부분 안내 세션 1회 출력, dik, 2026-10-01
local function ReportPartial()
    if partialNotified or #missingList == 0 then
        return
    end
    partialNotified = true
    ns.Print(L.MSG_THREAT_PARTIAL:format(ns.FormatMissingAPIs(missingList)))
end

-- secret 가능 이름 글자 설정(nil 이면 대체 글자), dik, 2026-10-01
local function SetSecretLabel(fs, name)
    local text = ns.CombatHud.NameText(name)
    if ns.IsSecret(text) then
        fs:SetText(text)
    elseif text == nil then
        fs:SetText(L.VALUE_UNKNOWN)
    else
        fs:SetText(text)
    end
end

-- 행 생성, dik, 2026-10-01
local function CreateRow()
    local row = {}
-- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    row.bar = Widgets.CreateBar(body, { height = ROW_H, readable = true })
    local overlay = CreateFrame("Frame", nil, row.bar)
    overlay:SetAllPoints(row.bar)
    overlay:SetFrameLevel(row.bar:GetFrameLevel() + 4)
    row.overlay = overlay
    row.name = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.status = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "BAR_TEXT_DIM")
    row.status:SetJustifyH("RIGHT")
    row.status:SetWordWrap(false)
    row.status:SetWidth(STATUS_W)
    row.pct = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)
    row.pct:SetWidth(PCT_W)
    row.bar:Hide()
    return row
end

-- 행 조회(없으면 생성), dik, 2026-10-01
local function GetRow(index)
    if not rows[index] then
        rows[index] = CreateRow()
    end
    return rows[index]
end

-- 창 크기·행 앵커 재배치, dik, 2026-10-01
local function Relayout()
    if not active then
        return
    end
    local pad = Theme.PAD / 3
    local half = Theme.GAP / 2
    local width = GetNumber("frameWidth", DEFAULT_WIDTH)
    local headerH = math.ceil(measure:GetStringHeight())
    if headerH <= 0 then
        headerH = DEFAULT_HEADER_H
    end
    local shown = IsPercentShown()
    hud:SetSize(width, ns.Threat.CalcHeight(rowCount, headerH, ROW_H, ROW_GAP, pad))

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", body, "TOPLEFT", pad, -pad)
    header:SetPoint("TOPRIGHT", body, "TOPRIGHT", -pad, -pad)

    for k = 1, math.max(rowCount, #rows) do
        if k <= rowCount then
            local row = GetRow(k)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("TOPLEFT", body, "TOPLEFT", pad, -(pad + headerH + ROW_GAP + (k - 1) * (ROW_H + ROW_GAP)))
            row.bar:SetWidth(math.max(width - pad * 2, 1))
            row.bar:SetHeight(ROW_H)

            row.pct:ClearAllPoints()
            row.status:ClearAllPoints()
            row.name:ClearAllPoints()
            if shown then
                row.pct:SetPoint("RIGHT", row.overlay, "RIGHT", -half, 0)
                row.pct:Show()
                row.status:SetPoint("RIGHT", row.pct, "LEFT", -half, 0)
            else
                row.pct:Hide()
                row.status:SetPoint("RIGHT", row.overlay, "RIGHT", -half, 0)
            end
            row.name:SetPoint("LEFT", row.overlay, "LEFT", half, 0)
            row.name:SetPoint("RIGHT", row.status, "LEFT", -half, 0)
            row.bar:Show()
        elseif rows[k] then
            rows[k].bar:Hide()
        end
    end
end

-- % 글자 채우기(보일 때만 호출), dik, 2026-10-01
local function FillPercentText(row, pct, pMode)
    local text = ns.Threat.PercentText(pct, pMode)
    if text then
        row.pct:SetText(text)
        return
    end
    if secretPercentFailed then
        row.pct:SetText(L.VALUE_UNKNOWN)
        return
    end
    local ok = xpcall(function()
        row.pct:SetFormattedText(L.FMT_COMBATHUD_PERCENT, pct)
    end, geterrorhandler())
    if not ok then
        secretPercentFailed = true
        ns.Print(L.MSG_THREAT_PERCENT_FAILED)
        row.pct:SetText(L.VALUE_UNKNOWN)
    end
end

-- 행 채우기(상태 모드·% 모드·표시 여부 반환), dik, 2026-10-01
local function FillRow(row, unit, shown)
    local T = ns.Threat
    if unit == "player" then
        row.name:SetText(L.THREAT_ME)
    else
        SetSecretLabel(row.name, T.ReadName(unit))
    end

    local status, sMode = T.ReadSituation(unit, "target")
    local pct, pMode = nil, "off"
    if shown then
        pct, pMode = T.ReadPercent(unit, "target")
    end

    row.status:SetText(T.StatusText(status, sMode))
    -- 바 위 흐린 글자 보정, dik, 2026-10-02
    local statusToken = T.StatusTextToken(status, sMode)
    if statusToken == "TEXT_DIM" then
        statusToken = "BAR_TEXT_DIM"
    end
    row.status:SetTextColor(Theme.GetColor(statusToken))

    local r, g, b, token = T.StatusColor(status, sMode)
    if r then
        row.bar:SetColor(r, g, b)
    else
        row.bar:SetColorToken(token)
    end

    row.bar:SetRange(0, T.PERCENT_MAX)
    if shown then
        row.bar:SetValue(ns.CombatHud.BarValue(pct))
        FillPercentText(row, pct, pMode)
    else
        row.bar:SetValue(0)
    end
    return sMode, pMode
end

-- 전체 채우기, dik, 2026-10-01
local function Fill()
    local T = ns.Threat
    local exists, canAttack, name = T.ReadTarget()
    if not T.ShouldShowBody(exists, canAttack, inCombat, IsOn("onlyInCombat")) then
        body:Hide()
        return
    end
    body:Show()
    SetSecretLabel(header, name)

    local units = T.BuildUnitList(IsOn("showParty"))
    local count = math.min(#units, MAX_ROWS)
    if count ~= rowCount then
        rowCount = count
        Relayout()
    end

    local shown = IsPercentShown()
    for k = 1, count do
        local sMode, pMode = FillRow(GetRow(k), units[k], shown)
        if k == 1 then
            local mode = T.RowMode(sMode, pMode, shown)
            hiddenStreak = T.NextHiddenStreak(hiddenStreak, mode, inCombat)
            if hiddenStreak >= T.HIDDEN_STREAK_LIMIT and not unavailableNotified then
                unavailableNotified = true
                ns.Print(L.MSG_THREAT_UNAVAILABLE)
            end
        end
    end
end

-- 갱신 주기 처리(이벤트 프레임 OnUpdate), dik, 2026-10-01
local function OnUpdate(_, elapsed)
    if not active then
        return
    end
    sinceRefresh = sinceRefresh + elapsed
    if inCombat and body:IsShown() then
        pollAcc = pollAcc + elapsed
        if pollAcc >= POLL_TICK then
            pollAcc = 0
            dirty = true
        end
    else
        pollAcc = 0
    end
    if dirty and sinceRefresh >= REFRESH_MIN then
        dirty = false
        sinceRefresh = 0
        Fill()
    end
end

-- 이벤트 처리(인자 미사용), dik, 2026-10-01
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Threat.ResetFailures()
    end
    dirty = true
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
    for _, name in ipairs(ns.Threat.EVENTS) do
        if not pcall(eventFrame.RegisterEvent, eventFrame, name) then
            AddMissing(name)
        end
    end
end

-- 창·본문·머리줄 생성, dik, 2026-10-01
local function BuildWindow()
    hud = ns.Display.CreateHudFrame(MODULE_ID, "main", ns.Threat.HUD_MAIN)
    body = CreateFrame("Frame", nil, hud, "BackdropTemplate")
    body:SetAllPoints(hud)
    Theme.ApplyBackdrop(body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    measure = Widgets.CreateLabel(body, "FONT_SMALL", "TEXT")
    measure:SetText("0")
    measure:Hide()

    header = Widgets.CreateLabel(body, "FONT_SMALL", "TEXT")
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)

    GetRow(1)
    Relayout()
    hud:Show()
    hud:SetHudActive(true)
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    active = true

    local missing
    support, missing = ns.Threat.GetFeatureSupport({ percent = IsOn("showPercent") })
    for i = 1, #missing do
        AddMissing(missing[i])
    end

    inCombat = ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true
    BuildWindow()
    CreateEventFrame()
    ReportPartial()
    dirty = true
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            Relayout()
            dirty = true
        end
        return
    end
    if scope ~= MODULE_ID then
        return
    end
    if key == "frameWidth" or key == "showPercent" then
        Relayout()
        dirty = true
        if key == "showPercent" and value == true and support.percent ~= true then
            AddMissing("UnitDetailedThreatSituation")
            ReportPartial()
        end
    elseif key == "bgAlpha" then
        Theme.ApplyBackdrop(body, "BG", "BORDER", value)
    elseif key == "showParty" or key == "onlyInCombat" then
        dirty = true
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
