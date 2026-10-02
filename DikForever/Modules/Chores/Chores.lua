-- 잡일 자동화 모듈 등록·상점/퀘스트 창 자동 처리·로그, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "chores"
local SELL_MAX = 12
local SELL_INTERVAL = 0.2
local QUALITY_POOR = 0
local BAG_FIRST = 0
local BAG_LAST_DEFAULT = 4
local GUILD_CHECK_DELAY = 1.0
local ROUND_CLOSE_GAP = 2
local QUEST_ROUND_MAX = 20
local LOG_MAX = 50
local AREA_VERSION = 1
-- 빠른 줍기 상수 추가, dik, 2026-10-02
local LOOT_SLOT_MAX = 20
local LOOT_PASS_MAX = 2
local LOOT_THRESHOLD_DEFAULT = 2
local AUTOLOOT_CVAR = "autoLootDefault"
local AUTOLOOT_TOGGLE = "AUTOLOOTTOGGLE"

local EVENT_ORDER = {
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "QUEST_GREETING",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_FINISHED",
    -- 빠른 줍기 이벤트 추가, dik, 2026-10-02
    "LOOT_READY",
    "LOOT_OPENED",
    "LOOT_CLOSED",
}

local EVENT_GROUPS = {
    MERCHANT_SHOW = { "sell", "repair" },
    MERCHANT_CLOSED = { "sell", "repair" },
    GOSSIP_SHOW = { "gossip" },
    QUEST_GREETING = { "greeting" },
    QUEST_DETAIL = { "accept" },
    QUEST_PROGRESS = { "turnIn" },
    QUEST_COMPLETE = { "turnIn" },
    -- 전리품 창 닫힘 그룹 매핑 추가, dik, 2026-10-02
    LOOT_CLOSED = { "loot" },
}

local API_GROUPS = {
    sell = {
        "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
        "C_Item.GetItemInfo", "C_Container.UseContainerItem", "C_Timer",
    },
    repair = { "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems", "GetMoney" },
    guild = { "IsInGuild", "CanGuildBankRepair", "C_Timer" },
    gossip = {
        "C_GossipInfo.GetActiveQuests", "C_GossipInfo.GetAvailableQuests",
        "C_GossipInfo.SelectActiveQuest", "C_GossipInfo.SelectAvailableQuest", "GetTime",
    },
    greeting = {
        "GetNumActiveQuests", "GetActiveTitle", "GetNumAvailableQuests",
        "GetAvailableQuestInfo", "SelectActiveQuest", "SelectAvailableQuest", "GetTime",
    },
    accept = { "AcceptQuest", "UnitExists", "UnitIsPlayer", "GetTime" },
    turnIn = {
        "IsQuestCompletable", "CompleteQuest", "GetQuestMoneyToGet",
        "GetNumQuestChoices", "GetQuestReward", "GetTime",
    },
    -- 빠른 줍기 API 그룹 추가, dik, 2026-10-02
    loot = { "GetNumLootItems", "GetLootSlotInfo", "LootSlot" },
}

-- 빠른 줍기 그룹 순서 추가, dik, 2026-10-02
local API_GROUP_ORDER = { "sell", "repair", "guild", "gossip", "greeting", "accept", "turnIn", "loot" }

local FEATURE_GROUP = {
    sellJunk = "sell",
    autoRepair = "repair",
    autoAccept = "accept",
    autoTurnIn = "turnIn",
    -- 빠른 줍기 그룹 매핑, dik, 2026-10-02
    fastLoot = "loot",
}

local LOG_KINDS = {
    sell = true, repair = true, guildRepair = true, repairNoMoney = true, accept = true,
    turnIn = true, reward = true, skip = true, blocked = true,
}

local state = {
    blocked = false,
    blockedFunc = nil,
    readOnly = false,
    merchantOpen = false,
    merchantSkip = false,
    personalRepaired = false,
    guildRepaired = false,
    token = 0,
    round = nil,
    -- 전리품 회차 상태 추가, dik, 2026-10-02
    loot = nil,
    groups = {},
    missing = {},
    log = {},
    totals = { soldCount = 0, soldMoney = 0, repairMoney = 0, accepted = 0, turnedIn = 0 },
    frame = nil,
}

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- secret 이면 nil 로 바꾼 값, dik, 2026-09-30
local function Plain(v)
    if ns.IsSecret(v) then
        return nil
    end
    return v
end

-- 설정 켜짐 판정, dik, 2026-09-30
local function Setting(key)
    return ns.GetSetting(MODULE_ID, key) == true
end

-- 잡템 선택(순수 함수), dik, 2026-09-30
local function SelectJunk(items, max)
    local picked = {}
    local candidates = 0
    if not IsNumber(max) then
        max = 0
    end
    if type(items) == "table" then
        for i = 1, #items do
            local it = items[i]
            if type(it) == "table" and it.quality == QUALITY_POOR and it.locked ~= true and it.noValue ~= true
                and IsNumber(it.sellPrice) and it.sellPrice > 0 and IsNumber(it.count) and it.count >= 1 then
                candidates = candidates + 1
                if #picked < max then
                    picked[#picked + 1] = it
                end
            end
        end
    end
    return picked, candidates - #picked
end

-- 판매 금액 계산(순수 함수), dik, 2026-09-30
local function SumSale(sold)
    local money = 0
    local count = 0
    if type(sold) == "table" then
        count = #sold
        for i = 1, count do
            local it = sold[i]
            if type(it) == "table" and IsNumber(it.sellPrice) and IsNumber(it.count) then
                money = money + it.sellPrice * it.count
            end
        end
    end
    return count, money
end

-- 수리 판정(순수 함수), dik, 2026-09-30
local function DecideRepair(s)
    if type(s) ~= "table" or s.merchantCanRepair ~= true or s.canRepair ~= true
        or not IsNumber(s.cost) or s.cost <= 0 then
        return "none", 0
    end
    if s.useGuild == true and s.guildAllowed == true then
        return "guild", s.cost
    end
    if IsNumber(s.money) and s.money >= s.cost then
        return "personal", s.cost
    end
    return "noMoney", s.cost
end

-- 퀘스트 회차 판정(순수 함수), dik, 2026-09-30
local function IsNewRound(round, npc, now)
    if round == nil then
        return true
    end
    if npc ~= round.npc then
        return true
    end
    local closeAt = round.lastCloseAt
    if IsNumber(closeAt) and IsNumber(round.lastEventAt) and closeAt >= round.lastEventAt
        and IsNumber(now) and now - closeAt > ROUND_CLOSE_GAP then
        return true
    end
    return false
end

-- 목록 창 퀘스트 선택(순수 함수), dik, 2026-09-30
local function PickQuest(active, available, opts)
    if type(opts) ~= "table" then
        return nil
    end
    if opts.turnIn and type(active) == "table" then
        for i = 1, #active do
            local q = active[i]
            if type(q) == "table" and q.id ~= nil and q.isComplete == true and q.repeatable ~= true then
                return "turnIn", q.id
            end
        end
    end
    if opts.accept and type(available) == "table" then
        for i = 1, #available do
            local q = available[i]
            if type(q) == "table" and q.id ~= nil and q.isTrivial ~= true and q.repeatable ~= true
                and q.isIgnored ~= true then
                return "accept", q.id
            end
        end
    end
    return nil
end

-- 보상 처리 판정(순수 함수), dik, 2026-09-30
local function DecideReward(numChoices)
    if not IsNumber(numChoices) or numChoices >= 2 then
        return "manual", nil
    end
    if numChoices == 1 then
        return "take", 1
    end
    return "take", 0
end

-- 자동 줍기 판정(순수 함수), dik, 2026-10-02
local function IsAutoLoot(arg, cvar, toggle)
    if type(arg) == "boolean" then
        return arg
    end
    if type(cvar) == "boolean" and type(toggle) == "boolean" then
        return cvar ~= toggle
    end
    return nil
end

-- 주울 칸 선택(순수 함수), dik, 2026-10-02
local function PlanLoot(slots, ctx, max)
    local picked = {}
    local candidates = 0
    local grouped = type(ctx) == "table" and ctx.grouped == true
    local threshold = type(ctx) == "table" and ctx.threshold or nil
    local limit = 0
    if IsNumber(max) and max >= 1 then
        limit = max
    end
    if type(slots) == "table" then
        for i = 1, #slots do
            local s = slots[i]
            if type(s) == "table" and s.present == true and s.locked ~= true then
                local ok = true
                if grouped and s.kind ~= "money" and s.kind ~= "currency" then
                    ok = IsNumber(s.quality) and IsNumber(threshold) and s.quality < threshold
                end
                if ok then
                    candidates = candidates + 1
                    if #picked < limit then
                        picked[#picked + 1] = s.index
                    end
                end
            end
        end
    end
    return picked, candidates - #picked
end

-- 로그 영역 검증(손상 값 보정), dik, 2026-09-30
local function ValidateArea(area)
    if not IsNumber(area.version) or area.version < 1 then
        area.version = AREA_VERSION
    end
    local log = {}
    if type(area.log) == "table" then
        for i = 1, #area.log do
            local item = area.log[i]
            if type(item) == "table" and LOG_KINDS[item.kind] == true and #log < LOG_MAX then
                log[#log + 1] = item
            end
        end
    end
    area.log = log
end

-- 저장 영역 로드(쓰기 금지 판정 포함), dik, 2026-09-30
local function LoadArea()
    if ns.IsDatabaseNewer() then
        state.readOnly = true
        return
    end
    local area = ns.GetModuleData(MODULE_ID)
    if type(area) ~= "table" then
        return
    end
    if IsNumber(area.version) and area.version > AREA_VERSION then
        state.readOnly = true
        return
    end
    ValidateArea(area)
    state.log = area.log
end

-- 로그 추가·세션 합계 누적·갱신 발행, dik, 2026-09-30
local function AddLog(entry)
    if ns.HasAPI("time") then
        entry.t = time()
    end
    entry.char = ns.GetCurrentCharacterKey()
    table.insert(state.log, 1, entry)
    while #state.log > LOG_MAX do
        table.remove(state.log)
    end
    local totals = state.totals
    if entry.kind == "sell" then
        totals.soldCount = totals.soldCount + (entry.count or 0)
        totals.soldMoney = totals.soldMoney + (entry.money or 0)
    elseif entry.kind == "repair" or entry.kind == "guildRepair" then
        totals.repairMoney = totals.repairMoney + (entry.money or 0)
    elseif entry.kind == "accept" then
        totals.accepted = totals.accepted + 1
    elseif entry.kind == "turnIn" then
        totals.turnedIn = totals.turnedIn + 1
    end
    ns.Fire("CHORES_UPDATED")
end

-- 동작 가드(모든 동작 함수 호출 직전), dik, 2026-09-30
local function CanAct(feature)
    if state.blocked or not Setting(feature) or not state.groups[FEATURE_GROUP[feature]] then
        return false
    end
    if InCombatLockdown() then
        return false
    end
    -- 빠른 줍기 가드 분기 추가, dik, 2026-10-02
    if feature == "fastLoot" then
        local loot = state.loot
        return loot ~= nil and loot.skip == false and loot.calls < LOOT_SLOT_MAX
    end
    if feature == "sellJunk" or feature == "autoRepair" then
        return state.merchantOpen and not state.merchantSkip
    end
    local round = state.round
    if round == nil or round.skip then
        return false
    end
    if round.actions >= QUEST_ROUND_MAX then
        if not round.limitShown then
            round.limitShown = true
            ns.Print(L.MSG_CHORES_QUEST_LIMIT)
        end
        return false
    end
    return true
end

-- 퀘스트 회차 동작 수 증가, dik, 2026-09-30
local function Spend(round)
    round.actions = round.actions + 1
end

-- 회차 NPC 식별자(없음·secret 이면 nil), dik, 2026-09-30
local function ReadNpcGuid()
    if not ns.HasAPI("UnitGUID") then
        return nil
    end
    local guid = UnitGUID("npc")
    if ns.IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    return guid
end

-- 로그용 퀘스트 제목, dik, 2026-09-30
local function ReadTitle()
    if not ns.HasAPI("GetTitleText") then
        return nil
    end
    local title = GetTitleText()
    if ns.IsSecret(title) or type(title) ~= "string" or title == "" then
        return nil
    end
    return title
end

-- 퀘스트 창 이벤트 공통 진입(회차 갱신·Shift 판정), dik, 2026-09-30
-- GetTime 없으면 회차 없음, dik, 2026-09-30
local function EnterQuestEvent()
    if not ns.HasAPI("GetTime") then
        return nil
    end
    local now = GetTime()
    local npc = ReadNpcGuid()
    if IsNewRound(state.round, npc, now) then
        state.round = { npc = npc, skip = false, actions = 0, skipLogged = false }
    end
    local round = state.round
    round.lastEventAt = now
    if IsShiftKeyDown() then
        round.skip = true
    end
    if round.skip then
        if not round.skipLogged then
            round.skipLogged = true
            AddLog({ kind = "skip", text = "quest" })
        end
        return nil
    end
    return round
end

-- 가방 스캔(잡템 후보 수집), dik, 2026-09-30
local function ScanBags()
    local items = {}
    local last = BAG_LAST_DEFAULT
    if IsNumber(NUM_BAG_SLOTS) then
        last = NUM_BAG_SLOTS
    end
    for bag = BAG_FIRST, last do
        local slots = Plain(C_Container.GetContainerNumSlots(bag))
        if IsNumber(slots) then
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if type(info) == "table" then
                    local quality = Plain(info.quality)
                    local price = nil
                    if quality == QUALITY_POOR and info.itemID ~= nil then
                        price = Plain(select(11, C_Item.GetItemInfo(info.itemID)))
                    end
                    items[#items + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID, quality = quality,
                        count = Plain(info.stackCount), locked = Plain(info.isLocked),
                        noValue = Plain(info.hasNoValue), sellPrice = price,
                    }
                end
            end
        end
    end
    return items
end

-- 판매 종료 요약(로그·채팅), dik, 2026-09-30
local function FinishSell(chain)
    if #chain.sold < 1 then
        return
    end
    local count, money = SumSale(chain.sold)
    local left = chain.leftover + (#chain.picked - #chain.sold)
    AddLog({ kind = "sell", count = count, left = left, money = money })
    if Setting("chatSummary") then
        local msg = L.MSG_CHORES_SOLD:format(count, ns.FormatMoney(money))
        if left > 0 then
            msg = msg .. L.MSG_CHORES_SOLD_LEFT:format(left)
        end
        ns.Print(msg)
    end
end

-- 판매 체인 한 칸 처리 후 다음 칸 예약, dik, 2026-09-30
local function SellStep(chain)
    if chain.token ~= state.token then
        FinishSell(chain)
        return
    end
    local entry = chain.picked[chain.index]
    if entry == nil or not CanAct("sellJunk") then
        FinishSell(chain)
        return
    end
    local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if type(info) == "table" and info.itemID == entry.itemID and info.isLocked ~= true then
        C_Container.UseContainerItem(entry.bag, entry.slot)
        chain.sold[#chain.sold + 1] = entry
    end
    chain.index = chain.index + 1
    if chain.index > #chain.picked then
        FinishSell(chain)
        return
    end
    C_Timer.After(SELL_INTERVAL, function()
        SellStep(chain)
    end)
end

-- 잡템 판매 시작(스캔·선택), dik, 2026-09-30
local function StartSell()
    if not Setting("sellJunk") or not state.groups.sell or not CanAct("sellJunk") then
        return
    end
    local picked, leftover = SelectJunk(ScanBags(), SELL_MAX)
    if #picked == 0 then
        return
    end
    SellStep({ token = state.token, picked = picked, leftover = leftover, index = 1, sold = {} })
end

-- 수리 판정 입력 읽기, dik, 2026-09-30
local function ReadRepairState(useGuild, allowGuild)
    local cost, canRepair = GetRepairAllCost()
    local guildAllowed = false
    if allowGuild and state.groups.guild and Plain(IsInGuild()) and Plain(CanGuildBankRepair()) then
        guildAllowed = true
    end
    return {
        merchantCanRepair = Plain(CanMerchantRepair()),
        cost = Plain(cost),
        canRepair = Plain(canRepair),
        money = Plain(GetMoney()),
        useGuild = useGuild,
        guildAllowed = guildAllowed,
    }
end

-- 수리비 부족 처리(채팅·로그), dik, 2026-09-30
local function ReportNoMoney(cost)
    AddLog({ kind = "repairNoMoney", money = cost })
    ns.Print(L.MSG_CHORES_REPAIR_NO_MONEY:format(ns.FormatMoney(cost)))
end

-- 길드 수리 1초 뒤 확인·개인 소지금 대체, dik, 2026-09-30
local function FinishGuildRepair(token, cost)
    if token ~= state.token or not state.merchantOpen then
        return
    end
    local remaining = Plain(GetRepairAllCost())
    if not IsNumber(remaining) then
        return
    end
    if remaining <= 0 then
        AddLog({ kind = "guildRepair", money = cost })
        if Setting("chatSummary") then
            ns.Print(L.MSG_CHORES_GUILD_REPAIRED:format(ns.FormatMoney(cost)))
        end
        return
    end
    local s = ReadRepairState(false, false)
    s.cost = remaining
    local action, need = DecideRepair(s)
    if action == "personal" and not state.personalRepaired then
        if CanAct("autoRepair") then
            state.personalRepaired = true
            RepairAllItems(false)
            AddLog({ kind = "repair", money = need, text = "guildFallback" })
            if Setting("chatSummary") then
                ns.Print(L.MSG_CHORES_GUILD_FALLBACK:format(ns.FormatMoney(need)))
            end
        end
    elseif action == "noMoney" then
        if CanAct("autoRepair") then
            ReportNoMoney(need)
        end
    end
end

-- 상점 수리 처리, dik, 2026-09-30
local function StartRepair()
    if not Setting("autoRepair") or not state.groups.repair then
        return
    end
    local action, cost = DecideRepair(ReadRepairState(Setting("guildRepair"), true))
    if action == "personal" then
        if CanAct("autoRepair") then
            state.personalRepaired = true
            RepairAllItems(false)
            AddLog({ kind = "repair", money = cost })
            if Setting("chatSummary") then
                ns.Print(L.MSG_CHORES_REPAIRED:format(ns.FormatMoney(cost)))
            end
        end
    elseif action == "guild" then
        if not state.guildRepaired and CanAct("autoRepair") then
            state.guildRepaired = true
            local token = state.token
            RepairAllItems(true)
            C_Timer.After(GUILD_CHECK_DELAY, function()
                FinishGuildRepair(token, cost)
            end)
        end
    elseif action == "noMoney" then
        if CanAct("autoRepair") then
            ReportNoMoney(cost)
        end
    end
end

-- 상점 열림 처리(회차 시작), dik, 2026-09-30
local function OnMerchantShow()
    state.merchantOpen = true
    state.merchantSkip = IsShiftKeyDown() and true or false
    state.personalRepaired = false
    state.guildRepaired = false
    state.token = state.token + 1
    if state.merchantSkip then
        AddLog({ kind = "skip", text = "merchant" })
        return
    end
    StartRepair()
    StartSell()
end

-- 목록 창 원소 변환(대화 목록), dik, 2026-09-30
local function ConvertGossip(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do
            local q = list[i]
            if type(q) == "table" then
                out[#out + 1] = {
                    id = q.questID, isComplete = q.isComplete, isTrivial = q.isTrivial,
                    repeatable = q.repeatable, isIgnored = q.isIgnored,
                }
            end
        end
    end
    return out
end

-- 대화 목록 창 처리, dik, 2026-09-30
local function OnGossipShow()
    -- 그룹 검사 전 회차·Shift 판정, dik, 2026-09-30
    local round = EnterQuestEvent()
    if round == nil or not state.groups.gossip then
        return
    end
    local opts = {
        turnIn = Setting("autoTurnIn") and state.groups.turnIn,
        accept = Setting("autoAccept") and state.groups.accept,
    }
    if not opts.turnIn and not opts.accept then
        return
    end
    local active = ConvertGossip(C_GossipInfo.GetActiveQuests())
    local available = ConvertGossip(C_GossipInfo.GetAvailableQuests())
    local kind, id = PickQuest(active, available, opts)
    if kind == "turnIn" then
        if CanAct("autoTurnIn") then
            Spend(round)
            C_GossipInfo.SelectActiveQuest(id)
        end
    elseif kind == "accept" then
        if CanAct("autoAccept") then
            Spend(round)
            C_GossipInfo.SelectAvailableQuest(id)
        end
    end
end

-- 인사 목록 창 처리, dik, 2026-09-30
local function OnQuestGreeting()
    -- 그룹 검사 전 회차·Shift 판정, dik, 2026-09-30
    local round = EnterQuestEvent()
    if round == nil or not state.groups.greeting then
        return
    end
    local opts = {
        turnIn = Setting("autoTurnIn") and state.groups.turnIn,
        accept = Setting("autoAccept") and state.groups.accept,
    }
    if not opts.turnIn and not opts.accept then
        return
    end
    local active = {}
    local numActive = Plain(GetNumActiveQuests())
    if IsNumber(numActive) then
        for i = 1, numActive do
            local _, isComplete = GetActiveTitle(i)
            active[#active + 1] = { id = i, isComplete = Plain(isComplete) }
        end
    end
    local available = {}
    local numAvailable = Plain(GetNumAvailableQuests())
    if IsNumber(numAvailable) then
        for i = 1, numAvailable do
            local isTrivial, _, isRepeatable = GetAvailableQuestInfo(i)
            available[#available + 1] = { id = i, isTrivial = Plain(isTrivial), repeatable = Plain(isRepeatable) }
        end
    end
    local kind, id = PickQuest(active, available, opts)
    if kind == "turnIn" then
        if CanAct("autoTurnIn") then
            Spend(round)
            SelectActiveQuest(id)
        end
    elseif kind == "accept" then
        if CanAct("autoAccept") then
            Spend(round)
            SelectAvailableQuest(id)
        end
    end
end

-- 퀘스트 수락 창 처리, dik, 2026-09-30
local function OnQuestDetail(startItemID)
    -- 그룹 검사 전 회차·Shift 판정, dik, 2026-09-30
    local round = EnterQuestEvent()
    if round == nil or not state.groups.accept then
        return
    end
    if ns.IsSecret(startItemID) or (startItemID ~= nil and startItemID ~= 0) then
        return
    end
    local isPlayer = UnitIsPlayer("npc")
    -- nil 반환을 false 로 보도록 판정 변경, dik, 2026-09-30
    if not Plain(UnitExists("npc")) or ns.IsSecret(isPlayer) or (isPlayer ~= nil and isPlayer ~= false) then
        return
    end
    local autoAccept = nil
    if ns.HasAPI("QuestGetAutoAccept") then
        autoAccept = QuestGetAutoAccept()
    end
    if ns.IsSecret(autoAccept) or (autoAccept ~= nil and autoAccept ~= false) then
        return
    end
    if CanAct("autoAccept") then
        Spend(round)
        local title = ReadTitle()
        AcceptQuest()
        AddLog({ kind = "accept", text = title })
    end
end

-- 퀘스트 진행 창 처리(반납 완료 누르기), dik, 2026-09-30
local function OnQuestProgress()
    -- 그룹 검사 전 회차·Shift 판정, dik, 2026-09-30
    local round = EnterQuestEvent()
    if round == nil or not state.groups.turnIn then
        return
    end
    if not Plain(IsQuestCompletable()) then
        return
    end
    local money = GetQuestMoneyToGet()
    if money ~= nil and (ns.IsSecret(money) or not IsNumber(money) or money > 0) then
        return
    end
    if CanAct("autoTurnIn") then
        Spend(round)
        CompleteQuest()
    end
end

-- 퀘스트 보상 창 처리(보상 받기), dik, 2026-09-30
local function OnQuestComplete()
    -- 그룹 검사 전 회차·Shift 판정, dik, 2026-09-30
    local round = EnterQuestEvent()
    if round == nil or not state.groups.turnIn then
        return
    end
    local action, index = DecideReward(Plain(GetNumQuestChoices()))
    local title = ReadTitle()
    if action == "take" then
        if CanAct("autoTurnIn") then
            Spend(round)
            GetQuestReward(index)
            AddLog({ kind = "turnIn", text = title })
        end
    elseif CanAct("autoTurnIn") then
        round.rewardShown = round.rewardShown or {}
        local key = title or ""
        if not round.rewardShown[key] then
            round.rewardShown[key] = true
            ns.Print(L.MSG_CHORES_CHOOSE_REWARD:format(title or L.VALUE_UNKNOWN))
            AddLog({ kind = "reward", text = title })
        end
    end
end

-- 자동 줍기 CVar 읽기(읽기 전용), dik, 2026-10-02
local function ReadAutoLootCvar()
    local value = nil
    if ns.HasAPI("C_CVar.GetCVarBool") then
        value = C_CVar.GetCVarBool(AUTOLOOT_CVAR)
    elseif ns.HasAPI("GetCVarBool") then
        value = GetCVarBool(AUTOLOOT_CVAR)
    end
    value = Plain(value)
    if type(value) ~= "boolean" then
        return nil
    end
    return value
end

-- 자동 줍기 반전 키 읽기, dik, 2026-10-02
local function ReadAutoLootToggle()
    if not ns.HasAPI("IsModifiedClick") then
        return nil
    end
    local value = Plain(IsModifiedClick(AUTOLOOT_TOGGLE))
    if type(value) ~= "boolean" then
        return nil
    end
    return value
end

-- 칸 종류 문자열 변환, dik, 2026-10-02
local function ReadSlotKind(index)
    if not ns.HasAPI("GetLootSlotType") then
        return nil
    end
    local value = Plain(GetLootSlotType(index))
    local types = Enum and Enum.LootSlotType
    local itemType, moneyType, currencyType = 1, 2, 3
    if type(types) == "table" then
        itemType = types.Item or itemType
        moneyType = types.Money or moneyType
        currencyType = types.Currency or currencyType
    end
    if value == moneyType then
        return "money"
    elseif value == currencyType then
        return "currency"
    elseif value == itemType then
        return "item"
    end
    return nil
end

-- 전리품 칸 스캔, dik, 2026-10-02
local function ScanLoot()
    local slots = {}
    local count = Plain(GetNumLootItems())
    if not IsNumber(count) then
        count = 0
    end
    for i = 1, count do
        local icon, _, _, _, quality, locked = GetLootSlotInfo(i)
        slots[#slots + 1] = {
            index = i, present = Plain(icon) ~= nil, quality = Plain(quality),
            locked = Plain(locked), kind = ReadSlotKind(i),
        }
    end
    return slots
end

-- 무리 판정 입력 읽기, dik, 2026-10-02
local function ReadLootContext()
    local grouped = true
    if ns.HasAPI("IsInGroup") then
        grouped = Plain(IsInGroup()) == true
    end
    local threshold = LOOT_THRESHOLD_DEFAULT
    if ns.HasAPI("GetLootThreshold") then
        local value = Plain(GetLootThreshold())
        if IsNumber(value) and value >= 0 and value <= 7 then
            threshold = value
        end
    end
    return { grouped = grouped, threshold = threshold }
end

-- 전리품 창 열림 처리(회차 판정·일괄 줍기), dik, 2026-10-02
local function OnLootOpen(autoArg)
    if state.loot == nil then
        state.loot = { skip = IsShiftKeyDown() == true, calls = 0, passes = 0, done = false }
    end
    local loot = state.loot
    if loot.skip or loot.done then
        return
    end
    if not state.groups.loot or not Setting("fastLoot") then
        return
    end
    loot.passes = loot.passes + 1
    local arg = Plain(autoArg)
    local cvar, toggle = nil, nil
    if type(arg) ~= "boolean" then
        cvar = ReadAutoLootCvar()
        toggle = ReadAutoLootToggle()
    end
    if IsAutoLoot(arg, cvar, toggle) ~= true then
        loot.done = true
        return
    end
    local slots = ScanLoot()
    local picked = PlanLoot(slots, ReadLootContext(), LOOT_SLOT_MAX - loot.calls)
    for i = 1, #picked do
        if CanAct("fastLoot") then
            loot.calls = loot.calls + 1
            LootSlot(picked[i])
        else
            break
        end
    end
    local seen = 0
    for i = 1, #slots do
        if slots[i].present then
            seen = seen + 1
        end
    end
    if seen >= 1 or loot.passes >= LOOT_PASS_MAX then
        loot.done = true
    end
end

-- 창 닫힘 시각 기록, dik, 2026-09-30
local function OnWindowClosed()
    if state.round ~= nil and ns.HasAPI("GetTime") then
        state.round.lastCloseAt = GetTime()
    end
end

-- 차단 감지 처리(이번 접속 전부 중지), dik, 2026-09-30
-- 코어 차단 통지(정규화 함수 이름) 수신으로 변경, dik, 2026-10-02
local function OnActionBlocked(funcName)
    if state.blocked then
        return
    end
    state.blocked = true
    if type(funcName) == "string" then
        state.blockedFunc = funcName
    end
    state.token = state.token + 1
    ns.Print(L.MSG_CHORES_BLOCKED:format(state.blockedFunc or L.VALUE_UNKNOWN))
    AddLog({ kind = "blocked", text = state.blockedFunc })
end

-- 이벤트 분배, dik, 2026-09-30
-- 차단 이벤트 분기 코어 이관, dik, 2026-10-02
local function OnEvent(_, event, arg1)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        state.merchantOpen = false
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "QUEST_GREETING" then
        OnQuestGreeting()
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail(arg1)
    elseif event == "QUEST_PROGRESS" then
        OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
        OnWindowClosed()
    -- 전리품 이벤트 분기 추가, dik, 2026-10-02
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootOpen(arg1)
    elseif event == "LOOT_CLOSED" then
        state.loot = nil
    end
end

-- API 그룹 판정·이벤트 프레임 생성·등록·미지원 안내, dik, 2026-09-30
local function InitializeChores()
    LoadArea()
    local missing = {}
    local seen = {}
    for i = 1, #API_GROUP_ORDER do
        local name = API_GROUP_ORDER[i]
        local lost = ns.GetMissingAPIs(API_GROUPS[name])
        state.groups[name] = #lost == 0
        for j = 1, #lost do
            if not seen[lost[j]] then
                seen[lost[j]] = true
                missing[#missing + 1] = lost[j]
            end
        end
    end
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    -- 줍기 열림 실패 카운터 추가, dik, 2026-10-02
    local lootOpenFailed = 0
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        local registered = pcall(frame.RegisterEvent, frame, name)
        if not registered then
            missing[#missing + 1] = name
            -- 줍기 열림 이벤트 실패 집계, dik, 2026-10-02
            if name == "LOOT_READY" or name == "LOOT_OPENED" then
                lootOpenFailed = lootOpenFailed + 1
            end
            local groups = EVENT_GROUPS[name]
            if groups ~= nil then
                for j = 1, #groups do
                    state.groups[groups[j]] = false
                end
            end
        end
    end
    -- 줍기 열림 이벤트 둘 다 실패 시 그룹 끔, dik, 2026-10-02
    if lootOpenFailed >= 2 then
        state.groups.loot = false
    end
    -- 동작 차단 공통 처리 구독(WFA-040), dik, 2026-10-02
    ns.ActionBlock.Register(MODULE_ID, {
        "UseContainerItem", "RepairAllItems", "SelectActiveQuest", "SelectAvailableQuest",
        "AcceptQuest", "CompleteQuest", "GetQuestReward", "LootSlot",
    }, OnActionBlocked)
    state.missing = missing
    if #missing > 0 then
        ns.Print(L.MSG_CHORES_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
end

-- 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_CHORES,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_CHORES_DESC,
    category = "feature",
    order = 30,
    requires = { "IsShiftKeyDown", "InCombatLockdown" },
    settings = {
        { key = "sellJunk", type = "checkbox", label = L.SETTING_CHORES_SELL,
          tooltip = L.SETTING_CHORES_SELL_TIP, default = true },
        { key = "autoRepair", type = "checkbox", label = L.SETTING_CHORES_REPAIR,
          tooltip = L.SETTING_CHORES_REPAIR_TIP, default = true },
        { key = "guildRepair", type = "checkbox", label = L.SETTING_CHORES_GUILD_REPAIR,
          tooltip = L.SETTING_CHORES_GUILD_REPAIR_TIP, default = false },
        { key = "autoAccept", type = "checkbox", label = L.SETTING_CHORES_ACCEPT,
          tooltip = L.SETTING_CHORES_ACCEPT_TIP, default = true },
        { key = "autoTurnIn", type = "checkbox", label = L.SETTING_CHORES_TURNIN,
          tooltip = L.SETTING_CHORES_TURNIN_TIP, default = true },
        -- 빠른 줍기 설정 추가, dik, 2026-10-02
        { key = "fastLoot", type = "checkbox", label = L.SETTING_CHORES_LOOT,
          tooltip = L.SETTING_CHORES_LOOT_TIP, default = true },
        { key = "chatSummary", type = "checkbox", label = L.SETTING_CHORES_CHAT,
          tooltip = L.SETTING_CHORES_CHAT_TIP, default = true },
    },
    OnInitialize = function()
        InitializeChores()
    end,
})

ns.Chores = {}
ns.Chores.SelectJunk = SelectJunk
ns.Chores.SumSale = SumSale
ns.Chores.DecideRepair = DecideRepair
ns.Chores.PickQuest = PickQuest
ns.Chores.DecideReward = DecideReward
ns.Chores.IsNewRound = IsNewRound
-- 순수 함수 공개 추가, dik, 2026-10-02
ns.Chores.IsAutoLoot = IsAutoLoot
ns.Chores.PlanLoot = PlanLoot

-- 로그 복사본(최신 1번), dik, 2026-09-30
function ns.Chores.GetLog()
    local list = {}
    for i = 1, #state.log do
        local copy = {}
        for k, v in pairs(state.log[i]) do
            copy[k] = v
        end
        list[i] = copy
    end
    return list
end

-- 이번 접속 합계(새 테이블), dik, 2026-09-30
function ns.Chores.GetSessionTotals()
    local totals = state.totals
    return {
        soldCount = totals.soldCount, soldMoney = totals.soldMoney, repairMoney = totals.repairMoney,
        accepted = totals.accepted, turnedIn = totals.turnedIn,
    }
end

-- 상태 스냅샷(새 테이블), dik, 2026-09-30
function ns.Chores.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    return {
        blocked = state.blocked,
        blockedFunc = state.blockedFunc,
        missing = missing,
        readOnly = state.readOnly,
    }
end
