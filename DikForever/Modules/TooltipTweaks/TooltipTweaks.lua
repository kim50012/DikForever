-- 툴팁 개선 모듈 backend (커서 위치·직업색 규칙), dik, 2026-10-02
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "tooltipTweaks"
local ANCHOR_RIGHT = "ANCHOR_CURSOR_RIGHT"
local ANCHOR_LEFT = "ANCHOR_CURSOR_LEFT"
local ANCHOR_FALLBACK = "ANCHOR_CURSOR"
local CONFLICT_ADDON = "ForeverCursorTooltip"
local CLASS_LINE_FIRST = 2
local CLASS_LINE_LAST = 6
local CURSOR_APIS = { "GameTooltip_SetDefaultAnchor", "hooksecurefunc" }
local COLOR_APIS = { "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Unit" }

ns.TooltipTweaks = {
  MODULE_ID = MODULE_ID,
  ANCHOR_RIGHT = ANCHOR_RIGHT,
  ANCHOR_LEFT = ANCHOR_LEFT,
  ANCHOR_FALLBACK = ANCHOR_FALLBACK,
  CONFLICT_ADDON = CONFLICT_ADDON,
  CLASS_LINE_FIRST = CLASS_LINE_FIRST,
  CLASS_LINE_LAST = CLASS_LINE_LAST,
  CURSOR_APIS = CURSOR_APIS,
  COLOR_APIS = COLOR_APIS,
}

-- 유한 number 판정, dik, 2026-10-02
local function IsNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 간격 정규화, dik, 2026-10-02
local function Gap(v)
  if IsNumber(v) then
    return v
  end
  return 0
end

-- 커서 앵커 계산, dik, 2026-10-02
function ns.TooltipTweaks.CalcAnchor(side, offsetX, offsetY)
  local x = Gap(offsetX)
  local y = Gap(offsetY)
  if side == "left" then
    if x == 0 then
      return ANCHOR_LEFT, 0, y
    end
    return ANCHOR_LEFT, -x, y
  end
  return ANCHOR_RIGHT, x, y
end

-- 위치 변경 판정, dik, 2026-10-02
function ns.TooltipTweaks.ShouldMove(o)
  if type(o) ~= "table" then
    return false
  end
  if o.enabled ~= true then
    return false
  end
  if o.conflict == true then
    return false
  end
  if o.inCombat == true and o.cursorInCombat ~= true then
    return false
  end
  if o.scope == "world" and o.isWorld ~= true then
    return false
  end
  return true
end

-- 직업색 조회, dik, 2026-10-02
function ns.TooltipTweaks.ClassColor(classFile, colors)
  if ns.IsSecret(classFile) then
    return nil
  end
  if type(classFile) ~= "string" or type(colors) ~= "table" then
    return nil
  end
  local c = colors[classFile]
  if type(c) ~= "table" or not IsNumber(c.r) or not IsNumber(c.g) or not IsNumber(c.b) then
    return nil
  end
  return c.r, c.g, c.b
end

-- 0~1 자르고 255 단계 변환, dik, 2026-10-02
local function ToByte(v)
  if v < 0 then
    v = 0
  elseif v > 1 then
    v = 1
  end
  return math.floor(v * 255 + 0.5)
end

-- 색 코드 문자열, dik, 2026-10-02
function ns.TooltipTweaks.ColorHex(r, g, b)
  if not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then
    return nil
  end
  return string.format("%02x%02x%02x", ToByte(r), ToByte(g), ToByte(b))
end

-- 직업명 단어 칠하기, dik, 2026-10-02
function ns.TooltipTweaks.ColorizeWord(text, word, r, g, b)
  if ns.IsSecret(text) or ns.IsSecret(word) then
    return nil
  end
  if type(text) ~= "string" or type(word) ~= "string" or text == "" or word == "" then
    return nil
  end
  local hex = ns.TooltipTweaks.ColorHex(r, g, b)
  if not hex then
    return nil
  end
  if text:sub(1, 1) == "<" then
    return nil
  end
  if text:find("|cff" .. hex .. word, 1, true) then
    return nil
  end
  local s, e = text:find(word, 1, true)
  if not s then
    return nil
  end
  return text:sub(1, s - 1) .. "|cff" .. hex .. word .. "|r" .. text:sub(e + 1)
end

-- 충돌 애드온 감지, dik, 2026-10-02
function ns.TooltipTweaks.IsConflict()
  if not ns.HasAPI("C_AddOns.IsAddOnLoaded") then
    return false
  end
  local loaded = C_AddOns.IsAddOnLoaded(CONFLICT_ADDON)
  if ns.IsSecret(loaded) then
    return false
  end
  return loaded == true
end

-- 커서 위치 기능 차단 사유, dik, 2026-10-02
function ns.TooltipTweaks.CursorBlockReason()
  if #ns.GetMissingAPIs(CURSOR_APIS) > 0 then
    return L.TIPTW_BLOCK_API
  end
  if ns.TooltipTweaks.IsConflict() then
    return L.TIPTW_BLOCK_FCT
  end
  return nil
end

-- 직업색 기능 차단 사유, dik, 2026-10-02
function ns.TooltipTweaks.ColorBlockReason()
  if #ns.GetMissingAPIs(COLOR_APIS) > 0 then
    return L.TIPTW_BLOCK_API
  end
  return nil
end

-- 유닛 직업 읽기, dik, 2026-10-02
function ns.TooltipTweaks.ReadUnitClass(unit)
  if ns.IsSecret(unit) or type(unit) ~= "string" then
    return nil
  end
  local isPlayer = UnitIsPlayer(unit)
  if ns.IsSecret(isPlayer) or isPlayer ~= true then
    return nil
  end
  local className, classFile = UnitClass(unit)
  if ns.IsSecret(className) or ns.IsSecret(classFile) or type(classFile) ~= "string" then
    return nil
  end
  if type(className) ~= "string" then
    className = nil
  end
  return className, classFile
end

-- 전투 중 여부, dik, 2026-10-02
function ns.TooltipTweaks.InCombat()
  return InCombatLockdown() == true
end

ns.RegisterModule({
  id = "tooltipTweaks",
  title = L.MODULE_TIPTW,
  description = L.MODULE_TIPTW_DESC,
  category = "display",
  order = 88,
  requires = { "GameTooltip" },
  settings = {
    { key = "cursorAnchor", type = "checkbox", label = L.SETTING_TIPTW_CURSOR, tooltip = L.SETTING_TIPTW_CURSOR_TIP,
      default = true, unavailable = function() return ns.TooltipTweaks.CursorBlockReason() end },
    { key = "anchorSide", type = "select", label = L.SETTING_TIPTW_SIDE, tooltip = L.SETTING_TIPTW_SIDE_TIP,
      items = { { value = "right", text = L.TIPTW_SIDE_RIGHT }, { value = "left", text = L.TIPTW_SIDE_LEFT } }, default = "right" },
    { key = "anchorScope", type = "select", label = L.SETTING_TIPTW_SCOPE, tooltip = L.SETTING_TIPTW_SCOPE_TIP,
      items = { { value = "all", text = L.TIPTW_SCOPE_ALL }, { value = "world", text = L.TIPTW_SCOPE_WORLD } }, default = "all" },
    { key = "offsetX", type = "slider", label = L.SETTING_TIPTW_OFFSET_X, tooltip = L.SETTING_TIPTW_OFFSET_X_TIP,
      min = 0, max = 100, step = 1, default = 30 },
    { key = "offsetY", type = "slider", label = L.SETTING_TIPTW_OFFSET_Y, tooltip = L.SETTING_TIPTW_OFFSET_Y_TIP,
      min = -100, max = 100, step = 1, default = -25 },
    { key = "cursorInCombat", type = "checkbox", label = L.SETTING_TIPTW_COMBAT, tooltip = L.SETTING_TIPTW_COMBAT_TIP, default = true },
    { key = "classColorName", type = "checkbox", label = L.SETTING_TIPTW_CLASS_NAME, tooltip = L.SETTING_TIPTW_CLASS_NAME_TIP,
      default = true, unavailable = function() return ns.TooltipTweaks.ColorBlockReason() end },
    { key = "classColorClass", type = "checkbox", label = L.SETTING_TIPTW_CLASS_WORD, tooltip = L.SETTING_TIPTW_CLASS_WORD_TIP,
      default = false, unavailable = function() return ns.TooltipTweaks.ColorBlockReason() end },
  },
})
