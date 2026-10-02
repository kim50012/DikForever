-- 장비 아이템 레벨 숫자 표시(캐릭터 창·가방), dik, 2026-10-02
local addonName, ns = ...

local module = ns.GetModule("itemLevel")
if not module then
    return
end

local L = ns.L

local MODULE_ID = "itemLevel"
local PART_A = "A"
local PART_B = "B"

local overlays = {}
local skipped = {}
local pending = {}
local pendingCount = 0
local slotEntries = {}
local bagRoots = {}
local missingA = {}
local missingB = {}
local charFrame = nil
local availableA = false
local availableB = false
local settingChar = true
local settingBags = true
local settingQuality = true
local dirtyA = true
local dirtyB = true
local wasShownA = false
local lastSignature = ""
local prevShownBags = {}
local passAcc = 0
local bagAcc = 0
local notifiedA = false
local notifiedB = false
local eventFrame = nil
local built = false

-- 대기 목록 등록, dik, 2026-10-02
local function AddPending(itemID)
    if type(itemID) ~= "number" or ns.IsSecret(itemID) then
        return
    end
    if pending[itemID] then
        return
    end
    if pendingCount >= ns.ItemLevel.PENDING_MAX then
        pending = {}
        pendingCount = 0
    end
    pending[itemID] = true
    pendingCount = pendingCount + 1
end

-- 더티 표시 일괄, dik, 2026-10-02
local function MarkAllDirty()
    dirtyA = true
    dirtyB = true
end

-- 명시 보호 버튼 판정, dik, 2026-10-02
local function IsExplicitProtected(button)
    if type(button.IsProtected) ~= "function" then
        return false
    end
    local protected, explicit = button:IsProtected()
    if ns.IsSecret(protected) then
        return true
    end
    return protected == true and (explicit == true or explicit == nil)
end

-- 자체 프레임·글자 부착(전투 밖만), dik, 2026-10-02
local function Attach(button, part)
    if skipped[button] then
        return nil
    end
    if IsExplicitProtected(button) then
        skipped[button] = true
        return nil
    end
    if InCombatLockdown and InCombatLockdown() then
        ns.Display.RunOutOfCombat("itemLevel:attach", MarkAllDirty)
        return nil
    end
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints(button)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(ns.Theme.GetFont("FONT_NUMBER"))
    fs:SetPoint("BOTTOM", frame, "BOTTOM", 0, ns.ItemLevel.TEXT_OFFSET_Y)
    fs:SetJustifyH("CENTER")
    fs:SetShadowColor(ns.Theme.GetColor("TEXT_SHADOW"))
    fs:SetShadowOffset(1, -1)
    fs:Hide()
    local ov = { frame = frame, fs = fs, part = part, key = nil }
    overlays[button] = ov
    return ov
end

-- 글자 비우고 숨김, dik, 2026-10-02
local function ClearOverlay(ov)
    ov.fs:SetText("")
    ov.fs:Hide()
end

-- 레벨 글자 표시, dik, 2026-10-02
local function ShowLevel(ov, level, quality)
    local r, g, b = ns.ItemLevel.ResolveColor(quality, settingQuality, ITEM_QUALITY_COLORS)
    if r then
        ov.fs:SetTextColor(r, g, b)
    else
        ov.fs:SetTextColor(ns.Theme.GetColor("TEXT"))
    end
    ov.fs:SetText(level)
    ov.frame:Show()
    ov.fs:Show()
end

-- 부분 전체 숨김, dik, 2026-10-02
local function HidePart(part)
    for _, ov in pairs(overlays) do
        if ov.part == part then
            ClearOverlay(ov)
            ov.frame:Hide()
            ov.key = nil
        end
    end
end

-- 장비 칸 1개 그리기, dik, 2026-10-02
local function RenderSlot(entry)
    local ov = overlays[entry.button]
    if not ov then
        ov = Attach(entry.button, PART_A)
        if not ov then
            return
        end
    end
    local link = ns.ItemLevel.GetEquippedLink(entry.slot)
    if not link then
        ClearOverlay(ov)
        return
    end
    local level, waitId = ns.ItemLevel.GetLevel(link)
    if not level then
        ClearOverlay(ov)
        AddPending(waitId)
        return
    end
    local quality = ns.ItemLevel.GetEquippedQuality(entry.slot, link)
    ShowLevel(ov, level, quality)
end

-- 가방 칸 1개 그리기, dik, 2026-10-02
local function RenderBag(ov, bag, slot)
    local link, quality, itemID = ns.ItemLevel.GetBagItem(bag, slot)
    if not link then
        ClearOverlay(ov)
        return
    end
    local isEquip = ns.ItemLevel.ClassifyLink(link)
    if isEquip == nil then
        ClearOverlay(ov)
        AddPending(itemID or ns.ItemLevel.ParseItemId(link))
        return
    end
    if not isEquip then
        ClearOverlay(ov)
        return
    end
    local level, waitId = ns.ItemLevel.GetLevel(link)
    if not level then
        ClearOverlay(ov)
        AddPending(waitId)
        return
    end
    ShowLevel(ov, level, quality)
end

-- 읽기 메서드 오류 감싸기, dik, 2026-10-02
local function SafeCall(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return value
    end
    return nil
end

-- 부모 가방 번호 읽기, dik, 2026-10-02
local function ParentId(button)
    local parent = button:GetParent()
    if type(parent) ~= "table" then
        return nil
    end
    return parent:GetID()
end

-- 정수 판정(secret 제외), dik, 2026-10-02
local function IsInteger(value)
    return type(value) == "number" and not ns.IsSecret(value) and value == math.floor(value)
end

-- 버튼의 가방·칸 번호 식별, dik, 2026-10-02
local function Identify(button, combined)
    local bag = nil
    if type(button.GetBagID) == "function" then
        bag = SafeCall(button.GetBagID, button)
    elseif not combined and type(button.GetParent) == "function" then
        bag = SafeCall(ParentId, button)
    end
    local slot = nil
    if type(button.GetID) == "function" then
        slot = SafeCall(button.GetID, button)
    end
    if not IsInteger(bag) or not IsInteger(slot) then
        return nil
    end
    if bag < 0 or bag > ns.ItemLevel.GetMaxBag() then
        return nil
    end
    if slot < 1 or slot > ns.ItemLevel.GetBagSlotCount(bag) then
        return nil
    end
    return bag, slot
end

-- 가방 버튼 1개 처리, dik, 2026-10-02
local function ProcessButton(button, combined, force)
    local bag, slot = Identify(button, combined)
    local ov = overlays[button]
    if not bag then
        if ov then
            ClearOverlay(ov)
            ov.key = nil
        end
        return
    end
    local key = bag .. ":" .. slot
    if ov and ov.key == key and not force then
        return
    end
    if not ov then
        ov = Attach(button, PART_B)
        if not ov then
            return
        end
    end
    RenderBag(ov, bag, slot)
    ov.key = key
end

-- 프레임 하위 버튼 순회, dik, 2026-10-02
local function WalkFrame(frame, depth, combined, force)
    if type(frame.GetChildren) ~= "function" then
        return
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and type(child.GetObjectType) == "function" and child:IsShown() then
            local kind = child:GetObjectType()
            if kind == "ItemButton" or kind == "Button" then
                ProcessButton(child, combined, force)
            elseif depth < ns.ItemLevel.MAX_WALK_DEPTH then
                WalkFrame(child, depth + 1, combined, force)
            end
        end
    end
end

-- 보이는 가방 창 목록과 서명, dik, 2026-10-02
local function CollectVisibleBags()
    local list = {}
    local names = {}
    for _, root in ipairs(bagRoots) do
        if root.frame:IsShown() then
            list[#list + 1] = root
            names[#names + 1] = root.name
        end
    end
    return list, table.concat(names, ",")
end

-- 부분 A 점검, dik, 2026-10-02
local function PassA()
    local shownNow = charFrame:IsShown() == true
    if shownNow and (not wasShownA or dirtyA) then
        for _, entry in ipairs(slotEntries) do
            RenderSlot(entry)
        end
        dirtyA = false
    end
    wasShownA = shownNow
end

-- 부분 B 점검, dik, 2026-10-02
local function PassB(elapsed)
    bagAcc = bagAcc + elapsed
    local list, signature = CollectVisibleBags()
    local changed = signature ~= lastSignature
    lastSignature = signature
    -- 새로 보인 가방 창 다시 그림(O1), dik, 2026-10-02
    local newlyShown = {}
    local nowShown = {}
    for _, root in ipairs(list) do
        nowShown[root.name] = true
        if not prevShownBags[root.name] then
            newlyShown[root.name] = true
        end
    end
    prevShownBags = nowShown
    if #list == 0 then
        return
    end
    if not (changed or dirtyB or bagAcc >= ns.ItemLevel.BAG_RESCAN_INTERVAL) then
        return
    end
    local force = dirtyB
    dirtyB = false
    bagAcc = 0
    for _, root in ipairs(list) do
        WalkFrame(root.frame, 1, root.name == ns.ItemLevel.COMBINED_FRAME, force or newlyShown[root.name] == true)
    end
end

-- 0.25초 점검 본문, dik, 2026-10-02
local function OnUpdate(_, elapsed)
    passAcc = passAcc + elapsed
    if passAcc < ns.ItemLevel.PASS_INTERVAL then
        return
    end
    local step = passAcc
    passAcc = 0
    if availableA and settingChar then
        PassA()
    end
    if availableB and settingBags then
        PassB(step)
    end
end

-- 점검 설치·해제, dik, 2026-10-02
local function UpdateRunning()
    if not eventFrame then
        return
    end
    if (availableA and settingChar) or (availableB and settingBags) then
        eventFrame:SetScript("OnUpdate", OnUpdate)
    else
        eventFrame:SetScript("OnUpdate", nil)
    end
end

-- 이벤트 처리, dik, 2026-10-02
local function OnEvent(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        dirtyA = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        MarkAllDirty()
    elseif event == "BAG_UPDATE_DELAYED" then
        dirtyB = true
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.IsSecret(arg1) or not pending[arg1] then
            return
        end
        pending[arg1] = nil
        pendingCount = pendingCount - 1
        MarkAllDirty()
    end
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-02
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame", nil, UIParent)
    eventFrame:SetScript("OnEvent", OnEvent)
    for _, name in ipairs(ns.ItemLevel.EVENTS) do
        pcall(eventFrame.RegisterEvent, eventFrame, name)
    end
end

-- 부분 A 요소 찾기, dik, 2026-10-02
local function FindPartA()
    if not ns.ItemLevel.IsPartAvailable("character") then
        return
    end
    charFrame = ns.Display.Find("CharacterFrame")
    if not charFrame then
        missingA[#missingA + 1] = "CharacterFrame"
    end
    for _, def in ipairs(ns.ItemLevel.SLOT_BUTTONS) do
        local button = ns.Display.Find(def.name)
        if button then
            slotEntries[#slotEntries + 1] = { button = button, slot = def.slot }
        elseif not def.optional then
            missingA[#missingA + 1] = def.name
        end
    end
    availableA = charFrame ~= nil and #slotEntries > 0
end

-- 부분 B 요소 찾기, dik, 2026-10-02
local function FindPartB()
    if not ns.ItemLevel.IsPartAvailable("bags") then
        return
    end
    for _, name in ipairs(ns.ItemLevel.CONTAINER_FRAMES) do
        local frame = ns.Display.Find(name)
        if frame then
            bagRoots[#bagRoots + 1] = { name = name, frame = frame }
        end
    end
    if #bagRoots == 0 then
        missingB[#missingB + 1] = "ContainerFrame*"
    end
    availableB = #bagRoots > 0
end

-- 누락 안내(세션 1회), dik, 2026-10-02
local function NotifyMissing()
    if #missingA > 0 and not notifiedA then
        notifiedA = true
        ns.Print(L.MSG_ILVL_PART_MISSING:format(L.ILVL_PART_CHARACTER, ns.FormatMissingAPIs(missingA)))
    end
    if #missingB > 0 and not notifiedB then
        notifiedB = true
        ns.Print(L.MSG_ILVL_PART_MISSING:format(L.ILVL_PART_BAGS, ns.FormatMissingAPIs(missingB)))
    end
end

-- READY 초기화, dik, 2026-10-02
local function Initialize()
    if built then
        return
    end
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    built = true
    settingChar = ns.GetSetting(MODULE_ID, "showCharacter") ~= false
    settingBags = ns.GetSetting(MODULE_ID, "showBags") ~= false
    settingQuality = ns.GetSetting(MODULE_ID, "qualityColor") ~= false
    FindPartA()
    FindPartB()
    CreateEventFrame()
    NotifyMissing()
    UpdateRunning()
end

-- 설정 변경 처리, dik, 2026-10-02
local function OnSettingChanged(scope, key, value)
    if scope ~= MODULE_ID or not built then
        return
    end
    if key == "showCharacter" then
        settingChar = value ~= false
        if settingChar then
            dirtyA = true
        else
            HidePart(PART_A)
        end
    elseif key == "showBags" then
        settingBags = value ~= false
        if settingBags then
            dirtyB = true
        else
            HidePart(PART_B)
        end
    elseif key == "qualityColor" then
        settingQuality = value ~= false
        MarkAllDirty()
    end
    UpdateRunning()
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
