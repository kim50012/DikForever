-- 퀘스트 추적 스킨 화면, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("questTracker")
if not module then
    return
end

local L = ns.L
local QT = ns.QuestTracker

local MODULE_ID = "questTracker"
local HEADER_PANEL_KEY = "questTracker:headerPanels"
local OWNER_HEADER = "questTracker:header"
local OWNER_FONT = "questTracker:font"
local OWNER_COLORS = "questTracker:colors"
local OWNER_BACKGROUND = "questTracker:background"
local OWNERS = { OWNER_HEADER, OWNER_FONT, OWNER_COLORS, OWNER_BACKGROUND }
local TOKEN_NAMES = { "ACCENT", "TEXT", "TEXT_DIM", "DANGER" }

local started = false
local firstEnterDone = false
local noTrackerShown = false
local partialShown = false
local passInstalled = false
local passHalted = false
local root = nil
local eventFrame = nil
local elapsed = 0
local refs = {}
local colorMap = {}
local conflictList = {}
local missingSet = {}
local missingList = {}
local failedFace = {}
local headerPaneled = {}
local headerTexts = {}

-- 없는 요소 기록, dik, 2026-10-01
local function AddMissing(name)
    if type(name) ~= "string" or missingSet[name] then
        return
    end
    missingSet[name] = true
    missingList[#missingList + 1] = name
end

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting(MODULE_ID, key) == true
end

-- 활성 owner 존재 여부, dik, 2026-10-01
local function AnyActive()
    for _, owner in ipairs(OWNERS) do
        if ns.Display.IsSkinActive(owner) then
            return true
        end
    end
    return false
end

-- 명시 보호 프레임 여부, dik, 2026-10-01
local function IsExplicitProtected(frame)
    if type(frame.IsProtected) ~= "function" then
        return false
    end
    local protected, explicit = frame:IsProtected()
    if ns.IsSecret(protected) then
        return true
    end
    return protected == true and (explicit == true or explicit == nil)
end

-- 자체 패널 집합, dik, 2026-10-01
local function BuildPanelSet()
    local set = {}
    for _, owner in ipairs(OWNERS) do
        for _, panel in ipairs(ns.Display.GetPanels(owner)) do
            set[panel] = true
        end
    end
    return set
end

-- 글자 순회 수집, dik, 2026-10-01
local function CollectFontStrings(startFrame)
    local out = {}
    local panelSet = BuildPanelSet()
    local function visit(frame, depth)
        if #out >= QT.MAX_FONTSTRINGS or panelSet[frame] or IsExplicitProtected(frame) then
            return
        end
        if type(frame.GetRegions) == "function" then
            for _, region in ipairs({ frame:GetRegions() }) do
                if #out >= QT.MAX_FONTSTRINGS then
                    return
                end
                if region:GetObjectType() == "FontString" then
                    out[#out + 1] = region
                end
            end
        end
        if depth >= QT.MAX_WALK_DEPTH or type(frame.GetChildren) ~= "function" then
            return
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() then
                visit(child, depth + 1)
            end
        end
    end
    visit(startFrame, 0)
    return out
end

-- 서체 적용(조건부), dik, 2026-10-01
local function ApplyFace(owner, target, faceKey)
    if failedFace[faceKey] or type(target.GetFont) ~= "function" then
        return
    end
    local path, size = target:GetFont()
    if type(size) ~= "number" or QT.SameFace(path, ns.Theme[faceKey]) then
        return
    end
    if not ns.Display.SetFontFace(owner, target, faceKey) then
        failedFace[faceKey] = true
    end
end

-- 글자색 읽기(안전), dik, 2026-10-01
local function ReadTextColor(fontString)
    if type(fontString.GetTextColor) ~= "function" then
        return nil
    end
    local r, g, b = fontString:GetTextColor()
    if ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) then
        return nil
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return r, g, b
end

-- 글자색 적용(조건부), dik, 2026-10-01
local function ApplyColor(owner, fontString, token)
    local r, g, b = ReadTextColor(fontString)
    if not r then
        return
    end
    local tr, tg, tb = ns.Theme.GetColor(token)
    if not QT.ColorEquals(r, g, b, tr, tg, tb) then
        ns.Display.SetTextColor(owner, fontString, token)
    end
end

-- 머리글 수집, dik, 2026-10-01
local function CollectHeaders()
    local list = {}
    local seen = {}
    for _, path in ipairs(QT.HEADER_PATHS) do
        local header = ns.Display.Find(unpack(path))
        if header and not seen[header] and not IsExplicitProtected(header) then
            seen[header] = true
            list[#list + 1] = header
        end
    end
    return list
end

-- 머리글 자체 패널 부착, dik, 2026-10-01
local function AttachHeaderPanels(headers)
    for _, header in ipairs(headers) do
        if not headerPaneled[header] then
            if ns.Display.AttachPanel(OWNER_HEADER, header, "PANEL", "BORDER") then
                headerPaneled[header] = true
            end
        end
    end
end

-- 머리글 스킨 단계, dik, 2026-10-01
local function StyleHeaders()
    local headers = CollectHeaders()
    local texts = {}
    local needPanel = false
    for _, header in ipairs(headers) do
        local text = ns.Display.Find(header, QT.HEADER_TEXT_KEY)
        if text then
            texts[text] = true
            ApplyFace(OWNER_HEADER, text, "FACE_DISPLAY")
            ApplyColor(OWNER_HEADER, text, "ACCENT")
        end
        local bg = ns.Display.Find(header, QT.HEADER_BG_KEY)
        if bg and type(bg.GetVertexColor) == "function" then
            local alpha = select(4, bg:GetVertexColor())
            if not ns.IsSecret(alpha) and type(alpha) == "number" and alpha > 0 then
                ns.Display.HideTexture(OWNER_HEADER, bg)
            end
        end
        if not headerPaneled[header] then
            needPanel = true
        end
    end
    headerTexts = texts
    if needPanel then
        ns.Display.RunOutOfCombat(HEADER_PANEL_KEY, function()
            if started and ns.Display.IsSkinActive(OWNER_HEADER) then
                AttachHeaderPanels(CollectHeaders())
            end
        end)
    end
end

-- 글꼴 객체 단계, dik, 2026-10-01
local function StyleFontObjects()
    for _, name in ipairs(QT.FONT_OBJECTS) do
        local fontObj = ns.Display.Find(name)
        if fontObj then
            ApplyFace(OWNER_FONT, fontObj, "FACE_BODY")
        end
    end
end

-- 글자 순회 단계, dik, 2026-10-01
local function StyleFontStrings(fontOn, colorsOn, headerOn)
    for _, fs in ipairs(CollectFontStrings(root)) do
        if not (headerOn and headerTexts[fs]) then
            if fontOn then
                ApplyFace(OWNER_FONT, fs, "FACE_BODY")
            end
            if colorsOn then
                local r, g, b = ReadTextColor(fs)
                if r then
                    local token = QT.ResolveColor(r, g, b, refs, colorMap)
                    if token then
                        ApplyColor(OWNER_COLORS, fs, token)
                    end
                end
            end
        end
    end
end

-- 점검 1회, dik, 2026-10-01
local function RunPass()
    local headerOn = ns.Display.IsSkinActive(OWNER_HEADER)
    local fontOn = ns.Display.IsSkinActive(OWNER_FONT)
    local colorsOn = ns.Display.IsSkinActive(OWNER_COLORS)
    if headerOn then
        StyleHeaders()
    end
    if fontOn then
        StyleFontObjects()
    end
    if fontOn or colorsOn then
        StyleFontStrings(fontOn, colorsOn, headerOn)
    end
end

-- 주기 점검 설치, dik, 2026-10-01
local function EnsurePass()
    if passInstalled or passHalted or not eventFrame then
        return
    end
    passInstalled = true
    elapsed = 0
    eventFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < QT.PASS_INTERVAL then
            return
        end
        elapsed = 0
        if not started then
            return
        end
        if not AnyActive() then
            eventFrame:SetScript("OnUpdate", nil)
            passInstalled = false
            return
        end
        if root:IsShown() then
            -- 점검 오류 시 세션 동안 중지, dik, 2026-10-01
            local ok = xpcall(RunPass, geterrorhandler())
            if not ok then
                passHalted = true
                eventFrame:SetScript("OnUpdate", nil)
                passInstalled = false
            end
        end
    end)
end

-- 없는 요소 안내, dik, 2026-10-01
local function ReportPartial()
    if partialShown or #missingList == 0 then
        return
    end
    partialShown = true
    ns.Print(L.MSG_QT_PARTIAL:format(ns.FormatMissingAPIs(missingList)))
end

-- 글자색 계획 계산, dik, 2026-10-01
local function PlanColors()
    refs = QT.BuildColorRefs(ns.Display.Find(QT.COLOR_TABLE))
    local tokenColors = {}
    for _, token in ipairs(TOKEN_NAMES) do
        local r, g, b = ns.Theme.GetColor(token)
        tokenColors[token] = { r, g, b, r = r, g = g, b = b }
    end
    local map, conflicts = QT.ValidateColorMap(refs, tokenColors)
    colorMap = map
    conflictList = conflicts
end

-- 부분 첫 적용, dik, 2026-10-01
local function ApplyPart(part)
    if part.id == "header" then
        ns.Display.BeginSkin(OWNER_HEADER)
        if #CollectHeaders() == 0 then
            AddMissing(table.concat(QT.HEADER_PATHS[1], "."))
        end
    elseif part.id == "font" then
        ns.Display.BeginSkin(OWNER_FONT)
    elseif part.id == "colors" then
        if #refs == 0 then
            AddMissing(QT.COLOR_TABLE)
            return
        end
        for _, key in ipairs(conflictList) do
            AddMissing(QT.COLOR_TABLE .. "." .. key)
        end
        ns.Display.BeginSkin(OWNER_COLORS)
    else
        ns.Display.BeginSkin(OWNER_BACKGROUND)
        ns.Display.AttachPanel(OWNER_BACKGROUND, root, "BG", "BORDER", ns.GetSetting(MODULE_ID, "bgAlpha"))
    end
    RunPass()
    EnsurePass()
end

-- 부분 켜기(전투 밖 지연), dik, 2026-10-01
local function EnablePart(part, onDone)
    ns.Display.RunOutOfCombat(part.owner, function()
        if started and IsOn(part.key) then
            -- 적용 오류가 나도 onDone 보장, dik, 2026-10-01
            xpcall(ApplyPart, geterrorhandler(), part)
        end
        if onDone then
            onDone()
        end
    end)
end

-- 추적기 탐색·시작, dik, 2026-10-01
local function TryStart()
    if started then
        return true
    end
    local found = ns.Display.Find(QT.ROOT)
    if not found then
        return false
    end
    root = found
    started = true
    PlanColors()

    local pending = 0
    for _, part in ipairs(QT.PARTS) do
        if IsOn(part.key) then
            pending = pending + 1
        end
    end
    if pending == 0 then
        ReportPartial()
    end
    local function onDone()
        pending = pending - 1
        if pending == 0 then
            ReportPartial()
        end
    end
    for _, part in ipairs(QT.PARTS) do
        if IsOn(part.key) then
            EnablePart(part, onDone)
        end
    end

    eventFrame:UnregisterEvent("ADDON_LOADED")
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    return true
end

-- 이벤트 프레임 생성, dik, 2026-10-01
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if started then
            return
        end
        if event == "ADDON_LOADED" then
            if arg1 == QT.ADDON_TRACKER then
                TryStart()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            TryStart()
            if not started and not firstEnterDone and not noTrackerShown then
                noTrackerShown = true
                ns.Print(L.MSG_QT_NO_TRACKER)
            end
            firstEnterDone = true
        end
    end)
    for _, name in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD" }) do
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, name)
        if not ok then
            AddMissing(name)
        end
    end
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    CreateEventFrame()
    TryStart()
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not started or scope ~= MODULE_ID then
        return
    end
    for _, part in ipairs(QT.PARTS) do
        if part.key == key then
            if value == true then
                EnablePart(part, ReportPartial)
            else
                ns.Display.RestoreSkin(part.owner)
                if part.id == "header" then
                    headerPaneled = {}
                    headerTexts = {}
                end
                ns.Print(L.MSG_SKIN_RESTORED)
            end
            return
        end
    end
    if key == "bgAlpha" and type(value) == "number" then
        for _, panel in ipairs(ns.Display.GetPanels(OWNER_BACKGROUND)) do
            ns.Theme.ApplyBackdrop(panel, "BG", "BORDER", value)
        end
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
