-- API 존재 검사·secret 판정 호환 유틸, dik, 2026-09-30
local addonName, ns = ...

-- API 경로 존재 여부(캐시 없음), dik, 2026-09-30
function ns.HasAPI(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local current = _G
    for part in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return false
        end
        current = current[part]
        if current == nil then
            return false
        end
    end
    return current ~= _G
end

-- 없는 API 경로 배열, dik, 2026-09-30
function ns.GetMissingAPIs(paths)
    local missing = {}
    if type(paths) ~= "table" then
        return missing
    end
    for i = 1, #paths do
        local path = paths[i]
        if type(path) == "string" and not ns.HasAPI(path) then
            missing[#missing + 1] = path
        end
    end
    return missing
end

-- secret 값 판정, dik, 2026-09-30
function ns.IsSecret(value)
    if type(issecretvalue) == "function" then
        return issecretvalue(value) == true
    end
    return false
end

-- 없는 API 표시 문자열(앞 2개 + 외 N개), dik, 2026-09-30
function ns.FormatMissingAPIs(list)
    if type(list) ~= "table" or #list == 0 then
        return ""
    end
    if #list <= 2 then
        return table.concat(list, ", ")
    end
    return ns.L.FMT_MORE_APIS:format(list[1] .. ", " .. list[2], #list - 2)
end
