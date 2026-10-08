-- 대상 강조 판정 어댑터·모듈 등록, dik, 2026-10-05
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "unitMark"
local FIRE_DELAY = 0.5
-- 관계 변경 이벤트 감시 추가, dik, 2026-10-08
local WATCH_EVENTS = { "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION" }
local WHERE_KEYS = { hud = "onHud", nameplate = "onNameplate", tooltip = "onTooltip" }

ns.UnitMark = ns.UnitMark or {}
local UM = ns.UnitMark
UM.MODULE_ID = MODULE_ID

local errorReported = false
local eventFrame = nil
local pending = false
local elapsedSum = 0

-- 세션 1회 오류 보고, dik, 2026-10-05
local function ReportOnce(err)
    if errorReported then
        return
    end
    errorReported = true
    geterrorhandler()(err)
end

-- 유닛 토큰 유효 여부, dik, 2026-10-05
local function IsUnitToken(unit)
    return not ns.IsSecret(unit) and type(unit) == "string"
end

-- 플레이어 유닛 여부(plain true 만), dik, 2026-10-05
local function IsPlayerUnit(unit)
    if not ns.HasAPI("UnitIsPlayer") then
        return false
    end
    local ok, r = pcall(UnitIsPlayer, unit)
    if not ok then
        ReportOnce(r)
        return false
    end
    return not ns.IsSecret(r) and r == true
end

-- 툴팁 줄 목록의 퀘스트 목표 여부, dik, 2026-10-05
function UM.QuestFromLines(lines, questType)
    if type(lines) ~= "table" then
        return nil
    end
    for i = 1, #lines do
        local line = lines[i]
        if type(line) == "table" then
            local lineType = line.type
            if ns.IsSecret(lineType) then
                return nil
            end
            if lineType == questType then
                local completed = line.completed
                if ns.IsSecret(completed) then
                    return nil
                end
                if completed ~= true then
                    return true
                end
            end
        end
    end
    return false
end

-- 분류 문자열의 등급, dik, 2026-10-05
function UM.RankFromClassification(cls, isBoss)
    if isBoss == true or cls == "worldboss" then
        return "boss"
    end
    if cls == "rareelite" then
        return "rareelite"
    end
    if cls == "elite" then
        return "elite"
    end
    if cls == "rare" then
        return "rare"
    end
    return nil
end

-- 등급 표시 형식(꼬리표·꼬리표색·테두리색), dik, 2026-10-05
function UM.RankStyle(rank)
    if rank == "boss" then
        return L.UNITMARK_TAG_BOSS, "RANK_BOSS", "RANK_BOSS"
    elseif rank == "rareelite" then
        return L.UNITMARK_TAG_RAREELITE, "RANK_RARE", "RANK_ELITE"
    elseif rank == "elite" then
        return L.UNITMARK_TAG_ELITE, "RANK_ELITE", "RANK_ELITE"
    elseif rank == "rare" then
        return L.UNITMARK_TAG_RARE, "RANK_RARE", "RANK_RARE"
    end
    return nil, nil, nil
end

-- 퀘스트 대상 판정 어댑터, dik, 2026-10-05
function UM.ReadQuest(unit)
    if not IsUnitToken(unit) then
        return nil
    end
    if IsPlayerUnit(unit) then
        return false
    end
    if ns.HasAPI("C_QuestLog.UnitIsRelatedToActiveQuest") then
        local ok, r = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if not ok then
            ReportOnce(r)
            return nil
        end
        if ns.IsSecret(r) then
            return nil
        end
        return r == true
    end
    if ns.HasAPI("C_TooltipInfo.GetUnit") and ns.HasAPI("Enum.TooltipDataLineType.QuestObjective") then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if not ok then
            ReportOnce(data)
            return nil
        end
        if ns.IsSecret(data) or type(data) ~= "table" then
            return nil
        end
        return UM.QuestFromLines(data.lines, Enum.TooltipDataLineType.QuestObjective)
    end
    return nil
end

-- 등급 판정 어댑터, dik, 2026-10-05
function UM.ReadRank(unit)
    if not IsUnitToken(unit) then
        return nil
    end
    if IsPlayerUnit(unit) or not ns.HasAPI("UnitClassification") then
        return nil
    end
    local ok, cls = pcall(UnitClassification, unit)
    if not ok then
        ReportOnce(cls)
        return nil
    end
    if ns.IsSecret(cls) then
        return nil
    end
    local isBoss = false
    if ns.HasAPI("UnitIsBossMob") then
        local okBoss, boss = pcall(UnitIsBossMob, unit)
        if not okBoss then
            ReportOnce(boss)
        elseif not ns.IsSecret(boss) and boss == true then
            isBoss = true
        end
    end
    return UM.RankFromClassification(cls, isBoss)
end

-- 선점 몹 판정 어댑터, dik, 2026-10-05
function UM.ReadTapDenied(unit)
    if not IsUnitToken(unit) then
        return nil
    end
    if IsPlayerUnit(unit) then
        return false
    end
    if not ns.HasAPI("UnitIsTapDenied") then
        return nil
    end
    local ok, r = pcall(UnitIsTapDenied, unit)
    if not ok then
        ReportOnce(r)
        return nil
    end
    if ns.IsSecret(r) then
        return nil
    end
    return r == true
end

-- 적용처별 조회(항상 plain), dik, 2026-10-05
function UM.Get(unit, where)
    local key = WHERE_KEYS[where]
    if not key or not ns.IsModuleEnabled(MODULE_ID) or not ns.IsModuleSupported(MODULE_ID) then
        return false, nil, false, false
    end
    if ns.GetSetting(MODULE_ID, key) == false then
        return false, nil, false, false
    end
    -- 퀘스트 판정 1회 공유·bar·tapped 반환 추가, dik, 2026-10-05
    local wantName = ns.GetSetting(MODULE_ID, "questName") ~= false
    local wantBar = where ~= "tooltip" and ns.GetSetting(MODULE_ID, "questBar") ~= false
    local tapped = UM.ReadTapDenied(unit) == true
    local quest, bar = false, false
    if not tapped and (wantName or wantBar) and UM.ReadQuest(unit) == true then
        quest = wantName
        bar = wantBar
    end
    local rank = nil
    if where ~= "tooltip" and ns.GetSetting(MODULE_ID, "rankMark") ~= false then
        rank = UM.ReadRank(unit)
    end
    return quest, rank, bar, tapped
end

-- 플레이어 이름표 직업색 바 색, dik, 2026-10-05
function UM.GetClassBar(unit)
    if not IsUnitToken(unit) then
        return nil
    end
    if not ns.IsModuleEnabled(MODULE_ID) or not ns.IsModuleSupported(MODULE_ID) then
        return nil
    end
    if ns.GetSetting(MODULE_ID, "onNameplate") == false or ns.GetSetting(MODULE_ID, "classBar") == false then
        return nil
    end
    if not IsPlayerUnit(unit) then
        return nil
    end
    if not ns.HasAPI("UnitClass") then
        return nil
    end
    local ok, r, classFile = pcall(UnitClass, unit)
    if not ok then
        ReportOnce(r)
        return nil
    end
    return ns.ClassBarColor(classFile)
end

-- 호감도 값 분류(적대·중립), dik, 2026-10-08
function UM.ReactionFromValue(reaction)
    if ns.IsSecret(reaction) then
        return nil
    end
    if type(reaction) ~= "number" then
        return nil
    end
    if reaction ~= reaction or reaction == math.huge or reaction == -math.huge then
        return nil
    end
    if reaction == 1 or reaction == 2 or reaction == 3 then
        return "hostile"
    end
    if reaction == 4 then
        return "neutral"
    end
    return nil
end

-- 이름표 NPC 이름 관계 색 토큰, dik, 2026-10-08
function UM.GetNameReaction(unit)
    if not IsUnitToken(unit) then
        return nil
    end
    if not ns.IsModuleEnabled(MODULE_ID) or not ns.IsModuleSupported(MODULE_ID) then
        return nil
    end
    if ns.GetSetting(MODULE_ID, "onNameplate") == false or ns.GetSetting(MODULE_ID, "reactionName") == false then
        return nil
    end
    if IsPlayerUnit(unit) then
        return nil
    end
    if not ns.HasAPI("UnitReaction") then
        return nil
    end
    local ok, r = pcall(UnitReaction, unit, "player")
    if not ok then
        ReportOnce(r)
        return nil
    end
    local kind = UM.ReactionFromValue(r)
    if kind == "hostile" then
        return "REACTION_HOSTILE"
    elseif kind == "neutral" then
        return "REACTION_NEUTRAL"
    end
    return nil
end

-- 부분별 사용 불가 사유, dik, 2026-10-05
function UM.GetUnavailableReason(part)
    if part == "quest" then
        local hasPrimary = ns.HasAPI("C_QuestLog.UnitIsRelatedToActiveQuest")
        local hasSecondary = ns.HasAPI("C_TooltipInfo.GetUnit") and ns.HasAPI("Enum.TooltipDataLineType.QuestObjective")
        if not hasPrimary and not hasSecondary then
            return L.UNITMARK_UNAVAILABLE_QUEST
        end
    elseif part == "rank" then
        if not ns.HasAPI("UnitClassification") then
            return L.UNITMARK_UNAVAILABLE_RANK
        end
    elseif part == "nameplate" then
        if not ns.HasAPI("C_NamePlate.GetNamePlateForUnit") then
            return L.UNITMARK_UNAVAILABLE_NAMEPLATE
        end
    -- 관계 색 사용 불가 사유 분기 추가, dik, 2026-10-08
    elseif part == "reaction" then
        local reason = UM.GetUnavailableReason("nameplate")
        if reason then
            return reason
        end
        if not ns.HasAPI("UnitReaction") then
            return L.UNITMARK_UNAVAILABLE_REACTION
        end
    end
    return nil
end

-- 0.5초 묶음 발행 타이머, dik, 2026-10-05
local function OnUpdate(self, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum < FIRE_DELAY then
        return
    end
    pending = false
    elapsedSum = 0
    self:SetScript("OnUpdate", nil)
    ns.Fire("UNIT_MARK_CHANGED")
end

-- 재판정 이벤트 수신, dik, 2026-10-05
local function OnWatchEvent(self)
    if pending or not ns.IsModuleEnabled(MODULE_ID) then
        return
    end
    pending = true
    elapsedSum = 0
    self:SetScript("OnUpdate", OnUpdate)
end

-- 이벤트 수집 프레임 준비, dik, 2026-10-05
local function EnsureFrame()
    if eventFrame or not ns.IsModuleEnabled(MODULE_ID) or not ns.IsModuleSupported(MODULE_ID) then
        return
    end
    eventFrame = CreateFrame("Frame")
    for i = 1, #WATCH_EVENTS do
        pcall(eventFrame.RegisterEvent, eventFrame, WATCH_EVENTS[i])
    end
    eventFrame:SetScript("OnEvent", OnWatchEvent)
end

ns.On("READY", EnsureFrame)

ns.On("SETTING_CHANGED", function(scope)
    if scope == MODULE_ID then
        EnsureFrame()
        ns.Fire("UNIT_MARK_CHANGED")
    end
end)

ns.RegisterModule({
    id = MODULE_ID,
    title = L.MODULE_UNITMARK,
    description = L.MODULE_UNITMARK_DESC,
    category = "display",
    order = 78,
    settings = {
        { key = "questName", type = "checkbox", label = L.SETTING_UNITMARK_QUEST, tooltip = L.SETTING_UNITMARK_QUEST_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("quest") end },
        -- 퀘스트 대상 생명력 바 설정 추가, dik, 2026-10-05
        { key = "questBar", type = "checkbox", label = L.SETTING_UNITMARK_BAR, tooltip = L.SETTING_UNITMARK_BAR_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("quest") end },
        { key = "rankMark", type = "checkbox", label = L.SETTING_UNITMARK_RANK, tooltip = L.SETTING_UNITMARK_RANK_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("rank") end },
        { key = "onHud", type = "checkbox", label = L.SETTING_UNITMARK_HUD, tooltip = L.SETTING_UNITMARK_HUD_TIP, default = true },
        { key = "onNameplate", type = "checkbox", label = L.SETTING_UNITMARK_NAMEPLATE, tooltip = L.SETTING_UNITMARK_NAMEPLATE_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("nameplate") end },
        -- 플레이어 이름표 직업색 설정 추가, dik, 2026-10-05
        { key = "classBar", type = "checkbox", label = L.SETTING_UNITMARK_CLASSBAR, tooltip = L.SETTING_UNITMARK_CLASSBAR_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("nameplate") end },
        -- 이름표 이름 적대·중립 색 설정 추가, dik, 2026-10-08
        { key = "reactionName", type = "checkbox", label = L.SETTING_UNITMARK_REACTION, tooltip = L.SETTING_UNITMARK_REACTION_TIP, default = true,
          unavailable = function() return ns.UnitMark.GetUnavailableReason("reaction") end },
        { key = "onTooltip", type = "checkbox", label = L.SETTING_UNITMARK_TOOLTIP, tooltip = L.SETTING_UNITMARK_TOOLTIP_TIP, default = true },
    },
})
