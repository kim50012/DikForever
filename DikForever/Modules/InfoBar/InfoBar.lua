-- 상단 정보바 모듈 등록·공급자·메뉴 판정, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "infoBar"

ns.InfoBar = {}

ns.InfoBar.MENU_BUTTONS = {
    { key = "character", label = L.MENU_CHARACTER,
      candidates = { { path = "ToggleCharacter", args = { "PaperDollFrame" } } } },
    { key = "spellbook", label = L.MENU_SPELLBOOK,
      candidates = { { path = "PlayerSpellsUtil.ToggleSpellBookFrame" },
                     { path = "ToggleSpellBook", args = { "spell" } } } },
    { key = "bags", label = L.MENU_BAGS, candidates = { { path = "ToggleAllBags" } } },
    { key = "quest", label = L.MENU_QUEST, candidates = { { path = "ToggleQuestLog" } } },
    { key = "map", label = L.MENU_MAP, candidates = { { path = "ToggleWorldMap" } } },
    { key = "friends", label = L.MENU_FRIENDS,
      candidates = { { path = "ToggleFriendsFrame", args = { 1 } } } },
    { key = "guild", label = L.MENU_GUILD, candidates = { { path = "ToggleGuildFrame" } } },
    -- 내부 항목 event 필드·이동 버튼 추가, dik, 2026-10-01
    { key = "dikforever", label = L.MENU_DIKFOREVER, internal = true, combatAllowed = true, event = "TOGGLE_MAIN" },
    { key = "move",       label = L.MENU_MOVE,       internal = true, combatAllowed = false, event = "TOGGLE_MOVE_MODE" },
}

ns.InfoBar.ELEMENTS = {
    { key = "showMenu", kind = "menu" },
    { key = "showClock", kind = "clock" },
    { key = "showCoords", provider = "coords" },
    { key = "showZone", provider = "zone" },
    { key = "infoFps", provider = "fps" },
    { key = "infoLatency", provider = "latency" },
    { key = "infoGold", provider = "gold" },
    { key = "infoBags", provider = "bags" },
    { key = "infoFriends", provider = "friends" },
    { key = "infoGuild", provider = "guild" },
    { key = "infoDurability", provider = "durability" },
}

ns.InfoBar.HUD_BAR = { key = "bar", point = "TOP", relativePoint = "TOP", x = 0, y = -2, strata = "LOW" }

ns.InfoBar.OWNER = "infoBar"

local blocked = false

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 비어 있지 않은 문자열 판정, dik, 2026-10-01
local function IsText(v)
    return type(v) == "string" and v ~= ""
end

-- 점 경로로 함수 찾기, dik, 2026-10-01
local function FindFunction(path)
    local node = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        node = node[part]
    end
    if type(node) == "function" then
        return node
    end
    return nil
end

-- 후보 중 첫 지원 경로 선택, dik, 2026-10-01
local function PickCandidate(def, hasApi)
    for i = 1, #def.candidates do
        local cand = def.candidates[i]
        if hasApi(cand.path) then
            return cand
        end
    end
    return nil
end

-- 지역 문구 판정, dik, 2026-10-01
function ns.InfoBar.EvalZone(zone, subZone)
    if not IsText(zone) then
        return nil
    end
    if IsText(subZone) and subZone ~= zone then
        return L.FMT_ZONE_SUB:format(zone, subZone), "TEXT"
    end
    return zone, "TEXT"
end

-- 좌표 문구 판정, dik, 2026-10-01
function ns.InfoBar.EvalCoords(x, y)
    if IsNumber(x) and IsNumber(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
        and not (x == 0 and y == 0) then
        return L.FMT_COORDS:format(x * 100, y * 100), "TEXT"
    end
    return L.COORD_NONE, "TEXT_DIM"
end

-- 시계 문구 판정, dik, 2026-10-01
function ns.InfoBar.EvalClock(hour, minute, use24)
    if not IsNumber(hour) or not IsNumber(minute) or math.floor(hour) ~= hour
        or math.floor(minute) ~= minute or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return nil
    end
    if use24 == true then
        return L.FMT_CLOCK_24:format(hour, minute), "TEXT"
    end
    local h12 = hour % 12
    if h12 == 0 then
        h12 = 12
    end
    if hour < 12 then
        return L.FMT_CLOCK_AM:format(h12, minute), "TEXT"
    end
    return L.FMT_CLOCK_PM:format(h12, minute), "TEXT"
end

-- 시계 공급자 id 선택, dik, 2026-10-01
function ns.InfoBar.GetClockProvider(mode)
    if mode == "server" then
        return "timeServer"
    end
    return "timeLocal"
end

-- 메뉴 버튼 해석, dik, 2026-10-01
function ns.InfoBar.ResolveMenu(hasApi)
    if type(hasApi) ~= "function" then
        hasApi = ns.HasAPI
    end
    local resolved = {}
    local missing = {}
    for i = 1, #ns.InfoBar.MENU_BUTTONS do
        local def = ns.InfoBar.MENU_BUTTONS[i]
        if def.internal then
            resolved[#resolved + 1] = def
        else
            local cand = PickCandidate(def, hasApi)
            if cand then
                resolved[#resolved + 1] = { key = def.key, label = def.label, path = cand.path,
                    args = cand.args, combatAllowed = false }
            else
                missing[#missing + 1] = def.candidates[1].path
            end
        end
    end
    return resolved, missing
end

-- 차단 상태 조회, dik, 2026-10-01
function ns.InfoBar.IsBlocked()
    return blocked
end

-- 차단 상태 켜고 1회 안내, dik, 2026-10-01
function ns.InfoBar.MarkBlocked()
    if blocked then
        return
    end
    blocked = true
    ns.Print(L.MSG_MENU_BLOCKED)
    -- 버튼 갱신 내부 이벤트 발행(WFA-040), dik, 2026-10-02
    ns.Fire("INFOBAR_BLOCKED")
end

-- 메뉴 버튼 동작 실행, dik, 2026-10-01
function ns.InfoBar.OpenMenu(key)
    local def
    for i = 1, #ns.InfoBar.MENU_BUTTONS do
        if ns.InfoBar.MENU_BUTTONS[i].key == key then
            def = ns.InfoBar.MENU_BUTTONS[i]
            break
        end
    end
    if not def then
        return "unknown"
    end
    -- 내부 항목은 event 필드 이벤트 발행, dik, 2026-10-01
    if def.internal then
        ns.Fire(type(def.event) == "string" and def.event or "TOGGLE_MAIN")
        return "ok"
    end
    if blocked then
        return "blocked"
    end
    if ns.HasAPI("InCombatLockdown") and InCombatLockdown() then
        ns.Print(L.MSG_MENU_COMBAT)
        return "combat"
    end
    local cand = PickCandidate(def, ns.HasAPI)
    local fn = cand and FindFunction(cand.path) or nil
    if not fn then
        ns.Print(L.MSG_MENU_UNAVAILABLE:format(def.label))
        return "missing"
    end
    local args = cand.args
    local ok = xpcall(function() fn(unpack(args or {})) end, geterrorhandler())
    return ok and "ok" or "error"
end

-- 지역 공급자 값, dik, 2026-10-01
local function GetZoneValue()
    local zone = GetRealZoneText()
    local sub = GetSubZoneText()
    if ns.IsSecret(zone) or ns.IsSecret(sub) then
        return nil
    end
    return ns.InfoBar.EvalZone(zone, sub)
end

-- 좌표 공급자 값, dik, 2026-10-01
local function GetCoordsValue()
    local map = C_Map.GetBestMapForUnit("player")
    if ns.IsSecret(map) then
        return nil
    end
    if type(map) ~= "number" then
        return ns.InfoBar.EvalCoords(nil, nil)
    end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
        return ns.InfoBar.EvalCoords(nil, nil)
    end
    local x, y = pos:GetXY()
    if ns.IsSecret(x) or ns.IsSecret(y) then
        return nil
    end
    return ns.InfoBar.EvalCoords(x, y)
end

-- 로컬 시계 공급자 값, dik, 2026-10-01
local function GetLocalTimeValue()
    local t = date("*t")
    if type(t) ~= "table" or ns.IsSecret(t.hour) or ns.IsSecret(t.min) then
        return nil
    end
    return ns.InfoBar.EvalClock(t.hour, t.min, ns.GetSetting(MODULE_ID, "clock24h"))
end

-- 서버 시계 공급자 값, dik, 2026-10-01
local function GetServerTimeValue()
    local h, m = GetGameTime()
    if ns.IsSecret(h) or ns.IsSecret(m) then
        return nil
    end
    return ns.InfoBar.EvalClock(h, m, ns.GetSetting(MODULE_ID, "clock24h"))
end

ns.InfoText.Register({ id = "zone", label = L.INFO_ZONE, order = 80,
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
    requires = { "GetRealZoneText", "GetSubZoneText" }, showLabel = false, Get = GetZoneValue })
ns.InfoText.Register({ id = "coords", label = L.INFO_COORDS, order = 90, interval = 0.5,
    requires = { "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition" }, Get = GetCoordsValue })
ns.InfoText.Register({ id = "timeLocal", label = L.INFO_TIME_LOCAL, order = 100, interval = 1,
    requires = { "date" }, showLabel = false, Get = GetLocalTimeValue })
ns.InfoText.Register({ id = "timeServer", label = L.INFO_TIME_SERVER, order = 110, interval = 1,
    requires = { "GetGameTime" }, showLabel = false, Get = GetServerTimeValue })

ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_INFOBAR,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_INFOBAR_DESC,
    category = "display",
    order = 20,
    settings = {
        { key = "barAlpha", type = "slider", label = L.SETTING_INFOBAR_BG_ALPHA,
          tooltip = L.SETTING_INFOBAR_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.8 },
        { key = "showMenu", type = "checkbox", label = L.SETTING_INFOBAR_SHOW_MENU,
          tooltip = L.SETTING_INFOBAR_SHOW_MENU_TIP, default = true },
        { key = "showClock", type = "checkbox", label = L.SETTING_INFOBAR_SHOW_CLOCK,
          tooltip = L.SETTING_INFOBAR_SHOW_CLOCK_TIP, default = true },
        { key = "clockMode", type = "select", label = L.SETTING_INFOBAR_CLOCK_MODE,
          tooltip = L.SETTING_INFOBAR_CLOCK_MODE_TIP,
          items = {
              { value = "local", text = L.INFOBAR_CLOCK_LOCAL },
              { value = "server", text = L.INFOBAR_CLOCK_SERVER },
          },
          default = "local" },
        { key = "clock24h", type = "checkbox", label = L.SETTING_INFOBAR_CLOCK_24H,
          tooltip = L.SETTING_INFOBAR_CLOCK_24H_TIP, default = false },
        { key = "showCoords", type = "checkbox", label = L.SETTING_INFOBAR_SHOW_COORDS,
          tooltip = L.SETTING_INFOBAR_SHOW_COORDS_TIP, default = true },
        { key = "showZone", type = "checkbox", label = L.SETTING_INFOBAR_SHOW_ZONE,
          tooltip = L.SETTING_INFOBAR_SHOW_ZONE_TIP, default = true },
        { key = "infoFps", type = "checkbox", label = L.SETTING_CHAT_INFO_FPS,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoLatency", type = "checkbox", label = L.SETTING_CHAT_INFO_LATENCY,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoGold", type = "checkbox", label = L.SETTING_CHAT_INFO_GOLD,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoBags", type = "checkbox", label = L.SETTING_CHAT_INFO_BAGS,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoFriends", type = "checkbox", label = L.SETTING_CHAT_INFO_FRIENDS,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoGuild", type = "checkbox", label = L.SETTING_CHAT_INFO_GUILD,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
        { key = "infoDurability", type = "checkbox", label = L.SETTING_CHAT_INFO_DURABILITY,
          tooltip = L.SETTING_INFOBAR_INFO_ITEM_TIP, default = false },
    },
    -- 동작 차단 공통 처리 구독(WFA-040), dik, 2026-10-02
    OnInitialize = function()
        ns.ActionBlock.Register(MODULE_ID, {
            "ToggleCharacter", "ToggleSpellBookFrame", "ToggleSpellBook", "ToggleAllBags",
            "ToggleQuestLog", "ToggleWorldMap", "ToggleFriendsFrame", "ToggleGuildFrame",
            "ShowUIPanel", "HideUIPanel",
        }, function()
            ns.InfoBar.MarkBlocked()
        end)
    end,
})
