-- 레벨링 페이지, dik, 2026-09-30
local addonName, ns = ...

local module = ns.GetModule("leveling")
if not module then
    return
end

local L = ns.L

local FALLBACK_LINE_H = 14
local TICK_SECONDS = 1.0
local LABEL_W = 170
local HEADER_H = 28

local COLUMNS = {
    { key = "startedAt", title = L.LEVELING_COL_START, width = 110, align = "LEFT", defaultAsc = false },
    { key = "duration", title = L.LEVELING_COL_DURATION, width = 76, align = "RIGHT", defaultAsc = false },
    { key = "xp", title = L.LEVELING_COL_XP, width = 70, align = "RIGHT", defaultAsc = false },
    { key = "rate", title = L.LEVELING_COL_RATE, width = 64, align = "RIGHT", defaultAsc = false },
    { key = "level", title = L.LEVELING_COL_LEVEL, width = 60, align = "RIGHT", defaultAsc = false },
    { key = "kills", title = L.LEVELING_COL_KILLS, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "quests", title = L.LEVELING_COL_QUESTS, flex = true, align = "RIGHT", defaultAsc = false },
}

-- 그리드 행 정의(2열 x 5행), dik, 2026-09-30
local GRID = {
    { left = "sessionTime", right = "sessionXp" },
    { left = "rateRecent", right = "rateSession" },
    { left = "eta", right = "killsToLevel" },
    { left = "kills", right = "quests" },
    { left = "levels" },
}

local STATIC_LABELS = {
    sessionTime = "LEVELING_SESSION_TIME",
    sessionXp = "LEVELING_SESSION_XP",
    rateSession = "LEVELING_RATE_SESSION",
    eta = "LEVELING_ETA",
    killsToLevel = "LEVELING_KILLS_TO_LEVEL",
    kills = "LEVELING_KILLS",
    quests = "LEVELING_QUESTS",
    levels = "LEVELING_LEVELS",
}

local page
local bar
local statusLabel
local noteLabel
local resetBtn
local header
local tbl
local cells = {}
local tickAcc = 0

-- 글자 높이 계산, dik, 2026-09-30
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 통계 값 문구 생성, dik, 2026-09-30
local function BuildValues(snap)
    local unknown = L.VALUE_UNKNOWN
    local values = {}
    for i = 1, #GRID do
        for _, key in pairs(GRID[i]) do
            values[key] = unknown
        end
    end
    if not snap.ready or snap.maxLevel then
        values.rateRecentLabel = L.LEVELING_RATE_RECENT:format(snap.recentMinutes or 0)
        return values
    end
    values.rateRecentLabel = L.LEVELING_RATE_RECENT:format(snap.recentMinutes or 0)
    values.sessionTime = ns.FormatDuration(snap.elapsed)
    values.sessionXp = ns.FormatNumber(snap.sessionXp)
    values.rateRecent = ns.FormatNumber(snap.recentRate)
    values.rateSession = ns.FormatNumber(snap.sessionRate)
    values.eta = ns.FormatDuration(snap.etaSeconds)
    if snap.killsSupported then
        if snap.killsToLevel then
            values.killsToLevel = L.LEVELING_KILLS_TO_LEVEL_VALUE:format(ns.FormatNumber(snap.killsToLevel),
                ns.FormatNumber(snap.avgKillXp))
        end
        values.kills = L.LEVELING_KILLS_VALUE:format(ns.FormatNumber(snap.kills), ns.FormatNumber(snap.killXp))
    end
    if snap.questsSupported then
        values.quests = L.LEVELING_QUESTS_VALUE:format(ns.FormatNumber(snap.quests), ns.FormatNumber(snap.questXp))
    end
    if type(snap.levelsGained) == "number" then
        values.levels = L.LEVELING_LEVELS_VALUE:format(snap.levelsGained)
    end
    return values
end

-- 그리드 값만 갱신, dik, 2026-09-30
local function FillGrid(snap)
    local values = BuildValues(snap)
    cells.rateRecent.label:SetText(values.rateRecentLabel)
    for i = 1, #GRID do
        for _, key in pairs(GRID[i]) do
            cells[key].value:SetText(values[key])
        end
    end
end

-- 경험치 바 갱신, dik, 2026-09-30
local function FillBar(snap)
    if not snap.ready then
        bar:SetRange(0, 1)
        bar:SetValue(0)
        bar:SetSecondaryShown(false)
        bar:SetText(nil)
    elseif snap.secret then
        local rawXp, rawMax = ns.Leveling.GetRawXp()
        bar:SetRange(0, rawMax)
        bar:SetValue(rawXp)
        bar:SetSecondaryShown(false)
        bar:SetText(nil)
    elseif snap.maxLevel then
        bar:SetRange(0, 1)
        bar:SetValue(1)
        bar:SetSecondaryShown(false)
        bar:SetText(L.LEVELING_MAX_LEVEL_BAR:format(snap.level or L.VALUE_UNKNOWN))
    elseif snap.xp and snap.xpMax then
        local text = L.LEVELING_BAR_TEXT:format(snap.level or L.VALUE_UNKNOWN, ns.FormatNumber(snap.xp),
            ns.FormatNumber(snap.xpMax), ns.FormatPercent(snap.xpRatio))
        bar:SetRange(0, snap.xpMax)
        bar:SetValue(snap.xp)
        if snap.restXp and snap.restXp > 0 then
            bar:SetSecondaryValue(math.min(snap.xp + snap.restXp, snap.xpMax))
            bar:SetSecondaryShown(true)
            text = text .. L.LEVELING_BAR_REST:format(ns.FormatNumber(snap.restXp))
        else
            bar:SetSecondaryShown(false)
        end
        bar:SetText(text)
    else
        bar:SetRange(0, 1)
        bar:SetValue(0)
        bar:SetSecondaryShown(false)
        bar:SetText(nil)
    end
end

-- 상태 안내 줄 갱신, dik, 2026-09-30
local function FillStatus(snap)
    local theme = ns.Theme
    if not snap.ready then
        statusLabel:SetText(L.LEVELING_NOT_READY)
        statusLabel:SetTextColor(theme.GetColor("TEXT"))
    elseif snap.secret then
        statusLabel:SetText(L.LEVELING_SECRET)
        statusLabel:SetTextColor(theme.GetColor("DANGER"))
    elseif snap.maxLevel then
        statusLabel:SetText(L.LEVELING_MAX_LEVEL)
        statusLabel:SetTextColor(theme.GetColor("TEXT"))
    else
        statusLabel:SetText("")
    end
end

-- 초기화 버튼 상태 갱신, dik, 2026-09-30
local function FillButton(snap)
    local theme = ns.Theme
    if snap.ready then
        resetBtn:Enable()
        resetBtn.label:SetTextColor(theme.GetColor("TEXT"))
    else
        resetBtn:Disable()
        resetBtn.label:SetTextColor(theme.GetColor("TEXT_DIM"))
    end
end

-- 세션 기록 표 갱신, dik, 2026-09-30
local function FillTable()
    local history = ns.Leveling.GetHistory()
    local rows = {}
    local unknown = L.VALUE_UNKNOWN
    for i = 1, #history do
        local rec = history[i]
        local rate = ns.Leveling.ComputeRate(rec.xp, rec.duration)
        rows[i] = {
            id = tostring(rec.startedAt) .. "#" .. i,
            data = rec,
            cells = {
                startedAt = { text = ns.FormatDateTime(rec.startedAt), sortValue = rec.startedAt, colorToken = "TEXT" },
                duration = { text = ns.FormatDuration(rec.duration), sortValue = rec.duration, colorToken = "TEXT" },
                xp = { text = ns.FormatNumber(rec.xp), sortValue = rec.xp, colorToken = "TEXT" },
                rate = { text = ns.FormatNumber(rate), sortValue = rate, colorToken = "TEXT" },
                level = { text = L.FMT_LEVEL_RANGE:format(rec.startLevel or unknown, rec.endLevel or unknown),
                    sortValue = rec.endLevel, colorToken = "TEXT" },
                kills = { text = ns.FormatNumber(rec.kills), sortValue = rec.kills, colorToken = "TEXT" },
                quests = { text = ns.FormatNumber(rec.quests), sortValue = rec.quests, colorToken = "TEXT" },
            },
        }
    end
    tbl:SetRows(rows)
end

-- 전체 재배치, dik, 2026-09-30
local function Layout(snap)
    local theme = ns.Theme
    local gap = theme.GAP
    local y = 0

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    y = y + bar:GetHeight() + gap

    statusLabel:ClearAllPoints()
    statusLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    statusLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    y = y + math.ceil(GetLineHeight(statusLabel)) + gap

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
        y = y + math.ceil(rowH) + gap
    end

    local btnLabel = resetBtn.label
    resetBtn:SetWidth(math.floor(btnLabel:GetStringWidth() + theme.PAD * 2 + 0.5))
    resetBtn:SetHeight(math.max(theme.MENU_ITEM_H, math.floor(GetLineHeight(btnLabel) + gap + 0.5)))
    local lineH = math.max(resetBtn:GetHeight(), GetLineHeight(noteLabel))
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y + (lineH - resetBtn:GetHeight()) / 2))
    noteLabel:ClearAllPoints()
    if snap.killsSupported then
        noteLabel:SetPoint("LEFT", page, "TOPLEFT", 0, -(y + lineH / 2))
        noteLabel:SetPoint("RIGHT", resetBtn, "LEFT", -gap, 0)
        noteLabel:Show()
    else
        noteLabel:Hide()
    end
    y = y + lineH + gap

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    header:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    y = y + HEADER_H

    tbl:ClearAllPoints()
    tbl:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    tbl:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    tbl:SetPoint("BOTTOM", page, "BOTTOM", 0, 0)
end

-- 전체 갱신, dik, 2026-09-30
local function FillAll()
    if not page then
        return
    end
    local snap = ns.Leveling.GetSnapshot()
    FillBar(snap)
    FillStatus(snap)
    FillGrid(snap)
    FillButton(snap)
    FillTable()
    Layout(snap)
end

-- 세션 초기화 클릭, dik, 2026-09-30
local function OnResetClick()
    ns.Leveling.ResetSession()
end

-- 레벨링 페이지 생성, dik, 2026-09-30
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    bar = ns.Widgets.CreateBar(page, { fontToken = "FONT_SMALL" })
    statusLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    statusLabel:SetWordWrap(false)

    for i = 1, #GRID do
        for _, key in pairs(GRID[i]) do
            local label = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
            label:SetWordWrap(false)
            local staticKey = STATIC_LABELS[key]
            if staticKey then
                label:SetText(L[staticKey])
            end
            local value = ns.Widgets.CreateLabel(page, "FONT_NUMBER", "TEXT")
            value:SetWordWrap(false)
            cells[key] = { label = label, value = value }
        end
    end

    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(false)
    noteLabel:SetText(L.LEVELING_KILL_NOTE)
    resetBtn = ns.Widgets.CreateButton(page, L.LEVELING_RESET, OnResetClick)
    -- 툴팁 연결, dik, 2026-10-01
    ns.Widgets.SetTooltip(resetBtn, L.LEVELING_RESET, L.TIP_LEVELING_RESET)

    header = ns.Widgets.CreateSectionHeader(page, L.LEVELING_HISTORY)
    header:SetHeight(HEADER_H)
    tbl = ns.Widgets.CreateTable(page, COLUMNS, { emptyText = L.LEVELING_HISTORY_EMPTY })
    tbl:SetSort("startedAt", false)

    page:SetScript("OnUpdate", function(_, elapsed)
        tickAcc = tickAcc + elapsed
        if tickAcc >= TICK_SECONDS then
            tickAcc = 0
            FillGrid(ns.Leveling.GetSnapshot())
        end
    end)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 갱신, dik, 2026-09-30
function module.OnPageShow()
    tickAcc = 0
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-09-30
function module.OnPageHide()
    tickAcc = 0
end

-- 보일 때만 즉시 갱신, dik, 2026-09-30
local function RefreshOrMark()
    if not page then
        return
    end
    if page:IsVisible() then
        FillAll()
    end
end

ns.On("LEVELING_UPDATED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if scope == "leveling" and key == "recentMinutes" then
        RefreshOrMark()
    elseif scope == "global" and key == "fontSize" then
        if page and page:IsVisible() then
            tbl:Refresh()
            FillAll()
        end
    end
end)
