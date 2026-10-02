-- 전투 HUD 보안 버튼·기본 프레임 숨기기(K2 가드 파일), dik, 2026-10-01
-- 기본 프레임 숨기기 제거(WFA-021), dik, 2026-10-01
local addonName, ns = ...

local module = ns.GetModule("combatHud")
if not module then
    return
end

ns.CombatHudSecure = {}

local inCombatFlag = false
local flagFrame = nil

-- 보안 조작 가능 여부(전투 밖·차단 없음), dik, 2026-10-01
function ns.CombatHudSecure.CanTouch()
    if ns.CombatHud.IsBlocked() then
        return false
    end
    if not ns.HasAPI("InCombatLockdown") then
        return false
    end
    if InCombatLockdown() == true then
        return false
    end
    if inCombatFlag then
        return false
    end
    return true
end

-- 클릭 대상 선택 버튼 생성, dik, 2026-10-01
-- 오른쪽 클릭 메뉴 인자 추가(WFA-031), dik, 2026-10-02
function ns.CombatHudSecure.CreateClickButton(hud, unit, watch, menu)
    if not ns.CombatHudSecure.CanTouch() then return nil end
    local ok, btn = xpcall(function()
        return CreateFrame("Button", nil, UIParent, "SecureUnitButtonTemplate")
    end, geterrorhandler())
    if not ok or not btn then
        return nil
    end
    btn:SetAllPoints(hud)
    btn:SetFrameStrata(hud:GetFrameStrata())
    btn:SetFrameLevel(hud:GetFrameLevel() + 2)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("type1", "target")
    -- 오른쪽 클릭 메뉴 type2 조건부 설정(WFA-031), dik, 2026-10-02
    if menu == true then
        btn:SetAttribute("type2", "togglemenu")
    end
    if watch and ns.HasAPI("RegisterUnitWatch") then
        RegisterUnitWatch(btn)
    end
    return btn
end

-- 버튼 마우스 켜기·끄기, dik, 2026-10-01
function ns.CombatHudSecure.SetClickMouse(button, on)
    if not ns.CombatHudSecure.CanTouch() then return false end
    if type(button) ~= "table" then
        return false
    end
    button:EnableMouse(on == true)
    return true
end

-- 전투 플래그 이벤트 프레임(READY 활성·지원일 때만), dik, 2026-10-01
ns.On("READY", function()
    if flagFrame then
        return
    end
    if not (ns.IsModuleEnabled("combatHud") and ns.IsModuleSupported("combatHud")) then
        return
    end
    inCombatFlag = ns.HasAPI("InCombatLockdown") and InCombatLockdown() == true
    flagFrame = CreateFrame("Frame")
    flagFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    flagFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    flagFrame:SetScript("OnEvent", function(_, event)
        inCombatFlag = event == "PLAYER_REGEN_DISABLED"
    end)
end)
