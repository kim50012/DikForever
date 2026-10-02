-- 피해량 미터 창(HUD·머리줄·바 행·갱신), dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("damageMeter")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local MODULE_ID = "damageMeter"
local SEG_BTN_W = 56
-- 잠금 버튼 폭, dik, 2026-10-01
local LOCK_BTN_W = 36
local ROW_GAP = 1
local RANK_NAME_GAP = 2
local REFRESH_MIN = 0.5
local COMBAT_TICK = 1.0
local POLL_TICK = 1.0

local DEFAULT_BAR_HEIGHT = 16
local DEFAULT_MAX_BARS = 8
local DEFAULT_WIDTH = 240
local DEFAULT_BG_ALPHA = 0.8

local STATE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

-- 공유 상태만 파일 로컬 유지, 창별 상태는 windows[i] 로 이동, dik, 2026-10-01
local active = false
local inCombat = false
local pollMode = false
local badFormatShown = false
local eventFrame = nil
-- 창 객체 표(1~WINDOW_MAX), dik, 2026-10-01
local windows = {}

-- 숫자 설정 조회, dik, 2026-10-01
local function GetNumber(key, default)
    local value = ns.GetSetting(MODULE_ID, key)
    if type(value) ~= "number" then
        return default
    end
    return value
end

-- 창별 설정 키 생성, dik, 2026-10-01
local function WinKey(win, base)
    return ns.DamageMeter.WindowKey(base, win.index)
end

-- 창별 숫자 설정 조회, dik, 2026-10-01
local function WinNumber(win, base, default)
    return GetNumber(WinKey(win, base), default)
end

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting(MODULE_ID, key) == true
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

-- 구간 버튼 글자 갱신, dik, 2026-10-01
-- 창 단위로 변경(창별 segment 키), dik, 2026-10-01
local function UpdateSegmentLabel(win)
    local text = L.DAMAGEMETER_SEG_OVERALL
    if ns.GetSetting(MODULE_ID, WinKey(win, "segment")) == "current" then
        text = L.DAMAGEMETER_SEG_CURRENT
    end
    win.segButton.label:SetText(text)
end

-- 잠금 버튼 글자·색 갱신, dik, 2026-10-01
local function UpdateLockLabel(win)
    if ns.GetSetting(MODULE_ID, WinKey(win, "locked")) == true then
        win.lockButton.label:SetText(L.HUD_LOCK_ON)
        win.lockButton.label:SetTextColor(Theme.GetColor("TEXT_DIM"))
    else
        win.lockButton.label:SetText(L.HUD_LOCK_OFF)
        win.lockButton.label:SetTextColor(Theme.GetColor("ACCENT"))
    end
end

-- 행 글자 앵커 설정(초당 표시 여부), dik, 2026-10-01
local function AnchorRowTexts(row, showPerSecond)
    local half = Theme.GAP / 2
    row.total:ClearAllPoints()
    if showPerSecond then
        row.total:SetPoint("RIGHT", row.perSecond, "LEFT", -Theme.GAP, 0)
    else
        row.total:SetPoint("RIGHT", row.overlay, "RIGHT", -half, 0)
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.rank, "RIGHT", RANK_NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -half, 0)
    row.perSecondMode = showPerSecond
end

-- 바 행 생성, dik, 2026-10-01
-- 창 본문(win.body)을 부모로 사용, dik, 2026-10-01
local function CreateRow(win, barHeight)
    local half = Theme.GAP / 2
    local row = {}
-- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    row.bar = Widgets.CreateBar(win.body, { height = barHeight, readable = true })
    row.overlay = CreateFrame("Frame", nil, row.bar)
    row.overlay:SetAllPoints(row.bar)
    row.overlay:SetFrameLevel(row.bar:GetFrameLevel() + 4)

    row.rank = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "BAR_TEXT_DIM")
    row.rank:SetPoint("LEFT", row.overlay, "LEFT", half, 0)
    row.rank:SetWordWrap(false)

    row.perSecond = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "BAR_TEXT_DIM")
    row.perSecond:SetPoint("RIGHT", row.overlay, "RIGHT", -half, 0)
    row.perSecond:SetJustifyH("RIGHT")
    row.perSecond:SetWordWrap(false)

    row.total = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.total:SetJustifyH("RIGHT")
    row.total:SetWordWrap(false)

    row.name = Widgets.CreateLabel(row.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    row.name:SetWordWrap(false)

    AnchorRowTexts(row, true)
    row.bar:Hide()
    return row
end

-- 창 크기·바 재배치, dik, 2026-10-01
-- 창 단위·잠금 버튼 폭 반영, dik, 2026-10-01
local function Layout(win)
    if not active or not win or not win.hud then
        return
    end
    local pad = Theme.PAD / 3
    local width = WinNumber(win, "width", DEFAULT_WIDTH)
    local barHeight = GetNumber("barHeight", DEFAULT_BAR_HEIGHT)
    local maxBars = math.floor(WinNumber(win, "maxBars", DEFAULT_MAX_BARS))
    local headerH = win.dropdown:GetHeight()
    local rows = win.rows

    win.hud:SetSize(width, ns.DamageMeter.CalcWindowHeight(headerH, barHeight, maxBars, ROW_GAP, pad))

    win.dropdown:SetWidth(math.max(width - pad * 2 - SEG_BTN_W - LOCK_BTN_W - Theme.GAP, 1))
    win.segButton:SetSize(SEG_BTN_W, headerH)
    win.lockButton:SetSize(LOCK_BTN_W, headerH)

    while #rows < maxBars do
        rows[#rows + 1] = CreateRow(win, barHeight)
    end
    local showPerSecond = IsOn("showPerSecond")
    for k, row in ipairs(rows) do
        if k <= maxBars then
            row.bar:SetSize(math.max(width - pad * 2, 1), barHeight)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("TOPLEFT", win.body, "TOPLEFT", pad, -(pad + headerH + pad + (k - 1) * (barHeight + ROW_GAP)))
        else
            row.bar:Hide()
        end
        if row.perSecondMode ~= showPerSecond then
            AnchorRowTexts(row, showPerSecond)
        end
    end

    win.statusText:ClearAllPoints()
    win.statusText:SetPoint("TOPLEFT", win.body, "TOPLEFT", pad, -(pad + headerH + pad))
    win.statusText:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -pad, pad)
end

-- 행 전체 숨김, dik, 2026-10-01
-- 창 단위로 변경, dik, 2026-10-01
local function HideRows(win)
    for _, row in ipairs(win.rows) do
        row.bar:Hide()
    end
end

-- 한 행 채우기, dik, 2026-10-01
local function FillRow(row, index, src, session, first, showPerSecond, useClassColor)
    row.rank:SetText(L.FMT_RANK:format(index))

    local name = ns.DamageMeter.ShortName(src.name)
    if not ns.IsSecret(name) and name == nil then
        name = L.VALUE_UNKNOWN
    end
    row.name:SetText(name)

    row.bar:SetRange(0, ns.DamageMeter.ResolveMax(session, first))
    row.bar:SetValue(ns.DamageMeter.BarValue(src.totalAmount))

    local total = ns.DamageMeter.FormatAmount(src.totalAmount)
    if not ns.IsSecret(total) and total == nil then
        total = L.VALUE_UNKNOWN
    end
    row.total:SetText(total)

    if showPerSecond then
        local perSecond = ns.DamageMeter.FormatAmount(src.amountPerSecond)
        if not ns.IsSecret(perSecond) and perSecond == nil then
            perSecond = L.VALUE_UNKNOWN
        end
        row.perSecond:SetText(perSecond)
        row.perSecond:Show()
    else
        row.perSecond:Hide()
    end

    local r, g, b
    if useClassColor then
        r, g, b = ns.DamageMeter.GetClassColor(src.classFilename)
    end
    if r then
        row.bar:SetColor(r, g, b)
    else
        row.bar:SetColorToken("ACCENT")
    end
    row.bar:Show()
end

-- 창 내용 채우기, dik, 2026-10-01
-- 창 단위·종류/구간/maxBars 는 창 키, dik, 2026-10-01
local function Fill(win)
    local session, status = ns.DamageMeter.GetSession(ns.GetSetting(MODULE_ID, WinKey(win, "meterType")), ns.GetSetting(MODULE_ID, WinKey(win, "segment")))
    if status ~= "ok" then
        HideRows(win)
        win.statusText:SetText(ns.DamageMeter.STATUS_TEXT[status] or L.DAMAGEMETER_ERROR)
        win.statusText:Show()
        if status == "bad_format" and not badFormatShown then
            badFormatShown = true
            ns.Print(L.MSG_DAMAGEMETER_BAD_FORMAT)
        end
        return
    end
    win.statusText:Hide()

    local list = session.combatSources
    local rows = win.rows
    local maxBars = math.floor(WinNumber(win, "maxBars", DEFAULT_MAX_BARS))
    local showPerSecond = IsOn("showPerSecond")
    local useClassColor = IsOn("classColor")

    local first = nil
    for i = 1, #list do
        local candidate = list[i]
        if not ns.IsSecret(candidate) and type(candidate) == "table" then
            first = candidate
            break
        end
    end

    local placed = 0
    for i = 1, #list do
        local src = list[i]
        if not ns.IsSecret(src) and type(src) == "table" then
            placed = placed + 1
            if placed > maxBars then
                placed = maxBars
                break
            end
            FillRow(rows[placed], placed, src, session, first, showPerSecond, useClassColor)
        end
    end
    for k = placed + 1, #rows do
        rows[k].bar:Hide()
    end
end

-- 갱신 주기 처리(본문 OnUpdate), dik, 2026-10-01
-- 창 단위 누적값 사용, dik, 2026-10-01
local function OnBodyUpdate(win, elapsed)
    if not active then
        return
    end
    win.sinceRefresh = win.sinceRefresh + elapsed
    if inCombat then
        win.combatAcc = win.combatAcc + elapsed
        if win.combatAcc >= COMBAT_TICK then
            win.combatAcc = 0
            win.dirty = true
        end
    end
    if pollMode then
        win.pollAcc = win.pollAcc + elapsed
        if win.pollAcc >= POLL_TICK then
            win.pollAcc = 0
            win.dirty = true
        end
    end
    if win.dirty and win.sinceRefresh >= REFRESH_MIN then
        win.dirty = false
        win.sinceRefresh = 0
        Fill(win)
    end
end

-- 이벤트 프레임 생성, dik, 2026-10-01
-- 만들어진 모든 창에 dirty·combatAcc 전파, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if not active then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        end
        for _, win in pairs(windows) do
            if event == "PLAYER_REGEN_DISABLED" then
                win.combatAcc = 0
            else
                win.dirty = true
            end
        end
    end)
    local meterOk = RegisterEvents(eventFrame, ns.DamageMeter.EVENTS)
    RegisterEvents(eventFrame, STATE_EVENTS)
    pollMode = meterOk == 0
end

-- 머리줄·본문 생성, dik, 2026-10-01
-- 창 단위·잠금 버튼 추가, dik, 2026-10-01
local function CreateHeader(win)
    local hud = win.hud
    local pad = Theme.PAD / 3
    win.dropdown = Widgets.CreateDropdown(hud, {
        width = DEFAULT_WIDTH,
        items = ns.DamageMeter.TYPE_ITEMS,
        value = ns.GetSetting(MODULE_ID, WinKey(win, "meterType")),
        onChange = function(value)
            ns.SetSetting(MODULE_ID, WinKey(win, "meterType"), value)
        end,
    })
    win.dropdown:SetPoint("TOPLEFT", hud, "TOPLEFT", pad, -pad)

    win.segButton = Widgets.CreateButton(hud, "", function()
        local nextValue = "current"
        if ns.GetSetting(MODULE_ID, WinKey(win, "segment")) == "current" then
            nextValue = "overall"
        end
        ns.SetSetting(MODULE_ID, WinKey(win, "segment"), nextValue)
    end)
    win.segButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -pad, -pad)
    win.segButton.label:SetFontObject(Theme.GetFont("FONT_SMALL"))
    UpdateSegmentLabel(win)

    win.lockButton = Widgets.CreateButton(hud, "", function()
        local current = ns.GetSetting(MODULE_ID, WinKey(win, "locked")) == true
        ns.SetSetting(MODULE_ID, WinKey(win, "locked"), not current)
    end)
    win.lockButton:SetPoint("TOPRIGHT", win.segButton, "TOPLEFT", -Theme.GAP / 2, 0)
    win.lockButton.label:SetFontObject(Theme.GetFont("FONT_SMALL"))
    if Widgets.SetTooltip then
        Widgets.SetTooltip(win.lockButton, L.HUD_LOCK_TIP_TITLE, L.HUD_LOCK_TIP)
    end
end

-- 창 1개 생성(한 번만), dik, 2026-10-01
local function BuildWindow(i)
    local hw = ns.DamageMeter.HUD_WINDOWS[i]
    local win = {
        index = i,
        rows = {},
        dirty = true,
        sinceRefresh = REFRESH_MIN,
        combatAcc = 0,
        pollAcc = 0,
    }
    windows[i] = win

    win.hud = ns.Display.CreateHudFrame(MODULE_ID, hw.key, {
        label = L.FMT_HUD_LABEL_INDEXED:format(L.HUD_LABEL_DAMAGEMETER, i),
        point = hw.point,
        relativePoint = hw.relativePoint,
        x = hw.x,
        y = hw.y,
        strata = hw.strata,
    })

    win.panel = Widgets.CreatePanel(win.hud)
    win.panel:SetAllPoints(win.hud)
    Theme.ApplyBackdrop(win.panel, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    CreateHeader(win)

    win.body = CreateFrame("Frame", nil, win.hud)
    win.body:SetAllPoints(win.hud)
    win.body:SetScript("OnUpdate", function(_, elapsed)
        OnBodyUpdate(win, elapsed)
    end)

    win.statusText = Widgets.CreateLabel(win.body, "FONT_SMALL", "TEXT_DIM")
    win.statusText:SetJustifyH("LEFT")
    win.statusText:SetJustifyV("TOP")
    win.statusText:SetWordWrap(true)
    win.statusText:Hide()

    Layout(win)
    win.hud:ApplySavedPosition()
    win.hud:Show()
    win.hud:SetHudActive(true)
    win.hud:SetDragUnlocked(ns.GetSetting(MODULE_ID, WinKey(win, "locked")) ~= true)
    UpdateLockLabel(win)
    return win
end

-- 창 개수 적용(생성·표시·숨김), dik, 2026-10-01
local function ApplyWindowCount()
    local count = ns.DamageMeter.ClampWindowCount(ns.GetSetting(MODULE_ID, "windowCount"))
    for i = 1, ns.DamageMeter.WINDOW_MAX do
        local win = windows[i]
        if i <= count then
            if not win then
                BuildWindow(i)
            else
                win.hud:Show()
                win.hud:SetHudActive(true)
                win.dirty = true
            end
        elseif win then
            win.hud:Hide()
            win.hud:SetHudActive(false)
        end
    end
end

-- READY 초기화, dik, 2026-10-01
-- 창 개수 적용 방식으로 변경, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    active = true
    inCombat = ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true

    ApplyWindowCount()
    CreateEventFrame()
end

-- 모든 창에 함수 적용, dik, 2026-10-01
local function ForEachWindow(fn)
    for i = 1, ns.DamageMeter.WINDOW_MAX do
        if windows[i] then
            fn(windows[i])
        end
    end
end

-- 설정 변경 처리, dik, 2026-10-01
-- 창별 키 파싱·공통 키 전 창 적용, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            ForEachWindow(function(win)
                win.dropdown:Refresh()
                Layout(win)
                win.dirty = true
            end)
        end
        return
    end
    if scope ~= MODULE_ID then
        return
    end

    if key == "windowCount" then
        ApplyWindowCount()
        return
    end

    local base, index = ns.DamageMeter.ParseWindowKey(key)
    if base then
        local win = windows[index]
        if not win then
            return
        end
        if base == "meterType" or base == "segment" then
            ns.DamageMeter.ResetFailure()
            if base == "meterType" then
                win.dropdown:SetValue(value)
            else
                UpdateSegmentLabel(win)
            end
            win.dirty = true
        elseif base == "width" or base == "maxBars" then
            Layout(win)
            win.dirty = true
        elseif base == "locked" then
            win.hud:SetDragUnlocked(value ~= true)
            UpdateLockLabel(win)
        end
        return
    end

    if key == "barHeight" then
        ForEachWindow(function(win)
            Layout(win)
            win.dirty = true
        end)
    elseif key == "bgAlpha" then
        ForEachWindow(function(win)
            Theme.ApplyBackdrop(win.panel, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))
        end)
    elseif key == "classColor" or key == "showPerSecond" then
        ForEachWindow(function(win)
            if key == "showPerSecond" then
                Layout(win)
            end
            win.dirty = true
        end)
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
