-- 능력치·미니맵 모듈 등록·판정 함수·능력치 공급자, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "statsMinimap"

ns.StatsMinimap = {}

ns.StatsMinimap.STAT_ROWS = {
    { provider = "statStrength", set = "main" },
    { provider = "statAgility", set = "main" },
    { provider = "statStamina", set = "main" },
    { provider = "statIntellect", set = "main" },
    { provider = "statArmor", set = "main" },
    { provider = "statAttackPower", set = "all" },
    { provider = "statSpellPower", set = "all" },
    { provider = "statCrit", set = "all" },
    { provider = "statHaste", set = "all" },
    { provider = "statMastery", set = "all" },
}

ns.StatsMinimap.MINIMAP_GROUPS = {
    { key = "border", kind = "texture", candidates = { { "MinimapCompassTexture" }, { "MinimapBorder" } } },
    { key = "borderTop", kind = "texture",
      candidates = { { "MinimapCluster", "BorderTop" }, { "MinimapBorderTop" } } },
    { key = "zoneText", kind = "font", candidates = { { "MinimapZoneText" } } },
}

ns.StatsMinimap.HUD_STATS = { key = "stats", point = "TOPLEFT", relativePoint = "TOPLEFT", x = 16, y = -140, strata = "LOW" }

ns.StatsMinimap.PANEL_MIN_W = 120

ns.StatsMinimap.OWNER = "statsMinimap"

ns.StatsMinimap.SKIN_OWNER = "statsMinimap:minimap"

local SPELL_SCHOOL_FIRST = 2
local SPELL_SCHOOL_LAST = 7
local COMMON_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 능력치 정수 문구 판정, dik, 2026-10-01
function ns.StatsMinimap.EvalStat(v)
    if ns.IsSecret(v) or not IsNumber(v) then
        return nil
    end
    return ns.FormatNumber(math.floor(v + 0.5)), "TEXT"
end

-- 능력치 퍼센트 문구 판정, dik, 2026-10-01
function ns.StatsMinimap.EvalPercent(v)
    if ns.IsSecret(v) or not IsNumber(v) then
        return nil
    end
    return L.FMT_STAT_PERCENT:format(math.max(v, 0)), "TEXT"
end

-- 공격력 합산(기본+증가+감소), dik, 2026-10-01
function ns.StatsMinimap.SumAttackPower(base, pos, neg)
    if ns.IsSecret(base) or ns.IsSecret(pos) or ns.IsSecret(neg) then
        return nil
    end
    if not IsNumber(base) then
        return nil
    end
    if pos == nil then
        pos = 0
    end
    if neg == nil then
        neg = 0
    end
    if not IsNumber(pos) or not IsNumber(neg) then
        return nil
    end
    local total = base + pos + neg
    if total < 0 then
        return 0
    end
    return total
end

-- 주문력 6칸 최댓값, dik, 2026-10-01
function ns.StatsMinimap.MaxOf(list)
    if type(list) ~= "table" then
        return nil
    end
    for i = 1, 6 do
        if ns.IsSecret(list[i]) then
            return nil
        end
    end
    local best
    for i = 1, 6 do
        local v = list[i]
        if IsNumber(v) and (best == nil or v > best) then
            best = v
        end
    end
    return best
end

-- 행 표시 여부 판정, dik, 2026-10-01
function ns.StatsMinimap.IsRowVisible(row, set)
    if set == "main" then
        return type(row) == "table" and row.set == "main"
    end
    return true
end

-- 폭 배열 최댓값(비수치는 0), dik, 2026-10-01
local function MaxWidth(list)
    local best = 0
    for i = 1, #list do
        local w = list[i]
        if IsNumber(w) and w > best then
            best = w
        end
    end
    return best
end

-- 패널 크기·행 y 좌표 계산, dik, 2026-10-01
function ns.StatsMinimap.LayoutStats(labelWidths, valueWidths, rowH, headerH, gap, pad, minW)
    local n = #labelWidths
    if n == 0 then
        return 0, 0, {}
    end
    local width = math.max(minW, pad + MaxWidth(labelWidths) + gap * 2 + MaxWidth(valueWidths) + pad)
    local height = pad + headerH + n * rowH + pad
    local ys = {}
    for k = 1, n do
        ys[k] = -(pad + headerH + (k - 1) * rowH)
    end
    return width, height, ys
end

-- 공통 이벤트를 붙인 이벤트 목록, dik, 2026-10-01
local function BuildEvents(...)
    local events = { ... }
    for i = 1, #COMMON_EVENTS do
        events[#events + 1] = COMMON_EVENTS[i]
    end
    return events
end

-- 주 능력치 공급자 값, dik, 2026-10-01
local function GetPrimaryStat(index)
    local _, effective = UnitStat("player", index)
    return ns.StatsMinimap.EvalStat(effective)
end

-- 방어도 공급자 값, dik, 2026-10-01
local function GetArmorValue()
    local _, effective = UnitArmor("player")
    return ns.StatsMinimap.EvalStat(effective)
end

-- 공격력 공급자 값, dik, 2026-10-01
local function GetAttackPowerValue()
    return ns.StatsMinimap.EvalStat(ns.StatsMinimap.SumAttackPower(UnitAttackPower("player")))
end

-- 주문력 공급자 값, dik, 2026-10-01
local function GetSpellPowerValue()
    local list = {}
    for school = SPELL_SCHOOL_FIRST, SPELL_SCHOOL_LAST do
        list[school - SPELL_SCHOOL_FIRST + 1] = GetSpellBonusDamage(school)
    end
    return ns.StatsMinimap.EvalStat(ns.StatsMinimap.MaxOf(list))
end

-- 치명타 공급자 값, dik, 2026-10-01
local function GetCritValue()
    return ns.StatsMinimap.EvalPercent(GetCritChance())
end

-- 가속 공급자 값, dik, 2026-10-01
local function GetHasteValue()
    return ns.StatsMinimap.EvalPercent(GetHaste())
end

-- 특화 공급자 값, dik, 2026-10-01
local function GetMasteryValue()
    return ns.StatsMinimap.EvalPercent((GetMasteryEffect()))
end

ns.InfoText.Register({ id = "statStrength", label = L.STAT_STRENGTH, order = 200,
    events = BuildEvents("UNIT_STATS"), interval = 2, requires = { "UnitStat" }, showLabel = false,
    Get = function() return GetPrimaryStat(1) end })
ns.InfoText.Register({ id = "statAgility", label = L.STAT_AGILITY, order = 210,
    events = BuildEvents("UNIT_STATS"), interval = 2, requires = { "UnitStat" }, showLabel = false,
    Get = function() return GetPrimaryStat(2) end })
ns.InfoText.Register({ id = "statStamina", label = L.STAT_STAMINA, order = 220,
    events = BuildEvents("UNIT_STATS"), interval = 2, requires = { "UnitStat" }, showLabel = false,
    Get = function() return GetPrimaryStat(3) end })
ns.InfoText.Register({ id = "statIntellect", label = L.STAT_INTELLECT, order = 230,
    events = BuildEvents("UNIT_STATS"), interval = 2, requires = { "UnitStat" }, showLabel = false,
    Get = function() return GetPrimaryStat(4) end })
ns.InfoText.Register({ id = "statArmor", label = L.STAT_ARMOR, order = 240,
    events = BuildEvents("UNIT_RESISTANCES"), interval = 2, requires = { "UnitArmor" }, showLabel = false,
    Get = GetArmorValue })
ns.InfoText.Register({ id = "statAttackPower", label = L.STAT_ATTACK_POWER, order = 250,
    events = BuildEvents("UNIT_ATTACK_POWER", "UNIT_STATS"), interval = 2,
    requires = { "UnitAttackPower" }, showLabel = false, Get = GetAttackPowerValue })
ns.InfoText.Register({ id = "statSpellPower", label = L.STAT_SPELL_POWER, order = 260,
    events = BuildEvents("SPELL_POWER_CHANGED", "UNIT_STATS"), interval = 2,
    requires = { "GetSpellBonusDamage" }, showLabel = false, Get = GetSpellPowerValue })
ns.InfoText.Register({ id = "statCrit", label = L.STAT_CRIT, order = 270,
    events = BuildEvents("COMBAT_RATING_UPDATE", "UNIT_STATS"), interval = 2,
    requires = { "GetCritChance" }, showLabel = false, Get = GetCritValue })
ns.InfoText.Register({ id = "statHaste", label = L.STAT_HASTE, order = 280,
    events = BuildEvents("COMBAT_RATING_UPDATE", "UNIT_SPELL_HASTE"), interval = 2,
    requires = { "GetHaste" }, showLabel = false, Get = GetHasteValue })
ns.InfoText.Register({ id = "statMastery", label = L.STAT_MASTERY, order = 290,
    events = BuildEvents("MASTERY_UPDATE", "COMBAT_RATING_UPDATE"), interval = 2,
    requires = { "GetMasteryEffect" }, showLabel = false, Get = GetMasteryValue })

ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_STATSMINIMAP,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_STATSMINIMAP_DESC,
    category = "display",
    order = 50,
    settings = {
        { key = "showStats", type = "checkbox", label = L.SETTING_STATS_SHOW,
          tooltip = L.SETTING_STATS_SHOW_TIP, default = true },
        { key = "statsSet", type = "select", label = L.SETTING_STATS_SET,
          tooltip = L.SETTING_STATS_SET_TIP,
          items = {
              { value = "main", text = L.STATS_SET_MAIN },
              { value = "all", text = L.STATS_SET_ALL },
          },
          default = "all" },
        { key = "statsAlpha", type = "slider", label = L.SETTING_STATS_BG_ALPHA,
          tooltip = L.SETTING_STATS_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
        { key = "skinMinimap", type = "checkbox", label = L.SETTING_MINIMAP_SKIN,
          tooltip = L.SETTING_MINIMAP_SKIN_TIP, default = true },
        { key = "minimapShape", type = "select", label = L.SETTING_MINIMAP_SHAPE,
          tooltip = L.SETTING_MINIMAP_SHAPE_TIP,
          items = {
              { value = "square", text = L.MINIMAP_SHAPE_SQUARE },
              { value = "round", text = L.MINIMAP_SHAPE_ROUND },
          },
          default = "square" },
    },
})
