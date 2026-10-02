-- 퀘스트 진행 파티 알림 모듈 등록·순수 함수·어댑터·대기열, dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "partyQuest"
local SCAN_DELAY = 0.3
local BASELINE_DELAY = 2
local TICK = 0.25
local SEND_INTERVAL = 1.0
local QUEUE_MAX = 5
local QUEUE_TTL = 60
local REPEAT_SPAN = 30
local MAX_BYTES = 255
local CHANNEL = "PARTY"
local FOREVERUI = "ForeverUI"
local ELLIPSIS = "\226\128\166"

local EVENTS = {
    "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED",
    "QUEST_WATCH_UPDATE",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
}

ns.PartyQuest = ns.PartyQuest or {}
local PQ = ns.PartyQuest
PQ.MODULE_ID = MODULE_ID
PQ.SCAN_DELAY = SCAN_DELAY
PQ.BASELINE_DELAY = BASELINE_DELAY
PQ.TICK = TICK
PQ.SEND_INTERVAL = SEND_INTERVAL
PQ.QUEUE_MAX = QUEUE_MAX
PQ.QUEUE_TTL = QUEUE_TTL
PQ.REPEAT_GUARD = REPEAT_SPAN
PQ.MAX_BYTES = MAX_BYTES
PQ.CHANNEL = CHANNEL
PQ.FOREVERUI = FOREVERUI
PQ.EVENTS = EVENTS

local frame
local sendFn
local sendBlocked = false
local droppedNotified = false
local blockedNotified = false
local snapshot
local baselineAt = 0
local scanAt
local queue = {}
local lastSent = {}
local lastSendAt = -1000
local failedEvents = {}

-- 유한 number 판정, dik, 2026-10-02
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 오류 처리기 포함 호출(ok, 반환...), dik, 2026-10-02
local function SafeCall(fn, ...)
    local args = { ... }
    local n = select("#", ...)
    return xpcall(function() return fn(unpack(args, 1, n)) end, geterrorhandler())
end

-- 메시지 문자열 정리, dik, 2026-10-02
function PQ.Sanitize(s)
    if ns.IsSecret(s) or type(s) ~= "string" then
        return ""
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|", "")
    s = s:gsub("%s+", " ")
    s = s:gsub("^ ", "")
    s = s:gsub(" $", "")
    return s
end

-- UTF-8 경계 바이트 자르기, dik, 2026-10-02
function PQ.Truncate(msg, maxBytes)
    if type(msg) ~= "string" or #msg <= maxBytes then
        return msg
    end
    local cut = maxBytes - 3
    while cut > 0 do
        local b = msg:byte(cut + 1)
        if b and b >= 0x80 and b <= 0xBF then
            cut = cut - 1
        else
            break
        end
    end
    return msg:sub(1, cut) .. ELLIPSIS
end

-- 퀘스트 완료 메시지, dik, 2026-10-02
function PQ.FormatQuest(title)
    return PQ.Truncate(L.FMT_PQA_QUEST:format(PQ.Sanitize(title)), MAX_BYTES)
end

-- 목표 완료 메시지, dik, 2026-10-02
function PQ.FormatObjective(title, text, index)
    local body = PQ.Sanitize(text)
    if body == "" then
        body = L.FMT_PQA_OBJECTIVE_INDEX:format(tonumber(index) or 0)
    end
    return PQ.Truncate(L.FMT_PQA_OBJECTIVE:format(PQ.Sanitize(title), body), MAX_BYTES)
end

-- 로그 순서 정렬 키 목록, dik, 2026-10-02
local function SortedIds(cur)
    local ids = {}
    for id in pairs(cur) do
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
        local ia = IsNumber(cur[a].index) and cur[a].index or a
        local ib = IsNumber(cur[b].index) and cur[b].index or b
        if ia ~= ib then
            return ia < ib
        end
        return a < b
    end)
    return ids
end

-- 스냅샷 비교 알림·병합 스냅샷, dik, 2026-10-02
function PQ.Diff(prev, cur, opts)
    local alerts, merged = {}, {}
    if type(cur) ~= "table" then
        return alerts, merged
    end
    opts = opts or {}
    local ids = SortedIds(cur)
    for n = 1, #ids do
        local id = ids[n]
        local entry = cur[id]
        local p = type(prev) == "table" and prev[id] or nil
        local sameCount = p ~= nil and #p.objectives == #entry.objectives
        local m = {
            title = entry.title,
            complete = entry.complete,
            failed = entry.failed,
            index = entry.index,
            objectives = {},
        }
        for i = 1, #entry.objectives do
            local o = entry.objectives[i]
            local finished = o.finished
            if finished == nil and sameCount then
                finished = p.objectives[i].finished
            end
            m.objectives[i] = { text = o.text, finished = finished }
        end
        merged[id] = m
        if p then
            local questAlert = false
            if opts.quests == true and p.complete == false and entry.complete == true and entry.failed ~= true then
                questAlert = true
                alerts[#alerts + 1] = {
                    kind = "quest", key = id .. ":q", questID = id,
                    text = PQ.FormatQuest(entry.title),
                }
            end
            -- 실패 퀘스트 목표 알림 제외(R7), dik, 2026-10-02
            if opts.objectives == true and not questAlert and sameCount and entry.failed ~= true then
                for i = 1, #entry.objectives do
                    if p.objectives[i].finished == false and entry.objectives[i].finished == true then
                        alerts[#alerts + 1] = {
                            kind = "objective", key = id .. ":" .. i, questID = id, index = i,
                            text = PQ.FormatObjective(entry.title, entry.objectives[i].text, i),
                        }
                    end
                end
            end
        end
    end
    return alerts, merged
end

-- 발송 채널 결정, dik, 2026-10-02
function PQ.ResolveChannel(g)
    if type(g) ~= "table" or g.home == nil then
        return nil, "unknown"
    end
    if g.home == false then
        if g.instance == true then
            return nil, "instance"
        end
        return nil, "solo"
    end
    if g.raid == nil or g.instance == nil then
        return nil, "unknown"
    end
    if g.raid == true then
        return nil, "raid"
    end
    if g.instance == true then
        return nil, "instance"
    end
    return CHANNEL
end

-- 같은 알림 반복 억제 판정, dik, 2026-10-02
function PQ.IsRepeat(key, now, lastSentTable)
    local t = lastSentTable and lastSentTable[key]
    return t ~= nil and now - t < REPEAT_SPAN
end

-- 읽기 결과 boolean 정리(secret·비boolean 은 nil), dik, 2026-10-02
local function PlainBoolean(ok, v)
    if ok and not ns.IsSecret(v) and type(v) == "boolean" then
        return v
    end
    return nil
end

-- 그룹 상태 읽기, dik, 2026-10-02
function PQ.ReadGroup()
    local g = {}
    if type(LE_PARTY_CATEGORY_HOME) == "number" then
        g.home = PlainBoolean(SafeCall(IsInGroup, LE_PARTY_CATEGORY_HOME))
        g.raid = PlainBoolean(SafeCall(IsInRaid, LE_PARTY_CATEGORY_HOME))
        if type(LE_PARTY_CATEGORY_INSTANCE) == "number" then
            g.instance = PlainBoolean(SafeCall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
        else
            g.instance = false
        end
    else
        g.home = PlainBoolean(SafeCall(IsInGroup))
        g.raid = PlainBoolean(SafeCall(IsInRaid))
        g.instance = false
    end
    return g
end

-- 퀘스트 한 줄 읽기(skip/unreadable/entry), dik, 2026-10-02
local function ReadEntry(info, index)
    if type(info) ~= "table" then
        return "skip"
    end
    local id = info.questID
    if ns.IsSecret(id) or not IsNumber(id) then
        return "skip"
    end
    local flags = { info.isHeader, info.isHidden, info.isTask, info.isBounty }
    for i = 1, 4 do
        if ns.IsSecret(flags[i]) then
            return "unreadable", id
        end
    end
    if flags[1] or flags[2] or flags[3] or flags[4] then
        return "skip"
    end
    local title = info.title
    if ns.IsSecret(title) or type(title) ~= "string" or title == "" then
        title = nil
        if ns.HasAPI("C_QuestLog.GetTitleForQuestID") then
            local ok, t = SafeCall(C_QuestLog.GetTitleForQuestID, id)
            if ok and not ns.IsSecret(t) and type(t) == "string" and t ~= "" then
                title = t
            end
        end
    end
    if title == nil then
        return "unreadable", id
    end
    local okC, complete = SafeCall(C_QuestLog.IsComplete, id)
    complete = PlainBoolean(okC, complete)
    if complete == nil then
        return "unreadable", id
    end
    local failed = false
    if ns.HasAPI("C_QuestLog.IsFailed") then
        local okF, f = SafeCall(C_QuestLog.IsFailed, id)
        if okF and ns.IsSecret(f) then
            return "unreadable", id
        end
        failed = okF and f == true
    end
    local okO, objs = SafeCall(C_QuestLog.GetQuestObjectives, id)
    if not okO or ns.IsSecret(objs) or type(objs) ~= "table" then
        return "unreadable", id
    end
    local list = {}
    for i = 1, #objs do
        local o = objs[i]
        local text, finished = "", nil
        if type(o) == "table" then
            if not ns.IsSecret(o.text) and type(o.text) == "string" then
                text = o.text
            end
            if not ns.IsSecret(o.finished) and type(o.finished) == "boolean" then
                finished = o.finished
            end
        end
        list[i] = { text = text, finished = finished }
    end
    return {
        title = title, complete = complete, failed = failed, index = index, objectives = list,
    }
end

-- 퀘스트 로그 스냅샷 읽기(실패 시 nil), dik, 2026-10-02
function PQ.ReadSnapshot(prev)
    local ok, num = SafeCall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or ns.IsSecret(num) or not IsNumber(num) then
        return nil
    end
    local cur = {}
    for i = 1, num do
        local okI, info = SafeCall(C_QuestLog.GetInfo, i)
        if okI then
            local result, id = ReadEntry(info, i)
            if type(result) == "table" then
                cur[info.questID] = result
            elseif result == "unreadable" and type(prev) == "table" and prev[id] then
                cur[id] = prev[id]
            end
        end
    end
    return cur
end

-- 내 채팅창 표시 규칙(반복 억제 기록 포함), dik, 2026-10-02
local function EchoOrDrop(item, now)
    lastSent[item.key] = now
    if ns.GetSetting(MODULE_ID, "echoLocal") == true then
        ns.Print(item.text)
    end
end

-- 발송 중지 처리, dik, 2026-10-02
local function MarkBlocked()
    sendBlocked = true
    for i = #queue, 1, -1 do
        queue[i] = nil
    end
    if not blockedNotified then
        blockedNotified = true
        ns.Print(L.MSG_PQA_BLOCKED)
    end
end

-- 알림 생성 후 채널 분기, dik, 2026-10-02
local function Notify(alert, now)
    if PQ.IsRepeat(alert.key, now, lastSent) then
        return
    end
    local channel = PQ.ResolveChannel(PQ.ReadGroup())
    if channel == CHANNEL and sendFn and not sendBlocked then
        if #queue >= QUEUE_MAX then
            if not droppedNotified then
                droppedNotified = true
                ns.Print(L.MSG_PQA_DROPPED)
            end
        else
            queue[#queue + 1] = { key = alert.key, text = alert.text, at = now }
        end
    else
        EchoOrDrop(alert, now)
    end
end

-- 전투·채팅 잠금 판정, dik, 2026-10-02
local function IsHeld()
    local combat = InCombatLockdown()
    if ns.IsSecret(combat) or combat == true then
        return true
    end
    if ns.HasAPI("C_ChatInfo.InChatMessagingLockdown") then
        local ok, locked = SafeCall(C_ChatInfo.InChatMessagingLockdown)
        if ok and (ns.IsSecret(locked) or locked == true) then
            return true
        end
    end
    return false
end

-- 대기열 1건 처리, dik, 2026-10-02
local function Process(now)
    if #queue == 0 then
        return
    end
    while queue[1] and now - queue[1].at > QUEUE_TTL do
        table.remove(queue, 1)
    end
    if #queue == 0 or IsHeld() or now - lastSendAt < SEND_INTERVAL then
        return
    end
    local item = table.remove(queue, 1)
    local channel = PQ.ResolveChannel(PQ.ReadGroup())
    if channel == CHANNEL and sendFn and not sendBlocked then
        local ok = xpcall(function() sendFn(item.text, CHANNEL) end, geterrorhandler())
        lastSendAt = now
        lastSent[item.key] = now
        if not ok then
            MarkBlocked()
        end
    else
        EchoOrDrop(item, now)
    end
end

-- 기준선 재설정과 스캔 예약, dik, 2026-10-02
local function ResetBaseline(now)
    snapshot = nil
    baselineAt = now + BASELINE_DELAY
    scanAt = now + SCAN_DELAY
end

-- 스캔 예약(이미 있으면 유지), dik, 2026-10-02
local function ScheduleScan(now)
    if not scanAt then
        scanAt = now + SCAN_DELAY
    end
end

-- 스캔 1회 실행, dik, 2026-10-02
local function Scan(now)
    scanAt = nil
    local cur = PQ.ReadSnapshot(snapshot)
    if cur == nil then
        return
    end
    if snapshot == nil then
        snapshot = cur
        return
    end
    local opts = {
        objectives = ns.GetSetting(MODULE_ID, "objectives") == true,
        quests = ns.GetSetting(MODULE_ID, "quests") == true,
    }
    local alerts, merged = PQ.Diff(snapshot, cur, opts)
    snapshot = merged
    for i = 1, #alerts do
        Notify(alerts[i], now)
    end
end

-- 이벤트 처리, dik, 2026-10-02
-- 차단 이벤트 분기 코어 이관(WFA-040), dik, 2026-10-02
local function OnEvent(_, event, arg1)
    local now = GetTime()
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
        ScheduleScan(now)
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if ns.IsSecret(arg1) or arg1 == "player" then
            ScheduleScan(now)
        end
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if snapshot and not ns.IsSecret(arg1) and type(arg1) == "number" then
            snapshot[arg1] = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetBaseline(now)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Process(now)
    end
end

local elapsedTotal = 0

-- 예약 스캔·대기열 점검, dik, 2026-10-02
local function OnUpdate(_, elapsed)
    local now = GetTime()
    if scanAt and now >= scanAt and now >= baselineAt then
        Scan(now)
    end
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal >= TICK then
        elapsedTotal = 0
        Process(now)
    end
end

-- READY 안내 출력, dik, 2026-10-02
local function OnReady()
    if ns.HasAPI("C_AddOns.IsAddOnLoaded") then
        local ok, loaded = SafeCall(C_AddOns.IsAddOnLoaded, FOREVERUI)
        if ok and not ns.IsSecret(loaded) and loaded == true then
            ns.Print(L.MSG_PQA_FOREVERUI)
        end
    end
    if #failedEvents > 0 then
        ns.Print(L.MSG_PQA_PARTIAL:format(ns.FormatMissingAPIs(failedEvents)))
    end
    if not sendFn then
        ns.Print(L.MSG_PQA_NO_SEND)
    end
end

-- 이벤트 프레임·발송 API·기준선 초기화, dik, 2026-10-02
local function InitializePartyQuest()
    if ns.HasAPI("C_ChatInfo.SendChatMessage") then
        sendFn = C_ChatInfo.SendChatMessage
    elseif ns.HasAPI("SendChatMessage") then
        sendFn = SendChatMessage
    end
    frame = CreateFrame("Frame")
    for i = 1, #EVENTS do
        local ok = pcall(frame.RegisterEvent, frame, EVENTS[i])
        if not ok then
            failedEvents[#failedEvents + 1] = EVENTS[i]
        end
    end
    frame:SetScript("OnEvent", OnEvent)
    frame:SetScript("OnUpdate", OnUpdate)
    -- 동작 차단 공통 처리 구독(WFA-040), dik, 2026-10-02
    ns.ActionBlock.Register(MODULE_ID, { "SendChatMessage" }, MarkBlocked, { stopOnUnknown = false })
    ResetBaseline(GetTime())
    ns.On("READY", OnReady)
end

ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_PARTY_QUEST,
    description = L.MODULE_PARTY_QUEST_DESC,
    category = "feature",
    order = 85,
    requires = { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
        "C_QuestLog.IsComplete", "IsInGroup", "IsInRaid" },
    settings = {
        { key = "objectives", type = "checkbox", label = L.SETTING_PQA_OBJECTIVES,
            tooltip = L.SETTING_PQA_OBJECTIVES_TIP, default = true },
        { key = "quests", type = "checkbox", label = L.SETTING_PQA_QUESTS,
            tooltip = L.SETTING_PQA_QUESTS_TIP, default = true },
        { key = "echoLocal", type = "checkbox", label = L.SETTING_PQA_ECHO,
            tooltip = L.SETTING_PQA_ECHO_TIP, default = false },
    },
    OnInitialize = function()
        InitializePartyQuest()
    end,
})
