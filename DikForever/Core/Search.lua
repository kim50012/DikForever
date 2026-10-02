-- 기능 검색 색인·정규화·매칭·순위, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.Search = { MAX_RESULTS = 10 }

local GLOBAL_SCOPE = "global"
local AUTO_ENABLED_KEY = "enabled"

local index = nil

-- 검색어 정규화, dik, 2026-10-01
function ns.Search.Normalize(s)
    if type(s) ~= "string" then
        return ""
    end
    local text = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (string.lower(text):gsub("%s", ""))
end

-- 검색어 토큰화, dik, 2026-10-01
function ns.Search.Tokenize(query)
    local tokens = {}
    if type(query) ~= "string" then
        return tokens
    end
    local trimmed = query:match("^%s*(.-)%s*$")
    for piece in trimmed:gmatch("%S+") do
        local token = ns.Search.Normalize(piece)
        if token ~= "" then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

-- 모든 토큰이 필드 중 하나에 있는지 판정, dik, 2026-10-01
function ns.Search.Matches(tokens, fields)
    if type(tokens) ~= "table" or #tokens == 0 or type(fields) ~= "table" then
        return false
    end
    for i = 1, #tokens do
        local found = false
        for j = 1, #fields do
            if type(fields[j]) == "string" and string.find(fields[j], tokens[i], 1, true) then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- 색인 항목 추가, dik, 2026-10-01
local function AddEntry(list, entry)
    entry.seq = #list + 1
    entry.normTitle = ns.Search.Normalize(entry.title)
    entry.normBody = ns.Search.Normalize(entry.body)
    list[#list + 1] = entry
end

-- 색인 구성, dik, 2026-10-01
local function BuildIndex()
    local list = {}
    local modules = ns.GetAllModules()
    for i = 1, #modules do
        local module = modules[i]
        AddEntry(list, {
            kind = "module",
            moduleId = module.id,
            scope = module.id,
            group = module.title,
            title = module.title,
            body = module.description,
        })
    end
    local globalDefs = ns.GetSettingDefs(GLOBAL_SCOPE)
    for i = 1, #globalDefs do
        local def = globalDefs[i]
        AddEntry(list, {
            kind = "setting",
            scope = GLOBAL_SCOPE,
            key = def.key,
            group = L.SECTION_GENERAL,
            title = def.label,
            body = def.tooltip,
        })
    end
    for i = 1, #modules do
        local module = modules[i]
        local defs = ns.GetSettingDefs(module.id)
        for j = 1, #defs do
            local def = defs[j]
            if def.key ~= AUTO_ENABLED_KEY then
                AddEntry(list, {
                    kind = "setting",
                    moduleId = module.id,
                    scope = module.id,
                    key = def.key,
                    group = module.title,
                    title = def.label,
                    body = def.tooltip,
                })
            end
        end
    end
    return list
end

-- 순위 계산(작을수록 위), dik, 2026-10-01
local function GetRank(entry, tokens)
    local inTitle = ns.Search.Matches(tokens, { entry.normTitle })
    if entry.kind == "module" then
        return inTitle and 1 or 2
    end
    return inTitle and 3 or 4
end

-- 기능 검색, dik, 2026-10-01
function ns.Search.Find(query, limit)
    local tokens = ns.Search.Tokenize(query)
    if #tokens == 0 then
        return {}, 0
    end
    if not index then
        index = BuildIndex()
    end
    local maxCount = limit
    if type(maxCount) ~= "number" or maxCount < 0 then
        maxCount = ns.Search.MAX_RESULTS
    end

    local matched = {}
    for i = 1, #index do
        local entry = index[i]
        if ns.Search.Matches(tokens, { entry.normTitle, entry.normBody }) then
            matched[#matched + 1] = { entry = entry, rank = GetRank(entry, tokens) }
        end
    end
    table.sort(matched, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.entry.seq < b.entry.seq
    end)

    local results = {}
    for i = 1, math.min(#matched, maxCount) do
        results[i] = matched[i].entry
    end
    return results, #matched
end

-- 색인 비우기, dik, 2026-10-01
function ns.Search.Reset()
    index = nil
end
