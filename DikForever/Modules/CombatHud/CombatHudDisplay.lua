-- 전투 HUD 유닛 프레임·디버프·내구도·갱신·보안 예약, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("combatHud")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local MODULE_ID = "combatHud"
local REFRESH_MIN = 0.05
local AURA_MIN = 0.2
local POLL_TICK = 0.25
local SECURE_RETRY_MAX = 10

-- 체력 높이 기본값·넓은 바 상수 추가, dik, 2026-10-01
local DEFAULT_HEALTH_H = 18
local TARGET_PAD = 2
local DEFAULT_TARGET_W = 420
local DEFAULT_TARGET_H = 24
local DEFAULT_SCALE = 1
-- 자원 바 높이 기본값(powerHeight) 12 로 변경, dik, 2026-10-01
local DEFAULT_POWER_H = 12
local ROW_GAP = 2
local ICON_SIZE = 22
local ICON_GAP = 2
local AURA_ROW_GAP = 2
local DEFAULT_HEADER_H = 14
local DEFAULT_WIDTH = 220
local DEFAULT_BG_ALPHA = 0.8
local DEFAULT_MAX_DEBUFFS = 8
-- 버프 최대 개수 기본값(WFA-039), dik, 2026-10-02
local DEFAULT_MAX_BUFFS = 8
-- 대상의 대상 주기·기본 크기 상수, dik, 2026-10-01
local TOT_TICK = 0.2
local DEFAULT_TOT_W = 120
local DEFAULT_TOT_H = 18

local active = false
local support = {}
local frames = {}
local frameList = {}
local dirty = {}
local buttons = {}
local missingList = {}
local eventFrame = nil
local partialShown = false
local secretPercentFailed = false
local valueFailed = false
local secureDone = false
local securePending = false
local mousePending = false
local retryCount = 0
local lastMoving = false
local pollMode = false
local targetStyle = "classic"
local sinceRefresh = REFRESH_MIN
local sinceAura = AURA_MIN
local pollAcc = 0
-- 대상의 대상 주기 누적값 추가, dik, 2026-10-01
local totAcc = 0
-- 오라 시간 글자 주기·누적·기본 숫자 숨김 성공 여부(WFA-045), dik, 2026-10-03
local AURA_TIME_TICK = 0.2
local sinceAuraTime = 0
local hideCountdownOk = false
-- 오라 툴팁 지원 여부(T1), dik, 2026-10-02
local tooltipOk = false

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

-- 전투 중 여부, dik, 2026-10-01
local function IsInCombat()
    return ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true
end

-- 이벤트 일괄 등록, 성공 개수·실패 이름 반환, dik, 2026-10-01
local function RegisterEvents(frame, names)
    local okCount = 0
    local failed = {}
    for _, name in ipairs(names) do
        if pcall(frame.RegisterEvent, frame, name) then
            okCount = okCount + 1
        else
            failed[#failed + 1] = name
        end
    end
    return okCount, failed
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
    if partialShown or #missingList == 0 then
        return
    end
    partialShown = true
    ns.Print(L.MSG_COMBATHUD_PARTIAL:format(ns.FormatMissingAPIs(missingList)))
end

-- 유닛 dirty 표시(part 배열), dik, 2026-10-01
local function MarkParts(key, parts)
    local d = dirty[key]
    if not d or type(parts) ~= "table" then
        return
    end
    for _, part in ipairs(parts) do
        d[part] = true
    end
end

-- 유닛 전체 dirty 표시, dik, 2026-10-01
local function MarkAll(key)
    local d = dirty[key]
    if d then
        d.health = true
        d.power = true
        d.info = true
        d.aura = true
    end
end

-- 모든 유닛 전체 dirty 표시, dik, 2026-10-01
local function MarkEveryUnit()
    for i = 1, #frameList do
        MarkAll(frameList[i].key)
    end
end

-- secret 가능 글자 설정(nil 이면 대체 글자), dik, 2026-10-01
local function SetSecretText(fs, value, fallback)
    if ns.IsSecret(value) then
        fs:SetText(value)
    elseif value == nil then
        fs:SetText(fallback or "")
    else
        fs:SetText(value)
    end
end

-- HUD 배율 설정값(0 이하는 기본값), dik, 2026-10-01
local function GetScale()
    local scale = GetNumber("hudScale", DEFAULT_SCALE)
    if scale <= 0 then
        return DEFAULT_SCALE
    end
    return scale
end

-- HUD 배율 적용(바뀌었으면 true), dik, 2026-10-01
local function ApplyScale(uf)
    local scale = GetScale()
    local changed = uf.scale ~= nil and uf.scale ~= scale
    uf.scale = scale
    uf.hud:SetScale(scale)
    return changed
end

-- 이름 글자 서체 적용(서체 원복 후 문자 종류별 대체), dik, 2026-10-01
local function ApplyNameFont(fs, token, text, colorToken)
    fs:SetFontObject(Theme.GetFont(token))
    fs:SetTextColor(Theme.GetColor(colorToken))
    -- 이름 서체 명시 원복 추가, dik, 2026-10-02
    local face, size, flags = Theme.GetFont(token):GetFont()
    if type(face) == "string" and type(size) == "number" then
        if fs:SetFont(face, size, flags or "") == false and Theme.FACE_FALLBACK then
            Theme.SetFontFace(fs, Theme.FACE_FALLBACK)
        end
    end
    local script = ns.CombatHud.ClassifyScript(text)
    if script == "mixed" then
        if Theme.FACE_FALLBACK then
            Theme.SetFontFace(fs, Theme.FACE_FALLBACK)
        end
    elseif script == "cjk" then
        if not Theme.SetFontFace(fs, Theme.FACE_CJK) and Theme.FACE_FALLBACK then
            Theme.SetFontFace(fs, Theme.FACE_FALLBACK)
        end
    end
end

-- 체력 값 축약 표시(W2), dik, 2026-10-01
local function ShowAbbrevValue(fs, cur)
    local C = ns.CombatHud
    local value, mode = C.HealthAbbrev(cur)
    if mode == "text" or mode == "raw" then
        fs:SetText(value)
    elseif mode == "secretApi" then
        local ok = xpcall(function()
            fs:SetText(C.CallAbbrevAPI(value))
        end, geterrorhandler())
        if not ok then
            if C.MarkAbbrevFailed() then
                ns.Print(L.MSG_COMBATHUD_ABBREV_FAILED)
            end
            fs:SetText(value)
        end
    else
        fs:SetText("")
    end
end

-- 현재/최대 값 쌍 표시(실패 시 대체 글자), dik, 2026-10-01
local function ShowValuePair(fs, cur, max, fallbackFn)
    local text, mode = ns.CombatHud.ValuePairText(cur, max)
    if mode == "secret" and not valueFailed then
        local ok = xpcall(function()
            fs:SetFormattedText(L.FMT_COMBATHUD_VALUE_PAIR_RAW, cur, max)
        end, geterrorhandler())
        if ok then
            return
        end
        valueFailed = true
        ns.Print(L.MSG_COMBATHUD_VALUE_FAILED)
    end
    if mode == "text" then
        fs:SetText(text)
    elseif mode == "secret" then
        fallbackFn(fs, cur)
    else
        fs:SetText("")
    end
end

-- 기존형 값 쌍 대체 글자(현재값만), dik, 2026-10-01
local function ShowCurOnly(fs, cur)
    SetSecretText(fs, cur, "")
end

-- 머리줄 이름 오른쪽 앵커(내구도 항목 유무), dik, 2026-10-01
local function AnchorHeader(uf)
    local pad = Theme.PAD / 3
    local half = Theme.GAP / 2
    uf.name:ClearAllPoints()
    -- 꼬리표 표시 중이면 이름 왼쪽 앵커를 꼬리표로, dik, 2026-10-05
    if uf.rankOn and uf.rankText then
        uf.name:SetPoint("LEFT", uf.rankText, "RIGHT", half, 0)
    else
        uf.name:SetPoint("LEFT", uf.level, "RIGHT", half, 0)
    end
    if uf.durability and uf.durability.infoActive then
        uf.name:SetPoint("RIGHT", uf.durability, "LEFT", -half, 0)
    else
        uf.name:SetPoint("RIGHT", uf.body, "RIGHT", -pad, 0)
    end
end

-- 디버프 아이콘 재배치, dik, 2026-10-01
local function LayoutAuraIcons(uf)
    local positions = ns.CombatHud.LayoutIcons(uf.iconCount, uf.width, ICON_SIZE, ICON_GAP)
    for k = 1, #uf.icons do
        local icon = uf.icons[k]
        local p = positions[k]
        if k <= uf.iconCount and p then
            icon.frame:ClearAllPoints()
            icon.frame:SetPoint("TOPLEFT", uf.auraRow, "TOPLEFT", p[1] or p.x or 0, p[2] or p.y or 0)
        end
    end
end

-- 유닛 프레임 크기·내부 배치, dik, 2026-10-01
local function LayoutUnit(uf, width)
    -- 배율·체력 높이 설정 반영, dik, 2026-10-01
    local changed = ApplyScale(uf)
    local healthH = GetNumber("healthHeight", DEFAULT_HEALTH_H)
    -- 자원 바 높이 설정 반영, dik, 2026-10-01
    local powerH = GetNumber("powerHeight", DEFAULT_POWER_H)
    local pad = Theme.PAD / 3
    local headerH = math.ceil(uf.measure:GetStringHeight())
    if headerH <= 0 then
        headerH = DEFAULT_HEADER_H
    end
    uf.width = width
    uf.powerOn = IsOn("showPower") and support.power == true
    uf.hud:SetSize(width, ns.CombatHud.CalcFrameHeight(headerH, healthH, powerH, uf.powerOn, ROW_GAP, pad))
    uf.health:SetHeight(healthH)
    uf.power:SetHeight(powerH)

    uf.level:ClearAllPoints()
    uf.level:SetPoint("TOPLEFT", uf.body, "TOPLEFT", pad, -pad)
    AnchorHeader(uf)

    uf.health:ClearAllPoints()
    uf.health:SetPoint("TOPLEFT", uf.body, "TOPLEFT", pad, -(pad + headerH + ROW_GAP))
    uf.health:SetWidth(math.max(width - pad * 2, 1))

    uf.power:ClearAllPoints()
    uf.power:SetPoint("TOPLEFT", uf.health, "BOTTOMLEFT", 0, -ROW_GAP)
    uf.power:SetWidth(math.max(width - pad * 2, 1))
    if not uf.powerOn then
        uf.power:Hide()
    end

    uf.auraRow:SetSize(width, ICON_SIZE)
    LayoutAuraIcons(uf)
    return changed
end

-- 넓은 대상 바 크기·내부 배치, dik, 2026-10-01
local function LayoutTargetBar(uf)
    local changed = ApplyScale(uf)
    local w = GetNumber("targetWidth", DEFAULT_TARGET_W)
    local h = GetNumber("targetHeight", DEFAULT_TARGET_H)
    uf.width = w
    uf.hud:SetSize(w, h)

    uf.health:ClearAllPoints()
    uf.health:SetPoint("TOPLEFT", uf.body, "TOPLEFT", TARGET_PAD, -TARGET_PAD)
    uf.health:SetWidth(math.max(w - TARGET_PAD * 2, 1))
    uf.health:SetHeight(math.max(h - TARGET_PAD * 2, 1))

    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    local token = Theme.OutlineToken(ns.CombatHud.TargetTextFont(h))
    uf.nameToken = token
    uf.percentText:SetFontObject(Theme.GetFont(token))
    uf.percentText:SetTextColor(Theme.GetColor("TEXT"))
    uf.valueText:SetFontObject(Theme.GetFont(token))
    uf.valueText:SetTextColor(Theme.GetColor("TEXT"))
    uf.nameText:SetFontObject(Theme.GetFont(token))
    uf.nameText:SetTextColor(Theme.GetColor("TEXT"))

    -- 이름 앵커 4분기(% 오른쪽·값 왼쪽 사이), dik, 2026-10-01
    local inset = ns.CombatHud.TargetNameInset(w)
    local half = Theme.GAP / 2
    uf.nameText:ClearAllPoints()
    if IsOn("showHealthPercent") then
        uf.nameText:SetPoint("LEFT", uf.percentText, "RIGHT", half, 0)
    else
        uf.nameText:SetPoint("LEFT", uf.overlay, "LEFT", inset, 0)
    end
    if IsOn("targetShowValue") then
        uf.nameText:SetPoint("RIGHT", uf.valueText, "LEFT", -half, 0)
    else
        uf.nameText:SetPoint("RIGHT", uf.overlay, "RIGHT", -inset, 0)
    end

    uf.auraRow:SetSize(w, ICON_SIZE)
    LayoutAuraIcons(uf)
    return changed
end

-- 대상의 대상 크기·내부 배치, dik, 2026-10-01
local function LayoutToT(uf)
    local changed = ApplyScale(uf)
    local w = GetNumber("totWidth", DEFAULT_TOT_W)
    local h = GetNumber("totHeight", DEFAULT_TOT_H)
    uf.width = w
    uf.hud:SetSize(w, h)

    uf.health:ClearAllPoints()
    uf.health:SetPoint("TOPLEFT", uf.body, "TOPLEFT", TARGET_PAD, -TARGET_PAD)
    uf.health:SetWidth(math.max(w - TARGET_PAD * 2, 1))
    uf.health:SetHeight(math.max(h - TARGET_PAD * 2, 1))

    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    local token = Theme.OutlineToken(ns.CombatHud.TargetTextFont(h))
    uf.nameToken = token
    uf.percentText:SetFontObject(Theme.GetFont(token))
    uf.percentText:SetTextColor(Theme.GetColor("TEXT"))
    uf.nameText:SetFontObject(Theme.GetFont(token))
    uf.nameText:SetTextColor(Theme.GetColor("TEXT"))

    local half = Theme.GAP / 2
    uf.nameText:ClearAllPoints()
    uf.nameText:SetPoint("LEFT", uf.overlay, "LEFT", half, 0)
    if IsOn("showHealthPercent") then
        uf.nameText:SetPoint("RIGHT", uf.percentText, "LEFT", -half, 0)
    else
        uf.nameText:SetPoint("RIGHT", uf.overlay, "RIGHT", -half, 0)
    end
    return changed
end

-- 오라 툴팁 사용 여부(T2), dik, 2026-10-02
local function IsTooltipOn()
    return tooltipOk and IsOn("auraTooltip")
end

-- 툴팁 주인 여부(T4), dik, 2026-10-02
local function IsTooltipOwner(frame)
    if type(GameTooltip) ~= "table" then
        return false
    end
    if type(GameTooltip.IsOwned) == "function" then
        return GameTooltip:IsOwned(frame) == true
    end
    if type(GameTooltip.GetOwner) == "function" then
        return GameTooltip:GetOwner() == frame
    end
    return false
end

-- 전체 아이콘 마우스 재적용(O1), dik, 2026-10-02
local function ApplyIconMouse()
    local on = IsTooltipOn()
    for i = 1, #frameList do
        local icons = frameList[i].icons
        for k = 1, #icons do
            icons[k].frame:EnableMouse(on)
            if not on and IsTooltipOwner(icons[k].frame) then
                GameTooltip:Hide()
            end
        end
    end
end

-- 오라 툴팁 표시(T3), dik, 2026-10-02
local function ShowAuraTooltip(uf, icon)
    if not IsTooltipOn() or type(icon.auraIndex) ~= "number" then
        return false
    end
    GameTooltip:SetOwner(icon.frame, "ANCHOR_BOTTOMRIGHT")
    -- secret 접근 거부는 이번 툴팁만 생략, dik, 2026-10-03
    local ok, err = pcall(GameTooltip.SetUnitAura, GameTooltip, uf.unit, icon.auraIndex, icon.auraFilter)
    if ok then
        GameTooltip:Show()
        return true
    end
    if ns.CombatHud.IsSecretAuraError(err) then
        GameTooltip:Hide()
        return false
    end
    geterrorhandler()(err)
    -- 실패 시 전체 아이콘 마우스 통과(O1), dik, 2026-10-02
    tooltipOk = false
    GameTooltip:Hide()
    ApplyIconMouse()
    return false
end

-- 디버프 아이콘 조회·생성, dik, 2026-10-01
local function GetIcon(uf, index)
    local icon = uf.icons[index]
    if icon then
        return icon
    end
    icon = {}
    icon.frame = CreateFrame("Frame", nil, uf.auraRow, "BackdropTemplate")
    -- 오라 툴팁 마우스·핸들러(T2~T4), dik, 2026-10-02
    icon.frame:EnableMouse(IsTooltipOn())
    icon.frame:SetScript("OnEnter", function()
        ShowAuraTooltip(uf, icon)
    end)
    icon.frame:SetScript("OnLeave", function()
        if IsTooltipOwner(icon.frame) then
            GameTooltip:Hide()
        end
    end)
    -- 아이콘 숨김 시 툴팁 해제(O2), dik, 2026-10-02
    icon.frame:SetScript("OnHide", function()
        if IsTooltipOwner(icon.frame) then
            GameTooltip:Hide()
        end
    end)
    icon.frame:SetSize(ICON_SIZE, ICON_SIZE)
    Theme.ApplyBackdrop(icon.frame, "PANEL", "DANGER")
    icon.tex = icon.frame:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", icon.frame, "TOPLEFT", 1, -1)
    icon.tex:SetPoint("BOTTOMRIGHT", icon.frame, "BOTTOMRIGHT", -1, 1)
    icon.cd = CreateFrame("Cooldown", nil, icon.frame, "CooldownFrameTemplate")
    icon.cd:SetPoint("TOPLEFT", icon.frame, "TOPLEFT", 1, -1)
    icon.cd:SetPoint("BOTTOMRIGHT", icon.frame, "BOTTOMRIGHT", -1, 1)
    local top = CreateFrame("Frame", nil, icon.frame)
    top:SetAllPoints(icon.frame)
    top:SetFrameLevel(icon.cd:GetFrameLevel() + 1)
    -- 기본 카운트다운 숨김·시간 글자 추가(WFA-045), dik, 2026-10-03
    if type(icon.cd.SetHideCountdownNumbers) == "function" then
        icon.cd:SetHideCountdownNumbers(true)
        hideCountdownOk = true
    end
    icon.time = Widgets.CreateLabel(top, "FONT_TINY_OUTLINE", "TEXT")
    icon.time:SetPoint("BOTTOM", top, "BOTTOM", 0, 1)
    icon.time:SetJustifyH("CENTER")
    icon.time:Hide()
    icon.count = Widgets.CreateLabel(top, "FONT_TINY_OUTLINE", "TEXT")
    icon.count:SetPoint("TOPRIGHT", top, "TOPRIGHT", -1, -1)
    icon.count:SetJustifyH("RIGHT")
    icon.frame:Hide()
    uf.icons[index] = icon
    return icon
end

-- 아이콘 값 사용 가능 여부(A3), dik, 2026-10-01
local function IsUsableIcon(icon)
    if ns.IsSecret(icon) then
        return true
    end
    if type(icon) == "number" then
        return true
    end
    return type(icon) == "string" and icon ~= ""
end

-- 아이콘 남은 시간 글자 갱신(WFA-045), dik, 2026-10-03
local function UpdateIconTime(icon, now)
    local text = nil
    if hideCountdownOk and type(icon.expires) == "number" and type(ns.CombatHud.AuraTimeText) == "function" then
        text = ns.CombatHud.AuraTimeText(icon.expires - now)
    end
    if text ~= icon.timeText then
        if text then
            icon.time:SetText(text)
            icon.time:Show()
        else
            icon.time:Hide()
        end
        icon.timeText = text
    end
end

-- 오라 아이콘 1개 채우기(A9), dik, 2026-10-02
local function FillAuraIcon(uf, count, aura, kind, auraIndex, auraFilter, borderToken)
    local C = ns.CombatHud
    local widget = GetIcon(uf, count)
    widget.kind = kind
    widget.auraIndex = auraIndex
    widget.auraFilter = auraFilter
    Theme.ApplyBackdrop(widget.frame, "PANEL", borderToken)
    widget.tex:SetTexture(aura.icon)
    local countText = C.AuraCountText(aura.applications)
    if countText then
        widget.count:SetText(countText)
        widget.count:Show()
    else
        widget.count:Hide()
    end
    local start, duration = C.AuraCooldown(aura.duration, aura.expirationTime)
    -- 남은 시간 글자용 만료 시각 저장(WFA-045), dik, 2026-10-03
    if start then
        widget.cd:SetCooldown(start, duration)
        widget.cd:Show()
        widget.expires = start + duration
    else
        widget.cd:Hide()
        widget.expires = nil
    end
    -- 재사용 시 시간 글자 강제 갱신, dik, 2026-10-03
    widget.timeText = false
    UpdateIconTime(widget, GetTime())
    widget.frame:Show()
end

-- 디버프 줄 채우기, dik, 2026-10-01
-- 디버프 다음 버프 단계·툴팁 갱신(A9·T5), dik, 2026-10-02
local function FillAura(uf)
    local C = ns.CombatHud
    local count = 0
    if support.debuffs and IsOn(uf.def.debuffSetting) then
        local maxCount = math.floor(GetNumber("maxDebuffs", DEFAULT_MAX_DEBUFFS))
        local filter = C.BuildDebuffFilter(uf.key == "target" and IsOn("targetOnlyMine"))
        local list = C.ReadDebuffs(uf.unit, filter, maxCount)
        for i = 1, #list do
            local aura = list[i]
            if IsUsableIcon(aura.icon) then
                count = count + 1
                FillAuraIcon(uf, count, aura, "debuff", i, filter, "DANGER")
            end
        end
    end
    if support.debuffs and uf.def.buffSetting and IsOn(uf.def.buffSetting) then
        local filter = C.BuildBuffFilter()
        local list, _, indices = C.ReadBuffs(uf.unit, GetNumber("maxBuffs", DEFAULT_MAX_BUFFS), IsOn("hidePermanentBuffs"))
        for i = 1, #list do
            local aura = list[i]
            if IsUsableIcon(aura.icon) then
                count = count + 1
                FillAuraIcon(uf, count, aura, "buff", indices and indices[i], filter, "BORDER")
            end
        end
    end
    uf.iconCount = count
    for k = 1, #uf.icons do
        local icon = uf.icons[k]
        if k > count then
            icon.frame:Hide()
        end
        if IsTooltipOwner(icon.frame) and not (k <= count and ShowAuraTooltip(uf, icon)) then
            GameTooltip:Hide()
        end
    end
    LayoutAuraIcons(uf)
end

-- 대상 강조(꼬리표·테두리) 적용 후 퀘스트 여부 반환, dik, 2026-10-05
-- 바 보라·선점 회색 변경 여부 반환 추가, dik, 2026-10-05
local function ApplyMark(uf)
    local quest, rank, bar, tapped = false, nil, false, false
    if ns.UnitMark then
        quest, rank, bar, tapped = ns.UnitMark.Get(uf.unit, "hud")
    end
    -- 바 보라색·선점 회색 여부 기록, dik, 2026-10-05
    local tappedOn = (tapped == true) and (ns.GetSetting("unitMark", "questBar") ~= false)
    local barChanged = (uf.markBar == true) ~= (bar == true) or (uf.markTapped == true) ~= tappedOn
    uf.markBar = (bar == true)
    uf.markTapped = tappedOn
    local tag, tagColor, borderColor
    if rank and ns.UnitMark then
        tag, tagColor, borderColor = ns.UnitMark.RankStyle(rank)
    end
    if uf.rankText then
        local on = tag ~= nil
        if on then
            uf.rankText:SetText(tag)
            uf.rankText:SetTextColor(Theme.GetColor(tagColor))
            uf.rankText:Show()
        else
            uf.rankText:Hide()
        end
        if not uf.wide and uf.rankOn ~= on then
            uf.rankOn = on
            AnchorHeader(uf)
        end
    end
    borderColor = borderColor or "BORDER"
    if uf.borderToken ~= borderColor then
        Theme.ApplyBackdrop(uf.body, "BG", borderColor, GetNumber("bgAlpha", DEFAULT_BG_ALPHA))
        uf.borderToken = borderColor
    end
    return quest == true, barChanged
end

-- 머리줄(레벨·이름) 채우기, dik, 2026-10-01
local function FillInfo(uf)
    local C = ns.CombatHud
    SetSecretText(uf.level, C.LevelText(UnitLevel(uf.unit)), "")
    -- 이름 서체 적용 후 표시, dik, 2026-10-01
    local name = C.NameText(UnitName(uf.unit))
    if not ns.IsSecret(name) and name == nil then
        name = L.VALUE_UNKNOWN
    end
    -- 퀘스트 대상이면 보라색·외곽선 이름, dik, 2026-10-05
    local nameToken, nameColor = "FONT_SMALL", "TEXT"
    local quest, barChanged
    if uf.unit == "target" then
        quest, barChanged = ApplyMark(uf)
    end
    if quest then
        nameToken, nameColor = Theme.OutlineToken(nameToken), "QUEST_TARGET"
    end
    ApplyNameFont(uf.name, nameToken, name, nameColor)
    uf.name:SetText(name)
    return barChanged
end

-- 체력 % 글자 채우기, dik, 2026-10-01
local function FillPercent(uf, dead)
    local fs = uf.percentText
    if not IsOn("showHealthPercent") then
        fs:Hide()
        return
    end
    fs:Show()
    if dead then
        fs:SetText(L.COMBATHUD_DEAD)
        return
    end
    local value, mode = ns.CombatHud.GetHealthPercent(uf.unit)
    if mode == "secret" and secretPercentFailed then
        mode = "none"
    end
    if mode == "text" then
        fs:SetText(value)
    elseif mode == "secret" then
        local ok = xpcall(function()
            fs:SetFormattedText(L.FMT_COMBATHUD_PERCENT, value)
        end, geterrorhandler())
        if not ok then
            secretPercentFailed = true
            ns.Print(L.MSG_COMBATHUD_PERCENT_FAILED)
            fs:SetText(L.VALUE_UNKNOWN)
        end
    else
        fs:SetText(L.VALUE_UNKNOWN)
    end
end

-- 체력 바 색 적용, dik, 2026-10-01
local function ApplyHealthColor(uf)
    -- 퀘스트 대상 바 보라색 최우선, dik, 2026-10-05
    if uf.markBar == true then
        uf.health:SetColorToken("QUEST_BAR")
        return
    end
    -- 선점 몹 바 회색, dik, 2026-10-05
    if uf.markTapped == true then
        uf.health:SetColorToken("HEALTH_TAPPED")
        return
    end
    -- 붉은색 고정 키 교체(targetRedFixed), dik, 2026-10-01
    if uf.key == "target" and IsOn("targetRedFixed") then
        uf.health:SetColorToken("HEALTH_RED")
        return
    end
    local unit = uf.unit
    local _, classFile = UnitClass(unit)
    local reaction = nil
    if ns.HasAPI("UnitReaction") then
        reaction = UnitReaction(unit, "player")
    end
    local r, g, b, token = ns.CombatHud.PickHealthColor(IsOn("classColor"), UnitIsPlayer(unit), classFile, reaction)
    if r then
        uf.health:SetColor(r, g, b)
    else
        uf.health:SetColorToken(token)
    end
end

-- 체력 바·색·글자 채우기, dik, 2026-10-01
local function FillHealth(uf)
    local C = ns.CombatHud
    local unit = uf.unit
    local cur, max = C.ReadHealth(unit)
    local dead = C.IsDead(unit)
    uf.health:SetRange(0, C.BarMax(max))
    if dead then
        uf.health:SetValue(0)
    else
        uf.health:SetValue(C.BarValue(cur))
    end

    -- 색 선택을 헬퍼로 이동, dik, 2026-10-01
    ApplyHealthColor(uf)

    FillPercent(uf, dead)

    -- 체력 값 쌍 표시(현재 / 최대), dik, 2026-10-01
    if IsOn("showHealthText") then
        uf.valueText:Show()
        ShowValuePair(uf.valueText, cur, max, ShowCurOnly)
    else
        uf.valueText:Hide()
    end
end

-- 자원 바 채우기, dik, 2026-10-01
local function FillPower(uf)
    if not uf.powerOn then
        return
    end
    local C = ns.CombatHud
    local cur, max, token = C.ReadPower(uf.unit)
    if not ns.IsSecret(max) and (type(max) ~= "number" or max <= 0) then
        uf.power:Hide()
        return
    end
    uf.power:SetRange(0, C.BarMax(max))
    uf.power:SetValue(C.BarValue(cur))
    local r, g, b, colorToken = C.PickPowerColor(token)
    if r then
        uf.power:SetColor(r, g, b)
    else
        uf.power:SetColorToken(colorToken)
    end
    uf.power:Show()
    -- 자원 값 쌍 표시, dik, 2026-10-01
    if IsOn("showPowerText") then
        uf.powerText:Show()
        ShowValuePair(uf.powerText, cur, max, ShowCurOnly)
    else
        uf.powerText:Hide()
    end
end

-- 대상 본문 표시 갱신(유닛 있음 여부 반환), dik, 2026-10-01
local function UpdateVisibility(uf)
    -- 대상의 대상도 존재 판정, dik, 2026-10-01
    if uf.key ~= "target" and uf.key ~= "targettarget" then
        return true
    end
    local exists = UnitExists(uf.unit)
    if not ns.IsSecret(exists) and exists ~= true then
        uf.body:Hide()
        -- 넓은 바 꼬리표는 hud 자식이라 명시 숨김, dik, 2026-10-05
        if uf.rankText then
            uf.rankText:Hide()
        end
        return false
    end
    uf.body:Show()
    return true
end

-- 넓은 대상 바 부분 채우기, dik, 2026-10-01
local function FillTargetBar(uf, doInfo, doHealth)
    local C = ns.CombatHud
    if doHealth then
        local cur, max = C.ReadHealth(uf.unit)
        local dead = C.IsDead(uf.unit)
        uf.health:SetRange(0, C.BarMax(max))
        if dead then
            uf.health:SetValue(0)
        else
            uf.health:SetValue(C.BarValue(cur))
        end
        ApplyHealthColor(uf)
        FillPercent(uf, dead)
        if IsOn("targetShowValue") then
            uf.valueText:Show()
            -- 값 쌍 표시, 실패 시 축약값, dik, 2026-10-01
            ShowValuePair(uf.valueText, cur, max, ShowAbbrevValue)
        else
            uf.valueText:Hide()
        end
    end
    if doInfo then
        local value = C.TargetNameText(UnitName(uf.unit))
        -- 퀘스트 대상이면 보라색 이름, dik, 2026-10-05
        local nameToken, nameColor = uf.nameToken or "FONT_SMALL", "TEXT"
        local quest, barChanged = ApplyMark(uf)
        if quest then
            nameToken, nameColor = Theme.OutlineToken(nameToken), "QUEST_TARGET"
        end
        -- info 뒤 바 색 변경 시 같은 주기 재적용, dik, 2026-10-05
        if barChanged then
            ApplyHealthColor(uf)
        end
        ApplyNameFont(uf.nameText, nameToken, value, nameColor)
        uf.nameText:SetText(value)
    end
end

-- 대상의 대상 부분 채우기, dik, 2026-10-01
local function FillToT(uf, doInfo, doHealth)
    local C = ns.CombatHud
    if doHealth then
        local cur, max = C.ReadHealth(uf.unit)
        local dead = C.IsDead(uf.unit)
        uf.health:SetRange(0, C.BarMax(max))
        if dead then
            uf.health:SetValue(0)
        else
            uf.health:SetValue(C.BarValue(cur))
        end
        ApplyHealthColor(uf)
        FillPercent(uf, dead)
    end
    if doInfo then
        local name = C.NameText(UnitName(uf.unit))
        if not ns.IsSecret(name) and name == nil then
            name = L.VALUE_UNKNOWN
        end
        -- 퀘스트 대상이면 보라색 이름, dik, 2026-10-05
        local nameToken, nameColor = uf.nameToken or "FONT_SMALL", "TEXT"
        local quest, barChanged = ApplyMark(uf)
        if quest then
            nameToken, nameColor = Theme.OutlineToken(nameToken), "QUEST_TARGET"
        end
        -- info 뒤 바 색 변경 시 같은 주기 재적용, dik, 2026-10-05
        if barChanged then
            ApplyHealthColor(uf)
        end
        ApplyNameFont(uf.nameText, nameToken, name, nameColor)
        uf.nameText:SetText(name)
    end
end

-- 유닛 부분 채우기, dik, 2026-10-01
local function FillUnit(uf, doInfo, doHealth, doPower, doAura)
    if not UpdateVisibility(uf) then
        return
    end
    -- 대상의 대상은 자원·디버프 없음, dik, 2026-10-01
    if uf.tot then
        FillToT(uf, doInfo, doHealth)
        return
    end
    -- 넓은 바는 머리줄·자원 없음, dik, 2026-10-01
    if uf.wide then
        FillTargetBar(uf, doInfo, doHealth)
    else
        if doInfo and FillInfo(uf) then
            ApplyHealthColor(uf)
        end
        if doHealth then
            FillHealth(uf)
        end
        if doPower then
            FillPower(uf)
        end
    end
    if doAura then
        FillAura(uf)
    end
end

-- 유닛 프레임 생성, dik, 2026-10-01
local function BuildUnit(u)
    local pad = Theme.PAD / 3
    local half = Theme.GAP / 2
    local uf = { def = u, key = u.key, unit = u.unit, icons = {}, iconCount = 0, width = DEFAULT_WIDTH }

    uf.hud = ns.Display.CreateHudFrame(MODULE_ID, u.key, u.hud)
    uf.body = CreateFrame("Frame", nil, uf.hud, "BackdropTemplate")
    uf.body:SetAllPoints(uf.hud)
    Theme.ApplyBackdrop(uf.body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    uf.measure = Widgets.CreateLabel(uf.body, "FONT_SMALL", "TEXT")
    uf.measure:SetText("0")
    uf.measure:Hide()

    uf.level = Widgets.CreateLabel(uf.body, "FONT_SMALL", "TEXT_DIM")
    uf.level:SetWordWrap(false)
    uf.name = Widgets.CreateLabel(uf.body, "FONT_SMALL", "TEXT")
    uf.name:SetWordWrap(false)
    -- 대상 강조 테두리 기준값·꼬리표(대상만), dik, 2026-10-05
    uf.borderToken = "BORDER"
    if u.key == "target" then
        uf.rankText = Widgets.CreateLabel(uf.body, "FONT_SMALL_OUTLINE", "TEXT")
        uf.rankText:SetPoint("LEFT", uf.level, "RIGHT", half, 0)
        uf.rankText:SetWordWrap(false)
        uf.rankText:Hide()
    end

    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    uf.health = Widgets.CreateBar(uf.body, { height = GetNumber("healthHeight", DEFAULT_HEALTH_H), readable = true })
    local overlay = CreateFrame("Frame", nil, uf.health)
    overlay:SetAllPoints(uf.health)
    overlay:SetFrameLevel(uf.health:GetFrameLevel() + 4)
    uf.valueText = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.valueText:SetPoint("LEFT", overlay, "LEFT", half, 0)
    uf.valueText:SetWordWrap(false)
    uf.percentText = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.percentText:SetPoint("RIGHT", overlay, "RIGHT", -half, 0)
    uf.percentText:SetJustifyH("RIGHT")
    uf.percentText:SetWordWrap(false)

    -- 자원 바 생성 높이 설정 반영, dik, 2026-10-01
    uf.power = Widgets.CreateBar(uf.body, { height = GetNumber("powerHeight", DEFAULT_POWER_H), readable = true })
    uf.power:Hide()
    -- 자원 바 글자 겹침 프레임, dik, 2026-10-01
    local powerOverlay = CreateFrame("Frame", nil, uf.power)
    powerOverlay:SetAllPoints(uf.power)
    powerOverlay:SetFrameLevel(uf.power:GetFrameLevel() + 4)
    uf.powerText = Widgets.CreateLabel(powerOverlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.powerText:SetPoint("LEFT", powerOverlay, "LEFT", half, 0)
    uf.powerText:SetWordWrap(false)

    uf.auraRow = CreateFrame("Frame", nil, uf.body)
    uf.auraRow:SetPoint("TOPLEFT", uf.body, "BOTTOMLEFT", 0, -AURA_ROW_GAP)

    if u.key == "player" then
        uf.durability = ns.Display.CreateInfoText(uf.body, "durability", "combatHud:durability", nil)
        uf.durability:SetPoint("TOPRIGHT", uf.body, "TOPRIGHT", -pad, -pad)
        uf.durability:SetActive(IsOn("showDurability"))
    end

    LayoutUnit(uf, GetNumber("frameWidth", DEFAULT_WIDTH))
    uf.hud:ApplySavedPosition()
    uf.hud:Show()
    uf.hud:SetHudActive(true)

    frames[u.key] = uf
    frameList[#frameList + 1] = uf
    -- both 공유 dirty 표 보존, dik, 2026-10-01
    dirty[u.key] = dirty[u.key] or {}
    MarkAll(u.key)
    return uf
end

-- 넓은 대상 바 생성, dik, 2026-10-01
local function BuildTargetBar(u)
    local half = Theme.GAP / 2
    local uf = { def = u, key = u.key, unit = u.unit, icons = {}, iconCount = 0, width = DEFAULT_TARGET_W, wide = true }

    uf.hud = ns.Display.CreateHudFrame(MODULE_ID, "targetBar", ns.CombatHud.HUD_TARGET_BAR)
    uf.body = CreateFrame("Frame", nil, uf.hud, "BackdropTemplate")
    uf.body:SetAllPoints(uf.hud)
    Theme.ApplyBackdrop(uf.body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    uf.health = Widgets.CreateBar(uf.body, { height = DEFAULT_TARGET_H - TARGET_PAD * 2, readable = true })
    uf.overlay = CreateFrame("Frame", nil, uf.health)
    uf.overlay:SetAllPoints(uf.health)
    uf.overlay:SetFrameLevel(uf.health:GetFrameLevel() + 4)
    uf.percentText = Widgets.CreateLabel(uf.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.percentText:SetPoint("LEFT", uf.overlay, "LEFT", half, 0)
    uf.percentText:SetWordWrap(false)
    uf.valueText = Widgets.CreateLabel(uf.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.valueText:SetPoint("RIGHT", uf.overlay, "RIGHT", -half, 0)
    uf.valueText:SetJustifyH("RIGHT")
    uf.valueText:SetWordWrap(false)
    uf.nameText = Widgets.CreateLabel(uf.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.nameText:SetJustifyH("CENTER")
    uf.nameText:SetWordWrap(false)
    -- 대상 강조 테두리 기준값·꼬리표, dik, 2026-10-05
    uf.borderToken = "BORDER"
    uf.rankText = Widgets.CreateLabel(uf.hud, "FONT_SMALL_OUTLINE", "TEXT")
    uf.rankText:SetPoint("BOTTOMLEFT", uf.hud, "TOPLEFT", 0, 2)
    uf.rankText:SetWordWrap(false)
    uf.rankText:Hide()

    uf.auraRow = CreateFrame("Frame", nil, uf.body)
    uf.auraRow:SetPoint("TOPLEFT", uf.body, "BOTTOMLEFT", 0, -AURA_ROW_GAP)

    LayoutTargetBar(uf)
    uf.hud:ApplySavedPosition()
    uf.hud:Show()
    uf.hud:SetHudActive(true)

    frames[u.key] = uf
    frameList[#frameList + 1] = uf
    -- both 공유 dirty 표 보존, dik, 2026-10-01
    dirty[u.key] = dirty[u.key] or {}
    MarkAll(u.key)
    return uf
end

-- 대상의 대상 프레임 생성, dik, 2026-10-01
local function BuildToT()
    local half = Theme.GAP / 2
    local u = ns.CombatHud.TOT_UNIT
    local uf = { def = u, key = "targettarget", unit = "targettarget", tot = true, icons = {}, iconCount = 0, width = DEFAULT_TOT_W }
    local opts = ns.CombatHud.HUD_TOT_WIDE
    if targetStyle == "classic" then
        opts = ns.CombatHud.HUD_TOT_CLASSIC
    end

    uf.hud = ns.Display.CreateHudFrame(MODULE_ID, "targetTarget", opts)
    uf.body = CreateFrame("Frame", nil, uf.hud, "BackdropTemplate")
    uf.body:SetAllPoints(uf.hud)
    Theme.ApplyBackdrop(uf.body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    uf.health = Widgets.CreateBar(uf.body, { height = DEFAULT_TOT_H - TARGET_PAD * 2, readable = true })
    uf.overlay = CreateFrame("Frame", nil, uf.health)
    uf.overlay:SetAllPoints(uf.health)
    uf.overlay:SetFrameLevel(uf.health:GetFrameLevel() + 4)
    uf.percentText = Widgets.CreateLabel(uf.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.percentText:SetPoint("RIGHT", uf.overlay, "RIGHT", -half, 0)
    uf.percentText:SetJustifyH("RIGHT")
    uf.percentText:SetWordWrap(false)
    uf.nameText = Widgets.CreateLabel(uf.overlay, "FONT_SMALL_OUTLINE", "TEXT")
    uf.nameText:SetJustifyH("LEFT")
    uf.nameText:SetWordWrap(false)
    -- 대상 강조 테두리 기준값, dik, 2026-10-05
    uf.borderToken = "BORDER"

    LayoutToT(uf)
    uf.hud:ApplySavedPosition()
    uf.hud:Show()
    uf.hud:SetHudActive(true)

    frames[u.key] = uf
    frameList[#frameList + 1] = uf
    dirty[u.key] = dirty[u.key] or {}
    MarkAll(u.key)
    return uf
end

-- 재배치(전투 밖 전용), dik, 2026-10-01
local function Relayout()
    if not active then
        return
    end
    local width = GetNumber("frameWidth", DEFAULT_WIDTH)
    for i = 1, #frameList do
        local uf = frameList[i]
        -- 스타일별 배치·배율 변경 시 저장 위치 재적용, dik, 2026-10-01
        local changed
        -- 대상의 대상 재배치 분기 추가, dik, 2026-10-01
        if uf.tot then
            changed = LayoutToT(uf)
        elseif uf.wide then
            changed = LayoutTargetBar(uf)
        else
            changed = LayoutUnit(uf, width)
        end
        if changed then
            uf.hud:ApplySavedPosition()
        end
    end
    MarkEveryUnit()
end

-- 재배치 예약, dik, 2026-10-01
local function ScheduleRelayout()
    ns.Display.RunOutOfCombat("combatHud:layout", Relayout)
end

-- 모든 버튼 마우스 상태 적용(전부 성공 여부 반환), dik, 2026-10-01
local function ApplyMouseAll()
    local allOk = true
    for i = 1, #buttons do
        if not ns.CombatHudSecure.SetClickMouse(buttons[i], not lastMoving) then
            allOk = false
        end
    end
    return allOk
end

-- 보안 작업(버튼 생성·기본 프레임 숨기기), dik, 2026-10-01
-- 기본 프레임 숨기기 제거(클릭 버튼만), dik, 2026-10-01
local function RunSecure()
    if not active or secureDone then
        return
    end
    local S = ns.CombatHudSecure
    if not S or ns.CombatHud.IsBlocked() then
        ReportPartial()
        return
    end
    if not S.CanTouch() then
        if not ns.HasAPI("InCombatLockdown") then
            AddMissing("InCombatLockdown")
            ReportPartial()
            return
        end
        securePending = true
        return
    end
    secureDone = true
    securePending = false

    local made = 0
    if IsOn("clickTargeting") and support.click then
        -- 유닛 메뉴 설정 1회 읽기(WFA-031), dik, 2026-10-02
        local menuOn = IsOn("unitMenu")
        for i = 1, #frameList do
            local uf = frameList[i]
            -- 대상의 대상도 대상 감시 사용, dik, 2026-10-01
            local watch = uf.key ~= "player"
            if not (watch and not support.targetWatch) then
                -- 메뉴 인자 전달(WFA-031), dik, 2026-10-02
                local btn = S.CreateClickButton(uf.hud, uf.unit, watch, menuOn)
                if btn then
                    buttons[#buttons + 1] = btn
                    made = made + 1
                end
            end
        end
        if made == 0 then
            ns.Print(L.MSG_COMBATHUD_DISPLAY_ONLY)
        elseif ns.Display.IsMoveMode() then
            lastMoving = true
            ApplyMouseAll()
        end
    elseif IsOn("clickTargeting") then
        ns.Print(L.MSG_COMBATHUD_DISPLAY_ONLY)
    end

    ReportPartial()
end

-- 이동 모드 전환 시 버튼 마우스 전환, dik, 2026-10-01
local function OnMoveMode(moving)
    if not active or #buttons == 0 then
        return
    end
    lastMoving = moving == true
    if not ApplyMouseAll() then
        ns.Display.RunOutOfCombat("combatHud:clickMouse", function()
            if not ApplyMouseAll() then
                mousePending = true
            end
        end)
    end
end

-- 재시도 대기 처리(가드 실패분), dik, 2026-10-01
local function ProcessRetry()
    if not (securePending or mousePending) then
        retryCount = 0
        return
    end
    if IsInCombat() then
        return
    end
    retryCount = retryCount + 1
    if retryCount > SECURE_RETRY_MAX then
        securePending = false
        mousePending = false
        retryCount = 0
        return
    end
    if securePending then
        securePending = false
        RunSecure()
    end
    if mousePending then
        mousePending = false
        if not ApplyMouseAll() then
            mousePending = true
        end
    end
end

-- 갱신 주기 처리(이벤트 프레임 OnUpdate), dik, 2026-10-01
local function OnUpdate(_, elapsed)
    if not active then
        return
    end
    sinceRefresh = sinceRefresh + elapsed
    sinceAura = sinceAura + elapsed
    -- 대상의 대상 0.2초 주기 갱신, dik, 2026-10-01
    if frames.targettarget then
        totAcc = totAcc + elapsed
        if totAcc >= TOT_TICK then
            totAcc = 0
            local d = dirty.targettarget
            d.info = true
            d.health = true
        end
    end
    if pollMode then
        pollAcc = pollAcc + elapsed
        if pollAcc >= POLL_TICK then
            pollAcc = 0
            for i = 1, #frameList do
                local d = dirty[frameList[i].key]
                d.health = true
                d.power = true
            end
        end
    end
    if sinceRefresh >= REFRESH_MIN then
        local ran = false
        for i = 1, #frameList do
            local uf = frameList[i]
            local d = dirty[uf.key]
            if d.health or d.power or d.info then
                ran = true
                FillUnit(uf, d.info, d.health, d.power, false)
            end
        end
        -- 같은 키 유닛 표 모두 채운 뒤 플래그 해제, dik, 2026-10-01
        if ran then
            for i = 1, #frameList do
                local d = dirty[frameList[i].key]
                d.info = false
                d.health = false
                d.power = false
            end
            sinceRefresh = 0
        end
    end
    if sinceAura >= AURA_MIN then
        local ran = false
        for i = 1, #frameList do
            local uf = frameList[i]
            local d = dirty[uf.key]
            if d.aura then
                ran = true
                FillUnit(uf, false, false, false, true)
            end
        end
        -- 같은 키 유닛 표 모두 채운 뒤 플래그 해제, dik, 2026-10-01
        if ran then
            for i = 1, #frameList do
                dirty[frameList[i].key].aura = false
            end
            sinceAura = 0
        end
    end
    -- 오라 남은 시간 글자 0.2초 주기 갱신(WFA-045), dik, 2026-10-03
    sinceAuraTime = sinceAuraTime + elapsed
    if sinceAuraTime >= AURA_TIME_TICK then
        sinceAuraTime = 0
        local now = GetTime()
        for i = 1, #frameList do
            local uf = frameList[i]
            if uf.hud:IsVisible() then
                for k = 1, uf.iconCount do
                    local icon = uf.icons[k]
                    if icon then
                        UpdateIconTime(icon, now)
                    end
                end
            end
        end
    end
    ProcessRetry()
end

-- 이벤트 처리, dik, 2026-10-01
-- 동작 차단 분기 제거(코어 공통 처리로 이전), dik, 2026-10-02
local function OnEvent(_, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        ns.CombatHud.ResetDebuffFailure()
        MarkAll("target")
        -- 대상 변경 시 대상의 대상도 갱신, dik, 2026-10-01
        MarkAll("targettarget")
        return
    end
    -- 대상의 대상 변경 이벤트 처리, dik, 2026-10-01
    if event == "UNIT_TARGET" then
        if not ns.IsSecret(arg1) and arg1 == "target" then
            MarkAll("targettarget")
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        MarkEveryUnit()
        return
    end
    local parts = ns.CombatHud.UNIT_EVENTS[event]
    if not parts or ns.IsSecret(arg1) then
        return
    end
    if arg1 == "player" or arg1 == "target" then
        MarkParts(arg1, parts)
    end
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-01
local function CreateEventFrame()
    local C = ns.CombatHud
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
    local names = {}
    for eventName in pairs(C.UNIT_EVENTS) do
        names[#names + 1] = eventName
    end
    for _, eventName in ipairs(C.GLOBAL_EVENTS) do
        names[#names + 1] = eventName
    end
    local _, failed = RegisterEvents(eventFrame, names)
    for _, name in ipairs(failed) do
        AddMissing(name)
        if name == "UNIT_HEALTH" or name == "UNIT_POWER_UPDATE" then
            pollMode = true
        end
    end
    -- 대상의 대상 이벤트 등록(실패 무안내), dik, 2026-10-01
    if frames.targettarget then
        RegisterEvents(eventFrame, { "UNIT_TARGET" })
    end
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    active = true

    local wanted = {
        power = IsOn("showPower"),
        percentSecret = IsOn("showHealthPercent"),
        -- 버프 설정도 오라 API 부분 안내 대상(WFA-039), dik, 2026-10-02
        debuffs = IsOn("targetDebuffs") or IsOn("playerDebuffs") or IsOn("targetBuffs") or IsOn("playerBuffs"),
        click = IsOn("clickTargeting"),
        targetWatch = IsOn("clickTargeting"),
        -- 시전 바 API 부분 안내 대상 추가, dik, 2026-10-01
        cast = IsOn("targetCastBar"),
    }
    local missing
    support, missing = ns.CombatHud.GetFeatureSupport(wanted)
    for i = 1, #missing do
        AddMissing(missing[i])
    end
    -- 오라 툴팁 지원 판정 1회(T1), dik, 2026-10-02
    tooltipOk = type(GameTooltip) == "table" and type(GameTooltip.SetUnitAura) == "function"

    -- 대상 모양을 READY 에서 1회 결정, dik, 2026-10-01
    targetStyle = ns.CombatHud.ResolveTargetStyle(ns.GetSetting(MODULE_ID, "targetStyle"))
    for _, u in ipairs(ns.CombatHud.UNITS) do
        if IsOn(u.setting) then
            -- both 면 기존형 다음 넓은 바, dik, 2026-10-01
            if u.key == "target" and targetStyle == "wide" then
                BuildTargetBar(u)
            elseif u.key == "target" and targetStyle == "both" then
                BuildUnit(u)
                BuildTargetBar(u)
            else
                BuildUnit(u)
            end
        end
    end

    -- 대상의 대상은 대상 프레임 설정과 독립, dik, 2026-10-01
    if IsOn("targetOfTarget") then
        BuildToT()
    end

    CreateEventFrame()

    if IsInCombat() then
        ns.Print(L.MSG_COMBATHUD_PENDING)
    end
    ns.Display.RunOutOfCombat("combatHud:secure", RunSecure)
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            ScheduleRelayout()
            MarkEveryUnit()
        end
        return
    end
    if scope ~= MODULE_ID then
        return
    end
    if ns.CombatHud.RELOAD_KEYS[key] then
        ns.Print(L.MSG_RELOAD_REQUIRED)
        return
    end
    if key == "skinActionBars" then
        return
    end
    -- 크기·배율 설정 추가 및 대상 색·값 갱신, dik, 2026-10-01
    -- 자원 높이 재배치 키 추가, dik, 2026-10-01
    -- 대상의 대상 크기 재배치 키 추가, dik, 2026-10-01
    if key == "frameWidth" or key == "showPower" or key == "healthHeight" or key == "targetWidth"
        or key == "targetHeight" or key == "hudScale" or key == "powerHeight"
        or key == "totWidth" or key == "totHeight" then
        ScheduleRelayout()
    -- 자원 높이·대상 색 키 교체·이름 앵커 재배치, dik, 2026-10-01
    elseif key == "targetRedFixed" or key == "targetShowValue" or key == "showHealthPercent" then
        if key == "targetShowValue" or key == "showHealthPercent" then
            ScheduleRelayout()
        end
        if key == "showHealthPercent" then
            MarkEveryUnit()
        elseif dirty.target then
            dirty.target.health = true
        end
    -- 시전 바 크기는 시전 바 파일 담당, dik, 2026-10-01
    elseif key == "castWidth" or key == "castHeight" then
        return
    elseif key == "bgAlpha" then
        for i = 1, #frameList do
            -- 등급 테두리 색 유지, dik, 2026-10-05
            Theme.ApplyBackdrop(frameList[i].body, "BG", frameList[i].borderToken or "BORDER", value)
        end
    elseif key == "showDurability" then
        local uf = frames.player
        if uf and uf.durability then
            uf.durability:SetActive(value == true)
            AnchorHeader(uf)
        end
    -- 버프 설정 키 추가(WFA-039), dik, 2026-10-02
    elseif key == "targetDebuffs" or key == "targetOnlyMine" or key == "playerDebuffs" or key == "maxDebuffs"
        or key == "targetBuffs" or key == "playerBuffs" or key == "maxBuffs" or key == "hidePermanentBuffs" then
        ns.CombatHud.ResetDebuffFailure()
        for i = 1, #frameList do
            dirty[frameList[i].key].aura = true
        end
    -- 오라 툴팁 마우스 재적용(T2·T4), dik, 2026-10-02
    elseif key == "auraTooltip" then
        ApplyIconMouse()
    else
        MarkEveryUnit()
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
ns.On("HUD_MOVE_MODE", OnMoveMode)
-- 대상 강조 변경 시 대상·대상의 대상 재채움, dik, 2026-10-05
ns.On("UNIT_MARK_CHANGED", function()
    MarkAll("target")
    MarkAll("targettarget")
end)
