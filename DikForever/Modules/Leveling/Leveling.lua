-- 레벨링 페이스 모듈 등록·경험치 추적·세션 계산, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "leveling"
local AREA_VERSION = 1
local HISTORY_MAX = 20
local KILL_AVG_COUNT = 10
local KILL_GRACE_SECONDS = 3
local MIN_RATE_SECONDS = 60
local RESUME_GAP_SECONDS = 300
local SAMPLE_KEEP_SECONDS = 1800
local SAMPLE_MAX = 500
local DEFAULT_RECENT_MINUTES = 10

local EVENT_ORDER = {
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_LOGOUT",
}

local SESSION_NUMBER_FIELDS = {
    "startedAt", "lastActiveAt", "duration", "xp", "kills", "killXp", "quests", "questXp", "levelsGained",
}
local HISTORY_NUMBER_FIELDS = {
    "startedAt", "endedAt", "duration", "xp", "kills", "killXp", "quests", "questXp", "levelsGained",
}

local state = {
    ready = false,
    readOnly = false,
    secret = false,
    needRebase = false,
    pendingLevel = nil,
    area = nil,
    baseline = nil,
    segmentStartedAt = 0,
    samples = {},
    lastRegenEnabled = nil,
    killsSupported = false,
    questsSupported = false,
    regenEndSupported = false,
    frame = nil,
}

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 비-secret 유한 number 판정, dik, 2026-09-30
local function IsPlainNumber(v)
    return not ns.IsSecret(v) and IsNumber(v)
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

-- 최근 구간 설정값(분), dik, 2026-09-30
local function GetRecentMinutes()
    local v = ns.GetSetting(MODULE_ID, "recentMinutes")
    if IsNumber(v) and v > 0 then
        return v
    end
    return DEFAULT_RECENT_MINUTES
end

-- 델타 계산(순수 함수), dik, 2026-09-30
local function ComputeDelta(prev, cur)
    local remain = math.max(0, prev.xpMax - prev.xp)
    if cur.level > prev.level then
        return remain + cur.xp, cur.level - prev.level, cur.level
    end
    if cur.level == prev.level then
        if cur.xp >= prev.xp then
            return cur.xp - prev.xp, 0, cur.level
        end
        return remain + cur.xp, 1, prev.level + 1
    end
    return math.max(0, cur.xp - prev.xp), 0, prev.level
end

-- 시간당 경험치(순수 함수), dik, 2026-09-30
local function ComputeRate(xp, seconds)
    if IsNumber(seconds) and seconds >= MIN_RATE_SECONDS and IsNumber(xp) then
        return math.floor(xp * 3600 / seconds)
    end
    return nil
end

-- 레벨업 예상 초(순수 함수), dik, 2026-09-30
local function ComputeEta(remaining, rate)
    if IsNumber(remaining) and IsNumber(rate) and remaining > 0 and rate > 0 then
        return math.ceil(remaining * 3600 / rate)
    end
    return nil
end

-- 레벨업까지 처치 수(순수 함수), dik, 2026-09-30
local function ComputeKillsToLevel(remaining, avg)
    if IsNumber(remaining) and IsNumber(avg) and remaining > 0 and avg > 0 then
        return math.ceil(remaining / avg)
    end
    return nil
end

-- 레벨·경험치 읽기(secret·비정상이면 nil), dik, 2026-09-30
local function ReadValues()
    local level = UnitLevel("player")
    local xp = UnitXP("player")
    local xpMax = UnitXPMax("player")
    if ns.IsSecret(level) or ns.IsSecret(xp) or ns.IsSecret(xpMax) then
        return nil, nil, nil, nil, true
    end
    if not IsNumber(level) or not IsNumber(xp) or not IsNumber(xpMax) then
        return nil, nil, nil, nil, false
    end
    local rest = nil
    if ns.HasAPI("GetXPExhaustion") then
        rest = GetXPExhaustion()
        if ns.IsSecret(rest) then
            rest = nil
        elseif not IsNumber(rest) then
            rest = 0
        end
    end
    return level, xp, xpMax, rest, false
end

-- 새 세션 테이블, dik, 2026-09-30
local function NewSession(now, level)
    return {
        startedAt = now, lastActiveAt = now, duration = 0, xp = 0,
        kills = 0, killXp = 0, quests = 0, questXp = 0,
        startLevel = level, endLevel = level, levelsGained = 0, recentKills = {},
    }
end

-- 세션을 기록 맨 앞에 보관(경험치 0 이면 버림), dik, 2026-09-30
local function ArchiveSession(session, endedAt, duration)
    if type(session) ~= "table" or not IsNumber(session.xp) or session.xp <= 0 then
        return
    end
    local record = {
        startedAt = session.startedAt, endedAt = endedAt, duration = duration, xp = session.xp,
        kills = session.kills, killXp = session.killXp, quests = session.quests, questXp = session.questXp,
        startLevel = session.startLevel, endLevel = session.endLevel, levelsGained = session.levelsGained,
    }
    local history = state.area.history
    table.insert(history, 1, record)
    while #history > HISTORY_MAX do
        table.remove(history)
    end
end

-- 진행 구간 포함 세션 시간, dik, 2026-09-30
local function GetElapsed(now)
    local current = state.area.current
    return current.duration + math.max(0, now - state.segmentStartedAt)
end

-- 저장 영역 검증(손상 값 보정), dik, 2026-09-30
local function ValidateStore(store)
    if not IsNumber(store.version) or store.version < 1 then
        store.version = AREA_VERSION
    end
    local history = {}
    if type(store.history) == "table" then
        for i = 1, #store.history do
            local item = store.history[i]
            if type(item) == "table" then
                for j = 1, #HISTORY_NUMBER_FIELDS do
                    local f = HISTORY_NUMBER_FIELDS[j]
                    if not IsNumber(item[f]) then
                        item[f] = 0
                    end
                end
                if not IsNumber(item.startLevel) then
                    item.startLevel = nil
                end
                if not IsNumber(item.endLevel) then
                    item.endLevel = nil
                end
                history[#history + 1] = item
            end
        end
    end
    store.history = history
    local current = store.current
    if type(current) ~= "table" then
        store.current = nil
        return
    end
    for j = 1, #SESSION_NUMBER_FIELDS do
        local f = SESSION_NUMBER_FIELDS[j]
        if not IsNumber(current[f]) then
            current[f] = 0
        end
    end
    if not IsNumber(current.startLevel) then
        current.startLevel = nil
    end
    if not IsNumber(current.endLevel) then
        current.endLevel = nil
    end
    local kills = {}
    if type(current.recentKills) == "table" then
        for i = 1, #current.recentKills do
            if IsNumber(current.recentKills[i]) then
                kills[#kills + 1] = current.recentKills[i]
            end
        end
    end
    current.recentKills = kills
end

-- 준비 판정·세션 재개/시작(READY·CHAR_UPDATED), dik, 2026-09-30
local function Prepare()
    if state.ready or ns.GetCurrentCharacterKey() == nil then
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
        area = { version = AREA_VERSION, history = {} }
    end
    -- 세션 시작 시 대기 레벨 초기화, dik, 2026-09-30
    state.pendingLevel = nil
    state.area = area
    state.readOnly = readOnly
    local level, xp, xpMax, _, secret = ReadValues()
    local current = area.current
    if current ~= nil and now - current.lastActiveAt > RESUME_GAP_SECONDS then
        ArchiveSession(current, current.lastActiveAt, current.duration)
        current = nil
    end
    if current == nil then
        current = NewSession(now, level)
        area.current = current
    end
    state.segmentStartedAt = now
    state.samples = {}
    state.secret = secret
    state.baseline = nil
    state.needRebase = secret
    if level ~= nil then
        state.baseline = { level = level, xp = xp, xpMax = xpMax }
    end
    state.ready = true
    ns.Fire("LEVELING_UPDATED")
end

-- 전투 판정(전투 중 또는 종료 유예 이내), dik, 2026-09-30
local function IsKillContext()
    if not state.killsSupported then
        return false
    end
    if InCombatLockdown() == true then
        return true
    end
    if state.regenEndSupported and state.lastRegenEnabled ~= nil and ns.HasAPI("GetTime") then
        return GetTime() - state.lastRegenEnabled <= KILL_GRACE_SECONDS
    end
    return false
end

-- 델타를 세션에 누적, dik, 2026-09-30
local function Accumulate(delta, levelsGained, baseLevel, now)
    local current = state.area.current
    current.xp = current.xp + delta
    current.levelsGained = current.levelsGained + levelsGained
    current.endLevel = baseLevel
    current.lastActiveAt = now
    local samples = state.samples
    samples[#samples + 1] = { t = now, xp = delta }
    while #samples > 0 and (samples[1].t <= now - SAMPLE_KEEP_SECONDS or #samples > SAMPLE_MAX) do
        table.remove(samples, 1)
    end
    if IsKillContext() then
        current.kills = current.kills + 1
        current.killXp = current.killXp + delta
        local kills = current.recentKills
        kills[#kills + 1] = delta
        if #kills > KILL_AVG_COUNT then
            table.remove(kills, 1)
        end
    end
end

-- 경험치 변화 처리(기준값 갱신·델타 누적), dik, 2026-09-30
-- 레벨업 레벨은 pendingLevel 로 다음 회차에 반영, dik, 2026-09-30
local function Refresh()
    if not state.ready then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local level, xp, xpMax, _, secret = ReadValues()
    if secret then
        local changed = not state.secret
        state.secret = true
        state.needRebase = true
        if changed then
            ns.Fire("LEVELING_UPDATED")
        end
        return
    end
    if level == nil then
        return
    end
    local wasSecret = state.secret
    state.secret = false
    if state.pendingLevel ~= nil then
        level = math.max(level, state.pendingLevel)
        state.pendingLevel = nil
    end
    local cur = { level = level, xp = xp, xpMax = xpMax }
    if xpMax <= 0 then
        state.baseline = cur
        state.needRebase = false
        if wasSecret then
            ns.Fire("LEVELING_UPDATED")
        end
        return
    end
    if state.baseline == nil or state.needRebase then
        state.baseline = cur
        state.needRebase = false
        ns.Fire("LEVELING_UPDATED")
        return
    end
    local prev = state.baseline
    local delta, levelsGained, baseLevel = ComputeDelta(prev, cur)
    state.baseline = { level = baseLevel, xp = xp, xpMax = xpMax }
    if delta > 0 then
        Accumulate(delta, levelsGained, baseLevel, now)
    end
    if delta > 0 or wasSecret or baseLevel ~= prev.level or xp ~= prev.xp or xpMax ~= prev.xpMax then
        ns.Fire("LEVELING_UPDATED")
    end
end

-- 퀘스트 반납 처리, dik, 2026-09-30
local function OnQuestTurnedIn(xpReward)
    if not state.ready then
        return
    end
    local current = state.area.current
    current.quests = current.quests + 1
    if IsPlainNumber(xpReward) and xpReward > 0 then
        current.questXp = current.questXp + xpReward
    end
    ns.Fire("LEVELING_UPDATED")
end

-- 로그아웃 시 세션 시간 확정, dik, 2026-09-30
local function OnLogout()
    if not state.ready then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local current = state.area.current
    current.duration = GetElapsed(now)
    current.lastActiveAt = now
    state.segmentStartedAt = now
end

-- 이벤트 분배, dik, 2026-09-30
local function OnEvent(_, event, arg1, arg2)
    if event == "PLAYER_XP_UPDATE" then
        if type(arg1) == "string" and not ns.IsSecret(arg1) and arg1 ~= "player" then
            return
        end
        Refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        -- 레벨업 인자만 기억, dik, 2026-09-30
        if IsPlainNumber(arg1) then
            state.pendingLevel = arg1
        end
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(arg2)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.HasAPI("GetTime") then
            state.lastRegenEnabled = GetTime()
        end
    elseif event == "PLAYER_LOGOUT" then
        OnLogout()
    end
end

-- 이벤트 프레임 생성·등록·실패 안내, dik, 2026-09-30
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    local missing = {}
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        local registered = pcall(frame.RegisterEvent, frame, name)
        if registered then
            if name == "QUEST_TURNED_IN" then
                state.questsSupported = true
            elseif name == "PLAYER_REGEN_ENABLED" then
                state.regenEndSupported = true
            end
        else
            missing[#missing + 1] = name
        end
    end
    state.killsSupported = ns.HasAPI("InCombatLockdown")
    if not state.killsSupported then
        missing[#missing + 1] = "InCombatLockdown"
    end
    if #missing > 0 then
        ns.Print(L.MSG_LEVELING_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
    ns.On("READY", Prepare)
    ns.On("CHAR_UPDATED", Prepare)
end

-- 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_LEVELING,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_LEVELING_DESC,
    category = "feature",
    order = 20,
    requires = { "UnitXP", "UnitXPMax", "UnitLevel" },
    settings = {
        { key = "recentMinutes", type = "slider", label = L.SETTING_LEVELING_RECENT,
          tooltip = L.SETTING_LEVELING_RECENT_TIP, min = 5, max = 30, step = 5, default = 10 },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
    OnSettingChanged = function(_, key)
        if key == "recentMinutes" then
            ns.Fire("LEVELING_UPDATED")
        end
    end,
})

ns.Leveling = {}
ns.Leveling.ComputeDelta = ComputeDelta
ns.Leveling.ComputeRate = ComputeRate
ns.Leveling.ComputeEta = ComputeEta
ns.Leveling.ComputeKillsToLevel = ComputeKillsToLevel

-- 원시 경험치 값 그대로 반환(바 전달 전용), dik, 2026-09-30
function ns.Leveling.GetRawXp()
    local rest = nil
    if ns.HasAPI("GetXPExhaustion") then
        rest = GetXPExhaustion()
    end
    return UnitXP("player"), UnitXPMax("player"), rest
end

-- 세션 스냅샷(매 호출 새 테이블), dik, 2026-09-30
function ns.Leveling.GetSnapshot(now)
    local snap = {
        ready = state.ready,
        secret = state.secret,
        maxLevel = false,
        killsSupported = state.killsSupported,
        questsSupported = state.questsSupported,
        recentMinutes = GetRecentMinutes(),
        readOnly = state.readOnly,
    }
    if not state.ready then
        return snap
    end
    if not IsNumber(now) then
        now = GetNow()
    end
    if now == nil then
        snap.ready = false
        return snap
    end
    local level, xp, xpMax, rest, secret = ReadValues()
    snap.secret = secret
    local valid = level ~= nil
    if valid then
        snap.level, snap.xp, snap.xpMax, snap.restXp = level, xp, xpMax, rest
        if xpMax <= 0 then
            snap.maxLevel = true
            valid = false
        else
            snap.xpRatio = xp / xpMax
            snap.remaining = xpMax - xp
        end
    end
    local current = state.area.current
    local elapsed = GetElapsed(now)
    snap.elapsed = elapsed
    snap.sessionXp = current.xp
    snap.startedAt = current.startedAt
    snap.levelsGained = current.levelsGained
    snap.quests = current.quests
    snap.questXp = current.questXp
    snap.sessionRate = ComputeRate(current.xp, elapsed)
    local window = snap.recentMinutes * 60
    local span = math.min(window, now - state.segmentStartedAt)
    local recentXp = 0
    for i = 1, #state.samples do
        local sample = state.samples[i]
        if sample.t > now - window then
            recentXp = recentXp + sample.xp
        end
    end
    snap.recentRate = ComputeRate(recentXp, span)
    snap.kills = current.kills
    snap.killXp = current.killXp
    local count = #current.recentKills
    if count >= 1 then
        local sum = 0
        for i = 1, count do
            sum = sum + current.recentKills[i]
        end
        snap.avgKillXp = math.floor(sum / count)
    end
    if valid then
        local rate = snap.sessionRate
        if snap.recentRate ~= nil and snap.recentRate > 0 then
            rate = snap.recentRate
        end
        snap.etaSeconds = ComputeEta(snap.remaining, rate)
        if state.killsSupported then
            snap.killsToLevel = ComputeKillsToLevel(snap.remaining, snap.avgKillXp)
        end
    end
    return snap
end

-- 세션 기록 복사본(최신 1번), dik, 2026-09-30
function ns.Leveling.GetHistory()
    local list = {}
    if not state.ready then
        return list
    end
    local history = state.area.history
    for i = 1, #history do
        local copy = {}
        for k, v in pairs(history[i]) do
            copy[k] = v
        end
        list[i] = copy
    end
    return list
end

-- 세션 초기화(보관 후 새 세션), dik, 2026-09-30
function ns.Leveling.ResetSession()
    if not state.ready then
        return false
    end
    local now = GetNow()
    if now == nil then
        return false
    end
    local current = state.area.current
    ArchiveSession(current, now, GetElapsed(now))
    local level = nil
    if state.baseline ~= nil then
        level = state.baseline.level
    end
    state.area.current = NewSession(now, level)
    state.segmentStartedAt = now
    state.samples = {}
    ns.Print(L.MSG_LEVELING_RESET)
    ns.Fire("LEVELING_UPDATED")
    return true
end
