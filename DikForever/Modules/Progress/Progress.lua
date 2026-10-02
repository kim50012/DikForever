-- 평판·진척 모듈 등록·수집·Legacy 추정·행 빌더, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "progress"
local AREA_VERSION = 1
local REP_SCAN_MAX = 400
local REP_MAX = 200
local ZONE_MAX = 80
local CRITERIA_MAX = 100
local REP_DELAY = 1
local PVP_DELAY = 1
local EXPLORE_DELAY = 10
local LEVEL_MILESTONES = { 25, 45, 60 }
local PROF_MILESTONES = { 150, 225, 300 }
local BG_FACTION_IDS = { 889, 890, 509, 510, 729, 730 }
local EXPLORE_META_IDS = { 42, 43 }
local MILESTONE_COUNT = 3

local EVENT_ORDER = {
    "UPDATE_FACTION",
    "PLAYER_PVP_KILLS_CHANGED",
    "HONOR_LEVEL_UPDATE",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "ACHIEVEMENT_EARNED",
}

local REP_REQUIRED_APIS = { "C_Reputation.GetNumFactions", "C_Reputation.GetFactionDataByIndex" }
local REP_OPTIONAL_APIS = { "C_Reputation.GetFactionDataByID" }
local PVP_APIS = { "GetPVPLifetimeStats", "UnitHonorLevel" }
local EXPLORE_REQUIRED_APIS = { "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo" }

local FACTION_SECRET_FIELDS = {
    "factionID", "name", "reaction", "currentReactionThreshold",
    "nextReactionThreshold", "currentStanding", "isHeader", "isHeaderWithRep",
}

local DELAYS = { rep = REP_DELAY, pvp = PVP_DELAY, explore = EXPLORE_DELAY }

local state = {
    ready = false,
    readOnly = false,
    characterKey = nil,
    area = nil,
    pendingRep = false,
    sessionBase = {},
    scheduled = { rep = false, pvp = false, explore = false },
    sections = { rep = "ok", pvp = "ok", explore = "ok" },
    missing = { rep = {}, pvp = {}, explore = {} },
    eventMissing = {},
    frame = nil,
}

ns.Progress = {}

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 정수 판정, dik, 2026-10-01
local function IsInt(v)
    return IsNumber(v) and v == math.floor(v)
end

-- 양의 정수 판정, dik, 2026-10-01
local function IsPosInt(v)
    return IsInt(v) and v > 0
end

-- 비어 있지 않은 문자열 판정, dik, 2026-10-01
local function IsText(v)
    return type(v) == "string" and v ~= ""
end

-- 현재 시각(time 없으면 nil), dik, 2026-10-01
local function GetNow()
    if ns.HasAPI("time") then
        local now = time()
        if IsNumber(now) then
            return now
        end
    end
    return nil
end

-- 평판 항목 검증, dik, 2026-10-01
local function IsValidRepEntry(e)
    return type(e) == "table" and IsText(e.name) and IsInt(e.reaction) and e.reaction >= 1
        and e.reaction <= 8 and IsNumber(e.standing) and IsNumber(e.min) and IsNumber(e.max)
end

-- 지역 항목 검증, dik, 2026-10-01
local function IsValidZone(z)
    return type(z) == "table" and IsPosInt(z.id) and IsText(z.name) and IsInt(z.done)
        and IsInt(z.total) and z.done >= 0 and z.total >= 0 and z.done <= z.total
end

-- 평판 항목 만들기(순수 함수), dik, 2026-10-01
function ns.Progress.MakeRepEntry(data)
    if type(data) ~= "table" then
        return nil
    end
    if not IsPosInt(data.factionID) or not IsText(data.name) then
        return nil
    end
    if data.isHeader == true and data.isHeaderWithRep ~= true then
        return nil
    end
    local reaction = data.reaction
    if not IsInt(reaction) or reaction < 1 or reaction > 8 then
        return nil
    end
    if not IsNumber(data.currentReactionThreshold) or not IsNumber(data.nextReactionThreshold)
        or not IsNumber(data.currentStanding) then
        return nil
    end
    return data.factionID, {
        name = data.name,
        reaction = reaction,
        standing = data.currentStanding,
        min = data.currentReactionThreshold,
        max = data.nextReactionThreshold,
    }
end

-- 진행 값(순수 함수), dik, 2026-10-01
function ns.Progress.RepProgress(entry)
    if type(entry) ~= "table" or not IsNumber(entry.min) or not IsNumber(entry.max)
        or not IsNumber(entry.standing) then
        return 0, 1, 0
    end
    local span = entry.max - entry.min
    if span <= 0 then
        return 1, 1, 1
    end
    local value = entry.standing - entry.min
    if value < 0 then
        value = 0
    elseif value > span then
        value = span
    end
    return value, span, value / span
end

-- 등급 이름, dik, 2026-10-01
function ns.Progress.StandingLabel(reaction)
    if IsInt(reaction) and reaction >= 1 and reaction <= 8 then
        return L["REP_STANDING_" .. string.format("%d", reaction)]
    end
    return L.VALUE_UNKNOWN
end

-- 우열 비교(순수 함수), dik, 2026-10-01
function ns.Progress.IsBetterRep(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    if a.reaction > b.reaction then
        return true
    end
    return a.reaction == b.reaction and a.standing > b.standing
end

-- 이정표 달성 수·다음 목표(순수 함수), dik, 2026-10-01
function ns.Progress.MilestoneState(value, milestones)
    if not IsNumber(value) then
        value = 0
    end
    local reached = 0
    local nextTarget = nil
    if type(milestones) == "table" then
        for i = 1, #milestones do
            if milestones[i] <= value then
                reached = reached + 1
            elseif nextTarget == nil then
                nextTarget = milestones[i]
            end
        end
    end
    return reached, nextTarget
end

-- 지역 요약(순수 함수), dik, 2026-10-01
function ns.Progress.SummarizeZones(zones)
    local summary = { left = 0, doneZones = 0, totalZones = 0 }
    if type(zones) ~= "table" then
        return summary
    end
    for i = 1, #zones do
        local z = zones[i]
        if IsValidZone(z) then
            summary.left = summary.left + (z.total - z.done)
            summary.totalZones = summary.totalZones + 1
            if z.done >= z.total then
                summary.doneZones = summary.doneZones + 1
            end
        end
    end
    return summary
end

-- 저장 영역 검증(손상 값 보정), dik, 2026-10-01
local function ValidateStore(store)
    if not IsNumber(store.version) or store.version < 1 then
        store.version = AREA_VERSION
    end
    if type(store.rep) ~= "table" or type(store.rep.list) ~= "table" then
        store.rep = nil
    else
        local list = store.rep.list
        for k, v in pairs(list) do
            if not IsPosInt(k) or not IsValidRepEntry(v) then
                list[k] = nil
            end
        end
    end
    if type(store.pvp) ~= "table" then
        store.pvp = nil
    else
        if not IsNumber(store.pvp.kills) then
            store.pvp.kills = nil
        end
        if not IsNumber(store.pvp.honorLevel) then
            store.pvp.honorLevel = nil
        end
    end
    if type(store.explore) ~= "table" or type(store.explore.zones) ~= "table" then
        store.explore = nil
    else
        local clean = {}
        local zones = store.explore.zones
        for i = 1, #zones do
            if IsValidZone(zones[i]) then
                clean[#clean + 1] = zones[i]
            end
        end
        store.explore.zones = clean
    end
end

-- 저장 영역 직접 읽기(생성 없음), dik, 2026-10-01
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

-- 캐릭터 영역 읽기(version 이 새거면 nil), dik, 2026-10-01
local function GetReadArea(key, currentKey)
    local area
    if key == currentKey and state.ready and state.characterKey == key then
        area = state.area
    else
        area = ReadStored(key)
    end
    if type(area) ~= "table" or (IsNumber(area.version) and area.version > AREA_VERSION) then
        return nil
    end
    return area
end

-- 영역의 평판 맵(걸러 낸 새 테이블), dik, 2026-10-01
local function GetRepMap(area)
    local map = {}
    if type(area) == "table" and type(area.rep) == "table" and type(area.rep.list) == "table" then
        for k, v in pairs(area.rep.list) do
            if IsPosInt(k) and IsValidRepEntry(v) then
                map[k] = v
            end
        end
    end
    return map
end

-- 영역의 지역 배열(걸러 낸 새 테이블), dik, 2026-10-01
local function GetZoneList(area)
    local list = {}
    if type(area) == "table" and type(area.explore) == "table" and type(area.explore.zones) == "table" then
        local zones = area.explore.zones
        for i = 1, #zones do
            if IsValidZone(zones[i]) then
                list[#list + 1] = zones[i]
            end
        end
    end
    return list
end

-- 맵 키 오름차순 배열, dik, 2026-10-01
local function SortedKeys(map)
    local keys = {}
    for k in pairs(map) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- 섹션 켜짐 여부(설정), dik, 2026-10-01
local function IsSectionOn(section)
    if section == "pvp" then
        return ns.GetSetting(MODULE_ID, "pvpSection") ~= false
    elseif section == "explore" then
        return ns.GetSetting(MODULE_ID, "exploreSection") ~= false
    end
    return true
end

-- 섹션 수집 가능 여부(설정 켜짐·필요 API 있음), dik, 2026-10-01
local function IsSectionActive(section)
    return IsSectionOn(section) and state.sections[section] ~= "missing"
end

-- 섹션 상태 재계산(secret·notFound 는 유지), dik, 2026-10-01
local function ComputeSections()
    local missing = {
        rep = ns.GetMissingAPIs(REP_REQUIRED_APIS),
        pvp = ns.GetMissingAPIs(PVP_APIS),
        explore = ns.GetMissingAPIs(EXPLORE_REQUIRED_APIS),
    }
    if #missing.pvp < #PVP_APIS then
        missing.pvp = {}
    end
    state.missing = missing
    local sections = {}
    for _, section in ipairs({ "rep", "pvp", "explore" }) do
        local prev = state.sections[section]
        if not IsSectionOn(section) then
            sections[section] = "off"
        elseif #missing[section] > 0 then
            sections[section] = "missing"
        elseif prev == "secret" or prev == "notFound" then
            sections[section] = prev
        else
            sections[section] = "ok"
        end
    end
    state.sections = sections
end

-- 안내 목록(등록 실패 이벤트 + 켜진 섹션의 없는 API), dik, 2026-10-01
local function BuildNotice()
    local list = {}
    local seen = {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    for i = 1, #state.eventMissing do
        add(state.eventMissing[i])
    end
    if IsSectionOn("rep") then
        for i = 1, #state.missing.rep do
            add(state.missing.rep[i])
        end
        local optional = ns.GetMissingAPIs(REP_OPTIONAL_APIS)
        for i = 1, #optional do
            add(optional[i])
        end
    end
    if IsSectionOn("pvp") then
        local absent = ns.GetMissingAPIs(PVP_APIS)
        for i = 1, #absent do
            add(absent[i])
        end
    end
    if IsSectionOn("explore") then
        for i = 1, #state.missing.explore do
            add(state.missing.explore[i])
        end
    end
    return list
end

-- 평판 원본 1행 읽기(secret 여부·항목), dik, 2026-10-01
local function ReadFaction(data)
    if type(data) ~= "table" then
        return "skip"
    end
    if ns.IsSecret(data) then
        return "secret"
    end
    for i = 1, #FACTION_SECRET_FIELDS do
        if ns.IsSecret(data[FACTION_SECRET_FIELDS[i]]) then
            return "secret"
        end
    end
    local fid, entry = ns.Progress.MakeRepEntry(data)
    if entry == nil then
        return "skip"
    end
    return "ok", fid, entry
end

-- 섹션 secret 상태 기록·발행(저장값 유지), dik, 2026-10-01
local function MarkSecret(section)
    state.sections[section] = "secret"
    ns.Fire("PROGRESS_UPDATED", section)
end

-- 평판 수집(목록 통째 교체), dik, 2026-10-01
local function CollectRep()
    if not state.ready or state.sections.rep == "missing" then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local n = C_Reputation.GetNumFactions()
    if ns.IsSecret(n) then
        MarkSecret("rep")
        return
    end
    if not IsNumber(n) then
        n = 0
    end
    local fresh = {}
    local count = 0
    local seen = {}
    for i = 1, math.min(n, REP_SCAN_MAX) do
        local status, fid, entry = ReadFaction(C_Reputation.GetFactionDataByIndex(i))
        if status == "secret" then
            MarkSecret("rep")
            return
        end
        if status == "ok" then
            seen[fid] = true
            if fresh[fid] ~= nil then
                fresh[fid] = entry
            elseif count < REP_MAX then
                count = count + 1
                fresh[fid] = entry
            end
        end
    end
    local old = GetRepMap(state.area)
    local canLookup = ns.HasAPI("C_Reputation.GetFactionDataByID")
    local oldKeys = SortedKeys(old)
    for i = 1, #oldKeys do
        local fid = oldKeys[i]
        if not seen[fid] and count < REP_MAX then
            local keep = old[fid]
            if canLookup then
                local status, gotId, entry = ReadFaction(C_Reputation.GetFactionDataByID(fid))
                if status == "secret" then
                    MarkSecret("rep")
                    return
                end
                if status == "ok" and gotId == fid then
                    keep = entry
                end
            end
            fresh[fid] = keep
            count = count + 1
        end
    end
    state.area.rep = { scannedAt = now, list = fresh }
    for fid, entry in pairs(fresh) do
        if state.sessionBase[fid] == nil then
            state.sessionBase[fid] = entry.standing
        end
    end
    state.sections.rep = "ok"
    state.pendingRep = false
    ns.Fire("PROGRESS_UPDATED", "rep")
end

-- PvP 수집(필드별 저장), dik, 2026-10-01
local function CollectPvp()
    if not state.ready or not IsSectionActive("pvp") then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local pvp = state.area.pvp
    if type(pvp) ~= "table" then
        pvp = {}
    end
    local saved = false
    local secretHit = false
    if ns.HasAPI("GetPVPLifetimeStats") then
        local kills = GetPVPLifetimeStats()
        if ns.IsSecret(kills) then
            secretHit = true
        else
            if IsNumber(kills) then
                pvp.kills = kills
            else
                pvp.kills = nil
            end
            saved = true
        end
    end
    if ns.HasAPI("UnitHonorLevel") then
        local honor = UnitHonorLevel("player")
        if ns.IsSecret(honor) then
            secretHit = true
        else
            if IsNumber(honor) then
                pvp.honorLevel = honor
            else
                pvp.honorLevel = nil
            end
            saved = true
        end
    end
    if saved then
        pvp.scannedAt = now
        state.area.pvp = pvp
    end
    if secretHit then
        state.sections.pvp = "secret"
    else
        state.sections.pvp = "ok"
    end
    ns.Fire("PROGRESS_UPDATED", "pvp")
end

-- 탐험 원본 읽기(지역 배열 또는 nil·사유), dik, 2026-10-01
local function ScanExplore()
    local zones = {}
    for m = 1, #EXPLORE_META_IDS do
        local meta = EXPLORE_META_IDS[m]
        local metaId = GetAchievementInfo(meta)
        if ns.IsSecret(metaId) then
            return nil, "secret"
        end
        if metaId ~= nil then
            local metaCount = GetAchievementNumCriteria(meta)
            if ns.IsSecret(metaCount) then
                return nil, "secret"
            end
            if not IsPosInt(metaCount) then
                metaCount = 0
            end
            for i = 1, math.min(metaCount, CRITERIA_MAX) do
                if #zones >= ZONE_MAX then
                    break
                end
                local criteriaString, _, completed, _, _, _, _, assetId = GetAchievementCriteriaInfo(meta, i)
                if ns.IsSecret(criteriaString) or ns.IsSecret(completed) or ns.IsSecret(assetId) then
                    return nil, "secret"
                end
                -- 지역 도전과제 존재 확인 후 조회, dik, 2026-10-01
                local subId, subName
                if IsPosInt(assetId) then
                    subId, subName = GetAchievementInfo(assetId)
                end
                if ns.IsSecret(subId) or ns.IsSecret(subName) then
                    return nil, "secret"
                end
                if IsPosInt(assetId) and subId ~= nil then
                    local t = GetAchievementNumCriteria(assetId)
                    if ns.IsSecret(t) then
                        return nil, "secret"
                    end
                    local done
                    local total
                    if IsPosInt(t) then
                        total = math.min(t, CRITERIA_MAX)
                        done = 0
                        for j = 1, total do
                            local _, _, subDone = GetAchievementCriteriaInfo(assetId, j)
                            if ns.IsSecret(subDone) then
                                return nil, "secret"
                            end
                            if subDone == true then
                                done = done + 1
                            end
                        end
                    else
                        total = 1
                        done = completed == true and 1 or 0
                    end
                    local name = criteriaString
                    if not IsText(name) then
                        -- 이름 폴백 subName 재사용, dik, 2026-10-01
                        name = subName
                    end
                    if IsText(name) then
                        zones[#zones + 1] = { id = assetId, name = name, done = done, total = total }
                    end
                end
            end
        end
    end
    if #zones == 0 then
        return nil, "notFound"
    end
    return zones
end

-- 탐험 수집(지역 0개면 저장값 유지), dik, 2026-10-01
local function CollectExplore()
    if not state.ready or not IsSectionActive("explore") then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local zones, reason = ScanExplore()
    if zones == nil then
        state.sections.explore = reason
        ns.Fire("PROGRESS_UPDATED", "explore")
        return
    end
    state.area.explore = { scannedAt = now, zones = zones }
    state.sections.explore = "ok"
    ns.Fire("PROGRESS_UPDATED", "explore")
end

local COLLECTORS = { rep = CollectRep, pvp = CollectPvp, explore = CollectExplore }

-- 수집 예약(섹션별 1개 합치기), dik, 2026-10-01
local function Schedule(section, fromEvent)
    if not state.ready or not IsSectionActive(section) or state.scheduled[section] then
        return
    end
    if ns.HasAPI("C_Timer.After") then
        state.scheduled[section] = true
        C_Timer.After(DELAYS[section], function()
            state.scheduled[section] = false
            if state.ready and IsSectionActive(section) then
                COLLECTORS[section]()
            end
        end)
    elseif not (section == "explore" and fromEvent) then
        COLLECTORS[section]()
    end
end

-- 준비 판정·영역 로드·첫 수집(READY·CHAR_UPDATED), dik, 2026-10-01
local function Prepare()
    if state.ready then
        return
    end
    local key = ns.GetCurrentCharacterKey()
    if key == nil then
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
        area = { version = AREA_VERSION }
    end
    state.area = area
    state.readOnly = readOnly
    state.characterKey = key
    state.sessionBase = {}
    state.ready = true
    if state.sections.rep ~= "missing" then
        CollectRep()
    end
    if IsSectionActive("pvp") then
        CollectPvp()
    end
    Schedule("explore", false)
    ns.Fire("PROGRESS_UPDATED", "status")
end

-- 이벤트 분배, dik, 2026-10-01
local function OnEvent(_, event)
    if event == "UPDATE_FACTION" then
        if state.ready then
            Schedule("rep", true)
        else
            state.pendingRep = true
        end
    elseif event == "PLAYER_PVP_KILLS_CHANGED" or event == "HONOR_LEVEL_UPDATE" then
        Schedule("pvp", true)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA" or event == "ACHIEVEMENT_EARNED" then
        Schedule("explore", true)
    end
end

-- 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_PROGRESS,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_PROGRESS_DESC,
    category = "feature",
    order = 90,
    requires = { "time" },
    settings = {
        { key = "pvpSection", type = "checkbox", label = L.SETTING_PROGRESS_PVP,
            tooltip = L.SETTING_PROGRESS_PVP_TIP, default = true },
        { key = "exploreSection", type = "checkbox", label = L.SETTING_PROGRESS_EXPLORE,
            tooltip = L.SETTING_PROGRESS_EXPLORE_TIP, default = true },
    },
    OnInitialize = function(_)
        local frame = CreateFrame("Frame")
        state.frame = frame
        frame:SetScript("OnEvent", OnEvent)
        local failed = {}
        for i = 1, #EVENT_ORDER do
            local name = EVENT_ORDER[i]
            local registered = pcall(frame.RegisterEvent, frame, name)
            if not registered then
                failed[#failed + 1] = name
            end
        end
        state.eventMissing = failed
        ComputeSections()
        local notice = BuildNotice()
        if #notice > 0 then
            ns.Print(L.MSG_PROGRESS_UNSUPPORTED:format(ns.FormatMissingAPIs(notice)))
        end
        ns.On("READY", Prepare)
        ns.On("CHAR_UPDATED", Prepare)
    end,
    OnSettingChanged = function(_, key, value)
        ComputeSections()
        if state.ready and value == true then
            if key == "pvpSection" then
                Schedule("pvp", false)
            elseif key == "exploreSection" then
                Schedule("explore", false)
            end
        end
        ns.Fire("PROGRESS_UPDATED", "status")
    end,
})

-- 캐릭터 이름 정보(유일 이름 판정용), dik, 2026-10-01
local function BuildNames(keys)
    local infos = {}
    local counts = {}
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        if type(info) == "table" and IsText(info.name) then
            infos[keys[i]] = info
            counts[info.name] = (counts[info.name] or 0) + 1
        end
    end
    return infos, counts
end

-- 표시 이름(유일하면 이름, 아니면 키), dik, 2026-10-01
local function DisplayName(key, infos, counts)
    local info = infos[key]
    if info ~= nil and counts[info.name] == 1 then
        return info.name
    end
    return key
end

-- 직업 파일명(없으면 nil), dik, 2026-10-01
local function ClassFileOf(key, infos)
    local info = infos[key]
    if info ~= nil and IsText(info.classFile) then
        return info.classFile
    end
    return nil
end

-- 이번 접속 변화량, dik, 2026-10-01
function ns.Progress.GetSessionGain(factionId)
    if not state.ready or type(state.area) ~= "table" then
        return nil
    end
    local area = state.area
    if type(area.rep) ~= "table" or type(area.rep.list) ~= "table" then
        return nil
    end
    local entry = area.rep.list[factionId]
    local base = state.sessionBase[factionId]
    if not IsValidRepEntry(entry) or not IsNumber(base) then
        return nil
    end
    return entry.standing - base
end

-- 이번 접속 변화 요약, dik, 2026-10-01
function ns.Progress.GetSessionSummary()
    local summary = { count = 0, total = 0 }
    if not state.ready or type(state.area) ~= "table" then
        return summary
    end
    local map = GetRepMap(state.area)
    for fid in pairs(map) do
        local gain = ns.Progress.GetSessionGain(fid)
        if gain ~= nil and gain ~= 0 then
            summary.count = summary.count + 1
            summary.total = summary.total + gain
        end
    end
    return summary
end

-- 평판별 최고 항목 맵·처음 본 순서, dik, 2026-10-01
local function BuildBestMap()
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local best = {}
    local order = {}
    for i = 1, #keys do
        local key = keys[i]
        local area = GetReadArea(key, currentKey)
        if area ~= nil then
            local map = GetRepMap(area)
            local fids = SortedKeys(map)
            for j = 1, #fids do
                local fid = fids[j]
                local entry = map[fid]
                local cur = best[fid]
                if cur == nil then
                    best[fid] = { key = key, entry = entry, count = 1 }
                    order[#order + 1] = fid
                else
                    cur.count = cur.count + 1
                    if ns.Progress.IsBetterRep(entry, cur.entry) then
                        cur.key = key
                        cur.entry = entry
                    end
                end
            end
        end
    end
    return best, order, keys
end

-- 요약 행 만들기(최고 항목 기준), dik, 2026-10-01
local function MakeSummaryRow(fid, b, infos, counts)
    local value, span, ratio = ns.Progress.RepProgress(b.entry)
    return {
        id = tostring(fid),
        factionId = fid,
        name = b.entry.name,
        reaction = b.entry.reaction,
        value = value,
        span = span,
        ratio = ratio,
        bestKey = b.key,
        bestName = DisplayName(b.key, infos, counts),
        bestClassFile = ClassFileOf(b.key, infos),
        count = b.count,
    }
end

-- 평판 표 행(매 호출 새 배열), dik, 2026-10-01
function ns.Progress.GetRepRows(charKey)
    local rows = {}
    if charKey == "all" then
        local best, order, keys = BuildBestMap()
        local infos, counts = BuildNames(keys)
        for i = 1, #order do
            local row = MakeSummaryRow(order[i], best[order[i]], infos, counts)
            row.gain = ns.Progress.GetSessionGain(order[i])
            rows[#rows + 1] = row
        end
        return rows
    end
    local currentKey = ns.GetCurrentCharacterKey()
    local area = GetReadArea(charKey, currentKey)
    if area == nil then
        return rows
    end
    local map = GetRepMap(area)
    local fids = SortedKeys(map)
    for i = 1, #fids do
        local fid = fids[i]
        local entry = map[fid]
        local value, span, ratio = ns.Progress.RepProgress(entry)
        local gain = nil
        if charKey == currentKey then
            gain = ns.Progress.GetSessionGain(fid)
        end
        rows[#rows + 1] = {
            id = tostring(fid),
            factionId = fid,
            name = entry.name,
            reaction = entry.reaction,
            value = value,
            span = span,
            ratio = ratio,
            gain = gain,
        }
    end
    return rows
end

-- Legacy 행 계산(행 배열·요약), dik, 2026-10-01
local function BuildLegacy()
    local keys = ns.GetCharacterKeys()
    local infos, counts = BuildNames(keys)
    local classBest = {}
    local classOrder = {}
    local profBest = {}
    local profOrder = {}
    local targets = 0
    local withProf = 0
    for i = 1, #keys do
        local key = keys[i]
        local info = ns.GetCharacterInfo(key)
        if type(info) == "table" then
            targets = targets + 1
            if IsText(info.classFile) and IsNumber(info.level) then
                local cur = classBest[info.classFile]
                if cur == nil then
                    classBest[info.classFile] = { key = key, info = info }
                    classOrder[#classOrder + 1] = info.classFile
                elseif info.level > cur.info.level then
                    cur.key = key
                    cur.info = info
                end
            end
            if type(info.professions) == "table" then
                withProf = withProf + 1
                for p = 1, #info.professions do
                    local prof = info.professions[p]
                    if type(prof) == "table" and IsText(prof.name) and IsNumber(prof.rank) then
                        local groupKey = "n:" .. prof.name
                        if IsPosInt(prof.skillLine) then
                            groupKey = string.format("%d", prof.skillLine)
                        end
                        local cur = profBest[groupKey]
                        if cur == nil then
                            profBest[groupKey] = { key = key, info = info, prof = prof }
                            profOrder[#profOrder + 1] = groupKey
                        elseif prof.rank > cur.prof.rank then
                            cur.key = key
                            cur.info = info
                            cur.prof = prof
                        end
                    end
                end
            end
        end
    end
    local rows = {}
    local reachedSum = 0
    for i = 1, #classOrder do
        local classFile = classOrder[i]
        local b = classBest[classFile]
        local reached, nextTarget = ns.Progress.MilestoneState(b.info.level, LEVEL_MILESTONES)
        local name = classFile
        if IsText(b.info.className) then
            name = b.info.className
        end
        reachedSum = reachedSum + reached
        rows[#rows + 1] = {
            id = "1:" .. classFile,
            kind = "class",
            name = name,
            classFile = classFile,
            bestKey = b.key,
            bestName = DisplayName(b.key, infos, counts),
            bestClassFile = classFile,
            value = b.info.level,
            reached = reached,
            total = MILESTONE_COUNT,
            nextTarget = nextTarget,
        }
    end
    for i = 1, #profOrder do
        local groupKey = profOrder[i]
        local b = profBest[groupKey]
        local reached, nextTarget = ns.Progress.MilestoneState(b.prof.rank, PROF_MILESTONES)
        reachedSum = reachedSum + reached
        rows[#rows + 1] = {
            id = "2:" .. groupKey,
            kind = "profession",
            name = b.prof.name,
            bestKey = b.key,
            bestName = DisplayName(b.key, infos, counts),
            bestClassFile = ClassFileOf(b.key, infos),
            value = b.prof.rank,
            reached = reached,
            total = MILESTONE_COUNT,
            nextTarget = nextTarget,
        }
    end
    local summary = {
        reached = reachedSum,
        total = #rows * MILESTONE_COUNT,
        profUnknown = targets >= 1 and withProf == 0,
    }
    return rows, summary
end

-- Legacy 행, dik, 2026-10-01
function ns.Progress.GetLegacyRows()
    local rows = BuildLegacy()
    return rows
end

-- Legacy 요약, dik, 2026-10-01
function ns.Progress.GetLegacySummary()
    local _, summary = BuildLegacy()
    return summary
end

-- PvP 캐릭터 행, dik, 2026-10-01
function ns.Progress.GetPvpRows()
    local rows = {}
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local infos, counts = BuildNames(keys)
    for i = 1, #keys do
        local key = keys[i]
        local area = GetReadArea(key, currentKey)
        if area ~= nil and type(area.pvp) == "table" and IsNumber(area.pvp.scannedAt) then
            local kills = nil
            if IsNumber(area.pvp.kills) then
                kills = area.pvp.kills
            end
            local honorLevel = nil
            if IsNumber(area.pvp.honorLevel) then
                honorLevel = area.pvp.honorLevel
            end
            rows[#rows + 1] = {
                id = key,
                displayName = DisplayName(key, infos, counts),
                classFile = ClassFileOf(key, infos),
                kills = kills,
                honorLevel = honorLevel,
                scannedAt = area.pvp.scannedAt,
            }
        end
    end
    return rows
end

-- 전장 평판 행, dik, 2026-10-01
function ns.Progress.GetBgRows()
    local rows = {}
    local best, _, keys = BuildBestMap()
    local infos, counts = BuildNames(keys)
    for i = 1, #BG_FACTION_IDS do
        local fid = BG_FACTION_IDS[i]
        if best[fid] ~= nil then
            rows[#rows + 1] = MakeSummaryRow(fid, best[fid], infos, counts)
        end
    end
    return rows
end

-- 탐험 항목 모으기(지역 원소 + 최고 캐릭터 키), dik, 2026-10-01
local function BuildExploreItems(charKey)
    local items = {}
    local currentKey = ns.GetCurrentCharacterKey()
    if charKey ~= "all" then
        local area = GetReadArea(charKey, currentKey)
        local zones = GetZoneList(area)
        for i = 1, #zones do
            local z = zones[i]
            items[#items + 1] = { id = z.id, name = z.name, done = z.done, total = z.total, bestKey = charKey }
        end
        return items
    end
    local keys = ns.GetCharacterKeys()
    local byId = {}
    for i = 1, #keys do
        local area = GetReadArea(keys[i], currentKey)
        local zones = GetZoneList(area)
        for j = 1, #zones do
            local z = zones[j]
            local cur = byId[z.id]
            if cur == nil then
                cur = { id = z.id, name = z.name, done = z.done, total = z.total, bestKey = keys[i] }
                byId[z.id] = cur
                items[#items + 1] = cur
            elseif z.done > cur.done then
                cur.name = z.name
                cur.done = z.done
                cur.total = z.total
                cur.bestKey = keys[i]
            end
        end
    end
    return items
end

-- 탐험 표 행, dik, 2026-10-01
function ns.Progress.GetExploreRows(charKey)
    local rows = {}
    local items = BuildExploreItems(charKey)
    local infos, counts
    if charKey == "all" then
        infos, counts = BuildNames(ns.GetCharacterKeys())
    end
    for i = 1, #items do
        local z = items[i]
        local ratio = 1
        if z.total > 0 then
            ratio = z.done / z.total
        end
        local row = {
            id = tostring(z.id),
            name = z.name,
            done = z.done,
            total = z.total,
            left = z.total - z.done,
            ratio = ratio,
        }
        if charKey == "all" then
            row.bestKey = z.bestKey
            row.bestName = DisplayName(z.bestKey, infos, counts)
            row.bestClassFile = ClassFileOf(z.bestKey, infos)
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- 탐험 요약, dik, 2026-10-01
function ns.Progress.GetExploreSummary(charKey)
    return ns.Progress.SummarizeZones(BuildExploreItems(charKey))
end

-- 드롭다운 항목(전체 + 캐릭터), dik, 2026-10-01
function ns.Progress.GetCharacterItems()
    local keys = ns.GetCharacterKeys()
    local infos, counts = BuildNames(keys)
    local items = { { value = "all", text = L.PROGRESS_ALL_CHARS } }
    for i = 1, #keys do
        items[#items + 1] = { value = keys[i], text = DisplayName(keys[i], infos, counts) }
    end
    return items
end

-- 수집 예약 요청(페이지 열 때), dik, 2026-10-01
function ns.Progress.RequestScan()
    if not state.ready then
        return
    end
    Schedule("rep", false)
    Schedule("pvp", false)
    Schedule("explore", false)
end

-- 배열 복사, dik, 2026-10-01
local function CopyArray(source)
    local copy = {}
    for i = 1, #source do
        copy[i] = source[i]
    end
    return copy
end

-- 상태 조회(섹션 상태·없는 API 복사본), dik, 2026-10-01
function ns.Progress.GetStatus()
    return {
        ready = state.ready,
        readOnly = state.readOnly,
        sections = {
            rep = state.sections.rep,
            pvp = state.sections.pvp,
            explore = state.sections.explore,
        },
        missing = {
            rep = CopyArray(state.missing.rep),
            pvp = CopyArray(state.missing.pvp),
            explore = CopyArray(state.missing.explore),
        },
    }
end
