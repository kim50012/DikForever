-- 미니맵 스킨 모듈 등록·그룹 상수·저장값 이관, dik, 2026-10-03
local addonName, ns = ...
local L = ns.L

ns.MinimapSkin = {}

ns.MinimapSkin.MODULE_ID = "minimapSkin"

ns.MinimapSkin.SKIN_OWNER = "minimapSkin"

ns.MinimapSkin.MINIMAP_GROUPS = {
    { key = "border", kind = "texture", candidates = { { "MinimapCompassTexture" }, { "MinimapBorder" } } },
    { key = "borderTop", kind = "texture",
      candidates = { { "MinimapCluster", "BorderTop" }, { "MinimapBorderTop" } } },
    { key = "zoneText", kind = "font", candidates = { { "MinimapZoneText" } } },
}

-- 능력치 패널 설정에서 미니맵 설정 이관, dik, 2026-10-03
function ns.MinimapSkin.MigrateLegacy(settingsModules)
    if type(settingsModules) ~= "table" then
        return false
    end
    local old = settingsModules.statsMinimap
    if type(old) ~= "table" or (old.skinMinimap == nil and old.minimapShape == nil) then
        return false
    end
    if type(settingsModules.minimapSkin) ~= "table" then
        settingsModules.minimapSkin = {}
    end
    local new = settingsModules.minimapSkin
    if old.skinMinimap == false then
        new.enabled = false
    end
    if old.minimapShape == "square" or old.minimapShape == "round" then
        new.shape = old.minimapShape
    end
    old.skinMinimap = nil
    old.minimapShape = nil
    return true
end

-- 미니맵 스킨 모듈 등록, dik, 2026-10-03
ns.RegisterModule({
    id = "minimapSkin",
    title = L.MODULE_MINIMAPSKIN,
    description = L.MODULE_MINIMAPSKIN_DESC,
    category = "display",
    order = 55,
    settings = {
        { key = "shape", type = "select", label = L.SETTING_MINIMAP_SHAPE,
          tooltip = L.SETTING_MINIMAP_SHAPE_TIP,
          items = {
              { value = "square", text = L.MINIMAP_SHAPE_SQUARE },
              { value = "round", text = L.MINIMAP_SHAPE_ROUND },
          },
          default = "square" },
    },
    OnInitialize = function()
        if ns.IsDatabaseNewer() then
            return
        end
        if type(ns.db) ~= "table" or type(ns.db.settings) ~= "table" then
            return
        end
        if ns.MinimapSkin.MigrateLegacy(ns.db.settings.modules) then
            ns.Print(L.MSG_MINIMAPSKIN_MIGRATED)
        end
    end,
})
