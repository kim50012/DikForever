-- 설정 이전용 표 직렬화·역직렬화(Base64+체크섬), dik, 2026-10-02
local addonName, ns = ...

ns.Serialize = {}

local PREFIX = "DIKF1!"
local MAX_LEN = 200000
local MAX_DEPTH = 12
local MAX_NODES = 20000
local MAX_STRING = 20000
local CHECKSUM_MOD = 16777213
local CHECKSUM_PERIOD = 97
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local byte, char, sub, format = string.byte, string.char, string.sub, string.format
local concat = table.concat
local floor = math.floor
local HUGE = math.huge

local B64_ENCODE = {}
local B64_DECODE = {}
for i = 1, #B64_CHARS do
    local c = sub(B64_CHARS, i, i)
    B64_ENCODE[i - 1] = c
    B64_DECODE[byte(c)] = i - 1
end

-- 체크섬 계산, dik, 2026-10-02
local function Checksum(body)
    local sum = 0
    local n = #body
    local i = 1
    while i <= n do
        local last = i + 4095
        if last > n then
            last = n
        end
        local bytes = { byte(body, i, last) }
        for j = 1, #bytes do
            sum = (sum + bytes[j] * (((i + j - 2) % CHECKSUM_PERIOD) + 1)) % CHECKSUM_MOD
        end
        i = last + 1
    end
    return sum
end

-- Base64 인코딩, dik, 2026-10-02
local function Base64Encode(data)
    local out = {}
    local n = #data
    local count = 0
    for i = 1, n, 3 do
        local a, b, c = byte(data, i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(v / 262144)
        local c2 = floor(v / 4096) % 64
        local c3 = floor(v / 64) % 64
        local c4 = v % 64
        count = count + 1
        if c == nil then
            if b == nil then
                out[count] = B64_ENCODE[c1] .. B64_ENCODE[c2] .. "=="
            else
                out[count] = B64_ENCODE[c1] .. B64_ENCODE[c2] .. B64_ENCODE[c3] .. "="
            end
        else
            out[count] = B64_ENCODE[c1] .. B64_ENCODE[c2] .. B64_ENCODE[c3] .. B64_ENCODE[c4]
        end
    end
    return concat(out)
end

-- Base64 디코딩(실패 시 nil), dik, 2026-10-02
local function Base64Decode(text)
    local n = #text
    if n == 0 or n % 4 ~= 0 then
        return nil
    end
    local out = {}
    local count = 0
    for i = 1, n, 4 do
        local a, b, c, d = byte(text, i, i + 3)
        local isLast = (i + 3 == n)
        local va, vb = B64_DECODE[a], B64_DECODE[b]
        if va == nil or vb == nil then
            return nil
        end
        local vc, vd
        if c == 61 then
            if not isLast or d ~= 61 then
                return nil
            end
            local v = va * 4 + floor(vb / 16)
            count = count + 1
            out[count] = char(v)
        else
            vc = B64_DECODE[c]
            if vc == nil then
                return nil
            end
            if d == 61 then
                if not isLast then
                    return nil
                end
                local v = va * 1024 + vb * 16 + floor(vc / 4)
                count = count + 1
                out[count] = char(floor(v / 256), v % 256)
            else
                vd = B64_DECODE[d]
                if vd == nil then
                    return nil
                end
                local v = va * 262144 + vb * 4096 + vc * 64 + vd
                count = count + 1
                out[count] = char(floor(v / 65536), floor(v / 256) % 256, v % 256)
            end
        end
    end
    return concat(out)
end

-- 바이트 단위 문자열 비교(로케일 무관), dik, 2026-10-02
local function ByteLess(a, b)
    local la, lb = #a, #b
    local m = la < lb and la or lb
    for i = 1, m do
        local x, y = byte(a, i), byte(b, i)
        if x ~= y then
            return x < y
        end
    end
    return la < lb
end

-- 유한 숫자 판정, dik, 2026-10-02
local function IsFinite(v)
    return v == v and v ~= HUGE and v ~= -HUGE
end

-- 값 하나를 버퍼에 직렬화(실패 시 false), dik, 2026-10-02
local function EncodeValue(v, depth, buf)
    local t = type(v)
    if t == "boolean" then
        buf[#buf + 1] = v and "T" or "F"
        return true
    elseif t == "number" then
        if not IsFinite(v) then
            return false
        end
        buf[#buf + 1] = "N" .. format("%.14g", v) .. ";"
        return true
    elseif t == "string" then
        if #v > MAX_STRING then
            return false
        end
        buf[#buf + 1] = "S" .. #v .. ":" .. v
        return true
    elseif t == "table" then
        if depth > MAX_DEPTH then
            return false
        end
        local numKeys, strKeys = {}, {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "number" and IsFinite(k) then
                numKeys[#numKeys + 1] = k
            elseif kt == "string" then
                strKeys[#strKeys + 1] = k
            else
                return false
            end
        end
        table.sort(numKeys)
        table.sort(strKeys, ByteLess)
        buf[#buf + 1] = "{"
        for i = 1, #numKeys do
            local k = numKeys[i]
            buf[#buf + 1] = "N" .. format("%.14g", k) .. ";"
            if not EncodeValue(v[k], depth + 1, buf) then
                return false
            end
        end
        for i = 1, #strKeys do
            local k = strKeys[i]
            if #k > MAX_STRING then
                return false
            end
            buf[#buf + 1] = "S" .. #k .. ":" .. k
            if not EncodeValue(v[k], depth + 1, buf) then
                return false
            end
        end
        buf[#buf + 1] = "}"
        return true
    end
    return false
end

-- 표를 이전 문자열로 변환, dik, 2026-10-02
function ns.Serialize.Encode(tbl)
    if type(tbl) ~= "table" then
        return nil, "E-FMT"
    end
    local buf = {}
    if not EncodeValue(tbl, 1, buf) then
        return nil, "E-FMT"
    end
    local body = concat(buf)
    local text = PREFIX .. format("%06X", Checksum(body)) .. "!" .. Base64Encode(body)
    if #text > MAX_LEN then
        return nil, "E-LEN"
    end
    return text
end

local ParseValue

-- 숫자 토큰 해석(실패 시 nil), dik, 2026-10-02
local function ParseNumber(ctx)
    local s, pos = ctx.s, ctx.pos
    local close = string.find(s, ";", pos + 1, true)
    if not close then
        return nil
    end
    local token = sub(s, pos + 1, close - 1)
    if token == "" or not string.find(token, "^[%d%.eE%+%-]+$") then
        return nil
    end
    local v = tonumber(token)
    if v == nil or not IsFinite(v) then
        return nil
    end
    ctx.pos = close + 1
    return v
end

-- 문자열 토큰 해석(실패 시 nil), dik, 2026-10-02
local function ParseString(ctx)
    local s, pos = ctx.s, ctx.pos
    local digits, colon = string.match(s, "^(%d+)():", pos + 1)
    if not digits or #digits > 5 then
        return nil
    end
    local len = tonumber(digits)
    if len > MAX_STRING then
        return nil
    end
    local start = colon + 1
    if start + len - 1 > #s then
        return nil
    end
    ctx.pos = start + len
    return sub(s, start, start + len - 1)
end

-- 값 하나 재귀 해석(성공 여부, 값), dik, 2026-10-02
ParseValue = function(ctx, depth)
    ctx.nodes = ctx.nodes + 1
    if ctx.nodes > MAX_NODES then
        return false
    end
    local s = ctx.s
    local c = sub(s, ctx.pos, ctx.pos)
    if c == "T" then
        ctx.pos = ctx.pos + 1
        return true, true
    elseif c == "F" then
        ctx.pos = ctx.pos + 1
        return true, false
    elseif c == "N" then
        local v = ParseNumber(ctx)
        if v == nil then
            return false
        end
        return true, v
    elseif c == "S" then
        local v = ParseString(ctx)
        if v == nil then
            return false
        end
        return true, v
    elseif c == "{" then
        if depth > MAX_DEPTH then
            return false
        end
        ctx.pos = ctx.pos + 1
        local result = {}
        while true do
            local k = sub(s, ctx.pos, ctx.pos)
            if k == "}" then
                ctx.pos = ctx.pos + 1
                return true, result
            end
            if k ~= "S" and k ~= "N" then
                return false
            end
            ctx.nodes = ctx.nodes + 1
            if ctx.nodes > MAX_NODES then
                return false
            end
            local key
            if k == "S" then
                key = ParseString(ctx)
            else
                key = ParseNumber(ctx)
            end
            if key == nil then
                return false
            end
            local ok, value = ParseValue(ctx, depth + 1)
            if not ok then
                return false
            end
            result[key] = value
        end
    end
    return false
end

-- 이전 문자열을 표로 복원, dik, 2026-10-02
function ns.Serialize.Decode(text)
    if type(text) ~= "string" then
        return nil, "E-FMT"
    end
    local clean = text:gsub("[ \t\r\n]", "")
    if #clean > MAX_LEN then
        return nil, "E-LEN"
    end
    if sub(clean, 1, #PREFIX) ~= PREFIX then
        local ver = string.match(clean, "^DIKF(%d+)!")
        if ver and tonumber(ver) ~= 1 then
            return nil, "E-VER"
        end
        return nil, "E-FMT"
    end
    local sumText, rest = string.match(sub(clean, #PREFIX + 1), "^(%x%x%x%x%x%x)!(.*)$")
    if not sumText then
        return nil, "E-FMT"
    end
    local body = Base64Decode(rest)
    if not body then
        return nil, "E-FMT"
    end
    if Checksum(body) ~= tonumber(sumText, 16) then
        return nil, "E-SUM"
    end
    local ctx = { s = body, pos = 1, nodes = 0 }
    if sub(body, 1, 1) ~= "{" then
        return nil, "E-FMT"
    end
    local ok, value = ParseValue(ctx, 1)
    if not ok or ctx.pos ~= #body + 1 then
        return nil, "E-FMT"
    end
    return value
end
