-- 가방 아이콘 표시 모듈 등록·판정 규칙·어댑터, dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "bagIcons"
local QUALITY_POOR = 0
local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4
local RED_MIN_R = 0.9
local RED_MAX_GB = 0.2
local CACHE_MAX = 500

ns.BagIcons = {
    MODULE_ID = MODULE_ID,
    QUALITY_POOR = QUALITY_POOR,
    ITEM_CLASS_WEAPON = ITEM_CLASS_WEAPON,
    ITEM_CLASS_ARMOR = ITEM_CLASS_ARMOR,
    RED_MIN_R = RED_MIN_R,
    RED_MAX_GB = RED_MAX_GB,
    CACHE_MAX = CACHE_MAX,
}

local cache = {}
local cacheCount = 0
local pending = {}

-- 비 secret number 판정, dik, 2026-10-02
local function IsPlainNumber(value)
    return type(value) == "number" and not ns.IsSecret(value)
end

-- 비 secret string 판정, dik, 2026-10-02
local function IsPlainString(value)
    return type(value) == "string" and not ns.IsSecret(value)
end

-- 잡템 판정, dik, 2026-10-02
function ns.BagIcons.IsJunk(quality)
    return IsPlainNumber(quality) and quality == QUALITY_POOR
end

-- 장비 분류 판정, dik, 2026-10-02
function ns.BagIcons.IsEquipmentClass(classID)
    return IsPlainNumber(classID) and (classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR)
end

-- 빨간 색 판정, dik, 2026-10-02
function ns.BagIcons.IsRedColor(color)
    if type(color) ~= "table" or ns.IsSecret(color) then
        return false
    end
    local r, g, b = color.r, color.g, color.b
    if not (IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b)) then
        return false
    end
    return r >= RED_MIN_R and g <= RED_MAX_GB and b <= RED_MAX_GB
end

-- 툴팁 줄 빨간 글자 판정, dik, 2026-10-02
function ns.BagIcons.HasRedLine(lines)
    if type(lines) ~= "table" or ns.IsSecret(lines) then
        return false
    end
    for i = 2, #lines do
        local line = lines[i]
        if type(line) == "table" and not ns.IsSecret(line) then
            if ns.BagIcons.IsRedColor(line.leftColor) or ns.BagIcons.IsRedColor(line.rightColor) then
                return true
            end
        end
    end
    return false
end

-- 요구 레벨 초과 판정, dik, 2026-10-02
function ns.BagIcons.IsLevelTooHigh(minLevel, playerLevel)
    return IsPlainNumber(minLevel) and IsPlainNumber(playerLevel) and minLevel > playerLevel
end

-- 칸별 흑백·빨강 원하는 상태 계산, dik, 2026-10-02
function ns.BagIcons.Decide(s)
    if type(s) ~= "table" or s.empty then
        return false, false
    end
    local wantGrey = s.greyOn == true and ns.BagIcons.IsJunk(s.quality)
    local wantRed = s.redOn == true and ns.BagIcons.IsEquipmentClass(s.classID) and s.unusable == true
    return wantGrey, wantRed
end

-- 판정 방식 결정, dik, 2026-10-02
function ns.BagIcons.GetJudgeMethod()
    if ns.HasAPI("C_TooltipInfo.GetBagItem") then
        return "tooltip"
    end
    if ns.HasAPI("C_Item.GetItemInfo") and ns.HasAPI("UnitLevel") then
        return "level"
    end
    return nil
end

-- 판정 수단 없음 안내 문구, dik, 2026-10-02
function ns.BagIcons.GetUnusableUnavailableReason()
    if ns.BagIcons.GetJudgeMethod() ~= nil then
        return nil
    end
    return L.SETTING_BAGICONS_UNUSABLE_UNAVAILABLE:format(
        ns.FormatMissingAPIs({ "C_TooltipInfo.GetBagItem", "C_Item.GetItemInfo" }))
end

-- 칸 정보 읽기 어댑터, dik, 2026-10-02
function ns.BagIcons.ReadSlot(bag, slot)
    if not ns.HasAPI("C_Container.GetContainerItemInfo") then
        return { empty = true }
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" or ns.IsSecret(info) then
        return { empty = true }
    end
    local result = { empty = false }
    if IsPlainNumber(info.quality) then
        result.quality = info.quality
    end
    if IsPlainNumber(info.itemID) then
        result.itemID = info.itemID
    end
    if IsPlainString(info.hyperlink) then
        result.link = info.hyperlink
    end
    if type(info.isLocked) == "boolean" and not ns.IsSecret(info.isLocked) then
        result.isLocked = info.isLocked
    end
    if result.itemID and ns.HasAPI("C_Item.GetItemInfoInstant") then
        local classID = select(6, C_Item.GetItemInfoInstant(result.itemID))
        if IsPlainNumber(classID) then
            result.classID = classID
        end
    end
    return result
end

-- 캐시 저장(상한 초과 시 비움), dik, 2026-10-02
local function StoreCache(key, value)
    if cache[key] == nil then
        if cacheCount >= CACHE_MAX then
            cache = {}
            cacheCount = 0
        end
        cacheCount = cacheCount + 1
    end
    cache[key] = value
end

-- 못 쓰는 장비 판정(nil = 보류), dik, 2026-10-02
function ns.BagIcons.JudgeUnusable(bag, slot, itemID, link)
    local key
    if IsPlainString(link) then
        key = link
    elseif IsPlainNumber(itemID) then
        key = itemID
    else
        return nil
    end
    if cache[key] ~= nil then
        return cache[key]
    end
    local method = ns.BagIcons.GetJudgeMethod()
    if method == nil then
        return nil
    end
    if IsPlainNumber(itemID) and ns.HasAPI("C_Item.GetItemInfo") and C_Item.GetItemInfo(itemID) == nil then
        pending[itemID] = true
        if ns.HasAPI("C_Item.RequestLoadItemDataByID") then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    local result
    if method == "tooltip" then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if type(data) ~= "table" or ns.IsSecret(data) then
            return nil
        end
        local lines = data.lines
        if type(lines) ~= "table" or ns.IsSecret(lines) or #lines < 2 then
            return nil
        end
        result = ns.BagIcons.HasRedLine(lines)
    else
        if not IsPlainNumber(itemID) then
            return nil
        end
        result = ns.BagIcons.IsLevelTooHigh(select(5, C_Item.GetItemInfo(itemID)), UnitLevel("player"))
    end
    StoreCache(key, result)
    return result
end

-- 판정 캐시·보류 비움, dik, 2026-10-02
function ns.BagIcons.ClearCache()
    cache = {}
    cacheCount = 0
    pending = {}
end

-- 보류 항목 회수, dik, 2026-10-02
function ns.BagIcons.TakePending(itemID)
    if pending[itemID] then
        pending[itemID] = nil
        return true
    end
    return false
end

ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_BAGICONS,
    description = L.MODULE_BAGICONS_DESC,
    category = "display",
    order = 86,
    requires = { "C_Container.GetContainerItemInfo", "C_Item.GetItemInfoInstant", "InCombatLockdown" },
    settings = {
        { key = "greyDesaturate", type = "checkbox", label = L.SETTING_BAGICONS_GREY,
          tooltip = L.SETTING_BAGICONS_GREY_TIP, default = true },
        { key = "unusableTint", type = "checkbox", label = L.SETTING_BAGICONS_UNUSABLE,
          tooltip = L.SETTING_BAGICONS_UNUSABLE_TIP, default = true,
          unavailable = function() return ns.BagIcons.GetUnusableUnavailableReason() end },
    },
})
