-- 전투 HUD 대상 시전 바, dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("combatHud")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local MODULE_ID = "combatHud"
local CAST_TICK = 0.05
local CAST_POLL = 0.1
local DEFAULT_CAST_W = 240
local DEFAULT_CAST_H = 16
local DEFAULT_SCALE = 1
local DEFAULT_BG_ALPHA = 0.8

local active = false
local hud = nil
local body = nil
local icon = nil
local bar = nil
local nameText = nil
local timeText = nil
local eventFrame = nil
local dirty = true
local pollMode = false
local partialNotified = false
local lastScale = nil
local tickAcc = 0
local pollAcc = 0

-- 숫자 설정 조회, dik, 2026-10-01
local function GetNumber(key, default)
    local value = ns.GetSetting(MODULE_ID, key)
    if type(value) ~= "number" then
        return default
    end
    return value
end

-- 설정 켜짐 여부, dik, 2026-10-01
local function IsOn(key)
    return ns.GetSetting(MODULE_ID, key) == true
end

-- 아이콘 값 사용 가능 여부, dik, 2026-10-01
local function IsUsableIcon(value)
    if ns.IsSecret(value) then
        return true
    end
    if type(value) == "number" then
        return true
    end
    return type(value) == "string" and value ~= ""
end

-- 배율 설정값(0 이하는 기본값), dik, 2026-10-01
local function GetHudScale()
    local scale = GetNumber("hudScale", DEFAULT_SCALE)
    if scale <= 0 then
        return DEFAULT_SCALE
    end
    return scale
end

-- 크기·배율·내부 배치 즉시 적용, dik, 2026-10-01
local function Layout()
    local width = GetNumber("castWidth", DEFAULT_CAST_W)
    local height = GetNumber("castHeight", DEFAULT_CAST_H)
    local scale = GetHudScale()
    local inner = math.max(height - 2, 1)

    hud:SetScale(scale)
    hud:SetSize(width, height)

    icon:ClearAllPoints()
    icon:SetPoint("LEFT", body, "LEFT", 1, 0)
    icon:SetSize(inner, inner)

    bar:ClearAllPoints()
    bar:SetPoint("LEFT", icon, "RIGHT", Theme.GAP / 4, 0)
    bar:SetPoint("RIGHT", body, "RIGHT", -1, 0)
    bar:SetHeight(inner)

    if lastScale ~= scale then
        lastScale = scale
        hud:ApplySavedPosition()
    end
end

-- 글꼴·글자색 적용, dik, 2026-10-01
local function ApplyFonts()
    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    local font = Theme.GetFont("FONT_SMALL_OUTLINE")
    nameText:SetFontObject(font)
    nameText:SetTextColor(Theme.GetColor("TEXT"))
    timeText:SetFontObject(font)
    timeText:SetTextColor(Theme.GetColor("TEXT"))
end

-- 시전 바 채우기, dik, 2026-10-01
local function FillCast()
    local C = ns.CombatHud
    local kind, name, tex, startMS, endMS, notInterruptible = C.ReadCast("target")
    if kind == nil then
        body:Hide()
        return
    end
    local now = GetTime() * 1000
    local minV, maxV, value, mode = C.CastProgress(kind, startMS, endMS, now)
    if mode == "none" then
        body:Hide()
        return
    end
    body:Show()
    bar:SetRange(minV, maxV)
    bar:SetValue(value)
    bar:SetColorToken(C.CastColorToken(notInterruptible))

    local shownName = C.NameText(name)
    if ns.IsSecret(shownName) then
        nameText:SetText(shownName)
    elseif shownName == nil then
        nameText:SetText(L.VALUE_UNKNOWN)
    else
        nameText:SetText(shownName)
    end

    if IsUsableIcon(tex) then
        icon:SetTexture(tex)
        icon:Show()
    else
        icon:Hide()
    end

    local remain = C.CastRemainText(endMS, now)
    if type(remain) == "string" then
        timeText:SetText(remain)
    else
        timeText:SetText("")
    end
end

-- 이벤트 처리(arg1 은 secret 검사 후 비교), dik, 2026-10-01
local function OnEvent(_, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        dirty = true
        return
    end
    if not ns.IsSecret(arg1) and arg1 == "target" then
        dirty = true
    end
end

-- 갱신 주기 처리, dik, 2026-10-01
local function OnUpdate(_, elapsed)
    if not active then
        return
    end
    if dirty then
        dirty = false
        tickAcc = 0
        FillCast()
        return
    end
    if body:IsShown() then
        tickAcc = tickAcc + elapsed
        if tickAcc >= CAST_TICK then
            tickAcc = 0
            FillCast()
        end
    elseif pollMode then
        pollAcc = pollAcc + elapsed
        if pollAcc >= CAST_POLL then
            pollAcc = 0
            FillCast()
        end
    end
end

-- 이벤트 등록 헬퍼(성공 수·실패 이름 반환), dik, 2026-10-01
local function RegisterEvents(frame, names)
    local ok = 0
    local failed = {}
    for i = 1, #names do
        if pcall(frame.RegisterEvent, frame, names[i]) then
            ok = ok + 1
        else
            failed[#failed + 1] = names[i]
        end
    end
    return ok, failed
end

-- 이벤트 프레임 생성·등록, dik, 2026-10-01
local function CreateEventFrame()
    local C = ns.CombatHud
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)

    local coreOk, coreFailed = RegisterEvents(eventFrame, C.CAST_EVENTS)
    local _, otherFailed = RegisterEvents(eventFrame, { "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" })
    RegisterEvents(eventFrame, C.CAST_EVENTS_OPTIONAL)

    for i = 1, #otherFailed do
        coreFailed[#coreFailed + 1] = otherFailed[i]
    end
    pollMode = coreOk == 0
    if #coreFailed > 0 and not partialNotified then
        partialNotified = true
        ns.Print(L.MSG_COMBATHUD_PARTIAL:format(ns.FormatMissingAPIs(coreFailed)))
    end
end

-- 창·본문·아이콘·막대·글자 생성, dik, 2026-10-01
local function BuildCastBar()
    local C = ns.CombatHud
    local opts = C.HUD_CAST_WIDE
    if C.ResolveTargetStyle(ns.GetSetting(MODULE_ID, "targetStyle")) == "classic" then
        opts = C.HUD_CAST_CLASSIC
    end
    hud = ns.Display.CreateHudFrame(MODULE_ID, "targetCast", opts)

    body = CreateFrame("Frame", nil, hud, "BackdropTemplate")
    body:SetAllPoints(hud)
    Theme.ApplyBackdrop(body, "BG", "BORDER", GetNumber("bgAlpha", DEFAULT_BG_ALPHA))

    icon = body:CreateTexture(nil, "ARTWORK")
    -- 바 위 글자 외곽선·밝은 바 보정, dik, 2026-10-02
    bar = Widgets.CreateBar(body, { readable = true })

    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 4)

    timeText = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    timeText:SetJustifyH("RIGHT")
    timeText:SetWordWrap(false)
    timeText:SetPoint("RIGHT", overlay, "RIGHT", -Theme.GAP / 2, 0)

    nameText = Widgets.CreateLabel(overlay, "FONT_SMALL_OUTLINE", "TEXT")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetPoint("LEFT", overlay, "LEFT", Theme.GAP / 2, 0)
    nameText:SetPoint("RIGHT", timeText, "LEFT", -Theme.GAP / 2, 0)

    Layout()
    body:Hide()
    hud:Show()
    hud:SetHudActive(true)
    hud:ApplySavedPosition()
end

-- READY 초기화, dik, 2026-10-01
local function Initialize()
    if not (ns.IsModuleEnabled(MODULE_ID) and ns.IsModuleSupported(MODULE_ID)) then
        return
    end
    if not IsOn("targetCastBar") then
        return
    end
    if not (ns.HasAPI("UnitCastingInfo") and ns.HasAPI("UnitChannelInfo")) then
        return
    end
    active = true
    BuildCastBar()
    CreateEventFrame()
    dirty = true
end

-- 설정 변경 처리, dik, 2026-10-01
local function OnSettingChanged(scope, key, value)
    if not active then
        return
    end
    if scope == "global" then
        if key == "fontSize" then
            ApplyFonts()
            dirty = true
        end
        return
    end
    if scope ~= MODULE_ID then
        return
    end
    if key == "castWidth" or key == "castHeight" or key == "hudScale" then
        Layout()
    elseif key == "bgAlpha" then
        Theme.ApplyBackdrop(body, "BG", "BORDER", value)
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
