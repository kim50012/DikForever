-- 부캐 요약 페이지, dik, 2026-09-30
local addonName, ns = ...

local module = ns.GetModule("alts")
if not module then
    return
end

local L = ns.L

local DELETE_CONFIRM_SECONDS = 5
local FALLBACK_LINE_H = 14
local TIP_SEPARATOR = " · "

local COLUMNS = {
    { key = "name", title = L.ALTS_COL_NAME, width = 100, align = "LEFT", defaultAsc = true },
    { key = "level", title = L.ALTS_COL_LEVEL, width = 36, align = "RIGHT", defaultAsc = false },
    { key = "xp", title = L.ALTS_COL_XP, width = 56, align = "RIGHT", defaultAsc = false },
    { key = "rest", title = L.ALTS_COL_REST, width = 100, align = "RIGHT", defaultAsc = false },
    { key = "money", title = L.ALTS_COL_MONEY, width = 120, align = "RIGHT", defaultAsc = false },
    { key = "lastSeen", title = L.ALTS_COL_LAST_SEEN, width = 72, align = "RIGHT", defaultAsc = false },
    { key = "zone", title = L.ALTS_COL_ZONE, flex = true, align = "LEFT", defaultAsc = true },
}

local page
local tbl
local totalLabel
local noteLabel
local deleteBtn
local confirmKey
local confirmAt = 0
local confirmToken = 0
local tooltipShown = false

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

-- 삭제 확인 취소, dik, 2026-09-30
local function CancelConfirm()
    confirmKey = nil
    confirmToken = confirmToken + 1
    if deleteBtn then
        deleteBtn.label:SetText(L.ALTS_DELETE)
    end
end

-- 삭제 버튼 폭 고정, dik, 2026-09-30
local function FitDeleteButton()
    local label = deleteBtn.label
    local current = label:GetText()
    local maxW = 0
    local texts = { L.ALTS_DELETE, L.ALTS_DELETE_CONFIRM }
    for i = 1, #texts do
        label:SetText(texts[i])
        maxW = math.max(maxW, label:GetStringWidth())
    end
    label:SetText(current)
    local theme = ns.Theme
    deleteBtn:SetWidth(math.floor(maxW + theme.PAD * 2 + 0.5))
    deleteBtn:SetHeight(math.max(theme.MENU_ITEM_H, math.floor(GetLineHeight(label) + theme.GAP + 0.5)))
end

-- 푸터·표 재배치, dik, 2026-09-30
local function LayoutFooter()
    if not page then
        return
    end
    local gap = ns.Theme.GAP
    FitDeleteButton()
    local showNote = ns.GetSetting("alts", "showEstimate") and ns.HasAPI("time")
    local bottom = 0
    noteLabel:ClearAllPoints()
    if showNote then
        noteLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
        noteLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        noteLabel:Show()
        bottom = math.ceil(GetLineHeight(noteLabel)) + gap
    else
        noteLabel:Hide()
    end
    local lineH = math.max(deleteBtn:GetHeight(), GetLineHeight(totalLabel))
    deleteBtn:ClearAllPoints()
    deleteBtn:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom + (lineH - deleteBtn:GetHeight()) / 2)
    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("LEFT", page, "BOTTOMLEFT", 0, bottom + lineH / 2)
    totalLabel:SetPoint("RIGHT", deleteBtn, "LEFT", -gap, 0)
    tbl:ClearAllPoints()
    tbl:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    tbl:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    tbl:SetPoint("BOTTOM", page, "BOTTOM", 0, bottom + lineH + gap)
end

-- 삭제 버튼 상태 갱신, dik, 2026-09-30
local function UpdateDeleteButton()
    local theme = ns.Theme
    local id = tbl:GetSelectedId()
    if id and ns.Alts.CanDelete(id) then
        deleteBtn:Enable()
        deleteBtn.label:SetTextColor(theme.GetColor("TEXT"))
    else
        CancelConfirm()
        deleteBtn:Disable()
        deleteBtn.label:SetTextColor(theme.GetColor("TEXT_DIM"))
    end
end

-- 휴식 경험치 셀 문구, dik, 2026-09-30
local function BuildRestText(rec)
    if rec.restXp == nil then
        return L.VALUE_UNKNOWN
    end
    local text
    if type(rec.xpMax) == "number" and rec.xpMax > 0 and rec.restRatio then
        text = L.FMT_REST:format(ns.FormatNumber(rec.restXp), math.floor(rec.restRatio * 100))
    else
        text = ns.FormatNumber(rec.restXp)
    end
    if rec.restEstimated then
        text = L.FMT_ESTIMATED:format(text)
    end
    return text
end

-- 레코드를 표 행으로 변환, dik, 2026-09-30
local function BuildTableRow(rec, now)
    local nameCell = { text = rec.displayName, sortValue = rec.displayName }
    local classColor = GetClassColor(rec.classFile)
    if classColor then
        nameCell.color = classColor
    else
        nameCell.colorToken = "TEXT"
    end

    local lastSeenCell
    if rec.isCurrent then
        lastSeenCell = { text = L.ALTS_ONLINE, colorToken = "ACCENT", sortValue = rec.lastSeenSort }
    else
        lastSeenCell = { text = ns.FormatElapsed(rec.lastSeen, now), colorToken = "TEXT", sortValue = rec.lastSeenSort }
    end

    local zoneCell = { text = rec.zoneText or L.VALUE_UNKNOWN, sortValue = rec.zoneText,
        colorToken = rec.zoneText and "TEXT" or "TEXT_DIM" }

    return {
        id = rec.key,
        data = rec,
        cells = {
            name = nameCell,
            level = { text = rec.level and tostring(rec.level) or L.VALUE_UNKNOWN, sortValue = rec.level, colorToken = "TEXT" },
            xp = { text = ns.FormatPercent(rec.xpRatio), sortValue = rec.xpRatio, colorToken = "TEXT" },
            rest = { text = BuildRestText(rec), sortValue = rec.restRatio, colorToken = "TEXT" },
            money = { text = ns.FormatMoney(rec.money), sortValue = rec.money, colorToken = "TEXT" },
            lastSeen = lastSeenCell,
            zone = zoneCell,
        },
    }
end

-- 표·푸터 다시 채움, dik, 2026-09-30
local function Fill()
    if not page then
        return
    end
    local now = ns.HasAPI("time") and time() or nil
    local records = ns.Alts.BuildRows(now)
    local rows = {}
    for i = 1, #records do
        rows[i] = BuildTableRow(records[i], now)
    end
    tbl:SetRows(rows)

    local totals = ns.Alts.GetTotals(records)
    local moneyText = totals.moneyCount > 0 and ns.FormatMoney(totals.money) or L.VALUE_UNKNOWN
    totalLabel:SetText(L.ALTS_TOTAL:format(totals.count, moneyText))
    noteLabel:SetText(L.ALTS_ESTIMATE_NOTE)
    UpdateDeleteButton()
    LayoutFooter()
end

-- 삭제 버튼 클릭 처리, dik, 2026-09-30
local function OnDeleteClick()
    local key = tbl:GetSelectedId()
    if not key then
        return
    end
    if confirmKey == key and GetTime() - confirmAt <= DELETE_CONFIRM_SECONDS then
        local ok = ns.Alts.DeleteCharacter(key)
        CancelConfirm()
        if ok then
            tbl:SetSelectedId(nil)
        end
        Fill()
        return
    end
    confirmKey = key
    confirmAt = GetTime()
    confirmToken = confirmToken + 1
    deleteBtn.label:SetText(L.ALTS_DELETE_CONFIRM)
    if C_Timer and C_Timer.After then
        local token = confirmToken
        C_Timer.After(DELETE_CONFIRM_SECONDS, function()
            if token == confirmToken and confirmKey then
                CancelConfirm()
            end
        end)
    end
end

-- 행 툴팁 표시, dik, 2026-09-30
local function ShowRowTooltip(rowFrame, row)
    local rec = row and row.data
    if not rec then
        return
    end
    local theme = ns.Theme
    local unknown = L.VALUE_UNKNOWN
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    local color = GetClassColor(rec.classFile)
    if color then
        GameTooltip:SetText(rec.displayName, color.r, color.g, color.b)
    else
        GameTooltip:SetText(rec.displayName, theme.GetColor("TEXT"))
    end
    local dr, dg, db = theme.GetColor("TEXT_DIM")
    GameTooltip:AddLine(L.TIP_ALTS_LEVEL_CLASS:format(rec.level or unknown, rec.raceName or unknown,
        rec.className or unknown), dr, dg, db)
    GameTooltip:AddLine(L.TIP_ALTS_XP:format(ns.FormatNumber(rec.xp), ns.FormatNumber(rec.xpMax)), dr, dg, db)
    local restLine = L.TIP_ALTS_REST:format(ns.FormatNumber(rec.restXp))
    if rec.restEstimated then
        restLine = restLine .. " " .. L.TIP_ALTS_ESTIMATED
    end
    restLine = restLine .. TIP_SEPARATOR .. (rec.resting and L.TIP_ALTS_RESTING or L.TIP_ALTS_NOT_RESTING)
    GameTooltip:AddLine(restLine, dr, dg, db)
    local guild = (rec.guild and rec.guild ~= "") and rec.guild or L.TIP_ALTS_NO_GUILD
    GameTooltip:AddLine(L.TIP_ALTS_GUILD:format(guild), dr, dg, db)
    local seen = rec.isCurrent and L.ALTS_ONLINE or ns.FormatDateTime(rec.lastSeen)
    GameTooltip:AddLine(L.TIP_ALTS_LAST_SEEN:format(seen), dr, dg, db)
    GameTooltip:AddLine(L.TIP_ALTS_ZONE:format(rec.zoneText or unknown), dr, dg, db)
    GameTooltip:Show()
    tooltipShown = true
end

-- 부캐 요약 페이지 생성, dik, 2026-09-30
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    tbl = ns.Widgets.CreateTable(page, COLUMNS, {
        emptyText = L.CHAR_LIST_EMPTY,
        onSortChanged = function(key, asc)
            ns.Alts.SetSortState(key, asc)
        end,
        onRowClick = function(row)
            if row.id ~= tbl:GetSelectedId() then
                CancelConfirm()
            end
            tbl:SetSelectedId(row.id)
            UpdateDeleteButton()
        end,
        onRowEnter = ShowRowTooltip,
        onRowLeave = function()
            tooltipShown = false
            GameTooltip:Hide()
        end,
    })

    totalLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    totalLabel:SetWordWrap(false)
    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(false)
    deleteBtn = ns.Widgets.CreateButton(page, L.ALTS_DELETE, OnDeleteClick)
    -- 툴팁 연결, dik, 2026-10-01
    ns.Widgets.SetTooltip(deleteBtn, L.ALTS_DELETE, L.TIP_ALTS_DELETE)

    local sortKey, sortAsc = ns.Alts.GetSortState()
    tbl:SetSort(sortKey, sortAsc)
    Fill()
    return page
end

-- 페이지 표시 시 다시 채움, dik, 2026-09-30
function module.OnPageShow()
    Fill()
end

-- 페이지 숨김 시 정리, dik, 2026-09-30
function module.OnPageHide()
    CancelConfirm()
    if tooltipShown then
        tooltipShown = false
        GameTooltip:Hide()
    end
end

-- 보일 때만 즉시 갱신, dik, 2026-09-30
local function RefreshOrMark()
    if page and page:IsVisible() then
        Fill()
    end
end

ns.On("CHAR_UPDATED", RefreshOrMark)
ns.On("CHAR_DELETED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if scope == "alts" and key == "showEstimate" then
        RefreshOrMark()
    elseif scope == "global" and key == "fontSize" then
        if page and page:IsVisible() then
            tbl:Refresh()
            Fill()
        end
    end
end)
