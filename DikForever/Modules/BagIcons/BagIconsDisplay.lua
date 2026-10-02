-- 가방 아이콘 표시 화면(흑백·빨간 색조), dik, 2026-10-02
local addonName, ns = ...

local module = ns.GetModule("bagIcons")
if not module then
    return
end
local L = ns.L

local MODULE_ID = "bagIcons"
local CONTAINER_FRAME_MAX = 13
local CONTAINER_ITEM_MAX = 36
local WATCH_INTERVAL = 0.2
local HEAL_INTERVAL = 1.0
local SCAN_MAX_PER_PASS = 40
local SEEN_MAX = 500

local EVENT_NAMES = {
    "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "GET_ITEM_INFO_RECEIVED",
    "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED",
}

local FRAME_NAMES = { "ContainerFrameCombinedBags" }
for i = 1, CONTAINER_FRAME_MAX do
    FRAME_NAMES[#FRAME_NAMES + 1] = "ContainerFrame" .. i
end

local applied = setmetatable({}, { __mode = "k" })
local orig = setmetatable({}, { __mode = "k" })
local seen = {}
local seenCount = 0

local active = false
local dirty = false
local watcher
local tickAcc = 0
local sinceRefresh = 0
local prevShown = {}

local passGreyOn = false
local passRedOn = false
local passJudged = 0
local passPending = false

-- 전투 중 여부, dik, 2026-10-02
local function InCombat()
    return ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true
end

-- 설정 켜짐 여부, dik, 2026-10-02
local function IsOn(key)
    return ns.GetSetting(MODULE_ID, key) == true
end

-- secret 아닌 숫자 여부, dik, 2026-10-02
local function IsPlainNumber(value)
    return not ns.IsSecret(value) and type(value) == "number"
end

-- 창의 보이는 아이템 버튼 순회, dik, 2026-10-02
local function ForEachButton(frame, fn)
    if frame:IsShown() ~= true then
        return
    end
    if type(frame.EnumerateValidItems) == "function" then
        for _, button in frame:EnumerateValidItems() do
            if type(button) == "table" and button:IsShown() == true then
                fn(button, frame)
            end
        end
        return
    end
    local name = frame:GetName()
    if type(name) ~= "string" then
        return
    end
    for i = 1, CONTAINER_ITEM_MAX do
        local button = ns.Display.Find(name .. "Item" .. i)
        if button and button:IsShown() == true then
            fn(button, frame)
        end
    end
end

-- 버튼의 가방·칸 번호, dik, 2026-10-02
local function GetBagSlot(button, frame)
    local bag
    if type(button.GetBagID) == "function" then
        bag = button:GetBagID()
    else
        bag = frame:GetID()
    end
    local slot = button:GetID()
    if IsPlainNumber(bag) and IsPlainNumber(slot) and slot >= 1 then
        return bag, slot
    end
    return nil
end

-- 버튼 아이콘 텍스처 조회, dik, 2026-10-02
local function GetIcon(button)
    local icon = ns.Display.Find(button, "icon")
    if not icon then
        local name = button:GetName()
        if type(name) == "string" then
            icon = ns.Display.Find(name .. "IconTexture")
        end
    end
    if icon and type(icon.SetDesaturated) == "function" and type(icon.SetVertexColor) == "function"
        and type(icon.GetVertexColor) == "function" then
        return icon
    end
    return nil
end

-- 적용 기록 조회·생성, dik, 2026-10-02
local function EnsureRecord(icon)
    local rec = applied[icon]
    if not rec then
        rec = {}
        applied[icon] = rec
    end
    return rec
end

-- 흑백 적용·원복, dik, 2026-10-02
local function ApplyGrey(icon, want, isLocked)
    local rec = applied[icon]
    if want then
        icon:SetDesaturated(true)
        EnsureRecord(icon).grey = true
    elseif rec and rec.grey then
        icon:SetDesaturated(isLocked == true)
        rec.grey = nil
    end
end

-- 빨간 색조 적용·원복, dik, 2026-10-02
local function ApplyRed(icon, want)
    local rec = applied[icon]
    if want then
        if not orig[icon] then
            orig[icon] = { icon:GetVertexColor() }
        end
        icon:SetVertexColor(ns.Theme.GetColor("BAG_UNUSABLE"))
        EnsureRecord(icon).red = true
    elseif rec and rec.red then
        local o = orig[icon]
        if o and IsPlainNumber(o[1]) and IsPlainNumber(o[2]) and IsPlainNumber(o[3]) then
            icon:SetVertexColor(o[1], o[2], o[3], IsPlainNumber(o[4]) and o[4] or 1)
        else
            icon:SetVertexColor(1, 1, 1, 1)
        end
        orig[icon] = nil
        rec.red = nil
    end
end

-- 못 쓰는 장비 판정(패스당 신규 상한), dik, 2026-10-02
local function Judge(bag, slot, info)
    local key = info.link
    if ns.IsSecret(key) or type(key) ~= "string" then
        key = info.itemID
    end
    if not seen[key] then
        if passJudged >= SCAN_MAX_PER_PASS then
            passPending = true
            return nil
        end
        passJudged = passJudged + 1
    end
    local result = ns.BagIcons.JudgeUnusable(bag, slot, info.itemID, info.link)
    if result == nil then
        passPending = true
    elseif key ~= nil and not seen[key] then
        if seenCount >= SEEN_MAX then
            seen = {}
            seenCount = 0
        end
        seen[key] = true
        seenCount = seenCount + 1
    end
    return result
end

-- 버튼 1개 처리, dik, 2026-10-02
local function ProcessButton(button, frame)
    local bag, slot = GetBagSlot(button, frame)
    if not bag then
        return
    end
    local icon = GetIcon(button)
    if not icon then
        return
    end
    local info = ns.BagIcons.ReadSlot(bag, slot)
    local unusable
    if passRedOn and not info.empty and ns.BagIcons.IsEquipmentClass(info.classID) then
        unusable = Judge(bag, slot, info)
    end
    local wantGrey, wantRed = ns.BagIcons.Decide({
        empty = info.empty,
        quality = info.quality,
        classID = info.classID,
        unusable = unusable,
        greyOn = passGreyOn,
        redOn = passRedOn,
    })
    ApplyGrey(icon, wantGrey, info.isLocked)
    ApplyRed(icon, wantRed)
end

-- 보이는 가방 창 전체 갱신, dik, 2026-10-02
local function Refresh()
    if InCombat() then
        dirty = true
        return
    end
    passGreyOn = IsOn("greyDesaturate")
    passRedOn = IsOn("unusableTint") and ns.BagIcons.GetJudgeMethod() ~= nil
    passJudged = 0
    passPending = false
    sinceRefresh = 0
    for i = 1, #FRAME_NAMES do
        local frame = ns.Display.Find(FRAME_NAMES[i])
        if frame then
            ForEachButton(frame, ProcessButton)
        end
    end
    dirty = passPending
end

-- 표시 종류별 원복, dik, 2026-10-02
local function RestoreKind(kind)
    if InCombat() then
        ns.Display.RunOutOfCombat("bagIcons:restore:" .. kind, function()
            RestoreKind(kind)
        end)
        return
    end
    for icon, rec in pairs(applied) do
        if kind == "grey" and rec.grey then
            ApplyGrey(icon, false, false)
        elseif kind == "red" and rec.red then
            ApplyRed(icon, false)
        end
    end
end

-- 감시 틱 처리, dik, 2026-10-02
local function OnUpdate(_, elapsed)
    tickAcc = tickAcc + elapsed
    sinceRefresh = sinceRefresh + elapsed
    if tickAcc < WATCH_INTERVAL then
        return
    end
    tickAcc = 0
    local anyShown = false
    local newShown = false
    for i = 1, #FRAME_NAMES do
        local name = FRAME_NAMES[i]
        local frame = ns.Display.Find(name)
        local shown = frame ~= nil and frame:IsShown() == true
        if shown then
            anyShown = true
            if not prevShown[name] then
                newShown = true
            end
        end
        prevShown[name] = shown
    end
    if not anyShown then
        return
    end
    if newShown or dirty or sinceRefresh >= HEAL_INTERVAL then
        Refresh()
    end
end

-- 이벤트 처리, dik, 2026-10-02
local function OnEvent(_, event, arg1)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not ns.IsSecret(arg1) and ns.BagIcons.TakePending(arg1) then
            dirty = true
        end
    elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" then
        ns.BagIcons.ClearCache()
        seen = {}
        seenCount = 0
        dirty = true
    else
        dirty = true
    end
end

-- 이벤트 등록, dik, 2026-10-02
local function RegisterEvents(target)
    for i = 1, #EVENT_NAMES do
        pcall(target.RegisterEvent, target, EVENT_NAMES[i])
    end
end

-- READY 초기화, dik, 2026-10-02
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    local found = false
    for i = 1, #FRAME_NAMES do
        if ns.Display.Find(FRAME_NAMES[i]) then
            found = true
            break
        end
    end
    if not found then
        ns.Print(L.MSG_BAGICONS_NO_FRAMES)
        return
    end
    if IsOn("unusableTint") and ns.BagIcons.GetJudgeMethod() == "level" then
        ns.Print(L.MSG_BAGICONS_LEVEL_ONLY)
    end
    active = true
    dirty = true
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnEvent)
    watcher:SetScript("OnUpdate", OnUpdate)
    RegisterEvents(watcher)
end

-- 설정 변경 처리, dik, 2026-10-02
local function OnSettingChanged(scope, key, value)
    if not active or scope ~= MODULE_ID then
        return
    end
    local kind
    if key == "greyDesaturate" then
        kind = "grey"
    elseif key == "unusableTint" then
        kind = "red"
    else
        return
    end
    if value == true then
        dirty = true
    else
        RestoreKind(kind)
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
