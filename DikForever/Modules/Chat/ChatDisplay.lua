-- 채팅창 스킨·정보줄 화면, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("chat")
if not module then
    return
end

local L = ns.L

local DEFAULT_WINDOW_COUNT = 10
local INFO_LINE_GAP_Y = -2
local INFO_LINE_EXTRA_H = 4
local FALLBACK_FONT_H = 12
local ANCHOR_FRAME_NAME = "ChatFrame1"
local ANCHOR_EDIT_NAME = "ChatFrame1EditBox"
local INFO_OWNER = "chat:infoLine"
local OWNER_BACKGROUND = "chat:background"

local BG_SUFFIXES = {
    "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "TopTexture", "BottomTexture",
}

-- { parentKey, 전역 접미사 }
local TAB_TEXTURES = {
    { "Left", "Left" }, { "Middle", "Middle" }, { "Right", "Right" },
    { "ActiveLeft", "SelectedLeft" }, { "ActiveMiddle", "SelectedMiddle" }, { "ActiveRight", "SelectedRight" },
    { "HighlightLeft", "HighlightLeft" }, { "HighlightMiddle", "HighlightMiddle" }, { "HighlightRight", "HighlightRight" },
}

local EDIT_SUFFIXES = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local active = false
local initialDone = false
local enteredWorldHandled = false
local unsupportedShown = false
local missingSet = {}
local missingList = {}
local tabSelected = {}
local infoItems = {}
local infoLine = nil
local layouting = false
local eventFrame = nil

-- 없는 요소 기록, dik, 2026-10-01
local function AddMissing(name)
    if type(name) ~= "string" or missingSet[name] then
        return
    end
    missingSet[name] = true
    missingList[#missingList + 1] = name
end

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting("chat", key) == true
end

-- 채팅창 이름 목록, dik, 2026-10-01
local function GetWindowNames()
    local names = {}
    if type(CHAT_FRAMES) == "table" then
        for _, name in ipairs(CHAT_FRAMES) do
            if type(name) == "string" then
                names[#names + 1] = name
            end
        end
        return names
    end
    local count = type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS or DEFAULT_WINDOW_COUNT
    for i = 1, count do
        names[#names + 1] = "ChatFrame" .. i
    end
    return names
end

-- 이벤트 등록 헬퍼, dik, 2026-10-01
local function RegisterEventSafe(frame, name)
    local ok = pcall(frame.RegisterEvent, frame, name)
    if not ok then
        AddMissing(name)
    end
    return ok
end

-- 탭 글자 조회, dik, 2026-10-01
local function FindTabText(tabName)
    return ns.Display.Find(tabName, "Text") or ns.Display.Find(tabName .. "Text")
end

-- 배경 스킨 적용, dik, 2026-10-01
local function ApplyBackground()
    local owner = OWNER_BACKGROUND
    ns.Display.BeginSkin(owner)
    local alpha = ns.GetSetting("chat", "bgAlpha")
    for _, winName in ipairs(GetWindowNames()) do
        local win = ns.Display.Find(winName)
        if win then
            for _, suffix in ipairs(BG_SUFFIXES) do
                local tex = ns.Display.Find(winName .. suffix)
                if tex then
                    ns.Display.HideTexture(owner, tex)
                else
                    AddMissing(winName .. suffix)
                end
            end
            ns.Display.AttachPanel(owner, win, "BG", "BORDER", alpha)
        end
    end
end

-- 탭 스킨 적용, dik, 2026-10-01
local function ApplyTabs()
    local owner = "chat:tabs"
    ns.Display.BeginSkin(owner)
    for _, winName in ipairs(GetWindowNames()) do
        if ns.Display.Find(winName) then
            local tabName = winName .. "Tab"
            local tab = ns.Display.Find(tabName)
            if tab then
                for _, pair in ipairs(TAB_TEXTURES) do
                    local tex = ns.Display.Find(tabName, pair[1]) or ns.Display.Find(tabName .. pair[2])
                    if tex then
                        ns.Display.HideTexture(owner, tex)
                    else
                        AddMissing(tabName .. pair[2])
                    end
                end
                ns.Display.AttachPanel(owner, tab, "PANEL", "BORDER")
                local text = FindTabText(tabName)
                if text then
                    ns.Display.SetFontFace(owner, text, "FACE_BODY")
                    ns.Display.SetTextColor(owner, text, tabSelected[tabName] and "ACCENT" or "TEXT_DIM")
                else
                    AddMissing(tabName .. "Text")
                end
            else
                AddMissing(tabName)
            end
        end
    end
end

-- 입력창 스킨 적용, dik, 2026-10-01
local function ApplyEditBox()
    local owner = "chat:editBox"
    ns.Display.BeginSkin(owner)
    for _, winName in ipairs(GetWindowNames()) do
        if ns.Display.Find(winName) then
            local editName = winName .. "EditBox"
            local edit = ns.Display.Find(editName)
            if edit then
                for _, suffix in ipairs(EDIT_SUFFIXES) do
                    local tex = ns.Display.Find(editName .. suffix) or ns.Display.Find(editName, suffix)
                    if tex then
                        ns.Display.HideTexture(owner, tex)
                    else
                        AddMissing(editName .. suffix)
                    end
                end
                ns.Display.AttachPanel(owner, edit, "PANEL", "BORDER")
                ns.Display.SetFontFace(owner, edit, "FACE_BODY")
            else
                AddMissing(editName)
            end
        end
    end
end

-- 글꼴 스킨 적용, dik, 2026-10-01
local function ApplyFont()
    local owner = "chat:font"
    ns.Display.BeginSkin(owner)
    for _, winName in ipairs(GetWindowNames()) do
        local win = ns.Display.Find(winName)
        if win then
            ns.Display.SetFontFace(owner, win, "FACE_BODY")
        end
    end
end

local PART_APPLY = {
    skinBackground = ApplyBackground,
    skinTabs = ApplyTabs,
    skinEditBox = ApplyEditBox,
    skinFont = ApplyFont,
}

-- 켜진 부분 재적용, dik, 2026-10-01
local function ReapplyPart(part)
    if IsOn(part.key) and ns.Display.IsSkinActive(part.owner) then
        PART_APPLY[part.key]()
    end
end

-- 켜진 부분 전체 재적용, dik, 2026-10-01
local function ReapplyAll()
    for _, part in ipairs(ns.Chat.SKIN_PARTS) do
        ReapplyPart(part)
    end
end

-- 정보줄 앵커 대상, dik, 2026-10-01
local function GetAnchorTarget()
    return ns.Display.Find(ANCHOR_EDIT_NAME) or ns.Display.Find(ANCHOR_FRAME_NAME)
end

-- 정보줄 높이, dik, 2026-10-01
local function GetInfoLineHeight()
    local fontObj = ns.Theme.GetFont("FONT_SMALL")
    local size
    if fontObj and fontObj.GetFont then
        local _, fontSize = fontObj:GetFont()
        size = fontSize
    end
    if type(size) ~= "number" then
        size = FALLBACK_FONT_H
    end
    return math.max(ns.Theme.STATUSBAR_H, math.ceil(size) + INFO_LINE_EXTRA_H)
end

-- 정보줄 재배치, dik, 2026-10-01
local function RelayoutInfo()
    if not active or not infoLine or layouting then
        return
    end
    layouting = true
    infoLine:SetHeight(GetInfoLineHeight())

    local candidates = {}
    local widths = {}
    for _, entry in ipairs(infoItems) do
        if entry.active and entry.supported then
            candidates[#candidates + 1] = entry
            widths[#widths + 1] = entry.item:GetTextWidth()
        else
            entry.item:Hide()
        end
    end

    local available = nil
    if ns.GetSetting("chat", "infoPosition") == "below" then
        local target = GetAnchorTarget()
        if target then
            available = target:GetWidth()
        end
    end

    local xs, placed, total = ns.Chat.LayoutInfo(widths, available, ns.Theme.GAP * 2, ns.Theme.PAD / 2)
    for i, entry in ipairs(candidates) do
        if xs[i] then
            entry.item:ClearAllPoints()
            entry.item:SetPoint("LEFT", infoLine, "LEFT", xs[i], 0)
            entry.item:Show()
        else
            entry.item:Hide()
        end
    end

    if available == nil and placed > 0 then
        infoLine:SetWidth(total)
    end
    if IsOn("showInfo") and placed >= 1 then
        infoLine:Show()
    else
        infoLine:Hide()
    end
    layouting = false
end

-- 정보줄 위치 적용, dik, 2026-10-01
local function ApplyInfoPosition()
    if not infoLine then
        return
    end
    local target = nil
    if ns.GetSetting("chat", "infoPosition") == "below" then
        target = GetAnchorTarget()
    end
    if target then
        infoLine:SetHudActive(false)
        infoLine:ClearAllPoints()
        infoLine:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, INFO_LINE_GAP_Y)
        infoLine:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, INFO_LINE_GAP_Y)
    else
        infoLine:ClearAllPoints()
        infoLine:SetHudActive(true)
    end
end

-- 미지원 항목 안내, dik, 2026-10-01
local function ReportUnsupported()
    if unsupportedShown then
        return
    end
    local list = {}
    local seen = {}
    for _, entry in ipairs(infoItems) do
        if entry.active and not entry.supported then
            local _, missing = ns.InfoText.IsSupported(entry.provider)
            for _, name in ipairs(missing or {}) do
                if not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
        end
    end
    if #list > 0 then
        unsupportedShown = true
        ns.Print(L.MSG_INFO_UNSUPPORTED:format(ns.FormatMissingAPIs(list)))
    end
end

-- 정보 항목 켜기/끄기, dik, 2026-10-01
local function SyncInfoItem(entry)
    local on = IsOn(entry.key)
    if on then
        entry.supported = entry.item:SetActive(true) == true
    else
        entry.item:SetActive(false)
        entry.supported = true
    end
    entry.active = on
end

-- 정보줄 생성, dik, 2026-10-01
local function CreateInfoLine()
    local info = ns.Chat.HUD_INFO_LINE
    infoLine = ns.Display.CreateHudFrame("chat", info.key, {
        label = L.HUD_LABEL_CHAT_INFO,
        point = info.point,
        relativePoint = info.relativePoint,
        x = info.x,
        y = info.y,
    })
    ns.Theme.ApplyBackdrop(infoLine, "BG", "BORDER", ns.GetSetting("chat", "bgAlpha"))
    infoLine:SetHeight(GetInfoLineHeight())
    infoLine:SetScript("OnSizeChanged", function()
        RelayoutInfo()
    end)
    for _, def in ipairs(ns.Chat.INFO_ITEMS) do
        local entry = { key = def.key, provider = def.provider, active = false, supported = true }
        entry.item = ns.Display.CreateInfoText(infoLine, def.provider, INFO_OWNER, function()
            RelayoutInfo()
        end)
        infoItems[#infoItems + 1] = entry
    end
    for _, entry in ipairs(infoItems) do
        SyncInfoItem(entry)
    end
    ReportUnsupported()
end

-- 배경 알파 갱신, dik, 2026-10-01
local function ApplyBgAlpha(alpha)
    for _, panel in ipairs(ns.Display.GetPanels(OWNER_BACKGROUND)) do
        ns.Theme.ApplyBackdrop(panel, "BG", "BORDER", alpha)
    end
    if infoLine then
        ns.Theme.ApplyBackdrop(infoLine, "BG", "BORDER", alpha)
    end
end

-- 사후 훅 설치, dik, 2026-10-01
local function InstallHooks()
    local function hook(owner, funcName, fn)
        if not ns.Display.HookAfter(owner, funcName, fn) then
            AddMissing(funcName)
        end
    end
    local function reapplyBackground() ReapplyPart(ns.Chat.SKIN_PARTS[1]) end
    local function reapplyTabs() ReapplyPart(ns.Chat.SKIN_PARTS[2]) end
    local function reapplyEdit() ReapplyPart(ns.Chat.SKIN_PARTS[3]) end
    local function reapplyFont() ReapplyPart(ns.Chat.SKIN_PARTS[4]) end

    hook("chat:background", "FCF_SetWindowColor", reapplyBackground)
    hook("chat:background", "FCF_SetWindowAlpha", reapplyBackground)
    hook("chat:background", "FCF_OpenTemporaryWindow", reapplyBackground)
    hook("chat:tabs", "FCF_OpenTemporaryWindow", reapplyTabs)
    hook("chat:tabs", "FCFTab_UpdateColors", function(tab, selected)
        local tabName = tab and tab.GetName and tab:GetName()
        if not tabName then
            return
        end
        tabSelected[tabName] = selected and true or false
        local text = FindTabText(tabName)
        if text then
            ns.Display.SetTextColor("chat:tabs", text, selected and "ACCENT" or "TEXT_DIM")
        end
    end)
    hook("chat:editBox", "FCF_OpenTemporaryWindow", reapplyEdit)
    hook("chat:font", "FCF_SetChatWindowFontSize", reapplyFont)
    hook("chat:font", "FCF_OpenTemporaryWindow", reapplyFont)
end

-- 이벤트 재적용 프레임, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if not active then
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            if enteredWorldHandled then
                return
            end
            enteredWorldHandled = true
        end
        ReapplyAll()
        RelayoutInfo()
    end)
    RegisterEventSafe(eventFrame, "UPDATE_CHAT_WINDOWS")
    RegisterEventSafe(eventFrame, "UPDATE_FLOATING_CHAT_WINDOWS")
    RegisterEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")
end

-- 스킨 부분 켜기(전투 밖 지연), dik, 2026-10-01
local function EnablePart(part, onDone)
    ns.Display.RunOutOfCombat(part.owner, function()
        if IsOn(part.key) then
            -- 적용 오류가 나도 onDone 보장, dik, 2026-10-01
            xpcall(PART_APPLY[part.key], geterrorhandler())
        end
        if onDone then
            onDone()
        end
    end)
end

-- 첫 적용 후 안내, dik, 2026-10-01
local function ReportPartial()
    initialDone = true
    -- 기본 채팅창 부재도 안내에 포함, dik, 2026-10-01
    if not ns.Display.Find(ANCHOR_FRAME_NAME) then
        AddMissing(ANCHOR_FRAME_NAME)
    end
    if #missingList > 0 then
        ns.Print(L.MSG_CHAT_SKIN_PARTIAL:format(ns.FormatMissingAPIs(missingList)))
    end
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled("chat") and ns.IsModuleSupported("chat")) then
        return
    end
    active = true

    InstallHooks()
    CreateEventFrame()
    CreateInfoLine()

    -- 위치 적용 전에 정보줄 폭 확정, dik, 2026-10-01
    if ns.GetSetting("chat", "infoPosition") == "below" and GetAnchorTarget() then
        RelayoutInfo()
        ApplyInfoPosition()
        RelayoutInfo()
    else
        ns.Display.RunOutOfCombat(INFO_OWNER, function()
            RelayoutInfo()
            ApplyInfoPosition()
            RelayoutInfo()
        end)
    end

    local pending = 0
    for _, part in ipairs(ns.Chat.SKIN_PARTS) do
        if IsOn(part.key) then
            pending = pending + 1
        end
    end
    if pending == 0 then
        ReportPartial()
        return
    end
    local function onDone()
        pending = pending - 1
        if pending == 0 and not initialDone then
            ReportPartial()
        end
    end
    for _, part in ipairs(ns.Chat.SKIN_PARTS) do
        if IsOn(part.key) then
            EnablePart(part, onDone)
        end
    end
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            RelayoutInfo()
        end
        return
    end
    if scope ~= "chat" then
        return
    end

    for _, part in ipairs(ns.Chat.SKIN_PARTS) do
        if part.key == key then
            if value == true then
                EnablePart(part)
            else
                ns.Display.RestoreSkin(part.owner)
                ns.Print(L.MSG_SKIN_RESTORED)
            end
            return
        end
    end

    if key == "bgAlpha" then
        if type(value) == "number" then
            ApplyBgAlpha(value)
        end
    elseif key == "infoPosition" then
        -- 위치 적용 전에 정보줄 폭 확정, dik, 2026-10-01
        ns.Display.RunOutOfCombat(INFO_OWNER, function()
            RelayoutInfo()
            ApplyInfoPosition()
            RelayoutInfo()
        end)
    elseif key == "showInfo" then
        RelayoutInfo()
    else
        for _, entry in ipairs(infoItems) do
            if entry.key == key then
                SyncInfoItem(entry)
                ReportUnsupported()
                RelayoutInfo()
                return
            end
        end
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
