-- 아이템 툴팁 줄 공급자 레지스트리·줄 조립, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.TooltipLines = {}

local PROVIDER_LINE_MAX = 12
local TOTAL_LINE_MAX = 20
local DEFAULT_ORDER = 100
local ITEM_PATTERN = "item:(%d+)"

local providers = {}

-- 유한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 양의 정수 판정, dik, 2026-10-01
local function IsPositiveInt(v)
    return IsNumber(v) and math.floor(v) == v and v > 0
end

-- nil 또는 string 판정, dik, 2026-10-01
local function IsOptString(v)
    return v == nil or type(v) == "string"
end

-- nil 또는 r·g·b 가 number 인 table 판정, dik, 2026-10-01
local function IsOptColor(v)
    if v == nil then
        return true
    end
    return type(v) == "table" and type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number"
end

-- 유효한 줄 판정, dik, 2026-10-01
local function IsValidLine(line)
    return type(line) == "table" and type(line.left) == "string" and line.left ~= ""
        and IsOptString(line.right) and IsOptString(line.leftToken) and IsOptString(line.rightToken)
        and IsOptColor(line.leftColor) and IsOptColor(line.rightColor)
end

-- 색 table 복사, dik, 2026-10-01
local function CopyColor(c)
    if c == nil then
        return nil
    end
    return { r = c.r, g = c.g, b = c.b }
end

-- 줄 새 테이블 복사, dik, 2026-10-01
local function CopyLine(line)
    return {
        left = line.left,
        right = line.right,
        leftToken = line.leftToken,
        rightToken = line.rightToken,
        leftColor = CopyColor(line.leftColor),
        rightColor = CopyColor(line.rightColor),
    }
end

-- 아이템 줄 공급자 등록, dik, 2026-10-01
function ns.TooltipLines.RegisterItem(def)
    local id = type(def) == "table" and def.id or nil
    if type(id) ~= "string" or id == "" or providers[id] or type(def.Get) ~= "function" then
        ns.Print(L.ERR_TOOLTIP_PROVIDER:format(type(id) == "string" and id or "?"))
        return false
    end
    if not IsNumber(def.order) then
        def.order = DEFAULT_ORDER
    end
    providers[id] = def
    ns.Fire("TOOLTIP_PROVIDER_ADDED", id)
    return true
end

-- 등록된 공급자 유무, dik, 2026-10-01
function ns.TooltipLines.HasItemProviders()
    return next(providers) ~= nil
end

-- 공급자 정렬 목록(order 오름차순·같으면 id), dik, 2026-10-01
local function SortedProviders()
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

-- 아이템 툴팁 줄 조립(매번 새 배열), dik, 2026-10-01
function ns.TooltipLines.BuildItem(itemId, link)
    local result = {}
    if not IsPositiveInt(itemId) then
        return result
    end
    local list = SortedProviders()
    for i = 1, #list do
        local def = list[i]
        local ok, lines = xpcall(def.Get, geterrorhandler(), itemId, link)
        if ok and type(lines) == "table" then
            local taken = 0
            for j = 1, #lines do
                if taken >= PROVIDER_LINE_MAX or #result >= TOTAL_LINE_MAX then
                    break
                end
                if IsValidLine(lines[j]) then
                    taken = taken + 1
                    result[#result + 1] = CopyLine(lines[j])
                end
            end
        end
        if #result >= TOTAL_LINE_MAX then
            break
        end
    end
    return result
end

-- 아이템 id 추출(number 또는 링크 string), dik, 2026-10-01
function ns.TooltipLines.ParseItemId(v)
    if type(v) == "number" then
        if IsPositiveInt(v) then
            return v
        end
        return nil
    end
    if type(v) == "string" then
        local captured = v:match(ITEM_PATTERN)
        local n = captured and tonumber(captured) or nil
        if n and n > 0 then
            return n
        end
    end
    return nil
end
