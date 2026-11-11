-- ============================================================================
-- HandkerSheaf.lua (the Handkerquest addon) - WoW Forever Edition
-- "Don't go off on an adventure without your handkerchief." (the name: handkerchief + quest)
-- Objective Tracker sorting, filters & (?)/(•••) quest stacks, plus the Field Tally:
-- a handwritten list (on a torn rag, soft hide, slate, bark, a pipe-weed leaf, glowing arcane script and
-- more) of the quest items still to gather and the tasks still to do, with a map preview on hover and
-- minimap pins.
--
-- Internal names use the old "Cache ForQuest" prefixes (CFQ, QRF_). Keep them: renaming
-- QRF_SavedState would reset everyone's saved settings.
--
-- WHERE TO MAKE SIMPLE CHANGES (search for the name):
--   Default settings (what's on/off for new players) .... CFQ = { parchmentOpts = ... }
--   Default tally size / position ........................ shoppingListCfg
--   Tally colours, borders and each look ................ P.STYLES
--   Paper / rag / stone / bark / leaf / leather / arcane  textures\ (made by tools\TexGen.cs)
--   Items / tasks / tasks-apart toggles by the gear ..... P.QUICK_GLYPHS, P.QUICK_SIZE
--   Handwriting fonts and their sizes ................... P.FONT_STYLES (text size slider: P.TEXT_SCALE_MIN/MAX)
--   Ink drops of "Blotted scrawl" ........................ P.SetInkDrops, textures\ink_blots
--   Gap between the tally and the chat box .............. P.PILE_MARGIN_X / P.PILE_MARGIN_Y
--   How many rows / pages the tally shows ............... MAX_SHOPPING_ROWS, P.MAX_AREAS
--   "Hunting grounds" distances (glow) .................. P.HUNT_SPOT_RADIUS, P.HUNT_POI_RADIUS
--   When a mob stops counting as a possible dropper ..... P.RULE_OUT_LOOTS
--   Hover map size ...................................... P.PREVIEW_W, P.PREVIEW_H
--   Frames the hover map avoids covering ................ P.AVOID_FRAMES
--   Minimap pins (how many) ............................. P.MAX_MINIMAP_PINS
--   Button / header texts ............................... CONFIG (just below)
-- ============================================================================
-- EDIT: names and labels shown on the filter buttons and menu headers
local CONFIG = {
    ADDON_NAME          = "Handkerquest",   -- internal: folder / .toc / ADDON_LOADED. Never change (players' settings)
    DISPLAY_NAME        = "HandkerSheaf",   -- the name players see (options panel, Settings list, chat)
    REWARD_BTN_ALL      = "Rewards: All",
    LEVEL_BTN_ALL       = "Levels: All",
    TRACKER_BTN_ALL     = "Filter: All",
    HEADER_REWARDS      = "Available Rewards:",
    HEADER_LEVELS       = "Quest Level Filter:",
    collapseRightOffset = -65,
}
-- ============================================================================

local ICON_ARROW_UP   = "|TInterface\\Buttons\\UI-MicroStream-Yellow:11:11:0:0:32:32:6:26:26:6|t"
local ICON_ARROW_DOWN = "|TInterface\\Buttons\\UI-MicroStream-Yellow:11:11:0:0:32:32:6:26:6:26|t"
local CIRCLE_MASK_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local selectedFilters = {}          -- Reward filter IDs
local selectedLevelFilters = {}     -- Level filter IDs ("TIER_*", "LVL_*")
local levelSortMode = "NONE"        -- "NONE", "ASC", or "DESC"
local distSortMode = "NONE"         -- "NONE", "ASC" (nearest first), or "DESC" (farthest first)
local primarySortKey = "LVL"        -- "LVL" or "DIST": whichever sort was switched on most recently wins ties

-- Settings and shared state. EDIT: the true/false values below are the defaults a new player
-- starts with (each can also be switched in Options > AddOns > HandkerSheaf).
-- Add new settings to this table rather than as new "local" lines: Lua allows only 200 locals here.
local CFQ = {
    parchmentOpts = {
        showTabs = true,                -- more pages for quests that aren't near you, one per place
        pagesFollowTracker = true,      -- "Clusters" pages: cluster size follows the tracker's (•••) stacking slider
        autoFrontOnAreaChange = true,   -- turn back to the "Near me" page when you enter a new area
        hideWhenNothingNearby = false,  -- put the tally away when the "Near me" page has nothing to gather or do
        showTrackerOptionsButton = true,-- gear button above "All Objectives"
        inkEffects = true,              -- tally text glows in an item's hunting grounds / burns for a mob that drops it
        mapPreview = true,              -- hovering a tally item shows a little map of where it's gathered
        minimapPins = true,             -- looted-here spots of the super-tracked quest's items on the minimap
        tallyLoot = true,               -- the tally lists quest items to gather...
        tallyTasks = true,              -- ...and tasks: enemies to slay / other quest steps
        tallySeparate = false,          -- tasks under their own heading, after the items
    },
    parchmentFont = "QUILL",            -- handwriting on the parchment: "QUILL", "SCRAWL", "PLAIN" or "BLOTTED" (P.FONT_STYLES)
    parchmentStyle = "RAG",             -- the tally's look: "RAG", "CRUMPLED", "STONE", "BARK", "LEAF", "LEATHER", "ARCANE", "HANDKERCHIEF", "PARCHMENT" or "NATIVE"
    huntSpots = {},                     -- [progKey] = { { m = mapID, x, y, a = subzone }, ... } where the item was looted
    learnedDroppers = {},               -- ["npc:ID"] = { label = name, loots = n, tries = {}, [progKey] = times the item dropped }
    pageRadiusPercent = 16,             -- "Clusters" pages: own cluster size (% of the zone map) when not following the tracker
    nearRadiusPercent = 10,             -- "Near me" page: how close (% of the zone map) the items must be
    tallyTextScale = 100,               -- the tally's writing size, % of the usual (options slider, 80-150)
    arcaneRuneColor = nil,              -- Arcane script: { r, g, b } of the rune circle & its glow (nil = the look's violet)
    inkColors = {},                     -- [look key] = { r, g, b } writing colour chosen for that look (missing = its own)
    pageGrouping = "AREA",              -- other pages by "AREA" (map areas), "ZONE" or "RADIUS" (clusters)
    learnedQuestAreas = {},             -- [questID] = "Subzone name" where the quest's objectives were last worked
    stackHiddenRegistry = setmetatable({}, { __mode = "k" }), -- every native tracker frame we have hidden
    reportedErrors = {},
    sortCycleButtons = {},
    optionWidgets = {},
}

local turnInStackEnabled = true     -- (?) Turn-in quest stacking toggle (Objective Tracker only)
local turnInRadiusPercent = 16      -- 1% to 50% of zone map
local incompleteStackEnabled = false-- (•••) Incomplete quest stacking toggle (Objective Tracker only)
local incompleteRadiusPercent = 16  -- 1% to 50% of zone map

local showShoppingList = true       -- the Field Tally is shown
local shoppingListScope = "AREA"    -- no longer used (still written to the save, never read)
-- EDIT: width / height are the tally's default size in pixels (also what "Reset Position & Size" uses)
local shoppingListCfg = {
    width = 230,
    height = 175,
    point = "BOTTOMLEFT",
    relPoint = "BOTTOMLEFT",
    x = 36,
    y = 250,
    useDefaultAnchor = true,        -- true = sit just above the chat box (recomputed from ChatFrame1)
}

local activeMenuTab = "REWARDS"     -- "REWARDS" or "LEVELS"

local collapsedCategories = {}
local knownRewardMeta = {}
local knownLevelMeta = {}
local cachedQuestCoords = {}        -- [questID] = { mapID = number, x = number, y = number }

local autoUntrack = true
local showCategories = true
local showMapBadges = false         -- Default FALSE: Keep map clean & show in Tooltip Popup instead
local filterMapPins = true
local mapFilterHideMode = false

local availableRewards = {}
local availableLevelFilters = {}
local dropdownDisplayList = {}
local questRewardMap = {}
local questTitleLookup = {}         -- [lowerCleanTitle] = qData (for Map Tooltip matching)
local clusterGroupsMap = {}         -- [clusterID] = { id, zone, isComplete, quests = { qData, ... } }
local matchingQuestsList = {}

local recentActiveQuests = {}       -- [questID] = timestamp when objective progressed or mob targeted
local prevObjectiveProgress = {}    -- [questID .. "_" .. objIdx] = numFulfilled
local flashObjectiveUntil = {}      -- [questID .. "_" .. objIdx] = GetTime() + 2.0 (the row flashes until then)

local dropdownRowPool = {}
local customListRowPool = {}
local trackerStackDeckPool = {}
local shoppingListRowPool = {}

local savedWatchedQuests = nil
local isSyncingTracker = false
local isReorderingTrackerUI = false
local lastWatchOrderSignature = ""
local lastCompletionSignature = ""
local lastSelectedQuestID = nil

local nativeTitleFont, nativeTitleSize, nativeTitleFlags = nil, nil, nil
local nativeLineFont, nativeLineSize, nativeLineFlags = nil, nil, nil

local customScrollOffset = 0
local dropdownScrollOffset = 0
local shoppingScrollOffset = 0
local dropdownSearchText = ""

-- EDIT: list limits (quest log rows, filter-menu rows, quests per tracker stack, tally rows)
local MAX_CUSTOM_ROWS = 11
local MAX_DROPDOWN_ROWS = 12
local MAX_CARDS_PER_STACK = 8
local MAX_SHOPPING_ROWS = 18

local sharedMenuFrame = nil
local questLogBar = nil
local trackerFilterBtn = nil
local trackerControlBar = nil
local shoppingListFrame = nil

local LayoutObjectiveTrackerWithStacks
local ScanQuestLogRewards
local SyncObjectiveTracker
local UpdateShoppingListUI

local CATEGORY_NAMES = {
    [1] = "Seasonal & Event",
    [2] = "Currencies",
    [3] = "Reputation & Renown",
    [4] = "Items & Caches",
    [5] = "Gear & Money",
}

local LEVEL_CATEGORY_NAMES = {
    [101] = "Recommended Difficulty",
    [102] = "Exact Quest Levels",
}

local SEASONAL_CURRENCY_IDS = {
    [241]  = true, [515]  = true, [1166] = true, [2032] = true,
    [2588] = true, [2778] = true, [3100] = true,
}

local SEASONAL_ITEM_IDS = {
    [21100]  = true, [23247]  = true, [33226]  = true, [37829]  = true,
    [44791]  = true, [49927]  = true, [116415] = true, [211515] = true,
}

local SEASONAL_KEYWORDS = {
    "tricky treat", "darkmoon", "timewarped", "brewfest", "love token",
    "coin of ancestry", "burning blossom", "noblegarden", "winter veil",
    "midsummer", "hallow", "spooky", "pilgrim", "lunar festival",
    "celebration token", "anniversary", "trial of style", "trader's tender",
    "community coupon", "prize ticket", "prize token", "riders of azeroth",
    "holiday", "festival"
}

-- ============================================================================
-- STRING SANITIZATION & GRADIENT HELPERS
-- ============================================================================
local function StripLeadingLevelTag(str)
    if not str then return "" end
    local s = string.gsub(str, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = string.gsub(s, "^%s*%[%d+[^%]]*%]%s*", "")
    return strtrim(s)
end

local function ApplyHorizontalGradient(tex, r, g, b, leftAlpha, rightAlpha)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, leftAlpha), CreateColor(r, g, b, rightAlpha))
    else
        tex:SetColorTexture(r, g, b, leftAlpha)
    end
end

local function ApplyTwoColorVerticalGradient(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    else
        tex:SetColorTexture(r1, g1, b1, a1)
    end
end

-- ============================================================================
-- POLISHED ROUND NATIVE POI ICON BUILDER (? & •••)
-- ============================================================================
local function CreateRoundQuestPOI(parent, size, isComplete, isBackLayer, dimFactor)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.isComplete = isComplete
    f.isBackLayer = isBackLayer
    f.dimFactor = dimFactor or 1.0

    local function AddCircleMask(tex)
        local m = f:CreateMaskTexture()
        m:SetAllPoints(tex)
        m:SetTexture(CIRCLE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        tex:AddMaskTexture(m)
    end

    local outerRim = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    outerRim:SetAllPoints()
    outerRim:SetColorTexture(0.10, 0.07, 0.02, 0.98)
    AddCircleMask(outerRim)
    f.outerRim = outerRim

    local ring = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    ring:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    ring:SetColorTexture(0.86, 0.68, 0.20, 1.0)
    AddCircleMask(ring)
    f.ring = ring

    local innerRim = f:CreateTexture(nil, "BORDER", nil, 2)
    innerRim:SetPoint("TOPLEFT", f, "TOPLEFT", 2.5, -2.5)
    innerRim:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2.5, 2.5)
    innerRim:SetColorTexture(0.12, 0.05, 0.02, 0.98)
    AddCircleMask(innerRim)
    f.innerRim = innerRim

    local bg = f:CreateTexture(nil, "ARTWORK", nil, 0)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 3.5, -3.5)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3.5, 3.5)
    bg:SetColorTexture(0.28, 0.08, 0.04, 0.98)
    AddCircleMask(bg)
    f.bg = bg

    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local fontSize = math.max(11, math.floor(size * 0.60))

    local qShadow = f:CreateFontString(nil, "OVERLAY", nil, 1)
    qShadow:SetPoint("CENTER", f, "CENTER", 1, -1)
    qShadow:SetFont(fontPath, fontSize, "")
    qShadow:SetText("?")
    f.qShadow = qShadow

    local qMark = f:CreateFontString(nil, "OVERLAY", nil, 2)
    qMark:SetPoint("CENTER", f, "CENTER", 0, 0)
    qMark:SetFont(fontPath, fontSize, "")
    qMark:SetText("?")
    f.qMark = qMark

    f.dots = {}
    local dotSize = math.max(2.2, math.floor(size * 0.12))
    local spacing = math.max(3.8, math.floor(size * 0.22))
    for i = 1, 3 do
        local offsetX = (i - 2) * spacing
        local d = f:CreateTexture(nil, "OVERLAY", nil, 2)
        d:SetSize(dotSize, dotSize)
        d:SetPoint("CENTER", f, "CENTER", offsetX, 0)
        d:SetColorTexture(1.0, 0.84, 0.18, 1.0)
        f.dots[i] = d
    end

    function f:SetVisualState(completeState, isSelected)
        self.isComplete = completeState
        local dim = self.dimFactor or 1.0

        if completeState then
            self.qMark:Show()
            self.qShadow:Show()
            for i = 1, 3 do self.dots[i]:Hide() end
        else
            self.qMark:Hide()
            self.qShadow:Hide()
            for i = 1, 3 do self.dots[i]:Show() end
        end

        if self.isBackLayer then
            self.outerRim:SetColorTexture(0.06, 0.04, 0.01, 0.95)
            self.ring:SetColorTexture(0.68 * dim, 0.54 * dim, 0.16 * dim, 0.95)
            self.innerRim:SetColorTexture(0.10, 0.04, 0.02, 0.95)
            self.bg:SetColorTexture(0.20 * dim, 0.06 * dim, 0.03 * dim, 0.96)
            self.qShadow:SetTextColor(0, 0, 0, 0.8)
            self.qMark:SetTextColor(0.85 * dim, 0.70 * dim, 0.18 * dim, 0.90)
            for i = 1, 3 do
                self.dots[i]:SetColorTexture(0.85 * dim, 0.72 * dim, 0.22 * dim, 0.90)
            end
        elseif isSelected then
            self.outerRim:SetColorTexture(0.18, 0.12, 0.02, 1.0)
            self.ring:SetColorTexture(1.0, 0.92, 0.42, 1.0)
            self.innerRim:SetColorTexture(0.45, 0.30, 0.04, 0.98)
            self.bg:SetColorTexture(1.0, 0.82, 0.08, 1.0)
            self.qShadow:SetTextColor(1.0, 0.95, 0.55, 0.60)
            self.qMark:SetTextColor(0.20, 0.07, 0.01, 1.0)
            for i = 1, 3 do
                self.dots[i]:SetColorTexture(0.20, 0.07, 0.01, 1.0)
            end
        else
            self.outerRim:SetColorTexture(0.10, 0.07, 0.02, 0.98)
            self.ring:SetColorTexture(0.84, 0.67, 0.20, 0.98)
            self.innerRim:SetColorTexture(0.12, 0.04, 0.02, 0.98)
            self.bg:SetColorTexture(0.28, 0.08, 0.04, 0.98)
            self.qShadow:SetTextColor(0.04, 0.01, 0.0, 0.95)
            self.qMark:SetTextColor(1.0, 0.84, 0.12, 1.0)
            for i = 1, 3 do
                self.dots[i]:SetColorTexture(1.0, 0.84, 0.18, 1.0)
            end
        end
    end

    f:SetVisualState(isComplete, false)
    return f
end

-- ============================================================================
-- STATE PERSISTENCE
-- ============================================================================
local function SaveState()
    QRF_SavedState = QRF_SavedState or {}
    QRF_SavedState.selectedFilters = selectedFilters
    QRF_SavedState.selectedLevelFilters = selectedLevelFilters
    QRF_SavedState.levelSortMode = levelSortMode
    QRF_SavedState.turnInStackEnabled = turnInStackEnabled
    QRF_SavedState.turnInRadiusPercent = turnInRadiusPercent
    QRF_SavedState.incompleteStackEnabled = incompleteStackEnabled
    QRF_SavedState.incompleteRadiusPercent = incompleteRadiusPercent
    QRF_SavedState.activeMenuTab = activeMenuTab
    QRF_SavedState.collapsedCategories = collapsedCategories
    QRF_SavedState.knownRewardMeta = knownRewardMeta
    QRF_SavedState.knownLevelMeta = knownLevelMeta
    QRF_SavedState.cachedQuestCoords = cachedQuestCoords
    QRF_SavedState.savedWatchedQuests = savedWatchedQuests
    QRF_SavedState.autoUntrack = autoUntrack
    QRF_SavedState.showCategories = showCategories
    QRF_SavedState.showMapBadgesV2 = showMapBadges
    QRF_SavedState.filterMapPins = filterMapPins
    QRF_SavedState.mapFilterHideMode = mapFilterHideMode
    QRF_SavedState.showShoppingList = showShoppingList
    QRF_SavedState.shoppingListScope = shoppingListScope
    QRF_SavedState.parchmentFont = CFQ.parchmentFont
    QRF_SavedState.pageRadiusPercent = CFQ.pageRadiusPercent
    QRF_SavedState.nearRadiusPercent = CFQ.nearRadiusPercent
    QRF_SavedState.tallyTextScale = CFQ.tallyTextScale
    QRF_SavedState.arcaneRuneColor = CFQ.arcaneRuneColor
    QRF_SavedState.inkColors = CFQ.inkColors
    QRF_SavedState.arcaneInkColor = nil    -- an earlier test build: now inkColors.ARCANE
    QRF_SavedState.pageGrouping = CFQ.pageGrouping
    QRF_SavedState.tallySort = nil          -- line-order setting from a v2.2 preview build: no longer used
    QRF_SavedState.shoppingListCfg = shoppingListCfg
    QRF_SavedState.lastSelectedQuestID = lastSelectedQuestID
    QRF_SavedState.distSortMode = distSortMode
    QRF_SavedState.primarySortKey = primarySortKey
    QRF_SavedState.parchmentOpts = CFQ.parchmentOpts
    QRF_SavedState.learnedQuestAreas = CFQ.learnedQuestAreas
    QRF_SavedState.parchmentStyle = CFQ.parchmentStyle
    QRF_SavedState.huntSpots = CFQ.huntSpots
    QRF_SavedState.learnedDroppers = CFQ.learnedDroppers
end

-- A saved { r, g, b } (each 0-1), or nil if it's missing or broken
function CFQ.ValidColor(c)
    if type(c) ~= "table" then return nil end
    local out = {}
    for k = 1, 3 do
        if type(c[k]) ~= "number" or c[k] ~= c[k] then return nil end
        out[k] = math.max(0, math.min(1, c[k]))
    end
    return out
end

local function LoadState()
    if type(QRF_SavedState) == "table" then
        selectedFilters = QRF_SavedState.selectedFilters or {}
        selectedLevelFilters = QRF_SavedState.selectedLevelFilters or {}
        for k in pairs(selectedLevelFilters) do
            if string.find(tostring(k), "^CLUSTER_") then
                selectedLevelFilters[k] = nil
            end
        end
        if QRF_SavedState.levelSortMode then
            levelSortMode = QRF_SavedState.levelSortMode
        end
        if QRF_SavedState.turnInStackEnabled ~= nil then
            turnInStackEnabled = QRF_SavedState.turnInStackEnabled
        end
        if type(QRF_SavedState.turnInRadiusPercent) == "number" then
            turnInRadiusPercent = math.max(1, math.min(50, QRF_SavedState.turnInRadiusPercent))
        end
        if QRF_SavedState.incompleteStackEnabled ~= nil then
            incompleteStackEnabled = QRF_SavedState.incompleteStackEnabled
        end
        if type(QRF_SavedState.incompleteRadiusPercent) == "number" then
            incompleteRadiusPercent = math.max(1, math.min(50, QRF_SavedState.incompleteRadiusPercent))
        end
        activeMenuTab = QRF_SavedState.activeMenuTab or "REWARDS"
        collapsedCategories = QRF_SavedState.collapsedCategories or {}
        knownRewardMeta = QRF_SavedState.knownRewardMeta or {}
        knownLevelMeta = QRF_SavedState.knownLevelMeta or {}
        cachedQuestCoords = QRF_SavedState.cachedQuestCoords or {}
        savedWatchedQuests = QRF_SavedState.savedWatchedQuests
        if QRF_SavedState.autoUntrack ~= nil then autoUntrack = QRF_SavedState.autoUntrack end
        if QRF_SavedState.showCategories ~= nil then showCategories = QRF_SavedState.showCategories end
        if QRF_SavedState.showMapBadgesV2 ~= nil then showMapBadges = QRF_SavedState.showMapBadgesV2 end
        if QRF_SavedState.filterMapPins ~= nil then filterMapPins = QRF_SavedState.filterMapPins end
        if QRF_SavedState.mapFilterHideMode ~= nil then mapFilterHideMode = QRF_SavedState.mapFilterHideMode end
        if QRF_SavedState.showShoppingList ~= nil then showShoppingList = QRF_SavedState.showShoppingList end
        if type(QRF_SavedState.parchmentFont) == "string" then CFQ.parchmentFont = QRF_SavedState.parchmentFont end
        if QRF_SavedState.pageGrouping == "AREA" or QRF_SavedState.pageGrouping == "ZONE" or QRF_SavedState.pageGrouping == "RADIUS" then
            CFQ.pageGrouping = QRF_SavedState.pageGrouping
        end
        if type(QRF_SavedState.tallyTextScale) == "number" then
            CFQ.tallyTextScale = math.max(80, math.min(150, math.floor(QRF_SavedState.tallyTextScale + 0.5)))   -- P.TEXT_SCALE_MIN/MAX
        end
        CFQ.arcaneRuneColor = CFQ.ValidColor(QRF_SavedState.arcaneRuneColor)
        CFQ.inkColors = {}
        if type(QRF_SavedState.inkColors) == "table" then
            for k, c in pairs(QRF_SavedState.inkColors) do
                if type(k) == "string" then CFQ.inkColors[k] = CFQ.ValidColor(c) end
            end
        end
        if not CFQ.inkColors.ARCANE then CFQ.inkColors.ARCANE = CFQ.ValidColor(QRF_SavedState.arcaneInkColor) end
        if type(QRF_SavedState.nearRadiusPercent) == "number" then
            CFQ.nearRadiusPercent = math.max(1, math.min(50, math.floor(QRF_SavedState.nearRadiusPercent + 0.5)))
        end
        if type(QRF_SavedState.pageRadiusPercent) == "number" then
            CFQ.pageRadiusPercent = math.max(1, math.min(50, math.floor(QRF_SavedState.pageRadiusPercent + 0.5)))
        end
        if type(QRF_SavedState.shoppingListCfg) == "table" then
            local sc = QRF_SavedState.shoppingListCfg
            shoppingListCfg.width    = math.max(185, math.min(520, tonumber(sc.width) or 230))
            shoppingListCfg.height   = math.max(95, math.min(520, tonumber(sc.height) or 175))
            shoppingListCfg.point    = sc.point or "BOTTOMLEFT"
            shoppingListCfg.relPoint = sc.relPoint or "BOTTOMLEFT"
            shoppingListCfg.x        = tonumber(sc.x) or 36
            shoppingListCfg.y        = tonumber(sc.y) or 250
            if sc.useDefaultAnchor ~= nil then
                shoppingListCfg.useDefaultAnchor = sc.useDefaultAnchor
            else
                -- older saves: only move to the chat-side default spot if the list was never moved
                local wasOldDefault = (sc.point == "TOPRIGHT" and tonumber(sc.x) == -310 and tonumber(sc.y) == -220)
                shoppingListCfg.useDefaultAnchor = wasOldDefault or sc.point == nil
            end
        end
        if type(QRF_SavedState.lastSelectedQuestID) == "number" then
            lastSelectedQuestID = QRF_SavedState.lastSelectedQuestID
        end
        if QRF_SavedState.distSortMode == "ASC" or QRF_SavedState.distSortMode == "DESC" then
            distSortMode = QRF_SavedState.distSortMode
        end
        if QRF_SavedState.primarySortKey == "LVL" or QRF_SavedState.primarySortKey == "DIST" then
            primarySortKey = QRF_SavedState.primarySortKey
        end
        if type(QRF_SavedState.parchmentOpts) == "table" then
            for k, v in pairs(QRF_SavedState.parchmentOpts) do
                if CFQ.parchmentOpts[k] ~= nil and type(v) == "boolean" then
                    CFQ.parchmentOpts[k] = v
                end
            end
            local po = CFQ.parchmentOpts
            if not (po.tallyLoot or po.tallyTasks) then po.tallyLoot = true end   -- never an empty tally
        end
        if type(QRF_SavedState.learnedQuestAreas) == "table" then
            CFQ.learnedQuestAreas = QRF_SavedState.learnedQuestAreas
        end
        local ps = QRF_SavedState.parchmentStyle
        if ps == "HANDKERCHIEF" or ps == "PARCHMENT" or ps == "CRUMPLED" or ps == "RAG" or ps == "STONE" or ps == "BARK" or ps == "LEAF"
            or ps == "LEATHER" or ps == "ARCANE" or ps == "NATIVE" then
            CFQ.parchmentStyle = ps
        end
        if type(QRF_SavedState.huntSpots) == "table" then
            CFQ.huntSpots = QRF_SavedState.huntSpots
        end
        if type(QRF_SavedState.learnedDroppers) == "table" then
            CFQ.learnedDroppers = QRF_SavedState.learnedDroppers
        end
    end
end

-- ============================================================================
-- QUEST LEVEL, OBJECTIVES, QUANTITY PARSER & COORDINATE HELPERS
-- ============================================================================
local function GetPlayerLevelSafe()
    local lvl = UnitLevel and UnitLevel("player") or 60
    if not lvl or lvl <= 0 then lvl = 1 end
    return lvl
end

local function GetQuestDifficultyInfo(questLevel)
    local pLevel = GetPlayerLevelSafe()
    local qLevel = tonumber(questLevel) or pLevel
    if qLevel <= 0 then qLevel = pLevel end

    local diff = qLevel - pLevel
    local greenRange = 5
    if pLevel >= 40 then
        greenRange = math.floor(pLevel / 5) + 1
    elseif pLevel >= 20 then
        greenRange = math.floor(pLevel / 10) + 4
    end

    if diff >= 5 then
        return "TIER_RED", "Very Difficult (Red)", "FFFF2020", 5
    elseif diff >= 3 then
        return "TIER_ORANGE", "Difficult (Orange)", "FFFF8040", 4
    elseif diff >= -2 then
        return "TIER_YELLOW", "Optimal (Yellow)", "FFFFFF00", 3
    elseif -diff <= greenRange then
        return "TIER_GREEN", "Easy (Green)", "FF40C040", 2
    else
        return "TIER_GREY", "Trivial (Grey)", "FF909090", 1
    end
end

local function QueryQuestLevel(questID, infoTable)
    if infoTable and infoTable.level and infoTable.level > 0 then
        return infoTable.level
    end
    if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
        if ok and lvl and lvl > 0 then
            return lvl
        end
    end
    return GetPlayerLevelSafe()
end

local function IsQuestReadyForTurnIn(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then
        local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and ready ~= nil then return ready end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, comp = pcall(C_QuestLog.IsComplete, questID)
        if ok and comp then return true end
    end
    if IsQuestComplete then
        local ok, comp = pcall(IsQuestComplete, questID)
        if ok and comp then return true end
    end
    return false
end

-- Strips every count fragment ("0/1 ", "/6 ", ": 2/6", "(2/6)") from an objective so only the
-- item / mob / place name remains. Some clients send kill & exploration objectives as "/6 Name"
-- (current count missing).
function CFQ.CleanObjectiveName(text)
    if not text then return "" end
    local s = string.gsub(text, "^%s*%-+%s*", "")
    s = string.gsub(s, "^%s*%d*%s*/%s*%d+%s*[:%-]?%s*", "")
    s = string.gsub(s, "%s*%(%s*%d*%s*/%s*%d+%s*%)%s*$", "")
    s = string.gsub(s, "%s*:?%s*%d*%s*/%s*%d+%s*$", "")
    s = string.gsub(s, "%s*:%s*$", "")
    return strtrim(s)
end

-- Rebuilds a tracker sub-line with the real numbers when the raw text carries a (possibly broken) count
function CFQ.FormatObjectiveLine(text, numFulfilled, numRequired)
    if not text or text == "" then return text end
    local req = tonumber(numRequired)
    if req and req > 0 and string.find(text, "%d*%s*/%s*%d+") then
        local name = CFQ.CleanObjectiveName(text)
        if name ~= "" then
            return string.format("%d/%d %s", tonumber(numFulfilled) or 0, req, name)
        end
    end
    return text
end

-- The quest API tags every objective with a type: "item" means an item that has to be looted /
-- gathered into your bags. Everything else is a goal, not loot: "monster" (kills), "object"
-- (click / use something in the world), "event" (explore, escort, speak), "reputation",
-- "progressbar", "spell", "player", "log", ... Only "item" objectives are tally items; the rest are tasks.
-- Some clients return no type through GetQuestLogLeaderBoard; fall back to the objective's wording.
CFQ.NON_ITEM_WORDS = {
    "slain", "killed", "defeated", "destroyed", "rescued", "freed", "saved", "escorted",
    "explored", "discovered", "visited", "located", "investigated", "entrance", "speak with",
    "talk to", "used", "activated", "lit", "burned", "captured", "subdued", "tamed", "cleansed",
    "placed", "planted", "bombed", "slay", "kill", "defeat", "destroy", "protect", "reach",
    "find", "found", "search", "searched", "scout", "scouted", "escort", "inspect", "inspected",
    "examine", "examined", "observe", "observed", "witness", "witnessed", "survive", "survived",
    "defend", "defended", "complete", "completed", "deliver", "delivered", "warn", "warned",
    "interrupt", "interrupted", "visit", "slaughtered", "vanquished", "eliminated", "assassinated",
}
function CFQ.IsCollectItemObjective(objType, name)
    if objType and objType ~= "" then
        return objType == "item"
    end
    local lower = string.lower(name or "")
    if lower == "" then return false end
    for _, w in ipairs(CFQ.NON_ITEM_WORDS) do
        local s, e = string.find(lower, w, 1, true)
        if s then
            local nextCh = string.sub(lower, e + 1, e + 1)
            local before = (s == 1) or not string.find(string.sub(lower, s - 1, s - 1), "%a")
            -- "Scout's Report" is loot: a possessive is a name, not a verb
            local after = (e == string.len(lower)) or not (string.find(nextCh, "%a") or nextCh == "'")
            if before and after then return false end
        end
    end
    return true
end

-- Tally line kinds besides loot: "slay" (kill objectives) or "task" (explore, use, speak, escort, ...)
CFQ.SLAY_WORDS = { "slain", "killed", "defeated", "destroyed", "slay", "kill", "defeat", "slaughtered",
    "vanquished", "eliminated", "assassinated" }
function CFQ.ObjectiveKind(objType, name)
    if objType == "monster" then return "slay" end
    if objType and objType ~= "" then return "task" end
    local lower = string.lower(name or "")
    for _, w in ipairs(CFQ.SLAY_WORDS) do
        local s, e = string.find(lower, w, 1, true)
        if s and (s == 1 or not string.find(string.sub(lower, s - 1, s - 1), "%a"))
            and (e == string.len(lower) or not string.find(string.sub(lower, e + 1, e + 1), "%a")) then
            return "slay"
        end
    end
    return "task"
end

-- The quest's goals that aren't loot, for the tally's check-offs: every step, one-step quests included
-- ("Sit by the fire", user decision: a new character's only quest must still bring the tally up).
-- A step of one is just a box to tick (no "0/1"); a count above one keeps it ("0/6 Gnarlpine Ambusher slain").
-- qtyObjs = the counted objectives already parsed for this quest.
function CFQ.ExtractTaskObjectives(questID, logIndex, isComplete, qtyObjs)
    local raw = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objs) == "table" then
            for idx, o in ipairs(objs) do raw[idx] = { text = o.text, type = o.type, finished = o.finished } end
        end
    end
    if #raw == 0 and GetQuestLogLeaderBoard and logIndex and logIndex > 0 then
        local n = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(logIndex)) or 0
        for idx = 1, n do
            local ok, text, objType, finished = pcall(GetQuestLogLeaderBoard, idx, logIndex)
            if ok and text then raw[idx] = { text = text, type = objType, finished = finished } end
        end
    end
    local counted = {}
    for _, o in ipairs(qtyObjs or {}) do counted[o.index] = o end
    local list = {}
    for idx, r in ipairs(raw) do
        local o = counted[idx]
        if o then
            if not o.isItem then
                o.kind = CFQ.ObjectiveKind(o.objType, o.itemName)
                o.single = (o.numRequired or 1) <= 1 or nil     -- "0/1 City Gate" is just a box to tick
                table.insert(list, o)
            end
        elseif r.type ~= "item" and type(r.text) == "string" then
            -- a one-off step ("Speak with Denalan"): no count, just a box to tick
            local name = CFQ.CleanObjectiveName(strtrim(string.gsub(r.text, "^%-+%s*", "")))
            if name ~= "" then
                local done = (r.finished == true) or (isComplete == true)
                table.insert(list, { index = idx, progKey = tostring(questID) .. "_" .. tostring(idx), text = r.text,
                    itemName = name, objType = r.type, numFulfilled = done and 1 or 0, numRequired = 1,
                    finished = done, isItem = false, single = true, kind = CFQ.ObjectiveKind(r.type, name) })
            end
        end
    end
    return list
end

-- Every counted objective of a quest (items, kills, objects, ...): the tally's items and tasks come from these
local function ExtractQuestQuantityObjectives(questID, logIndex, isComplete)
    local results = {}
    local rawList = nil

    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and objs and #objs > 0 then
            rawList = objs
        end
    end

    local function ParseSingleObjective(idx, text, objType, numFulfilled, numRequired, finished)
        if not text or text == "" then return end
        local cleanText = strtrim(string.gsub(text, "^%-+%s*", ""))

        local cur, max = tonumber(numFulfilled), tonumber(numRequired)
        local itemName = cleanText

        -- Parse patterns like "0/1 Silvery Spinnerets" or "4/10 Young Nightsaber slain" or "Fel Moss: 2/6"
        local pCur, pMax, pRest = string.match(cleanText, "^(%d+)%s*/%s*(%d+)%s+(.+)$")
        if pCur and pMax and pRest then
            cur = tonumber(pCur)
            max = tonumber(pMax)
            itemName = strtrim(pRest)
        else
            local rName, rCur, rMax = string.match(cleanText, "^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
            if rName and rCur and rMax then
                cur = tonumber(rCur)
                max = tonumber(rMax)
                itemName = strtrim(rName)
            else
                -- "/6 Gnarlpine Ambusher slain" (leading count with the current value missing)
                local bareMax = string.match(cleanText, "^%s*/%s*(%d+)")
                if bareMax and not max then
                    max = tonumber(bareMax)
                end
            end
        end
        local stripped = CFQ.CleanObjectiveName(itemName)
        if stripped ~= "" then itemName = stripped end

        local isQuantityType = (objType == "monster" or objType == "item" or objType == "object" or objType == "progressbar")
        local hasCount = (max and max >= 1 and (isQuantityType or pCur ~= nil or rCur ~= nil or max > 1))

        if hasCount then
            cur = cur or 0
            local isDone = (finished == true) or (isComplete == true) or (cur >= max)
            if isDone and cur < max then cur = max end

            -- Track live tick-ups so the tally can flash newly progressed rows
            local progKey = tostring(questID) .. "_" .. tostring(idx)
            local isItem = CFQ.IsCollectItemObjective(objType, itemName)
            local prevCur = prevObjectiveProgress[progKey]
            if prevCur ~= nil and cur > prevCur then
                flashObjectiveUntil[progKey] = GetTime() + 2.0
                recentActiveQuests[questID] = GetTime()
                -- an item just went into your bags: remember where (hunting grounds) and what you looted it from
                if isItem and CFQ.OnItemProgress then pcall(CFQ.OnItemProgress, questID, progKey) end
            end
            prevObjectiveProgress[progKey] = cur

            table.insert(results, {
                index = idx,
                progKey = progKey,
                text = cleanText,
                itemName = itemName,
                objType = objType,
                numFulfilled = cur,
                numRequired = max,
                finished = isDone,
                isItem = isItem,
            })
        end
    end

    if rawList then
        for idx, obj in ipairs(rawList) do
            ParseSingleObjective(idx, obj.text, obj.type, obj.numFulfilled, obj.numRequired, obj.finished)
        end
    elseif GetQuestLogLeaderBoard and logIndex and logIndex > 0 then
        local numLB = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(logIndex) or 0
        for idx = 1, numLB do
            local ok, text, objType, finished = pcall(GetQuestLogLeaderBoard, idx, logIndex)
            if ok and text then
                ParseSingleObjective(idx, text, objType, nil, nil, finished)
            end
        end
    end

    return results
end

local function GetFirstQuestObjectiveText(questID, logIndex, isComplete, headerName)
    if isComplete then
        return string.format("Ready for turn-in (%s)", headerName or "Hub")
    end
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and objs and #objs > 0 then
            for _, obj in ipairs(objs) do
                if not obj.finished and obj.text and obj.text ~= "" then
                    return "- " .. CFQ.FormatObjectiveLine(obj.text, obj.numFulfilled, obj.numRequired)
                end
            end
            if objs[1].text and objs[1].text ~= "" then
                return "- " .. CFQ.FormatObjectiveLine(objs[1].text, objs[1].numFulfilled, objs[1].numRequired)
            end
        end
    end
    if GetQuestLogLeaderBoard and logIndex and logIndex > 0 then
        local ok, text = pcall(GetQuestLogLeaderBoard, 1, logIndex)
        if ok and text and text ~= "" then
            return "- " .. text
        end
    end
    return "- In progress (" .. (headerName or "Zone") .. ")"
end

local function IsQuestSuperTracked(questID)
    if not questID then return false end
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local stID = C_SuperTrack.GetSuperTrackedQuestID()
        if stID and stID > 0 then
            return stID == questID
        end
    end
    return lastSelectedQuestID == questID
end

local function ActivateQuestTarget(questID)
    if not questID then return end
    lastSelectedQuestID = questID
    if C_QuestLog and C_QuestLog.AddQuestWatch and not (C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil) then
        pcall(C_QuestLog.AddQuestWatch, questID)
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
    end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, questID)
    end
    SaveState()
end

-- The quest's objective area as the world map would place it (C_QuestLog.GetQuestsOnMap), on the map
-- you're on or one of its parents (Northshire -> Elwynn Forest), so a new character needn't open the
-- map first. Each map's list is read once a second at most.
CFQ.mapQuestCache = {}
function CFQ.QuestPosNearPlayer(questID)
    if not (C_Map and C_Map.GetBestMapForUnit and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    local now = GetTime()
    for _ = 1, 3 do
        if not mapID or mapID == 0 then break end
        local c = CFQ.mapQuestCache[mapID]
        if not c or now - c.t > 1 then
            c = { t = now, pos = {} }
            local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
            if ok and type(list) == "table" then
                for _, info in ipairs(list) do
                    if info.questID and info.x and info.y and (info.x > 0 or info.y > 0) then
                        c.pos[info.questID] = { info.x, info.y }
                    end
                end
            end
            CFQ.mapQuestCache[mapID] = c
        end
        local p = c.pos[questID]
        if p then return mapID, p[1], p[2] end
        local okI, info = pcall(C_Map.GetMapInfo, mapID)
        mapID = okI and info and info.parentMapID or nil
    end
    return nil
end

local function QueryQuestCoordinates(questID)
    if not questID then return nil, nil, nil end

    local activeMapID = (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID())
        or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
        if ok and mapID and x and y and (x > 0 or y > 0) then
            cachedQuestCoords[questID] = { mapID = mapID, x = x, y = y }
            return mapID, x, y
        end
    end

    do
        local mapID, x, y = CFQ.QuestPosNearPlayer(questID)
        if mapID then
            cachedQuestCoords[questID] = { mapID = mapID, x = x, y = y }
            return mapID, x, y
        end
    end

    if activeMapID and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, questID, activeMapID)
        if ok and x and y and (x > 0 or y > 0) then
            cachedQuestCoords[questID] = { mapID = activeMapID, x = x, y = y }
            return activeMapID, x, y
        end
    end

    if activeMapID and C_TaskQuest and C_TaskQuest.GetQuestLocation then
        local ok, x, y = pcall(C_TaskQuest.GetQuestLocation, questID, activeMapID)
        if ok and x and y and (x > 0 or y > 0) then
            cachedQuestCoords[questID] = { mapID = activeMapID, x = x, y = y }
            return activeMapID, x, y
        end
    end

    local cached = cachedQuestCoords[questID]
    if cached and cached.x and cached.y then
        return cached.mapID, cached.x, cached.y
    end

    return nil, nil, nil
end

local function GetPlayerMapPositionSafe()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return nil, nil, nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, nil, nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and pos and pos.GetXY then
        local x, y = pos:GetXY()
        if x and y and (x > 0 or y > 0) then
            return mapID, x, y
        end
    end
    return mapID, nil, nil
end

-- ============================================================================
-- REWARD & API HELPERS
-- ============================================================================
local function GetQuestCurrencies(questID)
    if C_QuestLog and C_QuestLog.GetQuestRewardCurrencies then
        return C_QuestLog.GetQuestRewardCurrencies(questID)
    elseif C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
        return C_QuestInfoSystem.GetQuestRewardCurrencies(questID)
    end
    return nil
end

local function GetQuestMoneyCopper(questID)
    local money = 0
    if C_QuestLog and C_QuestLog.GetRewardMoney then
        money = C_QuestLog.GetRewardMoney(questID) or 0
    elseif GetQuestLogRewardMoney then
        money = GetQuestLogRewardMoney(questID) or 0
    end
    return money
end

local function FormatMoneyBadge(copper)
    if not copper or copper <= 0 then return "" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    if gold > 0 then
        if silver > 0 and gold < 10 then
            return string.format("|cFFFFD700%dg|r|cFFC7C7CF%ds|r", gold, silver)
        end
        return string.format("|cFFFFD700%dg|r", gold)
    elseif silver > 0 then
        return string.format("|cFFC7C7CF%ds|r", silver)
    else
        return string.format("|cFFEDA55F%dc|r", cop)
    end
end

local function FormatMoneyWithIcons(copper)
    if not copper or copper <= 0 then return nil end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t |cFFFFD700%dg|r", gold))
    end
    if silver > 0 then
        table.insert(parts, string.format("|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t |cFFC7C7CF%ds|r", silver))
    end
    if cop > 0 then
        table.insert(parts, string.format("|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t |cFFEDA55F%dc|r", cop))
    end
    return table.concat(parts, " ")
end

local function GetMoneyCoinIcon(copper)
    if not copper or copper <= 0 then
        return "Interface\\MoneyFrame\\UI-GoldIcon"
    elseif copper >= 10000 then
        return "Interface\\MoneyFrame\\UI-GoldIcon"
    elseif copper >= 100 then
        return "Interface\\MoneyFrame\\UI-SilverIcon"
    else
        return "Interface\\MoneyFrame\\UI-CopperIcon"
    end
end

local function IsQuestWatched(questID)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        return C_QuestLog.GetQuestWatchType(questID) ~= nil
    end
    return false
end

local function IsItemEquipment(itemID)
    if not itemID or not C_Item or not C_Item.GetItemInfoInstant then return false end
    local _, _, _, itemEquipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
    if classID == 2 or classID == 4 then return true end
    if itemEquipLoc and itemEquipLoc ~= "" and itemEquipLoc ~= "INVTYPE_NON_EQUIP" and itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        return true
    end
    return false
end

local function IsSeasonalReward(name, currencyID, itemID)
    if currencyID and SEASONAL_CURRENCY_IDS[currencyID] then return true end
    if itemID and SEASONAL_ITEM_IDS[itemID] then return true end
    if name then
        local lower = string.lower(name)
        for _, kw in ipairs(SEASONAL_KEYWORDS) do
            if string.find(lower, kw, 1, true) then return true end
        end
    end
    return false
end

local function IsReputationReward(name, currencyID)
    if currencyID and C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency then
        local ok, factionID = pcall(C_CurrencyInfo.GetFactionGrantedByCurrency, currencyID)
        if ok and factionID and factionID > 0 then return true end
    end
    if name then
        local lower = string.lower(name)
        if string.find(lower, "reputation", 1, true) or string.find(lower, "renown", 1, true) or string.find(lower, "commendation", 1, true) then
            return true
        end
    end
    return false
end

local function GetCompactRewardString(qData, maxBadges)
    if not qData or not qData.order then return "" end
    local rCount = 0
    for _, sel in pairs(selectedFilters) do
        if sel then rCount = rCount + 1 end
    end
    local parts = {}
    local limit = maxBadges or 2
    for _, rID in ipairs(qData.order) do
        if rCount == 0 or selectedFilters[rID] then
            if #parts < limit and qData.badges[rID] then
                table.insert(parts, qData.badges[rID])
            end
        end
    end
    return table.concat(parts, " ")
end

local function GetLeftAlignedLogRewardString(qData, maxBadges)
    if not qData or not qData.order then return "" end
    local rCount = 0
    for _, sel in pairs(selectedFilters) do
        if sel then rCount = rCount + 1 end
    end
    local parts = {}
    local limit = maxBadges or 3
    for _, rID in ipairs(qData.order) do
        if rCount == 0 or selectedFilters[rID] then
            if #parts < limit then
                local str = (qData.logLineRewards and qData.logLineRewards[rID]) or qData.badges[rID]
                if str then
                    table.insert(parts, str)
                end
            end
        end
    end
    return table.concat(parts, "   ")
end

-- ============================================================================
-- FILTER COUNT, MATCHING & SORT COMPARATORS
-- ============================================================================
local function GetActiveRewardFilterCount()
    local count = 0
    for _, isSelected in pairs(selectedFilters) do
        if isSelected then count = count + 1 end
    end
    return count
end

local function GetActiveLevelFilterCount()
    local count = 0
    for _, isSelected in pairs(selectedLevelFilters) do
        if isSelected then count = count + 1 end
    end
    return count
end

local function IsAnySortActive()
    return (levelSortMode ~= "NONE") or (distSortMode ~= "NONE")
end

local function IsTrackerSortingOrClusteringActive()
    return IsAnySortActive() or turnInStackEnabled or incompleteStackEnabled
end

-- Distance sort is applied visually only; reordering the native watch list every time the
-- player takes a step would thrash QUEST_WATCH_LIST_CHANGED, so watch reordering ignores it.
local function IsWatchReorderActive()
    return (levelSortMode ~= "NONE") or turnInStackEnabled or incompleteStackEnabled
end

local function IsQuestLogOverrideActive()
    return (GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0) or IsAnySortActive()
end

-- ----------------------------------------------------------------------------
-- DISTANCE FROM PLAYER (world yards when the client can convert map coords)
-- ----------------------------------------------------------------------------
CFQ.DIST_UNKNOWN = math.huge
CFQ.DIST_SAME_ZONE = 1e7    -- no coordinates, but the quest's log header is the zone you're standing in

function CFQ.MapPosToWorld(mapID, x, y)
    if not mapID or not x or not y then return nil end
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
        if ok and continentID and worldPos and worldPos.GetXY then
            local wx, wy = worldPos:GetXY()
            if wx and wy then return continentID, wx, wy end
        end
    end
    return nil
end

CFQ.UpdateQuestDistances = function()
    local pMap, px, py = GetPlayerMapPositionSafe()
    local pCont, pwx, pwy
    if pMap and px and py then
        pCont, pwx, pwy = CFQ.MapPosToWorld(pMap, px, py)
    end
    local realZone = string.lower(strtrim((GetRealZoneText and GetRealZoneText()) or ""))

    for _, q in pairs(questRewardMap) do
        local d = CFQ.DIST_UNKNOWN
        if pMap and px and py and q.mapID and q.x and q.y then
            local qCont, qwx, qwy = CFQ.MapPosToWorld(q.mapID, q.x, q.y)
            if pCont and qCont and pCont == qCont then
                local dx, dy = qwx - pwx, qwy - pwy
                d = math.sqrt(dx * dx + dy * dy)
            elseif q.mapID == pMap then
                local dx, dy = q.x - px, q.y - py
                d = math.sqrt(dx * dx + dy * dy) * 1000   -- pseudo-yards on the same map
            end
        end
        if d == CFQ.DIST_UNKNOWN and realZone ~= "" and string.lower(q.header or "") == realZone then
            d = CFQ.DIST_SAME_ZONE
        end
        if d < CFQ.DIST_SAME_ZONE then
            d = math.floor(d / 5) * 5   -- 5-yard buckets so tiny steps don't reshuffle ties
        end
        q.distance = d
    end

    for _, cg in pairs(clusterGroupsMap) do
        local m = CFQ.DIST_UNKNOWN
        for _, q in ipairs(cg.quests) do
            if (q.distance or CFQ.DIST_UNKNOWN) < m then m = q.distance end
        end
        cg.minDistance = m
    end
end

local function GetDistanceTier(d)
    if d == nil or d == CFQ.DIST_UNKNOWN then return 2 end
    if d >= CFQ.DIST_SAME_ZONE then return 1 end
    return 0
end

-- Returns true / false when the active sorts decide the order, or nil when they tie.
local function CompareActiveSorts(aLevel, aDist, bLevel, bDist, ignoreDistance)
    local function ByLevel()
        if levelSortMode == "NONE" or aLevel == bLevel then return nil end
        if levelSortMode == "ASC" then return (aLevel or 0) < (bLevel or 0) end
        return (aLevel or 0) > (bLevel or 0)
    end
    local function ByDistance()
        if ignoreDistance or distSortMode == "NONE" then return nil end
        local ta, tb = GetDistanceTier(aDist), GetDistanceTier(bDist)
        if ta ~= tb then return ta < tb end          -- unknown distances always sink to the bottom
        if ta ~= 0 or aDist == bDist then return nil end
        if distSortMode == "ASC" then return aDist < bDist end
        return aDist > bDist
    end
    local first, second = ByLevel, ByDistance
    if primarySortKey == "DIST" then first, second = ByDistance, ByLevel end
    local r = first()
    if r ~= nil then return r end
    return second()
end

local function DoesQuestMatchRewardFilters(questID)
    local rCount = GetActiveRewardFilterCount()
    if rCount == 0 then return true end
    local qData = questRewardMap[questID]
    if not qData then return false end
    for rID, isSelected in pairs(selectedFilters) do
        if isSelected and qData.rewards[rID] then
            return true
        end
    end
    return false
end

local function DoesQuestMatchLevelFilters(questID)
    local lCount = GetActiveLevelFilterCount()
    if lCount == 0 then return true end
    local qData = questRewardMap[questID]
    if not qData then return false end
    for lID, isSelected in pairs(selectedLevelFilters) do
        if isSelected and qData.levelKeys and qData.levelKeys[lID] then
            return true
        end
    end
    return false
end

local function DoesQuestMatchFilter(questID)
    if not questRewardMap[questID] then return false end
    return DoesQuestMatchRewardFilters(questID) and DoesQuestMatchLevelFilters(questID)
end

local function IsQuestStackingEnabledFor(qData)
    if not qData then return false end
    if qData.isComplete then
        return turnInStackEnabled
    else
        return incompleteStackEnabled
    end
end

-- aDist / bDist override each side's distance (decks sort by their nearest member);
-- ignoreDistance is used when ordering the native watch list.
local function CompareQuestsForTrackerEx(a, b, aDist, bDist, ignoreDistance)
    if not a or not b then return false end
    if a.isFromMap ~= b.isFromMap then
        return not a.isFromMap
    end

    local sorted = CompareActiveSorts(a.level, aDist or a.distance, b.level, bDist or b.distance, ignoreDistance)
    if sorted ~= nil then return sorted end

    if a.clusterID ~= b.clusterID and turnInStackEnabled then
        local aTurnInStack = (a.isComplete and a.clusterSize and a.clusterSize >= 2) and 1 or 0
        local bTurnInStack = (b.isComplete and b.clusterSize and b.clusterSize >= 2) and 1 or 0
        if aTurnInStack ~= bTurnInStack then
            return aTurnInStack > bTurnInStack
        end
    end

    if a.header ~= b.header then return a.header < b.header end
    if a.level ~= b.level then return a.level < b.level end
    if (a.logIndex or 0) ~= (b.logIndex or 0) then
        return (a.logIndex or 0) < (b.logIndex or 0)
    end
    return a.questID < b.questID
end

local function CompareQuestsForTracker(a, b)
    return CompareQuestsForTrackerEx(a, b)
end

local function CompareQuestsForWatchList(a, b)
    return CompareQuestsForTrackerEx(a, b, nil, nil, true)
end

-- Used when a stack is collapsed (or finishes collapsing) so the selected quest sits on top!
local function BuildCollapsedStackQuestOrder(quests)
    local ordered = {}
    for i = 1, #quests do
        ordered[i] = quests[i]
    end
    table.sort(ordered, function(a, b)
        local aSel = IsQuestSuperTracked(a.questID)
        local bSel = IsQuestSuperTracked(b.questID)
        if aSel ~= bSel then
            return aSel
        end
        return CompareQuestsForTracker(a, b)
    end)
    return ordered
end

local function CompareQuestsForQuestLog(a, b)
    if not a or not b then return false end
    if a.isFromMap ~= b.isFromMap then
        return not a.isFromMap
    end
    if IsAnySortActive() then
        local sorted = CompareActiveSorts(a.level, a.distance, b.level, b.distance, false)
        if sorted ~= nil then return sorted end
        if a.header ~= b.header then return a.header < b.header end
        if a.title ~= b.title then return a.title < b.title end
        return a.questID < b.questID
    else
        if a.header ~= b.header then return a.header < b.header end
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
    end
end

-- The usable item the tracker shows for this quest (an eye, a phial...), or nil. A finished quest only
-- keeps its item if the game says so (showItemWhenComplete).
function CFQ.QuestItemInfo(logIndex, isComplete)
    if not (GetQuestLogSpecialItemInfo and logIndex and logIndex > 0) then return nil end
    local ok, link, tex, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, logIndex)
    if not ok or not (link or tex) then return nil end
    if isComplete and not showWhenComplete then return nil end
    return { link = link, tex = tex, charges = charges, logIndex = logIndex }
end

function CFQ.QuestHasItemButton(logIndex, isComplete)
    return CFQ.QuestItemInfo(logIndex, isComplete) ~= nil
end

-- ============================================================================
-- DUAL SPATIAL CLUSTERING ENGINE (OBJECTIVE TRACKER ONLY)
-- ============================================================================
local function BuildQuestClusters()
    wipe(clusterGroupsMap)

    local readyQuests = {}
    local incompleteQuests = {}

    for _, qData in pairs(questRewardMap) do
        if not qData.isFromMap then
            qData.clusterID = nil
            qData.clusterSize = 0
            qData.clusterOrder = nil

            if qData.hasQuestItem and not CFQ.ItemButtonsSupported() then
                -- no secure buttons on this client: a quest item to click keeps its own tracker line
            elseif qData.isComplete then
                table.insert(readyQuests, qData)
            else
                table.insert(incompleteQuests, qData)
            end
        end
    end

    local function RunProximityClustering(questPool, radiusPct, prefixKey, isCompleteGroup)
        if #questPool == 0 then return end
        local tolerance = (radiusPct or 16) / 100.0

        table.sort(questPool, function(a, b)
            if a.header ~= b.header then return a.header < b.header end
            return a.questID < b.questID
        end)

        local visited = {}
        local clusters = {}

        local function AreQuestsClose(q1, q2)
            if q1.mapID and q2.mapID and q1.x and q1.y and q2.x and q2.y then
                if q1.mapID ~= q2.mapID then return false end
                local dx = q1.x - q2.x
                local dy = q1.y - q2.y
                return math.sqrt(dx * dx + dy * dy) <= tolerance
            end
            if (not q1.x or not q2.x) and q1.header and q2.header and q1.header == q2.header then
                return true
            end
            return false
        end

        for i = 1, #questPool do
            local seed = questPool[i]
            if not visited[seed.questID] then
                local group = { seed }
                visited[seed.questID] = true

                local qIdx = 1
                while qIdx <= #group do
                    local current = group[qIdx]
                    for j = 1, #questPool do
                        local candidate = questPool[j]
                        if not visited[candidate.questID] and AreQuestsClose(current, candidate) then
                            visited[candidate.questID] = true
                            table.insert(group, candidate)
                        end
                    end
                    qIdx = qIdx + 1
                end
                table.insert(clusters, group)
            end
        end

        table.sort(clusters, function(cA, cB)
            if #cA ~= #cB then return #cA > #cB end
            return (cA[1].header or "") < (cB[1].header or "")
        end)

        local multiIdx = 0
        for _, group in ipairs(clusters) do
            if #group >= 2 then
                multiIdx = multiIdx + 1
                local zoneLabel = group[1].header or "Zone"
                local cID = prefixKey .. "_" .. tostring(multiIdx) .. "_" .. string.gsub(zoneLabel, "%s+", "")

                for _, qData in ipairs(group) do
                    qData.clusterID = cID
                    qData.clusterSize = #group
                    qData.clusterOrder = multiIdx
                end

                table.sort(group, CompareQuestsForTracker)

                local minDist = CFQ.DIST_UNKNOWN
                for _, qData in ipairs(group) do
                    if (qData.distance or CFQ.DIST_UNKNOWN) < minDist then minDist = qData.distance end
                end

                clusterGroupsMap[cID] = {
                    id = cID,
                    index = multiIdx,
                    zone = zoneLabel,
                    isComplete = isCompleteGroup,
                    quests = group,
                    minDistance = minDist,
                }
            else
                local single = group[1]
                single.clusterSize = 1
            end
        end
    end

    RunProximityClustering(readyQuests, turnInRadiusPercent, "CLUSTER_TURNIN", true)
    RunProximityClustering(incompleteQuests, incompleteRadiusPercent, "CLUSTER_INCOMP", false)
end

-- ============================================================================
-- QUEST LOG & LOCAL ZONE MAP SCANNER
-- ============================================================================
ScanQuestLogRewards = function()
    wipe(availableRewards)
    wipe(availableLevelFilters)
    wipe(questRewardMap)
    wipe(questTitleLookup)

    local rewardRegistry = {}
    local levelRegistry = {}
    local currentHeader = "Quests"

    local function EnsureQuestEntry(questID, rawTitle, header, qLevel, isFromMap, suggestedGroup, isComplete, logIndex)
        if not questRewardMap[questID] then
            local cleanTitle = StripLeadingLevelTag(rawTitle or ("Quest #" .. tostring(questID)))
            local tierID, tierName, hexColor, tierOrder = GetQuestDifficultyInfo(qLevel)
            local exactKey = "LVL_" .. tostring(qLevel)
            local mapID, x, y = QueryQuestCoordinates(questID)
            local objText = GetFirstQuestObjectiveText(questID, logIndex, isComplete, header)
            local qtyObjs = (not isFromMap) and ExtractQuestQuantityObjectives(questID, logIndex, isComplete) or {}
            local itemObjs = {}   -- the tally's item lines: things you actually collect
            for _, o in ipairs(qtyObjs) do
                if o.isItem then o.kind = "loot"; table.insert(itemObjs, o) end
            end
            -- kill / other check-offs (shown when the tally's tasks toggle is on)
            local taskObjs = (not isFromMap) and CFQ.ExtractTaskObjectives(questID, logIndex, isComplete, qtyObjs) or {}

            local entry = {
                questID = questID,
                logIndex = logIndex or 0,
                title = cleanTitle,
                header = header or "Quests",
                level = qLevel,
                tierID = tierID,
                tierName = tierName,
                levelHex = hexColor,
                tierOrder = tierOrder,
                isFromMap = isFromMap or false,
                suggestedGroup = suggestedGroup or 0,
                isComplete = isComplete or false,
                objectiveText = objText,
                quantityObjectives = qtyObjs,
                itemObjectives = itemObjs,
                taskObjectives = taskObjs,
                questItem = (not isFromMap) and CFQ.QuestItemInfo(logIndex, isComplete) or nil,
                mapID = mapID,
                x = x,
                y = y,
                levelKeys = {
                    [tierID] = true,
                    [exactKey] = true,
                },
                rewards = {},
                badges = {},
                logLineRewards = {},
                mapIcons = {},
                tooltipRewards = {},
                order = {},
            }

            questRewardMap[questID] = entry
            entry.hasQuestItem = entry.questItem ~= nil
            if cleanTitle ~= "" then
                questTitleLookup[string.lower(cleanTitle)] = entry
            end

            knownLevelMeta[tierID] = {
                id = tierID,
                name = "|c" .. hexColor .. tierName .. "|r",
                rawName = tierName,
                categoryGroup = 101,
                sortPriority = tierOrder,
            }
            if not levelRegistry[tierID] then
                levelRegistry[tierID] = {
                    id = tierID,
                    name = "|c" .. hexColor .. tierName .. "|r",
                    rawName = tierName,
                    icon = nil,
                    categoryGroup = 101,
                    sortPriority = tierOrder,
                    questCount = 0,
                }
                table.insert(availableLevelFilters, levelRegistry[tierID])
            end
            levelRegistry[tierID].questCount = levelRegistry[tierID].questCount + 1

            local shortTier = string.match(tierName, "^([%a%s]+)%s*%(") or tierName
            shortTier = strtrim(shortTier)
            local exactLabel = string.format("|c%sLevel %d|r |cFFBBBBBB- %s|r", hexColor, qLevel, shortTier)
            local rawExactLabel = string.format("level %d %s", qLevel, string.lower(shortTier))

            knownLevelMeta[exactKey] = {
                id = exactKey,
                name = string.format("Level %d (%s)", qLevel, shortTier),
                rawName = rawExactLabel,
                categoryGroup = 102,
                sortPriority = qLevel,
            }
            if not levelRegistry[exactKey] then
                levelRegistry[exactKey] = {
                    id = exactKey,
                    name = exactLabel,
                    rawName = rawExactLabel,
                    icon = nil,
                    categoryGroup = 102,
                    sortPriority = qLevel,
                    questCount = 0,
                }
                table.insert(availableLevelFilters, levelRegistry[exactKey])
            end
            levelRegistry[exactKey].questCount = levelRegistry[exactKey].questCount + 1
        end
        return questRewardMap[questID]
    end

    local function RegisterReward(questID, title, header, qLevel, isFromMap, suggestedGroup, isComplete, logIndex, rewardID, name, icon, categoryGroup, sortPriority, badgeStr, mapIconTex, tooltipLineStr, logLineStr)
        local qEntry = EnsureQuestEntry(questID, title, header, qLevel, isFromMap, suggestedGroup, isComplete, logIndex)

        knownRewardMeta[rewardID] = {
            id = rewardID,
            name = name,
            icon = icon,
            categoryGroup = categoryGroup,
            sortPriority = sortPriority,
        }

        if not qEntry.rewards[rewardID] then
            qEntry.rewards[rewardID] = true
            qEntry.badges[rewardID] = badgeStr
            qEntry.logLineRewards[rewardID] = logLineStr or badgeStr
            qEntry.mapIcons[rewardID] = "|T" .. tostring(mapIconTex or icon or 134400) .. ":15:15:0:0|t"
            qEntry.tooltipRewards[rewardID] = tooltipLineStr or badgeStr
            table.insert(qEntry.order, rewardID)

            if not rewardRegistry[rewardID] then
                rewardRegistry[rewardID] = {
                    id = rewardID,
                    name = name,
                    icon = icon,
                    categoryGroup = categoryGroup,
                    sortPriority = sortPriority,
                    questCount = 0,
                }
                table.insert(availableRewards, rewardRegistry[rewardID])
            end
            rewardRegistry[rewardID].questCount = rewardRegistry[rewardID].questCount + 1
        end
    end

    local function ScanSingleQuest(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex)
        EnsureQuestEntry(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex)

        if HaveQuestRewardData and not HaveQuestRewardData(questID) and C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
            C_TaskQuest.RequestPreloadRewardData(questID)
        end

        local currencies = GetQuestCurrencies(questID)
        if currencies and #currencies > 0 then
            for _, curr in ipairs(currencies) do
                local cID = "CURR_" .. tostring(curr.currencyID or curr.name or "UNKNOWN")
                local cName = curr.name or "Currency"
                local cIcon = curr.texture or 134400
                local amt = curr.totalRewardAmount or curr.numItems or 0
                local badge = "|T" .. cIcon .. ":13:13:0:0|t|cFF00CCFF" .. amt .. "|r"
                local logLine = string.format("|T%s:13:13:0:0|t |cFF00CCFF%d|r |cFFCCCCCC%s|r", tostring(cIcon), amt, cName)
                local tipStr = string.format("|T%s:14:14:0:0|t |cFF00CCFF%d|r |cFFFFFFFF%s|r", tostring(cIcon), amt, cName)

                local catGroup = 2
                if IsSeasonalReward(cName, curr.currencyID, nil) then
                    catGroup = 1
                elseif IsReputationReward(cName, curr.currencyID) then
                    catGroup = 3
                end

                RegisterReward(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex, cID, cName, cIcon, catGroup, 1, badge, cIcon, tipStr, logLine)
            end
        end

        local function ProcessQuestItem(name, tex, numItems, itemID)
            if IsItemEquipment(itemID) then
                local icon = tex or 132739
                local badge = "|T" .. icon .. ":13:13:0:0|t"
                local logLine = string.format("|T%s:13:13:0:0|t |cFFCCCCCC%s|r", tostring(icon), name or "Equipment")
                local tipStr = string.format("|T%s:14:14:0:0|t |cFFFFFFFF%s|r", tostring(icon), name or "Equipment")
                RegisterReward(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex, "ITEM_GEAR", "Equipment & Weapons", icon, 5, 1, badge, icon, tipStr, logLine)
            else
                if itemID and not name and C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(itemID)
                end
                local rID = "ITEM_" .. tostring(itemID or name or "ITEM")
                local rName = name or ("Item #" .. tostring(itemID or ""))
                local rIcon = tex or 134400
                local amtStr = (numItems and numItems > 1) and ("|cFFFFFFFF" .. numItems .. "|r") or ""
                local badge = "|T" .. rIcon .. ":13:13:0:0|t" .. amtStr
                local qtyPrefix = (numItems and numItems > 1) and (tostring(numItems) .. "x ") or ""
                local logLine = string.format("|T%s:13:13:0:0|t |cFFCCCCCC%s%s|r", tostring(rIcon), qtyPrefix, rName)
                local tipStr = string.format("|T%s:14:14:0:0|t |cFFFFFFFF%s%s|r", tostring(rIcon), qtyPrefix, rName)

                local catGroup = IsSeasonalReward(rName, nil, itemID) and 1 or 4
                RegisterReward(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex, rID, rName, rIcon, catGroup, 2, badge, rIcon, tipStr, logLine)
            end
        end

        local numRewards = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
        for r = 1, numRewards do
            local name, tex, numItems, _, _, itemID = GetQuestLogRewardInfo(r, questID)
            ProcessQuestItem(name, tex, numItems, itemID)
        end

        local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0
        for c = 1, numChoices do
            local name, tex, numItems, _, _, itemID = GetQuestLogChoiceInfo(c, questID)
            ProcessQuestItem(name, tex, numItems, itemID)
        end

        local copper = GetQuestMoneyCopper(questID)
        if copper > 0 then
            local goldIcon = "Interface\\MoneyFrame\\UI-GoldIcon"
            local mapCoinIcon = GetMoneyCoinIcon(copper)
            local badge = FormatMoneyBadge(copper)
            local coinRichStr = FormatMoneyWithIcons(copper) or badge
            RegisterReward(questID, qTitle, headerName, qLevel, isFromMap, suggestedGroup, isComplete, logIndex, "GOLD", "Money (Gold / Silver)", goldIcon, 5, 2, badge, mapCoinIcon, coinRichStr, coinRichStr)
        end

        local qEntry = questRewardMap[questID]
        if qEntry and #qEntry.order > 1 then
            table.sort(qEntry.order, function(a, b)
                local metaA = knownRewardMeta[a]
                local metaB = knownRewardMeta[b]
                local catA = metaA and metaA.categoryGroup or 99
                local catB = metaB and metaB.categoryGroup or 99
                if catA ~= catB then return catA < catB end
                return a < b
            end)
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    currentHeader = info.title or "Quests"
                elseif not info.isHidden and info.questID then
                    local qLevel = QueryQuestLevel(info.questID, info)
                    local isComp = IsQuestReadyForTurnIn(info.questID)
                    ScanSingleQuest(info.questID, info.title or "Quest", currentHeader, qLevel, false, info.suggestedGroup, isComp, i)
                end
            end
        end
    end

    -- Forget learned parchment areas for quests that have left the log (only once the log is populated)
    if next(questRewardMap) and C_QuestLog and C_QuestLog.IsOnQuest then
        for qID in pairs(CFQ.learnedQuestAreas) do
            if not questRewardMap[qID] then
                local ok, onQuest = pcall(C_QuestLog.IsOnQuest, qID)
                if ok and onQuest == false then
                    CFQ.learnedQuestAreas[qID] = nil
                end
            end
        end
    end

    if distSortMode ~= "NONE" then
        CFQ.UpdateQuestDistances()
    end

    BuildQuestClusters()

    if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID then
        local uiMapID = WorldMapFrame:GetMapID()
        if uiMapID and C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
            local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
            local zoneHeader = "Map: " .. ((mapInfo and mapInfo.name) or "Local Zone")
            local taskQuests = C_TaskQuest.GetQuestsForPlayerByMapID(uiMapID)
            if taskQuests then
                for _, task in ipairs(taskQuests) do
                    local qID = task.questId or task.questID
                    if qID and not questRewardMap[qID] then
                        local qTitle = (C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(qID))
                            or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qID))
                            or ("Map Quest #" .. tostring(qID))
                        local qLevel = QueryQuestLevel(qID, nil)
                        ScanSingleQuest(qID, qTitle, zoneHeader, qLevel, true, 0, false, 999)
                    end
                end
            end
        end
    end

    for id, isSelected in pairs(selectedFilters) do
        if isSelected and not rewardRegistry[id] and knownRewardMeta[id] then
            local meta = knownRewardMeta[id]
            rewardRegistry[id] = {
                id = id,
                name = meta.name,
                icon = meta.icon,
                categoryGroup = meta.categoryGroup or 4,
                sortPriority = meta.sortPriority or 1,
                questCount = 0,
            }
            table.insert(availableRewards, rewardRegistry[id])
        end
    end

    for id, isSelected in pairs(selectedLevelFilters) do
        if isSelected and not levelRegistry[id] and knownLevelMeta[id] and LEVEL_CATEGORY_NAMES[knownLevelMeta[id].categoryGroup] then
            local meta = knownLevelMeta[id]
            levelRegistry[id] = {
                id = id,
                name = meta.name,
                rawName = meta.rawName or string.lower(meta.name),
                categoryGroup = meta.categoryGroup or 102,
                sortPriority = meta.sortPriority or 1,
                questCount = 0,
            }
            table.insert(availableLevelFilters, levelRegistry[id])
        end
    end

    table.sort(availableRewards, function(a, b)
        if a.categoryGroup ~= b.categoryGroup then return a.categoryGroup < b.categoryGroup end
        if a.sortPriority ~= b.sortPriority then return a.sortPriority < b.sortPriority end
        return a.name < b.name
    end)

    table.sort(availableLevelFilters, function(a, b)
        if a.categoryGroup ~= b.categoryGroup then return a.categoryGroup < b.categoryGroup end
        if a.sortPriority ~= b.sortPriority then
            if a.categoryGroup == 102 and levelSortMode == "DESC" then
                return a.sortPriority > b.sortPriority
            end
            return a.sortPriority < b.sortPriority
        end
        return a.name < b.name
    end)

    if distSortMode ~= "NONE" then
        CFQ.UpdateQuestDistances()   -- picks up map/task quests appended after clustering
    end
end

-- ============================================================================
-- FIELD TALLY: the handwritten list of quest items still to gather and tasks still to do
-- A pile of pages, one per area with something on it ("Near me" always on top). Finished lines
-- are ticked and struck through until the quest is turned in; the dog-eared corner turns pages.
-- EDIT: P.MAX_AREAS = how many pages at most; INK colours are the defaults before a look applies
--       (the real colours of each look are in P.STYLES further down).
-- ============================================================================
local P = {
    CURRENT_KEY = "__HERE__",
    MAX_AREAS = 8,              -- "Near me" + up to 7 other pages (the last one "Elsewhere" when there are more)
    MAX_BACK_SHEETS = 3,
    INK       = { 0.17, 0.10, 0.05 },   -- iron-gall ink
    INK_RED   = { 0.48, 0.15, 0.06 },   -- counts / fresh entries
    INK_GREEN = { 0.18, 0.36, 0.13 },   -- "(turn in)" notes
    BACK_SLOTS = {
        { angle =  0.026, dx =  2, dy = -3 },
        { angle = -0.040, dx = -3, dy = -6 },
        { angle =  0.055, dx =  4, dy = -9 },
    },
    areas = {},
    selectedKey = "__HERE__",
    lastAreaSig = nil,
    currentGlowUntil = 0,
}
CFQ.P = P

P.VI_TL = (Enum and Enum.VertexIndex and Enum.VertexIndex.TopLeft) or 1
P.VI_BL = (Enum and Enum.VertexIndex and Enum.VertexIndex.BottomLeft) or 2
P.VI_TR = (Enum and Enum.VertexIndex and Enum.VertexIndex.TopRight) or 3
P.VI_BR = (Enum and Enum.VertexIndex and Enum.VertexIndex.BottomRight) or 4

-- Stable pseudo-random 0..1 so torn edges don't shimmer while resizing
function P.Hash01(a, b, c)
    local n = (a or 0) * 127.1 + (b or 0) * 311.7 + (c or 0) * 74.7
    local s = math.sin(n) * 43758.5453
    return s - math.floor(s)
end

-- ----------------------------------------------------------------------------
-- ROUGH-CUT SHEET GEOMETRY
-- Drawn looks: a body quad plus torn "deckle" strips along all four edges (texture looks are one
-- image quad, the handkerchief has its own cloth shape). Vertex offsets give every strip a jagged
-- outer edge and rotate the whole sheet a few degrees (back sheets).
-- ----------------------------------------------------------------------------
function P.PlaceQuad(sheet, tex, x0, y0, x1, y1, tlx, tly, blx, bly, trx, try, brx, bry)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", sheet, "CENTER", (x0 + x1) * 0.5, (y0 + y1) * 0.5)
    tex:SetSize(math.max(0.5, x1 - x0), math.max(0.5, y1 - y0))
    if tex.SetVertexOffset then
        local c, s = sheet.cosA or 1, sheet.sinA or 0
        local px, py
        px, py = x0 + (tlx or 0), y1 + (tly or 0)
        tex:SetVertexOffset(P.VI_TL, (px * c - py * s) - x0, (px * s + py * c) - y1)
        px, py = x0 + (blx or 0), y0 + (bly or 0)
        tex:SetVertexOffset(P.VI_BL, (px * c - py * s) - x0, (px * s + py * c) - y0)
        px, py = x1 + (trx or 0), y1 + (try or 0)
        tex:SetVertexOffset(P.VI_TR, (px * c - py * s) - x1, (px * s + py * c) - y1)
        px, py = x1 + (brx or 0), y0 + (bry or 0)
        tex:SetVertexOffset(P.VI_BR, (px * c - py * s) - x1, (px * s + py * c) - y0)
    end
end

function P.GetSheetSeg(sheet, layer, idx)
    local pool = sheet.segs[layer]
    local tex = pool[idx]
    if not tex then
        tex = sheet:CreateTexture(nil, "BACKGROUND", nil, (layer == 1) and 0 or 1)
        local col = (layer == 1) and sheet.opts.rim or sheet.opts.paper
        tex:SetColorTexture(col[1], col[2], col[3], col[4])
        pool[idx] = tex
    end
    tex:Show()
    return tex
end

function P.LayoutSheet(sheet, w, h, angle, dx, dy)
    w = math.floor(w + 0.5)
    h = math.floor(h + 0.5)
    angle = math.floor(angle * 2000 + 0.5) / 2000
    dx = math.floor(dx * 4 + 0.5) / 4
    dy = math.floor(dy * 4 + 0.5) / 4
    local key = w .. ":" .. h .. ":" .. angle .. ":" .. dx .. ":" .. dy
    if sheet.layoutKey == key then return end
    sheet.layoutKey = key

    local parent = sheet:GetParent()
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", parent, "TOPLEFT", dx, dy)
    sheet:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", dx, dy)
    sheet.cosA, sheet.sinA = math.cos(angle), math.sin(angle)

    local o = sheet.opts
    local PQ = P.PlaceQuad
    local inset = o.inset or 0
    local hw, hh = w * 0.5 - inset, h * 0.5 - inset

    if sheet.grain then PQ(sheet, sheet.grain, -hw, -hh, hw, hh) end
    if sheet.shadeTop then
        PQ(sheet, sheet.shadeTop, -hw, hh - 20, hw, hh)
        PQ(sheet, sheet.shadeBot, -hw, -hh, hw, -hh + 14)
        PQ(sheet, sheet.shadeL, -hw, -hh, -hw + 9, hh)
        PQ(sheet, sheet.shadeR, hw - 9, -hh, hw, hh)
    end
    if sheet.hem then P.LayoutCloth(sheet, hw, hh) end

    -- Texture looks: one quad with the image (rotated with the sheet); no drawn edges
    if o.image then
        P.HideClothShape(sheet)
        for layer = 1, 2 do
            for _, tex in ipairs(sheet.segs[layer]) do tex:Hide() end
        end
        PQ(sheet, sheet.body, -hw, -hh, hw, hh)
        return
    end

    -- Cloth (handkerchief): rounded corners and a scalloped lace edge instead of torn paper
    if o.cloth then
        P.LayoutClothShape(sheet, hw, hh, o.cloth)
        for layer = 1, 2 do
            for _, tex in ipairs(sheet.segs[layer]) do tex:Hide() end
        end
        return
    end
    P.HideClothShape(sheet)
    PQ(sheet, sheet.body, -hw, -hh, hw, hh)

    local D = o.depth or 4
    local minD = o.minDepth or 1
    local segW = o.segW or 8
    local ovIn = o.overlap or 0.6
    local ovAlong = o.overlap and 0 or 0.35
    local hasVO = sheet.body.SetVertexOffset ~= nil
    local seed = sheet.seed
    local layers = o.rim and 2 or 1
    local counts = { 0, 0 }

    for edge = 1, 4 do
        local alongX = (edge <= 2)
        local startV = alongX and (-hw - D * 0.5) or -hh
        local endV = alongX and (hw + D * 0.5) or hh
        local n = math.max(1, math.ceil((endV - startV) / segW))
        local prevD = minD + (D - minD) * P.Hash01(seed, edge, 0)
        for k = 0, n - 1 do
            local a = startV + k * segW
            local b = math.min(endV, a + segW) + ovAlong
            local nextD = minD + (D - minD) * P.Hash01(seed, edge, k + 1)
            for li = 1, layers do
                local layer = (layers == 2) and li or 2
                local extra = (layer == 1) and 1.3 or 0          -- the rim sits 1.3px proud of the paper
                local D2, e0, e1 = D + extra, prevD + extra, nextD + extra
                counts[layer] = counts[layer] + 1
                local tex = P.GetSheetSeg(sheet, layer, counts[layer])
                if not hasVO then
                    local avg = (e0 + e1) * 0.5
                    if edge == 1 then PQ(sheet, tex, a, hh - ovIn, b, hh + avg)
                    elseif edge == 2 then PQ(sheet, tex, a, -hh - avg, b, -hh + ovIn)
                    elseif edge == 3 then PQ(sheet, tex, -hw - avg, a, -hw + ovIn, b)
                    else PQ(sheet, tex, hw - ovIn, a, hw + avg, b) end
                elseif edge == 1 then      -- top: jag the upper vertices
                    PQ(sheet, tex, a, hh - ovIn, b, hh + D2, 0, e0 - D2, 0, 0, 0, e1 - D2, 0, 0)
                elseif edge == 2 then      -- bottom: jag the lower vertices
                    PQ(sheet, tex, a, -hh - D2, b, -hh + ovIn, 0, 0, 0, D2 - e0, 0, 0, 0, D2 - e1)
                elseif edge == 3 then      -- left: jag the outer (left) vertices
                    PQ(sheet, tex, -hw - D2, a, -hw + ovIn, b, D2 - e1, 0, D2 - e0, 0, 0, 0, 0, 0)
                else                       -- right: jag the outer (right) vertices
                    PQ(sheet, tex, hw - ovIn, a, hw + D2, b, 0, 0, 0, 0, e1 - D2, 0, e0 - D2, 0)
                end
            end
            prevD = nextD
        end
    end

    for layer = 1, 2 do
        local pool = sheet.segs[layer]
        for i = counts[layer] + 1, #pool do pool[i]:Hide() end
    end
end

-- ----------------------------------------------------------------------------
-- CLOTH SHAPE (handkerchief look)
-- A rounded rectangle (two crossed rects + a disc in each corner) trimmed all round with a
-- scalloped lace edge: overlapping little discs half tucked under the cloth, each with a thread
-- outline and an embroidered eyelet, rippling gently like a hem that has been washed and ironed
-- by someone in a hurry. Discs are round, so rotating the sheet only moves their centres.
-- ----------------------------------------------------------------------------
function P.ClothTex(sheet, pool, i, sub)
    local cl = sheet.clothParts
    local list = cl[pool]
    local t = list[i]
    if not t then
        t = sheet:CreateTexture(nil, "BACKGROUND", nil, sub)
        if pool ~= "body2" then t:SetTexture(CIRCLE_MASK_TEX) end   -- a plain white disc
        list[i] = t
    end
    t:Show()
    return t
end

function P.LayoutClothShape(sheet, hw, hh, cl)
    sheet.clothParts = sheet.clothParts or { body2 = {}, corner = {}, lace = {}, thread = {}, eye = {} }
    local PQ = P.PlaceQuad
    local paper = sheet.opts.paper
    local R = math.min(cl.radius or 9, hw, hh)
    local c, s = sheet.cosA or 1, sheet.sinA or 0
    local function Disc(t, x, y, rad, col)
        t:ClearAllPoints()
        t:SetPoint("CENTER", sheet, "CENTER", x * c - y * s, x * s + y * c)
        t:SetSize(rad * 2, rad * 2)
        t:SetVertexColor(col[1], col[2], col[3], col[4])
    end

    -- the cloth itself
    PQ(sheet, sheet.body, -hw, -hh + R, hw, hh - R)
    sheet.body:Show()
    local b2 = P.ClothTex(sheet, "body2", 1, 3)
    b2:SetColorTexture(paper[1], paper[2], paper[3], paper[4])
    PQ(sheet, b2, -hw + R, -hh, hw - R, hh)
    local corners = { { hw - R, hh - R }, { -hw + R, hh - R }, { -hw + R, -hh + R }, { hw - R, -hh + R } }
    for k, cc in ipairs(corners) do
        Disc(P.ClothTex(sheet, "corner", k, 3), cc[1], cc[2], R, paper)
    end

    -- the scalloped lace trim, walked round the outline (counter-clockwise from the bottom-right)
    local counts = { lace = 0, thread = 0, eye = 0 }
    local r = cl.scallop
    if r then
        local step = cl.step or (r * 1.7)
        local ripple = cl.ripple or 0
        local seed = sheet.seed or 0
        local idx = 0
        local function Put(x, y, nx, ny)
            idx = idx + 1
            local w = ripple * math.sin(idx * 0.83 + seed) + ripple * 0.4 * math.sin(idx * 2.3 + seed * 2)
            local cx, cy = x + nx * w, y + ny * w
            if cl.thread then
                counts.thread = counts.thread + 1
                Disc(P.ClothTex(sheet, "thread", counts.thread, 0), cx, cy, r + 1.1, cl.thread)
            end
            counts.lace = counts.lace + 1
            Disc(P.ClothTex(sheet, "lace", counts.lace, 1), cx, cy, r, cl.lace or paper)
            if cl.eyelet then
                counts.eye = counts.eye + 1
                Disc(P.ClothTex(sheet, "eye", counts.eye, 2), cx + nx * r * 0.45, cy + ny * r * 0.45, 1.1, cl.eyelet)
            end
        end
        local function Edge(x0, y0, x1, y1, nx, ny)
            local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            local n = math.max(1, math.floor(len / step + 0.5))
            for i = 0, n - 1 do
                local t = i / n
                Put(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, nx, ny)
            end
        end
        local function Arc(cx, cy, a0)
            local m = math.max(1, math.floor(R * math.pi * 0.5 / step + 0.5))
            for j = 0, m - 1 do
                local a = a0 + (j / m) * math.pi * 0.5
                local ca, sa = math.cos(a), math.sin(a)
                Put(cx + ca * R, cy + sa * R, ca, sa)
            end
        end
        local pi = math.pi
        Edge(hw, -hh + R, hw, hh - R, 1, 0)
        Arc(hw - R, hh - R, 0)
        Edge(hw - R, hh, -hw + R, hh, 0, 1)
        Arc(-hw + R, hh - R, pi * 0.5)
        Edge(-hw, hh - R, -hw, -hh + R, -1, 0)
        Arc(-hw + R, -hh + R, pi)
        Edge(-hw + R, -hh, hw - R, -hh, 0, -1)
        Arc(hw - R, -hh + R, pi * 1.5)
    end
    for pool, n in pairs(counts) do
        local list = sheet.clothParts[pool]
        for i = n + 1, #list do list[i]:Hide() end
    end
end

function P.HideClothShape(sheet)
    if not sheet.clothParts then return end
    for _, list in pairs(sheet.clothParts) do
        for _, t in ipairs(list) do t:Hide() end
    end
end

function P.CreateSheet(parent, seed, opts)
    local sheet = CreateFrame("Frame", nil, parent)
    sheet:SetAllPoints(parent)
    sheet.seed = seed
    sheet.opts = opts
    sheet.cosA, sheet.sinA = 1, 0
    sheet.segs = { {}, {} }

    sheet.body = sheet:CreateTexture(nil, "BACKGROUND", nil, 3)

    -- Paper grain and edge shading are created on every sheet that may need them, so a style
    -- change can switch them on and off without rebuilding the pile.
    if opts.decor then
        sheet.grain = sheet:CreateTexture(nil, "BACKGROUND", nil, 4)
        sheet.grain:SetTexture("Interface\\QuestFrame\\UI-QuestGreeting-TopLeft")
        -- plain parchment only: the upper part of this art is the quest frame's dark header band
        sheet.grain:SetTexCoord(0.20, 0.95, 0.45, 0.98)
        sheet.shadeTop = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        sheet.shadeBot = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        sheet.shadeL = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        sheet.shadeR = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        -- Handkerchief: a woven border (wide band + thin inner stripe), the running stitch that sews
        -- the lace on, soft creases where it was folded in four, and a couple of drape wrinkles
        sheet.hem = {}
        for k = 1, 4 do sheet.hem[k] = sheet:CreateTexture(nil, "BACKGROUND", nil, 6) end
        sheet.hem2 = {}
        for k = 1, 4 do sheet.hem2[k] = sheet:CreateTexture(nil, "BACKGROUND", nil, 6) end
        sheet.folds = {}
        for k = 1, 4 do sheet.folds[k] = sheet:CreateTexture(nil, "BACKGROUND", nil, 5) end
        sheet.drape = {}
        for k = 1, 4 do sheet.drape[k] = sheet:CreateTexture(nil, "BACKGROUND", nil, 5) end
        sheet.stitches = {}
    end

    sheet.Layout = P.LayoutSheet
    P.RestyleSheet(sheet, opts)
    return sheet
end

-- Recolours a sheet for the current style (opts = paper/rim colours + edge shape + decorations)
function P.RestyleSheet(sheet, opts)
    sheet.opts = opts
    sheet.layoutKey = nil
    local pc = opts.paper
    if opts.image then
        -- texture looks (every look with style.image): the image carries its own shape; paper = tint
        sheet.body:SetTexture(opts.image)
        local f = opts.flip or 0
        local l, r = 0, 1
        local t, b = 0, 1
        if f == 1 or f == 3 then l, r = 1, 0 end
        if f == 2 or f == 3 then t, b = 1, 0 end
        sheet.body:SetTexCoord(l, r, t, b)
        sheet.body:SetVertexColor(pc[1], pc[2], pc[3], pc[4])
    else
        sheet.body:SetColorTexture(pc[1], pc[2], pc[3], pc[4])
        sheet.body:SetTexCoord(0, 1, 0, 1)
        sheet.body:SetVertexColor(1, 1, 1, 1)
    end
    for layer = 1, 2 do
        local col = (layer == 1) and opts.rim or opts.paper
        for _, tex in ipairs(sheet.segs[layer]) do
            if col then tex:SetColorTexture(col[1], col[2], col[3], col[4]) end
        end
    end
    if sheet.grain then
        local g = opts.grain
        sheet.grain:SetShown(g and true or false)
        if g then sheet.grain:SetVertexColor(g[1], g[2], g[3], g[4]) end
    end
    if sheet.shadeTop then
        local s = opts.shade
        for _, t in ipairs({ sheet.shadeTop, sheet.shadeBot, sheet.shadeL, sheet.shadeR }) do t:SetShown(s and true or false) end
        sheet.shadeTop:Hide()        -- no shaded band along the top: sides and foot only
        if s then
            local r, g, b = s[1], s[2], s[3]
            ApplyTwoColorVerticalGradient(sheet.shadeTop, r * 1.2, g * 1.2, b * 1.2, 0.0, r, g, b, 0.34)
            ApplyTwoColorVerticalGradient(sheet.shadeBot, r, g, b, 0.30, r * 1.2, g * 1.2, b * 1.2, 0.0)
            ApplyHorizontalGradient(sheet.shadeL, r, g, b, 0.26, 0.0)
            ApplyHorizontalGradient(sheet.shadeR, r, g, b, 0.0, 0.26)
        end
    end
    if sheet.hem then
        local hem = opts.hem
        local on = hem and true or false
        for k = 1, 4 do
            sheet.hem[k]:SetShown(on)
            sheet.hem2[k]:SetShown(on and hem.stripe ~= nil)
            sheet.folds[k]:SetShown(on)
            sheet.drape[k]:SetShown(on)
        end
        if hem then
            for k = 1, 4 do
                sheet.hem[k]:SetColorTexture(hem.band[1], hem.band[2], hem.band[3], hem.band[4])
                if hem.stripe then sheet.hem2[k]:SetColorTexture(hem.stripe[1], hem.stripe[2], hem.stripe[3], hem.stripe[4]) end
            end
            -- creases fade out to either side: the shadowed half, then the half catching the light
            local d, l = hem.creaseDark, hem.creaseLight
            ApplyHorizontalGradient(sheet.folds[1], d[1], d[2], d[3], 0, d[4])     -- left of the vertical crease
            ApplyHorizontalGradient(sheet.folds[2], l[1], l[2], l[3], l[4], 0)     -- right of it
            ApplyTwoColorVerticalGradient(sheet.folds[3], d[1], d[2], d[3], 0, d[1], d[2], d[3], d[4])   -- below the horizontal crease
            ApplyTwoColorVerticalGradient(sheet.folds[4], l[1], l[2], l[3], l[4], l[1], l[2], l[3], 0)   -- above it
            -- drape wrinkles: same idea, softer
            ApplyHorizontalGradient(sheet.drape[1], d[1], d[2], d[3], 0, d[4] * 0.8)
            ApplyHorizontalGradient(sheet.drape[2], l[1], l[2], l[3], l[4] * 0.8, 0)
            ApplyHorizontalGradient(sheet.drape[3], d[1], d[2], d[3], 0, d[4] * 0.6)
            ApplyHorizontalGradient(sheet.drape[4], l[1], l[2], l[3], l[4] * 0.6, 0)
        end
        for _, ln in ipairs(sheet.stitches) do
            if hem then ln:SetColorTexture(hem.stitch[1], hem.stitch[2], hem.stitch[3], hem.stitch[4]) else ln:Hide() end
        end
    end
end

-- Handkerchief hem band, running stitch and fold creases. Placed with the sheet's rotation so they
-- tilt with it during a page turn.
function P.LayoutCloth(sheet, hw, hh)
    local hem = sheet.opts.hem
    if not hem then
        for _, ln in ipairs(sheet.stitches) do ln:Hide() end
        return
    end
    local PQ = P.PlaceQuad
    -- Woven border: bands on top/bottom run the full width, the side bands stop short of them, so
    -- the corners aren't doubled up
    local b0, b1 = hem.inset or 3, (hem.inset or 3) + (hem.width or 7)
    PQ(sheet, sheet.hem[1], -hw + b0, hh - b1, hw - b0, hh - b0)       -- top band
    PQ(sheet, sheet.hem[2], -hw + b0, -hh + b0, hw - b0, -hh + b1)     -- bottom band
    PQ(sheet, sheet.hem[3], -hw + b0, -hh + b1, -hw + b1, hh - b1)     -- left band
    PQ(sheet, sheet.hem[4], hw - b1, -hh + b1, hw - b0, hh - b1)       -- right band
    if hem.stripe then
        local s0 = b1 + (hem.stripeGap or 2)
        local s1 = s0 + (hem.stripeWidth or 1.2)
        PQ(sheet, sheet.hem2[1], -hw + s0, hh - s1, hw - s0, hh - s0)
        PQ(sheet, sheet.hem2[2], -hw + s0, -hh + s0, hw - s0, -hh + s1)
        PQ(sheet, sheet.hem2[3], -hw + s0, -hh + s1, -hw + s1, hh - s1)
        PQ(sheet, sheet.hem2[4], hw - s1, -hh + s1, hw - s0, hh - s1)
    end
    -- folded in four: soft creases through the middle, slightly off-centre, fading to each side
    local fx, fy = hw * 0.06, -hh * 0.08
    PQ(sheet, sheet.folds[1], fx - 7, -hh + 1, fx, hh - 1)
    PQ(sheet, sheet.folds[2], fx, -hh + 1, fx + 5, hh - 1)
    PQ(sheet, sheet.folds[3], -hw + 1, fy - 7, hw - 1, fy)
    PQ(sheet, sheet.folds[4], -hw + 1, fy, hw - 1, fy + 5)
    -- two drape wrinkles running down from the top-right, where it was picked up and stuffed in a pocket
    local slant = hh * 0.35
    local yb, yt = hh * 0.05, hh - 2
    local x1, x2 = hw * 0.30, hw * 0.62
    PQ(sheet, sheet.drape[1], x1 - 9, yb, x1, yt, slant, 0, 0, 0, slant, 0, 0, 0)
    PQ(sheet, sheet.drape[2], x1, yb, x1 + 6, yt, slant, 0, 0, 0, slant, 0, 0, 0)
    PQ(sheet, sheet.drape[3], x2 - 7, yb + hh * 0.3, x2, yt, slant * 0.6, 0, 0, 0, slant * 0.6, 0, 0, 0)
    PQ(sheet, sheet.drape[4], x2, yb + hh * 0.3, x2 + 5, yt, slant * 0.6, 0, 0, 0, slant * 0.6, 0, 0, 0)

    -- running stitch that sews the lace on, just inside the cloth's edge (straight runs only:
    -- the corners are rounded)
    local s = hem.stitchInset or 1.8
    local R = (sheet.opts.cloth and sheet.opts.cloth.radius) or 0
    local dash, gap = 3, 2.5
    local c, sn = sheet.cosA or 1, sheet.sinA or 0
    local n = 0
    local function Dash(x0, y0, x1, y1)
        n = n + 1
        local ln = sheet.stitches[n]
        if not ln then
            ln = sheet:CreateLine(nil, "BACKGROUND", nil, 7)
            local st = hem.stitch
            ln:SetColorTexture(st[1], st[2], st[3], st[4])
            ln:SetThickness(1.1)
            sheet.stitches[n] = ln
        end
        ln:SetStartPoint("CENTER", sheet, x0 * c - y0 * sn, x0 * sn + y0 * c)
        ln:SetEndPoint("CENTER", sheet, x1 * c - y1 * sn, x1 * sn + y1 * c)
        ln:Show()
    end
    local x0, x1, y0, y1 = -hw + s, hw - s, -hh + s, hh - s
    local v = x0 + R
    while v + dash <= x1 - R do Dash(v, y1, v + dash, y1); Dash(v, y0, v + dash, y0); v = v + dash + gap end
    v = y0 + R
    while v + dash <= y1 - R do Dash(x0, v, x0, v + dash); Dash(x1, v, x1, v + dash); v = v + dash + gap end
    for i = n + 1, #sheet.stitches do sheet.stitches[i]:Hide() end
end

-- ----------------------------------------------------------------------------
-- POSITIONING (default: just above the chat box, left side of the screen)
-- ----------------------------------------------------------------------------
-- The pages under the top sheet hang up to ~10px below and left of the frame (plus their torn
-- edges and the drop shadow), and swing further out while a page turns. The default spot leaves
-- room for that so the pile never laps over the chat tabs.
-- EDIT: pixels to the right of / above the chat box for the default spot
P.PILE_MARGIN_X = 10
P.PILE_MARGIN_Y = 20

function P.ComputeDefaultAnchor()
    local cf = ChatFrame1
    if cf and cf.GetLeft and cf:GetLeft() and cf:GetTop() then
        local uiScale = UIParent:GetEffectiveScale() or 1
        local ratio = (cf:GetEffectiveScale() or 1) / uiScale
        local left = cf:GetLeft() * ratio
        -- +32 clears the chat tabs that sit on top of the chat frame; use the tab itself when it's taller
        local top = cf:GetTop() * ratio + 32
        local tab = _G.ChatFrame1Tab
        if tab and tab.GetTop and tab:GetTop() then
            local tabTop = tab:GetTop() * ((tab:GetEffectiveScale() or 1) / uiScale)
            if tabTop > top then top = tabTop end
        end
        return math.floor(left + P.PILE_MARGIN_X + 0.5), math.floor(top + P.PILE_MARGIN_Y + 0.5)
    end
    return 36, 250
end

function P.ApplyPosition(f)
    f:ClearAllPoints()
    f:SetSize(shoppingListCfg.width or 230, shoppingListCfg.height or 175)
    if shoppingListCfg.useDefaultAnchor then
        local x, y = P.ComputeDefaultAnchor()
        shoppingListCfg.point, shoppingListCfg.relPoint = "BOTTOMLEFT", "BOTTOMLEFT"
        shoppingListCfg.x, shoppingListCfg.y = x, y
    end
    f:SetPoint(shoppingListCfg.point or "BOTTOMLEFT", UIParent, shoppingListCfg.relPoint or "BOTTOMLEFT",
        shoppingListCfg.x or 36, shoppingListCfg.y or 250)
end

local function ResetShoppingListPosition()
    shoppingListCfg.width = 230
    shoppingListCfg.height = 175
    shoppingListCfg.useDefaultAnchor = true
    if shoppingListFrame then
        P.ApplyPosition(shoppingListFrame)
    end
    SaveState()
    if UpdateShoppingListUI then UpdateShoppingListUI() end
end
CFQ.ResetShoppingListPosition = ResetShoppingListPosition

-- ----------------------------------------------------------------------------
-- INK & QUILL HELPERS
-- ----------------------------------------------------------------------------
-- Handwriting faces built into the client (no font files shipped with the addon).
-- Morpheus is the calligraphic face Blizzard uses for books & letters.
-- EDIT: item / title / small are font sizes for the list rows, the page heading and the footer.
P.FONT_STYLES = {
    { key = "QUILL",  label = "Quill script", path = "Fonts\\MORPHEUS.TTF", item = 13, title = 15, small = 11 },
    { key = "SCRAWL", label = "Rough scrawl", path = "Fonts\\SKURRI.TTF",   item = 12, title = 14, small = 10 },   -- also carved bark's letters
    { key = "PLAIN",  label = "Plain print",  path = nil,                   item = 11, title = 12, small = 9 },
    -- a rough hand with drops of ink shaken off the quill here and there (P.SetInkDrops)
    -- bold = a second pass of the quill (px to the right), so the letters read as soaked-in ink, not hairlines;
    -- haloScale = wet ink spreads less round them (a tight bleed, not a blur)
    { key = "BLOTTED", label = "Blotted scrawl", path = "Fonts\\SKURRI.TTF", item = 12, title = 14, small = 10, drops = true,
      bold = 0.8, haloScale = 0.55 },
}

-- The handwriting actually used: carved bark brings its own lettering (style.font)
function P.EffectiveFont()
    local look = P.GetStyle()
    local st = P.GetFontStyle()
    if look.font then
        for _, f in ipairs(P.FONT_STYLES) do if f.key == look.font then st = f end end
    end
    return st
end

function P.GetFontStyle()
    for _, st in ipairs(P.FONT_STYLES) do
        if st.key == CFQ.parchmentFont then return st end
    end
    return P.FONT_STYLES[1]
end

function P.CycleFontStyle()
    local idx = 1
    for i, st in ipairs(P.FONT_STYLES) do
        if st.key == CFQ.parchmentFont then idx = i end
    end
    CFQ.parchmentFont = P.FONT_STYLES[(idx % #P.FONT_STYLES) + 1].key
end

-- Text size (options slider, % of the usual): the list's lines and notes. The heading grows by half
-- as much so it keeps clear of its underline.
P.TEXT_SCALE_MIN, P.TEXT_SCALE_MAX = 80, 150
function P.TextScale(kind)
    local pct = CFQ.tallyTextScale or 100
    if kind == "title" then pct = 100 + (pct - 100) * 0.5 end
    return math.floor(pct + 0.5) / 100
end

-- Applies the chosen handwriting face; falls back to the standard UI font if the client can't load it
function P.SetInkFont(fs, kind, flags)
    local look = P.GetStyle()
    local st = P.EffectiveFont()
    local scale = P.TextScale(kind)
    local cacheKey = st.key .. ":" .. look.key .. ":" .. scale
    if fs.inkKey == cacheKey and fs.inkKind == kind then return end
    local ok = st.path and fs:SetFont(st.path, math.floor((st[kind] or st.item) * scale + 0.5), flags or "")
    if not st.path or ok == false then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.floor((P.FONT_STYLES[3][kind] or 11) * scale + 0.5), flags or "")   -- [3] = Plain print
    end
    if fs.SetShadowColor then
        local sh = look.inkShadow
        if sh then
            fs:SetShadowColor(sh[1], sh[2], sh[3], sh[4]) -- chalk dust / the shadow inside a carved cut
            if fs.SetShadowOffset then fs:SetShadowOffset(sh[5] or 1, sh[6] or -1) end
        elseif look.textShadow then
            fs:SetShadowColor(0, 0, 0, 1)                 -- UI text: the usual drop shadow
            if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        else
            fs:SetShadowColor(0, 0, 0, 0)                 -- ink doesn't cast drop shadows
        end
    end
    fs.inkKey, fs.inkKind = cacheKey, kind
end

-- Wet ink / arcane light (style.halo): copies of the words nudged a fraction of a pixel round them,
-- under the ink. In the ink's own colour they read as ink soaking into the cloth; in the look's glow
-- colour (halo.color) as light around the letters. color = the line's main colour.
P.HALO_OFFS = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
function P.PlainText(s)
    return (string.gsub(string.gsub(s or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

-- Places a copy of a font string (bold pass, wet ink) dx, dy off it, wrapping or cutting off exactly
-- like it: a one-line heading's copies span the same box (so they end in the same "..." instead of
-- wrapping a word onto a second line), a list line's copies get its width and wrap setting
function P.MatchCopy(c, fs, dx, dy)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", fs, "TOPLEFT", dx, dy)
    if fs.singleLine then
        c:SetPoint("TOPRIGHT", fs, "TOPRIGHT", dx, dy)
        c:SetWordWrap(false)
        if c.SetMaxLines then c:SetMaxLines(1) end
        return
    end
    local w = fs:GetWidth()
    if w and w > 0 then c:SetWidth(w) end
    local wrap = true
    if fs.GetWordWrap then
        local ok, v = pcall(fs.GetWordWrap, fs)
        if ok and v ~= nil then wrap = v end
    end
    c:SetWordWrap(wrap)
end

-- A second pass of the quill a fraction of a pixel to the right, for faces with style.bold: thicker
-- strokes in the same colours (colour codes kept), drawn with the words
function P.SetBold(fs, text, color)
    local b = P.EffectiveFont().bold
    if not b or not text or text == "" then
        if fs.boldCopy then fs.boldCopy:Hide() end
        return
    end
    local c = fs.boldCopy
    if not c then
        local layer, sub = fs:GetDrawLayer()
        c = fs:GetParent():CreateFontString(nil, layer or "ARTWORK", nil, sub or 0)
        c:SetJustifyH("LEFT")
        c:SetJustifyV("TOP")
        fs.boldCopy = c
    end
    local path, size, flags = fs:GetFont()
    c:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
    if c.SetShadowColor then c:SetShadowColor(0, 0, 0, 0) end
    P.MatchCopy(c, fs, b, 0)
    local col = color or P.INK
    c:SetTextColor(col[1], col[2], col[3], 1)
    c:SetText(text)
    c:Show()
end

function P.SetHalo(fs, text, color)
    P.SetBold(fs, text, color)
    local hl = P.GetStyle().halo
    if not hl or not text or text == "" then
        if fs.halo then for _, c in ipairs(fs.halo) do c:Hide() end end
        return
    end
    if not fs.halo then
        fs.halo = {}
        local parent = fs:GetParent()
        for k = 1, #P.HALO_OFFS do
            local c = parent:CreateFontString(nil, "ARTWORK", nil, 6)
            c:SetJustifyH("LEFT")
            c:SetJustifyV("TOP")
            fs.halo[k] = c
        end
    end
    local path, size, flags = fs:GetFont()
    local plain = P.PlainText(text)
    local col = hl.color or color or P.INK
    local r = (hl.radius or 0.8) * (hl.color and 1 or (P.EffectiveFont().haloScale or 1))
    for k, c in ipairs(fs.halo) do
        c:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
        if c.SetShadowColor then c:SetShadowColor(0, 0, 0, 0) end
        P.MatchCopy(c, fs, P.HALO_OFFS[k][1] * r, P.HALO_OFFS[k][2] * r)
        c:SetText(plain)
        c:SetTextColor(col[1], col[2], col[3], hl.alpha or 0.2)
        c.haloCol = col
        c:Show()
    end
end

-- "Blotted scrawl": drops of ink shaken off the quill, placed by a hash of the line so they stay put.
-- d = { key, lastW (width of the last line), textH, lines, textW, ink }; nil = no drops on this row.
P.DROP_MAX = 8
-- 2x2 atlas of soaked-in blots (tools/TexGen.cs InkBlots): dark where the drop landed, fading out along a
-- ragged front as the material drinks it. 1 big blot, 2 smaller blot, 3 splash with
-- specks, 4 teardrop. Each blot fills about half its cell, so a texture is drawn twice the blot's size.
P.INK_BLOTS_TEX = "Interface\\AddOns\\Handkerquest\\textures\\ink_blots"
P.BLOT_CELLS = { { 0, 0.5, 0, 0.5 }, { 0.5, 1, 0, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0.5, 1, 0.5, 1 } }
function P.StrHash(s)
    local h = 7
    for i = 1, string.len(s) do h = (h * 31 + string.byte(s, i)) % 1000003 end
    return h
end

function P.SetInkDrops(row, d)
    local drops = row.drops
    if not (d and P.EffectiveFont().drops) then
        if drops then for _, t in ipairs(drops) do t:Hide() end end
        return
    end
    if not drops then
        drops = {}
        for k = 1, P.DROP_MAX do
            local t = row:CreateTexture(nil, "ARTWORK", nil, 5)
            t:SetTexture(P.INK_BLOTS_TEX)
            t:Hide()
            drops[k] = t
        end
        row.drops = drops
    end
    local h = P.StrHash(d.key or "")
    local used = 0
    local lineH = d.textH / math.max(1, d.lines)
    local ink = d.ink
    -- size = the blot itself; cell = which blot in the atlas, mirrored either way so no two repeat
    local function Drop(x, y, size, a, cell)
        if used >= P.DROP_MAX then return end
        used = used + 1
        local t = drops[used]
        local tc = P.BLOT_CELLS[cell]
        local l, r, tp, bt = tc[1], tc[2], tc[3], tc[4]
        if P.Hash01(h, used, 11) < 0.5 then l, r = r, l end
        if P.Hash01(h, used, 12) < 0.5 then tp, bt = bt, tp end
        local squash = 0.85 + 0.25 * P.Hash01(h, used, 5)
        t:SetTexture(P.INK_BLOTS_TEX)
        t:SetTexCoord(l, r, tp, bt)
        t:ClearAllPoints()
        t:SetSize(size * 2, size * 2 * squash)
        t:SetPoint("CENTER", row.itemText, "TOPLEFT", x, y)
        t:SetVertexColor(ink[1], ink[2], ink[3], a)
        t:Show()
    end
    local function OnLine(salt)                                       -- a written line and how long it is
        local li = 1 + math.floor(P.Hash01(h, salt, 31) * d.lines * 0.999)
        return li, (li == d.lines) and d.lastW or d.textW
    end
    -- every line: tiny spatters round the stroke, flicked off as the nib scraped across the grain
    local nSp = 2 + math.floor(P.Hash01(h, 30, 1) * 3.99)             -- two to five
    for k = 1, nSp do
        local li, w = OnLine(k)
        Drop(2 + P.Hash01(h, k, 32) * math.max(6, w - 2),
            -(li - 0.5) * lineH + (P.Hash01(h, k, 33) - 0.5) * lineH * 1.1,
            0.9 + P.Hash01(h, k, 34) * 1.1, 0.85, 2)
    end
    -- one line in five: the quill rested on the surface a moment, a bigger blot on the stroke (just
    -- under the letters' middle, so the word stays readable)
    if P.Hash01(h, 1, 1) < 0.2 then
        local li, w = OnLine(40)
        Drop(math.max(4, (0.15 + 0.85 * P.Hash01(h, 41, 1)) * w),
            -(li - 0.5) * lineH + lineH * 0.35,
            4.0 + P.Hash01(h, 42, 1) * 2.5, 0.95, (P.Hash01(h, 43, 1) < 0.6) and 1 or 4)
    end
    -- rarely: the quill lifted after the last word and let a proper splash go
    if P.Hash01(h, 4, 1) < 0.08 then
        Drop(math.min(d.textW + 6, d.lastW + 8 + P.Hash01(h, 2, 1) * 6),
            -(d.textH - lineH * 0.5) + (P.Hash01(h, 7, 1) - 0.5) * lineH * 0.6,
            5.5 + P.Hash01(h, 3, 1) * 2.0, 1.0, 3)
    end
    for k = used + 1, P.DROP_MAX do drops[k]:Hide() end
end

-- ----------------------------------------------------------------------------
-- LOOKS: a torn rag (default), crumpled paper, chalked stone, carved bark, a pipe-weed leaf, etched leather, arcane
-- script (glowing mage writing in the air), handkerchief notes, the parchment pile, or a
-- see-through WoW window
-- Every colour the tally draws with comes from here.
-- EDIT: colours are { red, green, blue, opacity } from 0 to 1. Per look:
--   paper = the sheet, back = the pages underneath, ink / inkRed / inkGreen = writing, counts and
--   "(turn in)", title / footer / faded = heading, footer and ticked-off items, hem = the
--   handkerchief border, cloth = its lace edge (scallop = size of each scallop), pad = space
--   between the edge and the writing; texture looks also have inset = { left, top, right, bottom }
--   as fractions of the window, so the writing stays on the material when the window is stretched.
--   halo = { alpha, radius [, color] } soft copies round the words: wet ink (no color: the ink's own) or
--   glowing light; bleedWidth / bleedAlpha = how far ticks and strikes spread into the material.
--   To make a different look the default, change parchmentStyle near the top of the file to that look's key.
-- ----------------------------------------------------------------------------
P.STYLES = {
    {
        key = "HANDKERCHIEF", label = "Handkerchief notes",
        paper = { 0.95, 0.93, 0.88, 0.98 }, rim = nil,
        depth = 1.6, minDepth = 0.4, segW = 4,
        -- soft cloth: rounded corners, scalloped lace with eyelets, rippling a little
        cloth = { radius = 9, scallop = 4.6, step = 7.5, ripple = 1.1,
                  lace = { 0.99, 0.98, 0.95, 0.98 }, thread = { 0.60, 0.67, 0.84, 0.95 }, eyelet = { 0.50, 0.58, 0.80, 0.70 } },
        shade = nil, grain = nil,
        hem = {
            band = { 0.42, 0.56, 0.84, 0.30 }, inset = 4, width = 4,
            stripe = { 0.32, 0.46, 0.78, 0.55 }, stripeGap = 2, stripeWidth = 1.2,
            stitch = { 0.40, 0.50, 0.75, 0.75 }, stitchInset = 1.6,
            creaseDark = { 0.36, 0.37, 0.45, 0.16 }, creaseLight = { 1, 1, 1, 0.55 },
        },
        back = { { 0.93, 0.84, 0.84, 0.98 }, { 0.86, 0.90, 0.83, 0.98 }, { 0.95, 0.91, 0.78, 0.98 } },
        backRim = nil, backDepth = 1.6, backMinDepth = 0.4, backSegW = 4,
        backThread = { 0.62, 0.54, 0.56, 0.90 },        -- the hankies underneath: same cloth, own colours
        shadowAlpha = 0.20, pile = true, cornerInset = 4,
        ink = { 0.10, 0.13, 0.30 }, inkRed = { 0.62, 0.12, 0.12 }, inkGreen = { 0.16, 0.40, 0.20 },
        title = { 0.10, 0.13, 0.30 }, faded = { 0.42, 0.44, 0.52 }, footer = { 0.30, 0.34, 0.50 },
        sub = { 0.38, 0.42, 0.58 }, close = { 0.30, 0.34, 0.52 }, gear = { 0.28, 0.33, 0.52 },
        wash = { 0.40, 0.48, 0.70, 0.06 }, washFlash = { 0.95, 0.72, 0.20, 0.45 },
        divider = { 0.35, 0.42, 0.62, 0.14 }, highlight = { 0.30, 0.40, 0.70, 0.10 },
        grip = { 0.45, 0.52, 0.72, 0.85 }, pad = 7,           -- writing kept inside the woven border
        -- cloth drinks ink: a soft halo of ink round the letters, wide bleed round every stroke
        halo = { alpha = 0.20, radius = 0.9 }, bleedWidth = 2.6, bleedAlpha = 0.32,
        corner = { u1 = { 0.50, 0.52, 0.60 }, u2 = { 0.86, 0.85, 0.80 }, tip = { 1.00, 0.99, 0.96 },
                   crease = { 0.78, 0.78, 0.82 }, edge = { 0.40, 0.48, 0.68, 0.75 }, cut = { 0.45, 0.55, 0.78, 0.80 },
                   shadow = { 0.10, 0.12, 0.20 } },
    },
    {
        key = "PARCHMENT", label = "Parchment",
        paper = { 0.93, 0.85, 0.67, 0.97 }, rim = { 0.40, 0.27, 0.12, 0.95 },
        depth = 4.5, minDepth = 0.8, segW = 8,
        shade = { 0.35, 0.22, 0.08 }, grain = { 1.0, 0.94, 0.80, 0.30 }, hem = nil,
        back = { { 0.84, 0.75, 0.56, 0.98 }, { 0.78, 0.69, 0.51, 0.98 }, { 0.72, 0.63, 0.46, 0.98 } },
        backRim = { 0.34, 0.22, 0.09, 0.95 }, backDepth = 4, backMinDepth = 0.8, backSegW = 11,
        shadowAlpha = 0.36, pile = true,
        ink = { 0.17, 0.10, 0.05 }, inkRed = { 0.48, 0.15, 0.06 }, inkGreen = { 0.18, 0.36, 0.13 },
        title = { 0.17, 0.10, 0.05 }, faded = { 0.38, 0.30, 0.21 }, footer = { 0.36, 0.22, 0.08 },
        sub = { 0.48, 0.35, 0.23 }, close = { 0.40, 0.25, 0.11 }, gear = { 0.42, 0.26, 0.09 },
        wash = { 0.55, 0.40, 0.18, 0.06 }, washFlash = { 0.95, 0.72, 0.20, 0.45 },
        divider = { 0.45, 0.32, 0.15, 0.14 }, highlight = { 0.45, 0.30, 0.08, 0.10 },
        grip = { 0.75, 0.55, 0.30, 0.85 }, pad = 0,
        corner = { u1 = { 0.42, 0.30, 0.16 }, u2 = { 0.78, 0.68, 0.50 }, tip = { 0.98, 0.92, 0.78 },
                   crease = { 0.70, 0.58, 0.38 }, edge = { 0.33, 0.21, 0.08, 0.75 }, cut = { 0.45, 0.31, 0.14, 0.70 },
                   shadow = { 0.10, 0.05, 0.01 } },
    },
    {
        -- a sheet someone crumpled into a ball and flattened out again: texture image, pencil writing
        key = "CRUMPLED", label = "Crumpled paper",
        image = "Interface\\AddOns\\Handkerquest\\textures\\crumpled_paper",
        paper = { 1, 1, 1, 1 }, depth = 1,
        back = { { 0.93, 0.93, 0.92, 1 }, { 0.88, 0.88, 0.87, 1 }, { 0.83, 0.83, 0.82, 1 } },
        -- where the paper's bottom-right corner is in the image (fraction of width, of height):
        -- the folded page-turn corner is placed exactly there
        imageCorner = { 0.036, 0.034 },
        shadowAlpha = 0.35, pile = true,
        ink = { 0.20, 0.20, 0.22 }, inkRed = { 0.62, 0.16, 0.12 }, inkGreen = { 0.18, 0.42, 0.22 },
        title = { 0.20, 0.20, 0.22 }, faded = { 0.50, 0.50, 0.50 }, footer = { 0.38, 0.38, 0.40 },
        sub = { 0.45, 0.45, 0.48 }, close = { 0.35, 0.35, 0.38 }, gear = { 0.35, 0.35, 0.38 },
        wash = { 0.30, 0.30, 0.30, 0.05 }, washFlash = { 0.95, 0.72, 0.20, 0.45 },
        divider = { 0.35, 0.35, 0.40, 0.12 }, highlight = { 0.30, 0.30, 0.30, 0.08 },
        grip = { 0.45, 0.45, 0.48, 0.85 }, pad = 8,
        inset = { 0.039, 0.047, 0.047, 0.047 },  -- writing area: left, top, right, bottom (fractions of the window)
        corner = { u1 = { 0.55, 0.55, 0.53 }, u2 = { 0.86, 0.85, 0.82 }, tip = { 0.98, 0.97, 0.94 },
                   crease = { 0.78, 0.77, 0.74 }, edge = { 0.45, 0.45, 0.45, 0.70 }, cut = { 0.55, 0.55, 0.55, 0.70 },
                   shadow = { 0.10, 0.10, 0.10 } },
    },
    {
        -- a strip torn off a dwarf's shirt: cotton weave, torn edges, loose threads, the shirt's hem,
        -- written on in soot
        key = "RAG", label = "Torn rag",
        image = "Interface\\AddOns\\Handkerquest\\textures\\torn_rag",
        paper = { 1, 1, 1, 1 }, depth = 1,
        back = { { 0.92, 0.90, 0.86, 1 }, { 0.86, 0.83, 0.78, 1 }, { 0.80, 0.77, 0.71, 1 } },
        imageCorner = { 0.068, 0.046 },        -- the cloth's bottom-right corner (see Crumpled paper)
        shadowAlpha = 0.32, pile = true,
        ink = { 0.15, 0.12, 0.10 }, inkRed = { 0.55, 0.20, 0.10 }, inkGreen = { 0.25, 0.38, 0.18 },
        title = { 0.15, 0.12, 0.10 }, faded = { 0.48, 0.43, 0.36 }, footer = { 0.40, 0.34, 0.26 },
        sub = { 0.50, 0.42, 0.32 }, close = { 0.35, 0.28, 0.20 }, gear = { 0.35, 0.28, 0.20 },
        wash = { 0.45, 0.38, 0.25, 0.06 }, washFlash = { 0.95, 0.72, 0.20, 0.45 },
        divider = { 0.45, 0.38, 0.25, 0.12 }, highlight = { 0.45, 0.35, 0.15, 0.08 },
        grip = { 0.55, 0.48, 0.36, 0.85 }, pad = 8,
        inset = { 0.102, 0.102, 0.109, 0.075 },  -- writing kept clear of the torn edges and above the hem
        halo = { alpha = 0.17, radius = 0.8 }, bleedWidth = 2.2, bleedAlpha = 0.30,   -- soot ink soaking into cotton
        corner = { u1 = { 0.50, 0.46, 0.38 }, u2 = { 0.84, 0.80, 0.70 }, tip = { 0.93, 0.90, 0.81 },
                   crease = { 0.74, 0.70, 0.60 }, edge = { 0.45, 0.40, 0.30, 0.70 }, cut = { 0.55, 0.50, 0.40, 0.60 },
                   shadow = { 0.10, 0.08, 0.05 } },
    },
    {
        -- a smooth dark river slate, chalked on: pale chalk with a faint dusty smear (inkShadow), and a
        -- chalked dog-ear mark for the page corner instead of a fold (rigid: stone doesn't bend)
        key = "STONE", label = "Chalked slate",
        image = "Interface\\AddOns\\Handkerquest\\textures\\stone",
        paper = { 1, 1, 1, 1 }, depth = 1, rigid = true,
        back = { { 0.86, 0.86, 0.86, 1 }, { 0.76, 0.76, 0.76, 1 }, { 0.66, 0.66, 0.66, 1 } },
        imageCorner = { 0.15, 0.15 },          -- where the corner mark sits on the stone's face
        shadowAlpha = 0.45, pile = true,
        inkShadow = { 0.92, 0.91, 0.87, 0.22, 1, 0 },   -- r, g, b, opacity, x, y offset: chalk dust
        bleed = { 0.92, 0.91, 0.87, 0.30 }, bleedFollowsInk = true,   -- the dust around chalked lines (chalk: takes the writing colour)
        ink = { 0.93, 0.92, 0.88 }, inkRed = { 0.95, 0.62, 0.50 }, inkGreen = { 0.62, 0.86, 0.58 },
        title = { 0.96, 0.95, 0.91 }, faded = { 0.62, 0.62, 0.60 }, footer = { 0.80, 0.80, 0.76 },
        sub = { 0.75, 0.75, 0.72 }, close = { 0.85, 0.85, 0.82 }, gear = { 0.85, 0.85, 0.82 },
        wash = { 1, 1, 1, 0.05 }, washFlash = { 0.95, 0.80, 0.40, 0.35 },
        divider = { 1, 1, 1, 0.10 }, highlight = { 1, 1, 1, 0.07 },
        grip = { 0.85, 0.85, 0.82, 0.85 }, pad = 8,
        inset = { 0.185, 0.155, 0.140, 0.165 },  -- on the flat face, off the rolled-away rim
        -- rough chalk: a slate-coloured speckle tiled over the writing knocks gaps into the strokes
        inkGrain = { path = "Interface\\AddOns\\Handkerquest\\textures\\chalk_grain", size = 128, alpha = 0.85 },
        corner = { u1 = { 0.30, 0.30, 0.30 }, u2 = { 0.45, 0.45, 0.45 }, tip = { 0.93, 0.92, 0.88 },
                   crease = { 0.93, 0.92, 0.88 }, edge = { 0.93, 0.92, 0.88, 0.85 }, cut = { 0.93, 0.92, 0.88, 0.85 },
                   shadow = { 0.93, 0.92, 0.88 } },
    },
    {
        -- a jagged slab of chocolate-brown bark, letters carved into it: the cuts show the reddish inner bark,
        -- with a dark shadow inside the top-left wall of each cut (inkShadow)
        key = "BARK", label = "Carved bark",
        image = "Interface\\AddOns\\Handkerquest\\textures\\bark",
        paper = { 1, 1, 1, 1 }, depth = 1, rigid = true,
        back = { { 0.84, 0.82, 0.80, 1 }, { 0.74, 0.72, 0.70, 1 }, { 0.64, 0.62, 0.60, 1 } },
        imageCorner = { 0.19, 0.19 },
        shadowAlpha = 0.45, pile = true,
        inkShadow = { 0.07, 0.04, 0.02, 0.95, -1, 1 },
        font = "SCRAWL",                                  -- blocky, straight-cut letters: a knife can't do curves
        bleed = { 0.07, 0.04, 0.02, 0.55 },
        ink = { 0.87, 0.57, 0.42 }, inkRed = { 0.96, 0.78, 0.60 }, inkGreen = { 0.70, 0.80, 0.48 },
        title = { 0.90, 0.60, 0.45 }, faded = { 0.52, 0.37, 0.30 }, footer = { 0.80, 0.55, 0.42 },
        sub = { 0.75, 0.52, 0.40 }, close = { 0.87, 0.57, 0.42 }, gear = { 0.87, 0.57, 0.42 },
        wash = { 1, 0.9, 0.7, 0.05 }, washFlash = { 0.95, 0.75, 0.35, 0.35 },
        divider = { 1, 0.9, 0.7, 0.10 }, highlight = { 1, 0.9, 0.7, 0.07 },
        grip = { 0.87, 0.57, 0.42, 0.85 }, pad = 8,
        inset = { 0.165, 0.170, 0.180, 0.180 },  -- inside the jagged break
        corner = { u1 = { 0.20, 0.14, 0.10 }, u2 = { 0.35, 0.26, 0.18 }, tip = { 0.87, 0.57, 0.42 },
                   crease = { 0.87, 0.57, 0.42 }, edge = { 0.87, 0.57, 0.42, 0.95 }, cut = { 0.87, 0.57, 0.42, 0.95 },
                   shadow = { 0.07, 0.04, 0.02 } },
    },
    {
        -- a broad cured leaf of the finest pipe-weed (Longbottom's best): gold-brown, puckered between
        -- the veins, a pale midrib, written on in dark ink. It bends, so the page corner is a real fold.
        key = "LEAF", label = "Pipe-weed leaf",
        image = "Interface\\AddOns\\Handkerquest\\textures\\pipeweed_leaf",
        paper = { 1, 1, 1, 1 }, depth = 1,
        back = { { 0.92, 0.86, 0.80, 1 }, { 0.84, 0.76, 0.68, 1 }, { 0.76, 0.66, 0.56, 1 } },
        imageCorner = { 0.221, 0.221 },        -- where the leaf's edge crosses the bottom-right diagonal
        shadowAlpha = 0.35, pile = true,
        -- the leaves underneath fan out from the shared stem (pivot = x fraction of the width from the
        -- middle) instead of lying flipped: angles in radians, tips swung upward; flips = 0 none, 2 upside down
        fan = { pivot = -0.47, angles = { 0.17, 0.34, 0.51 }, flips = { 2, 0, 2 } },
        -- near-black oak-gall ink: brown ink vanished into the brown curing spots
        ink = { 0.05, 0.05, 0.03 }, inkRed = { 0.46, 0.04, 0.02 }, inkGreen = { 0.06, 0.20, 0.04 },
        title = { 0.04, 0.04, 0.02 }, faded = { 0.27, 0.20, 0.11 }, footer = { 0.12, 0.09, 0.04 },
        sub = { 0.20, 0.14, 0.06 }, close = { 0.12, 0.09, 0.04 }, gear = { 0.12, 0.09, 0.04 },
        wash = { 0.45, 0.30, 0.10, 0.06 }, washFlash = { 0.95, 0.72, 0.20, 0.45 },
        divider = { 0.35, 0.22, 0.08, 0.14 }, highlight = { 0.40, 0.25, 0.05, 0.10 },
        grip = { 0.40, 0.26, 0.12, 0.85 }, pad = 8,
        inset = { 0.148, 0.203, 0.273, 0.156 },  -- inside the blade, clear of the tapering tip
        foldAtEdge = true,                       -- its long edge runs along the fold: dog-ear on the leaf's corner
        halo = { alpha = 0.14, radius = 0.7 }, bleedWidth = 1.8, bleedAlpha = 0.30,   -- ink creeping along the leaf's fibres
        corner = { u1 = { 0.42, 0.28, 0.12 }, u2 = { 0.70, 0.52, 0.28 }, tip = { 0.86, 0.68, 0.40 },
                   crease = { 0.62, 0.44, 0.22 }, edge = { 0.35, 0.22, 0.08, 0.70 }, cut = { 0.45, 0.30, 0.12, 0.60 },
                   shadow = { 0.10, 0.06, 0.02 } },
    },
    {
        -- a rough-cut piece of supple tan leather, the garment kind: hide-shaped (leg lobes, knife-cut edges),
        -- soft drape folds, fine grain. The list is pressed in: dark letters with a pale lip below-right.
        key = "LEATHER", label = "Etched leather",
        image = "Interface\\AddOns\\Handkerquest\\textures\\etched_leather",
        paper = { 1, 1, 1, 1 }, depth = 1,
        back = { { 0.92, 0.88, 0.84, 1 }, { 0.83, 0.78, 0.73, 1 }, { 0.74, 0.69, 0.64, 1 } },
        imageCorner = { 0.133, 0.133 },
        shadowAlpha = 0.35, pile = true,
        inkShadow = { 0.96, 0.84, 0.66, 0.45, 1, -1 },  -- the lit lower-right wall of each pressed letter
        bleed = { 0.96, 0.84, 0.66, 0.30 },
        ink = { 0.17, 0.09, 0.04 }, inkRed = { 0.46, 0.09, 0.05 }, inkGreen = { 0.17, 0.28, 0.11 },
        title = { 0.21, 0.11, 0.05 }, faded = { 0.44, 0.31, 0.19 }, footer = { 0.30, 0.18, 0.09 },
        sub = { 0.38, 0.24, 0.13 }, close = { 0.28, 0.16, 0.08 }, gear = { 0.28, 0.16, 0.08 },
        wash = { 0.30, 0.18, 0.08, 0.08 }, washFlash = { 0.95, 0.72, 0.20, 0.40 },
        divider = { 0.30, 0.18, 0.08, 0.16 }, highlight = { 1.00, 0.86, 0.62, 0.10 },
        grip = { 0.30, 0.18, 0.09, 0.85 }, pad = 8,
        inset = { 0.078, 0.109, 0.109, 0.148 },  -- the largest rectangle on the hide ([TexGen]::SafeRect)
        corner = { u1 = { 0.50, 0.36, 0.22 }, u2 = { 0.68, 0.52, 0.34 }, tip = { 0.80, 0.64, 0.44 },
                   crease = { 0.58, 0.42, 0.26 }, edge = { 0.32, 0.20, 0.10, 0.70 }, cut = { 0.42, 0.28, 0.15, 0.60 },
                   shadow = { 0.10, 0.06, 0.02 } },
    },
    {
        -- a paladin's tablet: white marble with an arched top, a gold-inlaid groove inside the edge; the
        -- letters are cut and gilded (a dark shadow in the top-left wall of each cut) and a soft holy light
        -- breathes round them. Stone doesn't bend: a gilded dog-ear mark (rigid). The tablets underneath
        -- are only mirrored, so their arches stay on top.
        key = "MARBLE", label = "Sanctified marble",
        image = "Interface\\AddOns\\Handkerquest\\textures\\sanctified_marble",
        paper = { 1, 1, 1, 1 }, depth = 1, rigid = true,
        back = { { 0.90, 0.89, 0.87, 1 }, { 0.80, 0.79, 0.77, 1 }, { 0.70, 0.69, 0.67, 1 } },
        flips = { 1, 0, 1 },
        imageCorner = { 0.17, 0.15 },          -- inside the gold groove
        shadowAlpha = 0.40, pile = true,
        inkShadow = { 0.30, 0.24, 0.14, 0.55, -1, 1 },
        bleed = { 0.36, 0.28, 0.16, 0.30 },
        ink = { 0.66, 0.48, 0.12 }, inkRed = { 0.64, 0.16, 0.10 }, inkGreen = { 0.22, 0.44, 0.20 },
        title = { 0.58, 0.40, 0.08 }, faded = { 0.60, 0.56, 0.48 }, footer = { 0.52, 0.42, 0.22 },
        sub = { 0.55, 0.45, 0.28 }, close = { 0.50, 0.40, 0.20 }, gear = { 0.50, 0.40, 0.20 },
        wash = { 0.85, 0.70, 0.30, 0.06 }, washFlash = { 1.00, 0.85, 0.40, 0.45 },
        divider = { 0.60, 0.48, 0.25, 0.18 }, highlight = { 1.00, 0.85, 0.40, 0.10 },
        grip = { 0.55, 0.45, 0.25, 0.85 }, pad = 8,
        inset = { 0.16, 0.24, 0.16, 0.13 },    -- inside the groove, below the arch's narrow top
        halo = { color = { 1.00, 0.86, 0.45 }, alpha = 0.40, radius = 1.4, pulse = true, pulseSpeed = 1.2 },   -- holy light
        corner = { u1 = { 0.70, 0.69, 0.66 }, u2 = { 0.85, 0.84, 0.81 }, tip = { 0.70, 0.52, 0.14 },
                   crease = { 0.70, 0.52, 0.14 }, edge = { 0.70, 0.52, 0.14, 0.95 }, cut = { 0.70, 0.52, 0.14, 0.95 },
                   shadow = { 0.30, 0.24, 0.14 } },
    },
    {
        -- a plate of beaten gold: hammer dents, a raised rolled rim, a rivet in each corner. The list is
        -- engraved (dark lines, a bright lower wall: inkShadow) and a band of light sweeps across the
        -- metal now and then (style.sheen). Rigid: an engraved dog-ear mark.
        key = "GILDED", label = "Gilded plate",
        image = "Interface\\AddOns\\Handkerquest\\textures\\gilded_plate",
        paper = { 1, 1, 1, 1 }, depth = 1, rigid = true,
        back = { { 0.88, 0.86, 0.82, 1 }, { 0.78, 0.76, 0.72, 1 }, { 0.68, 0.66, 0.62, 1 } },
        imageCorner = { 0.16, 0.16 },          -- on the face, inside the rivet
        shadowAlpha = 0.45, pile = true,
        inkShadow = { 1.00, 0.93, 0.62, 0.50, 1, -1 },
        bleed = { 0.30, 0.18, 0.04, 0.40 },
        ink = { 0.24, 0.14, 0.03 }, inkRed = { 0.50, 0.08, 0.04 }, inkGreen = { 0.12, 0.28, 0.08 },
        title = { 0.20, 0.11, 0.02 }, faded = { 0.50, 0.36, 0.12 }, footer = { 0.30, 0.18, 0.05 },
        sub = { 0.36, 0.23, 0.07 }, close = { 0.30, 0.18, 0.05 }, gear = { 0.30, 0.18, 0.05 },
        wash = { 0.40, 0.25, 0.05, 0.08 }, washFlash = { 1.00, 0.95, 0.70, 0.45 },
        divider = { 0.35, 0.22, 0.05, 0.18 }, highlight = { 1.00, 0.95, 0.70, 0.12 },
        grip = { 0.30, 0.18, 0.05, 0.85 }, pad = 8,
        inset = { 0.13, 0.12, 0.13, 0.12 },    -- inside the rim
        sheen = { color = { 1.00, 0.96, 0.80 }, alpha = 0.35, width = 0.22, sweep = 1.6, every = 7 },
        corner = { u1 = { 0.55, 0.40, 0.12 }, u2 = { 0.80, 0.62, 0.25 }, tip = { 0.24, 0.14, 0.03 },
                   crease = { 0.24, 0.14, 0.03 }, edge = { 0.24, 0.14, 0.03, 0.95 }, cut = { 0.24, 0.14, 0.03, 0.95 },
                   shadow = { 1.00, 0.93, 0.62 } },
    },
    {
        -- a leaf of a holy book: cream vellum, a gold-leaf border between a blue and a red rule, gold bosses
        -- in the corners. Black iron-gall writing; the heading in red (a rubric) with its first letter gilded
        -- (style.initial); "(turn in)" in the border's blue. It bends: a real fold.
        key = "VELLUM", label = "Illuminated vellum",
        image = "Interface\\AddOns\\Handkerquest\\textures\\illuminated_vellum",
        paper = { 1, 1, 1, 1 }, depth = 1,
        back = { { 0.95, 0.93, 0.88, 1 }, { 0.89, 0.86, 0.80, 1 }, { 0.83, 0.80, 0.73, 1 } },
        imageCorner = { 0.052, 0.052 },        -- the page's own corner
        shadowAlpha = 0.32, pile = true,
        ink = { 0.10, 0.08, 0.07 }, inkRed = { 0.66, 0.10, 0.06 }, inkGreen = { 0.18, 0.26, 0.60 },
        title = { 0.62, 0.10, 0.06 }, initial = { 0.80, 0.58, 0.12 },
        faded = { 0.50, 0.45, 0.38 }, footer = { 0.40, 0.33, 0.25 },
        sub = { 0.48, 0.40, 0.30 }, close = { 0.35, 0.28, 0.20 }, gear = { 0.35, 0.28, 0.20 },
        wash = { 0.45, 0.38, 0.25, 0.05 }, washFlash = { 0.95, 0.75, 0.25, 0.45 },
        divider = { 0.62, 0.10, 0.06, 0.18 }, highlight = { 0.45, 0.35, 0.15, 0.07 },
        grip = { 0.50, 0.40, 0.28, 0.85 }, pad = 8,
        inset = { 0.12, 0.11, 0.12, 0.11 },    -- inside the red rule
        halo = { alpha = 0.10, radius = 0.6 }, bleedWidth = 1.4, bleedAlpha = 0.22,   -- iron-gall barely bites into skin
        corner = { u1 = { 0.70, 0.66, 0.56 }, u2 = { 0.90, 0.87, 0.78 }, tip = { 0.97, 0.94, 0.86 },
                   crease = { 0.80, 0.76, 0.66 }, edge = { 0.55, 0.48, 0.36, 0.70 }, cut = { 0.65, 0.58, 0.45, 0.60 },
                   shadow = { 0.10, 0.08, 0.05 } },
    },
    {
        -- a mage's writing hanging in the air: words of violet-white light over a faint haze, a rune circle
        -- turning slowly behind them (arcane.ring, added light) and motes drifting up. Nothing to fold, so the
        -- page corner is a glowing mark (rigid), and there's no pile: the footer says which page.
        key = "ARCANE", label = "Arcane script",
        image = "Interface\\AddOns\\Handkerquest\\textures\\arcane_haze",
        paper = { 1, 1, 1, 1 }, depth = 1, rigid = true,
        back = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
        imageCorner = { 0.06, 0.08 },
        shadowAlpha = 0, pile = false,
        arcane = { ring = "Interface\\AddOns\\Handkerquest\\textures\\arcane_ring", ringColor = { 0.62, 0.40, 1.00 },
                   ringAlpha = 0.30, spin = 0.06, motes = 10,
                   moteColors = { { 0.55, 0.90, 1.00 }, { 0.75, 0.50, 1.00 } } },   -- 40% / 60% of the motes
        -- rune & writing colours can be changed in the options (P.ApplyTallyColors rewrites this entry)
        halo = { color = { 0.60, 0.35, 1.00 }, alpha = 0.45, radius = 1.2, pulse = true },
        bleed = { 0.62, 0.38, 1.00, 0.55 }, bleedWidth = 2.6,
        ink = { 0.90, 0.86, 1.00 }, inkRed = { 0.55, 0.90, 1.00 }, inkGreen = { 0.60, 1.00, 0.78 },
        title = { 0.96, 0.90, 1.00 }, faded = { 0.56, 0.50, 0.72 }, footer = { 0.76, 0.68, 0.96 },
        sub = { 0.72, 0.62, 0.94 }, close = { 0.86, 0.78, 1.00 }, gear = { 0.86, 0.78, 1.00 },
        wash = { 0.60, 0.40, 1.00, 0.10 }, washFlash = { 0.55, 0.90, 1.00, 0.40 },
        divider = { 0.70, 0.50, 1.00, 0.14 }, highlight = { 0.60, 0.40, 1.00, 0.12 },
        grip = { 0.80, 0.70, 1.00, 0.85 }, pad = 8,
        inset = { 0.07, 0.09, 0.07, 0.10 },
        corner = { u1 = { 0.20, 0.12, 0.35 }, u2 = { 0.40, 0.28, 0.65 }, tip = { 0.80, 0.70, 1.00 },
                   crease = { 0.70, 0.55, 1.00 }, edge = { 0.75, 0.60, 1.00, 0.90 }, cut = { 0.75, 0.60, 1.00, 0.90 },
                   shadow = { 0.60, 0.35, 1.00 } },
    },
    {
        key = "NATIVE", label = "Transparent window",
        paper = { 0.02, 0.02, 0.03, 0.70 }, rim = { 0.55, 0.55, 0.60, 0.85 },
        depth = 1, minDepth = 1, segW = 40,                              -- straight edges, 1px border
        shade = nil, grain = nil, hem = nil,
        back = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
        backRim = nil, backDepth = 1, backMinDepth = 1, backSegW = 40,
        shadowAlpha = 0, pile = false,                                   -- no paper pile: the footer shows the page
        ink = { 0.85, 0.85, 0.85 }, inkRed = { 1.00, 0.82, 0.00 }, inkGreen = { 0.25, 0.95, 0.25 },
        title = { 1.00, 0.82, 0.00 }, faded = { 0.55, 0.55, 0.55 }, footer = { 0.70, 0.70, 0.70 },
        sub = { 0.75, 0.75, 0.75 }, close = { 0.80, 0.80, 0.80 }, gear = { 0.80, 0.80, 0.80 },
        wash = { 1, 1, 1, 0.05 }, washFlash = { 1.0, 0.82, 0.0, 0.40 },
        divider = { 1, 1, 1, 0.08 }, highlight = { 1, 1, 1, 0.07 },
        grip = { 0.80, 0.80, 0.80, 0.85 }, pad = 0,
        textShadow = true, name = { 0.95, 0.95, 0.95 },
        corner = { u1 = { 0.08, 0.08, 0.10 }, u2 = { 0.22, 0.22, 0.25 }, tip = { 0.50, 0.50, 0.55 },
                   crease = { 0.25, 0.25, 0.28 }, edge = { 0.60, 0.60, 0.65, 0.80 }, cut = { 0.50, 0.50, 0.55, 0.80 },
                   shadow = { 0, 0, 0 } },
    },
}

function P.GetStyle()
    for _, st in ipairs(P.STYLES) do
        if st.key == CFQ.parchmentStyle then return st end
    end
    return P.STYLES[1]
end

-- ----------------------------------------------------------------------------
-- TALLY COLOURS (options panel)
--  * Rune colour (Arcane script only, beside the Look button): the rune circle and its light (glow round
--    the words, motes, ticks & strikes, corner mark) = CFQ.arcaneRuneColor.
--  * Writing colour (every look): CFQ.inkColors[look key]; each look remembers its own. The heading,
--    faded lines, footer and buttons keep the look's own shading relative to its ink. Wet ink (no
--    style.bleed) bleeds in the writing colour anyway; the slate's chalk dust follows it (bleedFollowsInk);
--    bark's carved shadow and leather's pressed lip are the material's and stay (arcane: the runes').
-- nil = the look's own colours (the first swatch). Custom... = WoW's colour picker.
-- ----------------------------------------------------------------------------
P.ARCANE_RUNE_COLORS = {
    { label = "Violet",     c = { 0.62, 0.40, 1.00 } },
    { label = "Frost blue", c = { 0.30, 0.68, 1.00 } },
    { label = "Fel green",  c = { 0.35, 1.00, 0.30 } },
    { label = "Fire",       c = { 1.00, 0.48, 0.12 } },
    { label = "Gold",       c = { 1.00, 0.80, 0.22 } },
    { label = "Crimson",    c = { 1.00, 0.20, 0.25 } },
    { label = "Rose",       c = { 1.00, 0.42, 0.80 } },
    { label = "Silver",     c = { 0.82, 0.86, 0.95 } },
}
-- the first swatch is the current look's own ink (filled in by the options panel)
P.INK_COLORS = {
    { label = "The look's own", own = true },
    { label = "Soot black",  c = { 0.08, 0.07, 0.06 } },
    { label = "Sepia",       c = { 0.38, 0.22, 0.10 } },
    { label = "Indigo",      c = { 0.14, 0.20, 0.50 } },
    { label = "Forest green", c = { 0.10, 0.34, 0.16 } },
    { label = "Oxblood red", c = { 0.55, 0.10, 0.08 } },
    { label = "Gold",        c = { 0.96, 0.80, 0.34 } },
    { label = "Ice",         c = { 0.78, 0.92, 1.00 } },
    { label = "White",       c = { 1.00, 1.00, 1.00 } },
}
P.ARCANE_RUNE_FIELDS = { "bleed", "wash", "washFlash", "divider", "highlight", "corner" }
P.INK_FIELDS = { "ink", "title", "faded", "footer", "sub", "close", "gear", "grip", "name" }

function P.CopyTable(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = P.CopyTable(v) end
    return o
end

function P.MixColor(c, to, t, a)
    local out = {}
    for k = 1, 3 do out[k] = c[k] + ((to and to[k] or 1) - c[k]) * t end
    out[4] = a
    return out
end

function P.ScaleColor(c, s, a)
    return { c[1] * s, c[2] * s, c[3] * s, a }
end

function P.SameColor(a, b)
    if not (a and b) then return a == b end
    for k = 1, 3 do if math.abs((a[k] or 0) - (b[k] or 0)) > 0.01 then return false end end
    return true
end

-- Each look's own colours, kept for "back to the first swatch" (taken once, before any change)
function P.StyleDefaults(st)
    P.STYLE_DEFAULTS = P.STYLE_DEFAULTS or {}
    local d = P.STYLE_DEFAULTS[st.key]
    if not d then
        d = {}
        for _, k in ipairs(P.INK_FIELDS) do d[k] = P.CopyTable(st[k]) end
        for _, k in ipairs(P.ARCANE_RUNE_FIELDS) do d[k] = P.CopyTable(st[k]) end
        if st.arcane then
            d.ringColor, d.moteColors = P.CopyTable(st.arcane.ringColor), P.CopyTable(st.arcane.moteColors)
            d.haloColor = P.CopyTable(st.halo and st.halo.color)
        end
        P.STYLE_DEFAULTS[st.key] = d
    end
    return d
end

-- A field moved by the same step the ink moved (keeps the look's own lighter/fainter shading), alpha kept
function P.ShiftColor(c, from, to)
    local out = {}
    for k = 1, 3 do out[k] = math.max(0, math.min(1, c[k] + (to[k] - from[k]))) end
    out[4] = c[4]
    return out
end

-- Rewrites the looks in P.STYLES from the chosen colours (P.ApplyStyle runs this first)
function P.ApplyTallyColors()
    for _, st in ipairs(P.STYLES) do
        local d = P.StyleDefaults(st)
        -- runes (arcane only)
        if st.arcane then
            local c = CFQ.ValidColor(CFQ.arcaneRuneColor)
            if c and P.SameColor(c, d.ringColor) then c = nil end
            if not c then
                st.arcane.ringColor, st.arcane.moteColors = P.CopyTable(d.ringColor), P.CopyTable(d.moteColors)
                if st.halo then st.halo.color = P.CopyTable(d.haloColor) end
                for _, k in ipairs(P.ARCANE_RUNE_FIELDS) do st[k] = P.CopyTable(d[k]) end
            else
                st.arcane.ringColor = c
                st.arcane.moteColors = { P.MixColor(c, nil, 0.45), P.MixColor(c, nil, 0.15) }
                if st.halo then st.halo.color = { c[1], c[2], c[3] } end
                st.bleed = { c[1], c[2], c[3], 0.55 }
                st.wash = { c[1], c[2], c[3], 0.10 }
                st.washFlash = P.MixColor(c, nil, 0.40, 0.40)
                st.divider = P.MixColor(c, nil, 0.20, 0.14)
                st.highlight = { c[1], c[2], c[3], 0.12 }
                st.corner = { u1 = P.ScaleColor(c, 0.32), u2 = P.ScaleColor(c, 0.65), tip = P.MixColor(c, nil, 0.50),
                    crease = P.MixColor(c, nil, 0.25), edge = P.MixColor(c, nil, 0.35, 0.90), cut = P.MixColor(c, nil, 0.35, 0.90),
                    shadow = { c[1], c[2], c[3] } }
            end
        end
        -- writing (every look)
        local w = CFQ.ValidColor(CFQ.inkColors and CFQ.inkColors[st.key])
        if w and P.SameColor(w, d.ink) then w = nil end
        for _, k in ipairs(P.INK_FIELDS) do
            if d[k] then st[k] = w and P.ShiftColor(d[k], d.ink, w) or P.CopyTable(d[k]) end
        end
        if w then st.ink = { w[1], w[2], w[3] } end
        if not st.arcane and d.bleed then
            st.bleed = (w and st.bleedFollowsInk) and P.ShiftColor(d.bleed, d.ink, w) or P.CopyTable(d.bleed)
        end
    end
end

-- Options: the rune colour, or the current look's writing colour; nil = the look's own
function P.SetTallyColor(which, c)
    c = CFQ.ValidColor(c)
    if which == "rune" then
        CFQ.arcaneRuneColor = c
    else
        CFQ.inkColors = CFQ.inkColors or {}
        CFQ.inkColors[P.GetStyle().key] = c
    end
    SaveState()
    P.ApplyStyle()
    if UpdateShoppingListUI then UpdateShoppingListUI() end
end

function P.GetTallyColor(which)
    local st = P.GetStyle()
    if which == "rune" then
        local d = P.STYLE_DEFAULTS and P.STYLE_DEFAULTS.ARCANE
        return CFQ.arcaneRuneColor or (d and d.ringColor) or P.ARCANE_RUNE_COLORS[1].c
    end
    return (CFQ.inkColors and CFQ.inkColors[st.key]) or P.StyleDefaults(st).ink
end

-- What's stored (nil = the look's own), to put back when the colour picker is cancelled
function P.GetStoredTallyColor(which)
    if which == "rune" then return CFQ.arcaneRuneColor end
    return CFQ.inkColors and CFQ.inkColors[P.GetStyle().key]
end

function P.CycleStyle()
    local idx = 1
    for i, st in ipairs(P.STYLES) do
        if st.key == CFQ.parchmentStyle then idx = i end
    end
    CFQ.parchmentStyle = P.STYLES[(idx % #P.STYLES) + 1].key
end

function P.Hex(c)
    return string.format("FF%02X%02X%02X", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Puts the page-turn corner on the sheet's real corner: just past the frame for paper, inside the
-- rounded corner for cloth (cornerInset), and on the image's own corner for texture looks
-- (imageCorner, so it follows the window size)
function P.PlaceCorner(f)
    local c = f and f.corner
    if not c then return end
    local st = P.GetStyle()
    local offX, offY
    if st.imageCorner then
        local w, h = f:GetWidth() or 230, f:GetHeight() or 175
        offX = -math.floor(w * st.imageCorner[1] + 0.5)
        offY = math.floor(h * st.imageCorner[2] + 0.5)
    else
        local ci = st.cornerInset or 0
        offX, offY = 3 - ci, -3 + ci
    end
    if c.offX == offX and c.offY == offY and c:GetPoint(1) then return end
    c.offX, c.offY = offX, offY
    c:ClearAllPoints()
    c:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", offX, offY)
    c.drawnKey = nil
end

-- Repaints the whole pile and its chrome for the current look
function P.ApplyStyle(f)
    P.ApplyTallyColors()
    f = f or shoppingListFrame
    if not f then return end
    local st = P.GetStyle()
    P.INK, P.INK_RED, P.INK_GREEN = st.ink, st.inkRed, st.inkGreen
    P.BLEED = st.bleed
    P.BLEED_W, P.BLEED_A, P.HALO = st.bleedWidth or 1.0, st.bleedAlpha or 0.25, st.halo
    f.styleKey = st.key

    local cl = st.cloth
    -- image looks: the texture's own shape casts the shadow (tinted black) and makes the pile underneath
    P.RestyleSheet(f.shadowSheet, { paper = { 0, 0, 0, st.shadowAlpha or 0 }, depth = st.depth + 0.5, minDepth = 1, segW = 14, overlap = 0,
        cloth = cl and { radius = cl.radius + 1 } or nil, image = st.image })      -- a soft rounded shadow, no lace
    for k, sh in ipairs(f.backSheets) do
        local bp = st.back[k]
        P.RestyleSheet(sh, { paper = bp, rim = st.backRim, depth = st.backDepth, minDepth = st.backMinDepth, segW = st.backSegW,
            cloth = cl and { radius = cl.radius, scallop = cl.scallop, step = cl.step, ripple = cl.ripple,
                lace = { math.min(1, bp[1] * 1.03), math.min(1, bp[2] * 1.03), math.min(1, bp[3] * 1.03), bp[4] },
                thread = st.backThread } or nil,
            image = st.image, flip = st.fan and st.fan.flips[k] or (st.flips and st.flips[k]) or k })   -- each page underneath turned a different way
    end
    P.RestyleSheet(f.topSheet, {
        paper = st.paper, rim = st.rim, depth = st.depth, minDepth = st.minDepth, segW = st.segW,
        grain = st.grain, shade = st.shade, hem = st.hem, cloth = cl, image = st.image,
    })
    P.PlaceCorner(f)
    f.shadowSheet:SetShown((st.shadowAlpha or 0) > 0)

    local cc = st.close
    if f.closeBtn then f.closeBtn.txt:SetTextColor(cc[1], cc[2], cc[3]) end
    if f.optBtn then
        f.optBtn.iconColor = { st.gear[1], st.gear[2], st.gear[3] }
        CFQ.SetGearHover(f.optBtn, false)
    end
    if f.gripTex then f.gripTex:SetVertexColor(st.grip[1], st.grip[2], st.grip[3], st.grip[4]) end

    if f.footerFS then f.footerFS:SetTextColor(st.footer[1], st.footer[2], st.footer[3], 0.95) end
    P.LayoutPads(f)
    P.LayoutInkGrain(f)
    P.LayoutArcane(f)
    P.LayoutSheen(f)
    if f.corner then f.corner.drawnKey = nil; P.DrawCorner(f.corner) end
    P.ApplyStackLayout(f)
end

-- Rough chalk: a tiling grain over everything written on the top page (style.inkGrain). It is the
-- stone's own colour, so it only shows where it breaks up the chalk. One texel per pixel.
function P.LayoutInkGrain(f)
    if not f or not f.chrome then return end
    local g = P.GetStyle().inkGrain
    if not g then
        if f.inkGrain then f.inkGrain:Hide() end
        return
    end
    if not f.inkGrain then
        local fr = CreateFrame("Frame", nil, f.chrome)          -- above the rows, below corner & grip
        fr:SetAllPoints(f.chrome)
        fr:SetFrameLevel((f.baseLevel or 30) + 20)
        fr.tex = fr:CreateTexture(nil, "OVERLAY")
        fr.tex:SetAllPoints()
        f.inkGrain = fr
    end
    local w, h = f:GetWidth() or 230, f:GetHeight() or 175
    local tex = f.inkGrain.tex
    tex:SetTexture(g.path, "REPEAT", "REPEAT")              -- texcoords past 1 repeat the tile
    tex:SetTexCoord(0, w / g.size, 0, h / g.size)
    tex:SetVertexColor(1, 1, 1, g.alpha or 1)
    f.inkGrain:Show()
end

-- Arcane script (style.arcane): a glowing rune circle behind the words (added light, turning slowly,
-- on the top page so it moves with a page turn) and motes of light drifting up. P.AnimateArcane runs it.
P.ARCANE_MOTES = 12
function P.LayoutArcane(f)
    if not f or not f.topSheet then return end
    local ac = P.GetStyle().arcane
    if not ac then
        if f.arcane then
            f.arcane.ring:Hide()
            for _, m in ipairs(f.arcane.motes) do m:Hide() end
        end
        f.arcaneOn = false
        return
    end
    if not f.arcane then
        local A = { motes = {} }
        A.ring = f.topSheet:CreateTexture(nil, "BACKGROUND", nil, 6)
        if A.ring.SetBlendMode then A.ring:SetBlendMode("ADD") end
        for k = 1, P.ARCANE_MOTES do
            local m = f.chrome:CreateTexture(nil, "BACKGROUND", nil, 7)      -- behind the words
            m:SetTexture(CIRCLE_MASK_TEX)
            if m.SetBlendMode then m:SetBlendMode("ADD") end
            m:Hide()
            A.motes[k] = m
        end
        f.arcane = A
    end
    local A = f.arcane
    local w, h = f:GetWidth() or 230, f:GetHeight() or 175
    local d = math.min(w, h) * 0.95                                           -- kept round, whatever the window
    A.ring:SetTexture(ac.ring)
    A.ring:ClearAllPoints()
    A.ring:SetPoint("CENTER", f.topSheet, "CENTER", 0, 0)
    A.ring:SetSize(d, d)
    local c = ac.ringColor
    A.ring:SetVertexColor(c[1], c[2], c[3], ac.ringAlpha or 0.3)
    A.ring:Show()
    f.arcaneOn = true
end

function P.AnimateArcane(f, now)
    local ac = P.GetStyle().arcane
    local A = f.arcane
    if not (ac and A) then return end
    if A.ring.SetRotation then pcall(A.ring.SetRotation, A.ring, -now * (ac.spin or 0.06)) end
    local c = ac.ringColor
    A.ring:SetVertexColor(c[1], c[2], c[3], (ac.ringAlpha or 0.3) * (0.75 + 0.25 * math.sin(now * 1.3)))
    local w, h = f:GetWidth() or 230, f:GetHeight() or 175
    local n = math.min(#A.motes, ac.motes or 10)
    for k, m in ipairs(A.motes) do
        if k > n then
            m:Hide()
        else
            -- each mote rises through the page and fades, then is lit again somewhere else
            local t = now * (0.07 + 0.06 * P.Hash01(k, 3, 11)) + P.Hash01(k, 4, 11)
            local cyc = math.floor(t)
            local p = t - cyc
            local x = w * (0.08 + 0.84 * P.Hash01(k, cyc, 12)) + math.sin(now * 0.9 + k) * 4
            local s = 1.5 + 2.0 * P.Hash01(k, cyc, 13)
            m:ClearAllPoints()
            m:SetPoint("CENTER", f.chrome, "BOTTOMLEFT", x, h * (0.10 + 0.85 * p))
            m:SetSize(s, s)
            local a = math.sin(math.pi * p) * 0.85
            local mc = ac.moteColors or { { 0.55, 0.90, 1.00 }, { 0.75, 0.50, 1.00 } }
            mc = (P.Hash01(k, cyc, 14) > 0.6) and mc[1] or mc[2]
            m:SetVertexColor(mc[1], mc[2], mc[3], a)
            m:Show()
        end
    end
    P.PulseHalo(f, now)
end

-- A glow that breathes (style.halo.pulse: arcane light, the marble's holy light): its copies of the words
-- fade in and out together
function P.PulseHalo(f, now)
    local hl = P.GetStyle().halo
    if not (hl and hl.pulse) then return end
    local k = 0.75 + 0.25 * math.sin(now * (hl.pulseSpeed or 2.1))
    local function Pulse(fs)
        if not fs or not fs.halo then return end
        for _, cp in ipairs(fs.halo) do
            if cp:IsShown() and cp.haloCol then cp:SetTextColor(cp.haloCol[1], cp.haloCol[2], cp.haloCol[3], (hl.alpha or 0.4) * k) end
        end
    end
    Pulse(f.titleFS)
    for _, row in ipairs(shoppingListRowPool) do
        if row:IsShown() then Pulse(row.itemText) end
    end
end

-- Gilded plate (style.sheen): a band of light sweeps across the metal now and then. Two gradient halves
-- (rising, falling), added light on the top page behind the words, kept inside the plate's face
-- (style.inset) so it never spills past the rim.
function P.LayoutSheen(f)
    if not f or not f.topSheet then return end
    local sh = P.GetStyle().sheen
    if not sh then
        if f.sheen then f.sheen.a:Hide(); f.sheen.b:Hide() end
        f.sheenOn = false
        return
    end
    if not f.sheen then
        local S = {}
        for _, k in ipairs({ "a", "b" }) do
            S[k] = f.topSheet:CreateTexture(nil, "BACKGROUND", nil, 7)
            if S[k].SetBlendMode then S[k]:SetBlendMode("ADD") end
            S[k]:Hide()
        end
        f.sheen = S
    end
    local c = sh.color
    ApplyHorizontalGradient(f.sheen.a, c[1], c[2], c[3], 0, 1)
    ApplyHorizontalGradient(f.sheen.b, c[1], c[2], c[3], 1, 0)
    f.sheenOn = true
end

function P.AnimateSheen(f, now)
    local st = P.GetStyle()
    local sh, S = st.sheen, f.sheen
    if not (sh and S) then return end
    local w, h = f:GetWidth() or 230, f:GetHeight() or 175
    local ins = st.inset or { 0, 0, 0, 0 }
    local left, right = w * ins[1], w * (1 - ins[3])
    local top, bottom = h * ins[2], h * (1 - ins[4])
    local p = (now % (sh.every or 7)) / (sh.sweep or 1.6)            -- 0..1 while the light passes
    if p >= 1 or right - left < 10 then S.a:Hide(); S.b:Hide(); return end
    local bw = w * (sh.width or 0.22)
    local xc = left - bw / 2 + p * (right - left + bw)
    local alpha = (sh.alpha or 0.3) * math.sin(math.pi * p)
    local function Half(tex, x0, x1)
        x0, x1 = math.max(x0, left), math.min(x1, right)
        if x1 - x0 < 1 then tex:Hide(); return end
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", f.topSheet, "TOPLEFT", x0, -top)
        tex:SetSize(x1 - x0, bottom - top)
        tex:SetAlpha(alpha)
        tex:Show()
    end
    Half(S.a, xc - bw / 2, xc)
    Half(S.b, xc, xc + bw / 2)
end

-- Space between the window's edge and the writing on each side (left, top, right, bottom).
-- Texture looks stretch with the window, so their margins are fractions of it (style.inset: the
-- largest rectangle on the material, measured by TexGen.SafeRect); drawn looks use a fixed pad.
function P.GetPads(f)
    local st = P.GetStyle()
    local pad = st.pad or 0
    local ins = st.inset
    if not ins then return pad, pad, pad, pad end
    local w, h = (f and f:GetWidth()) or 230, (f and f:GetHeight()) or 175
    local function S(frac, size) return math.max(pad, math.floor(frac * size + 0.5)) end
    return S(ins[1], w), S(ins[2], h), S(ins[3], w), S(ins[4], h)
end

-- Keeps the title, close button, list, footer and resize grip on the material
function P.LayoutPads(f)
    if not f or not f.chrome then return end
    local l, t, r, b = P.GetPads(f)
    local key = P.GetStyle().key .. ":" .. l .. ":" .. t .. ":" .. r .. ":" .. b
    if f.padKey == key then return end
    f.padKey = key
    f.pad, f.padL, f.padT, f.padR, f.padB = math.min(l, t, r, b), l, t, r, b
    if f.closeBtn then
        f.closeBtn:ClearAllPoints()
        f.closeBtn:SetPoint("TOPRIGHT", f.chrome, "TOPRIGHT", -5 - r, -5 - t)
    end
    if f.titleFS then
        f.titleFS:ClearAllPoints()
        f.titleFS:SetPoint("TOPLEFT", f.chrome, "TOPLEFT", 10 + l, -6 - t)
        f.titleFS:SetPoint("RIGHT", f.itemsBtn or f.optBtn, "LEFT", -6, 0)
    end
    if f.content then
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT", f.chrome, "TOPLEFT", 6 + l, -28 - t)
        f.content:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", -6 - r, 17 + b)
    end
    if f.footerFS then
        f.footerFS:ClearAllPoints()
        f.footerFS:SetPoint("BOTTOMLEFT", f.chrome, "BOTTOMLEFT", 22 + l, 5 + b)
        f.footerFS:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", -30 - r, 5 + b)
    end
    if f.resizeGrip then
        -- texture looks: the grip sits on the material's bottom-left, not out on the background
        local inset = P.GetStyle().inset
        f.resizeGrip:ClearAllPoints()
        f.resizeGrip:SetPoint("BOTTOMLEFT", f.chrome, "BOTTOMLEFT", inset and (1 + l) or 1, inset and (1 + b) or 1)
    end
end

-- A quill stroke: a crisp core line plus a wider, faint "bleed" line so the ink looks absorbed by the paper
function P.NewStroke(parent, layer, sub)
    sub = sub or 4
    return {
        bleed = parent:CreateLine(nil, layer or "OVERLAY", nil, sub - 1),
        main = parent:CreateLine(nil, layer or "OVERLAY", nil, sub),
    }
end

function P.DrawStroke(s, rel, x0, y0, x1, y1, thick, alpha, ink)
    ink = ink or P.INK
    s.main:SetStartPoint("TOPLEFT", rel, x0, y0)
    s.main:SetEndPoint("TOPLEFT", rel, x1, y1)
    s.main:SetThickness(thick)
    s.main:SetColorTexture(ink[1], ink[2], ink[3], alpha)
    s.bleed:SetStartPoint("TOPLEFT", rel, x0 + 0.4, y0 - 0.4)
    s.bleed:SetEndPoint("TOPLEFT", rel, x1 - 0.3, y1 - 0.3)
    s.bleed:SetThickness(thick + (P.BLEED_W or 1.0))      -- wet ink spreads further (style.bleedWidth)
    local bl = P.BLEED                       -- chalk dust, a carved cut's shadow, a pressed lip or arcane light; else the ink soaking in
    if bl then
        s.bleed:SetColorTexture(bl[1], bl[2], bl[3], alpha * bl[4])
    else
        s.bleed:SetColorTexture(ink[1], ink[2], ink[3], alpha * (P.BLEED_A or 0.25))
    end
    s.main:Show()
    s.bleed:Show()
end

function P.HideStroke(s)
    s.main:Hide()
    s.bleed:Hide()
end

-- Greedy word wrap with a measuring FontString, so each struck-through line gets a strike of its own width
function P.WrapLines(measureFS, text, maxW)
    local lines, widths = {}, {}
    local cur, gap = "", ""
    local function Width(s)
        measureFS:SetText(s)
        return measureFS:GetStringWidth() or 0
    end
    -- keep the original spacing between words (e.g. the double space after the count)
    for word, space in string.gmatch(text, "(%S+)(%s*)") do
        local candidate = (cur == "") and word or (cur .. gap .. word)
        if cur ~= "" and Width(candidate) > maxW then
            table.insert(lines, cur)
            cur = word
        else
            cur = candidate
        end
        gap = space
    end
    if cur ~= "" then table.insert(lines, cur) end
    if #lines == 0 then lines[1] = "" end
    for i, ln in ipairs(lines) do
        widths[i] = math.min(maxW, Width(ln))
    end
    return lines, widths
end

-- ----------------------------------------------------------------------------
-- PAGES (one per area) & PAGE ORDER
-- ----------------------------------------------------------------------------
function P.GetAreaIndex(key)
    for i, a in ipairs(P.areas) do
        if a.key == key then return i end
    end
    return 1
end

function P.GetSelectedArea()
    return P.areas[P.GetAreaIndex(P.selectedKey)]
end

function P.GetNeighborArea(dir)
    local n = #P.areas
    if n < 2 then return nil end
    local i = P.GetAreaIndex(P.selectedKey)
    return P.areas[((i - 1 + (dir or 1)) % n) + 1]
end

-- ----------------------------------------------------------------------------
-- DOG-EARED PAGE CORNER (hot corner that turns to the next area's page)
-- Built from 1px scanline strips (no vertex offsets). Drawn looks colour them; texture looks sample the
-- material itself (P.DrawMaterialFold); rigid looks draw a mark instead (see P.DrawCorner):
--   * the folded-over flap (upper-left triangle, paper underside, shaded toward the fold)
--   * the gap the fold leaves (lower-right triangle), showing the page underneath
-- Hovering lifts the corner further, like a thumb about to turn the page.
-- ----------------------------------------------------------------------------
P.CORNER_MAX = 34
P.CORNER_REST = 15
P.CORNER_HOVER = 30

function P.HGradient(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    else
        tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

-- Vertex-colour gradient over whatever the texture already shows (texture looks keep their image)
function P.TexGradient(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    else
        tex:SetVertexColor((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
    end
end

-- One scanline of the fold (the page beneath, the flap, the crease); made when first needed, since a
-- fold that reaches the image's corner can need more rows than the corner button is tall
function P.CornerRow(c, j)
    if not c.under[j] then
        c.under[j] = c:CreateTexture(nil, "ARTWORK", nil, 1)
        c.flap[j] = c:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    c.crease = c.crease or {}
    if not c.crease[j] then c.crease[j] = c:CreateTexture(nil, "ARTWORK", nil, 4) end
    return c.under[j], c.flap[j], c.crease[j]
end

-- The fold on a texture look: an N-px square in the sheet's bottom-right corner (sheet pixels, from
-- the top-left), folded on its diagonal. Each row: the uncovered part past the fold (the same
-- material, in the flap's shadow), the flap (the corner mirrored across the fold, back side up) and a
-- short crease at the fold. All three sample the image, so they only show where there is material.
function P.DrawMaterialFold(c, sheet, pw, ph, N, lift, sqX, sqY)
    local st = P.GetStyle()
    local x0, y0 = sqX or (pw - N), sqY or (ph - N)      -- the square's top-left (default: in the image's corner)
    local function TX(a) return (x0 + a) / pw end
    local function TY(b) return (y0 + b) / ph end
    local d = 0.60 - 0.08 * lift                         -- shadow right under the fold
    local t, k = 1.04 - 0.05 * lift, 0.80 - 0.07 * lift  -- the flap: light at the tip, shaded at the crease
    local cr = 0.42 - 0.06 * lift
    for j = 1, N do
        local under, flap, crease = P.CornerRow(c, j)
        local vTop, vBot = j - 1, j
        local cut = N - (j - 0.5)                        -- where the fold crosses this row
        local uw = N - cut
        local y = -(y0 + vTop)
        under:ClearAllPoints()
        under:SetPoint("TOPLEFT", sheet, "TOPLEFT", x0 + cut, y)
        under:SetSize(math.max(0.5, uw), 1)
        under:SetTexture(st.image)
        under:SetTexCoord(TX(cut), TX(N), TY(vTop), TY(vBot))
        -- the cast shadow fades out over ~18px, however long the row is
        local far = d + (0.88 - d) * math.min(1, uw / 18)
        P.TexGradient(under, d, d, d, 1, far, far, far, 1)
        under:Show()
        if cut > 0.4 then
            flap:ClearAllPoints()
            flap:SetPoint("TOPLEFT", sheet, "TOPLEFT", x0, y)
            flap:SetSize(cut, 1)
            flap:SetTexture(st.image)
            -- what was at (N - v, N - u) now lies at (u, v): the corner mirrored across the fold
            flap:SetTexCoord(
                TX(N - vTop), TY(N),            -- top-left     <- (u = 0,   v = top)
                TX(N - vBot), TY(N),            -- bottom-left  <- (u = 0,   v = bottom)
                TX(N - vTop), TY(N - cut),      -- top-right    <- (u = cut, v = top)
                TX(N - vBot), TY(N - cut))      -- bottom-right <- (u = cut, v = bottom)
            -- light at the tip, shading into the crease over the last ~20px
            local tipV = k + (t - k) * math.min(1, cut / 20)
            P.TexGradient(flap, tipV, tipV, tipV * 0.98, 1, k, k, k * 0.97, 1)
            flap:Show()
        else
            flap:Hide()
        end
        -- the crease: a dark line of the material itself, so it stops where the material does
        local cw = 1.6 + 0.6 * lift
        crease:ClearAllPoints()
        crease:SetPoint("TOPLEFT", sheet, "TOPLEFT", x0 + cut - cw * 0.5, y)
        crease:SetSize(cw, 1)
        crease:SetTexture(st.image)
        crease:SetTexCoord(TX(cut - cw * 0.5), TX(cut + cw * 0.5), TY(vTop), TY(vBot))
        crease:SetVertexColor(cr, cr * 0.95, cr * 0.9, 1)
        crease:Show()
    end
    for j = N + 1, #c.under do
        c.under[j]:Hide(); c.flap[j]:Hide()
        if c.crease[j] then c.crease[j]:Hide() end
    end
    -- the straight drawn edges and lines belong to the drawn looks; the material shows its own
    c.flapTop:Hide(); c.flapLeft:Hide(); c.foldEdge:Hide(); c.foldShadow:Hide()
end

function P.DrawCorner(c)
    local S = math.max(2, math.min(P.CORNER_MAX, c.size or P.CORNER_REST))
    local st = P.GetStyle()
    local parent = c:GetParent()
    local pw, ph = (parent and parent:GetWidth()) or 0, (parent and parent:GetHeight()) or 0
    local key = math.floor(S * 4 + 0.5) .. ":" .. st.key .. ":" .. math.floor(pw) .. ":" .. math.floor(ph)
    if c.drawnKey == key then return end
    c.drawnKey = key

    local ox = P.CORNER_MAX - S              -- the active corner sits in the bottom-right of the button
    local lift = (S - P.CORNER_REST) / (P.CORNER_HOVER - P.CORNER_REST)   -- 0 at rest, 1 fully lifted
    if lift < 0 then lift = 0 elseif lift > 1 then lift = 1 end
    local n = math.floor(S + 0.5)
    local cs = st.corner
    local u1, u2, tip, cr = cs.u1, cs.u2, cs.tip, cs.crease
    local tipK = 1 - 0.06 * lift

    -- Rigid looks (stone, bark, arcane) can't fold: a dog-ear is chalked, carved or drawn in light instead,
    -- drawn bigger on hover. foldShadow becomes the dust / the cut's shadow / the glow beside the diagonal.
    if st.rigid then
        for j = 1, #c.under do c.under[j]:Hide(); c.flap[j]:Hide() end
        for j = 1, #(c.crease or {}) do c.crease[j]:Hide() end
        local e, sh = cs.edge, st.inkShadow
        local th = 1.4 + 0.4 * lift
        local function Mark(line, x0, y0, x1, y1)
            line:SetStartPoint("TOPLEFT", c, x0, y0)
            line:SetEndPoint("TOPLEFT", c, x1, y1)
            line:SetThickness(th)
            line:SetColorTexture(e[1], e[2], e[3], e[4])
            line:Show()
        end
        Mark(c.foldEdge, ox + S, -ox, ox, -(ox + S))
        Mark(c.flapTop, ox, -ox, ox + S, -ox)
        Mark(c.flapLeft, ox, -ox, ox, -(ox + S))
        local sx, sy = (sh and sh[5]) or 1, (sh and sh[6]) or 0
        c.foldShadow:SetStartPoint("TOPLEFT", c, ox + S + sx, -ox + sy)
        c.foldShadow:SetEndPoint("TOPLEFT", c, ox + sx, -(ox + S) + sy)
        c.foldShadow:SetThickness(th)
        c.foldShadow:SetColorTexture(cs.shadow[1], cs.shadow[2], cs.shadow[3], (sh and sh[4] or 0.3) * 0.8)
        c.foldShadow:Show()
        return
    end

    -- Texture looks: the fold runs right across the material, so everything past the fold line folds
    -- over. The square reaches the image's own corner (not just the material's), which makes the flap's
    -- outline the material's real edge (curved, lobed, torn) mirrored, and the uncovered part follow
    -- that edge too: transparent texels stay transparent. Square-local point (a, b) (a right, b down
    -- from the square's top-left) -> texture coords of the sheet. The fold is as far in from the
    -- material's corner (P.PlaceCorner) as on other looks; the square just grows by that inset.
    local img = st.image and pw > 0 and ph > 0
    if img then
        local offX, offY = c.offX or 0, c.offY or 0
        if st.foldAtEdge then
            -- an edge that runs along the fold (the leaf's long side) would fold over its whole length:
            -- keep the square on the material's corner instead
            P.DrawMaterialFold(c, parent, pw, ph, n, lift, pw + offX - n, ph - offY - n)
        else
            local N = math.max(n, math.floor(S + math.max(0, -offX) + math.max(0, offY) + 0.5))
            P.DrawMaterialFold(c, parent, pw, ph, N, lift)
        end
        return
    end

    for j = 1, #c.under do
        local under, flap = c.under[j], c.flap[j]
        if j <= n then
            local y = -(ox + j - 1)
            local cut = S - (j - 0.5)              -- where the fold line crosses this row
            if cut < 0 then cut = 0 end
            local uw = S - cut
            local vTop, vBot = j - 1, j
            under:ClearAllPoints()
            under:SetPoint("TOPLEFT", c, "TOPLEFT", ox + cut, y)
            under:SetSize(math.max(0.5, uw), 1)
            -- the page beneath, darkened right under the fold where the flap shades it
            under:SetTexCoord(0, 1, 0, 1)
            P.HGradient(under, u1[1], u1[2], u1[3], 1, u2[1], u2[2], u2[3], 1)
            under:Show()

            if cut > 0.4 then
                flap:ClearAllPoints()
                flap:SetPoint("TOPLEFT", c, "TOPLEFT", ox, y)
                flap:SetSize(cut, 1)
                flap:SetTexCoord(0, 1, 0, 1)
                -- underside of the parchment: lighter at the tip, shading into the crease
                P.HGradient(flap, tip[1] * tipK, tip[2] * tipK, tip[3] * tipK, 1,
                    cr[1] - 0.08 * lift, cr[2] - 0.08 * lift, cr[3] - 0.06 * lift, 1)
                flap:Show()
            else
                flap:Hide()
            end
        else
            under:Hide()
            flap:Hide()
        end
    end
    for j = 1, #(c.crease or {}) do c.crease[j]:Hide() end
    c.flapTop:Show(); c.flapLeft:Show(); c.foldEdge:Show(); c.foldShadow:Show()

    -- crease, cast shadow and the flap's cut edges
    c.foldShadow:SetStartPoint("TOPLEFT", c, ox + S + 1.2, -ox - 1.2)
    c.foldShadow:SetEndPoint("TOPLEFT", c, ox + 1.2, -(ox + S) - 1.2)
    c.foldShadow:SetThickness(2.5 + 2 * lift)
    c.foldShadow:SetColorTexture(cs.shadow[1], cs.shadow[2], cs.shadow[3], 0.20 + 0.15 * lift)
    c.foldEdge:SetStartPoint("TOPLEFT", c, ox + S, -ox)
    c.foldEdge:SetEndPoint("TOPLEFT", c, ox, -(ox + S))
    c.foldEdge:SetThickness(1)
    c.foldEdge:SetColorTexture(cs.edge[1], cs.edge[2], cs.edge[3], cs.edge[4])
    c.flapTop:SetStartPoint("TOPLEFT", c, ox, -ox)
    c.flapTop:SetEndPoint("TOPLEFT", c, ox + S, -ox)
    c.flapTop:SetThickness(1)
    c.flapTop:SetColorTexture(cs.cut[1], cs.cut[2], cs.cut[3], cs.cut[4])
    c.flapLeft:SetStartPoint("TOPLEFT", c, ox, -ox)
    c.flapLeft:SetEndPoint("TOPLEFT", c, ox, -(ox + S))
    c.flapLeft:SetThickness(1)
    c.flapLeft:SetColorTexture(cs.cut[1], cs.cut[2], cs.cut[3], cs.cut[4])
end

function P.CreateCorner(f, parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(P.CORNER_MAX, P.CORNER_MAX)
    c:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 3, -3)   -- also covers the torn rim at the corner
    c:SetFrameLevel((f.baseLevel or 30) + 22)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.size, c.target = P.CORNER_REST, P.CORNER_REST
    c.under, c.flap = {}, {}
    for j = 1, P.CORNER_MAX do
        c.under[j] = c:CreateTexture(nil, "ARTWORK", nil, 1)
        c.flap[j] = c:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    c.foldShadow = c:CreateLine(nil, "ARTWORK", nil, 2)
    c.foldEdge = c:CreateLine(nil, "ARTWORK", nil, 5)
    c.flapTop = c:CreateLine(nil, "ARTWORK", nil, 4)
    c.flapLeft = c:CreateLine(nil, "ARTWORK", nil, 4)

    c:SetScript("OnEnter", function(self)
        self.target = P.CORNER_HOVER
        local nxt, prev = P.GetNeighborArea(1), P.GetNeighborArea(-1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Turn the page", 1, 0.82, 0)
        if nxt then
            GameTooltip:AddLine(string.format("Next: %s  (%d left)", nxt.title or "Elsewhere", nxt.remaining or 0), 0.9, 0.9, 0.9)
        end
        if prev and prev ~= nxt then
            GameTooltip:AddLine(string.format("Back: %s", prev.title or "Elsewhere"), 0.75, 0.75, 0.75)
        end
        GameTooltip:AddLine("Left-Click: next page  |  Right-Click: previous page", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self)
        self.target = P.CORNER_REST
        GameTooltip:Hide()
    end)
    c:SetScript("OnClick", function(_, button)
        P.TurnPage((button == "RightButton") and -1 or 1)
    end)

    P.DrawCorner(c)
    return c
end

function P.UpdateCorner(f)
    if not f.corner then return end
    local multi = #P.areas > 1
    f.corner:SetShown(multi)
    if multi then
        P.PlaceCorner(f)          -- texture looks: follows the image's corner as the window is resized
        P.DrawCorner(f.corner)
    end
end

-- ----------------------------------------------------------------------------
-- STACK LAYOUT, PAGE-TURN ANIMATION & PER-FRAME DRIVER
-- ----------------------------------------------------------------------------
function P.ApplyStackLayout(f)
    if not f.topSheet then return end
    local w, h = f:GetWidth(), f:GetHeight()
    if not w or w < 20 or not h or h < 20 then return end
    local sh = f.shuffle
    local t = sh and math.min(1, sh.t) or 0
    local dir = (sh and sh.dir) or 1
    local pulse = math.sin(math.pi * t)
    local wob = math.sin(2 * math.pi * t)

    f.shadowSheet:Layout(w, h, 0.004, 3, -4)
    local visible = f.visibleBackSheets or 0
    local fan = P.GetStyle().fan
    for k = 1, P.MAX_BACK_SHEETS do
        local s = f.backSheets[k]
        if k <= visible then
            local slot = P.BACK_SLOTS[k]
            local sign = (k % 2 == 0) and -1 or 1
            s:Show()
            if fan then
                -- fanned (leaf): turn about the stem, not the middle: shift by pivot - rotated pivot
                local a = fan.angles[k] + wob * 0.02 * sign
                local px = fan.pivot * w
                s:Layout(w, h, a, px * (1 - math.cos(a)) - pulse * dir * 3 * k, -px * math.sin(a))
            else
                s:Layout(w, h, slot.angle + wob * 0.02 * sign, slot.dx - pulse * dir * 3 * k, slot.dy)
            end
        else
            s:Hide()
        end
    end
    -- Page turn: the top sheet is lifted by its corner and slid aside, then the next one settles in
    f.topSheet:Layout(w, h, -dir * 0.09 * pulse, dir * 38 * pulse, -10 * pulse)
    f.chrome:SetAlpha(sh and math.abs(1 - 2 * t) or 1)
end

function P.SelectArea(key, animate, dir)
    local f = shoppingListFrame
    if not f or not key then return end
    if key == P.selectedKey and not f.shuffle then return end
    if animate and f:IsShown() then
        f.shuffle = { t = 0, dur = 0.55, key = key, swapped = false, dir = dir or 1 }
    else
        P.selectedKey = key
        shoppingScrollOffset = 0
        UpdateShoppingListUI()
    end
end

function P.TurnPage(dir)
    local f = shoppingListFrame
    if not f or f.shuffle then return end
    local a = P.GetNeighborArea(dir or 1)
    if a then P.SelectArea(a.key, true, dir or 1) end
end

function P.OnUpdate(f, elapsed)
    local dt = math.min(math.max(elapsed or 0, 0.001), 0.05)

    if f.shuffle then
        local sh = f.shuffle
        sh.t = sh.t + dt / sh.dur
        if sh.t >= 0.5 and not sh.swapped then
            sh.swapped = true
            P.selectedKey = sh.key
            shoppingScrollOffset = 0
            UpdateShoppingListUI()
            if not f:IsShown() then
                f.shuffle = nil
                return
            end
        end
        if sh.t >= 1 then f.shuffle = nil end
        P.ApplyStackLayout(f)
    end

    if next(P.fxRows) then P.AnimateRowFX(GetTime()) end
    if f.arcaneOn then
        P.AnimateArcane(f, GetTime())
    elseif P.HALO and P.HALO.pulse then
        P.PulseHalo(f, GetTime())
    end
    if f.sheenOn then P.AnimateSheen(f, GetTime()) end

    local c = f.corner
    if c and c:IsShown() then
        local d = (c.target or P.CORNER_REST) - (c.size or P.CORNER_REST)
        if math.abs(d) > 0.01 then
            if math.abs(d) < 0.25 then
                c.size = c.target
            else
                c.size = c.size + d * math.min(1, dt * 12)
            end
            P.DrawCorner(c)
        end
    end
end

-- When the player enters a new area, its page is fresh ink (red title for a few seconds) and,
-- optionally, gets turned back to the top of the pile.
function P.CheckAreaChange(f)
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    local sig = zone .. "|" .. sub
    if P.lastAreaSig == nil then
        P.lastAreaSig = sig
        return
    end
    if sig == P.lastAreaSig then return end
    P.lastAreaSig = sig
    P.currentGlowUntil = GetTime() + 7

    if CFQ.parchmentOpts.autoFrontOnAreaChange and P.selectedKey ~= P.CURRENT_KEY then
        if f:IsShown() and not f.shuffle then
            f.shuffle = { t = 0, dur = 0.55, key = P.CURRENT_KEY, swapped = false, dir = -1 }
        elseif not f.shuffle then
            P.selectedKey = P.CURRENT_KEY
            shoppingScrollOffset = 0
        end
    end
end

-- ----------------------------------------------------------------------------
-- CHECKLIST ROWS (hand-inked box, quill tick, per-line strike-through)
-- ----------------------------------------------------------------------------
local function AcquireShoppingListRow(idx, parent)
    local row = shoppingListRowPool[idx]
    if row then return row end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.seed = idx * 13.7

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.45, 0.30, 0.08, 0.10)

    -- Hand-drawn box: four slightly crooked quill strokes that overshoot their corners
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(11, 11)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -4)
    box.wash = box:CreateTexture(nil, "BACKGROUND")
    box.wash:SetAllPoints()
    box.wash:SetColorTexture(0.55, 0.40, 0.18, 0.06)

    local function J(k) return (P.Hash01(row.seed, k, 3) - 0.5) * 1.2 end
    local corners = {
        { 0 + J(1), 0 + J(2) }, { 11 + J(3), 0 + J(4) }, { 11 + J(5), -11 + J(6) }, { 0 + J(7), -11 + J(8) },
    }
    box.sides = {}
    box.corners = corners
    for k = 1, 4 do
        box.sides[k] = P.NewStroke(box, "ARTWORK", 3)
    end
    P.DrawBoxSides(box)

    -- Quill tick: heavy short down-stroke, then a long flick up and out past the box's top-right
    box.tick = { P.NewStroke(box, "OVERLAY", 5), P.NewStroke(box, "OVERLAY", 5), P.NewStroke(box, "OVERLAY", 5) }
    for _, s in ipairs(box.tick) do P.HideStroke(s) end
    row.box = box

    row.itemText = row:CreateFontString(nil, "OVERLAY")
    P.SetInkFont(row.itemText, "item")
    row.itemText:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 2)
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetJustifyV("TOP")
    row.itemText:SetWordWrap(true)
    row.itemText:SetTextColor(P.INK[1], P.INK[2], P.INK[3], 1)

    -- "(turn in)" note: separate so the strike-through never runs through it
    row.suffixText = row:CreateFontString(nil, "OVERLAY")
    P.SetInkFont(row.suffixText, "small")
    row.suffixText:SetJustifyH("LEFT")
    row.suffixText:SetTextColor(P.INK_GREEN[1], P.INK_GREEN[2], P.INK_GREEN[3], 1)
    row.suffixText:Hide()

    row.strikes = {}

    -- Faint ruled line under each entry, like a ledger
    row.divider = row:CreateTexture(nil, "BACKGROUND")
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    row.divider:SetColorTexture(0.45, 0.32, 0.15, 0.14)

    shoppingListRowPool[idx] = row
    P.StyleRow(row)
    return row
end

-- the box's four crooked strokes, in the current ink
function P.DrawBoxSides(box)
    local corners = box.corners
    for k = 1, 4 do
        local a, b = corners[k], corners[(k % 4) + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len, dy / len
        P.DrawStroke(box.sides[k], box, a[1] - ux * 0.4, a[2] - uy * 0.4, b[1] + ux * 1.1, b[2] + uy * 1.1, 1.05, 0.72)
    end
end

-- re-inks a row after the look changes
function P.StyleRow(row)
    local st = P.GetStyle()
    if row.styleKey == st.key then return end
    row.styleKey = st.key
    local h, d = st.highlight, st.divider
    row.highlight:SetColorTexture(h[1], h[2], h[3], h[4])
    row.divider:SetColorTexture(d[1], d[2], d[3], d[4])
    P.DrawBoxSides(row.box)
    row.suffixText:SetTextColor(st.inkGreen[1], st.inkGreen[2], st.inkGreen[3], 1)
    if row.lasso then row.lassoKey = nil end
end

-- ----------------------------------------------------------------------------
-- INK EFFECTS: a warm glow when you're in an item's hunting grounds, flames when your
-- target drops it (or is one to slay), and a red ink circle round the lines of the quest you're tracking
-- ----------------------------------------------------------------------------
function P.EnsureRowFX(row)
    if row.fx then return row.fx end
    local fx = { inner = {}, outer = {}, all = {} }
    -- copies of the words nudged a pixel or two in every direction under the ink: only their edges
    -- show, which reads as a halo (glow) or a licking flame.
    local function Copy(list, sub, ox, oy)
        local fs = row:CreateFontString(nil, "ARTWORK", nil, sub)
        fs:SetPoint("TOPLEFT", row.itemText, "TOPLEFT", ox, oy)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:Hide()
        table.insert(list, fs)
        table.insert(fx.all, fs)
    end
    for k = 0, 7 do
        local a = k * math.pi / 4
        Copy(fx.inner, 2, math.cos(a) * 1.2, math.sin(a) * 1.2)
    end
    for k = 0, 3 do
        local a = math.pi / 4 + k * math.pi / 2
        Copy(fx.outer, 1, math.cos(a) * 2.4, math.sin(a) * 2.4 + 0.6)   -- a touch higher: heat rises
    end
    -- heat haze rising off the line
    fx.haze = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    fx.haze:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 16, 1)
    fx.haze:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 2)
    fx.haze:Hide()
    fx.embers = {}
    for k = 1, 6 do
        local e = row:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetSize(2, 2)
        e:Hide()
        fx.embers[k] = e
    end
    row.fx = fx
    return fx
end

-- mode: nil (off), "glow" (hunting grounds), "fire" (your target drops it) or "smoulder" (it might)
-- key: the item's progKey (rows are pooled, so a row can show a different item after a re-render)
function P.SetRowFX(row, mode, plainText, textW, key)
    if not mode and not row.fx then return end
    local fx = P.EnsureRowFX(row)
    if not mode then
        row.fxMode, row.fxKey, row.fxSince = nil, nil, nil
        for _, fs in ipairs(fx.all) do fs:Hide() end
        fx.haze:Hide()
        for _, e in ipairs(fx.embers) do e:Hide() end
        P.fxRows[row] = nil
        return
    end
    if row.fxMode ~= mode or row.fxKey ~= key or not row.fxSince then row.fxSince = GetTime() end
    row.fxMode, row.fxKey = mode, key
    local path, size, flags = row.itemText:GetFont()
    path = path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    size = size or 12
    for _, fs in ipairs(fx.all) do
        fs:SetFont(path, size, flags or "")
        fs:SetWidth(textW)
        fs:SetText(plainText)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
        fs:Show()
    end
    if mode == "fire" then
        ApplyTwoColorVerticalGradient(fx.haze, 1.0, 0.45, 0.05, 0.30, 1.0, 0.70, 0.10, 0.0)
        fx.haze:Show()
    else
        fx.haze:Hide()
        for _, e in ipairs(fx.embers) do e:Hide() end
    end
    row.fxTextW = textW
    P.fxRows[row] = true
end
P.fxRows = setmetatable({}, { __mode = "k" })

-- per-frame flicker / pulse for every row that has an effect on
function P.AnimateRowFX(now)
    for row in pairs(P.fxRows) do
        local fx, mode = row.fx, row.fxMode
        if not (fx and mode and row:IsShown()) then
            P.fxRows[row] = nil
        elseif mode == "glow" then
            -- slow breathing gold; brighter for the first few seconds after you walk in
            local fresh = math.max(0, 1 - (now - (row.fxSince or now)) / 4)
            local a = 0.30 + 0.22 * (0.5 + 0.5 * math.sin(now * 2.6 + (row.seed or 0))) + 0.35 * fresh
            for _, fs in ipairs(fx.outer) do fs:SetTextColor(1.0, 0.72, 0.20, a * 0.45) end
            for _, fs in ipairs(fx.inner) do fs:SetTextColor(1.0, 0.88, 0.45, a * 0.75) end
        else
            -- flames ("fire": known dropper) or a smoulder ("smoulder": only the names suggest it):
            -- two out-of-phase flickers, colour sliding between deep orange and yellow
            local heat = (mode == "fire") and 1 or 0.45
            local s = row.seed or 0
            local f1 = 0.55 + 0.25 * math.sin(now * 17 + s) + 0.20 * math.sin(now * 29 + s * 2)
            local f2 = 0.55 + 0.25 * math.sin(now * 23 + s * 3) + 0.20 * math.sin(now * 11 + s)
            local flare = heat * math.max(0, 1 - (now - (row.fxSince or now)) / 2.5)   -- big flare-up as it catches
            for i, fs in ipairs(fx.outer) do
                -- each tongue of flame flickers on its own
                local fi = 0.5 + 0.5 * math.sin(now * (13 + i * 3) + s + i)
                fs:SetTextColor(1.0, 0.28 + 0.15 * f2, 0.04, heat * math.min(1, 0.25 + 0.45 * fi * f1 + 0.25 * flare))
            end
            for _, fs in ipairs(fx.inner) do
                fs:SetTextColor(1.0, 0.62 + 0.30 * f1, 0.12 + 0.20 * f2, heat * math.min(1, 0.50 + 0.35 * f2 + 0.15 * flare))
            end
            fx.haze:SetAlpha(0.55 + 0.45 * f1)
            local w = math.max(20, math.min(row.fxTextW or 100, (row.itemText:GetStringWidth() or 100)))
            local h = row:GetHeight() or 20
            local nEmbers = (mode == "fire") and #fx.embers or 2
            for k, e in ipairs(fx.embers) do
              if k > nEmbers then
                e:Hide()
              else
                -- each ember rises from the words, drifts and fades, then is re-lit somewhere else
                local speed = 0.55 + 0.35 * P.Hash01(s, k, 1)
                local t = now * speed + P.Hash01(s, k, 2)
                local cycle = math.floor(t)
                local p = t - cycle
                local x = 18 + w * P.Hash01(s, k, cycle) + math.sin(t * 6 + k) * 2
                e:ClearAllPoints()
                e:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 2 + p * (h + 6))
                e:SetColorTexture(1.0, 0.55 + 0.4 * (1 - p), 0.1, (1 - p) * 0.95 * heat)
                e:Show()
              end
            end
        end
    end
end

-- red ink circled round the box of an item whose quest you're tracking
function P.SetRowLasso(row, on)
    if not on then
        if row.lasso then for _, s in ipairs(row.lasso) do P.HideStroke(s) end end
        return
    end
    if not row.lasso then
        row.lasso = {}
        for k = 1, 9 do row.lasso[k] = P.NewStroke(row.box, "OVERLAY", 7) end
    end
    local n = #row.lasso
    local cx, cy, rx, ry = 5.5, -5.5, 9.5, 8.5
    local prevX, prevY
    for k = 0, n do
        -- a loop that doesn't quite close, overshooting where the quill started
        local a = -0.6 + (k / n) * (2 * math.pi + 0.5)
        local wob = 1 + (P.Hash01(row.seed, k, 7) - 0.5) * 0.12
        local x, y = cx + math.cos(a) * rx * wob, cy + math.sin(a) * ry * wob
        if prevX then
            P.DrawStroke(row.lasso[k], row.box, prevX, prevY, x, y, 1.2, 0.85, P.INK_RED)
        end
        prevX, prevY = x, y
    end
end

function P.ShowTick(box, seed)
    local w = (P.Hash01(seed, 9, 1) - 0.5) * 1.6
    P.DrawStroke(box.tick[1], box, 1.5, -5.0 + w * 0.3, 4.6, -9.6, 2.1, 0.93)        -- down-stroke
    P.DrawStroke(box.tick[2], box, 4.6, -9.6, 10.6 + w, 0.4, 1.6, 0.93)              -- up-stroke
    P.DrawStroke(box.tick[3], box, 10.6 + w, 0.4, 14.2 + w, 4.2, 0.8, 0.70)          -- tapering flick
end

function P.HideTick(box)
    for _, s in ipairs(box.tick) do P.HideStroke(s) end
end

function P.GetStrike(row, k)
    local s = row.strikes[k]
    if not s then
        s = P.NewStroke(row, "OVERLAY", 6)
        row.strikes[k] = s
    end
    return s
end

function P.HideStrikes(row)
    for _, s in ipairs(row.strikes) do P.HideStroke(s) end
end

-- Gear icon with a safe text fallback (no custom art files required)
function CFQ.ApplyGearIcon(btn, r, g, b, fallbackText, fontSize)
    local atlases = { "QuestLog-icon-setting", "GM-icon-settings", "Options_Gear" }
    if C_Texture and C_Texture.GetAtlasInfo then
        for _, atlas in ipairs(atlases) do
            local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
            if ok and info then
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetAllPoints()
                btn.icon:SetAtlas(atlas)
                btn.icon:SetVertexColor(r, g, b)
                btn.iconColor = { r, g, b }
                return true
            end
        end
    end
    btn.txt = btn:CreateFontString(nil, "OVERLAY")
    btn.txt:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize or 10, "OUTLINE")
    btn.txt:SetPoint("CENTER")
    btn.txt:SetText(fallbackText)
    btn.txt:SetTextColor(r, g, b)
    btn.iconColor = { r, g, b }
    return false
end

function CFQ.SetGearHover(btn, hovered)
    local c = btn.iconColor or { 1, 1, 1 }
    local r, g, b = c[1], c[2], c[3]
    if hovered then r, g, b = 1.0, 0.82, 0.0 end
    if btn.icon then btn.icon:SetVertexColor(r, g, b) end
    if btn.txt then btn.txt:SetTextColor(r, g, b) end
end

-- ----------------------------------------------------------------------------
-- FRAME CONSTRUCTION
-- ----------------------------------------------------------------------------
local function EnsureShoppingListFrame()
    if shoppingListFrame then return shoppingListFrame end

    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local f = CreateFrame("Frame", "QRF_ClusterShoppingList", UIParent)
    f:SetFrameStrata("MEDIUM")
    f.baseLevel = 30
    f:SetFrameLevel(f.baseLevel)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f.visibleBackSheets = 0
    shoppingListFrame = f
    P.ApplyPosition(f)

    local function SavePoint(self)
        local pt, _, relPt, xOfs, yOfs = self:GetPoint(1)
        if pt then
            shoppingListCfg.point = pt
            shoppingListCfg.relPoint = relPt or pt
            shoppingListCfg.x = math.floor((xOfs or 0) + 0.5)
            shoppingListCfg.y = math.floor((yOfs or 0) + 0.5)
            shoppingListCfg.useDefaultAnchor = false
        end
    end

    f:SetScript("OnDragStart", function(self)
        if not self.isResizing then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint(self)
        SaveState()
    end)

    -- Page pile (bottom to top): drop shadow, up to 3 pages underneath, the top page.
    -- Colours and edge shapes come from the chosen look (P.ApplyStyle at the end).
    local base = f.baseLevel
    local st = P.GetStyle()
    f.shadowSheet = P.CreateSheet(f, 11, {
        paper = { 0, 0, 0, st.shadowAlpha or 0 }, depth = 4, minDepth = 1, segW = 14, overlap = 0,
    })
    f.shadowSheet:SetFrameLevel(base + 1)

    f.backSheets = {}
    for k = 1, P.MAX_BACK_SHEETS do
        local sh = P.CreateSheet(f, 20 + k * 7, {
            paper = st.back[k], rim = st.backRim, depth = st.backDepth, minDepth = st.backMinDepth, segW = st.backSegW,
        })
        sh:SetFrameLevel(base + 5 - k)   -- back1 (closest) = base+4 ... back3 = base+2
        f.backSheets[k] = sh
    end

    f.topSheet = P.CreateSheet(f, 7, {
        paper = st.paper, rim = st.rim, depth = st.depth, minDepth = st.minDepth, segW = st.segW,
        grain = st.grain, shade = st.shade, hem = st.hem, decor = true,
    })
    f.topSheet:SetFrameLevel(base + 12)

    -- Chrome: everything written on the top page (moves & fades with it during a page turn)
    local chrome = CreateFrame("Frame", nil, f.topSheet)
    chrome:SetAllPoints(f.topSheet)
    chrome:SetFrameLevel(base + 17)
    f.chrome = chrome

    -- Close (×), inked
    local closeBtn = CreateFrame("Button", nil, chrome)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(base + 19)
    closeBtn.txt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtn.txt:SetFont(fontPath, 13, "")
    closeBtn.txt:SetPoint("CENTER")
    closeBtn.txt:SetText("×")
    closeBtn.txt:SetTextColor(0.40, 0.25, 0.11)
    closeBtn:SetScript("OnEnter", function(self)
        self.txt:SetTextColor(P.INK_RED[1], P.INK_RED[2], P.INK_RED[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Put the Field Tally away", 1, 0.82, 0)
        GameTooltip:AddLine("Bring it back in HandkerSheaf Options (gear above the tracker) or with /hanky list", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function(self)
        local cc = P.GetStyle().close
        self.txt:SetTextColor(cc[1], cc[2], cc[3])
        GameTooltip:Hide()
    end)
    f.closeBtn = closeBtn
    closeBtn:SetScript("OnClick", function()
        showShoppingList = false
        f:Hide()
        SaveState()
        if CFQ.RefreshOptionsPanel then CFQ.RefreshOptionsPanel() end
    end)

    -- Options gear -> HandkerSheaf options panel
    local optBtn = CreateFrame("Button", nil, chrome)
    optBtn:SetSize(13, 13)
    optBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    optBtn:SetFrameLevel(base + 19)
    if not CFQ.ApplyGearIcon(optBtn, 0.42, 0.26, 0.09, "opt", 9) then
        optBtn:SetSize(20, 14)
    end
    optBtn:SetScript("OnEnter", function(self)
        CFQ.SetGearHover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("HandkerSheaf Options", 1, 0.82, 0)
        GameTooltip:AddLine("Look, handwriting, tracker & map settings", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-Click: reset the parchment's size & position", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    optBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    optBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ResetShoppingListPosition()
        elseif CFQ.OpenOptions then
            CFQ.OpenOptions()
        end
    end)
    optBtn:SetScript("OnLeave", function(self)
        CFQ.SetGearHover(self, false)
        GameTooltip:Hide()
    end)
    f.optBtn = optBtn

    -- Items / tasks / tasks apart toggles, left of the gear (full ink = on, faded = off)
    f.quickBtns = {}
    for _, kind in ipairs(P.QUICK_ORDER) do f.quickBtns[kind] = P.CreateQuickButton(chrome, base + 19, kind) end
    f.itemsBtn, f.tasksBtn, f.sepBtn = f.quickBtns.items, f.quickBtns.tasks, f.quickBtns.separate
    f.sepBtn:SetPoint("RIGHT", optBtn, "LEFT", -P.QUICK_GEAR_GAP, 0)
    f.tasksBtn:SetPoint("RIGHT", f.sepBtn, "LEFT", -P.QUICK_GAP, 0)
    f.itemsBtn:SetPoint("RIGHT", f.tasksBtn, "LEFT", -P.QUICK_GAP, 0)

    -- Page heading (area name) in handwriting, with a quill-ruled underline
    local titleFS = chrome:CreateFontString(nil, "OVERLAY")
    P.SetInkFont(titleFS, "title")
    titleFS:SetPoint("TOPLEFT", chrome, "TOPLEFT", 10, -6)
    titleFS:SetPoint("RIGHT", f.itemsBtn, "LEFT", -6, 0)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    if titleFS.SetMaxLines then titleFS:SetMaxLines(1) end
    titleFS.singleLine = true          -- its bold pass / wet-ink copies cut off with it, never wrap under it
    titleFS:SetTextColor(P.INK[1], P.INK[2], P.INK[3], 1)
    f.titleFS = titleFS
    f.titleRule = P.NewStroke(chrome, "ARTWORK", 4)
    f.titleRule2 = P.NewStroke(chrome, "ARTWORK", 4)

    -- Hidden measuring string for the hand-wrapped (struck-through) lines
    f.measureFS = chrome:CreateFontString(nil, "OVERLAY")
    f.measureFS:SetAlpha(0)
    f.measureFS:SetWordWrap(false)

    -- Content Container for Checklist Rows
    local content = CreateFrame("Frame", nil, chrome)
    content:SetPoint("TOPLEFT", chrome, "TOPLEFT", 6, -28)
    content:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -6, 17)
    content:SetFrameLevel(base + 18)
    f.content = content

    -- Footer (tally + page number), clear of the resize grip (left) and the dog-ear (right)
    local footerFS = chrome:CreateFontString(nil, "OVERLAY")
    P.SetInkFont(footerFS, "small")
    footerFS:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 22, 5)
    footerFS:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -30, 5)
    footerFS:SetJustifyH("LEFT")
    footerFS:SetWordWrap(false)
    footerFS:SetTextColor(0.36, 0.22, 0.08, 0.95)
    f.footerFS = footerFS

    f:SetScript("OnMouseWheel", function(_, delta)
        local total = f.totalItems or 0
        local maxScroll = math.max(0, total - 1)
        shoppingScrollOffset = math.min(maxScroll, math.max(0, shoppingScrollOffset - delta))
        P.Render(f)
    end)

    -- Dog-eared corner (bottom-right): the page-turn hot corner
    f.corner = P.CreateCorner(f, chrome)

    -- Resize grip (bottom-left, so the dog-ear owns the bottom-right corner)
    local resizeGrip = CreateFrame("Button", nil, chrome)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 1, 1)
    resizeGrip:SetFrameLevel(base + 21)
    f.resizeGrip = resizeGrip
    resizeGrip:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local gripTex = resizeGrip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTex:SetTexCoord(1, 0, 0, 1)         -- mirrored to point into the bottom-left corner
    gripTex:SetVertexColor(0.75, 0.55, 0.30, 0.85)
    resizeGrip.gripTex = gripTex
    f.gripTex = gripTex

    resizeGrip:SetScript("OnEnter", function(self)
        self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        self.gripTex:SetTexCoord(1, 0, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Resize the parchment", 1, 0.82, 0)
        GameTooltip:AddLine("Left-Click & Drag: resize width & height", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-Click: reset size & position", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function(self)
        self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        self.gripTex:SetTexCoord(1, 0, 0, 1)
        GameTooltip:Hide()
    end)

    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ResetShoppingListPosition()
            return
        end
        if button == "LeftButton" then
            f.isResizing = true
            self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            self.gripTex:SetTexCoord(1, 0, 0, 1)
            local scale = f:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            f.resizeStartX = cx / scale
            f.resizeStartY = cy / scale
            f.resizeStartW = f:GetWidth()
            f.resizeStartH = f:GetHeight()
            f.resizeStartRight = f:GetRight()
            f.resizeStartTop = f:GetTop()

            self:SetScript("OnUpdate", function()
                if not f.isResizing then return end
                local s = f:GetEffectiveScale() or 1
                local mx, my = GetCursorPosition()
                mx = mx / s
                my = my / s

                -- dragging the bottom-left corner: the top-right corner stays put
                local newW = math.max(185, math.min(520, f.resizeStartW - (mx - f.resizeStartX)))
                local newH = math.max(95, math.min(520, f.resizeStartH - (my - f.resizeStartY)))

                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", f.resizeStartRight, f.resizeStartTop)
                f:SetSize(newW, newH)
                P.Render(f)
            end)
        end
    end)

    resizeGrip:SetScript("OnMouseUp", function(self)
        if f.isResizing then
            f.isResizing = false
            self:SetScript("OnUpdate", nil)
            self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
            self.gripTex:SetTexCoord(1, 0, 0, 1)
            shoppingListCfg.width = math.floor((f:GetWidth() or 230) + 0.5)
            shoppingListCfg.height = math.floor((f:GetHeight() or 175) + 0.5)
            SavePoint(f)
            SaveState()
            UpdateShoppingListUI()
        end
    end)

    f:SetScript("OnSizeChanged", function(self)
        P.LayoutPads(self)
        P.LayoutInkGrain(self)
        P.LayoutArcane(self)
        P.ApplyStackLayout(self)
    end)
    f:SetScript("OnHide", function(self)
        if CFQ.HideMapPreview then CFQ.HideMapPreview() end
        self.shuffle = nil
        self.chrome:SetAlpha(1)
        if self.corner then self.corner.size, self.corner.target = P.CORNER_REST, P.CORNER_REST end
    end)
    f:SetScript("OnUpdate", P.OnUpdate)

    P.ApplyStyle(f)
    f:Hide()
    return f
end

-- ----------------------------------------------------------------------------
-- AREA GROUPING
-- ----------------------------------------------------------------------------
-- Which tally quests (items or tasks to do) are "near me" (within the proximity radius, or just worked
-- on), plus every eligible quest so the rest can be filed onto area pages.
function P.CollectQuests()
    local playerMapID, px, py = GetPlayerMapPositionSafe()
    local realZoneRaw = strtrim((GetRealZoneText and GetRealZoneText()) or "")
    local subZoneRaw  = strtrim((GetSubZoneText and GetSubZoneText()) or "")
    local realZone = string.lower(realZoneRaw)
    local subZone  = string.lower(subZoneRaw)
    local areaName = (subZoneRaw ~= "" and subZoneRaw) or (realZoneRaw ~= "" and realZoneRaw) or nil
    local nearTol = P.GetNearRadius() / 100
    local now = GetTime()

    local nearSet, eligible = {}, {}
    for qID, qData in pairs(questRewardMap) do
        if not qData.isFromMap and #P.TallyObjectives(qData) > 0 and DoesQuestMatchFilter(qID) then
            table.insert(eligible, qData)
            local near, learnHere = false, false

            -- 1) Distance from you to the quest's objective area (on your map; a quest placed on a
            --    parent or child map, e.g. Elwynn Forest vs Northshire, is translated onto yours)
            local qx, qy = qData.x, qData.y
            if playerMapID and qData.mapID and qx and qy and qData.mapID ~= playerMapID then
                qx, qy = P.TranslatePos(qData.mapID, qx, qy, playerMapID)
            end
            local comparable = playerMapID and px and py and qData.mapID and qx and qy
            qData.playerDist = nil
            if comparable then
                local dx, dy = px - qx, py - qy
                qData.playerDist = math.sqrt(dx * dx + dy * dy)
                if qData.playerDist <= nearTol then
                    near, learnHere = true, true
                end
            end

            -- 2) You just progressed it or targeted one of its mobs (last 3 minutes)
            local t = recentActiveQuests[qID]
            if t and (now - t) < 180 then
                near = true
                if (now - t) < 20 then learnHere = true end
            end

            -- 3) No usable coordinates (e.g. you're in a cave sub-map, or the client has no waypoint):
            --    fall back to wording / zone clues
            if not near and not comparable then
                local lowerHeader = string.lower(qData.header or "")
                -- the quest log heading names your zone or the sub-zone you're in (e.g. "Northshire Valley")
                local isSameZone = lowerHeader ~= "" and (
                    (realZone ~= "" and (lowerHeader == realZone
                        or string.find(realZone, lowerHeader, 1, true) or string.find(lowerHeader, realZone, 1, true)))
                    or (subZone ~= "" and (lowerHeader == subZone
                        or string.find(subZone, lowerHeader, 1, true) or string.find(lowerHeader, subZone, 1, true))))
                if subZone ~= "" and string.len(subZone) >= 4 then
                    local lowerTitle = string.lower(qData.title or "")
                    local lowerObj   = string.lower(qData.objectiveText or "")
                    if string.find(lowerTitle, subZone, 1, true) or string.find(lowerObj, subZone, 1, true) then
                        near, learnHere = true, true
                    end
                end
                if not near and isSameZone and (IsQuestSuperTracked(qID) or (not qData.x and IsQuestWatched(qID))) then
                    near = true
                end
            end

            -- Remember where this quest's objectives are worked so its area page gets a real name
            if learnHere and areaName then
                CFQ.learnedQuestAreas[qID] = areaName
            end
            if near then nearSet[qID] = true end
        end
    end

    return nearSet, eligible, areaName or "Field Tally"
end

-- ----------------------------------------------------------------------------
-- WHAT THE TALLY LISTS: items and/or tasks (two toggle buttons beside the gear), plus a third toggle
-- that puts the tasks under their own heading. Lines otherwise keep the tracker's quest order.
-- ----------------------------------------------------------------------------
P.GROUP_HEADINGS = { items = "Items", tasks = "Tasks" }

-- A line is an item to gather, or a task (enemies to slay and every other quest step)
function P.LineGroup(e)
    return (e.kind == nil or e.kind == "loot") and "items" or "tasks"
end

-- The lines a quest puts on the tally, in the quest's own objective order
function P.TallyObjectives(q)
    local o = CFQ.parchmentOpts
    local list = {}
    if o.tallyLoot then
        for _, ob in ipairs(q.itemObjectives or {}) do table.insert(list, ob) end
    end
    if o.tallyTasks then
        for _, ob in ipairs(q.taskObjectives or {}) do table.insert(list, ob) end
    end
    table.sort(list, function(a, b) return (a.index or 0) < (b.index or 0) end)
    return list
end

function P.ShowsEverything()
    local o = CFQ.parchmentOpts
    return o.tallyLoot and o.tallyTasks and true or false
end

-- "gathered" when the tally only lists items, else "done"
function P.TallyVerb()
    local o = CFQ.parchmentOpts
    return (o.tallyLoot and not o.tallyTasks) and "gathered" or "done"
end

-- Switch items or tasks on/off; the last one on stays on (an empty tally has nothing to click)
function P.SetTallyShows(which, on)
    local o = CFQ.parchmentOpts
    local key = (which == "items") and "tallyLoot" or "tallyTasks"
    local was = o[key]
    o[key] = on and true or false
    if not (o.tallyLoot or o.tallyTasks) then o[key] = was; return false end
    return true
end

-- Tasks apart: items first, then tasks under their own heading, each keeping the usual order
function P.SortTallyRows(items)
    if not CFQ.parchmentOpts.tallySeparate then return items end
    local out = {}
    for _, e in ipairs(items) do if P.LineGroup(e) == "items" then table.insert(out, e) end end
    for _, e in ipairs(items) do if P.LineGroup(e) == "tasks" then table.insert(out, e) end end
    return out
end

function P.FlattenQuests(quests)
    local items = {}
    local doneCount = 0
    for _, qData in ipairs(quests) do
        for _, obj in ipairs(P.TallyObjectives(qData)) do
            if obj.finished then
                doneCount = doneCount + 1
            end
            table.insert(items, {
                qData = qData,
                questID = qData.questID,
                questTitle = qData.title,
                level = qData.level,
                levelHex = qData.levelHex,
                isQuestComplete = qData.isComplete,
                progKey = obj.progKey,
                itemName = obj.itemName,
                numFulfilled = obj.numFulfilled,
                numRequired = obj.numRequired,
                finished = obj.finished,
                kind = obj.kind or "loot",
                single = obj.single,
            })
        end
    end
    return P.SortTallyRows(items), doneCount
end

-- Three little inked toggles left of the gear: items, tasks, tasks apart. Full ink = on, faded = off,
-- red under the mouse. Strokes are { x0, y0, x1, y1 [, thickness x] } from the top-left of a
-- P.QUICK_SIZE square; P.QUICK_GAP = space between them (P.QUICK_GEAR_GAP before the gear).
P.QUICK_SIZE, P.QUICK_GAP, P.QUICK_GEAR_GAP = 16, 6, 7
P.QUICK_GLYPHS = {
    items = {      -- a basket: woven body, rim and a looped handle
        { 1.5, -7.5, 14.5, -7.5, 1.15 },                                  -- rim
        { 2, -7.5, 4, -14.5 }, { 14, -7.5, 12, -14.5 }, { 4, -14.5, 12, -14.5 },   -- sides, bottom
        { 2.9, -11, 13.1, -11, 0.8 },                                      -- weave
        { 6.3, -7.5, 6.8, -14.5, 0.8 }, { 9.7, -7.5, 9.2, -14.5, 0.8 },
        { 4, -7.5, 4.4, -5 }, { 4.4, -5, 5.8, -3 }, { 5.8, -3, 8, -2.2 },                         -- handle
        { 8, -2.2, 10.2, -3 }, { 10.2, -3, 11.6, -5 }, { 11.6, -5, 12, -7.5 },
    },
    tasks = {      -- a sword, point up and to the right
        { 6.2, -9.8, 14.6, -1.4, 1.35 },                                   -- blade
        { 3.4, -7.2, 8.8, -12.6, 1.15 },                                   -- cross-guard
        { 6.2, -9.8, 2.6, -13.4, 1.25 },                                   -- grip
        { 1.6, -14.4, 2.6, -13.4, 2.0 },                                   -- pommel
    },
    separate = {   -- two lists, each with its own bullet
        { 1.4, -3, 3.4, -3, 1.6 }, { 5.6, -3, 14.6, -3 }, { 5.6, -6.2, 12, -6.2 },
        { 1.4, -10, 3.4, -10, 1.6 }, { 5.6, -10, 14.6, -10 }, { 5.6, -13.2, 12, -13.2 },
    },
}
P.QUICK_OPTS = { items = "tallyLoot", tasks = "tallyTasks", separate = "tallySeparate" }
P.QUICK_ORDER = { "items", "tasks", "separate" }      -- left to right

function P.CreateQuickButton(parent, level, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(P.QUICK_SIZE, P.QUICK_SIZE)
    b:SetFrameLevel(level)
    b.kind = kind
    b.strokes = {}
    for i = 1, #P.QUICK_GLYPHS[kind] do b.strokes[i] = P.NewStroke(b, "OVERLAY", 4) end
    b:SetScript("OnEnter", function(self) self.hover = true; P.DrawQuickButton(self); P.QuickButtonTooltip(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; P.DrawQuickButton(self); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) P.OnQuickButtonClick(self) end)
    return b
end

function P.IsQuickOn(b)
    return CFQ.parchmentOpts[P.QUICK_OPTS[b.kind]] and true or false
end

function P.DrawQuickButton(b)
    if not b then return end
    local on = P.IsQuickOn(b)
    b.on = on
    local st = P.GetStyle()
    local ink = b.hover and P.INK_RED or (on and P.INK or (st.faded or P.INK))
    local alpha = on and 1 or 0.40
    if b.hover then alpha = math.max(alpha, 0.85) end
    for i, g in ipairs(P.QUICK_GLYPHS[b.kind]) do
        P.DrawStroke(b.strokes[i], b, g[1], g[2], g[3], g[4], (on and 1.4 or 1.1) * (g[5] or 1), alpha, ink)
    end
end

function P.QuickButtonTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    local on = P.IsQuickOn(b)
    if b.kind == "items" then
        GameTooltip:AddLine("Items: " .. (on and "shown" or "hidden"), 1, 0.82, 0)
        GameTooltip:AddLine("Quest items to loot or gather.", 0.9, 0.9, 0.9, true)
    elseif b.kind == "tasks" then
        GameTooltip:AddLine("Tasks: " .. (on and "shown" or "hidden"), 1, 0.82, 0)
        GameTooltip:AddLine("Enemies to slay and other quest steps.", 0.9, 0.9, 0.9, true)
    else
        GameTooltip:AddLine("Tasks apart: " .. (on and "on" or "off"), 1, 0.82, 0)
        GameTooltip:AddLine(on and "Items first, then the tasks under their own heading."
            or "Items and tasks together, in the tracker's quest order.", 0.9, 0.9, 0.9, true)
    end
    if b.kind ~= "separate" and on and not P.ShowsEverything() then
        GameTooltip:AddLine("One of items or tasks always stays on.", 0.65, 0.65, 0.65, true)
    else
        GameTooltip:AddLine("Click to switch " .. (on and "off" or "on"), 0.65, 0.65, 0.65)
    end
    GameTooltip:Show()
end

function P.OnQuickButtonClick(b)
    local on = P.IsQuickOn(b)
    if b.kind == "separate" then
        CFQ.parchmentOpts.tallySeparate = not on
    else
        P.SetTallyShows(b.kind, not on)
    end
    P.OnTallyChoiceChanged()
    if b.hover then P.QuickButtonTooltip(b) end
end

-- "Tasks apart" headings: small faded writing with a quill rule after it
P.KIND_HEADING_H = 15
function P.DrawKindHeading(f, idx, text, y, w, st)
    f.kindHeads = f.kindHeads or {}
    local h = f.kindHeads[idx]
    if not h then
        h = { fs = f.content:CreateFontString(nil, "OVERLAY"), rule = P.NewStroke(f.content, "ARTWORK", 4) }
        h.fs:SetJustifyH("LEFT")
        h.fs:SetWordWrap(false)
        f.kindHeads[idx] = h
    end
    P.SetInkFont(h.fs, "small")
    local c = st.sub or st.faded
    h.fs:SetTextColor(c[1], c[2], c[3], 1)
    h.fs:SetText(text)
    h.fs:ClearAllPoints()
    h.fs:SetPoint("TOPLEFT", f.content, "TOPLEFT", 2, y - 2)
    h.fs:Show()
    local tw = h.fs:GetStringWidth() or 60
    local ry = y - 8
    if tw + 20 < w then
        h.rule.main:Show(); h.rule.bleed:Show()
        P.DrawStroke(h.rule, f.content, tw + 8, ry, w - 8, ry - 0.5, 0.8, 0.40)
    else
        h.rule.main:Hide(); h.rule.bleed:Hide()
    end
end

function P.HideKindHeadings(f, from)
    for k = from or 1, #(f.kindHeads or {}) do
        local h = f.kindHeads[k]
        h.fs:Hide(); h.rule.main:Hide(); h.rule.bleed:Hide()
    end
end

-- Would the tally be put away with these pages? (no lines anywhere, or nothing near you and either no
-- other pages or "hide when nothing is nearby")
function P.ShouldHideTally(areas)
    local current = areas[1]
    local anyItems = false
    for _, a in ipairs(areas) do
        if #a.items > 0 then anyItems = true break end
    end
    return not anyItems or (#current.items == 0 and (#areas == 1 or CFQ.parchmentOpts.hideWhenNothingNearby))
end

-- The same, judged on everything the tally could list: switching items or tasks off never puts the
-- tally away (it would take its buttons with it)
function P.ShouldHideUnfiltered(areas)
    if P.ShowsEverything() then return P.ShouldHideTally(areas) end
    local o = CFQ.parchmentOpts
    local a, b = o.tallyLoot, o.tallyTasks
    o.tallyLoot, o.tallyTasks = true, true
    local ok, all = pcall(P.BuildAreas)
    o.tallyLoot, o.tallyTasks = a, b
    return ok and P.ShouldHideTally(all) or false
end

-- After items / tasks / tasks apart changed (the buttons or the options panel)
function P.OnTallyChoiceChanged()
    shoppingScrollOffset = 0
    SaveState()
    UpdateShoppingListUI()
    local f = shoppingListFrame
    if f and f.quickBtns then
        for _, b in pairs(f.quickBtns) do P.DrawQuickButton(b) end
    end
    if CFQ.RefreshOptionsPanel then pcall(CFQ.RefreshOptionsPanel) end
end

-- Page radius (% of the zone map): either its own setting or the tracker's (•••) stacking slider
function P.GetPageRadius()
    if CFQ.parchmentOpts.pagesFollowTracker then
        return incompleteRadiusPercent or 16
    end
    return CFQ.pageRadiusPercent or 16
end

P.COMPASS = {   -- 8 sectors starting east, counter-clockwise (map y grows downward)
    "Eastern", "North-eastern", "Northern", "North-western", "Western", "South-western", "Southern", "South-eastern",
}

-- "Northern Teldrassil" from where the page's quests sit on their zone map
function P.CompassName(cx, cy, zone)
    zone = zone or "the wilds"
    local dx, dy = cx - 0.5, 0.5 - cy
    if math.sqrt(dx * dx + dy * dy) < 0.13 then return "Central " .. zone end
    local ang = math.atan2(dy, dx)
    if ang < 0 then ang = ang + 2 * math.pi end
    local sector = math.floor((ang + math.pi / 8) / (math.pi / 4)) % 8 + 1
    return P.COMPASS[sector] .. " " .. zone
end

-- Leader clustering (no chaining): each quest joins the nearest page whose centre is within the
-- radius, otherwise it starts a page of its own. Single-linkage (as the tracker stacks use) would
-- chain a whole zone's worth of quests into one page.
function P.ClusterIntoPages(quests, radius)
    table.sort(quests, function(a, b)
        if a.mapID ~= b.mapID then return (a.mapID or 0) < (b.mapID or 0) end
        return a.questID < b.questID
    end)
    local pages = {}
    for _, q in ipairs(quests) do
        local best, bestD = nil, nil
        for _, pg in ipairs(pages) do
            if pg.mapID == q.mapID then
                local dx, dy = q.x - pg.cx, q.y - pg.cy
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= radius and (not bestD or d < bestD) then best, bestD = pg, d end
            end
        end
        if not best then
            best = { mapID = q.mapID, cx = q.x, cy = q.y, quests = {} }
            table.insert(pages, best)
        end
        table.insert(best.quests, q)
        local n = #best.quests
        best.cx = best.cx + (q.x - best.cx) / n
        best.cy = best.cy + (q.y - best.cy) / n
    end
    return pages
end

-- Name a page: the area where its objectives were actually worked (learned as you play), else a compass
-- direction on the zone map, else the quest log header
function P.NamePage(pg)
    -- the explored map area at the page's centre is the most accurate name
    local atCentre = pg.cx and P.AreaNameAt(pg.mapID, pg.cx, pg.cy)
    if atCentre then return atCentre end
    local votes, bestName, bestN = {}, nil, 0
    for _, q in ipairs(pg.quests) do
        local nm = CFQ.learnedQuestAreas[q.questID]
        if nm then
            votes[nm] = (votes[nm] or 0) + 1
            if votes[nm] > bestN then bestName, bestN = nm, votes[nm] end
        end
    end
    if bestName then return bestName end
    local zone = pg.quests[1] and pg.quests[1].header
    if pg.cx then return P.CompassName(pg.cx, pg.cy, zone) end
    return zone or "Elsewhere"
end

-- "Near me" radius (% of the zone map): how close you must be to a quest's objective area
function P.GetNearRadius()
    return CFQ.nearRadiusPercent or 10
end

-- ----------------------------------------------------------------------------
-- AREA PAGE NAMES
-- ----------------------------------------------------------------------------
P.GROUPINGS = {
    { key = "AREA",   label = "Map areas" },   -- the explored subzone the items are in (world-map area names)
    { key = "ZONE",   label = "Zones" },       -- one page per zone
    { key = "RADIUS", label = "Clusters" },    -- quests close together share a page (the Cluster size slider)
}

function P.GetGrouping()
    for _, g in ipairs(P.GROUPINGS) do
        if g.key == CFQ.pageGrouping then return g end
    end
    return P.GROUPINGS[1]
end

function P.CycleGrouping()
    local idx = 1
    for i, g in ipairs(P.GROUPINGS) do
        if g.key == CFQ.pageGrouping then idx = i end
    end
    CFQ.pageGrouping = P.GROUPINGS[(idx % #P.GROUPINGS) + 1].key
end

-- Subzone name at a map position, the same way the world map labels areas you have explored
P.areaNameCache = {}
function P.AreaNameAt(mapID, x, y)
    if not (mapID and x and y) then return nil end
    local key = mapID .. ":" .. math.floor(x * 250) .. ":" .. math.floor(y * 250)
    local cached = P.areaNameCache[key]
    if cached then return cached end
    local api = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
    if not (api and C_Map and C_Map.GetAreaInfo and CreateVector2D) then return nil end
    local ok, ids = pcall(api, mapID, CreateVector2D(x, y))
    if ok and type(ids) == "table" then
        for _, id in ipairs(ids) do
            local okN, name = pcall(C_Map.GetAreaInfo, id)
            if okN and type(name) == "string" and name ~= "" then
                P.areaNameCache[key] = name        -- only cache hits: unexplored spots may get explored later
                return name
            end
        end
    end
    return nil
end

function P.ZoneNameOf(q)
    if q.mapID and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, q.mapID)
        if ok and info and info.name and info.name ~= "" then return info.name end
    end
    return q.header or "Elsewhere"
end

-- The map area a quest's items are in: explored subzone at its position > where you've worked it >
-- compass sector of its zone > quest log header
function P.AreaNameOf(q)
    if q.mapID and q.x and q.y then
        local nm = P.AreaNameAt(q.mapID, q.x, q.y)
        if nm then return nm end
    end
    local learned = CFQ.learnedQuestAreas[q.questID]
    if learned then return learned end
    if q.x and q.y then return P.CompassName(q.x, q.y, P.ZoneNameOf(q)) end
    return q.header or "Elsewhere"
end

function P.BuildAreas()
    local nearSet, eligible, here = P.CollectQuests()
    -- Page 1 is always "Near me": what you can gather or do from where you stand
    local current = { key = P.CURRENT_KEY, title = "Near me", subtitle = here, isCurrent = true, quests = {} }
    local areas = { current }

    local rest = {}
    for _, q in ipairs(eligible) do
        if nearSet[q.questID] then
            table.insert(current.quests, q)
        elseif not q.isComplete then        -- area pages only carry quests not yet complete
            table.insert(rest, q)
        end
    end

    if CFQ.parchmentOpts.showTabs then
        local mode = P.GetGrouping().key
        local named = {}       -- { title, quests } before merging

        if mode == "RADIUS" then
            local withCoords = {}
            for _, q in ipairs(rest) do
                if q.mapID and q.x and q.y then
                    table.insert(withCoords, q)
                else
                    table.insert(named, { title = CFQ.learnedQuestAreas[q.questID] or q.header or "Elsewhere", quests = { q } })
                end
            end
            for _, pg in ipairs(P.ClusterIntoPages(withCoords, P.GetPageRadius() / 100)) do
                pg.title = P.NamePage(pg)
                table.insert(named, pg)
            end
        else
            for _, q in ipairs(rest) do
                local title = (mode == "ZONE") and P.ZoneNameOf(q) or P.AreaNameOf(q)
                table.insert(named, { title = title, quests = { q } })
            end
        end

        -- One page per name, in every mode: never "Dolanaar II / III"
        local byTitle, others = {}, {}
        for _, pg in ipairs(named) do
            local k = string.lower(pg.title or "Elsewhere")
            if k == "near me" then k = "near me (area)" end
            local page = byTitle[k]
            if not page then
                page = { key = "AREA:" .. k, title = pg.title or "Elsewhere", quests = {} }
                byTitle[k] = page
                table.insert(others, page)
            end
            for _, q in ipairs(pg.quests) do table.insert(page.quests, q) end
        end

        -- Nearest page first (by its closest quest), then alphabetical
        for _, pg in ipairs(others) do
            local d = nil
            for _, q in ipairs(pg.quests) do
                if q.playerDist and (not d or q.playerDist < d) then d = q.playerDist end
            end
            pg.playerDist = d
        end
        table.sort(others, function(a, b)
            local da, db = a.playerDist or math.huge, b.playerDist or math.huge
            if da ~= db then return da < db end
            return a.title < b.title
        end)

        local maxOthers = P.MAX_AREAS - 1
        if #others > maxOthers then
            local overflow = { key = "AREA:__elsewhere", title = "Elsewhere", quests = {} }
            for i = maxOthers, #others do
                for _, q in ipairs(others[i].quests) do table.insert(overflow.quests, q) end
            end
            for i = #others, maxOthers, -1 do table.remove(others, i) end
            table.insert(others, overflow)
        end
        for _, pg in ipairs(others) do table.insert(areas, pg) end
    end

    for _, a in ipairs(areas) do
        table.sort(a.quests, CompareQuestsForTracker)
        a.items, a.doneCount = P.FlattenQuests(a.quests)
        a.remaining = #a.items - a.doneCount
    end
    return areas
end

-- ----------------------------------------------------------------------------
-- RENDER THE SELECTED SHEET
-- ----------------------------------------------------------------------------
function P.Render(f)
    local area = P.GetSelectedArea()
    if not area then return end

    local items = area.items or {}
    f.totalItems = #items
    for _, row in ipairs(shoppingListRowPool) do
        row:Hide()
    end

    local pageIdx, pageCount = P.GetAreaIndex(area.key), #P.areas
    local pageStr = (pageCount > 1) and string.format("  ·  page %d of %d", pageIdx, pageCount) or ""
    local now = GetTime()
    local w = f:GetWidth() or 230
    local st = P.GetStyle()
    if f.styleKey ~= st.key then P.ApplyStyle(f) end
    P.LayoutPads(f)
    local padL, padT, padR, padB = P.GetPads(f)
    for _, b in pairs(f.quickBtns or {}) do P.DrawQuickButton(b) end      -- in this look's ink

    -- Heading: fresh red ink for a few seconds after you arrive in a new area
    P.SetInkFont(f.titleFS, "title")
    P.SetInkFont(f.footerFS, "small")
    local title = area.title or (area.isCurrent and "Field Tally" or "Elsewhere")
    if st.initial then                       -- illuminated: the heading's first letter in gold (style.initial)
        local first, rest = string.match(title, "^([%z\1-\127\194-\244][\128-\191]*)(.*)$")   -- one UTF-8 letter
        if first then title = "|c" .. P.Hex(st.initial) .. first .. "|r" .. rest end
    end
    if area.isCurrent and now < (P.currentGlowUntil or 0) then
        f.titleFS:SetTextColor(P.INK_RED[1], P.INK_RED[2], P.INK_RED[3], 1)
    else
        f.titleFS:SetTextColor(st.title[1], st.title[2], st.title[3], 1)
    end
    if area.isCurrent and area.subtitle and area.subtitle ~= "" then
        f.titleFS:SetText(title .. "  |c" .. P.Hex(st.sub) .. "· " .. area.subtitle .. "|r")
    else
        f.titleFS:SetText(title)
    end
    P.SetHalo(f.titleFS, f.titleFS:GetText(),
        (area.isCurrent and now < (P.currentGlowUntil or 0)) and P.INK_RED or st.title)
    local ruleW = math.min(w - 20 - padL - padR, math.max(60, (f.titleFS:GetStringWidth() or 80) + 22))
    P.DrawStroke(f.titleRule, f.chrome, 8 + padL, -25 - padT, 8 + padL + ruleW, -24 - padT, 1.2, 0.70)
    P.DrawStroke(f.titleRule2, f.chrome, 14 + padL, -27.5 - padT, 8 + padL + ruleW * 0.55, -27 - padT, 0.7, 0.40)

    if #items == 0 then
        P.HideKindHeadings(f, 1)
        local row = AcquireShoppingListRow(1, f.content)
        P.StyleRow(row)
        P.SetRowFX(row, nil)
        P.SetRowLasso(row, false)
        row.box:Hide()
        P.HideStrikes(row)
        row.suffixText:Hide()
        P.SetInkFont(row.itemText, "item")
        row.itemText:SetWidth(math.max(120, w - 30 - padL - padR))
        row.itemText:SetTextColor(st.faded[1], st.faded[2], st.faded[3], 1)
        local verb = (P.TallyVerb() == "gathered") and "gather" or "do"
        row.itemText:SetText((area.isCurrent and ("Nothing to " .. verb .. " near you.") or ("Nothing left to " .. verb .. " here.")) ..
            ((pageCount > 1) and "\nTurn the page corner to see other areas." or ""))
        P.SetHalo(row.itemText, row.itemText:GetText(), st.faded)
        P.SetInkDrops(row, nil)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -2)
        row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -2)
        row:SetHeight(math.max(36, math.ceil(row.itemText:GetStringHeight() or 30) + 6))
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
        f.footerFS:SetText("nothing here" .. pageStr)
        return
    end

    if shoppingScrollOffset > math.max(0, #items - 1) then
        shoppingScrollOffset = math.max(0, #items - 1)
    end

    local contentW = math.max(150, w - 12 - padL - padR)
    local contentH = math.max(55, (f:GetHeight() or 175) - 45 - padT - padB)
    local yCursor = 0
    local shownRows = 0
    P.SetInkFont(f.measureFS, "item")
    local huntCtx = CFQ.BuildHuntContext()
    local countHex, nameHex = P.Hex(st.inkRed), P.Hex(st.name or st.ink)
    local trackedID = P.GetSuperTrackedID()
    CFQ.slayLit = false          -- set again below while a slay line burns for your target

    -- Tasks apart: "Items" and "Tasks" headings (when the page has both)
    local heads = false
    if CFQ.parchmentOpts.tallySeparate then
        local seen = {}
        for _, e in ipairs(items) do seen[P.LineGroup(e)] = true end
        heads = seen.items and seen.tasks and true or false
    end
    local usedHeads, lastGroup = 0, nil

    for i = 1 + shoppingScrollOffset, #items do
        if shownRows >= MAX_SHOPPING_ROWS then break end
        local entry = items[i]
        local row = AcquireShoppingListRow(shownRows + 1, f.content)
        P.StyleRow(row)
        row.box:Show()
        P.SetInkFont(row.itemText, "item")
        P.SetInkFont(row.suffixText, "small")
        P.HideStrikes(row)
        row.suffixText:Hide()

        local textW = math.max(110, contentW - 24)
        row.itemText:SetWidth(textW)

        local isFlashing = flashObjectiveUntil[entry.progKey] and (now < flashObjectiveUntil[entry.progKey])
        -- a one-off step ("Speak with Denalan") has no count: the box alone says whether it's done
        local countStr = entry.single and "" or string.format("%d/%d", entry.numFulfilled or 0, entry.numRequired or 1)
        local nameStr = entry.itemName or ""
        local lineStr = (countStr ~= "") and (countStr .. "  " .. nameStr) or nameStr
        local strH
        local inkLines, inkWidths, inkH          -- the written lines (for ink drops), before any "(turn in)"

        local wa = st.wash
        if entry.finished then
            P.ShowTick(row.box, row.seed)
            row.box.wash:SetColorTexture(wa[1], wa[2], wa[3], wa[4])

            -- Faded ink, wrapped by hand so every line gets a strike exactly as long as its words
            local lines, widths = P.WrapLines(f.measureFS, lineStr, textW)
            row.itemText:SetTextColor(st.faded[1], st.faded[2], st.faded[3], 1)
            row.itemText:SetText(table.concat(lines, "\n"))
            strH = math.max(14, math.ceil(row.itemText:GetStringHeight() or 14))
            local lineH = strH / #lines
            inkLines, inkWidths, inkH = lines, widths, strH
            for k, lw in ipairs(widths) do
                local tilt = (P.Hash01(row.seed, k, 5) - 0.5) * 1.8
                local y = -(k - 0.5) * lineH + 0.5
                P.DrawStroke(P.GetStrike(row, k), row.itemText, -2, y + tilt * 0.5, lw + 2, y - tilt * 0.5, 1.3, 0.82)
            end

            if entry.isQuestComplete then
                row.suffixText:SetText("(turn in)")
                local sw = row.suffixText:GetStringWidth() or 40
                local lastW = widths[#widths] or 0
                row.suffixText:ClearAllPoints()
                if lastW + 8 + sw <= textW then
                    -- same line, after the struck words
                    row.suffixText:SetPoint("TOPLEFT", row.itemText, "TOPLEFT", lastW + 8, -(#lines - 1) * lineH - 1)
                else
                    row.suffixText:SetPoint("TOPLEFT", row.itemText, "TOPLEFT", 0, -strH - 1)
                    strH = strH + math.ceil(row.suffixText:GetStringHeight() or 11) + 1
                end
                row.suffixText:Show()
            end
        else
            P.HideTick(row.box)
            if isFlashing then
                local wf = st.washFlash
                row.box.wash:SetColorTexture(wf[1], wf[2], wf[3], wf[4])   -- fresh tally mark
            else
                row.box.wash:SetColorTexture(wa[1], wa[2], wa[3], wa[4])
            end
            row.itemText:SetTextColor(P.INK[1], P.INK[2], P.INK[3], 1)
            if countStr ~= "" then
                row.itemText:SetText(string.format("|c%s%s|r  |c%s%s|r", countHex, countStr, nameHex, nameStr))
            else
                row.itemText:SetText(string.format("|c%s%s|r", nameHex, nameStr))
            end
            strH = math.max(14, math.ceil(row.itemText:GetStringHeight() or 14))
            inkH = strH
        end

        -- wet ink / arcane light round the words, and drops shaken off the quill ("Blotted scrawl")
        local lineInk = entry.finished and st.faded or P.INK
        P.SetHalo(row.itemText, row.itemText:GetText(), lineInk)
        if P.EffectiveFont().drops then
            if not inkLines then inkLines, inkWidths = P.WrapLines(f.measureFS, lineStr, textW) end
            P.SetInkDrops(row, { key = (entry.progKey or "") .. nameStr, lastW = inkWidths[#inkWidths] or 0,
                textH = inkH, lines = #inkLines, textW = textW, ink = lineInk })
        else
            P.SetInkDrops(row, nil)
        end

        -- glow in its hunting grounds, flames when your target drops it, red ink circle round the
        -- items of the quest you're tracking
        local fxMode = CFQ.GetItemFXMode(entry, huntCtx)
        if fxMode == "fire" and entry.kind == "slay" then CFQ.slayLit = true end
        P.SetRowFX(row, fxMode, lineStr, textW, entry.progKey)
        P.SetRowLasso(row, trackedID ~= nil and trackedID == entry.questID)

        local rowH = strH + 7
        local group = P.LineGroup(entry)
        local headH = (heads and group ~= lastGroup) and P.KIND_HEADING_H or 0

        if (math.abs(yCursor) + headH + rowH) > (contentH + 4) and shownRows > 0 then
            row:Hide()
            break
        end
        if headH > 0 then
            usedHeads = usedHeads + 1
            P.DrawKindHeading(f, usedHeads, P.GROUP_HEADINGS[group], yCursor, contentW, st)
            yCursor = yCursor - headH
            lastGroup = group
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, yCursor)
        row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, yCursor)
        row:SetHeight(rowH)

        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(entry.questID)
                end
            else
                -- same as clicking the quest's icon in the Objective Tracker: track it / stop tracking
                CFQ.ToggleSuperTrack(entry.questID)
            end
        end)

        row:SetScript("OnEnter", function(self)
            P.PlaceTooltip(self)
            local lvlStr = string.format("|c%s[%d]|r ", entry.levelHex or "FFFFFF00", entry.level or 0)
            GameTooltip:AddLine(lvlStr .. "|cFFFFD100" .. (entry.questTitle or "Quest") .. "|r")
            if entry.single then
                GameTooltip:AddLine((entry.itemName or "Objective") .. (entry.finished and "  (done)" or ""), 0.9, 0.9, 0.9, true)
            else
                GameTooltip:AddLine(string.format("%s: %d / %d", entry.itemName or "Objective", entry.numFulfilled or 0, entry.numRequired or 1), 0.9, 0.9, 0.9)
            end
            if entry.isQuestComplete then
                GameTooltip:AddLine("All objectives complete — ready to turn in!", 0.25, 0.95, 0.25)
            end
            CFQ.AddHuntTooltipLines(GameTooltip, entry)
            local tracked = P.GetSuperTrackedID() == entry.questID
            GameTooltip:AddLine((tracked and "Left-Click: stop tracking this quest" or "Left-Click: track this quest")
                .. "  |  Right-Click: open the quest log", 0.65, 0.65, 0.65)
            GameTooltip:Show()
            local okPv, errPv = pcall(CFQ.ShowMapPreview, entry, GameTooltip)
            if not okPv then CFQ.HideMapPreview(); CFQ.ReportError(errPv) end
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
            CFQ.HideMapPreview()
        end)

        row:Show()
        yCursor = yCursor - rowH
        shownRows = shownRows + 1
    end

    P.HideKindHeadings(f, usedHeads + 1)
    local doneCount = area.doneCount or 0
    local verb = P.TallyVerb()
    if #items > shownRows then
        f.footerFS:SetText(string.format("%d of %d %s  ·  %d-%d shown%s",
            doneCount, #items, verb, shoppingScrollOffset + 1, shoppingScrollOffset + shownRows, pageStr))
    else
        f.footerFS:SetText(string.format("%d of %d %s%s", doneCount, #items, verb, pageStr))
    end
end

UpdateShoppingListUI = function()
    local f = EnsureShoppingListFrame()
    if not showShoppingList then
        f:Hide()
        return
    end

    local areas = P.BuildAreas()
    P.areas = areas
    local current = areas[1]
    P.CheckAreaChange(f)

    local selected = nil
    for _, a in ipairs(areas) do
        if a.key == P.selectedKey then selected = a break end
    end
    if not selected then
        P.selectedKey = current.key
        shoppingScrollOffset = 0
    end

    -- whether to put the tally away is judged on everything it could list, so filtering it down to
    -- nothing (even with "hide when nothing is nearby") never takes its buttons away
    if P.ShouldHideUnfiltered(areas) then
        f:Hide()
        return
    end

    -- one page per area: the pile under the top page shows how many other pages there are
    -- (the see-through window and arcane script have no pile; the footer still reads "page n of m")
    f.visibleBackSheets = P.GetStyle().pile and math.max(0, math.min(#areas - 1, P.MAX_BACK_SHEETS)) or 0
    f:Show()
    P.Render(f)
    P.UpdateCorner(f)
    P.ApplyStackLayout(f)
end

-- Why the tally stays put away right after you switch it on (or nil if it's up), so it never seems broken
function P.HiddenReason()
    local f = EnsureShoppingListFrame()
    if not showShoppingList or f:IsShown() then return nil end
    local o = CFQ.parchmentOpts
    local a, b = o.tallyLoot, o.tallyTasks
    o.tallyLoot, o.tallyTasks = true, true
    local ok, _, eligible = pcall(P.CollectQuests)
    o.tallyLoot, o.tallyTasks = a, b
    if not ok or type(eligible) ~= "table" then return nil end
    if #eligible == 0 then
        return "the Field Tally is on, but there's nothing to list yet: it appears when a tracked quest has items to gather or tasks to do."
    elseif o.hideWhenNothingNearby then
        return "the Field Tally is on, but hidden until something is nearby (Options: \"...only when something is nearby\")."
    end
    return "the Field Tally is on, but there's nothing near you and \"Pages for other areas\" is off."
end

-- Switching the tally on: show it, or say in chat why it isn't up
function P.TurnTallyOn()
    showShoppingList = true
    UpdateShoppingListUI()
    local why = P.HiddenReason()
    if why then print("|cFFFFD100HandkerSheaf:|r " .. why) end
end

-- ============================================================================
-- HUNTING GROUNDS
-- Where a tally item is gathered (learned from where you loot it + the quest's own objective
-- area) and which mobs drop it (learned from the loot window + unit tooltips, names as a last resort).
-- EDIT: the radii are fractions of the map's width (0.035 = 3.5%): bigger = the glow starts further out.
-- ============================================================================
P.HUNT_SPOT_RADIUS = 0.035      -- a looted-here spot counts as hunting ground within 3.5% of the map
P.HUNT_POI_RADIUS = 0.06        -- ...and so does the quest's objective area (its map POI) within 6%
P.MAX_HUNT_SPOTS = 12           -- per item; nearby loots merge into one spot

function P.Round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- "npc:1234" from a creature GUID, so a mob is recognised whatever its name is in your language
function P.NpcKey(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if (kind == "Creature" or kind == "Vehicle") and id then return "npc:" .. id end
    return nil
end

-- Position on another map (e.g. a spot looted on the zone map, shown on the continent map)
function P.TranslatePos(fromMap, x, y, toMap)
    if not (fromMap and x and y and toMap) then return nil end
    if fromMap == toMap then return x, y end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y))
    if not (ok and cont and wpos) then return nil end
    local ok2, _, mpos = pcall(C_Map.GetMapPosFromWorldPos, cont, wpos, toMap)
    if ok2 and mpos and mpos.GetXY then
        local mx, my = mpos:GetXY()
        if mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then return mx, my end
    end
    return nil
end

-- An item objective just ticked up: you are standing in its hunting grounds, and whatever you just
-- looted drops it
function CFQ.OnItemProgress(questID, progKey)
    local mapID, x, y = GetPlayerMapPositionSafe()
    if mapID and x and y then
        local list = CFQ.huntSpots[progKey]
        if not list then
            list = {}
            CFQ.huntSpots[progKey] = list
        end
        local sub = strtrim((GetSubZoneText and GetSubZoneText()) or "")
        local merged = false
        local mergeR = P.HUNT_SPOT_RADIUS * 0.6
        for _, sp in ipairs(list) do
            if sp.m == mapID then
                local dx, dy = sp.x - x, sp.y - y
                if dx * dx + dy * dy < mergeR * mergeR then
                    sp.n = math.min(50, (sp.n or 1) + 1)
                    sp.x = P.Round4(sp.x + (x - sp.x) / sp.n)
                    sp.y = P.Round4(sp.y + (y - sp.y) / sp.n)
                    if sub ~= "" then sp.a = sub end
                    merged = true
                    break
                end
            end
        end
        if not merged then
            table.insert(list, 1, { m = mapID, x = P.Round4(x), y = P.Round4(y), a = (sub ~= "") and sub or nil, n = 1 })
            while #list > P.MAX_HUNT_SPOTS do table.remove(list) end
        end
    end

    local src = CFQ.lastLootMob
    if src and (GetTime() - src.t) < 8 and not (src.recorded and src.recorded[progKey]) then
        local d = CFQ.DropperRecord(src.key, src.label)
        d[progKey] = (d[progKey] or 0) + 1
    end
end

-- ----------------------------------------------------------------------------
-- WHO DROPS WHAT: evidence first, guesses last
-- The game has no drop-table API, but the loot window is authoritative: every slot says which
-- corpse it came from (GetLootSourceInfo) and what the item is. So each time you loot a mob we
-- record, per npc id: how many of its corpses you looted ("loots") and, per item you still needed,
-- how many tries that was ("tries"), plus how many times each tally item was in the loot ([progKey] = hits).
-- Hits make a mob a sure dropper; P.RULE_OUT_LOOTS tries at an item with no hit rule it out, whatever its name.
-- ----------------------------------------------------------------------------
CFQ.countedCorpses = {}

function CFQ.DropperRecord(key, label)
    local d = CFQ.learnedDroppers[key]
    if not d then
        d = { loots = 0 }
        CFQ.learnedDroppers[key] = d
    end
    if label and label ~= "" then d.label = label end
    return d
end

-- Name of the mob behind a GUID, if we have seen it (target, or the last thing you targeted)
function P.NameForGUID(guid)
    if not guid then return nil end
    if UnitGUID and UnitGUID("target") == guid then return UnitName("target") end
    if UnitGUID and UnitGUID("mouseover") == guid then return UnitName("mouseover") end
    local last = CFQ.lastTargetMob
    if last and last.guid == guid then return last.name end
    return nil
end

-- Reads the open loot window: which corpses, and which tally items each one gave
function CFQ.ScanLootWindow()
    local needed, anyNeeded = {}, false
    for _, q in pairs(questRewardMap) do
        for _, o in ipairs(q.itemObjectives or {}) do
            if not o.finished and o.itemName and o.itemName ~= "" then
                needed[string.lower(o.itemName)] = o.progKey
                anyNeeded = true
            end
        end
    end
    if not (anyNeeded and GetNumLootItems and GetLootSlotInfo and GetLootSourceInfo) then return {} end

    local found = {}           -- [progKey] = true: items seen in this loot window
    local corpses = {}         -- [guid] = npc key
    local okN, n = pcall(GetNumLootItems)
    for slot = 1, (okN and tonumber(n)) or 0 do
        local okI, _, itemName = pcall(GetLootSlotInfo, slot)
        local progKey = okI and type(itemName) == "string" and needed[string.lower(itemName)]
        local src = { pcall(GetLootSourceInfo, slot) }       -- ok, guid1, qty1, guid2, qty2, ... (area loot)
        if src[1] then
            for j = 2, #src, 2 do
                local guid = src[j]
                local key = P.NpcKey(guid)
                if key then
                    corpses[guid] = key
                    if progKey then
                        local d = CFQ.DropperRecord(key, P.NameForGUID(guid))
                        local mark = guid .. "|" .. progKey
                        if not CFQ.countedCorpses[mark] then
                            CFQ.countedCorpses[mark] = true
                            d[progKey] = (d[progKey] or 0) + 1
                        end
                        found[progKey] = true
                    end
                end
            end
        end
    end
    -- every corpse looted once counts as a try at each item you still needed then, whether it
    -- dropped or not (re-opening the same corpse doesn't count again)
    for guid, key in pairs(corpses) do
        if not CFQ.countedCorpses[guid] then
            CFQ.countedCorpses[guid] = true
            local d = CFQ.DropperRecord(key, P.NameForGUID(guid))
            d.loots = (d.loots or 0) + 1
            d.tries = d.tries or {}
            for _, pk in pairs(needed) do d.tries[pk] = (d.tries[pk] or 0) + 1 end
        end
    end
    -- keep the session's "already counted" list short
    local c = 0
    for _ in pairs(CFQ.countedCorpses) do c = c + 1 end
    if c > 400 then CFQ.countedCorpses = {} end
    return found
end

-- The loot window opened: read it, and remember which mob it's from (not herbs, chests or fishing)
function CFQ.OnLootOpened()
    CFQ.lastLootMob = nil
    if IsFishingLoot and IsFishingLoot() then return end
    local okScan, found = pcall(CFQ.ScanLootWindow)
    found = okScan and found or {}
    local srcGUID
    if GetLootSourceInfo then
        local ok, guid = pcall(GetLootSourceInfo, 1)
        if ok then srcGUID = guid end
    end
    if type(srcGUID) == "string" and not P.NpcKey(srcGUID) then return end   -- a game object, not a mob

    local name, guid
    if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target")
        and not (UnitIsPlayer and UnitIsPlayer("target")) then
        name, guid = UnitName("target"), UnitGUID and UnitGUID("target")
    end
    if srcGUID and guid ~= srcGUID then
        local last = CFQ.lastTargetMob
        if last and last.guid == srcGUID then name, guid = last.name, last.guid else name, guid = nil, srcGUID end
    end
    local key = P.NpcKey(guid) or (name and string.lower(name))
    if key then
        -- "recorded": items the loot window already credited, so the quest-progress fallback
        -- (CFQ.OnItemProgress) doesn't count the same drop twice
        CFQ.lastLootMob = { key = key, label = name, t = GetTime(), recorded = found }
    end
end

P.GENERIC_WORDS = {
    small = true, large = true, piece = true, sample = true, fragment = true, shard = true, scrap = true,
    token = true, bundle = true, pouch = true, part = true, essence = true, crate = true, supply = true,
    ancient = true, elder = true, young = true, giant = true, greater = true, lesser = true, mature = true,
    the = true, with = true, from = true, some = true, intact = true, pristine = true, fresh = true, rough = true,
}

function P.NameWords(s)
    local out = {}
    for word in string.gmatch(string.lower(s or ""), "[%a']+") do
        word = string.gsub(word, "'s$", "")
        if string.len(word) > 4 and string.sub(word, -1) == "s" then word = string.sub(word, 1, -2) end
        if string.len(word) >= 4 and not P.GENERIC_WORDS[word] then out[word] = true end
    end
    return out
end

-- "Small Spider Leg" / "Webwood Spider", "Gnarlpine Fang" / "Gnarlpine Mystic": a distinctive word in common
function P.NamesShareWord(itemName, mobName)
    local a = P.NameWords(itemName)
    for w in pairs(P.NameWords(mobName)) do
        if a[w] then return true end
    end
    return false
end

-- Unit tooltip lines (lower case). Retail-style tooltips list the quest objectives a mob is part of.
function CFQ.ReadUnitTooltip(unit)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, ln in ipairs(data.lines) do
                if type(ln.leftText) == "string" then table.insert(lines, string.lower(ln.leftText)) end
            end
            return lines
        end
    end
    local tip = CFQ.scanTip
    if not tip then
        local ok, t = pcall(CreateFrame, "GameTooltip", "HKQ_ScanTooltip", nil, "GameTooltipTemplate")
        if not ok or not t then return lines end
        tip = t
        CFQ.scanTip = tip
    end
    pcall(function()
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        tip:SetUnit(unit)
        local nLines = tip:NumLines()
        for i = 1, tonumber(nLines) or 0 do
            local fs = _G["HKQ_ScanTooltipTextLeft" .. i]
            local txt = fs and fs.GetText and fs:GetText()
            if type(txt) == "string" then table.insert(lines, string.lower(txt)) end
        end
        tip:Hide()
    end)
    return lines
end

-- EDIT: looted this many of a mob without ever getting the item = it doesn't drop it
P.RULE_OUT_LOOTS = 4

-- Which unfinished tally items could this mob drop? Returns { [progKey] = "sure" | "guess" } or nil.
--   sure:  you've looted the item from this npc before, or its tooltip names the item / the quest
--   guess: only the names look related (and nothing rules it out)
function CFQ.FindTargetDrops(unit)
    unit = unit or "target"
    if not (UnitExists and UnitExists(unit)) then return nil end
    if UnitIsPlayer and UnitIsPlayer(unit) then return nil end
    if UnitCanAttack and not UnitCanAttack("player", unit) then return nil end   -- friendly NPCs don't drop loot
    local name = UnitName and UnitName(unit)
    if not name or name == "" then return nil end
    local learnedA = CFQ.learnedDroppers[P.NpcKey(UnitGUID and UnitGUID(unit)) or ""]
    local learnedB = CFQ.learnedDroppers[string.lower(name)]
    local tipLines = CFQ.ReadUnitTooltip(unit)

    -- Does the client say this unit is part of one of your quests? (nil = it can't tell us)
    local related
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, r = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and type(r) == "boolean" then related = r end
    end
    -- Does its tooltip carry any quest of yours? Once we've seen tooltips do that on this client,
    -- a tooltip *without* quest lines is evidence too.
    local titles = {}
    for _, q in pairs(questRewardMap) do
        if q.title and q.title ~= "" then titles[string.lower(q.title)] = true end
    end
    local tipHasQuest = false
    for _, ln in ipairs(tipLines) do
        if titles[strtrim(ln)] then tipHasQuest = true break end
    end
    if tipHasQuest then CFQ.tooltipShowsQuests = true end

    local keys, any = {}, false
    for _, q in pairs(questRewardMap) do
        local onlyItems = true
        for _, o in ipairs(q.quantityObjectives or {}) do
            if not o.isItem and not o.finished then onlyItems = false end
        end
        local lowerTitle = string.lower(q.title or "")
        for _, obj in ipairs(q.itemObjectives or {}) do
            if not obj.finished then
                local k = obj.progKey
                local level
                local hits = ((learnedA and learnedA[k]) or 0) + ((learnedB and learnedB[k]) or 0)
                local loots = ((learnedA and learnedA.tries and learnedA.tries[k]) or 0)
                    + ((learnedB and learnedB.tries and learnedB.tries[k]) or 0)
                if hits > 0 then
                    level = "sure"
                else
                    local lowerItem = string.lower(obj.itemName or "")
                    for _, ln in ipairs(tipLines) do
                        if (lowerItem ~= "" and string.find(ln, lowerItem, 1, true))
                            or (onlyItems and lowerTitle ~= "" and strtrim(ln) == lowerTitle) then
                            level = "sure"
                            break
                        end
                    end
                end
                if not level then
                    local ruledOut = loots >= P.RULE_OUT_LOOTS                         -- looted often, never got it
                        or related == false                                            -- client: not a quest mob
                        or (CFQ.tooltipShowsQuests and not tipHasQuest)                -- tooltip would have said so
                    if not ruledOut and P.NamesShareWord(obj.itemName, name) then level = "guess" end
                end
                if level then
                    keys[k] = level
                    any = true
                end
            end
        end
    end
    return any and keys or nil
end

-- New target: set the tally alight for anything it may drop
function CFQ.OnTargetChanged()
    local guid = UnitGUID and UnitGUID("target")
    if UnitExists and UnitExists("target") and not (UnitIsPlayer and UnitIsPlayer("target")) then
        CFQ.lastTargetMob = { guid = guid, name = UnitName("target"), t = GetTime() }
    end
    local keys = CFQ.FindTargetDrops("target")
    if not keys then
        P.fire = nil
        return
    end
    local now = GetTime()
    P.fire = { keys = keys, guid = guid, since = now }
    for k in pairs(keys) do
        local qID = tonumber(string.match(k, "^(%d+)_"))
        if qID then recentActiveQuests[qID] = now end     -- puts it on the "Near me" page
    end
    -- turn back to "Near me" so the burning line is in front of you
    local f = shoppingListFrame
    if f and f:IsShown() and P.selectedKey ~= P.CURRENT_KEY and not f.shuffle then
        f.shuffle = { t = 0, dur = 0.55, key = P.CURRENT_KEY, swapped = false, dir = -1 }
    end
end

-- Location snapshot for one render: where you are, and the quest objective areas on your map
function CFQ.BuildHuntContext()
    local mapID, x, y = GetPlayerMapPositionSafe()
    local ctx = { mapID = mapID, x = x, y = y, pois = {},
        sub = string.lower(strtrim((GetSubZoneText and GetSubZoneText()) or "")) }
    if mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                if info.questID and info.x and info.y then ctx.pois[info.questID] = { info.x, info.y } end
            end
        end
    end
    return ctx
end

function CFQ.IsInHuntGrounds(entry, ctx)
    if not entry or not ctx then return false end
    local px, py = ctx.x, ctx.y
    local function Near(x, y, r)
        if not (x and y and px and py) then return false end
        local dx, dy = x - px, y - py
        return dx * dx + dy * dy <= r * r
    end
    for _, sp in ipairs(CFQ.huntSpots[entry.progKey] or {}) do
        if ctx.sub ~= "" and sp.a and string.lower(sp.a) == ctx.sub then return true end   -- same subzone
        if ctx.mapID then
            local sx, sy = P.TranslatePos(sp.m, sp.x, sp.y, ctx.mapID)
            if Near(sx, sy, P.HUNT_SPOT_RADIUS) then return true end
        end
    end
    local poi = ctx.pois[entry.questID]
    if poi and Near(poi[1], poi[2], P.HUNT_POI_RADIUS) then return true end
    local q = entry.qData
    if q and not q.isComplete and q.mapID and q.mapID == ctx.mapID and Near(q.x, q.y, P.HUNT_POI_RADIUS) then
        return true
    end
    return false
end

-- Your target is one of the enemies a slay line asks for (its name is in the line)
function CFQ.TargetIsToSlay(entry)
    if not (entry and entry.kind == "slay" and UnitExists and UnitExists("target")) then return false end
    if UnitIsDead and UnitIsDead("target") then return false end
    local name = UnitName and UnitName("target")
    if not name or name == "" then return false end
    return string.find(string.lower(entry.itemName or ""), string.lower(name), 1, true) ~= nil
end

function CFQ.GetItemFXMode(entry, ctx)
    if not CFQ.parchmentOpts.inkEffects or entry.finished then return nil end
    if entry.kind == "slay" then
        if CFQ.TargetIsToSlay(entry) then return "fire" end        -- your target is one to slay
        if CFQ.IsInHuntGrounds(entry, ctx) then return "glow" end
        return nil
    end
    local level = P.fire and P.fire.keys[entry.progKey]
    if level == "sure" then return "fire" end           -- known to drop it: full flames
    if level then return "smoulder" end                 -- only the names suggest it: a smoulder
    if CFQ.IsInHuntGrounds(entry, ctx) then return "glow" end
    return nil
end

-- Mobs you've looted this item from (most often first), with how many of their corpses you looted
function CFQ.GetKnownDroppers(progKey)
    local list = {}
    for _, d in pairs(CFQ.learnedDroppers) do
        if type(d) == "table" and type(d[progKey]) == "number" and d.label then
            local tries = (d.tries and d.tries[progKey]) or d.loots or 0
            table.insert(list, { name = d.label, n = d[progKey], loots = math.max(tries, d[progKey]) })
        end
    end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return list
end

function CFQ.AddHuntTooltipLines(tt, entry)
    local level = P.fire and P.fire.keys[entry.progKey]
    if entry.kind == "slay" or entry.kind == "task" then
        if entry.finished then return end
        if CFQ.TargetIsToSlay(entry) then
            tt:AddLine("Your target is one of them!", 1.0, 0.50, 0.10)
        elseif CFQ.IsInHuntGrounds(entry, CFQ.BuildHuntContext()) then
            tt:AddLine((entry.kind == "slay") and "You're where they roam" or "You're in the quest's area", 1.0, 0.85, 0.35)
        end
        return
    end
    if level == "sure" and not entry.finished then
        tt:AddLine("Your target drops this!", 1.0, 0.50, 0.10)
    elseif level and not entry.finished then
        tt:AddLine("Your target might drop this (going by its name)", 1.0, 0.65, 0.30)
    elseif not entry.finished and CFQ.IsInHuntGrounds(entry, CFQ.BuildHuntContext()) then
        tt:AddLine("You're in its hunting grounds", 1.0, 0.85, 0.35)
    end
    local spots = CFQ.huntSpots[entry.progKey]
    if spots and #spots > 0 then
        tt:AddLine(string.format("Found it in %d spot%s so far", #spots, (#spots == 1) and "" or "s"), 0.80, 0.72, 0.50)
    end
    local droppers = CFQ.GetKnownDroppers(entry.progKey)
    if #droppers > 0 then
        local names = {}
        for i = 1, math.min(3, #droppers) do
            local dr = droppers[i]
            names[i] = string.format("%s (%d of %d)", dr.name, dr.n, dr.loots)
        end
        tt:AddLine("Looted from: " .. table.concat(names, ", "), 0.80, 0.72, 0.50, true)
    end
end

-- Forget spots and droppers for quests that have left the log
function CFQ.PruneHuntData()
    if not next(questRewardMap) then return end      -- quest log not loaded yet: keep everything
    local function Alive(progKey)
        local qID = tonumber(string.match(tostring(progKey), "^(%d+)_"))
        return qID and questRewardMap[qID] ~= nil
    end
    for k in pairs(CFQ.huntSpots) do
        if not Alive(k) then CFQ.huntSpots[k] = nil end
    end
    for mob, d in pairs(CFQ.learnedDroppers) do
        local keep = false
        if type(d) == "table" then
            for k, v in pairs(d) do
                if type(v) == "number" and string.find(tostring(k), "^%d+_%d+$") then   -- per-item hit counts only
                    if Alive(k) then keep = true else d[k] = nil end
                end
            end
            for k in pairs(d.tries or {}) do
                if Alive(k) then keep = true else d.tries[k] = nil end
            end
        end
        if not keep then CFQ.learnedDroppers[mob] = nil end
    end
end

-- ----------------------------------------------------------------------------
-- CLICKING AN ITEM: track its quest exactly like clicking the quest's icon in the Objective Tracker
-- (super-track it; click again to stop). Blizzard then draws its own shaded quest area on the map
-- and its waypoint arrow, as for any super-tracked quest.
-- ----------------------------------------------------------------------------
function CFQ.ToggleSuperTrack(questID)
    if not questID then return end
    local ST = C_SuperTrack
    if not (ST and ST.SetSuperTrackedQuestID) then
        ActivateQuestTarget(questID)          -- very old clients: the addon's own tracking
    elseif IsQuestSuperTracked(questID) and ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == questID then
        pcall(ST.SetSuperTrackedQuestID, 0)
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_OFF then
            pcall(PlaySound, SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_OFF)
        end
    else
        pcall(ST.SetSuperTrackedQuestID, questID)
        lastSelectedQuestID = questID
        SaveState()
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON then
            pcall(PlaySound, SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON)
        end
    end
    if LayoutObjectiveTrackerWithStacks then LayoutObjectiveTrackerWithStacks() end
    if shoppingListFrame and shoppingListFrame:IsShown() then P.Render(shoppingListFrame) end
end

-- The map an item is gathered on: where you've looted it most, else the quest's zone, else yours
function CFQ.GetHuntMapID(focus)
    if not focus then return nil end
    local votes, best, bestN = {}, nil, 0
    for _, sp in ipairs(CFQ.huntSpots[focus.progKey] or {}) do
        votes[sp.m] = (votes[sp.m] or 0) + (sp.n or 1)
        if votes[sp.m] > bestN then best, bestN = sp.m, votes[sp.m] end
    end
    if best then return best end
    local q = questRewardMap[focus.questID]
    if q and q.mapID then return q.mapID end
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- A circled patch of map on the hover preview: a dashed ink ring and a small pip in the middle
-- (no fill, so the map art underneath stays visible)
function P.AcquireHuntCircle(ov, i)
    local c = ov.circles[i]
    if c then return c end
    c = CreateFrame("Frame", nil, ov)
    c.dashes = {}
    for k = 1, 20 do c.dashes[k] = c:CreateLine(nil, "OVERLAY") end
    c.pip = c:CreateTexture(nil, "OVERLAY")
    c.pip:SetTexture(CIRCLE_MASK_TEX)
    c.pip:SetPoint("CENTER")
    ov.circles[i] = c
    return c
end

function P.PlaceHuntCircle(c, canvas, x, y, radiusPx, kind)
    local W, H = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    c:ClearAllPoints()
    c:SetSize(radiusPx * 2, radiusPx * 2)
    c:SetPoint("CENTER", canvas, "TOPLEFT", x * W, -y * H)
    -- spots you looted in: amber. The quest's objective area: red.
    local r, g, b = 1.0, 0.62, 0.10
    if kind == "poi" then r, g, b = 0.90, 0.18, 0.08 end
    local n = #c.dashes
    local thick = math.max(1.5, radiusPx * 0.035)
    for k, ln in ipairs(c.dashes) do
        local a0 = (k - 1) / n * 2 * math.pi
        local a1 = a0 + (2 * math.pi / n) * 0.55
        ln:SetStartPoint("CENTER", c, math.cos(a0) * radiusPx, math.sin(a0) * radiusPx)
        ln:SetEndPoint("CENTER", c, math.cos(a1) * radiusPx, math.sin(a1) * radiusPx)
        ln:SetThickness(thick)
        ln:SetColorTexture(r, g, b, 0.90)
        ln:Show()
    end
    local pip = math.max(4, radiusPx * 0.12)
    c.pip:SetSize(pip, pip)
    c.pip:SetVertexColor(r, g, b, 0.95)
    c:Show()
end

-- Where an item is gathered, on one map: looted-here spots (amber) + the quest's objective area (red)
function CFQ.CollectHuntMarks(questID, progKey, mapID)
    local marks = {}
    for _, sp in ipairs(CFQ.huntSpots[progKey] or {}) do
        local x, y = P.TranslatePos(sp.m, sp.x, sp.y, mapID)
        if x then table.insert(marks, { x = x, y = y, r = P.HUNT_SPOT_RADIUS, kind = "spot", n = sp.n or 1 }) end
    end
    local poiX, poiY
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                if info.questID == questID and info.x and info.y then poiX, poiY = info.x, info.y end
            end
        end
    end
    if not poiX then
        local q = questRewardMap[questID]
        if q and q.mapID and not q.isComplete then poiX, poiY = P.TranslatePos(q.mapID, q.x, q.y, mapID) end
    end
    if poiX then table.insert(marks, { x = poiX, y = poiY, r = P.HUNT_POI_RADIUS, kind = "poi", n = 0 }) end
    return marks
end

-- ----------------------------------------------------------------------------
-- MAP PREVIEW ON HOVER
-- A little map under the item's tooltip: the zone's own map art, cropped around where the item is
-- gathered, with the quest's objective area, your looted-here spots and where you are now.
-- It is a separate frame, so it never draws on (or covers anything on) the real world map.
-- ----------------------------------------------------------------------------
-- EDIT: size of the map area in pixels (keep roughly 3:2, the shape of zone maps)
P.PREVIEW_W, P.PREVIEW_H = 220, 147

function CFQ.EnsureMapPreview()
    if CFQ.mapPreview then return CFQ.mapPreview end
    local pv = CreateFrame("Frame", "HKQ_MapPreview", UIParent)
    pv:SetSize(P.PREVIEW_W + 8, P.PREVIEW_H + 24)
    pv:SetFrameStrata("TOOLTIP")
    pv:SetClampedToScreen(true)
    if pv.EnableMouse then pv:EnableMouse(false) end
    local border = pv:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetAllPoints()
    border:SetColorTexture(0.62, 0.62, 0.66, 0.95)
    local bg = pv:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.03, 0.03, 0.05, 0.96)
    pv.title = pv:CreateFontString(nil, "OVERLAY")
    pv.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
    pv.title:SetPoint("TOPLEFT", pv, "TOPLEFT", 6, -5)
    pv.title:SetPoint("RIGHT", pv, "RIGHT", -6, 0)
    pv.title:SetJustifyH("LEFT")
    pv.title:SetWordWrap(false)

    -- clipping viewport onto the (larger) map
    local sf = CreateFrame("ScrollFrame", nil, pv)
    sf:SetPoint("TOPLEFT", pv, "TOPLEFT", 4, -20)
    sf:SetSize(P.PREVIEW_W, P.PREVIEW_H)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(P.PREVIEW_W, P.PREVIEW_H)
    sf:SetScrollChild(child)
    child.circles = {}
    pv.sf, pv.child = sf, child
    pv.tiles = {}
    -- fallback when the client gives no map art: a plain parchment sketch
    pv.paper = child:CreateTexture(nil, "BACKGROUND", nil, -1)
    pv.paper:SetAllPoints(child)
    pv.paper:SetColorTexture(0.80, 0.72, 0.54, 1)

    -- Blizzard's own quest-area shape, drawn only inside this preview
    local ok, blob = pcall(CreateFrame, "QuestPOIFrame", nil, child)
    if ok and type(blob) == "table" and type(blob.DrawBlob) == "function" then
        blob:SetAllPoints(child)
        pcall(blob.SetFillTexture, blob, "Interface\\WorldMap\\UI-QuestBlob-Inside")
        pcall(blob.SetBorderTexture, blob, "Interface\\WorldMap\\UI-QuestBlob-Outside")
        pcall(blob.SetFillAlpha, blob, 128)
        pcall(blob.SetBorderAlpha, blob, 220)
        pcall(blob.SetBorderScalar, blob, 0.5)
        pv.blob = blob
    end

    -- you are here
    local you = CreateFrame("Frame", nil, child)
    you:SetSize(9, 9)
    you:SetFrameLevel(child:GetFrameLevel() + 20)
    you.ring = you:CreateTexture(nil, "ARTWORK", nil, 0)
    you.ring:SetTexture(CIRCLE_MASK_TEX)
    you.ring:SetAllPoints()
    you.ring:SetVertexColor(0, 0, 0, 0.9)
    you.dot = you:CreateTexture(nil, "ARTWORK", nil, 1)
    you.dot:SetTexture(CIRCLE_MASK_TEX)
    you.dot:SetPoint("TOPLEFT", 1.5, -1.5)
    you.dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    you.dot:SetVertexColor(1.0, 0.92, 0.25, 1)
    pv.you = you

    pv.note = pv:CreateFontString(nil, "OVERLAY")
    pv.note:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    pv.note:SetPoint("BOTTOM", sf, "BOTTOM", 0, 4)
    pv.note:SetTextColor(1.0, 0.75, 0.45)
    pv:Hide()
    CFQ.mapPreview = pv
    return pv
end

-- Map art for one map: layer size, tile size and the tile files (nil if the client has none)
function P.GetMapArt(mapID)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local layer = ok and type(layers) == "table" and layers[1]
    if not (layer and layer.layerWidth and layer.tileWidth) then return nil end
    local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not (ok2 and type(files) == "table" and #files > 0) then return nil end
    return { w = layer.layerWidth, h = layer.layerHeight, tw = layer.tileWidth, th = layer.tileHeight, files = files }
end

function CFQ.ShowMapPreview(entry, anchor)
    if not CFQ.parchmentOpts.mapPreview or not entry then return end
    local mapID = CFQ.GetHuntMapID({ questID = entry.questID, progKey = entry.progKey })
    local pv = CFQ.EnsureMapPreview()
    if not mapID then
        pv:Hide()
        return
    end
    local PW, PH = P.PREVIEW_W, P.PREVIEW_H
    local art = P.GetMapArt(mapID)
    local LW, LH = art and art.w or 1002, art and art.h or 668
    local marks = CFQ.CollectHuntMarks(entry.questID, entry.progKey, mapID)

    -- zoom to fit the marks with some margin (never closer than a third of the map, never past its edges)
    -- EDIT: change 0.35 below to zoom the preview in (smaller) or out (bigger)
    local minX, maxX, minY, maxY = 1, 0, 1, 0
    for _, mk in ipairs(marks) do
        minX, maxX = math.min(minX, mk.x - mk.r), math.max(maxX, mk.x + mk.r)
        minY, maxY = math.min(minY, mk.y - mk.r), math.max(maxY, mk.y + mk.r)
    end
    local scaleFit = math.max(PW / LW, PH / LH)            -- the whole map just fills the viewport
    local s = scaleFit
    local cx, cy = 0.5, 0.5
    if #marks > 0 then
        cx, cy = (minX + maxX) * 0.5, (minY + maxY) * 0.5
        local ex = math.max(1, (maxX - minX) * LW * 1.5)
        local ey = math.max(1, (maxY - minY) * LH * 1.5)
        s = math.min(PW / ex, PH / ey, PW / (0.35 * LW))     -- at least a third of the zone across: stays sharp
        s = math.max(s, scaleFit)
    end
    local CW, CH = LW * s, LH * s
    local child = pv.child
    child:SetSize(CW, CH)
    local sx = math.max(0, math.min(CW - PW, cx * CW - PW * 0.5))
    local sy = math.max(0, math.min(CH - PH, cy * CH - PH * 0.5))
    pv.sf:SetHorizontalScroll(sx)
    pv.sf:SetVerticalScroll(sy)

    -- map tiles
    local nTiles = 0
    if art then
        local cols = math.max(1, math.ceil(art.w / art.tw))
        for i, fid in ipairs(art.files) do
            local t = pv.tiles[i]
            if not t then
                t = child:CreateTexture(nil, "BACKGROUND", nil, 0)
                pv.tiles[i] = t
            end
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            t:SetTexture(fid)
            t:ClearAllPoints()
            t:SetSize(art.tw * s, art.th * s)
            t:SetPoint("TOPLEFT", child, "TOPLEFT", col * art.tw * s, -row * art.th * s)
            t:Show()
            nTiles = i
        end
    end
    for i = nTiles + 1, #pv.tiles do pv.tiles[i]:Hide() end
    pv.paper:SetShown(nTiles == 0)

    -- the quest's own area outline, then our rings on top
    if pv.blob then
        pcall(pv.blob.SetMapID, pv.blob, mapID)
        pcall(pv.blob.DrawNone, pv.blob)
        pcall(pv.blob.DrawBlob, pv.blob, entry.questID, true)
    end
    for i, mk in ipairs(marks) do
        local c = P.AcquireHuntCircle(child, i)
        c:SetFrameLevel(child:GetFrameLevel() + 10)          -- rings over the quest-area shape
        P.PlaceHuntCircle(c, child, mk.x, mk.y, mk.r * CW, mk.kind)
    end
    for i = #marks + 1, #child.circles do child.circles[i]:Hide() end

    local pMap, px, py = GetPlayerMapPositionSafe()
    local yx, yy
    if pMap and px and py then yx, yy = P.TranslatePos(pMap, px, py, mapID) end
    if yx then
        pv.you:ClearAllPoints()
        pv.you:SetPoint("CENTER", child, "TOPLEFT", yx * CW, -yy * CH)
        pv.you:Show()
    else
        pv.you:Hide()
    end

    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    pv.title:SetText("|cFFFFD100" .. ((info and info.name) or "Map") .. "|r  |cFFCCCCCC" .. (entry.itemName or "") .. "|r")
    pv.note:SetText((#marks == 0) and "no known spot yet: loot one and it's marked" or "")

    P.PlacePreview(pv, anchor or GameTooltip)
    pv:Show()
end

function CFQ.HideMapPreview()
    if CFQ.mapPreview then CFQ.mapPreview:Hide() end
end

-- ----------------------------------------------------------------------------
-- KEEPING POP-UPS CLEAR: the item tooltip goes beside the tally on whichever side has room, and
-- the map preview tries a ring of spots round the tooltip and the tally and takes the one that
-- stays on screen and covers the least: the tally and tooltip first, then other visible windows.
-- ----------------------------------------------------------------------------
function P.GetSuperTrackedID()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok then return (id and id > 0) and id or nil end
    end
    return lastSelectedQuestID
end

-- A visible frame's rectangle in UIParent units, grown by pad (nil if hidden / not laid out)
function P.ScreenRect(frame, pad)
    if type(frame) ~= "table" or not (frame.IsVisible and frame:IsVisible()) or not frame.GetRect then return nil end
    local l, b, w, h = frame:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local k = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    pad = pad or 0
    return { l = l * k - pad, b = b * k - pad, r = (l + w) * k + pad, t = (b + h) * k + pad }
end

function P.Overlap(a, b)
    if not (a and b) then return 0 end
    local w = math.min(a.r, b.r) - math.max(a.l, b.l)
    local h = math.min(a.t, b.t) - math.max(a.b, b.b)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- Windows and HUD pieces a pop-up shouldn't sit on (whichever exist and are showing).
-- EDIT: add another addon's frame by its global name (type /fstack in game to find it).
P.AVOID_FRAMES = {
    "ObjectiveTrackerFrame", "MinimapCluster", "PlayerFrame", "TargetFrame", "FocusFrame", "BuffFrame",
    "DebuffFrame", "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "MicroMenuContainer", "MicroButtonAndBagsBar",
    "BagsBar", "StanceBar", "PetActionBar", "PartyFrame", "CompactRaidFrameContainer", "WorldMapFrame",
    "QuestFrame", "GossipFrame", "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "MerchantFrame",
    "ContainerFrameCombinedBags", "SettingsPanel", "QRF_OptionsStandalone", "DressUpFrame", "MailFrame",
}

function P.CollectAvoidRects()
    local list, seen = {}, {}
    local function Add(name)
        if seen[name] then return end
        seen[name] = true
        local r = P.ScreenRect(_G[name], 2)
        if r then table.insert(list, r) end
    end
    for _, name in ipairs(P.AVOID_FRAMES) do Add(name) end
    for i = 1, (tonumber(NUM_CHAT_WINDOWS) or 10) do Add("ChatFrame" .. i) end
    for i = 1, 6 do Add("ContainerFrame" .. i) end
    for _, name in ipairs(UISpecialFrames or {}) do
        if type(name) == "string" then Add(name) end
    end
    return list
end

-- The tally's footprint, including the pages fanned out underneath
function P.TallyRect()
    return P.ScreenRect(shoppingListFrame, 12)
end

-- Item tooltip beside the tally, on the side with more room, level with the row
function P.PlaceTooltip(row)
    local F = P.TallyRect()
    if not F then
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local screenW = UIParent:GetWidth() or 1920
    local rowRight = (row.GetRight and row:GetRight()) or F.r
    local rowLeft = (row.GetLeft and row:GetLeft()) or F.l
    if (screenW - F.r) >= F.l then
        GameTooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", (F.r - rowRight) + 4, 4)
    else
        GameTooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -(rowLeft - F.l) - 4, 4)
    end
end

function P.PlacePreview(pv, tip)
    local W, H = pv:GetWidth() or 228, pv:GetHeight() or 171
    local T = P.ScreenRect(tip, 0)
    local F = P.TallyRect()
    pv:ClearAllPoints()
    if not T and not F then
        -- nothing to measure against yet: plain under-the-tooltip spot
        pv:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -2)
        return
    end
    local SW, SH = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
    local others = P.CollectAvoidRects()
    local cands = {}
    local function Add(x, y) table.insert(cands, { x = x, y = y }) end
    local g = 3
    if T then
        Add(T.l, T.b - g - H)               -- under the tooltip
        Add(T.r - W, T.b - g - H)
        Add(T.l, T.t + g)                   -- over it
        Add(T.r - W, T.t + g)
        Add(T.r + g, T.t - H)               -- beside it
        Add(T.l - g - W, T.t - H)
    end
    if F then
        Add(F.r + g, F.t - H)               -- beside the tally
        Add(F.l - g - W, F.t - H)
        Add(F.r + g, F.b)
        Add(F.l - g - W, F.b)
        Add(F.l, F.t + g)                   -- over / under it
        Add(F.r - W, F.t + g)
        Add(F.l, F.b - g - H)
    end
    local best, bestScore
    local cx = T and (T.l + T.r) * 0.5 or (F.l + F.r) * 0.5
    local cy = T and (T.b + T.t) * 0.5 or (F.b + F.t) * 0.5
    for _, c in ipairs(cands) do
        -- keep it fully on screen
        local x = math.max(0, math.min(SW - W, c.x))
        local y = math.max(0, math.min(SH - H, c.y))
        local R = { l = x, b = y, r = x + W, t = y + H }
        local score = 50 * (P.Overlap(R, F) + P.Overlap(R, T))
        for _, o in ipairs(others) do score = score + P.Overlap(R, o) end
        local dx, dy = (x + W * 0.5) - cx, (y + H * 0.5) - cy
        score = score + 0.05 * math.sqrt(dx * dx + dy * dy)          -- prefer close by
        if not bestScore or score < bestScore then best, bestScore = { x = x, y = y }, score end
    end
    pv:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", best.x, best.y)
end

-- ----------------------------------------------------------------------------
-- MINIMAP PINS: amber pips where you've looted the items of the quest you're tracking.
-- Blizzard already shows the tracked quest's own area / arrow; these add the spots you've
-- actually found the items. Positions come from world coordinates, scaled by the minimap's
-- zoom (yards across the minimap per zoom level, as every minimap-pin addon uses), and turned
-- with the player when "Rotate Minimap" is on. Out-of-range spots sit on the rim.
-- ----------------------------------------------------------------------------
P.MINIMAP_YARDS = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}
P.MAX_MINIMAP_PINS = 8      -- EDIT: most pins shown at once (nearest first)

function P.AcquireMinimapPin(i)
    P.mmPins = P.mmPins or {}
    local pin = P.mmPins[i]
    if pin then return pin end
    pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(10, 10)
    pin:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
    pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 0)
    pin.ring:SetTexture(CIRCLE_MASK_TEX)
    pin.ring:SetAllPoints()
    pin.ring:SetVertexColor(0.25, 0.12, 0.02, 0.95)
    pin.dot = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    pin.dot:SetTexture(CIRCLE_MASK_TEX)
    pin.dot:SetPoint("TOPLEFT", 2, -2)
    pin.dot:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.dot:SetVertexColor(1.0, 0.66, 0.12, 1)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.itemName or "Quest item", 1.0, 0.82, 0)
        GameTooltip:AddLine("You've found it here" .. ((self.n or 1) > 1 and string.format(" (%d times)", self.n) or ""), 0.9, 0.9, 0.9)
        if self.questTitle then GameTooltip:AddLine(self.questTitle, 0.65, 0.65, 0.65) end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.mmPins[i] = pin
    return pin
end

function CFQ.UpdateMinimapPins()
    local shown = 0
    local mm = Minimap
    local qID = P.GetSuperTrackedID()
    local q = qID and questRewardMap[qID]
    if mm and q and CFQ.parchmentOpts.minimapPins and mm.IsVisible and mm:IsVisible() then
        local pMap, px, py = GetPlayerMapPositionSafe()
        local pc, pwx, pwy
        if pMap and px and py then pc, pwx, pwy = CFQ.MapPosToWorld(pMap, px, py) end
        if pc then
            local rawZoom = mm.GetZoom and mm:GetZoom()
            local zoom = tonumber(rawZoom) or 0
            local sizes = (IsIndoors and IsIndoors()) and P.MINIMAP_YARDS.indoor or P.MINIMAP_YARDS.outdoor
            local yardsAcross = sizes[zoom] or sizes[0]
            local R = (mm:GetWidth() or 140) * 0.5
            local pxPerYard = R / (yardsAcross * 0.5)
            local facing = 0
            if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then facing = GetPlayerFacing() or 0 end
            local cosF, sinF = math.cos(facing), math.sin(facing)

            -- nearest spots first, across every unfinished item of the tracked quest
            local spots = {}
            for _, obj in ipairs(q.itemObjectives or {}) do
                if not obj.finished then
                    for _, sp in ipairs(CFQ.huntSpots[obj.progKey] or {}) do
                        local c, wx, wy = CFQ.MapPosToWorld(sp.m, sp.x, sp.y)
                        if c and c == pc then
                            -- world X runs north, world Y runs west
                            local east, north = -(wy - pwy), (wx - pwx)
                            table.insert(spots, { east = east, north = north, d = east * east + north * north,
                                item = obj.itemName, n = sp.n })
                        end
                    end
                end
            end
            table.sort(spots, function(a, b) return a.d < b.d end)
            for _, s in ipairs(spots) do
                if shown >= P.MAX_MINIMAP_PINS then break end
                local x = (s.east * cosF + s.north * sinF) * pxPerYard
                local y = (-s.east * sinF + s.north * cosF) * pxPerYard
                local dist = math.sqrt(x * x + y * y)
                local edge = R - 6
                local onRim = dist > edge
                if onRim and dist > 0 then x, y = x / dist * edge, y / dist * edge end
                shown = shown + 1
                local pin = P.AcquireMinimapPin(shown)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", mm, "CENTER", x, y)
                pin:SetAlpha(onRim and 0.55 or 1)
                pin.itemName, pin.n, pin.questTitle = s.item, s.n, q.title
                pin:Show()
            end
        end
    end
    for i = shown + 1, #(P.mmPins or {}) do P.mmPins[i]:Hide() end
end

-- moves with you: re-placed ten times a second (pins only show for the tracked quest's looted spots)
function CFQ.EnsureMinimapDriver()
    if CFQ.mmDriver or not Minimap then return end
    local drv = CreateFrame("Frame", nil, Minimap)
    drv.acc = 0
    drv:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + (elapsed or 0)
        if self.acc < 0.1 then return end
        self.acc = 0
        local ok, err = pcall(CFQ.UpdateMinimapPins)
        if not ok then
            CFQ.ReportError(err)
            self:SetScript("OnUpdate", nil)     -- don't spam errors every frame
        end
    end)
    CFQ.mmDriver = drv
end

-- ============================================================================
-- INTERACTIVE STACKED (? & •••) CARD DECK WIDGET (OBJECTIVE TRACKER ONLY)
-- Selected quest stays in place while fanned out, and moves to #1 on top AFTER collapse!
-- ============================================================================
local PopulateTrackerStackDeck

local function ApplyNativeTrackerFontsToDeck(deck)
    if not deck then return end
    if nativeTitleFont and nativeTitleSize then
        deck.topCard.leadQuestText:SetFont(nativeTitleFont, nativeTitleSize, nativeTitleFlags or "")
        for i = 1, MAX_CARDS_PER_STACK do
            if deck.cards[i] and deck.cards[i].titleText then
                deck.cards[i].titleText:SetFont(nativeTitleFont, nativeTitleSize, nativeTitleFlags or "")
            end
        end
    end
    if nativeLineFont and nativeLineSize then
        deck.topCard.subLineText:SetFont(nativeLineFont, nativeLineSize, nativeLineFlags or "")
        for i = 1, MAX_CARDS_PER_STACK do
            if deck.cards[i] and deck.cards[i].subLineText then
                deck.cards[i].subLineText:SetFont(nativeLineFont, nativeLineSize, nativeLineFlags or "")
            end
        end
    end
end

local function RefreshExpandedDeckHighlightsInPlace(deck)
    if not deck or not deck.displayQuests then return end
    local quests = deck.displayQuests
    local count = math.min(#quests, MAX_CARDS_PER_STACK)

    for i = 1, count do
        local card = deck.cards[i]
        local qData = quests[i]
        if card and qData then
            local superTracked = IsQuestSuperTracked(qData.questID)
            local lvlTag = string.format("|c%s[%d]|r ", qData.levelHex or "FFFFFFFF", qData.level or 0)

            card.qIcon:SetVisualState(qData.isComplete, superTracked)

            local titleCol = superTracked and "|cFFFFF5BA" or "|cFFFFD100"
            local subCol   = superTracked and "|cFFFFE699" or "|cFFCCCCCC"
            card.titleText:SetText(lvlTag .. titleCol .. (qData.title or "Quest") .. "|r")
            card.subLineText:SetText(subCol .. (qData.objectiveText or "") .. "|r")
            card.badgeText:SetText(GetCompactRewardString(qData, 2))

            if superTracked then
                card.body.outerGlow:Show()
                card.body.border:SetColorTexture(1.0, 0.86, 0.18, 1.0)
                card.body.bg:SetColorTexture(0.17, 0.13, 0.04, 0.98)
            else
                card.body.outerGlow:Hide()
                card.body.border:SetColorTexture(0.42, 0.42, 0.48, 0.92)
                card.body.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)
            end
        end
    end
end

local function AcquireTrackerStackDeck(index, parentFrame)
    local deck = trackerStackDeckPool[index]
    if deck then
        deck:SetParent(parentFrame)
        ApplyNativeTrackerFontsToDeck(deck)
        return deck
    end

    deck = CreateFrame("Button", "QRF_TrackerStackDeck" .. index, parentFrame)
    deck:SetSize(242, 42)
    deck:EnableMouse(true)
    deck:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    deck.expandProgress = 0
    deck.isHovered = false
    deck.hoverGraceTimer = 0
    deck.needsCollapsePromotion = false
    deck.cards = {}

    local ICON_COL_WIDTH = 26
    local CARD_HEIGHT = 36

    local backLayer2 = CreateFrame("Frame", nil, deck)
    backLayer2:SetPoint("TOPLEFT", deck, "TOPLEFT", 6, -6)
    backLayer2:SetPoint("TOPRIGHT", deck, "TOPRIGHT", 6, -6)
    backLayer2:SetHeight(CARD_HEIGHT)
    backLayer2:SetFrameLevel(deck:GetFrameLevel() + 1)

    backLayer2.qIcon = CreateRoundQuestPOI(backLayer2, 20, true, true, 0.65)
    backLayer2.qIcon:SetPoint("TOPLEFT", backLayer2, "TOPLEFT", 0, -2)

    backLayer2.cardBox = CreateFrame("Frame", nil, backLayer2)
    backLayer2.cardBox:SetPoint("TOPLEFT", backLayer2, "TOPLEFT", ICON_COL_WIDTH, 0)
    backLayer2.cardBox:SetPoint("BOTTOMRIGHT", backLayer2, "BOTTOMRIGHT", 0, 0)
    backLayer2.cardBox.border = backLayer2.cardBox:CreateTexture(nil, "BACKGROUND")
    backLayer2.cardBox.border:SetPoint("TOPLEFT", -1, 1)
    backLayer2.cardBox.border:SetPoint("BOTTOMRIGHT", 1, -1)
    backLayer2.cardBox.border:SetColorTexture(0.32, 0.28, 0.14, 0.90)
    backLayer2.cardBox.bg = backLayer2.cardBox:CreateTexture(nil, "ARTWORK")
    backLayer2.cardBox.bg:SetAllPoints()
    backLayer2.cardBox.bg:SetColorTexture(0.03, 0.03, 0.04, 0.94)
    deck.backCard2 = backLayer2

    local backLayer1 = CreateFrame("Frame", nil, deck)
    backLayer1:SetPoint("TOPLEFT", deck, "TOPLEFT", 3, -3)
    backLayer1:SetPoint("TOPRIGHT", deck, "TOPRIGHT", 3, -3)
    backLayer1:SetHeight(CARD_HEIGHT)
    backLayer1:SetFrameLevel(deck:GetFrameLevel() + 3)

    backLayer1.qIcon = CreateRoundQuestPOI(backLayer1, 20, true, true, 0.82)
    backLayer1.qIcon:SetPoint("TOPLEFT", backLayer1, "TOPLEFT", 0, -2)

    backLayer1.cardBox = CreateFrame("Frame", nil, backLayer1)
    backLayer1.cardBox:SetPoint("TOPLEFT", backLayer1, "TOPLEFT", ICON_COL_WIDTH, 0)
    backLayer1.cardBox:SetPoint("BOTTOMRIGHT", backLayer1, "BOTTOMRIGHT", 0, 0)
    backLayer1.cardBox.border = backLayer1.cardBox:CreateTexture(nil, "BACKGROUND")
    backLayer1.cardBox.border:SetPoint("TOPLEFT", -1, 1)
    backLayer1.cardBox.border:SetPoint("BOTTOMRIGHT", 1, -1)
    backLayer1.cardBox.border:SetColorTexture(0.50, 0.43, 0.18, 0.94)
    backLayer1.cardBox.bg = backLayer1.cardBox:CreateTexture(nil, "ARTWORK")
    backLayer1.cardBox.bg:SetAllPoints()
    backLayer1.cardBox.bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    deck.backCard1 = backLayer1

    local topCard = CreateFrame("Frame", nil, deck)
    topCard:SetPoint("TOPLEFT", deck, "TOPLEFT", 0, 0)
    topCard:SetPoint("TOPRIGHT", deck, "TOPRIGHT", 0, 0)
    topCard:SetHeight(CARD_HEIGHT)
    topCard:SetFrameLevel(deck:GetFrameLevel() + 5)

    topCard.qIcon = CreateRoundQuestPOI(topCard, 20, true, false, 1.0)
    topCard.qIcon:SetPoint("TOPLEFT", topCard, "TOPLEFT", 0, -2)

    local topBody = CreateFrame("Frame", nil, topCard)
    topBody:SetPoint("TOPLEFT", topCard, "TOPLEFT", ICON_COL_WIDTH, 0)
    topBody:SetPoint("BOTTOMRIGHT", topCard, "BOTTOMRIGHT", 0, 0)

    topBody.outerGlow = topBody:CreateTexture(nil, "BACKGROUND", nil, -1)
    topBody.outerGlow:SetPoint("TOPLEFT", -2, 2)
    topBody.outerGlow:SetPoint("BOTTOMRIGHT", 2, -2)
    topBody.outerGlow:SetColorTexture(1.0, 0.85, 0.15, 0.45)
    topBody.outerGlow:Hide()

    topBody.border = topBody:CreateTexture(nil, "BACKGROUND", nil, 0)
    topBody.border:SetPoint("TOPLEFT", -1, 1)
    topBody.border:SetPoint("BOTTOMRIGHT", 1, -1)
    topBody.border:SetColorTexture(0.65, 0.55, 0.22, 0.92)

    topBody.bg = topBody:CreateTexture(nil, "ARTWORK")
    topBody.bg:SetAllPoints()
    topBody.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)
    topCard.body = topBody

    topCard.leadQuestText = topBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    topCard.leadQuestText:SetPoint("TOPLEFT", topBody, "TOPLEFT", 6, -4)
    topCard.leadQuestText:SetPoint("RIGHT", topBody, "RIGHT", -36, 0)
    topCard.leadQuestText:SetJustifyH("LEFT")
    topCard.leadQuestText:SetWordWrap(false)

    topCard.stackCountText = topBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    topCard.stackCountText:SetPoint("TOPRIGHT", topBody, "TOPRIGHT", -5, -4)
    topCard.stackCountText:SetJustifyH("RIGHT")

    topCard.subLineText = topBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    topCard.subLineText:SetPoint("BOTTOMLEFT", topBody, "BOTTOMLEFT", 6, 4)
    topCard.subLineText:SetPoint("RIGHT", topBody, "RIGHT", -52, 0)
    topCard.subLineText:SetJustifyH("LEFT")
    topCard.subLineText:SetWordWrap(false)

    topCard.badgeText = topBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    topCard.badgeText:SetPoint("BOTTOMRIGHT", topBody, "BOTTOMRIGHT", -5, 4)
    topCard.badgeText:SetJustifyH("RIGHT")

    deck.topCard = topCard

    for c = 1, MAX_CARDS_PER_STACK do
        local card = CreateFrame("Button", nil, deck)
        card:SetHeight(CARD_HEIGHT)
        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        card:SetFrameLevel(deck:GetFrameLevel() + 10 + c)
        card:Hide()

        card.qIcon = CreateRoundQuestPOI(card, 20, true, false, 1.0)
        card.qIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -2)

        local body = CreateFrame("Frame", nil, card)
        body:SetPoint("TOPLEFT", card, "TOPLEFT", ICON_COL_WIDTH, 0)
        body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        card.body = body

        body.outerGlow = body:CreateTexture(nil, "BACKGROUND", nil, -1)
        body.outerGlow:SetPoint("TOPLEFT", -2, 2)
        body.outerGlow:SetPoint("BOTTOMRIGHT", 2, -2)
        body.outerGlow:SetColorTexture(1.0, 0.85, 0.15, 0.40)
        body.outerGlow:Hide()

        body.border = body:CreateTexture(nil, "BACKGROUND", nil, 0)
        body.border:SetPoint("TOPLEFT", -1, 1)
        body.border:SetPoint("BOTTOMRIGHT", 1, -1)
        body.border:SetColorTexture(0.42, 0.42, 0.48, 0.92)

        body.bg = body:CreateTexture(nil, "ARTWORK")
        body.bg:SetAllPoints()
        body.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)

        body.highlight = body:CreateTexture(nil, "HIGHLIGHT")
        body.highlight:SetAllPoints()
        body.highlight:SetColorTexture(1.0, 0.82, 0.0, 0.16)

        card.titleText = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.titleText:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -4)
        card.titleText:SetPoint("RIGHT", body, "RIGHT", -6, 0)
        card.titleText:SetJustifyH("LEFT")
        card.titleText:SetWordWrap(false)

        card.subLineText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.subLineText:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 4)
        card.subLineText:SetPoint("RIGHT", body, "RIGHT", -52, 0)
        card.subLineText:SetJustifyH("LEFT")
        card.subLineText:SetWordWrap(false)

        card.badgeText = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.badgeText:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -5, 4)
        card.badgeText:SetJustifyH("RIGHT")

        card:SetScript("OnEnter", function(self)
            self.body.border:SetColorTexture(1.0, 0.85, 0.20, 1.0)
        end)

        card:SetScript("OnLeave", function(self)
            local isSel = self.qData and IsQuestSuperTracked(self.qData.questID)
            if isSel then
                self.body.border:SetColorTexture(1.0, 0.85, 0.15, 1.0)
                self.body.bg:SetColorTexture(0.16, 0.12, 0.04, 0.98)
            else
                self.body.border:SetColorTexture(0.42, 0.42, 0.48, 0.92)
                self.body.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)
            end
        end)

        deck.cards[c] = card
    end

    deck:SetScript("OnClick", function(self, button)
        if not self.clusterData or not self.clusterData.quests or #self.clusterData.quests == 0 then return end
        local topQuest = (self.displayQuests and self.displayQuests[1]) or self.clusterData.quests[1]
        if button == "RightButton" then
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(topQuest.questID)
            end
        else
            ActivateQuestTarget(topQuest.questID)
            RefreshExpandedDeckHighlightsInPlace(self)
        end
    end)

    deck:SetScript("OnUpdate", function(self, elapsed)
        elapsed = math.min(elapsed, 0.05)
        local numCards = self.numActiveCards or 0
        if numCards == 0 then return end

        local mouseOverAny = self:IsMouseOver(4, -4, -4, 4) or self.topCard:IsMouseOver(4, -4, -4, 4)
        if not mouseOverAny and self.expandProgress > 0.05 then
            for i = 1, numCards do
                local c = self.cards[i]
                if c:IsShown() and c:IsMouseOver(4, -4, -6, 6) then
                    mouseOverAny = true
                    break
                end
            end
        end

        if mouseOverAny then
            self.hoverGraceTimer = 0.14
            self.isHovered = true
        elseif self.hoverGraceTimer > 0 then
            self.hoverGraceTimer = self.hoverGraceTimer - elapsed
            if self.hoverGraceTimer <= 0 then
                self.isHovered = false
            end
        else
            self.isHovered = false
        end

        local target = self.isHovered and 1.0 or 0.0
        if math.abs(self.expandProgress - target) > 0.005 then
            local speed = self.isHovered and 11.0 or 9.0
            self.expandProgress = self.expandProgress + (target - self.expandProgress) * math.min(1.0, elapsed * speed)
            if math.abs(self.expandProgress - target) <= 0.01 then
                self.expandProgress = target
            end

            local p = self.expandProgress
            self.topCard:SetAlpha(1.0 - p)
            self.backCard1:SetAlpha(1.0 - p)
            self.backCard2:SetAlpha((numCards >= 3) and (1.0 - p) or 0)

            for i = 1, numCards do
                local card = self.cards[i]
                if p > 0.02 then
                    card:Show()
                    card:SetAlpha(p)
                    local stackedX = math.min(i - 1, 2) * 3 * (1.0 - p)
                    local stackedY = -math.min(i - 1, 2) * 3 * (1.0 - p)
                    local fannedY = -((i - 1) * (CARD_HEIGHT + 4))
                    local curY = stackedY + (fannedY - stackedY) * p

                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", self, "TOPLEFT", stackedX, curY)
                    card:SetPoint("TOPRIGHT", self, "TOPRIGHT", stackedX, curY)
                else
                    card:Hide()
                end
            end

            local collapsedH = CARD_HEIGHT + 6
            local expandedH = (numCards * CARD_HEIGHT) + ((numCards - 1) * 4)
            self:SetHeight(collapsedH + (expandedH - collapsedH) * p)

            if self.expandProgress <= 0.01 and not self.isHovered and self.needsCollapsePromotion and self.clusterData then
                self.needsCollapsePromotion = false
                PopulateTrackerStackDeck(self, self.clusterData, true)
            end

            if LayoutObjectiveTrackerWithStacks then
                LayoutObjectiveTrackerWithStacks(true)
            end
        elseif self.expandProgress <= 0.01 and not self.isHovered and self.needsCollapsePromotion and self.clusterData then
            self.needsCollapsePromotion = false
            PopulateTrackerStackDeck(self, self.clusterData, true)
        end
    end)

    ApplyNativeTrackerFontsToDeck(deck)
    trackerStackDeckPool[index] = deck
    return deck
end

local function UpdateDeckCollapsedTopCard(deck, clusterGroup, orderedQuests)
    local quests = orderedQuests or clusterGroup.quests
    local count = math.min(#quests, MAX_CARDS_PER_STACK)
    local isCompCluster = clusterGroup.isComplete == true

    local selectedQuest = nil
    for i = 1, #quests do
        if quests[i] and IsQuestSuperTracked(quests[i].questID) then
            selectedQuest = quests[i]
            break
        end
    end

    local anySelectedInStack = (selectedQuest ~= nil)
    local topQuest = selectedQuest or quests[1]

    deck.backCard1.qIcon:SetVisualState(isCompCluster, false)
    deck.backCard2.qIcon:SetVisualState(isCompCluster, false)
    deck.topCard.qIcon:SetVisualState(isCompCluster, anySelectedInStack)

    if anySelectedInStack then
        deck.topCard.body.outerGlow:Show()
        deck.topCard.body.border:SetColorTexture(1.0, 0.86, 0.18, 1.0)
        deck.topCard.body.bg:SetColorTexture(0.17, 0.13, 0.04, 0.98)
        deck.backCard1.cardBox.border:SetColorTexture(0.85, 0.68, 0.16, 0.95)
        deck.backCard2.cardBox.border:SetColorTexture(0.65, 0.50, 0.12, 0.90)
        deck.topCard.stackCountText:SetText(string.format("|cFFFFF5BAx%d|r", #quests))
    else
        deck.topCard.body.outerGlow:Hide()
        deck.topCard.body.border:SetColorTexture(0.65, 0.55, 0.22, 0.92)
        deck.topCard.body.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)
        deck.backCard1.cardBox.border:SetColorTexture(0.50, 0.43, 0.18, 0.94)
        deck.backCard2.cardBox.border:SetColorTexture(0.32, 0.28, 0.14, 0.90)
        deck.topCard.stackCountText:SetText(string.format("|cFFFFD100x%d|r", #quests))
    end

    if topQuest then
        local lvlStr = string.format("|c%s[%d]|r ", topQuest.levelHex or "FFFFFFFF", topQuest.level or 0)
        local titleColor = anySelectedInStack and "|cFFFFF5BA" or "|cFFFFD100"
        local subColor   = anySelectedInStack and "|cFFFFE699" or "|cFFCCCCCC"
        deck.topCard.leadQuestText:SetText(lvlStr .. titleColor .. (topQuest.title or "Quest") .. "|r")
        deck.topCard.subLineText:SetText(subColor .. (topQuest.objectiveText or "") .. "|r")
        deck.topCard.badgeText:SetText(GetCompactRewardString(topQuest, 2))
    end

    deck.backCard2:SetShown(count >= 3 and deck.expandProgress < 0.95)
end

PopulateTrackerStackDeck = function(deck, clusterGroup, forcePromoteTop)
    local isCurrentlyFannedOut = (deck.clusterID == clusterGroup.id) and (deck.expandProgress > 0.02 or deck.isHovered) and not forcePromoteTop

    if deck.clusterID ~= clusterGroup.id then
        deck.expandProgress = 0
        deck.isHovered = false
        deck.hoverGraceTimer = 0
        deck.needsCollapsePromotion = false
        deck.topCard:SetAlpha(1.0)
        deck.backCard1:SetAlpha(1.0)
        deck:SetHeight(42)
        for i = 1, MAX_CARDS_PER_STACK do
            deck.cards[i]:Hide()
        end
    end

    deck.clusterID = clusterGroup.id
    deck.clusterData = clusterGroup
    ApplyNativeTrackerFontsToDeck(deck)

    if isCurrentlyFannedOut and deck.displayQuests and #deck.displayQuests == #clusterGroup.quests then
        local byID = {}
        for _, q in ipairs(clusterGroup.quests) do
            byID[q.questID] = q
        end
        local allPresent = true
        for i, oldQ in ipairs(deck.displayQuests) do
            if byID[oldQ.questID] then
                deck.displayQuests[i] = byID[oldQ.questID]
            else
                allPresent = false
                break
            end
        end
        if allPresent then
            deck.needsCollapsePromotion = true
            UpdateDeckCollapsedTopCard(deck, clusterGroup, deck.displayQuests)
            RefreshExpandedDeckHighlightsInPlace(deck)
            return
        end
    end

    local orderedQuests = BuildCollapsedStackQuestOrder(clusterGroup.quests)
    deck.displayQuests = orderedQuests

    local count = math.min(#orderedQuests, MAX_CARDS_PER_STACK)
    deck.numActiveCards = count

    UpdateDeckCollapsedTopCard(deck, clusterGroup, orderedQuests)

    for i = 1, MAX_CARDS_PER_STACK do
        local card = deck.cards[i]
        local qData = orderedQuests[i]
        if i <= count and qData then
            card.qData = qData
            local superTracked = IsQuestSuperTracked(qData.questID)
            local lvlTag = string.format("|c%s[%d]|r ", qData.levelHex or "FFFFFFFF", qData.level or 0)

            card.qIcon:SetVisualState(qData.isComplete, superTracked)

            local titleCol = superTracked and "|cFFFFF5BA" or "|cFFFFD100"
            local subCol   = superTracked and "|cFFFFE699" or "|cFFCCCCCC"
            card.titleText:SetText(lvlTag .. titleCol .. (qData.title or "Quest") .. "|r")
            card.subLineText:SetText(subCol .. (qData.objectiveText or "") .. "|r")
            card.badgeText:SetText(GetCompactRewardString(qData, 2))

            if superTracked then
                card.body.outerGlow:Show()
                card.body.border:SetColorTexture(1.0, 0.86, 0.18, 1.0)
                card.body.bg:SetColorTexture(0.17, 0.13, 0.04, 0.98)
            else
                card.body.outerGlow:Hide()
                card.body.border:SetColorTexture(0.42, 0.42, 0.48, 0.92)
                card.body.bg:SetColorTexture(0.07, 0.07, 0.09, 0.97)
            end

            card:SetScript("OnClick", function(selfCard, button)
                local clickedQuest = selfCard.qData
                if not clickedQuest then return end
                if IsShiftKeyDown() then
                    if IsQuestWatched(clickedQuest.questID) then
                        if C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, clickedQuest.questID) end
                    else
                        if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, clickedQuest.questID) end
                    end
                    PopulateTrackerStackDeck(deck, clusterGroup, false)
                elseif button == "RightButton" then
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(clickedQuest.questID)
                    elseif QuestMapFrame_ShowQuestDetails then
                        QuestMapFrame_ShowQuestDetails(clickedQuest.questID)
                    end
                else
                    deck.needsCollapsePromotion = true
                    ActivateQuestTarget(clickedQuest.questID)
                    UpdateDeckCollapsedTopCard(deck, clusterGroup, deck.displayQuests)
                    RefreshExpandedDeckHighlightsInPlace(deck)
                    if UpdateShoppingListUI then UpdateShoppingListUI() end
                end
            end)
        else
            card.qData = nil
            card:Hide()
        end
    end
end

-- ============================================================================
-- SINGLE-ROW CLUSTER SLIDER BAR FLUSH UNDER THE "QUESTS" HEADER
-- ============================================================================
local ApplyFilterChanges

local function UpdateTrackerControlBarVisuals()
    if not trackerControlBar then return end

    trackerControlBar.turnInToggle.poi:SetVisualState(true, turnInStackEnabled)
    trackerControlBar.turnInSlider.UpdatingFromCode = true
    trackerControlBar.turnInSlider:SetValue(turnInRadiusPercent)
    trackerControlBar.turnInSlider.UpdatingFromCode = false
    trackerControlBar.turnInSlider:SetAlpha(turnInStackEnabled and 1.0 or 0.40)

    local tFillW = math.max(2, math.floor((turnInRadiusPercent / 50.0) * 60))
    trackerControlBar.turnInSlider.fill:SetWidth(tFillW)
    trackerControlBar.turnInSlider.fill:SetShown(turnInStackEnabled)
    trackerControlBar.turnInValText:SetText(turnInStackEnabled and string.format("|cFFFFD100%d%%|r", turnInRadiusPercent) or "|cFF777777Off|r")

    trackerControlBar.incompToggle.poi:SetVisualState(false, incompleteStackEnabled)
    trackerControlBar.incompSlider.UpdatingFromCode = true
    trackerControlBar.incompSlider:SetValue(incompleteRadiusPercent)
    trackerControlBar.incompSlider.UpdatingFromCode = false
    trackerControlBar.incompSlider:SetAlpha(incompleteStackEnabled and 1.0 or 0.40)

    local iFillW = math.max(2, math.floor((incompleteRadiusPercent / 50.0) * 60))
    trackerControlBar.incompSlider.fill:SetWidth(iFillW)
    trackerControlBar.incompSlider.fill:SetShown(incompleteStackEnabled)
    trackerControlBar.incompValText:SetText(incompleteStackEnabled and string.format("|cFFFFD100%d%%|r", incompleteRadiusPercent) or "|cFF777777Off|r")
end

local function EnsureTrackerControlBar(trackerModule)
    if not trackerModule or not trackerModule.ContentsFrame then return nil end
    local contentsFrame = trackerModule.ContentsFrame

    if not trackerControlBar then
        local bar = CreateFrame("Frame", "QRF_TrackerSubHeaderBar", contentsFrame)
        bar:SetHeight(24)
        bar:EnableMouse(true)

        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        ApplyHorizontalGradient(bg, 0.08, 0.06, 0.03, 0.85, 0.05)

        local botLine = bar:CreateTexture(nil, "BORDER")
        botLine:SetHeight(1)
        botLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -2, 0)
        botLine:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        ApplyHorizontalGradient(botLine, 0.72, 0.58, 0.22, 0.55, 0.0)

        local function CreateLargerClusterControl(isCompleteType, anchorLeftX)
            local toggleBtn = CreateFrame("Button", nil, bar)
            toggleBtn:SetSize(20, 20)
            toggleBtn:SetPoint("LEFT", bar, "LEFT", anchorLeftX, 0)
            toggleBtn.poi = CreateRoundQuestPOI(toggleBtn, 20, isCompleteType, false, 1.0)
            toggleBtn.poi:SetAllPoints()

            local slider = CreateFrame("Slider", nil, bar)
            slider:SetOrientation("HORIZONTAL")
            slider:SetSize(62, 14)
            slider:SetPoint("LEFT", toggleBtn, "RIGHT", 5, 0)
            slider:SetMinMaxValues(1, 50)
            slider:SetValueStep(1)
            if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

            local trackBorder = slider:CreateTexture(nil, "BACKGROUND", nil, 0)
            trackBorder:SetHeight(8)
            trackBorder:SetPoint("LEFT", slider, "LEFT", 0, 0)
            trackBorder:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
            trackBorder:SetColorTexture(0.58, 0.48, 0.20, 0.90)

            local trackBg = slider:CreateTexture(nil, "BACKGROUND", nil, 1)
            trackBg:SetHeight(6)
            trackBg:SetPoint("LEFT", slider, "LEFT", 1, 0)
            trackBg:SetPoint("RIGHT", slider, "RIGHT", -1, 0)
            trackBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

            local fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
            fill:SetHeight(6)
            fill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
            fill:SetWidth(20)
            fill:SetColorTexture(0.85, 0.68, 0.15, 0.85)
            slider.fill = fill

            local thumb = slider:CreateTexture(nil, "OVERLAY", nil, 3)
            thumb:SetSize(16, 18)
            thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            slider:SetThumbTexture(thumb)

            local valText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valText:SetPoint("LEFT", slider, "RIGHT", 4, 0)
            valText:SetJustifyH("LEFT")

            return toggleBtn, slider, valText
        end

        local tBtn, tSlider, tVal = CreateLargerClusterControl(true, 0)
        -- Toggling a stack type never touches the watch list: decks only contain quests that are
        -- already tracked, so switching off just un-hides their native blocks.
        tBtn:SetScript("OnClick", function()
            turnInStackEnabled = not turnInStackEnabled
            ApplyFilterChanges()
            CFQ.RequestNativeTrackerUpdate()           -- let Blizzard re-show / re-anchor its blocks
            CFQ.ScheduleTrackerRelayout(0.15)
        end)
        tSlider:SetScript("OnValueChanged", function(self, val)
            local rounded = math.floor((val or 16) + 0.5)
            if rounded ~= turnInRadiusPercent then
                turnInRadiusPercent = rounded
                if not self.UpdatingFromCode then
                    if not turnInStackEnabled then turnInStackEnabled = true end
                    ApplyFilterChanges()
                end
            end
        end)
        bar.turnInToggle = tBtn
        bar.turnInSlider = tSlider
        bar.turnInValText = tVal

        local iBtn, iSlider, iVal = CreateLargerClusterControl(false, 132)
        iBtn:SetScript("OnClick", function()
            incompleteStackEnabled = not incompleteStackEnabled
            ApplyFilterChanges()
            CFQ.RequestNativeTrackerUpdate()
            CFQ.ScheduleTrackerRelayout(0.15)
        end)
        iSlider:SetScript("OnValueChanged", function(self, val)
            local rounded = math.floor((val or 16) + 0.5)
            if rounded ~= incompleteRadiusPercent then
                incompleteRadiusPercent = rounded
                if not self.UpdatingFromCode then
                    if not incompleteStackEnabled then incompleteStackEnabled = true end
                    ApplyFilterChanges()
                end
            end
        end)
        bar.incompToggle = iBtn
        bar.incompSlider = iSlider
        bar.incompValText = iVal

        trackerControlBar = bar
    end

    trackerControlBar:SetParent(contentsFrame)
    trackerControlBar:ClearAllPoints()
    if trackerModule.Header and trackerModule.Header:IsShown() then
        trackerControlBar:SetPoint("TOPLEFT", trackerModule.Header, "BOTTOMLEFT", -26, -1)
        trackerControlBar:SetPoint("TOPRIGHT", trackerModule.Header, "BOTTOMRIGHT", -6, -1)
    else
        trackerControlBar:SetPoint("TOPLEFT", contentsFrame, "TOPLEFT", -26, -1)
        trackerControlBar:SetPoint("TOPRIGHT", contentsFrame, "TOPRIGHT", -6, -1)
    end
    trackerControlBar:Show()
    UpdateTrackerControlBarVisuals()
    return trackerControlBar
end

-- ============================================================================
-- ON-SCREEN OBJECTIVE TRACKER SORTING & STACKED DECK RE-LAYOUT
-- Strictly separates Quest Blocks from POI Buttons and uses cumulative yOffset!
-- ============================================================================
local function SetNativeTrackerBlockHidden(blk, poiBtn, hidden)
    if not blk then return end
    if hidden then
        if not blk.qrfHiddenByStack and blk.IsMouseEnabled then
            blk.qrfPrevMouse = blk:IsMouseEnabled()
        end
        blk.qrfHiddenByStack = true
        CFQ.stackHiddenRegistry[blk] = true
        blk:SetAlpha(0)
        if blk.EnableMouse then blk:EnableMouse(false) end
        if blk.HeaderButton and blk.HeaderButton.EnableMouse then
            blk.HeaderButton:EnableMouse(false)
        end
        local p = poiBtn or blk.poiButton
        if p then
            if not p.qrfHiddenByStack and p.IsMouseEnabled then
                p.qrfPrevMouse = p:IsMouseEnabled()
            end
            p.qrfHiddenByStack = true
            CFQ.stackHiddenRegistry[p] = true
            p:SetAlpha(0)
            if p.EnableMouse then p:EnableMouse(false) end
        end
    else
        if blk.qrfHiddenByStack then
            blk.qrfHiddenByStack = false
            blk:SetAlpha(1)
            if blk.EnableMouse then blk:EnableMouse(true) end
            if blk.HeaderButton and blk.HeaderButton.EnableMouse then
                blk.HeaderButton:EnableMouse(true)
            end
        end
        local p = poiBtn or blk.poiButton
        if p and p.qrfHiddenByStack then
            p.qrfHiddenByStack = false
            p:SetAlpha(1)
            if p.EnableMouse then p:EnableMouse(true) end
        end
    end
end

-- Restores EVERY native frame we have ever hidden (even ones Blizzard has since recycled for a
-- different quest or that lost their id), so a block can never get stranded invisible.
-- Called at the start of each full layout; frames that should stay stacked are re-hidden in the
-- same pass, so there is no visible flicker.
function CFQ.RestoreAllStackHiddenFrames()
    for frame in pairs(CFQ.stackHiddenRegistry) do
        if frame.qrfHiddenByStack then
            frame.qrfHiddenByStack = false
            frame:SetAlpha(1)
            if frame.EnableMouse then frame:EnableMouse(frame.qrfPrevMouse ~= false) end
            if frame.HeaderButton and frame.HeaderButton.EnableMouse then
                frame.HeaderButton:EnableMouse(true)
            end
        end
        frame.qrfPrevMouse = nil
        CFQ.stackHiddenRegistry[frame] = nil
    end
end

function CFQ.ReportError(err)
    local msg = tostring(err)
    if CFQ.reportedErrors[msg] then return end
    CFQ.reportedErrors[msg] = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler("HandkerSheaf: " .. msg)
    else
        print("|cFFFF5555HandkerSheaf error:|r " .. msg)
    end
end

function CFQ.ErrorWithStack(err)
    return tostring(err) .. ((debugstack and ("\n" .. debugstack(2))) or "")
end

-- Ask Blizzard's tracker to rebuild and re-anchor its own quest blocks. Needed whenever we
-- stop stacking: blocks we parked off-screen / Blizzard skipped while they were hidden only come
-- back when the native tracker runs a full layout (our Update hook then re-applies our layout).
function CFQ.RequestNativeTrackerUpdate()
    if InCombatLockdown() then return end
    if QuestObjectiveTracker and QuestObjectiveTracker.MarkDirty then
        pcall(QuestObjectiveTracker.MarkDirty, QuestObjectiveTracker)
    end
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then
        pcall(ObjectiveTrackerFrame.Update, ObjectiveTrackerFrame)
    elseif ObjectiveTracker_Update then
        pcall(ObjectiveTracker_Update)
    elseif WatchFrame_Update then
        pcall(WatchFrame_Update)
    end
end

-- /hanky debug: prints what the tracker contents frame holds so in-game layout problems can be diagnosed
function CFQ.DebugDumpTracker()
    local out = function(s) print("|cFFFFD100" .. CONFIG.DISPLAY_NAME .. "|r " .. s) end
    local mod = QuestObjectiveTracker
    out(string.format("turnIn=%s incomp=%s lvl=%s dist=%s filters=%d/%d",
        tostring(turnInStackEnabled), tostring(incompleteStackEnabled), levelSortMode, distSortMode,
        GetActiveRewardFilterCount(), GetActiveLevelFilterCount()))
    if not mod or not mod.ContentsFrame then out("QuestObjectiveTracker.ContentsFrame missing!"); return end
    local c = mod.ContentsFrame
    out(string.format("module shown=%s vis=%s h=%.0f | contents shown=%s h=%.0f clips=%s",
        tostring(mod:IsShown()), tostring(mod:IsVisible()), mod:GetHeight() or -1,
        tostring(c:IsShown()), c:GetHeight() or -1, tostring(c.DoesClipChildren and c:DoesClipChildren())))
    local n = 0
    for _, ch in ipairs({ c:GetChildren() }) do
        n = n + 1
        local kind = (ch == trackerControlBar and "BAR") or (ch.clusterData and "DECK")
            or ((type(ch.id) == "number" and ch.parentBlock == nil) and "BLOCK") or "other"
        local p, rel, rp, x, y = ch:GetPoint(1)
        local relName = rel and ((rel.GetName and rel:GetName()) or (rel == c and "contents") or (rel == trackerControlBar and "bar") or tostring(rel.id or "?")) or "-"
        local q = type(ch.id) == "number" and questRewardMap[ch.id]
        out(string.format("%d %s id=%s shown=%s vis=%s a=%.2f stackHid=%s w=%.0f h=%.0f pts=%d %s>%s:%s %.0f,%.0f %s%s",
            n, kind, tostring(ch.id), tostring(ch:IsShown()), tostring(ch:IsVisible()), ch:GetAlpha() or -1,
            tostring(ch.qrfHiddenByStack), ch:GetWidth() or -1, ch:GetHeight() or -1, ch:GetNumPoints() or 0,
            tostring(p), relName, tostring(rp), x or 0, y or 0,
            q and ("'" .. (q.title or "") .. "'") or "", (q and q.clusterID) and (" " .. q.clusterID) or ""))
    end
    out(n .. " children")
end

-- /hanky items: every counted objective, its type, and whether it's an item (+) or a task (-) (for "why is X listed?")
function CFQ.DebugDumpItems()
    print("|cFFFFD100HandkerSheaf items:|r objectives with counts (+ = item, - = task)")
    local ids = {}
    for qID in pairs(questRewardMap) do table.insert(ids, qID) end
    table.sort(ids)
    local n = 0
    for _, qID in ipairs(ids) do
        local q = questRewardMap[qID]
        for _, o in ipairs(q.quantityObjectives or {}) do
            n = n + 1
            local spots = CFQ.huntSpots[o.progKey]
            print(string.format("  %s %s: %s  [type=%s] %d/%d%s", o.isItem and "|cFF40FF40+|r" or "|cFF888888-|r",
                q.title or tostring(qID), o.itemName or "?", tostring(o.objType or "none"),
                o.numFulfilled or 0, o.numRequired or 0,
                (spots and #spots > 0) and string.format("  (%d hunt spots)", #spots) or ""))
        end
    end
    if n == 0 then print("  (no counted objectives in your quest log)") end
end

function CFQ.ScheduleTrackerRelayout(delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.1, function()
            if not InCombatLockdown() and LayoutObjectiveTrackerWithStacks then
                LayoutObjectiveTrackerWithStacks()
            end
        end)
    end
end

-- ============================================================================
-- QUEST ITEM BUTTONS ON DECKS
-- A quest with a usable item (an eye, a phial...) still stacks; its item gets our own button to the LEFT
-- of the deck: in a row beside the collapsed deck, sliding next to its own card as the deck fans out.
-- Blizzard's button lives on the quest's tracker block, which the deck hides, so we make our own secure
-- item buttons (SecureActionButtonTemplate, type "item": they work in combat). Secure frames can only be
-- set up, moved or shown out of combat: in combat they stay where they were (the layout is frozen then
-- anyway) and catch up when combat ends. They're parented to UIParent and placed by screen position,
-- never anchored to a deck: anchoring them would make the deck protected and break its hover animation.
-- ============================================================================
CFQ.ITEM_BTN_SIZE = 24
CFQ.itemButtons = {}

function CFQ.AcquireItemButton(i)
    local b = CFQ.itemButtons[i]
    if b then return b end
    b = CreateFrame("Button", "HandkerquestQuestItem" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetSize(CFQ.ITEM_BTN_SIZE, CFQ.ITEM_BTN_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(30)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", -1, 1)
    b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    b.bg:SetColorTexture(0, 0, 0, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local okC, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if okC and cd then
        cd:SetAllPoints()
        b.cooldown = cd
    end
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    CFQ.itemButtons[i] = b
    return b
end

-- Can this client make secure item buttons? (If not, quests with items stay out of decks instead.)
function CFQ.ItemButtonsSupported()
    if CFQ.secureItemsOK == nil then
        if InCombatLockdown() then return false end          -- ask again out of combat
        local ok, b = pcall(CFQ.AcquireItemButton, 1)
        CFQ.secureItemsOK = (ok and b and b.SetAttribute) and true or false
    end
    return CFQ.secureItemsOK
end

function CFQ.UpdateItemCooldown(b)
    if not (b.cooldown and GetQuestLogSpecialItemCooldown and b.logIndex) then return end
    local ok, start, dur, enable = pcall(GetQuestLogSpecialItemCooldown, b.logIndex)
    if ok and start and dur and dur > 0 and enable ~= 0 then
        b.cooldown:SetCooldown(start, dur)
    elseif b.cooldown.Clear then
        b.cooldown:Clear()
    end
end

-- Point a button at a quest's item (out of combat only: secure attributes)
function CFQ.SetItemButton(b, it)
    if b.link ~= it.link then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", it.link)                   -- used from your bags, like the tracker's own button
    end
    b.link, b.logIndex, b.questLogIndex = it.link, it.logIndex, it.logIndex
    b.icon:SetTexture(it.tex)
    b.count:SetText((it.charges and it.charges > 1) and tostring(it.charges) or "")
    CFQ.UpdateItemCooldown(b)
end

-- Put a button beside every deck quest that has an item: left of the collapsed deck in a row (the top
-- card's item nearest the deck), gliding next to each quest's own card as the deck fans out.
function CFQ.PlaceDeckItemButtons()
    if InCombatLockdown() then CFQ.itemButtonsDirty = true; return end
    CFQ.itemButtonsDirty = false
    local used = 0
    if CFQ.ItemButtonsSupported() then
        local ui = UIParent:GetEffectiveScale()
        local size, gap = CFQ.ITEM_BTN_SIZE, 4
        for _, deck in ipairs(trackerStackDeckPool) do
            if deck:IsVisible() and deck.displayQuests and deck:GetLeft() and deck:GetTop() then
                local s = deck:GetEffectiveScale() / ui
                local p = deck.expandProgress or 0
                local deckLeft, deckTop = deck:GetLeft() * s, deck:GetTop() * s
                local k = 0
                for i, q in ipairs(deck.displayQuests) do
                    if i > (deck.numActiveCards or 0) then break end
                    local it = q.questItem
                    if it and it.link then
                        used = used + 1
                        local b = CFQ.AcquireItemButton(used)
                        CFQ.SetItemButton(b, it)
                        local x, y = deckLeft - gap - k * (size + 3), deckTop - 4
                        local card = deck.cards[i]
                        if p > 0.02 and card and card:IsShown() and card:GetLeft() and card:GetTop() then
                            local cx, cy = card:GetLeft() * s - gap, card:GetTop() * s - 4
                            x, y = x + (cx - x) * p, y + (cy - y) * p
                        end
                        b:ClearAllPoints()
                        b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
                        b.questID = q.questID
                        b:Show()
                        k = k + 1
                    end
                end
            end
        end
    end
    for i = used + 1, #CFQ.itemButtons do CFQ.itemButtons[i]:Hide() end
end

local function LayoutTrackerImpl(isAnimationTick)
    local previousDecksByCluster = {}
    if not isAnimationTick then
        ScanQuestLogRewards()
        CFQ.RestoreAllStackHiddenFrames()
        for _, deck in ipairs(trackerStackDeckPool) do
            if deck:IsShown() and deck.clusterID then
                previousDecksByCluster[deck.clusterID] = deck
            end
            deck:Hide()
        end
    end

    local usedDecks = {}
    local controlBarPlaced = false
    local hasActiveFilter = (GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0)

    local function AcquireDeckForCluster(cID, contents)
        local existing = previousDecksByCluster[cID]
        if existing and not usedDecks[existing] then
            usedDecks[existing] = true
            existing:SetParent(contents)
            ApplyNativeTrackerFontsToDeck(existing)
            return existing
        end
        for idx = 1, 24 do
            local candidate = AcquireTrackerStackDeck(idx, contents)
            if not usedDecks[candidate] and not candidate:IsShown() then
                usedDecks[candidate] = true
                return candidate
            end
        end
        local fallback = AcquireTrackerStackDeck(1, contents)
        usedDecks[fallback] = true
        return fallback
    end

    local function ProcessTrackerModule(trackerModule)
        if not trackerModule or not trackerModule.ContentsFrame then return end
        local contents = trackerModule.ContentsFrame
        local rawBlocks = {}
        local poiByQuestID = {}

        local children = { contents:GetChildren() }
        -- Pass 1: Separate POI buttons from actual Quest Blocks so POI buttons are never treated as blocks!
        for _, child in ipairs(children) do
            local isOurDeck = (child.clusterData ~= nil) or (child == trackerControlBar)
            if child and not isOurDeck then
                local isTrueQuestBlock = (type(child.id) == "number")
                    and (child.parentBlock == nil)
                    and (child.HeaderText ~= nil or child.HeaderButton ~= nil or child.lines ~= nil)

                if not isTrueQuestBlock then
                    local poiQID = child.questID or (child.parentBlock and child.parentBlock.id)
                    if type(poiQID) == "number" then
                        poiByQuestID[poiQID] = child
                    end
                end
            end
        end

        -- Pass 2: Collect true Quest Blocks
        for _, child in ipairs(children) do
            local isOurDeck = (child.clusterData ~= nil) or (child == trackerControlBar)
            if child and not isOurDeck then
                local isTrueQuestBlock = (type(child.id) == "number")
                    and (child.parentBlock == nil)
                    and (child.HeaderText ~= nil or child.HeaderButton ~= nil or child.lines ~= nil)

                if isTrueQuestBlock then
                    local qID = child.id
                    local poiBtn = poiByQuestID[qID] or child.poiButton
                    local qData = questRewardMap[qID]

                    if qData then
                        local headerFS = child.HeaderText or (child.HeaderButton and child.HeaderButton.Text)
                        if headerFS and headerFS.GetFont and not nativeTitleFont then
                            nativeTitleFont, nativeTitleSize, nativeTitleFlags = headerFS:GetFont()
                        end
                        if not nativeLineFont and child.lines then
                            for _, line in pairs(child.lines) do
                                if line and line.Text and line.Text.GetFont then
                                    nativeLineFont, nativeLineSize, nativeLineFlags = line.Text:GetFont()
                                    break
                                end
                            end
                        end

                        -- If a filter is active with autoUntrack, hide non-matching blocks immediately (even if SuperTracked)
                        local filteredOut = (hasActiveFilter and autoUntrack and not DoesQuestMatchFilter(qID))
                        if filteredOut then
                            SetNativeTrackerBlockHidden(child, poiBtn, true)
                            child:ClearAllPoints()
                            child:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, 2000)
                        elseif child:IsShown() or child.qrfHiddenByStack then
                            table.insert(rawBlocks, {
                                frame = child,
                                poiBtn = poiBtn,
                                questID = qID,
                                qData = qData,
                            })
                        end
                    elseif child.qrfHiddenByStack then
                        SetNativeTrackerBlockHidden(child, poiBtn, false)
                    end
                end
            end
        end

        if #rawBlocks == 0 then return end

        local activeBar = nil
        if not controlBarPlaced then
            controlBarPlaced = true
            activeBar = EnsureTrackerControlBar(trackerModule)
        end

        local layoutItems = {}
        local seenClusters = {}

        -- A deck only ever holds quests that already have a native tracker block. Stacking is
        -- purely visual: switching it off must reveal exactly the same quests, never fewer.
        local trackedClusterViews = {}
        for _, blkEntry in ipairs(rawBlocks) do
            local cID = blkEntry.qData and blkEntry.qData.clusterID
            local src = cID and clusterGroupsMap[cID]
            if src then
                local view = trackedClusterViews[cID]
                if not view then
                    view = { id = src.id, index = src.index, zone = src.zone, isComplete = src.isComplete,
                             quests = {}, minDistance = CFQ.DIST_UNKNOWN }
                    trackedClusterViews[cID] = view
                end
                table.insert(view.quests, blkEntry.qData)
            end
        end
        for _, view in pairs(trackedClusterViews) do
            table.sort(view.quests, CompareQuestsForTracker)
            for _, q in ipairs(view.quests) do
                if (q.distance or CFQ.DIST_UNKNOWN) < view.minDistance then view.minDistance = q.distance end
            end
        end

        for _, blkEntry in ipairs(rawBlocks) do
            local qData = blkEntry.qData
            local blk = blkEntry.frame
            local poiBtn = blkEntry.poiBtn
            local cID = qData and qData.clusterID
            local cGroup = cID and trackedClusterViews[cID]

            if cGroup and #cGroup.quests >= 2 and IsQuestStackingEnabledFor(qData) then
                SetNativeTrackerBlockHidden(blk, poiBtn, true)
                blk:ClearAllPoints()
                blk:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, 2000)

                if not seenClusters[cID] then
                    seenClusters[cID] = true
                    local deck
                    if isAnimationTick then
                        for _, existingDeck in ipairs(trackerStackDeckPool) do
                            if existingDeck:IsShown() and existingDeck.clusterID == cID then
                                deck = existingDeck
                                break
                            end
                        end
                    end
                    if not deck then
                        deck = AcquireDeckForCluster(cID, contents)
                        PopulateTrackerStackDeck(deck, cGroup, false)
                        deck:Show()
                    end
                    table.insert(layoutItems, {
                        isDeck = true,
                        frame = deck,
                        poiBtn = nil,
                        qData = (deck.displayQuests and deck.displayQuests[1]) or cGroup.quests[1],
                        sortDist = cGroup.minDistance,   -- a stack sorts by its nearest member
                    })
                end
            else
                SetNativeTrackerBlockHidden(blk, poiBtn, false)

                local headerFS = blk.HeaderText or (blk.HeaderButton and blk.HeaderButton.Text)
                if headerFS and headerFS.SetText and qData then
                    local lvlTag = string.format("|c%s[%d]|r ", qData.levelHex or "FFFFFFFF", qData.level or 0)
                    local cleanTitle = qData.title or ""
                    if IsTrackerSortingOrClusteringActive() or GetActiveLevelFilterCount() > 0 then
                        headerFS:SetText(lvlTag .. cleanTitle)
                    else
                        headerFS:SetText(cleanTitle)
                    end
                end

                table.insert(layoutItems, {
                    isDeck = false,
                    frame = blk,
                    poiBtn = poiBtn,
                    qData = qData,
                    sortDist = qData and qData.distance,
                })
            end
        end

        if #layoutItems > 0 then
            if IsTrackerSortingOrClusteringActive() then
                table.sort(layoutItems, function(itemA, itemB)
                    return CompareQuestsForTrackerEx(itemA.qData, itemB.qData, itemA.sortDist, itemB.sortDist)
                end)
            else
                table.sort(layoutItems, function(itemA, itemB)
                    return (itemA.qData.logIndex or 0) < (itemB.qData.logIndex or 0)
                end)
            end

            -- Direct cumulative yCursor layout relative to the header / control bar so blocks NEVER collide!
            local anchorTopFrame = (activeBar and activeBar:IsShown() and activeBar)
                or (trackerModule.Header and trackerModule.Header:IsShown() and trackerModule.Header)
                or contents
            local yCursor = -6

            for _, item in ipairs(layoutItems) do
                local f = item.frame
                -- Blizzard can size a block by its LEFT/RIGHT anchors rather than an explicit width.
                -- Remember the resolved width before we drop those anchors, or a re-anchored block
                -- collapses to 0 px wide and its text disappears.
                local resolvedW = (not item.isDeck) and f:GetWidth() or 0
                if resolvedW and resolvedW > 40 then f.qrfWidth = resolvedW end
                f:ClearAllPoints()
                if item.isDeck then
                    if anchorTopFrame == activeBar then
                        f:SetPoint("TOPLEFT", activeBar, "BOTTOMLEFT", 0, yCursor)
                        f:SetPoint("TOPRIGHT", activeBar, "BOTTOMRIGHT", -4, yCursor)
                    else
                        f:SetPoint("TOPLEFT", anchorTopFrame, "BOTTOMLEFT", -26, yCursor)
                        f:SetWidth(242)
                    end
                else
                    if anchorTopFrame == activeBar then
                        f:SetPoint("TOPLEFT", activeBar, "BOTTOMLEFT", 26, yCursor)
                    else
                        f:SetPoint("TOPLEFT", anchorTopFrame, "BOTTOMLEFT", 0, yCursor)
                    end
                    if f.qrfWidth and (f:GetWidth() or 0) < 40 then f:SetWidth(f.qrfWidth) end
                    -- Ensure native POI button stays anchored beside its unstacked quest block
                    if item.poiBtn and item.poiBtn ~= f then
                        item.poiBtn:ClearAllPoints()
                        item.poiBtn:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 1)
                    end
                end

                local itemH = math.max(24, f:GetHeight() or 36)
                yCursor = yCursor - (itemH + 6)
            end
        end
    end

    if QuestObjectiveTracker then
        ProcessTrackerModule(QuestObjectiveTracker)
    end

    pcall(CFQ.PlaceDeckItemButtons)

    if not isAnimationTick and UpdateShoppingListUI then
        UpdateShoppingListUI()
    end
end

-- Guarded wrapper: an error in a layout pass is reported and the tracker keeps working
-- (stacked blocks are never left hidden).
LayoutObjectiveTrackerWithStacks = function(isAnimationTick)
    if isReorderingTrackerUI or InCombatLockdown() then return end
    isReorderingTrackerUI = true
    local ok, err = xpcall(function() LayoutTrackerImpl(isAnimationTick) end, CFQ.ErrorWithStack)
    isReorderingTrackerUI = false
    if not ok then CFQ.ReportError(err) end
end

local function SyncObjectiveTrackerImpl()
    local hasFilter = (GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0)
    local targetWatchList = {}

    if hasFilter and autoUntrack then
        if not savedWatchedQuests then
            savedWatchedQuests = {}
            local numEntries = C_QuestLog.GetNumQuestLogEntries()
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID and IsQuestWatched(info.questID) then
                    savedWatchedQuests[info.questID] = true
                end
            end
        end

        for qID, qData in pairs(questRewardMap) do
            if not qData.isFromMap and DoesQuestMatchFilter(qID) then
                table.insert(targetWatchList, qData)
            end
        end
    else
        if savedWatchedQuests then
            for qID, qData in pairs(questRewardMap) do
                if not qData.isFromMap and savedWatchedQuests[qID] then
                    table.insert(targetWatchList, qData)
                end
            end
            savedWatchedQuests = nil
        else
            for qID, qData in pairs(questRewardMap) do
                if not qData.isFromMap and IsQuestWatched(qID) then
                    table.insert(targetWatchList, qData)
                end
            end
        end
    end

    if IsWatchReorderActive() then
        table.sort(targetWatchList, CompareQuestsForWatchList)
    else
        table.sort(targetWatchList, function(a, b)
            return (a.logIndex or 0) < (b.logIndex or 0)
        end)
    end

    -- If a filter is active and the currently SuperTracked quest does NOT match the filter,
    -- switch SuperTracking to the first matching quest so Blizzard doesn't force-show the unmatched quest!
    if hasFilter and autoUntrack and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
        local curST = C_SuperTrack.GetSuperTrackedQuestID()
        if curST and curST > 0 and not DoesQuestMatchFilter(curST) then
            local nextST = (targetWatchList[1] and targetWatchList[1].questID) or 0
            pcall(C_SuperTrack.SetSuperTrackedQuestID, nextST)
        end
    end

    local sigParts = {}
    local compParts = {}
    local targetSet = {}
    for _, qData in ipairs(targetWatchList) do
        local compFlag = qData.isComplete and "1" or "0"
        local clustKey = qData.clusterID or "NONE"
        table.insert(sigParts, string.format("%d:%s:%s", qData.questID, compFlag, clustKey))
        table.insert(compParts, string.format("%d:%s", qData.questID, compFlag))
        targetSet[qData.questID] = true
    end
    local newSignature = table.concat(sigParts, ",")
    local newCompSig = table.concat(compParts, ",")
    local completionJustChanged = (lastCompletionSignature ~= "" and lastCompletionSignature ~= newCompSig)
    lastCompletionSignature = newCompSig

    if newSignature ~= lastWatchOrderSignature then
        lastWatchOrderSignature = newSignature

        if IsWatchReorderActive() and C_QuestLog.RemoveQuestWatch and C_QuestLog.AddQuestWatch and not InCombatLockdown() then
            local numEntries = C_QuestLog.GetNumQuestLogEntries()
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID and IsQuestWatched(info.questID) then
                    pcall(C_QuestLog.RemoveQuestWatch, info.questID)
                end
            end
            for _, qData in ipairs(targetWatchList) do
                pcall(C_QuestLog.AddQuestWatch, qData.questID)
            end
        else
            local numEntries = C_QuestLog.GetNumQuestLogEntries()
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and not info.isHidden and info.questID then
                    local qID = info.questID
                    local shouldWatch = targetSet[qID] == true
                    local currentlyWatched = IsQuestWatched(qID)
                    if shouldWatch and not currentlyWatched and C_QuestLog.AddQuestWatch then
                        pcall(C_QuestLog.AddQuestWatch, qID)
                    elseif not shouldWatch and currentlyWatched and C_QuestLog.RemoveQuestWatch then
                        pcall(C_QuestLog.RemoveQuestWatch, qID)
                    end
                end
            end
        end
    end

    LayoutObjectiveTrackerWithStacks()

    if completionJustChanged and C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if not InCombatLockdown() then
                LayoutObjectiveTrackerWithStacks()
            end
        end)
    end

    SaveState()
end

SyncObjectiveTracker = function()
    if isSyncingTracker or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
    isSyncingTracker = true
    local ok, err = xpcall(SyncObjectiveTrackerImpl, CFQ.ErrorWithStack)
    isSyncingTracker = false
    if not ok then CFQ.ReportError(err) end
end

-- ============================================================================
-- WORLD MAP PIN TOOLTIP ENHANCER (SUBSCRIPT "lvl" + CURRENCY/REWARD LINE)
-- ============================================================================
local tooltipMeasureFS = nil

local function EnhanceMapTooltip(tooltip)
    if not tooltip or not tooltip:IsShown() then return end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not WorldMapFrame:IsMouseOver() then return end

    local namePrefix = tooltip:GetName() or "GameTooltip"
    local line1 = _G[namePrefix .. "TextLeft1"]
    if not line1 or not line1.GetText then return end

    local rawLine1 = line1:GetText()
    if not rawLine1 or rawLine1 == "" then return end

    if tooltip.qrfProcessedHeader == rawLine1 then return end

    local cleanSearchTitle = StripLeadingLevelTag(rawLine1)
    local qData = cleanSearchTitle ~= "" and questTitleLookup[string.lower(cleanSearchTitle)]

    if not qData then
        local owner = tooltip:GetOwner()
        if owner then
            local qID = owner.questID or owner.questId or (owner.GetQuestID and owner:GetQuestID()) or (owner.data and owner.data.Id)
            if type(qID) == "number" and questRewardMap[qID] then
                qData = questRewardMap[qID]
            end
        end
    end

    if not qData then
        if tooltip.qrfSubLvl then tooltip.qrfSubLvl:Hide() end
        return
    end

    local fontPath, fontSize, fontFlags = line1:GetFont()
    fontPath = fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontSize = fontSize or 14

    if not tooltipMeasureFS then
        tooltipMeasureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tooltipMeasureFS:Hide()
    end

    local lvlNumStr = tostring(qData.level or 0)
    tooltipMeasureFS:SetFont(fontPath, fontSize, fontFlags or "")
    tooltipMeasureFS:SetText(lvlNumStr)
    local numWidth = tooltipMeasureFS:GetStringWidth() or 10

    local newHeader = string.format("|c%s%s|r     |cFFFFD100%s|r", qData.levelHex or "FFFFFFFF", lvlNumStr, qData.title or cleanSearchTitle)
    line1:SetText(newHeader)
    tooltip.qrfProcessedHeader = newHeader

    if not tooltip.qrfSubLvl then
        tooltip.qrfSubLvl = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    tooltip.qrfSubLvl:SetFont(fontPath, math.max(8, math.floor(fontSize * 0.62)), "OUTLINE")
    tooltip.qrfSubLvl:ClearAllPoints()
    tooltip.qrfSubLvl:SetPoint("BOTTOMLEFT", line1, "TOPLEFT", numWidth + 1.5, -(fontSize + 1))
    tooltip.qrfSubLvl:SetText("|cFFCCCCCC" .. "lvl|r")
    tooltip.qrfSubLvl:Show()

    local rewardParts = {}
    if qData.order and #qData.order > 0 then
        for _, rID in ipairs(qData.order) do
            local rStr = (qData.tooltipRewards and qData.tooltipRewards[rID]) or qData.badges[rID]
            if rStr then
                table.insert(rewardParts, rStr)
            end
        end
    else
        local copper = GetQuestMoneyCopper(qData.questID)
        if copper > 0 then
            table.insert(rewardParts, FormatMoneyWithIcons(copper) or FormatMoneyBadge(copper))
        end
    end

    if #rewardParts > 0 then
        tooltip:AddLine("|cFFFFD100Reward:|r " .. table.concat(rewardParts, "   "), 1, 1, 1, false)
        tooltip:Show()
    end
end

local function HookAllMapTooltips()
    local function AttachTooltipHooks(tip)
        if not tip or tip.qrfMapHooked then return end
        tip.qrfMapHooked = true

        tip:HookScript("OnShow", function(self)
            self.qrfProcessedHeader = nil
            EnhanceMapTooltip(self)
        end)
        tip:HookScript("OnUpdate", function(self)
            EnhanceMapTooltip(self)
        end)
        tip:HookScript("OnHide", function(self)
            self.qrfProcessedHeader = nil
            if self.qrfSubLvl then self.qrfSubLvl:Hide() end
        end)
    end

    AttachTooltipHooks(GameTooltip)
    if WorldMapTooltip then
        AttachTooltipHooks(WorldMapTooltip)
    end
    if Questie_BaseTooltip then
        AttachTooltipHooks(Questie_BaseTooltip)
    end
end

local function GetMapPinIconString(questID)
    local qData = questRewardMap[questID]
    if not qData then return "" end
    local rCount = GetActiveRewardFilterCount()
    if rCount > 0 then
        for _, rID in ipairs(qData.order) do
            if selectedFilters[rID] and qData.mapIcons and qData.mapIcons[rID] then
                return " " .. qData.mapIcons[rID]
            end
        end
    elseif #qData.order > 0 then
        local firstID = qData.order[1]
        if qData.mapIcons and qData.mapIcons[firstID] then
            return " " .. qData.mapIcons[firstID]
        end
    end
    return ""
end

local function UpdateWorldMapPins()
    if not WorldMapFrame or not WorldMapFrame:IsShown() or not WorldMapFrame.pinPools then return end

    local anyFilterActive = (GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0)
    local uiMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    for _, pool in pairs(WorldMapFrame.pinPools) do
        if pool and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do
                local qID = pin.questID or pin.questId or (pin.GetQuestID and pin:GetQuestID())
                -- Quest-area highlights ("blobs") also carry a questID, but they are the shaded
                -- collection zones, not pins: never dim them or hang a badge on them.
                local isAreaHighlight = type(pin.DrawBlob) == "function"
                    or (pin.GetObjectType and pin:GetObjectType() == "QuestPOIFrame")
                if isAreaHighlight then qID = nil end   -- the branch below restores any old badge / dim
                if qID and type(qID) == "number" then
                    if uiMapID and pin.normalizedX and pin.normalizedY then
                        cachedQuestCoords[qID] = { mapID = uiMapID, x = pin.normalizedX, y = pin.normalizedY }
                    end

                    local qData = questRewardMap[qID]
                    if qData then
                        local matches = DoesQuestMatchFilter(qID)

                        if not pin.qrfMapBadge then
                            local pill = CreateFrame("Frame", nil, pin)
                            pill:SetSize(64, 18)
                            pill:SetPoint("TOP", pin, "BOTTOM", 0, 1)
                            pill:SetFrameLevel(pin:GetFrameLevel() + 5)

                            pill.lvlNum = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            pill.lvlNum:SetFont(fontPath, 11, "OUTLINE")

                            pill.lvlSub = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            pill.lvlSub:SetFont(fontPath, 8, "OUTLINE")
                            pill.lvlSub:SetPoint("BOTTOMLEFT", pill.lvlNum, "BOTTOMRIGHT", 0.5, -1)
                            pill.lvlSub:SetText("|cFFBBBBBB" .. "lvl|r")

                            pill.iconText = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            pill.iconText:SetFont(fontPath, 11, "OUTLINE")
                            pill.iconText:SetPoint("LEFT", pill.lvlSub, "RIGHT", 2, 1)

                            pin.qrfMapBadge = pill
                        end

                        if pin.qrfMapBadge.border then pin.qrfMapBadge.border:Hide() end
                        if pin.qrfMapBadge.bg then pin.qrfMapBadge.bg:Hide() end
                        if pin.qrfMapBadge.text then pin.qrfMapBadge.text:Hide() end

                        if showMapBadges then
                            local iconStr = GetMapPinIconString(qID)
                            pin.qrfMapBadge.lvlNum:SetText(string.format("|c%s%d|r", qData.levelHex or "FFFFFFFF", qData.level or 0))
                            pin.qrfMapBadge.iconText:SetText(iconStr)

                            local totalW = (pin.qrfMapBadge.lvlNum:GetStringWidth() or 8)
                                + (pin.qrfMapBadge.lvlSub:GetStringWidth() or 10)
                                + (pin.qrfMapBadge.iconText:GetStringWidth() or 0)
                            pin.qrfMapBadge.lvlNum:ClearAllPoints()
                            pin.qrfMapBadge.lvlNum:SetPoint("LEFT", pin.qrfMapBadge, "CENTER", -(totalW * 0.5), 0)
                            pin.qrfMapBadge:Show()
                        else
                            pin.qrfMapBadge:Hide()
                        end

                        if anyFilterActive and filterMapPins then
                            if matches then
                                pin:SetAlpha(1.0)
                            else
                                pin:SetAlpha(mapFilterHideMode and 0.0 or 0.18)
                            end
                        else
                            pin:SetAlpha(1.0)
                        end
                    end
                elseif pin.qrfMapBadge then
                    pin.qrfMapBadge:Hide()
                    pin:SetAlpha(1.0)
                end
            end
        end
    end
end

-- ============================================================================
-- BUTTON LABELS, FILTERED QUEST LIST & QUEST LOG REWARD LINE BELOW OBJECTIVES
-- ============================================================================
-- Level-only arrow (for level-specific labels)
local function GetShortSortSuffix()
    if levelSortMode == "ASC" then return " " .. ICON_ARROW_UP
    elseif levelSortMode == "DESC" then return " " .. ICON_ARROW_DOWN
    end
    return ""
end

-- "lvl↑ dist↓" — primary sort first; "" when no sort is active
function CFQ.GetSortSummary()
    local parts = {}
    local function Piece(key)
        local mode = (key == "LVL") and levelSortMode or distSortMode
        if mode ~= "NONE" then
            table.insert(parts, ((key == "LVL") and "lvl" or "dist") .. (mode == "ASC" and ICON_ARROW_UP or ICON_ARROW_DOWN))
        end
    end
    Piece(primarySortKey)
    Piece(primarySortKey == "LVL" and "DIST" or "LVL")
    return table.concat(parts, " ")
end

local function UpdateAllButtonLabels()
    local rCount = GetActiveRewardFilterCount()
    local lCount = GetActiveLevelFilterCount()
    local totalActive = rCount + lCount
    local hasSnapshot = (savedWatchedQuests ~= nil)
    local sortTag = GetShortSortSuffix()
    local sortSummary = CFQ.GetSortSummary()

    if questLogBar then
        if rCount == 0 then
            questLogBar.rewardBtn:SetText(CONFIG.REWARD_BTN_ALL)
        elseif rCount == 1 then
            local rName = "1 Reward"
            for id, sel in pairs(selectedFilters) do
                if sel and knownRewardMeta[id] then
                    rName = knownRewardMeta[id].name
                    break
                end
            end
            if string.len(rName) > 12 then rName = string.sub(rName, 1, 10) .. ".." end
            questLogBar.rewardBtn:SetText("R: " .. rName)
        else
            questLogBar.rewardBtn:SetText("Rewards (" .. rCount .. ")")
        end

        if lCount == 0 then
            questLogBar.levelBtn:SetText(CONFIG.LEVEL_BTN_ALL .. sortTag)
        elseif lCount == 1 then
            local lName = "1 Level"
            for id, sel in pairs(selectedLevelFilters) do
                if sel and knownLevelMeta[id] then
                    lName = knownLevelMeta[id].name
                    break
                end
            end
            lName = string.gsub(lName, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if string.len(lName) > 11 then lName = string.sub(lName, 1, 9) .. ".." end
            questLogBar.levelBtn:SetText(lName .. sortTag)
        else
            questLogBar.levelBtn:SetText("Levels (" .. lCount .. ")" .. sortTag)
        end

        if totalActive > 0 or IsAnySortActive() or hasSnapshot then
            questLogBar.resetBtn:Enable()
        else
            questLogBar.resetBtn:Disable()
        end
    end

    if trackerFilterBtn then
        if totalActive == 0 then
            if sortSummary ~= "" then
                trackerFilterBtn:SetText(sortSummary)
            else
                trackerFilterBtn:SetText(CONFIG.TRACKER_BTN_ALL)
            end
        else
            trackerFilterBtn:SetText("Filter (" .. totalActive .. ")" .. ((sortSummary ~= "") and (" " .. sortSummary) or ""))
        end
    end

    if CFQ.RefreshSortButtons then CFQ.RefreshSortButtons() end

    UpdateTrackerControlBarVisuals()
end

local function GetAnchorDepthToQuestButton(frame, button)
    local cur = frame
    for depth = 1, 12 do
        if not cur or not cur.GetPoint or cur == button.qrfBadge then
            return nil
        end
        local _, relTo = cur:GetPoint(1)
        if not relTo then
            return nil
        end
        if relTo == button or relTo == button.Text or (relTo.GetParent and relTo:GetParent() == button) then
            return depth
        end
        cur = relTo
    end
    return nil
end

local function FindLowestQuestAnchor(button)
    local bestAnchor = button.Text or button
    local bestDepth = 0
    local bestBottom = bestAnchor and bestAnchor.GetBottom and bestAnchor:GetBottom() or nil
    local textLeftX = 28

    if button.Text and button.Text.GetLeft and button.Text:GetLeft() and button:GetLeft() then
        textLeftX = math.max(24, math.floor(button.Text:GetLeft() - button:GetLeft()))
    end

    local function CheckCandidate(candidate)
        if not candidate or candidate == button or candidate == button.qrfBadge or candidate == button.Checkbox or candidate == button.TagTexture then
            return
        end
        if not candidate.IsShown or not candidate:IsShown() then
            return
        end
        local depth = GetAnchorDepthToQuestButton(candidate, button)
        if depth then
            local candBottom = candidate.GetBottom and candidate:GetBottom() or nil
            if candBottom and bestBottom then
                if candBottom < (bestBottom - 1) or (math.abs(candBottom - bestBottom) <= 1 and depth > bestDepth) then
                    bestBottom = candBottom
                    bestDepth = depth
                    bestAnchor = candidate
                end
            elseif depth >= bestDepth then
                bestDepth = depth
                bestAnchor = candidate
            end
        end
    end

    if QuestScrollFrame and QuestScrollFrame.objectiveFramePool and QuestScrollFrame.objectiveFramePool.EnumerateActive then
        for objFrame in QuestScrollFrame.objectiveFramePool:EnumerateActive() do
            CheckCandidate(objFrame)
        end
    end

    if QuestScrollFrame and QuestScrollFrame.Contents and QuestScrollFrame.Contents.GetChildren then
        local contentsChildren = { QuestScrollFrame.Contents:GetChildren() }
        for _, child in ipairs(contentsChildren) do
            CheckCandidate(child)
        end
    end

    if button.GetChildren then
        local btnChildren = { button:GetChildren() }
        for _, child in ipairs(btnChildren) do
            CheckCandidate(child)
        end
    end

    return bestAnchor, bestDepth, textLeftX
end

local function RenderCustomFilteredList()
    if not QuestScrollFrame or not QuestScrollFrame.qrfCustomList then return end
    local listFrame = QuestScrollFrame.qrfCustomList

    wipe(matchingQuestsList)
    for questID, qData in pairs(questRewardMap) do
        if DoesQuestMatchFilter(questID) then
            table.insert(matchingQuestsList, qData)
        end
    end
    table.sort(matchingQuestsList, CompareQuestsForQuestLog)

    local totalRows = #matchingQuestsList
    local rCount = GetActiveRewardFilterCount()
    local lCount = GetActiveLevelFilterCount()

    local sortDesc = ""
    local summary = CFQ.GetSortSummary()
    if summary ~= "" then sortDesc = " • " .. summary end

    if rCount == 0 and lCount == 0 then
        listFrame.headerText:SetText(string.format("|cFFFFD100Quests (%d)%s|r", totalRows, sortDesc))
    else
        listFrame.headerText:SetText(string.format("|cFFFFD100Filtered Quests (%d)%s|r", totalRows, sortDesc))
    end

    if customScrollOffset > math.max(0, totalRows - MAX_CUSTOM_ROWS) then
        customScrollOffset = math.max(0, totalRows - MAX_CUSTOM_ROWS)
    end

    for i = 1, MAX_CUSTOM_ROWS do
        local row = customListRowPool[i]
        local qData = matchingQuestsList[i + customScrollOffset]

        if qData then
            local badgeStr = GetLeftAlignedLogRewardString(qData, 3)
            local watchedIcon = IsQuestWatched(qData.questID) and "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:0|t " or ""
            local mapTag = qData.isFromMap and "|cFF00CCFF[Map]|r " or ""
            local lvlPrefix = string.format("|c%s[%d]|r ", qData.levelHex or "FFFFFFFF", qData.level or 0)
            local groupTag = (qData.suggestedGroup and qData.suggestedGroup > 1) and string.format(" |cFFFF8040(%dP)|r", qData.suggestedGroup) or ""

            row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.0)
            row.titleText:SetText(watchedIcon .. mapTag .. lvlPrefix .. "|cFFFFD100" .. qData.title .. "|r" .. groupTag)
            row.zoneText:SetText("|cFFCCCCCC" .. (qData.objectiveText or qData.header or "") .. "|r")
            row.badgeText:SetText(badgeStr)

            row:SetScript("OnClick", function()
                if IsShiftKeyDown() and not qData.isFromMap then
                    if IsQuestWatched(qData.questID) then
                        if C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, qData.questID) end
                    else
                        if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, qData.questID) end
                    end
                    RenderCustomFilteredList()
                    LayoutObjectiveTrackerWithStacks()
                else
                    ActivateQuestTarget(qData.questID)
                    if QuestMapFrame_OpenToQuestDetails and not qData.isFromMap then
                        QuestMapFrame_OpenToQuestDetails(qData.questID)
                    end
                    RenderCustomFilteredList()
                    LayoutObjectiveTrackerWithStacks()
                end
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    if totalRows > MAX_CUSTOM_ROWS then
        listFrame.scrollHint:SetText(string.format(
            "Showing %d-%d of %d (Scroll wheel)",
            customScrollOffset + 1,
            math.min(totalRows, customScrollOffset + MAX_CUSTOM_ROWS),
            totalRows
        ))
        listFrame.scrollHint:Show()
    else
        listFrame.scrollHint:Hide()
    end
end

local isUpdatingQuestLogLayout = false

local function UpdateQuestLogUIImpl(fromBlizzardQuestLogUpdate)
    ScanQuestLogRewards()
    UpdateAllButtonLabels()
    UpdateWorldMapPins()
    LayoutObjectiveTrackerWithStacks()

    if QuestScrollFrame then
        local customList = QuestScrollFrame.qrfCustomList
        if IsQuestLogOverrideActive() then
            if customList then
                RenderCustomFilteredList()
                customList:Show()
            end
        else
            if customList then
                customList:Hide()
            end

            if QuestScrollFrame.titleFramePool then
                local anyHeightAdjusted = false
                for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
                    if button then
                        if not button.qrfBadge then
                            button.qrfBadge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            button.qrfBadge:SetJustifyH("LEFT")
                            button.qrfBadge:SetWordWrap(false)
                        end

                        local currentH = button:GetHeight() or 20
                        if fromBlizzardQuestLogUpdate or not button.qrfBaseHeight or math.abs(currentH - (button.qrfPaddedHeight or -1)) > 0.5 then
                            button.qrfBaseHeight = currentH
                        end

                        local questID = button.questID or (button.info and button.info.questID)
                        local qData = questID and questRewardMap[questID]

                        if questID and not (button.info and button.info.isHeader) and qData then
                            local rewardLine = GetLeftAlignedLogRewardString(qData, 3)
                            if rewardLine and rewardLine ~= "" then
                                local lowestAnchor, anchorDepth, leftX = FindLowestQuestAnchor(button)
                                local baseH = button.qrfBaseHeight or 20

                                button.qrfBadge:ClearAllPoints()
                                if anchorDepth > 0 and lowestAnchor then
                                    button.qrfBadge:SetPoint("TOPLEFT", lowestAnchor, "BOTTOMLEFT", 0, -4)
                                    button.qrfBadge:SetPoint("RIGHT", button, "RIGHT", -28, 0)
                                elseif baseH > 26 then
                                    button.qrfBadge:SetPoint("TOPLEFT", button, "TOPLEFT", leftX, -(baseH - 1))
                                    button.qrfBadge:SetPoint("RIGHT", button, "RIGHT", -28, 0)
                                else
                                    button.qrfBadge:SetPoint("TOPLEFT", button.Text or button, "BOTTOMLEFT", 0, -4)
                                    button.qrfBadge:SetPoint("RIGHT", button, "RIGHT", -28, 0)
                                end

                                button.qrfBadge:SetText(rewardLine)
                                button.qrfBadge:Show()

                                local paddedH = baseH + 16
                                button.qrfPaddedHeight = paddedH
                                button:SetHeight(paddedH)
                                anyHeightAdjusted = true
                            else
                                button.qrfBadge:SetText("")
                                button.qrfBadge:Hide()
                                if button.qrfBaseHeight then
                                    button:SetHeight(button.qrfBaseHeight)
                                end
                            end
                        else
                            button.qrfBadge:SetText("")
                            button.qrfBadge:Hide()
                        end
                        button:SetAlpha(1.0)
                    end
                end

                if anyHeightAdjusted and QuestScrollFrame.Contents and QuestScrollFrame.Contents.Layout then
                    pcall(QuestScrollFrame.Contents.Layout, QuestScrollFrame.Contents)
                end
            end
        end
    end

    if UpdateShoppingListUI then
        UpdateShoppingListUI()
    end
end

local function UpdateQuestLogUI(fromBlizzardQuestLogUpdate)
    if isUpdatingQuestLogLayout then return end
    isUpdatingQuestLogLayout = true
    local ok, err = xpcall(function() UpdateQuestLogUIImpl(fromBlizzardQuestLogUpdate) end, CFQ.ErrorWithStack)
    isUpdatingQuestLogLayout = false
    if not ok then CFQ.ReportError(err) end
end

ApplyFilterChanges = function()
    customScrollOffset = 0
    lastWatchOrderSignature = ""
    ScanQuestLogRewards()
    SyncObjectiveTracker()
    UpdateQuestLogUI(false)
    SaveState()
end

-- ============================================================================
-- DROPDOWN MENU BUILDER
-- ============================================================================
local function AreAllCategoryItemsChecked(categoryGroup, isLevelTab)
    local sourceList = isLevelTab and availableLevelFilters or availableRewards
    local targetMap = isLevelTab and selectedLevelFilters or selectedFilters
    local foundAny = false
    for _, item in ipairs(sourceList) do
        if item.categoryGroup == categoryGroup then
            foundAny = true
            if not targetMap[item.id] then
                return false
            end
        end
    end
    return foundAny
end

local function ToggleCategorySelection(categoryGroup, isLevelTab)
    local sourceList = isLevelTab and availableLevelFilters or availableRewards
    local targetMap = isLevelTab and selectedLevelFilters or selectedFilters
    local allChecked = AreAllCategoryItemsChecked(categoryGroup, isLevelTab)
    for _, item in ipairs(sourceList) do
        if item.categoryGroup == categoryGroup then
            if allChecked then
                targetMap[item.id] = nil
            else
                targetMap[item.id] = true
            end
        end
    end
    ApplyFilterChanges()
end

local function RebuildDropdownMenu(menuFrame, searchJustChanged)
    if not menuFrame then return end
    ScanQuestLogRewards()
    wipe(dropdownDisplayList)

    local isLevelTab = (activeMenuTab == "LEVELS")
    local sourceList = isLevelTab and availableLevelFilters or availableRewards
    local targetMap = isLevelTab and selectedLevelFilters or selectedFilters
    local catNameMap = isLevelTab and LEVEL_CATEGORY_NAMES or CATEGORY_NAMES

    menuFrame.headerLabel:SetText(isLevelTab and CONFIG.HEADER_LEVELS or CONFIG.HEADER_REWARDS)

    if menuFrame.tabRewardsBtn and menuFrame.tabLevelsBtn then
        local rCount = GetActiveRewardFilterCount()
        local lCount = GetActiveLevelFilterCount()
        local rLabel = rCount > 0 and ("Rewards (" .. rCount .. ")") or "Rewards"
        local lLabel = lCount > 0 and ("Quest Levels (" .. lCount .. ")") or "Quest Levels"
        lLabel = lLabel .. GetShortSortSuffix()

        menuFrame.tabRewardsBtn:SetText(isLevelTab and ("|cFFAAAAAA" .. rLabel .. "|r") or ("|cFFFFD100" .. rLabel .. "|r"))
        menuFrame.tabLevelsBtn:SetText(isLevelTab and ("|cFFFFD100" .. lLabel .. "|r") or ("|cFFAAAAAA" .. lLabel .. "|r"))
    end

    -- Sort bar ([lvl] [dist] cycle buttons) is shown on both tabs: distance isn't level-specific
    local listStartY = -102
    menuFrame.sortBar:Show()
    if CFQ.RefreshSortButtons then CFQ.RefreshSortButtons() end

    local query = string.lower(strtrim(dropdownSearchText or ""))
    local lastCategory = nil
    local maxWidth = 285
    local categoryCounts = {}

    for _, entry in ipairs(sourceList) do
        local plainName = string.gsub(entry.name or "", "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if menuFrame.measureLabel then
            menuFrame.measureLabel:SetText(plainName .. " (" .. entry.questCount .. ")")
            local w = menuFrame.measureLabel:GetStringWidth() + 80
            if w > maxWidth then maxWidth = w end
        end

        local matchTarget = entry.rawName or string.lower(plainName)
        if query == "" or string.find(matchTarget, query, 1, true) then
            local cat = entry.categoryGroup
            categoryCounts[cat] = (categoryCounts[cat] or 0) + 1
            if query ~= "" and searchJustChanged and collapsedCategories[cat] then
                collapsedCategories[cat] = false
            end
        end
    end

    for _, entry in ipairs(sourceList) do
        local plainName = string.gsub(entry.name or "", "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local matchTarget = entry.rawName or string.lower(plainName)
        if query == "" or string.find(matchTarget, query, 1, true) then
            local cat = entry.categoryGroup
            if showCategories and cat ~= lastCategory then
                lastCategory = cat
                table.insert(dropdownDisplayList, {
                    isHeader = true,
                    categoryGroup = cat,
                    title = catNameMap[cat] or "Filters",
                    itemCount = categoryCounts[cat] or 0,
                })
            end

            if not showCategories or not collapsedCategories[cat] then
                table.insert(dropdownDisplayList, {
                    isHeader = false,
                    item = entry,
                })
            end
        end
    end

    if menuFrame.groupToggleBtn then
        menuFrame.groupToggleBtn:SetText(showCategories and "Group: ON" or "Group: OFF")
    end

    for _, row in ipairs(dropdownRowPool) do
        row:Hide()
    end

    local rowHeight = 21
    local yOffset = listStartY
    local totalEntries = #dropdownDisplayList

    local maxScroll = math.max(0, totalEntries - MAX_DROPDOWN_ROWS)
    if dropdownScrollOffset > maxScroll then
        dropdownScrollOffset = maxScroll
    end

    if totalEntries == 0 then
        local emptyRow = dropdownRowPool[1]
        emptyRow:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset)
        emptyRow:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, yOffset)
        emptyRow.check:Hide()
        emptyRow.collapseText:SetText("")
        emptyRow.label:SetPoint("LEFT", emptyRow, "LEFT", 8, 0)
        emptyRow.label:SetText(isLevelTab and "|cFF888888No matching quest levels|r" or "|cFF888888No matching quest rewards|r")
        emptyRow:SetScript("OnClick", nil)
        emptyRow:Show()
        yOffset = yOffset - rowHeight
    else
        local visibleCount = math.min(totalEntries, MAX_DROPDOWN_ROWS)
        for i = 1, visibleCount do
            local row = dropdownRowPool[i]
            local entry = dropdownDisplayList[i + dropdownScrollOffset]

            row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset)
            row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, yOffset)

            if entry.isHeader then
                local cat = entry.categoryGroup
                local isCollapsed = collapsedCategories[cat] == true
                row.bg:SetColorTexture(0.20, 0.18, 0.10, 0.70)
                row.check:Show()
                row.check:SetChecked(AreAllCategoryItemsChecked(cat, isLevelTab))
                row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
                row.label:SetText("|cFFFFD100" .. entry.title .. "|r |cFFAAAAAA(" .. entry.itemCount .. ")|r")
                row.collapseText:SetText(isCollapsed and "|cFFFFD100[+]|r" or "|cFFFFD100[-]|r")

                row:SetScript("OnClick", function(self, button)
                    local cursorX = GetCursorPosition() / self:GetEffectiveScale()
                    local leftEdge = self:GetLeft() or 0
                    if (cursorX - leftEdge) <= 28 or button == "RightButton" then
                        ToggleCategorySelection(cat, isLevelTab)
                    else
                        collapsedCategories[cat] = not isCollapsed
                        SaveState()
                    end
                    RebuildDropdownMenu(menuFrame, false)
                end)
            else
                local item = entry.item
                row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.0)
                row.check:Show()
                row.check:SetChecked(targetMap[item.id] == true)
                row.collapseText:SetText("")
                row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)

                local iconStr = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
                row.label:SetText(iconStr .. item.name .. " |cFF888888(" .. item.questCount .. ")|r")

                row:SetScript("OnClick", function()
                    if targetMap[item.id] then
                        targetMap[item.id] = nil
                    else
                        targetMap[item.id] = true
                    end
                    ApplyFilterChanges()
                    RebuildDropdownMenu(menuFrame, false)
                end)
            end

            row:Show()
            yOffset = yOffset - rowHeight
        end
    end

    if totalEntries > MAX_DROPDOWN_ROWS then
        menuFrame.scrollHint:SetPoint("TOP", menuFrame, "TOP", 0, yOffset - 2)
        menuFrame.scrollHint:SetText(string.format(
            "|cFF888888Showing %d-%d of %d (Scroll wheel)|r",
            dropdownScrollOffset + 1,
            math.min(totalEntries, dropdownScrollOffset + MAX_DROPDOWN_ROWS),
            totalEntries
        ))
        menuFrame.scrollHint:Show()
        yOffset = yOffset - 16
    else
        menuFrame.scrollHint:Hide()
    end

    menuFrame.footerDivider:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset - 4)
    menuFrame.footerDivider:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, yOffset - 4)

    menuFrame.untrackRow:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset - 8)
    menuFrame.untrackRow:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -65, yOffset - 8)
    menuFrame.untrackRow.check:SetChecked(autoUntrack)

    menuFrame.mapFilterRow:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset - 26)
    menuFrame.mapFilterRow:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -65, yOffset - 26)
    menuFrame.mapFilterRow.check:SetChecked(filterMapPins)
    menuFrame.mapFilterRow.label:SetText(string.format(
        "|cFFCCCCCCFilter zone map pins|r |cFFFFD100[%s]|r",
        mapFilterHideMode and "Hide" or "Dim"
    ))

    menuFrame.mapBadgeRow:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset - 44)
    menuFrame.mapBadgeRow:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -65, yOffset - 44)
    menuFrame.mapBadgeRow.check:SetChecked(showMapBadges)

    menuFrame.optionsRow:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, yOffset - 62)
    menuFrame.optionsRow:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -65, yOffset - 62)

    menuFrame.doneBtn:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -8, 8)

    local finalWidth = math.min(math.max(maxWidth, 285), 340)
    local finalHeight = math.abs(yOffset) + 90
    menuFrame:SetSize(finalWidth, finalHeight)
end

-- ============================================================================
-- SHARED DROPDOWN MENU FRAME CREATION
-- ============================================================================
local function ResetAllFilters()
    wipe(selectedFilters)
    wipe(selectedLevelFilters)
    levelSortMode = "NONE"
    distSortMode = "NONE"
    primarySortKey = "LVL"
    dropdownSearchText = ""
    if sharedMenuFrame and sharedMenuFrame.searchBox then
        sharedMenuFrame.searchBox:SetText("")
    end
    ApplyFilterChanges()
    if sharedMenuFrame and sharedMenuFrame:IsShown() then
        RebuildDropdownMenu(sharedMenuFrame, false)
    end
end
CFQ.ResetAllFilters = ResetAllFilters

-- ----------------------------------------------------------------------------
-- SINGLE-BUTTON CYCLING SORTS:  [lvl]  ->  [lvl ↑]  ->  [lvl ↓]  ->  [lvl]   (same for [dist])
-- Off = no arrow, no highlight. The sort switched on most recently is the primary one.
-- ----------------------------------------------------------------------------
function CFQ.GetSortMode(key)
    return (key == "LVL") and levelSortMode or distSortMode
end

function CFQ.CycleSortMode(key)
    local cur = CFQ.GetSortMode(key)
    local nxt = (cur == "NONE" and "ASC") or (cur == "ASC" and "DESC") or "NONE"
    if key == "LVL" then levelSortMode = nxt else distSortMode = nxt end

    local other = (key == "LVL") and "DIST" or "LVL"
    if cur == "NONE" then
        primarySortKey = key
    elseif nxt == "NONE" and primarySortKey == key then
        primarySortKey = other
    end
    if key == "DIST" and nxt ~= "NONE" then
        CFQ.UpdateQuestDistances()
    end

    ApplyFilterChanges()
    if sharedMenuFrame and sharedMenuFrame:IsShown() then
        RebuildDropdownMenu(sharedMenuFrame, false)
    end
    CFQ.RefreshSortButtons()
end

CFQ.RefreshSortButtons = function()
    local bothOn = (levelSortMode ~= "NONE") and (distSortMode ~= "NONE")
    for _, btn in ipairs(CFQ.sortCycleButtons) do
        local mode = CFQ.GetSortMode(btn.sortKey)
        if mode == "NONE" then
            btn.border:SetColorTexture(0.30, 0.30, 0.34, 0.90)
            btn.bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)
            btn.glow:Hide()
            btn.txt:SetText("|cFF9A9A9A" .. btn.baseLabel .. "|r")
            btn.rank:SetText("")
        else
            btn.border:SetColorTexture(1.0, 0.82, 0.20, 1.0)
            btn.bg:SetColorTexture(0.30, 0.22, 0.04, 0.98)
            btn.glow:Show()
            btn.txt:SetText("|cFFFFE27A" .. btn.baseLabel .. "|r " .. ((mode == "ASC") and ICON_ARROW_UP or ICON_ARROW_DOWN))
            if bothOn then
                btn.rank:SetText((primarySortKey == btn.sortKey) and "1" or "2")
            else
                btn.rank:SetText("")
            end
        end
    end
end

function CFQ.CreateSortCycleButton(parent, baseLabel, sortKey, width)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 50, 18)
    btn.sortKey = sortKey
    btn.baseLabel = baseLabel
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn.glow = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.glow:SetPoint("TOPLEFT", -2, 2)
    btn.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.glow:SetColorTexture(1.0, 0.80, 0.15, 0.35)
    btn.glow:Hide()

    btn.border = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    btn.border:SetAllPoints()

    btn.bg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn.bg:SetPoint("TOPLEFT", 1, -1)
    btn.bg:SetPoint("BOTTOMRIGHT", -1, 1)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.10)

    btn.txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.txt:SetPoint("CENTER", btn, "CENTER", 0, 0)

    btn.rank = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.rank:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    btn.rank:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -1)
    btn.rank:SetTextColor(1, 0.9, 0.5)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- right-click: straight to Off
            if CFQ.GetSortMode(self.sortKey) ~= "NONE" then
                if self.sortKey == "LVL" then levelSortMode = "DESC" else distSortMode = "DESC" end
                CFQ.CycleSortMode(self.sortKey)
            end
        else
            CFQ.CycleSortMode(self.sortKey)
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.sortKey == "LVL" then
            GameTooltip:AddLine("Sort by Quest Level", 1, 0.82, 0)
            GameTooltip:AddLine("Click to cycle:  " .. ICON_ARROW_UP .. " low → high,  " .. ICON_ARROW_DOWN .. " high → low,  off", 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("Sort by Distance", 1, 0.82, 0)
            GameTooltip:AddLine("Click to cycle:  " .. ICON_ARROW_UP .. " nearest first,  " .. ICON_ARROW_DOWN .. " farthest first,  off", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Quests with no known location sit at the bottom.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine("Right-click: turn off", 0.7, 0.7, 0.7)
        if levelSortMode ~= "NONE" and distSortMode ~= "NONE" then
            GameTooltip:AddLine("Both on: the one switched on last (marked 1) sorts first; the other breaks ties.", 0.6, 0.85, 1.0, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(CFQ.sortCycleButtons, btn)
    return btn
end

local function EnsureSharedMenu()
    if sharedMenuFrame then return sharedMenuFrame end

    local menuFrame = CreateFrame("Frame", "QRF_SharedDropdownMenu", UIParent)
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetFrameLevel(150)
    menuFrame:SetClampedToScreen(true)
    menuFrame:EnableMouse(true)
    menuFrame:EnableMouseWheel(true)
    menuFrame:SetMovable(true)
    menuFrame:RegisterForDrag("LeftButton")
    menuFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    menuFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    menuFrame:Hide()

    menuFrame:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    menuFrame:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        if self.searchBox then self.searchBox:ClearFocus() end
    end)
    menuFrame:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() then
            local overRewardBtn = questLogBar and questLogBar.rewardBtn and questLogBar.rewardBtn:IsMouseOver()
            local overLevelBtn  = questLogBar and questLogBar.levelBtn and questLogBar.levelBtn:IsMouseOver()
            local overTrackerBtn = trackerFilterBtn and trackerFilterBtn:IsMouseOver()
            if not self:IsMouseOver() and not overRewardBtn and not overLevelBtn and not overTrackerBtn then
                self:Hide()
            end
        end
    end)

    local bg = menuFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.96)

    local border = menuFrame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.45, 0.45, 0.5, 0.90)
    bg:SetDrawLayer("ARTWORK", -1)

    menuFrame.measureLabel = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menuFrame.measureLabel:Hide()

    menuFrame.headerLabel = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menuFrame.headerLabel:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 10, -8)
    menuFrame.headerLabel:SetText(CONFIG.HEADER_REWARDS)

    local closeBtn = CreateFrame("Button", nil, menuFrame, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() menuFrame:Hide() end)

    local groupToggleBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    groupToggleBtn:SetSize(68, 18)
    groupToggleBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    groupToggleBtn:SetText("Group: ON")
    groupToggleBtn:SetScript("OnClick", function()
        showCategories = not showCategories
        SaveState()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.groupToggleBtn = groupToggleBtn

    local menuResetBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    menuResetBtn:SetSize(48, 18)
    menuResetBtn:SetPoint("RIGHT", groupToggleBtn, "LEFT", -2, 0)
    menuResetBtn:SetText("Reset")
    menuResetBtn:SetScript("OnClick", function() ResetAllFilters() end)
    menuResetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset Filters", 1, 0.82, 0)
        GameTooltip:AddLine("Clears every reward & level filter, the search box, and both sorts.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    menuResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    menuFrame.menuResetBtn = menuResetBtn

    local searchBox = CreateFrame("EditBox", nil, menuFrame, "InputBoxTemplate")
    searchBox:SetSize(180, 18)
    searchBox:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 14, -27)
    searchBox:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -32, -27)
    searchBox:SetAutoFocus(false)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchPlaceholder:SetText("Search rewards or levels...")

    local clearSearchBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    clearSearchBtn:SetSize(20, 18)
    clearSearchBtn:SetPoint("LEFT", searchBox, "RIGHT", 2, 0)
    clearSearchBtn:SetText("X")
    clearSearchBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    searchBox:SetScript("OnTextChanged", function(self)
        local newText = self:GetText() or ""
        if newText == "" then searchPlaceholder:Show() else searchPlaceholder:Hide() end
        if newText ~= dropdownSearchText then
            dropdownSearchText = newText
            dropdownScrollOffset = 0
            RebuildDropdownMenu(menuFrame, true)
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    menuFrame.searchBox = searchBox

    local tabRewardsBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    tabRewardsBtn:SetHeight(20)
    tabRewardsBtn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, -50)
    tabRewardsBtn:SetPoint("RIGHT", menuFrame, "TOP", -2, 0)
    tabRewardsBtn:SetScript("OnClick", function()
        activeMenuTab = "REWARDS"
        dropdownScrollOffset = 0
        SaveState()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.tabRewardsBtn = tabRewardsBtn

    local tabLevelsBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    tabLevelsBtn:SetHeight(20)
    tabLevelsBtn:SetPoint("LEFT", menuFrame, "TOP", 2, 0)
    tabLevelsBtn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, -50)
    tabLevelsBtn:SetScript("OnClick", function()
        activeMenuTab = "LEVELS"
        dropdownScrollOffset = 0
        SaveState()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.tabLevelsBtn = tabLevelsBtn

    local sortBar = CreateFrame("Frame", nil, menuFrame)
    sortBar:SetHeight(22)
    sortBar:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, -74)
    sortBar:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, -74)

    sortBar.bg = sortBar:CreateTexture(nil, "BACKGROUND")
    sortBar.bg:SetAllPoints()
    sortBar.bg:SetColorTexture(0.12, 0.14, 0.18, 0.90)

    sortBar.label = sortBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortBar.label:SetPoint("LEFT", sortBar, "LEFT", 6, 0)
    sortBar.label:SetText("|cFFFFD100Sort:|r |cFF888888(click to cycle)|r")

    local distBtn = CFQ.CreateSortCycleButton(sortBar, "dist", "DIST", 54)
    distBtn:SetPoint("RIGHT", sortBar, "RIGHT", -3, 0)
    local lvlBtn = CFQ.CreateSortCycleButton(sortBar, "lvl", "LVL", 46)
    lvlBtn:SetPoint("RIGHT", distBtn, "LEFT", -4, 0)
    menuFrame.sortLvlBtn = lvlBtn
    menuFrame.sortDistBtn = distBtn
    menuFrame.sortBar = sortBar

    for i = 1, MAX_DROPDOWN_ROWS do
        local row = CreateFrame("Button", nil, menuFrame)
        row:SetHeight(21)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.12)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(20, 20)
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.check:SetMouseClickEnabled(false)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row.collapseText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.collapseText:SetPoint("RIGHT", row, "RIGHT", CONFIG.collapseRightOffset, 0)

        dropdownRowPool[i] = row
    end

    menuFrame.scrollHint = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    menuFrame:SetScript("OnMouseWheel", function(_, delta)
        local maxScroll = math.max(0, #dropdownDisplayList - MAX_DROPDOWN_ROWS)
        dropdownScrollOffset = math.min(maxScroll, math.max(0, dropdownScrollOffset - delta))
        RebuildDropdownMenu(menuFrame, false)
    end)

    local footerDivider = menuFrame:CreateTexture(nil, "ARTWORK")
    footerDivider:SetHeight(1)
    footerDivider:SetColorTexture(0.35, 0.35, 0.4, 0.8)
    menuFrame.footerDivider = footerDivider

    local untrackRow = CreateFrame("Button", nil, menuFrame)
    untrackRow:SetHeight(18)
    untrackRow.check = CreateFrame("CheckButton", nil, untrackRow, "UICheckButtonTemplate")
    untrackRow.check:SetSize(18, 18)
    untrackRow.check:SetPoint("LEFT", untrackRow, "LEFT", 2, 0)
    untrackRow.check:SetMouseClickEnabled(false)
    untrackRow.label = untrackRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    untrackRow.label:SetPoint("LEFT", untrackRow.check, "RIGHT", 2, 0)
    untrackRow.label:SetText("|cFFCCCCCCAuto-untrack non-matching quests|r")
    untrackRow:SetScript("OnClick", function()
        autoUntrack = not autoUntrack
        untrackRow.check:SetChecked(autoUntrack)
        ApplyFilterChanges()
    end)
    menuFrame.untrackRow = untrackRow

    local mapFilterRow = CreateFrame("Button", nil, menuFrame)
    mapFilterRow:SetHeight(18)
    mapFilterRow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mapFilterRow.check = CreateFrame("CheckButton", nil, mapFilterRow, "UICheckButtonTemplate")
    mapFilterRow.check:SetSize(18, 18)
    mapFilterRow.check:SetPoint("LEFT", mapFilterRow, "LEFT", 2, 0)
    mapFilterRow.check:SetMouseClickEnabled(false)
    mapFilterRow.label = mapFilterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mapFilterRow.label:SetPoint("LEFT", mapFilterRow.check, "RIGHT", 2, 0)
    mapFilterRow:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            mapFilterHideMode = not mapFilterHideMode
        else
            filterMapPins = not filterMapPins
        end
        SaveState()
        UpdateWorldMapPins()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.mapFilterRow = mapFilterRow

    local mapBadgeRow = CreateFrame("Button", nil, menuFrame)
    mapBadgeRow:SetHeight(18)
    mapBadgeRow.check = CreateFrame("CheckButton", nil, mapBadgeRow, "UICheckButtonTemplate")
    mapBadgeRow.check:SetSize(18, 18)
    mapBadgeRow.check:SetPoint("LEFT", mapBadgeRow, "LEFT", 2, 0)
    mapBadgeRow.check:SetMouseClickEnabled(false)
    mapBadgeRow.label = mapBadgeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mapBadgeRow.label:SetPoint("LEFT", mapBadgeRow.check, "RIGHT", 2, 0)
    mapBadgeRow.label:SetText("|cFFCCCCCCShow under-pin lvl & icons (Off = Tooltip)|r")
    mapBadgeRow:SetScript("OnClick", function()
        showMapBadges = not showMapBadges
        mapBadgeRow.check:SetChecked(showMapBadges)
        SaveState()
        UpdateWorldMapPins()
    end)
    menuFrame.mapBadgeRow = mapBadgeRow

    local optionsRow = CreateFrame("Button", nil, menuFrame)
    optionsRow:SetHeight(18)
    optionsRow.gear = CreateFrame("Frame", nil, optionsRow)
    optionsRow.gear:SetSize(14, 14)
    optionsRow.gear:SetPoint("LEFT", optionsRow, "LEFT", 4, 0)
    if not CFQ.ApplyGearIcon(optionsRow.gear, 1.0, 0.82, 0.0, "+", 11) then
        optionsRow.gear:SetSize(14, 14)
    end
    optionsRow.label = optionsRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optionsRow.label:SetPoint("LEFT", optionsRow.gear, "RIGHT", 5, 0)
    optionsRow.label:SetText("|cFFFFD100HandkerSheaf Options...|r |cFF888888(parchment & more)|r")
    local optHl = optionsRow:CreateTexture(nil, "HIGHLIGHT")
    optHl:SetAllPoints()
    optHl:SetColorTexture(1, 1, 1, 0.08)
    optionsRow:SetScript("OnClick", function()
        menuFrame:Hide()
        if CFQ.OpenOptions then CFQ.OpenOptions() end
    end)
    menuFrame.optionsRow = optionsRow

    local doneBtn = CreateFrame("Button", nil, menuFrame, "UIPanelButtonTemplate")
    doneBtn:SetSize(52, 22)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() menuFrame:Hide() end)
    menuFrame.doneBtn = doneBtn

    sharedMenuFrame = menuFrame
    return menuFrame
end

local function ToggleMenuAtButton(anchorBtn, isTrackerButton, tabOverride)
    local menu = EnsureSharedMenu()
    if menu:IsShown() and menu.anchorOwner == anchorBtn and (not tabOverride or activeMenuTab == tabOverride) then
        menu:Hide()
        return
    end

    if tabOverride then
        activeMenuTab = tabOverride
        dropdownScrollOffset = 0
        SaveState()
    end

    menu.anchorOwner = anchorBtn
    menu:ClearAllPoints()

    if isTrackerButton then
        local trackerFrame = ObjectiveTrackerFrame or QuestWatchFrame or anchorBtn
        menu:SetPoint("TOPRIGHT", trackerFrame, "TOPLEFT", -38, 0)
    else
        if QuestMapFrame and QuestMapFrame:IsShown() then
            menu:SetPoint("TOPRIGHT", QuestScrollFrame or anchorBtn, "TOPLEFT", -8, 24)
        else
            menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
        end
    end

    RebuildDropdownMenu(menu, false)
    menu:Show()
end

-- ============================================================================
-- OBJECTIVE TRACKER & QUEST LOG UI ATTACHMENT
-- ============================================================================
local function CreateObjectiveTrackerButton()
    if trackerFilterBtn then return end
    local parentFrame = ObjectiveTrackerFrame or QuestWatchFrame
    if not parentFrame then return end

    EnsureSharedMenu()

    local btn = CreateFrame("Button", "QRF_TrackerFilterButton", parentFrame, "UIPanelButtonTemplate")
    btn:SetSize(88, 18)
    btn:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -26, -2)
    btn:SetFrameLevel(parentFrame:GetFrameLevel() + 10)
    btn:SetText(CONFIG.TRACKER_BTN_ALL)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ResetAllFilters()
        else
            ToggleMenuAtButton(self, true, nil)
        end
    end)

    trackerFilterBtn = btn

    -- Quick Options gear: left-aligned, just above the "All Objectives" title
    local optBtn = CreateFrame("Button", "QRF_TrackerOptionsButton", parentFrame)
    optBtn:SetSize(16, 16)
    local headerAnchor = parentFrame.Header or parentFrame.HeaderMenu or parentFrame
    optBtn:SetPoint("BOTTOMLEFT", headerAnchor, "TOPLEFT", 0, 2)
    optBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 10)
    if not CFQ.ApplyGearIcon(optBtn, 0.85, 0.70, 0.30, "opt", 10) then
        optBtn:SetSize(30, 16)
    end
    optBtn.label = optBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optBtn.label:SetPoint("LEFT", optBtn, "RIGHT", 3, 0)
    optBtn.label:SetText("")
    optBtn:SetScript("OnClick", function()
        if CFQ.OpenOptions then CFQ.OpenOptions() end
    end)
    optBtn:SetScript("OnEnter", function(self)
        CFQ.SetGearHover(self, true)
        self.label:SetText("|cFFFFD100HandkerSheaf|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("HandkerSheaf Options", 1, 0.82, 0)
        GameTooltip:AddLine("Parchment pages, handwriting, tracker & map settings", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    optBtn:SetScript("OnLeave", function(self)
        CFQ.SetGearHover(self, false)
        self.label:SetText("")
        GameTooltip:Hide()
    end)
    CFQ.trackerOptionsBtn = optBtn
    CFQ.UpdateTrackerOptionsButton()

    UpdateAllButtonLabels()
end

local function CreateQuestLogUI()
    if not QuestScrollFrame or QuestScrollFrame.qrfBar then return end
    EnsureSharedMenu()

    local bar = CreateFrame("Frame", "QRF_FilterBar", QuestScrollFrame)
    bar:SetSize(268, 22)
    bar:SetPoint("BOTTOMLEFT", QuestScrollFrame, "TOPLEFT", 2, 3)

    local rewardBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    rewardBtn:SetSize(106, 22)
    rewardBtn:SetPoint("LEFT", bar, "LEFT", 0, 0)
    rewardBtn:SetText(CONFIG.REWARD_BTN_ALL)
    rewardBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rewardBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            wipe(selectedFilters)
            ApplyFilterChanges()
            if sharedMenuFrame and sharedMenuFrame:IsShown() then
                RebuildDropdownMenu(sharedMenuFrame, false)
            end
        else
            ToggleMenuAtButton(self, false, "REWARDS")
        end
    end)
    bar.rewardBtn = rewardBtn

    local levelBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    levelBtn:SetSize(104, 22)
    levelBtn:SetPoint("LEFT", rewardBtn, "RIGHT", 3, 0)
    levelBtn:SetText(CONFIG.LEVEL_BTN_ALL)
    levelBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    levelBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            wipe(selectedLevelFilters)
            levelSortMode = "NONE"
            ApplyFilterChanges()
            if sharedMenuFrame and sharedMenuFrame:IsShown() then
                RebuildDropdownMenu(sharedMenuFrame, false)
            end
        else
            ToggleMenuAtButton(rewardBtn, false, "LEVELS")
        end
    end)
    bar.levelBtn = levelBtn

    local resetBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    resetBtn:SetSize(48, 22)
    resetBtn:SetPoint("LEFT", levelBtn, "RIGHT", 3, 0)
    resetBtn:SetText("Reset")
    resetBtn:Disable()
    resetBtn:SetScript("OnClick", function() ResetAllFilters() end)
    bar.resetBtn = resetBtn

    local customList = CreateFrame("Frame", "QRF_CustomQuestList", QuestScrollFrame)
    customList:SetAllPoints(QuestScrollFrame)
    customList:SetFrameLevel(QuestScrollFrame:GetFrameLevel() + 15)
    customList:EnableMouse(true)
    customList:EnableMouseWheel(true)
    customList:Hide()

    local listBg = customList:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetColorTexture(0.06, 0.06, 0.08, 0.97)

    customList.headerText = customList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customList.headerText:SetPoint("TOPLEFT", customList, "TOPLEFT", 10, -8)

    local subHint = customList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subHint:SetPoint("TOPRIGHT", customList, "TOPRIGHT", -10, -8)
    subHint:SetText("Left-Click: Details | Shift + Left-Click: Track")

    local listDivider = customList:CreateTexture(nil, "ARTWORK")
    listDivider:SetHeight(1)
    listDivider:SetPoint("TOPLEFT", customList, "TOPLEFT", 8, -24)
    listDivider:SetPoint("TOPRIGHT", customList, "TOPRIGHT", -8, -24)
    listDivider:SetColorTexture(0.35, 0.35, 0.4, 0.8)

    for i = 1, MAX_CUSTOM_ROWS do
        local row = CreateFrame("Button", nil, customList)
        row:SetHeight(46)
        row:SetPoint("TOPLEFT", customList, "TOPLEFT", 8, -26 - ((i - 1) * 47))
        row:SetPoint("TOPRIGHT", customList, "TOPRIGHT", -8, -26 - ((i - 1) * 47))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.bg = row:CreateTexture(nil, "ARTWORK")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.0)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1.0, 0.82, 0.14)

        row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
        row.titleText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.titleText:SetJustifyH("LEFT")
        row.titleText:SetWordWrap(false)

        row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.zoneText:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -3)
        row.zoneText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.zoneText:SetJustifyH("LEFT")
        row.zoneText:SetWordWrap(false)

        row.badgeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.badgeText:SetPoint("TOPLEFT", row.zoneText, "BOTTOMLEFT", 0, -4)
        row.badgeText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.badgeText:SetJustifyH("LEFT")
        row.badgeText:SetWordWrap(false)

        customListRowPool[i] = row
    end

    customList.scrollHint = customList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customList.scrollHint:SetPoint("BOTTOM", customList, "BOTTOM", 0, 6)

    customList:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #matchingQuestsList - MAX_CUSTOM_ROWS)
        customScrollOffset = math.min(maxOffset, math.max(0, customScrollOffset - delta))
        RenderCustomFilteredList()
    end)

    QuestScrollFrame.qrfCustomList = customList

    QuestScrollFrame:HookScript("OnHide", function()
        if sharedMenuFrame and (sharedMenuFrame.anchorOwner == rewardBtn or sharedMenuFrame.anchorOwner == levelBtn) then
            sharedMenuFrame:Hide()
        end
    end)

    QuestScrollFrame.qrfBar = bar
    questLogBar = bar
    UpdateAllButtonLabels()
end

-- ============================================================================
-- HANDKERQUEST OPTIONS PANEL
-- Lives in Options > AddOns, opens from the tally's gear, the gear above "All Objectives", the
-- filter menu, or /hanky options. Falls back to a standalone window on clients without that menu.
-- EDIT: each Check(...) is one checkbox: its label, its tooltip, then what it reads and sets.
-- ============================================================================
CFQ.UpdateTrackerOptionsButton = function()
    local btn = CFQ.trackerOptionsBtn
    if not btn then return end
    btn:SetShown(CFQ.parchmentOpts.showTrackerOptionsButton ~= false)
end

CFQ.RefreshOptionsPanel = function()
    for _, w in ipairs(CFQ.optionWidgets) do
        if w.Refresh then w:Refresh() end
    end
    if CFQ.RefreshSortButtons then CFQ.RefreshSortButtons() end
end

-- The version comes live from the .toc's "## Version" line, so it never needs bumping here.
-- nil if the client can't tell us (the panel heading then shows the name alone).
function CFQ.AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, CONFIG.ADDON_NAME, "Version")
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

function CFQ.BuildOptionsPanel()
    if CFQ.optionsPanel then return CFQ.optionsPanel end

    -- The panel scrolls: it's taller than the Settings window. Everything below is built on the scroll
    -- child (p); the registered panel is the outer frame.
    local outer = CreateFrame("Frame", "QRF_OptionsPanel")
    outer.name = CONFIG.DISPLAY_NAME
    outer:Hide()
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
    if not okS or not scroll then scroll = CreateFrame("ScrollFrame", nil, outer) end
    scroll:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -28, 4)
    scroll:EnableMouseWheel(true)
    if not scroll.ScrollBar then
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, (self:GetScrollChild() and self:GetScrollChild():GetHeight() or 0) - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
        end)
    end
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(560, 900)
    scroll:SetScrollChild(p)
    local function FitWidth()
        local w = scroll:GetWidth()
        if w and w > 100 then p:SetWidth(w) end
    end
    outer:SetScript("OnSizeChanged", FitWidth)
    local y = -16

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
    local version = CFQ.AddonVersion()
    title:SetText(CONFIG.DISPLAY_NAME .. (version and (" |cFF888888v" .. version .. "|r") or ""))
    CFQ.optionsTitle = title
    y = y - 22
    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
    sub:SetText("Quest reward & level filters, tracker stacks, and the Field Tally parchment.")
    y = y - 26

    local function Section(text)
        local fs = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
        fs:SetText(text)
        local line = p:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", p, "RIGHT", -24, 0)
        line:SetColorTexture(0.6, 0.5, 0.2, 0.5)
        y = y - 22
    end

    local function Check(label, tip, getFn, setFn, indent)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + (indent or 0), y)
        cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        cb.label:SetText(label)
        cb:SetScript("OnClick", function(self)
            setFn(self:GetChecked() and true or false)
            SaveState()
            CFQ.RefreshOptionsPanel()
        end)
        if tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 0.82, 0)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        cb.Refresh = function(self) self:SetChecked(getFn() and true or false) end
        table.insert(CFQ.optionWidgets, cb)
        y = y - 26
        return cb
    end

    local function Button(label, width, x, onClick, refreshFn)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function(self)
            onClick(self)
            CFQ.RefreshOptionsPanel()
        end)
        if refreshFn then
            b.Refresh = refreshFn
            table.insert(CFQ.optionWidgets, b)
        end
        return b
    end

    local function RefreshParchment()
        if UpdateShoppingListUI then UpdateShoppingListUI() end
    end

    -- Field Tally parchment ---------------------------------------------------
    Section("Field Tally Parchment")
    Check("Show the parchment tally list",
        "The handwritten checklist of quest items to gather and tasks to do around you.",
        function() return showShoppingList end,
        function(v) if v then P.TurnTallyOn() else showShoppingList = false; RefreshParchment() end end)
    -- right under it (it decides whether the tally is up at all), greyed out while the tally is off
    local hideCb = Check("...only when something is nearby",
        "On: the tally only appears when the area you're in has something to gather or do, and puts itself away when it doesn't. Off: the pile stays up so you can leaf through other areas.",
        function() return CFQ.parchmentOpts.hideWhenNothingNearby end,
        function(v)
            CFQ.parchmentOpts.hideWhenNothingNearby = v
            if showShoppingList then P.TurnTallyOn() end      -- says so in chat if this just put it away
        end, 24)
    local hideRefresh = hideCb.Refresh
    hideCb.Refresh = function(self)
        hideRefresh(self)
        self:SetAlpha(showShoppingList and 1 or 0.45)
    end
    -- Slider row: label, slider (1-50% unless lo/hi are given), value, hint. get() returns the value; set(v) applies it.
    local function RadiusSlider(labelText, tipTitle, tipBody, get, set, hintFn, enabledFn, lo, hi)
        lo, hi = lo or 1, hi or 50
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(440, 26)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", 48, y)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetText(labelText)
        local slider = CreateFrame("Slider", nil, row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(170, 16)
        slider:SetPoint("LEFT", row, "LEFT", 110, 0)
        slider:SetMinMaxValues(lo, hi)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:EnableMouseWheel(true)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(6)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetColorTexture(0.08, 0.08, 0.08, 0.9)
        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(4)
        fill:SetPoint("LEFT", slider, "LEFT", 1, 0)
        fill:SetColorTexture(1.0, 0.82, 0.0, 0.85)
        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(18, 18)
        thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetThumbTexture(thumb)
        local valText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
        local hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", valText, "RIGHT", 8, 0)

        local function Show(v)
            fill:SetWidth(math.max(1, (v - lo) / (hi - lo) * 168))
            valText:SetText(v .. "%")
        end
        slider:SetScript("OnValueChanged", function(self, val)
            local v = math.floor((val or 10) + 0.5)
            Show(v)
            if self.updating then return end
            if v ~= get() then set(v) end
        end)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue((self:GetValue() or get()) + delta)
        end)
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tipTitle, 1, 0.82, 0)
            GameTooltip:AddLine(tipBody, 0.9, 0.9, 0.9, true)
            local h = hintFn and hintFn()
            if h and h ~= "" then GameTooltip:AddLine(h, 0.55, 0.85, 0.55, true) end
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.Refresh = function()
            local v = get()
            slider.updating = true
            slider:SetValue(v)
            slider.updating = false
            Show(v)
            hint:SetText((hintFn and hintFn()) or "")
            row:SetAlpha((not enabledFn or enabledFn()) and 1 or 0.45)
        end
        row.slider = slider
        table.insert(CFQ.optionWidgets, row)
        y = y - 30
        return row
    end

    -- "Near me" (page 1): how close you must be to a quest's objective area
    CFQ.nearRadiusRow = RadiusSlider("Near me distance", "Near me distance",
        "Page 1 lists quest items and tasks within this distance of where you're standing (as % of the zone map), plus anything you've progressed in the last few minutes.",
        function() return P.GetNearRadius() end,
        function(v) CFQ.nearRadiusPercent = v; SaveState(); RefreshParchment() end)

    -- What the tally lists (same as the toggles beside its gear; one of items / tasks always stays on)
    Check("List quest items",
        "Quest items to loot or gather.",
        function() return CFQ.parchmentOpts.tallyLoot end,
        function(v) P.SetTallyShows("items", v); P.OnTallyChoiceChanged() end)
    Check("List tasks",
        "Enemies to slay and other quest steps. Each gets its own box to tick; a line to slay catches fire while your target is one of them.",
        function() return CFQ.parchmentOpts.tallyTasks end,
        function(v) P.SetTallyShows("tasks", v); P.OnTallyChoiceChanged() end)
    Check("Tasks apart from items",
        "Items first, then the tasks under their own heading. Off: items and tasks together, in the tracker's quest order.",
        function() return CFQ.parchmentOpts.tallySeparate end,
        function(v) CFQ.parchmentOpts.tallySeparate = v; P.OnTallyChoiceChanged() end)

    Check("Pages for other areas",
        "Quests that aren't near you go on more pages in the pile, one per place (see Other pages by). Click the dog-eared corner to turn to the next page (right-click to go back).",
        function() return CFQ.parchmentOpts.showTabs end,
        function(v) CFQ.parchmentOpts.showTabs = v; RefreshParchment() end)

    -- How area pages (page 2+) are divided up
    local groupBtn = Button("Other pages by: Map areas", 230, 48, function()
        P.CycleGrouping()
        shoppingScrollOffset = 0
        SaveState()
        RefreshParchment()
    end, function(self)
        self:SetText("Other pages by: " .. P.GetGrouping().label)
        self:SetAlpha(CFQ.parchmentOpts.showTabs and 1 or 0.45)
    end)
    groupBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Other pages by", 1, 0.82, 0)
        GameTooltip:AddLine("How the quests that aren't near you are split into pages (page 1 is always Near me).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Map areas: one page per explored subzone the quest is in (the names on your world map).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Zones: one page per zone.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Clusters: quests close together share a page, named after the place. How close is the Cluster size below.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Pages with the same name are always merged.", 0.55, 0.85, 0.55, true)
        GameTooltip:Show()
    end)
    groupBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 30

    local function DistanceMode() return CFQ.parchmentOpts.showTabs and P.GetGrouping().key == "RADIUS" end
    local followCb = Check("Cluster size follows the tracker's (•••) stacking slider",
        "Clusters only. On: quests that would share a (•••) stack in the Objective Tracker share a page. Off: set the cluster size yourself below.",
        function() return CFQ.parchmentOpts.pagesFollowTracker end,
        function(v) CFQ.parchmentOpts.pagesFollowTracker = v; RefreshParchment() end)
    local baseRefresh = followCb.Refresh
    followCb.Refresh = function(self)
        baseRefresh(self)
        self:SetAlpha(DistanceMode() and 1 or 0.45)
    end


    -- Clusters (page 2+): how far apart quests can be and still share a page
    CFQ.pageRadiusRow = RadiusSlider("Cluster size", "Cluster size",
        "Clusters only. Quests within this distance of each other (as % of the zone map) share a page. Smaller = more, tighter pages.",
        function() return P.GetPageRadius() end,
        function(v)
            if CFQ.parchmentOpts.pagesFollowTracker then
                -- linked: this slider *is* the tracker's (•••) slider
                incompleteRadiusPercent = v
                ApplyFilterChanges()
            else
                CFQ.pageRadiusPercent = v
                SaveState()
                RefreshParchment()
            end
        end,
        function() return CFQ.parchmentOpts.pagesFollowTracker and "(linked to •••)" or "" end,
        DistanceMode)
    Check("Turn back to \"Near me\" when you arrive somewhere new",
        "When you enter a new area, the pile turns back to the Near me page and its heading is written in fresh red ink.",
        function() return CFQ.parchmentOpts.autoFrontOnAreaChange end,
        function(v) CFQ.parchmentOpts.autoFrontOnAreaChange = v end)

    Check("Mark the tracked quest's item spots on the minimap",
        "Amber pips on the minimap where you've looted the items of the quest you're tracking (click an item on the tally to track its quest). Pips beyond the minimap's edge sit on the rim, pointing the way.",
        function() return CFQ.parchmentOpts.minimapPins end,
        function(v) CFQ.parchmentOpts.minimapPins = v; CFQ.UpdateMinimapPins() end)
    Check("Little map when you hover an item",
        "Shows a small map under the item's tooltip: the quest's objective area, the spots you've looted it in, and where you are.",
        function() return CFQ.parchmentOpts.mapPreview end,
        function(v) CFQ.parchmentOpts.mapPreview = v; if not v then CFQ.HideMapPreview() end end)
    Check("Glowing & burning ink",
        "An item's line glows when you walk into its hunting grounds, and catches fire while your target is a mob that may drop it.",
        function() return CFQ.parchmentOpts.inkEffects end,
        function(v) CFQ.parchmentOpts.inkEffects = v; RefreshParchment() end)
    CFQ.textSizeRow = RadiusSlider("Text size", "Text size",
        "How big the tally's writing is, as % of the usual size. The page heading grows by half as much.",
        function() return CFQ.tallyTextScale or 100 end,
        function(v) CFQ.tallyTextScale = v; SaveState(); RefreshParchment() end,
        nil, nil, P.TEXT_SCALE_MIN, P.TEXT_SCALE_MAX)

    -- Colour swatches (+ Custom... = WoW's colour picker). which = "rune" (Arcane script's rune circle,
    -- beside the Look button, only while that look is chosen) or "ink" (the writing, every look; each
    -- look remembers its own). The first swatch is always the look's own colour.
    local function IsArcane() return P.GetStyle().key == "ARCANE" end
    local function OpenColorPicker(which)
        if not ColorPickerFrame then return end
        local before = CFQ.ValidColor(P.GetStoredTallyColor(which))
        local cur = P.GetTallyColor(which)
        local function Picked()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            P.SetTallyColor(which, { r, g, b })
            CFQ.RefreshOptionsPanel()
        end
        local function Cancelled()
            P.SetTallyColor(which, before)
            CFQ.RefreshOptionsPanel()
        end
        pcall(function()
            if ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({ r = cur[1], g = cur[2], b = cur[3], hasOpacity = false,
                    swatchFunc = Picked, cancelFunc = Cancelled })
            else
                ColorPickerFrame.hasOpacity = false
                ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Picked, Cancelled
                ColorPickerFrame.previousValues = { r = cur[1], g = cur[2], b = cur[3] }
                ColorPickerFrame:SetColorRGB(cur[1], cur[2], cur[3])
                ColorPickerFrame:Hide()
                ColorPickerFrame:Show()
            end
        end)
    end
    local function ColorRow(x, rowY, labelText, labelW, which, presets, tipBody, shownFn)
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(labelW + #presets * 22 + 82, 22)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", x, rowY - 1)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetText(labelText)
        local function Tip(owner, name)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:AddLine(labelText .. (name and (": " .. name) or ""), 1, 0.82, 0)
            GameTooltip:AddLine(tipBody, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
        local function OwnColor()
            if which == "rune" then return presets[1].c end
            return P.StyleDefaults(P.GetStyle()).ink
        end
        row.swatches = {}
        for k, pr in ipairs(presets) do
            local b = CreateFrame("Button", nil, row)
            b:SetSize(18, 18)
            b:SetPoint("LEFT", row, "LEFT", labelW + (k - 1) * 22, 0)
            b.ring = b:CreateTexture(nil, "BACKGROUND")
            b.ring:SetAllPoints()
            b.fill = b:CreateTexture(nil, "ARTWORK")
            b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
            b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
            b.preset = pr
            b:SetScript("OnClick", function()
                local c = pr.c
                if k == 1 then c = nil end                             -- the first swatch = the look's own
                P.SetTallyColor(which, c)
                CFQ.RefreshOptionsPanel()
            end)
            b:SetScript("OnEnter", function(self) Tip(self, pr.label) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.swatches[k] = b
        end
        if ColorPickerFrame then
            local cb = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            cb:SetSize(70, 20)
            cb:SetPoint("LEFT", row, "LEFT", labelW + #presets * 22 + 6, 0)
            cb:SetText("Custom...")
            cb:SetScript("OnClick", function() OpenColorPicker(which) end)
            cb:SetScript("OnEnter", function(self) Tip(self, "any colour") end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.customBtn = cb
        end
        row.Refresh = function(self)
            local stored = CFQ.ValidColor(P.GetStoredTallyColor(which))
            local own = OwnColor()
            if stored and P.SameColor(stored, own) then stored = nil end
            local any = false
            for k, b in ipairs(self.swatches) do
                local c = (k == 1) and own or b.preset.c
                b.fill:SetColorTexture(c[1], c[2], c[3], 1)
                local on
                if k == 1 then on = (stored == nil) else on = stored ~= nil and P.SameColor(stored, c) end
                any = any or on
                b.selected = on
                if on then b.ring:SetColorTexture(1, 0.82, 0, 1) else b.ring:SetColorTexture(0, 0, 0, 0.9) end
            end
            if self.customBtn then self.customBtn:SetText(any and "Custom..." or "Custom •") end
            self:SetShown(not shownFn or shownFn())
        end
        table.insert(CFQ.optionWidgets, row)
        return row
    end

    y = y - 4
    -- Look: a drop-down list of every look (a little swatch of each, the current one ticked; hover one
    -- to read about it). Clicking outside the list, or the button again, closes it.
    local LOOK_BLURBS = {
        HANDKERCHIEF = "Scribbled on a hemmed, folded handkerchief.",
        PARCHMENT = "A pile of torn parchment pages.",
        CRUMPLED = "A sheet crumpled into a ball and flattened out again, in pencil.",
        RAG = "A strip torn off a dwarf's shirt, hem and all, written in soot.",
        STONE = "A smooth dark river stone, written on in chalk.",
        BARK = "A jagged slab of dark bark, the list carved into the red underbark.",
        LEAF = "A cured leaf of Longbottom's finest, written in ink.",
        LEATHER = "A rough-cut piece of soft tan hide, the list pressed into it.",
        MARBLE = "A white marble tablet, the list cut in and gilded, glowing with holy light.",
        GILDED = "A plate of beaten gold, the list engraved; light glints across it now and then.",
        VELLUM = "A page of a holy book with a gold-leaf border, the heading in red.",
        ARCANE = "A mage's words of light hanging in the air, a rune circle turning behind them.",
        NATIVE = "A see-through WoW-style panel, in the handwriting you pick.",
    }
    local lookBtn = Button("Look: Torn rag", 210, 24, function(self)
        if self.list:IsShown() then self.list:Hide() else self.list:Show() end
    end, function(self)
        self:SetText("Look: " .. P.GetStyle().label)
        if self.list and self.list:IsShown() then self.list:Refresh() end
    end)
    lookBtn.arrow = lookBtn:CreateTexture(nil, "OVERLAY")
    lookBtn.arrow:SetSize(16, 16)
    lookBtn.arrow:SetPoint("RIGHT", lookBtn, "RIGHT", -4, 0)
    lookBtn.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    lookBtn:SetScript("OnEnter", function(self)
        if self.list:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Look of the Field Tally", 1, 0.82, 0)
        GameTooltip:AddLine("Click to pick one from the list.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    lookBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local ROW_H = 20
    -- Layers: the list sits above everything (FULLSCREEN_DIALOG), the click-catcher just under it (DIALOG,
    -- still above the Settings window). Set again every time the list opens: when Settings shows our panel
    -- it re-parents it, which pulls the list back down to the window's layer, under the catcher, and every
    -- click on a look then only closed the list.
    local list = CreateFrame("Frame", nil, lookBtn)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetToplevel(true)
    list:EnableMouse(true)
    list:SetPoint("TOPLEFT", lookBtn, "BOTTOMLEFT", 0, -2)
    list:SetSize(230, #P.STYLES * ROW_H + 10)
    list.bg = list:CreateTexture(nil, "BACKGROUND")
    list.bg:SetAllPoints()
    list.bg:SetColorTexture(0.06, 0.05, 0.04, 0.96)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                            { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local t = list:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.6, 0.5, 0.2, 0.8)
        t:SetPoint(edge[1], list, edge[1], 0, 0)
        t:SetPoint(edge[2], list, edge[2], 0, 0)
        if edge[3] == 1 then t:SetWidth(1) else t:SetHeight(1) end
    end
    list:Hide()
    -- a click anywhere else closes the list
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function()
        -- if a click still lands here over a look (layers changed under us), pick that look
        for _, row in ipairs(list.rows or {}) do
            if row:IsShown() and row:IsMouseOver() then row:GetScript("OnClick")(row); return end
        end
        list:Hide()
    end)
    catcher:Hide()
    list:SetFrameLevel(catcher:GetFrameLevel() + 5)
    list.rows = {}
    for k, st in ipairs(P.STYLES) do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(222, ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -5 - (k - 1) * ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 0.82, 0, 0.15)
        row.tick = row:CreateTexture(nil, "ARTWORK")
        row.tick:SetSize(14, 14)
        row.tick:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(16, 16)
        row.swatch:SetPoint("LEFT", row, "LEFT", 20, 0)
        if st.image then
            row.swatch:SetTexture(st.image)
            row.swatch:SetTexCoord(0.25, 0.75, 0.25, 0.75)          -- the middle of the material
        else
            local c = st.paper
            row.swatch:SetColorTexture(c[1], c[2], c[3], math.max(c[4] or 1, 0.6))
        end
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 6, 0)
        row.label:SetText(st.label)
        row.key = st.key
        row:SetScript("OnClick", function(self)
            CFQ.parchmentStyle = self.key
            list:Hide()
            SaveState()
            P.ApplyStyle()
            RefreshParchment()
            CFQ.RefreshOptionsPanel()
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(list, "ANCHOR_RIGHT")
            GameTooltip:AddLine(st.label, 1, 0.82, 0)
            if LOOK_BLURBS[st.key] then GameTooltip:AddLine(LOOK_BLURBS[st.key], 0.9, 0.9, 0.9, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        list.rows[k] = row
    end
    list.Refresh = function(self)
        local cur = P.GetStyle().key
        for _, row in ipairs(self.rows) do
            row.tick:SetShown(row.key == cur)
            row.label:SetTextColor(1, row.key == cur and 0.82 or 1, row.key == cur and 0 or 1)
        end
    end
    list:SetScript("OnShow", function(self)
        catcher:SetFrameStrata("DIALOG")
        catcher:Show()
        self:SetFrameStrata("FULLSCREEN_DIALOG")
        self:Raise()
        self:Refresh()
        GameTooltip:Hide()
    end)
    list:SetScript("OnHide", function() catcher:Hide() end)
    lookBtn.list = list
    list.catcher = catcher
    CFQ.lookDropDown = list
    outer:HookScript("OnHide", function() list:Hide() end)
    -- beside the Look button, only while Arcane script is the look
    CFQ.runeColorRow = ColorRow(244, y, "Runes", 42, "rune", P.ARCANE_RUNE_COLORS,
        "Arcane script: the colour of the rune circle and its light (the glow round the words, the motes, ticks and strikes, the corner mark).",
        IsArcane)
    y = y - 28
    Button("Handwriting: Quill script", 190, 24, function()
        P.CycleFontStyle()
        SaveState()
        RefreshParchment()
    end, function(self)
        -- some looks bring their own lettering (carved bark: knife-cut letters)
        local forced = P.GetStyle().font
        local label = P.GetFontStyle().label
        if forced then
            for _, fst in ipairs(P.FONT_STYLES) do if fst.key == forced then label = fst.label .. " (set by the look)" end end
        end
        self:SetText("Handwriting: " .. label)
        self:SetAlpha(forced and 0.45 or 1)
    end)
    Button("Reset Position & Size", 160, 220, function()
        ResetShoppingListPosition()
        P.TurnTallyOn()
    end)
    y = y - 30

    -- every look; each look remembers its own
    CFQ.inkColorRow = ColorRow(24, y, "Writing colour", 128, "ink", P.INK_COLORS,
        "The colour of the tally's writing: the lines, heading and footer. Each look remembers its own; the first swatch is the look's own ink.")
    y = y - 34

    -- Tracker & map -----------------------------------------------------------
    Section("Tracker & Map")
    Check("Quick Options gear above the tracker",
        "The small gear just above \"All Objectives\" that opens this panel.",
        function() return CFQ.parchmentOpts.showTrackerOptionsButton end,
        function(v) CFQ.parchmentOpts.showTrackerOptionsButton = v; CFQ.UpdateTrackerOptionsButton() end)
    Check("Auto-untrack quests that don't match the filter",
        nil,
        function() return autoUntrack end,
        function(v) autoUntrack = v; ApplyFilterChanges() end)
    Check("Filter zone map pins",
        "Dim (or hide) world map quest pins that don't match the active filter.",
        function() return filterMapPins end,
        function(v) filterMapPins = v; UpdateWorldMapPins() end)
    Check("Show level & reward icons under map pins",
        "Off: they only show in the pin's tooltip.",
        function() return showMapBadges end,
        function(v) showMapBadges = v; UpdateWorldMapPins() end)
    y = y + 2
    Button("Non-matching pins: Dim", 180, 24, function()
        mapFilterHideMode = not mapFilterHideMode
        SaveState()
        UpdateWorldMapPins()
    end, function(self)
        self:SetText("Non-matching pins: " .. (mapFilterHideMode and "Hide" or "Dim"))
    end)
    y = y - 34

    -- Sorting -----------------------------------------------------------------
    Section("Sorting")
    local sortLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sortLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 24, y - 3)
    sortLabel:SetText("Tracker & quest log:")
    local lvlBtn = CFQ.CreateSortCycleButton(p, "lvl", "LVL", 50)
    lvlBtn:SetPoint("LEFT", sortLabel, "RIGHT", 10, 0)
    local distBtn = CFQ.CreateSortCycleButton(p, "dist", "DIST", 58)
    distBtn:SetPoint("LEFT", lvlBtn, "RIGHT", 6, 0)
    Button("Reset Filters & Sorts", 160, 260, function()
        ResetAllFilters()
    end)
    y = y - 34

    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
    hint:SetPoint("RIGHT", p, "RIGHT", -24, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Slash: /hanky (filter menu), /hanky options, /hanky lvl, /hanky dist, /hanky list, /hanky look, /hanky resetlist, /hanky items, /hanky reset")

    p:SetHeight(math.abs(y) + 40)
    outer:SetScript("OnShow", function() FitWidth(); CFQ.RefreshOptionsPanel() end)
    CFQ.optionsPanel = outer
    CFQ.optionsPanelHeight = math.abs(y) + 30
    return outer
end

function CFQ.RegisterOptions()
    if CFQ.optionsRegistered then return end
    CFQ.optionsRegistered = true
    local p = CFQ.BuildOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, p, CONFIG.DISPLAY_NAME)
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            CFQ.optionsCategory = category
            return
        end
    end
    if InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, p)
        CFQ.optionsLegacy = true
    end
end

function CFQ.ShowStandaloneOptions()
    local host = CFQ.optionsStandalone
    if not host then
        host = CreateFrame("Frame", "QRF_OptionsStandalone", UIParent)
        host:SetSize(540, math.min((CFQ.optionsPanelHeight or 560) + 10, 620))
        host:SetPoint("CENTER")
        host:SetFrameStrata("DIALOG")
        host:SetClampedToScreen(true)
        host:EnableMouse(true)
        host:SetMovable(true)
        host:RegisterForDrag("LeftButton")
        host:SetScript("OnDragStart", host.StartMoving)
        host:SetScript("OnDragStop", host.StopMovingOrSizing)
        local bg = host:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.96)
        local border = host:CreateTexture(nil, "BACKGROUND", nil, -1)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.55, 0.45, 0.20, 0.9)
        local close = CreateFrame("Button", nil, host, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, -2)
        if UISpecialFrames then table.insert(UISpecialFrames, "QRF_OptionsStandalone") end
        CFQ.optionsStandalone = host
    end
    local p = CFQ.BuildOptionsPanel()
    p:SetParent(host)
    p:ClearAllPoints()
    p:SetAllPoints(host)
    p:Show()
    host:Show()
    CFQ.RefreshOptionsPanel()
end

CFQ.OpenOptions = function()
    CFQ.RegisterOptions()
    if CFQ.optionsCategory and Settings and Settings.OpenToCategory then
        if InCombatLockdown() then
            print("|cFFFFD100HandkerSheaf:|r options will open after combat.")
            CFQ.openOptionsAfterCombat = true
            return
        end
        local id = (CFQ.optionsCategory.GetID and CFQ.optionsCategory:GetID()) or CFQ.optionsCategory.ID
        local ok = pcall(Settings.OpenToCategory, id)
        if ok then return end
    elseif CFQ.optionsLegacy and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(CFQ.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(CFQ.optionsPanel)   -- first call only opens the frame on old clients
        return
    end
    CFQ.ShowStandaloneOptions()
end

-- Slash Commands (/hanky, /handkerquest, and the old /cfq)
SLASH_HANDKERQUEST1 = "/hanky"
SLASH_HANDKERQUEST2 = "/handkerquest"
SLASH_HANDKERQUEST3 = "/cfq"           -- old Cache ForQuest command, kept so muscle memory still works
SlashCmdList["HANDKERQUEST"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    if cmd == "reset" then
        ResetAllFilters()
    elseif cmd == "asc" or cmd == "desc" then
        if levelSortMode == "NONE" then primarySortKey = "LVL" end
        levelSortMode = (cmd == "asc") and "ASC" or "DESC"
        ApplyFilterChanges()
    elseif cmd == "lvl" or cmd == "level" then
        CFQ.CycleSortMode("LVL")
    elseif cmd == "dist" or cmd == "distance" then
        CFQ.CycleSortMode("DIST")
    elseif cmd == "list" or cmd == "tally" then
        if showShoppingList then
            showShoppingList = false
            UpdateShoppingListUI()
        else
            P.TurnTallyOn()
        end
        SaveState()
        CFQ.RefreshOptionsPanel()
    elseif cmd == "resetlist" then
        ResetShoppingListPosition()
        P.TurnTallyOn()
        CFQ.RefreshOptionsPanel()
    elseif cmd == "debug" then
        CFQ.DebugDumpTracker()
    elseif cmd == "items" then
        CFQ.DebugDumpItems()
    elseif cmd == "look" or cmd == "style" or string.find(cmd, "^look ") or string.find(cmd, "^style ") then
        local want = string.match(cmd, "^%a+%s+(%a+)")
        local alias = { handkerchief = "HANDKERCHIEF", hanky = "HANDKERCHIEF", parchment = "PARCHMENT",
            crumpled = "CRUMPLED", paper = "CRUMPLED", rag = "RAG", torn = "RAG", shirt = "RAG",
            stone = "STONE", rock = "STONE", chalk = "STONE", slate = "STONE", bark = "BARK", carved = "BARK", wood = "BARK",
            leaf = "LEAF", pipeweed = "LEAF", tobacco = "LEAF", longbottom = "LEAF",
            leather = "LEATHER", etched = "LEATHER", tooled = "LEATHER", hide = "LEATHER", suede = "LEATHER",
            marble = "MARBLE", tablet = "MARBLE", sanctified = "MARBLE", holy = "MARBLE",
            gold = "GILDED", gilded = "GILDED", plate = "GILDED", golden = "GILDED",
            vellum = "VELLUM", illuminated = "VELLUM", manuscript = "VELLUM", libram = "VELLUM", book = "VELLUM",
            arcane = "ARCANE", mage = "ARCANE", magic = "ARCANE", rune = "ARCANE", runes = "ARCANE",
            window = "NATIVE", transparent = "NATIVE", native = "NATIVE" }
        if want and alias[want] then CFQ.parchmentStyle = alias[want] else P.CycleStyle() end
        SaveState()
        P.ApplyStyle()
        UpdateShoppingListUI()
        CFQ.RefreshOptionsPanel()
        print("|cFFFFD100HandkerSheaf:|r Field Tally look: " .. P.GetStyle().label)
    elseif cmd == "options" or cmd == "opt" or cmd == "config" or cmd == "settings" then
        CFQ.OpenOptions()
    else
        local anchor = trackerFilterBtn or (questLogBar and questLogBar.rewardBtn) or UIParent
        ToggleMenuAtButton(anchor, true, "LEVELS")
    end
end

-- ============================================================================
-- INITIALIZATION, PROXIMITY TICKER & OBJECTIVE TRACKER HOOKS
-- ============================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("QUEST_LOG_UPDATE")
loader:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
loader:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
loader:RegisterEvent("SUPER_TRACKING_CHANGED")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:RegisterEvent("ZONE_CHANGED")
loader:RegisterEvent("ZONE_CHANGED_INDOORS")
loader:RegisterEvent("ZONE_CHANGED_NEW_AREA")
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("BAG_UPDATE_COOLDOWN")
loader:RegisterEvent("LOOT_OPENED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(CFQ.itemButtons) do if b:IsShown() then CFQ.UpdateItemCooldown(b) end end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        pcall(CFQ.PlaceDeckItemButtons)                -- item buttons catch up after combat
        if CFQ.openOptionsAfterCombat then
            CFQ.openOptionsAfterCombat = false
            CFQ.OpenOptions()
        end
        return
    end
    if event == "LOOT_OPENED" then
        pcall(CFQ.OnLootOpened)
        return
    end
    if event == "ADDON_LOADED" and arg1 == "Handkerquest" then
        LoadState()
    elseif event == "PLAYER_ENTERING_WORLD" then
        LoadState()
        CreateQuestLogUI()
        CreateObjectiveTrackerButton()
        EnsureShoppingListFrame()
        HookAllMapTooltips()
        CFQ.RegisterOptions()
        CFQ.EnsureMinimapDriver()

        -- Chat frames settle into their Edit Mode layout a moment after login; re-seat the
        -- parchment above the chat box if it is still on its default anchor.
        if C_Timer and C_Timer.After then
            C_Timer.After(1.5, function()
                if shoppingListCfg.useDefaultAnchor and shoppingListFrame then
                    CFQ.P.ApplyPosition(shoppingListFrame)
                end
            end)
            -- once the quest log has settled, forget hunting spots / droppers of quests you no longer have
            C_Timer.After(15, function() pcall(CFQ.PruneHuntData) end)
        end

        if QuestLogQuests_Update then
            hooksecurefunc("QuestLogQuests_Update", function()
                UpdateQuestLogUI(true)
            end)
        end
        if QuestObjectiveTracker and QuestObjectiveTracker.Update then
            hooksecurefunc(QuestObjectiveTracker, "Update", function() LayoutObjectiveTrackerWithStacks() end)
        end
        if ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then
            hooksecurefunc(ObjectiveTrackerFrame, "Update", function() LayoutObjectiveTrackerWithStacks() end)
        end
        if WatchFrame_Update then
            hooksecurefunc("WatchFrame_Update", function() LayoutObjectiveTrackerWithStacks() end)
        end
        if WorldMapFrame and WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnShow", function()
                HookAllMapTooltips()
                UpdateQuestLogUI(false)
            end)
            if WorldMapFrame.OnMapChanged then
                hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                    UpdateQuestLogUI(false)
                end)
            end
        end

        -- Lightweight 1.2s proximity ticker so the tally updates as you walk into/out of quest hubs
        if C_Timer and C_Timer.NewTicker and not self.proximityTicker then
            self.proximityTicker = C_Timer.NewTicker(1.2, function()
                if InCombatLockdown() then return end
                if showShoppingList then
                    UpdateShoppingListUI()
                end
                -- Distance sort: re-order the tracker every ~3.6s as you move (skipped while a stack is fanned open)
                if distSortMode ~= "NONE" then
                    CFQ.distTick = (CFQ.distTick or 0) + 1
                    if CFQ.distTick >= 3 then
                        CFQ.distTick = 0
                        local anyHovered = false
                        for _, deck in ipairs(trackerStackDeckPool) do
                            if deck:IsShown() and (deck.isHovered or (deck.expandProgress or 0) > 0.02) then
                                anyHovered = true
                                break
                            end
                        end
                        if not anyHovered then
                            LayoutObjectiveTrackerWithStacks()
                            if QuestScrollFrame and QuestScrollFrame:IsShown() and IsQuestLogOverrideActive() then
                                RenderCustomFilteredList()
                            end
                        end
                    end
                end
            end)
        end

        ApplyFilterChanges()
        UpdateShoppingListUI()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- If the player targets a mob whose name matches a quantity objective, mark that quest active locally
        local targetName = UnitName and UnitName("target")
        if targetName and targetName ~= "" then
            local lowerTarget = string.lower(targetName)
            for qID, qData in pairs(questRewardMap) do
                if qData.quantityObjectives then
                    for _, obj in ipairs(qData.quantityObjectives) do
                        if obj.itemName and string.find(string.lower(obj.itemName), lowerTarget, 1, true) then
                            recentActiveQuests[qID] = GetTime()
                        end
                    end
                end
            end
        end
        -- a mob that may drop a tally item, or one you're to slay, sets its line alight (cleared when you change target)
        local hadFire = CFQ.P.fire ~= nil
        local ok, err = pcall(CFQ.OnTargetChanged)
        if not ok then CFQ.P.fire = nil; CFQ.ReportError(err) end
        if (targetName and targetName ~= "") or hadFire or CFQ.P.fire or CFQ.slayLit then
            UpdateShoppingListUI()
        end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        UpdateShoppingListUI()
    elseif event == "SUPER_TRACKING_CHANGED" then
        LayoutObjectiveTrackerWithStacks()
        UpdateShoppingListUI()
        if QuestScrollFrame and QuestScrollFrame:IsShown() and IsQuestLogOverrideActive() then
            RenderCustomFilteredList()
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_WATCH_LIST_CHANGED" or event == "PLAYER_LEVEL_UP" then
        if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
        if not isSyncingTracker then
            ScanQuestLogRewards()
            SyncObjectiveTracker()
            UpdateQuestLogUI(false)
            UpdateShoppingListUI()
            if sharedMenuFrame and sharedMenuFrame:IsShown() then
                RebuildDropdownMenu(sharedMenuFrame, false)
            end
        end
    end
end)
