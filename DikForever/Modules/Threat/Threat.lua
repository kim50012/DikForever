-- 위협 표시 모듈 등록·상수·API 어댑터·순수 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "threat"

local support = { percent = false, color = false, attack = false }
local situationFailed = false
local percentFailed = false

-- 유한 number 판정(secret 아닌 값 전용), dik, 2026-10-01
local function IsFinite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

ns.Threat = {}
ns.Threat.MODULE_ID = MODULE_ID

ns.Threat.HUD_MAIN = {
    label = L.HUD_LABEL_THREAT, point = "LEFT", relativePoint = "CENTER",
    x = 340, y = -160, strata = "LOW",
}

ns.Threat.PARTY_UNITS = { "party1", "party2", "party3", "party4" }

ns.Threat.STATUS_TEXT_KEYS = {
    [0] = "THREAT_STATUS_LOW",
    [1] = "THREAT_STATUS_HIGH",
    [2] = "THREAT_STATUS_INSECURE",
    [3] = "THREAT_STATUS_TANKING",
}

ns.Threat.STATUS_TEXT_TOKENS = {
    [0] = "TEXT_DIM",
    [1] = "ACCENT",
    [2] = "DANGER",
    [3] = "DANGER",
}

ns.Threat.STATUS_BAR_TOKENS = {
    [0] = "BAR_SECONDARY",
    [1] = "ACCENT",
    [2] = "DANGER",
    [3] = "DANGER",
}

ns.Threat.EVENTS = {
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

ns.Threat.FEATURE_APIS = {
    { key = "percent", apis = { "UnitDetailedThreatSituation" } },
    { key = "color", apis = { "GetThreatStatusColor" } },
    { key = "attack", apis = { "UnitCanAttack" } },
}

ns.Threat.PERCENT_MAX = 100
ns.Threat.HIDDEN_STREAK_LIMIT = 20

-- 기능별 API 지원·없는 경로 판정, dik, 2026-10-01
function ns.Threat.GetFeatureSupport(wanted)
    local wantPercent = true
    if type(wanted) == "table" then
        wantPercent = wanted.percent == true
    end
    local result = {}
    for _, feature in ipairs(ns.Threat.FEATURE_APIS) do
        result[feature.key] = #ns.GetMissingAPIs(feature.apis) == 0
    end
    support.percent = result.percent == true
    support.color = result.color == true
    support.attack = result.attack == true
    local missing = {}
    if wantPercent and not result.percent then
        missing[1] = "UnitDetailedThreatSituation"
    end
    return result, missing
end

-- 위협 상태 어댑터(상태, 모드 반환), dik, 2026-10-01
function ns.Threat.ReadSituation(unit, mobUnit)
    if situationFailed then
        return nil, "error"
    end
    local ok, s = xpcall(function() return UnitThreatSituation(unit, mobUnit) end, geterrorhandler())
    if not ok then
        situationFailed = true
        return nil, "error"
    end
    if ns.IsSecret(s) then
        return s, "secret"
    end
    if IsFinite(s) then
        return s, "plain"
    end
    return nil, "none"
end

-- 위협 % 어댑터(값, 모드 반환), dik, 2026-10-01
function ns.Threat.ReadPercent(unit, mobUnit)
    if not support.percent then
        return nil, "off"
    end
    if percentFailed then
        return nil, "error"
    end
    local ok, p = xpcall(function()
        local _, _, scaled = UnitDetailedThreatSituation(unit, mobUnit)
        return scaled
    end, geterrorhandler())
    if not ok then
        percentFailed = true
        return nil, "error"
    end
    if ns.IsSecret(p) then
        return p, "secret"
    end
    if IsFinite(p) then
        return math.min(math.max(p, 0), ns.Threat.PERCENT_MAX), "plain"
    end
    return nil, "none"
end

-- 대상 존재·공격 가능·이름 원시 조회, dik, 2026-10-01
function ns.Threat.ReadTarget()
    local exists = UnitExists("target")
    local canAttack = nil
    if support.attack then
        canAttack = UnitCanAttack("player", "target")
    end
    local name = UnitName("target")
    return exists, canAttack, name
end

-- 유닛 이름 원시 조회, dik, 2026-10-01
function ns.Threat.ReadName(unit)
    local name = UnitName(unit)
    return name
end

-- 세션 실패 플래그 해제, dik, 2026-10-01
function ns.Threat.ResetFailures()
    situationFailed = false
    percentFailed = false
end

-- 상태 문구, dik, 2026-10-01
function ns.Threat.StatusText(status, mode)
    if mode == "plain" then
        if IsFinite(status) then
            local key = ns.Threat.STATUS_TEXT_KEYS[status]
            if key then
                return L[key]
            end
        end
        return L.VALUE_UNKNOWN
    end
    if mode == "none" then
        return L.THREAT_STATUS_NONE
    end
    return L.THREAT_STATUS_HIDDEN
end

-- 상태 글자 색 토큰, dik, 2026-10-01
function ns.Threat.StatusTextToken(status, mode)
    if mode == "plain" and IsFinite(status) then
        local token = ns.Threat.STATUS_TEXT_TOKENS[status]
        if token then
            return token
        end
    end
    return "TEXT_DIM"
end

-- 상태 막대 색 선택, dik, 2026-10-01
function ns.Threat.PickStatusColor(status, mode, colorFn)
    if mode == "plain" then
        if type(colorFn) == "function" then
            local r, g, b = colorFn(status)
            if not ns.IsSecret(r) and not ns.IsSecret(g) and not ns.IsSecret(b)
                and IsFinite(r) and IsFinite(g) and IsFinite(b) then
                return r, g, b, nil
            end
        end
        if IsFinite(status) then
            local token = ns.Threat.STATUS_BAR_TOKENS[status]
            if token then
                return nil, nil, nil, token
            end
        end
        return nil, nil, nil, "ACCENT"
    end
    if mode == "none" then
        return nil, nil, nil, "BAR_SECONDARY"
    end
    return nil, nil, nil, "ACCENT"
end

-- 상태 막대 색 어댑터, dik, 2026-10-01
function ns.Threat.StatusColor(status, mode)
    return ns.Threat.PickStatusColor(status, mode, support.color and GetThreatStatusColor or nil)
end

-- % 글자, dik, 2026-10-01
function ns.Threat.PercentText(pct, mode)
    if mode == "plain" then
        if IsFinite(pct) then
            return L.FMT_PERCENT_INT:format(math.floor(pct + 0.5))
        end
        return L.VALUE_UNKNOWN
    end
    if mode == "secret" then
        return nil
    end
    return L.VALUE_UNKNOWN
end

-- 행 판정, dik, 2026-10-01
function ns.Threat.RowMode(statusMode, pctMode, percentShown)
    if statusMode == "plain" or statusMode == "none" then
        return "open"
    end
    if statusMode == "secret" or statusMode == "error" then
        if (pctMode == "secret" or pctMode == "plain") and percentShown == true then
            return "limited"
        end
    end
    return "hidden"
end

-- 비공개 연속 횟수 갱신, dik, 2026-10-01
function ns.Threat.NextHiddenStreak(streak, rowMode, counting)
    if type(streak) ~= "number" then
        streak = 0
    end
    if counting ~= true then
        return streak
    end
    if rowMode == "hidden" then
        return streak + 1
    end
    return 0
end

-- 본문 표시 여부, dik, 2026-10-01
function ns.Threat.ShouldShowBody(targetExists, canAttack, inCombat, onlyInCombat)
    if onlyInCombat == true and inCombat ~= true then
        return false
    end
    if not ns.IsSecret(targetExists) and targetExists ~= true then
        return false
    end
    if not ns.IsSecret(canAttack) and canAttack == false then
        return false
    end
    return true
end

-- 행 대상 유닛 목록, dik, 2026-10-01
function ns.Threat.BuildUnitList(showParty, existsFn)
    if type(existsFn) ~= "function" then
        existsFn = UnitExists
    end
    local units = { "player" }
    if showParty == true then
        for _, u in ipairs(ns.Threat.PARTY_UNITS) do
            local v = existsFn(u)
            if ns.IsSecret(v) or v == true then
                units[#units + 1] = u
            end
        end
    end
    return units
end

-- 창 높이 계산, dik, 2026-10-01
function ns.Threat.CalcHeight(rowCount, headerH, rowH, gap, pad)
    if type(rowCount) ~= "number" then
        rowCount = 1
    end
    return pad * 2 + headerH + math.max(1, rowCount) * (gap + rowH)
end

-- 위협 표시 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "threat",
    title = L.MODULE_THREAT,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_THREAT_DESC,
    category = "display",
    order = 70,
    requires = { "UnitThreatSituation", "UnitExists" },
    settings = {
        { key = "showPercent", type = "checkbox", label = L.SETTING_THREAT_PERCENT,
          tooltip = L.SETTING_THREAT_PERCENT_TIP, default = true },
        { key = "showParty", type = "checkbox", label = L.SETTING_THREAT_PARTY,
          tooltip = L.SETTING_THREAT_PARTY_TIP, default = true },
        { key = "onlyInCombat", type = "checkbox", label = L.SETTING_THREAT_COMBAT_ONLY,
          tooltip = L.SETTING_THREAT_COMBAT_ONLY_TIP, default = true },
        { key = "frameWidth", type = "slider", label = L.SETTING_THREAT_WIDTH,
          tooltip = L.SETTING_THREAT_WIDTH_TIP, min = 160, max = 300, step = 10, default = 200 },
        { key = "bgAlpha", type = "slider", label = L.SETTING_THREAT_BG_ALPHA,
          tooltip = L.SETTING_THREAT_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
    },
})
