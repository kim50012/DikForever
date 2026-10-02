-- 재료 쇼핑 리스트 페이지, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("shopping")
if not module then
    return
end

local L = ns.L

local SEARCH_DELAY = 0.2
local PROF_DROPDOWN_W = 150
local TARGET_VISIBLE_ROWS = 4
local CLEAR_CONFIRM_SECONDS = 5
local QTY_STEP_SHIFT = 10
local HEADER_H = 28
local FALLBACK_LINE_H = 14
local RECIPE_MAX = 3000
local TARGET_MAX = 50
local QTY_MAX = 999

local TARGET_COLUMNS = {
    { key = "name", title = L.SHOP_COL_RECIPE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "count", title = L.SHOP_COL_COUNT, width = 50, align = "RIGHT", defaultAsc = false },
    { key = "prof", title = L.SHOP_COL_PROF, width = 100, align = "LEFT", defaultAsc = true },
}

local REAGENT_COLUMNS = {
    { key = "name", title = L.SHOP_COL_ITEM, flex = true, align = "LEFT", defaultAsc = true },
    { key = "need", title = L.SHOP_COL_NEED, width = 55, align = "RIGHT", defaultAsc = false },
    { key = "owned", title = L.SHOP_COL_OWNED, width = 55, align = "RIGHT", defaultAsc = false },
    { key = "short", title = L.SHOP_COL_SHORT, width = 55, align = "RIGHT", defaultAsc = false },
    { key = "where", title = L.SHOP_COL_WHERE, width = 170, align = "LEFT", defaultAsc = true },
}

local RECIPE_COLUMNS = {
    { key = "name", title = L.SHOP_COL_RECIPE, flex = true, align = "LEFT", defaultAsc = true },
    { key = "prof", title = L.SHOP_COL_PROF, width = 90, align = "LEFT", defaultAsc = true },
    { key = "reagents", title = L.SHOP_COL_REAGENTS, width = 220, align = "LEFT", defaultAsc = true },
}

local page
local listBtn
local addBtn
local scopeLabel
local noticeLabel
local listArea
local addArea
local targetTitle
local targetLine
local targetTbl
local minusBtn
local plusBtn
local removeBtn
local clearBtn
local reagentTitle
local reagentLine
local reagentTbl
local ddProf
local searchBox
local recipeTitle
local recipeLine
local recipeTbl
local previewLabel
local qtyMinusBtn
local qtyLabel
local qtyPlusBtn
local addTargetBtn
local cacheLabel
local noteLabel

local view = "list"
local dirty = false
local tooltipShown = false
local searchGen = 0
local profKey = "all"
local query = ""
local addQty = 1
local previewOverride
local targetRecs = {}
local recipeRecs = {}
local lastSummary
local confirmArmed = false
local confirmAt = 0
local confirmToken = 0

-- ns.Shopping 함수 조회, dik, 2026-10-01
local function Shop(name)
    local s = ns.Shopping
    local f = s and s[name]
    if type(f) == "function" then
        return f
    end
    return nil
end

-- 상태 조회, dik, 2026-10-01
local function GetShopStatus()
    local f = Shop("GetStatus")
    local s = f and f()
    if type(s) == "table" then
        return s
    end
    return nil
end

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

-- 품질색 복사, dik, 2026-10-01
local function GetQualityColor(quality)
    local c = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if type(c) == "table" and c.r and c.g and c.b then
        return { r = c.r, g = c.g, b = c.b }
    end
    return nil
end

-- 횟수 보정, dik, 2026-10-01
local function ClampQty(v)
    local f = Shop("ClampCount")
    if f then
        return f(v)
    end
    if type(v) ~= "number" or v ~= v then
        return 1
    end
    return math.max(1, math.min(QTY_MAX, math.floor(v)))
end

-- 증감 단위, dik, 2026-10-01
local function GetStep()
    if IsShiftKeyDown and IsShiftKeyDown() then
        return QTY_STEP_SHIFT
    end
    return 1
end

-- 행 툴팁 숨김, dik, 2026-10-01
local function HideRowTooltip()
    if tooltipShown then
        tooltipShown = false
        GameTooltip:Hide()
    end
end

-- 모두 삭제 확인 취소, dik, 2026-10-01
local function CancelConfirm()
    confirmArmed = false
    confirmToken = confirmToken + 1
    if clearBtn then
        clearBtn.label:SetText(L.SHOP_BTN_CLEAR)
    end
end

-- 모두 삭제 버튼 폭 고정, dik, 2026-10-01
local function FitClearButton()
    local label = clearBtn.label
    local current = label:GetText()
    local maxW = 0
    local texts = { L.SHOP_BTN_CLEAR, L.SHOP_BTN_CLEAR_CONFIRM }
    for i = 1, #texts do
        label:SetText(texts[i])
        maxW = math.max(maxW, label:GetStringWidth())
    end
    label:SetText(current)
    clearBtn:SetWidth(math.floor(maxW + ns.Theme.PAD * 2 + 0.5))
end

-- 알림 문구 판정(우선순위 1개), dik, 2026-10-01
local function PickNotice(status, summary)
    if not status or not status.ready then
        return L.SHOP_NOT_READY, "TEXT_DIM"
    end
    if status.readOnly then
        return L.SHOP_READ_ONLY, "TEXT_DIM"
    end
    if status.scanEnabled == false then
        return L.SHOP_SCAN_UNAVAILABLE, "DANGER"
    end
    if status.inventory == false then
        return L.SHOP_NO_INVENTORY, "DANGER"
    end
    if status.secret then
        return L.SHOP_SECRET, "DANGER"
    end
    local scan = type(status.lastScan) == "table" and status.lastScan or nil
    if scan and scan.failed then
        return L.SHOP_SCAN_FAILED, "DANGER"
    end
    if scan and type(scan.count) == "number" and scan.count == 0 then
        return L.SHOP_SCAN_EMPTY, "DANGER"
    end
    if status.recipeTruncated then
        return L.SHOP_RECIPE_TRUNCATED:format(RECIPE_MAX), "DANGER"
    end
    if scan and scan.reason == "linked" then
        return L.SHOP_SCAN_SKIPPED_LINKED, "TEXT_DIM"
    end
    if view == "list" and summary and type(summary.unknown) == "number" and summary.unknown > 0 then
        return L.SHOP_UNKNOWN_TARGETS:format(summary.unknown), "TEXT_DIM"
    end
    return nil, nil
end

-- 알림 줄 채움, dik, 2026-10-01
local function FillNotice(status, summary)
    local text, token = PickNotice(status, summary)
    noticeLabel:SetText(text or "")
    if token then
        SetLabelColor(noticeLabel, token)
    end
end

-- 보기 버튼 색과 보유 범위 채움, dik, 2026-10-01
local function FillTopBar(status)
    listBtn.label:SetTextColor(ns.Theme.GetColor(view == "list" and "ACCENT" or "TEXT"))
    addBtn.label:SetTextColor(ns.Theme.GetColor(view == "add" and "ACCENT" or "TEXT"))
    -- 보유 범위 라벨을 onlyKey 기준으로 변경, dik, 2026-10-01
    if status and type(status.onlyKey) == "string" then
        scopeLabel:SetText(L.SHOP_SCOPE_CURRENT)
    else
        scopeLabel:SetText(L.SHOP_SCOPE_ALL)
    end
end

-- 푸터 채움, dik, 2026-10-01
local function FillFooter(status)
    local f = Shop("GetStats")
    local stats = f and f()
    if type(stats) ~= "table" then
        stats = { recipes = 0, profs = 0 }
    end
    local text = L.SHOP_CACHE_STATUS:format(ns.FormatNumber(stats.recipes or 0), stats.profs or 0)
    local p = status and status.scanning and status.progress
    if type(p) == "table" then
        text = text .. " · " .. L.SHOP_SCANNING:format(p.done or 0, p.total or 0)
    end
    cacheLabel:SetText(text)
    noteLabel:SetText(L.SHOP_NOTE)
end

-- 목록 보기 채움(요약 반환), dik, 2026-10-01
local function FillList()
    local f = Shop("GetTargetRows")
    local recs = f and f() or {}
    targetRecs = {}
    local rows = {}
    for i = 1, #recs do
        local rec = recs[i]
        targetRecs[rec.id] = rec
        local name = rec.name or L.SHOP_RECIPE_UNKNOWN:format(rec.recipe or 0)
        local prof = rec.profName or L.VALUE_UNKNOWN
        local count = rec.count or 0
        rows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                name = { text = name, sortValue = name, colorToken = rec.known == false and "TEXT_DIM" or "TEXT" },
                count = { text = ns.FormatNumber(count), sortValue = count, colorToken = "ACCENT" },
                prof = { text = prof, sortValue = prof, colorToken = "TEXT_DIM" },
            },
        }
    end
    targetTbl:SetRows(rows)
    targetTitle:SetText(L.SHOP_TARGETS_SECTION:format(#recs))

    local g = Shop("GetShortageRows")
    local srows, summary
    if g then
        srows, summary = g()
    end
    srows = srows or {}
    summary = summary or { items = 0, shortItems = 0, unknown = 0 }
    local out = {}
    for i = 1, #srows do
        local rec = srows[i]
        local name = rec.name or (rec.itemId and L.INV_ITEM_UNKNOWN:format(rec.itemId)) or L.VALUE_UNKNOWN
        local need, owned, short = rec.need or 0, rec.owned or 0, rec.short or 0
        local where = rec.whereText or L.VALUE_UNKNOWN
        local nameCell = { text = name, sortValue = name }
        local color = GetQualityColor(rec.quality)
        if color then
            nameCell.color = color
        else
            nameCell.colorToken = "TEXT"
        end
        local shortCell
        if short > 0 then
            shortCell = { text = ns.FormatNumber(short), sortValue = short, colorToken = "DANGER" }
        else
            shortCell = { text = L.SHOP_ENOUGH, sortValue = short, colorToken = "TEXT_DIM" }
        end
        out[i] = {
            id = rec.id or rec.key or i,
            data = rec,
            cells = {
                name = nameCell,
                need = { text = ns.FormatNumber(need), sortValue = need, colorToken = "TEXT" },
                owned = { text = ns.FormatNumber(owned), sortValue = owned, colorToken = "TEXT" },
                short = shortCell,
                where = { text = where, sortValue = where, colorToken = "TEXT_DIM" },
            },
        }
    end
    reagentTbl:SetRows(out)
    reagentTitle:SetText(L.SHOP_REAGENTS_SECTION:format(summary.shortItems or 0, summary.items or 0))
    return summary
end

-- 드롭다운 항목 갱신과 선택 키 검증, dik, 2026-10-01
local function FillDropdown()
    local f = Shop("GetProfFilterItems")
    local items = f and f()
    if type(items) ~= "table" or #items == 0 then
        items = { { value = "all", text = L.SHOP_ALL_PROFS } }
    end
    local found = false
    for i = 1, #items do
        if items[i].value == profKey then
            found = true
            break
        end
    end
    if not found then
        profKey = "all"
    end
    ddProf:SetItems(items, profKey)
end

-- 미리보기 줄 채움, dik, 2026-10-01
local function FillPreview()
    if previewOverride then
        previewLabel:SetText(previewOverride.text)
        SetLabelColor(previewLabel, previewOverride.token)
        return
    end
    local id = recipeTbl:GetSelectedId()
    local rec = id ~= nil and recipeRecs[id] or nil
    if rec then
        local f = Shop("GetReagentText")
        local text = f and f(rec.recipe, addQty) or L.SHOP_NO_REAGENTS
        previewLabel:SetText(L.SHOP_PREVIEW:format(rec.name or L.VALUE_UNKNOWN, text))
        SetLabelColor(previewLabel, "TEXT")
    else
        previewLabel:SetText(L.SHOP_PREVIEW_NONE)
        SetLabelColor(previewLabel, "TEXT_DIM")
    end
end

-- 횟수 라벨 채움과 폭 고정, dik, 2026-10-01
local function FillQty()
    qtyLabel:SetText(L.SHOP_QTY:format(QTY_MAX))
    qtyLabel:SetWidth(math.ceil(qtyLabel:GetStringWidth()) + 1)
    qtyLabel:SetText(L.SHOP_QTY:format(addQty))
end

-- 추가 보기 채움, dik, 2026-10-01
local function FillAdd()
    FillDropdown()
    local f = Shop("GetRecipeRows")
    local recs, matchCount
    if f then
        recs, matchCount = f(profKey, query)
    end
    recs = recs or {}
    matchCount = matchCount or #recs
    recipeRecs = {}
    local rows = {}
    for i = 1, #recs do
        local rec = recs[i]
        recipeRecs[rec.id] = rec
        local name = rec.name or L.SHOP_RECIPE_UNKNOWN:format(rec.recipe or 0)
        local prof = rec.profName or L.VALUE_UNKNOWN
        local reagents = rec.reagentText or L.SHOP_NO_REAGENTS
        rows[i] = {
            id = rec.id,
            data = rec,
            cells = {
                name = { text = name, sortValue = name, colorToken = "TEXT" },
                prof = { text = prof, sortValue = prof, colorToken = "TEXT_DIM" },
                reagents = { text = reagents, sortValue = reagents, colorToken = "TEXT_DIM" },
            },
        }
    end
    recipeTbl:SetRows(rows)
    if matchCount > #recs then
        recipeTitle:SetText(L.SHOP_RECIPES_SECTION_CAPPED:format(ns.FormatNumber(matchCount), #recs))
    else
        recipeTitle:SetText(L.SHOP_RECIPES_SECTION:format(ns.FormatNumber(matchCount)))
    end
    FillQty()
    FillPreview()
end

-- 버튼 활성 상태 갱신, dik, 2026-10-01
local function UpdateButtons()
    if view == "list" then
        local hasSel = targetTbl:GetSelectedId() ~= nil
        SetButtonEnabled(minusBtn, hasSel)
        SetButtonEnabled(plusBtn, hasSel)
        SetButtonEnabled(removeBtn, hasSel)
        local hasTargets = next(targetRecs) ~= nil
        if not hasTargets and confirmArmed then
            CancelConfirm()
        end
        SetButtonEnabled(clearBtn, hasTargets)
    else
        SetButtonEnabled(addTargetBtn, recipeTbl:GetSelectedId() ~= nil)
    end
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

-- 목록 보기 배치, dik, 2026-10-01
local function LayoutList(gap)
    local t = PlaceHeader(listArea, targetTitle, targetLine, 0)
    local tableH = (1 + TARGET_VISIBLE_ROWS) * GetRowHeight()
    targetTbl:ClearAllPoints()
    targetTbl:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -(t + 1))
    targetTbl:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", 0, -(t + 1))
    targetTbl:SetHeight(tableH)
    t = t + 1 + tableH + gap

    minusBtn:ClearAllPoints()
    minusBtn:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -t)
    plusBtn:ClearAllPoints()
    plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", gap, 0)
    removeBtn:ClearAllPoints()
    removeBtn:SetPoint("LEFT", plusBtn, "RIGHT", gap, 0)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("LEFT", removeBtn, "RIGHT", gap, 0)
    t = t + minusBtn:GetHeight() + gap

    t = PlaceHeader(listArea, reagentTitle, reagentLine, t)
    reagentTbl:ClearAllPoints()
    reagentTbl:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -(t + 1))
    reagentTbl:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", 0, -(t + 1))
    reagentTbl:SetPoint("BOTTOM", listArea, "BOTTOM", 0, 0)
end

-- 추가 보기 배치, dik, 2026-10-01
local function LayoutAdd(gap)
    local rowH = math.max(searchBox:GetHeight(), ddProf:GetHeight())
    ddProf:ClearAllPoints()
    ddProf:SetPoint("TOPLEFT", addArea, "TOPLEFT", 0, 0)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", ddProf, "TOPRIGHT", gap, 0)
    searchBox:SetPoint("TOPRIGHT", addArea, "TOPRIGHT", 0, 0)
    local t = rowH + gap

    t = PlaceHeader(addArea, recipeTitle, recipeLine, t)

    local btnH = qtyMinusBtn:GetHeight()
    qtyMinusBtn:ClearAllPoints()
    qtyMinusBtn:SetPoint("BOTTOMLEFT", addArea, "BOTTOMLEFT", 0, 0)
    qtyLabel:ClearAllPoints()
    qtyLabel:SetPoint("LEFT", qtyMinusBtn, "RIGHT", gap, 0)
    qtyPlusBtn:ClearAllPoints()
    qtyPlusBtn:SetPoint("LEFT", qtyLabel, "RIGHT", gap, 0)
    addTargetBtn:ClearAllPoints()
    addTargetBtn:SetPoint("LEFT", qtyPlusBtn, "RIGHT", gap * 2, 0)

    previewLabel:ClearAllPoints()
    previewLabel:SetPoint("BOTTOMLEFT", addArea, "BOTTOMLEFT", 0, btnH + gap)
    previewLabel:SetPoint("BOTTOMRIGHT", addArea, "BOTTOMRIGHT", 0, btnH + gap)
    local bottom = btnH + gap + math.ceil(GetLineHeight(previewLabel)) + gap

    recipeTbl:ClearAllPoints()
    recipeTbl:SetPoint("TOPLEFT", addArea, "TOPLEFT", 0, -(t + 1))
    recipeTbl:SetPoint("TOPRIGHT", addArea, "TOPRIGHT", 0, -(t + 1))
    recipeTbl:SetPoint("BOTTOM", addArea, "BOTTOM", 0, bottom)
end

-- 전체 재배치, dik, 2026-10-01
local function Layout()
    local theme = ns.Theme
    local gap = theme.GAP
    local y

    listBtn:ClearAllPoints()
    listBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    addBtn:ClearAllPoints()
    addBtn:SetPoint("LEFT", listBtn, "RIGHT", gap, 0)
    scopeLabel:ClearAllPoints()
    scopeLabel:SetPoint("RIGHT", page, "TOPRIGHT", 0, -(listBtn:GetHeight() / 2))
    y = listBtn:GetHeight() + gap

    noticeLabel:ClearAllPoints()
    if (noticeLabel:GetText() or "") ~= "" then
        noticeLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        noticeLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        noticeLabel:Show()
        y = y + math.ceil(GetLineHeight(noticeLabel)) + gap
    else
        noticeLabel:Hide()
    end

    noteLabel:ClearAllPoints()
    noteLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    noteLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    local bottom = math.ceil(GetLineHeight(noteLabel)) + gap
    cacheLabel:ClearAllPoints()
    cacheLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, bottom)
    cacheLabel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    bottom = bottom + math.ceil(GetLineHeight(cacheLabel)) + gap

    for _, area in ipairs({ listArea, addArea }) do
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    end
    if view == "list" then
        LayoutList(gap)
    else
        LayoutAdd(gap)
    end
end

-- 전체 채움, dik, 2026-10-01
local function FillAll()
    if not page then
        return
    end
    dirty = false
    local status = GetShopStatus()
    FillTopBar(status)
    local summary
    if view == "list" then
        addArea:Hide()
        listArea:Show()
        summary = FillList()
        lastSummary = summary
    else
        listArea:Hide()
        addArea:Show()
        FillAdd()
    end
    FillNotice(status, summary)
    FillFooter(status)
    UpdateButtons()
    Layout()
end

-- 기록 진행 중 가벼운 갱신, dik, 2026-10-01
local function FillLight()
    local status = GetShopStatus()
    FillNotice(status, lastSummary)
    FillFooter(status)
    Layout()
end

-- 보기 전환, dik, 2026-10-01
local function SetView(v)
    if view == v then
        return
    end
    view = v
    CancelConfirm()
    HideRowTooltip()
    previewOverride = nil
    if searchBox then
        searchBox:ClearFocus()
    end
    if ddProf then
        ddProf:Close()
    end
    FillAll()
end

-- 선택된 목표 조회, dik, 2026-10-01
local function GetSelectedTarget()
    local id = targetTbl:GetSelectedId()
    return id ~= nil and targetRecs[id] or nil
end

-- 목표 횟수 증감, dik, 2026-10-01
local function ChangeTargetCount(sign)
    local rec = GetSelectedTarget()
    local f = Shop("SetTargetCount")
    if not rec or not f then
        return
    end
    f(rec.recipe, (rec.count or 1) + sign * GetStep())
    FillAll()
end

-- 목표 삭제, dik, 2026-10-01
local function OnRemoveClick()
    local rec = GetSelectedTarget()
    local f = Shop("RemoveTarget")
    if not rec or not f then
        return
    end
    f(rec.recipe)
    targetTbl:SetSelectedId(nil)
    FillAll()
end

-- 모두 삭제 두 번 눌러 확인, dik, 2026-10-01
local function OnClearClick()
    local f = Shop("ClearTargets")
    if not f then
        return
    end
    if confirmArmed and GetTime() - confirmAt <= CLEAR_CONFIRM_SECONDS then
        CancelConfirm()
        f()
        targetTbl:SetSelectedId(nil)
        FillAll()
        return
    end
    confirmArmed = true
    confirmAt = GetTime()
    confirmToken = confirmToken + 1
    clearBtn.label:SetText(L.SHOP_BTN_CLEAR_CONFIRM)
    if C_Timer and C_Timer.After then
        local token = confirmToken
        C_Timer.After(CLEAR_CONFIRM_SECONDS, function()
            if token == confirmToken and confirmArmed then
                CancelConfirm()
            end
        end)
    end
end

-- 추가 횟수 증감, dik, 2026-10-01
local function ChangeAddQty(sign)
    addQty = ClampQty(addQty + sign * GetStep())
    previewOverride = nil
    FillQty()
    FillPreview()
    Layout()
end

-- 목록에 추가, dik, 2026-10-01
local function OnAddClick()
    local id = recipeTbl:GetSelectedId()
    local rec = id ~= nil and recipeRecs[id] or nil
    local f = Shop("AddTarget")
    if not rec or not f then
        return
    end
    local ok, errKey = f(rec.recipe, addQty)
    if ok then
        local g = Shop("GetStats")
        local stats = g and g()
        local targets = type(stats) == "table" and stats.targets or 0
        previewOverride = { text = L.SHOP_ADDED:format(rec.name or L.VALUE_UNKNOWN, addQty, targets), token = "TEXT" }
    else
        local text = L[errKey or ""] or L.SHOP_ERR_UNKNOWN_RECIPE
        if errKey == "SHOP_ERR_TARGET_FULL" then
            text = text:format(TARGET_MAX)
        end
        previewOverride = { text = text, token = "DANGER" }
    end
    FillAll()
end

-- 재료 행 오버 툴팁, dik, 2026-10-01
local function ShowReagentTooltip(rowFrame, row)
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

-- 목표 행 오버 툴팁, dik, 2026-10-01
local function ShowTargetTooltip(rowFrame, row)
    local rec = row and row.data
    if not rec then
        return
    end
    local f = Shop("GetTargetDetail")
    local detail = f and f(rec.recipe)
    local ar, ag, ab = ns.Theme.GetColor("ACCENT")
    local tr, tg, tb = ns.Theme.GetColor("TEXT")
    local dr, dg, db = ns.Theme.GetColor("TEXT_DIM")
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if type(detail) == "table" then
        GameTooltip:AddLine(detail.name or rec.name or L.VALUE_UNKNOWN, ar, ag, ab)
        local lines = detail.lines or {}
        for i = 1, #lines do
            local line = lines[i]
            GameTooltip:AddDoubleLine(line.name or L.VALUE_UNKNOWN, ns.FormatNumber(line.need or 0),
                tr, tg, tb, tr, tg, tb)
        end
        if (detail.skipped or 0) > 0 then
            GameTooltip:AddLine(L.SHOP_TIP_SKIPPED, dr, dg, db)
        end
    else
        GameTooltip:AddLine(rec.name or L.VALUE_UNKNOWN, ar, ag, ab)
        GameTooltip:AddLine(L.SHOP_RECIPE_MISSING_TIP, dr, dg, db)
    end
    GameTooltip:Show()
    tooltipShown = true
end

-- 목표 행 클릭 처리, dik, 2026-10-01
local function OnTargetRowClick(row)
    targetTbl:SetSelectedId(row.id)
    CancelConfirm()
    UpdateButtons()
end

-- 레시피 행 클릭 처리, dik, 2026-10-01
local function OnRecipeRowClick(row)
    recipeTbl:SetSelectedId(row.id)
    previewOverride = nil
    FillPreview()
    UpdateButtons()
    Layout()
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

-- 전문기술 드롭다운 변경 처리, dik, 2026-10-01
local function OnProfChanged(value)
    profKey = value or "all"
    FillAll()
end

-- 쇼핑 목록 페이지 생성, dik, 2026-10-01
function module.CreatePage(_, parent)
    if page then
        return page
    end
    page = CreateFrame("Frame", nil, parent)
    local widgets = ns.Widgets
    local rowH = ns.Theme.MENU_ITEM_H

    listBtn = widgets.CreateButton(page, L.SHOP_VIEW_LIST, function()
        SetView("list")
    end)
    addBtn = widgets.CreateButton(page, L.SHOP_VIEW_ADD, function()
        SetView("add")
    end)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(listBtn, L.SHOP_VIEW_LIST, L.TIP_SHOP_VIEW_LIST)
    widgets.SetTooltip(addBtn, L.SHOP_VIEW_ADD, L.TIP_SHOP_VIEW_ADD)
    scopeLabel = widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    scopeLabel:SetJustifyH("RIGHT")
    noticeLabel = widgets.CreateLabel(page, "FONT_SMALL", "TEXT")
    noticeLabel:SetWordWrap(false)

    listArea = CreateFrame("Frame", nil, page)
    addArea = CreateFrame("Frame", nil, page)

    targetTitle = widgets.CreateLabel(listArea, "FONT_MENU", "ACCENT")
    targetTitle:SetWordWrap(false)
    targetLine = listArea:CreateTexture(nil, "ARTWORK")
    targetLine:SetHeight(1)
    targetLine:SetColorTexture(ns.Theme.GetColor("BORDER"))
    targetTbl = widgets.CreateTable(listArea, TARGET_COLUMNS, {
        rowHeight = rowH,
        emptyText = L.SHOP_TARGETS_EMPTY,
        onRowClick = OnTargetRowClick,
        onRowEnter = ShowTargetTooltip,
        onRowLeave = HideRowTooltip,
    })
    minusBtn = widgets.CreateButton(listArea, L.SHOP_BTN_MINUS, function()
        ChangeTargetCount(-1)
    end)
    plusBtn = widgets.CreateButton(listArea, L.SHOP_BTN_PLUS, function()
        ChangeTargetCount(1)
    end)
    removeBtn = widgets.CreateButton(listArea, L.SHOP_BTN_REMOVE, OnRemoveClick)
    clearBtn = widgets.CreateButton(listArea, L.SHOP_BTN_CLEAR, OnClearClick)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(minusBtn, nil, L.TIP_SHOP_TARGET_MINUS)
    widgets.SetTooltip(plusBtn, nil, L.TIP_SHOP_TARGET_PLUS)
    widgets.SetTooltip(removeBtn, L.SHOP_BTN_REMOVE, L.TIP_SHOP_REMOVE)
    widgets.SetTooltip(clearBtn, L.SHOP_BTN_CLEAR, L.TIP_SHOP_CLEAR)
    FitClearButton()
    reagentTitle = widgets.CreateLabel(listArea, "FONT_MENU", "ACCENT")
    reagentTitle:SetWordWrap(false)
    reagentLine = listArea:CreateTexture(nil, "ARTWORK")
    reagentLine:SetHeight(1)
    reagentLine:SetColorTexture(ns.Theme.GetColor("BORDER"))
    reagentTbl = widgets.CreateTable(listArea, REAGENT_COLUMNS, {
        rowHeight = rowH,
        emptyText = L.SHOP_REAGENTS_EMPTY,
        onRowEnter = ShowReagentTooltip,
        onRowLeave = HideRowTooltip,
    })
    reagentTbl:SetSort("short", false)

    ddProf = widgets.CreateDropdown(addArea, { width = PROF_DROPDOWN_W,
        items = { { value = "all", text = L.SHOP_ALL_PROFS } }, value = "all", onChange = OnProfChanged })
    searchBox = widgets.CreateSearchBox(addArea, { placeholder = L.SHOP_SEARCH_PLACEHOLDER, onChange = OnSearchChanged })
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(ddProf, nil, L.TIP_SHOP_PROF)
    searchBox:SetTooltip(nil, L.TIP_SHOP_SEARCH)
    recipeTitle = widgets.CreateLabel(addArea, "FONT_MENU", "ACCENT")
    recipeTitle:SetWordWrap(false)
    recipeLine = addArea:CreateTexture(nil, "ARTWORK")
    recipeLine:SetHeight(1)
    recipeLine:SetColorTexture(ns.Theme.GetColor("BORDER"))
    recipeTbl = widgets.CreateTable(addArea, RECIPE_COLUMNS, {
        rowHeight = rowH,
        emptyText = L.SHOP_RECIPES_EMPTY,
        onRowClick = OnRecipeRowClick,
    })
    recipeTbl:SetSort("name", true)
    previewLabel = widgets.CreateLabel(addArea, "FONT_SMALL", "TEXT_DIM")
    previewLabel:SetWordWrap(false)
    qtyMinusBtn = widgets.CreateButton(addArea, L.SHOP_BTN_MINUS, function()
        ChangeAddQty(-1)
    end)
    qtyLabel = widgets.CreateLabel(addArea, "FONT_BODY", "TEXT")
    qtyLabel:SetJustifyH("CENTER")
    qtyPlusBtn = widgets.CreateButton(addArea, L.SHOP_BTN_PLUS, function()
        ChangeAddQty(1)
    end)
    addTargetBtn = widgets.CreateButton(addArea, L.SHOP_BTN_ADD, OnAddClick)
    -- 툴팁 연결, dik, 2026-10-01
    widgets.SetTooltip(qtyMinusBtn, nil, L.TIP_SHOP_QTY_MINUS)
    widgets.SetTooltip(qtyPlusBtn, nil, L.TIP_SHOP_QTY_PLUS)
    widgets.SetTooltip(addTargetBtn, L.SHOP_BTN_ADD, L.TIP_SHOP_ADD)

    cacheLabel = widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    cacheLabel:SetWordWrap(false)
    noteLabel = widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
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
        ddProf:Refresh()
        searchBox:Refresh()
        targetTbl:Refresh()
        reagentTbl:Refresh()
        recipeTbl:Refresh()
    end
    FillAll()
end

-- 페이지 숨김 시 정리, dik, 2026-10-01
function module.OnPageHide()
    if searchBox then
        searchBox:ClearFocus()
    end
    if ddProf then
        ddProf:Close()
    end
    HideRowTooltip()
    CancelConfirm()
end

-- 글꼴 크기 변경 반영 후 채움, dik, 2026-10-01
local function RefreshFonts()
    ddProf:Refresh()
    searchBox:Refresh()
    targetTbl:Refresh()
    reagentTbl:Refresh()
    recipeTbl:Refresh()
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

-- 쇼핑 갱신 이벤트 처리, dik, 2026-10-01
ns.On("SHOPPING_UPDATED", function(reason)
    if not page then
        return
    end
    if not page:IsVisible() then
        dirty = true
        return
    end
    local status = reason == "status" and GetShopStatus() or nil
    if status and status.ready and status.scanning then
        FillLight()
    else
        FillAll()
    end
end)
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
    elseif scope == "shopping" or (scope == "inventory" and key == "enabled") then
        RefreshOrMark()
    end
end)
