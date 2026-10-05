-- 화면 모듈 공통 유틸(스킨 기록·HUD 프레임·이동 모드·정보 텍스트), dik, 2026-10-01
local addonName, ns = ...

local L = ns.L
local Theme = ns.Theme

local Display = {}
ns.Display = Display

local HIDDEN_ALPHA = 0
local FALLBACK_CHANNEL = 1
local OFFSCREEN_MIN_VISIBLE = 50
local HUD_VERSION = 1
local DEFAULT_STRATA = "MEDIUM"
local OVERLAY_BORDER_TOKEN = "ACCENT"
local OVERLAY_BG_TOKEN = "SELECTED"
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local skins = {}
local hooked = {}
local pendingOrder = {}
local pendingFns = {}
local huds = {}
local hudList = {}
local infoItems = {}
local moveOn = false
local dragging
-- 전투당 1회 끌기 거부 안내 플래그, dik, 2026-10-01
local dragCombatNotified = false

-- 정수 반올림, dik, 2026-10-01
local function Round(value)
    return math.floor(value + 0.5)
end

-- 유한 number 판정, dik, 2026-10-01
local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- 전투 중 여부, dik, 2026-10-01
local function IsInCombat()
    if not ns.HasAPI("InCombatLockdown") then
        return false
    end
    return InCombatLockdown() == true
end

-- owner 별 스킨 기록 조회·생성, dik, 2026-10-01
local function GetSkin(owner)
    local skin = skins[owner]
    if not skin then
        skin = { active = false, records = {}, seen = {}, panels = {}, panelMap = {} }
        skins[owner] = skin
    end
    return skin
end

-- 대상별 첫 기록 여부 확인 후 표시, dik, 2026-10-01
local function MarkFirst(skin, kind, target)
    local map = skin.seen[kind]
    if not map then
        map = {}
        skin.seen[kind] = map
    end
    if map[target] then
        return false
    end
    map[target] = true
    return true
end

-- 전역 이름·parentKey 경로 조회, dik, 2026-10-01
function Display.Find(root, ...)
    local current = root
    if type(root) == "string" then
        current = _G[root]
    end
    if type(current) ~= "table" then
        return nil
    end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        current = current[key]
        if type(current) ~= "table" then
            return nil
        end
    end
    return current
end

-- 전투 밖 대기 실행 비우기, dik, 2026-10-01
local function FlushPending()
    local order, fns = pendingOrder, pendingFns
    pendingOrder, pendingFns = {}, {}
    for i = 1, #order do
        local fn = fns[order[i]]
        if fn then
            xpcall(fn, geterrorhandler())
        end
    end
end

-- 전투 밖에서 실행, dik, 2026-10-01
function Display.RunOutOfCombat(key, fn)
    if type(fn) ~= "function" then
        return
    end
    if not IsInCombat() then
        xpcall(fn, geterrorhandler())
        return
    end
    if pendingFns[key] == nil then
        pendingOrder[#pendingOrder + 1] = key
    end
    pendingFns[key] = fn
end

-- 사후 훅 1회 설치, dik, 2026-10-01
function Display.HookAfter(owner, funcName, fn)
    if type(fn) ~= "function" then
        return false
    end
    local byOwner = hooked[owner]
    if byOwner and byOwner[funcName] then
        return true
    end
    if not ns.HasAPI(funcName) or not ns.HasAPI("hooksecurefunc") then
        return false
    end
    if not byOwner then
        byOwner = {}
        hooked[owner] = byOwner
    end
    byOwner[funcName] = true
    hooksecurefunc(funcName, function(...)
        if not Display.IsSkinActive(owner) then
            return
        end
        local args = { ... }
        local n = select("#", ...)
        xpcall(function()
            fn(unpack(args, 1, n))
        end, geterrorhandler())
    end)
    return true
end

-- owner 스킨 활성 표시, dik, 2026-10-01
function Display.BeginSkin(owner)
    GetSkin(owner).active = true
end

-- owner 스킨 활성 여부, dik, 2026-10-01
function Display.IsSkinActive(owner)
    local skin = skins[owner]
    return skin ~= nil and skin.active == true
end

-- 텍스처 숨김(기록형), dik, 2026-10-01
function Display.HideTexture(owner, texture)
    if type(texture) ~= "table" or type(texture.GetVertexColor) ~= "function" then
        return
    end
    local skin = GetSkin(owner)
    local r, g, b, a = texture:GetVertexColor()
    if MarkFirst(skin, "tex", texture) then
        skin.records[#skin.records + 1] = { kind = "tex", target = texture, r = r, g = g, b = b, a = a }
    end
    texture:SetVertexColor(r or FALLBACK_CHANNEL, g or FALLBACK_CHANNEL, b or FALLBACK_CHANNEL, HIDDEN_ALPHA)
end

-- 글자색 변경(기록형), dik, 2026-10-01
function Display.SetTextColor(owner, fontString, colorToken)
    if type(fontString) ~= "table" or type(fontString.GetTextColor) ~= "function" then
        return
    end
    local skin = GetSkin(owner)
    if MarkFirst(skin, "text", fontString) then
        local r, g, b, a = fontString:GetTextColor()
        skin.records[#skin.records + 1] = { kind = "text", target = fontString, r = r, g = g, b = b, a = a }
    end
    fontString:SetTextColor(Theme.GetColor(colorToken))
end

-- 서체 교체(기록형), dik, 2026-10-01
function Display.SetFontFace(owner, target, faceKey)
    if type(target) ~= "table" or type(target.GetFont) ~= "function" then
        return false
    end
    local facePath = Theme[faceKey]
    if type(facePath) ~= "string" then
        return false
    end
    local skin = GetSkin(owner)
    local original = target:GetFont()
    local first = not (skin.seen.font and skin.seen.font[target])
    if not Theme.SetFontFace(target, facePath) then
        return false
    end
    if first and type(original) == "string" then
        MarkFirst(skin, "font", target)
        skin.records[#skin.records + 1] = { kind = "font", target = target, face = original }
    end
    return true
end

-- 자체 배경 패널 부착, dik, 2026-10-01
function Display.AttachPanel(owner, target, bgToken, borderToken, bgAlpha)
    if type(target) ~= "table" then
        return nil
    end
    local skin = GetSkin(owner)
    local panel = skin.panelMap[target]
    if not panel then
        panel = CreateFrame("Frame", nil, target, "BackdropTemplate")
        panel:SetAllPoints(target)
        skin.panelMap[target] = panel
        skin.panels[#skin.panels + 1] = panel
    end
    panel:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1))
    Theme.ApplyBackdrop(panel, bgToken, borderToken, bgAlpha)
    panel:Show()
    return panel
end

-- owner 패널 목록, dik, 2026-10-01
function Display.GetPanels(owner)
    local list = {}
    local skin = skins[owner]
    if skin then
        for i = 1, #skin.panels do
            list[i] = skin.panels[i]
        end
    end
    return list
end

-- 기록 역순 복원, dik, 2026-10-01
function Display.RestoreSkin(owner)
    local skin = skins[owner]
    if not skin then
        return
    end
    for i = #skin.records, 1, -1 do
        local rec = skin.records[i]
        if rec.kind == "tex" then
            rec.target:SetVertexColor(rec.r or FALLBACK_CHANNEL, rec.g or FALLBACK_CHANNEL, rec.b or FALLBACK_CHANNEL, rec.a or FALLBACK_CHANNEL)
        elseif rec.kind == "text" then
            rec.target:SetTextColor(rec.r or FALLBACK_CHANNEL, rec.g or FALLBACK_CHANNEL, rec.b or FALLBACK_CHANNEL, rec.a or FALLBACK_CHANNEL)
        elseif rec.kind == "font" then
            Theme.SetFontFace(rec.target, rec.face)
        end
    end
    for i = 1, #skin.panels do
        skin.panels[i]:Hide()
    end
    skin.records = {}
    skin.seen = {}
    skin.active = false
end

-- HUD 저장 영역 조회, dik, 2026-10-01
local function GetHudData(moduleId)
    local data = ns.GetModuleData(moduleId)
    if type(data) ~= "table" then
        return nil
    end
    return data
end

-- HUD 저장 가능 여부(M5), dik, 2026-10-01
local function CanWriteHud(data)
    if not data or ns.IsDatabaseNewer() then
        return false
    end
    local hud = data.hud
    if type(hud) == "table" and type(hud.version) == "number" and hud.version > HUD_VERSION then
        return false
    end
    return true
end

-- HUD 위치 저장, dik, 2026-10-01
local function WriteHudPosition(info)
    local data = GetHudData(info.moduleId)
    if not CanWriteHud(data) then
        return
    end
    local point, _, relativePoint, x, y = info.frame:GetPoint(1)
    if not point or not IsFinite(x) or not IsFinite(y) then
        return
    end
    if type(data.hud) ~= "table" then
        data.hud = {}
    end
    if data.hud.version == nil then
        data.hud.version = HUD_VERSION
    end
    data.hud[info.key] = { point = point, relativePoint = relativePoint or point, x = Round(x), y = Round(y) }
end

-- HUD 저장 항목 삭제, dik, 2026-10-01
local function ClearHudPosition(info)
    local data = GetHudData(info.moduleId)
    if not CanWriteHud(data) or type(data.hud) ~= "table" then
        return
    end
    data.hud[info.key] = nil
end

-- 기본 위치 적용, dik, 2026-10-01
local function ApplyDefaultPosition(info)
    local opts = info.opts
    local point = opts.point or "CENTER"
    info.frame:ClearAllPoints()
    info.frame:SetPoint(point, UIParent, opts.relativePoint or point, opts.x or 0, opts.y or 0)
end

-- 저장 항목 유효성(M4), dik, 2026-10-01
local function IsValidEntry(entry)
    return type(entry) == "table" and ANCHORS[entry.point] == true and ANCHORS[entry.relativePoint] == true
        and IsFinite(entry.x) and IsFinite(entry.y)
end

-- 화면 밖 판정(가로·세로 50px 미만), dik, 2026-10-01
local function IsOffScreen(frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local pLeft, pRight, pTop, pBottom = UIParent:GetLeft(), UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (left and right and top and bottom and pLeft and pRight and pTop and pBottom) then
        return false
    end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, right, top, bottom = left * ratio, right * ratio, top * ratio, bottom * ratio
    -- 축별 기준을 프레임 크기 절반 이하로 제한, dik, 2026-10-01
    local minX = math.min(OFFSCREEN_MIN_VISIBLE, math.max(0, right - left) / 2)
    local minY = math.min(OFFSCREEN_MIN_VISIBLE, math.max(0, top - bottom) / 2)
    local overlapX = math.min(right, pRight) - math.max(left, pLeft)
    local overlapY = math.min(top, pTop) - math.max(bottom, pBottom)
    return overlapX < minX or overlapY < minY
end

-- 저장 위치 복원, dik, 2026-10-01
local function ApplySaved(info)
    local data = GetHudData(info.moduleId)
    local entry = data and type(data.hud) == "table" and data.hud[info.key] or nil
    if not IsValidEntry(entry) then
        ApplyDefaultPosition(info)
        return
    end
    info.frame:ClearAllPoints()
    info.frame:SetPoint(entry.point, UIParent, entry.relativePoint, entry.x, entry.y)
    if IsOffScreen(info.frame) then
        ApplyDefaultPosition(info)
        ClearHudPosition(info)
    end
end

-- 이동 모드 종료 공통 처리, dik, 2026-10-01
local function EndMoveMode(messageKey)
    if dragging then
        local info = dragging
        dragging = nil
        info.frame:StopMovingOrSizing()
        WriteHudPosition(info)
    end
    moveOn = false
    for i = 1, #hudList do
        local overlay = hudList[i].overlay
        if overlay then
            overlay:Hide()
        end
    end
    ns.Print(L[messageKey])
    ns.Fire("HUD_MOVE_MODE", false)
end

-- 이동 덮개 생성, dik, 2026-10-01
local function CreateOverlay(info)
    local frame = info.frame
    local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 1)
    Theme.ApplyBackdrop(overlay, OVERLAY_BG_TOKEN, OVERLAY_BORDER_TOKEN)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    local name = overlay:CreateFontString(nil, "OVERLAY")
    name:SetFontObject(Theme.GetFont("FONT_SMALL"))
    name:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    name:SetTextColor(Theme.GetColor(OVERLAY_BORDER_TOKEN))
    name:SetText(info.opts.label or info.key)
    overlay.nameText = name
    overlay:SetScript("OnDragStart", function()
        dragging = info
        frame:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function()
        if dragging == info then
            dragging = nil
            frame:StopMovingOrSizing()
            WriteHudPosition(info)
        end
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        -- 오른쪽 클릭을 설정 창 열기 이벤트로 변경, dik, 2026-10-05
        if button == "RightButton" and dragging == nil then
            ns.Fire("HUD_EDIT_OPEN", info.moduleId, info.key)
        end
    end)
    overlay:Hide()
    return overlay
end

-- HUD 직접 끌기 스크립트 설치(1회), dik, 2026-10-01
local function InstallDrag(info)
    if info.dragHooked then
        return
    end
    info.dragHooked = true
    local frame = info.frame
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if not info.dragUnlocked or moveOn or not info.active then
            return
        end
        if IsInCombat() then
            if not dragCombatNotified then
                dragCombatNotified = true
                ns.Print(L.MSG_HUD_DRAG_COMBAT)
            end
            return
        end
        if dragging and dragging ~= info then
            return
        end
        dragging = info
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        if dragging == info then
            dragging = nil
            frame:StopMovingOrSizing()
            WriteHudPosition(info)
        end
    end)
end

-- HUD 프레임 생성, dik, 2026-10-01
function Display.CreateHudFrame(moduleId, key, opts)
    opts = type(opts) == "table" and opts or {}
    local byModule = huds[moduleId]
    if not byModule then
        byModule = {}
        huds[moduleId] = byModule
    end
    if byModule[key] then
        return byModule[key].frame
    end
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetFrameStrata(opts.strata or DEFAULT_STRATA)
    frame:Hide()
    local info = { frame = frame, moduleId = moduleId, key = key, opts = opts, active = false }
    byModule[key] = info
    hudList[#hudList + 1] = info

    frame.SetHudActive = function(_, active)
        info.active = active == true
        if info.active then
            Display.RunOutOfCombat("hud:" .. moduleId .. ":" .. key, function()
                ApplySaved(info)
            end)
            -- 이동 모드 중 재활성 시 덮개 표시, dik, 2026-10-05
            if moveOn then
                if not info.overlay then
                    info.overlay = CreateOverlay(info)
                end
                info.overlay:SetFrameLevel(frame:GetFrameLevel() + 1)
                info.overlay:Show()
            end
        else
            -- 직접 끌기 중단을 덮개 유무와 무관하게 수행, dik, 2026-10-01
            if dragging == info then
                dragging = nil
                frame:StopMovingOrSizing()
            end
        end
        if not info.active and info.overlay then
            info.overlay:Hide()
            -- 남은 이동 대상 없으면 이동 모드 종료, dik, 2026-10-01
            if moveOn then
                local remain = 0
                for i = 1, #hudList do
                    local other = hudList[i]
                    if other.active and other.frame:IsShown() and other.overlay and other.overlay:IsShown() then
                        remain = remain + 1
                    end
                end
                if remain == 0 then
                    EndMoveMode("MSG_MOVE_OFF")
                end
            end
        end
    end
    frame.IsHudActive = function()
        return info.active
    end
    -- 본문 직접 끌기 잠금 전환, dik, 2026-10-01
    frame.SetDragUnlocked = function(_, unlocked)
        local want = unlocked == true
        Display.RunOutOfCombat("hud:drag:" .. moduleId .. ":" .. key, function()
            if frame:IsProtected() == true then
                return
            end
            if want then
                info.dragUnlocked = true
                frame:EnableMouse(true)
                InstallDrag(info)
            else
                info.dragUnlocked = false
                if dragging == info and not moveOn then
                    dragging = nil
                    frame:StopMovingOrSizing()
                    WriteHudPosition(info)
                end
                frame:EnableMouse(false)
            end
        end)
    end
    frame.IsDragUnlocked = function()
        return info.dragUnlocked == true
    end
    frame.ApplySavedPosition = function()
        ApplySaved(info)
    end
    frame.ResetPosition = function()
        ApplyDefaultPosition(info)
        ClearHudPosition(info)
    end
    return frame
end

-- HUD 프레임·표시 이름 조회, dik, 2026-10-05
function Display.GetHud(moduleId, key)
    local byModule = huds[moduleId]
    local info = byModule and byModule[key]
    if not info then
        return nil
    end
    return info.frame, (info.opts.label or key)
end

-- 이동 모드 전환, dik, 2026-10-01
function Display.SetMoveMode(on)
    if on == true then
        if moveOn then
            return false
        end
        if IsInCombat() then
            ns.Print(L.MSG_MOVE_COMBAT)
            return false
        end
        local targets = {}
        for i = 1, #hudList do
            local info = hudList[i]
            if info.active and info.frame:IsShown() then
                targets[#targets + 1] = info
            end
        end
        if #targets == 0 then
            ns.Print(L.MSG_MOVE_NONE)
            return false
        end
        for i = 1, #targets do
            local info = targets[i]
            if not info.overlay then
                info.overlay = CreateOverlay(info)
            end
            info.overlay:SetFrameLevel(info.frame:GetFrameLevel() + 1)
            info.overlay:Show()
        end
        moveOn = true
        ns.Print(L.MSG_MOVE_ON)
        ns.Fire("HUD_MOVE_MODE", true)
        return true
    end
    if not moveOn then
        return false
    end
    EndMoveMode("MSG_MOVE_OFF")
    return true
end

-- 이동 모드 여부, dik, 2026-10-01
function Display.IsMoveMode()
    return moveOn
end

-- 정보 텍스트 요소 생성, dik, 2026-10-01
function Display.CreateInfoText(parent, providerId, owner, onChanged)
    local item = CreateFrame("Frame", nil, parent)
    local text = item:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(Theme.GetFont("FONT_SMALL"))
    text:SetPoint("LEFT", item, "LEFT", 0, 0)
    item.text = text
    item.providerId = providerId
    item.owner = owner
    item.onChanged = onChanged
    item.infoActive = false
    item:Hide()

    item.GetTextWidth = function()
        return math.ceil(text:GetStringWidth())
    end
    item.Refresh = function()
        local value, colorToken = ns.InfoText.GetValue(providerId)
        if value == nil then
            value = L.VALUE_UNKNOWN
            colorToken = "TEXT_DIM"
        end
        -- 값 없음도 이름 붙여 표시("길드 -"), dik, 2026-10-01
        local def = ns.InfoText.GetProvider(providerId)
        if def and def.showLabel ~= false then
            value = L.INFO_ITEM_FMT:format(def.label, value)
        end
        text:SetText(value)
        text:SetTextColor(Theme.GetColor(colorToken or "TEXT_DIM"))
        item:SetSize(math.max(1, math.ceil(text:GetStringWidth())), math.max(1, math.ceil(text:GetStringHeight())))
    end
    item.SetActive = function(_, on)
        if on then
            if not ns.InfoText.Acquire(providerId, owner) then
                item.infoActive = false
                item:Hide()
                return false
            end
            item.infoActive = true
            item:Show()
            item:Refresh()
            return true
        end
        ns.InfoText.Release(providerId, owner)
        item.infoActive = false
        item:Hide()
        return true
    end
    infoItems[#infoItems + 1] = item
    return item
end

-- 이벤트 프레임(전투 시작·종료), dik, 2026-10-01
local eventFrame = CreateFrame("Frame")
for _, eventName in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
end
eventFrame:SetScript("OnEvent", function(_, event)
    -- 전투 안내 플래그 해제·직접 끌기 중단 추가, dik, 2026-10-01
    if event == "PLAYER_REGEN_ENABLED" then
        dragCombatNotified = false
        FlushPending()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if moveOn then
            EndMoveMode("MSG_MOVE_COMBAT_EXIT")
        elseif dragging then
            local info = dragging
            dragging = nil
            info.frame:StopMovingOrSizing()
            WriteHudPosition(info)
        end
    end
end)

ns.On("TOGGLE_MOVE_MODE", function()
    Display.SetMoveMode(not moveOn)
end)

ns.On("INFO_UPDATED", function(id)
    for i = 1, #infoItems do
        local item = infoItems[i]
        if item.infoActive and item.providerId == id then
            item:Refresh()
            if item.onChanged then
                item.onChanged(item)
            end
        end
    end
end)
