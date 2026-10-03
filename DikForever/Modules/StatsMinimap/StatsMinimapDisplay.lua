-- 능력치 패널·미니맵 스킨 화면, dik, 2026-10-01
-- 미니맵 스킨 코드 제거, dik, 2026-10-03
local addonName, ns = ...

local module = ns.GetModule("statsMinimap")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme

local ROW_H_FALLBACK = 14
local ROW_PAD = 4

local active = false
local statsPartialShown = false
local hudActive = false
local layouting = false
local hud = nil
local title = nil
local rows = nil

-- 설정 값 조회, dik, 2026-10-01
local function Get(key)
    return ns.GetSetting("statsMinimap", key)
end

-- 행 이름 글자 높이 기준 행 높이, dik, 2026-10-01
local function GetRowHeight()
    local h = 0
    if rows and rows[1] then
        h = rows[1].label:GetStringHeight()
    end
    if type(h) ~= "number" or h <= 0 then
        h = ROW_H_FALLBACK
    end
    return math.ceil(h) + ROW_PAD
end

-- 패널 재배치, dik, 2026-10-01
local function Layout()
    if not active or not hud or layouting then
        return
    end
    layouting = true
    local showStats = Get("showStats") == true
    local statsSet = Get("statsSet")
    local visible = {}
    for _, row in ipairs(rows) do
        local want = showStats and ns.StatsMinimap.IsRowVisible(row.def, statsSet)
        if want then
            if not row.on then
                row.supported = row.item:SetActive(true) == true
                row.on = true
            end
        else
            if row.on then
                row.item:SetActive(false)
            end
            row.on = false
        end
        if want and row.supported then
            visible[#visible + 1] = row
        else
            row.label:Hide()
        end
    end

    if #visible == 0 then
        hud:Hide()
        if hudActive then
            hud:SetHudActive(false)
            hudActive = false
        end
        layouting = false
        return
    end

    local rowH = GetRowHeight()
    local pad = Theme.PAD / 2
    local labelWidths = {}
    local valueWidths = {}
    for i, row in ipairs(visible) do
        labelWidths[i] = math.ceil(row.label:GetStringWidth())
        valueWidths[i] = row.item:GetTextWidth()
    end
    local width, height, ys = ns.StatsMinimap.LayoutStats(
        labelWidths, valueWidths, rowH, rowH, Theme.GAP, pad, ns.StatsMinimap.PANEL_MIN_W)

    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", hud, "TOPLEFT", pad, -pad)
    for i, row in ipairs(visible) do
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", hud, "TOPLEFT", pad, ys[i])
        row.label:Show()
        row.item:ClearAllPoints()
        row.item:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -pad, ys[i])
    end
    hud:SetSize(width, height)
    hud:Show()
    if not hudActive then
        hud:SetHudActive(true)
        hudActive = true
    end
    layouting = false
end

-- 능력치 없는 API 안내(세션 1회), dik, 2026-10-01
local function ShowStatsPartial()
    if statsPartialShown then
        return
    end
    local list = {}
    local seen = {}
    for _, def in ipairs(ns.StatsMinimap.STAT_ROWS) do
        local ok, missing = ns.InfoText.IsSupported(def.provider)
        if not ok then
            for _, name in ipairs(missing or {}) do
                if type(name) == "string" and not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
        end
    end
    if #list > 0 then
        statsPartialShown = true
        ns.Print(L.MSG_STATS_PARTIAL:format(ns.FormatMissingAPIs(list)))
    end
end

-- 능력치 패널 구성(1회), dik, 2026-10-01
local function BuildPanel()
    local hs = ns.StatsMinimap.HUD_STATS
    hud = ns.Display.CreateHudFrame("statsMinimap", hs.key, {
        label = L.HUD_LABEL_STATS,
        point = hs.point,
        relativePoint = hs.relativePoint,
        x = hs.x,
        y = hs.y,
        strata = hs.strata,
    })
    Theme.ApplyBackdrop(hud, "BG", "BORDER", Get("statsAlpha"))

    title = hud:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(Theme.GetFont("FONT_SMALL"))
    title:SetTextColor(Theme.GetColor("ACCENT"))
    title:SetText(L.STATS_TITLE)

    rows = {}
    for _, def in ipairs(ns.StatsMinimap.STAT_ROWS) do
        local provider = ns.InfoText.GetProvider(def.provider)
        local label = hud:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(Theme.GetFont("FONT_SMALL"))
        label:SetTextColor(Theme.GetColor("TEXT_DIM"))
        label:SetText(provider and provider.label or L.VALUE_UNKNOWN)
        label:Hide()
        local item = ns.Display.CreateInfoText(hud, def.provider, ns.StatsMinimap.OWNER, Layout)
        rows[#rows + 1] = { def = def, label = label, item = item, on = false, supported = true }
    end
end

-- 패널 켜기 또는 재배치, dik, 2026-10-01
local function SyncPanel()
    if Get("showStats") == true and not hud then
        BuildPanel()
        Layout()
        ShowStatsPartial()
        return
    end
    Layout()
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled("statsMinimap") and ns.IsModuleSupported("statsMinimap")) then
        return
    end
    active = true
    if Get("showStats") == true then
        SyncPanel()
    end
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        -- 글꼴 크기 변경 시 값 크기 갱신, dik, 2026-10-01
        if key == "fontSize" then
            for _, row in ipairs(rows or {}) do
                if row.on and row.supported then
                    row.item:Refresh()
                end
            end
            Layout()
        end
        return
    end
    if scope ~= "statsMinimap" then
        return
    end

    if key == "showStats" or key == "statsSet" then
        SyncPanel()
    elseif key == "statsAlpha" then
        if hud and type(value) == "number" then
            Theme.ApplyBackdrop(hud, "BG", "BORDER", value)
        end
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
