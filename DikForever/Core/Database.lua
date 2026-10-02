-- SavedVariables 초기화·병합·마이그레이션, dik, 2026-09-30
local addonName, ns = ...

-- 스키마 버전 2 로 상향, dik, 2026-09-30
local SCHEMA_VERSION = 2

-- 기본값 표, dik, 2026-09-30
local DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    window = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 760,
        height = 480,
        lastPage = "home",
    },
    settings = {
        global = {
            scale = 1.0,
            fontSize = 12,
            lockWindow = false,
            rememberPage = true,
        },
        modules = {},
    },
    modules = {},
    chars = {},
}

-- 버전별 마이그레이션 함수 자리(MIGRATIONS[n] = n-1 -> n), dik, 2026-09-30
local MIGRATIONS = {}

-- v1 -> v2 chars 구조 정리, dik, 2026-09-30
MIGRATIONS[2] = function(db)
    if type(db.chars) ~= "table" then
        db.chars = {}
        return
    end
    local chars = db.chars
    local removeKeys = {}
    for key, entry in pairs(chars) do
        if type(key) ~= "string" or type(entry) ~= "table" then
            removeKeys[#removeKeys + 1] = key
        end
    end
    for i = 1, #removeKeys do
        chars[removeKeys[i]] = nil
    end
    for _, entry in pairs(chars) do
        if type(entry.info) ~= "table" then
            entry.info = {}
        end
        if type(entry.data) ~= "table" then
            entry.data = {}
        end
    end
end

local databaseNewer = false

-- 깊은 복사, dik, 2026-09-30
local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- 없는 키 채우기(fixTypes 면 타입 다른 키 교체), dik, 2026-09-30
local function MergeDefaults(target, defaults, fixTypes)
    for key, defValue in pairs(defaults) do
        local current = target[key]
        if current == nil then
            target[key] = DeepCopy(defValue)
        elseif type(defValue) == "table" and type(current) == "table" then
            MergeDefaults(current, defValue, fixTypes)
        elseif fixTypes and type(current) ~= type(defValue) then
            target[key] = DeepCopy(defValue)
        end
    end
end

-- DB 생성·병합·마이그레이션, dik, 2026-09-30
function ns.InitDatabase()
    databaseNewer = false
    if type(DikForeverDB) ~= "table" then
        DikForeverDB = DeepCopy(DEFAULTS)
        ns.db = DikForeverDB
        return
    end

    local stored = DikForeverDB.schemaVersion
    if type(stored) == "number" and stored > SCHEMA_VERSION then
        databaseNewer = true
    end

    if databaseNewer then
        MergeDefaults(DikForeverDB, DEFAULTS, false)
        ns.Print(ns.L.MSG_SCHEMA_NEWER)
    else
        if type(stored) == "number" then
            for version = stored + 1, SCHEMA_VERSION do
                local migrate = MIGRATIONS[version]
                if type(migrate) == "function" then
                    migrate(DikForeverDB)
                end
            end
        end
        MergeDefaults(DikForeverDB, DEFAULTS, true)
        DikForeverDB.schemaVersion = SCHEMA_VERSION
    end

    ns.db = DikForeverDB
end

-- 저장 데이터가 코드보다 새것인지, dik, 2026-09-30
function ns.IsDatabaseNewer()
    return databaseNewer
end

-- 창 위치·크기 기본값 복원, dik, 2026-09-30
function ns.ResetWindow()
    if not ns.db then
        return
    end
    local window = ns.db.window
    if type(window) ~= "table" then
        window = {}
        ns.db.window = window
    end
    local defaults = DEFAULTS.window
    window.point = defaults.point
    window.relativePoint = defaults.relativePoint
    window.x = defaults.x
    window.y = defaults.y
    window.width = defaults.width
    window.height = defaults.height
    ns.Fire("WINDOW_RESET")
end
