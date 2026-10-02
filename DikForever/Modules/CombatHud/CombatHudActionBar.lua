-- 기본 액션바 외형 스킨, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("combatHud")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme

local BORDER_OUTSET = 1
local PASS_INTERVAL = 0.5
local APPLY_KEY = "combatHud:actionBar"
local NORMAL_KEY = "NormalTexture"

local active = false
local pending = nil
local firstChecked = false
local partialShown = false
local elapsed = 0
local passFrame = nil
local entries = {}
local found = {}
local panelDone = {}

-- 설정 값 조회, dik, 2026-10-01
local function Get(key)
    return ns.GetSetting("combatHud", key)
end

-- 쓰기 가능 여부(전투·차단), dik, 2026-10-01
local function CanWrite()
    if not ns.HasAPI("InCombatLockdown") or InCombatLockdown() == true then
        return false
    end
    local secure = ns.CombatHudSecure
    if not secure or type(secure.CanTouch) ~= "function" or not secure.CanTouch() then
        return false
    end
    if ns.CombatHud.IsBlocked() then
        return false
    end
    return true
end

-- 버튼 하나의 텍스처·서체 대상 수집 후 적용, dik, 2026-10-01
local function ProcessButton(name, btn, entry)
    local owner = ns.CombatHud.ACTION_OWNER
    for _, key in ipairs(ns.CombatHud.ACTION_HIDE_KEYS) do
        local tex = ns.Display.Find(btn, key)
        if not tex and key == NORMAL_KEY then
            tex = ns.Display.Find(name .. NORMAL_KEY)
        end
        if tex and not entry.texSet[tex] then
            entry.texSet[tex] = true
            entry.tex[#entry.tex + 1] = tex
        end
    end
    for _, tex in ipairs(entry.tex) do
        ns.Display.HideTexture(owner, tex)
    end
    for _, key in ipairs(ns.CombatHud.ACTION_FONT_KEYS) do
        local fs = ns.Display.Find(btn, key) or ns.Display.Find(name .. key)
        if fs and not entry.fontSet[fs] then
            entry.fontSet[fs] = true
            entry.fonts[#entry.fonts + 1] = { fs = fs, noRetry = false }
        end
    end
    for _, item in ipairs(entry.fonts) do
        if not item.noRetry and not ns.Display.SetFontFace(owner, item.fs, "FACE_BODY") then
            item.noRetry = true
        end
    end
    local panel = ns.Display.AttachPanel(owner, btn, "BG", "BORDER")
    if panel and not panelDone[btn] then
        panelDone[btn] = true
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", btn, "TOPLEFT", -BORDER_OUTSET, BORDER_OUTSET)
        panel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", BORDER_OUTSET, -BORDER_OUTSET)
    end
end

-- 아직 못 찾은 버튼 탐색·처리, 없는 요소 이름 반환, dik, 2026-10-01
local function ScanButtons()
    local missing = {}
    local hud = ns.CombatHud
    for _, prefix in ipairs(hud.ACTION_BUTTON_PREFIXES) do
        for i = 1, hud.ACTION_BUTTON_COUNT do
            local name = prefix .. i
            if not found[name] then
                local btn = ns.Display.Find(name)
                if btn then
                    found[name] = true
                    local entry = { name = name, btn = btn, tex = {}, texSet = {}, fonts = {}, fontSet = {} }
                    entries[#entries + 1] = entry
                    ProcessButton(name, btn, entry)
                    -- 처음 찾은 버튼만 NormalTexture 부재 안내(B4), dik, 2026-10-01
                    if not firstChecked then
                        firstChecked = true
                        if not (ns.Display.Find(btn, NORMAL_KEY) or ns.Display.Find(name .. NORMAL_KEY)) then
                            missing[#missing + 1] = name .. "." .. NORMAL_KEY
                        end
                    end
                elseif name == "ActionButton1" then
                    missing[#missing + 1] = name
                end
            end
        end
    end
    return missing
end

-- 부분 안내(세션 1회), dik, 2026-10-01
local function ShowPartial(list)
    if partialShown or #list == 0 then
        return
    end
    partialShown = true
    ns.Print(string.format(L.MSG_COMBATHUD_PARTIAL, ns.FormatMissingAPIs(list)))
end

-- 첫 적용 실행 본체, dik, 2026-10-01
local function ApplyNow()
    if not active or Get("skinActionBars") ~= true or not CanWrite() then
        return
    end
    ns.Display.BeginSkin(ns.CombatHud.ACTION_OWNER)
    local missing = ScanButtons()
    -- 이미 찾은 버튼은 전체 재적용, dik, 2026-10-01
    for _, entry in ipairs(entries) do
        ProcessButton(entry.name, entry.btn, entry)
    end
    ShowPartial(missing)
end

-- 스킨 끄기 실행 본체, dik, 2026-10-01
local function DisableNow()
    if Get("skinActionBars") == true then
        return
    end
    ns.Display.RestoreSkin(ns.CombatHud.ACTION_OWNER)
    ns.Print(L.MSG_SKIN_RESTORED)
end

-- 대기 중인 켜기·끄기 실행(가드 통과 시), dik, 2026-10-01
local function TryPending()
    if not pending or not CanWrite() then
        return
    end
    local action = pending
    pending = nil
    if action == "apply" then
        ApplyNow()
    else
        DisableNow()
    end
end

-- 첫 적용 전투 밖 예약, dik, 2026-10-01
local function Apply()
    pending = "apply"
    ns.Display.RunOutOfCombat(APPLY_KEY, TryPending)
end

-- 끄기 전투 밖 예약, dik, 2026-10-01
local function Disable()
    pending = "restore"
    ns.Display.RunOutOfCombat(APPLY_KEY, TryPending)
end

-- 재적용 점검 1회, dik, 2026-10-01
local function RunPass()
    if not active or not CanWrite() then
        return
    end
    if pending then
        TryPending()
        return
    end
    if Get("skinActionBars") ~= true then
        return
    end
    local owner = ns.CombatHud.ACTION_OWNER
    if not ns.Display.IsSkinActive(owner) then
        return
    end
    for _, entry in ipairs(entries) do
        for _, tex in ipairs(entry.tex) do
            local alpha = select(4, tex:GetVertexColor())
            if type(alpha) == "number" and alpha > 0 then
                ns.Display.HideTexture(owner, tex)
            end
        end
        for _, item in ipairs(entry.fonts) do
            if not item.noRetry and item.fs:GetFont() ~= Theme.FACE_BODY then
                if not ns.Display.SetFontFace(owner, item.fs, "FACE_BODY") then
                    item.noRetry = true
                end
            end
        end
    end
    local missing = ScanButtons()
    ShowPartial(missing)
end

-- 점검 프레임 시작, dik, 2026-10-01
local function StartPass()
    if passFrame then
        return
    end
    passFrame = CreateFrame("Frame")
    passFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < PASS_INTERVAL then
            return
        end
        elapsed = 0
        RunPass()
    end)
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled("combatHud") and ns.IsModuleSupported("combatHud")) then
        return
    end
    active = true
    if Get("skinActionBars") == true then
        Apply()
        StartPass()
    end
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active or scope ~= "combatHud" or key ~= "skinActionBars" then
        return
    end
    if value == true then
        Apply()
        StartPass()
    else
        Disable()
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
