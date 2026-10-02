-- 설정 이전 backend(수집·검사·적용·백업), dik, 2026-10-02
local addonName, ns = ...

local L = ns.L

local MODULE_ID = "transfer"
local PAYLOAD_VERSION = 1
local ADDON_ID = "DikForever"
local MAX_SCHEMA = 2
local AREA_VERSION = 1
local HUD_VERSION = 1
local POS_LIMIT = 10000
local KEY_MAX_LEN = 32
local PARTS = { "settings", "layout", "lists", "editMode" }
local APPLY_PARTS = { "settings", "layout", "lists" }
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local WINDOW_FIELDS = { "point", "relativePoint", "x", "y", "width", "height" }
local QUIET = { quiet = true }
local ERROR_KEYS = {
    ["E-LEN"] = "TRANSFER_ERR_LEN",
    ["E-FMT"] = "TRANSFER_ERR_FMT",
    ["E-VER"] = "TRANSFER_ERR_VER",
    ["E-SUM"] = "TRANSFER_ERR_SUM",
    ["E-COMBAT"] = "TRANSFER_ERR_COMBAT",
    ["E-READONLY"] = "TRANSFER_ERR_READONLY",
    ["E-BAK"] = "TRANSFER_ERR_BAK",
    ["E-EMPTY"] = "TRANSFER_ERR_EMPTY",
    ["E-EXPORT"] = "TRANSFER_ERR_EXPORT",
}

ns.Transfer = ns.Transfer or {}
ns.Transfer.PARTS = PARTS

-- 유한 number 판정, dik, 2026-10-02
local function IsFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 표 키 개수, dik, 2026-10-02
local function CountKeys(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do
            n = n + 1
        end
    end
    return n
end

-- 위치 숫자 검증·정수화, dik, 2026-10-02
local function NormalizePos(v)
    if IsFinite(v) and math.abs(v) <= POS_LIMIT then
        return true, math.floor(v + 0.5)
    end
    return false
end

-- 창 필드 검증, dik, 2026-10-02
local function ValidateWindowField(name, v)
    if name == "point" or name == "relativePoint" then
        return type(v) == "string" and ANCHORS[v] == true, v
    elseif name == "x" or name == "y" then
        return NormalizePos(v)
    elseif name == "width" then
        if IsFinite(v) and v >= 400 and v <= 2000 then
            return true, math.floor(v + 0.5)
        end
    elseif name == "height" then
        if IsFinite(v) and v >= 300 and v <= 1500 then
            return true, math.floor(v + 0.5)
        end
    end
    return false
end

-- HUD 엔트리 검증(새 표 반환), dik, 2026-10-02
local function ValidateHudEntry(e)
    if type(e) ~= "table" then
        return nil
    end
    if type(e.point) ~= "string" or not ANCHORS[e.point] then
        return nil
    end
    if type(e.relativePoint) ~= "string" or not ANCHORS[e.relativePoint] then
        return nil
    end
    local okX, x = NormalizePos(e.x)
    local okY, y = NormalizePos(e.y)
    if not okX or not okY then
        return nil
    end
    return { point = e.point, relativePoint = e.relativePoint, x = x, y = y }
end

-- HUD 키 유효 판정, dik, 2026-10-02
local function IsValidHudKey(key)
    return type(key) == "string" and #key <= KEY_MAX_LEN and key ~= "version"
        and key:find("^[%w_]+$") ~= nil
end

-- 설정값 직렬화 가능 판정, dik, 2026-10-02
local function IsPlainSettingValue(v)
    local t = type(v)
    if t == "boolean" then
        return true
    elseif t == "number" then
        return IsFinite(v)
    elseif t == "string" then
        return #v <= 20000
    end
    return false
end

-- P1 설정 수집, dik, 2026-10-02
local function CollectSettings()
    local out = { global = {}, modules = {} }
    local count = 0
    local settings = ns.db and ns.db.settings
    if type(settings) ~= "table" then
        return out, 0
    end
    if type(settings.global) == "table" then
        local defs = ns.GetSettingDefs("global")
        for i = 1, #defs do
            local key = defs[i].key
            local v = settings.global[key]
            if v ~= nil and IsPlainSettingValue(v) and ns.ValidateSetting("global", key, v) then
                out.global[key] = v
                count = count + 1
            end
        end
    end
    if type(settings.modules) == "table" then
        local list = ns.GetAllModules()
        for i = 1, #list do
            local id = list[i].id
            local store = settings.modules[id]
            if id ~= MODULE_ID and type(store) == "table" then
                local defs = ns.GetSettingDefs(id)
                local picked
                for j = 1, #defs do
                    local key = defs[j].key
                    local v = store[key]
                    if v ~= nil and IsPlainSettingValue(v) and ns.ValidateSetting(id, key, v) then
                        picked = picked or {}
                        picked[key] = v
                        count = count + 1
                    end
                end
                if picked then
                    out.modules[id] = picked
                end
            end
        end
    end
    return out, count
end

-- P2 배치 수집, dik, 2026-10-02
local function CollectLayout()
    local out = { hud = {} }
    local count = 0
    local window = ns.db and ns.db.window
    if type(window) == "table" then
        local picked
        for i = 1, #WINDOW_FIELDS do
            local name = WINDOW_FIELDS[i]
            if window[name] ~= nil then
                local ok, v = ValidateWindowField(name, window[name])
                if ok then
                    picked = picked or {}
                    picked[name] = v
                end
            end
        end
        if picked then
            out.window = picked
            count = count + 1
        end
    end
    local store = ns.db and ns.db.modules
    if type(store) == "table" then
        local list = ns.GetAllModules()
        for i = 1, #list do
            local id = list[i].id
            local area = store[id]
            local hud = type(area) == "table" and area.hud or nil
            if type(hud) == "table" and hud.version == HUD_VERSION then
                local picked
                for key, entry in pairs(hud) do
                    if IsValidHudKey(key) then
                        local copy = ValidateHudEntry(entry)
                        if copy then
                            picked = picked or {}
                            picked[key] = copy
                            count = count + 1
                        end
                    end
                end
                if picked then
                    out.hud[id] = picked
                end
            end
        end
    end
    return out, count
end

-- 파티 모집 준비 판정(쓰기 없음), dik, 2026-10-02
local function IsLfgReady()
    if type(ns.Lfg) ~= "table" or type(ns.Lfg.AddCustomWord) ~= "function" then
        return false
    end
    local _, code = ns.Lfg.AddCustomWord(nil)
    return code ~= "LFG_ERR_NOT_READY"
end

-- 쇼핑 적용 가능 추정(드라이런), dik, 2026-10-02
local function IsShoppingUsable()
    if type(ns.Shopping) ~= "table" or type(ns.Shopping.ImportTargets) ~= "function" then
        return false
    end
    local supported = ns.IsModuleSupported("shopping")
    return ns.IsModuleEnabled("shopping") and supported
end

-- P3 목록 수집, dik, 2026-10-02
local function CollectLists()
    local out = {}
    local count = 0
    -- 준비 전 목록은 키 생략, dik, 2026-10-02
    if IsShoppingUsable() and type(ns.Shopping.ExportTargets) == "function" then
        local rows = {}
        local src = ns.Shopping.ExportTargets()
        if type(src) == "table" then
            for i = 1, #src do
                local r = src[i]
                if type(r) == "table" and IsFinite(r.recipe) and IsFinite(r.count) then
                    rows[#rows + 1] = { recipe = r.recipe, count = r.count }
                end
            end
        end
        out.shopping = rows
        count = count + #rows
    end
    if IsLfgReady() and type(ns.Lfg.ExportCustomWords) == "function" then
        local rows = {}
        local src = ns.Lfg.ExportCustomWords()
        if type(src) == "table" then
            for i = 1, #src do
                local r = src[i]
                if type(r) == "table" and type(r.word) == "string" and r.word ~= "" then
                    local row = { word = r.word }
                    if type(r.dungeon) == "string" then
                        row.dungeon = r.dungeon
                    end
                    rows[#rows + 1] = row
                end
            end
        end
        out.lfg = rows
        count = count + #rows
    end
    return out, count
end

-- P4 편집 모드 레이아웃 수집, dik, 2026-10-02
local function CollectEditMode()
    local rows = {}
    if not ns.HasAPI("C_EditMode.GetLayouts") or not ns.HasAPI("C_EditMode.ConvertLayoutInfoToString") then
        return rows, false
    end
    local ok, info = xpcall(function() return C_EditMode.GetLayouts() end, geterrorhandler())
    if not ok or ns.IsSecret(info) or type(info) ~= "table" or type(info.layouts) ~= "table" then
        return rows, true
    end
    local enumType = type(Enum) == "table" and Enum.EditModeLayoutType or nil
    for i = 1, #info.layouts do
        local layout = info.layouts[i]
        if not ns.IsSecret(layout) and type(layout) == "table" then
            local name = layout.layoutName
            local okShare, share = xpcall(function()
                return C_EditMode.ConvertLayoutInfoToString(layout)
            end, geterrorhandler())
            if okShare and not ns.IsSecret(share) and type(share) == "string" and share ~= ""
                and not ns.IsSecret(name) and type(name) == "string" then
                local kind = "other"
                local layoutType = layout.layoutType
                if type(enumType) == "table" and not ns.IsSecret(layoutType) then
                    if layoutType == enumType.Account then
                        kind = "account"
                    elseif layoutType == enumType.Character then
                        kind = "character"
                    end
                end
                rows[#rows + 1] = { name = name, kind = kind, share = share }
            end
        end
    end
    return rows, true
end

-- 편집 모드 상태, dik, 2026-10-02
function ns.Transfer.GetEditModeStatus()
    local rows, available = CollectEditMode()
    if not available then
        return "missing"
    end
    if #rows == 0 then
        return "empty"
    end
    return "ok"
end

-- 체크 항목 수집, dik, 2026-10-02
local function CollectParts(partsSet)
    local parts, counts = {}, { settings = 0, layout = 0, lists = 0, editMode = 0 }
    if partsSet.settings then
        parts.settings, counts.settings = CollectSettings()
    end
    if partsSet.layout then
        parts.layout, counts.layout = CollectLayout()
    end
    if partsSet.lists then
        parts.lists, counts.lists = CollectLists()
    end
    if partsSet.editMode then
        local rows = CollectEditMode()
        if #rows > 0 then
            parts.editMode = { layouts = rows }
            counts.editMode = #rows
        end
    end
    return parts, counts
end

-- 페이로드 생성·직렬화, dik, 2026-10-02
local function BuildString(parts)
    local payload = {
        v = PAYLOAD_VERSION,
        addon = ADDON_ID,
        created = time(),
        src = { schema = ns.db and ns.db.schemaVersion or MAX_SCHEMA },
        parts = parts,
    }
    local text = ns.Serialize.Encode(payload)
    if type(text) ~= "string" then
        return nil
    end
    return text
end

-- 체크 항목 존재 판정, dik, 2026-10-02
local function HasAnyPart(partsSet)
    if type(partsSet) ~= "table" then
        return false
    end
    for i = 1, #PARTS do
        if partsSet[PARTS[i]] then
            return true
        end
    end
    return false
end

-- 내보내기, dik, 2026-10-02
function ns.Transfer.Export(partsSet)
    if not HasAnyPart(partsSet) then
        return nil, "E-EMPTY"
    end
    local parts, counts = CollectParts(partsSet)
    local text = BuildString(parts)
    if not text then
        return nil, "E-EXPORT"
    end
    return text, counts
end

-- 설정 적용 계획(쓰기 없음), dik, 2026-10-02
local function PlanSettings(data)
    local ops, skipped = {}, 0
    if type(data.global) == "table" then
        for key, v in pairs(data.global) do
            local ok, norm = false, nil
            if type(key) == "string" then
                ok, norm = ns.ValidateSetting("global", key, v)
            end
            if ok then
                ops[#ops + 1] = { scope = "global", key = key, value = norm == nil and v or norm }
            else
                skipped = skipped + 1
            end
        end
    end
    if type(data.modules) == "table" then
        for id, store in pairs(data.modules) do
            if type(store) ~= "table" then
                skipped = skipped + 1
            elseif type(id) ~= "string" or id == MODULE_ID or not ns.GetModule(id) then
                skipped = skipped + math.max(1, CountKeys(store))
            else
                for key, v in pairs(store) do
                    local ok, norm = false, nil
                    if type(key) == "string" then
                        ok, norm = ns.ValidateSetting(id, key, v)
                    end
                    if ok then
                        ops[#ops + 1] = { scope = id, key = key, value = norm == nil and v or norm }
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    return ops, skipped
end

-- HUD 대상 영역 쓰기 가능 판정(raw), dik, 2026-10-02
local function CanWriteHud(id)
    local store = ns.db and ns.db.modules
    local area = type(store) == "table" and store[id] or nil
    local hud = type(area) == "table" and area.hud or nil
    if hud == nil then
        return true
    end
    return type(hud) == "table" and (hud.version == nil or hud.version == HUD_VERSION)
end

-- 배치 적용 계획(쓰기 없음), dik, 2026-10-02
local function PlanLayout(data)
    local plan = { fields = nil, hud = {}, skipped = 0 }
    if type(data.window) == "table" then
        for i = 1, #WINDOW_FIELDS do
            local name = WINDOW_FIELDS[i]
            local raw = data.window[name]
            if raw ~= nil then
                local ok, v = ValidateWindowField(name, raw)
                if ok then
                    plan.fields = plan.fields or {}
                    plan.fields[name] = v
                else
                    plan.skipped = plan.skipped + 1
                end
            end
        end
    end
    if type(data.hud) == "table" then
        for id, entries in pairs(data.hud) do
            if type(entries) ~= "table" then
                plan.skipped = plan.skipped + 1
            elseif type(id) ~= "string" or not ns.GetModule(id) or not CanWriteHud(id) then
                plan.skipped = plan.skipped + math.max(1, CountKeys(entries))
            else
                for key, entry in pairs(entries) do
                    local copy = IsValidHudKey(key) and ValidateHudEntry(entry) or nil
                    if copy then
                        plan.hud[#plan.hud + 1] = { id = id, key = key, entry = copy }
                    else
                        plan.skipped = plan.skipped + 1
                    end
                end
            end
        end
    end
    return plan
end

-- 목록 행 형식 검증, dik, 2026-10-02
local function PlanLists(data)
    local plan = { shopping = {}, shoppingTotal = 0, lfg = {}, lfgTotal = 0, skipped = 0 }
    if type(data.shopping) == "table" then
        plan.shoppingTotal = #data.shopping
        for i = 1, #data.shopping do
            local r = data.shopping[i]
            if type(r) == "table" and IsFinite(r.recipe) and r.recipe >= 1
                and r.recipe == math.floor(r.recipe) and IsFinite(r.count) then
                plan.shopping[#plan.shopping + 1] = { recipe = r.recipe, count = r.count }
            else
                plan.skipped = plan.skipped + 1
            end
        end
    end
    if type(data.lfg) == "table" then
        plan.lfgTotal = #data.lfg
        for i = 1, #data.lfg do
            local r = data.lfg[i]
            if type(r) == "table" and type(r.word) == "string" and r.word ~= ""
                and (r.dungeon == nil or type(r.dungeon) == "string") then
                plan.lfg[#plan.lfg + 1] = { word = r.word, dungeon = r.dungeon }
            else
                plan.skipped = plan.skipped + 1
            end
        end
    end
    return plan
end

-- 페이로드 개수(R8), dik, 2026-10-02
local function CountPayload(parts)
    local counts = { settings = 0, layout = 0, lists = 0, editMode = 0 }
    local s = parts.settings
    if type(s) == "table" then
        counts.settings = CountKeys(s.global)
        if type(s.modules) == "table" then
            for _, store in pairs(s.modules) do
                counts.settings = counts.settings + CountKeys(store)
            end
        end
    end
    local l = parts.layout
    if type(l) == "table" then
        if type(l.window) == "table" and next(l.window) ~= nil then
            counts.layout = 1
        end
        if type(l.hud) == "table" then
            for _, entries in pairs(l.hud) do
                counts.layout = counts.layout + CountKeys(entries)
            end
        end
    end
    local li = parts.lists
    if type(li) == "table" then
        counts.lists = (type(li.shopping) == "table" and #li.shopping or 0)
            + (type(li.lfg) == "table" and #li.lfg or 0)
    end
    return counts
end

-- 페이로드 레이아웃 행 추출, dik, 2026-10-02
local function ExtractLayouts(parts)
    local rows = {}
    local em = parts.editMode
    if type(em) == "table" and type(em.layouts) == "table" then
        for i = 1, #em.layouts do
            local r = em.layouts[i]
            if type(r) == "table" and type(r.name) == "string" and type(r.share) == "string"
                and r.share ~= "" then
                local kind = r.kind
                if kind ~= "account" and kind ~= "character" then
                    kind = "other"
                end
                rows[#rows + 1] = { name = r.name, kind = kind, share = r.share }
            end
        end
    end
    return rows
end

-- 문자열 해석·최상위 검사, dik, 2026-10-02
local function ParseText(text)
    local payload, err = ns.Serialize.Decode(text)
    if not payload then
        return nil, err or "E-FMT"
    end
    if type(payload) ~= "table" then
        return nil, "E-FMT"
    end
    local src = payload.src
    if payload.v ~= PAYLOAD_VERSION or payload.addon ~= ADDON_ID or type(src) ~= "table"
        or type(src.schema) ~= "number" or src.schema > MAX_SCHEMA then
        return nil, "E-VER"
    end
    if type(payload.parts) ~= "table" then
        return nil, "E-FMT"
    end
    return payload
end

-- 검사(드라이런), dik, 2026-10-02
function ns.Transfer.Inspect(text)
    local payload, err = ParseText(text)
    if not payload then
        return nil, err
    end
    local parts = payload.parts
    local counts = CountPayload(parts)
    local skipped = 0
    if type(parts.settings) == "table" then
        local _, sk = PlanSettings(parts.settings)
        skipped = skipped + sk
    end
    if type(parts.layout) == "table" then
        skipped = skipped + PlanLayout(parts.layout).skipped
    end
    if type(parts.lists) == "table" then
        local plan = PlanLists(parts.lists)
        skipped = skipped + plan.skipped
        if #plan.shopping > 0 and not IsShoppingUsable() then
            skipped = skipped + #plan.shopping
        end
        if #plan.lfg > 0 and not IsLfgReady() then
            skipped = skipped + #plan.lfg
        end
    end
    local layouts = ExtractLayouts(parts)
    counts.editMode = #layouts
    return {
        created = type(payload.created) == "number" and payload.created or nil,
        counts = counts,
        skipped = skipped,
        layouts = layouts,
        payload = payload,
    }
end

-- HUD 키 전부 삭제(version 제외, raw), dik, 2026-10-02
local function ClearWritableHud()
    local store = ns.db and ns.db.modules
    if type(store) ~= "table" then
        return
    end
    local list = ns.GetAllModules()
    for i = 1, #list do
        local id = list[i].id
        local area = store[id]
        local hud = type(area) == "table" and area.hud or nil
        if type(hud) == "table" and CanWriteHud(id) then
            for key in pairs(hud) do
                if key ~= "version" then
                    hud[key] = nil
                end
            end
        end
    end
end

-- 항목 적용 실행(P1 → P3 → P2), dik, 2026-10-02
local function RunParts(parts, active, restore)
    local applied, skipped, reload = 0, 0, false
    if active.settings and type(parts.settings) == "table" then
        local ops, sk = PlanSettings(parts.settings)
        skipped = skipped + sk
        for i = 1, #ops do
            local op = ops[i]
            local before = ns.GetSetting(op.scope, op.key)
            if ns.SetSetting(op.scope, op.key, op.value, QUIET) then
                applied = applied + 1
                if op.key == "enabled" and before ~= op.value then
                    reload = true
                end
            else
                skipped = skipped + 1
            end
        end
    end
    if active.lists and type(parts.lists) == "table" then
        local plan = PlanLists(parts.lists)
        skipped = skipped + plan.skipped
        if type(parts.lists.shopping) == "table" then
            local a, s
            if type(ns.Shopping) == "table" and type(ns.Shopping.ImportTargets) == "function" then
                a, s = ns.Shopping.ImportTargets(plan.shopping)
            end
            if a == nil then
                skipped = skipped + #plan.shopping
            else
                applied = applied + a
                skipped = skipped + (s or 0)
            end
        end
        -- 빈 목록도 교체 대상, dik, 2026-10-02
        if type(parts.lists.lfg) == "table" then
            if not IsLfgReady() then
                skipped = skipped + #plan.lfg
            else
                if type(ns.Lfg.ExportCustomWords) == "function" then
                    local current = ns.Lfg.ExportCustomWords()
                    for i = 1, #current do
                        ns.Lfg.RemoveCustomWord(current[i].word)
                    end
                end
                for i = 1, #plan.lfg do
                    if ns.Lfg.AddCustomWord(plan.lfg[i].word, plan.lfg[i].dungeon) then
                        applied = applied + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    if active.layout and type(parts.layout) == "table" then
        local plan = PlanLayout(parts.layout)
        skipped = skipped + plan.skipped
        -- 되돌리기 시 HUD 키 초기화 후 복원, dik, 2026-10-02
        if restore then
            ClearWritableHud()
        end
        if plan.fields then
            if type(ns.db.window) ~= "table" then
                ns.db.window = {}
            end
            for name, v in pairs(plan.fields) do
                ns.db.window[name] = v
            end
            applied = applied + 1
            reload = true
        end
        for i = 1, #plan.hud do
            local op = plan.hud[i]
            local area = ns.GetModuleData(op.id)
            if area then
                if type(area.hud) ~= "table" then
                    area.hud = {}
                end
                if area.hud.version == nil then
                    area.hud.version = HUD_VERSION
                end
                area.hud[op.key] = op.entry
                applied = applied + 1
                reload = true
            else
                skipped = skipped + 1
            end
        end
    end
    return { applied = applied, skipped = skipped, reload = reload }
end

-- 쓰기 전 공통 차단 판정, dik, 2026-10-02
local function CheckWritable()
    if InCombatLockdown() then
        return "E-COMBAT"
    end
    if ns.IsDatabaseNewer() or not ns.db then
        return "E-READONLY"
    end
    return nil
end

-- 이전 영역 version 이 코드보다 새것인지, dik, 2026-10-02
local function IsAreaNewer()
    local store = ns.db.modules
    local area = type(store) == "table" and store[MODULE_ID] or nil
    return type(area) == "table" and type(area.version) == "number" and area.version > AREA_VERSION
end

-- 적용 대상 항목 집합, dik, 2026-10-02
local function BuildActive(partsSet, parts)
    local active = {}
    if type(partsSet) == "table" and type(parts) == "table" then
        for i = 1, #APPLY_PARTS do
            local name = APPLY_PARTS[i]
            if partsSet[name] and type(parts[name]) == "table" then
                active[name] = true
            end
        end
    end
    return active
end

-- 결과 출력·이벤트 발행, dik, 2026-10-02
local function Finish(result, summaryText)
    ns.Print(string.format(summaryText, result.applied, result.skipped))
    if result.reload then
        ns.Print(L.TRANSFER_RELOAD)
    end
    ns.Fire("TRANSFER_APPLIED", result)
end

-- 적용(백업 후), dik, 2026-10-02
function ns.Transfer.Apply(preview, partsSet)
    local blocked = CheckWritable()
    if blocked then
        return nil, blocked
    end
    local parts = type(preview) == "table" and type(preview.payload) == "table"
        and preview.payload.parts or nil
    local active = BuildActive(partsSet, parts)
    if next(active) == nil then
        return nil, "E-EMPTY"
    end
    if IsAreaNewer() then
        return nil, "E-READONLY"
    end

    local backupParts, names = CollectParts(active), {}
    local data = BuildString(backupParts)
    if not data then
        return nil, "E-EXPORT"
    end
    for i = 1, #APPLY_PARTS do
        if active[APPLY_PARTS[i]] then
            names[#names + 1] = APPLY_PARTS[i]
        end
    end
    local area = ns.GetModuleData(MODULE_ID)
    area.version = AREA_VERSION
    area.backup = { created = time(), parts = names, data = data }

    local result = RunParts(parts, active)
    Finish(result, L.TRANSFER_SUMMARY)
    return result
end

-- 백업 원본 조회(raw), dik, 2026-10-02
local function GetBackup()
    local store = ns.db and ns.db.modules
    local area = type(store) == "table" and store[MODULE_ID] or nil
    local backup = type(area) == "table" and area.backup or nil
    if type(backup) == "table" and type(backup.data) == "string" then
        return backup
    end
    return nil
end

-- 백업 유무, dik, 2026-10-02
function ns.Transfer.HasBackup()
    local backup = GetBackup()
    if backup then
        return true, backup.created
    end
    return false
end

-- 되돌리기, dik, 2026-10-02
function ns.Transfer.Undo()
    local blocked = CheckWritable()
    if blocked then
        return nil, blocked
    end
    local backup = GetBackup()
    if not backup or type(backup.parts) ~= "table" then
        return nil, "E-BAK"
    end
    if IsAreaNewer() then
        return nil, "E-READONLY"
    end
    local payload = ParseText(backup.data)
    if not payload then
        return nil, "E-BAK"
    end
    local partsSet = {}
    for i = 1, #backup.parts do
        partsSet[backup.parts[i]] = true
    end
    local active = BuildActive(partsSet, payload.parts)
    if next(active) == nil then
        return nil, "E-BAK"
    end
    local result = RunParts(payload.parts, active, true)
    local area = ns.GetModuleData(MODULE_ID)
    area.backup = nil
    Finish(result, L.TRANSFER_UNDO_SUMMARY)
    return result
end

-- 오류 코드 문장, dik, 2026-10-02
function ns.Transfer.GetErrorText(errCode)
    local key = ERROR_KEYS[errCode] or "TRANSFER_ERR_FMT"
    return L[key]
end

-- 로그아웃 시 배포 프리셋 기록, dik, 2026-10-02
local function SaveDistPreset()
    if not ns.db or ns.IsDatabaseNewer() or IsAreaNewer() then
        return
    end
    local ok, text = xpcall(function()
        return ns.Transfer.Export({ settings = true, layout = true, editMode = true })
    end, geterrorhandler())
    if not ok or type(text) ~= "string" then
        return
    end
    local area = ns.GetModuleData(MODULE_ID)
    if area.version == nil then
        area.version = AREA_VERSION
    end
    area.distPreset = { created = time(), text = text }
end

-- 로그아웃 수집 프레임 생성, dik, 2026-10-02
local function InitializeTracking()
    if not ns.HasAPI("CreateFrame") then
        return
    end
    local frame = CreateFrame("Frame")
    local ok = pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")
    if not ok then
        return
    end
    frame:SetScript("OnEvent", SaveDistPreset)
end

-- 설정 이전 모듈 등록, dik, 2026-10-02
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_TRANSFER,
    description = L.MODULE_TRANSFER_DESC,
    category = "feature",
    order = 100,
    settings = {},
    OnInitialize = InitializeTracking,
})
