-- 어그로 미터 모듈 등록·위협 어댑터·순수 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

-- 모듈 id·세션 오류 플래그, dik, 2026-10-01
local MODULE_ID = "aggroMeter"

local failed = false

-- 유한 number 판정(secret 아닌 값 전용), dik, 2026-10-01
local function IsFinite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 어그로 미터 공개 테이블·상수, dik, 2026-10-01
ns.AggroMeter = {}
ns.AggroMeter.MODULE_ID = MODULE_ID

ns.AggroMeter.HUD_MAIN = {
    label = L.HUD_LABEL_AGGROMETER, point = "RIGHT", relativePoint = "RIGHT",
    x = -40, y = 140, strata = "MEDIUM",
}

ns.AggroMeter.PARTY_UNITS = { "party1", "party2", "party3", "party4" }

ns.AggroMeter.RAID_MAX = 40

ns.AggroMeter.EVENTS = {
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

-- 위협 조회 어댑터(scaled, 값, 모드 반환), dik, 2026-10-01
function ns.AggroMeter.ReadThreat(unit, mobUnit)
    if failed then
        return nil, nil, "error"
    end
    local ok, s, v = xpcall(function()
        local _, _, scaled, _, threatValue = UnitDetailedThreatSituation(unit, mobUnit)
        return scaled, threatValue
    end, geterrorhandler())
    if not ok then
        failed = true
        return nil, nil, "error"
    end
    local secretS = ns.IsSecret(s)
    local secretV = ns.IsSecret(v)
    -- secret 모드에서도 plain % 는 0~100 정규화, dik, 2026-10-01
    if not secretS then
        if IsFinite(s) then
            s = math.min(math.max(s, 0), 100)
        else
            s = nil
        end
    end
    if secretS or secretV then
        return s, v, "secret"
    end
    if not IsFinite(v) then
        v = nil
    end
    if s == nil and v == nil then
        return nil, nil, "none"
    end
    return s, v, "plain"
end

-- 세션 실패 플래그 해제, dik, 2026-10-01
function ns.AggroMeter.ResetFailures()
    failed = false
end

-- 그룹 유닛 목록, dik, 2026-10-01
function ns.AggroMeter.BuildGroupUnits(inRaid, count, existsFn)
    if type(existsFn) ~= "function" then
        existsFn = UnitExists
    end
    local units = {}
    if inRaid == true then
        local n = ns.AggroMeter.RAID_MAX
        if not ns.IsSecret(count) and IsFinite(count) then
            n = math.min(math.floor(count), ns.AggroMeter.RAID_MAX)
        end
        for i = 1, n do
            local u = "raid" .. i
            local e = existsFn(u)
            if ns.IsSecret(e) or e == true then
                units[#units + 1] = u
            end
        end
        return units
    end
    units[1] = "player"
    for _, u in ipairs(ns.AggroMeter.PARTY_UNITS) do
        local e = existsFn(u)
        if ns.IsSecret(e) or e == true then
            units[#units + 1] = u
        end
    end
    return units
end

-- 정렬 비교(plain 항목 전용), dik, 2026-10-01
local function CompareEntries(a, b)
    if a.value ~= b.value then
        if a.value == nil then
            return false
        end
        if b.value == nil then
            return true
        end
        return a.value > b.value
    end
    if a.scaled ~= b.scaled then
        if a.scaled == nil then
            return false
        end
        if b.scaled == nil then
            return true
        end
        return a.scaled > b.scaled
    end
    return a.index < b.index
end

-- 순서 규칙(줄 배열, 모드 반환), dik, 2026-10-01
function ns.AggroMeter.RankRows(entries)
    for _, e in ipairs(entries) do
        if e.mode == "error" then
            return {}, "error"
        end
    end
    local kept = {}
    local hasSecret = false
    for _, e in ipairs(entries) do
        if e.mode ~= "none" then
            kept[#kept + 1] = e
            if e.mode == "secret" then
                hasSecret = true
            end
        end
    end
    if #kept == 0 then
        return {}, "empty"
    end
    if hasSecret then
        return kept, "group"
    end
    table.sort(kept, CompareEntries)
    return kept, "ranked"
end

-- 순위 칸 글자, dik, 2026-10-01
function ns.AggroMeter.RankLabel(position, mode)
    if mode == "ranked" then
        return L.FMT_RANK:format(position)
    end
    return L.AGGRO_RANK_GROUP
end

-- % 글자, dik, 2026-10-01
function ns.AggroMeter.PercentText(scaled, mode)
    -- % 값 자체가 secret 일 때만 nil, dik, 2026-10-01
    if ns.IsSecret(scaled) then
        return nil
    end
    if mode ~= "error" and IsFinite(scaled) then
        return L.FMT_PERCENT_INT:format(math.floor(scaled + 0.5))
    end
    return L.VALUE_UNKNOWN
end

-- 창 높이 계산, dik, 2026-10-01
function ns.AggroMeter.CalcHeight(headerH, barH, rows, gap, pad)
    return pad * 2 + headerH + pad + rows * barH + (rows - 1) * gap
end

-- 어그로 미터 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_AGGROMETER,
    description = L.MODULE_AGGROMETER_DESC,
    category = "display",
    order = 75,
    requires = { "UnitDetailedThreatSituation", "UnitExists" },
    settings = {
        { key = "onlyInCombat", type = "checkbox", label = L.SETTING_AGGROMETER_COMBAT_ONLY,
          tooltip = L.SETTING_AGGROMETER_COMBAT_ONLY_TIP, default = true },
        { key = "maxRows", type = "slider", label = L.SETTING_AGGROMETER_MAX_ROWS,
          tooltip = L.SETTING_AGGROMETER_MAX_ROWS_TIP, min = 3, max = 20, step = 1, default = 10 },
        { key = "width", type = "slider", label = L.SETTING_AGGROMETER_WIDTH,
          tooltip = L.SETTING_AGGROMETER_WIDTH_TIP, min = 160, max = 360, step = 10, default = 220 },
        { key = "barHeight", type = "slider", label = L.SETTING_AGGROMETER_BAR_HEIGHT,
          tooltip = L.SETTING_AGGROMETER_BAR_HEIGHT_TIP, min = 12, max = 24, step = 1, default = 16 },
        { key = "classColor", type = "checkbox", label = L.SETTING_AGGROMETER_CLASS_COLOR,
          tooltip = L.SETTING_AGGROMETER_CLASS_COLOR_TIP, default = true },
        { key = "bgAlpha", type = "slider", label = L.SETTING_AGGROMETER_BG_ALPHA,
          tooltip = L.SETTING_AGGROMETER_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
        { key = "locked", type = "checkbox", label = L.SETTING_AGGROMETER_LOCKED,
          tooltip = L.SETTING_AGGROMETER_LOCKED_TIP, default = false },
    },
})
