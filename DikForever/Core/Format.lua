-- 표시 형식 유틸(숫자·금액·퍼센트·시간), dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

-- 유한한 number 판정, dik, 2026-09-30
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 정수부 세 자리 구분(0 쪽으로 버림), dik, 2026-09-30
function ns.FormatNumber(n)
    if not IsNumber(n) then
        return L.VALUE_UNKNOWN
    end
    local int = math.floor(math.abs(n))
    local text = string.format("%.0f", int)
    local sign = ""
    if n < 0 and int ~= 0 then
        sign = "-"
    end
    local grouped = ""
    while #text > 3 do
        grouped = "," .. text:sub(-3) .. grouped
        text = text:sub(1, -4)
    end
    return sign .. text .. grouped
end

-- 동전 단위를 금·은·동 문자열로, dik, 2026-09-30
function ns.FormatMoney(copper)
    if not IsNumber(copper) then
        return L.VALUE_UNKNOWN
    end
    local c = math.floor(math.abs(copper))
    local gold = math.floor(c / 10000)
    local silver = math.floor((c % 10000) / 100)
    local rest = c % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format(L.FMT_GOLD, ns.FormatNumber(gold))
    end
    if silver > 0 then
        parts[#parts + 1] = string.format(L.FMT_SILVER, silver)
    end
    if rest > 0 then
        parts[#parts + 1] = string.format(L.FMT_COPPER, rest)
    end
    if #parts == 0 then
        return string.format(L.FMT_COPPER, 0)
    end
    local text = table.concat(parts, " ")
    if copper < 0 and c > 0 then
        return "-" .. text
    end
    return text
end

-- 비율을 소수 1자리 버림 퍼센트로, dik, 2026-09-30
function ns.FormatPercent(ratio)
    if not IsNumber(ratio) then
        return L.VALUE_UNKNOWN
    end
    local r = ratio
    if r < 0 then
        r = 0
    end
    return string.format("%.1f%%", math.floor(r * 1000 + 1e-9) / 10)
end

-- 초를 큰 단위 2개로, dik, 2026-09-30
function ns.FormatDuration(seconds)
    if not IsNumber(seconds) then
        return L.VALUE_UNKNOWN
    end
    local s = math.floor(math.max(0, seconds))
    local days = math.floor(s / 86400)
    local hours = math.floor((s % 86400) / 3600)
    local minutes = math.floor((s % 3600) / 60)
    if days > 0 then
        if hours > 0 then
            return string.format(L.FMT_DAYS, days) .. " " .. string.format(L.FMT_HOURS, hours)
        end
        return string.format(L.FMT_DAYS, days)
    end
    if hours > 0 then
        if minutes > 0 then
            return string.format(L.FMT_HOURS, hours) .. " " .. string.format(L.FMT_MINUTES, minutes)
        end
        return string.format(L.FMT_HOURS, hours)
    end
    if minutes > 0 then
        return string.format(L.FMT_MINUTES, minutes)
    end
    return string.format(L.FMT_SECONDS, s % 60)
end

-- 경과 시간 문구(가장 큰 단위 하나), dik, 2026-09-30
function ns.FormatElapsed(timestamp, now)
    if not IsNumber(timestamp) then
        return L.VALUE_UNKNOWN
    end
    local current = now
    if not IsNumber(current) then
        if not ns.HasAPI("time") then
            return L.VALUE_UNKNOWN
        end
        current = time()
        if not IsNumber(current) then
            return L.VALUE_UNKNOWN
        end
    end
    local diff = current - timestamp
    if diff < 60 then
        return L.ELAPSED_JUST_NOW
    end
    local text
    if diff < 3600 then
        text = string.format(L.FMT_MINUTES, math.floor(diff / 60))
    elseif diff < 86400 then
        text = string.format(L.FMT_HOURS, math.floor(diff / 3600))
    else
        text = string.format(L.FMT_DAYS, math.floor(diff / 86400))
    end
    return string.format(L.ELAPSED_AGO, text)
end

-- 일시 문자열, dik, 2026-09-30
function ns.FormatDateTime(timestamp)
    if IsNumber(timestamp) and ns.HasAPI("date") then
        -- date 결과 문자열 검사, dik, 2026-09-30
        local text = date("%Y-%m-%d %H:%M", timestamp)
        if type(text) == "string" then
            return text
        end
    end
    return L.VALUE_UNKNOWN
end

-- 직업 바 색 덮어쓰기 표, dik, 2026-10-02
ns.CLASS_BAR_OVERRIDES = { ROGUE = { r = 0.72, g = 0.53, b = 0.04 } }

-- 직업 바 색 조회, dik, 2026-10-02
function ns.ClassBarColor(classFile, classColors)
    if ns.IsSecret(classFile) or type(classFile) ~= "string" then
        return nil
    end
    local o = ns.CLASS_BAR_OVERRIDES[classFile]
    if o then
        return o.r, o.g, o.b
    end
    if classColors == nil then
        classColors = RAID_CLASS_COLORS
    end
    if type(classColors) ~= "table" then
        return nil
    end
    local c = classColors[classFile]
    if type(c) ~= "table" or not IsNumber(c.r) or not IsNumber(c.g) or not IsNumber(c.b) then
        return nil
    end
    return c.r, c.g, c.b
end

-- 바 색 밝기 상한, dik, 2026-10-02
ns.BAR_LUMINANCE_MAX = 0.65

-- 바 색 가독성 보정(밝기 상한), dik, 2026-10-02
function ns.ReadableBarColor(r, g, b)
    if ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) then
        return r, g, b
    end
    if not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then
        return r, g, b
    end
    local y = 0.299 * r + 0.587 * g + 0.114 * b
    if y <= ns.BAR_LUMINANCE_MAX then
        return r, g, b
    end
    local k = ns.BAR_LUMINANCE_MAX / y
    return r * k, g * k, b * k
end
