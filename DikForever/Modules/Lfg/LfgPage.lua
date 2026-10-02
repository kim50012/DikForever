-- 파티 모집 게시판 페이지, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("lfg")
if not module then
    return
end

local L = ns.L

local REFRESH_DELAY = 0.5
local DUNGEON_DROPDOWN_W = 170
local ROLE_DROPDOWN_W = 110
local CATEGORY_DROPDOWN_W = 170
local CUSTOM_VISIBLE_ROWS = 4
local CUSTOM_MAX = 50
local HEADER_H = 28
local FALLBACK_LINE_H = 14
local TIP_SEPARATOR = " · "

local BOARD_COLUMNS = {
    { key = "dungeon", title = L.LFG_COL_DUNGEON, width = 120, align = "LEFT", defaultAsc = true },
    { key = "roles", title = L.LFG_COL_ROLES, width = 60, align = "LEFT", defaultAsc = true },
    { key = "name", title = L.LFG_COL_SENDER, width = 90, align = "LEFT", defaultAsc = true },
    { key = "text", title = L.LFG_COL_TEXT, flex = true, align = "LEFT", defaultAsc = true },
    { key = "at", title = L.LFG_COL_AGE, width = 60, align = "RIGHT", defaultAsc = false },
}

local CUSTOM_COLUMNS = {
    { key = "word", title = L.LFG_COL_WORD, width = 120, align = "LEFT", defaultAsc = true },
    { key = "category", title = L.LFG_COL_CATEGORY, flex = true, align = "LEFT", defaultAsc = true },
}

local DICT_COLUMNS = {
    { key = "name", title = L.LFG_COL_DUNGEON, width = 150, align = "LEFT", defaultAsc = true },
    { key = "aliases", title = L.LFG_COL_ALIASES, flex = true, align = "LEFT", defaultAsc = true },
}

local page
local boardBtn
local wordsBtn
local summaryLabel
local boardArea
local wordsArea
local ddDungeon
local ddRole
local clearBtn
local boardNotice
local boardTbl
local selectLabel
local whisperBtn
local inviteBtn
local resultLabel
local noteLabel
local ddCategory
local searchBox
local addBtn
local wordsResultLabel
local wordsNotice
local customTitle
local customLine
local customTbl
local removeBtn
local dictTitle
local dictLine
local dictTbl

local view = "board"
local dirty = false
local tooltipShown = false
local refreshGen = 0
local refreshPending = false
local dungeonFilter = "all"
local roleFilter = "all"
local categoryKey = "new"
local categoryReady = false
local boardResult
local wordsResult
local customRecs = {}
local lastTotal = 0

-- 글자 높이 계산, dik, 2026-10-01
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 표 행 높이 계산, dik, 2026-10-01
local function GetRowHeight()
    local theme = ns.Theme
    local _, size = theme.GetFont("FONT_BODY"):GetFont()
    if type(size) ~= "number" then
        return theme.MENU_ITEM_H
    end
    return math.max(theme.MENU_ITEM_H, math.ceil(size) + theme.GAP)
end

-- 라벨 색 토큰 적용, dik, 2026-10-01
local function SetLabelColor(label, token)
    label:SetTextColor(ns.Theme.GetColor(token))
end

-- 버튼 활성 전환, dik, 2026-10-01
local function SetButtonEnabled(btn, on)
    if on then
        btn:Enable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT"))
    else
        btn:Disable()
        btn.label:SetTextColor(ns.Theme.GetColor("TEXT_DIM"))
    end
end

-- 직업색 복사 조회, dik, 2026-10-01
local function GetClassColor(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if type(c) == "table" and c.r and c.g and c.b then
        return { r = c.r, g = c.g, b = c.b }
    end
    return nil
end

-- 상태 조회, dik, 2026-10-01
local function GetLfgStatus()
    local s = ns.Lfg.GetStatus()
    if type(s) == "table" then
        return s
    end
    return {}
end

-- 행 툴팁 숨김, dik, 2026-10-01
local function HideRowTooltip()
    if tooltipShown then
        tooltipShown = false
        GameTooltip:Hide()
    end
end

-- 결과 줄 채움, dik, 2026-10-01
local function FillResultLabel(label, result)
    if result then
        label:SetText(result.text)
        SetLabelColor(label, result.token)
    else
        label:SetText("")
    end
end

-- 알림 문구 판정(우선순위 1개), dik, 2026-10-01
local function PickBoardNotice(status, summary)
    if not status.ready then
        return L.LFG_NOT_READY, "TEXT_DIM"
    end
    if status.channelEnabled == false then
        return L.LFG_NO_CHANNEL, "DANGER"
    end
    if type(status.secretSkipped) == "number" and status.secretSkipped > 0 then
        return L.LFG_SECRET:format(status.secretSkipped), "TEXT_DIM"
    end
    if summary.total == 0 then
        return L.LFG_WAITING, "TEXT_DIM"
    end
    return nil, nil
end

-- 알림 줄 채움, dik, 2026-10-01
local function FillNotice(label, text, token)
    label:SetText(text or "")
    if token then
        SetLabelColor(label, token)
    end
end

-- 보기 버튼 색 채움, dik, 2026-10-01
local function FillTopBar()
    boardBtn.label:SetTextColor(ns.Theme.GetColor(view == "board" and "ACCENT" or "TEXT"))
    wordsBtn.label:SetTextColor(ns.Theme.GetColor(view == "words" and "ACCENT" or "TEXT"))
end

-- 선택 줄·버튼 활성 갱신, dik, 2026-10-01
local function UpdateBoardButtons(status, total)
    local id = boardTbl:GetSelectedId()
    local post = id ~= nil and ns.Lfg.GetPost(id) or nil
    if post then
        -- 선택 줄은 짧은 이름 우선, dik, 2026-10-01
        selectLabel:SetText(L.LFG_SELECTED:format(post.name or post.sender or "", post.displayText or ""))
        SetLabelColor(selectLabel, "TEXT")
    else
        selectLabel:SetText(L.LFG_SELECT_NONE)
        SetLabelColor(selectLabel, "TEXT_DIM")
    end
    SetButtonEnabled(whisperBtn, post ~= nil and status.whisper == true)
    SetButtonEnabled(inviteBtn, post ~= nil and status.invite == true)
    SetButtonEnabled(clearBtn, (total or 0) > 0)
end

-- 게시판 보기 채움, dik, 2026-10-01
local function FillBoard(status)
    local dungeonItems = ns.Lfg.GetDungeonFilterItems(dungeonFilter)
    if type(dungeonItems) == "table" and #dungeonItems > 0 then
        ddDungeon:SetItems(dungeonItems, dungeonFilter)
    end
    local recs, summary = ns.Lfg.GetBoardRows(dungeonFilter, roleFilter)
    recs = recs or {}
    summary = summary or { total = #recs, shown = #recs }
    lastTotal = summary.total or 0
    summaryLabel:SetText(L.LFG_SUMMARY:format(summary.total or 0, status.expireMinutes or 0))
    local now = time()
    local rows = {}
    for i = 1, #recs do
        local rec = recs[i]
        local dungeonCell = { text = rec.dungeonText or "", sortValue = rec.dungeonText or "" }
        dungeonCell.colorToken = rec.dungeonText == L.LFG_OTHER and "TEXT_DIM" or "ACCENT"
        local nameCell = { text = rec.name or "", sortValue = rec.name or "" }
        local color = GetClassColor(rec.classFile)
        if color then
            nameCell.color = color
        else
            nameCell.colorToken = "TEXT"
        end
        rows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                dungeon = dungeonCell,
                roles = { text = rec.rolesText or "", sortValue = rec.rolesText or "", colorToken = "TEXT" },
                name = nameCell,
                text = { text = rec.text or "", sortValue = rec.text or "", colorToken = "TEXT" },
                at = { text = ns.FormatElapsed(rec.at, now), sortValue = rec.at or 0, colorToken = "TEXT_DIM" },
            },
        }
    end
    boardTbl:SetRows(rows)
    local text, token = PickBoardNotice(status, summary)
    FillNotice(boardNotice, text, token)
    UpdateBoardButtons(status, summary.total)
    FillResultLabel(resultLabel, boardResult)
    noteLabel:SetText(L.LFG_NOTE)
end

-- 사용자 키워드 버튼 활성 갱신, dik, 2026-10-01
local function UpdateWordsButtons()
    SetButtonEnabled(removeBtn, customTbl:GetSelectedId() ~= nil)
end

-- 키워드 보기 채움, dik, 2026-10-01
local function FillWords(status)
    if not categoryReady then
        local items = ns.Lfg.GetCategoryItems()
        if type(items) == "table" and #items > 0 then
            categoryReady = true
            ddCategory:SetItems(items, categoryKey)
        end
    end
    local recs = ns.Lfg.GetCustomRows() or {}
    customRecs = {}
    local rows = {}
    for i = 1, #recs do
        local rec = recs[i]
        customRecs[rec.id] = rec
        rows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                word = { text = rec.word or "", sortValue = rec.word or "", colorToken = "TEXT" },
                category = { text = rec.categoryText or "", sortValue = rec.categoryText or "", colorToken = "TEXT_DIM" },
            },
        }
    end
    summaryLabel:SetText(L.LFG_CUSTOM_SUMMARY:format(status.customCount or #recs, CUSTOM_MAX))
    customTbl:SetRows(rows)
    customTitle:SetText(L.LFG_CUSTOM_SECTION:format(#recs))

    local drecs = ns.Lfg.GetDictionaryRows() or {}
    local drows = {}
    for i = 1, #drecs do
        local rec = drecs[i]
        drows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                name = { text = rec.name or "", sortValue = rec.name or "", colorToken = rec.raid and "ACCENT" or "TEXT" },
                aliases = { text = rec.aliasText or "", sortValue = rec.aliasText or "", colorToken = "TEXT_DIM" },
            },
        }
    end
    dictTbl:SetRows(drows)
    dictTitle:SetText(L.LFG_DICT_SECTION:format(#drecs))

    if status.readOnly then
        FillNotice(wordsNotice, L.LFG_READ_ONLY, "TEXT_DIM")
    else
        FillNotice(wordsNotice, nil, nil)
    end
    FillResultLabel(wordsResultLabel, wordsResult)
    UpdateWordsButtons()
end

-- 머리글 라벨·선 배치, dik, 2026-10-01
local function PlaceHeader(area, title, line, top)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(top + HEADER_H - math.ceil(GetLineHeight(title)) - 5))
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(top + HEADER_H))
    line:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(top + HEADER_H))
    return top + HEADER_H
end

-- 줄 라벨을 위에서부터 붙이고 다음 y 반환, dik, 2026-10-01
local function PlaceTopLine(area, label, y, gap)
    label:ClearAllPoints()
    if (label:GetText() or "") ~= "" then
        label:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
        label:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -y)
        label:Show()
        return y + math.ceil(GetLineHeight(label)) + gap
    end
    label:Hide()
    return y
end

-- 게시판 배치, dik, 2026-10-01
local function LayoutBoard(gap)
    local rowH = math.max(ddDungeon:GetHeight(), ddRole:GetHeight(), clearBtn:GetHeight())
    ddDungeon:ClearAllPoints()
    ddDungeon:SetPoint("TOPLEFT", boardArea, "TOPLEFT", 0, 0)
    ddRole:ClearAllPoints()
    ddRole:SetPoint("LEFT", ddDungeon, "RIGHT", gap, 0)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("TOPRIGHT", boardArea, "TOPRIGHT", 0, 0)
    local t = PlaceTopLine(boardArea, boardNotice, rowH + gap, gap)

    noteLabel:ClearAllPoints()
    noteLabel:SetPoint("BOTTOMLEFT", boardArea, "BOTTOMLEFT", 0, 0)
    noteLabel:SetPoint("BOTTOMRIGHT", boardArea, "BOTTOMRIGHT", 0, 0)
    local b1 = math.ceil(GetLineHeight(noteLabel)) + gap

    local btnH = whisperBtn:GetHeight()
    whisperBtn:ClearAllPoints()
    whisperBtn:SetPoint("BOTTOMLEFT", boardArea, "BOTTOMLEFT", 0, b1)
    inviteBtn:ClearAllPoints()
    inviteBtn:SetPoint("LEFT", whisperBtn, "RIGHT", gap, 0)
    resultLabel:ClearAllPoints()
    resultLabel:SetPoint("LEFT", inviteBtn, "RIGHT", gap, 0)
    resultLabel:SetPoint("RIGHT", boardArea, "BOTTOMRIGHT", 0, b1 + btnH / 2)
    local b2 = b1 + btnH + gap

    selectLabel:ClearAllPoints()
    selectLabel:SetPoint("BOTTOMLEFT", boardArea, "BOTTOMLEFT", 0, b2)
    selectLabel:SetPoint("BOTTOMRIGHT", boardArea, "BOTTOMRIGHT", 0, b2)
    local b3 = b2 + math.ceil(GetLineHeight(selectLabel)) + gap

    boardTbl:ClearAllPoints()
    boardTbl:SetPoint("TOPLEFT", boardArea, "TOPLEFT", 0, -t)
    boardTbl:SetPoint("TOPRIGHT", boardArea, "TOPRIGHT", 0, -t)
    boardTbl:SetPoint("BOTTOM", boardArea, "BOTTOM", 0, b3)
end

-- 키워드 배치, dik, 2026-10-01
local function LayoutWords(gap)
    local rowH = math.max(ddCategory:GetHeight(), searchBox:GetHeight(), addBtn:GetHeight())
    ddCategory:ClearAllPoints()
    ddCategory:SetPoint("TOPLEFT", wordsArea, "TOPLEFT", 0, 0)
    addBtn:ClearAllPoints()
    addBtn:SetPoint("TOPRIGHT", wordsArea, "TOPRIGHT", 0, 0)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", ddCategory, "TOPRIGHT", gap, 0)
    searchBox:SetPoint("TOPRIGHT", addBtn, "TOPLEFT", -gap, 0)
    local t = PlaceTopLine(wordsArea, wordsNotice, rowH + gap, gap)
    t = PlaceTopLine(wordsArea, wordsResultLabel, t, gap)

    t = PlaceHeader(wordsArea, customTitle, customLine, t)
    local tableH = (1 + CUSTOM_VISIBLE_ROWS) * GetRowHeight()
    customTbl:ClearAllPoints()
    customTbl:SetPoint("TOPLEFT", wordsArea, "TOPLEFT", 0, -(t + 1))
    customTbl:SetPoint("TOPRIGHT", wordsArea, "TOPRIGHT", 0, -(t + 1))
    customTbl:SetHeight(tableH)
    t = t + 1 + tableH + gap

    removeBtn:ClearAllPoints()
    removeBtn:SetPoint("TOPLEFT", wordsArea, "TOPLEFT", 0, -t)
    t = t + removeBtn:GetHeight() + gap

    t = PlaceHeader(wordsArea, dictTitle, dictLine, t)
    dictTbl:ClearAllPoints()
    dictTbl:SetPoint("TOPLEFT", wordsArea, "TOPLEFT", 0, -(t + 1))
    dictTbl:SetPoint("TOPRIGHT", wordsArea, "TOPRIGHT", 0, -(t + 1))
    dictTbl:SetPoint("BOTTOM", wordsArea, "BOTTOM", 0, 0)
end

-- 전체 재배치, dik, 2026-10-01
local function Layout()
    local gap = ns.Theme.GAP
    boardBtn:ClearAllPoints()
    boardBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    wordsBtn:ClearAllPoints()
    wordsBtn:SetPoint("LEFT", boardBtn, "RIGHT", gap, 0)
    summaryLabel:ClearAllPoints()
    summaryLabel:SetPoint("RIGHT", page, "TOPRIGHT", 0, -(boardBtn:GetHeight() / 2))
    local y = boardBtn:GetHeight() + gap
    for _, area in ipairs({ boardArea, wordsArea }) do
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    end
    if view == "board" then
        LayoutBoard(gap)
    else
        LayoutWords(gap)
    end
end

-- 전체 채움, dik, 2026-10-01
local function FillAll()
    if not page then
        return
    end
    dirty = false
    FillTopBar()
    local status = GetLfgStatus()
    if view == "board" then
        wordsArea:Hide()
        boardArea:Show()
        FillBoard(status)
    else
        boardArea:Hide()
        wordsArea:Show()
        FillWords(status)
    end
    Layout()
end

-- 보기 전환, dik, 2026-10-01
local function SetView(v)
    if view == v then
        return
    end
    view = v
    HideRowTooltip()
    searchBox:ClearFocus()
    ddDungeon:Close()
    ddRole:Close()
    ddCategory:Close()
    FillAll()
end

-- 글 행 오버 툴팁, dik, 2026-10-01
local function ShowPostTooltip(rowFrame, row)
    local id = row and row.id
    local post = id ~= nil and ns.Lfg.GetPost(id) or nil
    if not post then
        return
    end
    local ar, ag, ab = ns.Theme.GetColor("ACCENT")
    local tr, tg, tb = ns.Theme.GetColor("TEXT")
    local dr, dg, db = ns.Theme.GetColor("TEXT_DIM")
    local cr, cg, cb = ar, ag, ab
    local c = RAID_CLASS_COLORS and post.classFile and RAID_CLASS_COLORS[post.classFile]
    if type(c) == "table" and c.r and c.g and c.b then
        cr, cg, cb = c.r, c.g, c.b
    end
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(post.sender or post.name or "", cr, cg, cb)
    GameTooltip:AddLine((post.channel or "") .. TIP_SEPARATOR .. ns.FormatElapsed(post.at, time()), dr, dg, db)
    GameTooltip:AddLine(post.displayText or "", tr, tg, tb, true)
    local names = post.dungeonNames
    local dungeonText = L.LFG_OTHER
    if type(names) == "table" and #names > 0 then
        dungeonText = table.concat(names, TIP_SEPARATOR)
    end
    GameTooltip:AddLine(L.LFG_COL_DUNGEON .. ": " .. dungeonText, dr, dg, db)
    local roleLine = L.LFG_COL_ROLES .. ": " .. (post.rolesText or L.VALUE_UNKNOWN)
    if post.size then
        roleLine = roleLine .. TIP_SEPARATOR .. post.size
    end
    GameTooltip:AddLine(roleLine, dr, dg, db)
    GameTooltip:Show()
    tooltipShown = true
end

-- 글 행 클릭 처리(선택만), dik, 2026-10-01
local function OnBoardRowClick(row)
    boardTbl:SetSelectedId(row.id)
    boardResult = nil
    FillResultLabel(resultLabel, nil)
    UpdateBoardButtons(GetLfgStatus(), lastTotal)
    Layout()
end

-- 사용자 키워드 행 클릭 처리, dik, 2026-10-01
local function OnCustomRowClick(row)
    customTbl:SetSelectedId(row.id)
    UpdateWordsButtons()
end

-- 귓말·초대 결과 줄 반영, dik, 2026-10-01
local function ApplyActionResult(ok, errKey, name, okText)
    if ok then
        boardResult = { text = okText:format(name or ""), token = "TEXT" }
    else
        boardResult = { text = L[errKey or "LFG_ERR_POST_GONE"] or L.LFG_ERR_POST_GONE, token = "DANGER" }
    end
    FillResultLabel(resultLabel, boardResult)
    Layout()
end

-- 목록 비우기, dik, 2026-10-01
local function OnClearClick()
    ns.Lfg.ClearPosts()
    boardTbl:SetSelectedId(nil)
    boardResult = nil
    FillAll()
end

-- 키워드 추가, dik, 2026-10-01
local function OnAddClick()
    local input = searchBox:GetText() or ""
    local ok, errKey = ns.Lfg.AddCustomWord(input, categoryKey)
    if ok then
        searchBox:SetText("")
        -- 추가 결과는 정규화 단어로 행 조회, dik, 2026-10-01
        local norm, compact = ns.Lfg.NormalizeWord(input)
        local word, category = norm or input, ""
        local rows = ns.Lfg.GetCustomRows() or {}
        for i = 1, #rows do
            local rec = rows[i]
            if rec.word ~= nil and (rec.id == compact or rec.word == norm or rec.word == compact) then
                word, category = rec.word, rec.categoryText or ""
                break
            end
        end
        wordsResult = { text = L.LFG_WORD_ADDED:format(word, category), token = "TEXT" }
    else
        local text = L[errKey or "LFG_ERR_NOT_READY"] or L.LFG_ERR_NOT_READY
        if errKey == "LFG_ERR_WORD_FULL" then
            text = text:format(CUSTOM_MAX)
        end
        wordsResult = { text = text, token = "DANGER" }
    end
    FillAll()
end

-- 키워드 삭제, dik, 2026-10-01
local function OnRemoveClick()
    local id = customTbl:GetSelectedId()
    local rec = id ~= nil and customRecs[id] or nil
    if not rec then
        return
    end
    ns.Lfg.RemoveCustomWord(rec.word)
    customTbl:SetSelectedId(nil)
    wordsResult = nil
    FillAll()
end

-- 드롭다운 변경 처리(대기 중 갱신 취소), dik, 2026-10-01
local function OnFilterChanged()
    refreshGen = refreshGen + 1
    refreshPending = false
    FillAll()
end

-- 헤더 구분선 생성, dik, 2026-10-01
local function CreateLine(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(ns.Theme.GetColor("BORDER"))
    return line
end

-- 파티 모집 페이지 생성, dik, 2026-10-01
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)
    local widgets = ns.Widgets
    local rowH = ns.Theme.MENU_ITEM_H

    boardBtn = widgets.CreateButton(page, L.LFG_VIEW_BOARD, function()
        SetView("board")
    end)
    wordsBtn = widgets.CreateButton(page, L.LFG_VIEW_WORDS, function()
        SetView("words")
    end)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(boardBtn, L.LFG_VIEW_BOARD, L.TIP_LFG_VIEW_BOARD)
    widgets.SetTooltip(wordsBtn, L.LFG_VIEW_WORDS, L.TIP_LFG_VIEW_WORDS)
    summaryLabel = widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    summaryLabel:SetJustifyH("RIGHT")

    boardArea = CreateFrame("Frame", nil, page)
    wordsArea = CreateFrame("Frame", nil, page)

    ddDungeon = widgets.CreateDropdown(boardArea, { width = DUNGEON_DROPDOWN_W,
        items = { { value = "all", text = L.LFG_FILTER_ALL:format(0) } }, value = "all",
        onChange = function(value)
            dungeonFilter = value or "all"
            OnFilterChanged()
        end })
    ddRole = widgets.CreateDropdown(boardArea, { width = ROLE_DROPDOWN_W,
        items = ns.Lfg.GetRoleFilterItems(), value = "all",
        onChange = function(value)
            roleFilter = value or "all"
            OnFilterChanged()
        end })
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(ddDungeon, nil, L.TIP_LFG_DUNGEON)
    widgets.SetTooltip(ddRole, nil, L.TIP_LFG_ROLE)
    clearBtn = widgets.CreateButton(boardArea, L.LFG_BTN_CLEAR, OnClearClick)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(clearBtn, L.LFG_BTN_CLEAR, L.TIP_LFG_CLEAR)
    boardNotice = widgets.CreateLabel(boardArea, "FONT_SMALL", "TEXT_DIM")
    boardNotice:SetWordWrap(false)
    boardTbl = widgets.CreateTable(boardArea, BOARD_COLUMNS, {
        rowHeight = rowH,
        emptyText = L.LFG_EMPTY,
        onRowClick = OnBoardRowClick,
        onRowEnter = ShowPostTooltip,
        onRowLeave = HideRowTooltip,
    })
    boardTbl:SetSort("at", false)
    selectLabel = widgets.CreateLabel(boardArea, "FONT_BODY", "TEXT_DIM")
    selectLabel:SetWordWrap(false)
    whisperBtn = widgets.CreateButton(boardArea, L.LFG_BTN_WHISPER, function()
        local ok, errKey, name = ns.Lfg.OpenWhisper(boardTbl:GetSelectedId())
        ApplyActionResult(ok, errKey, name, L.LFG_WHISPER_OPENED)
    end)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(whisperBtn, L.LFG_BTN_WHISPER, L.TIP_LFG_WHISPER)
    inviteBtn = widgets.CreateButton(boardArea, L.LFG_BTN_INVITE, function()
        local ok, errKey, name = ns.Lfg.Invite(boardTbl:GetSelectedId())
        ApplyActionResult(ok, errKey, name, L.LFG_INVITED)
    end)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(inviteBtn, L.LFG_BTN_INVITE, L.TIP_LFG_INVITE)
    resultLabel = widgets.CreateLabel(boardArea, "FONT_SMALL", "TEXT")
    resultLabel:SetWordWrap(false)
    resultLabel:SetJustifyH("LEFT")
    noteLabel = widgets.CreateLabel(boardArea, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(true)

    ddCategory = widgets.CreateDropdown(wordsArea, { width = CATEGORY_DROPDOWN_W,
        items = { { value = "new", text = L.LFG_CATEGORY_NEW } }, value = "new",
        onChange = function(value)
            categoryKey = value or "new"
        end })
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(ddCategory, nil, L.TIP_LFG_CATEGORY)
    searchBox = widgets.CreateSearchBox(wordsArea, { placeholder = L.LFG_WORD_PLACEHOLDER, maxLetters = 30 })
    -- 툴팁 연결, dik, 2026-10-01
    searchBox:SetTooltip(nil, L.TIP_LFG_WORD)
    addBtn = widgets.CreateButton(wordsArea, L.LFG_BTN_ADD, OnAddClick)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(addBtn, L.LFG_BTN_ADD, L.TIP_LFG_ADD)
    wordsResultLabel = widgets.CreateLabel(wordsArea, "FONT_SMALL", "TEXT")
    wordsResultLabel:SetWordWrap(false)
    wordsNotice = widgets.CreateLabel(wordsArea, "FONT_SMALL", "TEXT_DIM")
    wordsNotice:SetWordWrap(false)
    customTitle = widgets.CreateLabel(wordsArea, "FONT_MENU", "ACCENT")
    customTitle:SetWordWrap(false)
    customLine = CreateLine(wordsArea)
    customTbl = widgets.CreateTable(wordsArea, CUSTOM_COLUMNS, {
        rowHeight = rowH,
        emptyText = L.LFG_CUSTOM_EMPTY,
        onRowClick = OnCustomRowClick,
    })
    removeBtn = widgets.CreateButton(wordsArea, L.LFG_BTN_REMOVE, OnRemoveClick)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(removeBtn, L.LFG_BTN_REMOVE, L.TIP_LFG_REMOVE)
    dictTitle = widgets.CreateLabel(wordsArea, "FONT_MENU", "ACCENT")
    dictTitle:SetWordWrap(false)
    dictLine = CreateLine(wordsArea)
    dictTbl = widgets.CreateTable(wordsArea, DICT_COLUMNS, { rowHeight = rowH })

    page:SetScript("OnSizeChanged", function()
        if page:IsVisible() then
            Layout()
        end
    end)

    FillAll()
    return page
end

-- 위젯 글꼴 갱신, dik, 2026-10-01
local function RefreshWidgets()
    ddDungeon:Refresh()
    ddRole:Refresh()
    ddCategory:Refresh()
    searchBox:Refresh()
    boardTbl:Refresh()
    customTbl:Refresh()
    dictTbl:Refresh()
end

-- 페이지 표시 시 전체 채움, dik, 2026-10-01
function module.OnPageShow()
    if dirty and page then
        RefreshWidgets()
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-10-01
function module.OnPageHide()
    if not page then
        return
    end
    ddDungeon:Close()
    ddRole:Close()
    ddCategory:Close()
    searchBox:ClearFocus()
    HideRowTooltip()
end

-- 갱신 합치기 예약, dik, 2026-10-01
local function QueueRefresh(fonts)
    if not page then
        return
    end
    if not page:IsVisible() then
        dirty = true
        return
    end
    if fonts then
        RefreshWidgets()
    end
    -- 대기 중이면 새 예약 없이 합침, dik, 2026-10-01
    if refreshPending then
        return
    end
    refreshGen = refreshGen + 1
    local gen = refreshGen
    if C_Timer and C_Timer.After then
        refreshPending = true
        C_Timer.After(REFRESH_DELAY, function()
            if gen ~= refreshGen then
                return
            end
            refreshPending = false
            if page:IsVisible() then
                FillAll()
            else
                dirty = true
            end
        end)
    else
        FillAll()
    end
end

-- 모집 갱신 이벤트 처리, dik, 2026-10-01
ns.On("LFG_UPDATED", function()
    QueueRefresh(false)
end)

-- 설정 변경 반영, dik, 2026-10-01
ns.On("SETTING_CHANGED", function(scope, key)
    if scope == "global" and key == "fontSize" then
        QueueRefresh(true)
    elseif scope == "lfg" then
        QueueRefresh(false)
    end
end)
