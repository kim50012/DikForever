-- 채팅창 모듈 등록·공개 상수·정보줄 배치 계산, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.Chat = {}

ns.Chat.INFO_ITEMS = {
    { key = "infoFps", provider = "fps" },
    { key = "infoLatency", provider = "latency" },
    { key = "infoGold", provider = "gold" },
    { key = "infoBags", provider = "bags" },
    { key = "infoFriends", provider = "friends" },
    { key = "infoGuild", provider = "guild" },
    { key = "infoDurability", provider = "durability" },
}

ns.Chat.SKIN_PARTS = {
    { key = "skinBackground", owner = "chat:background" },
    { key = "skinTabs", owner = "chat:tabs" },
    { key = "skinEditBox", owner = "chat:editBox" },
    { key = "skinFont", owner = "chat:font" },
}

ns.Chat.HUD_INFO_LINE = { key = "infoLine", point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 120 }

-- 정보줄 항목 배치 계산, dik, 2026-10-01
function ns.Chat.LayoutInfo(widths, available, gap, pad)
    local xs = {}
    local x = pad
    for i = 1, #widths do
        local w = widths[i]
        if available ~= nil and x + w > available - pad then
            break
        end
        xs[#xs + 1] = x
        x = x + w + gap
    end
    local placed = #xs
    local total = placed > 0 and (x - gap + pad) or 0
    return xs, placed, total
end

ns.RegisterModule({
    id = "chat",
    title = L.MODULE_CHAT,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_CHAT_DESC,
    category = "display",
    order = 10,
    -- 설정 창별 huds 태그 추가, dik, 2026-10-05
    settings = {
        { key = "skinBackground", huds = {}, type = "checkbox", label = L.SETTING_CHAT_SKIN_BG,
          tooltip = L.SETTING_CHAT_SKIN_BG_TIP, default = true },
        { key = "bgAlpha", huds = {}, type = "slider", label = L.SETTING_CHAT_BG_ALPHA,
          tooltip = L.SETTING_CHAT_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.6 },
        { key = "skinTabs", huds = {}, type = "checkbox", label = L.SETTING_CHAT_SKIN_TABS,
          tooltip = L.SETTING_CHAT_SKIN_TABS_TIP, default = true },
        { key = "skinEditBox", huds = {}, type = "checkbox", label = L.SETTING_CHAT_SKIN_EDITBOX,
          tooltip = L.SETTING_CHAT_SKIN_EDITBOX_TIP, default = true },
        { key = "skinFont", huds = {}, type = "checkbox", label = L.SETTING_CHAT_SKIN_FONT,
          tooltip = L.SETTING_CHAT_SKIN_FONT_TIP, default = true },
        { key = "showInfo", type = "checkbox", label = L.SETTING_CHAT_SHOW_INFO,
          tooltip = L.SETTING_CHAT_SHOW_INFO_TIP, default = true },
        { key = "infoPosition", type = "select", label = L.SETTING_CHAT_INFO_POSITION,
          tooltip = L.SETTING_CHAT_INFO_POSITION_TIP,
          items = {
              { value = "below", text = L.CHAT_POS_BELOW },
              { value = "free", text = L.CHAT_POS_FREE },
          },
          default = "below" },
        { key = "infoFps", type = "checkbox", label = L.SETTING_CHAT_INFO_FPS,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoLatency", type = "checkbox", label = L.SETTING_CHAT_INFO_LATENCY,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoGold", type = "checkbox", label = L.SETTING_CHAT_INFO_GOLD,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoBags", type = "checkbox", label = L.SETTING_CHAT_INFO_BAGS,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoFriends", type = "checkbox", label = L.SETTING_CHAT_INFO_FRIENDS,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoGuild", type = "checkbox", label = L.SETTING_CHAT_INFO_GUILD,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
        { key = "infoDurability", type = "checkbox", label = L.SETTING_CHAT_INFO_DURABILITY,
          tooltip = L.SETTING_CHAT_INFO_ITEM_TIP, default = true },
    },
})
