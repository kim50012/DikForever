-- 평판·진척 모듈 페이지, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("progress")
if not module then
    return
end

local L = ns.L
local format = string.format

local DROPDOWN_W = 170
local PVP_VISIBLE_ROWS = 4
local FALLBACK_LINE_H = 14

local VIEWS = { "rep", "legacy", "pvp", "explore" }

local VIEW_TITLES = {
    rep = "PROGRESS_VIEW_REP",
    legacy = "PROGRESS_VIEW_LEGACY",
    pvp = "PROGRESS_VIEW_PVP",
    explore = "PROGRESS_VIEW_EXPLORE",
}

-- 보기 버튼 툴팁 키, dik, 2026-10-01
local VIEW_TIPS = {
    rep = "TIP_PROGRESS_VIEW_REP",
    legacy = "TIP_PROGRESS_VIEW_LEGACY",
    pvp = "TIP_PROGRESS_VIEW_PVP",
    explore = "TIP_PROGRESS_VIEW_EXPLORE",
}

local VIEW_SETTINGS = {
    pvp = "pvpSection",
    explore = "exploreSection",
}

local REP_SUMMARY_COLUMNS = {
    { key = "name", title = L.REP_COL_FACTION, flex = true, align = "LEFT", defaultAsc = true },
    { key = "best", title = L.PROGRESS_COL_BEST, width = 100, align = "LEFT", defaultAsc = true },
    { key = "standing", title = L.REP_COL_STANDING, width = 90, align = "LEFT", defaultAsc = false },
    { key = "progress", title = L.REP_COL_PROGRESS, width = 110, align = "RIGHT", defaultAsc = false },
    { key = "ratio", title = L.REP_COL_RATIO, width = 60, align = "RIGHT", defaultAsc = false },
    { key = "gain", title = L.REP_COL_GAIN, width = 70, align = "RIGHT", defaultAsc = false },
}

local REP_CHAR_COLUMNS = {
    { key = "name", title = L.REP_COL_FACTION, flex = true, align = "LEFT", defaultAsc = true },
    { key = "standing", title = L.REP_COL_STANDING, width = 90, align = "LEFT", defaultAsc = false },
    { key = "progress", title = L.REP_COL_PROGRESS, width = 110, align = "RIGHT", defaultAsc = false },
    { key = "ratio", title = L.REP_COL_RATIO, width = 60, align = "RIGHT", defaultAsc = false },
    { key = "gain", title = L.REP_COL_GAIN, width = 70, align = "RIGHT", defaultAsc = false },
}

local LEGACY_COLUMNS = {
    { key = "kind", title = L.LEGACY_COL_KIND, width = 70, align = "LEFT", defaultAsc = true },
    { key = "name", title = L.LEGACY_COL_NAME, flex = true, align = "LEFT", defaultAsc = true },
    { key = "best", title = L.PROGRESS_COL_BEST, width = 100, align = "LEFT", defaultAsc = true },
    { key = "value", title = L.LEGACY_COL_VALUE, width = 70, align = "RIGHT", defaultAsc = false },
    { key = "reached", title = L.LEGACY_COL_REACHED, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "next", title = L.LEGACY_COL_NEXT, width = 120, align = "LEFT", defaultAsc = true },
}

local PVP_COLUMNS = {
    { key = "character", title = L.PROGRESS_COL_CHARACTER, flex = true, align = "LEFT", defaultAsc = true },
    { key = "kills", title = L.PVP_COL_KILLS, width = 90, align = "RIGHT", defaultAsc = false },
    { key = "honorLevel", title = L.PVP_COL_HONOR_LEVEL, width = 80, align = "RIGHT", defaultAsc = false },
    { key = "scanned", title = L.PVP_COL_SCANNED, width = 90, align = "RIGHT", defaultAsc = false },
}

local BG_COLUMNS = {
    { key = "name", title = L.REP_COL_FACTION, flex = true, align = "LEFT", defaultAsc = true },
    { key = "best", title = L.PROGRESS_COL_BEST, width = 100, align = "LEFT", defaultAsc = true },
    { key = "standing", title = L.REP_COL_STANDING, width = 90, align = "LEFT", defaultAsc = false },
    { key = "progress", title = L.REP_COL_PROGRESS, width = 110, align = "RIGHT", defaultAsc = false },
    { key = "ratio", title = L.REP_COL_RATIO, width = 60, align = "RIGHT", defaultAsc = false },
}

local EXPLORE_SUMMARY_COLUMNS = {
    { key = "name", title = L.EXPLORE_COL_ZONE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "best", title = L.PROGRESS_COL_BEST, width = 100, align = "LEFT", defaultAsc = true },
    { key = "done", title = L.EXPLORE_COL_DONE, width = 80, align = "RIGHT", defaultAsc = false },
    { key = "left", title = L.EXPLORE_COL_LEFT, width = 70, align = "RIGHT", defaultAsc = false },
    { key = "ratio", title = L.REP_COL_RATIO, width = 60, align = "RIGHT", defaultAsc = false },
}

local EXPLORE_CHAR_COLUMNS = {
    { key = "name", title = L.EXPLORE_COL_ZONE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "done", title = L.EXPLORE_COL_DONE, width = 80, align = "RIGHT", defaultAsc = false },
    { key = "left", title = L.EXPLORE_COL_LEFT, width = 70, align = "RIGHT", defaultAsc = false },
    { key = "ratio", title = L.REP_COL_RATIO, width = 60, align = "RIGHT", defaultAsc = false },
}

local page
local viewButtons = {}
local dropdown
local noticeLabel
local areas = {}
local curView = "rep"
local curChar = "all"
local dirty = false
local itemsSig
local repRowsById = {}

local repBar
local repSessionLabel
local repSummaryTbl
local repCharTbl
local repNoteLabel

local legacySummaryLabel
local legacyProfLabel
local legacyTbl
local legacyNoteLabel

local pvpTbl
local pvpBgHeader
local pvpBgTbl
local pvpNoteLabel

local exploreSummaryLabel
local exploreSummaryTbl
local exploreCharTbl
local exploreNoteLabel

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

-- 직업색 셀 생성, dik, 2026-10-01
local function ClassColorCell(text, classFile)
    local shown = text or L.VALUE_UNKNOWN
    local cell = { text = shown, sortValue = shown }
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        cell.color = { r = c.r, g = c.g, b = c.b }
    else
        cell.colorToken = "TEXT"
    end
    return cell
end

-- 부호 문구와 색 토큰, dik, 2026-10-01
local function FormatSigned(d)
    if type(d) ~= "number" then
        return L.VALUE_UNKNOWN, "TEXT_DIM"
    end
    if d > 0 then
        return format(L.REP_GAIN_PLUS, ns.FormatNumber(d)), "TEXT"
    end
    if d < 0 then
        return ns.FormatNumber(d), "DANGER"
    end
    return L.VALUE_UNKNOWN, "TEXT_DIM"
end

-- 이번 접속 셀 생성, dik, 2026-10-01
local function GainCell(d)
    local text, token = FormatSigned(d)
    return { text = text, sortValue = type(d) == "number" and d or nil, colorToken = token }
end

-- 보기 사용 가능 여부, dik, 2026-10-01
local function IsViewAvailable(view)
    local key = VIEW_SETTINGS[view]
    if not key then
        return true
    end
    return ns.GetSetting("progress", key) ~= false
end

-- 현재 보기 보정, dik, 2026-10-01
local function EnsureView()
    if not IsViewAvailable(curView) then
        curView = "rep"
    end
end

-- 현재 평판 표 조회, dik, 2026-10-01
local function GetRepTable()
    if curChar == "all" then
        return repSummaryTbl
    end
    return repCharTbl
end

-- 캐릭터 드롭다운 항목 갱신, dik, 2026-10-01
local function FillDropdown()
    local items = ns.Progress.GetCharacterItems()
    if type(items) ~= "table" then
        items = { { value = "all", text = L.PROGRESS_ALL_CHARS } }
    end
    local known = {}
    local parts = {}
    for i = 1, #items do
        known[items[i].value] = true
        parts[i] = tostring(items[i].value) .. "=" .. tostring(items[i].text)
    end
    if not known[curChar] then
        curChar = "all"
    end
    local sig = table.concat(parts, "|")
    if sig ~= itemsSig then
        itemsSig = sig
        dropdown:SetItems(items, curChar)
    else
        dropdown:SetValue(curChar)
    end
end

-- 알림 줄 문구 채움, dik, 2026-10-01
local function FillNotice()
    local status = ns.Progress.GetStatus()
    local text, token = "", "TEXT_DIM"
    if type(status) == "table" then
        local section = curView ~= "legacy" and curView or nil
        local state = section and type(status.sections) == "table" and status.sections[section] or nil
        if not status.ready then
            text = L.PROGRESS_NOT_READY
        elseif status.readOnly then
            text = L.PROGRESS_READ_ONLY
        elseif state == "missing" then
            local list = type(status.missing) == "table" and status.missing[section] or nil
            text = format(L.PROGRESS_SECTION_MISSING, ns.FormatMissingAPIs(list))
            token = "DANGER"
        elseif state == "secret" then
            text = L.PROGRESS_SECTION_SECRET
            token = "DANGER"
        elseif state == "notFound" and curView == "explore" then
            text = L.PROGRESS_EXPLORE_NOT_FOUND
        end
    end
    noticeLabel:SetText(text)
    SetLabelColor(noticeLabel, token)
end

-- 평판 행 변환, dik, 2026-10-01
local function BuildRepRows(list)
    local rows = {}
    repRowsById = {}
    for i = 1, #list do
        local row = list[i]
        local value = row.value
        local reaction = type(row.reaction) == "number" and row.reaction or 0
        rows[i] = {
            id = row.id,
            data = row,
            cells = {
                name = { text = row.name, sortValue = row.name, colorToken = "TEXT" },
                best = ClassColorCell(row.bestName, row.bestClassFile),
                standing = { text = ns.Progress.StandingLabel(row.reaction),
                    sortValue = reaction * 100000 + (type(value) == "number" and value or 0), colorToken = "TEXT" },
                progress = { text = format(L.REP_PROGRESS_VALUE, ns.FormatNumber(value), ns.FormatNumber(row.span)),
                    sortValue = value, colorToken = "TEXT" },
                ratio = { text = ns.FormatPercent(row.ratio), sortValue = row.ratio, colorToken = "TEXT" },
                gain = GainCell(row.gain),
            },
        }
        repRowsById[row.id] = row
    end
    return rows
end

-- 진행 바 갱신, dik, 2026-10-01
local function FillBar()
    local tbl = GetRepTable()
    local id = tbl:GetSelectedId()
    local row = id ~= nil and repRowsById[id] or nil
    if row and type(row.span) == "number" and type(row.value) == "number" then
        repBar:SetRange(0, row.span)
        repBar:SetValue(row.value)
        repBar:SetText(format(L.REP_BAR_TEXT, row.name, ns.Progress.StandingLabel(row.reaction),
            ns.FormatNumber(row.value), ns.FormatNumber(row.span), ns.FormatPercent(row.ratio)))
    else
        repBar:SetRange(0, 1)
        repBar:SetValue(0)
        repBar:SetText(L.REP_BAR_NONE)
    end
end

-- 평판 행 클릭 처리, dik, 2026-10-01
local function OnRepRowClick(row)
    GetRepTable():SetSelectedId(row.id)
    FillBar()
end

-- 평판 보기 채움, dik, 2026-10-01
local function FillRep()
    local rows = BuildRepRows(ns.Progress.GetRepRows(curChar) or {})
    GetRepTable():SetRows(rows)
    FillBar()

    local s = ns.Progress.GetSessionSummary()
    if type(s) == "table" and (s.count or 0) > 0 then
        local totalText = FormatSigned(s.total)
        repSessionLabel:SetText(format(L.REP_SESSION_SUMMARY, s.count, totalText))
    else
        repSessionLabel:SetText(L.REP_SESSION_NONE)
    end
    repNoteLabel:SetText(L.REP_NOTE)
end

-- Legacy 행 변환, dik, 2026-10-01
local function BuildLegacyRows(list)
    local rows = {}
    for i = 1, #list do
        local row = list[i]
        local isClass = row.kind == "class"
        local value = row.value
        local nameCell
        if isClass then
            nameCell = ClassColorCell(row.name, row.classFile)
        else
            nameCell = { text = row.name, sortValue = row.name, colorToken = "TEXT" }
        end
        local total = row.total or 3
        local nextCell
        if row.nextTarget == nil then
            nextCell = { text = L.LEGACY_DONE, colorToken = "TEXT" }
        else
            local fmt = isClass and L.LEGACY_NEXT_LEVEL or L.LEGACY_NEXT_SKILL
            nextCell = { text = format(fmt, row.nextTarget, row.nextTarget - value),
                sortValue = row.nextTarget - value, colorToken = "TEXT" }
        end
        rows[i] = {
            id = row.id,
            data = row,
            cells = {
                kind = { text = isClass and L.LEGACY_KIND_CLASS or L.LEGACY_KIND_PROF,
                    sortValue = isClass and 1 or 2, colorToken = "TEXT" },
                name = nameCell,
                best = ClassColorCell(row.bestName, row.bestClassFile or row.classFile),
                value = { text = isClass and format(L.LEGACY_VALUE_LEVEL, value) or ns.FormatNumber(value),
                    sortValue = value, colorToken = "TEXT" },
                reached = { text = format(L.LEGACY_REACHED, row.reached, total), sortValue = row.reached,
                    colorToken = row.reached >= total and "TEXT_DIM" or "TEXT" },
                next = nextCell,
            },
        }
    end
    return rows
end

-- Legacy 보기 채움, dik, 2026-10-01
local function FillLegacy()
    legacyTbl:SetRows(BuildLegacyRows(ns.Progress.GetLegacyRows() or {}))
    local s = ns.Progress.GetLegacySummary()
    if type(s) ~= "table" then
        s = { reached = 0, total = 0 }
    end
    legacySummaryLabel:SetText(format(L.LEGACY_SUMMARY, s.reached or 0, s.total or 0))
    legacyProfLabel:SetText(s.profUnknown and L.LEGACY_PROF_UNKNOWN or "")
    legacyNoteLabel:SetText(L.LEGACY_NOTE)
end

-- PvP 캐릭터 행 변환, dik, 2026-10-01
local function BuildPvpRows(list)
    local rows = {}
    for i = 1, #list do
        local row = list[i]
        rows[i] = {
            id = row.id,
            data = row,
            cells = {
                character = ClassColorCell(row.displayName, row.classFile),
                kills = { text = ns.FormatNumber(row.kills), sortValue = row.kills, colorToken = "TEXT" },
                honorLevel = { text = ns.FormatNumber(row.honorLevel), sortValue = row.honorLevel,
                    colorToken = "TEXT" },
                scanned = { text = ns.FormatElapsed(row.scannedAt), sortValue = row.scannedAt,
                    colorToken = "TEXT_DIM" },
            },
        }
    end
    return rows
end

-- PvP 보기 채움, dik, 2026-10-01
local function FillPvp()
    pvpTbl:SetRows(BuildPvpRows(ns.Progress.GetPvpRows() or {}))
    pvpBgTbl:SetRows(BuildRepRows(ns.Progress.GetBgRows() or {}))
    repRowsById = {}
    pvpNoteLabel:SetText(L.PVP_NOTE)
end

-- 탐험 행 변환, dik, 2026-10-01
local function BuildExploreRows(list)
    local rows = {}
    for i = 1, #list do
        local row = list[i]
        rows[i] = {
            id = row.id,
            data = row,
            cells = {
                name = { text = row.name, sortValue = row.name, colorToken = "TEXT" },
                best = ClassColorCell(row.bestName, row.bestClassFile),
                done = { text = format(L.EXPLORE_VALUE, row.done, row.total), sortValue = row.done,
                    colorToken = "TEXT" },
                left = { text = ns.FormatNumber(row.left), sortValue = row.left,
                    colorToken = row.left == 0 and "TEXT_DIM" or "TEXT" },
                ratio = { text = ns.FormatPercent(row.ratio), sortValue = row.ratio, colorToken = "TEXT" },
            },
        }
    end
    return rows
end

-- 탐험 보기 채움, dik, 2026-10-01
local function FillExplore()
    local tbl = curChar == "all" and exploreSummaryTbl or exploreCharTbl
    tbl:SetRows(BuildExploreRows(ns.Progress.GetExploreRows(curChar) or {}))
    local s = ns.Progress.GetExploreSummary(curChar)
    if type(s) ~= "table" then
        s = { left = 0, doneZones = 0, totalZones = 0 }
    end
    exploreSummaryLabel:SetText(format(L.EXPLORE_SUMMARY, s.left or 0, s.doneZones or 0, s.totalZones or 0))
    exploreNoteLabel:SetText(L.EXPLORE_NOTE)
end

-- 줄 배치 후 다음 y 반환, dik, 2026-10-01
local function PlaceLine(area, region, y, gap)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
    region:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -y)
    region:Show()
    return y + math.ceil(GetLineHeight(region)) + gap
end

-- 선택 줄 배치(빈 줄은 숨김), dik, 2026-10-01
local function PlaceOptionalLine(area, label, y, gap)
    if (label:GetText() or "") == "" then
        label:Hide()
        return y
    end
    return PlaceLine(area, label, y, gap)
end

-- 아래 안내 줄 배치 후 표 하단 여백 반환, dik, 2026-10-01
local function PlaceNote(area, label, gap)
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
    label:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    return math.ceil(GetLineHeight(label)) + gap
end

-- 표를 남은 높이에 배치, dik, 2026-10-01
local function PlaceTable(area, tbl, y, bottom)
    tbl:ClearAllPoints()
    tbl:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
    tbl:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -y)
    tbl:SetPoint("BOTTOM", area, "BOTTOM", 0, bottom)
end

-- 평판 영역 배치, dik, 2026-10-01
local function LayoutRep(area, gap)
    repBar:ClearAllPoints()
    repBar:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    repBar:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    local y = repBar:GetHeight() + gap
    y = PlaceLine(area, repSessionLabel, y, gap)
    local bottom = PlaceNote(area, repNoteLabel, gap)
    PlaceTable(area, repSummaryTbl, y, bottom)
    PlaceTable(area, repCharTbl, y, bottom)
    if curChar == "all" then
        repCharTbl:Hide()
        repSummaryTbl:Show()
    else
        repSummaryTbl:Hide()
        repCharTbl:Show()
    end
end

-- Legacy 영역 배치, dik, 2026-10-01
local function LayoutLegacy(area, gap)
    local y = PlaceLine(area, legacySummaryLabel, 0, gap)
    y = PlaceOptionalLine(area, legacyProfLabel, y, gap)
    local bottom = PlaceNote(area, legacyNoteLabel, gap)
    PlaceTable(area, legacyTbl, y, bottom)
end

-- PvP 영역 배치, dik, 2026-10-01
local function LayoutPvp(area, gap)
    pvpTbl:ClearAllPoints()
    pvpTbl:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    pvpTbl:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    pvpTbl:SetHeight((1 + PVP_VISIBLE_ROWS) * GetRowHeight())
    local y = pvpTbl:GetHeight() + gap
    pvpBgHeader:ClearAllPoints()
    pvpBgHeader:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
    pvpBgHeader:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -y)
    y = y + pvpBgHeader:GetHeight()
    local bottom = PlaceNote(area, pvpNoteLabel, gap)
    PlaceTable(area, pvpBgTbl, y, bottom)
end

-- 탐험 영역 배치, dik, 2026-10-01
local function LayoutExplore(area, gap)
    local y = PlaceLine(area, exploreSummaryLabel, 0, gap)
    local bottom = PlaceNote(area, exploreNoteLabel, gap)
    PlaceTable(area, exploreSummaryTbl, y, bottom)
    PlaceTable(area, exploreCharTbl, y, bottom)
    if curChar == "all" then
        exploreCharTbl:Hide()
        exploreSummaryTbl:Show()
    else
        exploreSummaryTbl:Hide()
        exploreCharTbl:Show()
    end
end

local AREA_LAYOUTS = {
    rep = LayoutRep,
    legacy = LayoutLegacy,
    pvp = LayoutPvp,
    explore = LayoutExplore,
}

-- 전체 재배치, dik, 2026-10-01
local function LayoutAll()
    local theme = ns.Theme
    local gap = theme.GAP
    local x = 0
    local topH = theme.MENU_ITEM_H

    for i = 1, #VIEWS do
        local view = VIEWS[i]
        local btn = viewButtons[view]
        if IsViewAvailable(view) then
            local label = btn.label
            local w = math.floor(label:GetStringWidth() + theme.PAD * 2 + 0.5)
            local h = math.max(theme.MENU_ITEM_H, math.floor(GetLineHeight(label) + gap + 0.5))
            btn:SetSize(w, h)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
            btn:Show()
            SetLabelColor(label, view == curView and "ACCENT" or "TEXT")
            x = x + w + gap
            topH = math.max(topH, h)
        else
            btn:Hide()
        end
    end

    if curView == "rep" or curView == "explore" then
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
        dropdown:Show()
        topH = math.max(topH, dropdown:GetHeight())
    else
        dropdown:Close()
        dropdown:Hide()
    end

    local y = topH + gap
    noticeLabel:ClearAllPoints()
    if (noticeLabel:GetText() or "") ~= "" then
        y = PlaceLine(page, noticeLabel, y, gap)
    else
        noticeLabel:Hide()
    end

    for i = 1, #VIEWS do
        local view = VIEWS[i]
        local area = areas[view]
        if view == curView then
            area:ClearAllPoints()
            area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
            area:Show()
            AREA_LAYOUTS[view](area, gap)
        else
            area:Hide()
        end
    end
end

-- 현재 보기 전체 채움, dik, 2026-10-01
local function FillAll()
    if not page or not ns.Progress then
        return
    end
    dirty = false
    EnsureView()
    FillDropdown()
    FillNotice()
    if curView == "rep" then
        FillRep()
    elseif curView == "legacy" then
        FillLegacy()
    elseif curView == "pvp" then
        FillPvp()
    else
        FillExplore()
    end
    LayoutAll()
end

-- 보기 전환, dik, 2026-10-01
local function SetView(view)
    curView = view
    FillAll()
end

-- 캐릭터 드롭다운 변경 처리, dik, 2026-10-01
local function OnCharChanged(value)
    curChar = value
    FillAll()
end

-- 표 생성 후 초기 정렬 설정, dik, 2026-10-01
local function MakeTable(parent, columns, opts, sortKey, sortAsc)
    local tbl = ns.Widgets.CreateTable(parent, columns, opts)
    tbl:SetSort(sortKey, sortAsc)
    return tbl
end

-- 줄 라벨 생성, dik, 2026-10-01
local function MakeLine(parent, fontToken, colorToken, wrap)
    local label = ns.Widgets.CreateLabel(parent, fontToken, colorToken)
    label:SetWordWrap(wrap)
    return label
end

-- 평판·진척 페이지 생성, dik, 2026-10-01
function module.CreatePage(_, parent)
    if page then
        return page
    end
    local widgets = ns.Widgets
    page = CreateFrame("Frame", nil, parent)

    for i = 1, #VIEWS do
        local view = VIEWS[i]
        viewButtons[view] = widgets.CreateButton(page, L[VIEW_TITLES[view]], function()
            SetView(view)
        end)
        -- 보기 버튼 툴팁 연결, dik, 2026-10-01
        widgets.SetTooltip(viewButtons[view], L[VIEW_TITLES[view]], L[VIEW_TIPS[view]])
    end

    dropdown = widgets.CreateDropdown(page, {
        width = DROPDOWN_W,
        items = { { value = "all", text = L.PROGRESS_ALL_CHARS } },
        value = "all",
        onChange = OnCharChanged,
    })
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(dropdown, nil, L.TIP_PROGRESS_CHAR)
    noticeLabel = MakeLine(page, "FONT_BODY", "TEXT_DIM", false)

    for i = 1, #VIEWS do
        local area = CreateFrame("Frame", nil, page)
        area:Hide()
        areas[VIEWS[i]] = area
    end

    local rowH = GetRowHeight()

    local repArea = areas.rep
    repBar = widgets.CreateBar(repArea)
    repSessionLabel = MakeLine(repArea, "FONT_BODY", "TEXT", false)
    repSummaryTbl = MakeTable(repArea, REP_SUMMARY_COLUMNS,
        { rowHeight = rowH, emptyText = L.REP_EMPTY, onRowClick = OnRepRowClick }, "name", true)
    repCharTbl = MakeTable(repArea, REP_CHAR_COLUMNS,
        { rowHeight = rowH, emptyText = L.REP_EMPTY, onRowClick = OnRepRowClick }, "name", true)
    repNoteLabel = MakeLine(repArea, "FONT_SMALL", "TEXT_DIM", true)

    local legacyArea = areas.legacy
    legacySummaryLabel = MakeLine(legacyArea, "FONT_BODY", "TEXT", false)
    legacyProfLabel = MakeLine(legacyArea, "FONT_BODY", "TEXT_DIM", false)
    legacyTbl = MakeTable(legacyArea, LEGACY_COLUMNS,
        { rowHeight = rowH, emptyText = L.LEGACY_EMPTY }, "kind", true)
    legacyNoteLabel = MakeLine(legacyArea, "FONT_SMALL", "TEXT_DIM", true)

    local pvpArea = areas.pvp
    pvpTbl = MakeTable(pvpArea, PVP_COLUMNS, { rowHeight = rowH, emptyText = L.PVP_EMPTY }, "kills", false)
    pvpBgHeader = widgets.CreateSectionHeader(pvpArea, L.PVP_BG_SECTION)
    pvpBgTbl = MakeTable(pvpArea, BG_COLUMNS, { rowHeight = rowH, emptyText = L.PVP_BG_EMPTY }, nil, true)
    pvpNoteLabel = MakeLine(pvpArea, "FONT_SMALL", "TEXT_DIM", true)

    local exploreArea = areas.explore
    exploreSummaryLabel = MakeLine(exploreArea, "FONT_BODY", "TEXT", false)
    exploreSummaryTbl = MakeTable(exploreArea, EXPLORE_SUMMARY_COLUMNS,
        { rowHeight = rowH, emptyText = L.EXPLORE_EMPTY }, "left", false)
    exploreCharTbl = MakeTable(exploreArea, EXPLORE_CHAR_COLUMNS,
        { rowHeight = rowH, emptyText = L.EXPLORE_EMPTY }, "left", false)
    exploreNoteLabel = MakeLine(exploreArea, "FONT_SMALL", "TEXT_DIM", true)

    page:SetScript("OnSizeChanged", function()
        if page:IsVisible() and ns.Progress then
            LayoutAll()
        end
    end)

    FillAll()
    return page
end

-- 표·드롭다운 글꼴 다시 계산, dik, 2026-10-01
local function RefreshWidgets()
    dropdown:Refresh()
    repSummaryTbl:Refresh()
    repCharTbl:Refresh()
    legacyTbl:Refresh()
    pvpTbl:Refresh()
    pvpBgTbl:Refresh()
    exploreSummaryTbl:Refresh()
    exploreCharTbl:Refresh()
end

-- 페이지 표시 시 전체 갱신, dik, 2026-10-01
function module.OnPageShow()
    if not ns.Progress then
        return
    end
    ns.Progress.RequestScan()
    if dirty and page then
        RefreshWidgets()
    end
    FillAll()
    dirty = false
end

-- 페이지 숨김 시 정리, dik, 2026-10-01
function module.OnPageHide()
    if dropdown then
        dropdown:Close()
    end
end

-- 보일 때만 즉시 갱신, dik, 2026-10-01
local function RefreshOrMark()
    if not page then
        return
    end
    if page:IsVisible() then
        FillAll()
    else
        dirty = true
    end
end

ns.On("PROGRESS_UPDATED", RefreshOrMark)
ns.On("CHAR_UPDATED", RefreshOrMark)
ns.On("CHAR_DELETED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-10-01
ns.On("SETTING_CHANGED", function(scope, key)
    if not page then
        return
    end
    if scope == "global" and key == "fontSize" then
        if page:IsVisible() then
            RefreshWidgets()
            FillAll()
        else
            dirty = true
        end
    elseif scope == "progress" then
        RefreshOrMark()
    end
end)
