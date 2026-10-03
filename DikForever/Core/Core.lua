-- 진입점: 로드 이벤트·슬래시·compartment, dik, 2026-09-30
local addonName, ns = ...
local L = ns.L

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- 로드 이벤트 처리, dik, 2026-09-30
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then
            return
        end
        ns.InitDatabase()
        ns.InitializeModules()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.Fire("READY")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- 도움말 출력, dik, 2026-09-30
local function PrintHelp()
    ns.Print(L.HELP_HEADER)
    for _, line in ipairs(L.HELP_LINES) do
        ns.Print(line)
    end
end

SLASH_DIKFOREVER1 = "/dikf"
SLASH_DIKFOREVER2 = "/dikforever"

-- 슬래시 명령 처리, dik, 2026-09-30
SlashCmdList.DIKFOREVER = function(msg)
    local cmd = strtrim(msg or "")
    -- 레이아웃 명령 첫 단어 분리, dik, 2026-10-03
    local first, rest = cmd:match("^(%S+)%s*(.-)$")
    if cmd == "" then
        ns.Fire("TOGGLE_MAIN")
    elseif cmd == L.SLASH_CMD_SETTINGS then
        ns.Fire("OPEN_PAGE", "settings")
    elseif cmd == L.SLASH_CMD_OPTIONS then
        ns.Fire("OPEN_GAME_SETTINGS")
    elseif cmd == L.SLASH_CMD_RESET then
        ns.ResetWindow()
    -- 캐릭터 목록 슬래시 분기 추가, dik, 2026-09-30
    elseif cmd == L.SLASH_CMD_CHARACTERS then
        ns.PrintCharacters()
    -- 이동 모드 슬래시 분기 추가, dik, 2026-10-01
    elseif cmd == L.SLASH_CMD_MOVE then
        ns.Fire("TOGGLE_MOVE_MODE")
    -- 설정 이전 슬래시 분기 추가, dik, 2026-10-02
    elseif cmd == L.SLASH_CMD_TRANSFER then
        ns.Fire("OPEN_PAGE", "transfer")
    -- 레이아웃 슬래시 분기 추가, dik, 2026-10-03
    elseif first == L.SLASH_CMD_LAYOUTS then
        if not ns.Layouts then
            ns.Print(L.LAYOUTS_ERR_DISABLED)
        elseif rest == "" then
            ns.Fire("OPEN_PAGE", "layouts")
        elseif rest:match("^[1-5]$") then
            local n = tonumber(rest)
            local result, err = ns.Layouts.Load(n, { fromSlash = true })
            if not result then
                ns.Print(ns.Layouts.GetErrorText(err, n))
            end
        else
            ns.Print(L.LAYOUTS_SLASH_USAGE)
        end
    -- 버전 슬래시 분기 추가, dik, 2026-10-03
    elseif cmd == L.SLASH_CMD_VERSION then
        local version, build
        if ns.HasAPI("C_AddOns.GetAddOnMetadata") then
            version = C_AddOns.GetAddOnMetadata(addonName, "Version")
            build = C_AddOns.GetAddOnMetadata(addonName, "X-Build")
        end
        if type(version) ~= "string" or version == "" then
            ns.Print(L.VERSION_UNKNOWN)
        elseif type(build) == "string" and build ~= "" then
            ns.Print(L.VERSION_LINE_BUILD:format(version, build))
        else
            ns.Print(L.VERSION_LINE:format(version))
        end
    else
        PrintHelp()
    end
end

-- 애드온 목록 버튼 클릭, dik, 2026-09-30
function DikForever_OnAddonCompartmentClick()
    ns.Fire("TOGGLE_MAIN")
end
