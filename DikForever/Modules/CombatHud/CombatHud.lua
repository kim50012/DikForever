-- 전투 HUD 모듈 등록·상수·API 어댑터·순수 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "combatHud"

local failed = false
local blocked = false
local blockedFunc = nil

-- 유한 number 판정(secret 아닌 값 전용), dik, 2026-10-01
local function IsFinite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 색 표 항목의 r·g·b 조회, dik, 2026-10-01
local function ColorOf(colors, key)
    if type(colors) ~= "table" then
        return nil
    end
    local entry = colors[key]
    if type(entry) ~= "table" then
        return nil
    end
    local r, g, b = entry.r, entry.g, entry.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end
    return nil
end

ns.CombatHud = {}
ns.CombatHud.MODULE_ID = MODULE_ID

ns.CombatHud.HUD_PLAYER = {
    label = L.HUD_LABEL_COMBATHUD_PLAYER, point = "CENTER", relativePoint = "CENTER",
    x = -220, y = -160, strata = "LOW",
}

ns.CombatHud.HUD_TARGET = {
    label = L.HUD_LABEL_COMBATHUD_TARGET, point = "CENTER", relativePoint = "CENTER",
    x = 220, y = -160, strata = "LOW",
}

-- 넓은 대상 바 HUD 기본 위치, dik, 2026-10-01
ns.CombatHud.HUD_TARGET_BAR = {
    -- 이동 상자 이름을 넓은 바 전용으로 변경, dik, 2026-10-01
    label = L.HUD_LABEL_COMBATHUD_TARGET_BAR, point = "TOP", relativePoint = "TOP",
    x = 0, y = -120, strata = "LOW",
}

-- 대상 시전 바 HUD 기본 위치(넓은 바용), dik, 2026-10-01
ns.CombatHud.HUD_CAST_WIDE = {
    label = L.HUD_LABEL_COMBATHUD_CAST, point = "TOP", relativePoint = "TOP",
    x = 0, y = -175, strata = "LOW",
}

-- 대상 시전 바 HUD 기본 위치(기존형용), dik, 2026-10-01
ns.CombatHud.HUD_CAST_CLASSIC = {
    label = L.HUD_LABEL_COMBATHUD_CAST, point = "CENTER", relativePoint = "CENTER",
    x = 220, y = -230, strata = "LOW",
}

-- 대상의 대상 HUD 기본 위치(넓은 바용), dik, 2026-10-01
ns.CombatHud.HUD_TOT_WIDE = {
    label = L.HUD_LABEL_COMBATHUD_TOT, point = "TOP", relativePoint = "TOP",
    x = 290, y = -120, strata = "LOW",
}

-- 대상의 대상 HUD 기본 위치(기존형용), dik, 2026-10-01
ns.CombatHud.HUD_TOT_CLASSIC = {
    label = L.HUD_LABEL_COMBATHUD_TOT, point = "CENTER", relativePoint = "CENTER",
    x = 400, y = -160, strata = "LOW",
}

-- 대상 프레임 모양 선택지, dik, 2026-10-01
ns.CombatHud.TARGET_STYLE_ITEMS = {
    { value = "wide", text = L.COMBATHUD_STYLE_WIDE },
    { value = "classic", text = L.COMBATHUD_STYLE_CLASSIC },
    -- 둘 다 선택지 추가, dik, 2026-10-01
    { value = "both", text = L.COMBATHUD_STYLE_BOTH },
}

-- 체력 값 축약 API 후보(앞에서부터), dik, 2026-10-01
ns.CombatHud.ABBREV_APIS = { "AbbreviateNumbers", "AbbreviateLargeNumbers" }

-- 유닛별 버프 설정 키 추가(WFA-039), dik, 2026-10-02
ns.CombatHud.UNITS = {
    { key = "player", unit = "player", setting = "playerFrame", debuffSetting = "playerDebuffs",
      buffSetting = "playerBuffs", hud = ns.CombatHud.HUD_PLAYER },
    { key = "target", unit = "target", setting = "targetFrame", debuffSetting = "targetDebuffs",
      buffSetting = "targetBuffs", hud = ns.CombatHud.HUD_TARGET },
}

-- 대상의 대상 유닛 정의, dik, 2026-10-01
ns.CombatHud.TOT_UNIT = { key = "targettarget", unit = "targettarget", setting = "targetOfTarget" }

-- 대상 프레임 모양 변경도 /reload 대상, dik, 2026-10-01
-- 기본 프레임 숨기기 키 제거, dik, 2026-10-01
-- 시전 바·대상의 대상 켜기도 /reload 대상, dik, 2026-10-01
-- 오른쪽 클릭 메뉴 키 /reload 대상 추가(WFA-031), dik, 2026-10-02
ns.CombatHud.RELOAD_KEYS = {
    playerFrame = true, targetFrame = true, targetStyle = true, clickTargeting = true,
    targetCastBar = true, targetOfTarget = true, unitMenu = true,
}

ns.CombatHud.UNIT_EVENTS = {
    UNIT_HEALTH = { "health" },
    UNIT_MAXHEALTH = { "health" },
    UNIT_POWER_UPDATE = { "power" },
    UNIT_MAXPOWER = { "power" },
    UNIT_DISPLAYPOWER = { "power" },
    UNIT_NAME_UPDATE = { "info", "health" },
    UNIT_LEVEL = { "info", "health" },
    UNIT_FACTION = { "info", "health" },
    UNIT_AURA = { "aura" },
}

-- 차단 이벤트 코어 이관으로 제거(WFA-040), dik, 2026-10-02
ns.CombatHud.GLOBAL_EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD",
}

-- 대상 시전 바 핵심 이벤트, dik, 2026-10-01
ns.CombatHud.CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- 대상 시전 바 선택 이벤트, dik, 2026-10-01
ns.CombatHud.CAST_EVENTS_OPTIONAL = {
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

-- 대상 시전 바 기능 그룹 추가, dik, 2026-10-01
ns.CombatHud.FEATURE_APIS = {
    { key = "power", apis = { "UnitPower", "UnitPowerMax", "UnitPowerType" } },
    { key = "percentSecret", apis = { "UnitHealthPercent", "CurveConstants.ScaleTo100" } },
    { key = "debuffs", apis = { "C_UnitAuras.GetAuraDataByIndex" } },
    { key = "click", apis = { "InCombatLockdown", "SecureUnitButton_OnLoad" } },
    { key = "targetWatch", apis = { "RegisterUnitWatch" } },
    { key = "cast", apis = { "UnitCastingInfo", "UnitChannelInfo" } },
}

ns.CombatHud.ACTION_BUTTON_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}

ns.CombatHud.ACTION_BUTTON_COUNT = 12
ns.CombatHud.ACTION_HIDE_KEYS = { "NormalTexture", "SlotArt", "SlotBackground" }
ns.CombatHud.ACTION_FONT_KEYS = { "HotKey", "Count", "Name" }
ns.CombatHud.ACTION_OWNER = "combatHud:actionBar"

-- 기능별 API 지원·없는 경로 판정, dik, 2026-10-01
function ns.CombatHud.GetFeatureSupport(wanted)
    local wantAll = type(wanted) ~= "table"
    local support = {}
    local missing = {}
    local seen = {}
    for _, feature in ipairs(ns.CombatHud.FEATURE_APIS) do
        local lost = ns.GetMissingAPIs(feature.apis)
        support[feature.key] = #lost == 0
        if wantAll or wanted[feature.key] then
            for _, path in ipairs(lost) do
                if not seen[path] then
                    seen[path] = true
                    missing[#missing + 1] = path
                end
            end
        end
    end
    return support, missing
end

-- 바 값 결정, dik, 2026-10-01
function ns.CombatHud.BarValue(v)
    if ns.IsSecret(v) then
        return v
    end
    if IsFinite(v) then
        return v
    end
    return 0
end

-- 바 최댓값 결정, dik, 2026-10-01
function ns.CombatHud.BarMax(v)
    if ns.IsSecret(v) then
        return v
    end
    if IsFinite(v) and v > 0 then
        return v
    end
    return 1
end

-- 체력 비율 글자(값 둘 다 plain 일 때만), dik, 2026-10-01
function ns.CombatHud.PercentFromValues(cur, max)
    if ns.IsSecret(cur) or ns.IsSecret(max) then
        return nil
    end
    if IsFinite(cur) and IsFinite(max) and max > 0 and cur >= 0 then
        return string.format(L.FMT_PERCENT_INT, math.floor(cur * 100 / max))
    end
    return nil
end

-- 레벨 글자, dik, 2026-10-01
function ns.CombatHud.LevelText(level)
    if ns.IsSecret(level) then
        return level
    end
    if type(level) == "number" then
        if level == -1 then
            return L.COMBATHUD_LEVEL_UNKNOWN
        end
        if IsFinite(level) and level >= 1 then
            return tostring(math.floor(level))
        end
    end
    return nil
end

-- 이름 글자, dik, 2026-10-01
function ns.CombatHud.NameText(name)
    if ns.IsSecret(name) then
        return name
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

-- 체력 % 어댑터(값, 모드 반환), dik, 2026-10-01
function ns.CombatHud.GetHealthPercent(unit)
    if ns.HasAPI("UnitHealth") and ns.HasAPI("UnitHealthMax") then
        local text = ns.CombatHud.PercentFromValues(UnitHealth(unit), UnitHealthMax(unit))
        if text then
            return text, "text"
        end
    end
    if ns.HasAPI("UnitHealthPercent") and ns.HasAPI("CurveConstants.ScaleTo100") then
        local p = UnitHealthPercent(unit, false, CurveConstants.ScaleTo100)
        if ns.IsSecret(p) then
            return p, "secret"
        end
        if IsFinite(p) then
            return string.format(L.FMT_PERCENT_INT, math.floor(p + 0.5)), "text"
        end
    end
    return nil, "none"
end

-- 체력 원시값 조회, dik, 2026-10-01
function ns.CombatHud.ReadHealth(unit)
    if ns.HasAPI("UnitHealth") and ns.HasAPI("UnitHealthMax") then
        return UnitHealth(unit), UnitHealthMax(unit)
    end
    return nil, nil
end

-- 자원 원시값·토큰 조회, dik, 2026-10-01
function ns.CombatHud.ReadPower(unit)
    if not (ns.HasAPI("UnitPower") and ns.HasAPI("UnitPowerMax") and ns.HasAPI("UnitPowerType")) then
        return nil, nil, nil
    end
    local _, token = UnitPowerType(unit)
    return UnitPower(unit), UnitPowerMax(unit), token
end

-- 사망 판정, dik, 2026-10-01
function ns.CombatHud.IsDead(unit)
    if not ns.HasAPI("UnitIsDeadOrGhost") then
        return false
    end
    local dead = UnitIsDeadOrGhost(unit)
    if ns.IsSecret(dead) then
        return false
    end
    return dead == true
end

-- 체력 바 색 선택, dik, 2026-10-01
function ns.CombatHud.PickHealthColor(useClass, isPlayer, classFile, reaction, classColors, reactionColors)
    if useClass ~= true then
        return nil, nil, nil, "ACCENT"
    end
    if classColors == nil then
        classColors = RAID_CLASS_COLORS
    end
    if reactionColors == nil then
        reactionColors = FACTION_BAR_COLORS
    end
    if ns.IsSecret(isPlayer) then
        return nil, nil, nil, "ACCENT"
    end
    if isPlayer == true then
        if not ns.IsSecret(classFile) and type(classFile) == "string" then
            -- 직업 바 색 덮어쓰기 적용, dik, 2026-10-02
            local r, g, b = ns.ClassBarColor(classFile, classColors)
            if r then
                return r, g, b, nil
            end
        end
        return nil, nil, nil, "ACCENT"
    end
    if isPlayer == false and not ns.IsSecret(reaction) and IsFinite(reaction) then
        local r, g, b = ColorOf(reactionColors, reaction)
        if r then
            return r, g, b, nil
        end
        if reaction <= 3 then
            return nil, nil, nil, "DANGER"
        end
    end
    return nil, nil, nil, "ACCENT"
end

-- 자원 바 색 선택, dik, 2026-10-01
function ns.CombatHud.PickPowerColor(token, powerColors)
    if powerColors == nil then
        powerColors = PowerBarColor
    end
    if not ns.IsSecret(token) and type(token) == "string" then
        local r, g, b = ColorOf(powerColors, token)
        if r then
            return r, g, b, nil
        end
    end
    return nil, nil, nil, "BAR_SECONDARY"
end

-- 디버프 필터 문자열, dik, 2026-10-01
function ns.CombatHud.BuildDebuffFilter(onlyMine)
    if onlyMine == true then
        return "HARMFUL|PLAYER"
    end
    return "HARMFUL"
end

-- 디버프 목록 조회 어댑터(AuraData 무복사), dik, 2026-10-01
function ns.CombatHud.ReadDebuffs(unit, filter, max)
    if failed then
        return {}, "error"
    end
    if not ns.HasAPI("C_UnitAuras.GetAuraDataByIndex") then
        return {}, "unsupported"
    end
    local list = {}
    if not IsFinite(max) then
        return list, "ok"
    end
    for i = 1, math.floor(max) do
        local ok, aura = xpcall(function() return C_UnitAuras.GetAuraDataByIndex(unit, i, filter) end, geterrorhandler())
        if not ok then
            failed = true
            return list, "error"
        end
        if ns.IsSecret(aura) or type(aura) ~= "table" then
            break
        end
        list[#list + 1] = aura
    end
    return list, "ok"
end

-- 버프 조회 인덱스 상한, dik, 2026-10-02
ns.CombatHud.AURA_SCAN_MAX = 40

-- 버프 필터 문자열, dik, 2026-10-02
function ns.CombatHud.BuildBuffFilter()
    return "HELPFUL"
end

-- 지속시간 없는 상시 오라 판정(secret 은 false), dik, 2026-10-02
function ns.CombatHud.IsPermanentAura(duration)
    if ns.IsSecret(duration) then
        return false
    end
    return IsFinite(duration) and duration <= 0
end

-- 버프 목록 조회 어댑터(AuraData 무복사·API 인덱스 반환), dik, 2026-10-02
function ns.CombatHud.ReadBuffs(unit, max, hidePermanent)
    if failed then
        return {}, "error", {}
    end
    if not ns.HasAPI("C_UnitAuras.GetAuraDataByIndex") then
        return {}, "unsupported", {}
    end
    local list, indices = {}, {}
    if ns.IsSecret(max) or not IsFinite(max) or max < 1 then
        return list, "ok", indices
    end
    local limit = math.floor(max)
    local filter = ns.CombatHud.BuildBuffFilter()
    for i = 1, ns.CombatHud.AURA_SCAN_MAX do
        local ok, aura = xpcall(function() return C_UnitAuras.GetAuraDataByIndex(unit, i, filter) end, geterrorhandler())
        if not ok then
            failed = true
            return list, "error", indices
        end
        if ns.IsSecret(aura) or type(aura) ~= "table" then
            break
        end
        if not (hidePermanent == true and ns.CombatHud.IsPermanentAura(aura.duration)) then
            list[#list + 1] = aura
            indices[#indices + 1] = i
            if #list == limit then
                break
            end
        end
    end
    return list, "ok", indices
end

-- 디버프 조회 오류 플래그 해제, dik, 2026-10-01
function ns.CombatHud.ResetDebuffFailure()
    failed = false
end

-- 오라 중첩 글자, dik, 2026-10-01
function ns.CombatHud.AuraCountText(n)
    if ns.IsSecret(n) then
        return nil
    end
    if IsFinite(n) and n >= 2 then
        return tostring(math.floor(n))
    end
    return nil
end

-- 오라 쿨다운 시작·지속 계산, dik, 2026-10-01
function ns.CombatHud.AuraCooldown(duration, expirationTime)
    if ns.IsSecret(duration) or ns.IsSecret(expirationTime) then
        return nil
    end
    if IsFinite(duration) and IsFinite(expirationTime) and duration > 0 and expirationTime > 0 then
        return expirationTime - duration, duration
    end
    return nil
end

-- 오라 남은 시간 짧은 표기, dik, 2026-10-03
function ns.CombatHud.AuraTimeText(remaining)
    if ns.IsSecret(remaining) or not IsFinite(remaining) or remaining <= 0 then
        return nil
    end
    if remaining >= 3600 then
        return string.format(L.AURA_TIME_HOURS, math.min(99, math.floor(remaining / 3600)))
    end
    if remaining >= 60 then
        return string.format(L.AURA_TIME_MINUTES, math.floor(remaining / 60))
    end
    return tostring(math.max(1, math.floor(remaining)))
end

-- 디버프 아이콘 배치 좌표, dik, 2026-10-01
function ns.CombatHud.LayoutIcons(count, width, size, gap)
    local positions = {}
    if not IsFinite(count) then
        return positions
    end
    local step = size + gap
    local perRow = math.max(1, math.floor((width + gap) / step))
    for k = 1, math.floor(count) do
        positions[k] = {
            ((k - 1) % perRow) * step,
            0 - math.floor((k - 1) / perRow) * step,
        }
    end
    return positions
end

-- 프레임 높이 계산, dik, 2026-10-01
function ns.CombatHud.CalcFrameHeight(headerH, healthH, powerH, showPower, gap, pad)
    local height = pad * 2 + headerH + gap + healthH
    if showPower then
        height = height + gap + powerH
    end
    return height
end

-- 차단 첫 감지 기록(첫 호출만 true), dik, 2026-10-01
function ns.CombatHud.MarkBlocked(funcName)
    if blocked then
        return false
    end
    blocked = true
    if not ns.IsSecret(funcName) and type(funcName) == "string" and funcName ~= "" then
        blockedFunc = funcName
    end
    return true
end

-- 차단 감지 여부, dik, 2026-10-01
function ns.CombatHud.IsBlocked()
    return blocked
end

-- 차단 함수 이름, dik, 2026-10-01
function ns.CombatHud.GetBlockedFunc()
    return blockedFunc
end

-- 코어 차단 통지 수신·1회 안내, dik, 2026-10-02
local function OnActionBlocked(funcName)
    if ns.CombatHud.MarkBlocked(funcName) then
        local shown = funcName
        if type(shown) ~= "string" or shown == "" then
            shown = L.VALUE_UNKNOWN
        end
        ns.Print(L.MSG_COMBATHUD_BLOCKED:format(shown))
    end
end

local abbrevFailed = false

local CJK_RANGES = {
    { 0x2E80, 0x312F }, { 0x3190, 0x9FFF }, { 0xF900, 0xFAFF }, { 0x20000, 0x2FFFF },
}

local HANGUL_RANGES = {
    { 0xAC00, 0xD7A3 }, { 0x1100, 0x11FF }, { 0x3130, 0x318F },
}

-- 대상 프레임 모양 결정, dik, 2026-10-01
function ns.CombatHud.ResolveTargetStyle(value)
    if ns.IsSecret(value) then
        return "wide"
    end
    if value == "classic" then
        return "classic"
    end
    -- 둘 다 선택 반환 추가, dik, 2026-10-01
    if value == "both" then
        return "both"
    end
    return "wide"
end

-- 소수 한 자리 글자(끝 .0 제거), dik, 2026-10-01
local function TrimDecimal(t)
    local text = string.format("%.1f", t)
    if text:sub(-2) == ".0" then
        return text:sub(1, -3)
    end
    return text
end

-- 만·억 단위 축약 글자(plain 전용), dik, 2026-10-01
function ns.CombatHud.AbbrevKorean(v)
    if ns.IsSecret(v) then
        return nil
    end
    if not IsFinite(v) or v < 0 then
        return nil
    end
    local n = math.floor(v)
    if n < 10000 then
        return ns.FormatNumber(n)
    end
    if n < 100000000 then
        return TrimDecimal(math.floor(n / 1000) / 10) .. L.ABBREV_UNIT_MAN
    end
    return TrimDecimal(math.floor(n / 10000000) / 10) .. L.ABBREV_UNIT_EOK
end

-- 현재 / 최대 수치 글자(글자, 모드 반환), dik, 2026-10-01
function ns.CombatHud.ValuePairText(cur, max)
    if ns.IsSecret(cur) or ns.IsSecret(max) then
        return nil, "secret"
    end
    local a, b = ns.CombatHud.AbbrevKorean(cur), ns.CombatHud.AbbrevKorean(max)
    if a == nil and b == nil then
        return nil, "none"
    end
    return string.format(L.FMT_COMBATHUD_VALUE_PAIR, a or L.VALUE_UNKNOWN, b or L.VALUE_UNKNOWN), "text"
end

-- 옛 설정 키 이관(변경 여부 반환), dik, 2026-10-01
function ns.CombatHud.MigrateSettings(store)
    if type(store) ~= "table" then
        return false
    end
    local changed = false
    if store.targetRedBar ~= nil then
        store.targetRedBar = nil
        changed = true
    end
    if store.showHealthValue ~= nil then
        store.showHealthValue = nil
        changed = true
    end
    return changed
end

-- 처음 존재하는 축약 API 이름, dik, 2026-10-01
local function FirstAbbrevAPI()
    for _, name in ipairs(ns.CombatHud.ABBREV_APIS) do
        if ns.HasAPI(name) then
            return name
        end
    end
    return nil
end

-- 넓은 바 체력 값 어댑터(값, 모드 반환), dik, 2026-10-01
function ns.CombatHud.HealthAbbrev(cur)
    if ns.IsSecret(cur) then
        if not abbrevFailed and FirstAbbrevAPI() then
            return cur, "secretApi"
        end
        return cur, "raw"
    end
    local text = ns.CombatHud.AbbrevKorean(cur)
    if text then
        return text, "text"
    end
    return nil, "none"
end

-- 축약 API 호출(원시 반환), dik, 2026-10-01
function ns.CombatHud.CallAbbrevAPI(v)
    if ns.HasAPI("AbbreviateNumbers") then
        return (AbbreviateNumbers(v))
    end
    if ns.HasAPI("AbbreviateLargeNumbers") then
        return (AbbreviateLargeNumbers(v))
    end
    return v
end

-- 축약 실패 첫 기록(첫 호출만 true), dik, 2026-10-01
function ns.CombatHud.MarkAbbrevFailed()
    if abbrevFailed then
        return false
    end
    abbrevFailed = true
    return true
end

-- 축약 실패 여부, dik, 2026-10-01
function ns.CombatHud.IsAbbrevFailed()
    return abbrevFailed
end

-- 넓은 바 이름 글자(장식 여부 반환), dik, 2026-10-01
function ns.CombatHud.TargetNameText(name)
    if ns.IsSecret(name) then
        return name, false
    end
    if type(name) == "string" and name ~= "" then
        return string.format(L.FMT_COMBATHUD_TARGET_NAME, name), true
    end
    return L.VALUE_UNKNOWN, false
end

-- 코드포인트 범위 포함 여부, dik, 2026-10-01
local function InRanges(cp, ranges)
    for i = 1, #ranges do
        local r = ranges[i]
        if cp >= r[1] and cp <= r[2] then
            return true
        end
    end
    return false
end

-- UTF-8 한 글자 디코딩(코드포인트, 바이트 수), dik, 2026-10-01
local function DecodeAt(text, i, len)
    local b = text:byte(i)
    if b < 0x80 then
        return b, 1
    end
    local size, cp
    if b >= 0xC2 and b <= 0xDF then
        size, cp = 2, b - 0xC0
    elseif b >= 0xE0 and b <= 0xEF then
        size, cp = 3, b - 0xE0
    elseif b >= 0xF0 and b <= 0xF4 then
        size, cp = 4, b - 0xF0
    else
        return nil, 1
    end
    if i + size - 1 > len then
        return nil, 1
    end
    for k = 1, size - 1 do
        local c = text:byte(i + k)
        if c < 0x80 or c > 0xBF then
            return nil, 1
        end
        cp = cp * 64 + (c - 0x80)
    end
    return cp, size
end

-- 이름 글자 문자 체계 분류, dik, 2026-10-01
function ns.CombatHud.ClassifyScript(text)
    if ns.IsSecret(text) or type(text) ~= "string" then
        return "default"
    end
    local hasCjk, hasHangul = false, false
    local i, len = 1, #text
    while i <= len do
        local cp, size = DecodeAt(text, i, len)
        if cp then
            if InRanges(cp, CJK_RANGES) then
                hasCjk = true
            elseif InRanges(cp, HANGUL_RANGES) then
                hasHangul = true
            end
        end
        i = i + size
    end
    if not hasCjk then
        return "default"
    end
    if hasHangul then
        return "mixed"
    end
    return "cjk"
end

-- 넓은 바 이름 칸 양옆 여백, dik, 2026-10-01
function ns.CombatHud.TargetNameInset(width)
    if ns.IsSecret(width) or not IsFinite(width) then
        return 0
    end
    return math.floor(width * 0.2)
end

-- 넓은 바 글꼴 토큰, dik, 2026-10-01
function ns.CombatHud.TargetTextFont(height)
    if not ns.IsSecret(height) and IsFinite(height) and height >= 20 then
        return "FONT_BODY"
    end
    return "FONT_SMALL"
end

local castFailed = false

-- 시전 중 판정(이름 secret 이거나 빈 문자열 아님), dik, 2026-10-01
local function HasCastName(name)
    return ns.IsSecret(name) or (type(name) == "string" and name ~= "")
end

-- 대상 시전 조회 어댑터(오류 시 세션 중지·무보관), dik, 2026-10-01
function ns.CombatHud.ReadCast(unit)
    if castFailed then
        return nil
    end
    if ns.HasAPI("UnitCastingInfo") then
        local ok, name, _, texture, startMS, endMS, _, _, notInterruptible =
            xpcall(function() return UnitCastingInfo(unit) end, geterrorhandler())
        if not ok then
            castFailed = true
            return nil
        end
        if HasCastName(name) then
            return "cast", name, texture, startMS, endMS, notInterruptible
        end
    end
    if ns.HasAPI("UnitChannelInfo") then
        local ok, name, _, texture, startMS, endMS, _, notInterruptible =
            xpcall(function() return UnitChannelInfo(unit) end, geterrorhandler())
        if not ok then
            castFailed = true
            return nil
        end
        if HasCastName(name) then
            return "channel", name, texture, startMS, endMS, notInterruptible
        end
    end
    return nil
end

-- 시전 바 진행 값(최소, 최대, 값, 모드), dik, 2026-10-01
function ns.CombatHud.CastProgress(kind, startMS, endMS, nowMS)
    if ns.IsSecret(startMS) or ns.IsSecret(endMS) then
        return startMS, endMS, nowMS, "secret"
    end
    if ns.IsSecret(kind) or ns.IsSecret(nowMS) then
        return nil, nil, nil, "none"
    end
    if not (IsFinite(startMS) and IsFinite(endMS) and IsFinite(nowMS)) or endMS <= startMS then
        return nil, nil, nil, "none"
    end
    local value
    if kind == "cast" then
        value = nowMS
    elseif kind == "channel" then
        value = startMS + endMS - nowMS
    else
        return nil, nil, nil, "none"
    end
    return startMS, endMS, math.min(endMS, math.max(startMS, value)), "plain"
end

-- 시전 남은 시간 글자, dik, 2026-10-01
function ns.CombatHud.CastRemainText(endMS, nowMS)
    if ns.IsSecret(endMS) or ns.IsSecret(nowMS) then
        return nil
    end
    if IsFinite(endMS) and IsFinite(nowMS) then
        local r = math.max(0, (endMS - nowMS) / 1000)
        return string.format(L.FMT_COMBATHUD_CAST_TIME, r)
    end
    return nil
end

-- 시전 바 색 토큰(차단 불가 = 회색), dik, 2026-10-01
function ns.CombatHud.CastColorToken(notInterruptible)
    if ns.IsSecret(notInterruptible) then
        return "ACCENT"
    end
    if notInterruptible == true then
        return "TEXT_DIM"
    end
    return "ACCENT"
end

-- 전투 HUD 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "combatHud",
    title = L.MODULE_COMBATHUD,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_COMBATHUD_DESC,
    category = "display",
    order = 60,
    requires = { "UnitHealth", "UnitHealthMax", "UnitExists" },
    -- 대상 넓은 바·크기·배율 설정 추가, dik, 2026-10-01
    -- 자원 높이·수치 표시·붉은색 고정 키 교체, dik, 2026-10-01
    -- 대상 시전 바·대상의 대상 설정 6개 추가, dik, 2026-10-01
    settings = {
        { key = "playerFrame", type = "checkbox", label = L.SETTING_COMBATHUD_PLAYER,
          tooltip = L.SETTING_COMBATHUD_PLAYER_TIP, default = true },
        { key = "targetFrame", type = "checkbox", label = L.SETTING_COMBATHUD_TARGET,
          tooltip = L.SETTING_COMBATHUD_TARGET_TIP, default = true },
        { key = "targetStyle", type = "select", label = L.SETTING_COMBATHUD_TARGET_STYLE,
          tooltip = L.SETTING_COMBATHUD_TARGET_STYLE_TIP,
          items = ns.CombatHud.TARGET_STYLE_ITEMS,
          default = "wide" },
        { key = "clickTargeting", type = "checkbox", label = L.SETTING_COMBATHUD_CLICK,
          tooltip = L.SETTING_COMBATHUD_CLICK_TIP, default = true },
        -- 오른쪽 클릭 메뉴 설정 추가(WFA-031), dik, 2026-10-02
        { key = "unitMenu", type = "checkbox", label = L.SETTING_COMBATHUD_MENU,
          tooltip = L.SETTING_COMBATHUD_MENU_TIP, default = true },
        -- 기본 프레임 숨기기 설정 제거(WFA-021 이관), dik, 2026-10-01
        { key = "frameWidth", type = "slider", label = L.SETTING_COMBATHUD_WIDTH,
          tooltip = L.SETTING_COMBATHUD_WIDTH_TIP, min = 160, max = 480, step = 10, default = 220 },
        { key = "healthHeight", type = "slider", label = L.SETTING_COMBATHUD_HEALTH_HEIGHT,
          tooltip = L.SETTING_COMBATHUD_HEALTH_HEIGHT_TIP, min = 12, max = 40, step = 2, default = 18 },
        { key = "powerHeight", type = "slider", label = L.SETTING_COMBATHUD_POWER_HEIGHT,
          tooltip = L.SETTING_COMBATHUD_POWER_HEIGHT_TIP, min = 6, max = 30, step = 2, default = 12 },
        { key = "targetWidth", type = "slider", label = L.SETTING_COMBATHUD_TARGET_WIDTH,
          tooltip = L.SETTING_COMBATHUD_TARGET_WIDTH_TIP, min = 200, max = 800, step = 10, default = 420 },
        { key = "targetHeight", type = "slider", label = L.SETTING_COMBATHUD_TARGET_HEIGHT,
          tooltip = L.SETTING_COMBATHUD_TARGET_HEIGHT_TIP, min = 16, max = 48, step = 2, default = 24 },
        { key = "hudScale", type = "slider", label = L.SETTING_COMBATHUD_SCALE,
          tooltip = L.SETTING_COMBATHUD_SCALE_TIP, min = 0.5, max = 2, step = 0.05, default = 1 },
        { key = "bgAlpha", type = "slider", label = L.SETTING_COMBATHUD_BG_ALPHA,
          tooltip = L.SETTING_COMBATHUD_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
        { key = "showHealthPercent", type = "checkbox", label = L.SETTING_COMBATHUD_PERCENT,
          tooltip = L.SETTING_COMBATHUD_PERCENT_TIP, default = true },
        { key = "showHealthText", type = "checkbox", label = L.SETTING_COMBATHUD_HEALTH_TEXT,
          tooltip = L.SETTING_COMBATHUD_HEALTH_TEXT_TIP, default = true },
        { key = "showPowerText", type = "checkbox", label = L.SETTING_COMBATHUD_POWER_TEXT,
          tooltip = L.SETTING_COMBATHUD_POWER_TEXT_TIP, default = true },
        { key = "targetShowValue", type = "checkbox", label = L.SETTING_COMBATHUD_TARGET_VALUE,
          tooltip = L.SETTING_COMBATHUD_TARGET_VALUE_TIP, default = true },
        { key = "showPower", type = "checkbox", label = L.SETTING_COMBATHUD_POWER,
          tooltip = L.SETTING_COMBATHUD_POWER_TIP, default = true },
        { key = "classColor", type = "checkbox", label = L.SETTING_COMBATHUD_CLASS_COLOR,
          tooltip = L.SETTING_COMBATHUD_CLASS_COLOR_TIP, default = true },
        { key = "targetRedFixed", type = "checkbox", label = L.SETTING_COMBATHUD_TARGET_RED,
          tooltip = L.SETTING_COMBATHUD_TARGET_RED_TIP, default = false },
        { key = "targetDebuffs", type = "checkbox", label = L.SETTING_COMBATHUD_TARGET_DEBUFFS,
          tooltip = L.SETTING_COMBATHUD_TARGET_DEBUFFS_TIP, default = true },
        { key = "targetOnlyMine", type = "checkbox", label = L.SETTING_COMBATHUD_ONLY_MINE,
          tooltip = L.SETTING_COMBATHUD_ONLY_MINE_TIP, default = false },
        -- 내 디버프 기본값 켬(WFA-039), dik, 2026-10-02
        { key = "playerDebuffs", type = "checkbox", label = L.SETTING_COMBATHUD_PLAYER_DEBUFFS,
          tooltip = L.SETTING_COMBATHUD_PLAYER_DEBUFFS_TIP, default = true },
        { key = "maxDebuffs", type = "slider", label = L.SETTING_COMBATHUD_MAX_DEBUFFS,
          tooltip = L.SETTING_COMBATHUD_MAX_DEBUFFS_TIP, min = 1, max = 16, step = 1, default = 8 },
        -- 버프 표시·상시 숨김·오라 툴팁 설정 추가(WFA-039), dik, 2026-10-02
        { key = "targetBuffs", type = "checkbox", label = L.SETTING_COMBATHUD_TARGET_BUFFS,
          tooltip = L.SETTING_COMBATHUD_TARGET_BUFFS_TIP, default = true },
        { key = "playerBuffs", type = "checkbox", label = L.SETTING_COMBATHUD_PLAYER_BUFFS,
          tooltip = L.SETTING_COMBATHUD_PLAYER_BUFFS_TIP, default = true },
        { key = "maxBuffs", type = "slider", label = L.SETTING_COMBATHUD_MAX_BUFFS,
          tooltip = L.SETTING_COMBATHUD_MAX_BUFFS_TIP, min = 1, max = 16, step = 1, default = 8 },
        { key = "hidePermanentBuffs", type = "checkbox", label = L.SETTING_COMBATHUD_HIDE_PERMANENT,
          tooltip = L.SETTING_COMBATHUD_HIDE_PERMANENT_TIP, default = true },
        { key = "auraTooltip", type = "checkbox", label = L.SETTING_COMBATHUD_AURA_TOOLTIP,
          tooltip = L.SETTING_COMBATHUD_AURA_TOOLTIP_TIP, default = true },
        { key = "showDurability", type = "checkbox", label = L.SETTING_COMBATHUD_DURABILITY,
          tooltip = L.SETTING_COMBATHUD_DURABILITY_TIP, default = true },
        { key = "targetCastBar", type = "checkbox", label = L.SETTING_COMBATHUD_CAST,
          tooltip = L.SETTING_COMBATHUD_CAST_TIP, default = true },
        { key = "castWidth", type = "slider", label = L.SETTING_COMBATHUD_CAST_WIDTH,
          tooltip = L.SETTING_COMBATHUD_CAST_WIDTH_TIP, min = 120, max = 480, step = 10, default = 240 },
        { key = "castHeight", type = "slider", label = L.SETTING_COMBATHUD_CAST_HEIGHT,
          tooltip = L.SETTING_COMBATHUD_CAST_HEIGHT_TIP, min = 10, max = 32, step = 2, default = 16 },
        { key = "targetOfTarget", type = "checkbox", label = L.SETTING_COMBATHUD_TOT,
          tooltip = L.SETTING_COMBATHUD_TOT_TIP, default = true },
        { key = "totWidth", type = "slider", label = L.SETTING_COMBATHUD_TOT_WIDTH,
          tooltip = L.SETTING_COMBATHUD_TOT_WIDTH_TIP, min = 80, max = 240, step = 10, default = 120 },
        { key = "totHeight", type = "slider", label = L.SETTING_COMBATHUD_TOT_HEIGHT,
          tooltip = L.SETTING_COMBATHUD_TOT_HEIGHT_TIP, min = 12, max = 32, step = 2, default = 18 },
        { key = "skinActionBars", type = "checkbox", label = L.SETTING_COMBATHUD_SKIN_ACTIONBAR,
          tooltip = L.SETTING_COMBATHUD_SKIN_ACTIONBAR_TIP, default = true },
    },
    -- 옛 설정 키 이관 호출 추가, dik, 2026-10-01
    OnInitialize = function()
        -- 동작 차단 공통 처리 구독(WFA-040), dik, 2026-10-02
        ns.ActionBlock.Register(MODULE_ID, {
            "SetAttribute", "RegisterUnitWatch", "EnableMouse", "RegisterForClicks", "CreateFrame",
            "SetAllPoints", "SetFrameStrata", "SetFrameLevel", "SetPoint", "ClearAllPoints",
            "SetSize", "SetWidth", "SetHeight", "SetScale", "StartMoving", "StopMovingOrSizing",
            "UseAction",
        }, OnActionBlocked)
        if ns.IsDatabaseNewer() then
            return
        end
        if type(ns.db) ~= "table" or type(ns.db.settings) ~= "table"
            or type(ns.db.settings.modules) ~= "table" then
            return
        end
        if ns.CombatHud.MigrateSettings(ns.db.settings.modules[MODULE_ID]) then
            ns.Print(L.MSG_COMBATHUD_SETTINGS_MIGRATED)
        end
    end,
})
