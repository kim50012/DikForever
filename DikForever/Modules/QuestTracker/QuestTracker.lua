-- 퀘스트 추적 스킨 모듈 등록·공개 상수·글자색 계획 순수 함수, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

ns.QuestTracker = {}
local QT = ns.QuestTracker

QT.ROOT = "ObjectiveTrackerFrame"
QT.COLOR_TABLE = "OBJECTIVE_TRACKER_COLOR"
QT.ADDON_TRACKER = "Blizzard_ObjectiveTracker"

QT.PARTS = {
    { id = "header", key = "skinHeader", owner = "questTracker:header" },
    { id = "font", key = "skinFont", owner = "questTracker:font" },
    { id = "colors", key = "skinColors", owner = "questTracker:colors" },
    { id = "background", key = "showBackground", owner = "questTracker:background" },
}

QT.HEADER_PATHS = {
    { "ObjectiveTrackerFrame", "Header" },
    { "ScenarioObjectiveTracker", "Header" },
    { "UIWidgetObjectiveTracker", "Header" },
    { "CampaignQuestObjectiveTracker", "Header" },
    { "QuestObjectiveTracker", "Header" },
    { "AdventureObjectiveTracker", "Header" },
    { "AchievementObjectiveTracker", "Header" },
    { "MonthlyActivitiesObjectiveTracker", "Header" },
    { "ProfessionsRecipeTracker", "Header" },
    { "BonusObjectiveTracker", "Header" },
    { "WorldQuestObjectiveTracker", "Header" },
    { "ObjectiveTrackerBlocksFrame", "QuestHeader" },
    { "ObjectiveTrackerBlocksFrame", "CampaignQuestHeader" },
    { "ObjectiveTrackerBlocksFrame", "AchievementHeader" },
    { "ObjectiveTrackerBlocksFrame", "ScenarioHeader" },
    { "ObjectiveTrackerBlocksFrame", "ProfessionHeader" },
    { "ObjectiveTrackerBlocksFrame", "UIWidgetsHeader" },
    { "ObjectiveTrackerBlocksFrame", "MonthlyActivitiesHeader" },
}

QT.HEADER_TEXT_KEY = "Text"
QT.HEADER_BG_KEY = "Background"

QT.FONT_OBJECTS = { "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont" }

QT.COLOR_KEYS = {
    "Header", "HeaderHighlight", "Normal", "NormalHighlight", "Complete",
    "CompleteHighlight", "Failed", "FailedHighlight", "TimeLeft", "TimeLeftHighlight",
}

QT.COLOR_MAP = {
    Header = "ACCENT",
    HeaderHighlight = "ACCENT",
    Normal = "TEXT",
    NormalHighlight = "TEXT",
    Complete = "TEXT_DIM",
    CompleteHighlight = "TEXT",
    Failed = "DANGER",
    FailedHighlight = "DANGER",
    TimeLeft = "DANGER",
    TimeLeftHighlight = "DANGER",
}

QT.COLOR_EPS = 0.02
QT.PASS_INTERVAL = 0.25
QT.MAX_WALK_DEPTH = 10
QT.MAX_FONTSTRINGS = 1000

local TOKEN_ORDER = { "ACCENT", "TEXT", "TEXT_DIM", "DANGER" }

-- 유한 number 판정, dik, 2026-10-01
local function IsFinite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 색 표에서 유효 항목만 모은 참조 배열, dik, 2026-10-01
function QT.BuildColorRefs(tbl)
    local refs = {}
    if type(tbl) ~= "table" then
        return refs
    end
    for _, key in ipairs(QT.COLOR_KEYS) do
        local c = tbl[key]
        if type(c) == "table" and IsFinite(c.r) and IsFinite(c.g) and IsFinite(c.b) then
            refs[#refs + 1] = { key = key, r = c.r, g = c.g, b = c.b }
        end
    end
    return refs
end

-- 두 색의 채널별 오차 비교, dik, 2026-10-01
function QT.ColorEquals(r1, g1, b1, r2, g2, b2)
    if not (IsFinite(r1) and IsFinite(g1) and IsFinite(b1)
        and IsFinite(r2) and IsFinite(g2) and IsFinite(b2)) then
        return false
    end
    local eps = QT.COLOR_EPS
    return math.abs(r1 - r2) <= eps and math.abs(g1 - g2) <= eps and math.abs(b1 - b2) <= eps
end

-- 색을 참조 key 로 분류, dik, 2026-10-01
function QT.ClassifyColor(r, g, b, refs)
    if type(refs) ~= "table" then
        return nil
    end
    for _, ref in ipairs(refs) do
        if QT.ColorEquals(r, g, b, ref.r, ref.g, ref.b) then
            return ref.key
        end
    end
    return nil
end

-- 토큰 색이 다른 분류로 뒤집히는 매핑 제거, dik, 2026-10-01
function QT.ValidateColorMap(refs, tokenColors)
    local map = {}
    for key, token in pairs(QT.COLOR_MAP) do
        map[key] = token
    end
    local removed = {}
    if type(tokenColors) == "table" then
        for _, token in ipairs(TOKEN_ORDER) do
            local c = tokenColors[token]
            if type(c) == "table" then
                local k = QT.ClassifyColor(c[1], c[2], c[3], refs)
                if k and QT.COLOR_MAP[k] ~= token then
                    for key, target in pairs(QT.COLOR_MAP) do
                        if target == token then
                            map[key] = nil
                            removed[key] = true
                        end
                    end
                end
            end
        end
    end
    local conflicts = {}
    for _, key in ipairs(QT.COLOR_KEYS) do
        if removed[key] then
            conflicts[#conflicts + 1] = key
        end
    end
    return map, conflicts
end

-- 현재 색에 대응하는 테마 토큰 이름, dik, 2026-10-01
function QT.ResolveColor(r, g, b, refs, map)
    local k = QT.ClassifyColor(r, g, b, refs)
    if k and type(map) == "table" then
        return map[k]
    end
    return nil
end

-- 서체 경로 동일 판정, dik, 2026-10-01
function QT.SameFace(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    local na = a:lower():gsub("/", "\\")
    local nb = b:lower():gsub("/", "\\")
    return na == nb
end

ns.RegisterModule({
    id = "questTracker",
    title = L.MODULE_QUEST_TRACKER,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_QUEST_TRACKER_DESC,
    category = "display",
    order = 30,
    settings = {
        { key = "skinHeader", type = "checkbox", label = L.SETTING_QT_SKIN_HEADER,
          tooltip = L.SETTING_QT_SKIN_HEADER_TIP, default = true },
        { key = "skinFont", type = "checkbox", label = L.SETTING_QT_SKIN_FONT,
          tooltip = L.SETTING_QT_SKIN_FONT_TIP, default = true },
        { key = "skinColors", type = "checkbox", label = L.SETTING_QT_SKIN_COLORS,
          tooltip = L.SETTING_QT_SKIN_COLORS_TIP, default = true },
        { key = "showBackground", type = "checkbox", label = L.SETTING_QT_SHOW_BG,
          tooltip = L.SETTING_QT_SHOW_BG_TIP, default = false },
        { key = "bgAlpha", type = "slider", label = L.SETTING_QT_BG_ALPHA,
          tooltip = L.SETTING_QT_BG_ALPHA_TIP, min = 0, max = 1, step = 0.05, default = 0.6 },
    },
})
