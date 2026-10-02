-- 귀속·리셋 모듈 등록·수집·만료·입장 카운터, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "lockouts"
local AREA_VERSION = 1
local LIST_MAX = 50
local ENTRY_MAX = 30
local HOURLY_WINDOW_SECONDS = 3600
local REQUEST_MIN_INTERVAL = 10
local DEFAULT_LIMIT = 5

local EVENT_ORDER = {
    "UPDATE_INSTANCE_INFO",
    "PLAYER_ENTERING_WORLD",
    "BOSS_KILL",
    "CHAT_MSG_SYSTEM",
}

local state = {
    ready = false,
    readOnly = false,
    secret = false,
    characterKey = nil,
    area = nil,
    entries = nil,
    entryArea = nil,
    pendingScan = false,
    lastRequest = nil,
    timerPending = false,
    missing = {},
    frame = nil,
}

ns.Lockouts = {}

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 현재 시각(time 없으면 nil), dik, 2026-09-30
local function GetNow()
    if ns.HasAPI("time") then
        local now = time()
        if IsNumber(now) then
            return now
        end
    end
    return nil
end

-- 경과 판정용 시각(GetTime 없으면 nil), dik, 2026-09-30
local function GetClock()
    if ns.HasAPI("GetTime") then
        local t = GetTime()
        if IsNumber(t) then
            return t
        end
    end
    return nil
end

-- 레코드 만들기(순수 함수), dik, 2026-09-30
function ns.Lockouts.MakeRecord(raw, now)
    if type(raw) ~= "table" or not IsNumber(now) then
        return nil
    end
    if type(raw.name) ~= "string" or raw.name == "" or raw.locked ~= true then
        return nil
    end
    if not IsNumber(raw.reset) or raw.reset <= 0 then
        return nil
    end
    local record = {
        name = raw.name,
        resetAt = now + math.floor(raw.reset),
        isRaid = raw.isRaid == true,
        extended = raw.extended == true,
    }
    if IsNumber(raw.difficultyId) then
        record.difficultyId = raw.difficultyId
    end
    if type(raw.difficultyName) == "string" then
        record.difficultyName = raw.difficultyName
    end
    if IsNumber(raw.maxPlayers) then
        record.maxPlayers = raw.maxPlayers
    end
    if IsNumber(raw.lockoutId) then
        record.lockoutId = raw.lockoutId
    end
    if IsNumber(raw.numEncounters) and raw.numEncounters > 0 then
        local total = raw.numEncounters
        local progress = 0
        if IsNumber(raw.encounterProgress) then
            progress = raw.encounterProgress
        end
        if progress > total then
            progress = total
        end
        record.progress = progress
        record.total = total
    end
    return record
end

-- 남은 시간(순수 함수), dik, 2026-09-30
function ns.Lockouts.Remaining(record, now)
    if type(record) ~= "table" or not IsNumber(record.resetAt) or not IsNumber(now) then
        return nil
    end
    return record.resetAt - now
end

-- 만료 항목 제거(순수 함수 — list 변경), dik, 2026-09-30
function ns.Lockouts.PruneExpired(list, now)
    if type(list) ~= "table" or not IsNumber(now) then
        return 0
    end
    local total = #list
    local kept = 0
    for i = 1, total do
        local item = list[i]
        local remaining = nil
        if type(item) == "table" then
            remaining = ns.Lockouts.Remaining(item, now)
        end
        if remaining ~= nil and remaining > 0 then
            kept = kept + 1
            list[kept] = item
        end
    end
    for i = total, kept + 1, -1 do
        list[i] = nil
    end
    return total - kept
end

-- 입장 기록 원소가 1시간 창 안인지 판정, dik, 2026-09-30
local function IsInWindow(item, now)
    return type(item) == "table" and IsNumber(item.at) and IsNumber(now)
        and now - item.at < HOURLY_WINDOW_SECONDS
end

-- 같은 인스턴스 판정(순수), dik, 2026-09-30
local function IsSameInstance(item, mapId, difficultyId, name)
    local same = false
    if IsNumber(item.mapId) and IsNumber(mapId) then
        same = item.mapId == mapId
    elseif type(item.name) == "string" and type(name) == "string" then
        same = item.name == name
    end
    return same and item.difficultyId == difficultyId
end

-- 입장을 셀지 판정(순수 함수), dik, 2026-09-30
function ns.Lockouts.ShouldCountEntry(entries, charKey, mapId, difficultyId, name, now)
    if type(charKey) ~= "string" or type(entries) ~= "table" or not IsNumber(now) then
        return false
    end
    for i = 1, #entries do
        local item = entries[i]
        if IsInWindow(item, now) and item.char == charKey and item.reset ~= true
            and IsSameInstance(item, mapId, difficultyId, name) then
            return false
        end
    end
    return true
end

-- 입장 기록 정리(순수 함수 — entries 변경), dik, 2026-09-30
function ns.Lockouts.PruneEntries(entries, now)
    if type(entries) ~= "table" or not IsNumber(now) then
        return 0
    end
    local total = #entries
    local kept = 0
    for i = 1, total do
        local item = entries[i]
        if type(item) == "table" and IsNumber(item.at) and type(item.char) == "string"
            and now - item.at < HOURLY_WINDOW_SECONDS then
            kept = kept + 1
            entries[kept] = item
        end
    end
    for i = total, kept + 1, -1 do
        entries[i] = nil
    end
    return total - kept
end

-- 초기화 문구 일치 판정(순수 함수), dik, 2026-09-30
function ns.Lockouts.MatchResetMessage(msg, template)
    if type(msg) ~= "string" or type(template) ~= "string" then
        return false
    end
    local p = template:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%%%s", ".+")
    p = p:gsub("|1[^;]*;[^;]*;", ".-")
    return msg:find("^" .. p .. "$") ~= nil
end

-- 초기화 표시(순수 함수 — entries 변경), dik, 2026-09-30
function ns.Lockouts.MarkReset(entries, charKey, now)
    if type(entries) ~= "table" or type(charKey) ~= "string" or not IsNumber(now) then
        return 0
    end
    local marked = 0
    for i = 1, #entries do
        local item = entries[i]
        if IsInWindow(item, now) and item.char == charKey then
            item.reset = true
            marked = marked + 1
        end
    end
    return marked
end

-- 시간당 입장 상태(순수 함수), dik, 2026-09-30
function ns.Lockouts.HourlyStatus(entries, limit, now)
    if not IsNumber(limit) or limit < 1 then
        limit = DEFAULT_LIMIT
    end
    local win = {}
    if type(entries) == "table" then
        for i = 1, #entries do
            if IsInWindow(entries[i], now) then
                win[#win + 1] = entries[i]
            end
        end
    end
    table.sort(win, function(a, b)
        return a.at < b.at
    end)
    local count = #win
    local status = { count = count, limit = limit, left = math.max(0, limit - count) }
    if count >= limit then
        status.wait = win[count - limit + 1].at + HOURLY_WINDOW_SECONDS - now
    end
    return status
end

-- 저장 영역 검증(손상 값 보정), dik, 2026-09-30
local function ValidateStore(store)
    if not IsNumber(store.version) or store.version < 1 then
        store.version = AREA_VERSION
    end
    if not IsNumber(store.scannedAt) then
        store.scannedAt = nil
    end
    local clean = {}
    if type(store.list) == "table" then
        for i = 1, #store.list do
            local item = store.list[i]
            if type(item) == "table" and type(item.name) == "string" and item.name ~= ""
                and IsNumber(item.resetAt) then
                clean[#clean + 1] = item
            end
        end
    end
    store.list = clean
end

-- 저장 입장 기록을 메모리 배열로 복사(쓰기 금지 모드), dik, 2026-09-30
local function CopyEntries(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for i = 1, #source do
        local item = source[i]
        if type(item) == "table" then
            copy[#copy + 1] = {
                at = item.at, char = item.char, mapId = item.mapId,
                difficultyId = item.difficultyId, name = item.name, reset = item.reset,
            }
        end
    end
    return copy
end

-- 공통 영역의 입장 기록 로드(쓸 수 없으면 메모리 배열), dik, 2026-09-30
local function LoadEntries()
    state.entries = {}
    state.entryArea = nil
    if ns.IsDatabaseNewer() then
        local modules = ns.db and ns.db.modules
        if type(modules) == "table" and type(modules[MODULE_ID]) == "table" then
            state.entries = CopyEntries(modules[MODULE_ID].entries)
        end
        return
    end
    local common = ns.GetModuleData(MODULE_ID)
    if type(common) ~= "table" then
        return
    end
    if IsNumber(common.version) and common.version > AREA_VERSION then
        state.entries = CopyEntries(common.entries)
        return
    end
    if type(common.entries) ~= "table" then
        common.entries = {}
    end
    state.entries = common.entries
    state.entryArea = common
end

-- 전 캐릭터 만료 정리(쓰기 가능할 때만), dik, 2026-09-30
local function PruneAllExpired(now)
    if ns.IsDatabaseNewer() then
        return
    end
    local keys = ns.GetCharacterKeys()
    for i = 1, #keys do
        local key = keys[i]
        local data = nil
        if key == state.characterKey then
            if not state.readOnly then
                data = state.area
            end
        else
            data = ns.GetCharacterData(MODULE_ID, key)
        end
        if type(data) == "table" and not (IsNumber(data.version) and data.version > AREA_VERSION)
            and type(data.list) == "table" then
            ns.Lockouts.PruneExpired(data.list, now)
        end
    end
end

-- 갱신 요청 실행, dik, 2026-09-30
local function DoRequest()
    state.lastRequest = GetClock()
    RequestRaidInfo()
end

-- 갱신 요청(10초 간격·1회 예약), dik, 2026-09-30
local function Request()
    if not ns.HasAPI("RequestRaidInfo") then
        return
    end
    local clock = GetClock()
    if clock == nil or state.lastRequest == nil or clock - state.lastRequest >= REQUEST_MIN_INTERVAL then
        DoRequest()
        return
    end
    if state.timerPending or not ns.HasAPI("C_Timer.After") then
        return
    end
    state.timerPending = true
    C_Timer.After(math.max(0, state.lastRequest + REQUEST_MIN_INTERVAL - clock), function()
        state.timerPending = false
        DoRequest()
    end)
end

-- 귀속 API 12개 반환값 읽기(secret 이면 nil 반환), dik, 2026-09-30
local function ReadRaw(index)
    local r = { GetSavedInstanceInfo(index) }
    for i = 1, 12 do
        if ns.IsSecret(r[i]) then
            return nil
        end
    end
    return {
        name = r[1], lockoutId = r[2], reset = r[3], difficultyId = r[4], locked = r[5],
        extended = r[6], isRaid = r[8], maxPlayers = r[9], difficultyName = r[10],
        numEncounters = r[11], encounterProgress = r[12],
    }
end

-- 수집 중 secret 발생 처리(저장값 유지), dik, 2026-09-30
local function MarkSecret()
    state.secret = true
    state.pendingScan = false
    ns.Fire("LOCKOUTS_UPDATED")
end

-- 귀속 수집(목록 통째 교체), dik, 2026-09-30
local function Collect()
    local now = GetNow()
    if now == nil then
        return
    end
    local n = GetNumSavedInstances()
    if ns.IsSecret(n) then
        MarkSecret()
        return
    end
    if not IsNumber(n) then
        n = 0
    end
    local list = {}
    local index = 1
    while index <= n and #list < LIST_MAX do
        local raw = ReadRaw(index)
        if raw == nil then
            MarkSecret()
            return
        end
        local record = ns.Lockouts.MakeRecord(raw, now)
        if record ~= nil then
            list[#list + 1] = record
        end
        index = index + 1
    end
    state.area.list = list
    state.area.scannedAt = now
    state.secret = false
    state.pendingScan = false
    ns.Fire("LOCKOUTS_UPDATED")
end

-- 준비 판정·영역 로드·정리·요청(READY·CHAR_UPDATED), dik, 2026-09-30
local function Prepare()
    if state.ready then
        return
    end
    local key = ns.GetCurrentCharacterKey()
    if key == nil then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local area = nil
    local readOnly = false
    if ns.IsDatabaseNewer() then
        readOnly = true
    else
        local store = ns.GetCharacterData(MODULE_ID)
        if store == nil then
            return
        end
        if IsNumber(store.version) and store.version > AREA_VERSION then
            readOnly = true
        else
            ValidateStore(store)
            area = store
        end
    end
    if readOnly then
        area = { version = AREA_VERSION, list = {} }
    end
    state.area = area
    state.readOnly = readOnly
    state.characterKey = key
    state.secret = false
    state.ready = true
    LoadEntries()
    PruneAllExpired(now)
    ns.Lockouts.PruneEntries(state.entries, now)
    if ns.HasAPI("RequestRaidInfo") then
        Request()
    elseif state.pendingScan then
        Collect()
    end
    ns.Fire("LOCKOUTS_UPDATED")
end

-- 시간당 카운터 설정 여부, dik, 2026-09-30
local function IsCounterEnabled()
    return ns.GetSetting(MODULE_ID, "hourlyCounter") == true
end

-- 입장 기록 추가(파티·공격대 인스턴스), dik, 2026-09-30
local function RecordEntry()
    if not ns.HasAPI("IsInInstance") or not ns.HasAPI("GetInstanceInfo") then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local inInstance, instanceType = IsInInstance()
    if ns.IsSecret(inInstance) or ns.IsSecret(instanceType) then
        return
    end
    if inInstance ~= true or (instanceType ~= "party" and instanceType ~= "raid") then
        return
    end
    local info = { GetInstanceInfo() }
    local name, difficultyId, mapId = info[1], info[3], info[8]
    if ns.IsSecret(name) or type(name) ~= "string" then
        name = nil
    end
    if ns.IsSecret(difficultyId) or not IsNumber(difficultyId) then
        difficultyId = nil
    end
    if ns.IsSecret(mapId) or not IsNumber(mapId) then
        mapId = nil
    end
    local entries = state.entries
    ns.Lockouts.PruneEntries(entries, now)
    if not ns.Lockouts.ShouldCountEntry(entries, state.characterKey, mapId, difficultyId, name, now) then
        return
    end
    entries[#entries + 1] = {
        at = now, char = state.characterKey, mapId = mapId, difficultyId = difficultyId, name = name,
    }
    while #entries > ENTRY_MAX do
        table.remove(entries, 1)
    end
    local common = state.entryArea
    if common ~= nil and (not IsNumber(common.version) or common.version < 1) then
        common.version = AREA_VERSION
    end
    ns.Fire("LOCKOUTS_UPDATED")
    local status = ns.Lockouts.HourlyStatus(entries, ns.GetSetting(MODULE_ID, "hourlyLimit"), now)
    if status.wait ~= nil then
        ns.Print(L.MSG_LOCKOUTS_HOURLY_LIMIT:format(status.count, status.limit, ns.FormatDuration(status.wait)))
    end
end

-- 시스템 메시지 처리(초기화 감지), dik, 2026-09-30
local function OnSystemMessage(msg)
    if not state.ready or not IsCounterEnabled() then
        return
    end
    if ns.IsSecret(msg) or type(msg) ~= "string" or type(INSTANCE_RESET_SUCCESS) ~= "string" then
        return
    end
    local now = GetNow()
    if now ~= nil and ns.Lockouts.MatchResetMessage(msg, INSTANCE_RESET_SUCCESS) then
        ns.Lockouts.MarkReset(state.entries, state.characterKey, now)
    end
end

-- 이벤트 분배, dik, 2026-09-30
local function OnEvent(_, event, msg)
    if event == "UPDATE_INSTANCE_INFO" then
        if state.ready then
            Collect()
        else
            state.pendingScan = true
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if state.ready then
            Request()
            if IsCounterEnabled() then
                RecordEntry()
            end
        end
    elseif event == "BOSS_KILL" then
        if state.ready then
            Request()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(msg)
    end
end

-- 이벤트 프레임 생성·등록·선택 API 검사·구독, dik, 2026-09-30
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    local missing = {}
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        local registered = pcall(frame.RegisterEvent, frame, name)
        if not registered then
            missing[#missing + 1] = name
        end
    end
    if not ns.HasAPI("RequestRaidInfo") then
        missing[#missing + 1] = "RequestRaidInfo"
    end
    local dailyPath = "C_DateAndTime.GetSecondsUntilDailyReset"
    if not ns.HasAPI(dailyPath) and not ns.HasAPI("GetQuestResetTime") then
        missing[#missing + 1] = dailyPath
    end
    local weeklyPath = "C_DateAndTime.GetSecondsUntilWeeklyReset"
    if not ns.HasAPI(weeklyPath) then
        missing[#missing + 1] = weeklyPath
    end
    if not ns.HasAPI("IsInInstance") then
        missing[#missing + 1] = "IsInInstance"
    end
    if not ns.HasAPI("GetInstanceInfo") then
        missing[#missing + 1] = "GetInstanceInfo"
    end
    if type(INSTANCE_RESET_SUCCESS) ~= "string" then
        missing[#missing + 1] = "INSTANCE_RESET_SUCCESS"
    end
    state.missing = missing
    if #missing > 0 then
        ns.Print(L.MSG_LOCKOUTS_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
    ns.On("READY", Prepare)
    ns.On("CHAR_UPDATED", Prepare)
end

-- 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_LOCKOUTS,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_LOCKOUTS_DESC,
    category = "feature",
    order = 50,
    requires = { "GetNumSavedInstances", "GetSavedInstanceInfo", "time" },
    settings = {
        { key = "hourlyCounter", type = "checkbox", label = L.SETTING_LOCKOUTS_HOURLY,
            tooltip = L.SETTING_LOCKOUTS_HOURLY_TIP, default = false },
        { key = "hourlyLimit", type = "slider", label = L.SETTING_LOCKOUTS_LIMIT,
            tooltip = L.SETTING_LOCKOUTS_LIMIT_TIP, min = 1, max = 30, step = 1, default = 5 },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
    OnSettingChanged = function(_, key)
        if key == "hourlyCounter" or key == "hourlyLimit" then
            ns.Fire("LOCKOUTS_UPDATED")
        end
    end,
})

-- 저장 영역 직접 읽기(생성 없음), dik, 2026-09-30
local function ReadStored(key)
    local db = ns.db
    if type(db) ~= "table" or type(db.chars) ~= "table" then
        return nil
    end
    local entry = db.chars[key]
    if type(entry) ~= "table" or type(entry.data) ~= "table" then
        return nil
    end
    local area = entry.data[MODULE_ID]
    if type(area) == "table" then
        return area
    end
    return nil
end

-- 캐릭터 영역 읽기(검증·수정 없음, version 이 새거면 nil), dik, 2026-09-30
local function GetReadArea(key, currentKey)
    local area
    if key == currentKey and state.ready and state.characterKey == key then
        area = state.area
    elseif key == currentKey or ns.IsDatabaseNewer() then
        area = ReadStored(key)
    else
        area = ns.GetCharacterData(MODULE_ID, key)
    end
    if type(area) ~= "table" or (IsNumber(area.version) and area.version > AREA_VERSION) then
        return nil
    end
    return area
end

-- 표 행(매 호출 새 배열, 만료 제외), dik, 2026-09-30
function ns.Lockouts.BuildRows(now)
    if not IsNumber(now) then
        now = GetNow()
    end
    local rows = {}
    if now == nil then
        return rows
    end
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local nameCount = {}
    local infos = {}
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            infos[keys[i]] = info
            nameCount[info.name] = (nameCount[info.name] or 0) + 1
        end
    end
    for i = 1, #keys do
        local key = keys[i]
        local area = GetReadArea(key, currentKey)
        if area ~= nil and type(area.list) == "table" then
            local info = infos[key]
            local displayName = key
            local classFile = nil
            if info ~= nil then
                if nameCount[info.name] == 1 then
                    displayName = info.name
                end
                if type(info.classFile) == "string" then
                    classFile = info.classFile
                end
            end
            for idx = 1, #area.list do
                local rec = area.list[idx]
                if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then
                    local remaining = ns.Lockouts.Remaining(rec, now)
                    if remaining ~= nil and remaining > 0 then
                        rows[#rows + 1] = {
                            id = key .. "#" .. idx,
                            charKey = key,
                            isCurrent = key == currentKey,
                            displayName = displayName,
                            classFile = classFile,
                            name = rec.name,
                            extended = rec.extended == true,
                            isRaid = rec.isRaid == true,
                            difficultyName = type(rec.difficultyName) == "string" and rec.difficultyName or nil,
                            progress = IsNumber(rec.progress) and rec.progress or nil,
                            total = IsNumber(rec.total) and rec.total or nil,
                            resetAt = rec.resetAt,
                            remaining = remaining,
                        }
                    end
                end
            end
        end
    end
    return rows
end

-- 요약, dik, 2026-09-30
function ns.Lockouts.GetSummary(now)
    if not IsNumber(now) then
        now = GetNow()
    end
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local summary = {
        lockoutCount = #ns.Lockouts.BuildRows(now),
        scannedChars = 0,
        totalChars = #keys,
        currentScannedAt = nil,
    }
    for i = 1, #keys do
        local area = GetReadArea(keys[i], currentKey)
        if area ~= nil and IsNumber(area.scannedAt) then
            summary.scannedChars = summary.scannedChars + 1
            if keys[i] == currentKey then
                summary.currentScannedAt = area.scannedAt
            end
        end
    end
    return summary
end

-- 리셋 값 정리(secret·비정상은 nil), dik, 2026-09-30
local function CleanSeconds(v)
    if ns.IsSecret(v) or not IsNumber(v) or v <= 0 then
        return nil
    end
    return v
end

-- 일일·주간 리셋까지 남은 초, dik, 2026-09-30
function ns.Lockouts.GetResetTimes()
    local daily = nil
    local weekly = nil
    if ns.HasAPI("C_DateAndTime.GetSecondsUntilDailyReset") then
        daily = CleanSeconds(C_DateAndTime.GetSecondsUntilDailyReset())
    elseif ns.HasAPI("GetQuestResetTime") then
        daily = CleanSeconds(GetQuestResetTime())
    end
    if ns.HasAPI("C_DateAndTime.GetSecondsUntilWeeklyReset") then
        weekly = CleanSeconds(C_DateAndTime.GetSecondsUntilWeeklyReset())
    end
    return daily, weekly
end

-- 시간당 입장 현황, dik, 2026-09-30
function ns.Lockouts.GetHourly(now)
    if not IsNumber(now) then
        now = GetNow()
    end
    local status = ns.Lockouts.HourlyStatus(state.entries, ns.GetSetting(MODULE_ID, "hourlyLimit"), now)
    return {
        enabled = IsCounterEnabled(),
        count = status.count,
        limit = status.limit,
        left = status.left,
        wait = status.wait,
    }
end

-- 갱신 요청(간격 제한 규칙), dik, 2026-09-30
function ns.Lockouts.RequestRefresh()
    Request()
end

-- 상태 조회(없는 API·이벤트 이름 복사본), dik, 2026-09-30
function ns.Lockouts.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    return { ready = state.ready, readOnly = state.readOnly, secret = state.secret, missing = missing }
end
