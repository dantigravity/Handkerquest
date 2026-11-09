local here = (arg[0]:match("^(.*)[/\\]") or ".")
dofile(here .. "/wowmock.lua")
local addonPath = arg[1] or (here .. "/../Handkerquest.lua")

-- Expose the addon's locals to the test (test copy only)
local src = assert(io.open(addonPath), "cannot open " .. addonPath):read("*a") .. "\n_G.__CFQ = CFQ\n_G.__LAYOUT = function() LayoutObjectiveTrackerWithStacks() end\n_G.__QMAP = function() return questRewardMap end\n_G.__STATE = function() return { lvl = levelSortMode, dist = distSortMode, primary = primarySortKey, incomp = incompleteStackEnabled, turnin = turnInStackEnabled } end\n"
local chunk = assert(loadstring(src, "Handkerquest.lua"))
chunk()
local CFQ, P = __CFQ, __CFQ.P

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. msg) end
end
local function frames(n, dt)
    local f = QRF_ClusterShoppingList
    for _ = 1, n do NOW = NOW + (dt or 0.016); local s = f:GetScript("OnUpdate"); if f:IsShown() and s then s(f, dt or 0.016) end end
end

-- Tracker blocks for watched quests (+ any of our own frames parented to the contents frame)
local contents = QuestObjectiveTracker.ContentsFrame
local blocks = {}
contents.GetChildren = function(self)
    local out = {}
    for id in pairs(WATCHED) do
        local b = blocks[id]
        if not b then
            b = CreateFrame("Frame", nil, contents); b.id = id; b.HeaderText = b:CreateFontString(); b.__h = 36
            blocks[id] = b
        end
        b.__shown = true
        table.insert(out, b)
    end
    for id, b in pairs(blocks) do if not WATCHED[id] then b.__shown = false; table.insert(out, b) end end
    return unpack(out)
end

-- Boot
-- simpler: wowmock stores frames in an upvalue 'allFrames' of NewRegion; grab it
local NewRegion, Fire
do
    local i = 1
    while true do
        local name, val = debug.getupvalue(CreateFrame, i)
        if not name then break end
        if name == "NewRegion" then NewRegion = val end
        i = i + 1
    end
end
local allFrames
do
    local i = 1
    while true do
        local name, val = debug.getupvalue(NewRegion, i)
        if not name then break end
        if name == "allFrames" then allFrames = val end
        i = i + 1
    end
end
Fire = function(event, ...)
    for _, fr in ipairs(allFrames) do
        if fr.__events and fr.__events[event] and fr.__scripts.OnEvent then
            fr.__scripts.OnEvent(fr, event, ...)
        end
    end
end

Fire("ADDON_LOADED", "Handkerquest")
Fire("PLAYER_ENTERING_WORLD")
for _, t in ipairs(TIMERS or {}) do t() end; TIMERS = {}

local f = QRF_ClusterShoppingList
check(f ~= nil, "parchment frame exists")
check(f:IsShown(), "parchment shown with nearby quantity quests")

-- 1) Redundant "/N" fix
local foundBad, foundGood, foundKill, foundEvent = false, false, false, false
for _, fr in ipairs(allFrames) do
    if fr.__kind == "FontString" and type(fr.__text) == "string" and fr.__shown ~= false then
        if fr.__text:find("%d/%d+|r  |c%x+/%d") or fr.__text:find(" /6 ") or fr.__text:find(" /1 ") then foundBad = true end
        if fr.__text:find("1/7|r  |c%x%x%x%x%x%x%x%xSmall Spider Leg") then foundGood = true end
        if fr.__text:find("0/6|r  |c%x+Gnarlpine Ambusher slain") then foundKill = true end
        if fr.__text:find("^|c%x+Cenarion Hold depths entrance|r$") then foundEvent = true end   -- one-off step: no "0/1"
    end
end
check(not foundBad, "no redundant '/N' left in parchment rows")
check(foundGood, "item row reads '1/7  Small Spider Leg'")
check(foundKill, "kill objective of a multi-step quest is on the tally as '0/6  Gnarlpine Ambusher slain'")
check(foundEvent, "one-off step of a multi-step quest is on the tally, without a count")
check(#CFQ.P.FlattenQuests({ { questID = 1, quantityObjectives = { {}, {} }, itemObjectives = { { itemName = "x" } } } }) == 1, "FlattenQuests: quest-wide counts aren't lines")
check(CFQ.IsCollectItemObjective("item", "Gnarlpine Fang"), "type=item is collectable")
check(not CFQ.IsCollectItemObjective("monster", "Grell Earring"), "type=monster never collectable")
check(not CFQ.IsCollectItemObjective("object", "Moonwell Water Tube"), "type=object (use/click) not collectable")
check(not CFQ.IsCollectItemObjective(nil, "Gnarlpine Ambusher slain"), "untyped '... slain' falls back to not-item")
check(not CFQ.IsCollectItemObjective(nil, "Speak with Denalan"), "untyped 'Speak with' falls back to not-item")
check(CFQ.IsCollectItemObjective(nil, "Small Spider Leg"), "untyped plain noun falls back to item")
check(CFQ.IsCollectItemObjective(nil, "Lightning Gland"), "'lit' inside a word doesn't trigger the not-item list")
check(CFQ.CleanObjectiveName("/1 Cenarion Hold depths entrance") == "Cenarion Hold depths entrance", "CleanObjectiveName leading /1")
check(CFQ.CleanObjectiveName("Gnarlpine Fang: 7/15") == "Gnarlpine Fang", "CleanObjectiveName trailing count")
check(CFQ.CleanObjectiveName("0/6 Gnarlpine Ambusher slain") == "Gnarlpine Ambusher slain", "CleanObjectiveName full count")
check(CFQ.FormatObjectiveLine("/6 Gnarlpine Ambusher slain", 2, 6) == "2/6 Gnarlpine Ambusher slain", "FormatObjectiveLine rebuild")
check(CFQ.FormatObjectiveLine("Speak with Denalan", 0, 1) == "Speak with Denalan", "FormatObjectiveLine leaves plain text")

-- 1b) Finished item: quill tick + strike only through "count  name", "(turn in)" kept separate
local strokes = {}
local realDraw = P.DrawStroke
P.DrawStroke = function(s, rel, x0, y0, x1, y1, ...)
    table.insert(strokes, { s = s, rel = rel, x0 = x0, x1 = x1 })
    return realDraw(s, rel, x0, y0, x1, y1, ...)
end
Fire("ZONE_CHANGED")   -- re-renders the parchment (same zone: no page turn)
P.DrawStroke = realDraw
local fangRow
for _, fr in ipairs(allFrames) do
    if fr.__kind == "FontString" and fr.__shown ~= false and fr.__text == "15/15  Gnarlpine Fang"
        and fr.__parent and fr.__parent.itemText == fr then fangRow = fr end
end
check(fangRow ~= nil, "finished row text is just '15/15  Gnarlpine Fang' (no turn-in inside it)")
local strike
for _, st in ipairs(strokes) do if st.rel == fangRow then strike = st end end
check(strike ~= nil, "finished row has a strike line")
local textW = 6 * #"15/15  Gnarlpine Fang"
check(strike and strike.x0 == -2 and strike.x1 == textW + 2, "strike spans only the item text (+2px overhang), got " ..
    tostring(strike and strike.x0) .. ".." .. tostring(strike and strike.x1) .. " for text width " .. textW)
local suffixShown = false
for _, fr in ipairs(allFrames) do
    if fr.__kind == "FontString" and fr.__shown ~= false and fr.__text == "(turn in)" then suffixShown = true end
end
check(suffixShown, "'(turn in)' written separately, outside the strike")
local tickDrawn = 0
for _, st in ipairs(strokes) do if st.rel and st.rel.tick then tickDrawn = tickDrawn + 1 end end
check(tickDrawn >= 3, "quill tick drawn in the finished row's box (" .. tickDrawn .. " strokes)")
-- multi-line wrap: one strike per line, each as wide as its own words
local mfs = f.measureFS
local lines, widths = P.WrapLines(mfs, "3/3  Very Long Ancient Kaldorei Relic Fragment", 100)
check(#lines >= 2, "long finished entry wraps to several lines")
local okW = true
for i, ln in ipairs(lines) do if widths[i] ~= math.min(100, 6 * #ln) or 6 * #ln > 100 then okW = false end end
check(okW, "each wrapped line fits and gets its own measured width")

-- 2) Pages: one per area, pile under the top page, dog-eared corner
check(#P.areas >= 2, "current area + other-area page (got " .. #P.areas .. ")")
check(P.areas[1].title == "Near me" and P.areas[1].subtitle == "Dolanaar", "page 1 is \"Near me\" with your subzone as subtitle")
check(f.titleFS.__text:find("^Near me") and f.titleFS.__text:find("Dolanaar"), "heading reads Near me · Dolanaar: " .. tostring(f.titleFS.__text))
local nearIDs = {}
for _, q in ipairs(P.areas[1].quests) do nearIDs[q.questID] = true end
check(nearIDs[101] and nearIDs[103], "quests gathered right beside you are on Near me")
check(not nearIDs[104], "Darkshore quest is not on Near me")
CFQ.nearRadiusPercent = 1
Fire("ZONE_CHANGED")
nearIDs = {}
for _, q in ipairs(P.areas[1].quests) do nearIDs[q.questID] = true end
check(not nearIDs[101], "shrinking Near me distance drops quests that are further away")
local on2 = false
for i = 2, #P.areas do for _, q in ipairs(P.areas[i].quests) do if q.questID == 101 then on2 = true end end end
check(on2, "a quest that leaves Near me moves onto an area page")
CFQ.nearRadiusPercent = 10
Fire("ZONE_CHANGED")
local dark
for _, a in ipairs(P.areas) do if a.title and a.title:find("Darkshore") then dark = a end end
check(dark ~= nil and dark.title == "North-western Darkshore", "Darkshore quest gets a compass-named page (" .. tostring(dark and dark.title) .. ")")
check(P.ribbonPool == nil and P.UpdateRibbons == nil, "ribbons are gone")
check(f.scopeBtn == nil, "Area/Zone/All scope button is gone")
check(f.corner ~= nil and f.corner:IsShown(), "dog-eared corner shown when there are other pages")
check(f.visibleBackSheets == math.min(#P.areas - 1, 3), "pile shows one sheet per other page")
check(f.footerFS.__text:find("page 1 of " .. #P.areas), "footer shows page number: " .. tostring(f.footerFS.__text))
check(shoppingListCfg == nil, "shoppingListCfg stays local") -- sanity: not leaked to _G

-- default position: BOTTOMLEFT above chat, with room for the pile under the top page
local pt, _, relPt, defX, defY = f:GetPoint(1)
check(pt == "BOTTOMLEFT" and relPt == "BOTTOMLEFT", "default anchor bottom-left above chat (got " .. tostring(pt) .. ")")
-- mock chat frame: left 100, top 500; +32 for the tabs, + the pile margins
check(defX == 100 + P.PILE_MARGIN_X and defY == 500 + 32 + P.PILE_MARGIN_Y,
    "default spot clears the chat tabs by the pile margin (got " .. tostring(defX) .. "," .. tostring(defY) .. ")")
check(P.PILE_MARGIN_Y >= 14, "pile margin covers the back sheets' overhang (~9px offset + torn edge)")
ChatFrame1Tab = CreateFrame("Frame", "ChatFrame1Tab"); ChatFrame1Tab:SetPoint("BOTTOMLEFT", 0, 60)   -- a tall tab: top 560
local tx, ty = P.ComputeDefaultAnchor()
check(ty == 560 + P.PILE_MARGIN_Y, "a taller chat tab pushes the default spot up (got " .. tostring(ty) .. ")")
ChatFrame1Tab = nil
-- no yellow square: the brass tack is gone
local addonSrc = io.open(addonPath):read("*a")
check(not addonSrc:find("tackHead") and not addonSrc:find("Brass tack"), "brass tack (yellow square) removed")

-- 3) Hot corner: hover lifts it, click turns to the next page
local corner = f.corner
corner:GetScript("OnEnter")(corner)
frames(30)
check(math.abs(corner.size - P.CORNER_HOVER) < 0.01, "hovering lifts the dog-ear (size " .. corner.size .. ")")
corner:GetScript("OnLeave")(corner)
frames(30)
check(math.abs(corner.size - P.CORNER_REST) < 0.01, "leaving lets it fall back")
local nextArea = P.GetNeighborArea(1)
corner:GetScript("OnClick")(corner, "LeftButton")
check(f.shuffle ~= nil, "clicking the corner starts the page turn")
frames(40)
check(f.shuffle == nil, "page turn finishes")
check(P.selectedKey == nextArea.key, "next page now on top")
check(f.titleFS.__text:find(nextArea.title, 1, true), "title shows the next page's area")
check(f.footerFS.__text:find("page 2 of"), "footer shows page 2")
corner:GetScript("OnClick")(corner, "RightButton")
frames(40)
check(P.selectedKey == P.CURRENT_KEY, "right-click turns back a page")
-- wrap-around: turning past the last page returns to the first
for _ = 1, #P.areas do corner:GetScript("OnClick")(corner, "LeftButton"); frames(40) end
check(P.selectedKey == P.CURRENT_KEY, "pages wrap around")
P.SelectArea(dark.key, false)
check(P.selectedKey == dark.key, "jump straight to Darkshore page")

-- 4) Entering a new area: current page is turned back to the top, heading in fresh red ink
SUBZONE = "Ban'ethil Barrow Den"
Fire("ZONE_CHANGED")
frames(40)
check(P.selectedKey == P.CURRENT_KEY, "current-area page back on top after area change")
check(P.currentGlowUntil > NOW, "fresh-ink highlight active")
check(P.areas[1].subtitle == "Ban'ethil Barrow Den", "Near me subtitle follows the new subzone")

-- 4a) Page grouping by radius
local function Q(id, x, y) return { questID = id, mapID = 57, x = x, y = y, header = "Teldrassil" } end
local pg = P.ClusterIntoPages({ Q(1, 0.20, 0.20), Q(2, 0.25, 0.22), Q(3, 0.80, 0.80) }, 0.10)
check(#pg == 2, "far-apart quests get separate pages (" .. #pg .. ")")
-- a chain of quests 8% apart: single-linkage would make one page, leader clustering must not
local chain = {}
for i = 0, 8 do chain[#chain + 1] = Q(10 + i, 0.10 + i * 0.08, 0.5) end
check(#P.ClusterIntoPages(chain, 0.10) >= 3, "a long chain of quests doesn't collapse into one page")
check(#P.ClusterIntoPages({ Q(1, 0.2, 0.2), Q(2, 0.8, 0.8) }, 0.90) == 1, "a big radius merges them onto one page")
check(P.CompassName(0.5, 0.15, "Teldrassil") == "Northern Teldrassil", "compass name north")
check(P.CompassName(0.85, 0.85, "Teldrassil") == "South-eastern Teldrassil", "compass name south-east")
check(P.CompassName(0.52, 0.47, "Teldrassil") == "Central Teldrassil", "compass name centre")
CFQ.learnedQuestAreas[777] = "Starbreeze Village"
check(P.NamePage({ cx = 0.2, cy = 0.2, quests = { { questID = 777, header = "Teldrassil" } } }) == "Starbreeze Village",
    "a page is named after where its objectives were worked, when known")
-- sync with the tracker's (•••) slider vs. own radius
CFQ.parchmentOpts.pagesFollowTracker = true
QRF_TrackerSubHeaderBar.incompSlider:GetScript("OnValueChanged")(QRF_TrackerSubHeaderBar.incompSlider, 7)
check(P.GetPageRadius() == 7, "page radius follows the tracker (•••) slider")
check(__STATE().incomp, "moving the (•••) slider switches its stacking on (existing behaviour)")
QRF_TrackerSubHeaderBar.incompSlider:GetScript("OnValueChanged")(QRF_TrackerSubHeaderBar.incompSlider, 16)
QRF_TrackerSubHeaderBar.incompToggle:GetScript("OnClick")(QRF_TrackerSubHeaderBar.incompToggle)   -- back off for section 6
CFQ.parchmentOpts.pagesFollowTracker = false
CFQ.pageRadiusPercent = 30
check(P.GetPageRadius() == 30, "own page radius when not following the tracker")
CFQ.parchmentOpts.pagesFollowTracker = true

-- 4a2) Area page grouping modes; same-named pages always merge (no "Dolanaar II")
local function Titles()
    local t = {}
    for i = 2, #P.areas do t[#t + 1] = P.areas[i].title end
    table.sort(t)
    return table.concat(t, "|")
end
CFQ.nearRadiusPercent = 1                       -- push 101 off Near me so both 101 and 104 are on area pages
C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function(mapID) return { (mapID == 62) and 2 or 1 } end }
C_Map.GetAreaInfo = function(id) return (id == 2) and "Bashal'Aran" or "Dolanaar" end
CFQ.pageGrouping = "AREA"; Fire("ZONE_CHANGED")
check(Titles() == "Bashal'Aran|Dolanaar", "Map areas: pages named by the explored subzone at the items (" .. Titles() .. ")")
CFQ.pageGrouping = "ZONE"; Fire("ZONE_CHANGED")
check(Titles() == "Darkshore|Teldrassil", "Zones: one page per zone (" .. Titles() .. ")")
C_MapExplorationInfo = nil; wipe(P.areaNameCache)
CFQ.learnedQuestAreas[101], CFQ.learnedQuestAreas[104] = "Dolanaar", "Dolanaar"
CFQ.pageGrouping = "RADIUS"; Fire("ZONE_CHANGED")
check(Titles() == "Dolanaar", "Distance: far-apart clusters with the same name merge into one page (" .. Titles() .. ")")
check(not Titles():find(" II"), "no sequencing suffixes")
CFQ.learnedQuestAreas[101], CFQ.learnedQuestAreas[104] = nil, nil
CFQ.pageGrouping = "AREA"
P.CycleGrouping(); check(CFQ.pageGrouping == "ZONE", "grouping cycles AREA -> ZONE")
P.CycleGrouping(); check(CFQ.pageGrouping == "RADIUS", "grouping cycles ZONE -> RADIUS")
P.CycleGrouping(); check(CFQ.pageGrouping == "AREA", "grouping cycles back to AREA")
CFQ.nearRadiusPercent = 10; Fire("ZONE_CHANGED")

-- 4b) Handwriting cycles and persists
local before = CFQ.parchmentFont
P.CycleFontStyle()
check(CFQ.parchmentFont ~= before, "handwriting style cycles")
for _ = 1, #P.FONT_STYLES - 1 do P.CycleFontStyle() end
check(CFQ.parchmentFont == before, "handwriting style cycles back around")

-- 4c) Item-only wording fallback (untyped objectives)
check(CFQ.IsCollectItemObjective(nil, "Scout's Report"), "possessive 'Scout's Report' stays an item")
check(not CFQ.IsCollectItemObjective(nil, "Find the lost caravan"), "untyped 'Find ...' is not an item")
check(not CFQ.IsCollectItemObjective(nil, "Search the barrels"), "untyped 'Search ...' is not an item")
check(not CFQ.IsCollectItemObjective(nil, "Supplies delivered"), "untyped '... delivered' is not an item")
check(CFQ.IsCollectItemObjective(nil, "Founder's Token"), "'found' inside a word doesn't trigger the not-item list")

-- helpers: the tally row showing an item
local function RowFor(itemName)
    for _, fr in ipairs(allFrames) do
        if fr.__kind == "FontString" and fr.__shown ~= false and type(fr.__text) == "string"
            and fr.__text:find(itemName, 1, true) and fr.__parent and fr.__parent.box and fr.__parent.itemText == fr
            and fr.__parent.__shown then
            return fr.__parent
        end
    end
end
-- the item tests below look for rows by name: loot only, so they all fit on the mock tally (the
-- check-off tests further down switch slaying and other steps back on)
CFQ.parchmentOpts.tallyTasks = false
P.SelectArea(P.CURRENT_KEY, false)
SUBZONE = "Dolanaar"; Fire("ZONE_CHANGED"); frames(40)
local spiderRow = RowFor("Small Spider Leg")
check(spiderRow ~= nil, "Small Spider Leg row on the Near me page")

-- 4d) Looting: the spot is remembered and so is the mob it came from
UnitExists = function(u) return TARGET ~= nil end
UnitIsDead = function() return TARGET and TARGET.dead or false end
UnitIsPlayer = function() return false end
UnitCanAttack = function() return TARGET and TARGET.hostile ~= false end
UnitGUID = function() return TARGET and TARGET.guid end
UnitName = function() return TARGET and TARGET.name end
TARGET = { name = "Gnarlpine Ambusher", guid = "Creature-0-1-2-3-1994-0000ABCD", dead = true }
Fire("LOOT_OPENED")
check(CFQ.lastLootMob and CFQ.lastLootMob.key == "npc:1994", "loot window remembers the dead target's npc id")
QUESTS[2].objs[1].numFulfilled = 2; QUESTS[2].objs[1].text = "2/7 Small Spider Leg"
PX, PY = 0.30, 0.30          -- looted far from the quest's waypoint
Fire("QUEST_LOG_UPDATE")
local spots = CFQ.huntSpots["101_1"]
check(spots and #spots == 1 and spots[1].m == 57 and math.abs(spots[1].x - 0.30) < 1e-6 and spots[1].a == "Dolanaar",
    "item progress records a hunting spot where you looted it")
local d1994 = CFQ.learnedDroppers["npc:1994"]
check(d1994 and d1994["101_1"] == 1 and d1994.label == "Gnarlpine Ambusher", "item progress learns which mob dropped it")
check(not (CFQ.learnedDroppers["npc:1994"] or {})["102_1"], "kill objectives never learn droppers")
CFQ.lastLootMob = nil
QUESTS[2].objs[1].numFulfilled = 3; QUESTS[2].objs[1].text = "3/7 Small Spider Leg"
PX, PY = 0.305, 0.30
Fire("QUEST_LOG_UPDATE")
check(#CFQ.huntSpots["101_1"] == 1 and CFQ.huntSpots["101_1"][1].n == 2, "a loot right next to a known spot merges into it")
CFQ.OnLootOpened()
GetLootSourceInfo = function() return "GameObject-0-1-2-3-4-5" end
CFQ.OnLootOpened()
check(CFQ.lastLootMob == nil, "looting a herb / chest (game object) is not a mob")
GetLootSourceInfo = nil
TARGET = nil

-- 4e) Glow in the hunting grounds
SUBZONE = "Starbreeze"; PX, PY = 0.31, 0.30      -- back on the spot, other subzone: distance alone
Fire("ZONE_CHANGED"); P.SelectArea(P.CURRENT_KEY, false); frames(40)
spiderRow = RowFor("Small Spider Leg")
check(spiderRow and spiderRow.fxMode == "glow", "line glows in the item's hunting grounds (got " .. tostring(spiderRow and spiderRow.fxMode) .. ")")
frames(5)
check(spiderRow and spiderRow.fx.inner[1].__shown, "glow halo drawn")
PX, PY = 0.90, 0.90; SUBZONE = "Rut'theran"
Fire("ZONE_CHANGED"); frames(40)
spiderRow = RowFor("Small Spider Leg")
check(not spiderRow or spiderRow.fxMode == nil, "no glow away from its hunting grounds")
PX, PY = 0.55, 0.60; SUBZONE = "Dolanaar"; Fire("ZONE_CHANGED"); frames(40)
check(CFQ.IsInHuntGrounds({ progKey = "101_1", questID = 101 }, { mapID = 99, sub = "dolanaar", pois = {} }),
    "same subzone as a looted spot counts as its hunting grounds")
check(CFQ.IsInHuntGrounds({ progKey = "x", questID = 555 }, { mapID = 57, x = 0.5, y = 0.5, sub = "", pois = { [555] = { 0.53, 0.5 } } }),
    "inside the quest's objective area (map POI) counts")

-- 4f) Fire: targeting a mob that may drop it
check(P.NpcKey("Creature-0-3-0-0-1994-00001") == "npc:1994" and P.NpcKey("Player-1-0ABC") == nil, "npc id parsed from GUIDs")
check(P.NamesShareWord("Small Spider Leg", "Webwood Spider"), "'Spider Leg' / 'Webwood Spider' share a word")
check(not P.NamesShareWord("Small Spider Leg", "Gnarlpine Ambusher"), "unrelated mob shares no word")
check(not P.NamesShareWord("Small Gland", "Small Wolf"), "generic words ('small') don't count")
TARGET = { name = "Webwood Spider", guid = "Creature-0-1-2-3-1986-0001" }
Fire("PLAYER_TARGET_CHANGED"); frames(10)
spiderRow = RowFor("Small Spider Leg")
check(P.fire and P.fire.keys["101_1"] == "guess", "a spider is only a guess for Small Spider Leg (names alone)")
check(spiderRow and spiderRow.fxMode == "smoulder", "a guess only smoulders (got " .. tostring(spiderRow and spiderRow.fxMode) .. ")")
check(spiderRow and not spiderRow.fx.haze.__shown and spiderRow.fx.embers[1].__shown and not spiderRow.fx.embers[3].__shown,
    "smoulder: a couple of embers, no heat haze")
check(not P.fire.keys["104_1"], "Grell Earring not lit by a spider")

-- loot-window evidence: the corpse a quest item came from is a sure dropper
GetNumLootItems = function() return 2 end
GetLootSlotInfo = function(slot) if slot == 1 then return "tex", "Small Spider Leg", 1 end return "tex", "Silk Cloth", 1 end
GetLootSourceInfo = function() return "Creature-0-1-2-3-1986-0001", 1 end
TARGET.dead = true
Fire("LOOT_OPENED")
local d1986 = CFQ.learnedDroppers["npc:1986"]
check(d1986 and d1986["101_1"] == 1 and d1986.loots == 1 and d1986.label == "Webwood Spider", "loot window credits the corpse the item came from")
Fire("LOOT_OPENED")
check(d1986["101_1"] == 1 and d1986.loots == 1, "re-opening the same corpse isn't counted twice")
TARGET = { name = "Webwood Spider", guid = "Creature-0-1-2-3-1986-0009" }
Fire("PLAYER_TARGET_CHANGED"); frames(10)
spiderRow = RowFor("Small Spider Leg")
check(P.fire.keys["101_1"] == "sure" and spiderRow.fxMode == "fire", "after one loot, every Webwood Spider is a sure dropper: full flames")
check(spiderRow.fx.haze.__shown and spiderRow.fx.embers[1].__shown and spiderRow.fx.embers[6].__shown, "flames: heat haze and embers")
-- ruled out: a spider-named mob looted 4 times without ever having it
GetLootSlotInfo = function() return "tex", "Silk Cloth", 1 end
for i = 1, 4 do
    GetLootSourceInfo = function() return "Creature-0-1-2-3-2000-000" .. i, 1 end
    Fire("LOOT_OPENED")
end
TARGET = { name = "Giant Spider Matriarch", guid = "Creature-0-1-2-3-2000-0099" }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire == nil, "a mob looted 4 times without the item is ruled out despite its name")
GetNumLootItems, GetLootSlotInfo, GetLootSourceInfo = nil, nil, nil
-- the client says the mob isn't part of any of your quests
C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
TARGET = { name = "Lurking Spider", guid = "Creature-0-1-2-3-3000-0001" }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire == nil, "client says it's not a quest mob: no guess")
C_QuestLog.UnitIsRelatedToActiveQuest = nil
local dropLines = {}
CFQ.AddHuntTooltipLines({ AddLine = function(_, t) table.insert(dropLines, t) end }, { progKey = "101_1", questID = 101 })
check(table.concat(dropLines, "|"):find("Webwood Spider %(1 of 1%)"), "tooltip shows the loot record: " .. table.concat(dropLines, " / "))
TARGET = { name = "Gnarlpine Ambusher", guid = "Creature-0-1-2-3-1994-0002" }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire and P.fire.keys["101_1"], "a mob you've looted it from before is recognised by npc id")
TARGET = { name = "Moonkin", guid = "Creature-0-1-2-3-7000-0003" }
C_TooltipInfo = { GetUnit = function() return { lines = { { leftText = "Moonkin" }, { leftText = "Bashal'Aran" }, { leftText = " - 0/8 Grell Earring" } } } end }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire and P.fire.keys["104_1"] == "sure", "a unit tooltip listing the item is a sure dropper")
check(CFQ.tooltipShowsQuests, "learned that this client's unit tooltips list quests")
TARGET = { name = "Forest Spider", guid = "Creature-0-1-2-3-4000-0001" }
C_TooltipInfo = { GetUnit = function() return { lines = { { leftText = "Forest Spider" }, { leftText = "Level 5" } } } end }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire == nil, "tooltips list quests here, and this one lists none: no name guess")
CFQ.tooltipShowsQuests = nil
C_TooltipInfo = nil
TARGET = { name = "Webwood Spider", guid = "Creature-0-1-2-3-1986-0004", hostile = false }
Fire("PLAYER_TARGET_CHANGED")
check(P.fire == nil, "friendly NPCs never light the tally")
TARGET = nil
Fire("PLAYER_TARGET_CHANGED"); frames(5)
spiderRow = RowFor("Small Spider Leg")
check(P.fire == nil and spiderRow and spiderRow.fxMode ~= "fire", "fire goes out when you drop the target")
CFQ.parchmentOpts.inkEffects = false; Fire("ZONE_CHANGED")
spiderRow = RowFor("Small Spider Leg")
check(spiderRow and spiderRow.fxMode == nil, "ink effects can be switched off")
CFQ.parchmentOpts.inkEffects = true

-- 4g) Clicking an item tracks its quest, exactly like the quest's icon in the Objective Tracker
local stID = 0
C_SuperTrack.GetSuperTrackedQuestID = function() return stID end
C_SuperTrack.SetSuperTrackedQuestID = function(id) stID = id end
C_QuestLog.GetQuestsOnMap = function(m) if m == 57 then return { { questID = 101, x = 0.40, y = 0.40 } } end return {} end
local watchBefore = {}
for k in pairs(WATCHED) do watchBefore[k] = true end
spiderRow = RowFor("Small Spider Leg")
spiderRow:GetScript("OnClick")(spiderRow, "LeftButton")
check(stID == 101, "left-click super-tracks the item's quest")
local sameWatch = true
for k in pairs(WATCHED) do if not watchBefore[k] then sameWatch = false end end
check(sameWatch, "...without adding watches (same as the tracker's quest icon)")
spiderRow = RowFor("Small Spider Leg")
check(spiderRow and spiderRow.lasso and spiderRow.lasso[1].main.__shown, "the tracked quest's items are circled in red ink")
check(CFQ.huntOverlay == nil and CFQ.RefreshHuntMap == nil and CFQ.ToggleHuntFocus == nil,
    "no addon overlay on the world map: Blizzard shades the tracked quest's area itself")
spiderRow:GetScript("OnClick")(spiderRow, "LeftButton")
check(stID == 0, "clicking it again stops tracking (like the tracker icon)")
spiderRow = RowFor("Small Spider Leg")
check(spiderRow and not spiderRow.lasso[1].main.__shown, "red circle gone once untracked")
-- 4g2) Hovering an item shows a little map of where it's gathered
spiderRow = RowFor("Small Spider Leg")
spiderRow:GetScript("OnEnter")(spiderRow)
local pv = CFQ.mapPreview
check(pv and pv.__shown, "hovering an item pops up the map preview")
check(pv and pv.title.__text:find("Teldrassil") and pv.title.__text:find("Small Spider Leg"), "preview names the zone and the item")
local pvRings = 0
for _, c in ipairs(pv and pv.child.circles or {}) do if c.__shown then pvRings = pvRings + 1 end end
check(pvRings == 2, "preview rings the looted spot and the objective area (got " .. pvRings .. ")")
check(pv and pv.you.__shown, "preview marks where you are")
check(pv and pv.paper.__shown, "no map art from the client: plain parchment sketch underneath")
C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
C_Map.GetMapArtLayerTextures = function() local t = {}; for i = 1, 12 do t[i] = 10000 + i end; return t end
spiderRow:GetScript("OnEnter")(spiderRow)
local tilesShown = 0
for _, t in ipairs(pv.tiles) do if t.__shown then tilesShown = tilesShown + 1 end end
check(tilesShown == 12 and not pv.paper.__shown, "preview draws the zone's map tiles (" .. tilesShown .. ")")
check(pv.child.__w > P.PREVIEW_W, "preview is zoomed in on the item's area, not the whole zone")
spiderRow:GetScript("OnLeave")(spiderRow)
check(not pv.__shown, "preview hides with the tooltip")
CFQ.parchmentOpts.mapPreview = false
spiderRow:GetScript("OnEnter")(spiderRow)
check(not pv.__shown, "preview can be switched off")
CFQ.parchmentOpts.mapPreview = true
spiderRow:GetScript("OnLeave")(spiderRow)
C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = nil, nil
-- placement: tally on the left, tooltip goes to its right, preview lands clear of tally, tooltip and chat
f.__rect = { 40, 200, 230, 175 }                 -- left, bottom, width, height
GameTooltip.__rect = { 290, 300, 260, 80 }
ChatFrame1.__rect = { 40, 10, 430, 150 }
spiderRow:GetScript("OnEnter")(spiderRow)
local tpt, trel, trp = GameTooltip:GetPoint(1)
check(tpt == "TOPLEFT" and trel == spiderRow and trp == "TOPRIGHT", "tooltip opens beside the tally, on the side with room")
local _, prel, _, ppx, ppy = pv:GetPoint(1)
local PR = { l = ppx, b = ppy, r = ppx + pv:GetWidth(), t = ppy + pv:GetHeight() }
check(prel == UIParent and P.Overlap(PR, P.TallyRect()) == 0, "preview doesn't cover the tally")
check(P.Overlap(PR, P.ScreenRect(GameTooltip, 0)) == 0, "preview doesn't cover the tooltip")
check(P.Overlap(PR, P.ScreenRect(ChatFrame1, 0)) == 0, "preview stays off the chat window")
check(PR.l >= 0 and PR.b >= 0 and PR.r <= UIParent:GetWidth() and PR.t <= UIParent:GetHeight(), "preview fully on screen")
f.__rect = { 1650, 200, 230, 175 }               -- tally against the right edge: tooltip flips left
GameTooltip.__rect = { 1380, 300, 260, 80 }
spiderRow:GetScript("OnEnter")(spiderRow)
tpt = GameTooltip:GetPoint(1)
check(tpt == "TOPRIGHT", "tally at the right edge: tooltip opens on its left")
_, prel, _, ppx, ppy = pv:GetPoint(1)
PR = { l = ppx, b = ppy, r = ppx + pv:GetWidth(), t = ppy + pv:GetHeight() }
check(PR.r <= UIParent:GetWidth() and P.Overlap(PR, P.TallyRect()) == 0, "right edge: preview on screen and off the tally")
spiderRow:GetScript("OnLeave")(spiderRow)
f.__rect, GameTooltip.__rect, ChatFrame1.__rect = nil, nil, nil

-- minimap: amber pips where you've looted the tracked quest's items
Minimap = CreateFrame("Frame", "Minimap"); Minimap.__w, Minimap.__h = 140, 140
GetCVar = function() return "0" end
stID = 101
CFQ.UpdateMinimapPins()
check(P.mmPins and P.mmPins[1].__shown and P.mmPins[1].__alpha < 1, "a far-off spot sits on the minimap rim")
PX, PY = 0.3030, 0.3010
CFQ.UpdateMinimapPins()
local _, _, _, mx, my = P.mmPins[1]:GetPoint(1)
check(P.mmPins[1].__alpha == 1 and math.sqrt(mx * mx + my * my) < 64, "a nearby spot is drawn inside the minimap")
CFQ.parchmentOpts.minimapPins = false; CFQ.UpdateMinimapPins()
check(not P.mmPins[1].__shown, "minimap pins can be switched off")
CFQ.parchmentOpts.minimapPins = true
stID = 0; CFQ.UpdateMinimapPins()
check(not P.mmPins[1].__shown, "no pins when no quest is tracked")
PX, PY = 0.55, 0.60

-- 4h) Hunting data pruned for quests that left the log
CFQ.huntSpots["999_1"] = { { m = 57, x = 0.1, y = 0.1 } }
CFQ.learnedDroppers["wolf"] = { ["999_1"] = 2, label = "Wolf" }
CFQ.PruneHuntData()
check(CFQ.huntSpots["999_1"] == nil and CFQ.huntSpots["101_1"] ~= nil, "spots of abandoned quests pruned, live ones kept")
check(CFQ.learnedDroppers["wolf"] == nil and CFQ.learnedDroppers["npc:1994"] ~= nil, "droppers pruned the same way")

-- 4i) Looks: handkerchief (default), parchment, transparent window
check(CFQ.parchmentStyle == "RAG" and P.GetStyle().label == "Torn rag", "torn rag is the default look")
check(f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\torn_rag", "the default tally draws the torn rag texture")

-- the page-turn corner on a texture look: the fold shows the material itself, mirrored
local corner = f.corner
corner.drawnKey = nil; P.DrawCorner(corner)
local flap1, under1 = corner.flap[1], corner.under[1]
check(flap1.__tex == "Interface\\AddOns\\Handkerquest\\textures\\torn_rag" and under1.__tex == flap1.__tex,
    "folded corner: flap and the page beneath show the cloth itself")
check(flap1.__tc and #flap1.__tc == 8, "folded corner: the flap samples the corner through a mirrored mapping")
-- mirrored: along the flap's top row the texture runs vertically (x fixed, y changes)
check(flap1.__tc[1] == flap1.__tc[5] and flap1.__tc[2] ~= flap1.__tc[6], "folded corner: flap is the corner reflected across the fold")
-- the fold square reaches the image's own corner, so the flap is the material's real (torn, curved)
-- edge mirrored: more rows than the button is tall, the last row ending at the image's corner
local cpw, cph = corner:GetParent():GetWidth(), corner:GetParent():GetHeight()
local NF = P.CORNER_REST + (-corner.offX) + corner.offY
local tcOk = true
for _, v in ipairs(flap1.__tc) do if v < 1 - NF / math.min(cpw, cph) - 0.01 or v > 1.0001 then tcOk = false end end
check(tcOk, "folded corner: samples come from the sheet's bottom-right corner")
check(NF > P.CORNER_REST and corner.under[NF] and corner.under[NF].__shown and not (corner.under[NF + 1] and corner.under[NF + 1].__shown),
    "folded corner: the fold covers the whole corner of the image (" .. NF .. " rows)")
check(corner.under[NF].__tc[2] > 0.999 and corner.crease and corner.crease[1].__shown and corner.crease[1].__tex == flap1.__tex,
    "folded corner: rows reach the image's corner; the crease is drawn from the material itself")
check(not corner.foldEdge.__shown and not corner.foldShadow.__shown, "folded corner: no straight drawn lines that would overhang a curved edge")
check(not corner.flapTop.__shown and not corner.flapLeft.__shown, "folded corner: no drawn straight edges on a texture look")
corner.size = P.CORNER_HOVER; P.DrawCorner(corner)
check(corner.flap[20].__shown and corner.flap[20].__tex, "folded corner: still the material when lifted on hover")
corner.size = P.CORNER_REST; P.DrawCorner(corner)

CFQ.parchmentStyle = "HANDKERCHIEF"; P.ApplyStyle(); Fire("ZONE_CHANGED")
check(corner.flap[1].__tex == nil and corner.flapTop.__shown, "drawn looks: the corner goes back to inked strips and edges")
check(f.topSheet.hem[1].__shown and #f.topSheet.stitches > 10, "handkerchief has a hem band and running stitch")
local function CountShown(list) local n = 0; for _, t in ipairs(list or {}) do if t.__shown then n = n + 1 end end; return n end
local cp = f.topSheet.clothParts
check(cp and CountShown(cp.corner) == 4 and CountShown(cp.body2) == 1, "handkerchief: rounded corners (a disc in each corner)")
check(cp and CountShown(cp.lace) > 60 and CountShown(cp.thread) == CountShown(cp.lace) and CountShown(cp.eye) == CountShown(cp.lace),
    "handkerchief: scalloped lace all round, each scallop outlined with an eyelet (" .. (cp and CountShown(cp.lace) or 0) .. ")")
local segShown = 0
for _, t in ipairs(f.topSheet.segs[2]) do if t.__shown then segShown = segShown + 1 end end
check(segShown == 0, "handkerchief: no torn-paper edge strips")
local keepBack = f.visibleBackSheets; f.visibleBackSheets = 1; P.ApplyStackLayout(f)
check(f.backSheets[1].clothParts and CountShown(f.backSheets[1].clothParts.lace) > 60 and CountShown(f.backSheets[1].clothParts.eye) == 0,
    "hankies underneath are cloth too (lace, no eyelets)")
f.visibleBackSheets = keepBack; P.ApplyStackLayout(f)
check(f.shadowSheet.clothParts and CountShown(f.shadowSheet.clothParts.lace) == 0 and CountShown(f.shadowSheet.clothParts.corner) == 4,
    "shadow is a soft rounded shape without lace")
check(f.topSheet.hem2[1].__shown and f.topSheet.drape[1].__shown and f.topSheet.folds[1].__shown, "woven border stripe, drape wrinkles and soft creases")
check(f.visibleBackSheets == math.min(#P.areas - 1, 3), "handkerchief keeps a pile for other pages")
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "PARCHMENT" and not f.topSheet.hem[1].__shown and f.topSheet.grain.__shown,
    "parchment look: grain, no hem")
check(P.INK[1] == 0.17, "parchment ink restored")
check(not f.topSheet.shadeTop.__shown and f.topSheet.shadeL.__shown, "parchment: no shaded header band (side shading kept)")
check(CountShown(f.topSheet.clothParts.lace) == 0 and CountShown(f.topSheet.clothParts.corner) == 0, "parchment: lace and rounded corners gone")
local segBack = 0
for _, t in ipairs(f.topSheet.segs[2]) do if t.__shown then segBack = segBack + 1 end end
check(segBack > 20, "parchment: torn edges back")
NOW = NOW + 200   -- "worked on recently" wears off: other quests go back to their area pages

-- texture looks: crumpled paper and torn rag
local function anyShown(list) for _, t in ipairs(list or {}) do if t.__shown then return true end end return false end
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "CRUMPLED" and P.GetStyle().label == "Crumpled paper", "parchment -> crumpled paper")
check(f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\crumpled_paper", "crumpled paper draws its texture image")
check(not anyShown(f.topSheet.segs[2]) and not anyShown(f.topSheet.clothParts and f.topSheet.clothParts.lace)
    and not f.topSheet.hem[1].__shown and not f.topSheet.grain.__shown, "texture look: no drawn edges, lace, hem or grain")
check(f.shadowSheet.body.__tex and f.shadowSheet.body.__vc[1] == 0 and math.abs(f.shadowSheet.body.__vc[4] - 0.35) < 1e-6,
    "the shadow is the paper's own shape in black")
check(f.backSheets[1].body.__tex and f.backSheets[1].body.__tc[1] == 1 and f.backSheets[2].body.__tc[3] == 1,
    "pages underneath are the same sheet turned different ways")
check(f.pad == 8 and P.INK[1] == 0.20, "crumpled paper: pencil ink, writing inset from the edges")
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "RAG" and f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\torn_rag",
    "crumpled paper -> torn rag, with its texture")
check(f.padL == math.floor(f:GetWidth() * 0.102 + 0.5) and f.padB == math.floor(f:GetHeight() * 0.075 + 0.5)
    and f.visibleBackSheets == math.min(#P.areas - 1, 3), "torn rag: writing clear of the torn edges, rags piled underneath")
local _, _, _, cx, cy = f.corner:GetPoint(1)
local fw, fh = f:GetWidth(), f:GetHeight()
check(cx == -math.floor(fw * 0.068 + 0.5) and cy == math.floor(fh * 0.046 + 0.5),
    "the page-turn corner sits on the cloth's own corner (" .. tostring(cx) .. "," .. tostring(cy) .. ")")
f:SetSize(400, 300); P.UpdateCorner(f)
f:GetScript("OnSizeChanged")(f)
check(f.padL == 41 and f.padT == 31 and f.padB == 23, "a stretched rag keeps the writing on the cloth: margins grow with the window ("
    .. tostring(f.padL) .. "," .. tostring(f.padT) .. "," .. tostring(f.padB) .. ")")
local _, _, _, tx, ty = f.titleFS:GetPoint(1)
check(tx == 10 + 41 and ty == -6 - 31, "title follows the stretched margin")
local _, _, _, gx, gy = f.resizeGrip:GetPoint(1)
check(gx == 42 and gy == 24, "resize grip sits on the cloth's bottom-left, not on the background")
_, _, _, cx, cy = f.corner:GetPoint(1)
check(cx == -27 and cy == 14, "resizing the tally keeps the corner on the cloth's corner (" .. tostring(cx) .. "," .. tostring(cy) .. ")")
f:SetSize(fw, fh); P.UpdateCorner(f)
-- rigid looks: chalked stone and carved bark
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "STONE" and f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\stone",
    "torn rag -> chalked stone, with its texture")
check(f.padL == math.floor(f:GetWidth() * 0.185 + 0.5) and f.padT == math.floor(f:GetHeight() * 0.155 + 0.5) and P.INK[1] > 0.9,
    "chalked stone: pale chalk, writing kept on the flat face")
check(f.titleFS.__shadow and f.titleFS.__shadow[1] > 0.9 and f.titleFS.__shadow[4] < 0.5 and f.titleFS.__shadowOff[1] == 1,
    "chalk: a faint pale dust smear beside the letters, not a drop shadow")
check(P.BLEED and P.BLEED[1] > 0.9, "chalked ticks and strikes leave chalk dust")
check(f.inkGrain and f.inkGrain.__shown and f.inkGrain.tex.__tex == "Interface\\AddOns\\Handkerquest\\textures\\chalk_grain"
    and math.abs(f.inkGrain.tex.__tc[2] - f:GetWidth() / 128) < 1e-6, "rough chalk: grain tiled over the writing, one texel per pixel")
P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
check(not anyShown(f.corner.under) and not anyShown(f.corner.flap) and f.corner.foldEdge.__shown
    and f.corner.flapTop.__shown and f.corner.flapLeft.__shown and f.corner.foldEdge.__color[1] > 0.9,
    "stone can't fold: the page corner is a chalked dog-ear mark")
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "BARK" and f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\bark",
    "chalked stone -> carved bark, with its texture")
check(f.titleFS.__shadow and f.titleFS.__shadow[1] < 0.1 and f.titleFS.__shadow[4] > 0.9
    and f.titleFS.__shadowOff[1] == -1 and f.titleFS.__shadowOff[2] == 1,
    "carved letters: pale wood with a dark shadow inside the top-left of each cut")
check(not anyShown(f.corner.flap) and f.corner.foldShadow.__shown, "bark: a carved dog-ear mark with its shadow")
check(f.titleFS.inkKey:find("^SCRAWL:"), "bark: straight-cut letters (rough scrawl face)")
check(not (f.inkGrain and f.inkGrain.__shown), "bark: no chalk grain")
SlashCmdList["HANDKERQUEST"]("look stone")
check(CFQ.parchmentStyle == "STONE", "/hanky look stone")
SlashCmdList["HANDKERQUEST"]("look bark")
check(CFQ.parchmentStyle == "BARK", "/hanky look bark")
SlashCmdList["HANDKERQUEST"]("look rag")
P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
check(anyShown(f.corner.flap) and f.titleFS.__shadow[4] == 0, "back to the rag: a real fold again, no text shadow")
QRF_SavedState.parchmentStyle = "BARK"
Fire("ADDON_LOADED", "Handkerquest")
check(CFQ.parchmentStyle == "BARK", "saved bark look loads")
CFQ.parchmentStyle = "RAG"; P.ApplyStyle()
for _, tx in ipairs({ { "crumpled_paper", 512 }, { "torn_rag", 512 }, { "stone", 512 }, { "bark", 512 }, { "pipeweed_leaf", 512 },
                       { "etched_leather", 512 }, { "arcane_ring", 512 }, { "arcane_haze", 256 }, { "ink_blots", 256 } }) do
    local name, size = tx[1], tx[2]
    local fh = io.open(here .. "/textures/" .. name .. ".tga", "rb")
    local hdr = fh and fh:read(18)
    if fh then fh:close() end
    check(hdr and hdr:byte(3) == 2 and hdr:byte(13) + 256 * hdr:byte(14) == size and hdr:byte(15) + 256 * hdr:byte(16) == size
        and hdr:byte(17) == 32, name .. ".tga ships as a " .. size .. "x" .. size .. " 32-bit uncompressed TGA")
end
SlashCmdList["HANDKERQUEST"]("look rag")
check(CFQ.parchmentStyle == "RAG", "/hanky look rag")
SlashCmdList["HANDKERQUEST"]("look crumpled")
check(CFQ.parchmentStyle == "CRUMPLED", "/hanky look crumpled")
SlashCmdList["HANDKERQUEST"]("look handkerchief")
check(f.topSheet.body.__tex == nil and f.topSheet.body.__vc[1] == 1 and f.topSheet.body.__tc[1] == 0 and anyShown(f.topSheet.clothParts.lace),
    "back to the handkerchief: drawn cloth again, no leftover tint or flip")
CFQ.parchmentStyle = "BARK"; P.ApplyStyle()
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "LEAF" and f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\pipeweed_leaf",
    "carved bark -> pipe-weed leaf, with its texture")
P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
check(anyShown(f.corner.flap) and f.titleFS.__shadow[4] == 0 and not (f.inkGrain and f.inkGrain.__shown) and P.INK[1] < 0.1
    and P.GetStyle().title[1] < 0.1, "leaf: near-black ink that stands out on the brown leaf, and the corner is a real fold of the leaf")
check(f.corner.under[P.CORNER_REST] and f.corner.under[P.CORNER_REST].__shown
    and not (f.corner.under[P.CORNER_REST + 1] and f.corner.under[P.CORNER_REST + 1].__shown),
    "leaf: the dog-ear stays on the leaf's corner (its long edge runs along the fold)")
check(f.padR == math.floor(f:GetWidth() * 0.273 + 0.5), "leaf: writing kept clear of the tapering tip")
SlashCmdList["HANDKERQUEST"]("look pipeweed")
check(CFQ.parchmentStyle == "LEAF", "/hanky look pipeweed")
do  -- the leaves underneath fan out from the stem instead of lying flipped
    f.visibleBackSheets = 2; f.shuffle = nil
    P.ApplyStackLayout(f)
    local b1, b2 = f.backSheets[1], f.backSheets[2]
    local a1 = math.floor(0.17 * 2000 + 0.5) / 2000
    local w = f:GetWidth()
    check(math.abs(b1.sinA - math.sin(a1)) < 1e-6 and b2.sinA > b1.sinA, "leaf pile: back leaves fan wider one after another")
    check(math.abs(b1.__py - 0.47 * w * math.sin(a1)) < 0.3 and b1.__px < 0,
        "leaf pile: each leaf turns about the shared stem (shifted up, not about its middle)")
    check(b1.body.__tc[1] == 0 and b1.body.__tc[2] == 1 and b1.body.__tc[3] == 1
        and b2.body.__tc[1] == 0 and b2.body.__tc[3] == 0, "leaf pile: stems stay on the left (no left-right mirror)")
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); P.ApplyStackLayout(f)
    check(b1.body.__tc[1] == 1 and math.abs(b1.sinA - math.sin(0.026)) < 1e-6 and b1.__px == 2,
        "rag pile still alternates (flipped pages, small tilts)")
    CFQ.parchmentStyle = "LEAF"; P.ApplyStyle()
end
-- etched leather (soft tan hide): dark pressed letters with a pale lip below-right; leather bends, so a real fold
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "LEATHER" and f.topSheet.body.__tex == "Interface\\AddOns\\Handkerquest\\textures\\etched_leather",
    "pipe-weed leaf -> etched leather, with its texture")
P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
check(anyShown(f.corner.flap) and f.titleFS.__shadow[1] > 0.8 and f.titleFS.__shadowOff[1] == 1 and f.titleFS.__shadowOff[2] == -1
    and P.INK[1] < 0.3, "leather: dark letters with a pale pressed lip (shadow down-right), real fold")
check(f.padL == math.floor(f:GetWidth() * 0.078 + 0.5) and f.padB == math.floor(f:GetHeight() * 0.148 + 0.5),
    "leather: writing kept on the hide (margins follow the window)")
check(not (f.titleFS.halo and f.titleFS.halo[1].__shown), "leather: no wet-ink halo (pressed, not inked)")
SlashCmdList["HANDKERQUEST"]("look tooled")
check(CFQ.parchmentStyle == "LEATHER", "/hanky look tooled")
CFQ.parchmentStyle = "RAG"; SlashCmdList["HANDKERQUEST"]("look hide")
check(CFQ.parchmentStyle == "LEATHER", "/hanky look hide")

-- arcane script: words of light in the air, a turning rune circle, drifting motes, no pile
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "ARCANE" and f.arcaneOn and f.arcane.ring.__shown
    and f.arcane.ring.__tex == "Interface\\AddOns\\Handkerquest\\textures\\arcane_ring", "etched leather -> arcane script: the rune circle is up")
check(f.visibleBackSheets == 0 and not f.shadowSheet.__shown, "arcane script: no pile of pages, no shadow")
local th = f.titleFS.halo
check(th and th[1].__shown and th[1].__vc == nil and th[1].haloCol[3] == 1.0 and th[1].haloCol[1] < 0.7,
    "arcane script: a violet glow round the heading")
frames(30)
local motesUp = 0
for _, m in ipairs(f.arcane.motes) do if m.__shown then motesUp = motesUp + 1 end end
check(motesUp >= 8, "arcane script: motes of light drifting up (" .. motesUp .. ")")
P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
check(not anyShown(f.corner.flap) and f.corner.foldEdge.__shown, "arcane script: a glowing corner mark, nothing to fold")
SlashCmdList["HANDKERQUEST"]("look mage")
check(CFQ.parchmentStyle == "ARCANE", "/hanky look mage")
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(not f.arcaneOn and not f.arcane.ring.__shown and not (th and th[1].__shown), "leaving arcane script puts the circle and glow away")
check(#P.areas > 1 and CFQ.parchmentStyle == "NATIVE" and f.visibleBackSheets == 0 and not f.shadowSheet.__shown, "transparent window: no pile, no shadow, even with several pages")
check(f.titleFS.inkKey:find("^PLAIN:"), "transparent window uses the plain UI font")
check(f.footerFS.__text:find("page %d+ of"), "page number still in the footer: " .. tostring(f.footerFS.__text) .. " sel=" .. tostring(P.selectedKey) .. " n=" .. #P.areas)
frames(40)
SlashCmdList["HANDKERQUEST"]("look handkerchief")
check(CFQ.parchmentStyle == "HANDKERCHIEF" and f.styleKey == "HANDKERCHIEF", "/hanky look handkerchief")
check(QRF_SavedState.parchmentStyle == "HANDKERCHIEF", "look is saved")
QRF_SavedState.parchmentStyle = "PARCHMENT"
Fire("ADDON_LOADED", "Handkerquest")
check(CFQ.parchmentStyle == "PARCHMENT", "saved look loads")
QRF_SavedState.parchmentStyle = "BOGUS"
Fire("ADDON_LOADED", "Handkerquest")
check(CFQ.parchmentStyle == "PARCHMENT", "an unknown saved look is ignored on load")
check(type(QRF_SavedState.huntSpots) == "table" and QRF_SavedState.huntSpots["101_1"], "hunting spots are saved")
SlashCmdList["HANDKERQUEST"]("look handkerchief")
local printedItems = 0
local realPrint2 = print
print = function() printedItems = printedItems + 1 end
local okItems, errItems = pcall(SlashCmdList["HANDKERQUEST"], "items")
print = realPrint2
check(okItems and printedItems >= 5, "/hanky items lists objectives: " .. tostring(errItems))
UnitName = function() return "Gnarlpine Ambusher" end
UnitExists, UnitIsDead, UnitIsPlayer, UnitCanAttack, UnitGUID = nil, nil, nil, nil, nil

-- 5) Sorting
SlashCmdList["HANDKERQUEST"]("dist")
local st = __STATE()
check(st.dist == "ASC" and st.primary == "DIST", "dist cycles to ASC and becomes primary")
SlashCmdList["HANDKERQUEST"]("lvl")
st = __STATE()
check(st.lvl == "ASC" and st.primary == "LVL", "lvl cycles to ASC and becomes primary")
check(CFQ.GetSortSummary():find("^lvl"), "summary leads with primary sort")
SlashCmdList["HANDKERQUEST"]("lvl"); SlashCmdList["HANDKERQUEST"]("lvl")
st = __STATE()
check(st.lvl == "NONE" and st.primary == "DIST", "lvl cycles ASC->DESC->off and primary falls back to dist")
local menu = QRF_SharedDropdownMenu
check(menu and menu.sortLvlBtn and menu.sortDistBtn, "menu has lvl & dist cycle buttons")
check(menu.menuResetBtn ~= nil, "menu has Reset button")
check(menu.sortDistBtn.glow.__shown and not menu.sortLvlBtn.glow.__shown, "dist highlighted, lvl not")
menu.menuResetBtn:GetScript("OnClick")(menu.menuResetBtn)
st = __STATE()
check(st.lvl == "NONE" and st.dist == "NONE", "Reset clears both sorts")

-- 6) Stacking is visual only: toggling it never adds, removes or hides tracked quests
local bar = QRF_TrackerSubHeaderBar
check(bar ~= nil, "tracker control bar exists")
local function IncompDeck()
    for _, fr in ipairs(allFrames) do
        if fr.clusterData and fr.__shown and not fr.clusterData.isComplete then return fr end
    end
end
local function WatchedSnapshot() local t = {}; for k in pairs(WATCHED) do t[#t + 1] = k end; table.sort(t); return table.concat(t, ",") end

-- only 101 tracked: its untracked neighbour 102 must NOT be pulled into a deck
WATCHED = { [101] = true }
__LAYOUT()
bar.incompToggle:GetScript("OnClick")(bar.incompToggle)   -- incomplete stacking ON
st = __STATE()
check(st.incomp, "incomplete stacking on")
__LAYOUT()
check(IncompDeck() == nil, "no deck from a single tracked quest (untracked 102 not pulled in)")
check(blocks[101].__alpha ~= 0, "101 stays visible as a normal block")
check(not WATCHED[102], "stacking never adds watches")

-- 101 + 102 tracked: they stack, and switching off shows both again with the watch list untouched
WATCHED = { [101] = true, [102] = true }
__LAYOUT()
local deck = IncompDeck()
check(deck ~= nil and #deck.clusterData.quests == 2, "incomplete deck of 101+102 shown")
check(blocks[101].__alpha == 0 and blocks[102].__alpha == 0, "native blocks hidden behind the deck")
local before = WatchedSnapshot()
bar.incompToggle:GetScript("OnClick")(bar.incompToggle)   -- OFF
for _, t in ipairs(TIMERS or {}) do t() end; TIMERS = {}
__LAYOUT()
check(WatchedSnapshot() == before, "turning the stack off leaves the watch list unchanged")
check(IncompDeck() == nil, "deck gone when stacking off")
check(blocks[101].__alpha == 1 and blocks[102].__alpha == 1, "101 and 102 both visible again")
bar.incompToggle:GetScript("OnClick")(bar.incompToggle)   -- ON again
__LAYOUT()
check(WatchedSnapshot() == before, "turning the stack back on leaves the watch list unchanged")
bar.incompToggle:GetScript("OnClick")(bar.incompToggle)   -- leave it OFF for later tests

-- toggling asks Blizzard's tracker for a full rebuild (that's what re-shows its blocks in game)
local nativeUpdates = 0
QuestObjectiveTracker.MarkDirty = function() nativeUpdates = nativeUpdates + 1 end
bar.turnInToggle:GetScript("OnClick")(bar.turnInToggle)
bar.turnInToggle:GetScript("OnClick")(bar.turnInToggle)
check(nativeUpdates == 2, "each stack toggle requests a native tracker rebuild (got " .. nativeUpdates .. ")")

-- /hanky debug dump runs cleanly
local printed = 0
local realPrint = print
print = function(...) printed = printed + 1 end
local okDbg, errDbg = pcall(SlashCmdList["HANDKERQUEST"], "debug")
print = realPrint
check(okDbg, "/hanky debug runs without error: " .. tostring(errDbg))
check(printed >= 3, "/hanky debug prints the tracker state")

-- 7) Options panel
SlashCmdList["HANDKERQUEST"]("options")
check(OPENED_SETTINGS == 99, "options open in Settings > AddOns")
check(QRF_OptionsPanel:IsShown(), "options panel shown")
check(QRF_TrackerOptionsButton ~= nil and QRF_TrackerOptionsButton:IsShown(), "tracker gear exists")
check(f.optBtn ~= nil, "parchment gear exists")

-- handwriting button in the panel cycles the face
local fontBtn
for _, w in ipairs(CFQ.optionWidgets) do
    if type(w.__text) == "string" and w.__text:find("^Handwriting: ") then fontBtn = w end
end
check(fontBtn ~= nil and fontBtn.__text == "Handwriting: Quill script", "handwriting button shows Quill script by default")
if fontBtn then
    fontBtn:GetScript("OnClick")(fontBtn)
    check(fontBtn.__text == "Handwriting: Rough scrawl", "handwriting button cycles to Rough scrawl")
    fontBtn:GetScript("OnClick")(fontBtn); fontBtn:GetScript("OnClick")(fontBtn)
end
-- look button in the panel cycles handkerchief -> parchment -> window -> handkerchief
local lookBtn
for _, w in ipairs(CFQ.optionWidgets) do
    if type(w.__text) == "string" and w.__text:find("^Look: ") then lookBtn = w end
end
check(lookBtn ~= nil and lookBtn.__text == "Look: Handkerchief notes", "options show Look: Handkerchief notes")
if lookBtn then
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Parchment" and f.styleKey == "PARCHMENT", "look button switches to parchment")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Crumpled paper", "look button: crumpled paper")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Torn rag", "look button: torn rag")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Chalked slate", "look button: chalked stone")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Carved bark" and fontBtn.__alpha < 1 and fontBtn.__text:find("set by the look"),
        "look button: carved bark brings its own knife-cut lettering")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Pipe-weed leaf" and fontBtn.__alpha == 1, "look button: pipe-weed leaf (handwriting selectable again)")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Etched leather", "look button: etched leather")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Arcane script" and fontBtn.__alpha == 1, "look button: arcane script")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(lookBtn.__text == "Look: Transparent window" and fontBtn.__alpha < 1, "window look greys out the handwriting button")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(CFQ.parchmentStyle == "HANDKERCHIEF", "look button wraps back to the handkerchief")
end
local hasMapOpt, hasFxOpt = false, false
for _, w in ipairs(CFQ.optionWidgets) do
    if w.label and w.label.__text == "Mark the tracked quest's item spots on the minimap" then hasMapOpt = true end
    if w.label and w.label.__text == "Glowing & burning ink" then hasFxOpt = true end
end
check(hasMapOpt and hasFxOpt, "options for the minimap pins and the ink effects")

-- other-area pages off through the panel: single page, no dog-ear, no pile
for _, w in ipairs(CFQ.optionWidgets) do
    if w.label and w.label.__text == "Pages for other areas" then
        w.__checked = false
        w:GetScript("OnClick")(w)
    end
end
check(#P.areas == 1, "only the current-area page when other pages are off")
check(not f.corner:IsShown(), "dog-ear hidden with a single page")
check(f.visibleBackSheets == 0, "no pile under a single page")
for _, w in ipairs(CFQ.optionWidgets) do
    if w.label and w.label.__text == "Show the parchment tally list" then
        w.__checked = false
        w:GetScript("OnClick")(w)
    end
end
check(not f:IsShown(), "parchment hides via options checkbox")

-- area-page grouping button in the options panel
local gBtn
for _, w in ipairs(CFQ.optionWidgets) do if type(w.__text) == "string" and w.__text:find("^Other pages by: ") then gBtn = w end end
check(gBtn ~= nil and gBtn.__text == "Other pages by: Map areas", "options show Other pages by: Map areas")
if gBtn then
    gBtn:GetScript("OnClick")(gBtn)
    check(gBtn.__text == "Other pages by: Zones", "grouping button cycles to Zones")
    gBtn:GetScript("OnClick")(gBtn)
    check(gBtn.__text == "Other pages by: Clusters", "grouping button: Clusters (not \"Distance\")")
    gBtn:GetScript("OnClick")(gBtn)
end

-- page radius slider in the options panel
local prr = CFQ.pageRadiusRow
check(prr ~= nil, "options panel has the page radius slider")
check(CFQ.nearRadiusRow ~= nil, "options panel has the Near me distance slider")
if CFQ.nearRadiusRow then
    CFQ.nearRadiusRow.slider:GetScript("OnValueChanged")(CFQ.nearRadiusRow.slider, 14)
    check(CFQ.nearRadiusPercent == 14 and P.GetNearRadius() == 14, "Near me slider sets the proximity radius")
end
if prr then
    CFQ.parchmentOpts.pagesFollowTracker = false
    prr.slider:GetScript("OnValueChanged")(prr.slider, 9)
    check(CFQ.pageRadiusPercent == 9 and P.GetPageRadius() == 9, "panel slider sets its own page radius")
    CFQ.parchmentOpts.pagesFollowTracker = true
    prr.slider:GetScript("OnValueChanged")(prr.slider, 12)
    check(P.GetPageRadius() == 12 and __STATE().incomp == false, "linked panel slider moves the (•••) radius without switching stacking on")
end

-- Tally check-offs: tasks (kills / other steps) of multi-step quests, and the items / tasks / tasks-apart
-- toggles beside the gear
do
    CFQ.parchmentOpts.tallyTasks = true
    for _, w in ipairs(CFQ.optionWidgets) do     -- the tally was put away by the options tests above
        if w.label and w.label.__text == "Show the parchment tally list" then w.__checked = true; w:GetScript("OnClick")(w) end
    end
    P.SelectArea(P.CURRENT_KEY, false)
    local q102 = __QMAP()[102]
    check(q102 and #q102.taskObjectives == 2 and q102.taskObjectives[1].kind == "slay" and q102.taskObjectives[2].kind == "task"
        and q102.taskObjectives[2].single, "multi-step quest: a slay line and a one-off step")
    check(CFQ.ObjectiveKind(nil, "Gnarlpine Ambusher slain") == "slay" and CFQ.ObjectiveKind(nil, "Speak with Denalan") == "task"
        and CFQ.ObjectiveKind("monster", "x") == "slay" and CFQ.ObjectiveKind("event", "Kill zone") == "task", "objective kinds")
    local real = C_QuestLog.GetQuestObjectives
    local function With(objs) C_QuestLog.GetQuestObjectives = function() return objs end end
    With({ { text = "0/1 Mor'Ladim slain", type = "monster", numFulfilled = 0, numRequired = 1 } })
    local qty = { { index = 1, isItem = false, objType = "monster", itemName = "Mor'Ladim slain", numRequired = 1, numFulfilled = 0 } }
    check(#CFQ.ExtractTaskObjectives(900, 0, false, qty) == 0, "one enemy to slay (and nothing else): stays off the tally")
    qty[1].numRequired = 8
    check(#CFQ.ExtractTaskObjectives(900, 0, false, qty) == 1, "eight to slay: on the tally")
    With({ { text = "Speak with Denalan", type = "event" } })
    check(#CFQ.ExtractTaskObjectives(901, 0, false, {}) == 0, "a quest that's just one step stays off the tally")
    With({ { text = "Speak with Denalan", type = "event", finished = true }, { text = "Light the beacon", type = "object" } })
    local two = CFQ.ExtractTaskObjectives(901, 0, false, {})
    check(#two == 2 and two[1].finished and not two[2].finished and two[1].numRequired == 1, "two one-off steps: two boxes, the done one ticked")
    With({ { text = "0/1 Darnassus Bank", type = "event" }, { text = "0/1 City Gate", type = "event" }, { text = "0/6 Wolf slain", type = "monster" } })
    local three = CFQ.ExtractTaskObjectives(902, 0, false, {
        { index = 1, isItem = false, objType = "event", itemName = "Darnassus Bank", numRequired = 1, numFulfilled = 0 },
        { index = 3, isItem = false, objType = "monster", itemName = "Wolf slain", numRequired = 6, numFulfilled = 0 } })
    check(#three == 3 and three[1].single and three[2].single and not three[3].single,
        "counted steps of one ('0/1 Darnassus Bank') are a plain box, no '0/1'; 'slay 6' keeps its count")
    C_QuestLog.GetQuestObjectives = real

    Fire("ZONE_CHANGED")
    local ib, tb, sb = f.itemsBtn, f.tasksBtn, f.sepBtn
    check(ib and tb and sb and f.titleFS.__points[2][2] == ib and sb.__points[1][2] == f.optBtn,
        "items, tasks and tasks-apart toggles sit left of the gear; the heading stops at them")
    check(ib.on and tb.on and not sb.on and ib.strokes[1].main.__color[4] == 1 and sb.strokes[1].main.__color[4] < 0.5,
        "on = full ink, off = faded (tasks apart starts off)")
    check(ib.__w == P.QUICK_SIZE and P.QUICK_SIZE >= 16 and ib.__points[1][4] == -P.QUICK_GAP and tb.__points[1][4] == -P.QUICK_GAP
        and sb.__points[1][4] == -P.QUICK_GEAR_GAP and P.QUICK_GAP >= 5, "toggles are 16px with room between them")
    check(#ib.strokes == 13 and #tb.strokes == 4, "items = a basket, tasks = a sword")
    local kinds = {}
    for _, e in ipairs(P.areas[1].items) do kinds[e.kind] = true end
    check(kinds.loot and kinds.slay and kinds.task, "Near me lists items and tasks (slaying and other steps)")

    local click = function(b) b:GetScript("OnClick")(b, "LeftButton") end
    click(tb)
    local allLoot = true
    for _, e in ipairs(P.areas[1].items) do if e.kind ~= "loot" then allLoot = false end end
    check(not tb.on and tb.strokes[1].main.__color[4] < 0.5 and allLoot and f.footerFS.__text:find("gathered"),
        "tasks off: faded button, just items, footer says gathered")
    click(ib)
    check(CFQ.parchmentOpts.tallyLoot and ib.on, "items can't be switched off while tasks are off (one always stays on)")
    click(tb); click(ib)
    local only = P.areas[1].items
    local allTasks = #only > 0
    for _, e in ipairs(only) do if P.LineGroup(e) ~= "tasks" then allTasks = false end end
    check(not ib.on and tb.on and allTasks and f:IsShown() and f.footerFS.__text:find("done"), "items off: just tasks, footer counts what's done")
    local slayLine
    for _, e in ipairs(only) do if e.kind == "slay" then slayLine = e end end
    local UE, UD = UnitExists, UnitIsDead
    UnitExists = function() return true end; UnitIsDead = function() return false end
    check(slayLine and CFQ.GetItemFXMode(slayLine, CFQ.BuildHuntContext()) == "fire", "a slay line burns while your target is one of them")
    UnitIsDead = function() return true end
    check(CFQ.GetItemFXMode(slayLine, CFQ.BuildHuntContext()) ~= "fire", "...but not once it's dead")
    UnitExists, UnitIsDead = UE, UD
    -- switching items or tasks off never puts the tally (and its buttons) away
    CFQ.parchmentOpts.hideWhenNothingNearby = true
    local emptyPage = { { items = {} } }
    check(not P.ShouldHideUnfiltered(emptyPage), "items off and no tasks near: the tally stays up, even with 'hide when nothing is nearby'")
    CFQ.parchmentOpts.tallyLoot = true
    check(P.ShouldHideUnfiltered(emptyPage), "...but with both on and nothing near, that setting still hides it")
    CFQ.parchmentOpts.hideWhenNothingNearby = false
    P.OnTallyChoiceChanged()
    check(ib.on and tb.on, "items back on")

    local rows = P.SortTallyRows({ { kind = "task", itemName = "a" }, { kind = "loot", itemName = "b" },
        { kind = "slay", itemName = "c" }, { kind = "loot", itemName = "d" } })
    check(rows[1].itemName == "a" and rows[2].itemName == "b", "tasks apart off: the usual (tracker) order")
    click(sb)
    rows = P.SortTallyRows({ { kind = "task", itemName = "a" }, { kind = "loot", itemName = "b" },
        { kind = "slay", itemName = "c" }, { kind = "loot", itemName = "d" } })
    check(sb.on and rows[1].itemName == "b" and rows[2].itemName == "d" and rows[3].itemName == "a" and rows[4].itemName == "c",
        "tasks apart: items first, then tasks (slaying and steps together), each in the usual order")
    local h = f.kindHeads
    check(h and h[1].fs.__shown and h[1].fs.__text == "Items" and h[2].fs.__shown and h[2].fs.__text == "Tasks",
        "tasks apart: an Items heading and a Tasks heading")
    local seenTask, mixed = false, false
    for _, e in ipairs(P.areas[1].items) do
        if P.LineGroup(e) == "tasks" then seenTask = true elseif seenTask then mixed = true end
    end
    check(not mixed, "...and no item comes after a task on the page")
    click(sb)
    check(not sb.on and not h[1].fs.__shown and not h[2].fs.__shown, "tasks apart off: no headings")

    click(sb)
    check(QRF_SavedState.parchmentOpts.tallySeparate == true and QRF_SavedState.tallySort == nil, "tasks apart is saved (the old order setting is dropped)")
    QRF_SavedState.parchmentOpts = { tallyLoot = false, tallyTasks = false, tallySlay = true, tallySeparate = true }
    Fire("ADDON_LOADED", "Handkerquest")
    check(CFQ.parchmentOpts.tallyLoot and CFQ.parchmentOpts.tallySlay == nil and CFQ.parchmentOpts.tallySeparate,
        "an all-off save still lists items; the old slay key is ignored")

    local tasksCb, sepCb
    for _, w in ipairs(CFQ.optionWidgets) do
        if w.label and w.label.__text == "List tasks" then tasksCb = w end
        if w.label and w.label.__text == "Tasks apart from items" then sepCb = w end
    end
    check(tasksCb and sepCb, "options panel: List tasks, Tasks apart from items")
    if tasksCb and sepCb then
        tasksCb:SetChecked(true); tasksCb:GetScript("OnClick")(tasksCb)
        sepCb:SetChecked(false); sepCb:GetScript("OnClick")(sepCb)
        check(CFQ.parchmentOpts.tallyTasks == true and CFQ.parchmentOpts.tallySeparate == false and not sb.on,
            "options checkboxes switch tasks on and tasks apart off (and the toggles follow)")
    end
end

-- Wet ink on cloth and leaf, and the "Blotted scrawl" handwriting's drops of ink
do
    local function ShownRows()
        local out = {}
        for _, fr in ipairs(allFrames) do
            if fr.__kind == "Button" and fr.box and fr.itemText and fr.__shown and fr.__parent == f.content then table.insert(out, fr) end
        end
        return out
    end
    CFQ.parchmentFont = "QUILL"                      -- the options tests above left the handwriting elsewhere
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    local rows = ShownRows()
    local r1 = rows[1]
    local hl = r1 and r1.itemText.halo
    check(P.BLEED_W == 2.2 and hl and hl[1].__shown and (hl[1].haloCol == P.INK or hl[1].haloCol == P.GetStyle().faded)
        and hl[1].__points[1][4] == 0.8
        and not hl[1].__text:find("|c", 1, true), "rag: wet ink, a soft ink halo round the words (plain text, ink colour) and wide bleed")
    CFQ.parchmentStyle = "HANDKERCHIEF"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(P.BLEED_W == 2.6 and r1.itemText.halo[1].__shown and r1.itemText.halo[1].__points[1][4] == 0.9, "handkerchief: the wettest ink")
    CFQ.parchmentStyle = "CRUMPLED"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(P.BLEED_W == 1.0 and not r1.itemText.halo[1].__shown, "crumpled paper (pencil): dry, no halo")

    CFQ.parchmentFont = "PLAIN"; P.CycleFontStyle()
    check(CFQ.parchmentFont == "BLOTTED" and P.GetFontStyle().label == "Blotted scrawl", "handwriting cycles on to Blotted scrawl")
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    local function Drops()
        local n, pos = 0, {}
        for _, row in ipairs(ShownRows()) do
            for _, d in ipairs(row.drops or {}) do
                if d.__shown then n = n + 1; table.insert(pos, d.__px .. "," .. d.__py) end
            end
        end
        return n, table.concat(pos, ";")
    end
    local n1, p1 = Drops()
    Fire("ZONE_CHANGED")
    local n2, p2 = Drops()
    check(n1 > 0 and n1 == n2 and p1 == p2, "blotted scrawl: drops of ink here and there (" .. n1 .. "), in the same spots every redraw")
    check(rows[1].itemText.inkKey:find("^BLOTTED:"), "blotted scrawl writes in the rough hand")
    -- the drops are soaked-in blots from the atlas (a cell, mirrored either way), not plain dots
    local blotOk, nBlot = true, 0
    for _, row in ipairs(ShownRows()) do
        for _, d in ipairs(row.drops or {}) do
            if d.__shown then
                nBlot = nBlot + 1
                local tc = d.__tc
                if d.__tex ~= "Interface\\AddOns\\Handkerquest\\textures\\ink_blots" or not tc or #tc ~= 4
                    or math.abs(math.abs(tc[2] - tc[1]) - 0.5) > 1e-6 or math.abs(math.abs(tc[4] - tc[3]) - 0.5) > 1e-6 then blotOk = false end
            end
        end
    end
    check(nBlot > 0 and blotOk, "blotted scrawl: drops are irregular soaked-in blots from the ink_blots atlas")
    -- mostly tiny spatters round the stroke, every line; big blots are the exception
    local small, big, rowsWithSpatter, nRows = 0, 0, 0, 0
    for _, row in ipairs(ShownRows()) do
        nRows = nRows + 1
        local sp = 0
        for _, d in ipairs(row.drops or {}) do
            if d.__shown then
                if d.__w <= 4.1 then small = small + 1; sp = sp + 1 else big = big + 1 end
            end
        end
        if sp >= 2 then rowsWithSpatter = rowsWithSpatter + 1 end
    end
    check(rowsWithSpatter == nRows and small > big * 3,
        "blotted scrawl: tiny spatters on every line, few big blots (" .. small .. " small, " .. big .. " big)")
    -- over many lines: the quill rests (a bigger blot) on about one line in five, a splash rarely
    do
        local bigLines, splashes, lines = 0, 0, 200
        local fake = { drops = nil, itemText = rows[1].itemText }
        fake.CreateTexture = function(_, ...) return rows[1]:CreateTexture(...) end
        for i = 1, lines do
            P.SetInkDrops(fake, { key = "line " .. i, lastW = 120, textH = 14, lines = 1, textW = 160, ink = P.INK })
            local hasBig = false
            for _, d in ipairs(fake.drops) do
                if d.__shown and d.__w > 4.1 then hasBig = true end
                if d.__shown and d.__tc and d.__tc[3] == 0.5 and math.min(d.__tc[1], d.__tc[2]) == 0 then splashes = splashes + 1 end
            end
            if hasBig then bigLines = bigLines + 1 end
        end
        check(bigLines >= 20 and bigLines <= 70 and splashes <= 30,
            "blotted scrawl: a big blot on roughly one line in five (" .. bigLines .. "/200), splashes rare (" .. splashes .. ")")
    end
    -- bolder letters: a second pass of the quill, colours kept; the wet ink hugs them (a bleed, not a blur)
    local it = rows[1].itemText
    check(it.boldCopy and it.boldCopy.__shown and it.boldCopy.__points[1][4] == 0.8 and it.boldCopy.__text == it.__text,
        "blotted scrawl: bolder letters (a second pass 0.8px right, same words and colours)")
    check(math.abs(it.halo[1].__points[1][4] - 0.8 * 0.55) < 1e-6, "blotted scrawl: the wet ink spreads less round the letters")
    -- the heading is one line cut off with "...": its copies span the same box, so a long sub-zone
    -- ("Northshire Valley") never wraps a word under it onto the Items heading
    local tb, th = f.titleFS.boldCopy, f.titleFS.halo and f.titleFS.halo[1]
    check(f.titleFS.singleLine and tb and tb.__points[2] and tb.__points[2][1] == "TOPRIGHT" and tb.__points[2][2] == f.titleFS
        and th and th.__points[2] and th.__points[2][1] == "TOPRIGHT",
        "heading's bold pass and wet-ink copies cut off with the heading instead of wrapping")
    check(not (it.boldCopy.__points[2]), "list lines' copies still wrap with their line")
    CFQ.parchmentFont = "QUILL"; Fire("ZONE_CHANGED")
    check(not it.boldCopy.__shown and it.halo[1].__points[1][4] == 0.8, "other hands: no second pass, the usual spread")
    CFQ.parchmentFont = "BLOTTED"; Fire("ZONE_CHANGED")

    -- text size: the lines grow with the slider, the heading by half as much; saved and clamped
    CFQ.tallyTextScale = 150; Fire("ZONE_CHANGED")
    local _, sz = it:GetFont()
    local _, tsz = f.titleFS:GetFont()
    check(sz == 18 and tsz == 18, "text size 150%: lines 12 -> 18, heading 14 -> 18 (half as much) (" .. tostring(sz) .. ", " .. tostring(tsz) .. ")")
    check(it.boldCopy.__font and it.boldCopy.__font[2] == 18 and it.halo[1].__font[2] == 18, "...and the bold pass and wet ink follow")
    check(CFQ.textSizeRow and CFQ.textSizeRow.slider, "options: Text size slider")
    if CFQ.textSizeRow then
        CFQ.textSizeRow.slider:GetScript("OnValueChanged")(CFQ.textSizeRow.slider, 90)
        check(CFQ.tallyTextScale == 90 and QRF_SavedState.tallyTextScale == 90, "Text size slider sets and saves the size")
    end
    CFQ.tallyTextScale = 100; Fire("ZONE_CHANGED")
    CFQ.parchmentStyle = "BARK"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(Drops() == 0, "carved bark keeps its knife-cut letters: no ink drops")
    CFQ.parchmentFont = "QUILL"; P.CycleFontStyle(); P.CycleFontStyle(); P.CycleFontStyle()
    check(CFQ.parchmentFont == "BLOTTED", "quill -> scrawl -> plain -> blotted")
    P.CycleFontStyle()
    check(CFQ.parchmentFont == "QUILL", "...and back round to the quill")
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(Drops() == 0, "no drops in the other hands")
end

-- Near me on a fresh character: the quest's area as the world map shows it (no waypoint, map never
-- opened), possibly on a parent map of yours; a quest heading naming your sub-zone; and a chat note
-- when switching the tally on leaves it hidden
do
    local saved = { C_QuestLog.GetNextWaypoint, C_QuestLog.GetQuestsOnMap, C_Map.GetBestMapForUnit, C_Map.GetMapInfo,
                    C_Map.GetMapPosFromWorldPos, ZONE, SUBZONE }
    C_QuestLog.GetNextWaypoint = function() return nil end
    C_Map.GetBestMapForUnit = function() return 425 end      -- Northshire, inside Elwynn Forest (1429)
    C_Map.GetMapInfo = function(id) if id == 425 then return { name = "Northshire", parentMapID = 1429 } end return { name = "Elwynn Forest" } end
    C_QuestLog.GetQuestsOnMap = function(m) if m == 1429 then return { { questID = 777, x = 0.48, y = 0.41 } } end return {} end
    CFQ.mapQuestCache = {}
    local m, x, y = CFQ.QuestPosNearPlayer(777)
    check(m == 1429 and x == 0.48 and y == 0.41, "quest area found on the parent map (Northshire -> Elwynn) without opening the world map")
    check(CFQ.QuestPosNearPlayer(778) == nil, "...and nothing made up for a quest the map doesn't show")

    -- a quest placed on another map than yours is measured after translating it onto yours
    local q101 = __QMAP()[101]
    P.CollectQuests()
    check(q101.playerDist == nil, "no shared map and no translation: no distance")
    C_Map.GetMapPosFromWorldPos = function(_, w) local wx, wy = w.GetXY(); return 1, CreateVector2D(wx / 4000, wy / 4000) end
    local nearSet = P.CollectQuests()
    check(q101.playerDist and q101.playerDist < 0.03 and nearSet[101], "quest on a parent map translated onto yours: near me")
    C_Map.GetMapPosFromWorldPos = saved[5]

    -- no position at all: a quest log heading naming the sub-zone you're in counts as here
    local q104 = __QMAP()[104]
    local sx, sy, sm = q104.x, q104.y, q104.mapID
    q104.x, q104.y, q104.mapID = nil, nil, nil
    ZONE, SUBZONE = "Elwynn Forest", "Darkshore"
    WATCHED[104] = true
    nearSet = P.CollectQuests()
    check(nearSet[104], "tracked quest whose heading is your sub-zone (e.g. Northshire Valley) is near you")
    WATCHED[104] = nil
    q104.x, q104.y, q104.mapID = sx, sy, sm
    C_QuestLog.GetNextWaypoint, C_QuestLog.GetQuestsOnMap, C_Map.GetBestMapForUnit, C_Map.GetMapInfo = saved[1], saved[2], saved[3], saved[4]
    ZONE, SUBZONE = saved[6], saved[7]
    CFQ.mapQuestCache = {}

    -- switching the tally on while "...only when something is nearby" keeps it away says why in chat
    local printed = {}
    local realPrint = print
    print = function(s) table.insert(printed, tostring(s)) end
    CFQ.parchmentOpts.hideWhenNothingNearby = true
    local tabs = CFQ.parchmentOpts.showTabs
    CFQ.parchmentOpts.showTabs = true
    local px, py = PX, PY
    PX, PY = 0.02, 0.02
    NOW = NOW + 1000                                  -- nothing progressed lately
    SlashCmdList["HANDKERQUEST"]("tally")             -- off
    SlashCmdList["HANDKERQUEST"]("tally")             -- on again
    print = realPrint
    local said = false
    for _, s in ipairs(printed) do if s:find("hidden until something is nearby") then said = true end end
    check(not f:IsShown() and said, "tally switched on but nothing nearby: a chat note says why it's hidden")
    CFQ.parchmentOpts.hideWhenNothingNearby = false
    printed = {}
    print = function(s) table.insert(printed, tostring(s)) end
    P.TurnTallyOn()
    print = realPrint
    check(f:IsShown() and #printed == 0, "...and nothing said when it does come up")
    CFQ.parchmentOpts.showTabs = false
    CFQ.parchmentOpts.hideWhenNothingNearby = true
    SlashCmdList["HANDKERQUEST"]("tally"); printed = {}
    print = function(s) table.insert(printed, tostring(s)) end
    SlashCmdList["HANDKERQUEST"]("tally")
    print = realPrint
    check(printed[1] and printed[1]:find("hidden until something is nearby"), "other pages off too: still the nearby reason, not \"nothing to list\"")
    CFQ.parchmentOpts.showTabs, CFQ.parchmentOpts.hideWhenNothingNearby = tabs, false
    PX, PY = px, py

    -- options: the hide choice sits right under "Show the parchment tally list", indented; the panel scrolls
    local showIdx, hideIdx, hideCb
    for i, w in ipairs(CFQ.optionWidgets) do
        if w.label and w.label.__text == "Show the parchment tally list" then showIdx = i end
        if w.label and w.label.__text == "...only when something is nearby" then hideIdx, hideCb = i, w end
    end
    check(showIdx and hideIdx == showIdx + 1, "options: \"...only when something is nearby\" right under the tally checkbox")
    check(CFQ.optionsPanel == QRF_OptionsPanel and hideCb and hideCb.__parent ~= QRF_OptionsPanel,
        "options: built on a scroll child inside the registered panel, so it fits the Settings window")
end

-- ticker with distance sort
SlashCmdList["HANDKERQUEST"]("dist")
for _ = 1, 4 do TICKER() end

check(SLASH_HANDKERQUEST1 == "/hanky" and SLASH_HANDKERQUEST2 == "/handkerquest" and SLASH_HANDKERQUEST3 == "/cfq", "slash commands: /hanky, /handkerquest, old /cfq")
check(QRF_OptionsPanel and true, "options panel exists under the new name")
check(#ERRORS == 0, "no Lua errors reported (" .. #ERRORS .. ")")
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
