-- 부캐 요약 모듈 등록·행 계산·정렬 저장·삭제, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "alts"
local AREA_VERSION = 1
local REST_RATE_PER_BLOCK = 0.05
local REST_BLOCK_SECONDS = 28800
local REST_OUTSIDE_FACTOR = 0.25
local REST_CAP_FACTOR = 1.5

local COLUMN_KEYS = { "name", "level", "xp", "rest", "money", "lastSeen", "zone" }
local DEFAULT_ASC = {
    name = true,
    level = false,
    xp = false,
    rest = false,
    money = false,
    lastSeen = false,
    zone = true,
}

-- 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = "alts",
    title = L.MODULE_ALTS,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_ALTS_DESC,
    category = "feature",
    order = 10,
    settings = {
        { key = "showEstimate", type = "checkbox", label = L.SETTING_ALTS_ESTIMATE,
          tooltip = L.SETTING_ALTS_ESTIMATE_TIP, default = true },
    },
})

ns.Alts = {}
ns.Alts.COLUMN_KEYS = COLUMN_KEYS

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 유효 정렬 키 판정, dik, 2026-09-30
local function IsColumnKey(key)
    return type(key) == "string" and DEFAULT_ASC[key] ~= nil
end

-- 문자열이면 값, 아니면 nil, dik, 2026-09-30
local function StringOrNil(v)
    if type(v) == "string" then
        return v
    end
    return nil
end

-- number 이면 값, 아니면 nil, dik, 2026-09-30
local function NumberOrNil(v)
    if IsNumber(v) then
        return v
    end
    return nil
end

-- 모듈 영역 조회(새 스키마면 생성 없이 읽기만), dik, 2026-09-30
local function GetArea()
    if not ns.db then
        return nil
    end
    if ns.IsDatabaseNewer() then
        local modules = ns.db.modules
        if type(modules) == "table" and type(modules[MODULE_ID]) == "table" then
            return modules[MODULE_ID]
        end
        return nil
    end
    return ns.GetModuleData("alts")
end

-- 휴식 경험치 추정, dik, 2026-09-30
function ns.Alts.EstimateRest(info, now, isCurrent)
    if type(info) ~= "table" or not IsNumber(info.restXp) then
        return nil, false
    end
    local restXp = info.restXp
    if isCurrent or ns.GetSetting(MODULE_ID, "showEstimate") == false or not IsNumber(now)
        or not IsNumber(info.lastSeen) or not IsNumber(info.xpMax) or info.xpMax <= 0 then
        return restXp, false
    end
    local xpMax = info.xpMax
    local elapsed = math.max(0, now - info.lastSeen)
    local rate = REST_OUTSIDE_FACTOR
    if info.resting == true then
        rate = 1
    end
    local gain = xpMax * REST_RATE_PER_BLOCK * rate * elapsed / REST_BLOCK_SECONDS
    local cap = xpMax * REST_CAP_FACTOR
    local est = math.floor(math.max(restXp, math.min(restXp + gain, cap)))
    return est, est ~= restXp
end

-- 표시 이름에 서버를 붙일지 판정, dik, 2026-09-30
local function HasMultipleRealms(keys)
    local first = nil
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        local realm = info and info.realm
        if type(realm) == "string" then
            if first == nil then
                first = realm
            elseif first ~= realm then
                return true
            end
        end
    end
    return false
end

-- 표시 이름 생성, dik, 2026-09-30
local function BuildDisplayName(key, info, withRealm)
    local name = key
    if info and type(info.name) == "string" and info.name ~= "" then
        name = info.name
    end
    if withRealm and info and type(info.realm) == "string" then
        return string.format(L.FMT_NAME_REALM, name, info.realm)
    end
    return name
end

-- 위치 문자열 생성, dik, 2026-09-30
local function BuildZoneText(info)
    if type(info.zone) ~= "string" or info.zone == "" then
        return nil
    end
    if type(info.subZone) == "string" and info.subZone ~= "" then
        return info.zone .. " / " .. info.subZone
    end
    return info.zone
end

-- 캐릭터 1명의 행 레코드, dik, 2026-09-30
local function BuildRow(key, info, now, isCurrent, withRealm)
    local row = { key = key, isCurrent = isCurrent }
    row.displayName = BuildDisplayName(key, info, withRealm)
    if type(info) ~= "table" then
        return row
    end
    row.classFile = StringOrNil(info.classFile)
    row.className = StringOrNil(info.className)
    row.raceName = StringOrNil(info.raceName)
    row.guild = StringOrNil(info.guild)
    row.zone = StringOrNil(info.zone)
    row.subZone = StringOrNil(info.subZone)
    row.level = NumberOrNil(info.level)
    row.xp = NumberOrNil(info.xp)
    row.xpMax = NumberOrNil(info.xpMax)
    row.money = NumberOrNil(info.money)
    row.lastSeen = NumberOrNil(info.lastSeen)
    if type(info.resting) == "boolean" then
        row.resting = info.resting
    end
    if row.xp and row.xpMax and row.xpMax > 0 then
        row.xpRatio = math.min(1, row.xp / row.xpMax)
    end
    local restXp, estimated = ns.Alts.EstimateRest(info, now, isCurrent)
    row.restXp = restXp
    if restXp ~= nil then
        row.restEstimated = estimated
        if row.xpMax and row.xpMax > 0 then
            row.restRatio = restXp / row.xpMax
        end
    end
    if isCurrent then
        row.lastSeenSort = now or row.lastSeen
    else
        row.lastSeenSort = row.lastSeen
    end
    row.zoneText = BuildZoneText(info)
    return row
end

-- 행 레코드 배열 생성, dik, 2026-09-30
function ns.Alts.BuildRows(now)
    local current = now
    if not IsNumber(current) then
        current = nil
        if ns.HasAPI("time") then
            current = NumberOrNil(time())
        end
    end
    local keys = ns.GetCharacterKeys()
    local withRealm = HasMultipleRealms(keys)
    local currentKey = ns.GetCurrentCharacterKey()
    local rows = {}
    for i = 1, #keys do
        local key = keys[i]
        rows[i] = BuildRow(key, ns.GetCharacterInfo(key), current, currentKey ~= nil and key == currentKey, withRealm)
    end
    return rows
end

-- 합계 계산, dik, 2026-09-30
function ns.Alts.GetTotals(rows)
    local totals = { count = 0, money = 0, moneyCount = 0 }
    if type(rows) ~= "table" then
        return totals
    end
    totals.count = #rows
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and IsNumber(row.money) then
            totals.money = totals.money + row.money
            totals.moneyCount = totals.moneyCount + 1
        end
    end
    return totals
end

-- 저장 정렬 상태 조회(검증 후), dik, 2026-09-30
function ns.Alts.GetSortState()
    local area = GetArea()
    if not area then
        return "level", false
    end
    local key = area.sortKey
    if not IsColumnKey(key) then
        return "level", false
    end
    local asc = area.sortAsc
    if type(asc) ~= "boolean" then
        asc = DEFAULT_ASC[key]
    end
    return key, asc
end

-- 정렬 상태 저장(쓸 수 있을 때만), dik, 2026-09-30
function ns.Alts.SetSortState(key, asc)
    if not IsColumnKey(key) or type(asc) ~= "boolean" then
        return
    end
    if not ns.db or ns.IsDatabaseNewer() then
        return
    end
    local area = GetArea()
    if not area then
        return
    end
    if IsNumber(area.version) and area.version > AREA_VERSION then
        return
    end
    if not IsNumber(area.version) or area.version < AREA_VERSION then
        area.version = AREA_VERSION
    end
    area.sortKey = key
    area.sortAsc = asc
end

-- 삭제 가능 여부, dik, 2026-09-30
function ns.Alts.CanDelete(key)
    if type(key) ~= "string" then
        return false
    end
    local currentKey = ns.GetCurrentCharacterKey()
    if currentKey == nil or key == currentKey then
        return false
    end
    if ns.GetCharacterInfo(key) == nil then
        return false
    end
    return not ns.IsDatabaseNewer()
end

-- 캐릭터 삭제 후 안내 출력, dik, 2026-09-30
function ns.Alts.DeleteCharacter(key)
    if not ns.Alts.CanDelete(key) then
        return false
    end
    local deleted = ns.DeleteCharacter(key)
    if deleted then
        ns.Print(L.MSG_ALTS_DELETED:format(key))
    end
    return deleted
end
