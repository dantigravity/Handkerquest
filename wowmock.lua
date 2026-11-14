-- Minimal WoW API mock: enough surface for Handkerquest to load and run its main paths.
ERRORS = {}
local function noop() end

local frameMT
local allFrames = {}
local function NewRegion(kind, parent, name)
    local o = {
        __kind = kind, __shown = (kind ~= "Frame" and kind ~= "Button") and true or true,
        __parent = parent, __w = 0, __h = 0, __alpha = 1, __level = 1, __scripts = {},
        __points = {}, __text = "", __events = {}, __mouse = true,
    }
    setmetatable(o, frameMT)
    if name then _G[name] = o end
    table.insert(allFrames, o)
    return o
end

local methods = {}
function methods:SetSize(w, h) self.__w, self.__h = w, h; local s = self.__scripts.OnSizeChanged; if s then s(self, w, h) end end
function methods:SetWidth(w) self.__w = w end
function methods:SetHeight(h) self.__h = h end
function methods:GetWidth() if self.__w == 0 and self.__parent and self.__parent.GetWidth then return self.__parent:GetWidth() end return self.__w end
function methods:GetHeight() if self.__h == 0 and self.__parent and self.__parent.GetHeight then return self.__parent:GetHeight() end return self.__h end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
function methods:Show() self.__shown = true; local s = self.__scripts.OnShow; if s then s(self) end end
function methods:Hide() local was = self.__shown; self.__shown = false; local s = self.__scripts.OnHide; if s and was then s(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.__shown end
function methods:IsVisible() return self.__shown end
function methods:SetScript(k, fn) self.__scripts[k] = fn end
function methods:GetScript(k) return self.__scripts[k] end
function methods:HookScript(k, fn) local old = self.__scripts[k]; self.__scripts[k] = function(...) if old then old(...) end fn(...) end end
function methods:SetPoint(p, rel, rp, x, y) table.insert(self.__points, { p, rel, rp, x, y }); self.__px = (type(rel) == "number" and rel) or x or 0; self.__py = (type(rp) == "number" and rp) or y or 0 end
function methods:ClearAllPoints() self.__points = {} end
function methods:GetPoint(i) local pt = self.__points[i or 1]; if pt then return pt[1], pt[2], pt[3], pt[4], pt[5] end end
function methods:GetCenter() return 300 + (self.__px or 0), 400 + (self.__py or 0) end
function methods:GetLeft() return 100 + (self.__px or 0) end
function methods:GetTop() return 500 + (self.__py or 0) end
function methods:GetBottom() return 300 end
function methods:GetRight() return 400 end
function methods:GetRect() if self.__rect then return unpack(self.__rect) end return nil end
function methods:SetTexture(t) self.__tex = t; self.__color = nil; return true end
function methods:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a }; self.__tex = nil end
function methods:SetVertexColor(r, g, b, a) self.__vc = { r, g, b, a or 1 } end
function methods:SetShadowColor(r, g, b, a) self.__shadow = { r, g, b, a or 1 } end
function methods:SetShadowOffset(x, y) self.__shadowOff = { x, y } end
function methods:SetTexCoord(...) self.__tc = { ... } end
function methods:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
function methods:SetRotation(r) self.__rotation = r end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:SetAlpha(a) self.__alpha = a end
function methods:GetAlpha() return self.__alpha end
function methods:SetFrameLevel(l) self.__level = l end
function methods:SetFrameStrata(s) self.__strata = s end
function methods:SetAttribute(k, v) self.__attr = self.__attr or {}; self.__attr[k] = v end
function methods:GetAttribute(k) return self.__attr and self.__attr[k] end
function methods:GetFrameStrata() return self.__strata or "MEDIUM" end
function methods:GetFrameLevel() return self.__level end
function methods:SetParent(p) self.__parent = p end
function methods:GetParent() return self.__parent end
function methods:SetText(t)
    if self.__kind == "EditBox" and not self.__template and not self.__font then
        error("EditBox:SetText(): Font not set", 2)
    end
    self.__text = t or ""
end
function methods:GetText() return self.__text end
function methods:GetStringWidth() return 6 * #tostring(self.__text or "") end
function methods:GetUnboundedStringWidth() return 6 * #tostring(self.__text or "") end
function methods:GetStringHeight() return 12 end
function methods:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function methods:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function methods:SetFont(path, size, flags) self.__font = { path, size, flags }; return true end
function methods:GetFont() local f = self.__font; if f then return f[1], f[2], f[3] end return "Fonts\\FRIZQT__.TTF", 12, "" end
function methods:GetChecked() return self.__checked end
function methods:SetChecked(v) self.__checked = v end
function methods:IsMouseEnabled() return self.__mouse end
function methods:EnableMouse(v) self.__mouse = v end
function methods:IsMouseOver() return false end
function methods:GetChildren() return end
function methods:GetName() return nil end
function methods:GetID() return 42 end
function methods:RegisterEvent(e) self.__events[e] = true end
function methods:UnregisterEvent(e) self.__events[e] = nil end
function methods:CreateTexture(name) return NewRegion("Texture", self, name) end
function methods:CreateMaskTexture(name) return NewRegion("MaskTexture", self, name) end
function methods:CreateFontString(name) return NewRegion("FontString", self, name) end
function methods:CreateLine(name) return NewRegion("Line", self, name) end
function methods:GetTexture() return "tex" end
function methods:GetOwner() return nil end
methods.StartMoving = noop
methods.StopMovingOrSizing = noop

frameMT = { __index = function(t, k)
    local m = methods[k]
    if m then return m end
    local fields = { HeaderButton = true, Header = true, Text = true, Checkbox = true, TagTexture = true,
                     Contents = true, HeaderMenu = true, ContentsFrame = true }
    if fields[k] then return nil end
    if type(k) == "string" and k:match("^[A-Z]") then return noop end   -- any other Widget API call
    return nil
end }

function CreateFrame(kind, name, parent, template)
    local o = NewRegion(kind or "Frame", parent, name)
    o.__template = template
    return o
end
UIParent = CreateFrame("Frame", "UIParent"); UIParent.__w, UIParent.__h = 1920, 1080
UIParent.GetCenter = function() return 960, 540 end
ChatFrame1 = CreateFrame("Frame", "ChatFrame1"); ChatFrame1.__w, ChatFrame1.__h = 430, 120
GameTooltip = CreateFrame("Frame", "GameTooltip")
ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame")
ObjectiveTrackerFrame.Header = CreateFrame("Frame", nil, ObjectiveTrackerFrame)
QuestObjectiveTracker = CreateFrame("Frame", "QuestObjectiveTracker")
QuestObjectiveTracker.ContentsFrame = CreateFrame("Frame", nil, QuestObjectiveTracker)
QuestObjectiveTracker.Header = CreateFrame("Frame", nil, QuestObjectiveTracker)
QuestScrollFrame = CreateFrame("Frame", "QuestScrollFrame")
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame"); WorldMapFrame.__shown = false
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
Enum = { VertexIndex = { TopLeft = 1, BottomLeft = 2, TopRight = 3, BottomRight = 4 } }

NOW = 1000
function GetTime() return NOW end
function GetCursorPosition() return 500, 500 end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function UnitLevel() return 7 end
function UnitName() return "Gnarlpine Ambusher" end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then local old = a[b]; a[b] = function(...) local r = old and old(...); c(...); return r end
    elseif type(a) == "string" then local old = _G[a]; _G[a] = function(...) local r = old and old(...); b(...); return r end end
end
function geterrorhandler() return function(msg) table.insert(ERRORS, msg); print("ERRORHANDLER: " .. tostring(msg)) end end
function debugstack() return "(stack)" end
SlashCmdList = {}
function CreateVector2D(x, y) return { GetXY = function() return x, y end } end

ZONE, SUBZONE = "Teldrassil", "Dolanaar"
function GetRealZoneText() return ZONE end
function GetSubZoneText() return SUBZONE end

C_Timer = { After = function(_, fn) TIMERS = TIMERS or {}; table.insert(TIMERS, fn) end,
            NewTicker = function(_, fn) TICKER = fn; return {} end }
C_Map = {
    GetBestMapForUnit = function() return 57 end,
    GetPlayerMapPosition = function() return { GetXY = function() return PX or 0.55, PY or 0.60 end } end,
    GetWorldPosFromMapPos = function(mapID, v) local x, y = v.GetXY(); return 1, CreateVector2D(x * 4000, y * 4000) end,
    GetMapInfo = function(id) return { name = (id == 62) and "Darkshore" or "Teldrassil" } end,
}
C_Texture = { GetAtlasInfo = function(a) if a == "QuestLog-icon-setting" then return { width = 16 } end end }
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end, SetSuperTrackedQuestID = noop }

-- Quest log: header + 4 quests (two with the broken "/N" objective text from the screenshot)
WATCHED = { [101] = true, [102] = true }
QUESTS = {
    { isHeader = true, title = "Teldrassil" },
    { questID = 101, title = "Recipe of the Kaldorei", level = 7, complete = false,
      objs = { { text = "1/7 Small Spider Leg", type = "item", numFulfilled = 1, numRequired = 7, finished = false } },
      coords = { 57, 0.56, 0.61 } },
    { questID = 102, title = "Webwood Venom", level = 6, complete = false,
      objs = { { text = "/6 Gnarlpine Ambusher slain", type = "monster", numFulfilled = 0, numRequired = 6, finished = false },
               { text = "/1 Cenarion Hold depths entrance", type = "event", numFulfilled = 0, numRequired = 1, finished = false } },
      coords = { 57, 0.57, 0.60 } },
    { questID = 103, title = "Denalan's Earth", level = 5, complete = true,
      objs = { { text = "Gnarlpine Fang: 7/15", type = "item", numFulfilled = 15, numRequired = 15, finished = true } },
      coords = { 57, 0.58, 0.62 } },
    { isHeader = true, title = "Darkshore" },
    { questID = 104, title = "Bashal'Aran", level = 13, complete = false,
      objs = { { text = "0/8 Grell Earring", type = "item", numFulfilled = 0, numRequired = 8, finished = false } },
      coords = { 62, 0.40, 0.30 } },
}
local byID = {}
for i, q in ipairs(QUESTS) do if q.questID then byID[q.questID] = q; q.logIndex = i end end

C_QuestLog = {
    GetNumQuestLogEntries = function() return #QUESTS end,
    GetInfo = function(i) local q = QUESTS[i]; if not q then return nil end
        return { isHeader = q.isHeader, title = q.title, questID = q.questID, level = q.level, isHidden = false, suggestedGroup = 0 } end,
    GetQuestObjectives = function(id) local q = byID[id]; return q and q.objs or {} end,
    ReadyForTurnIn = function(id) return byID[id] and byID[id].complete or false end,
    IsComplete = function(id) return byID[id] and byID[id].complete or false end,
    GetQuestWatchType = function(id) return WATCHED[id] and 0 or nil end,
    AddQuestWatch = function(id) WATCHED[id] = true end,
    RemoveQuestWatch = function(id) WATCHED[id] = nil end,
    GetNextWaypoint = function(id) local q = byID[id]; if q and q.coords then return q.coords[1], q.coords[2], q.coords[3] end end,
    IsOnQuest = function(id) return byID[id] ~= nil end,
    GetRewardMoney = function() return 50 end,
    GetQuestRewardCurrencies = function() return {} end,
    GetTitleForQuestID = function(id) return byID[id] and byID[id].title end,
    SetSelectedQuest = noop,
}
function GetNumQuestLogRewards() return 0 end
function GetNumQuestLogChoices() return 0 end

Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return 99 end, panel = panel } end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, name)
        SETTINGS_SUB = { GetID = function() return 100 end, panel = panel, parent = parent, name = name }
        return SETTINGS_SUB
    end,
    RegisterAddOnCategory = function(cat) SETTINGS_CAT = cat end,
    OpenToCategory = function(id)
        OPENED_SETTINGS = id
        if SETTINGS_SUB and id == 100 then SETTINGS_SUB.panel:Show() else SETTINGS_CAT.panel:Show() end
    end,
}

-- WoW's colour picker (retail API): remembers the last request; tests set __rgb and call info.swatchFunc
ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame")
function ColorPickerFrame:SetupColorPickerAndShow(info) self.__info = info; self.__rgb = { info.r, info.g, info.b }; self:Show() end
function ColorPickerFrame:GetColorRGB() local c = self.__rgb or { 1, 1, 1 }; return c[1], c[2], c[3] end

-- Addon metadata: read from the real .toc next to the mock, like the client does
C_AddOns = {
    GetAddOnMetadata = function(addon, field)
        if addon ~= "Handkerquest" then return nil end
        local here = (arg and arg[0] and arg[0]:match("^(.*)[/\]")) or "."
        local fh = io.open(here .. "/Handkerquest.toc")
        if not fh then return nil end
        local found
        for line in fh:lines() do
            local k, v = line:gsub("\r", ""):match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
            if k == field then found = v; break end
        end
        fh:close()
        return found
    end,
}

-- Clocks: the realm's calendar time (retail API) plus WoW's global date()/time()
C_DateAndTime = {
    GetCurrentCalendarTime = function() return { year = 2026, month = 11, monthDay = 10, weekday = 3, hour = 21, minute = 40 } end,
}
function GetServerTime() return 1794350400 end
date = date or os.date
time = time or os.time
function GetRealmName() return "Forever" end
PLAYER_FACING = 0                      -- set by tests: radians from north, counter-clockwise (nil = unknown)
function GetPlayerFacing() return PLAYER_FACING end
GUILD_NAME = nil                       -- set by tests: the player's guild
function GetGuildInfo(unit) if unit == "player" and GUILD_NAME then return GUILD_NAME, "Member", 5 end return nil end

-- Achievements (retail API): id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild
ACHIEVEMENTS = {
    [6] = { "Level 10", 10, "Reach level 10." },
    [891] = { "Giddy Up!", 10, "Learn the riding skill." },
    [503] = { "50 Quests Completed", 10, "Complete 50 quests." },
    [5362] = { "Guild Level 5", 0, "Reach guild level 5.", true },
    [42] = { "Pipe|cFFFF0000 Dream|r", 0, "Odd name." },
}
-- The quest reward panel (retail API): set QUEST_PANEL, then fire QUEST_COMPLETE
QUEST_PANEL = nil   -- { id, title, rewards = { { name, count, quality, itemID } }, choices = { ... } }
function GetQuestID() return QUEST_PANEL and QUEST_PANEL.id or 0 end
function GetTitleText() return QUEST_PANEL and QUEST_PANEL.title or "" end
function GetNumQuestRewards() return QUEST_PANEL and #QUEST_PANEL.rewards or 0 end
function GetNumQuestChoices() return QUEST_PANEL and #QUEST_PANEL.choices or 0 end
function GetQuestItemInfo(kind, i)
    local list = QUEST_PANEL and ((kind == "choice") and QUEST_PANEL.choices or QUEST_PANEL.rewards)
    local it = list and list[i]
    if not it then return nil end
    return it[1], 134400, it[2], it[3], true, it[4]
end
function GetQuestItemLink(kind, i)
    local list = QUEST_PANEL and ((kind == "choice") and QUEST_PANEL.choices or QUEST_PANEL.rewards)
    local it = list and list[i]
    return it and ("|cff1eff00|Hitem:" .. it[4] .. "|h[" .. it[1] .. "]|h|r") or nil
end
QUEST_REWARD_TAKEN = nil
function GetQuestReward(choice) QUEST_REWARD_TAKEN = choice end
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }

function GetAchievementInfo(id)
    local a = ACHIEVEMENTS[id]
    if not a then return nil end
    return id, a[1], a[2], true, 11, 10, 26, a[3], 0, 236, "", a[4] or false
end
