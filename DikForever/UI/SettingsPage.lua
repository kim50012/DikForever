-- 설정 페이지 렌더러·게임 설정 카테고리, dik, 2026-09-30
local addonName, ns = ...

local L = ns.L

ns.SettingsUI = {}

local widgetRegistry = {}
local category
local canvasBuilt = false
-- 사유 안내 줄 높이 폴백 상수, dik, 2026-10-01
local NOTE_FALLBACK_H = 14
-- 검색 이동 강조 유지 시간·막대 폭 상수, dik, 2026-10-01
local HIGHLIGHT_SECONDS = 2
local HIGHLIGHT_BAR_W = 2

-- 위젯 레지스트리 등록, dik, 2026-09-30
local function RegisterWidget(scope, key, widget)
    widgetRegistry[scope] = widgetRegistry[scope] or {}
    widgetRegistry[scope][key] = widgetRegistry[scope][key] or {}
    local list = widgetRegistry[scope][key]
    list[#list + 1] = widget
end

-- 선언 한 건의 위젯 생성, dik, 2026-09-30
local function CreateSettingRow(parent, scope, def)
    local widget
    local function GetValue()
        return ns.GetSetting(scope, def.key)
    end
    local function OnChange(value)
        if not ns.SetSetting(scope, def.key, value) then
            widget:Refresh()
        end
    end
    if def.type == "checkbox" then
        widget = ns.Widgets.CreateCheckbox(parent, def, GetValue, OnChange)
    elseif def.type == "slider" then
        widget = ns.Widgets.CreateSlider(parent, def, GetValue, OnChange)
    -- select 설정 타입 분기 추가, dik, 2026-10-01
    elseif def.type == "select" then
        widget = ns.Widgets.CreateSelect(parent, def, GetValue, OnChange)
    else
        return nil
    end
    RegisterWidget(scope, def.key, widget)
    widget:Refresh()
    -- 사용 불가 사유 평가(체크박스 한정), dik, 2026-10-01
    local reason
    if def.type == "checkbox" and type(def.unavailable) == "function" then
        local ok, result = xpcall(def.unavailable, geterrorhandler())
        if ok and type(result) == "string" and result ~= "" then
            reason = result
            widget:SetEnabled(false)
        end
    end
    return widget, reason
end

-- 선언 목록 행 배치, dik, 2026-09-30
-- 줄 위치 기록 인자 rows 추가, dik, 2026-10-01
local function AddDefRows(content, scope, y, indent, rows)
    local theme = ns.Theme
    local defs = ns.GetSettingDefs(scope)
    for i = 1, #defs do
        local row, reason = CreateSettingRow(content, scope, defs[i])
        if row then
            -- 인스턴스별 줄 기록 추가, dik, 2026-10-01
            rows[scope] = rows[scope] or {}
            rows[scope][defs[i].key] = { widget = row, y = y }
            row:SetPoint("TOPLEFT", content, "TOPLEFT", theme.PAD + indent, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -theme.PAD, -y)
            y = y + row:GetHeight() + theme.GAP
            -- 사용 불가 사유 안내 줄 추가, dik, 2026-10-01
            if reason then
                local note = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT_DIM")
                note:SetPoint("TOPLEFT", content, "TOPLEFT", theme.PAD + indent + (row.labelOffset or 0), -y)
                note:SetPoint("TOPRIGHT", content, "TOPRIGHT", -theme.PAD, -y)
                note:SetJustifyH("LEFT")
                note:SetText(reason)
                local h = note:GetStringHeight()
                if not h or h <= 0 then
                    h = NOTE_FALLBACK_H
                end
                y = y + h + theme.GAP
            end
        end
    end
    return y
end

-- 섹션 제목 배치, dik, 2026-09-30
local function AddSectionHeader(content, text, y)
    local theme = ns.Theme
    local header = ns.Widgets.CreateSectionHeader(content, text)
    header:SetPoint("TOPLEFT", content, "TOPLEFT", theme.PAD, -y)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -theme.PAD, -y)
    return y + header:GetHeight() + theme.GAP
end

-- 안내 문구 배치, dik, 2026-09-30
local function AddDimText(content, text, y, indent)
    local theme = ns.Theme
    local fs = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT_DIM")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", theme.PAD + indent, -y)
    fs:SetText(text)
    return y + fs:GetStringHeight() + theme.GAP
end

-- 렌더 프레임에 FocusTarget 부착(스크롤 + 일시 강조), dik, 2026-10-01
local function AttachFocus(frame, scroll, content, rows, headings)
    local theme = ns.Theme
    local hlBg = content:CreateTexture(nil, "BACKGROUND")
    hlBg:SetColorTexture(theme.GetColor("SELECTED"))
    hlBg:Hide()
    local hlBar = content:CreateTexture(nil, "BACKGROUND", nil, 1)
    hlBar:SetColorTexture(theme.GetColor("ACCENT"))
    hlBar:SetWidth(HIGHLIGHT_BAR_W)
    hlBar:Hide()
    local generation = 0

    -- 대상 영역 강조(이전 강조는 옮김), dik, 2026-10-01
    local function Highlight(anchor)
        generation = generation + 1
        local mine = generation
        hlBg:ClearAllPoints()
        hlBg:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        hlBg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        hlBar:ClearAllPoints()
        hlBar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        hlBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        hlBg:Show()
        hlBar:Show()
        C_Timer.After(HIGHLIGHT_SECONDS, function()
            if mine == generation then
                hlBg:Hide()
                hlBar:Hide()
            end
        end)
    end

    -- 스크롤 이동(배치 전이면 1회만 재시도), dik, 2026-10-01
    local function ScrollToY(y)
        local offset = y - theme.GAP
        if scroll:GetHeight() > 0 then
            scroll.ScrollTo(offset)
            return
        end
        C_Timer.After(0, function()
            if scroll:GetHeight() > 0 then
                scroll.ScrollTo(offset)
            else
                scroll.ScrollTo(0)
            end
        end)
    end

    frame.FocusTarget = function(_, target)
        if type(target) ~= "table" then
            return false
        end
        local anchor, y
        if target.scope and target.key then
            local entry = rows[target.scope] and rows[target.scope][target.key]
            if entry then
                anchor, y = entry.widget, entry.y
            end
        elseif target.moduleId then
            local entry = headings[target.moduleId]
            if entry then
                anchor, y = entry.label, entry.y
            end
        end
        if not anchor then
            return false
        end
        ScrollToY(y)
        Highlight(anchor)
        return true
    end
end

-- 전체 설정 렌더러, dik, 2026-09-30
local function RenderAll(parent)
    local theme = ns.Theme
    local frame = CreateFrame("Frame", nil, parent)
    local scroll, content = ns.Widgets.CreateScrollArea(frame)
    local rows, headings = {}, {}
    local y = theme.PAD

    y = AddSectionHeader(content, L.SECTION_GENERAL, y)
    y = AddDefRows(content, "global", y, 0, rows)

    y = y + theme.GAP
    y = AddSectionHeader(content, L.SECTION_MODULES, y)
    local all = ns.GetAllModules()
    local hasExternal = false
    for i = 1, #all do
        local module = all[i]
        if not module.builtin then
            hasExternal = true
        end
        if not module.builtin or #ns.GetSettingDefs(module.id) > 0 then
            local title = ns.Widgets.CreateLabel(content, "FONT_MENU", "TEXT")
            title:SetPoint("TOPLEFT", content, "TOPLEFT", theme.PAD, -y)
            title:SetText(module.title)
            headings[module.id] = { label = title, y = y }
            y = y + title:GetStringHeight() + theme.GAP
            y = AddDefRows(content, module.id, y, theme.PAD, rows)
        end
    end
    if not hasExternal then
        y = AddDimText(content, L.MSG_NO_MODULES, y, 0)
    end

    content:SetHeight(y + theme.PAD)
    AttachFocus(frame, scroll, content, rows, headings)
    return frame
end

-- 한 모듈 설정 렌더러, dik, 2026-09-30
function ns.SettingsUI.RenderModuleSettings(parent, id)
    local theme = ns.Theme
    local frame = CreateFrame("Frame", nil, parent)
    local scroll, content = ns.Widgets.CreateScrollArea(frame)
    local rows = {}
    local y = theme.PAD
    if #ns.GetSettingDefs(id) == 0 then
        y = AddDimText(content, L.MSG_NO_SETTINGS, y, 0)
    else
        y = AddDefRows(content, id, y, 0, rows)
    end
    content:SetHeight(y + theme.PAD)
    AttachFocus(frame, scroll, content, rows, {})
    return frame
end

-- 설정 페이지 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = "settings",
    title = L.MENU_SETTINGS,
    builtin = true,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MENU_SETTINGS_DESC,
    CreatePage = function(_, parent)
        return RenderAll(parent)
    end,
})

-- 설정 변경 시 위젯 갱신, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    local byScope = widgetRegistry[scope]
    local list = byScope and byScope[key]
    if not list then
        return
    end
    for i = 1, #list do
        list[i]:Refresh()
    end
end)

-- 게임 설정 카테고리 등록, dik, 2026-09-30
ns.On("READY", function()
    if canvasBuilt then
        return
    end
    canvasBuilt = true
    local theme = ns.Theme
    local canvas = CreateFrame("Frame")
    local button = ns.Widgets.CreateButton(canvas, L.BUTTON_OPEN_MAIN, function()
        if SettingsPanel then
            HideUIPanel(SettingsPanel)
        end
        ns.Fire("OPEN_PAGE")
    end)
    button:SetPoint("TOPLEFT", canvas, "TOPLEFT", theme.PAD, -theme.PAD)

    local body = RenderAll(canvas)
    body:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -theme.PAD, -theme.GAP)
    body:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(canvas, "DikForever")
        Settings.RegisterAddOnCategory(category)
    end
end)

-- 게임 설정 열기 요청 처리, dik, 2026-09-30
ns.On("OPEN_GAME_SETTINGS", function()
    if InCombatLockdown() then
        ns.Print(L.MSG_COMBAT_OPTIONS)
        ns.Fire("OPEN_PAGE", "settings")
        return
    end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        ns.Fire("OPEN_PAGE", "settings")
    end
end)
