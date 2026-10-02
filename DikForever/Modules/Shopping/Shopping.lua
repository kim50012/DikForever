-- 재료 쇼핑 리스트 모듈 등록·레시피 기록·부족분 계산·툴팁 공급자, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "shopping"
local AREA_VERSION = 1
local RECIPE_MAX = 3000
local ITEM_NAME_MAX = 3000
local TARGET_MAX = 50
local QTY_MAX = 999
local REAGENT_ID_MAX = 5
local SCAN_DELAY = 0.5
local SCAN_BATCH = 50
local NAME_DELAY = 0.5
local RECIPE_DISPLAY_MAX = 200
local WHERE_MAX = 2
local BASIC_REAGENT_DEFAULT = 1
local PROVIDER_ORDER = 60
local COPY_DEPTH_MAX = 8

local EVENT_ORDER = {
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "NEW_RECIPE_LEARNED",
    "GET_ITEM_INFO_RECEIVED",
}

local OPTIONAL_APIS = {
    "C_TradeSkillUI.IsTradeSkillReady",
    "C_TradeSkillUI.GetBaseProfessionInfo",
    "C_Item.GetItemNameByID",
    "C_Item.RequestLoadItemDataByID",
}

local RECIPE_NUMBER_FIELDS = { "prof", "out", "outMin", "outMax", "skipped" }

local state = {
    ready = false,
    readOnly = false,
    secret = false,
    scanEnabled = false,
    tradeOpen = false,
    scanning = false,
    progress = nil,
    lastScan = nil,
    recipeTruncated = false,
    tooltip = false,
    missing = {},
    frame = nil,
    area = nil,
    recipeCount = 0,
    itemCount = 0,
    scanToken = 0,
    scanPending = false,
    namePending = false,
    pendingNames = {},
    requested = {},
    index = nil,
    indexDirty = true,
}

ns.Shopping = {}

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 양의 정수 판정, dik, 2026-10-01
local function IsPosInt(v)
    return IsNumber(v) and v > 0 and math.floor(v) == v
end

-- 횟수 보정(순수 함수), dik, 2026-10-01
function ns.Shopping.ClampCount(v)
    if not IsNumber(v) then
        return 1
    end
    return math.max(1, math.min(QTY_MAX, math.floor(v)))
end

-- 재료 구성 해석(순수 함수), dik, 2026-10-01
function ns.Shopping.ParseSchematic(schematic, basicType, isSecret)
    if type(schematic) ~= "table" then
        return nil, 0
    end
    local slots = schematic.reagentSlotSchematics
    if type(slots) ~= "table" then
        return nil, 0
    end
    if not IsNumber(basicType) then
        basicType = BASIC_REAGENT_DEFAULT
    end
    local function secret(v)
        return type(isSecret) == "function" and isSecret(v) == true
    end
    local out, outMin, outMax = schematic.outputItemID, schematic.quantityMin, schematic.quantityMax
    if secret(out) or secret(outMin) or secret(outMax) or secret(slots) then
        return nil, "secret"
    end
    local reagents = {}
    local skipped = 0
    for i = 1, #slots do
        local slot = slots[i]
        if secret(slot) then
            return nil, "secret"
        end
        if type(slot) == "table" then
            local reagentType, qty, list = slot.reagentType, slot.quantityRequired, slot.reagents
            if secret(reagentType) or secret(qty) or secret(list) then
                return nil, "secret"
            end
            if reagentType == basicType then
                local ids = {}
                local seen = {}
                if type(list) == "table" then
                    for j = 1, #list do
                        local reagent = list[j]
                        if secret(reagent) then
                            return nil, "secret"
                        end
                        if type(reagent) == "table" then
                            local itemId = reagent.itemID
                            if secret(itemId) then
                                return nil, "secret"
                            end
                            if IsPosInt(itemId) and not seen[itemId] then
                                seen[itemId] = true
                                ids[#ids + 1] = itemId
                            end
                        end
                    end
                end
                table.sort(ids)
                for j = #ids, REAGENT_ID_MAX + 1, -1 do
                    ids[j] = nil
                end
                if IsPosInt(qty) and #ids > 0 then
                    reagents[#reagents + 1] = { ids = ids, qty = qty }
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    local entry = { reagents = reagents }
    if IsNumber(out) then
        entry.out = out
    end
    if IsNumber(outMin) then
        entry.outMin = outMin
    end
    if IsNumber(outMax) then
        entry.outMax = outMax
    end
    return entry, skipped
end

-- 재료 묶음 키(순수 함수), dik, 2026-10-01
function ns.Shopping.SlotKey(ids)
    if type(ids) ~= "table" then
        return ""
    end
    return table.concat(ids, ",")
end

-- 필요량 합산(순수 함수), dik, 2026-10-01
function ns.Shopping.ComputeNeeds(targets, recipes)
    local needs = {}
    local unknown = 0
    if type(targets) ~= "table" or type(recipes) ~= "table" then
        return needs, unknown
    end
    local byKey = {}
    local seenRecipes = {}
    for i = 1, #targets do
        local t = targets[i]
        if type(t) == "table" then
            local r = recipes[t.recipe]
            if type(r) ~= "table" then
                unknown = unknown + 1
            elseif type(r.reagents) == "table" then
                local count = ns.Shopping.ClampCount(t.count)
                for j = 1, #r.reagents do
                    local slot = r.reagents[j]
                    local key = ns.Shopping.SlotKey(slot.ids)
                    if key ~= "" then
                        local need = byKey[key]
                        if need == nil then
                            local ids = {}
                            for k = 1, #slot.ids do
                                ids[k] = slot.ids[k]
                            end
                            need = { key = key, ids = ids, need = 0, uses = 0, recipes = {} }
                            byKey[key] = need
                            seenRecipes[key] = {}
                            needs[#needs + 1] = need
                        end
                        need.need = need.need + slot.qty * count
                        if not seenRecipes[key][t.recipe] then
                            seenRecipes[key][t.recipe] = true
                            need.recipes[#need.recipes + 1] = t.recipe
                            need.uses = need.uses + 1
                        end
                    end
                end
            end
        end
    end
    return needs, unknown
end

-- 부족분 계산(순수 함수), dik, 2026-10-01
function ns.Shopping.BuildShortage(needs, countsById, onlyKey)
    local rows = {}
    if type(needs) ~= "table" then
        return rows
    end
    if type(countsById) ~= "table" then
        countsById = {}
    end
    for i = 1, #needs do
        local need = needs[i]
        local byChar = {}
        local where = {}
        for j = 1, #need.ids do
            local counts = countsById[need.ids[j]]
            if type(counts) == "table" and type(counts.chars) == "table" then
                for k = 1, #counts.chars do
                    local ch = counts.chars[k]
                    if type(ch) == "table" and ch.key ~= nil and IsNumber(ch.total)
                        and (onlyKey == nil or ch.key == onlyKey) then
                        local item = byChar[ch.key]
                        if item == nil then
                            item = { key = ch.key, displayName = ch.displayName, classFile = ch.classFile, total = 0 }
                            byChar[ch.key] = item
                            where[#where + 1] = item
                        end
                        item.total = item.total + ch.total
                    end
                end
            end
        end
        table.sort(where, function(a, b)
            if a.total ~= b.total then
                return a.total > b.total
            end
            return tostring(a.key) < tostring(b.key)
        end)
        local owned = 0
        for j = 1, #where do
            owned = owned + where[j].total
        end
        local ids = {}
        for j = 1, #need.ids do
            ids[j] = need.ids[j]
        end
        rows[#rows + 1] = { id = need.key, key = need.key, ids = ids, itemId = ids[1], need = need.need,
            owned = owned, short = math.max(0, need.need - owned), uses = need.uses, where = where }
    end
    table.sort(rows, function(a, b)
        if a.short ~= b.short then
            return a.short > b.short
        end
        if a.need ~= b.need then
            return a.need > b.need
        end
        return a.key < b.key
    end)
    return rows
end

-- 보유 위치 문자열(순수 함수), dik, 2026-10-01
function ns.Shopping.FormatWhere(where, max)
    if not IsNumber(max) then
        max = WHERE_MAX
    end
    max = math.max(0, math.floor(max))
    if type(where) ~= "table" or #where == 0 then
        return L.VALUE_UNKNOWN
    end
    local parts = {}
    for i = 1, math.min(max, #where) do
        local item = where[i]
        local name = item.displayName
        if type(name) ~= "string" then
            name = tostring(item.key)
        end
        parts[#parts + 1] = L.SHOP_WHERE_ITEM:format(name, ns.FormatNumber(item.total))
    end
    local text = table.concat(parts, L.SHOP_WHERE_SEP)
    if #where > max then
        text = text .. L.SHOP_WHERE_MORE:format(#where - max)
    end
    return text
end

-- 툴팁 줄 조립(순수 함수), dik, 2026-10-01
function ns.Shopping.BuildTooltipLine(need, owned)
    if not IsNumber(need) or need <= 0 then
        return nil
    end
    if not IsNumber(owned) then
        owned = 0
    end
    local short = math.max(0, need - owned)
    if short > 0 then
        return { left = L.SHOP_TIP, right = L.SHOP_TIP_SHORT:format(ns.FormatNumber(need), ns.FormatNumber(short)),
            leftToken = "ACCENT", rightToken = "DANGER" }
    end
    return { left = L.SHOP_TIP, right = L.SHOP_TIP_ENOUGH:format(ns.FormatNumber(need)),
        leftToken = "ACCENT", rightToken = "TEXT" }
end

-- 표의 키 수, dik, 2026-10-01
local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- 기본 값만 깊은 복사, dik, 2026-10-01
local function CopyValue(v, depth)
    local kind = type(v)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return v
    end
    if kind ~= "table" or depth > COPY_DEPTH_MAX then
        return nil
    end
    local out = {}
    for k, x in pairs(v) do
        local keyKind = type(k)
        if keyKind == "string" or keyKind == "number" then
            out[k] = CopyValue(x, depth + 1)
        end
    end
    return out
end

-- 빈 영역 생성, dik, 2026-10-01
local function NewArea()
    return { version = AREA_VERSION, recipes = {}, profs = {}, targets = {}, items = {} }
end

-- 재료 id 목록 보정, dik, 2026-10-01
local function CleanIds(ids)
    if type(ids) ~= "table" then
        return nil
    end
    local list = {}
    local seen = {}
    for i = 1, #ids do
        local id = ids[i]
        if IsPosInt(id) and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    table.sort(list)
    if #list < 1 or #list > REAGENT_ID_MAX then
        return nil
    end
    return list
end

-- 레시피 항목 보정(잘못되면 false), dik, 2026-10-01
local function CleanRecipe(rec)
    if type(rec) ~= "table" or type(rec.name) ~= "string" or rec.name == "" or type(rec.reagents) ~= "table" then
        return false
    end
    local reagents = {}
    for i = 1, #rec.reagents do
        local slot = rec.reagents[i]
        if type(slot) == "table" and IsPosInt(slot.qty) then
            local ids = CleanIds(slot.ids)
            if ids ~= nil then
                reagents[#reagents + 1] = { ids = ids, qty = slot.qty }
            end
        end
    end
    rec.reagents = reagents
    for i = 1, #RECIPE_NUMBER_FIELDS do
        local field = RECIPE_NUMBER_FIELDS[i]
        if not IsNumber(rec[field]) then
            rec[field] = nil
        end
    end
    if rec.skipped ~= nil and rec.skipped <= 0 then
        rec.skipped = nil
    end
    if not IsNumber(rec.at) then
        rec.at = 0
    end
    return true
end

-- 저장 영역 검증(제자리 보정), dik, 2026-10-01
local function ValidateArea(area)
    if not IsNumber(area.version) or area.version < 1 then
        area.version = AREA_VERSION
    end
    for _, field in ipairs({ "recipes", "profs", "items", "targets" }) do
        if type(area[field]) ~= "table" then
            area[field] = {}
        end
    end
    for id, rec in pairs(area.recipes) do
        if not IsPosInt(id) or not CleanRecipe(rec) then
            area.recipes[id] = nil
        end
    end
    for id, prof in pairs(area.profs) do
        if not IsPosInt(id) or type(prof) ~= "table" or type(prof.name) ~= "string" then
            area.profs[id] = nil
        else
            if not IsNumber(prof.at) then
                prof.at = 0
            end
            if not IsNumber(prof.count) then
                prof.count = 0
            end
        end
    end
    for id, item in pairs(area.items) do
        if not IsPosInt(id) or type(item) ~= "table" or type(item.name) ~= "string" then
            area.items[id] = nil
        elseif not IsNumber(item.quality) then
            item.quality = nil
        end
    end
    local targets = {}
    local indexOf = {}
    local source = area.targets
    for i = 1, #source do
        local t = source[i]
        if type(t) == "table" and IsPosInt(t.recipe) then
            local count = ns.Shopping.ClampCount(t.count)
            local at = indexOf[t.recipe]
            if at ~= nil then
                targets[at].count = math.min(QTY_MAX, targets[at].count + count)
            elseif #targets < TARGET_MAX then
                targets[#targets + 1] = { recipe = t.recipe, count = count }
                indexOf[t.recipe] = #targets
            end
        end
    end
    area.targets = targets
end

-- 목표·레시피 색인 무효화, dik, 2026-10-01
local function Touch()
    state.indexDirty = true
end

-- 보유량 사용 가능 판정, dik, 2026-10-01
local function InventoryUsable()
    if type(ns.Inventory) ~= "table" or type(ns.Inventory.GetItemCounts) ~= "function" then
        return false
    end
    if not ns.IsModuleEnabled("inventory") then
        return false
    end
    local supported = ns.IsModuleSupported("inventory")
    return supported == true
end

-- 보유 범위 캐릭터 키(전 캐릭터면 nil), dik, 2026-10-01
local function GetOnlyKey()
    if ns.GetSetting(MODULE_ID, "countOtherChars") == false then
        local key = ns.GetCurrentCharacterKey()
        if type(key) == "string" then
            return key
        end
    end
    return nil
end

-- 재료 id 별 보유 조회 표, dik, 2026-10-01
local function GatherCounts(needs)
    local counts = {}
    if not InventoryUsable() then
        return counts
    end
    for i = 1, #needs do
        for j = 1, #needs[i].ids do
            local id = needs[i].ids[j]
            if counts[id] == nil then
                counts[id] = ns.Inventory.GetItemCounts(id)
            end
        end
    end
    return counts
end

-- 이름 캐시 넣기, dik, 2026-10-01
local function CachePut(itemId, name, quality)
    local area = state.area
    if area == nil then
        return
    end
    local existing = area.items[itemId]
    if existing ~= nil then
        if existing.name ~= name or existing.quality ~= quality then
            area.items[itemId] = { name = name, quality = quality }
        end
    elseif state.itemCount < ITEM_NAME_MAX then
        area.items[itemId] = { name = name, quality = quality }
        state.itemCount = state.itemCount + 1
    end
end

-- 클라이언트 이름 조회 후 캐시, dik, 2026-10-01
local function ResolveClientName(itemId)
    if not ns.HasAPI("C_Item.GetItemNameByID") then
        return nil
    end
    local name = C_Item.GetItemNameByID(itemId)
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    local quality = nil
    if ns.HasAPI("C_Item.GetItemQualityByID") then
        local q = C_Item.GetItemQualityByID(itemId)
        if not ns.IsSecret(q) and IsNumber(q) then
            quality = q
        end
    end
    CachePut(itemId, name, quality)
    return name, quality
end

-- 재료 이름·품질 조회, dik, 2026-10-01
function ns.Shopping.GetItemName(itemId)
    if not IsPosInt(itemId) then
        return nil
    end
    local area = state.area
    if area ~= nil and type(area.items[itemId]) == "table" then
        return area.items[itemId].name, area.items[itemId].quality
    end
    if type(ns.Inventory) == "table" and type(ns.Inventory.GetItemName) == "function" then
        local name, quality = ns.Inventory.GetItemName(itemId)
        if type(name) == "string" and name ~= "" then
            if not IsNumber(quality) then
                quality = nil
            end
            return name, quality
        end
    end
    local name, quality = ResolveClientName(itemId)
    if name ~= nil then
        return name, quality
    end
    if not state.requested[itemId] and ns.HasAPI("C_Item.RequestLoadItemDataByID") then
        state.requested[itemId] = true
        state.pendingNames[itemId] = true
        C_Item.RequestLoadItemDataByID(itemId)
    end
    return nil
end

-- 표시 이름(없으면 아이템 번호 문구), dik, 2026-10-01
local function DisplayName(itemId)
    local name, quality = ns.Shopping.GetItemName(itemId)
    if name == nil then
        name = L.INV_ITEM_UNKNOWN:format(itemId)
    end
    return name, quality
end

-- 이름 도착 알림 합치기, dik, 2026-10-01
local function ScheduleNames()
    if state.namePending then
        return
    end
    if ns.HasAPI("C_Timer.After") then
        state.namePending = true
        C_Timer.After(NAME_DELAY, function()
            state.namePending = false
            ns.Fire("SHOPPING_UPDATED", "names")
        end)
    else
        ns.Fire("SHOPPING_UPDATED", "names")
    end
end

-- 안 쓰는 이름 캐시 정리, dik, 2026-10-01
local function PruneNames()
    local area = state.area
    if state.readOnly or area == nil then
        return
    end
    local used = {}
    for _, rec in pairs(area.recipes) do
        for _, slot in ipairs(rec.reagents) do
            for _, id in ipairs(slot.ids) do
                used[id] = true
            end
        end
    end
    for id in pairs(area.items) do
        if not used[id] then
            area.items[id] = nil
        end
    end
end

-- 목표 추가, dik, 2026-10-01
function ns.Shopping.AddTarget(recipeId, count)
    if not state.ready then
        return false
    end
    local area = state.area
    if not IsPosInt(recipeId) or type(area.recipes[recipeId]) ~= "table" then
        return false, "SHOP_ERR_UNKNOWN_RECIPE"
    end
    local c = ns.Shopping.ClampCount(count)
    local found = nil
    for i = 1, #area.targets do
        if area.targets[i].recipe == recipeId then
            found = area.targets[i]
            break
        end
    end
    if found ~= nil then
        found.count = math.min(QTY_MAX, found.count + c)
    else
        if #area.targets >= TARGET_MAX then
            return false, "SHOP_ERR_TARGET_FULL"
        end
        area.targets[#area.targets + 1] = { recipe = recipeId, count = c }
    end
    Touch()
    ns.Fire("SHOPPING_UPDATED", "targets")
    return true
end

-- 목표 횟수 지정, dik, 2026-10-01
function ns.Shopping.SetTargetCount(recipeId, count)
    if not state.ready then
        return false
    end
    for i = 1, #state.area.targets do
        local t = state.area.targets[i]
        if t.recipe == recipeId then
            t.count = ns.Shopping.ClampCount(count)
            Touch()
            ns.Fire("SHOPPING_UPDATED", "targets")
            return true
        end
    end
    return false
end

-- 목표 삭제, dik, 2026-10-01
function ns.Shopping.RemoveTarget(recipeId)
    if not state.ready then
        return false
    end
    for i = 1, #state.area.targets do
        if state.area.targets[i].recipe == recipeId then
            table.remove(state.area.targets, i)
            Touch()
            ns.Fire("SHOPPING_UPDATED", "targets")
            return true
        end
    end
    return false
end

-- 목표 모두 삭제, dik, 2026-10-01
function ns.Shopping.ClearTargets()
    if not state.ready then
        return 0
    end
    local n = #state.area.targets
    if n > 0 then
        state.area.targets = {}
        Touch()
        ns.Fire("SHOPPING_UPDATED", "targets")
    end
    return n
end

-- 목표 내보내기(복사본), dik, 2026-10-02
function ns.Shopping.ExportTargets()
    local out = {}
    if not state.ready or state.area == nil then
        return out
    end
    for i = 1, #state.area.targets do
        local t = state.area.targets[i]
        out[#out + 1] = { recipe = t.recipe, count = t.count }
    end
    return out
end

-- 목표 가져오기(교체), dik, 2026-10-02
function ns.Shopping.ImportTargets(list)
    if not state.ready or state.readOnly then
        return nil
    end
    local targets = {}
    local seen = {}
    local applied, skipped = 0, 0
    if type(list) == "table" then
        for i = 1, #list do
            local row = list[i]
            if type(row) == "table" and IsPosInt(row.recipe) and IsNumber(row.count)
                and not seen[row.recipe] and #targets < TARGET_MAX then
                seen[row.recipe] = true
                targets[#targets + 1] = { recipe = row.recipe, count = ns.Shopping.ClampCount(row.count) }
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end
    state.area.targets = targets
    Touch()
    ns.Fire("SHOPPING_UPDATED", "targets")
    return applied, skipped
end

-- 레시피의 전문기술 표시 이름, dik, 2026-10-01
local function ProfName(rec)
    if rec.prof == nil then
        return L.SHOP_PROF_OTHER
    end
    local prof = state.area.profs[rec.prof]
    if type(prof) == "table" and type(prof.name) == "string" then
        return prof.name
    end
    return L.SHOP_PROF_UNKNOWN:format(rec.prof)
end

-- 목표 표 행, dik, 2026-10-01
function ns.Shopping.GetTargetRows()
    local rows = {}
    if not state.ready then
        return rows
    end
    local area = state.area
    for i = 1, #area.targets do
        local t = area.targets[i]
        local rec = area.recipes[t.recipe]
        if type(rec) == "table" then
            rows[#rows + 1] = { id = tostring(t.recipe), recipe = t.recipe, name = rec.name, count = t.count,
                profName = ProfName(rec), known = true }
        else
            rows[#rows + 1] = { id = tostring(t.recipe), recipe = t.recipe,
                name = L.SHOP_RECIPE_UNKNOWN:format(t.recipe), count = t.count, profName = nil, known = false }
        end
    end
    return rows
end

-- 목표 행 오버 상세, dik, 2026-10-01
function ns.Shopping.GetTargetDetail(recipeId)
    if not state.ready then
        return nil
    end
    local area = state.area
    local count = nil
    for i = 1, #area.targets do
        if area.targets[i].recipe == recipeId then
            count = area.targets[i].count
            break
        end
    end
    local rec = area.recipes[recipeId]
    if count == nil or type(rec) ~= "table" then
        return nil
    end
    local lines = {}
    for i = 1, #rec.reagents do
        local slot = rec.reagents[i]
        local name, quality = DisplayName(slot.ids[1])
        lines[#lines + 1] = { name = name, quality = quality, need = slot.qty * count }
    end
    return { name = rec.name, count = count, skipped = rec.skipped or 0, lines = lines }
end

-- 부족 재료 행·요약, dik, 2026-10-01
function ns.Shopping.GetShortageRows()
    if not state.ready then
        return {}, { items = 0, shortItems = 0, unknown = 0 }
    end
    local needs, unknown = ns.Shopping.ComputeNeeds(state.area.targets, state.area.recipes)
    local rows = ns.Shopping.BuildShortage(needs, GatherCounts(needs), GetOnlyKey())
    local shortItems = 0
    for i = 1, #rows do
        local row = rows[i]
        row.name, row.quality = DisplayName(row.itemId)
        row.whereText = ns.Shopping.FormatWhere(row.where)
        if row.short > 0 then
            shortItems = shortItems + 1
        end
    end
    return rows, { items = #rows, shortItems = shortItems, unknown = unknown }
end

-- 레시피 재료 문구, dik, 2026-10-01
function ns.Shopping.GetReagentText(recipeId, count)
    if not state.ready then
        return ""
    end
    local rec = state.area.recipes[recipeId]
    if type(rec) ~= "table" then
        return ""
    end
    if #rec.reagents == 0 then
        return L.SHOP_NO_REAGENTS
    end
    local c = ns.Shopping.ClampCount(count)
    local parts = {}
    for i = 1, #rec.reagents do
        local slot = rec.reagents[i]
        parts[#parts + 1] = DisplayName(slot.ids[1]) .. " " .. ns.FormatNumber(slot.qty * c)
    end
    return table.concat(parts, L.SHOP_WHERE_SEP)
end

-- 전문기술 필터 통과 판정, dik, 2026-10-01
local function PassProfFilter(rec, profFilter)
    if profFilter == "none" then
        return rec.prof == nil
    end
    if IsNumber(profFilter) then
        return rec.prof == profFilter
    end
    return true
end

-- 검색어 일치 판정, dik, 2026-10-01
local function PassQuery(name, recipeId, query)
    if type(ns.Inventory) == "table" and type(ns.Inventory.MatchQuery) == "function" then
        return ns.Inventory.MatchQuery(name, recipeId, query)
    end
    return type(query) ~= "string" or strtrim(query) == ""
end

-- 레시피 표 행, dik, 2026-10-01
function ns.Shopping.GetRecipeRows(profFilter, query)
    local rows = {}
    if not state.ready then
        return rows, 0
    end
    for id, rec in pairs(state.area.recipes) do
        if PassProfFilter(rec, profFilter) and PassQuery(rec.name, id, query) then
            rows[#rows + 1] = { recipe = id, name = rec.name }
        end
    end
    local matchCount = #rows
    table.sort(rows, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.recipe < b.recipe
    end)
    for i = #rows, RECIPE_DISPLAY_MAX + 1, -1 do
        rows[i] = nil
    end
    for i = 1, #rows do
        local row = rows[i]
        row.id = tostring(row.recipe)
        row.profName = ProfName(state.area.recipes[row.recipe])
        row.reagentText = ns.Shopping.GetReagentText(row.recipe, 1)
    end
    return rows, matchCount
end

-- 전문기술 드롭다운 항목, dik, 2026-10-01
function ns.Shopping.GetProfFilterItems()
    local items = { { value = "all", text = L.SHOP_ALL_PROFS } }
    if not state.ready then
        return items
    end
    local seen = {}
    local profs = {}
    local hasNone = false
    for _, rec in pairs(state.area.recipes) do
        if rec.prof == nil then
            hasNone = true
        elseif not seen[rec.prof] then
            seen[rec.prof] = true
            local prof = state.area.profs[rec.prof]
            local text = L.SHOP_PROF_UNKNOWN:format(rec.prof)
            if type(prof) == "table" and type(prof.name) == "string" then
                text = prof.name
            end
            profs[#profs + 1] = { value = rec.prof, text = text }
        end
    end
    table.sort(profs, function(a, b)
        if a.text ~= b.text then
            return a.text < b.text
        end
        return a.value < b.value
    end)
    for i = 1, #profs do
        items[#items + 1] = profs[i]
    end
    if hasNone then
        items[#items + 1] = { value = "none", text = L.SHOP_PROF_OTHER }
    end
    return items
end

-- 캐시 요약, dik, 2026-10-01
function ns.Shopping.GetStats()
    if not state.ready then
        return { recipes = 0, profs = 0, targets = 0 }
    end
    return { recipes = CountKeys(state.area.recipes), profs = CountKeys(state.area.profs),
        targets = #state.area.targets }
end

-- 상태 조회(새 테이블), dik, 2026-10-01
function ns.Shopping.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    local progress = nil
    if state.progress ~= nil then
        progress = { done = state.progress.done, total = state.progress.total }
    end
    local lastScan = nil
    if state.lastScan ~= nil then
        lastScan = {}
        for k, v in pairs(state.lastScan) do
            lastScan[k] = v
        end
    end
    return {
        ready = state.ready,
        readOnly = state.readOnly,
        secret = state.secret,
        scanEnabled = state.scanEnabled,
        tradeOpen = state.tradeOpen,
        scanning = state.scanning,
        progress = progress,
        lastScan = lastScan,
        recipeTruncated = state.recipeTruncated,
        inventory = InventoryUsable(),
        onlyKey = GetOnlyKey(),
        tooltip = state.tooltip,
        missing = missing,
    }
end

-- 툴팁용 필요량 색인 재구성, dik, 2026-10-01
local function RebuildIndex()
    local index = {}
    local needs = ns.Shopping.ComputeNeeds(state.area.targets, state.area.recipes)
    for i = 1, #needs do
        for j = 1, #needs[i].ids do
            index[needs[i].ids[j]] = needs[i]
        end
    end
    state.index = index
    state.indexDirty = false
end

-- 툴팁 공급자 본문, dik, 2026-10-01
local function ProviderGet(itemId)
    if ns.GetSetting(MODULE_ID, "showTooltip") ~= true or not state.ready or not IsPosInt(itemId) then
        return nil
    end
    if state.indexDirty or state.index == nil then
        RebuildIndex()
    end
    local need = state.index[itemId]
    if need == nil then
        return nil
    end
    local rows = ns.Shopping.BuildShortage({ need }, GatherCounts({ need }), GetOnlyKey())
    local line = ns.Shopping.BuildTooltipLine(need.need, rows[1].owned)
    if line == nil then
        return nil
    end
    return { line }
end

-- 플래그 true 판정(secret 제외), dik, 2026-10-01
local function FlagTrue(v)
    return not ns.IsSecret(v) and v == true
end

-- 링크·길드·NPC 제작 창 여부, dik, 2026-10-01
local function IsForeignCrafting()
    if ns.HasAPI("C_TradeSkillUI.IsTradeSkillLinked") and FlagTrue(C_TradeSkillUI.IsTradeSkillLinked()) then
        return true
    end
    if ns.HasAPI("C_TradeSkillUI.IsTradeSkillGuild") and FlagTrue(C_TradeSkillUI.IsTradeSkillGuild()) then
        return true
    end
    if ns.HasAPI("C_TradeSkillUI.IsNPCCrafting") and FlagTrue(C_TradeSkillUI.IsNPCCrafting()) then
        return true
    end
    return false
end

-- 전문기술 식별(id, 이름), dik, 2026-10-01
local function ReadProfession()
    if not ns.HasAPI("C_TradeSkillUI.GetBaseProfessionInfo") then
        return nil, nil
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if ns.IsSecret(info) or type(info) ~= "table" then
        return nil, nil
    end
    local id, name = info.professionID, info.professionName
    if ns.IsSecret(id) or ns.IsSecret(name) or not IsPosInt(id) or type(name) ~= "string" or name == "" then
        return nil, nil
    end
    return id, name
end

-- secret 발견 즉시 상태 반영, dik, 2026-10-01
local function MarkSecret(ctx)
    ctx.secret = true
    state.secret = true
end

-- 레시피 1개 기록, dik, 2026-10-01
local function ProcessRecipe(ctx, id)
    if ns.IsSecret(id) then
        MarkSecret(ctx)
        return
    end
    if not IsPosInt(id) then
        return
    end
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    if ns.IsSecret(info) then
        MarkSecret(ctx)
        return
    end
    if type(info) ~= "table" then
        return
    end
    local learned, name, recraft, salvage = info.learned, info.name, info.isRecraft, info.isSalvageRecipe
    if ns.IsSecret(learned) or ns.IsSecret(name) or ns.IsSecret(recraft) or ns.IsSecret(salvage) then
        MarkSecret(ctx)
        return
    end
    if learned ~= true or type(name) ~= "string" or name == "" or recraft == true or salvage == true then
        return
    end
    local entry, skipped = ns.Shopping.ParseSchematic(C_TradeSkillUI.GetRecipeSchematic(id, false),
        ctx.basicType, ns.IsSecret)
    if skipped == "secret" then
        MarkSecret(ctx)
        return
    end
    if entry == nil then
        ctx.unreadable = ctx.unreadable + 1
        return
    end
    ctx.learned = ctx.learned + 1
    local area = state.area
    local existing = area.recipes[id]
    if existing == nil then
        if state.recipeCount >= RECIPE_MAX then
            state.recipeTruncated = true
            return
        end
        state.recipeCount = state.recipeCount + 1
        ctx.newCount = ctx.newCount + 1
    end
    local rec = { name = name, prof = ctx.profId, out = entry.out, outMin = entry.outMin,
        outMax = entry.outMax, reagents = entry.reagents, at = time() }
    if skipped > 0 then
        rec.skipped = skipped
        ctx.skipped = ctx.skipped + skipped
    end
    area.recipes[id] = rec
    for i = 1, #rec.reagents do
        for j = 1, #rec.reagents[i].ids do
            ns.Shopping.GetItemName(rec.reagents[i].ids[j])
        end
    end
end

-- 기록 정상 완료 반영, dik, 2026-10-01
local function FinishScan(ctx)
    local now = time()
    if ctx.profId ~= nil then
        state.area.profs[ctx.profId] = { name = ctx.profName, at = now, count = ctx.learned }
    end
    state.lastScan = { at = now, profName = ctx.profName, count = ctx.learned, newCount = ctx.newCount,
        skipped = ctx.skipped, unreadable = ctx.unreadable, failed = false }
    state.scanning = false
    state.progress = nil
    -- 기록 시작 전 secret 기준 비교, dik, 2026-10-01
    local secretChanged = ctx.secretBefore ~= ctx.secret
    state.secret = ctx.secret
    if ctx.newCount > 0 then
        ns.Print(L.SHOP_MSG_SCANNED:format(ctx.profName or L.SHOP_PROF_OTHER, ctx.newCount))
    end
    Touch()
    if secretChanged then
        ns.Fire("SHOPPING_UPDATED", "status")
    end
    ns.Fire("SHOPPING_UPDATED", "recipes")
end

-- 기록 오류 반영(저장분 유지), dik, 2026-10-01
local function FailScan(ctx)
    state.scanning = false
    state.progress = nil
    state.lastScan = { at = time(), profName = ctx.profName, count = ctx.learned, newCount = ctx.newCount,
        skipped = ctx.skipped, unreadable = ctx.unreadable, failed = true }
    Touch()
    ns.Fire("SHOPPING_UPDATED", "status")
end

-- 배치 1회 처리, dik, 2026-10-01
local function ProcessBatch(ctx)
    local last = math.min(ctx.index + SCAN_BATCH - 1, #ctx.ids)
    for i = ctx.index, last do
        ProcessRecipe(ctx, ctx.ids[i])
    end
    ctx.index = last + 1
    state.progress.done = last
    if ctx.index > #ctx.ids then
        FinishScan(ctx)
    end
end

-- 배치 체인 실행(토큰 비교 중단), dik, 2026-10-01
local function RunBatch(ctx)
    while true do
        if ctx.token ~= state.scanToken or not state.tradeOpen or not state.scanning then
            return
        end
        local ok = xpcall(ctx.step, geterrorhandler())
        if not ok then
            FailScan(ctx)
            return
        end
        if not state.scanning then
            return
        end
        ns.Fire("SHOPPING_UPDATED", "status")
        if ns.HasAPI("C_Timer.After") then
            C_Timer.After(0, function()
                RunBatch(ctx)
            end)
            return
        end
    end
end

-- 기록 시작(조건 검사 후 배치 체인), dik, 2026-10-01
local function StartScan()
    if not state.ready or not state.tradeOpen or state.scanning then
        return
    end
    if ns.HasAPI("C_TradeSkillUI.IsTradeSkillReady") then
        local isReady = C_TradeSkillUI.IsTradeSkillReady()
        if not ns.IsSecret(isReady) and isReady ~= true then
            return
        end
    end
    if IsForeignCrafting() then
        state.lastScan = { at = time(), reason = "linked" }
        ns.Fire("SHOPPING_UPDATED", "status")
        return
    end
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if ns.IsSecret(ids) or type(ids) ~= "table" then
        return
    end
    local profId, profName = ReadProfession()
    if profId ~= nil then
        local old = state.area.profs[profId]
        if old == nil or old.name ~= profName then
            state.area.profs[profId] = { name = profName, at = old and old.at or 0, count = old and old.count or 0 }
        end
    end
    local basicType = nil
    if ns.HasAPI("Enum.CraftingReagentType.Basic") then
        basicType = Enum.CraftingReagentType.Basic
    end
    state.scanToken = state.scanToken + 1
    local ctx = { token = state.scanToken, ids = ids, index = 1, basicType = basicType, profId = profId,
        profName = profName, learned = 0, newCount = 0, skipped = 0, unreadable = 0, secret = false,
        secretBefore = state.secret }
    ctx.step = function()
        ProcessBatch(ctx)
    end
    state.scanning = true
    state.progress = { done = 0, total = #ids }
    RunBatch(ctx)
end

-- 기록 예약(0.5초 합치기·진행 중이면 중단), dik, 2026-10-01
local function RequestScan()
    if not state.ready or not state.tradeOpen then
        return
    end
    -- 중단 시 색인 무효화·상태 발행, dik, 2026-10-01
    if state.scanning then
        state.scanToken = state.scanToken + 1
        state.scanning = false
        state.progress = nil
        Touch()
        ns.Fire("SHOPPING_UPDATED", "status")
    end
    if state.scanPending then
        return
    end
    if ns.HasAPI("C_Timer.After") then
        state.scanPending = true
        C_Timer.After(SCAN_DELAY, function()
            state.scanPending = false
            StartScan()
        end)
    else
        StartScan()
    end
end

-- 이름 도착 처리, dik, 2026-10-01
local function OnItemInfo(itemId, success)
    if ns.IsSecret(itemId) or not IsPosInt(itemId) or not state.pendingNames[itemId] then
        return
    end
    state.pendingNames[itemId] = nil
    if ns.IsSecret(success) or success == false then
        return
    end
    if ResolveClientName(itemId) ~= nil then
        ScheduleNames()
    end
end

-- 이벤트 분배, dik, 2026-10-01
local function OnEvent(_, event, arg1, arg2)
    if event == "TRADE_SKILL_SHOW" then
        state.tradeOpen = true
        RequestScan()
    elseif event == "TRADE_SKILL_CLOSE" then
        local wasScanning = state.scanning
        state.tradeOpen = false
        state.scanToken = state.scanToken + 1
        state.scanning = false
        state.progress = nil
        -- 중단 시 색인 무효화, dik, 2026-10-01
        if wasScanning then
            Touch()
            ns.Fire("SHOPPING_UPDATED", "status")
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        OnItemInfo(arg1, arg2)
    elseif state.tradeOpen then
        RequestScan()
    end
end

-- 준비(READY): 저장 영역 검증 또는 쓰기 금지 메모리 영역, dik, 2026-10-01
local function Prepare()
    if state.ready then
        return
    end
    local area
    local readOnly = false
    if ns.IsDatabaseNewer() then
        readOnly = true
        local raw = nil
        if type(ns.db) == "table" and type(ns.db.modules) == "table" then
            raw = ns.db.modules[MODULE_ID]
        end
        if type(raw) == "table" and IsNumber(raw.version) and raw.version <= AREA_VERSION then
            area = CopyValue(raw, 1)
            ValidateArea(area)
        else
            area = NewArea()
        end
    else
        local store = ns.GetModuleData(MODULE_ID)
        if type(store) ~= "table" then
            readOnly = true
            area = NewArea()
        elseif IsNumber(store.version) and store.version > AREA_VERSION then
            readOnly = true
            area = NewArea()
        else
            ValidateArea(store)
            area = store
        end
    end
    state.area = area
    state.readOnly = readOnly
    state.recipeCount = CountKeys(area.recipes)
    if not readOnly then
        PruneNames()
    end
    state.itemCount = CountKeys(area.items)
    state.secret = false
    state.ready = true
    Touch()
    ns.Fire("SHOPPING_UPDATED", "status")
    RequestScan()
end

-- 이벤트 pcall 등록(성공 표·실패 이름 목록), dik, 2026-10-01
local function RegisterEvents(frame)
    local registered = {}
    local missing = {}
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        if pcall(frame.RegisterEvent, frame, name) then
            registered[name] = true
        else
            missing[#missing + 1] = name
        end
    end
    return registered, missing
end

-- 이벤트 프레임·등록·공급자·구독·안내, dik, 2026-10-01
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    local registered, missing = RegisterEvents(frame)
    state.scanEnabled = registered.TRADE_SKILL_SHOW == true
    local optional = ns.GetMissingAPIs(OPTIONAL_APIS)
    for i = 1, #optional do
        missing[#missing + 1] = optional[i]
    end
    if type(ns.TooltipLines) == "table" and type(ns.TooltipLines.RegisterItem) == "function" then
        -- 공급자 등록 결과로 tooltip 판정, dik, 2026-10-01
        state.tooltip = ns.TooltipLines.RegisterItem({ id = "shopping", order = PROVIDER_ORDER, Get = ProviderGet }) == true
    else
        missing[#missing + 1] = "ns.TooltipLines"
    end
    state.missing = missing
    ns.On("READY", Prepare)
    if #missing > 0 then
        ns.Print(L.MSG_SHOPPING_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
end

-- 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "shopping",
    title = L.MODULE_SHOPPING,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_SHOPPING_DESC,
    category = "feature",
    order = 70,
    requires = { "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo",
        "C_TradeSkillUI.GetRecipeSchematic", "time" },
    settings = {
        { key = "showTooltip", type = "checkbox", label = L.SETTING_SHOP_TOOLTIP,
            tooltip = L.SETTING_SHOP_TOOLTIP_TIP, default = true },
        { key = "countOtherChars", type = "checkbox", label = L.SETTING_SHOP_ALTS,
            tooltip = L.SETTING_SHOP_ALTS_TIP, default = true },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
    OnSettingChanged = function()
        ns.Fire("SHOPPING_UPDATED", "settings")
    end,
})
