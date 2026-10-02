-- 아이템 툴팁 줄 추가 훅, dik, 2026-10-01
local addonName, ns = ...

local L = ns.L

ns.Tooltip = {}

local METHOD_PROCESSOR = "dataProcessor"
local METHOD_SCRIPT = "scriptHook"
local FALLBACK_TOKEN = "TEXT"
local BLANK_LINE = " "

local installDone = false
local installed = false
local method = nil
local isReady = false
local shown = setmetatable({}, { __mode = "k" })
local clearHooked = setmetatable({}, { __mode = "k" })

-- 대상 툴팁 목록, dik, 2026-10-01
local function GetTargets()
    local list = {}
    if GameTooltip then
        list[#list + 1] = GameTooltip
    end
    if ItemRefTooltip then
        list[#list + 1] = ItemRefTooltip
    end
    return list
end

-- 대상 툴팁 필터, dik, 2026-10-01
local function IsTarget(tooltip)
    if tooltip == nil or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
        return false
    end
    if tooltip.IsForbidden and tooltip:IsForbidden() then
        return false
    end
    return true
end

-- 토큰 이름을 r, g, b 로 변환, dik, 2026-10-01
local function TokenToRGB(token)
    -- 토큰 색 pcall 제거, dik, 2026-10-01
    if type(token) == "string" then
        local r, g, b = ns.Theme.GetColor(token)
        return r, g, b
    end
    local r, g, b = ns.Theme.GetColor(FALLBACK_TOKEN)
    return r, g, b
end

-- 줄 색 결정(Color, Token, TEXT 순), dik, 2026-10-01
local function ResolveColor(color, token)
    if type(color) == "table" and color.r and color.g and color.b then
        return color.r, color.g, color.b
    end
    return TokenToRGB(token)
end

-- 툴팁에 공급자 줄 추가, dik, 2026-10-01
function ns.Tooltip.AppendItemLines(tooltip, itemId, link)
    if not tooltip or not ns.TooltipLines then
        return 0
    end
    if method == METHOD_SCRIPT and clearHooked[tooltip] and shown[tooltip] == itemId then
        return 0
    end
    local lines = ns.TooltipLines.BuildItem(itemId, link)
    if type(lines) ~= "table" or #lines == 0 then
        return 0
    end
    tooltip:AddLine(BLANK_LINE)
    for i = 1, #lines do
        local line = lines[i]
        local lr, lg, lb = ResolveColor(line.leftColor, line.leftToken)
        if line.right then
            local rr, rg, rb = ResolveColor(line.rightColor, line.rightToken)
            tooltip:AddDoubleLine(line.left, line.right, lr, lg, lb, rr, rg, rb)
        else
            tooltip:AddLine(line.left, lr, lg, lb)
        end
    end
    shown[tooltip] = itemId
    return #lines + 1
end

-- 툴팁 GetItem 링크 조회, dik, 2026-10-01
local function GetTooltipLink(tooltip)
    if not tooltip.GetItem then
        return nil
    end
    local _, link = tooltip:GetItem()
    if type(link) ~= "string" or ns.IsSecret(link) then
        return nil
    end
    return link
end

-- 훅 본문(필터·id 해석·추가·Show), dik, 2026-10-01
local function HandleTooltip(tooltip, data)
    if not IsTarget(tooltip) or not ns.TooltipLines then
        return
    end
    local link = GetTooltipLink(tooltip)
    local itemId
    if data ~= nil and type(data) == "table" then
        local id = data.id
        if id ~= nil and not ns.IsSecret(id) then
            itemId = ns.TooltipLines.ParseItemId(id)
        end
    end
    if not itemId and link then
        itemId = ns.TooltipLines.ParseItemId(link)
    end
    if not itemId then
        return
    end
    if ns.Tooltip.AppendItemLines(tooltip, itemId, link) > 0 then
        tooltip:Show()
    end
end

-- 데이터 처리기 콜백, dik, 2026-10-01
local function OnItemData(tooltip, data)
    xpcall(HandleTooltip, geterrorhandler(), tooltip, data)
end

-- 스크립트 훅 콜백, dik, 2026-10-01
local function OnSetItem(tooltip)
    xpcall(HandleTooltip, geterrorhandler(), tooltip, nil)
end

-- 표시 기록 지움 콜백, dik, 2026-10-01
local function OnCleared(tooltip)
    shown[tooltip] = nil
end

-- 훅 방식 판정·설치(1회), dik, 2026-10-01
function ns.Tooltip.Install()
    if installDone then
        return installed
    end
    installDone = true
    local targets = GetTargets()
    if ns.HasAPI("TooltipDataProcessor.AddTooltipPostCall") and ns.HasAPI("Enum.TooltipDataType.Item") then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemData)
        installed = true
        method = METHOD_PROCESSOR
    else
        local count = 0
        for i = 1, #targets do
            local tooltip = targets[i]
            if tooltip.HasScript and tooltip:HasScript("OnTooltipSetItem") then
                tooltip:HookScript("OnTooltipSetItem", OnSetItem)
                count = count + 1
            end
        end
        if count > 0 then
            installed = true
            method = METHOD_SCRIPT
        end
    end
    if not installed then
        ns.Print(L.MSG_TOOLTIP_UNAVAILABLE)
        return false
    end
    for i = 1, #targets do
        local tooltip = targets[i]
        if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") then
            tooltip:HookScript("OnTooltipCleared", OnCleared)
            clearHooked[tooltip] = true
        end
    end
    return true
end

-- 설치 상태 조회, dik, 2026-10-01
function ns.Tooltip.GetStatus()
    return { installed = installed, method = method }
end

-- 공급자가 생기면 1회 설치, dik, 2026-10-01
local function TryInstall()
    if not isReady or installDone then
        return
    end
    if ns.TooltipLines and ns.TooltipLines.HasItemProviders() then
        ns.Tooltip.Install()
    end
end

ns.On("READY", function()
    isReady = true
    TryInstall()
end)

ns.On("TOOLTIP_PROVIDER_ADDED", TryInstall)
