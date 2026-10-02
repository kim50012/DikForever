-- 잡일 자동화 페이지, dik, 2026-09-30
local addonName, ns = ...

local module = ns.GetModule("chores")
if not module then
    return
end

local L = ns.L

local FALLBACK_LINE_H = 14
local CHORES_SETTINGS_H = 150
local HEADER_H = 28

local COLUMNS = {
    { key = "t", title = L.CHORES_COL_TIME, width = 110, align = "LEFT", defaultAsc = false },
    { key = "char", title = L.CHORES_COL_CHAR, width = 90, align = "LEFT", defaultAsc = true },
    { key = "kind", title = L.CHORES_COL_KIND, width = 90, align = "LEFT", defaultAsc = true },
    { key = "detail", title = L.CHORES_COL_DETAIL, flex = true, align = "LEFT", defaultAsc = true },
}

local KIND_LABELS = {
    sell = "CHORES_KIND_SELL",
    repair = "CHORES_KIND_REPAIR",
    guildRepair = "CHORES_KIND_GUILD_REPAIR",
    repairNoMoney = "CHORES_KIND_REPAIR_NO_MONEY",
    accept = "CHORES_KIND_ACCEPT",
    turnIn = "CHORES_KIND_TURNIN",
    reward = "CHORES_KIND_REWARD",
    skip = "CHORES_KIND_SKIP",
    blocked = "CHORES_KIND_BLOCKED",
}

local WINDOW_LABELS = {
    merchant = "CHORES_WINDOW_MERCHANT",
    quest = "CHORES_WINDOW_QUEST",
}

local page
local settingsFrame
local totalLabel
local noteLabel
local statusLabel
local header
local tbl
local dirty = false

-- 글자 높이 계산, dik, 2026-09-30
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 로그 상세 문구 생성, dik, 2026-09-30
local function BuildDetail(entry)
    local unknown = L.VALUE_UNKNOWN
    local kind = entry.kind
    if kind == "sell" then
        local text = L.CHORES_LOG_SELL:format(entry.count or 0, ns.FormatMoney(entry.money))
        if type(entry.left) == "number" and entry.left > 0 then
            text = text .. L.CHORES_LOG_LEFT:format(entry.left)
        end
        return text
    elseif kind == "repair" then
        local text = ns.FormatMoney(entry.money)
        if entry.text == "guildFallback" then
            text = text .. L.CHORES_LOG_FALLBACK
        end
        return text
    elseif kind == "guildRepair" then
        return ns.FormatMoney(entry.money)
    elseif kind == "repairNoMoney" then
        return L.CHORES_LOG_NEED:format(ns.FormatMoney(entry.money))
    elseif kind == "accept" or kind == "turnIn" or kind == "reward" or kind == "blocked" then
        return entry.text or unknown
    elseif kind == "skip" then
        local key = WINDOW_LABELS[entry.text]
        return key and L[key] or unknown
    end
    return unknown
end

-- 상세 셀 색 토큰, dik, 2026-09-30
local function GetDetailToken(kind)
    if kind == "blocked" or kind == "repairNoMoney" then
        return "DANGER"
    elseif kind == "skip" then
        return "TEXT_DIM"
    end
    return "TEXT"
end

-- 로그 항목을 표 행으로 변환, dik, 2026-09-30
local function BuildRow(entry, i)
    local unknown = L.VALUE_UNKNOWN
    local info = entry.char and ns.GetCharacterInfo(entry.char)
    local charText = (info and info.name) or entry.char or unknown
    local kindKey = KIND_LABELS[entry.kind]
    local kindText = kindKey and L[kindKey] or unknown
    local detail = BuildDetail(entry)
    return {
        id = tostring(entry.t or 0) .. "#" .. i,
        data = entry,
        cells = {
            t = { text = ns.FormatDateTime(entry.t), sortValue = entry.t, colorToken = "TEXT" },
            char = { text = charText, sortValue = charText, colorToken = "TEXT" },
            kind = { text = kindText, sortValue = kindText, colorToken = "TEXT" },
            detail = { text = detail, sortValue = detail, colorToken = GetDetailToken(entry.kind) },
        },
    }
end

-- 상태 줄 문구 판정, dik, 2026-09-30
local function GetStatusText()
    local status = ns.Chores.GetStatus()
    if type(status) ~= "table" then
        return nil
    end
    if status.blocked then
        return L.CHORES_BLOCKED_NOTE
    end
    if type(status.missing) == "table" and #status.missing > 0 then
        return L.CHORES_UNSUPPORTED_NOTE:format(ns.FormatMissingAPIs(status.missing))
    end
    return nil
end

-- 전체 재배치, dik, 2026-09-30
local function Layout(showStatus)
    local gap = ns.Theme.GAP
    local y = 0

    settingsFrame:ClearAllPoints()
    settingsFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    settingsFrame:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    settingsFrame:SetHeight(CHORES_SETTINGS_H)
    y = y + CHORES_SETTINGS_H + gap

    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    totalLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    y = y + math.ceil(GetLineHeight(totalLabel)) + gap

    noteLabel:ClearAllPoints()
    noteLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    noteLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
    y = y + math.ceil(GetLineHeight(noteLabel)) + gap

    statusLabel:ClearAllPoints()
    if showStatus then
        statusLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        statusLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        statusLabel:Show()
        y = y + math.ceil(GetLineHeight(statusLabel)) + gap
    else
        statusLabel:Hide()
    end

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
    if not page or not ns.Chores then
        return
    end
    local t = ns.Chores.GetSessionTotals() or {}
    totalLabel:SetText(L.CHORES_SESSION:format(t.soldCount or 0, ns.FormatMoney(t.soldMoney or 0),
        ns.FormatMoney(t.repairMoney or 0), t.accepted or 0, t.turnedIn or 0))

    local statusText = GetStatusText()
    if statusText then
        statusLabel:SetText(statusText)
    end

    local log = ns.Chores.GetLog() or {}
    local rows = {}
    for i = 1, #log do
        rows[i] = BuildRow(log[i], i)
    end
    tbl:SetRows(rows)
    Layout(statusText ~= nil)
end

-- 잡일 자동화 페이지 생성, dik, 2026-09-30
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    settingsFrame = ns.SettingsUI.RenderModuleSettings(page, "chores")

    totalLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    totalLabel:SetWordWrap(false)
    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(false)
    noteLabel:SetText(L.CHORES_NOTE)
    statusLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "DANGER")
    statusLabel:SetWordWrap(false)
    statusLabel:Hide()

    header = ns.Widgets.CreateSectionHeader(page, L.CHORES_LOG_HEADER)
    header:SetHeight(HEADER_H)
    tbl = ns.Widgets.CreateTable(page, COLUMNS, { emptyText = L.CHORES_LOG_EMPTY })
    tbl:SetSort("t", false)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 갱신, dik, 2026-09-30
function module.OnPageShow()
    if dirty and tbl then
        tbl:Refresh()
    end
    dirty = false
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-09-30
function module.OnPageHide()
end

-- 보일 때만 갱신 아니면 표시만, dik, 2026-09-30
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

ns.On("CHORES_UPDATED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if scope == "chores" then
        RefreshOrMark()
    elseif scope == "global" and key == "fontSize" then
        if page and page:IsVisible() then
            tbl:Refresh()
            FillAll()
        elseif page then
            dirty = true
        end
    end
end)
