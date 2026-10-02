-- 공용 플랫 위젯 모음, dik, 2026-09-30
local addonName, ns = ...

local Theme = ns.Theme
local Widgets = {}
ns.Widgets = Widgets

local SCROLLBAR_W = 6
local SCROLLBAR_THUMB_H = 32
local CHECK_BOX_SIZE = 16
local CHECK_FILL_INSET = 3
local SLIDER_TRACK_H = 4
local SLIDER_THUMB_W = 10
local SLIDER_THUMB_H = 16
local TABLE_FLEX_MIN = 60
local TABLE_LINE_H = 1
-- 진행 바 기본 높이·안쪽 여백 상수 추가, dik, 2026-09-30
local BAR_H = 18
local BAR_INSET = 1
-- 진행 바 색 기본 알파 상수 추가, dik, 2026-09-30
local BAR_DEFAULT_ALPHA = 1
-- 드롭다운 기본 폭·최대 표시 행 상수, dik, 2026-09-30
local DROPDOWN_DEFAULT_W = 120
local DROPDOWN_MAX_VISIBLE = 10
local DROPDOWN_LIST_INSET = 1
-- 선택 설정 위젯 폭·간격 상수, dik, 2026-10-01
local SELECT_W = 180
local SELECT_LABEL_GAP = 4
local SELECT_LABEL_FALLBACK_H = 14

local SEARCH_MAX_LETTERS = 50
-- 비활성 체크박스 알파 상수, dik, 2026-10-01
local DISABLED_ALPHA = 0.4
-- 여러 줄 글상자 기본 높이 상수, dik, 2026-10-02
local TEXTAREA_DEFAULT_H = 90

-- 툴팁 연결, dik, 2026-09-30
local function AttachTooltip(frame, def)
    if not def or not def.tooltip then
        return
    end
    frame:HookScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.label or "", Theme.GetColor("TEXT"))
        local r, g, b = Theme.GetColor("TEXT_DIM")
        GameTooltip:AddLine(def.tooltip, r, g, b, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- 공통 툴팁 설정(대상당 훅 1회, 재호출 시 문구만 갱신), dik, 2026-10-01
function Widgets.SetTooltip(frame, title, body)
    local lines
    if type(body) == "string" then
        lines = { body }
    elseif type(body) == "table" then
        lines = body
    end
    frame.dfTipTitle = title
    frame.dfTipLines = lines
    if frame.dfTipHooked then
        return
    end
    frame.dfTipHooked = true
    frame:HookScript("OnEnter", function(owner)
        local tipTitle, tipLines = owner.dfTipTitle, owner.dfTipLines
        local hasTitle = type(tipTitle) == "string" and tipTitle ~= ""
        local count = tipLines and #tipLines or 0
        if not hasTitle and count == 0 then
            return
        end
        local r, g, b = Theme.GetColor("TEXT")
        local dr, dg, db = Theme.GetColor("TEXT_DIM")
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local first = 1
        if hasTitle then
            GameTooltip:SetText(tipTitle, r, g, b)
        else
            GameTooltip:SetText(tipLines[1], r, g, b, nil, true)
            first = 2
        end
        for i = first, count do
            GameTooltip:AddLine(tipLines[i], dr, dg, db, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- 오버 덮개 생성, dik, 2026-09-30
local function CreateHoverOverlay(frame)
    local tex = frame:CreateTexture(nil, "HIGHLIGHT")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(Theme.GetColor("HOVER"))
    return tex
end

-- 패널 생성, dik, 2026-09-30
function Widgets.CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(panel, "BG", "BORDER")
    return panel
end

-- 라벨 생성, dik, 2026-09-30
function Widgets.CreateLabel(parent, fontToken, colorToken)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(Theme.GetFont(fontToken))
    fs:SetTextColor(Theme.GetColor(colorToken))
    fs:SetJustifyH("LEFT")
    return fs
end

-- 버튼 생성, dik, 2026-09-30
function Widgets.CreateButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(btn, "PANEL", "BORDER")
    local label = Widgets.CreateLabel(btn, "FONT_BODY", "TEXT")
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetText(text or "")
    btn.label = label
    btn:SetSize(math.floor(label:GetStringWidth() + Theme.PAD * 2 + 0.5), Theme.MENU_ITEM_H)
    CreateHoverOverlay(btn)
    btn:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        end
    end)
    return btn
end

-- 공통 진행 바 생성(값은 StatusBar 에 그대로 전달), dik, 2026-09-30
function Widgets.CreateBar(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetHeight(opts.height or BAR_H)
    Theme.ApplyBackdrop(bar, "PANEL", "BORDER")

    local secondary = CreateFrame("StatusBar", nil, bar)
    secondary:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_INSET, -BAR_INSET)
    secondary:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
    secondary:SetStatusBarTexture(Theme.TEXTURE_WHITE)
    secondary:SetStatusBarColor(Theme.GetColor(opts.secondaryColorToken or "BAR_SECONDARY"))
    secondary:SetMinMaxValues(0, 1)
    secondary:SetValue(0)
    secondary:Hide()

    local primary = CreateFrame("StatusBar", nil, bar)
    primary:SetFrameLevel(secondary:GetFrameLevel() + 1)
    primary:SetPoint("TOPLEFT", secondary, "TOPLEFT", 0, 0)
    primary:SetPoint("BOTTOMRIGHT", secondary, "BOTTOMRIGHT", 0, 0)
    primary:SetStatusBarTexture(Theme.TEXTURE_WHITE)
    -- readable 바 초기색 보정, dik, 2026-10-02
    if opts.readable == true then
        local r, g, b, a = Theme.GetColor(opts.colorToken or "ACCENT")
        r, g, b = ns.ReadableBarColor(r, g, b)
        primary:SetStatusBarColor(r, g, b, a)
    else
        primary:SetStatusBarColor(Theme.GetColor(opts.colorToken or "ACCENT"))
    end
    primary:SetMinMaxValues(0, 1)
    primary:SetValue(0)

    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(primary:GetFrameLevel() + 1)
    local label = Widgets.CreateLabel(textFrame, opts.fontToken or "FONT_SMALL", opts.textColorToken or "TEXT")
    label:SetPoint("LEFT", textFrame, "LEFT", Theme.GAP, 0)
    label:SetPoint("RIGHT", textFrame, "RIGHT", -Theme.GAP, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetText("")

    -- 값 범위 전달, dik, 2026-09-30
    bar.SetRange = function(_, minValue, maxValue)
        primary:SetMinMaxValues(minValue, maxValue)
        secondary:SetMinMaxValues(minValue, maxValue)
    end

    -- 주 바 값 전달, dik, 2026-09-30
    bar.SetValue = function(_, value)
        primary:SetValue(value)
    end

    -- 보조 바 값 전달, dik, 2026-09-30
    bar.SetSecondaryValue = function(_, value)
        secondary:SetValue(value)
    end

    -- 보조 바 표시 전환, dik, 2026-09-30
    bar.SetSecondaryShown = function(_, shown)
        if shown then
            secondary:Show()
        else
            secondary:Hide()
        end
    end

    -- 바 텍스트 설정, dik, 2026-09-30
    bar.SetText = function(_, text)
        label:SetText(text or "")
    end

    -- 주 바 색 토큰 설정, dik, 2026-09-30
    bar.SetColorToken = function(_, token)
        -- readable 바는 보정색 적용, dik, 2026-10-02
        if opts.readable == true then
            local r, g, b, a = Theme.GetColor(token)
            r, g, b = ns.ReadableBarColor(r, g, b)
            primary:SetStatusBarColor(r, g, b, a)
            return
        end
        primary:SetStatusBarColor(Theme.GetColor(token))
    end

    -- 주 바 색 직접 설정, dik, 2026-09-30
    bar.SetColor = function(_, r, g, b, a)
        -- readable 바는 보정색 적용, dik, 2026-10-02
        if opts.readable == true then
            r, g, b = ns.ReadableBarColor(r, g, b)
        end
        -- 기본 알파를 상수로 교체, dik, 2026-09-30
        primary:SetStatusBarColor(r, g, b, a or BAR_DEFAULT_ALPHA)
    end

    return bar
end

-- 체크박스 생성, dik, 2026-09-30
function Widgets.CreateCheckbox(parent, def, getValue, onChange)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetHeight(24)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetSize(CHECK_BOX_SIZE, CHECK_BOX_SIZE)
    box:SetPoint("LEFT", frame, "LEFT", 0, 0)
    Theme.ApplyBackdrop(box, "PANEL", "BORDER")

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", CHECK_FILL_INSET, -CHECK_FILL_INSET)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_FILL_INSET, CHECK_FILL_INSET)
    fill:SetColorTexture(Theme.GetColor("ACCENT"))
    fill:Hide()

    local label = Widgets.CreateLabel(frame, "FONT_BODY", "TEXT")
    label:SetPoint("LEFT", box, "RIGHT", Theme.GAP, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    label:SetText(def.label or "")

    CreateHoverOverlay(frame)
    AttachTooltip(frame, def)

    -- 현재값으로 다시 그리기, dik, 2026-09-30
    frame.Refresh = function()
        fill:SetShown(getValue() and true or false)
    end

    frame:SetScript("OnClick", function(self)
        local newValue = not getValue()
        if onChange then
            onChange(newValue)
        end
        self:Refresh()
    end)

    -- 활성·비활성 전환과 글자 시작 오프셋 노출, dik, 2026-10-01
    frame.labelOffset = CHECK_BOX_SIZE + Theme.GAP
    frame.SetEnabled = function(self, on)
        if on == false then
            self:Disable()
            self:SetAlpha(DISABLED_ALPHA)
        else
            self:Enable()
            self:SetAlpha(1)
        end
    end

    frame:Refresh()
    return frame
end

-- step 의 소수 자릿수 계산, dik, 2026-09-30
local function CountDecimals(step)
    local d = 0
    while d < 6 do
        local scaled = step * 10 ^ d
        if math.abs(scaled - math.floor(scaled + 0.5)) < 1e-6 then
            break
        end
        d = d + 1
    end
    return d
end

-- 슬라이더 생성, dik, 2026-09-30
function Widgets.CreateSlider(parent, def, getValue, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(44)

    local step = def.step or 1
    local decimals = CountDecimals(step)
    local fmt = "%." .. decimals .. "f"

    local label = Widgets.CreateLabel(frame, "FONT_BODY", "TEXT")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    label:SetText(def.label or "")

    local valueText = Widgets.CreateLabel(frame, "FONT_NUMBER", "ACCENT")
    valueText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    valueText:SetJustifyH("RIGHT")

    -- 라벨 영역 툴팁 수신, dik, 2026-10-01
    frame:EnableMouse(true)

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    slider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 4)
    slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 4)
    slider:SetHeight(SLIDER_THUMB_H)
    slider:SetMinMaxValues(def.min, def.max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(SLIDER_TRACK_H)
    track:SetColorTexture(Theme.GetColor("BORDER"))

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(Theme.GetColor("ACCENT"))
    thumb:SetSize(SLIDER_THUMB_W, SLIDER_THUMB_H)
    slider:SetThumbTexture(thumb)

    local guard = false
    local dragging = false
    local committed

    -- 현재 슬라이더 값 읽기, dik, 2026-09-30
    local function CurrentValue()
        return tonumber(string.format(fmt, slider:GetValue()))
    end

    -- 값 확정 통지, dik, 2026-09-30
    local function Commit()
        local v = CurrentValue()
        if v ~= committed then
            committed = v
            if onChange then
                onChange(v)
            end
        end
    end

    slider:SetScript("OnValueChanged", function(_, value, userInput)
        valueText:SetText(string.format(fmt, value))
        if guard then
            return
        end
        if userInput and not dragging then
            Commit()
        end
    end)
    slider:SetScript("OnMouseDown", function()
        dragging = true
    end)
    slider:SetScript("OnMouseUp", function()
        dragging = false
        Commit()
    end)
    slider:SetScript("OnHide", function()
        dragging = false
    end)

    AttachTooltip(frame, def)
    AttachTooltip(slider, def)

    -- 현재값으로 다시 그리기, dik, 2026-09-30
    frame.Refresh = function()
        local v = tonumber(getValue()) or def.min
        guard = true
        slider:SetValue(v)
        guard = false
        committed = CurrentValue()
        valueText:SetText(string.format(fmt, v))
    end

    frame:Refresh()
    return frame
end

-- 섹션 머리글 생성, dik, 2026-09-30
function Widgets.CreateSectionHeader(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(28)
    local title = Widgets.CreateLabel(frame, "FONT_MENU", "ACCENT")
    title:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 5)
    title:SetText(text or "")
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(Theme.GetColor("BORDER"))
    return frame
end

-- 스크롤 영역 생성, dik, 2026-09-30
function Widgets.CreateScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetAllPoints(parent)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 5)
    local barTrack = bar:CreateTexture(nil, "BACKGROUND")
    barTrack:SetAllPoints(bar)
    barTrack:SetColorTexture(Theme.GetColor("PANEL"))
    local barThumb = bar:CreateTexture(nil, "OVERLAY")
    barThumb:SetColorTexture(Theme.GetColor("BORDER"))
    barThumb:SetSize(SCROLLBAR_W, SCROLLBAR_THUMB_H)
    bar:SetThumbTexture(barThumb)
    bar:Hide()

    local guard = false

    -- 스크롤 위치 설정, dik, 2026-09-30
    local function SetOffset(offset)
        scroll:SetVerticalScroll(offset)
        guard = true
        bar:SetValue(offset)
        guard = false
    end

    -- 최대 스크롤 계산, dik, 2026-09-30
    local function GetMaxScroll()
        return math.max(0, content:GetHeight() - scroll:GetHeight())
    end

    -- 스크롤바·콘텐츠 폭 갱신, dik, 2026-09-30
    local function UpdateLayout()
        local maxScroll = GetMaxScroll()
        guard = true
        bar:SetMinMaxValues(0, maxScroll)
        guard = false
        local width = scroll:GetWidth()
        if maxScroll > 0 then
            bar:Show()
            width = width - Theme.GAP
        else
            bar:Hide()
        end
        if width > 0 and math.abs(content:GetWidth() - width) > 0.01 then
            content:SetWidth(width)
        end
        SetOffset(math.min(scroll:GetVerticalScroll(), maxScroll))
    end

    scroll:SetScript("OnSizeChanged", UpdateLayout)
    content:SetScript("OnSizeChanged", UpdateLayout)
    scroll.UpdateLayout = UpdateLayout

    -- 지정 위치로 스크롤(0~최대로 자름), dik, 2026-10-01
    scroll.ScrollTo = function(offset)
        local target = tonumber(offset) or 0
        SetOffset(math.max(0, math.min(GetMaxScroll(), target)))
    end

    scroll:SetScript("OnMouseWheel", function(_, delta)
        local target = scroll:GetVerticalScroll() - delta * Theme.MENU_ITEM_H * 2
        SetOffset(math.max(0, math.min(GetMaxScroll(), target)))
    end)

    bar:SetScript("OnValueChanged", function(_, value)
        if not guard then
            scroll:SetVerticalScroll(value)
        end
    end)

    return scroll, content
end

-- 정렬값 추출, dik, 2026-09-30
local function GetSortValue(row, key)
    local cell = row.cells and row.cells[key]
    local v = cell and cell.sortValue
    if v ~= v then
        return nil
    end
    return v
end

-- 정렬값 타입 순위, dik, 2026-09-30
local function TypeRank(v)
    local t = type(v)
    if t == "number" then
        return 1
    elseif t == "string" then
        return 2
    end
    return 3
end

-- 정렬 비교자 생성, dik, 2026-09-30
local function MakeComparator(key, asc)
    return function(a, b)
        local va, vb = GetSortValue(a, key), GetSortValue(b, key)
        if va ~= nil and vb ~= nil then
            local ra, rb = TypeRank(va), TypeRank(vb)
            if ra ~= rb then
                return ra < rb
            end
            if ra == 3 then
                va, vb = tostring(va), tostring(vb)
            end
            if va ~= vb then
                if asc then
                    return va < vb
                end
                return va > vb
            end
        elseif va ~= nil then
            return true
        elseif vb ~= nil then
            return false
        end
        return tostring(a.id) < tostring(b.id)
    end
end

-- 글꼴 높이 보정 행 높이, dik, 2026-09-30
local function FitHeight(baseH, fontToken)
    local _, size = Theme.GetFont(fontToken):GetFont()
    if type(size) ~= "number" then
        return baseH
    end
    return math.max(baseH, math.ceil(size) + Theme.GAP)
end

-- 공통 표 위젯 생성, dik, 2026-09-30
function Widgets.CreateTable(parent, columns, opts)
    opts = opts or {}
    local L = ns.L or {}
    local baseH = opts.rowHeight or Theme.MENU_ITEM_H
    local rowH, headerH = baseH, baseH
    local sortKey, sortAsc = nil, true
    local selectedId = nil
    local rows, sorted = {}, {}
    local rowFrames = {}
    local headerCells = {}

    local tbl = CreateFrame("Frame", nil, parent)

    local header = CreateFrame("Frame", nil, tbl)
    header:SetPoint("TOPLEFT", tbl, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", tbl, "TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(Theme.GetColor("PANEL"))
    local headerLine = header:CreateTexture(nil, "BORDER")
    headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(TABLE_LINE_H)
    headerLine:SetColorTexture(Theme.GetColor("BORDER"))
    tbl.header = header

    local body = CreateFrame("Frame", nil, tbl)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", tbl, "BOTTOMRIGHT", 0, 0)
    local scroll, content = Widgets.CreateScrollArea(body)
    tbl.scroll = scroll

    local emptyLabel = Widgets.CreateLabel(body, "FONT_BODY", "TEXT_DIM")
    emptyLabel:SetPoint("CENTER", body, "CENTER", 0, 0)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:Hide()

    -- 열 키 존재 확인, dik, 2026-09-30
    local function HasColumn(key)
        for _, col in ipairs(columns) do
            if col.key == key then
                return true
            end
        end
        return false
    end

    -- 정렬 배열 재구성, dik, 2026-09-30
    local function ApplySort()
        sorted = {}
        for i, row in ipairs(rows) do
            sorted[i] = row
        end
        if sortKey then
            table.sort(sorted, MakeComparator(sortKey, sortAsc))
        end
    end

    -- 열 x·폭 계산, dik, 2026-09-30
    local function ComputeLayout(bodyW)
        local fixedSum, hasFlex = 0, false
        for _, col in ipairs(columns) do
            if col.flex then
                hasFlex = true
            else
                fixedSum = fixedSum + (col.width or 0)
            end
        end
        local flexW = math.max(TABLE_FLEX_MIN, bodyW - fixedSum)
        local total = fixedSum + (hasFlex and TABLE_FLEX_MIN or 0)
        local xs, ws = {}, {}
        local x = 0
        for i, col in ipairs(columns) do
            local w = col.flex and flexW or (col.width or 0)
            xs[i], ws[i] = x, w
            x = x + w
        end
        return xs, ws, total > bodyW
    end

    -- 행 프레임 생성, dik, 2026-09-30
    local function CreateRowFrame(index)
        local rf = CreateFrame("Button", nil, content)
        rf:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        CreateHoverOverlay(rf)
        local sel = rf:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints(rf)
        sel:SetColorTexture(Theme.GetColor("SELECTED"))
        sel:Hide()
        rf.selected = sel
        rf.fields = {}
        for i, col in ipairs(columns) do
            local fs = Widgets.CreateLabel(rf, "FONT_BODY", "TEXT")
            fs:SetWordWrap(false)
            fs:SetJustifyH(col.align or "LEFT")
            rf.fields[i] = fs
        end
        rf:SetScript("OnClick", function(self, button)
            if opts.onRowClick and self.row then
                opts.onRowClick(self.row, button)
            end
        end)
        rf:SetScript("OnEnter", function(self)
            if opts.onRowEnter and self.row then
                opts.onRowEnter(self, self.row)
            end
        end)
        rf:SetScript("OnLeave", function(self)
            if opts.onRowLeave and self.row then
                opts.onRowLeave(self, self.row)
            end
        end)
        rowFrames[index] = rf
        return rf
    end

    -- 헤더 셀 갱신, dik, 2026-09-30
    local function LayoutHeader(xs, ws)
        header:SetHeight(headerH)
        for i, col in ipairs(columns) do
            local cell = headerCells[i]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", header, "TOPLEFT", xs[i], 0)
            cell:SetSize(math.max(ws[i], 1), headerH)
            cell.title:ClearAllPoints()
            cell.title:SetPoint("LEFT", cell, "LEFT", 0, 0)
            cell.title:SetWidth(math.max(ws[i] - Theme.GAP, 1))
            local text = col.title or ""
            if col.key == sortKey then
                text = text .. (sortAsc and (L.TABLE_SORT_ASC or "") or (L.TABLE_SORT_DESC or ""))
                cell.title:SetTextColor(Theme.GetColor("ACCENT"))
            else
                cell.title:SetTextColor(Theme.GetColor("TEXT_DIM"))
            end
            cell.title:SetText(text)
        end
    end

    -- 전체 다시 그리기, dik, 2026-09-30
    local function Redraw()
        rowH = FitHeight(baseH, "FONT_BODY")
        headerH = FitHeight(baseH, "FONT_SMALL")
        header:SetHeight(headerH)
        local count = #sorted
        local totalH = count * rowH
        content:SetHeight(math.max(totalH, 1))
        scroll.UpdateLayout()

        local bodyW = scroll:GetWidth()
        if totalH > scroll:GetHeight() then
            bodyW = bodyW - Theme.GAP
        end
        if not bodyW or bodyW <= 0 then
            return
        end
        local xs, ws, overflow = ComputeLayout(bodyW)
        if overflow and tbl.SetClipsChildren then
            tbl:SetClipsChildren(true)
        end
        LayoutHeader(xs, ws)

        for i = 1, count do
            local rf = rowFrames[i] or CreateRowFrame(i)
            local row = sorted[i]
            rf.row = row
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowH)
            rf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * rowH)
            rf:SetHeight(rowH)
            rf.selected:SetShown(selectedId ~= nil and row.id == selectedId)
            for c, col in ipairs(columns) do
                local fs = rf.fields[c]
                local cell = row.cells and row.cells[col.key]
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", rf, "LEFT", xs[c], 0)
                fs:SetWidth(math.max(ws[c] - Theme.GAP, 1))
                local color = cell and cell.color
                if type(color) == "table" then
                    fs:SetTextColor(color.r, color.g, color.b)
                else
                    fs:SetTextColor(Theme.GetColor((cell and cell.colorToken) or "TEXT"))
                end
                fs:SetText((cell and cell.text) or "")
            end
            rf:Show()
        end
        for i = count + 1, #rowFrames do
            rowFrames[i].row = nil
            rowFrames[i]:Hide()
        end

        if count == 0 and opts.emptyText then
            emptyLabel:SetText(opts.emptyText)
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end
    end

    for i, col in ipairs(columns) do
        local cell = CreateFrame("Button", nil, header)
        local title = Widgets.CreateLabel(cell, "FONT_SMALL", "TEXT_DIM")
        title:SetWordWrap(false)
        title:SetJustifyH(col.align or "LEFT")
        cell.title = title
        if col.sortable ~= false then
            CreateHoverOverlay(cell)
            cell:SetScript("OnClick", function()
                if sortKey == col.key then
                    sortAsc = not sortAsc
                else
                    sortKey = col.key
                    sortAsc = col.defaultAsc ~= false
                end
                ApplySort()
                Redraw()
                if opts.onSortChanged then
                    opts.onSortChanged(sortKey, sortAsc)
                end
            end)
        end
        headerCells[i] = cell
    end

    -- 행 목록 설정, dik, 2026-09-30
    tbl.SetRows = function(_, newRows)
        rows = {}
        local found = false
        for i, row in ipairs(newRows or {}) do
            rows[i] = row
            if selectedId ~= nil and row.id == selectedId then
                found = true
            end
        end
        if not found then
            selectedId = nil
        end
        ApplySort()
        Redraw()
    end

    -- 정렬 상태 설정, dik, 2026-09-30
    tbl.SetSort = function(_, key, asc)
        if key ~= nil and HasColumn(key) then
            sortKey = key
            sortAsc = asc and true or false
        else
            sortKey = nil
            sortAsc = true
        end
        ApplySort()
        Redraw()
    end

    -- 정렬 상태 조회, dik, 2026-09-30
    tbl.GetSort = function()
        return sortKey, sortAsc
    end

    -- 선택 id 설정, dik, 2026-09-30
    tbl.SetSelectedId = function(_, id)
        selectedId = id
        Redraw()
    end

    -- 선택 id 조회, dik, 2026-09-30
    tbl.GetSelectedId = function()
        return selectedId
    end

    -- 전체 재배치, dik, 2026-09-30
    tbl.Refresh = function()
        Redraw()
    end

    tbl:SetScript("OnSizeChanged", function()
        Redraw()
    end)

    Redraw()
    return tbl
end

local openDropdown = nil
local dropdownEventFrame = nil

-- 드롭다운 바깥 클릭 감시 프레임 준비, dik, 2026-09-30
local function EnsureDropdownEvents()
    if dropdownEventFrame then
        return
    end
    dropdownEventFrame = CreateFrame("Frame")
    dropdownEventFrame:SetScript("OnEvent", function()
        local dd = openDropdown
        if not dd or not dd.list or not dd.IsMouseOver or not dd.list.IsMouseOver then
            return
        end
        if not dd:IsMouseOver() and not dd.list:IsMouseOver() then
            dd:Close()
        end
    end)
    pcall(dropdownEventFrame.RegisterEvent, dropdownEventFrame, "GLOBAL_MOUSE_DOWN")
end

-- 공통 드롭다운 위젯 생성, dik, 2026-09-30
function Widgets.CreateDropdown(parent, opts)
    opts = opts or {}
    local L = ns.L or {}
    local maxVisible = math.max(opts.maxVisible or DROPDOWN_MAX_VISIBLE, 1)
    local items = {}
    local selectedIndex = nil
    local enabled = true
    local list, listScroll, listContent
    local rowFrames = {}

    EnsureDropdownEvents()

    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(dd, "PANEL", "BORDER")
    dd:SetWidth(opts.width or DROPDOWN_DEFAULT_W)
    dd:SetHeight(FitHeight(Theme.MENU_ITEM_H, "FONT_BODY"))
    CreateHoverOverlay(dd)

    local arrow = Widgets.CreateLabel(dd, "FONT_SMALL", "TEXT_DIM")
    arrow:SetPoint("RIGHT", dd, "RIGHT", -Theme.PAD / 2, 0)
    arrow:SetText(L.DROPDOWN_ARROW or "")

    local label = Widgets.CreateLabel(dd, "FONT_BODY", "TEXT")
    label:SetPoint("LEFT", dd, "LEFT", Theme.PAD / 2, 0)
    label:SetPoint("RIGHT", arrow, "LEFT", -Theme.GAP, 0)
    label:SetWordWrap(false)

    -- 선택 문구·색 갱신, dik, 2026-09-30
    local function UpdateLabel()
        local item = selectedIndex and items[selectedIndex]
        if item then
            label:SetText(item.text or "")
        else
            label:SetText(opts.emptyText or L.VALUE_UNKNOWN or "")
        end
        if enabled and item then
            label:SetTextColor(Theme.GetColor("TEXT"))
        else
            label:SetTextColor(Theme.GetColor("TEXT_DIM"))
        end
    end

    -- 값으로 항목 위치 찾기, dik, 2026-09-30
    local function FindIndex(value)
        if value == nil then
            return nil
        end
        for i, item in ipairs(items) do
            if item.value == value then
                return i
            end
        end
        return nil
    end

    -- 목록 행 배치, dik, 2026-09-30
    local function LayoutList()
        local rowH = dd:GetHeight()
        local count = #items
        listContent:SetHeight(math.max(count * rowH, 1))
        list:SetHeight(math.min(count, maxVisible) * rowH + DROPDOWN_LIST_INSET * 2)
        for i = 1, count do
            local rf = rowFrames[i]
            if not rf then
                rf = CreateFrame("Button", nil, listContent)
                CreateHoverOverlay(rf)
                local sel = rf:CreateTexture(nil, "BACKGROUND")
                sel:SetAllPoints(rf)
                sel:SetColorTexture(Theme.GetColor("SELECTED"))
                sel:Hide()
                rf.selected = sel
                local text = Widgets.CreateLabel(rf, "FONT_BODY", "TEXT")
                text:SetPoint("LEFT", rf, "LEFT", Theme.PAD / 2, 0)
                text:SetPoint("RIGHT", rf, "RIGHT", -Theme.PAD / 2, 0)
                text:SetWordWrap(false)
                rf.text = text
                rf:SetScript("OnClick", function(self)
                    local item = self.item
                    dd:Close()
                    if item and item.value ~= dd:GetValue() then
                        selectedIndex = FindIndex(item.value)
                        UpdateLabel()
                        if opts.onChange then
                            opts.onChange(item.value, item)
                        end
                    end
                end)
                rowFrames[i] = rf
            end
            rf.item = items[i]
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * rowH)
            rf:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", 0, -(i - 1) * rowH)
            rf:SetHeight(rowH)
            rf.text:SetText(items[i].text or "")
            local isSelected = (i == selectedIndex)
            rf.selected:SetShown(isSelected)
            rf.text:SetTextColor(Theme.GetColor(isSelected and "ACCENT" or "TEXT"))
            rf:Show()
        end
        for i = count + 1, #rowFrames do
            rowFrames[i].item = nil
            rowFrames[i]:Hide()
        end
        listScroll.UpdateLayout()
    end

    -- 목록 프레임 생성, dik, 2026-09-30
    local function EnsureList()
        if list then
            return
        end
        list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        Theme.ApplyBackdrop(list, "BG", "BORDER")
        list:SetFrameStrata("DIALOG")
        list:SetClampedToScreen(true)
        list:EnableMouse(true)
        list:Hide()
        local host = CreateFrame("Frame", nil, list)
        host:SetPoint("TOPLEFT", list, "TOPLEFT", DROPDOWN_LIST_INSET, -DROPDOWN_LIST_INSET)
        host:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -DROPDOWN_LIST_INSET, DROPDOWN_LIST_INSET)
        listScroll, listContent = Widgets.CreateScrollArea(host)
        dd.list = list
    end

    -- 항목 교체, dik, 2026-09-30
    dd.SetItems = function(_, newItems, value)
        dd:Close()
        local previous = selectedIndex and items[selectedIndex]
        items = {}
        for i, item in ipairs(newItems or {}) do
            items[i] = item
        end
        local index = FindIndex(value)
        if not index then
            index = FindIndex(previous and previous.value)
        end
        selectedIndex = index or (#items > 0 and 1 or nil)
        UpdateLabel()
    end

    -- 선택 변경, dik, 2026-09-30
    dd.SetValue = function(_, value)
        local index = FindIndex(value)
        if not index then
            return false
        end
        selectedIndex = index
        UpdateLabel()
        return true
    end

    -- 현재 값 조회, dik, 2026-09-30
    dd.GetValue = function()
        local item = selectedIndex and items[selectedIndex]
        if item then
            return item.value
        end
        return nil
    end

    -- 활성 전환, dik, 2026-09-30
    dd.SetEnabled = function(_, value)
        enabled = value and true or false
        if enabled then
            dd:Enable()
        else
            dd:Close()
            dd:Disable()
        end
        UpdateLabel()
    end

    -- 열림 여부, dik, 2026-09-30
    dd.IsOpen = function()
        return list ~= nil and list:IsShown()
    end

    -- 목록 닫기, dik, 2026-09-30
    dd.Close = function()
        if list then
            list:Hide()
        end
        if openDropdown == dd then
            openDropdown = nil
        end
    end

    -- 글꼴 변경 후 재배치, dik, 2026-09-30
    dd.Refresh = function()
        dd:SetHeight(FitHeight(Theme.MENU_ITEM_H, "FONT_BODY"))
        if list then
            LayoutList()
        end
    end

    -- 목록 열기, dik, 2026-09-30
    local function Open()
        if not enabled or #items == 0 then
            return
        end
        if openDropdown and openDropdown ~= dd then
            openDropdown:Close()
        end
        EnsureList()
        list:SetScale(dd:GetEffectiveScale() / UIParent:GetEffectiveScale())
        list:SetWidth(dd:GetWidth())
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1)
        list:Show()
        LayoutList()
        openDropdown = dd
    end

    dd:SetScript("OnClick", function()
        if dd:IsOpen() then
            dd:Close()
        else
            Open()
        end
    end)
    dd:SetScript("OnHide", function()
        dd:Close()
    end)

    dd:SetItems(opts.items, opts.value)
    return dd
end

-- 선택지 조회 지점(동적 확장용), dik, 2026-10-01
local function GetSelectItems(def)
    if type(def.items) == "table" then
        return def.items
    end
    return {}
end

-- 선택 설정 위젯 생성, dik, 2026-10-01
function Widgets.CreateSelect(parent, def, getValue, onChange)
    local frame = CreateFrame("Frame", nil, parent)

    local label = Widgets.CreateLabel(frame, "FONT_BODY", "TEXT")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    label:SetText(def.label or "")

    local dd = Widgets.CreateDropdown(frame, {
        width = SELECT_W,
        items = GetSelectItems(def),
        value = getValue(),
        onChange = function(value)
            if onChange then
                onChange(value)
            end
        end,
    })
    local labelH = label:GetStringHeight()
    if not labelH or labelH == 0 then
        labelH = SELECT_LABEL_FALLBACK_H
    end
    -- 드롭다운 버튼 툴팁 추가, dik, 2026-10-01
    if def.tooltip then
        Widgets.SetTooltip(dd, def.label, def.tooltip)
    end
    dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -SELECT_LABEL_GAP)
    frame:SetHeight(labelH + SELECT_LABEL_GAP + dd:GetHeight())

    -- 라벨 영역 툴팁 수신, dik, 2026-10-01
    frame:EnableMouse(true)
    AttachTooltip(frame, def)

    -- 현재값으로 다시 그리기, dik, 2026-10-01
    frame.Refresh = function()
        if not dd:SetValue(getValue()) then
            dd:SetValue(def.default)
        end
    end

    frame:Refresh()
    return frame
end

-- 공통 검색 입력 위젯 생성, dik, 2026-10-01
function Widgets.CreateSearchBox(parent, opts)
    opts = opts or {}
    local L = ns.L or {}
    local sb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(sb, "PANEL", "BORDER")
    sb:SetHeight(FitHeight(Theme.MENU_ITEM_H, "FONT_BODY"))

    local clearBtn = CreateFrame("Button", nil, sb)
    clearBtn:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -1, -1)
    clearBtn:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -1, 1)
    local clearLabel = Widgets.CreateLabel(clearBtn, "FONT_SMALL", "TEXT_DIM")
    clearLabel:SetPoint("CENTER")
    clearLabel:SetText(L.SEARCH_CLEAR or "")
    clearBtn:Hide()

    local edit = CreateFrame("EditBox", nil, sb)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(false)
    edit:SetMaxLetters(opts.maxLetters or SEARCH_MAX_LETTERS)
    edit:SetFontObject(Theme.GetFont("FONT_BODY"))
    edit:SetTextColor(Theme.GetColor("TEXT"))
    edit:SetPoint("TOPLEFT", sb, "TOPLEFT", Theme.PAD / 2, -1)
    edit:SetPoint("BOTTOMRIGHT", clearBtn, "BOTTOMLEFT", 0, 0)

    local placeholder = Widgets.CreateLabel(sb, "FONT_BODY", "TEXT_DIM")
    placeholder:SetPoint("LEFT", sb, "LEFT", Theme.PAD / 2, 0)
    placeholder:SetPoint("RIGHT", clearBtn, "LEFT", 0, 0)
    placeholder:SetWordWrap(false)
    placeholder:SetText(opts.placeholder or "")

    -- 지우기 버튼 폭 계산, dik, 2026-10-01
    local function FitClearWidth()
        clearBtn:SetWidth(math.ceil(clearLabel:GetStringWidth()) + Theme.PAD)
    end

    -- placeholder·지우기 버튼 표시 갱신, dik, 2026-10-01
    local function UpdateDecor()
        local empty = edit:GetText() == ""
        if empty then
            clearBtn:Hide()
        else
            clearBtn:Show()
        end
        if empty and not edit:HasFocus() then
            placeholder:Show()
        else
            placeholder:Hide()
        end
    end

    edit:SetScript("OnTextChanged", function(_, userInput)
        UpdateDecor()
        if userInput and opts.onChange then
            opts.onChange(edit:GetText())
        end
    end)
    edit:SetScript("OnEditFocusGained", function()
        sb:SetBackdropBorderColor(Theme.GetColor("ACCENT"))
        UpdateDecor()
        -- 포커스 콜백 호출 추가, dik, 2026-10-01
        if opts.onFocusChanged then
            opts.onFocusChanged(true)
        end
    end)
    edit:SetScript("OnEditFocusLost", function()
        sb:SetBackdropBorderColor(Theme.GetColor("BORDER"))
        UpdateDecor()
        if opts.onFocusChanged then
            opts.onFocusChanged(false)
        end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        -- ESC 콜백 호출 추가, dik, 2026-10-01
        if opts.onEscapePressed then
            opts.onEscapePressed()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        -- Enter 콜백 호출 추가, dik, 2026-10-01
        if opts.onEnterPressed then
            opts.onEnterPressed(self:GetText())
        end
    end)
    clearBtn:SetScript("OnClick", function()
        edit:SetText("")
        if opts.onChange then
            opts.onChange("")
        end
        edit:ClearFocus()
    end)

    sb.GetText = function(_)
        return edit:GetText()
    end
    sb.SetText = function(_, text)
        edit:SetText(text or "")
        UpdateDecor()
    end
    sb.ClearFocus = function(_)
        edit:ClearFocus()
    end
    -- 입력창 툴팁·포커스 위임, dik, 2026-10-01
    sb.SetTooltip = function(_, title, body)
        Widgets.SetTooltip(edit, title, body)
    end
    sb.SetFocus = function(_)
        edit:SetFocus()
    end
    sb.Refresh = function(_)
        sb:SetHeight(FitHeight(Theme.MENU_ITEM_H, "FONT_BODY"))
        FitClearWidth()
        UpdateDecor()
    end

    FitClearWidth()
    UpdateDecor()
    return sb
end

-- 여러 줄 글상자 위젯 생성, dik, 2026-10-02
function Widgets.CreateTextArea(parent, opts)
    opts = opts or {}
    local readOnly = opts.readOnly == true
    local stored = ""
    local guard = false

    local area = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(area, "PANEL", "BORDER")
    area:SetHeight(opts.height or TEXTAREA_DEFAULT_H)
    area:EnableMouse(true)

    local scroll = CreateFrame("ScrollFrame", nil, area)
    scroll:SetPoint("TOPLEFT", area, "TOPLEFT", Theme.GAP, -Theme.GAP)
    scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -(Theme.GAP + SCROLLBAR_W), Theme.GAP)
    scroll:EnableMouseWheel(true)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(Theme.GetFont("FONT_BODY"))
    edit:SetTextColor(Theme.GetColor("TEXT"))
    edit:SetWidth(1)
    scroll:SetScrollChild(edit)

    local bar = CreateFrame("Slider", nil, area)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -1)
    bar:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    local barTrack = bar:CreateTexture(nil, "BACKGROUND")
    barTrack:SetAllPoints(bar)
    barTrack:SetColorTexture(Theme.GetColor("PANEL"))
    local barThumb = bar:CreateTexture(nil, "OVERLAY")
    barThumb:SetColorTexture(Theme.GetColor("BORDER"))
    barThumb:SetSize(SCROLLBAR_W, SCROLLBAR_THUMB_H)
    bar:SetThumbTexture(barThumb)
    bar:Hide()

    -- 스크롤 위치 설정(범위 안으로 자름), dik, 2026-10-02
    local function SetOffset(offset)
        local maxScroll = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, offset)))
    end

    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then
            edit:SetWidth(width)
        end
    end)
    scroll:SetScript("OnScrollRangeChanged", function(_, _, yRange)
        guard = true
        bar:SetMinMaxValues(0, yRange or 0)
        guard = false
        bar:SetShown((yRange or 0) > 0)
    end)
    scroll:SetScript("OnVerticalScroll", function(_, offset)
        guard = true
        bar:SetValue(offset)
        guard = false
    end)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        SetOffset(scroll:GetVerticalScroll() - delta * Theme.MENU_ITEM_H * 2)
    end)
    bar:SetScript("OnValueChanged", function(_, value)
        if not guard then
            SetOffset(value)
        end
    end)

    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top = -(y or 0)
        local cur = scroll:GetVerticalScroll()
        local viewH = scroll:GetHeight()
        if top < cur then
            SetOffset(top)
        elseif top + (h or 0) > cur + viewH then
            SetOffset(top + (h or 0) - viewH)
        end
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput and not guard then
            guard = true
            self:SetText(stored)
            guard = false
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        area:SetBackdropBorderColor(Theme.GetColor("ACCENT"))
        if readOnly then
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusLost", function()
        area:SetBackdropBorderColor(Theme.GetColor("BORDER"))
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    area:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)

    -- 글 설정(보관본 갱신), dik, 2026-10-02
    area.SetText = function(_, text)
        stored = type(text) == "string" and text or ""
        guard = true
        edit:SetText(stored)
        guard = false
        scroll:SetVerticalScroll(0)
    end

    -- 글 조회, dik, 2026-10-02
    area.GetText = function()
        if readOnly then
            return stored
        end
        return edit:GetText()
    end

    -- 전체 선택과 포커스, dik, 2026-10-02
    area.SelectAll = function()
        edit:SetFocus()
        edit:HighlightText()
    end

    -- 글 지우기, dik, 2026-10-02
    area.Clear = function(self)
        self:SetText("")
    end

    -- 포커스 해제, dik, 2026-10-02
    area.ClearFocus = function()
        edit:ClearFocus()
    end

    return area
end
