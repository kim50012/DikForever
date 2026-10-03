-- 레이아웃 칸 저장·불러오기 backend, dik, 2026-10-03
local addonName, ns = ...

local L = ns.L

local MODULE_ID = "layouts"
local AREA_VERSION = 1
local SLOT_COUNT = 5
local NAME_MAX_BYTES = 48
local EXPORT_PARTS = { settings = true, layout = true }

ns.Layouts = ns.Layouts or {}
ns.Layouts.SLOT_COUNT = SLOT_COUNT

-- 유한 number 판정, dik, 2026-10-03
local function IsFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 칸 번호 판정, dik, 2026-10-03
local function IsValidIndex(index)
    return IsFinite(index) and index == math.floor(index) and index >= 1 and index <= SLOT_COUNT
end

-- 영역 raw 읽기(생성 없음), dik, 2026-10-03
local function GetRawArea()
    local store = ns.db and ns.db.modules
    local area = type(store) == "table" and store[MODULE_ID] or nil
    if type(area) == "table" then
        return area
    end
    return nil
end

-- 칸 표 raw 읽기, dik, 2026-10-03
local function GetRawSlots()
    local area = GetRawArea()
    if area and type(area.slots) == "table" then
        return area.slots
    end
    return nil
end

-- 쓰기 가능 여부, dik, 2026-10-03
function ns.Layouts.IsWritable()
    if not ns.db or ns.IsDatabaseNewer() then
        return false
    end
    local area = GetRawArea()
    if area and type(area.version) == "number" and area.version > AREA_VERSION then
        return false
    end
    return true
end

-- 쓰기용 영역 확보, dik, 2026-10-03
local function GetWriteArea()
    local area = ns.GetModuleData(MODULE_ID)
    if not area then
        return nil
    end
    area.version = AREA_VERSION
    if type(area.slots) ~= "table" then
        area.slots = {}
    end
    return area
end

-- 칸 표시 이름, dik, 2026-10-03
local function DisplayName(index, name)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return string.format(L.LAYOUTS_SLOT_DEFAULT, index)
end

-- 개수 표 복사, dik, 2026-10-03
local function CopyCounts(counts)
    if type(counts) ~= "table" then
        return nil
    end
    local out = {}
    if IsFinite(counts.settings) then
        out.settings = counts.settings
    end
    if IsFinite(counts.layout) then
        out.layout = counts.layout
    end
    return out
end

-- 칸 목록(복사본, text 제외), dik, 2026-10-03
function ns.Layouts.GetSlots()
    local slots = GetRawSlots()
    local out = {}
    for i = 1, SLOT_COUNT do
        local raw = slots and slots[i]
        local name, created, counts
        local empty = true
        if type(raw) == "table" then
            if type(raw.name) == "string" and raw.name ~= "" then
                name = raw.name
            end
            if type(raw.text) == "string" then
                empty = false
                if IsFinite(raw.created) then
                    created = raw.created
                end
                counts = CopyCounts(raw.counts)
            end
        end
        out[i] = {
            index = i,
            name = name,
            displayName = DisplayName(i, name),
            empty = empty,
            created = created,
            counts = counts,
        }
    end
    return out
end

-- 현재 칸 이름 raw 조회, dik, 2026-10-03
local function GetRawName(index)
    local slots = GetRawSlots()
    local raw = slots and slots[index]
    if type(raw) == "table" and type(raw.name) == "string" and raw.name ~= "" then
        return raw.name
    end
    return nil
end

-- 칸 저장, dik, 2026-10-03
function ns.Layouts.Save(index)
    if not IsValidIndex(index) then
        return nil, "E-SLOT"
    end
    if not ns.Layouts.IsWritable() then
        return nil, "E-READONLY"
    end
    local text, counts = ns.Transfer.Export(EXPORT_PARTS)
    if type(text) ~= "string" or type(counts) ~= "table" then
        return nil, "E-EXPORT"
    end
    local area = GetWriteArea()
    if not area then
        return nil, "E-READONLY"
    end
    local name = GetRawName(index)
    local settingsCount = IsFinite(counts.settings) and counts.settings or 0
    local layoutCount = IsFinite(counts.layout) and counts.layout or 0
    area.slots[index] = {
        name = name,
        created = time(),
        text = text,
        counts = { settings = settingsCount, layout = layoutCount },
    }
    ns.Print(string.format(L.LAYOUTS_SAVED, DisplayName(index, name), settingsCount, layoutCount))
    ns.Fire("LAYOUTS_UPDATED", index)
    return { settings = settingsCount, layout = layoutCount }
end

-- 이름 정리(R2), dik, 2026-10-03
local function CleanName(name)
    if type(name) ~= "string" then
        return nil
    end
    local s = name:match("^%s*(.-)%s*$")
    s = s:gsub("|", "")
    s = s:gsub("%c", "")
    if s == "" then
        return nil
    end
    if #s > NAME_MAX_BYTES then
        local cut = NAME_MAX_BYTES
        while cut > 0 do
            local b = s:byte(cut + 1)
            if b and b >= 0x80 and b <= 0xBF then
                cut = cut - 1
            else
                break
            end
        end
        s = s:sub(1, cut)
        if s == "" then
            return nil
        end
    end
    return s
end

-- 칸 이름 변경, dik, 2026-10-03
function ns.Layouts.Rename(index, name)
    if not IsValidIndex(index) then
        return nil, "E-SLOT"
    end
    if not ns.Layouts.IsWritable() then
        return nil, "E-READONLY"
    end
    local area = GetWriteArea()
    if not area then
        return nil, "E-READONLY"
    end
    local clean = CleanName(name)
    local slot = area.slots[index]
    if type(slot) == "table" then
        slot.name = clean
        if clean == nil and type(slot.text) ~= "string" then
            area.slots[index] = nil
        end
    elseif clean ~= nil then
        area.slots[index] = { name = clean }
    end
    ns.Fire("LAYOUTS_UPDATED", index)
    return true
end

-- 칸 삭제, dik, 2026-10-03
function ns.Layouts.Delete(index)
    if not IsValidIndex(index) then
        return nil, "E-SLOT"
    end
    if not ns.Layouts.IsWritable() then
        return nil, "E-READONLY"
    end
    local slots = GetRawSlots()
    if not slots or slots[index] == nil then
        return false
    end
    slots[index] = nil
    ns.Fire("LAYOUTS_UPDATED", index)
    return true
end

-- 칸 불러오기, dik, 2026-10-03
function ns.Layouts.Load(index, _)
    if not IsValidIndex(index) then
        return nil, "E-SLOT"
    end
    if not ns.IsModuleEnabled(MODULE_ID) then
        return nil, "E-DISABLED"
    end
    local slots = GetRawSlots()
    local slot = slots and slots[index]
    if type(slot) ~= "table" or type(slot.text) ~= "string" then
        return nil, "E-EMPTY-SLOT"
    end
    if InCombatLockdown() then
        return nil, "E-COMBAT"
    end
    if not ns.Layouts.IsWritable() then
        return nil, "E-READONLY"
    end
    local preview = ns.Transfer.Inspect(slot.text)
    if not preview then
        return nil, "E-BROKEN"
    end
    local displayName = DisplayName(index, slot.name)
    local summary = string.format(L.LAYOUTS_LOAD_SUMMARY, (displayName:gsub("%%", "%%%%")))
    local result, err = ns.Transfer.Apply(preview, EXPORT_PARTS, { replaceHud = true, summary = summary })
    if not result then
        return nil, err
    end
    ns.Fire("LAYOUTS_LOADED", index, result)
    return result
end

-- 재시작 가능 여부, dik, 2026-10-03
function ns.Layouts.CanReload()
    return ns.HasAPI("ReloadUI") and not InCombatLockdown()
end

-- 재시작, dik, 2026-10-03
function ns.Layouts.Reload()
    if ns.Layouts.CanReload() then
        ReloadUI()
    end
end

-- 오류 코드 문장, dik, 2026-10-03
function ns.Layouts.GetErrorText(errCode, index)
    if errCode == "E-SLOT" then
        return L.LAYOUTS_ERR_SLOT
    elseif errCode == "E-DISABLED" then
        return L.LAYOUTS_ERR_DISABLED
    elseif errCode == "E-BROKEN" then
        return L.LAYOUTS_ERR_BROKEN
    elseif errCode == "E-EMPTY-SLOT" then
        return string.format(L.LAYOUTS_ERR_EMPTY_SLOT, IsFinite(index) and index or 0)
    elseif errCode == "E-COMBAT" or errCode == "E-READONLY" or errCode == "E-EXPORT" then
        return ns.Transfer.GetErrorText(errCode)
    end
    return L.LAYOUTS_ERR_BROKEN
end

-- 레이아웃 모듈 등록, dik, 2026-10-03
ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_LAYOUTS,
    description = L.MODULE_LAYOUTS_DESC,
    category = "feature",
    order = 95,
    settings = {},
})
