-- 모듈 레지스트리·설정 선언·검증, dik, 2026-09-30
local addonName, ns = ...

local L = ns.L

local GLOBAL_SCOPE = "global"
local modules = {}

-- 전역 설정 선언 4건, dik, 2026-09-30
local GLOBAL_SETTINGS = {
    { key = "scale", type = "slider", label = L.SETTING_SCALE, tooltip = L.SETTING_SCALE_TIP,
      min = 0.8, max = 1.3, step = 0.05, default = 1.0 },
    { key = "fontSize", type = "slider", label = L.SETTING_FONT_SIZE, tooltip = L.SETTING_FONT_SIZE_TIP,
      min = 10, max = 16, step = 1, default = 12 },
    { key = "lockWindow", type = "checkbox", label = L.SETTING_LOCK_WINDOW, tooltip = L.SETTING_LOCK_WINDOW_TIP,
      default = false },
    { key = "rememberPage", type = "checkbox", label = L.SETTING_REMEMBER_PAGE, tooltip = L.SETTING_REMEMBER_PAGE_TIP,
      default = true },
}

-- 모듈 등록, dik, 2026-09-30
function ns.RegisterModule(def)
    local missing = {}
    if type(def) ~= "table" then
        missing[1] = "id"
        missing[2] = "title"
    else
        if type(def.id) ~= "string" or def.id == "" then
            missing[#missing + 1] = "id"
        end
        if type(def.title) ~= "string" or def.title == "" then
            missing[#missing + 1] = "title"
        end
    end
    if #missing > 0 then
        ns.Print(L.ERR_MODULE_MISSING_FIELD:format(table.concat(missing, ", ")))
        return nil
    end

    -- 예약 scope 인 global 도 중복으로 거부, dik, 2026-09-30
    if modules[def.id] or def.id == GLOBAL_SCOPE then
        ns.Print(L.ERR_DUPLICATE_MODULE:format(def.id))
        return nil
    end

    if def.category == nil then
        def.category = "feature"
    elseif def.category ~= "feature" and def.category ~= "display" then
        ns.Print(L.WARN_UNKNOWN_CATEGORY:format(tostring(def.category), def.id))
        def.category = "feature"
    end
    if type(def.order) ~= "number" then
        def.order = 100
    end
    def.builtin = (def.builtin == true)
    if type(def.settings) ~= "table" then
        def.settings = {}
    end
    -- requires 정규화, dik, 2026-09-30
    if type(def.requires) ~= "table" then
        def.requires = {}
    end

    -- description 정규화, dik, 2026-10-01
    if type(def.description) ~= "string" or def.description == "" then
        def.description = nil
    end

    modules[def.id] = def
    return def
end

-- 모듈 조회, dik, 2026-09-30
function ns.GetModule(id)
    return modules[id]
end

-- 모듈 활성 여부, dik, 2026-09-30
function ns.IsModuleEnabled(id)
    local module = modules[id]
    if not module then
        return false
    end
    if module.builtin then
        return true
    end
    return ns.GetSetting(id, "enabled") ~= false
end

-- 메뉴 정렬 순위, dik, 2026-09-30
local function GetRank(module)
    if module.id == "home" then
        return 0
    elseif module.id == "settings" then
        return 3
    elseif module.category == "display" then
        return 2
    end
    return 1
end

-- 메뉴 정렬 비교, dik, 2026-09-30
local function CompareModules(a, b)
    local rankA, rankB = GetRank(a), GetRank(b)
    if rankA ~= rankB then
        return rankA < rankB
    end
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.id < b.id
end

-- 정렬된 모듈 배열, dik, 2026-09-30
local function CollectModules(activeOnly)
    local list = {}
    for id, module in pairs(modules) do
        if not activeOnly or ns.IsModuleEnabled(id) then
            list[#list + 1] = module
        end
    end
    table.sort(list, CompareModules)
    return list
end

-- 활성 모듈 목록, dik, 2026-09-30
function ns.GetModules()
    return CollectModules(true)
end

-- 비활성 포함 모듈 목록, dik, 2026-09-30
function ns.GetAllModules()
    return CollectModules(false)
end

-- 설정 선언 목록, dik, 2026-09-30
function ns.GetSettingDefs(scope)
    local defs = {}
    if scope == "global" then
        for i = 1, #GLOBAL_SETTINGS do
            defs[i] = GLOBAL_SETTINGS[i]
        end
        return defs
    end
    local module = modules[scope]
    if not module then
        return defs
    end
    if not module.builtin then
        defs[1] = {
            key = "enabled",
            type = "checkbox",
            label = L.SETTING_ENABLED,
            tooltip = L.SETTING_ENABLED_TIP,
            default = true,
        }
    end
    for i = 1, #module.settings do
        defs[#defs + 1] = module.settings[i]
    end
    return defs
end

-- 창별 설정 선언 거르기, dik, 2026-10-05
function ns.GetHudSettingDefs(moduleId, hudKey)
    local result = {}
    if moduleId == "global" or not modules[moduleId] then
        return result
    end
    local defs = ns.GetSettingDefs(moduleId)
    for i = 1, #defs do
        local def = defs[i]
        local huds = def.huds
        local keep = def.key == "enabled" or type(huds) ~= "table"
        if not keep then
            for k = 1, #huds do
                if huds[k] == hudKey then
                    keep = true
                    break
                end
            end
        end
        if keep then
            result[#result + 1] = def
        end
    end
    return result
end

-- 선언 찾기, dik, 2026-09-30
local function FindSettingDef(scope, key)
    local defs = ns.GetSettingDefs(scope)
    for i = 1, #defs do
        if defs[i].key == key then
            return defs[i]
        end
    end
    return nil
end

-- 저장소 테이블 조회(create 면 생성), dik, 2026-09-30
local function GetStore(scope, create)
    local db = ns.db
    if not db then
        return nil
    end
    if type(db.settings) ~= "table" then
        if not create then
            return nil
        end
        db.settings = {}
    end
    local settings = db.settings
    if scope == "global" then
        if type(settings.global) ~= "table" and create then
            settings.global = {}
        end
        return settings.global
    end
    if type(settings.modules) ~= "table" then
        if not create then
            return nil
        end
        settings.modules = {}
    end
    if type(settings.modules[scope]) ~= "table" and create then
        settings.modules[scope] = {}
    end
    return settings.modules[scope]
end

-- select 선택지 배열, dik, 2026-10-01
local function GetSelectItems(def)
    if type(def.items) == "table" then
        return def.items
    end
    return {}
end

-- select 선택지 포함 판정, dik, 2026-10-01
local function IsChoice(def, value)
    local items = GetSelectItems(def)
    for i = 1, #items do
        if items[i].value == value then
            return true
        end
    end
    return false
end

-- 설정값 조회, dik, 2026-09-30
function ns.GetSetting(scope, key)
    local def = FindSettingDef(scope, key)
    if not def then
        return nil
    end
    local store = GetStore(scope, false)
    if store == nil or store[key] == nil then
        return def.default
    end
    -- select 선택지 밖 저장값은 기본값 반환, dik, 2026-10-01
    if def.type == "select" and not IsChoice(def, store[key]) then
        return def.default
    end
    return store[key]
end

-- step 소수 자릿수, dik, 2026-09-30
local function CountDecimals(step)
    local fraction = tostring(step):match("%.(%d+)")
    if fraction then
        return #fraction
    end
    return 0
end

-- 슬라이더 값 보정, dik, 2026-09-30
local function NormalizeSlider(def, value)
    local v = value
    if v < def.min then
        v = def.min
    elseif v > def.max then
        v = def.max
    end
    v = def.min + math.floor((v - def.min) / def.step + 0.5) * def.step
    v = tonumber(string.format("%." .. CountDecimals(def.step) .. "f", v))
    if v < def.min then
        v = def.min
    elseif v > def.max then
        v = def.max
    end
    return v
end

-- 설정값 검증(출력 없음), dik, 2026-10-02
local function CheckSetting(scope, key, value)
    local def = FindSettingDef(scope, key)
    if not def then
        return nil, "ERR_SETTING_UNKNOWN_KEY"
    end
    if def.type == "checkbox" then
        if type(value) ~= "boolean" then
            return nil, "ERR_SETTING_TYPE"
        end
    elseif def.type == "slider" then
        if type(value) ~= "number" or value ~= value then
            return nil, "ERR_SETTING_TYPE"
        end
    -- select 타입·선택지 검증, dik, 2026-10-01
    elseif def.type == "select" then
        local valueType = type(value)
        if (valueType ~= "string" and valueType ~= "number") or value ~= value then
            return nil, "ERR_SETTING_TYPE"
        end
        if not IsChoice(def, value) then
            return nil, "ERR_SETTING_CHOICE"
        end
    end
    return def, nil
end

-- 설정값 검증 공개 함수, dik, 2026-10-02
function ns.ValidateSetting(scope, key, value)
    local def, errKey = CheckSetting(scope, key, value)
    if not def then
        return false, errKey
    end
    if def.type == "slider" then
        return true, NormalizeSlider(def, value)
    end
    return true, value
end

-- 설정값 검증·저장, dik, 2026-09-30
function ns.SetSetting(scope, key, value, opts)
    local quiet = type(opts) == "table" and opts.quiet == true
    local def, errKey = CheckSetting(scope, key, value)
    if not def then
        if not quiet then
            if errKey == "ERR_SETTING_UNKNOWN_KEY" then
                ns.Print(L.ERR_SETTING_UNKNOWN_KEY:format(tostring(scope), tostring(key)))
            elseif errKey == "ERR_SETTING_TYPE" then
                ns.Print(L.ERR_SETTING_TYPE:format(tostring(scope), tostring(key)))
            else
                ns.Print(L.ERR_SETTING_CHOICE:format(tostring(scope), tostring(key), tostring(value)))
            end
        end
        return false
    end
    if not ns.db then
        return false
    end

    local v = value
    if def.type == "slider" then
        v = NormalizeSlider(def, value)
    end

    local store = GetStore(scope, true)
    store[key] = v

    ns.Fire("SETTING_CHANGED", scope, key, v)

    local module = modules[scope]
    -- 미지원 모듈은 OnSettingChanged 생략, dik, 2026-09-30
    if module and not module.unsupported and type(module.OnSettingChanged) == "function" then
        module:OnSettingChanged(key, v)
    end
    if key == "enabled" and not quiet then
        ns.Print(L.MSG_RELOAD_REQUIRED)
    end
    return true
end

-- 모듈 전용 데이터 테이블, dik, 2026-09-30
function ns.GetModuleData(id)
    if not ns.db then
        return nil
    end
    if type(ns.db.modules) ~= "table" then
        ns.db.modules = {}
    end
    if type(ns.db.modules[id]) ~= "table" then
        ns.db.modules[id] = {}
    end
    return ns.db.modules[id]
end

-- 모듈 지원 여부와 없는 API, dik, 2026-09-30
function ns.IsModuleSupported(id)
    local module = modules[id]
    if not module or module.unsupported == nil then
        return true, {}
    end
    local missing = {}
    local stored = module.missingApis or {}
    for i = 1, #stored do
        missing[i] = stored[i]
    end
    return not module.unsupported, missing
end

-- 설정 기본값 채움 후 활성 모듈 OnInitialize 호출, dik, 2026-09-30
function ns.InitializeModules()
    local fixTypes = not ns.IsDatabaseNewer()
    -- 미지원 판정 1회, dik, 2026-09-30
    for _, module in pairs(modules) do
        module.missingApis = ns.GetMissingAPIs(module.requires)
        module.unsupported = (#module.missingApis > 0)
    end
    for id in pairs(modules) do
        local store = GetStore(id, true)
        if store then
            local defs = ns.GetSettingDefs(id)
            for i = 1, #defs do
                local def = defs[i]
                local current = store[def.key]
                -- select 는 선택지 기준으로만 보정, dik, 2026-10-01
                if current == nil then
                    store[def.key] = def.default
                elseif fixTypes then
                    if def.type == "select" then
                        if not IsChoice(def, current) then
                            store[def.key] = def.default
                        end
                    elseif type(current) ~= type(def.default) then
                        store[def.key] = def.default
                    end
                end
            end
        end
    end

    local list = CollectModules(true)
    for i = 1, #list do
        local module = list[i]
        -- 미지원 모듈은 안내만 하고 OnInitialize 생략, dik, 2026-09-30
        if module.unsupported then
            ns.Print(L.MSG_MODULE_UNSUPPORTED:format(module.title, ns.FormatMissingAPIs(module.missingApis)))
        elseif type(module.OnInitialize) == "function" then
            xpcall(function() module:OnInitialize() end, geterrorhandler())
        end
    end
end
