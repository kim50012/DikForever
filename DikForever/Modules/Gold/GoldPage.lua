-- 골드 장부 페이지, dik, 2026-09-30
local addonName, ns = ...

local module = ns.GetModule("gold")
if not module then
    return
end

local L = ns.L

local FALLBACK_LINE_H = 14
local TICK_SECONDS = 1.0
local LABEL_W = 110
local HEADER_H = 28
local DD_PERIOD_W = 110
local DD_CHAR_W = 150
local DD_VIEW_W = 90

local PERIOD_KEYS = {
    session = "GOLD_PERIOD_SESSION",
    today = "GOLD_PERIOD_TODAY",
    yesterday = "GOLD_PERIOD_YESTERDAY",
    d7 = "GOLD_PERIOD_7D",
    d30 = "GOLD_PERIOD_30D",
    d90 = "GOLD_PERIOD_90D",
}

local SOURCE_COLUMNS = {
    { key = "source", title = L.GOLD_COL_SOURCE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "income", title = L.GOLD_COL_INCOME, width = 120, align = "RIGHT", defaultAsc = false },
    { key = "expense", title = L.GOLD_COL_EXPENSE, width = 120, align = "RIGHT", defaultAsc = false },
    { key = "net", title = L.GOLD_COL_NET, width = 120, align = "RIGHT", defaultAsc = false },
}

local CHAR_COLUMNS = {
    { key = "name", title = L.GOLD_COL_CHARACTER, flex = true, align = "LEFT", defaultAsc = true },
    { key = "money", title = L.GOLD_COL_MONEY, width = 110, align = "RIGHT", defaultAsc = false },
    { key = "income", title = L.GOLD_COL_INCOME, width = 100, align = "RIGHT", defaultAsc = false },
    { key = "expense", title = L.GOLD_COL_EXPENSE, width = 100, align = "RIGHT", defaultAsc = false },
    { key = "net", title = L.GOLD_COL_NET, width = 100, align = "RIGHT", defaultAsc = false },
}

-- 그리드 행 정의(2열 x 3행), dik, 2026-09-30
local GRID = {
    { left = "time", right = "rate" },
    { left = "income", right = "expense" },
    { left = "net" },
}

local GRID_LABELS = {
    time = "GOLD_SESSION_TIME",
    rate = "GOLD_SESSION_RATE",
    income = "GOLD_SESSION_INCOME",
    expense = "GOLD_SESSION_EXPENSE",
    net = "GOLD_SESSION_NET",
}

local page
local ddPeriod
local ddChar
local ddView
local totalLabel
local statusLabel
local readOnlyLabel
local cells = {}
local resetBtn
local sectionTitle
local sectionLine
local sourceTbl
local charTbl
local periodTotalLabel
local noteLabel
local tickAcc = 0
local dirty = false
local charItemsSig
local session
local curPeriod
local curChar
local curView

-- 글자 높이 계산, dik, 2026-09-30
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 직업색 조회, dik, 2026-09-30
local function GetClassColor(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return { r = c.r, g = c.g, b = c.b }
    end
    return nil
end

-- 부호 금액 문구와 색 토큰, dik, 2026-09-30
local function FormatSigned(v)
    if type(v) ~= "number" then
        return L.VALUE_UNKNOWN, "TEXT_DIM"
    end
    if v > 0 then
        return L.FMT_SIGNED_PLUS:format(ns.FormatMoney(v)), "TEXT"
    end
    if v < 0 then
        return ns.FormatMoney(v), "DANGER"
    end
    return ns.FormatMoney(0), "TEXT"
end

-- 수입·지출 셀 문구와 색 토큰, dik, 2026-09-30
local function FormatFlow(v)
    if type(v) ~= "number" or v == 0 then
        return L.VALUE_UNKNOWN, "TEXT_DIM"
    end
    return ns.FormatMoney(v), "TEXT"
end

-- 캐릭터 표시 이름 맵, dik, 2026-09-30
local function BuildDisplayNames(list)
    local counts = {}
    for i = 1, #list do
        local name = list[i].name
        if type(name) == "string" and name ~= "" then
            counts[name] = (counts[name] or 0) + 1
        end
    end
    local map = {}
    for i = 1, #list do
        local rec = list[i]
        local name = rec.name
        if type(name) == "string" and name ~= "" and counts[name] == 1 then
            map[rec.key] = name
        else
            map[rec.key] = rec.key
        end
    end
    return map
end

-- 기간 드롭다운 항목 생성, dik, 2026-09-30
local function BuildPeriodItems()
    local items = {}
    for i = 1, #ns.Gold.PERIODS do
        local p = ns.Gold.PERIODS[i]
        items[i] = { value = p, text = L[PERIOD_KEYS[p]] }
    end
    return items
end

-- 보기 드롭다운 항목 생성, dik, 2026-09-30
local function BuildViewItems()
    return {
        { value = "source", text = L.GOLD_VIEW_SOURCE },
        { value = "character", text = L.GOLD_VIEW_CHARACTER },
    }
end

-- 라벨 색 토큰 적용, dik, 2026-09-30
local function SetLabelColor(label, token)
    label:SetTextColor(ns.Theme.GetColor(token))
end

-- 현재 보기 상태 읽기(세션 동안 페이지가 유지), dik, 2026-09-30
local function ReadView()
    if curPeriod == nil then
        curPeriod, curChar, curView = ns.Gold.GetViewState()
    end
    return curPeriod, curChar, curView
end

-- 보기 상태 변경·저장 시도, dik, 2026-09-30
local function WriteView(period, charFilter, view)
    curPeriod, curChar, curView = period, charFilter, view
    ns.Gold.SetViewState(period, charFilter, view)
end

-- 드롭다운 3개 갱신, dik, 2026-09-30
local function FillDropdowns()
    local period, charFilter, view = ReadView()
    local all = ns.Gold.AggregateByCharacter("today", "all")
    local names = BuildDisplayNames(all)

    local items = { { value = "all", text = L.GOLD_CHAR_ALL } }
    local known = { all = true }
    local parts = { "all" }
    for i = 1, #all do
        local key = all[i].key
        items[#items + 1] = { value = key, text = names[key] }
        known[key] = true
        parts[#parts + 1] = key .. "=" .. names[key]
    end
    if not known[charFilter] then
        charFilter = "all"
        WriteView(period, charFilter, view)
    end

    local shown = charFilter
    if period == "session" then
        local key = session and session.characterKey
        shown = (key and known[key]) and key or "all"
    end

    local sig = table.concat(parts, "|")
    if sig ~= charItemsSig then
        charItemsSig = sig
        ddChar:SetItems(items, shown)
    else
        ddChar:SetValue(shown)
    end
    ddChar:SetEnabled(period ~= "session")
    ddPeriod:SetValue(period)
    ddView:SetValue(view)
    return period, charFilter, view, names, known
end

-- 출처별 표 채움, dik, 2026-09-30
local function FillSourceTable(result)
    local rows = {}
    for i = 1, #ns.Gold.CATEGORIES do
        local cat = ns.Gold.CATEGORIES[i]
        local inc = result.inc[cat] or 0
        local exp = result.exp[cat] or 0
        local incText, incColor = FormatFlow(inc)
        local expText, expColor = FormatFlow(exp)
        local netText, netColor = FormatSigned(inc - exp)
        rows[i] = {
            id = cat,
            cells = {
                source = { text = L["GOLD_SRC_" .. cat:upper()], sortValue = i, colorToken = "TEXT" },
                income = { text = incText, sortValue = inc, colorToken = incColor },
                expense = { text = expText, sortValue = exp, colorToken = expColor },
                net = { text = netText, sortValue = inc - exp, colorToken = netColor },
            },
        }
    end
    sourceTbl:SetRows(rows)
end

-- 캐릭터별 표 채움, dik, 2026-09-30
local function FillCharTable(period, charFilter, names)
    local list = ns.Gold.AggregateByCharacter(period, charFilter)
    local rows = {}
    for i = 1, #list do
        local rec = list[i]
        local display = names[rec.key] or rec.key
        local nameCell = { text = display, sortValue = display }
        local color = GetClassColor(rec.classFile)
        if color then
            nameCell.color = color
        else
            nameCell.colorToken = "TEXT"
        end
        local incText, incColor = FormatFlow(rec.incTotal)
        local expText, expColor = FormatFlow(rec.expTotal)
        local netText, netColor = FormatSigned(rec.net)
        rows[i] = {
            id = rec.key,
            data = rec,
            cells = {
                name = nameCell,
                money = { text = rec.money and ns.FormatMoney(rec.money) or L.VALUE_UNKNOWN, sortValue = rec.money,
                    colorToken = rec.money and "TEXT" or "TEXT_DIM" },
                income = { text = incText, sortValue = rec.incTotal, colorToken = incColor },
                expense = { text = expText, sortValue = rec.expTotal, colorToken = expColor },
                net = { text = netText, sortValue = rec.net, colorToken = netColor },
            },
        }
    end
    charTbl:SetRows(rows)
end

-- 세션 그리드 값 갱신, dik, 2026-09-30
local function FillGrid()
    session = ns.Gold.GetSession()
    local unknown = L.VALUE_UNKNOWN
    local values = {}
    local colors = {}
    for i = 1, #GRID do
        for _, key in pairs(GRID[i]) do
            values[key] = unknown
            colors[key] = "TEXT_DIM"
        end
    end
    if session.ready and not session.secret then
        values.time, colors.time = ns.FormatDuration(session.elapsed), "TEXT"
        values.rate, colors.rate = FormatSigned(session.rate)
        values.income, colors.income = ns.FormatMoney(session.incTotal), "TEXT"
        values.expense, colors.expense = ns.FormatMoney(session.expTotal), "TEXT"
        values.net, colors.net = FormatSigned(session.net)
    end
    for key, cell in pairs(cells) do
        cell.value:SetText(values[key])
        SetLabelColor(cell.value, colors[key])
    end
end

-- 상태 안내 줄·버튼 갱신, dik, 2026-09-30
local function FillStatus()
    local theme = ns.Theme
    if not session.ready then
        statusLabel:SetText(L.GOLD_NOT_READY)
        SetLabelColor(statusLabel, "TEXT")
    elseif session.secret then
        statusLabel:SetText(L.GOLD_SECRET)
        SetLabelColor(statusLabel, "DANGER")
    else
        statusLabel:SetText("")
    end
    if session.ready and session.readOnly then
        readOnlyLabel:SetText(L.GOLD_READ_ONLY)
    else
        readOnlyLabel:SetText("")
    end
    if session.ready then
        resetBtn:Enable()
        resetBtn.label:SetTextColor(theme.GetColor("TEXT"))
    else
        resetBtn:Disable()
        resetBtn.label:SetTextColor(theme.GetColor("TEXT_DIM"))
    end
end

-- 전체 재배치, dik, 2026-09-30
local function Layout(view)
    local theme = ns.Theme
    local gap = theme.GAP
    local y = 0

    local ddH = ddPeriod:GetHeight()
    ddPeriod:ClearAllPoints()
    ddPeriod:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    ddChar:ClearAllPoints()
    ddChar:SetPoint("TOPLEFT", ddPeriod, "TOPRIGHT", gap, 0)
    ddView:ClearAllPoints()
    ddView:SetPoint("TOPLEFT", ddChar, "TOPRIGHT", gap, 0)
    y = y + ddH + gap

    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    totalLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    y = y + math.ceil(GetLineHeight(totalLabel)) + gap

    statusLabel:ClearAllPoints()
    if statusLabel:GetText() ~= "" then
        statusLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        statusLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        statusLabel:Show()
        y = y + math.ceil(GetLineHeight(statusLabel)) + gap
    else
        statusLabel:Hide()
    end

    for i = 1, #GRID do
        local rowH = 0
        local pair = GRID[i]
        for side = 1, 2 do
            local key = side == 1 and pair.left or pair.right
            local cell = key and cells[key]
            if cell then
                cell.label:ClearAllPoints()
                cell.value:ClearAllPoints()
                if side == 1 then
                    cell.label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
                    cell.value:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_W, -y)
                    cell.value:SetPoint("TOPRIGHT", page, "TOP", -gap, -y)
                else
                    cell.label:SetPoint("TOPLEFT", page, "TOP", gap, -y)
                    cell.value:SetPoint("TOPLEFT", page, "TOP", gap + LABEL_W, -y)
                    cell.value:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
                end
                cell.label:SetWidth(LABEL_W - gap)
                rowH = math.max(rowH, GetLineHeight(cell.label), GetLineHeight(cell.value))
            end
        end
        if i == #GRID then
            local btnLabel = resetBtn.label
            resetBtn:SetWidth(math.floor(btnLabel:GetStringWidth() + theme.PAD * 2 + 0.5))
            resetBtn:SetHeight(math.max(theme.MENU_ITEM_H, math.floor(GetLineHeight(btnLabel) + gap + 0.5)))
            rowH = math.max(rowH, resetBtn:GetHeight())
            resetBtn:ClearAllPoints()
            resetBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y + (rowH - resetBtn:GetHeight()) / 2))
        end
        y = y + math.ceil(rowH) + gap
    end

    readOnlyLabel:ClearAllPoints()
    if readOnlyLabel:GetText() ~= "" then
        readOnlyLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        readOnlyLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        readOnlyLabel:Show()
        y = y + math.ceil(GetLineHeight(readOnlyLabel)) + gap
    else
        readOnlyLabel:Hide()
    end

    sectionTitle:ClearAllPoints()
    sectionTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + HEADER_H - math.ceil(GetLineHeight(sectionTitle)) - 5))
    sectionLine:ClearAllPoints()
    sectionLine:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + HEADER_H))
    sectionLine:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y + HEADER_H))
    y = y + HEADER_H

    noteLabel:ClearAllPoints()
    noteLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    noteLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    local bottom = math.ceil(GetLineHeight(noteLabel)) + gap
    periodTotalLabel:ClearAllPoints()
    periodTotalLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, bottom)
    periodTotalLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    bottom = bottom + math.ceil(GetLineHeight(periodTotalLabel)) + gap

    for _, t in pairs({ sourceTbl, charTbl }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + 1))
        t:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y + 1))
        t:SetPoint("BOTTOM", page, "BOTTOM", 0, bottom)
    end
    if view == "character" then
        sourceTbl:Hide()
        charTbl:Show()
    else
        charTbl:Hide()
        sourceTbl:Show()
    end
end

-- 전체 갱신, dik, 2026-09-30
local function FillAll()
    if not page then
        return
    end
    dirty = false
    FillGrid()
    FillStatus()
    local period, charFilter, view, names, known = FillDropdowns()

    local money, count, moneyCount = ns.Gold.GetTotalMoney()
    local moneyText = (moneyCount and moneyCount > 0 and money) and ns.FormatMoney(money) or L.VALUE_UNKNOWN
    totalLabel:SetText(L.GOLD_TOTAL_MONEY:format(moneyText, count or 0))

    local result = ns.Gold.Aggregate(period, charFilter)
    local charText
    if period == "session" then
        local key = session.characterKey
        charText = key and names[key] or L.GOLD_CHAR_ALL
    elseif charFilter == "all" or not known[charFilter] then
        charText = L.GOLD_CHAR_ALL
    else
        charText = names[charFilter] or charFilter
    end
    sectionTitle:SetText(L.GOLD_SECTION:format(L[PERIOD_KEYS[period]], charText))

    FillSourceTable(result)
    FillCharTable(period, charFilter, names)

    local netText = FormatSigned(result.net)
    periodTotalLabel:SetText(L.GOLD_PERIOD_TOTAL:format(ns.FormatMoney(result.incTotal),
        ns.FormatMoney(result.expTotal), netText))
    noteLabel:SetText(L.GOLD_NOTE)

    Layout(view)
end

-- 바뀐 드롭다운 값만 저장 상태에 반영, dik, 2026-09-30
local function OnPeriodChanged(value)
    local _, charFilter, view = ReadView()
    WriteView(value, charFilter, view)
    FillAll()
end

-- 캐릭터 드롭다운 변경 처리, dik, 2026-09-30
local function OnCharChanged(value)
    local period, _, view = ReadView()
    WriteView(period, value, view)
    FillAll()
end

-- 보기 드롭다운 변경 처리, dik, 2026-09-30
local function OnViewChanged(value)
    local period, charFilter = ReadView()
    WriteView(period, charFilter, value)
    FillAll()
end

-- 세션 초기화 클릭, dik, 2026-09-30
local function OnResetClick()
    ns.Gold.ResetSession()
end

-- 골드 장부 페이지 생성, dik, 2026-09-30
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    ddPeriod = ns.Widgets.CreateDropdown(page, { width = DD_PERIOD_W, items = BuildPeriodItems(),
        onChange = OnPeriodChanged })
    ddChar = ns.Widgets.CreateDropdown(page, { width = DD_CHAR_W, items = { { value = "all", text = L.GOLD_CHAR_ALL } },
        onChange = OnCharChanged })
    ddView = ns.Widgets.CreateDropdown(page, { width = DD_VIEW_W, items = BuildViewItems(), onChange = OnViewChanged })
    -- 툴팁 연결, dik, 2026-10-01
    ns.Widgets.SetTooltip(ddPeriod, nil, L.TIP_GOLD_PERIOD)
    ns.Widgets.SetTooltip(ddChar, nil, L.TIP_GOLD_CHAR)
    ns.Widgets.SetTooltip(ddView, nil, L.TIP_GOLD_VIEW)

    totalLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    totalLabel:SetWordWrap(false)
    statusLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    statusLabel:SetWordWrap(false)
    readOnlyLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT_DIM")
    readOnlyLabel:SetWordWrap(false)

    for i = 1, #GRID do
        for _, key in pairs(GRID[i]) do
            local label = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
            label:SetWordWrap(false)
            label:SetText(L[GRID_LABELS[key]])
            local value = ns.Widgets.CreateLabel(page, "FONT_NUMBER", "TEXT")
            value:SetWordWrap(false)
            cells[key] = { label = label, value = value }
        end
    end
    resetBtn = ns.Widgets.CreateButton(page, L.GOLD_RESET, OnResetClick)
    -- 툴팁 연결, dik, 2026-10-01
    ns.Widgets.SetTooltip(resetBtn, L.GOLD_RESET, L.TIP_GOLD_RESET)

    sectionTitle = ns.Widgets.CreateLabel(page, "FONT_MENU", "ACCENT")
    sectionTitle:SetWordWrap(false)
    sectionLine = page:CreateTexture(nil, "ARTWORK")
    sectionLine:SetHeight(1)
    sectionLine:SetColorTexture(ns.Theme.GetColor("BORDER"))

    sourceTbl = ns.Widgets.CreateTable(page, SOURCE_COLUMNS, {})
    sourceTbl:SetSort("source", true)
    charTbl = ns.Widgets.CreateTable(page, CHAR_COLUMNS, { emptyText = L.GOLD_EMPTY })
    charTbl:SetSort("money", false)

    periodTotalLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    periodTotalLabel:SetWordWrap(false)
    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(false)

    page:SetScript("OnUpdate", function(_, elapsed)
        tickAcc = tickAcc + elapsed
        if tickAcc >= TICK_SECONDS then
            tickAcc = 0
            FillGrid()
        end
    end)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 갱신, dik, 2026-09-30
function module.OnPageShow()
    tickAcc = 0
    if dirty then
        ddPeriod:Refresh()
        ddChar:Refresh()
        ddView:Refresh()
        sourceTbl:Refresh()
        charTbl:Refresh()
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-09-30
function module.OnPageHide()
    tickAcc = 0
    if ddPeriod then
        ddPeriod:Close()
        ddChar:Close()
        ddView:Close()
    end
end

-- 보일 때만 즉시 갱신, dik, 2026-09-30
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

ns.On("GOLD_UPDATED", RefreshOrMark)
ns.On("CHAR_UPDATED", RefreshOrMark)
ns.On("CHAR_DELETED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if scope == "global" and key == "fontSize" and page then
        if page:IsVisible() then
            ddPeriod:Refresh()
            ddChar:Refresh()
            ddView:Refresh()
            sourceTbl:Refresh()
            charTbl:Refresh()
            FillAll()
        else
            dirty = true
        end
    end
end)
