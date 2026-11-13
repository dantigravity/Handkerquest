local here = (arg[0]:match("^(.*)[/\\]") or ".")
dofile(here .. "/wowmock.lua")
local addonPath = arg[1] or (here .. "/HandkerSheaf.lua")

-- Expose the addon's locals to the test (test copy only)
local src = assert(io.open(addonPath), "cannot open " .. addonPath):read("*a") .. "\n_G.__CFQ = CFQ\n_G.__LAYOUT = function() LayoutObjectiveTrackerWithStacks() end\n_G.__QMAP = function() return questRewardMap end\n_G.__STATE = function() return { lvl = levelSortMode, dist = distSortMode, primary = primarySortKey, incomp = incompleteStackEnabled, turnin = turnInStackEnabled } end\n"
local chunk = assert(loadstring(src, "HandkerSheaf.lua"))
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

-- "For me" (your own tasks) is tested on its own near the end: off here so the older checks keep their room
CFQ.parchmentOpts.forMe = false; P.OnTallyChoiceChanged()
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

-- paladin looks: sanctified marble, gilded plate, illuminated vellum (after etched leather)
do
    local TEX = "Interface\\AddOns\\Handkerquest\\textures\\"
    local function Tc(t) return t.__tc and table.concat(t.__tc, ",") or "0,1,0,1" end
    P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(CFQ.parchmentStyle == "MARBLE" and f.topSheet.body.__tex == TEX .. "sanctified_marble", "etched leather -> sanctified marble: the tablet texture")
    check(f.visibleBackSheets > 0 and Tc(f.backSheets[1].body) == "1,0,0,1" and Tc(f.backSheets[2].body) == "0,1,0,1",
        "marble: tablets underneath only mirrored, the arch stays on top")
    local th = f.titleFS.halo
    check(th and th[1].__shown and th[1].haloCol[1] == 1.00 and th[1].haloCol[2] > 0.8 and th[1].haloCol[3] < 0.5,
        "marble: a gold holy light round the heading")
    local pulses, real = 0, P.PulseHalo
    P.PulseHalo = function(...) pulses = pulses + 1; return real(...) end
    frames(5)
    P.PulseHalo = real
    check(pulses >= 5 and not f.arcaneOn, "marble: the holy light breathes (without the arcane circle)")
    P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
    check(not anyShown(f.corner.flap) and f.corner.foldEdge.__shown, "marble: a gilded dog-ear mark, stone doesn't fold")
    -- gilded plate
    P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(CFQ.parchmentStyle == "GILDED" and f.topSheet.body.__tex == TEX .. "gilded_plate" and f.sheenOn, "marble -> gilded plate, with its sheen")
    P.AnimateSheen(f, 0.8)
    local a = f.sheen.a
    local w = f:GetWidth()
    check(a.__shown and f.sheen.b.__shown and a.__points[1][4] >= w * 0.13 - 0.5, "gilded plate: the light sweeps across inside the rim")
    P.AnimateSheen(f, 3.0)
    check(not a.__shown and not f.sheen.b.__shown, "...then the plate rests until the next glint")
    P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
    check(not anyShown(f.corner.flap) and f.corner.foldEdge.__shown, "gilded plate: an engraved dog-ear mark")
    -- illuminated vellum
    P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
    check(CFQ.parchmentStyle == "VELLUM" and f.topSheet.body.__tex == TEX .. "illuminated_vellum" and not f.sheenOn
        and not (f.sheen.a.__shown or f.sheen.b.__shown), "gilded plate -> illuminated vellum: no sheen on the page")
    check(f.titleFS.__text:find("^|cFFCC941F") ~= nil, "vellum: the heading's first letter is gilded (" .. tostring(f.titleFS.__text) .. ")")
    P.UpdateCorner(f); f.corner.drawnKey = nil; P.DrawCorner(f.corner)
    check(anyShown(f.corner.flap), "vellum bends: a real page fold")
    for _, name in ipairs({ "marble", "gold", "vellum", "libram" }) do
        CFQ.parchmentStyle = "RAG"; SlashCmdList["HANDKERQUEST"]("look " .. name)
    end
    check(CFQ.parchmentStyle == "VELLUM", "/hanky look marble / gold / vellum / libram")
    for _, key in ipairs({ "MARBLE", "GILDED", "VELLUM" }) do
        local fh = io.open(here .. "/textures/" .. ({ MARBLE = "sanctified_marble", GILDED = "gilded_plate", VELLUM = "illuminated_vellum" })[key] .. ".tga", "rb")
        check(fh and fh:read(1) and true, key .. ": its texture file is in textures/")
        if fh then fh:close() end
    end
end

-- arcane script: words of light in the air, a turning rune circle, drifting motes, no pile
P.CycleStyle(); P.ApplyStyle(); Fire("ZONE_CHANGED")
check(CFQ.parchmentStyle == "ARCANE" and f.arcaneOn and f.arcane.ring.__shown
    and f.arcane.ring.__tex == "Interface\\AddOns\\Handkerquest\\textures\\arcane_ring", "illuminated vellum -> arcane script: the rune circle is up")
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
check(P.GetStyle().font == nil and f.titleFS.inkKey:find("^" .. P.GetFontStyle().key .. ":"), "transparent window writes in the chosen handwriting (" .. P.GetFontStyle().key .. "), not locked to plain print")
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
do  -- a quest with an item to click (Eyes of the Sentinels' eye, the phial...) still stacks; its item gets
    -- our own secure button to the left of the deck, gliding beside its own card when the deck fans out
    local real = GetQuestLogSpecialItemInfo
    local itemLog = __QMAP()[102].logIndex
    local ICON = "Interface\\Icons\\INV_Drink_06"
    GetQuestLogSpecialItemInfo = function(i) if i == itemLog then return "item:5185", ICON, 1, false end end
    __LAYOUT()
    local d = IncompDeck()
    local b = CFQ.itemButtons[1]
    check(__QMAP()[102].hasQuestItem and d and #d.clusterData.quests == 2, "102 has a quest item and still stacks with 101")
    check(b and b.__shown and b:GetAttribute("type") == "item" and b:GetAttribute("item") == "item:5185" and b.icon.__tex == ICON
        and b.questID == 102, "its item gets a secure item button (type item, the quest's item)")
    local pt = b.__points[1]
    check(pt[1] == "TOPRIGHT" and pt[2] == UIParent and pt[4] < d:GetLeft() and pt[5] == d:GetTop() - 4,
        "collapsed: the button sits left of the deck, level with its top (placed on screen, not anchored to the deck)")
    check(not (CFQ.itemButtons[2] and CFQ.itemButtons[2].__shown), "only quests with items get a button")
    -- fanned out: the button slides next to 102's own card
    local idx
    for i, q in ipairs(d.displayQuests) do if q.questID == 102 then idx = i end end
    local card = d.cards[idx]
    card:Show(); card.__py = -44
    d.expandProgress = 1
    CFQ.PlaceDeckItemButtons()
    pt = b.__points[1]
    check(pt[5] == card:GetTop() - 4 and pt[4] == card:GetLeft() - 4, "fanned out: the button sits beside 102's own card")
    -- in combat secure buttons can't move: they stay put and catch up afterwards
    local realCombat = InCombatLockdown
    InCombatLockdown = function() return true end
    d.expandProgress = 0
    CFQ.PlaceDeckItemButtons()
    check(b.__points[1][5] == card:GetTop() - 4 and CFQ.itemButtonsDirty, "in combat the button stays where it was")
    InCombatLockdown = realCombat
    Fire("PLAYER_REGEN_ENABLED")
    check(b.__points[1][5] == d:GetTop() - 4 and not CFQ.itemButtonsDirty, "after combat it catches up with the deck")
    card.__py = nil; card:Hide()
    -- a client without secure buttons: the quest keeps its own tracker line (and Blizzard's button) instead
    CFQ.secureItemsOK = false
    __LAYOUT()
    check(IncompDeck() == nil and blocks[102].__alpha ~= 0 and not b.__shown, "no secure buttons: a quest with an item stays out of decks")
    CFQ.secureItemsOK = true
    check(CFQ.QuestHasItemButton(itemLog, true) == false, "a finished quest's item only counts if the game still shows it")
    GetQuestLogSpecialItemInfo = function(i) if i == itemLog then return "item:5185", ICON, 1, true end end
    check(CFQ.QuestHasItemButton(itemLog, true) == true, "...which it says with showItemWhenComplete")
    GetQuestLogSpecialItemInfo = real
    __LAYOUT()
    check(not __QMAP()[102].hasQuestItem and IncompDeck() ~= nil and not b.__shown, "item used up: the deck stays, the button goes")
end
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
-- Look drop-down in the panel: every look listed, the current one ticked; picking one switches and closes it
local lookBtn
for _, w in ipairs(CFQ.optionWidgets) do
    if type(w.__text) == "string" and w.__text:find("^Look: ") then lookBtn = w end
end
check(lookBtn ~= nil and lookBtn.__text == "Look: Handkerchief notes", "options show Look: Handkerchief notes")
if lookBtn then
    local list = lookBtn.list
    check(list and not list.__shown and #list.rows == #P.STYLES and #P.STYLES == 13, "look drop-down: one row per look (13), closed")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(list.__shown and list.rows[1].tick.__shown and not list.rows[2].tick.__shown, "clicking the button opens the list, the handkerchief ticked")
    check(list.rows[4].swatch.__tex == "Interface\\AddOns\\Handkerquest\\textures\\torn_rag" and list.rows[1].swatch.__color ~= nil,
        "each row has a swatch: the material for texture looks, the cloth colour for drawn ones")
    local function Pick(key)
        if not list.__shown then lookBtn:GetScript("OnClick")(lookBtn) end
        for _, row in ipairs(list.rows) do if row.key == key then row:GetScript("OnClick")(row) end end
    end
    Pick("PARCHMENT")
    check(lookBtn.__text == "Look: Parchment" and f.styleKey == "PARCHMENT" and not list.__shown, "picking Parchment switches the look and closes the list")
    lookBtn:GetScript("OnClick")(lookBtn); lookBtn:GetScript("OnClick")(lookBtn)
    check(not list.__shown, "clicking the button again closes the list")
    do  -- in game, Settings re-parents our panel, which drops the list to the window's layer (HIGH), under the catcher
        local ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
        local catcher = list.catcher
        list:SetFrameStrata("HIGH")
        lookBtn:GetScript("OnClick")(lookBtn)
        check(list.__shown and catcher.__shown and ORDER[list:GetFrameStrata()] > ORDER[catcher:GetFrameStrata()]
            and ORDER[catcher:GetFrameStrata()] > ORDER.HIGH,
            "opening the list puts it back above the click-catcher (" .. list:GetFrameStrata() .. " over " .. catcher:GetFrameStrata() .. "), the catcher above Settings")
        -- safety net: a click that still reaches the catcher over a look picks that look
        local row = list.rows[3]
        row.IsMouseOver = function() return true end
        catcher:GetScript("OnClick")(catcher)
        row.IsMouseOver = nil
        check(CFQ.parchmentStyle == "CRUMPLED" and f.styleKey == "CRUMPLED" and not list.__shown and not catcher.__shown,
            "a click caught over a look still picks it (crumpled paper)")
        lookBtn:GetScript("OnClick")(lookBtn)
        catcher:GetScript("OnClick")(catcher)
        check(CFQ.parchmentStyle == "CRUMPLED" and not list.__shown, "a click anywhere else just closes the list")
    end
    Pick("BARK")
    check(lookBtn.__text == "Look: Carved bark" and fontBtn.__alpha < 1 and fontBtn.__text:find("set by the look"),
        "look list: carved bark brings its own knife-cut lettering")
    Pick("LEAF")
    check(lookBtn.__text == "Look: Pipe-weed leaf" and fontBtn.__alpha == 1, "look list: pipe-weed leaf (handwriting selectable again)")
    Pick("GILDED")
    check(lookBtn.__text == "Look: Gilded plate" and f.styleKey == "GILDED", "look list: gilded plate")
    Pick("ARCANE")
    check(lookBtn.__text == "Look: Arcane script" and fontBtn.__alpha == 1, "look list: arcane script")
    Pick("NATIVE")
    check(lookBtn.__text == "Look: Transparent window" and fontBtn.__alpha == 1 and not fontBtn.__text:find("set by the look"),
        "window look: the handwriting button stays live (no lock to plain print)")
    lookBtn:GetScript("OnClick")(lookBtn)
    check(list.__shown, "list open again")
    CFQ.optionsPanel:Show(); CFQ.optionsPanel:Hide()
    check(not list.__shown, "closing the options closes the list")
    Pick("HANDKERCHIEF")
    check(CFQ.parchmentStyle == "HANDKERCHIEF" and QRF_SavedState.parchmentStyle == "HANDKERCHIEF", "back to the handkerchief (saved)")
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

-- Tally check-offs: tasks (kills / other steps, one-step quests too), and the items / tasks / tasks-apart
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
    local one = CFQ.ExtractTaskObjectives(900, 0, false, qty)
    check(#one == 1 and one[1].single and one[1].kind == "slay", "one enemy to slay (and nothing else): on the tally as a plain box")
    qty[1].numRequired = 8
    one = CFQ.ExtractTaskObjectives(900, 0, false, qty)
    check(#one == 1 and not one[1].single, "eight to slay: on the tally with its count")
    With({ { text = "Sit by the fire", type = "event" } })
    one = CFQ.ExtractTaskObjectives(901, 0, false, {})
    check(#one == 1 and one[1].single and one[1].itemName == "Sit by the fire" and not one[1].finished,
        "a quest that's just one step ('Sit by the fire') gets a box on the tally")
    check(CFQ.ExtractTaskObjectives(901, 0, true, {})[1].finished, "...ticked once the quest is ready to turn in")
    do  -- a new character whose only quest is that one step: the tally comes up instead of staying put away
        local qFire = { questID = 901, title = "Rest by the Fire", isComplete = false, itemObjectives = {}, taskObjectives = one }
        local a = { items = P.FlattenQuests({ qFire }) }
        check(#a.items == 1 and not P.ShouldHideTally({ a }), "only quest is one step: the tally has a line and stays up")
    end
    With({ { text = "Collect 7 Small Spider Legs", type = "item" } })
    check(#CFQ.ExtractTaskObjectives(903, 0, false, {}) == 0, "an item objective is never a task")
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
do  -- the options heading shows the .toc's version live (no hard-coded number to forget)
    local tocVersion
    local fh = io.open(here .. "/Handkerquest.toc")
    if fh then
        for line in fh:lines() do tocVersion = tocVersion or line:gsub("\r", ""):match("^##%s*Version:%s*(.-)%s*$") end
        fh:close()
    end
    check(tocVersion and CFQ.AddonVersion() == tocVersion, "version comes from the .toc (" .. tostring(CFQ.AddonVersion()) .. " / " .. tostring(tocVersion) .. ")")
    local heading = CFQ.optionsTitle and CFQ.optionsTitle.__text or ""
    check(heading:find("HandkerSheaf", 1, true) and heading:find("v" .. tostring(tocVersion), 1, true), "options heading: " .. heading)
    local realMeta = C_AddOns
    C_AddOns = nil
    local okNo, vNo = pcall(CFQ.AddonVersion)
    C_AddOns = realMeta
    check(okNo and vNo == nil, "no metadata API: no version, no error")
end
do  -- players see "HandkerSheaf" (options panel, Settings list, chat); the addon id stays "Handkerquest"
    check(QRF_OptionsPanel.name == "HandkerSheaf", "options panel is listed as HandkerSheaf (" .. tostring(QRF_OptionsPanel.name) .. ")")
    local said, realPrintN = {}, print
    print = function(s) said[#said + 1] = tostring(s) end
    local styleBefore = CFQ.parchmentStyle
    pcall(SlashCmdList["HANDKERQUEST"], "look rag")
    print = realPrintN
    CFQ.parchmentStyle = styleBefore; P.ApplyStyle()
    check(said[1] and said[1]:find("HandkerSheaf:", 1, true) and not said[1]:find("Handkerquest", 1, true),
        "chat lines start with HandkerSheaf: (" .. tostring(said[1]) .. ")")
end
do  -- every slider (tracker (•••) bar, options panel) got a real range
    local bad, n = 0, 0
    for _, fr in ipairs(allFrames) do
        if fr.__kind == "Slider" then
            n = n + 1
            if type(fr.__min) ~= "number" or type(fr.__max) ~= "number" or fr.__max <= fr.__min then bad = bad + 1 end
        end
    end
    check(n >= 3 and bad == 0, "every slider has a min/max range (" .. n .. " sliders, " .. bad .. " without)")
end
do  -- tally colours: Arcane script's runes (beside the Look button, only on that look) and the writing (every look)
    local runeRow, inkRow = CFQ.runeColorRow, CFQ.inkColorRow
    local function Look(key) local s for _, x in ipairs(P.STYLES) do if x.key == key then s = x end end return s end
    local arc, rag, stone = Look("ARCANE"), Look("RAG"), Look("STONE")
    local Same = P.SameColor
    local function Click(b) b:GetScript("OnClick")(b) end
    local ragInk = P.CopyTable(P.StyleDefaults(rag).ink)
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
    check(runeRow and inkRow and not runeRow.__shown and inkRow.__shown, "rag look: no rune colours, the writing colour is there")
    check(runeRow.__points[1][4] == 244 and inkRow.__points[1][4] == 24, "rune swatches sit beside the Look button, writing on its own row")
    check(inkRow.swatches[1].selected and Same(inkRow.swatches[1].fill.__color, ragInk), "first writing swatch = the rag's own soot, picked")
    -- writing on the rag: oxblood red
    local red = P.INK_COLORS[6].c
    Click(inkRow.swatches[6])
    check(Same(CFQ.inkColors.RAG, red) and Same(rag.ink, red) and Same(P.INK, red) and inkRow.swatches[6].selected
        and not inkRow.swatches[1].selected and Same(QRF_SavedState.inkColors.RAG, red), "rag: oxblood writing (saved for the rag)")
    local d = P.StyleDefaults(rag)
    check(Same(rag.title, P.ShiftColor(d.title, d.ink, red)) and (not d.bleed or Same(rag.bleed, P.ShiftColor(d.bleed, d.ink, red))),
        "heading shifts with the writing; wet ink has no bleed of its own")
    -- each look remembers its own
    CFQ.parchmentStyle = "STONE"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
    check(CFQ.inkColors.STONE == nil and Same(stone.ink, P.StyleDefaults(stone).ink) and inkRow.swatches[1].selected
        and Same(inkRow.swatches[1].fill.__color, P.StyleDefaults(stone).ink), "slate keeps its own chalk; first swatch shows the chalk")
    Click(inkRow.swatches[9])
    check(Same(stone.ink, { 1, 1, 1 }) and Same(rag.ink, red), "white chalk on the slate, the rag stays red")
    local sd = P.StyleDefaults(stone)
    check(Same(stone.bleed, P.ShiftColor(sd.bleed, sd.ink, { 1, 1, 1 })), "the slate's chalk dust takes the writing colour")
    do  -- bark's carved shadow is the wood's, not the writing's
        local bark = Look("BARK")
        CFQ.parchmentStyle = "BARK"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
        Click(inkRow.swatches[7])
        check(Same(bark.ink, P.INK_COLORS[7].c) and Same(bark.bleed, P.StyleDefaults(bark).bleed) and bark.bleed[4] == P.StyleDefaults(bark).bleed[4],
            "gold letters on the bark: the carved shadow stays dark")
        Click(inkRow.swatches[1])
        CFQ.parchmentStyle = "STONE"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
    end
    -- arcane: runes show up beside the Look button
    SlashCmdList["HANDKERQUEST"]("look mage"); CFQ.RefreshOptionsPanel()
    check(runeRow.__shown and runeRow.swatches[1].selected, "arcane look: rune colours appear, the look's own violet picked")
    local fel = P.ARCANE_RUNE_COLORS[3].c
    Click(runeRow.swatches[3])
    check(Same(CFQ.arcaneRuneColor, fel) and Same(arc.arcane.ringColor, fel) and Same(arc.halo.color, fel) and Same(arc.bleed, fel)
        and Same(f.arcane.ring.__vc, fel) and runeRow.swatches[3].selected, "fel green runes: circle, glow round the words and ticks turn green")
    check(Same(arc.ink, P.StyleDefaults(arc).ink), "...the arcane writing keeps its own colour")
    Click(inkRow.swatches[7])
    check(Same(arc.ink, P.INK_COLORS[7].c) and Same(arc.arcane.ringColor, fel) and Same(arc.bleed, fel), "gold writing, separately from the runes")
    -- Custom...: WoW's colour picker
    check(runeRow.customBtn and runeRow.customBtn.__text == "Custom...", "Custom... button beside the swatches")
    Click(runeRow.customBtn)
    local info = ColorPickerFrame.__info
    check(info and Same({ info.r, info.g, info.b }, fel), "colour picker opens on the current rune colour")
    ColorPickerFrame.__rgb = { 0.1, 0.2, 0.9 }; info.swatchFunc()
    check(Same(CFQ.arcaneRuneColor, { 0.1, 0.2, 0.9 }) and runeRow.customBtn.__text == "Custom •", "picked colour applied, marked as custom")
    info.cancelFunc()
    check(Same(CFQ.arcaneRuneColor, fel), "cancelling the picker puts the colour back")
    Click(inkRow.customBtn)
    ColorPickerFrame.__rgb = { 0.5, 0.9, 0.5 }; ColorPickerFrame.__info.swatchFunc()
    check(Same(CFQ.inkColors.ARCANE, { 0.5, 0.9, 0.5 }) and inkRow.customBtn.__text == "Custom •", "custom writing colour")
    -- back to the rag: runes go away
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
    check(not runeRow.__shown and inkRow.swatches[6].selected, "rag again: rune colours hidden, its red writing still picked")
    -- saved and loaded; broken saved values ignored; the old arcane-only writing setting carries over
    QRF_SavedState.arcaneRuneColor = { 0.30, 0.68, 1.00 }
    QRF_SavedState.inkColors = { RAG = { "x", 1, 1 }, STONE = { 0.2, 0.3, 0.4 } }
    QRF_SavedState.arcaneInkColor = { 1, 0.92, 0.62 }
    Fire("ADDON_LOADED", "Handkerquest")
    P.ApplyStyle()
    check(Same(CFQ.arcaneRuneColor, { 0.30, 0.68, 1.00 }) and Same(arc.arcane.ringColor, { 0.30, 0.68, 1.00 })
        and CFQ.inkColors.RAG == nil and Same(rag.ink, ragInk) and Same(stone.ink, { 0.2, 0.3, 0.4 })
        and Same(CFQ.inkColors.ARCANE, { 1, 0.92, 0.62 }), "colours load; a broken one falls back to the look's own; old arcane writing kept")
    P.SetTallyColor("rune", CFQ.arcaneRuneColor)       -- saves
    check(QRF_SavedState.arcaneInkColor == nil and Same(QRF_SavedState.inkColors.ARCANE, { 1, 0.92, 0.62 }), "...and saved under the new key")
    -- back to the first swatches: exactly the looks as drawn
    CFQ.parchmentStyle = "ARCANE"; P.ApplyStyle(); CFQ.RefreshOptionsPanel()
    Click(runeRow.swatches[1]); Click(inkRow.swatches[1])
    check(CFQ.arcaneRuneColor == nil and CFQ.inkColors.ARCANE == nil and Same(arc.arcane.ringColor, { 0.62, 0.40, 1.00 })
        and Same(arc.arcane.moteColors[1], { 0.55, 0.90, 1.00 }) and Same(arc.corner.tip, { 0.80, 0.70, 1.00 })
        and Same(arc.footer, { 0.76, 0.68, 0.96 }) and Same(arc.ink, { 0.90, 0.86, 1.00 }), "first swatches = the look's own colours again")
    for _ = 1, 3 do TICKER() end
    CFQ.inkColors = {}; CFQ.parchmentStyle = "RAG"; P.ApplyStyle()
    check(Same(rag.ink, ragInk) and Same(stone.ink, P.StyleDefaults(stone).ink), "all looks back to their own ink")
end
do  -- "For me": your own tasks at the bottom of the "Near me" page
    local function redraw() P.OnTallyChoiceChanged() end
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    f:SetSize(320, 420)          -- room for a few tasks under the quest lines
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false }
    P.selectedKey = P.areas[1].key            -- on "Near me"
    redraw()
    check(f:IsShown() and f.forMeWrite and f.forMeWrite.__shown, "For me: the writing line is on Near me")
    check((f.forMeWrite.fs.__text == "add a task..." or f.forMeWrite.fs.__text == "a task" or f.forMeWrite.fs.__text == "task") and f.forMeNote and f.forMeNote.__shown
        and f.forMeNote.fs.__text:find("note"), "For me: two choices at the bottom, a task and a note (" .. tostring(f.forMeWrite.fs.__text) .. " / " .. tostring(f.forMeNote and f.forMeNote.fs.__text) .. ")")
    check(f.forMeWrite.mode.glyphKind == "task" and f.forMeNote.glyph.glyphKind == "entry", "For me: a box in front of the task, a quill in front of the note")
    do  -- side by side, each only as wide as its words, clear of the dog-ear
        local wl, nl = f.forMeWrite, f.forMeNote
        local _, _, _, nx = nl:GetPoint(1)
        check(nx == wl.__w + 10 and nl.__w == 20 + nl.fs:GetStringWidth() + 6, "For me: the note choice sits just right of the task choice")
    end
    check(f.forMeHead and f.forMeHead.__shown and f.forMeHead.fs.__text == "For me", "For me: its own heading, even before the first task")
    -- the section stands on the page bottom: the writing line's foot is the page's foot
    local function ContentH()
        local _, padT, _, padB = P.GetPads(f)
        return math.max(55, f:GetHeight() - 45 - padT - padB)
    end
    local writeH = math.max(14, P.LineHeight(f)) + 7
    check(math.abs(f.forMeWrite.__py - -(ContentH() - writeH)) < 0.5,
        "For me: the writing line sits on the bottom of the page (" .. f.forMeWrite.__py .. " vs " .. -(ContentH() - writeH) .. ")")
    local headY0 = f.forMeHead.__py
    check(headY0 < -ContentH() * 0.5, "For me: with no tasks the heading sits low on the page, not under the quest lines")

    -- written like the page's own heading ("Near me"): same writing, same ink, the double underline
    do
        local hf, tf = f.forMeHead.fs, f.titleFS
        check(hf.inkKind == "title" and hf.__font and tf.__font and hf.__font[2] == tf.__font[2],
            "For me heading: the page heading's writing and size (" .. tostring(hf.__font and hf.__font[2]) .. " vs " .. tostring(tf.__font and tf.__font[2]) .. ")")
        check(f.forMeHead.rule.main.__shown and f.forMeHead.rule2.main.__shown, "For me heading: the double quill underline")
    end

    -- the "+ add a task" button is only as wide as its words: the bottom row's right end (dog-ear) stays free
    do
        local wl = f.forMeWrite
        local wordsW = wl.fs:GetStringWidth()
        local anchoredRight = false
        for _, pt in ipairs(wl.__points) do if pt[1] == "TOPRIGHT" or pt[1] == "RIGHT" or pt[1] == "BOTTOMRIGHT" then anchoredRight = true end end
        local contentW = math.max(150, f:GetWidth() - 12 - (select(1, P.GetPads(f))) - (select(3, P.GetPads(f))))
        check(not anchoredRight and wl.__w == 20 + wordsW + 6, "For me: the add-task button is only as wide as its words (" .. tostring(wl.__w) .. ")")
        check(wl.__w <= contentW - P.CORNER_MAX, "For me: ...and stays clear of the dog-ear")
    end

    -- write one: click the line, type, Enter
    f.forMeWrite:GetScript("OnClick")(f.forMeWrite, "LeftButton")
    check(f.forMeEdit.__w <= math.max(150, f:GetWidth() - 12 - (select(1, P.GetPads(f))) - (select(3, P.GetPads(f)))) - 24 - P.CORNER_MAX + 0.01,
        "For me: the writing box stops short of the dog-ear")
    check(P.forMeEditing and f.forMeEdit and f.forMeEdit.__shown, "For me: clicking the line opens a writing box")
    check(f.forMeEdit.__font ~= nil, "For me: the writing box has its font before any text (WoW refuses text without one)")
    f.forMeEdit:SetText("  Buy bigger bags  ")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    local t1 = CFQ.notes.tasks[1]
    check(#CFQ.notes.tasks == 1 and t1.text == "Buy bigger bags" and not t1.done, "For me: Enter keeps the task, trimmed")
    check(not P.forMeEditing and not f.forMeEdit.__shown, "For me: the writing box closes after Enter")
    check(type(t1.when) == "string" and t1.when:find("%d+ %a%a%a %d%d:%d%d") and type(t1.t) == "number",
        "For me: a task is stamped with the time (" .. tostring(t1.when) .. ")")
    check(t1.place and t1.place.zone == GetRealZoneText() and t1.place.mapID ~= nil, "For me: a task is tied to where it was written")
    check(type(t1.owner) == "string" and t1.owner ~= "", "For me: a task knows who wrote it")
    check(f.forMeHead and f.forMeHead.__shown and f.forMeHead.fs.__text == "For me", "For me: the heading stays with the first task")
    local r1 = f.forMeRows and f.forMeRows[1]
    check(r1 and math.abs(f.forMeHead.__py - (headY0 + r1.__h)) < 0.5, "For me: each task lifts the heading by its line (rises from the bottom)")
    check(r1 and math.abs(r1.__py - (f.forMeWrite.__py + r1.__h)) < 0.5, "For me: the newest task sits right above the writing line")
    check(math.abs(f.forMeWrite.__py - -(ContentH() - writeH)) < 0.5, "For me: the writing line stays on the bottom")
    check(r1 and r1.__shown and r1.itemText.__text == "Buy bigger bags" and r1.box.__shown, "For me: the task is written with an inked box")
    check(r1.seed ~= (shoppingListRowPool and shoppingListRowPool[1] and shoppingListRowPool[1].seed), "For me rows have their own wobble")
    check(QRF_SavedState.notes and QRF_SavedState.notes.tasks[1].text == "Buy bigger bags", "For me: saved straight away")

    -- tick it off: it leaves "For me" and goes to the Journal, stamped; right-click there brings it back
    local nJournal = #CFQ.notes.journal
    f.fly = nil
    r1:GetScript("OnClick")(r1, "LeftButton")
    local done = CFQ.notes.journal[#CFQ.notes.journal]
    check(#CFQ.notes.tasks == 0 and not r1.__shown, "For me: a ticked task leaves Near me")
    check(#CFQ.notes.journal == nJournal + 1 and done.text == "Done: Buy bigger bags", "For me: ...and goes to the Journal as \"Done: ...\" (" .. tostring(done and done.text) .. ")")
    check(type(done.when) == "string" and done.when:find("%d+ %a%a%a %d%d:%d%d") and type(done.t) == "number" and done.place and done.place.zone ~= nil,
        "For me: ...stamped with the time and place it was done")
    check(done.doneTask and done.doneTask.text == "Buy bigger bags" and done.doneTask.when == t1.when and done.doneTask.place == t1.place,
        "For me: ...keeping the task as it was written")
    check(f.fly ~= nil and f.flyFS and f.flyFS.__text == "Done: Buy bigger bags", "For me: ...its words fly off to the Journal tab")
    check(QRF_SavedState.notes.journal[#QRF_SavedState.notes.journal].text == "Done: Buy bigger bags" and #QRF_SavedState.notes.tasks == 0, "For me: ticking is saved straight away")
    P.TaskBackFromJournal(done)
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Buy bigger bags" and not CFQ.notes.tasks[1].done
        and CFQ.notes.tasks[1].when == t1.when and #CFQ.notes.journal == nJournal, "For me: right-click the Done entry: back to For me, as written")
    r1 = f.forMeRows[1]
    check(r1.__shown and r1.itemText.__text == "Buy bigger bags", "For me: ...and on the page again")
    f.fly = nil

    -- Escape: nothing written
    f.forMeWrite:GetScript("OnClick")(f.forMeWrite, "LeftButton")
    f.forMeEdit:SetText("never mind this")
    f.forMeEdit:GetScript("OnEscapePressed")(f.forMeEdit)
    check(#CFQ.notes.tasks == 1 and not P.forMeEditing, "For me: Escape writes nothing")
    -- clicking away keeps what was written; "|" can't sneak in colour codes
    f.forMeWrite:GetScript("OnClick")(f.forMeWrite, "LeftButton")
    f.forMeEdit:SetText("Mine the |cffff0000copper|r")
    f.forMeEdit:GetScript("OnEditFocusLost")(f.forMeEdit)        -- at once: the opening click, not clicking away
    check(P.forMeEditing and f.forMeEdit.__shown and #CFQ.notes.tasks == 1, "For me: losing focus right as it opens keeps the box open (focus taken back)")
    NOW = NOW + 1
    f.forMeEdit:GetScript("OnEditFocusLost")(f.forMeEdit)
    check(#CFQ.notes.tasks == 2 and not CFQ.notes.tasks[2].text:find("|", 1, true), "For me: clicking away keeps it, without '|' escapes (" .. tostring(CFQ.notes.tasks[2] and CFQ.notes.tasks[2].text) .. ")")
    -- an empty line adds nothing
    f.forMeWrite:GetScript("OnClick")(f.forMeWrite, "LeftButton")
    f.forMeEdit:SetText("    ")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(#CFQ.notes.tasks == 2, "For me: a blank line adds nothing")

    -- right-click re-writes; re-writing to nothing rubs it out
    local r2 = f.forMeRows[2]
    r2:GetScript("OnClick")(r2, "RightButton")
    check(P.forMeEditing and P.forMeEditing.index == 2 and f.forMeEdit:GetText() == CFQ.notes.tasks[2].text, "For me: right-click opens it for re-writing")
    check(r2.itemText.__text == "", "For me: ...the box takes the line's place while you write")
    f.forMeEdit:SetText("Mine the copper vein")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(CFQ.notes.tasks[2].text == "Mine the copper vein" and r2.itemText.__text == "Mine the copper vein", "For me: re-written")
    r2:GetScript("OnClick")(r2, "RightButton")
    f.forMeEdit:SetText("")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(#CFQ.notes.tasks == 1, "For me: re-writing a task to nothing rubs it out")

    -- slash command keeps the player's capitals
    SlashCmdList["HANDKERQUEST"]("task Feed Gizmo the Cat")
    check(#CFQ.notes.tasks == 2 and CFQ.notes.tasks[2].text == "Feed Gizmo the Cat", "/hanky task adds a task as typed (" .. tostring(CFQ.notes.tasks[2] and CFQ.notes.tasks[2].text) .. ")")
    local nBefore = #CFQ.notes.tasks
    SlashCmdList["HANDKERQUEST"]("task")
    check(#CFQ.notes.tasks == nBefore, "/hanky task with nothing after it adds nothing")

    -- shift-click rubs out
    local realShift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    f.forMeRows[2]:GetScript("OnClick")(f.forMeRows[2], "LeftButton")
    IsShiftKeyDown = realShift
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Buy bigger bags", "For me: shift-click rubs a task out")

    -- fold away, and back
    CFQ.AddTask("Train cooking"); redraw()
    f.forMeHead:GetScript("OnClick")(f.forMeHead, "LeftButton")
    check(CFQ.notes.forMeFolded and P.PlainText(f.forMeHead.fs.__text) == "For me  · 2" and not f.forMeRows[1].__shown and not f.forMeWrite.__shown,
        "For me: clicking the heading folds it to For me · 2")
    f.forMeHead:GetScript("OnClick")(f.forMeHead, "LeftButton")
    check(not CFQ.notes.forMeFolded and f.forMeRows[1].__shown and f.forMeWrite.__shown, "For me: ...and open again")
    -- tick one more off, so the rest of these checks start from one task
    f.forMeRows[1]:GetScript("OnClick")(f.forMeRows[1], "LeftButton")
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Train cooking", "For me: the first task ticked off, the other stays")

    -- only on "Near me"
    P.RenderForMe(f, { isCurrent = false }, 0, 200, 120)
    check(not f.forMeWrite.__shown and not f.forMeRows[1].__shown and not f.forMeHead.__shown, "For me: not on other pages")
    redraw()

    -- room: with quest lines on the page, For me takes at most half of it (never less than heading + writing line)
    for k = 1, 12 do CFQ.AddTask("Task number " .. k) end
    local res = P.ForMeReserve(f, 200, 120, true)
    check(res <= 120 * P.FORME_SHARE + 0.01 and res >= P.KIND_HEADING_H, "For me: quest lines keep at least half the page (" .. res .. ")")
    redraw()
    check(f.forMeHead.hiddenCount > 0 and P.PlainText(f.forMeHead.fs.__text):find("^For me  · %+%d+$"), "For me: tasks that don't fit are counted on the heading (" .. tostring(f.forMeHead.fs.__text) .. ")")
    local lastShown
    for _, row in ipairs(f.forMeRows) do if row.__shown then lastShown = row end end
    check(lastShown and lastShown.itemText.__text == CFQ.notes.tasks[#CFQ.notes.tasks].text,
        "For me: when they don't all fit, the newest stays in sight (" .. tostring(lastShown and lastShown.itemText.__text) .. ")")
    check(f.forMeHead.__py <= -P.FORME_GAP and f.forMeHead.__py >= -ContentH(), "For me: the heading stays on the page")

    -- open tasks keep the tally up with no quest lines anywhere; "hide when nothing is nearby" still puts it away
    local empty = { { items = {} } }
    check(not P.ShouldHideTally(empty), "For me: open tasks keep the tally up with no quests")
    CFQ.parchmentOpts.hideWhenNothingNearby = true
    check(P.ShouldHideTally(empty), "For me: ...but 'only when something is nearby' still hides it")
    CFQ.parchmentOpts.hideWhenNothingNearby = false
    for _, t in ipairs(CFQ.notes.tasks) do t.done = true end
    check(P.ShouldHideTally(empty), "For me: only open tasks count (all ticked: hidden as before)")
    for _, t in ipairs(CFQ.notes.tasks) do t.done = false end
    CFQ.parchmentOpts.forMe = false
    check(P.ShouldHideTally(empty), "For me switched off: tasks don't hold the tally up")
    check(P.ForMeReserve(f, 200, 120, true) == 0, "For me switched off: no room kept")
    redraw()
    check(not f.forMeWrite.__shown and not f.forMeHead.__shown, "For me switched off: nothing drawn")
    CFQ.parchmentOpts.forMe = true
    redraw()

    -- a row ticks its own task even if the list shifted under it before the redraw
    CFQ.notes.tasks = {}
    CFQ.AddTask("One"); CFQ.AddTask("Two"); CFQ.AddTask("Three"); redraw()
    local row3 = f.forMeRows[3]
    table.remove(CFQ.notes.tasks, 1)            -- (as a re-write to nothing would, a frame before the redraw)
    row3:GetScript("OnClick")(row3, "LeftButton")
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Two" and CFQ.notes.journal[#CFQ.notes.journal].text == "Done: Three",
        "For me: a row ticks its own task after the list shifted")
    CFQ.AddTask("Four"); CFQ.AddTask("Five")

    -- saved and loaded back (reload); a task ticked under the old rule (stayed struck) moves to the Journal
    local nJ = #CFQ.notes.journal
    CFQ.notes.tasks[1].done = true
    CFQ.notes.forMeFolded = true
    P.ForMeChanged()
    Fire("ADDON_LOADED", "Handkerquest")
    check(#CFQ.notes.tasks == 2 and CFQ.notes.tasks[1].text == "Four" and not CFQ.notes.tasks[1].done and CFQ.notes.forMeFolded,
        "For me: tasks and the fold survive a reload")
    check(CFQ.notes.tasks[1].place and CFQ.notes.tasks[1].place.zone ~= nil, "For me: ...with where they were written")
    local moved
    for _, e in ipairs(CFQ.notes.journal) do if e.text == "Done: Two" then moved = e end end
    check(#CFQ.notes.journal == nJ + 1 and moved and moved.doneTask and moved.doneTask.text == "Two" and moved.when ~= nil,
        "For me: an old ticked task moves to the Journal on loading")
    local back
    for _, e in ipairs(CFQ.notes.journal) do if e.text == "Done: Three" then back = e end end
    check(back and back.doneTask and back.doneTask.text == "Three" and back.doneTask.place and back.doneTask.place.zone ~= nil,
        "For me: a Done entry keeps its task through a reload")
    -- a broken save loads what it can
    QRF_SavedState.notes = { tasks = { "junk", { text = 5 }, { text = "" }, { text = "Keep me", done = "yes", place = "here" } }, forMeFolded = "no" }
    Fire("ADDON_LOADED", "Handkerquest")
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Keep me" and CFQ.notes.tasks[1].done == false
        and CFQ.notes.tasks[1].place == nil and CFQ.notes.forMeFolded == false, "For me: a broken save loads what it can")
    QRF_SavedState.notes = "nonsense"
    Fire("ADDON_LOADED", "Handkerquest")
    check(type(CFQ.notes) == "table" and #CFQ.notes.tasks == 0, "For me: a nonsense save gives an empty list")
    CFQ.notes = { tasks = {}, forMeFolded = false }
    CFQ.parchmentOpts.forMe = false
    f:SetSize(fw0, fh0)
    redraw()
end
do  -- a task ticked off, in the Journal: "Done: ..." with a ticked box after its stamp; right-click = back to For me
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    f:SetSize(320, 420)
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.journalFilter = nil
    CFQ.AddEntry("An older note")
    CFQ.AddTask("Sell the wolf pelts")
    check(CFQ.CompleteTask(1) ~= nil and #CFQ.notes.tasks == 0, "Done task: CompleteTask takes it off For me")
    SlashCmdList["HANDKERQUEST"]("journal")
    local row = f.journalRows[1]
    check(row.__shown and row.text.__text == "Done: Sell the wolf pelts" and row.stamp.__text == P.EntryStamp(CFQ.notes.journal[2]),
        "Done task: newest in the Journal, stamped (" .. tostring(row.stamp.__text) .. ")")
    check(row.mark and row.mark.__shown and row.mark.glyphKind == "done", "Done task: a ticked box after its stamp")
    check(not (f.journalRows[2].mark and f.journalRows[2].mark.__shown), "Done task: ...your own notes get no mark")
    row:GetScript("OnClick")(row, "RightButton")
    check(#CFQ.notes.tasks == 1 and CFQ.notes.tasks[1].text == "Sell the wolf pelts" and #CFQ.notes.journal == 1,
        "Done task: right-click in the Journal puts it back on For me")
    f.journalRows[1]:GetScript("OnClick")(f.journalRows[1], "RightButton")
    check(P.journalEditing and P.journalEditing.entry == CFQ.notes.journal[1], "Done task: right-click on an ordinary note still opens it for writing")
    P.CancelJournalEdit()
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    CFQ.parchmentOpts.forMe = false
    P.selectedKey = P.areas[1] and P.areas[1].key
    f:SetSize(fw0, fh0)
    P.OnTallyChoiceChanged()
end
do  -- Journal: longer entries, newest first, on the last page of the pile
    local function redraw() P.OnTallyChoiceChanged() end
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    f:SetSize(320, 420)
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.journalFilter = nil
    P.selectedKey = P.areas[1].key
    redraw()
    local last = P.areas[#P.areas]
    check(last and last.isJournal and last.key == P.JOURNAL_KEY, "Journal: the last page of the pile")
    check(f.corner.__shown, "Journal: the dog-ear is there to turn to it")

    -- /hanky journal opens it
    SlashCmdList["HANDKERQUEST"]("journal")
    check(P.selectedKey == P.JOURNAL_KEY and f:IsShown() and P.PlainText(f.titleFS.__text) == "Journal", "/hanky journal opens the Journal page (" .. tostring(f.titleFS.__text) .. ")")
    check(f.journalWrite.__shown and f.journalWrite.fs.__text == "write your first note...", "Journal: an empty journal invites a first note")
    check(f.journalRows[1].__shown and f.journalRows[1].text.__text:find("empty"), "Journal: says it's empty")
    check(not (f.forMeHead and f.forMeHead.__shown) and not (f.forMeWrite and f.forMeWrite.__shown), "Journal: no For me section on the Journal page")
    check(not (shoppingListRowPool and shoppingListRowPool[1] and shoppingListRowPool[1].__shown), "Journal: no quest lines on it")

    -- write one on the page: a multi-line box under the writing line
    f.journalWrite:GetScript("OnClick")(f.journalWrite, "LeftButton")
    local eb = f.journalEdit
    check(P.journalEditing and eb and eb.__shown and eb.__font ~= nil, "Journal: clicking the line opens a writing box (with its font)")
    eb:SetText("Met a gnome in the mine.\nShe sold me a torch.")
    eb:GetScript("OnEnterPressed")(eb)
    local e1 = CFQ.notes.journal[1]
    check(#CFQ.notes.journal == 1 and e1.text == "Met a gnome in the mine.\nShe sold me a torch.", "Journal: Enter keeps the entry, lines and all")
    check(not P.journalEditing and not eb.__shown, "Journal: the box closes after Enter")
    check(type(e1.when) == "string" and e1.place and e1.place.zone and type(e1.t) == "number" and e1.owner, "Journal: stamped with time, place and who")
    local r1 = f.journalRows[1]
    check(r1.__shown and r1.text.__text == e1.text and r1.stamp.__text == P.EntryStamp(e1), "Journal: the entry under its stamp (" .. tostring(r1.stamp.__text) .. ")")
    check(r1.stamp.__text:find(e1.when, 1, true) and r1.stamp.__text:find(P.EntryPlaceName(e1), 1, true), "Journal: the stamp has the time and the place")

    -- Shift-Enter: a new line, still writing; Enter where the client already broke the line: no stray break
    f.journalWrite:GetScript("OnClick")(f.journalWrite, "LeftButton")
    local realShift = IsShiftKeyDown
    local inserted
    eb.Insert = function(self, s) inserted = s; self.__text = self.__text .. s end
    IsShiftKeyDown = function() return true end
    eb:SetText("First line")
    eb:GetScript("OnEnterPressed")(eb)
    IsShiftKeyDown = realShift
    check(P.journalEditing and inserted == "\n" and #CFQ.notes.journal == 1, "Journal: Shift-Enter starts a new line and keeps writing")
    eb:SetText("Hel\nlo there")
    eb.GetCursorPosition = function() return 4 end              -- the client put a break in for Enter
    eb:GetScript("OnEnterPressed")(eb)
    eb.GetCursorPosition = nil; eb.Insert = nil
    check(#CFQ.notes.journal == 2 and CFQ.notes.journal[2].text == "Hello there", "Journal: Enter keeps it without the client's stray line break (" .. tostring(CFQ.notes.journal[2] and CFQ.notes.journal[2].text) .. ")")

    -- newest first
    check(f.journalRows[1].text.__text == "Hello there" and f.journalRows[2].text.__text == e1.text, "Journal: newest entry first")
    check(f.footerFS.__text:find("^2 notes"), "Journal: the footer counts notes (" .. tostring(f.footerFS.__text) .. ")")

    -- Escape writes nothing; clicking away keeps it
    f.journalWrite:GetScript("OnClick")(f.journalWrite, "LeftButton")
    eb:SetText("never mind")
    eb:GetScript("OnEscapePressed")(eb)
    check(#CFQ.notes.journal == 2 and not P.journalEditing, "Journal: Escape writes nothing")
    f.journalWrite:GetScript("OnClick")(f.journalWrite, "LeftButton")
    eb:SetText("Clicked away |cffff0000here|r")
    eb:GetScript("OnEditFocusLost")(eb)
    check(P.journalEditing and eb.__shown and #CFQ.notes.journal == 2, "Journal: losing focus right as it opens keeps the box open (focus taken back)")
    NOW = NOW + 1
    eb:GetScript("OnEditFocusLost")(eb)
    check(#CFQ.notes.journal == 3 and not CFQ.notes.journal[3].text:find("|", 1, true), "Journal: clicking away keeps it, no '|' escapes")
    for _, t in ipairs(TIMERS or {}) do t() end; TIMERS = {}

    -- click an entry: write more; to nothing: rubbed out
    local top = f.journalRows[1]
    top:GetScript("OnClick")(top, "LeftButton")
    check(P.journalEditing and P.journalEditing.entry == CFQ.notes.journal[3] and eb:GetText() == CFQ.notes.journal[3].text and top.text.__text == "",
        "Journal: clicking an entry opens it for writing more, in its place")
    eb:SetText("Clicked away here, and more besides.")
    eb:GetScript("OnEnterPressed")(eb)
    check(CFQ.notes.journal[3].text == "Clicked away here, and more besides.", "Journal: written longer")
    top:GetScript("OnClick")(top, "LeftButton")
    eb:SetText("")
    eb:GetScript("OnEnterPressed")(eb)
    check(#CFQ.notes.journal == 2, "Journal: written down to nothing = rubbed out")
    IsShiftKeyDown = function() return true end
    f.journalRows[1]:GetScript("OnClick")(f.journalRows[1], "LeftButton")
    IsShiftKeyDown = realShift
    check(#CFQ.notes.journal == 1 and CFQ.notes.journal[1] == e1, "Journal: shift-click rubs an entry out")

    -- the place filter: click a stamp's place
    local a = CFQ.AddEntry("In the mine"); a.place = { zone = "Elwynn Forest", subzone = "Fargodeep Mine" }
    local b = CFQ.AddEntry("At the inn"); b.place = { zone = "Elwynn Forest", subzone = "Goldshire" }
    redraw()
    local mineRow
    for _, row in ipairs(f.journalRows) do if row.__shown and row.text.__text == "In the mine" then mineRow = row end end
    check(mineRow and mineRow.stampBtn.__shown, "Journal: the place in a stamp is clickable")
    mineRow.stampBtn:GetScript("OnClick")(mineRow.stampBtn)
    local shownTexts = {}
    for _, row in ipairs(f.journalRows) do if row.__shown then table.insert(shownTexts, row.text.__text) end end
    check(P.journalFilter == "Fargodeep Mine" and #shownTexts == 1 and shownTexts[1] == "In the mine",
        "Journal: clicking a place shows only what was written there (" .. table.concat(shownTexts, " / ") .. ")")
    check(P.PlainText(f.titleFS.__text):find("Fargodeep Mine", 1, true) and f.footerFS.__text:find("in Fargodeep Mine", 1, true),
        "Journal: the heading and footer say which place")
    f.journalRows[1].stampBtn:GetScript("OnClick")(f.journalRows[1].stampBtn)
    check(P.journalFilter == nil and f.footerFS.__text:find("^3 notes"), "Journal: click again: every note")

    -- the oldest makes room when the journal is full
    local maxE = P.NOTE_MAX_ENTRIES
    P.NOTE_MAX_ENTRIES = 3
    CFQ.AddEntry("Fourth")
    check(#CFQ.notes.journal == 3 and CFQ.notes.journal[1] == a and CFQ.notes.journal[3].text == "Fourth", "Journal: full: the oldest entry makes room")
    P.NOTE_MAX_ENTRIES = maxE

    -- /hanky entry
    SlashCmdList["HANDKERQUEST"]("entry Saw a Murloc Wearing a Hat")
    check(CFQ.notes.journal[#CFQ.notes.journal].text == "Saw a Murloc Wearing a Hat", "/hanky entry writes in the journal as typed")
    SlashCmdList["HANDKERQUEST"]("note Fizz Owes Me")
    check(CFQ.notes.journal[#CFQ.notes.journal].text == "Fizz Owes Me", "/hanky note writes a note as typed")
    do  -- bare "/hanky note": says how to use it (it used to open the tracker's filter menu)
        local nJ, said = #CFQ.notes.journal, nil
        local realPrint = print
        print = function(s) said = s end
        SlashCmdList["HANDKERQUEST"]("note")
        print = realPrint
        check(#CFQ.notes.journal == nJ and said and said:find("/hanky note <text>", 1, true), "bare /hanky note explains itself (" .. tostring(said) .. ")")
    end

    -- the tally stays up while you read the Journal, even with nothing to gather anywhere
    local realHide = P.ShouldHideUnfiltered
    P.ShouldHideUnfiltered = function() return true end
    redraw()
    check(f:IsShown() and P.selectedKey == P.JOURNAL_KEY, "Journal: the tally stays up while it's open")
    P.SelectArea(P.areas[1].key)
    check(not f:IsShown(), "Journal: ...but Near me with nothing on it is put away as before")
    P.ShouldHideUnfiltered = realHide
    P.selectedKey = P.JOURNAL_KEY
    redraw()

    -- walking into a new area never turns the page away from what you're writing
    f.journalWrite:GetScript("OnClick")(f.journalWrite, "LeftButton")
    local sub0 = SUBZONE
    SUBZONE = "Somewhere Else"
    CFQ.parchmentOpts.autoFrontOnAreaChange = true
    P.CheckAreaChange(f)
    frames(40)
    check(P.selectedKey == P.JOURNAL_KEY and P.journalEditing, "Journal: a new area doesn't turn the page while you write")
    eb:GetScript("OnEscapePressed")(eb)
    SUBZONE = sub0
    P.CheckAreaChange(f); frames(40)
    P.selectedKey = P.areas[1].key
    redraw()

    -- "For me": "write a note" goes to the Journal (flying off to the page corner)
    local wl, nl = f.forMeWrite, f.forMeNote
    local nTasks, nEntries = #CFQ.notes.tasks, #CFQ.notes.journal
    nl:GetScript("OnClick")(nl, "LeftButton")
    check(P.forMeEditing and CFQ.notes.writeMode == "entry" and wl.mode.glyphKind == "entry" and not nl.__shown,
        "For me: 'write a note' opens the box with a quill in front (the choices step aside)")
    f.forMeEdit:SetText("Fizz owes me a copper")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(#CFQ.notes.tasks == nTasks and #CFQ.notes.journal == nEntries + 1 and CFQ.notes.journal[#CFQ.notes.journal].text == "Fizz owes me a copper",
        "For me: an entry goes to the Journal, not the tasks")
    check(f.fly and f.flyFS.__shown and f.flyFS.__text == "Fizz owes me a copper", "For me: the entry flies off to the page corner")
    local c = f.corner
    frames(60)
    check(not f.fly and not f.flyFS.__shown, "For me: ...and lands")
    check(c.size > P.CORNER_REST or c.target == P.CORNER_REST, "For me: the corner flicks as it lands")
    check(nl.__shown and wl.mode.glyphKind == "task", "For me: back to the two choices after writing")
    -- 'add a task' always starts a task, whatever was written last
    wl:GetScript("OnClick")(wl, "LeftButton")
    check(CFQ.notes.writeMode == "task" and wl.mode.glyphKind == "task", "For me: 'add a task' starts a task")
    f.forMeEdit:GetScript("OnEscapePressed")(f.forMeEdit)
    -- switching while typing keeps you writing
    nl:GetScript("OnClick")(nl, "LeftButton")
    f.forMeEdit:SetText("half a thought")
    NOW = NOW + 1
    wl.mode.IsMouseOver = function() return true end
    f.forMeEdit:GetScript("OnEditFocusLost")(f.forMeEdit)
    check(P.forMeEditing and #CFQ.notes.journal == nEntries + 1, "For me: clicking the switch while typing doesn't end the writing")
    wl.mode:GetScript("OnClick")(wl.mode)
    wl.mode.IsMouseOver = nil
    check(CFQ.notes.writeMode == "task" and P.forMeEditing, "For me: ...it just switches (now a task)")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(#CFQ.notes.tasks == nTasks + 1 and CFQ.notes.tasks[#CFQ.notes.tasks].text == "half a thought", "For me: ...and Enter keeps it as a task")

    -- saved and loaded back
    CFQ.notes.writeMode = "entry"
    P.ForMeChanged()
    local nJ = #CFQ.notes.journal
    Fire("ADDON_LOADED", "Handkerquest")
    check(#CFQ.notes.journal == nJ and CFQ.notes.writeMode == "entry" and CFQ.notes.journal[1].place, "Journal: entries and the switch survive a reload")
    QRF_SavedState.notes = { journal = { 7, { text = false }, { text = "ok", place = { zone = 5, subzone = "Goldshire" } } }, writeMode = "bogus" }
    Fire("ADDON_LOADED", "Handkerquest")
    check(#CFQ.notes.journal == 1 and CFQ.notes.journal[1].text == "ok" and CFQ.notes.journal[1].place.zone == nil
        and CFQ.notes.journal[1].place.subzone == "Goldshire" and CFQ.notes.writeMode == "task", "Journal: a broken save loads what it can")

    -- switched off: no Journal page
    CFQ.parchmentOpts.forMe = false
    redraw()
    check(not P.areas[#P.areas].isJournal, "Journal: no page with For me switched off")
    local said
    local realPrint = print
    print = function(s) said = s end
    SlashCmdList["HANDKERQUEST"]("journal")
    print = realPrint
    check(said and said:find("For me", 1, true) and P.selectedKey ~= P.JOURNAL_KEY, "/hanky journal with it off: says how to switch it on")

    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.journalFilter = nil
    f:SetSize(fw0, fh0)
    P.selectedKey = P.areas[1].key
    redraw()
end
do  -- Tabs: the two quick tabs, cut from the sheet itself (Near me above Journal, right edge)
    local function redraw() P.OnTallyChoiceChanged() end
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    local look0 = CFQ.parchmentStyle
    f:SetSize(320, 420)
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    CFQ.parchmentStyle = "RAG"; P.ApplyStyle()
    P.selectedKey = P.areas[1].key
    P.tabBack = nil
    redraw()
    local near, jt = f.tabs and f.tabs.near, f.tabs and f.tabs.journal
    check(near and jt and near.__shown and jt.__shown, "Tabs: both shown with For me on")
    local st = P.GetStyle()
    check(near.tex.__tex == st.image and jt.tex.__tex == st.image, "Tabs: cut from the sheet's own image (the very same rag)")
    check(not f.knots, "Tabs: no knots any more")

    -- under the top sheet, sticking out of its right edge, below the close button, Near me above Journal
    check(near.__level < f.topSheet.__level and near.__level > f.backSheets[1].__level, "Tabs: tucked under the top sheet, above the pages underneath")
    local _, padT = P.GetPads(f)
    check(near.y >= padT + 20 and jt.y >= near.y + P.TAB_H, "Tabs: below the close button, Near me above the Journal")
    local function right(T) return T.x0 + T.width end
    check(near.edgeX > f:GetWidth() * 0.85 and right(near) > near.edgeX + P.TAB_OUT - 1, "Tabs: they stick out past the sheet's right edge")
    -- the strip's material edge lands P.TAB_OUT (+ open) past the sheet's edge: its right end = edge + 4 + out
    check(math.abs(right(near) - (near.edgeX + 4 + near.out)) < 0.01 and math.abs(right(jt) - (jt.edgeX + 4 + jt.out)) < 0.01,
        "Tabs: each is the sheet's edge moved out by exactly its reach")
    local tc = near.tex.__tc
    check(tc and math.abs(tc[3] - near.y / f:GetHeight()) < 1e-6 and math.abs((tc[2] - tc[1]) * f:GetWidth() - near.width) < 1e-6,
        "Tabs: the strip is the sheet's own rows at that height, unstretched")
    check(near.open and not jt.open and near.out == P.TAB_OUT + P.TAB_OPEN and jt.out == P.TAB_OUT, "Tabs: the open page's tab sticks out further")
    check(jt.tex.__vc and jt.tex.__vc[1] < 1 and near.tex.__vc[1] == 1, "Tabs: a closed tab sits a shade back")
    -- only the part sticking out takes the mouse
    check(near.glyph.__points[1] and near.strokes[1] and near.strokes[1].main.__shown, "Tabs: each has its inked glyph")

    -- hover slides it out a little, then back
    jt:GetScript("OnEnter")(jt)
    check(jt.slideTo == P.TAB_HOVER and f.tabsMoving, "Tabs: hover slides it out")
    frames(30)
    check(math.abs(jt.slide - P.TAB_HOVER) < 0.06, "Tabs: ...out")
    jt:GetScript("OnLeave")(jt)
    frames(30)
    check(jt.slide == 0 and not f.tabsMoving, "Tabs: ...and back")

    -- click: turn to the page; again: back where you were
    jt:GetScript("OnClick")(jt, "LeftButton")
    frames(60)
    check(P.selectedKey == P.JOURNAL_KEY and jt.open and not near.open, "Tabs: the quill tab turns to the Journal (and is now the open one)")
    jt:GetScript("OnClick")(jt, "LeftButton")
    frames(60)
    check(P.selectedKey == P.CURRENT_KEY, "Tabs: on the Journal, its tab turns back where you were")
    jt:GetScript("OnClick")(jt, "LeftButton"); frames(60)
    near:GetScript("OnClick")(near, "LeftButton"); frames(60)
    check(P.selectedKey == P.CURRENT_KEY, "Tabs: the compass tab turns to Near me")
    local farKey
    for _, a in ipairs(P.areas) do if not a.isCurrent and not a.isJournal then farKey = a.key break end end
    if farKey then
        P.SelectArea(farKey); P.tabBack = nil
        near:GetScript("OnClick")(near, "LeftButton"); frames(60)
        near:GetScript("OnClick")(near, "LeftButton"); frames(60)
        check(P.selectedKey == farKey, "Tabs: on Near me, its tab turns back to the area page you came from")
    end
    near:GetScript("OnClick")(near, "LeftButton"); frames(60)

    -- a note flies into the Journal tab, which gives a tug
    P.selectedKey = P.areas[1].key; redraw()
    f.forMeNote:GetScript("OnClick")(f.forMeNote, "LeftButton")
    f.forMeEdit:SetText("Into the tab")
    f.forMeEdit:GetScript("OnEnterPressed")(f.forMeEdit)
    check(f.fly ~= nil, "Tabs: a note flies off")
    frames(50)
    check(not f.fly and (jt.slide > 0 or jt.slideTo == 0), "Tabs: ...and the Journal tab tugs as it lands")
    frames(60)

    -- every look: image looks cut from their image; drawn looks in their paper colour
    for _, look in ipairs({ "CRUMPLED", "STONE", "BARK", "LEAF", "LEATHER", "MARBLE", "GILDED", "VELLUM", "ARCANE" }) do
        CFQ.parchmentStyle = look; P.ApplyStyle(); redraw()
        local s2 = P.GetStyle()
        check(near.__shown and near.tex.__tex == s2.image and near.edgeX > 0 and near.edgeX <= f:GetWidth(), "Tabs: " .. look .. " cut from its own image")
    end
    CFQ.parchmentStyle = "HANDKERCHIEF"; P.ApplyStyle(); redraw()
    local pp = P.GetStyle().paper
    check(near.tex.__color and math.abs(near.tex.__color[1] - pp[1]) < 1e-6, "Tabs: the handkerchief's tabs are its own colour")

    -- the edge measurements: a column with no material borrows the nearest one that has it
    check(P.EdgeAt({ 0.998, 0.10, 0.20, 0.998 }, 0) == 0.10 and math.abs(P.EdgeAt({ 0.1, 0.3 }, 0.5) - 0.2) < 1e-9,
        "Tabs: edge lookup skips rows with no material and blends between samples")

    -- switched off: no tabs
    CFQ.parchmentOpts.forMe = false
    redraw()
    check(not jt.__shown and not near.__shown, "Tabs: none with For me switched off")

    CFQ.parchmentStyle = look0; P.ApplyStyle()
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.tabBack = nil
    f:SetSize(fw0, fh0)
    P.selectedKey = P.areas[1].key
    redraw()
end
do  -- Auto entries: the Journal writes down the achievements you earn (off by default; only if the client has them)
    local function redraw() P.OnTallyChoiceChanged() end
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    f:SetSize(320, 420)
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.journalFilter = nil
    P.selectedKey = P.areas[1].key
    redraw()
    check(CFQ.achievementEvent == true and CFQ.AchievementsSupported(), "Achievements: this client has them, the event is registered")
    check(CFQ.parchmentOpts.autoAchievements == false, "Achievements: off by default")
    check(CFQ.achievementCheck and CFQ.achievementCheck.label.__text:find("achievements you earn", 1, true), "Achievements: the switch is in the options, under For me")

    -- off: nothing written
    Fire("ACHIEVEMENT_EARNED", 6, false)
    check(#CFQ.notes.journal == 0, "Achievements: off writes nothing")

    -- on: one entry, stamped like the player's own, marked as auto
    CFQ.achievementCheck:SetChecked(true)
    CFQ.achievementCheck:GetScript("OnClick")(CFQ.achievementCheck)
    check(CFQ.parchmentOpts.autoAchievements == true and QRF_SavedState.parchmentOpts.autoAchievements == true, "Achievements: the switch turns it on (and saves)")
    local realTime = GetServerTime
    local clock = 1794350400
    GetServerTime = function() return clock end
    Fire("ACHIEVEMENT_EARNED", 6, false)
    local e = CFQ.notes.journal[1]
    check(#CFQ.notes.journal == 1 and e.text == "Earned the achievement \"Level 10\" (10 points)." and e.auto == "achievement",
        "Achievements: earning one writes it in the Journal (" .. tostring(e and e.text) .. ")")
    check(type(e.when) == "string" and e.place and e.place.zone and e.owner and e.achievements[1].id == 6, "Achievements: stamped with time, place and who")

    -- within a few minutes, same place: the same entry; told twice: once
    clock = clock + 120
    Fire("ACHIEVEMENT_EARNED", 891, false)
    Fire("ACHIEVEMENT_EARNED", 891, false)
    check(#CFQ.notes.journal == 1 and e.text == "Earned 2 achievements: \"Level 10\" and \"Giddy Up!\" (20 points).",
        "Achievements: two close together share a note (" .. tostring(e.text) .. ")")
    -- guild achievements aren't yours; colour codes are stripped from names
    Fire("ACHIEVEMENT_EARNED", 5362, false)
    check(#CFQ.notes.journal == 1 and #e.achievements == 2, "Achievements: a guild's achievement isn't written down")
    clock = clock + 60
    Fire("ACHIEVEMENT_EARNED", 42, false)
    check(not e.text:find("|", 1, true) and e.achievements[3] and e.achievements[3].name == "Pipe Dream"
        and not e.achievements[3].name:find("|", 1, true), "Achievements: no colour codes in a name (" .. tostring(e.achievements[3].name) .. ")")
    -- later: a new entry
    clock = clock + P.AUTO_MERGE + 1
    Fire("ACHIEVEMENT_EARNED", 503, false)
    check(#CFQ.notes.journal == 2 and CFQ.notes.journal[2].text == "Earned the achievement \"50 Quests Completed\" (10 points).", "Achievements: minutes later, a note of its own")
    -- re-written by the player: never added to
    local e2 = CFQ.notes.journal[2]
    e2.text = "My fiftieth! Party at the inn."
    clock = clock + 10
    Fire("ACHIEVEMENT_EARNED", 891, false)
    check(#CFQ.notes.journal == 3 and e2.text == "My fiftieth! Party at the inn.", "Achievements: a note you re-wrote is never added to")
    -- another place: a new entry
    local zone0 = SUBZONE
    SUBZONE = "Fargodeep Mine"
    clock = clock + 10
    Fire("ACHIEVEMENT_EARNED", 6, false)
    check(#CFQ.notes.journal == 4 and P.EntryPlaceName(CFQ.notes.journal[4]) == "Fargodeep Mine", "Achievements: somewhere else, a note of its own")
    SUBZONE = zone0
    -- an unknown achievement: nothing, no error
    local n0 = #CFQ.notes.journal
    Fire("ACHIEVEMENT_EARNED", 99999, false)
    Fire("ACHIEVEMENT_EARNED", nil)
    check(#CFQ.notes.journal == n0, "Achievements: an unknown one writes nothing")
    GetServerTime = realTime

    -- drawn in faded ink with a small star; your own notes in the ink, no star
    CFQ.AddEntry("Bought a pie.")
    SlashCmdList["HANDKERQUEST"]("journal")
    local st = P.GetStyle()
    local rows = f.journalRows
    local mine, auto = rows[1], rows[2]
    check(mine.text.__text == "Bought a pie." and not (mine.mark and mine.mark.__shown), "Achievements: your own note has no star")
    check(auto.mark and auto.mark.__shown and auto.mark.strokes and #auto.mark.strokes == 5, "Achievements: an auto note has a small inked star")
    local c = auto.text.__textColor or auto.text.__color
    check(c and math.abs(c[1] - st.faded[1]) < 1e-6 and math.abs(c[2] - st.faded[2]) < 1e-6, "Achievements: an auto note is in faded ink")
    -- its tooltip names what was earned
    local said = {}
    local realAdd = GameTooltip.AddLine
    GameTooltip.AddLine = function(self, s, ...) said[#said + 1] = tostring(s); return realAdd(self, s, ...) end
    rows[3]:GetScript("OnEnter")(rows[3])
    GameTooltip.AddLine = realAdd
    local all = table.concat(said, "\n")
    check(all:find("Giddy Up!", 1, true) and all:find("Learn the riding skill.", 1, true) and all:find("when you earned it", 1, true),
        "Achievements: the tooltip lists them with what they were for")

    -- it survives a reload, star and all
    P.ForMeChanged()
    Fire("ADDON_LOADED", "Handkerquest")
    local back = CFQ.notes.journal[1]
    check(back.auto == "achievement" and #back.achievements == 3 and back.achievements[2].name == "Giddy Up!" and back.autoText == back.text,
        "Achievements: kept between logins")
    check(CFQ.notes.journal[#CFQ.notes.journal].auto == nil, "Achievements: your own notes stay your own after a reload")
    check(CFQ.parchmentOpts.autoAchievements == true, "Achievements: the switch is kept between logins")

    -- For me off: nothing written (the Journal is part of it)
    CFQ.parchmentOpts.forMe = false
    local n1 = #CFQ.notes.journal
    Fire("ACHIEVEMENT_EARNED", 503, false)
    check(#CFQ.notes.journal == n1, "Achievements: nothing written while For me is off")

    -- a client without achievements: not offered
    local realGet = GetAchievementInfo
    GetAchievementInfo = nil
    check(not CFQ.AchievementsSupported(), "Achievements: a client without them doesn't offer it")
    check(CFQ.OnAchievementEarned(6) == nil, "Achievements: ...and writes nothing, no error")
    GetAchievementInfo = realGet

    CFQ.parchmentOpts.autoAchievements = false
    CFQ.parchmentOpts.forMe = false
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    f:SetSize(fw0, fh0)
    P.selectedKey = P.areas[1].key
    redraw()
end
do  -- Auto entries: the quests you turn in, and what they gave you
    local function redraw() P.OnTallyChoiceChanged() end
    local fw0, fh0 = f:GetWidth(), f:GetHeight()
    f:SetSize(320, 420)
    CFQ.parchmentOpts.forMe = true
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    P.journalFilter = nil
    P.selectedKey = P.areas[1].key
    redraw()
    check(CFQ.questTurnInEvent == true, "Quests: the turn-in event is registered")
    check(CFQ.parchmentOpts.autoQuests == false, "Quests: off by default")
    check(CFQ.questCheck and CFQ.questCheck.label.__text:find("quests you turn in", 1, true), "Quests: the switch is in the options, under For me")

    local function turnIn(panel, choice, id, xp, money)
        QUEST_PANEL = panel
        if panel then Fire("QUEST_COMPLETE") end
        if panel then GetQuestReward(choice) end          -- the hooked call the Complete button makes
        QUEST_PANEL = nil
        Fire("QUEST_TURNED_IN", id, xp, money)
    end
    local panel1 = { id = 101, title = "Recipe of the Kaldorei", rewards = { { "Linen Cloth", 2, 1, 2589 } },
        choices = { { "Woodland Shield", 1, 2, 5395 }, { "Hunting Bow", 1, 2, 2504 } } }

    -- off: nothing written
    turnIn(panel1, 2, 101, 450, 150)
    check(#CFQ.notes.journal == 0, "Quests: off writes nothing")

    CFQ.questCheck:SetChecked(true)
    CFQ.questCheck:GetScript("OnClick")(CFQ.questCheck)
    check(CFQ.parchmentOpts.autoQuests == true and QRF_SavedState.parchmentOpts.autoQuests == true, "Quests: the switch turns it on (and saves)")
    local realTime = GetServerTime
    local clock = 1794350400
    GetServerTime = function() return clock end

    -- the items always given, the one chosen, xp and money
    turnIn(panel1, 2, 101, 450, 12345)
    local e = CFQ.notes.journal[1]
    check(#CFQ.notes.journal == 1 and e.auto == "quest"
        and e.text == "Turned in \"Recipe of the Kaldorei\" and received 2 Linen Cloth, Hunting Bow, 450 xp and 1g 23s 45c.",
        "Quests: turning one in writes it with what it gave (" .. tostring(e and e.text) .. ")")
    check(e.quests[1].id == 101 and e.quests[1].items[2].name == "Hunting Bow" and e.quests[1].items[2].link
        and not e.text:find("Woodland Shield", 1, true), "Quests: only the reward you chose")
    check(type(e.when) == "string" and e.place and e.owner, "Quests: stamped with time, place and who")

    -- close together: one note, a line each; one to choose from is given without a choice; told twice: once
    clock = clock + 60
    turnIn({ id = 102, title = "Webwood Venom", rewards = {}, choices = { { "Webwood Gloves", 1, 2, 9999 } } }, 0, 102, 300, 0)
    Fire("QUEST_TURNED_IN", 102, 300, 0)
    check(#CFQ.notes.journal == 1 and e.text == "Turned in 2 quests:\n\"Recipe of the Kaldorei\": 2 Linen Cloth, Hunting Bow, 450 xp and 1g 23s 45c.\n\"Webwood Venom\": Webwood Gloves and 300 xp.",
        "Quests: two close together share a note, a line each (" .. tostring(e.text) .. ")")

    -- a quest that completes itself (no reward panel): its name from the quest log, xp and money only
    clock = clock + 60
    turnIn(nil, nil, 103, 0, 75)
    check(#e.quests == 3 and e.text:find("\"Denalan's Earth\": 75c.", 1, true), "Quests: no reward panel: xp and money only, name from the log")
    -- a reward panel read for another quest isn't used
    clock = clock + 60
    QUEST_PANEL = { id = 555, title = "Some Other Quest", rewards = { { "Wrong Thing", 1, 1, 1 } }, choices = {} }
    Fire("QUEST_COMPLETE"); QUEST_PANEL = nil
    Fire("QUEST_TURNED_IN", 101, 10, 0)
    check(not e.text:find("Wrong Thing", 1, true) and not e.text:find("Some Other Quest", 1, true), "Quests: another quest's rewards are never written in")
    -- no name anywhere: nothing written, no error
    local n0 = #CFQ.notes.journal
    local q0 = #e.quests
    Fire("QUEST_TURNED_IN", 424242, 10, 0)
    Fire("QUEST_TURNED_IN", nil, nil, nil)
    check(#CFQ.notes.journal == n0 and #e.quests == q0, "Quests: one with no name writes nothing")

    -- later: a note of its own; achievements and quests never share one
    clock = clock + P.AUTO_MERGE + 1
    turnIn({ id = 102, title = "Webwood Venom", rewards = {}, choices = {} }, 0, 102, 0, 0)
    check(#CFQ.notes.journal == 2 and CFQ.notes.journal[2].text == "Turned in \"Webwood Venom\".", "Quests: nothing received: just the quest")
    CFQ.parchmentOpts.autoAchievements = true
    clock = clock + 5
    Fire("ACHIEVEMENT_EARNED", 6, false)
    check(#CFQ.notes.journal == 3 and CFQ.notes.journal[3].auto == "achievement", "Quests: an achievement gets a note of its own")
    CFQ.parchmentOpts.autoAchievements = false
    GetServerTime = realTime

    -- drawn like the achievement notes; the tooltip lists the quests and what each gave
    SlashCmdList["HANDKERQUEST"]("journal")
    local rows = f.journalRows
    local qrow = rows[3]
    check(qrow.mark and qrow.mark.__shown, "Quests: a quest note has the small star")
    local said = {}
    local realAdd = GameTooltip.AddLine
    GameTooltip.AddLine = function(self, s, ...) said[#said + 1] = tostring(s); return realAdd(self, s, ...) end
    qrow:GetScript("OnEnter")(qrow)
    GameTooltip.AddLine = realAdd
    local all = table.concat(said, "\n")
    check(all:find("when you turned it in", 1, true) and all:find("Recipe of the Kaldorei", 1, true) and all:find("Hunting Bow", 1, true)
        and all:find("450 xp, 1g 23s 45c", 1, true), "Quests: the tooltip lists each quest and what it gave")

    -- kept between logins
    P.ForMeChanged()
    Fire("ADDON_LOADED", "Handkerquest")
    local back = CFQ.notes.journal[1]
    check(back.auto == "quest" and #back.quests == 3 and back.quests[1].items[2].name == "Hunting Bow" and back.quests[1].money == 12345
        and back.autoText == back.text, "Quests: kept between logins")
    check(CFQ.parchmentOpts.autoQuests == true, "Quests: the switch is kept between logins")

    -- For me off: nothing written
    CFQ.parchmentOpts.forMe = false
    local n1 = #CFQ.notes.journal
    turnIn(panel1, 1, 101, 1, 1)
    check(#CFQ.notes.journal == n1, "Quests: nothing written while For me is off")
    check(P.MoneyText(10000) == "1g" and P.MoneyText(205) == "2s 5c" and P.MoneyText(0) == "", "Quests: money reads as g / s / c")

    CFQ.parchmentOpts.autoQuests = false
    CFQ.notes = { tasks = {}, journal = {}, forMeFolded = false, writeMode = "task" }
    f:SetSize(fw0, fh0)
    P.selectedKey = P.areas[1].key
    redraw()
end
do  -- every look survives a reload (sanctified marble / gilded plate / illuminated vellum used to fall back to the rag)
    local before = CFQ.parchmentStyle
    for _, key in ipairs({ "MARBLE", "GILDED", "VELLUM", "LEATHER" }) do
        QRF_SavedState.parchmentStyle = key
        Fire("ADDON_LOADED", "Handkerquest")
        check(CFQ.parchmentStyle == key, key .. " is still the look after a reload")
    end
    QRF_SavedState.parchmentStyle = "BOGUS"
    Fire("ADDON_LOADED", "Handkerquest")
    check(CFQ.parchmentStyle == "VELLUM" or CFQ.parchmentStyle == "LEATHER", "an unknown saved look leaves the look alone")
    CFQ.parchmentStyle = before; QRF_SavedState.parchmentStyle = before; P.ApplyStyle()
end
do  -- the .toc loads files that exist (code file renamed Handkerquest.lua -> Handkerchief.lua -> HandkerSheaf.lua; folder/.toc kept)
    local toc = io.open(here .. "/Handkerquest.toc")
    local listed, missing = {}, {}
    if toc then
        for line in toc:lines() do
            line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
            if line ~= "" and not line:match("^#") then
                listed[#listed + 1] = line
                local fh = io.open(here .. "/" .. line:gsub("\\", "/"))
                if fh then fh:close() else missing[#missing + 1] = line end
            end
        end
        toc:close()
    end
    check(toc and #listed > 0 and #missing == 0, "Handkerquest.toc lists only files that exist (" .. #listed .. " listed, missing: " .. table.concat(missing, ", ") .. ")")
    check(listed[1] == "HandkerSheaf.lua", "Handkerquest.toc loads HandkerSheaf.lua")
end
check(#ERRORS == 0, "no Lua errors reported (" .. #ERRORS .. ")")
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
