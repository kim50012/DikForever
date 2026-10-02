-- 이벤트 버스와 채팅 출력, dik, 2026-09-30
local addonName, ns = ...

local subscribers = {}

-- 이벤트 구독 등록, dik, 2026-09-30
function ns.On(event, fn)
    if type(fn) ~= "function" then
        return
    end
    local list = subscribers[event]
    if not list then
        list = {}
        subscribers[event] = list
    end
    list[#list + 1] = fn
end

-- 이벤트 발행, dik, 2026-09-30
function ns.Fire(event, ...)
    local list = subscribers[event]
    if not list then
        return
    end
    local n = select("#", ...)
    local args = { ... }
    local count = #list
    for i = 1, count do
        local fn = list[i]
        xpcall(function()
            fn(unpack(args, 1, n))
        end, geterrorhandler())
    end
end

-- 채팅 출력, dik, 2026-09-30
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[DikForever]|r " .. tostring(msg))
end
