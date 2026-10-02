-- 골드 장부 모듈 등록·수집·분류·집계, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "gold"
local AREA_VERSION = 1
local RETENTION_DAYS = 90
local CONTEXT_GRACE_SECONDS = 2
local RESUME_GAP_SECONDS = 300
local MIN_RATE_SECONDS = 60
local DAY_SECONDS = 86400
local DAY_KEY_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"

local CATEGORIES = { "merchant", "repair", "mail", "quest", "loot", "auction", "trade", "other" }
local PERIODS = { "session", "today", "yesterday", "d7", "d30", "d90" }
local VIEWS = { "source", "character" }
local PERIOD_DAYS = { d7 = 7, d30 = 30, d90 = 90 }

local EVENT_ORDER = {
    "PLAYER_MONEY",
    "PLAYER_LOGOUT",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "TRADE_SHOW",
    "TRADE_CLOSED",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "CHAT_MSG_MONEY",
    "QUEST_COMPLETE",
    "QUEST_FINISHED",
    "QUEST_TURNED_IN",
}

local OPEN_EVENTS = {
    MERCHANT_SHOW = "merchant",
    MAIL_SHOW = "mail",
    AUCTION_HOUSE_SHOW = "auction",
    TRADE_SHOW = "trade",
    LOOT_OPENED = "loot",
    QUEST_COMPLETE = "quest",
}
local CLOSE_EVENTS = {
    MERCHANT_CLOSED = "merchant",
    MAIL_CLOSED = "mail",
    AUCTION_HOUSE_CLOSED = "auction",
    TRADE_CLOSED = "trade",
    LOOT_CLOSED = "loot",
    QUEST_FINISHED = "quest",
}
local POINT_EVENTS = {
    CHAT_MSG_MONEY = "loot",
    QUEST_TURNED_IN = "quest",
}

local state = {
    ready = false,
    readOnly = false,
    secret = false,
    characterKey = nil,
    area = nil,
    lastMoney = nil,
    segmentStartedAt = 0,
    ctx = { windows = {}, repairAt = nil },
    missing = {},
    frame = nil,
}

ns.Gold = {}
ns.Gold.CATEGORIES = CATEGORIES
ns.Gold.PERIODS = PERIODS

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 유한한 양수 판정, dik, 2026-09-30
local function IsPositive(v)
    return IsNumber(v) and v > 0
end

-- 목록 포함 판정, dik, 2026-09-30
local function Contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
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

-- 델타 계산(순수 함수), dik, 2026-09-30
function ns.Gold.ComputeDelta(prev, cur)
    if IsNumber(prev) and IsNumber(cur) then
        return cur - prev
    end
    return nil
end

-- 출처 분류(순수 함수), dik, 2026-09-30
function ns.Gold.Classify(ctx, delta, now)
    if type(ctx) ~= "table" then
        return "other"
    end
    local hasNow = IsNumber(now)
    if IsNumber(delta) and delta < 0 and hasNow and IsNumber(ctx.repairAt) then
        local age = now - ctx.repairAt
        if age >= 0 and age <= CONTEXT_GRACE_SECONDS then
            return "repair"
        end
    end
    local windows = ctx.windows
    if type(windows) ~= "table" then
        return "other"
    end
    local best = nil
    local bestAt = nil
    for i = 1, #CATEGORIES do
        local category = CATEGORIES[i]
        local w = windows[category]
        if type(w) == "table" and IsNumber(w.openedAt) then
            local active = w.open == true
                or (hasNow and IsNumber(w.closedAt) and now - w.closedAt <= CONTEXT_GRACE_SECONDS)
            if active and (bestAt == nil or w.openedAt > bestAt) then
                best = category
                bestAt = w.openedAt
            end
        end
    end
    return best or "other"
end

-- 버킷에 금액 누적(순수 함수), dik, 2026-09-30
function ns.Gold.AddAmount(bucket, category, delta)
    if type(bucket) ~= "table" or type(category) ~= "string" or not IsNumber(delta) or delta == 0 then
        return
    end
    if type(bucket.inc) ~= "table" then
        bucket.inc = {}
    end
    if type(bucket.exp) ~= "table" then
        bucket.exp = {}
    end
    if delta > 0 then
        bucket.inc[category] = (bucket.inc[category] or 0) + delta
    else
        bucket.exp[category] = (bucket.exp[category] or 0) - delta
    end
end

-- 날짜 키(로컬 날짜), dik, 2026-09-30
function ns.Gold.DayKey(ts)
    if IsNumber(ts) and ns.HasAPI("date") then
        return date("%Y-%m-%d", ts)
    end
    return nil
end

-- 기간 첫날 키, dik, 2026-09-30
function ns.Gold.CutoffKey(now, days)
    if not IsNumber(now) or not IsNumber(days) then
        return nil
    end
    return ns.Gold.DayKey(now - (days - 1) * DAY_SECONDS)
end

-- 오래된 날짜 키 삭제, dik, 2026-09-30
function ns.Gold.PruneDays(daysTable, cutoffKey)
    if type(daysTable) ~= "table" or type(cutoffKey) ~= "string" then
        return 0
    end
    local stale = {}
    for key in pairs(daysTable) do
        if type(key) == "string" and key < cutoffKey then
            stale[#stale + 1] = key
        end
    end
    for i = 1, #stale do
        daysTable[stale[i]] = nil
    end
    return #stale
end

-- 기간의 날짜 범위, dik, 2026-09-30
function ns.Gold.PeriodRange(period, now)
    if not IsNumber(now) then
        now = GetNow()
    end
    if now == nil then
        return nil, nil
    end
    if period == "today" then
        local key = ns.Gold.DayKey(now)
        return key, key
    elseif period == "yesterday" then
        local key = ns.Gold.DayKey(now - DAY_SECONDS)
        return key, key
    elseif PERIOD_DAYS[period] ~= nil then
        return ns.Gold.CutoffKey(now, PERIOD_DAYS[period]), ns.Gold.DayKey(now)
    end
    return nil, nil
end

-- 시간당 골드(0 쪽으로 버림), dik, 2026-09-30
function ns.Gold.ComputeRate(net, seconds)
    if IsNumber(seconds) and seconds >= MIN_RATE_SECONDS and IsNumber(net) then
        local v = net * 3600 / seconds
        if v >= 0 then
            return math.floor(v)
        end
        return 0 - math.floor(-v)
    end
    return nil
end

-- 출처별 합 테이블 정리(잘못된 항목 삭제), dik, 2026-09-30
local function CleanCategoryTable(t)
    if type(t) ~= "table" then
        return {}
    end
    for key, value in pairs(t) do
        if type(key) ~= "string" or not Contains(CATEGORIES, key) or not IsPositive(value) then
            t[key] = nil
        end
    end
    return t
end

-- 날짜 버킷 정리, dik, 2026-09-30
local function CleanBucket(bucket)
    bucket.inc = CleanCategoryTable(bucket.inc)
    bucket.exp = CleanCategoryTable(bucket.exp)
end

-- 저장 영역 검증(손상 값 보정), dik, 2026-09-30
local function ValidateStore(store)
    if not IsNumber(store.version) or store.version < 1 then
        store.version = AREA_VERSION
    end
    if type(store.days) ~= "table" then
        store.days = {}
    end
    for key, bucket in pairs(store.days) do
        if type(key) ~= "string" or not key:match(DAY_KEY_PATTERN) or type(bucket) ~= "table" then
            store.days[key] = nil
        else
            CleanBucket(bucket)
        end
    end
    local session = store.session
    if type(session) ~= "table" then
        store.session = nil
        return
    end
    if not IsNumber(session.startedAt) then
        session.startedAt = 0
    end
    if not IsNumber(session.lastActiveAt) then
        session.lastActiveAt = 0
    end
    if not IsNumber(session.duration) then
        session.duration = 0
    end
    CleanBucket(session)
end

-- 새 세션 테이블, dik, 2026-09-30
local function NewSession(now)
    return { startedAt = now, lastActiveAt = now, duration = 0, inc = {}, exp = {} }
end

-- 진행 구간 포함 세션 시간, dik, 2026-09-30
local function GetElapsed(session, now)
    return session.duration + math.max(0, now - state.segmentStartedAt)
end

-- 보존 기간 밖 날짜 정리(삭제 수 반환), dik, 2026-09-30
local function PruneOld(now)
    local cutoff = ns.Gold.CutoffKey(now, RETENTION_DAYS)
    return ns.Gold.PruneDays(state.area.days, cutoff)
end

-- 준비 판정·세션 재개/시작(READY·CHAR_UPDATED), dik, 2026-09-30
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
        area = { version = AREA_VERSION, days = {} }
    end
    state.area = area
    state.readOnly = readOnly
    state.characterKey = key
    PruneOld(now)
    local session = area.session
    if session == nil or now - session.lastActiveAt > RESUME_GAP_SECONDS then
        session = NewSession(now)
        area.session = session
    end
    state.segmentStartedAt = now
    state.lastMoney = nil
    state.secret = false
    if ns.HasAPI("GetMoney") then
        local cur = GetMoney()
        if ns.IsSecret(cur) then
            state.secret = true
        elseif IsNumber(cur) then
            state.lastMoney = cur
        end
    end
    state.ready = true
    ns.Fire("GOLD_UPDATED")
end

-- 돈 변동 처리(분류·세션·일별 장부 누적), dik, 2026-09-30
local function OnMoney()
    if not state.ready then
        return
    end
    local now = GetNow()
    if now == nil then
        return
    end
    local cur = GetMoney()
    if ns.IsSecret(cur) then
        local changed = not state.secret
        state.secret = true
        if changed then
            ns.Fire("GOLD_UPDATED")
        end
        return
    end
    if not IsNumber(cur) then
        return
    end
    local wasSecret = state.secret
    state.secret = false
    if wasSecret or state.lastMoney == nil then
        state.lastMoney = cur
        if wasSecret then
            ns.Fire("GOLD_UPDATED")
        end
        return
    end
    local delta = ns.Gold.ComputeDelta(state.lastMoney, cur)
    state.lastMoney = cur
    if delta == nil or delta == 0 then
        return
    end
    local ctx = state.ctx
    local category = ns.Gold.Classify(ctx, delta, GetClock())
    if category == "repair" then
        ctx.repairAt = nil
    end
    local session = state.area.session
    ns.Gold.AddAmount(session, category, delta)
    session.lastActiveAt = now
    local dayKey = ns.Gold.DayKey(now)
    if dayKey ~= nil then
        local days = state.area.days
        local bucket = days[dayKey]
        local created = false
        if bucket == nil then
            bucket = { inc = {}, exp = {} }
            days[dayKey] = bucket
            created = true
        end
        ns.Gold.AddAmount(bucket, category, delta)
        if created then
            PruneOld(now)
        end
    end
    ns.Fire("GOLD_UPDATED")
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
    local session = state.area.session
    session.duration = GetElapsed(session, now)
    session.lastActiveAt = now
    state.segmentStartedAt = now
end

-- 창 문맥 갱신, dik, 2026-09-30
local function UpdateContext(event)
    local t = GetClock() or 0
    local windows = state.ctx.windows
    local category = OPEN_EVENTS[event]
    if category ~= nil then
        windows[category] = { open = true, openedAt = t }
        return
    end
    category = CLOSE_EVENTS[event]
    if category ~= nil then
        local w = windows[category]
        if w == nil then
            windows[category] = { open = false, openedAt = t, closedAt = t }
        else
            w.open = false
            w.closedAt = t
        end
        return
    end
    category = POINT_EVENTS[event]
    if category ~= nil then
        windows[category] = { open = false, openedAt = t, closedAt = t }
    end
end

-- 이벤트 분배, dik, 2026-09-30
local function OnEvent(_, event)
    if event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "PLAYER_LOGOUT" then
        OnLogout()
    else
        UpdateContext(event)
    end
end

-- 이벤트 프레임 생성·등록·훅·실패 안내, dik, 2026-09-30
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
    local hasRepair = ns.HasAPI("RepairAllItems")
    local hasHook = ns.HasAPI("hooksecurefunc")
    if hasRepair and hasHook then
        hooksecurefunc("RepairAllItems", function(guildBankRepair)
            if guildBankRepair ~= true then
                state.ctx.repairAt = GetClock()
            end
        end)
    else
        if not hasRepair then
            missing[#missing + 1] = "RepairAllItems"
        end
        if not hasHook then
            missing[#missing + 1] = "hooksecurefunc"
        end
    end
    state.missing = missing
    if #missing > 0 then
        ns.Print(L.MSG_GOLD_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
    ns.On("READY", Prepare)
    ns.On("CHAR_UPDATED", Prepare)
end

-- 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_GOLD,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_GOLD_DESC,
    category = "feature",
    order = 40,
    requires = { "GetMoney", "time", "date" },
    OnInitialize = function()
        InitializeTracking()
    end,
})

-- 출처 8개 키 0 초기화 테이블, dik, 2026-09-30
local function NewCategoryTable()
    local t = {}
    for i = 1, #CATEGORIES do
        t[CATEGORIES[i]] = 0
    end
    return t
end

-- 버킷 값을 결과에 더함(유효한 양수만), dik, 2026-09-30
local function AddBucket(result, bucket)
    if type(bucket) ~= "table" then
        return
    end
    for _, field in ipairs({ "inc", "exp" }) do
        local source = bucket[field]
        if type(source) == "table" then
            for i = 1, #CATEGORIES do
                local category = CATEGORIES[i]
                if IsPositive(source[category]) then
                    result[field][category] = result[field][category] + source[category]
                end
            end
        end
    end
end

-- 캐릭터 저장 영역 조회(읽기만, 못 쓰면 nil), dik, 2026-09-30
local function GetAreaFor(key)
    if key == ns.GetCurrentCharacterKey() then
        if state.ready and state.characterKey == key then
            return state.area
        end
        return nil
    end
    local data = ns.GetCharacterData(MODULE_ID, key)
    if type(data) ~= "table" then
        return nil
    end
    if IsNumber(data.version) and data.version > AREA_VERSION then
        return nil
    end
    return data
end

-- 집계(매 호출 새 테이블), dik, 2026-09-30
function ns.Gold.Aggregate(period, charFilter, now)
    if not IsNumber(now) then
        now = GetNow()
    end
    local result = { inc = NewCategoryTable(), exp = NewCategoryTable(), incTotal = 0, expTotal = 0, net = 0 }
    local keys = {}
    if period == "session" then
        local currentKey = ns.GetCurrentCharacterKey()
        if currentKey ~= nil then
            keys[1] = currentKey
        end
    elseif charFilter == "all" then
        keys = ns.GetCharacterKeys()
    elseif type(charFilter) == "string" then
        keys[1] = charFilter
    end
    local fromKey, toKey = ns.Gold.PeriodRange(period, now)
    for i = 1, #keys do
        local area = GetAreaFor(keys[i])
        if area ~= nil then
            if period == "session" then
                AddBucket(result, area.session)
            elseif fromKey ~= nil and toKey ~= nil and type(area.days) == "table" then
                for dayKey, bucket in pairs(area.days) do
                    if type(dayKey) == "string" and fromKey <= dayKey and dayKey <= toKey then
                        AddBucket(result, bucket)
                    end
                end
            end
        end
    end
    for i = 1, #CATEGORIES do
        result.incTotal = result.incTotal + result.inc[CATEGORIES[i]]
        result.expTotal = result.expTotal + result.exp[CATEGORIES[i]]
    end
    result.net = result.incTotal - result.expTotal
    return result
end

-- 캐릭터별 집계(매 호출 새 배열), dik, 2026-09-30
function ns.Gold.AggregateByCharacter(period, charFilter, now)
    local keys = {}
    if period == "session" then
        local currentKey = ns.GetCurrentCharacterKey()
        if currentKey ~= nil then
            keys[1] = currentKey
        end
    elseif charFilter == "all" then
        keys = ns.GetCharacterKeys()
    elseif type(charFilter) == "string" then
        keys[1] = charFilter
    end
    local rows = {}
    local nameCount = {}
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        local name = nil
        local classFile = nil
        local money = nil
        if type(info) == "table" then
            if type(info.name) == "string" and info.name ~= "" then
                name = info.name
            end
            if type(info.classFile) == "string" then
                classFile = info.classFile
            end
            if IsNumber(info.money) then
                money = info.money
            end
        end
        if name ~= nil then
            nameCount[name] = (nameCount[name] or 0) + 1
        end
        local agg = ns.Gold.Aggregate(period, keys[i], now)
        rows[i] = {
            key = keys[i], name = name, classFile = classFile, money = money,
            incTotal = agg.incTotal, expTotal = agg.expTotal, net = agg.net,
        }
    end
    for i = 1, #rows do
        local row = rows[i]
        if row.name == nil or nameCount[row.name] > 1 then
            row.name = row.key
        end
    end
    return rows
end

-- 전 캐릭터 소지금 합, dik, 2026-09-30
function ns.Gold.GetTotalMoney()
    local keys = ns.GetCharacterKeys()
    local total = 0
    local moneyCount = 0
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        if type(info) == "table" and IsNumber(info.money) then
            total = total + info.money
            moneyCount = moneyCount + 1
        end
    end
    if moneyCount == 0 then
        return nil, #keys, 0
    end
    return total, #keys, moneyCount
end

-- 세션 스냅샷(매 호출 새 테이블), dik, 2026-09-30
function ns.Gold.GetSession(now)
    local snap = { ready = state.ready, secret = state.secret, readOnly = state.readOnly }
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
    local session = state.area.session
    local result = { inc = NewCategoryTable(), exp = NewCategoryTable() }
    AddBucket(result, session)
    local incTotal = 0
    local expTotal = 0
    for i = 1, #CATEGORIES do
        incTotal = incTotal + result.inc[CATEGORIES[i]]
        expTotal = expTotal + result.exp[CATEGORIES[i]]
    end
    local elapsed = GetElapsed(session, now)
    snap.characterKey = state.characterKey
    snap.startedAt = session.startedAt
    snap.elapsed = elapsed
    snap.inc = result.inc
    snap.exp = result.exp
    snap.incTotal = incTotal
    snap.expTotal = expTotal
    snap.net = incTotal - expTotal
    snap.rate = ns.Gold.ComputeRate(snap.net, elapsed)
    return snap
end

-- 세션 초기화(새 세션 시작), dik, 2026-09-30
function ns.Gold.ResetSession()
    if not state.ready then
        return false
    end
    local now = GetNow()
    if now == nil then
        return false
    end
    state.area.session = NewSession(now)
    state.segmentStartedAt = now
    ns.Print(L.MSG_GOLD_RESET)
    ns.Fire("GOLD_UPDATED")
    return true
end

-- 보기 상태 저장 영역 조회(새 스키마면 읽기만), dik, 2026-09-30
local function GetViewArea()
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
    return ns.GetModuleData(MODULE_ID)
end

-- 캐릭터 필터 유효 판정, dik, 2026-09-30
local function IsValidCharFilter(charFilter)
    return charFilter == "all" or (type(charFilter) == "string" and Contains(ns.GetCharacterKeys(), charFilter))
end

-- 보기 상태 조회(검증 후), dik, 2026-09-30
function ns.Gold.GetViewState()
    local area = GetViewArea()
    local period = "today"
    local charFilter = "all"
    local view = "source"
    if area ~= nil then
        if Contains(PERIODS, area.period) then
            period = area.period
        end
        if IsValidCharFilter(area.charFilter) then
            charFilter = area.charFilter
        end
        if Contains(VIEWS, area.view) then
            view = area.view
        end
    end
    return period, charFilter, view
end

-- 보기 상태 저장(유효하고 쓸 수 있을 때만), dik, 2026-09-30
function ns.Gold.SetViewState(period, charFilter, view)
    if not Contains(PERIODS, period) or not Contains(VIEWS, view) or not IsValidCharFilter(charFilter) then
        return
    end
    if not ns.db or ns.IsDatabaseNewer() then
        return
    end
    local area = ns.GetModuleData(MODULE_ID)
    if not area then
        return
    end
    if IsNumber(area.version) and area.version > AREA_VERSION then
        return
    end
    if not IsNumber(area.version) or area.version < AREA_VERSION then
        area.version = AREA_VERSION
    end
    area.period = period
    area.charFilter = charFilter
    area.view = view
end

-- 상태 조회(없는 API·이벤트 이름 복사본), dik, 2026-09-30
function ns.Gold.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    return { missing = missing, readOnly = state.readOnly }
end
