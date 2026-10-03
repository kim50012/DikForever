-- 기본 UI 숨기기 보호 경계 가드·적용·재적용, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("hideFrames")
if not module then
    return
end
local L = ns.L

ns.HideFramesSecure = {}

local MODULE_ID = "hideFrames"
local EVENT_NAMES = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED" }

local holder = nil
local eventFrame = nil
local hiddenList = {}
local hiddenSet = {}
-- 프레임별 숨김 방식 기록, dik, 2026-10-03
local hiddenMode = {}
local reapplyCounts = {}
local stoppedSet = {}
local partialList = {}
local partialShown = false
local stoppedShown = false

-- 보호 조작 가능 여부(전투 밖), dik, 2026-10-01
function ns.HideFramesSecure.CanTouch()
    if not ns.HasAPI("InCombatLockdown") then
        return false
    end
    return InCombatLockdown() ~= true
end

-- 프레임을 숨김 보관 프레임 아래로 이동, dik, 2026-10-01
-- 투명화 방식(alpha) 분기 추가, dik, 2026-10-03
function ns.HideFramesSecure.HideFrame(frame, mode)
    if not ns.HideFramesSecure.CanTouch() then return nil end
    if type(frame) ~= "table" then
        return false
    end
    if mode == "alpha" then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        return true
    end
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
    end
    frame:SetParent(holder)
    return true
end

-- 부모가 보관 프레임인지 판정, dik, 2026-10-01
function ns.HideFramesSecure.IsHolder(parent)
    return holder ~= nil and parent == holder
end

-- 방식별 숨김 유지 여부 판정, dik, 2026-10-03
function ns.HideFramesSecure.IsStillHidden(frame, mode)
    if mode == "alpha" then
        return frame:GetAlpha() == 0 and not frame:IsMouseEnabled()
    end
    return ns.HideFramesSecure.IsHolder(frame:GetParent())
end

-- 활성·지원 모듈 여부, dik, 2026-10-01
local function IsActive()
    return ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)
end

-- 이벤트 일괄 등록, 성공 개수 반환, dik, 2026-10-01
local function RegisterEvents(frame, names)
    local okCount = 0
    for _, name in ipairs(names) do
        if pcall(frame.RegisterEvent, frame, name) then
            okCount = okCount + 1
        end
    end
    return okCount
end

-- 전투 중 예약 안내 1회씩, dik, 2026-10-01
local function NotifyPending()
    if ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true then
        ns.Print(L.MSG_HIDEFRAMES_PENDING)
    end
end

-- 없는 프레임 이름 합치기, dik, 2026-10-01
local function MergeMissing(missing)
    for _, name in ipairs(missing) do
        local dup = false
        for _, have in ipairs(partialList) do
            if have == name then
                dup = true
                break
            end
        end
        if not dup then
            partialList[#partialList + 1] = name
        end
    end
end

-- 켜진 묶음의 못 숨긴 프레임 숨기기, dik, 2026-10-01
local function HideGroups()
    for _, group in ipairs(ns.HideFrames.GROUPS) do
        if ns.GetSetting(MODULE_ID, group.key) == true then
            local found, missing = ns.HideFrames.ResolveGroup(group)
            for _, name in ipairs(found) do
                local f = ns.Display.Find(name)
                -- 묶음 숨김 방식 전달, dik, 2026-10-03
                if type(f) == "table" and not hiddenSet[f] and ns.HideFramesSecure.HideFrame(f, group.mode) == true then
                    hiddenSet[f] = true
                    hiddenMode[f] = group.mode
                    hiddenList[#hiddenList + 1] = f
                end
            end
            MergeMissing(missing)
        end
    end
end

-- 부분 안내 세션 1회, dik, 2026-10-01
local function NotifyPartial()
    if #partialList > 0 and not partialShown then
        partialShown = true
        ns.Print(L.MSG_HIDEFRAMES_PARTIAL:format(ns.FormatMissingAPIs(partialList)))
    end
end

-- 켜진 묶음 숨기기 적용, dik, 2026-10-01
local function Apply()
    if not IsActive() then
        return
    end
    if not ns.HideFramesSecure.CanTouch() then
        if ns.HasAPI("InCombatLockdown") then
            ns.Display.RunOutOfCombat("hideFrames:apply", Apply)
        end
        return
    end
    HideGroups()
    NotifyPartial()
end

-- 되돌려진 프레임 다시 숨기기, dik, 2026-10-01
local function Reapply()
    if not IsActive() then
        return
    end
    if not ns.HideFramesSecure.CanTouch() then
        return
    end
    -- 방식별 유지 판정·재적용, dik, 2026-10-03
    for _, f in ipairs(hiddenList) do
        local mode = hiddenMode[f]
        if not stoppedSet[f] and not ns.HideFramesSecure.IsStillHidden(f, mode) then
            local count = reapplyCounts[f] or 0
            if count < ns.HideFrames.REAPPLY_MAX then
                if ns.HideFramesSecure.HideFrame(f, mode) == true then
                    reapplyCounts[f] = count + 1
                end
            else
                stoppedSet[f] = true
                if not stoppedShown then
                    stoppedShown = true
                    ns.Print(L.MSG_HIDEFRAMES_REAPPLY_STOPPED)
                end
            end
        end
    end
    HideGroups()
    NotifyPartial()
end

-- READY 시 재적용 이벤트 프레임 생성과 첫 적용 예약, dik, 2026-10-01
ns.On("READY", function()
    if eventFrame or not IsActive() then
        return
    end
    eventFrame = CreateFrame("Frame")
    RegisterEvents(eventFrame, EVENT_NAMES)
    eventFrame:SetScript("OnEvent", function()
        ns.Display.RunOutOfCombat("hideFrames:reapply", Reapply)
    end)
    -- 켜진 묶음이 있을 때만 대기 안내, dik, 2026-10-01
    for _, group in ipairs(ns.HideFrames.GROUPS) do
        if ns.GetSetting(MODULE_ID, group.key) == true then
            NotifyPending()
            break
        end
    end
    ns.Display.RunOutOfCombat("hideFrames:apply", Apply)
end)

-- 묶음 설정 변경 처리, dik, 2026-10-01
ns.On("SETTING_CHANGED", function(scope, key, value)
    if scope ~= MODULE_ID or not ns.HideFrames.GetGroup(key) then
        return
    end
    if value == false then
        ns.Print(L.MSG_RELOAD_REQUIRED)
    elseif value == true and IsActive() then
        NotifyPending()
        ns.Display.RunOutOfCombat("hideFrames:apply", Apply)
    end
end)
