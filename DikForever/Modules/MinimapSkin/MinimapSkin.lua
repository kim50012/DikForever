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

-- 미니맵 크기 퍼센트 범위 상수, dik, 2026-10-03
ns.MinimapSkin.SIZE_MIN = 100
ns.MinimapSkin.SIZE_MAX = 200
ns.MinimapSkin.SIZE_STEP = 5
ns.MinimapSkin.SIZE_DEFAULT = 100

-- 기준 크기와 퍼센트로 미니맵 크기 계산, dik, 2026-10-03
function ns.MinimapSkin.CalcSize(base, percent)
    if type(base) ~= "number" or base ~= base or base <= 0 then
        return nil
    end
    if type(percent) ~= "number" or percent ~= percent then
        percent = 100
    end
    if percent < ns.MinimapSkin.SIZE_MIN then
        percent = ns.MinimapSkin.SIZE_MIN
    elseif percent > ns.MinimapSkin.SIZE_MAX then
        percent = ns.MinimapSkin.SIZE_MAX
    end
    return math.floor(base * percent / 100 + 0.5)
end

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
        { key = "size", type = "slider", label = L.SETTING_MINIMAP_SIZE,
          tooltip = L.SETTING_MINIMAP_SIZE_TIP,
          min = ns.MinimapSkin.SIZE_MIN, max = ns.MinimapSkin.SIZE_MAX,
          step = ns.MinimapSkin.SIZE_STEP, default = ns.MinimapSkin.SIZE_DEFAULT },
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
