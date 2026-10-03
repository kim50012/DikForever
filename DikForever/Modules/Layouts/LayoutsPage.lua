-- 레이아웃 페이지, dik, 2026-10-03
local addonName, ns = ...

local module = ns.GetModule("layouts")
if not module then
    return
end

local L = ns.L

local CONFIRM_SECONDS = 5
local FALLBACK_LINE_H = 14
local RENAME_W = 220

local page
local scroll
local content
local hintLabel
local rows = {}
local renameBox
local backupLabel
local noteLabel
local undoBtn
local reloadBtn
local resultLabel
local reloadLabel
local guardLabel

local inCombat = false
local reloadNeeded = false
local lastText
local armedKind
local armedIndex
local armedAt = 0
local confirmToken = 0
local renameIndex
local renameToken = 0

-- ns.Layouts 함수 조회, dik, 2026-10-03
local function Lay(name)
    local t = ns.Layouts
    local f = t and t[name]
    if type(f) == "function" then
        return f
    end
    return nil
end

-- 오류 문장 조회, dik, 2026-10-03
local function ErrorText(errCode, index)
    local f = Lay("GetErrorText")
    if f then
        return f(errCode, index)
    end
    return ""
end

-- 글자 높이 계산, dik, 2026-10-03
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return math.ceil(h)
end

-- 버튼 활성 전환, dik, 2026-10-03
local function SetButtonEnabled(btn, on)
    if on then
        btn:Enable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT"))
    else
        btn:Disable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT_DIM"))
    end
end

-- 쓰기 가능 여부, dik, 2026-10-03
local function IsWritable()
    local f = Lay("IsWritable")
    return f ~= nil and f() and true or false
end

-- 버튼 폭을 글자 후보 중 가장 긴 것에 맞춤, dik, 2026-10-03
local function FitButton(btn, texts)
    local label = btn.label
    local current = label:GetText()
    local maxW = 0
    for i = 1, #texts do
        label:SetText(texts[i])
        maxW = math.max(maxW, label:GetStringWidth())
    end
    label:SetText(current)
    btn:SetWidth(math.floor(maxW + ns.Theme.PAD * 2 + 0.5))
end

-- 확인 대기 글자 원복, dik, 2026-10-03
local function RefreshLabels()
    for i = 1, #rows do
        local row = rows[i]
        row.save.label:SetText(armedKind == "save" and armedIndex == i and L.LAYOUTS_BTN_SAVE_CONFIRM or L.LAYOUTS_BTN_SAVE)
        row.load.label:SetText(armedKind == "load" and armedIndex == i and L.LAYOUTS_BTN_LOAD_CONFIRM or L.LAYOUTS_BTN_LOAD)
        row.delete.label:SetText(armedKind == "delete" and armedIndex == i and L.LAYOUTS_BTN_DELETE_CONFIRM or L.LAYOUTS_BTN_DELETE)
    end
end

-- 확인 대기 취소, dik, 2026-10-03
local function CancelConfirm()
    armedKind = nil
    armedIndex = nil
    confirmToken = confirmToken + 1
    RefreshLabels()
end

-- 이름 입력 취소, dik, 2026-10-03
local function CancelRename()
    renameToken = renameToken + 1
    if renameIndex == nil then
        return
    end
    local row = rows[renameIndex]
    renameIndex = nil
    if renameBox then
        renameBox:ClearFocus()
        renameBox:Hide()
    end
    if row then
        row.name:Show()
    end
end

-- 전체 배치, dik, 2026-10-03
local function Layout()
    if not page then
        return
    end
    local gap = ns.Theme.GAP
    local y = 0

    -- 영역 하나를 가로 전체로 배치, dik, 2026-10-03
    local function Place(region, height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        region:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + height + gap
    end

    -- 글자 줄 배치(빈 글이면 숨김), dik, 2026-10-03
    local function PlaceText(label)
        if (label:GetText() or "") == "" then
            label:Hide()
            return
        end
        label:Show()
        Place(label, GetLineHeight(label))
    end

    Place(hintLabel, GetLineHeight(hintLabel))
    for i = 1, #rows do
        Place(rows[i], rows[i]:GetHeight())
    end

    y = y + gap
    Place(backupLabel, GetLineHeight(backupLabel))
    PlaceText(noteLabel)

    undoBtn:ClearAllPoints()
    undoBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    if reloadBtn:IsShown() then
        reloadBtn:ClearAllPoints()
        reloadBtn:SetPoint("LEFT", undoBtn, "RIGHT", gap, 0)
    end
    y = y + undoBtn:GetHeight() + gap

    PlaceText(resultLabel)
    PlaceText(reloadLabel)
    PlaceText(guardLabel)

    content:SetHeight(math.max(1, y))
    scroll.UpdateLayout()
end

-- 한 줄 채움, dik, 2026-10-03
local function FillRow(row, slot)
    local info = ""
    if slot.empty then
        row.name:SetText((slot.displayName or "") .. L.LAYOUTS_SLOT_EMPTY)
        row.name:SetTextColor(ns.Theme.GetColor("TEXT_DIM"))
    else
        row.name:SetText(slot.displayName or "")
        row.name:SetTextColor(ns.Theme.GetColor("TEXT"))
        local counts = slot.counts
        if type(counts) == "table" and type(counts.settings) == "number" and type(counts.layout) == "number" then
            info = L.LAYOUTS_SLOT_INFO:format(ns.FormatDateTime(slot.created), counts.settings, counts.layout)
        else
            info = ns.FormatDateTime(slot.created)
        end
    end
    row.info:SetText(info)
    row.empty = slot.empty and true or false
    row.slotName = slot.name
    row.slotDisplay = slot.displayName
end

-- 버튼 활성 상태 갱신, dik, 2026-10-03
local function UpdateButtons()
    if not page then
        return
    end
    local writable = IsWritable()
    for i = 1, #rows do
        local row = rows[i]
        SetButtonEnabled(row.save, writable)
        SetButtonEnabled(row.load, writable and not row.empty and not inCombat)
        SetButtonEnabled(row.rename, writable)
        SetButtonEnabled(row.delete, writable and not row.empty)
    end
    if armedKind then
        local row = rows[armedIndex]
        local ok = row ~= nil
        if ok and armedKind == "load" then
            ok = row.load:IsEnabled() and true or false
        elseif ok and armedKind == "delete" then
            ok = row.delete:IsEnabled() and true or false
        elseif ok then
            ok = row.save:IsEnabled() and true or false
        end
        if not ok then
            CancelConfirm()
        end
    end
    if renameIndex and not writable then
        CancelRename()
    end

    local hasBackup = false
    local f = ns.Transfer and ns.Transfer.HasBackup
    if f then
        hasBackup = f() and true or false
    end
    SetButtonEnabled(undoBtn, hasBackup and writable and not inCombat)

    local canReload = reloadNeeded and ns.HasAPI("ReloadUI")
    if canReload then
        reloadBtn:Show()
    else
        reloadBtn:Hide()
    end
    SetButtonEnabled(reloadBtn, not inCombat)

    if reloadNeeded then
        local text = L.TRANSFER_RELOAD
        if not canReload then
            text = text .. " · " .. L.LAYOUTS_RELOAD_NO_API
        end
        reloadLabel:SetText(text)
    else
        reloadLabel:SetText("")
    end

    local guardText
    if not writable then
        guardText = L.MSG_SCHEMA_NEWER
    elseif inCombat then
        guardText = L.TRANSFER_ERR_COMBAT
    end
    guardLabel:SetText(guardText or "")
    resultLabel:SetText(lastText or "")
end

-- 백업 상태 글 채움, dik, 2026-10-03
local function FillBackup()
    local f = ns.Transfer and ns.Transfer.HasBackup
    local has, created
    if f then
        has, created = f()
    end
    if has then
        backupLabel:SetText(L.TRANSFER_BACKUP_AT:format(ns.FormatDateTime(created)))
    else
        backupLabel:SetText(L.TRANSFER_NO_BACKUP)
    end
end

-- 전체 채움, dik, 2026-10-03
local function FillAll()
    if not page then
        return
    end
    local getSlots = Lay("GetSlots")
    local slots = getSlots and getSlots() or {}
    for i = 1, #rows do
        if slots[i] then
            FillRow(rows[i], slots[i])
        end
        FitButton(rows[i].save, { L.LAYOUTS_BTN_SAVE, L.LAYOUTS_BTN_SAVE_CONFIRM })
        FitButton(rows[i].load, { L.LAYOUTS_BTN_LOAD, L.LAYOUTS_BTN_LOAD_CONFIRM })
        FitButton(rows[i].delete, { L.LAYOUTS_BTN_DELETE, L.LAYOUTS_BTN_DELETE_CONFIRM })
    end
    RefreshLabels()
    FillBackup()
    UpdateButtons()
    Layout()
end

-- 확인 대기 시작, dik, 2026-10-03
local function ArmConfirm(kind, index)
    armedKind = kind
    armedIndex = index
    armedAt = GetTime()
    confirmToken = confirmToken + 1
    RefreshLabels()
    if C_Timer and C_Timer.After then
        local token = confirmToken
        C_Timer.After(CONFIRM_SECONDS, function()
            if token == confirmToken and armedKind then
                CancelConfirm()
            end
        end)
    end
end

-- 버튼 동작 공통 처리(확인 필요 시 두 번 눌러 실행), dik, 2026-10-03
local function RunAction(kind, index, needConfirm, action)
    CancelRename()
    if needConfirm then
        if armedKind == kind and armedIndex == index and GetTime() - armedAt <= CONFIRM_SECONDS then
            CancelConfirm()
        else
            CancelConfirm()
            ArmConfirm(kind, index)
            return
        end
    else
        CancelConfirm()
    end
    action()
end

-- 저장, dik, 2026-10-03
local function DoSave(index)
    local f = Lay("Save")
    if not f then
        return
    end
    lastText = nil
    local counts, errCode = f(index)
    if not counts then
        lastText = ErrorText(errCode, index)
    end
    FillAll()
end

-- 불러오기, dik, 2026-10-03
local function DoLoad(index)
    local f = Lay("Load")
    if not f then
        return
    end
    lastText = nil
    local result, errCode = f(index)
    if not result then
        lastText = ErrorText(errCode, index)
    end
    FillAll()
end

-- 삭제, dik, 2026-10-03
local function DoDelete(index)
    local f = Lay("Delete")
    if not f then
        return
    end
    lastText = nil
    local ok, errCode = f(index)
    if not ok and errCode then
        lastText = ErrorText(errCode, index)
    end
    FillAll()
end

-- 이름 입력 시작, dik, 2026-10-03
local function StartRename(index)
    CancelConfirm()
    CancelRename()
    local row = rows[index]
    if not row or not IsWritable() then
        return
    end
    renameIndex = index
    renameBox:ClearAllPoints()
    renameBox:SetPoint("LEFT", row.head, "LEFT", 0, 0)
    renameBox:SetWidth(RENAME_W)
    row.name:Hide()
    renameBox:SetText(row.slotName or row.slotDisplay or "")
    renameBox:Show()
    renameBox:SetFocus()
end

-- 이름 입력 확정, dik, 2026-10-03
local function CommitRename(text)
    local index = renameIndex
    if not index then
        return
    end
    CancelRename()
    local f = Lay("Rename")
    if not f then
        return
    end
    lastText = nil
    local ok, errCode = f(index, text or "")
    if not ok then
        lastText = ErrorText(errCode, index)
    end
    FillAll()
end

-- 되돌리기, dik, 2026-10-03
local function OnUndoClick()
    local f = ns.Transfer and ns.Transfer.Undo
    if not f then
        return
    end
    CancelConfirm()
    CancelRename()
    lastText = nil
    local result, errCode = f({ summary = L.LAYOUTS_UNDO_SUMMARY })
    if not result then
        -- 되돌리기 오류는 설정 이전 문장 사용, dik, 2026-10-03
        local textFn = ns.Transfer and ns.Transfer.GetErrorText
        if type(textFn) == "function" then
            lastText = textFn(errCode)
        else
            lastText = ErrorText(errCode)
        end
    end
    FillAll()
end

-- 지금 /reload, dik, 2026-10-03
local function OnReloadClick()
    local f = Lay("Reload")
    if f then
        CancelConfirm()
        CancelRename()
        f()
    end
end

-- 칸 한 줄 생성, dik, 2026-10-03
local function CreateRow(index)
    local widgets = ns.Widgets
    local gap = ns.Theme.GAP
    local row = CreateFrame("Frame", nil, content)
    row.empty = true

    row.save = widgets.CreateButton(row, L.LAYOUTS_BTN_SAVE, function()
        local needConfirm = not row.empty
        RunAction("save", index, needConfirm, function()
            DoSave(index)
        end)
    end)
    row.load = widgets.CreateButton(row, L.LAYOUTS_BTN_LOAD, function()
        RunAction("load", index, true, function()
            DoLoad(index)
        end)
    end)
    row.rename = widgets.CreateButton(row, L.LAYOUTS_BTN_RENAME, function()
        StartRename(index)
    end)
    row.delete = widgets.CreateButton(row, L.LAYOUTS_BTN_DELETE, function()
        RunAction("delete", index, true, function()
            DoDelete(index)
        end)
    end)
    widgets.SetTooltip(row.save, L.LAYOUTS_BTN_SAVE, L.TIP_LAYOUTS_SAVE)
    widgets.SetTooltip(row.load, L.LAYOUTS_BTN_LOAD, L.TIP_LAYOUTS_LOAD)
    widgets.SetTooltip(row.rename, L.LAYOUTS_BTN_RENAME, L.TIP_LAYOUTS_RENAME)
    widgets.SetTooltip(row.delete, L.LAYOUTS_BTN_DELETE, L.TIP_LAYOUTS_DELETE)

    local btnH = row.save:GetHeight()
    row.head = CreateFrame("Frame", nil, row)
    row.head:SetHeight(btnH)
    row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.head:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    row.name = widgets.CreateLabel(row.head, "FONT_BODY", "TEXT")
    row.name:SetPoint("LEFT", row.head, "LEFT", 0, 0)
    row.name:SetWordWrap(false)
    row.info = widgets.CreateLabel(row.head, "FONT_SMALL", "TEXT_DIM")
    row.info:SetPoint("LEFT", row.name, "RIGHT", gap * 2, 0)
    row.info:SetWordWrap(false)

    row.save:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(btnH + gap))
    row.load:SetPoint("LEFT", row.save, "RIGHT", gap, 0)
    row.rename:SetPoint("LEFT", row.load, "RIGHT", gap, 0)
    row.delete:SetPoint("LEFT", row.rename, "RIGHT", gap, 0)
    row:SetHeight(btnH * 2 + gap)
    return row
end

-- 레이아웃 페이지 생성, dik, 2026-10-03
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)
    local widgets = ns.Widgets
    scroll, content = widgets.CreateScrollArea(page)
    content:SetHeight(1)

    hintLabel = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    hintLabel:SetWordWrap(true)
    hintLabel:SetText(L.LAYOUTS_HINT)

    local count = ns.Layouts and ns.Layouts.SLOT_COUNT or 5
    for i = 1, count do
        rows[i] = CreateRow(i)
    end

    renameBox = widgets.CreateSearchBox(content, {
        maxLetters = 16,
        placeholder = L.LAYOUTS_RENAME_PLACEHOLDER,
        onEnterPressed = function(text)
            CommitRename(text)
        end,
        onEscapePressed = function()
            CancelRename()
        end,
        onFocusChanged = function(hasFocus)
            if hasFocus or renameIndex == nil then
                return
            end
            if C_Timer and C_Timer.After then
                local idx = renameIndex
                local token = renameToken
                C_Timer.After(0, function()
                    if renameIndex == idx and renameToken == token then
                        CancelRename()
                    end
                end)
            end
        end,
    })
    renameBox:SetTooltip(L.LAYOUTS_BTN_RENAME, L.TIP_LAYOUTS_RENAME)
    renameBox:SetFrameLevel(content:GetFrameLevel() + 10)
    renameBox:Hide()

    backupLabel = widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    noteLabel = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(true)
    noteLabel:SetText(L.LAYOUTS_BACKUP_NOTE)
    undoBtn = widgets.CreateButton(content, L.LAYOUTS_BTN_UNDO, OnUndoClick)
    widgets.SetTooltip(undoBtn, L.LAYOUTS_BTN_UNDO, L.TIP_LAYOUTS_UNDO)
    reloadBtn = widgets.CreateButton(content, L.LAYOUTS_BTN_RELOAD, OnReloadClick)
    widgets.SetTooltip(reloadBtn, L.LAYOUTS_BTN_RELOAD, L.TIP_LAYOUTS_RELOAD)
    reloadBtn:Hide()
    resultLabel = widgets.CreateLabel(content, "FONT_BODY", "DANGER")
    resultLabel:SetWordWrap(true)
    reloadLabel = widgets.CreateLabel(content, "FONT_SMALL", "ACCENT")
    reloadLabel:SetWordWrap(true)
    guardLabel = widgets.CreateLabel(content, "FONT_SMALL", "DANGER")
    guardLabel:SetWordWrap(true)

    if InCombatLockdown and InCombatLockdown() then
        inCombat = true
    end

    page:SetScript("OnSizeChanged", function()
        if page:IsVisible() then
            Layout()
        end
    end)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 채움, dik, 2026-10-03
function module.OnPageShow()
    if InCombatLockdown and InCombatLockdown() then
        inCombat = true
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-10-03
function module.OnPageHide()
    if not page then
        return
    end
    CancelRename()
    CancelConfirm()
end

-- 보일 때만 전체 갱신, dik, 2026-10-03
local function RefreshIfVisible()
    if page and page:IsVisible() then
        FillAll()
    end
end

-- 칸 변경 반영, dik, 2026-10-03
ns.On("LAYOUTS_UPDATED", function()
    RefreshIfVisible()
end)

-- 불러오기 결과 반영(재시작 필요 표시), dik, 2026-10-03
ns.On("LAYOUTS_LOADED", function(_, result)
    if type(result) == "table" and result.reload then
        reloadNeeded = true
    end
    RefreshIfVisible()
end)

-- 적용·되돌리기 결과 반영, dik, 2026-10-03
ns.On("TRANSFER_APPLIED", function(result)
    if type(result) == "table" and result.reload then
        reloadNeeded = true
    end
    RefreshIfVisible()
end)

-- 글꼴 크기 변경 시 보일 때만 갱신, dik, 2026-10-03
ns.On("SETTING_CHANGED", function(scope, key)
    if scope ~= "global" or key ~= "fontSize" then
        return
    end
    RefreshIfVisible()
end)

-- 전투 상태 이벤트 프레임, dik, 2026-10-03
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if page and page:IsVisible() then
        UpdateButtons()
        Layout()
    end
end)
