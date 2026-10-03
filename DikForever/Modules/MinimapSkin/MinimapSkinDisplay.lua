-- 미니맵 사각 스킨 화면, dik, 2026-10-03
local addonName, ns = ...

local module = ns.GetModule("minimapSkin")
if not module then
    return
end

local L = ns.L
local Theme = ns.Theme

local BORDER_OUTSET = 1

local active = false
local minimapPartialShown = false
local minimapFirstDone = false
local maskApplied = false
-- 미니맵 크기 세션 값 추가, dik, 2026-10-03
local sessionSize = nil
local baseW = nil
local baseH = nil
local sizeNoticeShown = false
local borderFrame = nil
local eventFrame = nil

-- 설정 값 조회, dik, 2026-10-03
local function Get(key)
    return ns.GetSetting("minimapSkin", key)
end

-- 자체 테두리 조회(필요 시 생성), dik, 2026-10-03
local function GetBorder(m)
    if not borderFrame then
        borderFrame = CreateFrame("Frame", nil, m, "BackdropTemplate")
        borderFrame:SetPoint("TOPLEFT", m, "TOPLEFT", -BORDER_OUTSET, BORDER_OUTSET)
        borderFrame:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", BORDER_OUTSET, -BORDER_OUTSET)
        Theme.ApplyBackdrop(borderFrame, "BG", "BORDER", 0)
    end
    return borderFrame
end

-- 미니맵 스킨 적용, dik, 2026-10-03
local function ApplyMinimap()
    if not active then
        return
    end
    local missing = {}
    local m = ns.Display.Find("Minimap")
    if not m then
        missing[1] = "Minimap"
    else
        ns.Display.BeginSkin(ns.MinimapSkin.SKIN_OWNER)
        for _, group in ipairs(ns.MinimapSkin.MINIMAP_GROUPS) do
            local applied = 0
            for _, path in ipairs(group.candidates) do
                local obj = ns.Display.Find(unpack(path))
                if obj then
                    if group.kind == "texture" and type(obj.GetVertexColor) == "function" then
                        ns.Display.HideTexture(ns.MinimapSkin.SKIN_OWNER, obj)
                        applied = applied + 1
                    elseif group.kind == "font" and type(obj.GetFont) == "function" then
                        if ns.Display.SetFontFace(ns.MinimapSkin.SKIN_OWNER, obj, "FACE_BODY") then
                            applied = applied + 1
                        end
                    end
                end
            end
            if applied == 0 then
                missing[#missing + 1] = table.concat(group.candidates[1], ".")
            end
        end

        if Get("shape") == "square" then
            if type(m.SetMaskTexture) == "function" then
                m:SetMaskTexture(Theme.TEXTURE_WHITE)
                maskApplied = true
                GetBorder(m):Show()
            else
                missing[#missing + 1] = "Minimap:SetMaskTexture"
                if borderFrame then
                    borderFrame:Hide()
                end
            end
        elseif borderFrame then
            borderFrame:Hide()
        end

        -- 미니맵 크기 세션 값 적용, dik, 2026-10-03
        if baseW == nil then
            baseW = m:GetWidth()
            baseH = m:GetHeight()
        end
        if sessionSize ~= ns.MinimapSkin.SIZE_DEFAULT then
            local w = ns.MinimapSkin.CalcSize(baseW, sessionSize)
            local h = ns.MinimapSkin.CalcSize(baseH, sessionSize)
            if not (w == baseW and h == baseH) then
                if type(w) == "number" and type(h) == "number" and type(m.SetSize) == "function" then
                    m:SetSize(w, h)
                else
                    missing[#missing + 1] = "Minimap:SetSize"
                end
            end
        end
    end

    if not minimapFirstDone then
        minimapFirstDone = true
        if #missing > 0 and not minimapPartialShown then
            minimapPartialShown = true
            ns.Print(L.MSG_MINIMAP_SKIN_PARTIAL:format(ns.FormatMissingAPIs(missing)))
        end
    end
end

-- 미니맵 스킨 전투 밖 적용 요청, dik, 2026-10-03
local function RequestMinimap()
    ns.Display.RunOutOfCombat("minimapSkin:minimap", ApplyMinimap)
end

-- 이벤트 프레임 생성, dik, 2026-10-03
local function CreateEventFrame()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function()
        if active and ns.Display.IsSkinActive(ns.MinimapSkin.SKIN_OWNER) then
            RequestMinimap()
        end
    end)
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_ENTERING_WORLD")
end

-- READY 초기화, dik, 2026-10-03
local function Initialize()
    if not (ns.IsModuleEnabled("minimapSkin") and ns.IsModuleSupported("minimapSkin")) then
        return
    end
    -- 크기 세션 값 고정, dik, 2026-10-03
    sessionSize = Get("size")
    active = true
    CreateEventFrame()
    RequestMinimap()
end

-- 설정 변경 처리, dik, 2026-10-03
local function OnSettingChanged(scope, key, value)
    -- 크기 변경 /reload 안내 추가, dik, 2026-10-03
    if not active or scope ~= "minimapSkin" then
        return
    end
    if key == "size" then
        if value ~= sessionSize and not sizeNoticeShown then
            sizeNoticeShown = true
            ns.Print(L.MSG_MINIMAP_SIZE_RELOAD)
        end
        return
    end
    if key ~= "shape" then
        return
    end
    if value == "square" then
        RequestMinimap()
    else
        if borderFrame then
            borderFrame:Hide()
        end
        if maskApplied then
            ns.Print(L.MSG_MINIMAP_SHAPE_RELOAD)
        end
    end
end

ns.On("READY", Initialize)
ns.On("SETTING_CHANGED", OnSettingChanged)
