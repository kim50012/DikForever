-- 색·글꼴·치수 테마 토큰, dik, 2026-09-30
local addonName, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.TEXTURE_WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.WINDOW_DEFAULT_W = 760
Theme.WINDOW_DEFAULT_H = 480
Theme.WINDOW_MIN_W = 600
Theme.WINDOW_MIN_H = 380
Theme.WINDOW_MAX_W = 1200
Theme.WINDOW_MAX_H = 800
Theme.TITLEBAR_H = 28
Theme.STATUSBAR_H = 20
Theme.SIDEBAR_W = 160
Theme.MENU_ITEM_H = 26
Theme.PAD = 12
Theme.GAP = 8

Theme.FACE_BODY = "Interface\\AddOns\\DikForever\\Media\\Fonts\\SebangGothicBold.ttf"
Theme.FACE_DISPLAY = "Interface\\AddOns\\DikForever\\Media\\Fonts\\YSpotlight.ttf"
-- 이름 글자 대체 서체 경로 추가, dik, 2026-10-01
Theme.FACE_FALLBACK = STANDARD_TEXT_FONT
Theme.FACE_CJK = "Fonts\\ARHei.ttf"

local DEFAULT_FONT_SIZE = 12

local COLORS = {
    BG = { 0.06, 0.06, 0.08, 0.95 },
    PANEL = { 0.10, 0.10, 0.13, 1.00 },
    BORDER = { 0.25, 0.25, 0.30, 1.00 },
    ACCENT = { 1.00, 0.82, 0.00, 1.00 },
    TEXT = { 0.92, 0.92, 0.92, 1.00 },
    TEXT_DIM = { 0.60, 0.60, 0.65, 1.00 },
    HOVER = { 1.00, 1.00, 1.00, 0.08 },
    SELECTED = { 1.00, 0.82, 0.00, 0.18 },
    DANGER = { 0.90, 0.30, 0.30, 1.00 },
    -- 진행 바 보조 값 색 토큰 추가, dik, 2026-09-30
    BAR_SECONDARY = { 0.35, 0.60, 1.00, 0.45 },
    -- 대상 빨간 체력 바 색 토큰 추가, dik, 2026-10-01
    HEALTH_RED = { 0.75, 0.12, 0.12, 1.00 },
    -- 거리 표시 색 토큰 추가, dik, 2026-10-02
    RANGE_MID = { 0.55, 0.85, 1.00, 1.00 },
    -- 가방 못 쓰는 장비 정점색 토큰 추가, dik, 2026-10-02
    BAG_UNUSABLE = { 1.00, 0.25, 0.25, 1.00 },
    TEXT_SHADOW = { 0.00, 0.00, 0.00, 1.00 },
    -- 바 위 보조 글자 색 토큰 추가, dik, 2026-10-02
    BAR_TEXT_DIM = { 0.80, 0.80, 0.84, 1.00 },
    -- 대상 강조 색 토큰 4개 추가, dik, 2026-10-05
    QUEST_TARGET = { 0.78, 0.47, 1.00, 1.00 },
    -- 퀘스트 대상 생명력 바 색 추가, dik, 2026-10-05
    QUEST_BAR = { 0.45, 0.20, 0.70, 1.00 },
    -- 선점 몹 생명력 바 회색 토큰 추가, dik, 2026-10-05
    HEALTH_TAPPED = { 0.50, 0.50, 0.50, 1.00 },
    RANK_ELITE = { 1.00, 0.82, 0.00, 1.00 },
    RANK_RARE = { 0.80, 0.85, 0.95, 1.00 },
    RANK_BOSS = { 1.00, 0.35, 0.10, 1.00 },
}

local FONT_DEFS = {
    FONT_TITLE = { face = Theme.FACE_DISPLAY, delta = 3 },
    FONT_NUMBER = { face = Theme.FACE_DISPLAY, delta = 1 },
    FONT_MENU = { face = Theme.FACE_BODY, delta = 1 },
    FONT_BODY = { face = Theme.FACE_BODY, delta = 0 },
    FONT_SMALL = { face = Theme.FACE_BODY, delta = -1 },
    -- 바 위 글자용 외곽선 토큰 추가, dik, 2026-10-02
    FONT_SMALL_OUTLINE = { face = Theme.FACE_BODY, delta = -1, flags = "OUTLINE", shadow = true },
    -- 오라 아이콘 시간·중첩 글자 토큰 추가, dik, 2026-10-03
    FONT_TINY_OUTLINE = { face = Theme.FACE_BODY, delta = -3, flags = "OUTLINE", shadow = true },
    FONT_BODY_OUTLINE = { face = Theme.FACE_BODY, delta = 0, flags = "OUTLINE", shadow = true },
}

local fonts = {}
local fallbackNoticePending = false
local fallbackNoticeDone = false
local isReady = false

-- 색 토큰 조회, dik, 2026-09-30
function Theme.GetColor(token)
    local c = COLORS[token]
    if not c then
        error("DikForever: unknown color token " .. tostring(token), 2)
    end
    return c[1], c[2], c[3], c[4]
end

-- 글꼴 토큰 조회, dik, 2026-09-30
function Theme.GetFont(token)
    local f = fonts[token]
    if not f then
        error("DikForever: unknown font token " .. tostring(token), 2)
    end
    return f
end

-- 배경·테두리 적용, dik, 2026-09-30
function Theme.ApplyBackdrop(frame, bgToken, borderToken, bgAlpha)
    if borderToken then
        frame:SetBackdrop({ bgFile = Theme.TEXTURE_WHITE, edgeFile = Theme.TEXTURE_WHITE, edgeSize = 1 })
        frame:SetBackdropBorderColor(Theme.GetColor(borderToken))
    else
        frame:SetBackdrop({ bgFile = Theme.TEXTURE_WHITE })
    end
    -- 배경 알파 인자 추가, dik, 2026-10-01
    if type(bgAlpha) == "number" then
        local r, g, b = Theme.GetColor(bgToken)
        frame:SetBackdropColor(r, g, b, math.min(math.max(bgAlpha, 0), 1))
    else
        frame:SetBackdropColor(Theme.GetColor(bgToken))
    end
end

-- 글꼴 경로만 교체, dik, 2026-10-01
function Theme.SetFontFace(target, facePath)
    local face, size, flags = target:GetFont()
    if type(size) ~= "number" then
        return false
    end
    if target:SetFont(facePath, size, flags or "") == false then
        target:SetFont(face, size, flags or "")
        return false
    end
    return true
end

-- 알림 출력 조건 확인, dik, 2026-09-30
local function FlushFallbackNotice()
    if fallbackNoticePending and isReady and not fallbackNoticeDone then
        fallbackNoticeDone = true
        fallbackNoticePending = false
        ns.Print(ns.L.MSG_FONT_FALLBACK)
    end
end

-- 글꼴 객체 크기 재적용, dik, 2026-09-30
function Theme.ApplyFonts(size)
    size = tonumber(size) or DEFAULT_FONT_SIZE
    -- 마지막 적용 결과만 안내 여부 결정, dik, 2026-09-30
    fallbackNoticePending = false
    for token, def in pairs(FONT_DEFS) do
        local f = fonts[token]
        -- 외곽선 flags 전달, dik, 2026-10-02
        local ok = f:SetFont(def.face, size + def.delta, def.flags or "")
        if ok == false then
            f:SetFont(STANDARD_TEXT_FONT, size + def.delta, def.flags or "")
            fallbackNoticePending = true
        end
    end
    FlushFallbackNotice()
end

-- 바 위 글자용 외곽선 토큰 매핑, dik, 2026-10-02
local OUTLINE_TOKENS = {
    FONT_SMALL = "FONT_SMALL_OUTLINE",
    FONT_BODY = "FONT_BODY_OUTLINE",
}

-- 바 위 글자용 외곽선 글꼴 토큰 변환, dik, 2026-10-02
function Theme.OutlineToken(token)
    return OUTLINE_TOKENS[token] or token
end

for token, def in pairs(FONT_DEFS) do
    fonts[token] = CreateFont("DikForeverFont_" .. token)
    -- 그림자 1회 설정, dik, 2026-10-02
    if def.shadow == true then
        fonts[token]:SetShadowColor(Theme.GetColor("TEXT_SHADOW"))
        fonts[token]:SetShadowOffset(1, -1)
    end
end
Theme.ApplyFonts(DEFAULT_FONT_SIZE)

ns.On("READY", function()
    isReady = true
    Theme.ApplyFonts(ns.GetSetting("global", "fontSize"))
end)

ns.On("SETTING_CHANGED", function(scope, key, value)
    if scope == "global" and key == "fontSize" then
        Theme.ApplyFonts(value)
    end
end)
