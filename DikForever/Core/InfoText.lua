-- 정보 텍스트 공급자 레지스트리·판정 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.InfoText = {}

local FALLBACK_INTERVAL = 5
local GUILD_REQUEST_INTERVAL = 60
local DEFAULT_ORDER = 100
local DEFAULT_BAG_SLOTS = 4
local FIRST_EQUIP_SLOT = 1
local LAST_EQUIP_SLOT = 19
local ENTERING_EVENT = "PLAYER_ENTERING_WORLD"
local TOKEN_TEXT = "TEXT"
local TOKEN_DIM = "TEXT_DIM"
local TOKEN_ACCENT = "ACCENT"
local TOKEN_DANGER = "DANGER"

local providers = {}
local states = {}
local eventRefs = {}
local frame = CreateFrame("Frame")

-- 유한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- secret 이면 nil 로 바꿔 반환, dik, 2026-10-01
local function Clean(v)
    if ns.IsSecret(v) then
        return nil
    end
    return v
end

-- 이벤트 등록 참조 카운트 증가(성공 여부 반환), dik, 2026-10-01
local function AcquireEvent(name)
    if (eventRefs[name] or 0) > 0 then
        eventRefs[name] = eventRefs[name] + 1
        return true
    end
    local registered = pcall(frame.RegisterEvent, frame, name)
    if registered then
        eventRefs[name] = 1
    end
    return registered
end

-- 이벤트 등록 참조 카운트 감소(0 이면 해제), dik, 2026-10-01
local function ReleaseEvent(name)
    local count = eventRefs[name]
    if not count then
        return
    end
    if count <= 1 then
        eventRefs[name] = nil
        frame:UnregisterEvent(name)
    else
        eventRefs[name] = count - 1
    end
end

-- 공급자 계산(오류·비문자열은 nil), dik, 2026-10-01
local function Compute(def)
    local ok, text, color = xpcall(def.Get, geterrorhandler())
    if not ok or type(text) ~= "string" then
        return nil, TOKEN_DIM
    end
    if type(color) ~= "string" then
        color = TOKEN_TEXT
    end
    return text, color
end

-- 재계산 후 값이 달라졌을 때만 발행, dik, 2026-10-01
local function Recalc(id, force)
    local state = states[id]
    local def = providers[id]
    if not state or not def then
        return
    end
    local text, color = Compute(def)
    if force or text ~= state.text or color ~= state.color then
        state.text = text
        state.color = color
        ns.Fire("INFO_UPDATED", id)
    end
end

-- request 실행(오류 전달), dik, 2026-10-01
local function RunRequest(def)
    if type(def.request) == "function" then
        xpcall(def.request, geterrorhandler())
    end
end

-- 활성 공급자 id 스냅샷, dik, 2026-10-01
local function ActiveIds()
    local ids = {}
    for id in pairs(states) do
        ids[#ids + 1] = id
    end
    return ids
end

-- 공급자 계산 주기(초, 없으면 nil), dik, 2026-10-01
local function PeriodOf(state, def)
    if state.fallback then
        return FALLBACK_INTERVAL
    end
    return def.interval
end

local dueCalc, dueRequest = {}, {}

-- 프레임 OnUpdate 누적 처리, dik, 2026-10-01
local function OnUpdateHandler(_, elapsed)
    local calcCount, requestCount = 0, 0
    for id, state in pairs(states) do
        local def = providers[id]
        if def then
            local period = PeriodOf(state, def)
            if period then
                state.elapsed = state.elapsed + elapsed
                if state.elapsed >= period then
                    state.elapsed = 0
                    calcCount = calcCount + 1
                    dueCalc[calcCount] = id
                end
            end
            if def.requestInterval then
                state.reqElapsed = state.reqElapsed + elapsed
                if state.reqElapsed >= def.requestInterval then
                    state.reqElapsed = 0
                    requestCount = requestCount + 1
                    dueRequest[requestCount] = id
                end
            end
        end
    end
    for i = 1, requestCount do
        local id = dueRequest[i]
        dueRequest[i] = nil
        if states[id] then
            RunRequest(providers[id])
        end
    end
    for i = 1, calcCount do
        local id = dueCalc[i]
        dueCalc[i] = nil
        Recalc(id)
    end
end

-- 이벤트 처리(선언 이벤트·입장 재계산), dik, 2026-10-01
local function OnEventHandler(_, event)
    local ids = ActiveIds()
    for i = 1, #ids do
        local id = ids[i]
        local state = states[id]
        if state and (event == ENTERING_EVENT or state.eventSet[event]) then
            Recalc(id)
        end
    end
end

frame:SetScript("OnEvent", OnEventHandler)

-- 주기 계산이 필요한 활성 공급자 유무로 OnUpdate 설정, dik, 2026-10-01
local function RefreshOnUpdate()
    local needed = false
    for id, state in pairs(states) do
        local def = providers[id]
        if def and (PeriodOf(state, def) or def.requestInterval) then
            needed = true
            break
        end
    end
    if needed then
        frame:SetScript("OnUpdate", OnUpdateHandler)
    else
        frame:SetScript("OnUpdate", nil)
    end
end

-- 공급자 활성화, dik, 2026-10-01
local function Activate(id)
    local def = providers[id]
    local state = { owners = {}, count = 0, elapsed = 0, reqElapsed = 0, regged = {}, eventSet = {}, fallback = false }
    states[id] = state
    local declared, succeeded = 0, 0
    for i = 1, #def.events do
        local name = def.events[i]
        if type(name) == "string" and not state.eventSet[name] then
            state.eventSet[name] = true
            declared = declared + 1
            if AcquireEvent(name) then
                succeeded = succeeded + 1
                state.regged[#state.regged + 1] = name
            end
        end
    end
    if declared > 0 and succeeded == 0 then
        state.fallback = true
    end
    if not state.eventSet[ENTERING_EVENT] and AcquireEvent(ENTERING_EVENT) then
        state.regged[#state.regged + 1] = ENTERING_EVENT
    end
    return state
end

-- 공급자 비활성화, dik, 2026-10-01
local function Deactivate(id)
    local state = states[id]
    if not state then
        return
    end
    states[id] = nil
    for i = 1, #state.regged do
        ReleaseEvent(state.regged[i])
    end
    RefreshOnUpdate()
end

-- 공급자 등록, dik, 2026-10-01
function ns.InfoText.Register(def)
    local id = type(def) == "table" and def.id or nil
    if type(def) ~= "table" or type(id) ~= "string" or id == ""
        or type(def.label) ~= "string" or type(def.Get) ~= "function" or providers[id] then
        ns.Print(L.ERR_INFO_PROVIDER:format(type(id) == "string" and id ~= "" and id or "?"))
        return nil
    end
    if type(def.requires) ~= "table" then
        def.requires = {}
    end
    if type(def.events) ~= "table" then
        def.events = {}
    end
    if not IsNumber(def.order) then
        def.order = DEFAULT_ORDER
    end
    def.showLabel = def.showLabel ~= false
    providers[id] = def
    return def
end

-- 공급자 조회, dik, 2026-10-01
function ns.InfoText.GetProvider(id)
    return providers[id]
end

-- 공급자 목록(order 오름차순·같으면 id), dik, 2026-10-01
function ns.InfoText.GetProviders()
    local list = {}
    for _, def in pairs(providers) do
        list[#list + 1] = def
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    return list
end

-- 지원 여부와 없는 API 배열, dik, 2026-10-01
function ns.InfoText.IsSupported(id)
    local def = providers[id]
    if not def then
        return false, {}
    end
    local missing = ns.GetMissingAPIs(def.requires)
    return #missing == 0, missing
end

-- 구독 시작(첫 구독자면 활성화), dik, 2026-10-01
function ns.InfoText.Acquire(id, owner)
    local def = providers[id]
    if not def or type(owner) ~= "string" or owner == "" then
        return false
    end
    if not ns.InfoText.IsSupported(id) then
        return false
    end
    local state = states[id]
    if state then
        if not state.owners[owner] then
            state.owners[owner] = true
            state.count = state.count + 1
        end
        return true
    end
    state = Activate(id)
    state.owners[owner] = true
    state.count = 1
    RefreshOnUpdate()
    RunRequest(def)
    Recalc(id, true)
    return true
end

-- 구독 해제(마지막이면 비활성화), dik, 2026-10-01
function ns.InfoText.Release(id, owner)
    local state = states[id]
    if not state or type(owner) ~= "string" or not state.owners[owner] then
        return
    end
    state.owners[owner] = nil
    state.count = state.count - 1
    if state.count <= 0 then
        Deactivate(id)
    end
end

-- 현재 값 조회, dik, 2026-10-01
function ns.InfoText.GetValue(id)
    local def = providers[id]
    if not def then
        return nil, TOKEN_DIM
    end
    local state = states[id]
    if state then
        return state.text, state.color or TOKEN_DIM
    end
    local text, color = Compute(def)
    return text, color or TOKEN_DIM
end

-- FPS 판정, dik, 2026-10-01
function ns.InfoText.EvalFps(fps)
    if not IsNumber(fps) then
        return nil
    end
    local n = math.floor(fps + 0.5)
    if n < 15 then
        return tostring(n), TOKEN_DANGER
    end
    return tostring(n), TOKEN_TEXT
end

-- 지연 판정, dik, 2026-10-01
function ns.InfoText.EvalLatency(home, world)
    local best = nil
    if IsNumber(home) and home >= 0 then
        best = home
    end
    if IsNumber(world) and world >= 0 and (best == nil or world > best) then
        best = world
    end
    if best == nil then
        return nil
    end
    local ms = math.floor(best)
    local text = string.format(L.FMT_MS, ms)
    if ms >= 300 then
        return text, TOKEN_DANGER
    end
    if ms >= 150 then
        return text, TOKEN_ACCENT
    end
    return text, TOKEN_TEXT
end

-- 골드 판정, dik, 2026-10-01
function ns.InfoText.EvalGold(copper)
    if not IsNumber(copper) then
        return nil
    end
    if copper >= 10000 then
        return string.format(L.FMT_GOLD, ns.FormatNumber(math.floor(copper / 10000))), TOKEN_TEXT
    end
    return ns.FormatMoney(copper), TOKEN_TEXT
end

-- 일반 가방 빈칸 합계, dik, 2026-10-01
function ns.InfoText.SumFreeSlots(list)
    if type(list) ~= "table" then
        return nil
    end
    local total, valid = 0, 0
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" and IsNumber(entry[1]) and entry[1] >= 0 and entry[2] == 0 then
            total = total + entry[1]
            valid = valid + 1
        end
    end
    if valid == 0 then
        return nil
    end
    return total
end

-- 가방 판정, dik, 2026-10-01
function ns.InfoText.EvalBags(free)
    if not IsNumber(free) then
        return nil
    end
    if free == 0 then
        return tostring(free), TOKEN_DANGER
    end
    if free <= 5 then
        return tostring(free), TOKEN_ACCENT
    end
    return tostring(free), TOKEN_TEXT
end

-- 접속자 수 판정, dik, 2026-10-01
function ns.InfoText.EvalOnline(online, total)
    if not (IsNumber(online) and online >= 0 and IsNumber(total) and total >= 0) then
        return nil
    end
    local text = string.format(L.FMT_ONLINE, math.floor(online), math.floor(total))
    if online == 0 then
        return text, TOKEN_DIM
    end
    return text, TOKEN_TEXT
end

-- 내구도 최솟값 판정, dik, 2026-10-01
function ns.InfoText.EvalDurability(list)
    if type(list) ~= "table" then
        return nil
    end
    local lowest = nil
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" then
            local cur, max = entry[1], entry[2]
            if IsNumber(max) and max > 0 and IsNumber(cur) and cur >= 0 then
                local p = math.floor(cur * 100 / max)
                if lowest == nil or p < lowest then
                    lowest = p
                end
            end
        end
    end
    if lowest == nil then
        return nil
    end
    local text = string.format(L.FMT_PERCENT_INT, lowest)
    if lowest < 25 then
        return text, TOKEN_DANGER
    end
    if lowest < 50 then
        return text, TOKEN_ACCENT
    end
    return text, TOKEN_TEXT
end

-- fps 공급자 값, dik, 2026-10-01
local function GetFpsValue()
    return ns.InfoText.EvalFps(Clean(GetFramerate()))
end

-- latency 공급자 값, dik, 2026-10-01
local function GetLatencyValue()
    local _, _, home, world = GetNetStats()
    return ns.InfoText.EvalLatency(Clean(home), Clean(world))
end

-- gold 공급자 값, dik, 2026-10-01
local function GetGoldValue()
    return ns.InfoText.EvalGold(Clean(GetMoney()))
end

-- bags 공급자 값, dik, 2026-10-01
local function GetBagsValue()
    local slots = NUM_BAG_SLOTS
    if not IsNumber(slots) then
        slots = DEFAULT_BAG_SLOTS
    end
    local list = {}
    for bag = 0, slots do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if not ns.IsSecret(free) and not ns.IsSecret(family) then
            list[#list + 1] = { free, family }
        end
    end
    return ns.InfoText.EvalBags(ns.InfoText.SumFreeSlots(list))
end

-- friends 공급자 값, dik, 2026-10-01
local function GetFriendsValue()
    return ns.InfoText.EvalOnline(Clean(C_FriendList.GetNumOnlineFriends()), Clean(C_FriendList.GetNumFriends()))
end

-- friends 요청(활성화 시 1회), dik, 2026-10-01
local function RequestFriends()
    if ns.HasAPI("C_FriendList.ShowFriends") then
        C_FriendList.ShowFriends()
    end
end

-- guild 공급자 값, dik, 2026-10-01
local function GetGuildValue()
    if Clean(IsInGuild()) ~= true then
        return nil
    end
    local total, online = GetNumGuildMembers()
    return ns.InfoText.EvalOnline(Clean(online), Clean(total))
end

-- guild 요청(길드 소속일 때), dik, 2026-10-01
local function RequestGuild()
    if ns.HasAPI("C_GuildInfo.GuildRoster") and IsInGuild() == true then
        C_GuildInfo.GuildRoster()
    end
end

-- durability 공급자 값, dik, 2026-10-01
local function GetDurabilityValue()
    local list = {}
    for slot = FIRST_EQUIP_SLOT, LAST_EQUIP_SLOT do
        local cur, max = GetInventoryItemDurability(slot)
        if not ns.IsSecret(cur) and not ns.IsSecret(max) then
            list[#list + 1] = { cur, max }
        end
    end
    return ns.InfoText.EvalDurability(list)
end

ns.InfoText.Register({ id = "fps", label = L.INFO_FPS, order = 10, interval = 1,
    requires = { "GetFramerate" }, Get = GetFpsValue })
ns.InfoText.Register({ id = "latency", label = L.INFO_LATENCY, order = 20, interval = 5,
    requires = { "GetNetStats" }, Get = GetLatencyValue })
ns.InfoText.Register({ id = "gold", label = L.INFO_GOLD, order = 30, events = { "PLAYER_MONEY" },
    requires = { "GetMoney" }, Get = GetGoldValue })
ns.InfoText.Register({ id = "bags", label = L.INFO_BAGS, order = 40, events = { "BAG_UPDATE_DELAYED" },
    requires = { "C_Container.GetContainerNumFreeSlots" }, Get = GetBagsValue })
ns.InfoText.Register({ id = "friends", label = L.INFO_FRIENDS, order = 50, events = { "FRIENDLIST_UPDATE" },
    requires = { "C_FriendList.GetNumOnlineFriends", "C_FriendList.GetNumFriends" },
    Get = GetFriendsValue, request = RequestFriends })
ns.InfoText.Register({ id = "guild", label = L.INFO_GUILD, order = 60,
    events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
    requires = { "IsInGuild", "GetNumGuildMembers" }, Get = GetGuildValue,
    request = RequestGuild, requestInterval = GUILD_REQUEST_INTERVAL })
ns.InfoText.Register({ id = "durability", label = L.INFO_DURABILITY, order = 70,
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
    requires = { "GetInventoryItemDurability" }, Get = GetDurabilityValue })
