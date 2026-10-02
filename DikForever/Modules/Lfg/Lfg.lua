-- 파티 모집 게시판 모듈 등록·수집·분류·귓말/초대, dik, 2026-10-01
local addonName, ns = ...
local L = ns.L

local MODULE_ID = "lfg"
local AREA_VERSION = 1
local POST_MAX = 200
local CUSTOM_MAX = 50
local WORD_MIN_CHARS = 2
local WORD_MAX_CHARS = 10
local DUNGEON_MAX_PER_POST = 3
local PRUNE_INTERVAL = 30
local WHISPER_PREFIX = "/w "
local CUSTOM_KEY_PREFIX = "custom:"
local SIZE_TOTALS = { [5] = true, [10] = true, [20] = true, [40] = true }
local LF_TOKEN_PATTERN = "^lf[0-9]+m$"
local CUSTOM_PRIORITY_BASE = 1000
local EXPIRE_DEFAULT = 15
local UNKNOWN_ORDER = 99999

local EVENT_ORDER = { "CHAT_MSG_CHANNEL", "CHAT_MSG_YELL" }
local WORD_GROUPS = { "lfg", "exclude", "tank", "healer", "dps" }
local ROLE_KEYS = { "tank", "healer", "dps" }

local state = {
    ready = false,
    readOnly = false,
    frame = nil,
    area = nil,
    dict = nil,
    posts = {},
    secretSkipped = 0,
    ticker = nil,
    channelEnabled = false,
    yellEnabled = false,
    hasIgnore = false,
    missing = {},
}

ns.Lfg = {}

-- 유한한 number 판정, dik, 2026-10-01
local function IsNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 비어 있지 않은 non-secret 문자열 판정, dik, 2026-10-01
local function IsPlainString(v)
    return not ns.IsSecret(v) and type(v) == "string" and v ~= ""
end

-- 내장 던전 항목 유효 판정, dik, 2026-10-01
local function IsValidDungeon(d)
    return type(d) == "table" and type(d.key) == "string" and d.key ~= ""
        and type(d.name) == "string" and d.name ~= ""
end

-- 내장 던전 key 집합, dik, 2026-10-01
local function CollectKeys(dungeons)
    local keys = {}
    if type(dungeons) == "table" then
        for i = 1, #dungeons do
            if IsValidDungeon(dungeons[i]) then
                keys[dungeons[i].key] = true
            end
        end
    end
    return keys
end

local builtinKeys = CollectKeys(L.LFG_DUNGEONS)

-- 본문 정리(순수 함수), dik, 2026-10-01
function ns.Lfg.StripText(text)
    if type(text) ~= "string" then
        return ""
    end
    local s = text
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|cn[^:]*:", "")
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|n", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- UTF-8 글자 수(순수 함수), dik, 2026-10-01
function ns.Lfg.CountChars(s)
    if type(s) ~= "string" then
        return 0
    end
    return #(s:gsub("[\128-\191]", ""))
end

-- 단어 정규화(순수 함수), dik, 2026-10-01
function ns.Lfg.NormalizeWord(word)
    if type(word) ~= "string" then
        return nil
    end
    local trimmed = word:match("^%s*(.-)%s*$")
    local lowered = string.lower(trimmed)
    local compact = lowered:gsub("%s", "")
    if compact == "" then
        return nil
    end
    return lowered, compact
end

-- 약칭·단어 그룹 분할 추가, dik, 2026-10-01
local function SplitWords(list)
    local group = { ascii = {}, hangul = {} }
    if type(list) == "table" then
        for i = 1, #list do
            local _, compact = ns.Lfg.NormalizeWord(list[i])
            if compact then
                if compact:find("^[a-z0-9]+$") then
                    group.ascii[#group.ascii + 1] = compact
                else
                    group.hangul[#group.hangul + 1] = compact
                end
            end
        end
    end
    return group
end

-- 사전 구성(순수 함수), dik, 2026-10-01
function ns.Lfg.BuildDictionary(dungeons, words, custom)
    local dict = { aliases = {}, names = {}, order = {}, raid = {}, known = {}, words = {} }
    if type(dungeons) ~= "table" then
        dungeons = {}
    end
    if type(words) ~= "table" then
        words = {}
    end
    if type(custom) ~= "table" then
        custom = {}
    end
    for i = 1, #dungeons do
        local d = dungeons[i]
        if IsValidDungeon(d) then
            dict.names[d.key] = d.name
            dict.order[d.key] = i
            dict.raid[d.key] = d.raid == true
            if type(d.aliases) == "table" then
                for a = 1, #d.aliases do
                    local _, compact = ns.Lfg.NormalizeWord(d.aliases[a])
                    if compact and not dict.known[compact] then
                        dict.known[compact] = true
                        dict.aliases[#dict.aliases + 1] = {
                            compact = compact,
                            ascii = compact:find("^[a-z0-9]+$") ~= nil,
                            key = d.key,
                            priority = i,
                            len = #compact,
                        }
                    end
                end
            end
        end
    end
    for g = 1, #WORD_GROUPS do
        local name = WORD_GROUPS[g]
        local group = SplitWords(words[name])
        dict.words[name] = group
        for i = 1, #group.ascii do
            dict.known[group.ascii[i]] = true
        end
        for i = 1, #group.hangul do
            dict.known[group.hangul[i]] = true
        end
    end
    for j = 1, #custom do
        local entry = custom[j]
        if type(entry) == "table" then
            local word, compact = ns.Lfg.NormalizeWord(entry.word)
            if word and not dict.known[compact] then
                local key = entry.dungeon
                local priority = CUSTOM_PRIORITY_BASE + j
                -- 내장 key 만 기존 분류로 연결, dik, 2026-10-01
                if type(key) ~= "string" or dict.order[key] == nil or dict.order[key] >= CUSTOM_PRIORITY_BASE then
                    key = CUSTOM_KEY_PREFIX .. compact
                    dict.names[key] = word
                    dict.order[key] = priority
                    dict.raid[key] = false
                end
                dict.known[compact] = true
                dict.aliases[#dict.aliases + 1] = {
                    compact = compact,
                    ascii = compact:find("^[a-z0-9]+$") ~= nil,
                    key = key,
                    priority = priority,
                    len = #compact,
                }
            end
        end
    end
    return dict
end

-- 단어 그룹 일치 판정, dik, 2026-10-01
local function HasWord(group, compact, tokens)
    if type(group) ~= "table" then
        return false
    end
    for i = 1, #group.hangul do
        if compact:find(group.hangul[i], 1, true) then
            return true
        end
    end
    for i = 1, #group.ascii do
        if tokens[group.ascii[i]] then
            return true
        end
    end
    return false
end

-- 일치 약칭이 다른 던전의 더 긴 약칭에 포함되는지, dik, 2026-10-01
local function IsContained(matched, keyK)
    local list = matched[keyK].aliases
    for a = 1, #list do
        local found = false
        for keyJ, info in pairs(matched) do
            if keyJ ~= keyK then
                for b = 1, #info.aliases do
                    local other = info.aliases[b]
                    if #other > #list[a] and other:find(list[a], 1, true) then
                        found = true
                        break
                    end
                end
            end
            if found then
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- 글 분류(순수 함수), dik, 2026-10-01
function ns.Lfg.Classify(text, dict)
    local plain = ns.Lfg.StripText(text)
    if plain == "" then
        return nil, "empty"
    end
    if type(dict) ~= "table" then
        return nil, "noinfo"
    end
    local lower = string.lower(plain)
    local compact = lower:gsub("%s", "")
    local tokens = {}
    for token in lower:gmatch("[a-z0-9]+") do
        tokens[token] = true
    end
    if HasWord(dict.words.exclude, compact, tokens) then
        return nil, "excluded"
    end
    local recruit = HasWord(dict.words.lfg, compact, tokens)
    if not recruit then
        for token in pairs(tokens) do
            if token:match(LF_TOKEN_PATTERN) then
                recruit = true
                break
            end
        end
    end
    if not recruit then
        return nil, "nolfg"
    end
    local matched = {}
    for i = 1, #dict.aliases do
        local e = dict.aliases[i]
        local hit
        if e.ascii then
            hit = tokens[e.compact] == true
        else
            hit = compact:find(e.compact, 1, true) ~= nil
        end
        if hit then
            local info = matched[e.key]
            if not info then
                info = { len = e.len, priority = e.priority, aliases = {} }
                matched[e.key] = info
            end
            info.aliases[#info.aliases + 1] = e.compact
            if e.len > info.len then
                info.len = e.len
            end
            if e.priority < info.priority then
                info.priority = e.priority
            end
        end
    end
    local keep = {}
    for key, info in pairs(matched) do
        if not IsContained(matched, key) then
            keep[#keep + 1] = { key = key, len = info.len, priority = info.priority }
        end
    end
    table.sort(keep, function(a, b)
        if a.len ~= b.len then
            return a.len > b.len
        end
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.key < b.key
    end)
    local dungeons = {}
    for i = 1, math.min(#keep, DUNGEON_MAX_PER_POST) do
        dungeons[i] = keep[i].key
    end
    local roles = {
        tank = HasWord(dict.words.tank, compact, tokens),
        healer = HasWord(dict.words.healer, compact, tokens),
        dps = HasWord(dict.words.dps, compact, tokens),
    }
    local size
    local a, b = lower:match("([0-9]+)%s*/%s*([0-9]+)")
    a, b = tonumber(a), tonumber(b)
    if a and b and a >= 1 and a < b and SIZE_TOTALS[b] then
        size = a .. "/" .. b
    end
    if #dungeons == 0 and not (roles.tank or roles.healer or roles.dps) and size == nil then
        return nil, "noinfo"
    end
    return { text = plain, dungeons = dungeons, roles = roles, size = size }
end

-- 만료·상한 정리(순수 함수), dik, 2026-10-01
function ns.Lfg.Prune(list, now, maxAge, maxCount)
    local kept = {}
    local total = 0
    if type(list) == "table" then
        for i = 1, #list do
            local p = list[i]
            total = total + 1
            if type(p) == "table" and IsNumber(p.at) and IsNumber(now) and IsNumber(maxAge)
                and now - p.at < maxAge then
                kept[#kept + 1] = p
            end
        end
    end
    table.sort(kept, function(x, y)
        if x.at ~= y.at then
            return x.at > y.at
        end
        return tostring(x.id) < tostring(y.id)
    end)
    if IsNumber(maxCount) then
        for i = #kept, maxCount + 1, -1 do
            kept[i] = nil
        end
    end
    return kept, total - #kept
end

-- 글 필터(순수 함수), dik, 2026-10-01
function ns.Lfg.FilterPosts(list, dungeonFilter, roleFilter)
    local out = {}
    if type(list) ~= "table" then
        return out
    end
    for i = 1, #list do
        local p = list[i]
        local okDungeon = true
        if dungeonFilter == "other" then
            okDungeon = #p.dungeons == 0
        elseif dungeonFilter ~= "all" and dungeonFilter ~= nil then
            okDungeon = false
            for d = 1, #p.dungeons do
                if p.dungeons[d] == dungeonFilter then
                    okDungeon = true
                    break
                end
            end
        end
        local okRole = true
        if roleFilter ~= "all" and roleFilter ~= nil then
            okRole = type(p.roles) == "table" and p.roles[roleFilter] == true
        end
        if okDungeon and okRole then
            out[#out + 1] = p
        end
    end
    return out
end

-- 짧은 이름(순수 함수), dik, 2026-10-01
function ns.Lfg.ShortName(sender)
    if type(sender) ~= "string" then
        return ""
    end
    local dash = sender:find("-", 1, true)
    if dash then
        return sender:sub(1, dash - 1)
    end
    return sender
end

-- 역할 문자열(순수 함수), dik, 2026-10-01
function ns.Lfg.FormatRoles(roles)
    local labels = { tank = L.LFG_ROLE_TANK, healer = L.LFG_ROLE_HEALER, dps = L.LFG_ROLE_DPS }
    local parts = {}
    if type(roles) == "table" then
        for i = 1, #ROLE_KEYS do
            if roles[ROLE_KEYS[i]] == true then
                parts[#parts + 1] = labels[ROLE_KEYS[i]]
            end
        end
    end
    if #parts == 0 then
        return L.VALUE_UNKNOWN
    end
    return table.concat(parts, L.LFG_ROLE_SEP)
end

-- 설정된 만료 분, dik, 2026-10-01
local function GetExpireMinutes()
    local v = ns.GetSetting(MODULE_ID, "expireMinutes")
    if IsNumber(v) and v > 0 then
        return v
    end
    return EXPIRE_DEFAULT
end

-- 글 배열(최신순), dik, 2026-10-01
local function ListPosts()
    local list = {}
    for _, p in pairs(state.posts) do
        list[#list + 1] = p
    end
    table.sort(list, function(x, y)
        if x.at ~= y.at then
            return x.at > y.at
        end
        return x.id < y.id
    end)
    return list
end

-- 만료·상한 정리 적용, dik, 2026-10-01
local function ApplyPrune()
    local list = ListPosts()
    local kept, removed = ns.Lfg.Prune(list, time(), GetExpireMinutes() * 60, POST_MAX)
    if removed > 0 then
        local map = {}
        for i = 1, #kept do
            map[kept[i].id] = kept[i]
        end
        state.posts = map
    end
    return removed
end

-- 글 수, dik, 2026-10-01
local function CountPosts()
    local n = 0
    for _ in pairs(state.posts) do
        n = n + 1
    end
    return n
end

-- 던전 이름, dik, 2026-10-01
function ns.Lfg.GetDungeonName(key)
    if type(key) ~= "string" then
        return L.VALUE_UNKNOWN
    end
    local name = state.dict and state.dict.names[key]
    if name then
        return name
    end
    if key:sub(1, #CUSTOM_KEY_PREFIX) == CUSTOM_KEY_PREFIX then
        return key:sub(#CUSTOM_KEY_PREFIX + 1)
    end
    return L.VALUE_UNKNOWN
end

-- 던전 열 문자열, dik, 2026-10-01
local function BuildDungeonText(dungeons)
    if #dungeons == 0 then
        return L.LFG_OTHER
    end
    local text = ns.Lfg.GetDungeonName(dungeons[1])
    if #dungeons > 1 then
        text = text .. L.LFG_DUNGEON_MORE:format(#dungeons - 1)
    end
    return text
end

-- 표시용 본문 이스케이프, dik, 2026-10-01
local function EscapeText(text)
    return (text:gsub("|", "||"))
end

-- 게시판 행, dik, 2026-10-01
function ns.Lfg.GetBoardRows(dungeonFilter, roleFilter)
    ApplyPrune()
    local list = ListPosts()
    local filtered = ns.Lfg.FilterPosts(list, dungeonFilter, roleFilter)
    local rows = {}
    for i = 1, #filtered do
        local p = filtered[i]
        rows[i] = {
            id = p.id,
            sender = p.sender,
            name = p.name,
            classFile = p.classFile,
            dungeonText = BuildDungeonText(p.dungeons),
            rolesText = ns.Lfg.FormatRoles(p.roles),
            text = EscapeText(p.text),
            at = p.at,
            source = p.source,
        }
    end
    return rows, { total = #list, shown = #rows }
end

-- 던전 필터 항목, dik, 2026-10-01
function ns.Lfg.GetDungeonFilterItems(current)
    -- 드롭다운 개수를 표 행과 맞추려 먼저 정리, dik, 2026-10-01
    ApplyPrune()
    local list = ListPosts()
    local counts = {}
    local otherCount = 0
    for i = 1, #list do
        local ds = list[i].dungeons
        if #ds == 0 then
            otherCount = otherCount + 1
        end
        for d = 1, #ds do
            counts[ds[d]] = (counts[ds[d]] or 0) + 1
        end
    end
    local order = state.dict and state.dict.order or {}
    -- 현재 값은 분류 key 일 때만 유지, dik, 2026-10-01
    if type(current) == "string" and order[current] ~= nil and counts[current] == nil then
        counts[current] = 0
    end
    local keys = {}
    for key in pairs(counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local oa, ob = order[a] or UNKNOWN_ORDER, order[b] or UNKNOWN_ORDER
        if oa ~= ob then
            return oa < ob
        end
        return a < b
    end)
    local items = { { value = "all", text = L.LFG_FILTER_ALL:format(#list) } }
    for i = 1, #keys do
        items[#items + 1] = {
            value = keys[i],
            text = L.LFG_FILTER_ITEM:format(ns.Lfg.GetDungeonName(keys[i]), counts[keys[i]]),
        }
    end
    if otherCount > 0 or current == "other" then
        items[#items + 1] = { value = "other", text = L.LFG_FILTER_ITEM:format(L.LFG_OTHER, otherCount) }
    end
    return items
end

-- 역할 필터 항목, dik, 2026-10-01
function ns.Lfg.GetRoleFilterItems()
    return {
        { value = "all", text = L.LFG_ROLE_FILTER_ALL },
        { value = "tank", text = L.LFG_ROLE_FILTER_TANK },
        { value = "healer", text = L.LFG_ROLE_FILTER_HEALER },
        { value = "dps", text = L.LFG_ROLE_FILTER_DPS },
    }
end

-- 툴팁용 글 복사본, dik, 2026-10-01
function ns.Lfg.GetPost(id)
    local p = state.posts[id]
    if not p then
        return nil
    end
    local names = {}
    for i = 1, #p.dungeons do
        names[i] = ns.Lfg.GetDungeonName(p.dungeons[i])
    end
    return {
        sender = p.sender,
        name = p.name,
        classFile = p.classFile,
        channel = p.channel,
        source = p.source,
        at = p.at,
        displayText = EscapeText(p.text),
        dungeonNames = names,
        rolesText = ns.Lfg.FormatRoles(p.roles),
        size = p.size,
    }
end

-- 귓말 입력창 열기(클릭 1회용), dik, 2026-10-01
function ns.Lfg.OpenWhisper(id)
    local post = state.posts[id]
    if not post then
        return false, "LFG_ERR_POST_GONE"
    end
    if ns.HasAPI("ChatFrame_SendTell") then
        ChatFrame_SendTell(post.sender)
    elseif ns.HasAPI("ChatFrame_OpenChat") then
        ChatFrame_OpenChat(WHISPER_PREFIX .. post.sender .. " ")
    else
        return false, "LFG_ERR_NO_WHISPER"
    end
    return true, nil, post.name
end

-- 파티 초대(클릭 1회용), dik, 2026-10-01
function ns.Lfg.Invite(id)
    local post = state.posts[id]
    if not post then
        return false, "LFG_ERR_POST_GONE"
    end
    if not ns.HasAPI("C_PartyInfo.InviteUnit") then
        return false, "LFG_ERR_NO_INVITE"
    end
    C_PartyInfo.InviteUnit(post.sender)
    return true, nil, post.name
end

-- 목록 비우기, dik, 2026-10-01
function ns.Lfg.ClearPosts()
    local n = CountPosts()
    state.posts = {}
    if n > 0 then
        ns.Fire("LFG_UPDATED", "posts")
    end
    return n
end

-- 사전 재구성과 글 재분류, dik, 2026-10-01
local function RebuildAndReclassify()
    local custom = state.area and state.area.custom or nil
    state.dict = ns.Lfg.BuildDictionary(L.LFG_DUNGEONS, L.LFG_WORDS, custom)
    for id, p in pairs(state.posts) do
        local result = ns.Lfg.Classify(p.text, state.dict)
        if result then
            p.dungeons = result.dungeons
            p.roles = result.roles
            p.size = result.size
        else
            state.posts[id] = nil
        end
    end
end

-- 사용자 키워드 추가, dik, 2026-10-01
function ns.Lfg.AddCustomWord(word, dungeonKey)
    if not state.ready or not state.area then
        return false, "LFG_ERR_NOT_READY"
    end
    local norm, compact = ns.Lfg.NormalizeWord(word)
    if not norm then
        return false, "LFG_ERR_WORD_LENGTH"
    end
    local chars = ns.Lfg.CountChars(compact)
    if chars < WORD_MIN_CHARS or chars > WORD_MAX_CHARS then
        return false, "LFG_ERR_WORD_LENGTH"
    end
    if state.dict.known[compact] then
        return false, "LFG_ERR_WORD_EXISTS"
    end
    local dungeon
    if dungeonKey ~= nil and dungeonKey ~= "new" then
        if type(dungeonKey) ~= "string" or not builtinKeys[dungeonKey] then
            return false, "LFG_ERR_UNKNOWN_DUNGEON"
        end
        dungeon = dungeonKey
    end
    local custom = state.area.custom
    if #custom >= CUSTOM_MAX then
        return false, "LFG_ERR_WORD_FULL"
    end
    custom[#custom + 1] = { word = norm, dungeon = dungeon }
    RebuildAndReclassify()
    ns.Fire("LFG_UPDATED", "words")
    return true
end

-- 사용자 키워드 삭제, dik, 2026-10-01
function ns.Lfg.RemoveCustomWord(word)
    if not state.ready or not state.area then
        return false
    end
    local _, compact = ns.Lfg.NormalizeWord(word)
    if not compact then
        return false
    end
    local custom = state.area.custom
    for i = 1, #custom do
        local _, c = ns.Lfg.NormalizeWord(custom[i].word)
        if c == compact then
            table.remove(custom, i)
            RebuildAndReclassify()
            ns.Fire("LFG_UPDATED", "words")
            return true
        end
    end
    return false
end

-- 사용자 키워드 내보내기(복사본), dik, 2026-10-02
function ns.Lfg.ExportCustomWords()
    local out = {}
    if not state.ready or not state.area then
        return out
    end
    local custom = state.area.custom
    for i = 1, #custom do
        out[#out + 1] = { word = custom[i].word, dungeon = custom[i].dungeon }
    end
    return out
end

-- 사용자 키워드 행, dik, 2026-10-01
function ns.Lfg.GetCustomRows()
    local rows = {}
    if not state.area then
        return rows
    end
    local custom = state.area.custom
    for i = 1, #custom do
        local entry = custom[i]
        local _, compact = ns.Lfg.NormalizeWord(entry.word)
        local category
        if entry.dungeon then
            category = ns.Lfg.GetDungeonName(entry.dungeon)
        else
            category = L.LFG_CUSTOM_NEW:format(entry.word)
        end
        rows[#rows + 1] = { id = compact, word = entry.word, categoryText = category }
    end
    return rows
end

-- 기본 사전 행, dik, 2026-10-01
function ns.Lfg.GetDictionaryRows()
    local rows = {}
    local dungeons = L.LFG_DUNGEONS
    if type(dungeons) ~= "table" then
        return rows
    end
    local sep = " " .. L.LFG_ROLE_SEP .. " "
    for i = 1, #dungeons do
        local d = dungeons[i]
        if IsValidDungeon(d) then
            local aliases = {}
            if type(d.aliases) == "table" then
                for a = 1, #d.aliases do
                    aliases[#aliases + 1] = tostring(d.aliases[a])
                end
            end
            rows[#rows + 1] = {
                id = d.key,
                name = d.name,
                aliasText = table.concat(aliases, sep),
                raid = d.raid == true,
            }
        end
    end
    return rows
end

-- 분류 선택 항목, dik, 2026-10-01
function ns.Lfg.GetCategoryItems()
    local items = { { value = "new", text = L.LFG_CATEGORY_NEW } }
    local dungeons = L.LFG_DUNGEONS
    if type(dungeons) == "table" then
        for i = 1, #dungeons do
            if IsValidDungeon(dungeons[i]) then
                items[#items + 1] = { value = dungeons[i].key, text = dungeons[i].name }
            end
        end
    end
    return items
end

-- 상태 조회, dik, 2026-10-01
function ns.Lfg.GetStatus()
    local missing = {}
    for i = 1, #state.missing do
        missing[i] = state.missing[i]
    end
    return {
        ready = state.ready,
        readOnly = state.readOnly,
        channelEnabled = state.channelEnabled,
        yellEnabled = state.yellEnabled,
        whisper = ns.HasAPI("ChatFrame_SendTell") or ns.HasAPI("ChatFrame_OpenChat"),
        invite = ns.HasAPI("C_PartyInfo.InviteUnit"),
        ticker = state.ticker ~= nil,
        secretSkipped = state.secretSkipped,
        total = CountPosts(),
        customCount = state.area and #state.area.custom or 0,
        expireMinutes = GetExpireMinutes(),
        missing = missing,
    }
end

-- 저장 영역 검증(제자리 보정), dik, 2026-10-01
local function ValidateArea(area)
    if not IsNumber(area.version) or area.version < 1 then
        area.version = AREA_VERSION
    end
    local clean = {}
    local seen = {}
    local src = type(area.custom) == "table" and area.custom or {}
    for i = 1, #src do
        local e = src[i]
        if type(e) == "table" then
            local word, compact = ns.Lfg.NormalizeWord(e.word)
            if word then
                local chars = ns.Lfg.CountChars(compact)
                if chars >= WORD_MIN_CHARS and chars <= WORD_MAX_CHARS and not seen[compact]
                    and #clean < CUSTOM_MAX then
                    seen[compact] = true
                    local dungeon
                    if type(e.dungeon) == "string" and builtinKeys[e.dungeon] then
                        dungeon = e.dungeon
                    end
                    clean[#clean + 1] = { word = word, dungeon = dungeon }
                end
            end
        end
    end
    area.custom = clean
end

-- 새 메모리 영역, dik, 2026-10-01
local function NewArea()
    return { version = AREA_VERSION, custom = {} }
end

-- 저장본 읽기 복사(쓰기 금지 모드), dik, 2026-10-01
local function CopyStored(raw)
    local area = { version = raw.version, custom = {} }
    if type(raw.custom) == "table" then
        for i = 1, #raw.custom do
            local e = raw.custom[i]
            if type(e) == "table" then
                local dungeon = type(e.dungeon) == "string" and e.dungeon or nil
                area.custom[#area.custom + 1] = { word = e.word, dungeon = dungeon }
            end
        end
    end
    return area
end

-- 준비(READY): 영역 검증·사전·주기, dik, 2026-10-01
local function Prepare()
    if state.ready then
        return
    end
    local area
    local readOnly = false
    if ns.IsDatabaseNewer() then
        readOnly = true
        local raw = nil
        if type(ns.db) == "table" and type(ns.db.modules) == "table" then
            raw = ns.db.modules[MODULE_ID]
        end
        if type(raw) == "table" and IsNumber(raw.version) and raw.version <= AREA_VERSION then
            area = CopyStored(raw)
            ValidateArea(area)
        else
            area = NewArea()
        end
    else
        local store = ns.GetModuleData(MODULE_ID)
        if type(store) ~= "table" then
            readOnly = true
            area = NewArea()
        elseif IsNumber(store.version) and store.version > AREA_VERSION then
            readOnly = true
            area = NewArea()
        else
            ValidateArea(store)
            area = store
        end
    end
    state.area = area
    state.readOnly = readOnly
    state.dict = ns.Lfg.BuildDictionary(L.LFG_DUNGEONS, L.LFG_WORDS, area.custom)
    if ns.HasAPI("C_Timer.NewTicker") and state.ticker == nil then
        state.ticker = C_Timer.NewTicker(PRUNE_INTERVAL, function()
            ApplyPrune()
            ns.Fire("LFG_UPDATED", "tick")
        end)
    end
    state.ready = true
    ns.Fire("LFG_UPDATED", "status")
end

-- 채팅 이벤트 수집, dik, 2026-10-01
local function OnEvent(_, event, ...)
    if not state.ready then
        return
    end
    local isYell = event == "CHAT_MSG_YELL"
    if isYell and ns.GetSetting(MODULE_ID, "includeYell") ~= true then
        return
    end
    local text, sender = ...
    if ns.IsSecret(text) or ns.IsSecret(sender) then
        state.secretSkipped = state.secretSkipped + 1
        if state.secretSkipped == 1 then
            ns.Fire("LFG_UPDATED", "status")
        end
        return
    end
    if type(text) ~= "string" or text == "" or type(sender) ~= "string" or sender == "" then
        return
    end
    local chanFull = select(4, ...)
    local chanBase = select(9, ...)
    local guid = select(12, ...)
    local guidOk = IsPlainString(guid)
    local shortName = ns.Lfg.ShortName(sender)
    local myGuid = UnitGUID("player")
    if guidOk and type(myGuid) == "string" and not ns.IsSecret(myGuid) and myGuid == guid then
        return
    end
    local myName = UnitName("player")
    if type(myName) == "string" and not ns.IsSecret(myName) and shortName == myName then
        return
    end
    if state.hasIgnore then
        local ignored = C_FriendList.IsIgnored(sender)
        if not ns.IsSecret(ignored) and ignored == true then
            return
        end
    end
    local result = ns.Lfg.Classify(text, state.dict)
    if not result then
        return
    end
    local classFile
    if guidOk and ns.HasAPI("GetPlayerInfoByGUID") then
        local _, englishClass = GetPlayerInfoByGUID(guid)
        if IsPlainString(englishClass) then
            classFile = englishClass
        end
    end
    local channel = ""
    if isYell then
        channel = L.LFG_SOURCE_YELL
    elseif IsPlainString(chanBase) then
        channel = chanBase
    elseif IsPlainString(chanFull) then
        channel = chanFull
    end
    state.posts[sender] = {
        id = sender,
        sender = sender,
        name = shortName,
        classFile = classFile,
        text = result.text,
        source = isYell and "yell" or "channel",
        channel = channel,
        at = time(),
        dungeons = result.dungeons,
        roles = result.roles,
        size = result.size,
    }
    ApplyPrune()
    ns.Fire("LFG_UPDATED", "posts")
end

-- 설정 변경 반영, dik, 2026-10-01
local function ApplySettings()
    if ns.GetSetting(MODULE_ID, "includeYell") ~= true then
        for id, p in pairs(state.posts) do
            if p.source == "yell" then
                state.posts[id] = nil
            end
        end
    end
    ApplyPrune()
    ns.Fire("LFG_UPDATED", "settings")
end

-- 이벤트 프레임·pcall 등록·선택 API 판정·안내, dik, 2026-10-01
local function InitializeTracking()
    local frame = CreateFrame("Frame")
    state.frame = frame
    frame:SetScript("OnEvent", OnEvent)
    local missing = {}
    local registered = {}
    for i = 1, #EVENT_ORDER do
        local name = EVENT_ORDER[i]
        if pcall(frame.RegisterEvent, frame, name) then
            registered[name] = true
        else
            missing[#missing + 1] = name
        end
    end
    state.channelEnabled = registered.CHAT_MSG_CHANNEL == true
    state.yellEnabled = registered.CHAT_MSG_YELL == true
    state.hasIgnore = ns.HasAPI("C_FriendList.IsIgnored")
    state.dict = ns.Lfg.BuildDictionary(L.LFG_DUNGEONS, L.LFG_WORDS, nil)
    if not ns.HasAPI("ChatFrame_SendTell") and not ns.HasAPI("ChatFrame_OpenChat") then
        missing[#missing + 1] = "ChatFrame_SendTell"
        missing[#missing + 1] = "ChatFrame_OpenChat"
    end
    if not ns.HasAPI("C_PartyInfo.InviteUnit") then
        missing[#missing + 1] = "C_PartyInfo.InviteUnit"
    end
    if not ns.HasAPI("C_Timer.NewTicker") then
        missing[#missing + 1] = "C_Timer.NewTicker"
    end
    state.missing = missing
    ns.On("READY", Prepare)
    if #missing > 0 then
        ns.Print(L.MSG_LFG_UNSUPPORTED:format(ns.FormatMissingAPIs(missing)))
    end
end

-- 모듈 등록, dik, 2026-10-01
ns.RegisterModule({
    id = "lfg",
    title = L.MODULE_LFG,
    -- 모듈 설명 추가, dik, 2026-10-01
    description = L.MODULE_LFG_DESC,
    category = "feature",
    order = 80,
    requires = { "time" },
    settings = {
        { key = "expireMinutes", type = "slider", label = L.SETTING_LFG_EXPIRE,
            tooltip = L.SETTING_LFG_EXPIRE_TIP, min = 5, max = 30, step = 5, default = 15 },
        { key = "includeYell", type = "checkbox", label = L.SETTING_LFG_YELL,
            tooltip = L.SETTING_LFG_YELL_TIP, default = true },
    },
    OnInitialize = function()
        InitializeTracking()
    end,
    OnSettingChanged = function()
        ApplySettings()
    end,
})
