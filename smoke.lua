local here = (arg[0]:match("^(.*)[/\\]") or ".")
dofile(here .. "/wowmock.lua")
local addonPath = arg[1] or (here .. "/../CacheForQuest.lua")

-- Expose the addon's locals to the test (test copy only)
local src = assert(io.open(addonPath), "cannot open " .. addonPath):read("*a") .. "\n_G.__CFQ = CFQ\n_G.__LAYOUT = function() LayoutObjectiveTrackerWithStacks() end\n_G.__STATE = function() return { lvl = levelSortMode, dist = distSortMode, primary = primarySortKey, incomp = incompleteStackEnabled, turnin = turnInStackEnabled } end\n"
local chunk = assert(loadstring(src, "CacheForQuest.lua"))
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

Fire("ADDON_LOADED", "CacheForQuest")
Fire("PLAYER_ENTERING_WORLD")
for _, t in ipairs(TIMERS or {}) do t() end; TIMERS = {}

local f = QRF_ClusterShoppingList
check(f ~= nil, "parchment frame exists")
check(f:IsShown(), "parchment shown with nearby quantity quests")

-- 1) Redundant "/N" fix
local foundBad, foundGood, foundKill, foundEvent = false, false, false, false
for _, fr in ipairs(allFrames) do
    if fr.__kind == "FontString" and type(fr.__text) == "string" and fr.__shown ~= false then
        if fr.__text:find("%d/%d+|r  |cFF2B1A0C/%d") or fr.__text:find(" /6 ") or fr.__text:find(" /1 ") then foundBad = true end
        if fr.__text:find("1/7|r  |cFF2B1A0CSmall Spider Leg") then foundGood = true end
        if fr.__text:find("Gnarlpine Ambusher slain") then foundKill = true end
        if fr.__text:find("Cenarion Hold depths entrance") then foundEvent = true end
    end
end
check(not foundBad, "no redundant '/N' left in parchment rows")
check(foundGood, "item row reads '1/7  Small Spider Leg'")
check(not foundKill, "kill objective (monster) is not on the tally")
check(not foundEvent, "exploration objective (event) is not on the tally")
check(#CFQ.P.FlattenQuests({ { questID = 1, quantityObjectives = { {}, {} }, itemObjectives = { { itemName = "x" } } } }) == 1, "FlattenQuests uses item objectives only")
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
    if fr.__kind == "FontString" and fr.__shown ~= false and fr.__text == "15/15  Gnarlpine Fang" then fangRow = fr end
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

-- default position: BOTTOMLEFT above chat
local pt, _, relPt = f:GetPoint(1)
check(pt == "BOTTOMLEFT" and relPt == "BOTTOMLEFT", "default anchor bottom-left above chat (got " .. tostring(pt) .. ")")

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

-- 5) Sorting
SlashCmdList["CACHEFORQUEST"]("dist")
local st = __STATE()
check(st.dist == "ASC" and st.primary == "DIST", "dist cycles to ASC and becomes primary")
SlashCmdList["CACHEFORQUEST"]("lvl")
st = __STATE()
check(st.lvl == "ASC" and st.primary == "LVL", "lvl cycles to ASC and becomes primary")
check(CFQ.GetSortSummary():find("^lvl"), "summary leads with primary sort")
SlashCmdList["CACHEFORQUEST"]("lvl"); SlashCmdList["CACHEFORQUEST"]("lvl")
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

-- /cfq debug dump runs cleanly
local printed = 0
local realPrint = print
print = function(...) printed = printed + 1 end
local okDbg, errDbg = pcall(SlashCmdList["CACHEFORQUEST"], "debug")
print = realPrint
check(okDbg, "/cfq debug runs without error: " .. tostring(errDbg))
check(printed >= 3, "/cfq debug prints the tracker state")

-- 7) Options panel
SlashCmdList["CACHEFORQUEST"]("options")
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
for _, w in ipairs(CFQ.optionWidgets) do if type(w.__text) == "string" and w.__text:find("^Area pages by: ") then gBtn = w end end
check(gBtn ~= nil and gBtn.__text == "Area pages by: Map areas", "options show Area pages by: Map areas")
if gBtn then
    gBtn:GetScript("OnClick")(gBtn)
    check(gBtn.__text == "Area pages by: Zones", "grouping button cycles to Zones")
    gBtn:GetScript("OnClick")(gBtn); gBtn:GetScript("OnClick")(gBtn)
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

-- ticker with distance sort
SlashCmdList["CACHEFORQUEST"]("dist")
for _ = 1, 4 do TICKER() end

check(#ERRORS == 0, "no Lua errors reported (" .. #ERRORS .. ")")
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
