-- 보유량 색인 모듈 등록·스캔·저장·조회·툴팁 공급자, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "inventory"
local AREA_VERSION = 1
local BAGS_MAX = 300
local BANK_MAX = 700
local MAIL_MAX = 300
local ITEM_NAME_MAX = 5000
local SCAN_DELAY = 0.5
local DISPLAY_MAX = 200
local BANK_TAB_MAX = 10
local BANK_BAG_MAX = 10
local DEFAULT_BAG_SLOTS = 4
local DEFAULT_BANK_BAGS = 7
local DEFAULT_ATTACHMENTS = 16
local PROVIDER_ORDER = 50
local DEFAULT_TOOLTIP_CHARS = 5
local TOOLTIP_CHARS_MIN = 1
local TOOLTIP_CHARS_MAX = 10

local EVENT_ORDER = {
    "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MAIL_SHOW",
    "MAIL_INBOX_UPDATE",
    "MAIL_CLOSED",
}

local MAIL_APIS = { "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem" }

local LOCATIONS = { "bags", "bank", "mail" }

local state = {
    ready = false,
    readOnly = false,
    secret = false,
    characterKey = nil,
    area = nil,
    bankEnabled = false,
    mailEnabled = false,
    bankOpen = false,
    mailOpen = false,
    bankType = nil,
    mailType = nil,
    pending = {},
    timerPending = false,
    missing = {},
    memNames = {},
    memCount = 0,
    frame = nil,
}

ns.Inventory = {}

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 양의 정수 판정, dik, 2026-10-01
local function IsPosInt(v)
    return IsNumber(v) and v > 0 and math.floor(v) == v
end

-- 수량 판정(유한한 number 1 이상), dik, 2026-10-01
local function IsQty(v)
    return IsNumber(v) and v >= 1
end

-- 인자 중 secret 존재 여부, dik, 2026-10-01
local function AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- 스캔 대상 가방 목록(순수 함수), dik, 2026-10-01
function ns.Inventory.GetBagContainers(enum, numBagSlots)
    local n = DEFAULT_BAG_SLOTS
    if IsNumber(numBagSlots) then
        n = numBagSlots
    end
    local list = {}
    local present = {}
    for bag = 0, n do
        list[#list + 1] = bag
        present[bag] = true
    end
    if type(enum) == "table" and IsNumber(enum.ReagentBag) and not present[enum.ReagentBag] then
        list[#list + 1] = enum.ReagentBag
    end
    return list
end

-- 스캔 대상 은행 목록(순수 함수), dik, 2026-10-01
function ns.Inventory.GetBankContainers(enum, numBagSlots, numBankBags)
    local list = {}
    local isTable = type(enum) == "table"
    if isTable and IsNumber(enum.CharacterBankTab_1) then
        for i = 1, BANK_TAB_MAX do
            local value = enum["CharacterBankTab_" .. i]
            if not IsNumber(value) then
                break
            end
            list[#list + 1] = value
        end
    else
        if isTable and IsNumber(enum.Bank) then
            list[#list + 1] = enum.Bank
        else
            list[#list + 1] = -1
        end
        if isTable and IsNumber(enum.BankBag_1) then
            for i = 1, BANK_BAG_MAX do
                local value = enum["BankBag_" .. i]
                if not IsNumber(value) then
                    break
                end
                list[#list + 1] = value
            end
        else
            local bagSlots = DEFAULT_BAG_SLOTS
            if IsNumber(numBagSlots) then
                bagSlots = numBagSlots
            end
            local count = DEFAULT_BANK_BAGS
            if IsNumber(numBankBags) then
                count = numBankBags
            end
            for i = 1, count do
                list[#list + 1] = bagSlots + i
            end
        end
    end
    if isTable and IsNumber(enum.Reagentbank) then
        list[#list + 1] = enum.Reagentbank
    end
    return list
end

-- 합산(순수 함수), dik, 2026-10-01
function ns.Inventory.Accumulate(entries, max)
    local map = {}
    local truncated = false
    if type(entries) ~= "table" then
        return map, truncated
    end
    if not IsNumber(max) then
        max = math.huge
    end
    local unique = 0
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" then
            local id = entry[1]
            local count = entry[2]
            if IsPosInt(id) and IsQty(count) then
                count = math.floor(count)
                if map[id] ~= nil then
                    map[id] = map[id] + count
                elseif unique < max then
                    map[id] = count
                    unique = unique + 1
                else
                    truncated = true
                end
            end
        end
    end
    return map, truncated
end

-- 링크에서 아이템 이름 추출(순수 함수), dik, 2026-10-01
function ns.Inventory.ParseLinkName(link)
    if type(link) ~= "string" then
        return nil
    end
    local name = link:match("|h%[(.-)%]|h")
    if name == nil or name == "" then
        return nil
    end
    return name
end

-- 검색어 일치 판정(순수 함수), dik, 2026-10-01
function ns.Inventory.MatchQuery(name, itemId, query)
    local q = ""
    if type(query) == "string" then
        q = strtrim(query)
    end
    if q == "" then
        return true
    end
    if q:find("^%d+$") then
        return tonumber(q) == itemId
    end
    if type(name) ~= "string" then
        return false
    end
    return string.lower(name):find(string.lower(q), 1, true) ~= nil
end

-- 툴팁 위치 문자열(순수), dik, 2026-10-01
local function BuildLocationText(item)
    local parts = {}
    if item.bags > 0 then
        parts[#parts + 1] = L.INV_LOC_BAGS:format(ns.FormatNumber(item.bags))
    end
    if item.bank > 0 then
        parts[#parts + 1] = L.INV_LOC_BANK:format(ns.FormatNumber(item.bank))
    end
    if item.mail > 0 then
        parts[#parts + 1] = L.INV_LOC_MAIL:format(ns.FormatNumber(item.mail))
    end
    return table.concat(parts, L.INV_LOC_SEP)
end

-- 툴팁 줄 조립(순수 함수), dik, 2026-10-01
function ns.Inventory.BuildTooltipLines(counts, maxChars)
    if type(counts) ~= "table" or not IsNumber(counts.total) or counts.total <= 0 then
        return nil
    end
    local limit = DEFAULT_TOOLTIP_CHARS
    if IsNumber(maxChars) then
        limit = math.floor(maxChars)
    end
    limit = math.max(TOOLTIP_CHARS_MIN, math.min(TOOLTIP_CHARS_MAX, limit))
    local lines = {
        { left = L.INV_TIP_TOTAL, right = ns.FormatNumber(counts.total),
            leftToken = "ACCENT", rightToken = "ACCENT" },
    }
    local chars = counts.chars
    if type(chars) ~= "table" then
        return lines
    end
    for i = 1, math.min(#chars, limit) do
        local item = chars[i]
        local line = { left = item.displayName, right = BuildLocationText(item), rightToken = "TEXT" }
        local color = nil
        if type(item.classFile) == "string" and type(RAID_CLASS_COLORS) == "table" then
            color = RAID_CLASS_COLORS[item.classFile]
        end
        if type(color) == "table" and IsNumber(color.r) and IsNumber(color.g) and IsNumber(color.b) then
            line.leftColor = { r = color.r, g = color.g, b = color.b }
        else
            line.leftToken = "TEXT"
        end
        lines[#lines + 1] = line
    end
    if #chars > limit then
        local rest = 0
        for i = limit + 1, #chars do
            rest = rest + chars[i].total
        end
        lines[#lines + 1] = { left = L.INV_TIP_MORE:format(#chars - limit), right = ns.FormatNumber(rest),
            leftToken = "TEXT_DIM", rightToken = "TEXT_DIM" }
    end
    return lines
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

-- 캐릭터 영역 읽기(수정 없음, version 이 새거면 nil), dik, 2026-10-01
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

-- 캐릭터 표시 이름·직업 표(이름 유일할 때만 name), dik, 2026-10-01
local function BuildCharMeta(keys)
    local nameCount = {}
    local infos = {}
    for i = 1, #keys do
        local info = ns.GetCharacterInfo(keys[i])
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            infos[keys[i]] = info
            nameCount[info.name] = (nameCount[info.name] or 0) + 1
        end
    end
    local names = {}
    local classes = {}
    for i = 1, #keys do
        local key = keys[i]
        local info = infos[key]
        names[key] = key
        if info ~= nil then
            if nameCount[info.name] == 1 then
                names[key] = info.name
            end
            if type(info.classFile) == "string" then
                classes[key] = info.classFile
            end
        end
    end
    return names, classes
end

-- 캐시에서 이름·품질 읽기(메모리 표 → 저장 캐시), dik, 2026-10-01
function ns.Inventory.GetItemName(itemId)
    if not IsPosInt(itemId) then
        return nil
    end
    local mem = state.memNames[itemId]
    if mem ~= nil then
        return mem.name, mem.quality
    end
    local db = ns.db
    if type(db) ~= "table" or type(db.modules) ~= "table" then
        return nil
    end
    local common = db.modules[MODULE_ID]
    if type(common) ~= "table" or type(common.items) ~= "table" then
        return nil
    end
    local rec = common.items[itemId]
    if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then
        local quality = nil
        if IsNumber(rec.quality) then
            quality = rec.quality
        end
        return rec.name, quality
    end
    return nil
end

-- 캐릭터별 보유 수 조회, dik, 2026-10-01
function ns.Inventory.GetItemCounts(itemId)
    if not IsPosInt(itemId) then
        return nil
    end
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local names, classes = BuildCharMeta(keys)
    local result = { total = 0, bags = 0, bank = 0, mail = 0, chars = {} }
    for i = 1, #keys do
        local key = keys[i]
        local area = GetReadArea(key, currentKey)
        if area ~= nil then
            local item = { key = key, displayName = names[key], classFile = classes[key],
                bags = 0, bank = 0, mail = 0, total = 0 }
            for j = 1, #LOCATIONS do
                local loc = LOCATIONS[j]
                local map = area[loc]
                if type(map) == "table" and IsQty(map[itemId]) then
                    item[loc] = map[itemId]
                    item.total = item.total + map[itemId]
                end
            end
            if item.total > 0 then
                result.bags = result.bags + item.bags
                result.bank = result.bank + item.bank
                result.mail = result.mail + item.mail
                result.total = result.total + item.total
                result.chars[#result.chars + 1] = item
            end
        end
    end
    table.sort(result.chars, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.key < b.key
    end)
    return result
end

-- 페이지 표 행(검색·필터·정렬·상한), dik, 2026-10-01
function ns.Inventory.BuildRows(filterKey, query)
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local targets = keys
    if filterKey ~= "all" then
        for i = 1, #keys do
            if keys[i] == filterKey then
                targets = { filterKey }
                break
            end
        end
    end
    local agg = {}
    for i = 1, #targets do
        local area = GetReadArea(targets[i], currentKey)
        if area ~= nil then
            local touched = {}
            for j = 1, #LOCATIONS do
                local loc = LOCATIONS[j]
                local map = area[loc]
                if type(map) == "table" then
                    for id, qty in pairs(map) do
                        if IsPosInt(id) and IsQty(qty) then
                            local item = agg[id]
                            if item == nil then
                                item = { bags = 0, bank = 0, mail = 0, total = 0, chars = 0 }
                                agg[id] = item
                            end
                            item[loc] = item[loc] + qty
                            item.total = item.total + qty
                            if not touched[id] then
                                touched[id] = true
                                item.chars = item.chars + 1
                            end
                        end
                    end
                end
            end
        end
    end
    local rows = {}
    for id, item in pairs(agg) do
        local name, quality = ns.Inventory.GetItemName(id)
        if ns.Inventory.MatchQuery(name, id, query) then
            if name == nil then
                name = L.INV_ITEM_UNKNOWN:format(id)
            end
            rows[#rows + 1] = { id = tostring(id), itemId = id, name = name, quality = quality,
                total = item.total, bags = item.bags, bank = item.bank, mail = item.mail, chars = item.chars }
        end
    end
    local matchCount = #rows
    table.sort(rows, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.itemId < b.itemId
    end)
    for i = #rows, DISPLAY_MAX + 1, -1 do
        rows[i] = nil
    end
    return rows, matchCount
end

-- 요약(기록 캐릭터 수·저장 항목 수·아이템 종 수), dik, 2026-10-01
function ns.Inventory.GetStats()
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    local stats = { chars = 0, entries = 0, items = 0 }
    local unique = {}
    for i = 1, #keys do
        local area = GetReadArea(keys[i], currentKey)
        if area ~= nil then
            if IsNumber(area.bagsAt) or IsNumber(area.bankAt) or IsNumber(area.mailAt) then
                stats.chars = stats.chars + 1
            end
            for j = 1, #LOCATIONS do
                local map = area[LOCATIONS[j]]
                if type(map) == "table" then
                    for id, qty in pairs(map) do
                        if IsPosInt(id) and IsQty(qty) then
                            stats.entries = stats.entries + 1
                            if not unique[id] then
                                unique[id] = true
                                stats.items = stats.items + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return stats
end

-- 위치별 갱신 시각·잘림 조회, dik, 2026-10-01
function ns.Inventory.GetScanInfo(key)
    local currentKey = ns.GetCurrentCharacterKey()
    if key == nil then
        key = currentKey
    end
    if key == nil then
        return nil
    end
    local area = GetReadArea(key, currentKey)
    if area == nil then
        return nil
    end
    local info = { truncated = {}, mailPartial = area.mailPartial == true }
    for j = 1, #LOCATIONS do
        local loc = LOCATIONS[j]
        if IsNumber(area[loc .. "At"]) then
            info[loc .. "At"] = area[loc .. "At"]
        end
        if type(area.truncated) == "table" and area.truncated[loc] == true then
            info.truncated[loc] = true
        end
    end
    return info
end

-- 상태 조회(없는 API·이벤트 이름 복사본), dik, 2026-10-01
function ns.Inventory.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    return {
        ready = state.ready,
        readOnly = state.readOnly,
        secret = state.secret,
        bankEnabled = state.bankEnabled,
        mailEnabled = state.mailEnabled,
        bankOpen = state.bankOpen,
        mailOpen = state.mailOpen,
        missing = missing,
    }
end

-- 드롭다운 항목(전체 + 캐릭터별), dik, 2026-10-01
function ns.Inventory.GetFilterItems()
    local keys = ns.GetCharacterKeys()
    local names = BuildCharMeta(keys)
    local items = { { value = "all", text = L.INV_ALL_CHARS } }
    for i = 1, #keys do
        items[#items + 1] = { value = keys[i], text = names[keys[i]] }
    end
    return items
end

-- 이름 캐시 저장소(쓸 수 없으면 nil), dik, 2026-10-01
local function GetNameStore()
    if state.readOnly or ns.IsDatabaseNewer() then
        return nil
    end
    local common = ns.GetModuleData(MODULE_ID)
    if type(common) ~= "table" then
        return nil
    end
    if IsNumber(common.version) and common.version > AREA_VERSION then
        return nil
    end
    if not IsNumber(common.version) or common.version < 1 then
        common.version = AREA_VERSION
    end
    if type(common.items) ~= "table" then
        common.items = {}
    end
    return common
end

-- 표의 키 수, dik, 2026-10-01
local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- 이름 캐시 반영(저장소 또는 세션 메모리), dik, 2026-10-01
local function CommitNames(names)
    if next(names) == nil then
        return
    end
    local store = GetNameStore()
    local count = nil
    for id, rec in pairs(names) do
        if store ~= nil then
            local existing = store.items[id]
            if type(existing) == "table" then
                if existing.name ~= rec.name or existing.quality ~= rec.quality then
                    store.items[id] = { name = rec.name, quality = rec.quality }
                end
            else
                if count == nil then
                    count = CountKeys(store.items)
                end
                if count < ITEM_NAME_MAX then
                    store.items[id] = { name = rec.name, quality = rec.quality }
                    count = count + 1
                end
            end
        else
            if state.memNames[id] ~= nil then
                state.memNames[id] = { name = rec.name, quality = rec.quality }
            elseif state.memCount < ITEM_NAME_MAX then
                state.memNames[id] = { name = rec.name, quality = rec.quality }
                state.memCount = state.memCount + 1
            end
        end
    end
end

-- 이름 캐시 정리(어느 캐릭터도 없는 id 삭제), dik, 2026-10-01
local function PruneNames()
    if state.readOnly then
        return
    end
    local store = GetNameStore()
    if store == nil then
        return
    end
    local used = {}
    local keys = ns.GetCharacterKeys()
    local currentKey = ns.GetCurrentCharacterKey()
    for i = 1, #keys do
        local area = GetReadArea(keys[i], currentKey)
        if area ~= nil then
            for j = 1, #LOCATIONS do
                local map = area[LOCATIONS[j]]
                if type(map) == "table" then
                    for id in pairs(map) do
                        used[id] = true
                    end
                end
            end
        end
    end
    for id in pairs(store.items) do
        if not used[id] then
            store.items[id] = nil
        end
    end
end

-- 위치 맵 검증(잘못된 항목 제거), dik, 2026-10-01
local function CleanMap(map)
    for id, qty in pairs(map) do
        if not IsPosInt(id) or not IsQty(qty) then
            map[id] = nil
        end
    end
end

-- 저장 영역 검증(손상 값 보정), dik, 2026-10-01
local function ValidateStore(store)
    if not IsNumber(store.version) or store.version < 1 then
        store.version = AREA_VERSION
    end
    for i = 1, #LOCATIONS do
        local loc = LOCATIONS[i]
        if type(store[loc]) ~= "table" then
            store[loc] = {}
        else
            CleanMap(store[loc])
        end
        if not IsNumber(store[loc .. "At"]) then
            store[loc .. "At"] = nil
        end
    end
    if type(store.truncated) ~= "table" then
        store.truncated = nil
    end
    if store.mailPartial ~= true then
        store.mailPartial = nil
    end
end

-- 컨테이너 목록 수집(entries·names·상태), dik, 2026-10-01
local function CollectContainers(list, requireFirst)
    local entries = {}
    local names = {}
    local total = 0
    local firstSlots = 0
    for index = 1, #list do
        local bag = list[index]
        local slots = C_Container.GetContainerNumSlots(bag)
        if ns.IsSecret(slots) then
            return nil, nil, "secret"
        end
        if not IsNumber(slots) then
            slots = 0
        end
        if index == 1 then
            firstSlots = slots
        end
        total = total + slots
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if ns.IsSecret(info) then
                return nil, nil, "secret"
            end
            if type(info) == "table" then
                local itemId = info.itemID
                local count = info.stackCount
                local link = info.hyperlink
                local quality = info.quality
                if AnySecret(itemId, count, link) then
                    return nil, nil, "secret"
                end
                entries[#entries + 1] = { itemId, count }
                if IsPosInt(itemId) and type(link) == "string" then
                    local name = ns.Inventory.ParseLinkName(link)
                    if name ~= nil then
                        if ns.IsSecret(quality) or not IsNumber(quality) then
                            quality = nil
                        end
                        names[itemId] = { name = name, quality = quality }
                    end
                end
            end
        end
    end
    if requireFirst then
        if firstSlots <= 0 then
            return nil, nil, "invalid"
        end
    elseif total <= 0 then
        return nil, nil, "invalid"
    end
    return entries, names, "ok"
end

-- 가방 스캔 대상 목록, dik, 2026-10-01
local function GetBagList()
    local enum = nil
    if ns.HasAPI("Enum.BagIndex") then
        enum = Enum.BagIndex
    end
    local slots = nil
    if ns.HasAPI("NUM_BAG_SLOTS") then
        slots = NUM_BAG_SLOTS
    end
    return ns.Inventory.GetBagContainers(enum, slots)
end

-- 은행 스캔 대상 목록, dik, 2026-10-01
local function GetBankList()
    local enum = nil
    if ns.HasAPI("Enum.BagIndex") then
        enum = Enum.BagIndex
    end
    local slots = nil
    if ns.HasAPI("NUM_BAG_SLOTS") then
        slots = NUM_BAG_SLOTS
    end
    local bankBags = nil
    if ns.HasAPI("NUM_BANKBAGSLOTS") then
        bankBags = NUM_BANKBAGSLOTS
    end
    return ns.Inventory.GetBankContainers(enum, slots, bankBags)
end

-- 우편 첨부 반복 상한, dik, 2026-10-01
local function GetAttachmentMax()
    if ns.HasAPI("ATTACHMENTS_MAX_RECEIVE") and IsNumber(ATTACHMENTS_MAX_RECEIVE)
        and ATTACHMENTS_MAX_RECEIVE >= 1 then
        return math.floor(ATTACHMENTS_MAX_RECEIVE)
    end
    return DEFAULT_ATTACHMENTS
end

-- 첨부 1칸 읽기(secret 이면 nil, true), dik, 2026-10-01
local function ReadAttachment(mailIndex, attachIndex)
    local r = { GetInboxItem(mailIndex, attachIndex) }
    local name, itemId, count, quality = r[1], r[2], r[4], r[5]
    if AnySecret(name, itemId, count) then
        return nil, true
    end
    if ns.IsSecret(quality) or not IsNumber(quality) then
        quality = nil
    end
    if not IsNumber(itemId) and ns.HasAPI("GetInboxItemLink") and type(ns.TooltipLines) == "table" then
        local link = GetInboxItemLink(mailIndex, attachIndex)
        if ns.IsSecret(link) then
            return nil, true
        end
        itemId = ns.TooltipLines.ParseItemId(link)
    end
    return { itemId = itemId, count = count, name = name, quality = quality }
end

-- 우편 수집(entries·names·상태·부분 여부), dik, 2026-10-01
local function CollectMail()
    local numItems, totalItems = GetInboxNumItems()
    if AnySecret(numItems, totalItems) then
        return nil, nil, "secret"
    end
    if not IsNumber(numItems) then
        return nil, nil, "invalid"
    end
    local entries = {}
    local names = {}
    local attachMax = GetAttachmentMax()
    for i = 1, numItems do
        local header = { GetInboxHeaderInfo(i) }
        local cod = header[6]
        local hasItem = header[8]
        if AnySecret(cod, hasItem) then
            return nil, nil, "secret"
        end
        local skip = (IsNumber(cod) and cod > 0) or not hasItem
        if not skip then
            for a = 1, attachMax do
                local att, secret = ReadAttachment(i, a)
                if secret then
                    return nil, nil, "secret"
                end
                if att ~= nil then
                    entries[#entries + 1] = { att.itemId, att.count }
                    if IsPosInt(att.itemId) and type(att.name) == "string" and att.name ~= "" then
                        names[att.itemId] = { name = att.name, quality = att.quality }
                    end
                end
            end
        end
    end
    local partial = IsNumber(totalItems) and totalItems > numItems
    return entries, names, "ok", partial
end

-- 스캔 결과 저장(통째 교체), dik, 2026-10-01
local function CommitScan(loc, map, truncated, partial, now)
    local area = state.area
    area[loc] = map
    area[loc .. "At"] = now
    if truncated then
        if type(area.truncated) ~= "table" then
            area.truncated = {}
        end
        area.truncated[loc] = true
    elseif type(area.truncated) == "table" then
        area.truncated[loc] = nil
        if next(area.truncated) == nil then
            area.truncated = nil
        end
    end
    if loc == "mail" then
        if partial then
            area.mailPartial = true
        else
            area.mailPartial = nil
        end
    end
end

-- 위치 스캔 실행, dik, 2026-10-01
local function ScanLocation(loc)
    if not state.ready then
        return
    end
    local entries, names, status, partial
    local max
    if loc == "bags" then
        entries, names, status = CollectContainers(GetBagList(), true)
        max = BAGS_MAX
    elseif loc == "bank" then
        if not state.bankOpen or not state.bankEnabled then
            return
        end
        entries, names, status = CollectContainers(GetBankList(), false)
        max = BANK_MAX
    elseif loc == "mail" then
        if not state.mailOpen or not state.mailEnabled then
            return
        end
        entries, names, status, partial = CollectMail()
        max = MAIL_MAX
    else
        return
    end
    if status == "secret" then
        if not state.secret then
            state.secret = true
            ns.Fire("INVENTORY_UPDATED", state.characterKey, "all")
        end
        return
    end
    if status ~= "ok" then
        return
    end
    local now = time()
    if not IsNumber(now) then
        return
    end
    local map, truncated = ns.Inventory.Accumulate(entries, max)
    state.secret = false
    CommitScan(loc, map, truncated, partial, now)
    CommitNames(names)
    ns.Fire("INVENTORY_UPDATED", state.characterKey, loc)
end

-- 대기 중 스캔 실행(bags → bank → mail), dik, 2026-10-01
local function RunPending()
    state.timerPending = false
    for i = 1, #LOCATIONS do
        local loc = LOCATIONS[i]
        if state.pending[loc] then
            state.pending[loc] = nil
            ScanLocation(loc)
        end
    end
end

-- 스캔 예약(0.5초 합치기), dik, 2026-10-01
local function Schedule(loc)
    if not state.ready then
        return
    end
    state.pending[loc] = true
    if state.timerPending then
        return
    end
    if ns.HasAPI("C_Timer.After") then
        state.timerPending = true
        C_Timer.After(SCAN_DELAY, RunPending)
    else
        RunPending()
    end
end

-- 예약된 위치 즉시 실행, dik, 2026-10-01
local function FlushPending(loc)
    if state.pending[loc] then
        state.pending[loc] = nil
        ScanLocation(loc)
    end
end

-- 은행 열림, dik, 2026-10-01
local function OpenBank()
    if not state.bankEnabled or state.bankOpen then
        return
    end
    state.bankOpen = true
    ScanLocation("bank")
end

-- 은행 닫힘(예약분 먼저 실행), dik, 2026-10-01
local function CloseBank()
    if not state.bankOpen then
        return
    end
    FlushPending("bags")
    FlushPending("bank")
    state.bankOpen = false
end

-- 우편함 열림(스캔하지 않음), dik, 2026-10-01
local function OpenMail()
    if not state.mailEnabled or state.mailOpen then
        return
    end
    state.mailOpen = true
end

-- 우편함 닫힘(예약분 먼저 실행), dik, 2026-10-01
local function CloseMail()
    if not state.mailOpen then
        return
    end
    FlushPending("mail")
    state.mailOpen = false
end

-- 상호작용 창 열림·닫힘 분배, dik, 2026-10-01
local function OnInteraction(kind, shown)
    if ns.IsSecret(kind) or not IsNumber(kind) then
        return
    end
    if state.bankType ~= nil and kind == state.bankType then
        if shown then
            OpenBank()
        else
            CloseBank()
        end
    elseif state.mailType ~= nil and kind == state.mailType then
        if shown then
            OpenMail()
        else
            CloseMail()
        end
    end
end

-- 이벤트 분배, dik, 2026-10-01
local function OnEvent(_, event, arg1)
    if event == "BAG_UPDATE_DELAYED" then
        Schedule("bags")
        if state.bankOpen then
            Schedule("bank")
        end
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if state.bankOpen then
            Schedule("bank")
        end
    elseif event == "BANKFRAME_OPENED" then
        OpenBank()
    elseif event == "BANKFRAME_CLOSED" then
        CloseBank()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        OnInteraction(arg1, true)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        OnInteraction(arg1, false)
    elseif event == "MAIL_SHOW" then
        OpenMail()
    elseif event == "MAIL_INBOX_UPDATE" then
        if state.mailOpen then
            Schedule("mail")
        end
    elseif event == "MAIL_CLOSED" then
        CloseMail()
    end
end

-- 준비 판정·영역 로드·정리·첫 스캔(READY·CHAR_UPDATED), dik, 2026-10-01
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
        area = { version = AREA_VERSION, bags = {}, bank = {}, mail = {} }
    end
    state.area = area
    state.readOnly = readOnly
    state.characterKey = key
    state.secret = false
    state.ready = true
    PruneNames()
    ScanLocation("bags")
    ns.Fire("INVENTORY_UPDATED", key, "all")
end

-- 이벤트 등록 결과로 기능 그룹 판정, dik, 2026-10-01
local function ResolveGroups(registered)
    local bankType = nil
    if ns.HasAPI("Enum.PlayerInteractionType.Banker") and IsNumber(Enum.PlayerInteractionType.Banker) then
        bankType = Enum.PlayerInteractionType.Banker
    end
    local mailType = nil
    if ns.HasAPI("Enum.PlayerInteractionType.MailInfo") and IsNumber(Enum.PlayerInteractionType.MailInfo) then
        mailType = Enum.PlayerInteractionType.MailInfo
    end
    local interaction = registered.PLAYER_INTERACTION_MANAGER_FRAME_SHOW == true
    state.bankType = bankType
    state.mailType = mailType
    state.bankEnabled = registered.BANKFRAME_OPENED == true or (interaction and bankType ~= nil)
    local mailApis = #ns.GetMissingAPIs(MAIL_APIS) == 0
    state.mailEnabled = mailApis and registered.MAIL_INBOX_UPDATE == true
        and (registered.MAIL_SHOW == true or (interaction and mailType ~= nil))
end

-- 이벤트 프레임 생성·등록·그룹 판정·공급자·구독·안내, dik, 2026-10-01
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    local missing = {}
    local registered = {}
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        local ok = pcall(frame.RegisterEvent, frame, name)
        if ok then
            registered[name] = true
        else
            missing[#missing + 1] = name
        end
    end
    ResolveGroups(registered)
    local mailMissing = ns.GetMissingAPIs(MAIL_APIS)
    for i = 1, #mailMissing do
        missing[#missing + 1] = mailMissing[i]
    end
    state.missing = missing
    if type(ns.TooltipLines) == "table" then
        ns.TooltipLines.RegisterItem({
            id = "inventory",
            order = PROVIDER_ORDER,
            Get = function(itemId)
                if ns.GetSetting(MODULE_ID, "showTooltip") ~= true then
                    return nil
                end
                return ns.Inventory.BuildTooltipLines(ns.Inventory.GetItemCounts(itemId),
                    ns.GetSetting(MODULE_ID, "tooltipMaxChars"))
            end,
        })
    end
    ns.On("READY", Prepare)
    ns.On("CHAR_UPDATED", Prepare)
    if #missing > 0 then
        ns.Print(L.MSG_INVENTORY_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
end

-- 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "inventory",
    title = L.MODULE_INVENTORY,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_INVENTORY_DESC,
    category = "feature",
    order = 60,
    requires = { "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo", "time" },
    settings = {
        { key = "showTooltip", type = "checkbox", label = L.SETTING_INV_TOOLTIP,
            tooltip = L.SETTING_INV_TOOLTIP_TIP, default = true },
        { key = "tooltipMaxChars", type = "slider", label = L.SETTING_INV_TOOLTIP_CHARS,
            tooltip = L.SETTING_INV_TOOLTIP_CHARS_TIP, min = 1, max = 10, step = 1, default = 5 },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
    OnSettingChanged = function()
        ns.Fire("INVENTORY_UPDATED", ns.GetCurrentCharacterKey(), "all")
    end,
})
