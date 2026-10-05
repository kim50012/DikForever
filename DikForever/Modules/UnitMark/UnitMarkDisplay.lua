-- 대상 강조 이름표·툴팁 화면 설치, dik, 2026-10-05
local addonName, ns = ...

if not ns.GetModule("unitMark") then
    return
end

local L = ns.L
local Theme = ns.Theme

local MODULE_ID = "unitMark"
local TICK = 0.25
local EVENT_ADDED = "NAME_PLATE_UNIT_ADDED"
local EVENT_REMOVED = "NAME_PLATE_UNIT_REMOVED"
-- 덮개 바 체력 이벤트 상수 추가, dik, 2026-10-05
local EVENT_HEALTH = "UNIT_HEALTH"
local EVENT_MAXHEALTH = "UNIT_MAXHEALTH"
local NAME_FLAGS = "OUTLINE"
local TAG_GAP = 1
local BORDER_PAD = 2

local plates = setmetatable({}, { __mode = "k" })
local eventFrame
local built = false
local registered = false
local nameplateFailed = false
local failedNotified = false
local tickAcc = 0

-- 값 목록 중 secret 존재 여부, dik, 2026-10-05
local function AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- FontString 형태 검사, dik, 2026-10-05
local function IsFontString(fs)
    return type(fs) == "table" and type(fs.SetTextColor) == "function" and type(fs.GetTextColor) == "function"
end

-- 이름 강조 중인 이름표 수, dik, 2026-10-05
-- 덮개 바 이름표도 집계하도록 이름 변경, dik, 2026-10-05
local function CountActive()
    local n = 0
    for _, state in pairs(plates) do
        if state.quest or state.barOn then
            n = n + 1
        end
    end
    return n
end

-- 이름 글자 강조 칠하기, dik, 2026-10-05
local function PaintName(state)
    local fs = state.fs
    local saved = state.saved
    if not fs or not saved then
        return
    end
    fs:SetTextColor(Theme.GetColor("QUEST_TARGET"))
    if type(saved.face) == "string" and type(saved.size) == "number" then
        local _, _, flags = fs:GetFont()
        if ns.IsSecret(flags) or flags ~= NAME_FLAGS then
            fs:SetFont(saved.face, saved.size, NAME_FLAGS)
        end
    end
    fs:SetShadowColor(Theme.GetColor("TEXT_SHADOW"))
    fs:SetShadowOffset(1, -1)
end

-- 이름 글자 원래 값 저장(secret 이면 실패), dik, 2026-10-05
local function CaptureName(state, fs)
    local r, g, b, a = fs:GetTextColor()
    local face, size, flags = fs:GetFont()
    local sr, sg, sb, sa = fs:GetShadowColor()
    local sx, sy = fs:GetShadowOffset()
    if AnySecret(r, g, b, a, face, size, flags, sr, sg, sb, sa, sx, sy) then
        return false
    end
    state.fs = fs
    state.saved = {
        r = r, g = g, b = b, a = a,
        face = face, size = size, flags = flags,
        sr = sr, sg = sg, sb = sb, sa = sa,
        sx = sx, sy = sy,
    }
    return true
end

-- 이름 글자 원복, dik, 2026-10-05
local function RestoreName(state)
    local saved = state.saved
    local fs = state.fs
    state.saved = nil
    state.fs = nil
    state.quest = false
    if not saved or not IsFontString(fs) then
        return
    end
    if saved.r then
        fs:SetTextColor(saved.r, saved.g, saved.b, saved.a)
    end
    if type(saved.face) == "string" and type(saved.size) == "number" then
        fs:SetFont(saved.face, saved.size, saved.flags or "")
    end
    if saved.sr then
        fs:SetShadowColor(saved.sr, saved.sg, saved.sb, saved.sa)
    end
    if saved.sx then
        fs:SetShadowOffset(saved.sx, saved.sy)
    end
end

-- 덮개 바를 체력 바 가시성에 동기화, dik, 2026-10-05
local function SyncOverlayVisible(state)
    local overlay = state.overlay
    local healthBar = state.healthBar
    if not state.barOn or not overlay then
        return
    end
    local want = true
    if healthBar and type(healthBar.IsVisible) == "function" then
        local v = healthBar:IsVisible()
        want = not (not ns.IsSecret(v) and v == false)
    end
    if want ~= overlay:IsShown() then
        if want then
            overlay:Show()
        else
            overlay:Hide()
        end
    end
end

-- 점검 본문, dik, 2026-10-05
local function OnTick(_, elapsed)
    tickAcc = tickAcc + elapsed
    if tickAcc < TICK then
        return
    end
    tickAcc = 0
    local any = false
    -- 덮개 바 가시성 동기화 추가, dik, 2026-10-05
    for _, state in pairs(plates) do
        if state.quest or state.barOn then
            any = true
            if state.quest then
                PaintName(state)
            end
            if state.barOn then
                SyncOverlayVisible(state)
            end
        end
    end
    if not any and eventFrame then
        eventFrame:SetScript("OnUpdate", nil)
    end
end

-- 점검 설치·해제, dik, 2026-10-05
local function SyncTick()
    if not eventFrame then
        return
    end
    -- 이름 또는 덮개 바 이름표 기준으로 변경, dik, 2026-10-05
    if CountActive() > 0 then
        if not eventFrame:GetScript("OnUpdate") then
            tickAcc = 0
            eventFrame:SetScript("OnUpdate", OnTick)
        end
    else
        eventFrame:SetScript("OnUpdate", nil)
    end
end

-- 이름표 원복, dik, 2026-10-05
local function RestorePlate(plate)
    local state = plates[plate]
    if not state then
        return
    end
    RestoreName(state)
    -- 보라 덮개 바 숨김 추가, dik, 2026-10-05
    state.barOn = false
    if state.overlay then
        state.overlay:Hide()
    end
    if state.holder then
        state.holder:Hide()
    end
end

-- 이름표 얻기(금지 프레임 제외), dik, 2026-10-05
local function ResolvePlate(unit)
    if not ns.HasAPI("C_NamePlate.GetNamePlateForUnit") then
        return nil
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if type(plate) ~= "table" then
        return nil
    end
    if type(plate.IsForbidden) == "function" then
        local forbidden = plate:IsForbidden()
        if ns.IsSecret(forbidden) or forbidden == true then
            return nil
        end
    end
    local uf = plate.UnitFrame
    if type(uf) ~= "table" then
        uf = nil
    end
    local fs = uf and uf.name
    if not IsFontString(fs) then
        fs = nil
    end
    local bar = uf and uf.healthBar
    if type(bar) ~= "table" then
        bar = nil
    end
    return plate, fs, bar
end

-- 자체 holder·꼬리표·테두리 생성, dik, 2026-10-05
local function EnsureParts(state, plate)
    if state.holder then
        return
    end
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetAllPoints(plate)
    local tag = holder:CreateFontString(nil, "OVERLAY")
    tag:SetFontObject(Theme.GetFont("FONT_SMALL_OUTLINE"))
    local border = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    state.holder = holder
    state.tag = tag
    state.border = border
    -- 보라 덮개 바 생성 추가, dik, 2026-10-05
    local overlay = CreateFrame("StatusBar", nil, holder)
    overlay:SetStatusBarTexture(Theme.TEXTURE_WHITE)
    overlay:SetStatusBarColor(Theme.GetColor("QUEST_BAR"))
    overlay:Hide()
    state.overlay = overlay
end

-- 덮개 바 값 결정(secret 은 그대로), dik, 2026-10-05
local function OverlayValue(v, isMax)
    if ns.CombatHud then
        if isMax and ns.CombatHud.BarMax then
            return ns.CombatHud.BarMax(v)
        elseif not isMax and ns.CombatHud.BarValue then
            return ns.CombatHud.BarValue(v)
        end
    end
    if ns.IsSecret(v) then
        return v
    end
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and (not isMax or v > 0) then
        return v
    end
    return isMax and 1 or 0
end

-- 덮개 바 값 갱신, dik, 2026-10-05
local function UpdateOverlay(state, unit)
    local overlay = state.overlay
    if not overlay then
        return
    end
    overlay:SetMinMaxValues(0, OverlayValue(UnitHealthMax(unit), true))
    overlay:SetValue(OverlayValue(UnitHealth(unit), false))
end

-- 이름표 판정·적용, dik, 2026-10-05
local function ApplyPlate(unit)
    if type(unit) ~= "string" or ns.IsSecret(unit) or not ns.UnitMark then
        return
    end
    -- 바 강조 여부 수신 추가, dik, 2026-10-05
    local quest, rank, questBar = ns.UnitMark.Get(unit, "nameplate")
    -- 플레이어 직업색 바 수신 추가, dik, 2026-10-05
    local cr, cg, cb
    if type(ns.UnitMark.GetClassBar) == "function" then
        cr, cg, cb = ns.UnitMark.GetClassBar(unit)
    end
    local hasClass = cr ~= nil
    local plate, fs, bar = ResolvePlate(unit)
    if not plate then
        return
    end
    local state = plates[plate]
    -- 바 강조도 강조 대상에 포함, dik, 2026-10-05
    if not quest and not rank and not questBar and not hasClass then
        if state then
            RestorePlate(plate)
            state.unit = unit
            SyncTick()
        end
        return
    end
    if not state then
        state = { unit = unit, quest = false }
        plates[plate] = state
    end
    state.unit = unit
    EnsureParts(state, plate)

    if state.saved and state.fs ~= fs then
        RestoreName(state)
    end
    if quest and fs then
        if not state.saved then
            CaptureName(state, fs)
        end
        if state.saved then
            state.quest = true
            PaintName(state)
        end
    elseif state.saved then
        RestoreName(state)
    end

    -- 체력 바 위 보라 덮개 표시, dik, 2026-10-05
    -- 퀘스트·직업색 덮개 색 지정과 가시성 동기화, dik, 2026-10-05
    if (questBar or hasClass) and bar and state.overlay then
        local overlay = state.overlay
        state.healthBar = bar
        if questBar then
            overlay:SetStatusBarColor(Theme.GetColor("QUEST_BAR"))
        else
            overlay:SetStatusBarColor(cr, cg, cb, 1)
        end
        overlay:ClearAllPoints()
        overlay:SetAllPoints(bar)
        local level = bar:GetFrameLevel()
        if type(level) == "number" and not ns.IsSecret(level) then
            overlay:SetFrameLevel(level + 1)
        end
        UpdateOverlay(state, unit)
        state.barOn = true
        SyncOverlayVisible(state)
    else
        if state.overlay then
            state.overlay:Hide()
        end
        state.barOn = false
    end

    local tagText, tagColor, borderColor = ns.UnitMark.RankStyle(rank)
    if tagText then
        state.tag:ClearAllPoints()
        if fs then
            state.tag:SetPoint("BOTTOM", fs, "TOP", 0, TAG_GAP)
        else
            state.tag:SetPoint("BOTTOM", plate, "TOP", 0, 0)
        end
        state.tag:SetText(tagText)
        state.tag:SetTextColor(Theme.GetColor(tagColor))
        state.tag:Show()
    else
        state.tag:Hide()
    end
    if borderColor and bar then
        state.border:ClearAllPoints()
        state.border:SetPoint("TOPLEFT", bar, "TOPLEFT", -BORDER_PAD, BORDER_PAD)
        state.border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BORDER_PAD, -BORDER_PAD)
        Theme.ApplyBackdrop(state.border, "BG", borderColor, 0)
        state.border:Show()
    else
        state.border:Hide()
    end
    state.holder:Show()
    SyncTick()
end

-- 보이는 이름표 전부 재판정, dik, 2026-10-05
local function ApplyAll()
    local seen = {}
    if ns.HasAPI("C_NamePlate.GetNamePlates") then
        local list = C_NamePlate.GetNamePlates()
        if type(list) == "table" then
            for i = 1, #list do
                local plate = list[i]
                local unit = type(plate) == "table" and plate.namePlateUnitToken or nil
                if type(unit) == "string" and not ns.IsSecret(unit) and not seen[unit] then
                    seen[unit] = true
                    ApplyPlate(unit)
                end
            end
        end
    end
    local units = {}
    for _, state in pairs(plates) do
        if state.unit and not seen[state.unit] then
            units[#units + 1] = state.unit
        end
    end
    for i = 1, #units do
        ApplyPlate(units[i])
    end
end

-- 이름표 전부 원복, dik, 2026-10-05
local function RestoreAll()
    for plate in pairs(plates) do
        RestorePlate(plate)
    end
    SyncTick()
end

-- 이름표 이벤트 처리, dik, 2026-10-05
local function OnEvent(_, event, unit)
    -- 덮개 바 체력 이벤트 처리 추가, dik, 2026-10-05
    if event == EVENT_HEALTH or event == EVENT_MAXHEALTH then
        if type(unit) ~= "string" or ns.IsSecret(unit) then
            return
        end
        for _, state in pairs(plates) do
            if state.barOn and state.unit == unit then
                UpdateOverlay(state, unit)
            end
        end
    elseif event == EVENT_ADDED then
        ApplyPlate(unit)
    elseif event == EVENT_REMOVED then
        if type(unit) ~= "string" or ns.IsSecret(unit) then
            return
        end
        for plate, state in pairs(plates) do
            if state.unit == unit then
                RestorePlate(plate)
                state.unit = nil
            end
        end
        SyncTick()
    end
end

-- 이름표 이벤트 등록(성공 여부), dik, 2026-10-05
local function RegisterPlateEvents()
    local okAdded = pcall(eventFrame.RegisterEvent, eventFrame, EVENT_ADDED)
    local okRemoved = pcall(eventFrame.RegisterEvent, eventFrame, EVENT_REMOVED)
    -- 덮개 바 체력 이벤트 등록 추가, dik, 2026-10-05
    local okHealth = pcall(eventFrame.RegisterEvent, eventFrame, EVENT_HEALTH)
    local okMax = pcall(eventFrame.RegisterEvent, eventFrame, EVENT_MAXHEALTH)
    if okAdded and okRemoved and okHealth and okMax then
        return true
    end
    eventFrame:UnregisterEvent(EVENT_ADDED)
    -- 실패 시 체력 이벤트도 해제, dik, 2026-10-05
    eventFrame:UnregisterEvent(EVENT_REMOVED)
    eventFrame:UnregisterEvent(EVENT_HEALTH)
    eventFrame:UnregisterEvent(EVENT_MAXHEALTH)
    return false
end

-- 이름표 표시 희망 여부, dik, 2026-10-05
local function WantNameplate()
    if not built or nameplateFailed or not ns.UnitMark then
        return false
    end
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return false
    end
    if ns.GetSetting(MODULE_ID, "onNameplate") == false then
        return false
    end
    return ns.UnitMark.GetUnavailableReason("nameplate") == nil
end

-- 이름표 켜기·끄기 동기화 후 재판정, dik, 2026-10-05
local function Refresh()
    if not built then
        return
    end
    if WantNameplate() then
        if not registered then
            if RegisterPlateEvents() then
                registered = true
            else
                nameplateFailed = true
                if not failedNotified then
                    failedNotified = true
                    ns.Print(L.UNITMARK_UNAVAILABLE_NAMEPLATE)
                end
                return
            end
        end
        ApplyAll()
    elseif registered then
        registered = false
        eventFrame:UnregisterEvent(EVENT_ADDED)
        -- 끄기 시 체력 이벤트도 해제, dik, 2026-10-05
        eventFrame:UnregisterEvent(EVENT_REMOVED)
        eventFrame:UnregisterEvent(EVENT_HEALTH)
        eventFrame:UnregisterEvent(EVENT_MAXHEALTH)
        RestoreAll()
    else
        RestoreAll()
    end
end

-- 유닛 툴팁 첫 줄 색 본문, dik, 2026-10-05
local function ApplyTooltip(tooltip)
    if tooltip ~= GameTooltip or type(tooltip.GetUnit) ~= "function" or not ns.UnitMark then
        return
    end
    if tooltip.IsForbidden and tooltip:IsForbidden() then
        return
    end
    local _, unit = tooltip:GetUnit()
    local quest = ns.UnitMark.Get(unit, "tooltip")
    if quest ~= true then
        return
    end
    local line = ns.Display.Find("GameTooltipTextLeft1")
    if line then
        line:SetTextColor(Theme.GetColor("QUEST_TARGET"))
    end
end

-- 유닛 툴팁 처리기 오류 격리, dik, 2026-10-05
local function OnUnitTooltip(tooltip)
    xpcall(function()
        ApplyTooltip(tooltip)
    end, geterrorhandler())
end

-- READY 초기화, dik, 2026-10-05
local function Initialize()
    if built then
        return
    end
    if not ns.IsModuleSupported(MODULE_ID) then
        return
    end
    built = true
    eventFrame = CreateFrame("Frame", nil, UIParent)
    eventFrame:SetScript("OnEvent", OnEvent)
    if ns.HasAPI("TooltipDataProcessor.AddTooltipPostCall") and ns.HasAPI("Enum.TooltipDataType.Unit") then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end
    Refresh()
end

-- 설정 변경 처리, dik, 2026-10-05
local function OnSettingChanged(scope)
    if scope == MODULE_ID then
        Refresh()
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
ns.On("UNIT_MARK_CHANGED", Refresh)
