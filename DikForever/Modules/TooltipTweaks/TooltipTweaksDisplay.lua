-- 툴팁 커서 위치·직업색 화면 설치, dik, 2026-10-02
local addonName, ns = ...

local module = ns.GetModule("tooltipTweaks")
if not module then
    return
end

local L = ns.L

local OWNER = "tooltipTweaks"
local ANCHOR_TOOLTIP_NAME = "GameTooltip_SetDefaultAnchor"

local conflict = false
local useFallback = false
local fallbackNotified = false
local installed = false
local probed = {}

-- 설정 값 조회, dik, 2026-10-02
local function Get(key)
    return ns.GetSetting(OWNER, key)
end

-- 툴팁 사용 가능 여부, dik, 2026-10-02
local function IsUsable(tooltip)
    if tooltip ~= GameTooltip then
        return false
    end
    if tooltip.IsForbidden and tooltip:IsForbidden() then
        return false
    end
    return true
end

-- 방향 앵커 실패 안내 1회, dik, 2026-10-02
local function NotifyFallback()
    if fallbackNotified then
        return
    end
    fallbackNotified = true
    ns.Print(L.MSG_TIPTW_ANCHOR_FALLBACK)
end

-- 기본 앵커 사후 훅 본문, dik, 2026-10-02
local function OnDefaultAnchor(tooltip, parent)
    if not IsUsable(tooltip) or type(parent) ~= "table" then
        return
    end
    local TT = ns.TooltipTweaks
    local o = {
        enabled = Get("cursorAnchor") == true,
        conflict = conflict,
        inCombat = TT.InCombat(),
        cursorInCombat = Get("cursorInCombat") == true,
        scope = Get("anchorScope"),
        isWorld = (parent == UIParent),
    }
    if not TT.ShouldMove(o) then
        return
    end
    local anchor, x, y = TT.CalcAnchor(Get("anchorSide"), Get("offsetX"), Get("offsetY"))
    if useFallback then
        tooltip:SetOwner(parent, TT.ANCHOR_FALLBACK)
        return
    end
    if probed[anchor] then
        tooltip:SetOwner(parent, anchor, x, y)
        return
    end
    local ok = pcall(tooltip.SetOwner, tooltip, parent, anchor, x, y)
    local matched = false
    if ok then
        matched = true
        if tooltip.GetAnchorType then
            local current = tooltip:GetAnchorType()
            if not ns.IsSecret(current) and current ~= anchor then
                matched = false
            end
        end
    end
    if matched then
        probed[anchor] = true
        return
    end
    useFallback = true
    NotifyFallback()
    tooltip:SetOwner(parent, TT.ANCHOR_FALLBACK)
end

-- 유닛 툴팁 직업색 처리 본문, dik, 2026-10-02
local function ApplyUnitColor(tooltip)
    if not IsUsable(tooltip) then
        return
    end
    local nameOn = Get("classColorName") == true
    local wordOn = Get("classColorClass") == true
    if not nameOn and not wordOn then
        return
    end
    if not tooltip.GetUnit then
        return
    end
    local TT = ns.TooltipTweaks
    local _, unit = tooltip:GetUnit()
    local className, classFile = TT.ReadUnitClass(unit)
    if not classFile then
        return
    end
    local r, g, b = TT.ClassColor(classFile, RAID_CLASS_COLORS)
    if not r then
        return
    end
    if nameOn then
        local nameLine = ns.Display.Find("GameTooltipTextLeft1")
        if nameLine then
            nameLine:SetTextColor(r, g, b)
        end
    end
    if wordOn and className then
        local count = tooltip:NumLines()
        if type(count) ~= "number" then
            return
        end
        local last = math.min(count, TT.CLASS_LINE_LAST)
        for i = TT.CLASS_LINE_FIRST, last do
            local fs = ns.Display.Find("GameTooltipTextLeft" .. i)
            if fs then
                local newText = TT.ColorizeWord(fs:GetText(), className, r, g, b)
                if newText then
                    fs:SetText(newText)
                    break
                end
            end
        end
    end
end

-- 유닛 처리기 오류 격리, dik, 2026-10-02
local function OnUnitTooltip(tooltip)
    xpcall(function()
        ApplyUnitColor(tooltip)
    end, geterrorhandler())
end

-- 없는 API 목록 합치기, dik, 2026-10-02
local function CollectMissing(hookFailed)
    local TT = ns.TooltipTweaks
    local missing = {}
    local seen = {}
    local function Add(list)
        for i = 1, #list do
            if not seen[list[i]] then
                seen[list[i]] = true
                missing[#missing + 1] = list[i]
            end
        end
    end
    Add(ns.GetMissingAPIs(TT.CURSOR_APIS))
    Add(ns.GetMissingAPIs(TT.COLOR_APIS))
    if hookFailed then
        Add({ ANCHOR_TOOLTIP_NAME })
    end
    return missing
end

-- READY 설치, dik, 2026-10-02
local function Initialize()
    if installed then
        return
    end
    if not (ns.IsModuleEnabled(OWNER) and ns.IsModuleSupported(OWNER)) then
        return
    end
    installed = true
    local TT = ns.TooltipTweaks
    ns.Display.BeginSkin(OWNER)
    conflict = TT.IsConflict()

    local hookFailed = false
    if #ns.GetMissingAPIs(TT.CURSOR_APIS) == 0 then
        if not ns.Display.HookAfter(OWNER, ANCHOR_TOOLTIP_NAME, OnDefaultAnchor) then
            hookFailed = true
        end
    end
    if #ns.GetMissingAPIs(TT.COLOR_APIS) == 0 then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end

    local missing = CollectMissing(hookFailed)
    if #missing > 0 then
        ns.Print(L.MSG_TIPTW_PARTIAL:format(ns.FormatMissingAPIs(missing)))
    end
    if conflict and Get("cursorAnchor") == true then
        ns.Print(L.MSG_TIPTW_FCT)
    end
end

ns.On("READY", Initialize)
