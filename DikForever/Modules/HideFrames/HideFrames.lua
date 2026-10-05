-- 기본 UI 숨기기 모듈 등록·묶음 해석·이관, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.HideFrames = ns.HideFrames or {}

ns.HideFrames.MODULE_ID = "hideFrames"
ns.HideFrames.REAPPLY_MAX = 5
-- 플레이어 묶음 투명화 방식 지정(taint 회피), dik, 2026-10-03
ns.HideFrames.GROUPS = {
    { key = "player", names = { "PlayerFrame" }, mode = "alpha" },
    { key = "target", names = { "TargetFrame" } },
    { key = "focus", names = { "FocusFrame" } },
    { key = "party", names = { "PartyFrame", "CompactPartyFrame" } },
    { key = "boss", names = { "BossTargetFrameContainer" } },
    { key = "castBar", names = { { "PlayerCastingBarFrame", "CastingBarFrame" } } },
    { key = "actionBars", names = { { "MainActionBar", "MainMenuBar" }, "MultiBarBottomLeft",
        "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" } },
    { key = "minimap", names = { "MinimapCluster" } },
    { key = "buffs", names = { "BuffFrame", "DebuffFrame" } },
    -- Issue Reporter 출처 묶음 추가, dik, 2026-10-05
    { key = "issueReporter", names = {}, source = "Blizzard_PTRFeedback" },
}

-- 생성 출처 문자열 plain 일치 판별, dik, 2026-10-05
function ns.HideFrames.MatchSource(location, pattern)
    if ns.IsSecret(location) or type(location) ~= "string" then
        return false
    end
    if type(pattern) ~= "string" or pattern == "" then
        return false
    end
    return string.find(location, pattern, 1, true) ~= nil
end

-- 묶음의 있는 이름·없는 이름 분류, dik, 2026-10-01
function ns.HideFrames.ResolveGroup(group, exists)
    local found, missing = {}, {}
    if type(group) ~= "table" or type(group.names) ~= "table" then
        return found, missing
    end
    if type(exists) ~= "function" then
        exists = ns.HasAPI
    end
    for _, entry in ipairs(group.names) do
        if type(entry) == "table" then
            local picked
            for _, alt in ipairs(entry) do
                if exists(alt) then
                    picked = alt
                    break
                end
            end
            if picked then
                found[#found + 1] = picked
            else
                missing[#missing + 1] = table.concat(entry, "/")
            end
        elseif exists(entry) then
            found[#found + 1] = entry
        else
            missing[#missing + 1] = entry
        end
    end
    return found, missing
end

-- key 로 묶음 조회, dik, 2026-10-01
function ns.HideFrames.GetGroup(key)
    for _, group in ipairs(ns.HideFrames.GROUPS) do
        if group.key == key then
            return group
        end
    end
    return nil
end

-- 묶음 전체가 없을 때 안내 문구, dik, 2026-10-01
function ns.HideFrames.GetUnavailableReason(key, exists)
    local group = ns.HideFrames.GetGroup(key)
    if not group then
        return nil
    end
    -- 출처 묶음은 이름 검사 대신 출처 메서드 검사, dik, 2026-10-05
    if group.source then
        if type(UIParent) == "table" and type(UIParent.GetSourceLocation) == "function" then
            return nil
        end
        return L.SETTING_HIDEFRAMES_NO_SOURCE
    end
    local found, missing = ns.HideFrames.ResolveGroup(group, exists)
    if #found == 0 then
        return L.SETTING_HIDEFRAMES_UNAVAILABLE:format(ns.FormatMissingAPIs(missing))
    end
    return nil
end

-- 전투 HUD 기본 프레임 숨기기 설정 이관, dik, 2026-10-01
function ns.HideFrames.MigrateLegacy(settingsModules)
    if type(settingsModules) ~= "table" then
        return false
    end
    local old = settingsModules.combatHud
    if type(old) ~= "table" or old.hideBlizzardFrames == nil then
        return false
    end
    if old.hideBlizzardFrames == true then
        if type(settingsModules.hideFrames) ~= "table" then
            settingsModules.hideFrames = {}
        end
        local hf = settingsModules.hideFrames
        if old.playerFrame ~= false then
            hf.player = true
        end
        if old.targetFrame ~= false then
            hf.target = true
        end
    end
    old.hideBlizzardFrames = nil
    return true
end

-- 기본 UI 숨기기 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "hideFrames",
    title = L.MODULE_HIDEFRAMES,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_HIDEFRAMES_DESC,
    category = "display",
    order = 80,
    requires = { "InCombatLockdown" },
    settings = {
        { key = "player", type = "checkbox", label = L.SETTING_HIDEFRAMES_PLAYER,
          tooltip = L.SETTING_HIDEFRAMES_PLAYER_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("player") end },
        { key = "target", type = "checkbox", label = L.SETTING_HIDEFRAMES_TARGET,
          tooltip = L.SETTING_HIDEFRAMES_TARGET_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("target") end },
        { key = "focus", type = "checkbox", label = L.SETTING_HIDEFRAMES_FOCUS,
          tooltip = L.SETTING_HIDEFRAMES_FOCUS_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("focus") end },
        { key = "party", type = "checkbox", label = L.SETTING_HIDEFRAMES_PARTY,
          tooltip = L.SETTING_HIDEFRAMES_PARTY_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("party") end },
        { key = "boss", type = "checkbox", label = L.SETTING_HIDEFRAMES_BOSS,
          tooltip = L.SETTING_HIDEFRAMES_BOSS_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("boss") end },
        { key = "castBar", type = "checkbox", label = L.SETTING_HIDEFRAMES_CASTBAR,
          tooltip = L.SETTING_HIDEFRAMES_CASTBAR_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("castBar") end },
        { key = "actionBars", type = "checkbox", label = L.SETTING_HIDEFRAMES_ACTIONBARS,
          tooltip = L.SETTING_HIDEFRAMES_ACTIONBARS_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("actionBars") end },
        { key = "minimap", type = "checkbox", label = L.SETTING_HIDEFRAMES_MINIMAP,
          tooltip = L.SETTING_HIDEFRAMES_MINIMAP_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("minimap") end },
        { key = "buffs", type = "checkbox", label = L.SETTING_HIDEFRAMES_BUFFS,
          tooltip = L.SETTING_HIDEFRAMES_BUFFS_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("buffs") end },
        -- Issue Reporter 숨기기 설정 추가, dik, 2026-10-05
        { key = "issueReporter", type = "checkbox", label = L.SETTING_HIDEFRAMES_ISSUEREPORTER,
          tooltip = L.SETTING_HIDEFRAMES_ISSUEREPORTER_TIP, default = false,
          unavailable = function() return ns.HideFrames.GetUnavailableReason("issueReporter") end },
    },
    OnInitialize = function()
        if ns.IsDatabaseNewer() then
            return
        end
        if type(ns.db) ~= "table" or type(ns.db.settings) ~= "table" then
            return
        end
        if ns.HideFrames.MigrateLegacy(ns.db.settings.modules) then
            ns.Print(L.MSG_HIDEFRAMES_MIGRATED)
        end
    end,
})
