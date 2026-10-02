-- 관리창 메인 프레임(타이틀바·사이드바·페이지 전환), dik, 2026-09-30
local addonName, ns = ...

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local FRAME_NAME = "DikForeverMainFrame"
local OFFSCREEN_MIN_VISIBLE = 50
local CLOSE_BUTTON_W = 28
local ICON_SIZE = 16
local TITLE_LINE_OFFSET = 24
local HEADER_H = Theme.MENU_ITEM_H - 6
local CATEGORY_INDENT = Theme.PAD / 2
local MOVE_BUTTON_H = Theme.TITLEBAR_H - 6
-- 기능 검색창·결과 목록 치수, dik, 2026-10-01
local SEARCH_BOX_W = 200
local SEARCH_LIST_W = 320
local SEARCH_LIST_LEVEL = 50

local frame
local moveButton
local searchBox
local searchList
local searchRows = {}
local searchNone
local searchMore
local titleText
local host
local statusText
local menuButtons = {}
local pages = {}
local currentId
local interacting = false

-- 값을 범위 안으로 자르기, dik, 2026-09-30
local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- 정수 반올림, dik, 2026-09-30
local function Round(value)
    return math.floor(value + 0.5)
end

-- 1px 구분선 텍스처 생성, dik, 2026-09-30
local function CreateLine(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(Theme.GetColor("BORDER"))
    return line
end

-- 창 위치·크기를 DB 에 저장, dik, 2026-09-30
local function SaveWindow()
    if not frame or not ns.db or not ns.db.window then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    local window = ns.db.window
    window.point = point
    window.relativePoint = relativePoint
    window.x = Round(x)
    window.y = Round(y)
    window.width = Round(Clamp(frame:GetWidth(), Theme.WINDOW_MIN_W, Theme.WINDOW_MAX_W))
    window.height = Round(Clamp(frame:GetHeight(), Theme.WINDOW_MIN_H, Theme.WINDOW_MAX_H))
end

-- 창이 화면 밖이면 중앙으로 복원, dik, 2026-09-30
local function EnsureOnScreen()
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local pLeft, pRight, pTop, pBottom = UIParent:GetLeft(), UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (left and right and top and bottom and pLeft and pRight and pTop and pBottom) then
        return
    end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, right, top, bottom = left * ratio, right * ratio, top * ratio, bottom * ratio
    local overlapX = math.min(right, pRight) - math.max(left, pLeft)
    local overlapY = math.min(top, pTop) - math.max(bottom, pBottom)
    if overlapX < OFFSCREEN_MIN_VISIBLE or overlapY < OFFSCREEN_MIN_VISIBLE then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        SaveWindow()
    end
end

-- 저장된 위치·크기를 프레임에 적용, dik, 2026-09-30
local function ApplyWindow()
    local window = ns.db and ns.db.window
    local width, height = Theme.WINDOW_DEFAULT_W, Theme.WINDOW_DEFAULT_H
    frame:ClearAllPoints()
    if window and type(window.point) == "string" then
        -- 저장값 타입 가드(값은 덮어쓰지 않음), dik, 2026-09-30
        local relativePoint = type(window.relativePoint) == "string" and window.relativePoint or window.point
        local x = type(window.x) == "number" and window.x or 0
        local y = type(window.y) == "number" and window.y or 0
        frame:SetPoint(window.point, UIParent, relativePoint, x, y)
        if type(window.width) == "number" then
            width = window.width
        end
        if type(window.height) == "number" then
            height = window.height
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:SetSize(Clamp(width, Theme.WINDOW_MIN_W, Theme.WINDOW_MAX_W), Clamp(height, Theme.WINDOW_MIN_H, Theme.WINDOW_MAX_H))
    EnsureOnScreen()
end

-- 이동·크기 조절 중단 후 저장, dik, 2026-09-30
local function StopInteraction()
    if not interacting then
        return
    end
    interacting = false
    frame:StopMovingOrSizing()
    frame:SetSize(
        Clamp(frame:GetWidth(), Theme.WINDOW_MIN_W, Theme.WINDOW_MAX_W),
        Clamp(frame:GetHeight(), Theme.WINDOW_MIN_H, Theme.WINDOW_MAX_H)
    )
    SaveWindow()
end

-- 창 잠금 여부, dik, 2026-09-30
local function IsLocked()
    return ns.GetSetting("global", "lockWindow") == true
end

-- 기본 페이지 id 결정, dik, 2026-09-30
local function DefaultPageId()
    if ns.GetSetting("global", "rememberPage") then
        local window = ns.db and ns.db.window
        local last = window and window.lastPage
        if last and menuButtons[last] then
            return last
        end
    end
    return "home"
end

-- 페이지 생성 실패 표시 프레임, dik, 2026-09-30
local function CreateErrorPage(module)
    local page = CreateFrame("Frame", nil, host)
    local text = Widgets.CreateLabel(page, "FONT_BODY", "DANGER")
    text:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    text:SetText(string.format(L.ERR_PAGE_CREATE, module.title))
    return page
end

-- 미지원 모듈 안내 페이지 생성, dik, 2026-09-30
local function CreateUnsupportedPage(missing)
    local page = CreateFrame("Frame", nil, host)
    local first = Widgets.CreateLabel(page, "FONT_BODY", "TEXT")
    first:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    first:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    first:SetText(L.PAGE_UNSUPPORTED)
    local second = Widgets.CreateLabel(page, "FONT_SMALL", "TEXT_DIM")
    second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -Theme.GAP)
    second:SetPoint("TOPRIGHT", first, "BOTTOMRIGHT", 0, -Theme.GAP)
    second:SetWordWrap(true)
    second:SetText(string.format(L.PAGE_UNSUPPORTED_APIS, table.concat(missing, ", ")))
    return page
end

-- 모듈 페이지 프레임 생성, dik, 2026-09-30
local function BuildPage(module)
    local page
    -- 미지원 모듈은 안내 페이지로 대체, dik, 2026-09-30
    local supported, missing = ns.IsModuleSupported(module.id)
    if not supported then
        page = CreateUnsupportedPage(missing)
    elseif module.CreatePage then
        local ok, result = xpcall(function()
            return module:CreatePage(host)
        end, function(err)
            return err
        end)
        if not ok then
            geterrorhandler()(result)
            page = CreateErrorPage(module)
        else
            page = result or CreateErrorPage(module)
        end
    elseif ns.SettingsUI and ns.SettingsUI.RenderModuleSettings then
        page = ns.SettingsUI.RenderModuleSettings(host, module.id)
    end
    if not page then
        page = CreateErrorPage(module)
    end
    page:ClearAllPoints()
    page:SetAllPoints(host)
    page:Hide()
    return page
end

-- 사이드바 선택 표시 갱신, dik, 2026-09-30
local function UpdateSelection(id)
    for menuId, button in pairs(menuButtons) do
        button:SetSelected(menuId == id)
    end
end

-- 검색 결과 목록 닫기, dik, 2026-10-01
local function CloseSearchList()
    if searchList then
        searchList:Hide()
    end
end

-- 페이지 전환, dik, 2026-09-30
local function ShowPage(id)
    -- 페이지 전환 시 검색 결과 목록 닫기, dik, 2026-10-01
    CloseSearchList()
    if not frame or not menuButtons[id] then
        return
    end
    if id == currentId and pages[id] then
        return
    end
    local module = ns.GetModule(id)
    if not module then
        return
    end
    local shown = frame:IsShown()
    if currentId then
        local previous = ns.GetModule(currentId)
        if pages[currentId] then
            pages[currentId]:Hide()
        end
        -- 미지원 모듈은 OnPageHide 생략, dik, 2026-09-30
        if shown and previous and previous.OnPageHide and (ns.IsModuleSupported(currentId)) then
            previous:OnPageHide()
        end
    end
    if not pages[id] then
        pages[id] = BuildPage(module)
    end
    currentId = id
    titleText:SetText(module.title)
    UpdateSelection(id)
    pages[id]:Show()
    -- 미지원 모듈은 OnPageShow 생략, dik, 2026-09-30
    if shown and module.OnPageShow and (ns.IsModuleSupported(id)) then
        module:OnPageShow()
    end
    if ns.db and ns.db.window then
        ns.db.window.lastPage = id
    end
end

-- 사이드바 메뉴 버튼 생성, dik, 2026-09-30
local function CreateMenuButton(parent, module, indent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(Theme.MENU_ITEM_H)

    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(Theme.GetColor("SELECTED"))
    selected:Hide()

    local bar = button:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(Theme.GetColor("ACCENT"))
    bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(2)
    bar:Hide()

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(Theme.GetColor("HOVER"))

    local labelX = Theme.PAD + indent
    if module.icon then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", button, "LEFT", labelX, 0)
        icon:SetTexture(module.icon)
        labelX = labelX + ICON_SIZE + Theme.GAP - 2
    end

    local label = Widgets.CreateLabel(button, "FONT_MENU", "TEXT")
    label:SetPoint("LEFT", button, "LEFT", labelX, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -Theme.GAP, 0)
    label:SetText(module.title)

    -- 미지원 모듈은 미선택 라벨을 TEXT_DIM 으로, dik, 2026-09-30
    local idleColor = (ns.IsModuleSupported(module.id)) and "TEXT" or "TEXT_DIM"
    label:SetTextColor(Theme.GetColor(idleColor))

    function button.SetSelected(_, isSelected)
        selected:SetShown(isSelected)
        bar:SetShown(isSelected)
        -- 미선택 색을 idleColor 로, dik, 2026-09-30
        label:SetTextColor(Theme.GetColor(isSelected and "ACCENT" or idleColor))
    end

    -- 모듈 설명·미지원 안내 툴팁, dik, 2026-10-01
    local tipLines = {}
    if module.description then
        tipLines[#tipLines + 1] = module.description
    end
    local supported, missing = ns.IsModuleSupported(module.id)
    if not supported then
        tipLines[#tipLines + 1] = string.format(L.STATUS_UNSUPPORTED, ns.FormatMissingAPIs(missing))
    end
    Widgets.SetTooltip(button, module.title, #tipLines > 0 and tipLines or nil)

    local moduleId = module.id
    button:SetScript("OnClick", function()
        ShowPage(moduleId)
    end)
    menuButtons[moduleId] = button
    return button
end

-- 사이드바 구성(생성 시 1회), dik, 2026-09-30
local function BuildSidebar(sidebar)
    local home, settings
    local features, displays = {}, {}
    for _, module in ipairs(ns.GetModules()) do
        if module.id == "home" then
            home = module
        elseif module.id == "settings" then
            settings = module
        elseif module.category == "display" then
            displays[#displays + 1] = module
        else
            features[#features + 1] = module
        end
    end

    local edge = CreateLine(sidebar)
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)

    local bottomArea = Theme.MENU_ITEM_H + 1
    local holder = CreateFrame("Frame", nil, sidebar)
    holder:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    holder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, bottomArea)
    local _, content = Widgets.CreateScrollArea(holder)

    local y = 0
    local function AddButton(module, indent)
        local button = CreateMenuButton(content, module, indent)
        button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        button:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        y = y + Theme.MENU_ITEM_H
    end
    local function AddGroup(headerText, list)
        if #list == 0 then
            return
        end
        local header = Widgets.CreateLabel(content, "FONT_SMALL", "TEXT_DIM")
        header:SetPoint("TOPLEFT", content, "TOPLEFT", Theme.PAD, -y)
        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Theme.PAD, -y)
        header:SetHeight(HEADER_H)
        header:SetText(headerText)
        y = y + HEADER_H
        for _, module in ipairs(list) do
            AddButton(module, CATEGORY_INDENT)
        end
    end

    if home then
        AddButton(home, 0)
    end
    AddGroup(L.CATEGORY_FEATURE, features)
    AddGroup(L.CATEGORY_DISPLAY, displays)
    content:SetHeight(math.max(y, 1))

    if settings then
        local divider = CreateLine(sidebar)
        divider:SetHeight(1)
        divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, Theme.MENU_ITEM_H)
        divider:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, Theme.MENU_ITEM_H)
        local button = CreateMenuButton(sidebar, settings, 0)
        button:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 0)
        button:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)
    end
end

-- 빈 검색 여부, dik, 2026-10-01
local function IsEmptyQuery(text)
    return #ns.Search.Tokenize(text) == 0
end

-- 결과 행 꼬리표 결정, dik, 2026-10-01
local function GetResultTag(item)
    local id = item.moduleId
    if id then
        if not (ns.IsModuleSupported(id)) then
            return L.SEARCH_TAG_UNSUPPORTED
        end
        if not ns.IsModuleEnabled(id) then
            return L.STATUS_DISABLED
        end
    end
    return item.kind == "module" and L.SEARCH_TAG_MODULE or L.SEARCH_TAG_SETTING
end

-- 검색 결과 클릭 이동(R-B6), dik, 2026-10-01
local function GoToResult(item)
    CloseSearchList()
    searchBox:ClearFocus()
    local target = "settings"
    local focus
    if item.kind == "module" then
        if menuButtons[item.moduleId] then
            ShowPage(item.moduleId)
            return
        end
        focus = { moduleId = item.moduleId }
    else
        focus = { scope = item.scope, key = item.key }
        if item.scope ~= "global" and menuButtons[item.scope] then
            local module = ns.GetModule(item.scope)
            if module and not module.CreatePage and (ns.IsModuleSupported(item.scope)) then
                target = item.scope
            end
        end
    end
    ShowPage(target)
    local page = pages[target]
    if page and type(page.FocusTarget) == "function" then
        page:FocusTarget(focus)
    end
end

-- 결과 행 1개 생성, dik, 2026-10-01
local function CreateSearchRow(index)
    local row = CreateFrame("Button", nil, searchList)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(Theme.GetColor("HOVER"))
    row.tag = Widgets.CreateLabel(row, "FONT_SMALL", "TEXT_DIM")
    row.tag:SetPoint("RIGHT", row, "RIGHT", -Theme.GAP, 0)
    row.path = Widgets.CreateLabel(row, "FONT_BODY", "TEXT")
    row.path:SetPoint("LEFT", row, "LEFT", Theme.GAP, 0)
    row.path:SetPoint("RIGHT", row.tag, "LEFT", -Theme.GAP, 0)
    row.path:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.item then
            GoToResult(self.item)
        end
    end)
    searchRows[index] = row
    return row
end

-- 결과 목록 채우기·표시, dik, 2026-10-01
local function UpdateSearchList(text)
    local results, total = ns.Search.Find(text, ns.Search.MAX_RESULTS)
    local count = #results
    local rowH = Theme.MENU_ITEM_H
    for i = 1, count do
        local item = results[i]
        local row = searchRows[i] or CreateSearchRow(i)
        row.item = item
        row.path:SetText(item.kind == "module" and item.title or string.format(L.SEARCH_PATH_FMT, item.group, item.title))
        row.tag:SetText(GetResultTag(item))
        Widgets.SetTooltip(row, item.title, item.body)
        local textH = math.max(row.path:GetStringHeight(), row.tag:GetStringHeight())
        rowH = math.max(rowH, math.ceil(textH) + Theme.GAP)
    end
    local y = 1
    for i, row in ipairs(searchRows) do
        if i <= count then
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", searchList, "TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", searchList, "TOPRIGHT", -1, -y)
            row:Show()
            y = y + rowH
        else
            row.item = nil
            row:Hide()
        end
    end
    searchNone:SetShown(count == 0)
    searchMore:SetShown(count > 0 and total > count)
    local line, lineH
    if count == 0 then
        line = searchNone
        line:SetText(L.SEARCH_NONE)
    elseif total > count then
        line = searchMore
        line:SetText(string.format(L.SEARCH_MORE, total - count))
    end
    if line then
        lineH = math.max(Theme.MENU_ITEM_H, math.ceil(line:GetStringHeight()) + Theme.GAP)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", searchList, "TOPLEFT", Theme.GAP, -y)
        line:SetPoint("TOPRIGHT", searchList, "TOPRIGHT", -Theme.GAP, -y)
        line:SetHeight(lineH)
        y = y + lineH
    end
    searchList:SetHeight(y + 1)
    searchList:Show()
end

-- 기능 검색창·결과 목록 구성, dik, 2026-10-01
local function BuildSearch(bar)
    searchBox = Widgets.CreateSearchBox(bar, {
        placeholder = L.SEARCH_PLACEHOLDER,
        onChange = function(text)
            if IsEmptyQuery(text) then
                CloseSearchList()
            else
                UpdateSearchList(text)
            end
        end,
        onEnterPressed = function(text)
            if IsEmptyQuery(text) then
                CloseSearchList()
                return
            end
            local results = ns.Search.Find(text, ns.Search.MAX_RESULTS)
            if results[1] then
                GoToResult(results[1])
            else
                CloseSearchList()
            end
        end,
        onEscapePressed = function()
            CloseSearchList()
        end,
        onFocusChanged = function(hasFocus)
            if hasFocus then
                local text = searchBox:GetText()
                if not IsEmptyQuery(text) then
                    UpdateSearchList(text)
                end
            elseif searchList:IsShown() and not searchList:IsMouseOver() then
                CloseSearchList()
            end
        end,
    })
    searchBox:SetWidth(SEARCH_BOX_W)
    searchBox:SetPoint("RIGHT", moveButton, "LEFT", -Theme.GAP, 0)
    searchBox:SetTooltip(L.SEARCH_TITLE, L.TIP_SEARCH)

    searchList = Widgets.CreatePanel(frame)
    searchList:SetWidth(SEARCH_LIST_W)
    searchList:SetPoint("TOPRIGHT", searchBox, "BOTTOMRIGHT", 0, -2)
    searchList:SetFrameLevel(frame:GetFrameLevel() + SEARCH_LIST_LEVEL)
    searchList:EnableMouse(true)
    searchNone = Widgets.CreateLabel(searchList, "FONT_SMALL", "TEXT_DIM")
    searchMore = Widgets.CreateLabel(searchList, "FONT_SMALL", "TEXT_DIM")
    searchNone:Hide()
    searchMore:Hide()
    searchList:Hide()
end

-- 이동 버튼 글자색 갱신, dik, 2026-10-01
local function UpdateMoveButton(on)
    if not moveButton then
        return
    end
    moveButton.label:SetTextColor(Theme.GetColor(on and "ACCENT" or "TEXT"))
end

-- 타이틀바 구성, dik, 2026-09-30
local function BuildTitleBar()
    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetHeight(Theme.TITLEBAR_H)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    Theme.ApplyBackdrop(bar, "PANEL", "PANEL")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if IsLocked() then
            return
        end
        interacting = true
        frame:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        StopInteraction()
    end)

    local line = CreateLine(bar)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    local name = Widgets.CreateLabel(bar, "FONT_TITLE", "ACCENT")
    name:SetPoint("LEFT", bar, "LEFT", Theme.PAD, 0)
    name:SetText("DikForever")

    local close = CreateFrame("Button", nil, bar)
    close:SetSize(CLOSE_BUTTON_W, Theme.TITLEBAR_H - 1)
    close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    local hover = close:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(Theme.GetColor("HOVER"))
    local mark = Widgets.CreateLabel(close, "FONT_MENU", "TEXT_DIM")
    mark:SetPoint("CENTER", close, "CENTER", 0, 0)
    mark:SetText("X")
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    Widgets.SetTooltip(close, L.TIP_CLOSE_TITLE, L.TIP_CLOSE)

    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    end
    -- versionText 를 블록 밖에서 참조하도록 선언 이동, dik, 2026-10-01
    local versionText
    if version then
        versionText = Widgets.CreateLabel(bar, "FONT_NUMBER", "TEXT_DIM")
        versionText:SetPoint("RIGHT", close, "LEFT", -Theme.GAP, 0)
        versionText:SetText("v" .. version)
    end

    -- 위치 이동 모드 토글 버튼, dik, 2026-10-01
    moveButton = Widgets.CreateButton(bar, L.BUTTON_MOVE_MODE, function()
        ns.Fire("TOGGLE_MOVE_MODE")
    end)
    moveButton.label:SetFontObject(Theme.GetFont("FONT_SMALL"))
    moveButton:SetSize(math.ceil(moveButton.label:GetStringWidth()) + Theme.GAP * 2, MOVE_BUTTON_H)
    if versionText then
        moveButton:SetPoint("RIGHT", versionText, "LEFT", -Theme.GAP, 0)
    else
        moveButton:SetPoint("RIGHT", close, "LEFT", -Theme.GAP, 0)
    end
    UpdateMoveButton(ns.Display and ns.Display.IsMoveMode and ns.Display.IsMoveMode())
    Widgets.SetTooltip(moveButton, L.BUTTON_MOVE_MODE, L.TIP_MOVE_MODE)
    BuildSearch(bar)
end

-- 크기 조절 핸들 생성, dik, 2026-09-30
local function BuildResizeHandle()
    local handle = CreateFrame("Button", nil, frame)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    handle:SetFrameLevel(frame:GetFrameLevel() + 5)
    local dots = {
        { 0, 0 }, { 4, 0 }, { 8, 0 },
        { 0, 4 }, { 4, 4 },
        { 0, 8 },
    }
    for _, offset in ipairs(dots) do
        local dot = handle:CreateTexture(nil, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", -offset[1] - 2, offset[2] + 2)
        dot:SetColorTexture(Theme.GetColor("TEXT_DIM"))
    end
    handle:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or IsLocked() then
            return
        end
        interacting = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    handle:SetScript("OnMouseUp", function()
        StopInteraction()
    end)
    Widgets.SetTooltip(handle, L.TIP_RESIZE_TITLE, L.TIP_RESIZE)
end

-- 메인 프레임 지연 생성, dik, 2026-09-30
local function EnsureFrame()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    Theme.ApplyBackdrop(frame, "BG", "BORDER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(Theme.WINDOW_MIN_W, Theme.WINDOW_MIN_H, Theme.WINDOW_MAX_W, Theme.WINDOW_MAX_H)
    end
    tinsert(UISpecialFrames, FRAME_NAME)
    frame:SetScale(ns.GetSetting("global", "scale") or 1)
    ApplyWindow()

    BuildTitleBar()

    local status = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    status:SetHeight(Theme.STATUSBAR_H)
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Theme.ApplyBackdrop(status, "PANEL", "PANEL")
    local statusLine = CreateLine(status)
    statusLine:SetHeight(1)
    statusLine:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    statusLine:SetPoint("TOPRIGHT", status, "TOPRIGHT", 0, 0)
    statusText = Widgets.CreateLabel(status, "FONT_SMALL", "TEXT_DIM")
    statusText:SetPoint("LEFT", status, "LEFT", Theme.PAD, 0)
    statusText:SetText(string.format(L.HOME_CHARACTER, UnitName("player") or "", GetRealmName() or ""))

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetWidth(Theme.SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(Theme.TITLEBAR_H + 1))
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, Theme.STATUSBAR_H + 1)
    Theme.ApplyBackdrop(sidebar, "PANEL", "PANEL")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, Theme.STATUSBAR_H + 1)

    titleText = Widgets.CreateLabel(content, "FONT_TITLE", "ACCENT")
    titleText:SetPoint("TOPLEFT", content, "TOPLEFT", Theme.PAD, -Theme.PAD)
    titleText:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Theme.PAD, -Theme.PAD)
    local titleLine = CreateLine(content)
    titleLine:SetHeight(1)
    titleLine:SetPoint("TOPLEFT", content, "TOPLEFT", Theme.PAD, -(Theme.PAD + TITLE_LINE_OFFSET))
    titleLine:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Theme.PAD, -(Theme.PAD + TITLE_LINE_OFFSET))

    host = CreateFrame("Frame", nil, content)
    host:SetPoint("TOPLEFT", content, "TOPLEFT", Theme.PAD, -(Theme.PAD + TITLE_LINE_OFFSET + Theme.GAP))
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Theme.PAD, Theme.PAD)

    BuildSidebar(sidebar)
    BuildResizeHandle()

    frame:SetScript("OnShow", function()
        EnsureOnScreen()
        if currentId then
            local module = ns.GetModule(currentId)
            -- 미지원 모듈은 OnPageShow 생략, dik, 2026-09-30
            if module and module.OnPageShow and (ns.IsModuleSupported(currentId)) then
                module:OnPageShow()
            end
        else
            ShowPage(DefaultPageId())
        end
    end)
    frame:SetScript("OnHide", function()
        -- 관리창 닫힐 때 검색 결과 목록 닫기, dik, 2026-10-01
        CloseSearchList()
        StopInteraction()
        local module = currentId and ns.GetModule(currentId)
        -- 미지원 모듈은 OnPageHide 생략, dik, 2026-09-30
        if module and module.OnPageHide and (ns.IsModuleSupported(currentId)) then
            module:OnPageHide()
        end
    end)
    frame:Hide()
    return frame
end

-- 관리창 토글, dik, 2026-09-30
local function Toggle()
    EnsureFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- 관리창 열기(지정 페이지 또는 기본 페이지), dik, 2026-09-30
local function Open(pageId)
    EnsureFrame()
    local target = DefaultPageId()
    if pageId and menuButtons[pageId] then
        target = pageId
    end
    ShowPage(target)
    if not frame:IsShown() then
        frame:Show()
    end
end

ns.MainFrame = {
    Toggle = Toggle,
    Open = Open,
    ShowPage = ShowPage,
}

ns.On("TOGGLE_MAIN", Toggle)
ns.On("OPEN_PAGE", Open)
-- 이동 모드 변경 시 버튼 색 갱신, dik, 2026-10-01
ns.On("HUD_MOVE_MODE", function(on)
    UpdateMoveButton(on == true)
end)
ns.On("WINDOW_RESET", function()
    if frame then
        ApplyWindow()
    end
end)
ns.On("SETTING_CHANGED", function(scope, key, value)
    if scope ~= "global" or not frame then
        return
    end
    if key == "scale" and type(value) == "number" then
        frame:SetScale(value)
    elseif key == "lockWindow" and value == true then
        StopInteraction()
    elseif key == "fontSize" and searchBox then
        -- 글꼴 크기 변경 시 검색창 높이 갱신, dik, 2026-10-01
        searchBox:Refresh()
    end
end)
