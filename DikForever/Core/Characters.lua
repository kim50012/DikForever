-- 캐릭터 스냅샷 수집·조회·삭제 API, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local currentKey = nil
local missingList = {}
local missingSet = {}
local snapshotDone = false

-- 세션 미지원 목록에 중복 없이 추가, dik, 2026-09-30
local function AddMissing(name)
    if not missingSet[name] then
        missingSet[name] = true
        missingList[#missingList + 1] = name
    end
end

-- 필요 API 전부 존재 검사(없는 것은 목록에 추가), dik, 2026-09-30
local function CheckAPIs(...)
    local ok = true
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if not ns.HasAPI(name) then
            AddMissing(name)
            ok = false
        end
    end
    return ok
end

-- secret 아닌 값만 저장하고 변경 표시, dik, 2026-09-30
local function SetField(info, changed, field, value)
    if value == nil or ns.IsSecret(value) then
        return
    end
    if info[field] ~= value then
        info[field] = value
        changed[field] = true
    end
end

-- 캐릭터 항목 조회(create 면 생성·복구), dik, 2026-09-30
local function GetEntry(key, create)
    local db = ns.db
    if not db or type(key) ~= "string" then
        return nil
    end
    if type(db.chars) ~= "table" then
        if not create then
            return nil
        end
        db.chars = {}
    end
    local entry = db.chars[key]
    if type(entry) ~= "table" then
        if not create then
            return nil
        end
        entry = {}
        db.chars[key] = entry
    end
    if create then
        if type(entry.info) ~= "table" then
            entry.info = {}
        end
        if type(entry.data) ~= "table" then
            entry.data = {}
        end
    end
    return entry
end

-- 이름·서버로 키 생성, dik, 2026-09-30
local function ReadKey()
    if not CheckAPIs("UnitName", "GetRealmName") then
        return nil
    end
    local name = UnitName("player")
    local realm = GetRealmName()
    if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then
        return nil
    end
    if ns.IsSecret(name) or ns.IsSecret(realm) then
        return nil
    end
    return name .. "-" .. realm:gsub("[%s%-]", "")
end

-- identity 그룹 수집, dik, 2026-09-30
local function CollectIdentity(info, changed)
    if not CheckAPIs("UnitName", "GetRealmName", "UnitClass", "UnitRace", "UnitFactionGroup") then
        return
    end
    SetField(info, changed, "name", (UnitName("player")))
    SetField(info, changed, "realm", GetRealmName())
    local className, classFile = UnitClass("player")
    SetField(info, changed, "classFile", classFile)
    SetField(info, changed, "className", className)
    local raceName, raceFile = UnitRace("player")
    SetField(info, changed, "raceFile", raceFile)
    SetField(info, changed, "raceName", raceName)
    SetField(info, changed, "faction", (UnitFactionGroup("player")))
end

-- level 그룹 수집, dik, 2026-09-30
local function CollectLevel(info, changed, levelArg)
    if type(levelArg) == "number" then
        SetField(info, changed, "level", levelArg)
        return
    end
    if not CheckAPIs("UnitLevel") then
        return
    end
    SetField(info, changed, "level", UnitLevel("player"))
end

-- xp 그룹 수집, dik, 2026-09-30
local function CollectXp(info, changed)
    if not CheckAPIs("UnitXP", "UnitXPMax", "GetXPExhaustion", "IsResting") then
        return
    end
    SetField(info, changed, "xp", UnitXP("player"))
    SetField(info, changed, "xpMax", UnitXPMax("player"))
    local rest = GetXPExhaustion()
    if rest == nil then
        rest = 0
    end
    SetField(info, changed, "restXp", rest)
    local resting = IsResting()
    if not ns.IsSecret(resting) then
        resting = resting and true or false
    end
    SetField(info, changed, "resting", resting)
end

-- money 그룹 수집, dik, 2026-09-30
local function CollectMoney(info, changed)
    if not CheckAPIs("GetMoney") then
        return
    end
    SetField(info, changed, "money", GetMoney())
end

-- zone 그룹 수집, dik, 2026-09-30
local function CollectZone(info, changed)
    if not CheckAPIs("GetRealZoneText", "GetSubZoneText") then
        return
    end
    SetField(info, changed, "zone", GetRealZoneText())
    local subZone = GetSubZoneText()
    if subZone == nil then
        subZone = ""
    end
    SetField(info, changed, "subZone", subZone)
end

-- guild 그룹 수집, dik, 2026-09-30
local function CollectGuild(info, changed)
    if not CheckAPIs("GetGuildInfo") then
        return
    end
    local guild = GetGuildInfo("player")
    if ns.IsSecret(guild) then
        return
    end
    if guild == nil or guild == "" then
        if info.guild ~= nil then
            info.guild = nil
            changed.guild = true
        end
        return
    end
    SetField(info, changed, "guild", guild)
end

-- 전문기술 배열 비교, dik, 2026-09-30
local function SameProfessions(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
        return false
    end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if type(x) ~= "table" or type(y) ~= "table" then
            return false
        end
        if x.name ~= y.name or x.rank ~= y.rank or x.maxRank ~= y.maxRank or x.skillLine ~= y.skillLine then
            return false
        end
    end
    return true
end

-- professions 그룹 수집, dik, 2026-09-30
local function CollectProfessions(info, changed)
    if not CheckAPIs("GetProfessions", "GetProfessionInfo") then
        return
    end
    local indexes = { GetProfessions() }
    local list = {}
    for i = 1, 5 do
        local index = indexes[i]
        if index ~= nil then
            if ns.IsSecret(index) then
                return
            end
            local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            if ns.IsSecret(name) or ns.IsSecret(rank) or ns.IsSecret(maxRank) or ns.IsSecret(skillLine) then
                return
            end
            if name ~= nil then
                list[#list + 1] = { name = name, rank = rank, maxRank = maxRank, skillLine = skillLine }
            end
        end
    end
    if not SameProfessions(info.professions, list) then
        info.professions = list
        changed.professions = true
    end
end

-- 수집 그룹·이벤트 트리거 표, dik, 2026-09-30
local GROUP_FUNCS = {
    identity = CollectIdentity,
    level = CollectLevel,
    xp = CollectXp,
    money = CollectMoney,
    zone = CollectZone,
    guild = CollectGuild,
    professions = CollectProfessions,
}
local ALL_GROUPS = { "identity", "level", "xp", "money", "zone", "guild", "professions" }

local EVENT_GROUPS = {
    PLAYER_XP_UPDATE = { "xp" },
    UPDATE_EXHAUSTION = { "xp" },
    PLAYER_UPDATE_RESTING = { "xp" },
    PLAYER_MONEY = { "money" },
    PLAYER_LEVEL_UP = { "level", "xp" },
    ZONE_CHANGED = { "zone" },
    ZONE_CHANGED_INDOORS = { "zone" },
    ZONE_CHANGED_NEW_AREA = { "zone" },
    SKILL_LINES_CHANGED = { "professions" },
    PLAYER_GUILD_UPDATE = { "guild" },
}
local EVENT_ORDER = {
    "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
    "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "SKILL_LINES_CHANGED", "PLAYER_GUILD_UPDATE", "PLAYER_LOGOUT",
}

-- 그룹 수집 후 변경 필드 반환, dik, 2026-09-30
local function RunGroups(info, groups, arg)
    local changed = {}
    for i = 1, #groups do
        local fn = GROUP_FUNCS[groups[i]]
        xpcall(function() fn(info, changed, arg) end, geterrorhandler())
    end
    return changed
end

-- 시각 기록, dik, 2026-09-30
local function StampLastSeen(info)
    if CheckAPIs("time") then
        local now = time()
        if not ns.IsSecret(now) then
            info.lastSeen = now
        end
    end
end

-- 첫 전체 스냅샷 후 미지원 안내 1회, dik, 2026-09-30
local function NotifyMissingOnce()
    if snapshotDone then
        return
    end
    snapshotDone = true
    if #missingList > 0 then
        ns.Print(string.format(L.MSG_CHAR_FIELDS_UNSUPPORTED, ns.FormatMissingAPIs(missingList)))
    end
end

-- 전체 스냅샷(READY·입장), dik, 2026-09-30
local function CollectFull()
    if ns.IsDatabaseNewer() or not ns.db then
        return
    end
    if not currentKey then
        currentKey = ReadKey()
        if not currentKey then
            return
        end
    end
    local entry = GetEntry(currentKey, true)
    local changed = RunGroups(entry.info, ALL_GROUPS)
    StampLastSeen(entry.info)
    if next(changed) ~= nil then
        ns.Fire("CHAR_UPDATED", currentKey, changed)
    end
    NotifyMissingOnce()
end

-- 부분 수집(이벤트 트리거), dik, 2026-09-30
local function CollectPartial(groups, arg)
    if ns.IsDatabaseNewer() or not ns.db or not currentKey then
        return
    end
    local entry = GetEntry(currentKey, true)
    local changed = RunGroups(entry.info, groups, arg)
    if next(changed) ~= nil then
        ns.Fire("CHAR_UPDATED", currentKey, changed)
    end
end

-- 로그아웃 저장(이벤트 발행 없음), dik, 2026-09-30
local function CollectLogout()
    if ns.IsDatabaseNewer() or not ns.db or not currentKey then
        return
    end
    local entry = GetEntry(currentKey, true)
    RunGroups(entry.info, { "xp", "money" })
    StampLastSeen(entry.info)
end

-- 수집 이벤트 프레임·등록(없는 이벤트는 건너뜀), dik, 2026-09-30
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGOUT" then
        CollectLogout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CollectFull()
    elseif EVENT_GROUPS[event] then
        CollectPartial(EVENT_GROUPS[event], arg1)
    end
end)

for i = 1, #EVENT_ORDER do
    local eventName = EVENT_ORDER[i]
    local registered = pcall(frame.RegisterEvent, frame, eventName)
    if not registered then
        AddMissing(eventName)
    end
end

ns.On("READY", CollectFull)

-- 현재 캐릭터 키, dik, 2026-09-30
function ns.GetCurrentCharacterKey()
    return currentKey
end

-- 캐릭터 키 목록(현재 먼저, 나머지 오름차순), dik, 2026-09-30
function ns.GetCharacterKeys()
    local keys = {}
    local db = ns.db
    if not db or type(db.chars) ~= "table" then
        return keys
    end
    for key, entry in pairs(db.chars) do
        if type(key) == "string" and type(entry) == "table" and key ~= currentKey then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    if currentKey and type(db.chars[currentKey]) == "table" then
        table.insert(keys, 1, currentKey)
    end
    return keys
end

-- 스냅샷 조회(원본 참조·읽기 전용), dik, 2026-09-30
function ns.GetCharacterInfo(key)
    local entry = GetEntry(key, false)
    if entry and type(entry.info) == "table" then
        return entry.info
    end
    return nil
end

-- 모듈별 캐릭터 데이터 영역, dik, 2026-09-30
function ns.GetCharacterData(moduleId, key)
    if type(moduleId) ~= "string" or moduleId == "" or not ns.db then
        return nil
    end
    local target = key
    if target == nil then
        target = currentKey
    end
    if type(target) ~= "string" then
        return nil
    end
    local writable = not ns.IsDatabaseNewer()
    local entry
    if target == currentKey and writable then
        entry = GetEntry(target, true)
    else
        entry = GetEntry(target, false)
        if entry and type(entry.data) ~= "table" then
            if not writable then
                return nil
            end
            entry.data = {}
        end
    end
    if not entry then
        return nil
    end
    if type(entry.data[moduleId]) ~= "table" then
        if not writable then
            return nil
        end
        entry.data[moduleId] = {}
    end
    return entry.data[moduleId]
end

-- 캐릭터 삭제(현재 캐릭터 불가), dik, 2026-09-30
function ns.DeleteCharacter(key)
    local db = ns.db
    if not db or ns.IsDatabaseNewer() or not currentKey then
        return false
    end
    if key == currentKey then
        ns.Print(L.ERR_CHAR_DELETE_CURRENT)
        return false
    end
    if type(db.chars) ~= "table" or type(key) ~= "string" or db.chars[key] == nil then
        ns.Print(string.format(L.ERR_CHAR_NOT_FOUND, tostring(key)))
        return false
    end
    db.chars[key] = nil
    ns.Fire("CHAR_DELETED", key)
    return true
end

-- 값을 출력 문자열로, dik, 2026-09-30
local function ValueText(value)
    if value == nil then
        return L.VALUE_UNKNOWN
    end
    return tostring(value)
end

-- 지역 출력 문자열, dik, 2026-09-30
local function ZoneText(info)
    if type(info.zone) ~= "string" then
        return L.VALUE_UNKNOWN
    end
    if type(info.subZone) == "string" and info.subZone ~= "" then
        return info.zone .. " / " .. info.subZone
    end
    return info.zone
end

-- 전문기술 출력 문자열, dik, 2026-09-30
local function ProfessionsText(info)
    if type(info.professions) ~= "table" then
        return L.CHAR_LIST_PROF_UNKNOWN
    end
    local parts = {}
    for i = 1, #info.professions do
        local prof = info.professions[i]
        if type(prof) == "table" then
            parts[#parts + 1] = string.format("%s %s/%s", ValueText(prof.name), ValueText(prof.rank), ValueText(prof.maxRank))
        end
    end
    if #parts == 0 then
        return L.CHAR_LIST_PROF_NONE
    end
    return table.concat(parts, ", ")
end

-- 마지막 접속 출력 문자열, dik, 2026-09-30
local function LastSeenText(info)
    if type(info.lastSeen) == "number" and ns.HasAPI("date") then
        return date("%Y-%m-%d %H:%M", info.lastSeen)
    end
    return L.VALUE_UNKNOWN
end

-- /dikf 캐릭터 채팅 출력, dik, 2026-09-30
function ns.PrintCharacters()
    local keys = ns.GetCharacterKeys()
    if #keys == 0 then
        ns.Print(L.CHAR_LIST_EMPTY)
        return
    end
    ns.Print(string.format(L.CHAR_LIST_HEADER, #keys))
    for i = 1, #keys do
        local key = keys[i]
        local info = ns.GetCharacterInfo(key) or {}
        if key == currentKey then
            ns.Print(string.format(L.CHAR_LIST_CURRENT, key, ValueText(info.level), ValueText(info.xp),
                ValueText(info.xpMax), ValueText(info.restXp), ValueText(info.money), ZoneText(info)))
            ns.Print(string.format(L.CHAR_LIST_PROFESSIONS, ProfessionsText(info)))
        else
            ns.Print(string.format(L.CHAR_LIST_OTHER, key, ValueText(info.level), LastSeenText(info)))
        end
    end
end
