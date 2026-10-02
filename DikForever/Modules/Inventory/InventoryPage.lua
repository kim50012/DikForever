-- 보유량 색인 페이지, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("inventory")
if not module then
    return
end

local L = ns.L

local FALLBACK_LINE_H = 14
local CHAR_DROPDOWN_W = 150
local SEARCH_DELAY = 0.2
local HEADER_H = 28

local COLUMNS = {
    { key = "name", title = L.INV_COL_ITEM, flex = true, align = "LEFT", defaultAsc = true },
    { key = "total", title = L.INV_COL_TOTAL, width = 60, align = "RIGHT", defaultAsc = false },
    { key = "bags", title = L.INV_COL_BAGS, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "bank", title = L.INV_COL_BANK, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "mail", title = L.INV_COL_MAIL, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "chars", title = L.INV_COL_CHARS, width = 50, align = "RIGHT", defaultAsc = false },
}

local page
local searchBox
local ddChar
local statusLabel
local noticeLabel
local sectionTitle
local sectionLine
local tbl
local summaryLabel
local noteLabel
local dirty = false
local tooltipShown = false
local searchGen = 0
local filterKey = "all"
local query = ""

-- 글자 높이 계산, dik, 2026-10-01
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = FALLBACK_LINE_H
    end
    return h
end

-- 라벨 색 토큰 적용, dik, 2026-10-01
local function SetLabelColor(label, token)
    label:SetTextColor(ns.Theme.GetColor(token))
end

-- 품질색 복사, dik, 2026-10-01
local function GetQualityColor(quality)
    local c = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if type(c) == "table" and c.r and c.g and c.b then
        return { r = c.r, g = c.g, b = c.b }
    end
    return nil
end

-- 위치별 수량 셀, dik, 2026-10-01
local function BuildCountCell(n)
    if type(n) ~= "number" or n <= 0 then
        return { text = L.VALUE_UNKNOWN, sortValue = 0, colorToken = "TEXT_DIM" }
    end
    return { text = ns.FormatNumber(n), sortValue = n, colorToken = "TEXT" }
end

-- 드롭다운 항목 갱신과 선택 키 검증, dik, 2026-10-01
local function FillDropdown()
    local items = ns.Inventory.GetFilterItems()
    local found = false
    for i = 1, #items do
        if items[i].value == filterKey then
            found = true
            break
        end
    end
    if not found then
        filterKey = "all"
    end
    ddChar:SetItems(items, filterKey)
    return items
end

-- 캐릭터 표시 이름 조회, dik, 2026-10-01
local function GetDisplayName(items, key)
    for i = 1, #items do
        if items[i].value == key then
            return items[i].text
        end
    end
    return key
end

-- 갱신 상태 줄 채움, dik, 2026-10-01
local function FillStatus(items)
    local current = ns.GetCurrentCharacterKey()
    local key = filterKey ~= "all" and filterKey or current
    local info = key and ns.Inventory.GetScanInfo(key)
    if not info then
        statusLabel:SetText("")
        return
    end
    local now = time()
    local status = ns.Inventory.GetStatus()
    local isCurrent = key == current
    -- 위치별 경과 문구, dik, 2026-10-01
    local function Part(at, featureOn)
        if isCurrent and featureOn == false then
            return L.VALUE_UNKNOWN
        end
        if at then
            return ns.FormatElapsed(at, now)
        end
        return L.INV_NEVER
    end
    statusLabel:SetText(L.INV_SCAN_STATUS:format(GetDisplayName(items, key), Part(info.bagsAt),
        Part(info.bankAt, status.bankEnabled), Part(info.mailAt, status.mailEnabled)))
end

-- 대상 캐릭터의 잘림·우편 일부 여부 모음, dik, 2026-10-01
local function CollectScanFlags()
    local truncated = {}
    local mailPartial = false
    local keys = filterKey == "all" and ns.GetCharacterKeys() or { filterKey }
    for i = 1, #keys do
        local info = ns.Inventory.GetScanInfo(keys[i])
        if info then
            if type(info.truncated) == "table" then
                for loc, on in pairs(info.truncated) do
                    if on then
                        truncated[loc] = true
                    end
                end
            end
            if info.mailPartial then
                mailPartial = true
            end
        end
    end
    return truncated, mailPartial
end

-- 알림 줄 채움(우선순위 1개), dik, 2026-10-01
local function FillNotice()
    local text, token
    local status = ns.Inventory.GetStatus()
    local tipStatus = ns.Tooltip and ns.Tooltip.GetStatus and ns.Tooltip.GetStatus()
    if not status.ready then
        text, token = L.INV_NOT_READY, "TEXT_DIM"
    elseif status.readOnly then
        text, token = L.INV_READ_ONLY, "TEXT_DIM"
    elseif status.secret then
        text, token = L.INV_SECRET, "DANGER"
    elseif tipStatus and not tipStatus.installed then
        text, token = L.INV_TOOLTIP_UNAVAILABLE, "TEXT_DIM"
    else
        local truncated, mailPartial = CollectScanFlags()
        local names = {}
        if truncated.bags then
            names[#names + 1] = L.INV_COL_BAGS
        end
        if truncated.bank then
            names[#names + 1] = L.INV_COL_BANK
        end
        if truncated.mail then
            names[#names + 1] = L.INV_COL_MAIL
        end
        if #names > 0 then
            text, token = L.INV_TRUNCATED:format(table.concat(names, ", ")), "DANGER"
        elseif mailPartial then
            text, token = L.INV_MAIL_PARTIAL, "TEXT_DIM"
        end
    end
    noticeLabel:SetText(text or "")
    if token then
        SetLabelColor(noticeLabel, token)
    end
end

-- 표 채움과 머리글, dik, 2026-10-01
local function FillTable()
    local recs, matchCount = ns.Inventory.BuildRows(filterKey, query)
    local rows = {}
    for i = 1, #recs do
        local rec = recs[i]
        local nameCell = { text = rec.name, sortValue = rec.name }
        local color = GetQualityColor(rec.quality)
        if color then
            nameCell.color = color
        else
            nameCell.colorToken = "TEXT"
        end
        rows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                name = nameCell,
                total = { text = ns.FormatNumber(rec.total), sortValue = rec.total, colorToken = "ACCENT" },
                bags = BuildCountCell(rec.bags),
                bank = BuildCountCell(rec.bank),
                mail = BuildCountCell(rec.mail),
                chars = { text = tostring(rec.chars), sortValue = rec.chars, colorToken = "TEXT" },
            },
        }
    end
    tbl:SetRows(rows)
    if matchCount > #recs then
        sectionTitle:SetText(L.INV_SECTION_CAPPED:format(ns.FormatNumber(matchCount), #recs))
    else
        sectionTitle:SetText(L.INV_SECTION:format(ns.FormatNumber(matchCount)))
    end
end

-- 푸터 채움, dik, 2026-10-01
local function FillFooter()
    local stats = ns.Inventory.GetStats()
    summaryLabel:SetText(L.INV_SUMMARY:format(stats.chars, ns.FormatNumber(stats.entries),
        ns.FormatNumber(stats.items)))
    noteLabel:SetText(L.INV_NOTE)
end

-- 전체 재배치, dik, 2026-10-01
local function Layout()
    local theme = ns.Theme
    local gap = theme.GAP
    local y = 0

    local rowH = math.max(searchBox:GetHeight(), ddChar:GetHeight())
    ddChar:ClearAllPoints()
    ddChar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local pageW = page:GetWidth() or 0
    if pageW > 0 and pageW - CHAR_DROPDOWN_W - gap < CHAR_DROPDOWN_W then
        searchBox:SetWidth(CHAR_DROPDOWN_W)
    else
        searchBox:SetPoint("TOPRIGHT", ddChar, "TOPLEFT", -gap, 0)
    end
    y = y + rowH + gap

    for _, label in ipairs({ statusLabel, noticeLabel }) do
        label:ClearAllPoints()
        if label:GetText() ~= "" then
            label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            label:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
            label:Show()
            y = y + math.ceil(GetLineHeight(label)) + gap
        else
            label:Hide()
        end
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

-- 전체 채움, dik, 2026-10-01
local function FillAll()
    if not page then
        return
    end
    dirty = false
    local items = FillDropdown()
    FillStatus(items)
    FillNotice()
    FillTable()
    FillFooter()
    Layout()
end

-- 행 툴팁 숨김, dik, 2026-10-01
local function HideRowTooltip()
    if tooltipShown then
        tooltipShown = false
        GameTooltip:Hide()
    end
end

-- 행 오버 툴팁 표시, dik, 2026-10-01
local function ShowRowTooltip(rowFrame, row)
    local rec = row and row.data
    if not rec or not rec.itemId then
        return
    end
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    local setByGame = false
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(rec.itemId)
        setByGame = true
    elseif GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink("item:" .. rec.itemId)
        setByGame = true
    else
        GameTooltip:ClearLines()
        -- 툴팁 줄 색 3값만 전달, dik, 2026-10-01
        local r, g, b = ns.Theme.GetColor("TEXT")
        GameTooltip:AddLine(rec.name or "", r, g, b)
    end
    local tipStatus = ns.Tooltip and ns.Tooltip.GetStatus and ns.Tooltip.GetStatus()
    local hooked = tipStatus and tipStatus.installed and setByGame
    if not hooked and ns.Tooltip and ns.Tooltip.AppendItemLines then
        ns.Tooltip.AppendItemLines(GameTooltip, rec.itemId)
    end
    GameTooltip:Show()
    tooltipShown = true
end

-- 검색어 변경 합치기, dik, 2026-10-01
local function OnSearchChanged(text)
    query = text or ""
    searchGen = searchGen + 1
    local gen = searchGen
    if C_Timer and C_Timer.After then
        C_Timer.After(SEARCH_DELAY, function()
            if gen == searchGen then
                FillAll()
            end
        end)
    else
        FillAll()
    end
end

-- 캐릭터 드롭다운 변경 처리, dik, 2026-10-01
local function OnCharChanged(value)
    filterKey = value or "all"
    FillAll()
end

-- 보유량 페이지 생성, dik, 2026-10-01
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)

    searchBox = ns.Widgets.CreateSearchBox(page, { placeholder = L.INV_SEARCH_PLACEHOLDER, onChange = OnSearchChanged })
    ddChar = ns.Widgets.CreateDropdown(page, { width = CHAR_DROPDOWN_W,
        items = { { value = "all", text = L.INV_ALL_CHARS } }, value = "all", onChange = OnCharChanged })
    -- 툴팁 연결, dik, 2026-10-01
    searchBox:SetTooltip(nil, L.TIP_INV_SEARCH)
    ns.Widgets.SetTooltip(ddChar, nil, L.TIP_INV_CHAR)

    statusLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    statusLabel:SetWordWrap(false)
    noticeLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT")
    noticeLabel:SetWordWrap(false)

    sectionTitle = ns.Widgets.CreateLabel(page, "FONT_MENU", "ACCENT")
    sectionTitle:SetWordWrap(false)
    sectionLine = page:CreateTexture(nil, "ARTWORK")
    sectionLine:SetHeight(1)
    sectionLine:SetColorTexture(ns.Theme.GetColor("BORDER"))

    tbl = ns.Widgets.CreateTable(page, COLUMNS, {
        emptyText = L.INV_EMPTY,
        onRowEnter = ShowRowTooltip,
        onRowLeave = HideRowTooltip,
    })
    tbl:SetSort("total", false)

    summaryLabel = ns.Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    summaryLabel:SetWordWrap(false)
    noteLabel = ns.Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    noteLabel:SetWordWrap(true)

    page:SetScript("OnSizeChanged", function()
        if page:IsVisible() then
            Layout()
        end
    end)

    FillAll()
    return page
end

-- 페이지 표시 시 전체 채움, dik, 2026-10-01
function module.OnPageShow()
    if dirty and page then
        ddChar:Refresh()
        searchBox:Refresh()
        tbl:Refresh()
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-10-01
function module.OnPageHide()
    if searchBox then
        searchBox:ClearFocus()
    end
    if ddChar then
        ddChar:Close()
    end
    HideRowTooltip()
end

-- 글꼴 크기 변경 반영 후 채움, dik, 2026-10-01
local function RefreshFonts()
    ddChar:Refresh()
    searchBox:Refresh()
    tbl:Refresh()
    FillAll()
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

ns.On("INVENTORY_UPDATED", RefreshOrMark)
ns.On("CHAR_UPDATED", RefreshOrMark)
ns.On("CHAR_DELETED", RefreshOrMark)

-- 설정 변경 반영, dik, 2026-10-01
ns.On("SETTING_CHANGED", function(scope, key)
    if not page then
        return
    end
    if scope == "global" and key == "fontSize" then
        if page:IsVisible() then
            RefreshFonts()
        else
            dirty = true
        end
    elseif scope == "inventory" then
        RefreshOrMark()
    end
end)
