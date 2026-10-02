-- 대상 거리 모듈 등록·거리 확인 어댑터·순수 함수, dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "range"

-- 유한 number 판정(secret 아닌 값 전용), dik, 2026-10-02
local function IsNumber(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 대상 거리 공개 테이블·상수, dik, 2026-10-02
ns.Range = {}
ns.Range.MODULE_ID = MODULE_ID

ns.Range.HUD_MAIN = {
    label = L.HUD_LABEL_RANGE, point = "CENTER", relativePoint = "CENTER",
    x = 0, y = -80, strata = "LOW",
}

ns.Range.HUD_WIDTH = 200
ns.Range.HUD_HEIGHT = 28
ns.Range.MELEE_YARDS = 5
ns.Range.MAX_YARDS = 100
ns.Range.SPELLS_PER_RANGE = 3

ns.Range.INTERACT_CHECKS = {
    { yards = 10, index = 3 },
    { yards = 28, index = 4 },
}

ns.Range.RED_MAX = 8
ns.Range.YELLOW_MAX = 30
ns.Range.GRAY_MIN = 35
ns.Range.UPDATE_INTERVAL = 0.1

ns.Range.EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "SPELLS_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "UNIT_FLAGS",
}

-- 공격 주문 여부(secret·오류는 거짓), dik, 2026-10-02
local function IsHarmful(spellID)
    if not ns.HasAPI("C_Spell.IsSpellHarmful") then
        return false
    end
    local ok, r = xpcall(function() return C_Spell.IsSpellHarmful(spellID) end, geterrorhandler())
    if not ok or ns.IsSecret(r) then
        return false
    end
    return r == true
end

-- 주문 사거리 읽기(minRange, maxRange 반환, 실패 시 nil), dik, 2026-10-02
local function ReadSpellRange(spellID)
    local ok, info = xpcall(function() return C_Spell.GetSpellInfo(spellID) end, geterrorhandler())
    if not ok or ns.IsSecret(info) or type(info) ~= "table" then
        return nil, nil
    end
    local minRange = info.minRange
    local maxRange = info.maxRange
    if ns.IsSecret(minRange) or ns.IsSecret(maxRange) then
        return nil, nil
    end
    if minRange == nil then
        minRange = 0
    end
    if maxRange == nil then
        maxRange = 0
    end
    if not IsNumber(minRange) or not IsNumber(maxRange) then
        return nil, nil
    end
    return minRange, maxRange
end

-- 주문책 칸 정보 읽기(spellID 반환, 후보 아니면 nil), dik, 2026-10-02
local function ReadSlotSpell(slot)
    local ok, info = xpcall(function()
        return C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
    end, geterrorhandler())
    if not ok or ns.IsSecret(info) or type(info) ~= "table" then
        return nil
    end
    local itemType = info.itemType
    local spellID = info.spellID
    local isPassive = info.isPassive
    local isOffSpec = info.isOffSpec
    if ns.IsSecret(itemType) or ns.IsSecret(spellID) or ns.IsSecret(isPassive) or ns.IsSecret(isOffSpec) then
        return nil
    end
    if itemType ~= Enum.SpellBookItemType.Spell or isPassive == true or isOffSpec == true then
        return nil
    end
    if not IsNumber(spellID) then
        return nil
    end
    return spellID
end

-- 주문책 후보 수집(야드별 목록 맵 반환), dik, 2026-10-02
local function CollectCandidates()
    local byYards = {}
    local seen = {}
    local okN, numLines = xpcall(function() return C_SpellBook.GetNumSpellBookSkillLines() end, geterrorhandler())
    if not okN or ns.IsSecret(numLines) or not IsNumber(numLines) then
        return byYards
    end
    for line = 1, numLines do
        local okL, lineInfo = xpcall(function() return C_SpellBook.GetSpellBookSkillLineInfo(line) end, geterrorhandler())
        if okL and not ns.IsSecret(lineInfo) and type(lineInfo) == "table" then
            local offset = lineInfo.itemIndexOffset
            local count = lineInfo.numSpellBookItems
            if not ns.IsSecret(offset) and not ns.IsSecret(count) and IsNumber(offset) and IsNumber(count) then
                for i = 1, count do
                    local spellID = ReadSlotSpell(offset + i)
                    if spellID and not seen[spellID] then
                        seen[spellID] = true
                        local minRange, maxRange = ReadSpellRange(spellID)
                        if minRange == 0 then
                            local yards = ns.Range.MELEE_YARDS
                            if maxRange > 0 then
                                yards = maxRange
                            end
                            if yards <= ns.Range.MAX_YARDS then
                                local list = byYards[yards]
                                if not list then
                                    list = {}
                                    byYards[yards] = list
                                end
                                list[#list + 1] = { spellID = spellID, harmful = IsHarmful(spellID) }
                            end
                        end
                    end
                end
            end
        end
    end
    return byYards
end

-- 확인 목록 정렬 비교(야드 오름차순, 같으면 주문 묶음 먼저), dik, 2026-10-02
local function CompareItems(a, b)
    if a.yards ~= b.yards then
        return a.yards < b.yards
    end
    return a.interact == nil and b.interact ~= nil
end

-- 확인 목록 생성(G1), dik, 2026-10-02
function ns.Range.BuildCheckers()
    local checkers = {}
    if ns.HasAPI("C_Spell.GetSpellInfo") and ns.HasAPI("C_SpellBook.GetNumSpellBookSkillLines")
        and ns.HasAPI("C_SpellBook.GetSpellBookSkillLineInfo") and ns.HasAPI("C_SpellBook.GetSpellBookItemInfo") then
        for yards, list in pairs(CollectCandidates()) do
            local spells = {}
            for _, c in ipairs(list) do
                if c.harmful and #spells < ns.Range.SPELLS_PER_RANGE then
                    spells[#spells + 1] = c.spellID
                end
            end
            for _, c in ipairs(list) do
                if not c.harmful and #spells < ns.Range.SPELLS_PER_RANGE then
                    spells[#spells + 1] = c.spellID
                end
            end
            checkers[#checkers + 1] = { yards = yards, spells = spells, bad = {} }
        end
    end
    if ns.HasAPI("CheckInteractDistance") then
        for _, check in ipairs(ns.Range.INTERACT_CHECKS) do
            checkers[#checkers + 1] = { yards = check.yards, interact = check.index }
        end
    end
    table.sort(checkers, CompareItems)
    return checkers
end

-- 주문 묶음 확인(true·false·nil), dik, 2026-10-02
local function ProbeSpells(item)
    for _, spellID in ipairs(item.spells) do
        if not item.bad[spellID] then
            local ok, r = xpcall(function() return C_Spell.IsSpellInRange(spellID, "target") end, geterrorhandler())
            if not ok then
                item.bad[spellID] = true
            elseif not ns.IsSecret(r) and (r == true or r == false) then
                return r
            end
        end
    end
    return nil
end

-- 상호작용 거리 확인(true·false·nil), dik, 2026-10-02
local function ProbeInteract(item)
    if item.failed then
        return nil
    end
    local ok, r = xpcall(function() return CheckInteractDistance("target", item.interact) end, geterrorhandler())
    if not ok then
        item.failed = true
        return nil
    end
    if ns.IsSecret(r) then
        return nil
    end
    if r == true or r == false then
        return r
    end
    return nil
end

-- 한 번 확인(G2), dik, 2026-10-02
function ns.Range.Probe(checkers, inCombat)
    local probe = {}
    if type(checkers) ~= "table" then
        return probe
    end
    for _, item in ipairs(checkers) do
        local result = nil
        if item.interact then
            if inCombat ~= true then
                result = ProbeInteract(item)
            end
        elseif item.spells then
            result = ProbeSpells(item)
        end
        probe[#probe + 1] = { yards = item.yards, result = result }
    end
    return probe
end

-- 구간 계산(G3 순수), dik, 2026-10-02
function ns.Range.CalcBracket(probe)
    if type(probe) ~= "table" then
        return nil, nil
    end
    local upper = nil
    for _, e in ipairs(probe) do
        if type(e) == "table" and e.result == true and IsNumber(e.yards) then
            if upper == nil or e.yards < upper then
                upper = e.yards
            end
        end
    end
    local lower = nil
    for _, e in ipairs(probe) do
        if type(e) == "table" and e.result == false and IsNumber(e.yards) then
            if (upper == nil or e.yards < upper) and (lower == nil or e.yards > lower) then
                lower = e.yards
            end
        end
    end
    if upper == nil and lower == nil then
        return nil, nil
    end
    return lower or 0, upper
end

-- 거리 색 토큰(C 순수), dik, 2026-10-02
function ns.Range.ColorToken(lower, upper)
    if lower == nil then
        return "TEXT_DIM"
    end
    if upper ~= nil and upper <= ns.Range.RED_MAX then
        return "DANGER"
    end
    if upper ~= nil and upper <= ns.Range.YELLOW_MAX then
        return "ACCENT"
    end
    if lower >= ns.Range.GRAY_MIN then
        return "TEXT_DIM"
    end
    return "RANGE_MID"
end

-- 거리 글자(T 순수), dik, 2026-10-02
function ns.Range.Text(lower, upper)
    if not IsNumber(lower) then
        return L.RANGE_UNKNOWN
    end
    local low = math.floor(lower + 0.5)
    if not IsNumber(upper) then
        return string.format(L.FMT_RANGE_OVER, low)
    end
    return string.format(L.FMT_RANGE_BRACKET, low, math.floor(upper + 0.5))
end

-- 표시 판정(V 어댑터), dik, 2026-10-02
function ns.Range.ShouldShow()
    local okE, exists = xpcall(function() return UnitExists("target") end, geterrorhandler())
    if not okE or ns.IsSecret(exists) or exists ~= true then
        return false
    end
    local okA, canAttack = xpcall(function() return UnitCanAttack("player", "target") end, geterrorhandler())
    if not okA or ns.IsSecret(canAttack) or canAttack ~= true then
        return false
    end
    if ns.HasAPI("UnitIsDeadOrGhost") then
        local okD, dead = xpcall(function() return UnitIsDeadOrGhost("target") end, geterrorhandler())
        if okD then
            if ns.IsSecret(dead) or dead == true then
                return false
            end
        end
    end
    return true
end

-- 전투 판정 어댑터(불명확하면 전투 중으로 간주), dik, 2026-10-02
function ns.Range.InCombat()
    local ok, r = xpcall(function() return InCombatLockdown() end, geterrorhandler())
    if not ok or ns.IsSecret(r) then
        return true
    end
    return r == true
end

-- 대상 거리 모듈 등록, dik, 2026-10-02
ns.RegisterModule({
    id = "range",
    title = L.MODULE_RANGE,
    description = L.MODULE_RANGE_DESC,
    category = "display",
    order = 77,
    requires = { "UnitExists", "UnitCanAttack", "C_Spell.IsSpellInRange", "C_Spell.GetSpellInfo",
                 "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookSkillLineInfo",
                 "C_SpellBook.GetSpellBookItemInfo", "Enum.SpellBookSpellBank.Player", "Enum.SpellBookItemType.Spell" },
    settings = {
        { key = "textScale", type = "slider", label = L.SETTING_RANGE_SCALE, tooltip = L.SETTING_RANGE_SCALE_TIP,
          default = 1.4, min = 0.8, max = 2.5, step = 0.1 },
    },
})
