-- 어그로 미터 창(HUD·머리줄·줄·이벤트·갱신), dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("aggroMeter")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

-- 모듈 id, dik, 2026-10-01
local MODULE_ID = "aggroMeter"

-- 머리줄 높이·줄 간격·잠금 버튼 폭, dik, 2026-10-01
local HEADER_H = 18
local ROW_GAP = 1
local LOCK_BTN_W = 36
local RANK_NAME_GAP = 2
local PCT_W = 40

-- 갱신 주기·기본값·상한, dik, 2026-10-01
local REFRESH_MIN = 0.2
local POLL_TICK = 0.5
local ROWS_CAP = 20
local DEFAULT_MAX_ROWS = 10
local DEFAULT_WIDTH = 220
local DEFAULT_BAR_HEIGHT = 16
local DEFAULT_BG_ALPHA = 0.8

-- 창 상태·갱신 상태 변수, dik, 2026-10-01
local active = false
local hud = nil
local body = nil
local header = nil
local modeText = nil
local statusText = nil
local lockButton = nil
local eventFrame = nil
local rows = {}
local dirty = true
local inCombat = false
local pollMode = false
local pctFailed = false
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

-- 표시 줄 수 설정(1~20 보정), dik, 2026-10-01
local function GetMaxRows()
    return math.min(math.max(math.floor(GetNumber("maxRows", DEFAULT_MAX_ROWS)), 1), ROWS_CAP)
end

-- 이벤트 일괄 등록, 성공 개수 반환, dik, 2026-10-01
local function RegisterEvents(frame, names)
    local okCount = 0
    for _, name in ipairs(names) do
        if pcall(frame.RegisterEvent, frame, name) then
            okCount = okCount + 1
        end
    end
    return okCount
end

-- secret 가능 이름 글자 설정(nil 이면 대체 글자), dik, 2026-10-01
local function SetNameLabel(fs, name)
    local text = ns.CombatHud.NameText(name)
    if not ns.IsSecret(text) and text == nil then
        text = L.VALUE_UNKNOWN
    end
    fs:SetText(text)
end

-- 잠금 버튼 글자·색 갱신, dik, 2026-10-01
local function UpdateLockLabel()
    if IsOn("locked") then
        lockButton.label:SetText(L.HUD_LOCK_ON)
        lockButton.label:SetTextColor(Theme.GetColor("TEXT_DIM"))
    else
        lockButton.label:SetText(L.HUD_LOCK_OFF)
        lockButton.label:SetTextColor(Theme.GetColor("ACCENT"))
    end
end

-- 줄 생성, dik, 2026-10-01
local function CreateRow(barHeight)
    local half = Theme.GAP / 2
    local row = {}
-- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    row.bar = Widgets.CreateBar(body, { height = barHeight, readable = true })
    row.overlay = CreateFrame("Frame", nil, row.bar)
    row.overlay:SetAllPoints(row.bar)
    row.overlay:SetFrameLevel(row.bar:GetFrameLevel() + 4)

    row.rank = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "BAR_TEXT_DIM")
    row.rank:SetPoint("LEFT", row.overlay, "LEFT", half, 0)
    row.rank:SetWordWrap(false)

    row.pct = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.pct:SetPoint("RIGHT", row.overlay, "RIGHT", -half, 0)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)
    row.pct:SetWidth(PCT_W)

    row.name = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", RANK_NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.pct, "LEFT", -half, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.bar:Hide()
    return row
end

-- 창 크기·줄 앵커 재배치, dik, 2026-10-01
local function Layout()
    if not active then
        return
    end
    local pad = Theme.PAD / 3
    local width = GetNumber("width", DEFAULT_WIDTH)
    local barHeight = GetNumber("barHeight", DEFAULT_BAR_HEIGHT)
    local maxRows = GetMaxRows()

    hud:SetSize(width, ns.AggroMeter.CalcHeight(HEADER_H, barHeight, maxRows, ROW_GAP, pad))
    lockButton:SetSize(LOCK_BTN_W, HEADER_H)

    while #rows < maxRows do
        rows[#rows + 1] = CreateRow(barHeight)
    end
    for k, row in ipairs(rows) do
        if k <= maxRows then
            row.bar:SetSize(math.max(width - pad * 2, 1), barHeight)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("TOPLEFT", body, "TOPLEFT", pad, -(pad + HEADER_H + pad + (k - 1) * (barHeight + ROW_GAP)))
        else
            row.bar:Hide()
        end
    end

    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", body, "TOPLEFT", pad, -(pad + HEADER_H + pad))
    statusText:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -pad, pad)
end

-- 줄 전체 숨김, dik, 2026-10-01
local function HideRows()
    for _, row in ipairs(rows) do
        row.bar:Hide()
    end
end

-- % 글자 채우기, dik, 2026-10-01
local function FillPercent(row, scaled, mode)
    local text = ns.AggroMeter.PercentText(scaled, mode)
    if not ns.IsSecret(text) and type(text) == "string" then
        row.pct:SetText(text)
        return
    end
    if pctFailed then
        row.pct:SetText(L.VALUE_UNKNOWN)
        return
    end
    local ok = xpcall(function()
        row.pct:SetFormattedText(L.FMT_COMBATHUD_PERCENT, scaled)
    end, geterrorhandler())
    if not ok then
        pctFailed = true
        row.pct:SetText(L.VALUE_UNKNOWN)
    end
end

-- 줄 1개 채우기, dik, 2026-10-01
local function FillRow(row, position, entry, mode, useClassColor)
    row.rank:SetText(ns.AggroMeter.RankLabel(position, mode))

    local name = ns.DamageMeter.ShortName(UnitName(entry.unit))
    if not ns.IsSecret(name) and name == nil then
        name = L.VALUE_UNKNOWN
    end
    row.name:SetText(name)

    row.bar:SetRange(0, 100)
    row.bar:SetValue(ns.CombatHud.BarValue(entry.scaled))
    FillPercent(row, entry.scaled, entry.mode)

    local r, g, b
    if useClassColor then
        local _, classFile = UnitClass(entry.unit)
        r, g, b = ns.DamageMeter.GetClassColor(classFile)
    end
    if r then
        row.bar:SetColor(r, g, b)
    else
        row.bar:SetColorToken("ACCENT")
    end
    row.bar:Show()
end

-- 레이드 여부 조회(secret·미존재는 false), dik, 2026-10-01
local function ReadInRaid()
    if not ns.HasAPI("IsInRaid") then
        return false
    end
    local value = IsInRaid()
    if ns.IsSecret(value) then
        return false
    end
    return value == true
end

-- 그룹 인원 수 조회(secret·미존재는 nil), dik, 2026-10-01
local function ReadGroupCount()
    if not ns.HasAPI("GetNumGroupMembers") then
        return nil
    end
    local value = GetNumGroupMembers()
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

-- 대상 존재·공격 가능 조회, dik, 2026-10-01
local function ReadTargetState()
    local exists = UnitExists("target")
    if ns.IsSecret(exists) then
        exists = true
    end
    local canAttack = nil
    if ns.HasAPI("UnitCanAttack") then
        canAttack = UnitCanAttack("player", "target")
        if ns.IsSecret(canAttack) then
            canAttack = nil
        end
    end
    return exists, canAttack
end

-- 모드 글자 설정, dik, 2026-10-01
local function SetModeText(text)
    if text then
        modeText:SetText(text)
        modeText:Show()
    else
        modeText:SetText("")
        modeText:Hide()
    end
end

-- 전체 채우기, dik, 2026-10-01
local function Fill()
    local exists, canAttack = ReadTargetState()
    local locked = IsOn("locked")
    local show = ns.Threat.ShouldShowBody(exists, canAttack, inCombat, IsOn("onlyInCombat")) or not locked
    if not show then
        body:Hide()
        return
    end
    body:Show()

    if exists ~= true or canAttack == false then
        header:SetText(L.AGGRO_NO_TARGET)
        SetModeText(nil)
        statusText:Hide()
        HideRows()
        return
    end
    SetNameLabel(header, UnitName("target"))

    local units = ns.AggroMeter.BuildGroupUnits(ReadInRaid(), ReadGroupCount())
    local entries = {}
    for i = 1, #units do
        local u = units[i]
        local scaled, value, mode = ns.AggroMeter.ReadThreat(u, "target")
        entries[#entries + 1] = { unit = u, index = i, scaled = scaled, value = value, mode = mode }
    end
    local ordered, mode = ns.AggroMeter.RankRows(entries)

    if mode == "empty" or mode == "error" then
        HideRows()
        SetModeText(nil)
        if mode == "empty" then
            statusText:SetText(L.AGGRO_EMPTY)
        else
            statusText:SetText(L.AGGRO_ERROR)
        end
        statusText:Show()
        return
    end

    statusText:Hide()
    if mode == "group" then
        SetModeText(L.AGGRO_MODE_GROUP)
    else
        SetModeText(nil)
    end

    local maxRows = GetMaxRows()
    local useClassColor = IsOn("classColor")
    local placed = math.min(#ordered, maxRows)
    for k = 1, placed do
        FillRow(rows[k], k, ordered[k], mode, useClassColor)
    end
    for k = placed + 1, #rows do
        rows[k].bar:Hide()
    end
end

-- 갱신 주기 처리(이벤트 프레임 OnUpdate), dik, 2026-10-01
local function OnUpdate(_, elapsed)
    if not active then
        return
    end
    sinceRefresh = sinceRefresh + elapsed
    if pollMode or (inCombat and body:IsShown()) then
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

-- 이벤트 처리(이벤트 이름만 사용), dik, 2026-10-01
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.AggroMeter.ResetFailures()
    end
    dirty = true
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
    local okCount = RegisterEvents(eventFrame, ns.AggroMeter.EVENTS)
    pollMode = okCount < #ns.AggroMeter.EVENTS
end

-- 창·본문·머리줄 생성, dik, 2026-10-01
local function BuildWindow()
    local pad = Theme.PAD / 3
    local half = Theme.GAP / 2
    hud = ns.Display.CreateHudFrame(ns.AggroMeter.MODULE_ID, "main", ns.AggroMeter.HUD_MAIN)
    body = CreateFrame("Frame", nil, hud, "BackdropTemplate")
    body:SetAllPoints(hud)
    Theme.ApplyBackdrop(body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    lockButton = Widgets.CreateButton(body, "", function()
        ns.SetSetting(MODULE_ID, "locked", not IsOn("locked"))
    end)
    lockButton:SetPoint("TOPRIGHT", body, "TOPRIGHT", -pad, -pad)
    lockButton.label:SetFontObject(Theme.GetFont("FONT_SMALL"))
    if Widgets.SetTooltip then
        Widgets.SetTooltip(lockButton, L.HUD_LOCK_TIP_TITLE, L.HUD_LOCK_TIP)
    end

    modeText = Widgets.CreateLabel(body, "FONT_SMALL", "TEXT_DIM")
    modeText:SetPoint("RIGHT", lockButton, "LEFT", -half, 0)
    modeText:SetJustifyH("RIGHT")
    modeText:SetWordWrap(false)
    modeText:Hide()

    header = Widgets.CreateLabel(body, "FONT_SMALL", "TEXT")
    header:SetPoint("LEFT", body, "TOPLEFT", pad, -(pad + HEADER_H / 2))
    header:SetPoint("RIGHT", modeText, "LEFT", -half, 0)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)

    statusText = Widgets.CreateLabel(body, "FONT_SMALL", "TEXT_DIM")
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    statusText:SetWordWrap(true)
    statusText:Hide()

    Layout()
    hud:ApplySavedPosition()
    hud:Show()
    hud:SetHudActive(true)
    hud:SetDragUnlocked(not IsOn("locked"))
    UpdateLockLabel()
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    active = true
    inCombat = ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true
    BuildWindow()
    CreateEventFrame()
    dirty = true
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            Layout()
            dirty = true
        end
        return
    end
    if scope ~= MODULE_ID then
        return
    end
    if key == "width" or key == "maxRows" or key == "barHeight" then
        Layout()
        dirty = true
    elseif key == "bgAlpha" then
        Theme.ApplyBackdrop(body, "BG", "BORDER", value)
    elseif key == "classColor" or key == "onlyInCombat" then
        dirty = true
    elseif key == "locked" then
        hud:SetDragUnlocked(value ~= true)
        UpdateLockLabel()
        dirty = true
        sinceRefresh = REFRESH_MIN
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
