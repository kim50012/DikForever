-- 홈 페이지 내장 모듈, dik, 2026-09-30
local addonName, ns = ...

local L = ns.L

local page
local content
local widgets = {}
local moduleRows = {}
local helpLines = {}
local pageCreated = false

-- 텍스트 줄 높이, dik, 2026-09-30
local function GetLineHeight(fontString)
    local h = fontString:GetStringHeight()
    if not h or h < 1 then
        h = 14
    end
    return h
end

-- 재사용 풀에서 라벨 확보, dik, 2026-09-30
local function AcquireLabel(pool, index, fontToken, colorToken)
    local fs = pool[index]
    if not fs then
        fs = ns.Widgets.CreateLabel(content, fontToken, colorToken)
        fs:SetWordWrap(false)
        pool[index] = fs
    end
    return fs
end

-- 모듈 행 확보, dik, 2026-09-30
local function AcquireModuleRow(index)
    local row = moduleRows[index]
    if not row then
        row = {
            name = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT"),
            status = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT"),
        }
        row.name:SetWordWrap(false)
        row.status:SetWordWrap(false)
        -- 줄 툴팁용 투명 프레임, dik, 2026-10-01
        row.hit = CreateFrame("Frame", nil, content)
        row.hit:EnableMouse(true)
        moduleRows[index] = row
    end
    return row
end

-- 목록·도움말 다시 계산, dik, 2026-09-30
local function Refresh()
    if not pageCreated then
        return
    end
    local theme = ns.Theme
    local pad = theme.PAD
    local gap = theme.GAP
    local y = pad

    widgets.title:ClearAllPoints()
    widgets.title:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
    y = y + GetLineHeight(widgets.title) + gap

    if widgets.version:IsShown() then
        widgets.version:ClearAllPoints()
        widgets.version:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
        y = y + GetLineHeight(widgets.version) + gap
    end

    widgets.character:ClearAllPoints()
    widgets.character:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
    y = y + GetLineHeight(widgets.character) + gap * 2

    widgets.modulesHeader:ClearAllPoints()
    widgets.modulesHeader:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
    widgets.modulesHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -pad, -y)
    y = y + widgets.modulesHeader:GetHeight() + gap

    local list = {}
    local all = ns.GetAllModules()
    for i = 1, #all do
        if not all[i].builtin then
            list[#list + 1] = all[i]
        end
    end

    for i = 1, #moduleRows do
        moduleRows[i].name:Hide()
        moduleRows[i].status:Hide()
        moduleRows[i].hit:Hide()
    end
    widgets.noModules:Hide()

    if #list == 0 then
        widgets.noModules:SetText(L.MSG_NO_MODULES)
        widgets.noModules:ClearAllPoints()
        widgets.noModules:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
        widgets.noModules:Show()
        y = y + GetLineHeight(widgets.noModules) + gap
    else
        for i = 1, #list do
            local module = list[i]
            local row = AcquireModuleRow(i)
            local enabled = ns.IsModuleEnabled(module.id)
            row.name:SetText(module.title)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
            row.name:Show()
            -- 상태 우선순위 미지원 > 비활성 > 활성, dik, 2026-09-30
            local supported, missing = ns.IsModuleSupported(module.id)
            local statusTip
            if not supported then
                statusTip = string.format(L.STATUS_UNSUPPORTED, ns.FormatMissingAPIs(missing))
                row.status:SetText(statusTip)
            else
                statusTip = enabled and L.HOME_STATUS_ENABLED_TIP or L.HOME_STATUS_DISABLED_TIP
                row.status:SetText(enabled and L.STATUS_ENABLED or L.STATUS_DISABLED)
            end
            row.status:SetTextColor(theme.GetColor((supported and enabled) and "TEXT" or "TEXT_DIM"))
            row.status:ClearAllPoints()
            row.status:SetPoint("TOPRIGHT", content, "TOPRIGHT", -pad, -y)
            row.status:Show()
            -- 줄 전체 툴팁 연결, dik, 2026-10-01
            local lineH = GetLineHeight(row.name)
            row.hit:ClearAllPoints()
            row.hit:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
            row.hit:SetPoint("TOPRIGHT", content, "TOPRIGHT", -pad, -y)
            row.hit:SetHeight(lineH)
            row.hit:Show()
            local tipLines = {}
            if module.description then
                tipLines[#tipLines + 1] = module.description
            end
            tipLines[#tipLines + 1] = statusTip
            ns.Widgets.SetTooltip(row.hit, module.title, tipLines)
            y = y + lineH + gap
        end
    end

    for i = 1, #helpLines do
        helpLines[i]:Hide()
    end
    widgets.helpHeader:Hide()

    if ns.GetSetting("home", "showHelp") then
        y = y + gap
        widgets.helpHeader:ClearAllPoints()
        widgets.helpHeader:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
        widgets.helpHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -pad, -y)
        widgets.helpHeader:Show()
        y = y + widgets.helpHeader:GetHeight() + gap
        for i = 1, #L.HELP_LINES do
            local fs = AcquireLabel(helpLines, i, "FONT_BODY", "TEXT")
            fs:SetText(L.HELP_LINES[i])
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)
            fs:Show()
            y = y + GetLineHeight(fs) + gap
        end
    end

    content:SetHeight(y + pad)
end

-- 홈 페이지 프레임 생성, dik, 2026-09-30
local function CreateHomePage(_, parent)
    if pageCreated then
        return page
    end
    page = CreateFrame("Frame", nil, parent)
    local _, scrollContent = ns.Widgets.CreateScrollArea(page)
    content = scrollContent

    widgets.title = ns.Widgets.CreateLabel(content, "FONT_TITLE", "ACCENT")
    widgets.title:SetText("DikForever")

    widgets.version = ns.Widgets.CreateLabel(content, "FONT_NUMBER", "TEXT_DIM")
    local version, build
    -- 빌드 해시 표시 추가, dik, 2026-10-03
    if ns.HasAPI("C_AddOns.GetAddOnMetadata") then
        version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        build = C_AddOns.GetAddOnMetadata(addonName, "X-Build")
    end
    if version and version ~= "" then
        if build and build ~= "" then
            widgets.version:SetText(string.format(L.HOME_VERSION_BUILD, version, build))
        else
            widgets.version:SetText(string.format(L.HOME_VERSION, version))
        end
        widgets.version:Show()
    else
        widgets.version:Hide()
    end

    widgets.character = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT")
    widgets.character:SetText(string.format(L.HOME_CHARACTER, UnitName("player") or "", GetRealmName() or ""))

    widgets.modulesHeader = ns.Widgets.CreateSectionHeader(content, L.HOME_MODULES)
    widgets.helpHeader = ns.Widgets.CreateSectionHeader(content, L.HELP_HEADER)
    widgets.noModules = ns.Widgets.CreateLabel(content, "FONT_BODY", "TEXT_DIM")
    widgets.noModules:SetWordWrap(false)

    pageCreated = true
    Refresh()
    return page
end

-- 홈 모듈 등록, dik, 2026-09-30
ns.RegisterModule({
    id = "home",
    title = L.MENU_HOME,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MENU_HOME_DESC,
    builtin = true,
    settings = {
        { key = "showHelp", type = "checkbox", label = L.SETTING_SHOW_HELP,
          tooltip = L.SETTING_SHOW_HELP_TIP, default = true },
    },
    CreatePage = CreateHomePage,
    OnPageShow = function()
        Refresh()
    end,
})

-- 설정 변경 시 홈 갱신, dik, 2026-09-30
ns.On("SETTING_CHANGED", function(scope, key)
    if (scope == "home" and key == "showHelp") or (scope == "global" and key == "fontSize") then
        Refresh()
    end
end)
