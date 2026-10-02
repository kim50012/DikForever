-- 외형 수집 툴팁 모듈 등록·상태 판정·캐시·공급자, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "transmog"
local PROVIDER_ORDER = 40
local CACHE_MAX = 500
local SOURCE_SCAN_MAX = 30
local OPTIONAL_APIS = {
    otherSource = "C_TransmogCollection.GetAllAppearanceSources",
    canCollect = "C_TransmogCollection.PlayerCanCollectSource",
}
local EVENT_ORDER = {
    "TRANSMOG_COLLECTION_UPDATED",
    "TRANSMOG_COLLECTION_SOURCE_ADDED",
    "TRANSMOG_COLLECTION_SOURCE_REMOVED",
}
local STATE_COLLECTED = "collected"
local STATE_OTHER = "otherSource"
local STATE_UNCOLLECTED = "uncollected"
local STATE_UNUSABLE = "unusable"

local STATE_TEXT = {
    [STATE_COLLECTED] = { key = "TMOG_STATE_COLLECTED", token = "TEXT" },
    [STATE_OTHER] = { key = "TMOG_STATE_OTHER", token = "TEXT" },
    [STATE_UNCOLLECTED] = { key = "TMOG_STATE_UNCOLLECTED", token = "ACCENT" },
    [STATE_UNUSABLE] = { key = "TMOG_STATE_UNUSABLE", token = "TEXT_DIM" },
}

local cache = {}
local cacheSize = 0
local cacheEnabled = false
local useOtherSource = false
local useCanCollect = false
local missingList = {}

ns.Transmog = ns.Transmog or {}

-- 유한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 양의 정수 판정, dik, 2026-10-01
local function IsPositiveInt(v)
    return IsNumber(v) and math.floor(v) == v and v > 0
end

-- 외형 상태 판정 순수 함수, dik, 2026-10-01
function ns.Transmog.ResolveState(facts)
    if type(facts) ~= "table" then
        return nil
    end
    if facts.sourceCollected == true then
        return STATE_COLLECTED
    end
    if facts.appearanceCollected == true then
        return STATE_OTHER
    end
    if facts.canCollect == false then
        return STATE_UNUSABLE
    end
    return STATE_UNCOLLECTED
end

-- 툴팁 줄 생성 순수 함수, dik, 2026-10-01
function ns.Transmog.BuildTooltipLines(state, onlyUncollected)
    local info = type(state) == "string" and STATE_TEXT[state] or nil
    if info == nil then
        return nil
    end
    if onlyUncollected == true and (state == STATE_COLLECTED or state == STATE_OTHER) then
        return nil
    end
    return {
        { left = L.TMOG_TIP_LABEL, right = L[info.key], leftToken = "TEXT_DIM", rightToken = info.token },
    }
end

-- 소스 수집 여부 조회(비-secret 일 때만 boolean), dik, 2026-10-01
local function ReadSourceCollected(sourceId)
    local info = C_TransmogCollection.GetSourceInfo(sourceId)
    if ns.IsSecret(info) or type(info) ~= "table" then
        return nil
    end
    local collected = info.isCollected
    if ns.IsSecret(collected) then
        return nil
    end
    return collected == true
end

-- 같은 외형의 다른 소스 수집 여부 판정, dik, 2026-10-01
local function ScanOtherSources(appearanceId, sourceId)
    local list = C_TransmogCollection.GetAllAppearanceSources(appearanceId)
    if ns.IsSecret(list) or type(list) ~= "table" then
        return nil
    end
    local count = math.min(#list, SOURCE_SCAN_MAX)
    for i = 1, count do
        local s = list[i]
        if not ns.IsSecret(s) and IsPositiveInt(s) and s ~= sourceId then
            if ReadSourceCollected(s) == true then
                return true
            end
        end
    end
    return false
end

-- 외형 사실 수집(API 호출), dik, 2026-10-01
local function CollectFacts(arg)
    local appearanceId, sourceId = C_TransmogCollection.GetItemInfo(arg)
    if ns.IsSecret(appearanceId) or ns.IsSecret(sourceId) then
        return nil
    end
    if not IsPositiveInt(sourceId) then
        return nil
    end
    local sourceCollected = ReadSourceCollected(sourceId)
    if sourceCollected == nil then
        return nil
    end
    local appearanceCollected = nil
    if sourceCollected then
        appearanceCollected = true
    elseif useOtherSource and IsPositiveInt(appearanceId) then
        appearanceCollected = ScanOtherSources(appearanceId, sourceId)
    end
    local canCollect = nil
    if useCanCollect then
        local hasData, can = C_TransmogCollection.PlayerCanCollectSource(sourceId)
        if not ns.IsSecret(hasData) and not ns.IsSecret(can) and hasData == true then
            canCollect = (can == true)
        end
    end
    return { sourceCollected = sourceCollected, appearanceCollected = appearanceCollected, canCollect = canCollect }
end

-- 캐시 전부 비움, dik, 2026-10-01
function ns.Transmog.ClearCache()
    cache = {}
    cacheSize = 0
end

-- 아이템 외형 상태 조회(캐시 우선), dik, 2026-10-01
function ns.Transmog.GetState(itemId, link)
    if not IsPositiveInt(itemId) then
        return nil
    end
    local arg = itemId
    -- secret 검사를 빈 문자열 비교보다 먼저, dik, 2026-10-01
    if type(link) == "string" and not ns.IsSecret(link) and link ~= "" then
        arg = link
    end
    if cacheEnabled and cache[arg] ~= nil then
        return cache[arg]
    end
    local state = ns.Transmog.ResolveState(CollectFacts(arg))
    if state ~= nil and cacheEnabled then
        if cacheSize >= CACHE_MAX then
            ns.Transmog.ClearCache()
        end
        cache[arg] = state
        cacheSize = cacheSize + 1
    end
    return state
end

-- 모듈 상태 조회, dik, 2026-10-01
function ns.Transmog.GetStatus()
    local missing = {}
    for i = 1, #missingList do
        missing[i] = missingList[i]
    end
    return {
        cacheEnabled = cacheEnabled,
        cacheSize = cacheSize,
        otherSource = useOtherSource,
        canCollect = useCanCollect,
        missing = missing,
    }
end

-- 이벤트 수신(캐시 비움만), dik, 2026-10-01
local function OnEvent()
    ns.Transmog.ClearCache()
end

-- 툴팁 공급자 Get, dik, 2026-10-01
local function GetTooltipLines(itemId, link)
    if ns.GetSetting(MODULE_ID, "showTooltip") ~= true then
        return nil
    end
    return ns.Transmog.BuildTooltipLines(ns.Transmog.GetState(itemId, link),
        ns.GetSetting(MODULE_ID, "onlyUncollected") == true)
end

-- 이벤트 프레임·등록·보조 판정·공급자·안내, dik, 2026-10-01
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    local missing = {}
    local registeredCount = 0
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        local ok = pcall(frame.RegisterEvent, frame, name)
        if ok then
            registeredCount = registeredCount + 1
        else
            missing[#missing + 1] = name
        end
    end
    cacheEnabled = registeredCount > 0
    useOtherSource = ns.HasAPI(OPTIONAL_APIS.otherSource) == true
    useCanCollect = ns.HasAPI(OPTIONAL_APIS.canCollect) == true
    if not useOtherSource then
        missing[#missing + 1] = OPTIONAL_APIS.otherSource
    end
    if not useCanCollect then
        missing[#missing + 1] = OPTIONAL_APIS.canCollect
    end
    missingList = missing
    if type(ns.TooltipLines) == "table" then
        ns.TooltipLines.RegisterItem({
            id = "transmog",
            order = PROVIDER_ORDER,
            Get = GetTooltipLines,
        })
    end
    if #missing > 0 then
        ns.Print(L.MSG_TRANSMOG_PARTIAL:format(ns.FormatMissingAPIs(missing)))
    end
end

-- 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "transmog",
    title = L.MODULE_TRANSMOG,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_TRANSMOG_DESC,
    category = "feature",
    order = 100,
    requires = { "C_TransmogCollection.GetItemInfo", "C_TransmogCollection.GetSourceInfo" },
    settings = {
        { key = "showTooltip", type = "checkbox", label = L.SETTING_TMOG_TOOLTIP,
            tooltip = L.SETTING_TMOG_TOOLTIP_TIP, default = true },
        { key = "onlyUncollected", type = "checkbox", label = L.SETTING_TMOG_ONLY_UNCOLLECTED,
            tooltip = L.SETTING_TMOG_ONLY_UNCOLLECTED_TIP, default = false },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
})
