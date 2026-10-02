-- 동작 차단 이벤트 원인 구분 공통 처리, dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

ns.ActionBlock = {}

local EVENT_NAMES = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }

local owners = {}
local unknownList = {}
local records = {}
local externalNotified = false

-- 차단 함수 이름 정규화(괄호·객체 접두 제거), dik, 2026-10-02
function ns.ActionBlock.NormalizeBlockedFunc(s)
    if ns.IsSecret(s) or type(s) ~= "string" then
        return nil
    end
    local open = s:find("(", 1, true)
    if open then
        s = s:sub(1, open - 1)
    end
    s = s:match("^%s*(.-)%s*$")
    s = s:match("([^:%.]*)$")
    if s == nil or s == "" then
        return nil
    end
    return s
end

-- 차단 분류(other·unknown·owned·external), dik, 2026-10-02
function ns.ActionBlock.ClassifyBlocked(arg1, arg2, addon, ownerMap, unknownIds)
    if ns.IsSecret(arg1) or arg1 ~= addon then
        return "other", {}, nil
    end
    local fn = ns.ActionBlock.NormalizeBlockedFunc(arg2)
    if fn == nil then
        return "unknown", unknownIds, nil
    end
    local list = ownerMap[fn]
    if list ~= nil and #list > 0 then
        return "owned", list, fn
    end
    return "external", {}, fn
end

-- 모듈 소유 함수·차단 콜백 등록(중복 시 이름만 병합), dik, 2026-10-02
function ns.ActionBlock.Register(moduleId, funcNames, onBlocked, opts)
    if type(moduleId) ~= "string" or type(funcNames) ~= "table" then
        return
    end
    local rec = records[moduleId]
    if rec == nil then
        if type(onBlocked) ~= "function" then
            return
        end
        rec = { onBlocked = onBlocked, notified = false, names = {} }
        records[moduleId] = rec
        if not (type(opts) == "table" and opts.stopOnUnknown == false) then
            unknownList[#unknownList + 1] = moduleId
        end
    end
    for i = 1, #funcNames do
        local name = funcNames[i]
        if type(name) == "string" and name ~= "" and not rec.names[name] then
            rec.names[name] = true
            local list = owners[name]
            if list == nil then
                list = {}
                owners[name] = list
            end
            list[#list + 1] = moduleId
        end
    end
end

-- 대상 모듈 콜백 모듈별 최초 1회 호출, dik, 2026-10-02
local function NotifyModules(modules, funcName, kind)
    for i = 1, #modules do
        local rec = records[modules[i]]
        if rec ~= nil and not rec.notified then
            rec.notified = true
            xpcall(function() rec.onBlocked(funcName, kind) end, geterrorhandler())
        end
    end
end

-- 차단 이벤트 처리, dik, 2026-10-02
local function OnEvent(_, _, arg1, arg2)
    local kind, modules, funcName = ns.ActionBlock.ClassifyBlocked(arg1, arg2, addonName, owners, unknownList)
    if kind == "owned" or kind == "unknown" then
        NotifyModules(modules, funcName, kind)
    elseif kind == "external" then
        if not externalNotified then
            externalNotified = true
            ns.Print(L.MSG_ACTION_BLOCKED_EXTERNAL:format(funcName))
        end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnEvent)
for i = 1, #EVENT_NAMES do
    pcall(frame.RegisterEvent, frame, EVENT_NAMES[i])
end
