-- 설정 이전 페이지, dik, 2026-10-02
local addonName, ns = ...

local module = ns.GetModule("transfer")
if not module then
    return
end

local L = ns.L

local CONFIRM_SECONDS = 5
local AREA_H = 90
local SHARE_AREA_H = 70
local HEADER_H = 28
local CHECK_H = 24
local FALLBACK_LINE_H = 14
local CHECK_W = 360

local PARTS = { "settings", "layout", "lists", "editMode" }
local APPLY_PARTS = { "settings", "layout", "lists" }
local PART_LABEL = {
    settings = L.TRANSFER_PART_SETTINGS,
    layout = L.TRANSFER_PART_LAYOUT,
    lists = L.TRANSFER_PART_LISTS,
    editMode = L.TRANSFER_PART_EDITMODE,
}
local COUNT_FORMAT = {
    settings = L.TRANSFER_COUNT_SETTINGS,
    layout = L.TRANSFER_COUNT_LAYOUT,
    lists = L.TRANSFER_COUNT_LISTS,
    editMode = L.TRANSFER_COUNT_EDITMODE,
}
local KIND_LABEL = {
    account = L.TRANSFER_KIND_ACCOUNT,
    character = L.TRANSFER_KIND_CHARACTER,
}

local page
local scroll
local content
local exportHeader
local importHeader
local exportCbs = {}
local importCbs = {}
local exportNote
local exportBtn
local exportCombat
local exportArea
local exportHint
local exportCounts
local pasteHint
local inputArea
local inspectBtn
local clearInputBtn
local importError
local previewCreated
local previewCounts
local previewSkipped
local applyBtn
local layoutTitle
local layoutRows = {}
local shareArea
local shareHint
local backupLabel
local undoBtn
local resultLabel
local guardLabel

local exportChecked = { settings = true, layout = true, lists = true, editMode = true }
local importChecked = { settings = false, layout = false, lists = false }
local importEnabled = { settings = false, layout = false, lists = false }
local exportDone = false
local exportCountText = ""
local preview
local importErrorText
local shareShown = false
local lastResultText
local pendingKind
local inCombat = false
local exportErrorText
local confirmArmed = false
local confirmAt = 0
local confirmToken = 0

-- ns.Transfer 함수 조회, dik, 2026-10-02
local function Tr(name)
    local t = ns.Transfer
    local f = t and t[name]
    if type(f) == "function" then
        return f
    end
    return nil
end

-- 오류 문장 조회, dik, 2026-10-02
local function ErrorText(errCode)
    local f = Tr("GetErrorText")
    if f then
        return f(errCode)
    end
    return L.TRANSFER_ERR_FMT or ""
end

-- 글자 높이 계산, dik, 2026-10-02
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return math.ceil(h)
end

-- 버튼 활성 전환, dik, 2026-10-02
local function SetButtonEnabled(btn, on)
    if on then
        btn:Enable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT"))
    else
        btn:Disable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT_DIM"))
    end
end

-- 저장 데이터가 새 버전인지, dik, 2026-10-02
local function IsReadOnly()
    return ns.IsDatabaseNewer() and true or false
end

-- 적용 확인 취소, dik, 2026-10-02
local function CancelConfirm()
    confirmArmed = false
    confirmToken = confirmToken + 1
    if applyBtn then
        applyBtn.label:SetText(L.TRANSFER_BTN_APPLY)
    end
end

-- 적용 버튼 폭 고정, dik, 2026-10-02
local function FitApplyButton()
    local label = applyBtn.label
    local current = label:GetText()
    local maxW = 0
    local texts = { L.TRANSFER_BTN_APPLY, L.TRANSFER_BTN_APPLY_CONFIRM }
    for i = 1, #texts do
        label:SetText(texts[i])
        maxW = math.max(maxW, label:GetStringWidth())
    end
    label:SetText(current)
    applyBtn:SetWidth(math.floor(maxW + ns.Theme.PAD * 2 + 0.5))
end

-- 체크 항목 집합 생성, dik, 2026-10-02
local function BuildPartsSet(parts, checked)
    local set = {}
    local any = false
    for i = 1, #parts do
        if checked[parts[i]] then
            set[parts[i]] = true
            any = true
        end
    end
    return set, any
end

-- 개수 줄 문장 생성, dik, 2026-10-02
local function BuildCountText(counts)
    local out = {}
    if type(counts) ~= "table" then
        return ""
    end
    for i = 1, #PARTS do
        local n = counts[PARTS[i]]
        if type(n) == "number" then
            out[#out + 1] = COUNT_FORMAT[PARTS[i]]:format(n)
        end
    end
    return table.concat(out, " · ")
end

-- 버튼·체크박스 활성 상태 갱신, dik, 2026-10-02
local function UpdateButtons()
    if not page then
        return
    end
    local readOnly = IsReadOnly()
    local _, anyExport = BuildPartsSet(PARTS, exportChecked)
    SetButtonEnabled(exportBtn, not inCombat and anyExport)

    local _, anyImport = BuildPartsSet(APPLY_PARTS, importChecked)
    local canApply = preview ~= nil and not inCombat and not readOnly and anyImport
    if not canApply and confirmArmed then
        CancelConfirm()
    end
    SetButtonEnabled(applyBtn, canApply)

    local hasBackup = false
    local f = Tr("HasBackup")
    if f then
        hasBackup = f() and true or false
    end
    SetButtonEnabled(undoBtn, hasBackup and not inCombat and not readOnly)

    local guardText
    if inCombat then
        guardText = ErrorText("E-COMBAT")
    elseif readOnly then
        guardText = ErrorText("E-READONLY")
    end
    guardLabel:SetText(guardText or "")
    exportCombat:SetText(inCombat and ErrorText("E-COMBAT") or exportErrorText or "")
end

-- 내보내기 체크박스 상태 채움, dik, 2026-10-02
local function FillExportChecks()
    local status = "ok"
    local f = Tr("GetEditModeStatus")
    if f then
        status = f()
    end
    local editOk = status == "ok"
    if not editOk then
        exportChecked.editMode = false
    end
    exportCbs.editMode:SetEnabled(editOk)
    if status == "missing" then
        exportNote:SetText(L.TRANSFER_EDITMODE_MISSING)
    elseif status == "empty" then
        exportNote:SetText(L.TRANSFER_EDITMODE_EMPTY)
    else
        exportNote:SetText("")
    end
    for i = 1, #PARTS do
        exportCbs[PARTS[i]]:Refresh()
    end
end

-- 가져오기 체크박스 상태 채움, dik, 2026-10-02
local function FillImportChecks()
    for i = 1, #APPLY_PARTS do
        local part = APPLY_PARTS[i]
        importCbs[part]:SetEnabled(importEnabled[part])
        importCbs[part]:Refresh()
    end
end

-- 레이아웃 행 확보, dik, 2026-10-02
local function EnsureLayoutRow(index)
    local row = layoutRows[index]
    if row then
        return row
    end
    local widgets = ns.Widgets
    row = CreateFrame("Frame", nil, content)
    row.btn = widgets.CreateButton(row, L.TRANSFER_BTN_VIEW, function()
        local item = row.item
        if item and type(item.share) == "string" then
            shareShown = true
            shareArea:SetText(item.share)
            shareArea:SelectAll()
            module.RefreshLayout()
        end
    end)
    widgets.SetTooltip(row.btn, L.TRANSFER_BTN_VIEW, L.TIP_TRANSFER_VIEW)
    row.btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.kind = widgets.CreateLabel(row, "FONT_SMALL", "TEXT_DIM")
    row.kind:SetPoint("RIGHT", row.btn, "LEFT", -ns.Theme.GAP, 0)
    row.kind:SetWordWrap(false)
    row.name = widgets.CreateLabel(row, "FONT_BODY", "TEXT")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row.kind, "LEFT", -ns.Theme.GAP, 0)
    row.name:SetWordWrap(false)
    row:SetHeight(row.btn:GetHeight())
    layoutRows[index] = row
    return row
end

-- 레이아웃 행 채움, dik, 2026-10-02
local function FillLayoutRows()
    local list = preview and type(preview.layouts) == "table" and preview.layouts or {}
    for i = 1, #list do
        local row = EnsureLayoutRow(i)
        local item = list[i]
        row.item = item
        row.name:SetText(type(item.name) == "string" and item.name or L.VALUE_UNKNOWN)
        row.kind:SetText(KIND_LABEL[item.kind] or L.TRANSFER_KIND_OTHER)
        row:Show()
    end
    for i = #list + 1, #layoutRows do
        layoutRows[i].item = nil
        layoutRows[i]:Hide()
    end
    return #list
end

-- 전체 배치, dik, 2026-10-02
local function Layout()
    if not page then
        return
    end
    local gap = ns.Theme.GAP
    local y = 0

    -- 영역 하나를 위쪽 기준 가로 전체로 배치, dik, 2026-10-02
    local function Place(region, height, indent)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", content, "TOPLEFT", indent or 0, -y)
        region:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + height + gap
    end

    -- 글자 줄 배치(빈 글이면 숨김), dik, 2026-10-02
    local function PlaceText(label)
        if (label:GetText() or "") == "" then
            label:Hide()
            return
        end
        label:Show()
        Place(label, GetLineHeight(label))
    end

    -- 체크박스 한 줄 배치, dik, 2026-10-02
    local function PlaceCheck(cb)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        cb:SetWidth(CHECK_W)
        y = y + CHECK_H + gap
    end

    -- 버튼 줄 배치(왼쪽부터), dik, 2026-10-02
    local function PlaceButtons(buttons)
        buttons[1]:ClearAllPoints()
        buttons[1]:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        for i = 2, #buttons do
            buttons[i]:ClearAllPoints()
            buttons[i]:SetPoint("LEFT", buttons[i - 1], "RIGHT", gap, 0)
        end
        y = y + buttons[1]:GetHeight() + gap
    end

    Place(exportHeader, HEADER_H)
    for i = 1, #PARTS do
        local cb = exportCbs[PARTS[i]]
        PlaceCheck(cb)
    end
    PlaceText(exportNote)
    PlaceButtons({ exportBtn })
    PlaceText(exportCombat)
    if exportDone then
        exportArea:Show()
        Place(exportArea, exportArea:GetHeight())
        exportHint:SetText(L.TRANSFER_COPY_HINT)
        PlaceText(exportHint)
        exportCounts:SetText(exportCountText)
        PlaceText(exportCounts)
    else
        exportArea:Hide()
        exportHint:Hide()
        exportCounts:Hide()
    end

    y = y + gap
    Place(importHeader, HEADER_H)
    PlaceText(pasteHint)
    Place(inputArea, inputArea:GetHeight())
    PlaceButtons({ inspectBtn, clearInputBtn })
    importError:SetText(importErrorText or "")
    PlaceText(importError)

    local layoutCount = FillLayoutRows()
    if preview then
        PlaceText(previewCreated)
        PlaceText(previewCounts)
        PlaceText(previewSkipped)
        for i = 1, #APPLY_PARTS do
            PlaceCheck(importCbs[APPLY_PARTS[i]])
            importCbs[APPLY_PARTS[i]]:Show()
        end
        PlaceButtons({ applyBtn })
        applyBtn:Show()
        if layoutCount > 0 then
            layoutTitle:Show()
            Place(layoutTitle, GetLineHeight(layoutTitle))
            for i = 1, layoutCount do
                Place(layoutRows[i], layoutRows[i]:GetHeight())
            end
            if shareShown then
                shareArea:Show()
                Place(shareArea, shareArea:GetHeight())
                shareHint:Show()
                Place(shareHint, GetLineHeight(shareHint))
            else
                shareArea:Hide()
                shareHint:Hide()
            end
        else
            layoutTitle:Hide()
            shareArea:Hide()
            shareHint:Hide()
        end
    else
        previewCreated:Hide()
        previewCounts:Hide()
        previewSkipped:Hide()
        for i = 1, #APPLY_PARTS do
            importCbs[APPLY_PARTS[i]]:Hide()
        end
        applyBtn:Hide()
        layoutTitle:Hide()
        shareArea:Hide()
        shareHint:Hide()
    end

    y = y + gap
    Place(backupLabel, GetLineHeight(backupLabel))
    PlaceButtons({ undoBtn })
    PlaceText(resultLabel)
    PlaceText(guardLabel)

    content:SetHeight(math.max(1, y))
    scroll.UpdateLayout()
end

-- 미리보기 글 채움, dik, 2026-10-02
local function FillPreview()
    if not preview then
        return
    end
    previewCreated:SetText(L.TRANSFER_PREVIEW_CREATED:format(ns.FormatDateTime(preview.created)))
    previewCounts:SetText(BuildCountText(preview.counts))
    local skipped = type(preview.skipped) == "number" and preview.skipped or 0
    previewSkipped:SetText(skipped > 0 and L.TRANSFER_PREVIEW_SKIPPED:format(skipped) or "")
end

-- 백업 상태 글 채움, dik, 2026-10-02
local function FillBackup()
    local f = Tr("HasBackup")
    local has, created
    if f then
        has, created = f()
    end
    if has then
        backupLabel:SetText(L.TRANSFER_BACKUP_AT:format(ns.FormatDateTime(created)))
    else
        backupLabel:SetText(L.TRANSFER_NO_BACKUP)
    end
    resultLabel:SetText(lastResultText or "")
end

-- 전체 채움, dik, 2026-10-02
local function FillAll()
    if not page then
        return
    end
    FillExportChecks()
    FillImportChecks()
    FillPreview()
    FillBackup()
    UpdateButtons()
    Layout()
end

-- 레이아웃 갱신 진입점, dik, 2026-10-02
function module.RefreshLayout()
    Layout()
end

-- 가져오기 결과 초기화, dik, 2026-10-02
local function ResetPreview()
    preview = nil
    importErrorText = nil
    shareShown = false
    for i = 1, #APPLY_PARTS do
        importChecked[APPLY_PARTS[i]] = false
        importEnabled[APPLY_PARTS[i]] = false
    end
    if shareArea then
        shareArea:Clear()
        shareArea:ClearFocus()
    end
    CancelConfirm()
end

-- 내보내기 문자열 만들기, dik, 2026-10-02
local function OnExportClick()
    local f = Tr("Export")
    if not f then
        return
    end
    local set = BuildPartsSet(PARTS, exportChecked)
    local text, info = f(set)
    if type(text) ~= "string" then
        exportDone = false
        exportCountText = ""
        exportErrorText = ErrorText(info)
        exportArea:Clear()
        FillAll()
        return
    end
    exportErrorText = nil
    exportDone = true
    exportCountText = BuildCountText(info)
    exportArea:SetText(text)
    FillAll()
    exportArea:SelectAll()
end

-- 검사, dik, 2026-10-02
local function OnInspectClick()
    local f = Tr("Inspect")
    if not f then
        return
    end
    ResetPreview()
    local result, errCode = f(inputArea:GetText())
    if type(result) == "table" then
        preview = result
        local counts = type(result.counts) == "table" and result.counts or {}
        for i = 1, #APPLY_PARTS do
            local part = APPLY_PARTS[i]
            local has = type(counts[part]) == "number" and counts[part] > 0
            importEnabled[part] = has
            importChecked[part] = has
        end
    else
        importErrorText = ErrorText(errCode)
    end
    FillAll()
end

-- 입력 지우기, dik, 2026-10-02
local function OnClearInputClick()
    inputArea:Clear()
    inputArea:ClearFocus()
    ResetPreview()
    FillAll()
end

-- 적용 두 번 눌러 확인, dik, 2026-10-02
local function OnApplyClick()
    local f = Tr("Apply")
    if not f or not preview then
        return
    end
    if confirmArmed and GetTime() - confirmAt <= CONFIRM_SECONDS then
        CancelConfirm()
        local set = BuildPartsSet(APPLY_PARTS, importChecked)
        pendingKind = "apply"
        local result, errCode = f(preview, set)
        pendingKind = nil
        if not result then
            lastResultText = ErrorText(errCode)
            FillAll()
        end
        return
    end
    confirmArmed = true
    confirmAt = GetTime()
    confirmToken = confirmToken + 1
    applyBtn.label:SetText(L.TRANSFER_BTN_APPLY_CONFIRM)
    if C_Timer and C_Timer.After then
        local token = confirmToken
        C_Timer.After(CONFIRM_SECONDS, function()
            if token == confirmToken and confirmArmed then
                CancelConfirm()
            end
        end)
    end
end

-- 되돌리기, dik, 2026-10-02
local function OnUndoClick()
    local f = Tr("Undo")
    if not f then
        return
    end
    CancelConfirm()
    pendingKind = "undo"
    local result, errCode = f()
    pendingKind = nil
    if not result then
        lastResultText = ErrorText(errCode)
        FillAll()
    end
end

-- 체크박스 생성, dik, 2026-10-02
local function MakeCheckbox(parent, part, checked, onChanged)
    return ns.Widgets.CreateCheckbox(parent, { label = PART_LABEL[part] }, function()
        return checked[part] and true or false
    end, function(value)
        checked[part] = value and true or false
        CancelConfirm()
        onChanged()
    end)
end

-- 설정 이전 페이지 생성, dik, 2026-10-02
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)
    local widgets = ns.Widgets
    scroll, content = widgets.CreateScrollArea(page)
    content:SetHeight(1)

    exportHeader = widgets.CreateSectionHeader(content, L.TRANSFER_EXPORT_TITLE)
    for i = 1, #PARTS do
        exportCbs[PARTS[i]] = MakeCheckbox(content, PARTS[i], exportChecked, UpdateButtons)
    end
    exportNote = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    exportNote:SetWordWrap(true)
    exportBtn = widgets.CreateButton(content, L.TRANSFER_BTN_EXPORT, OnExportClick)
    widgets.SetTooltip(exportBtn, L.TRANSFER_BTN_EXPORT, L.TIP_TRANSFER_EXPORT)
    exportCombat = widgets.CreateLabel(content, "FONT_SMALL", "DANGER")
    exportCombat:SetWordWrap(true)
    exportArea = widgets.CreateTextArea(content, { readOnly = true, height = AREA_H })
    exportHint = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    exportCounts = widgets.CreateLabel(content, "FONT_SMALL", "TEXT")
    exportCounts:SetWordWrap(true)

    importHeader = widgets.CreateSectionHeader(content, L.TRANSFER_IMPORT_TITLE)
    pasteHint = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    pasteHint:SetWordWrap(true)
    pasteHint:SetText(L.TRANSFER_PASTE_HINT)
    inputArea = widgets.CreateTextArea(content, { height = AREA_H })
    inspectBtn = widgets.CreateButton(content, L.TRANSFER_BTN_INSPECT, OnInspectClick)
    clearInputBtn = widgets.CreateButton(content, L.TRANSFER_BTN_CLEAR, OnClearInputClick)
    widgets.SetTooltip(inspectBtn, L.TRANSFER_BTN_INSPECT, L.TIP_TRANSFER_INSPECT)
    widgets.SetTooltip(clearInputBtn, L.TRANSFER_BTN_CLEAR, L.TIP_TRANSFER_CLEAR)
    importError = widgets.CreateLabel(content, "FONT_SMALL", "DANGER")
    importError:SetWordWrap(true)

    previewCreated = widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    previewCounts = widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    previewCounts:SetWordWrap(true)
    previewSkipped = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    for i = 1, #APPLY_PARTS do
        importCbs[APPLY_PARTS[i]] = MakeCheckbox(content, APPLY_PARTS[i], importChecked, UpdateButtons)
    end
    applyBtn = widgets.CreateButton(content, L.TRANSFER_BTN_APPLY, OnApplyClick)
    FitApplyButton()
    widgets.SetTooltip(applyBtn, L.TRANSFER_BTN_APPLY, L.TIP_TRANSFER_APPLY)
    layoutTitle = widgets.CreateLabel(content, "FONT_BODY", "ACCENT")
    layoutTitle:SetText(L.TRANSFER_PART_EDITMODE)
    shareArea = widgets.CreateTextArea(content, { readOnly = true, height = SHARE_AREA_H })
    shareHint = widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
    shareHint:SetWordWrap(true)
    shareHint:SetText(L.TRANSFER_EDITMODE_HINT)

    backupLabel = widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    undoBtn = widgets.CreateButton(content, L.TRANSFER_BTN_UNDO, OnUndoClick)
    widgets.SetTooltip(undoBtn, L.TRANSFER_BTN_UNDO, L.TIP_TRANSFER_UNDO)
    resultLabel = widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    resultLabel:SetWordWrap(true)
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

-- 페이지 표시 시 전체 채움, dik, 2026-10-02
function module.OnPageShow()
    if InCombatLockdown and InCombatLockdown() then
        inCombat = true
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-10-02
function module.OnPageHide()
    if not page then
        return
    end
    inputArea:ClearFocus()
    exportArea:ClearFocus()
    shareArea:ClearFocus()
    CancelConfirm()
end

-- 적용·되돌리기 결과 반영, dik, 2026-10-02
ns.On("TRANSFER_APPLIED", function(result)
    if type(result) == "table" then
        local fmt = pendingKind == "undo" and L.TRANSFER_UNDO_SUMMARY or L.TRANSFER_SUMMARY
        local text = fmt:format(result.applied or 0, result.skipped or 0)
        if result.reload then
            text = text .. " · " .. L.TRANSFER_RELOAD
        end
        lastResultText = text
    end
    if not page then
        return
    end
    if page:IsVisible() then
        FillAll()
    end
end)

-- 설정 변경 시 보일 때만 갱신, dik, 2026-10-02
ns.On("SETTING_CHANGED", function(scope, key)
    if not page or scope ~= "global" or key ~= "fontSize" then
        return
    end
    if page:IsVisible() then
        FillAll()
    end
end)

-- 전투 상태 이벤트 프레임, dik, 2026-10-02
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if not page then
        return
    end
    if page:IsVisible() then
        UpdateButtons()
        Layout()
    end
end)
