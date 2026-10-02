-- 아이템 레벨 모듈 등록·순수 함수·아이템 API 어댑터, dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

ns.ItemLevel = ns.ItemLevel or {}
local IL = ns.ItemLevel

IL.MODULE_ID = "itemLevel"
IL.SLOT_BUTTONS = {
    { name = "CharacterHeadSlot", slot = 1 },
    { name = "CharacterNeckSlot", slot = 2 },
    { name = "CharacterShoulderSlot", slot = 3 },
    { name = "CharacterBackSlot", slot = 15 },
    { name = "CharacterChestSlot", slot = 5 },
    { name = "CharacterWristSlot", slot = 9 },
    { name = "CharacterHandsSlot", slot = 10 },
    { name = "CharacterWaistSlot", slot = 6 },
    { name = "CharacterLegsSlot", slot = 7 },
    { name = "CharacterFeetSlot", slot = 8 },
    { name = "CharacterFinger0Slot", slot = 11 },
    { name = "CharacterFinger1Slot", slot = 12 },
    { name = "CharacterTrinket0Slot", slot = 13 },
    { name = "CharacterTrinket1Slot", slot = 14 },
    { name = "CharacterMainHandSlot", slot = 16 },
    { name = "CharacterSecondaryHandSlot", slot = 17 },
    { name = "CharacterRangedSlot", slot = 18, optional = true },
}
IL.CONTAINER_FRAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ContainerFrame6", "ContainerFrame7", "ContainerFrame8",
    "ContainerFrame9", "ContainerFrame10", "ContainerFrame11", "ContainerFrame12",
    "ContainerFrame13",
}
IL.COMBINED_FRAME = "ContainerFrameCombinedBags"
IL.WEAPON_CLASS = (type(Enum) == "table" and type(Enum.ItemClass) == "table"
    and type(Enum.ItemClass.Weapon) == "number") and Enum.ItemClass.Weapon or 2
IL.ARMOR_CLASS = (type(Enum) == "table" and type(Enum.ItemClass) == "table"
    and type(Enum.ItemClass.Armor) == "number") and Enum.ItemClass.Armor or 4
IL.EXCLUDED_EQUIP_LOCS = {
    INVTYPE_BODY = true,
    INVTYPE_TABARD = true,
    INVTYPE_NON_EQUIP_IGNORE = true,
    INVTYPE_NON_EQUIP = true,
    INVTYPE_BAG = true,
    INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true,
}
IL.DEFAULT_BAG_SLOTS = 4
IL.MAX_LEVEL = 10000
IL.CACHE_MAX = 500
IL.PENDING_MAX = 200
IL.PASS_INTERVAL = 0.25
IL.BAG_RESCAN_INTERVAL = 1.0
IL.MAX_WALK_DEPTH = 2
IL.TEXT_OFFSET_Y = 2
IL.EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" }

local cache = {}
local cacheCount = 0

-- 유한 number 판정(secret 제외), dik, 2026-10-02
local function IsPlainNumber(value)
    if type(value) ~= "number" or ns.IsSecret(value) then
        return false
    end
    return value == value and value ~= math.huge and value ~= -math.huge
end

-- 아이템 레벨 정규화, dik, 2026-10-02
function IL.Normalize(value)
    if not IsPlainNumber(value) then
        return nil
    end
    if value < 1 or value > IL.MAX_LEVEL then
        return nil
    end
    return math.floor(value + 0.5)
end

-- 장비(무기·방어구) 판정, dik, 2026-10-02
function IL.IsEquipment(classID, equipLoc)
    if type(classID) ~= "number" then
        return false
    end
    if classID ~= IL.WEAPON_CLASS and classID ~= IL.ARMOR_CLASS then
        return false
    end
    if type(equipLoc) ~= "string" or equipLoc == "" then
        return false
    end
    return IL.EXCLUDED_EQUIP_LOCS[equipLoc] ~= true
end

-- 품질색 해석, dik, 2026-10-02
function IL.ResolveColor(quality, useQuality, qualityColors)
    if useQuality ~= true then
        return nil
    end
    if not IsPlainNumber(quality) or quality < 0 or quality > 8 or quality ~= math.floor(quality) then
        return nil
    end
    if type(qualityColors) ~= "table" then
        return nil
    end
    local color = qualityColors[quality]
    if type(color) ~= "table" then
        return nil
    end
    local r, g, b = color.r, color.g, color.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return r, g, b
end

-- 링크의 itemID 추출, dik, 2026-10-02
function IL.ParseItemId(link)
    if type(link) ~= "string" or ns.IsSecret(link) then
        return nil
    end
    local text = link:match("item:(%d+)")
    if not text then
        return nil
    end
    return tonumber(text)
end

-- 링크의 itemID(동기 API 우선), dik, 2026-10-02
local function ResolveItemId(link)
    if ns.HasAPI("C_Item.GetItemInfoInstant") then
        local ok, itemId = xpcall(function() return C_Item.GetItemInfoInstant(link) end, geterrorhandler())
        if ok and IsPlainNumber(itemId) and itemId == math.floor(itemId) then
            return itemId
        end
    end
    return IL.ParseItemId(link)
end

-- 세션 캐시 저장, dik, 2026-10-02
local function CacheLevel(link, level)
    if cacheCount >= IL.CACHE_MAX then
        cache = {}
        cacheCount = 0
    end
    if cache[link] == nil then
        cacheCount = cacheCount + 1
    end
    cache[link] = level
end

-- 링크의 아이템 레벨(없으면 nil, itemID), dik, 2026-10-02
function IL.GetLevel(link)
    if type(link) ~= "string" or ns.IsSecret(link) then
        return nil, nil
    end
    local cached = cache[link]
    if cached then
        return cached
    end
    if ns.HasAPI("C_Item.GetDetailedItemLevelInfo") then
        local ok, value = xpcall(function() return C_Item.GetDetailedItemLevelInfo(link) end, geterrorhandler())
        local level = ok and IL.Normalize(value) or nil
        if level then
            CacheLevel(link, level)
            return level
        end
    end
    if ns.HasAPI("C_Item.GetItemInfo") then
        local ok, _, _, _, value = xpcall(function() return C_Item.GetItemInfo(link) end, geterrorhandler())
        local level = ok and IL.Normalize(value) or nil
        if level then
            CacheLevel(link, level)
            return level
        end
    end
    return nil, ResolveItemId(link)
end

-- 링크 장비 여부(nil=아직 모름), dik, 2026-10-02
function IL.ClassifyLink(link)
    if type(link) ~= "string" or ns.IsSecret(link) then
        return nil
    end
    if ns.HasAPI("C_Item.GetItemInfoInstant") then
        local ok, _, _, _, equipLoc, _, classID = xpcall(function() return C_Item.GetItemInfoInstant(link) end, geterrorhandler())
        if not ok then
            return false
        end
        if ns.IsSecret(equipLoc) or ns.IsSecret(classID) then
            return nil
        end
        if classID ~= nil then
            return IL.IsEquipment(classID, equipLoc)
        end
    end
    if ns.HasAPI("C_Item.GetItemInfo") then
        local ok, _, _, _, _, _, _, _, _, equipLoc, _, _, classID = xpcall(function() return C_Item.GetItemInfo(link) end, geterrorhandler())
        if not ok then
            return false
        end
        if ns.IsSecret(equipLoc) or ns.IsSecret(classID) then
            return nil
        end
        if classID ~= nil then
            return IL.IsEquipment(classID, equipLoc)
        end
    end
    return nil
end

-- 착용 장비 링크, dik, 2026-10-02
function IL.GetEquippedLink(slot)
    if not ns.HasAPI("GetInventoryItemLink") then
        return nil
    end
    local ok, link = xpcall(function() return GetInventoryItemLink("player", slot) end, geterrorhandler())
    if not ok or type(link) ~= "string" or ns.IsSecret(link) then
        return nil
    end
    return link
end

-- 품질 값 검증, dik, 2026-10-02
local function PlainQuality(value)
    if IsPlainNumber(value) then
        return value
    end
    return nil
end

-- 착용 장비 품질, dik, 2026-10-02
function IL.GetEquippedQuality(slot, link)
    if ns.HasAPI("GetInventoryItemQuality") then
        local ok, quality = xpcall(function() return GetInventoryItemQuality("player", slot) end, geterrorhandler())
        if ok and PlainQuality(quality) then
            return quality
        end
    end
    if type(link) == "string" and not ns.IsSecret(link) and ns.HasAPI("C_Item.GetItemInfo") then
        local ok, _, _, quality = xpcall(function() return C_Item.GetItemInfo(link) end, geterrorhandler())
        if ok then
            return PlainQuality(quality)
        end
    end
    return nil
end

-- 가방 칸 아이템 정보, dik, 2026-10-02
function IL.GetBagItem(bag, slot)
    if not ns.HasAPI("C_Container.GetContainerItemInfo") then
        return nil, nil, nil
    end
    local ok, info = xpcall(function() return C_Container.GetContainerItemInfo(bag, slot) end, geterrorhandler())
    if not ok or type(info) ~= "table" or ns.IsSecret(info) then
        return nil, nil, nil
    end
    local link, quality, itemId = info.hyperlink, info.quality, info.itemID
    if type(link) ~= "string" or ns.IsSecret(link) then
        return nil, nil, nil
    end
    return link, PlainQuality(quality), PlainQuality(itemId)
end

-- 가방 칸 수, dik, 2026-10-02
function IL.GetBagSlotCount(bag)
    if not ns.HasAPI("C_Container.GetContainerNumSlots") then
        return 0
    end
    local ok, count = xpcall(function() return C_Container.GetContainerNumSlots(bag) end, geterrorhandler())
    if not ok or not IsPlainNumber(count) or count < 0 then
        return 0
    end
    return math.floor(count)
end

-- 최대 가방 번호, dik, 2026-10-02
function IL.GetMaxBag()
    if IsPlainNumber(NUM_BAG_SLOTS) then
        return NUM_BAG_SLOTS
    end
    return IL.DEFAULT_BAG_SLOTS
end

-- 부분별 사용 불가 사유, dik, 2026-10-02
function IL.GetUnavailableReason(part)
    local needed
    if part == "character" then
        needed = { "GetInventoryItemLink" }
    elseif part == "bags" then
        needed = { "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots" }
    else
        return nil
    end
    local missing = ns.GetMissingAPIs(needed)
    if #missing == 0 then
        return nil
    end
    return L.SETTING_ILVL_UNAVAILABLE:format(ns.FormatMissingAPIs(missing))
end

-- 부분 사용 가능 여부, dik, 2026-10-02
function IL.IsPartAvailable(part)
    return IL.GetUnavailableReason(part) == nil
end

ns.RegisterModule({
    id = "itemLevel",
    title = L.MODULE_ITEMLEVEL,
    description = L.MODULE_ITEMLEVEL_DESC,
    category = "display",
    order = 85,
    requires = { "C_Item.GetItemInfo" },
    settings = {
        { key = "showCharacter", type = "checkbox", label = L.SETTING_ILVL_CHARACTER, tooltip = L.SETTING_ILVL_CHARACTER_TIP,
          default = true, unavailable = function() return ns.ItemLevel.GetUnavailableReason("character") end },
        { key = "showBags", type = "checkbox", label = L.SETTING_ILVL_BAGS, tooltip = L.SETTING_ILVL_BAGS_TIP,
          default = true, unavailable = function() return ns.ItemLevel.GetUnavailableReason("bags") end },
        { key = "qualityColor", type = "checkbox", label = L.SETTING_ILVL_QUALITY, tooltip = L.SETTING_ILVL_QUALITY_TIP,
          default = true },
    },
})
