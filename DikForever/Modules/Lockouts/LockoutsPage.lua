-- 귀속·리셋 페이지, dik, 2026-09-30
local addonName, ns = ...

local module = ns.GetModule("lockouts")
if not module then
    return
end

local L = ns.L
local format = string.format

local REFRESH_SECONDS = 5
local FALLBACK_LINE_H = 14
local LABEL_W = 110
local HEADER_H = 28
local SOON_SECONDS = 3600

local COLUMNS = {
    { key = "character", title = L.LOCKOUTS_COL_CHARACTER, width = 100, align = "LEFT", defaultAsc = true },
    { key = "instance", title = L.LOCKOUTS_COL_INSTANCE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "difficulty", title = L.LOCKOUTS_COL_DIFFICULTY, width = 80, align = "LEFT", defaultAsc = true },
    { key = "progress", title = L.LOCKOUTS_COL_PROGRESS, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "remaining", title = L.LOCKOUTS_COL_REMAINING, width = 80, align = "RIGHT", defaultAsc = true },
    { key = "resetAt", title = L.LOCKOUTS_COL_RESET_AT, width = 110, align = "RIGHT", defaultAsc = true },
}

local GRID_KEYS = { "daily", "weekly", "hourly" }

local GRID_LABELS = {
    daily = "LOCKOUTS_DAILY",
    weekly = "LOCKOUTS_WEEKLY",
    hourly = "LOCKOUTS_HOURLY",
}

local page
local statusLabel
local sectionTitle
local sectionLine
local tbl
local summaryLabel
local noteLabel
local cells = {}
local tickAcc = 0
local dirty = false

-- 글자 높이 계산, dik, 2026-09-30
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 라벨 색 토큰 적용, dik, 2026-09-30
local function SetLabelColor(label, token)
    label:SetTextColor(ns.Theme.GetColor(token))
end

-- 직업색 조회, dik, 2026-09-30
local function GetClassColor(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return { r = c.r, g = c.g, b = c.b }
    end
    return nil
end

-- 난이도 셀 문구, dik, 2026-09-30
local function GetDifficultyText(rec)
    if type(rec.difficultyName) == "string" and rec.difficultyName ~= "" then
        return rec.difficultyName
    end
    return rec.isRaid and L.LOCKOUTS_KIND_RAID or L.LOCKOUTS_KIND_DUNGEON
end

-- 표 행 변환, dik, 2026-09-30
local function BuildTableRows(list)
    local rows = {}
    for i = 1, #list do
        local rec = list[i]
        if type(rec) == "table" then
            local nameCell = { text = rec.displayName, sortValue = rec.displayName }
            local color = GetClassColor(rec.classFile)
            if color then
                nameCell.color = color
            else
                nameCell.colorToken = "TEXT"
            end

            local instText = rec.extended and format(L.LOCKOUTS_EXTENDED, rec.name) or rec.name
            local diffText = GetDifficultyText(rec)

            local progCell
            if type(rec.total) == "number" then
                progCell = {
                    text = format(L.LOCKOUTS_PROGRESS, rec.progress or 0, rec.total),
                    colorToken = (rec.progress == rec.total) and "TEXT_DIM" or "TEXT",
                }
                if rec.total > 0 and type(rec.progress) == "number" then
                    progCell.sortValue = rec.progress / rec.total
                end
            else
                progCell = { text = L.VALUE_UNKNOWN, colorToken = "TEXT_DIM" }
            end

            local remain = rec.remaining
            rows[#rows + 1] = {
                id = rec.id,
                data = rec,
                cells = {
                    character = nameCell,
                    instance = { text = instText, sortValue = rec.name, colorToken = "TEXT" },
                    difficulty = { text = diffText, sortValue = diffText, colorToken = "TEXT" },
                    progress = progCell,
                    remaining = { text = ns.FormatDuration(remain), sortValue = remain,
                        colorToken = (type(remain) == "number" and remain < SOON_SECONDS) and "ACCENT" or "TEXT" },
                    resetAt = { text = ns.FormatDateTime(rec.resetAt), sortValue = rec.resetAt, colorToken = "TEXT_DIM" },
                }
            }
        end
    end
    return rows
end

-- 리셋 그리드 값 채움, dik, 2026-09-30
local function FillGrid()
    local lockouts = ns.Lockouts
    local daily, weekly
    if lockouts then
        daily, weekly = lockouts.GetResetTimes()
    end
    local now = time()
    local resets = { daily = daily, weekly = weekly }
    for _, key in ipairs({ "daily", "weekly" }) do
        local sec = resets[key]
        local value = cells[key].value
        if type(sec) == "number" then
            value:SetText(format(L.LOCKOUTS_RESET_VALUE, ns.FormatDuration(sec), ns.FormatDateTime(now + sec)))
            SetLabelColor(value, "TEXT")
        else
            value:SetText(L.VALUE_UNKNOWN)
            SetLabelColor(value, "TEXT_DIM")
        end
    end

    local hourly = lockouts and lockouts.GetHourly()
    local hv = cells.hourly.value
    if type(hourly) == "table" and hourly.enabled then
        if hourly.wait == nil then
            hv:SetText(format(L.LOCKOUTS_HOURLY_VALUE, hourly.count or 0, hourly.limit or 0, hourly.left or 0))
            SetLabelColor(hv, "TEXT")
        else
            hv:SetText(format(L.LOCKOUTS_HOURLY_FULL, hourly.count or 0, hourly.limit or 0,
                ns.FormatDuration(hourly.wait)))
            SetLabelColor(hv, "DANGER")
        end
        return true
    end
    return false
end

-- 상태 안내 줄 채움, dik, 2026-09-30
local function FillStatus()
    local status = ns.Lockouts and ns.Lockouts.GetStatus()
    if type(status) ~= "table" then
        statusLabel:SetText("")
    elseif not status.ready then
        statusLabel:SetText(L.LOCKOUTS_NOT_READY)
        SetLabelColor(statusLabel, "TEXT_DIM")
    elseif status.secret then
        statusLabel:SetText(L.LOCKOUTS_SECRET)
        SetLabelColor(statusLabel, "DANGER")
    elseif status.readOnly then
        statusLabel:SetText(L.LOCKOUTS_READ_ONLY)
        SetLabelColor(statusLabel, "TEXT_DIM")
    else
        statusLabel:SetText("")
    end
end

-- 표·머리글·푸터 채움, dik, 2026-09-30
local function FillList(now)
    local lockouts = ns.Lockouts
    local rows = lockouts and lockouts.BuildRows(now)
    if type(rows) ~= "table" then
        rows = {}
    end
    sectionTitle:SetText(format(L.LOCKOUTS_SECTION, #rows))
    tbl:SetRows(BuildTableRows(rows))

    local summary = lockouts and lockouts.GetSummary(now)
    if type(summary) == "table" then
        local scanned = summary.currentScannedAt and ns.FormatElapsed(summary.currentScannedAt, now)
            or L.LOCKOUTS_SCAN_PENDING
        summaryLabel:SetText(format(L.LOCKOUTS_SUMMARY, summary.scannedChars or 0, summary.totalChars or 0, scanned))
    else
        summaryLabel:SetText("")
    end
    noteLabel:SetText(L.LOCKOUTS_NOTE)
end

-- 전체 재배치, dik, 2026-09-30
local function Layout(hourlyShown)
    local gap = ns.Theme.GAP
    local y = 0

    for _, key in ipairs(GRID_KEYS) do
        local cell = cells[key]
        if key == "hourly" and not hourlyShown then
            cell.label:Hide()
            cell.value:Hide()
        else
            cell.label:Show()
            cell.value:Show()
            cell.label:ClearAllPoints()
            cell.label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            cell.label:SetWidth(LABEL_W - gap)
            cell.value:ClearAllPoints()
            cell.value:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_W, -y)
            cell.value:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
            y = y + math.ceil(math.max(GetLineHeight(cell.label), GetLineHeight(cell.value))) + gap
        end
    end

    statusLabel:ClearAllPoints()
    if (statusLabel:GetText() or "") ~= "" then
        statusLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        statusLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        statusLabel:Show()
        y = y + math.ceil(GetLineHeight(statusLabel)) + gap
    else
        statusLabel:Hide()
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
    summaryLabel:ClearAllPoints()
    summaryLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, bottom)
    summaryLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    bottom = bottom + math.ceil(GetLineHeight(summaryLabel)) + gap

    tbl:ClearAllPoints()
    tbl:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + 1))
    tbl:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y + 1))
    tbl:SetPoint("BOTTOM", page, "BOTTOM", 0, bottom)
end

-- 전체 갱신, dik, 2026-09-30
local function FillAll()
    if not page then
        return
    end
    dirty = false
    local now = time()
    local hourlyShown = FillGrid()
    FillStatus()
    FillList(now)
    Layout(hourlyShown)
end

-- 귀속·리셋 페이지 생성, dik, 2026-09-30
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    for _, key in ipairs(GRID_KEYS) do
        local label = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
        label:SetWordWrap(false)
        label:SetText(L[GRID_LABELS[key]])
        local value = ns.Widgets.CreateLabel(page, "FONT_NUMBER", "TEXT")
        value:SetWordWrap(false)
        cells[key] = { label = label, value = value }
    end

    statusLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT_DIM")
    statusLabel:SetWordWrap(false)

    sectionTitle = ns.Widgets.CreateLabel(page, "FONT_MENU", "ACCENT")
    sectionTitle:SetWordWrap(false)
    sectionLine = page:CreateTexture(nil, "ARTWORK")
    sectionLine:SetHeight(1)
    sectionLine:SetColorTexture(ns.Theme.GetColor("BORDER"))

    tbl = ns.Widgets.CreateTable(page, COLUMNS, { emptyText = L.LOCKOUTS_EMPTY })
    tbl:SetSort("remaining", true)

    summaryLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    summaryLabel:SetWordWrap(false)
    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(true)

    page:SetScript("OnUpdate", function(_, elapsed)
        tickAcc = tickAcc + elapsed
        if tickAcc >= REFRESH_SECONDS then
            tickAcc = 0
            FillAll()
        end
    end)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 갱신, dik, 2026-09-30
function module.OnPageShow()
    tickAcc = 0
    if ns.Lockouts then
        ns.Lockouts.RequestRefresh()
    end
    if dirty and tbl then
        tbl:Refresh()
    end
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
    else
        dirty = true
    end
end

ns.On("LOCKOUTS_UPDATED", RefreshOrMark)
ns.On("CHAR_UPDATED", RefreshOrMark)
ns.On("CHAR_DELETED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if not page then
        return
    end
    if scope == "global" and key == "fontSize" then
        if page:IsVisible() then
            tbl:Refresh()
            FillAll()
        else
            dirty = true
        end
    elseif scope == "lockouts" then
        RefreshOrMark()
    end
end)
