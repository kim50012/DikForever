-- 피해량 미터 모듈 등록·구간 조회 어댑터·순수 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.DamageMeter = {}
local DM = ns.DamageMeter

DM.MODULE_ID = "damageMeter"

DM.TYPES = {
    { key = "DamageDone", label = L.DAMAGEMETER_TYPE_DAMAGE_DONE },
    { key = "Dps", label = L.DAMAGEMETER_TYPE_DPS },
    { key = "HealingDone", label = L.DAMAGEMETER_TYPE_HEALING_DONE },
    { key = "Hps", label = L.DAMAGEMETER_TYPE_HPS },
    { key = "Absorbs", label = L.DAMAGEMETER_TYPE_ABSORBS },
    { key = "Interrupts", label = L.DAMAGEMETER_TYPE_INTERRUPTS },
    { key = "Dispels", label = L.DAMAGEMETER_TYPE_DISPELS },
    { key = "DamageTaken", label = L.DAMAGEMETER_TYPE_DAMAGE_TAKEN },
    { key = "AvoidableDamageTaken", label = L.DAMAGEMETER_TYPE_AVOIDABLE_DAMAGE_TAKEN },
}

DM.SEGMENT_ITEMS = {
    { value = "current", text = L.DAMAGEMETER_SEG_CURRENT },
    { value = "overall", text = L.DAMAGEMETER_SEG_OVERALL },
}

-- 창 개수 상한·창별 설정 기본 키 표 추가, dik, 2026-10-01
DM.WINDOW_MAX = 3
DM.WINDOW_BASES = { "meterType", "segment", "width", "maxBars", "locked" }

-- HUD_WINDOW 를 3창 배열 HUD_WINDOWS 로 교체, dik, 2026-10-01
DM.HUD_WINDOWS = {
    { key = "window", point = "RIGHT", relativePoint = "RIGHT", x = -40, y = -80, strata = "MEDIUM" },
    { key = "window2", point = "RIGHT", relativePoint = "RIGHT", x = -290, y = -80, strata = "MEDIUM" },
    { key = "window3", point = "RIGHT", relativePoint = "RIGHT", x = -540, y = -80, strata = "MEDIUM" },
}

DM.EVENTS = {
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}

DM.STATUS_TEXT = {
    empty = L.DAMAGEMETER_EMPTY,
    unavailable = L.DAMAGEMETER_UNAVAILABLE,
    type_unsupported = L.DAMAGEMETER_TYPE_UNSUPPORTED,
    segment_unsupported = L.DAMAGEMETER_SEGMENT_UNSUPPORTED,
    bad_format = L.DAMAGEMETER_BAD_FORMAT,
    error = L.DAMAGEMETER_ERROR,
}

local EOK = 100000000
local MAN = 10000

local failed = false

-- 유한 number 판정(secret 아닌 값 전용), dik, 2026-10-01
local function IsFinite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 표시 종류 선택지 배열 생성, dik, 2026-10-01
function DM.BuildTypeItems(enumTable)
    local items = {}
    if type(enumTable) == "table" then
        for _, entry in ipairs(DM.TYPES) do
            if type(enumTable[entry.key]) == "number" then
                items[#items + 1] = { value = entry.key, text = entry.label }
            end
        end
    end
    if #items == 0 then
        items[1] = { value = "DamageDone", text = L.DAMAGEMETER_TYPE_DAMAGE_DONE }
    end
    return items
end

DM.TYPE_ITEMS = DM.BuildTypeItems(type(Enum) == "table" and Enum.DamageMeterType or nil)

-- 오류 플래그 해제, dik, 2026-10-01
function DM.ResetFailure()
    failed = false
end

-- 구간 조회 어댑터(API 반환 테이블 무가공), dik, 2026-10-01
function DM.GetSession(typeKey, segmentKey)
    if failed then
        return nil, "error"
    end
    if ns.HasAPI("C_DamageMeter.IsDamageMeterAvailable") then
        local okAvail, avail = xpcall(function() return C_DamageMeter.IsDamageMeterAvailable() end, geterrorhandler())
        -- 가용성 조회 오류 시 실패 플래그, dik, 2026-10-01
        if not okAvail then
            failed = true
            return nil, "error"
        end
        if not ns.IsSecret(avail) and avail == false then
            return nil, "unavailable"
        end
    end
    local typeEnum = type(Enum) == "table" and Enum.DamageMeterType or nil
    local t = type(typeEnum) == "table" and type(typeKey) == "string" and typeEnum[typeKey] or nil
    if type(t) ~= "number" then
        return nil, "type_unsupported"
    end
    local segEnum = type(Enum) == "table" and Enum.DamageMeterSessionType or nil
    local s
    if type(segEnum) == "table" then
        if segmentKey == "current" then
            s = segEnum.Current
        elseif segmentKey == "overall" then
            s = segEnum.Overall
        end
    end
    if type(s) ~= "number" then
        return nil, "segment_unsupported"
    end
    local ok, session = xpcall(function() return C_DamageMeter.GetCombatSessionFromType(s, t) end, geterrorhandler())
    if not ok then
        failed = true
        return nil, "error"
    end
    if ns.IsSecret(session) then
        return nil, "bad_format"
    end
    if session == nil then
        return nil, "empty"
    end
    if type(session) ~= "table" then
        return nil, "bad_format"
    end
    local list = session.combatSources
    if ns.IsSecret(list) then
        return nil, "bad_format"
    end
    if list == nil then
        return session, "empty"
    end
    if type(list) ~= "table" then
        return nil, "bad_format"
    end
    if #list == 0 then
        return session, "empty"
    end
    return session, "ok"
end

-- 총량 서식(secret 은 그대로 반환), dik, 2026-10-01
function DM.FormatAmount(v)
    if ns.IsSecret(v) then
        return v
    end
    if not IsFinite(v) then
        return nil
    end
    local a = math.abs(v)
    if a >= EOK then
        return string.format(L.FMT_AMOUNT_EOK, v / EOK)
    elseif a >= MAN then
        return string.format(L.FMT_AMOUNT_MAN, v / MAN)
    end
    return ns.FormatNumber(math.floor(v + 0.5))
end

-- 바 최댓값 결정, dik, 2026-10-01
function DM.ResolveMax(session, first)
    local m = session.maxAmount
    if ns.IsSecret(m) then
        return m
    end
    if IsFinite(m) and m > 0 then
        return m
    end
    if not ns.IsSecret(first) and type(first) == "table" then
        local f = first.totalAmount
        if ns.IsSecret(f) then
            return f
        end
        if IsFinite(f) and f > 0 then
            return f
        end
    end
    return 1
end

-- 바 값 결정, dik, 2026-10-01
function DM.BarValue(v)
    if ns.IsSecret(v) then
        return v
    end
    if IsFinite(v) then
        return v
    end
    return 0
end

-- 서버명 제거 이름, dik, 2026-10-01
function DM.ShortName(name)
    if ns.IsSecret(name) then
        return name
    end
    if type(name) == "string" and name ~= "" then
        return name:match("^([^%-]+)") or name
    end
    return nil
end

-- 직업색 조회, dik, 2026-10-01
function DM.GetClassColor(classFilename, ...)
    if ns.IsSecret(classFilename) or type(classFilename) ~= "string" then
        return nil
    end
    local colors = RAID_CLASS_COLORS
    if select("#", ...) > 0 then
        colors = ...
    end
    if type(colors) ~= "table" then
        return nil
    end
    -- 직업 바 색 덮어쓰기 적용, dik, 2026-10-02
    return ns.ClassBarColor(classFilename, colors)
end

-- 창 높이 계산, dik, 2026-10-01
function DM.CalcWindowHeight(headerH, barH, rows, rowGap, pad)
    return pad * 2 + headerH + pad + rows * barH + math.max(rows - 1, 0) * rowGap
end

-- 창 설정 키 조립, dik, 2026-10-01
function DM.WindowKey(base, index)
    if type(base) ~= "string" or not IsFinite(index) or index ~= math.floor(index) then
        return nil
    end
    local known = false
    for _, b in ipairs(DM.WINDOW_BASES) do
        if b == base then
            known = true
            break
        end
    end
    if not known then
        return nil
    end
    if index == 1 then
        return base
    end
    if index >= 2 and index <= DM.WINDOW_MAX then
        return base .. index
    end
    return nil
end

-- 창 설정 키 분해, dik, 2026-10-01
function DM.ParseWindowKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local function IsBase(s)
        for _, b in ipairs(DM.WINDOW_BASES) do
            if b == s then
                return true
            end
        end
        return false
    end
    if IsBase(key) then
        return key, 1
    end
    local base, digit = key:match("^(%a+)(%d)$")
    local n = tonumber(digit)
    if base and IsBase(base) and n and n >= 2 and n <= DM.WINDOW_MAX then
        return base, n
    end
    return nil
end

-- 창 개수 보정, dik, 2026-10-01
function DM.ClampWindowCount(v)
    if type(v) ~= "number" or v ~= v then
        return 1
    end
    if v >= DM.WINDOW_MAX then
        return DM.WINDOW_MAX
    end
    if v <= 1 then
        return 1
    end
    return math.floor(v)
end

-- 기본 표시 종류 선택, dik, 2026-10-01
function DM.PickDefaultType(items, preferred)
    if type(items) ~= "table" or type(items[1]) ~= "table" then
        return nil
    end
    for _, item in ipairs(items) do
        if item.value == preferred then
            return preferred
        end
    end
    return items[1].value
end

-- 창별 설정 선언 생성(창 1~3), dik, 2026-10-01
local function BuildWindowSettings()
    local defaultTypes = {
        DM.TYPE_ITEMS[1].value,
        DM.PickDefaultType(DM.TYPE_ITEMS, "HealingDone"),
        DM.PickDefaultType(DM.TYPE_ITEMS, "DamageTaken"),
    }
    local list = {}
    -- 설정 창별 huds 태그 추가, dik, 2026-10-05
    for i = 1, DM.WINDOW_MAX do
        local function Name(text)
            return L.FMT_DAMAGEMETER_WINDOW_SETTING:format(i, text)
        end
        list[#list + 1] = { key = DM.WindowKey("meterType", i), huds = { DM.HUD_WINDOWS[i].key }, type = "select",
          label = Name(L.SETTING_DAMAGEMETER_TYPE), tooltip = L.SETTING_DAMAGEMETER_TYPE_TIP,
          items = DM.TYPE_ITEMS, default = defaultTypes[i] }
        list[#list + 1] = { key = DM.WindowKey("segment", i), huds = { DM.HUD_WINDOWS[i].key }, type = "select",
          label = Name(L.SETTING_DAMAGEMETER_SEGMENT), tooltip = L.SETTING_DAMAGEMETER_SEGMENT_TIP,
          items = DM.SEGMENT_ITEMS, default = "current" }
        list[#list + 1] = { key = DM.WindowKey("width", i), huds = { DM.HUD_WINDOWS[i].key }, type = "slider",
          label = Name(L.SETTING_DAMAGEMETER_WIDTH), tooltip = L.SETTING_DAMAGEMETER_WIDTH_TIP,
          min = 160, max = 400, step = 10, default = 240 }
        list[#list + 1] = { key = DM.WindowKey("maxBars", i), huds = { DM.HUD_WINDOWS[i].key }, type = "slider",
          label = Name(L.SETTING_DAMAGEMETER_MAX_BARS), tooltip = L.SETTING_DAMAGEMETER_MAX_BARS_TIP,
          min = 3, max = 20, step = 1, default = 8 }
        list[#list + 1] = { key = DM.WindowKey("locked", i), huds = { DM.HUD_WINDOWS[i].key }, type = "checkbox",
          label = Name(L.SETTING_DAMAGEMETER_LOCKED), tooltip = L.SETTING_DAMAGEMETER_LOCKED_TIP,
          default = false }
    end
    return list
end

-- 설정 선언 표 재구성(창 개수·창별 설정), dik, 2026-10-01
local function BuildSettings()
    local settings = {
        { key = "windowCount", type = "slider", label = L.SETTING_DAMAGEMETER_WINDOW_COUNT,
          tooltip = L.SETTING_DAMAGEMETER_WINDOW_COUNT_TIP, min = 1, max = DM.WINDOW_MAX, step = 1, default = 1 },
        { key = "barHeight", type = "slider", label = L.SETTING_DAMAGEMETER_BAR_HEIGHT,
          tooltip = L.SETTING_DAMAGEMETER_BAR_HEIGHT_TIP, min = 12, max = 24, step = 1, default = 16 },
        { key = "showPerSecond", type = "checkbox", label = L.SETTING_DAMAGEMETER_PER_SECOND,
          tooltip = L.SETTING_DAMAGEMETER_PER_SECOND_TIP, default = true },
        { key = "classColor", type = "checkbox", label = L.SETTING_DAMAGEMETER_CLASS_COLOR,
          tooltip = L.SETTING_DAMAGEMETER_CLASS_COLOR_TIP, default = true },
        { key = "bgAlpha", type = "slider", label = L.SETTING_DAMAGEMETER_BG_ALPHA,
          tooltip = L.SETTING_DAMAGEMETER_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
    }
    for _, s in ipairs(BuildWindowSettings()) do
        settings[#settings + 1] = s
    end
    return settings
end

ns.RegisterModule({
    id = "damageMeter",
    title = L.MODULE_DAMAGEMETER,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_DAMAGEMETER_DESC,
    category = "display",
    order = 40,
    requires = { "C_DamageMeter.GetCombatSessionFromType", "Enum.DamageMeterType", "Enum.DamageMeterSessionType" },
    -- 설정 선언을 창 개수·창별 20개 표로 교체, dik, 2026-10-01
    settings = BuildSettings(),
})
