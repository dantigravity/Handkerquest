-- ============================================================================
-- Handkerquest.lua - WoW Forever Edition
-- "Don't go off on an adventure without your handkerchief." (the name: handkerchief + quest)
-- Objective Tracker sorting, filters & (?)/(•••) quest stacks, plus the Field Tally:
-- a handwritten list (on a handkerchief, parchment or a see-through window) of the quest
-- items still to gather, with a map preview on hover and minimap pins.
--
-- Internal names use the old "Cache ForQuest" prefixes (CFQ, QRF_). Keep them: renaming
-- QRF_SavedState would reset everyone's saved settings.
--
-- WHERE TO MAKE SIMPLE CHANGES (search for the name):
--   Default settings (what's on/off for new players) .... CFQ = { parchmentOpts = ... }
--   Default tally size / position ........................ shoppingListCfg
--   Tally colours, borders and each look ................ P.STYLES
--   Handwriting fonts and their sizes ................... P.FONT_STYLES
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
    ADDON_NAME          = "Handkerquest",
    VERSION             = "2.0.0",
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
-- starts with (each can also be switched in Options > AddOns > Handkerquest).
-- Add new settings to this table rather than as new "local" lines: Lua allows only 200 locals here.
local CFQ = {
    parchmentOpts = {
        showTabs = true,                -- a page for every other area with items to gather
        pagesFollowTracker = true,      -- page radius follows the tracker's (•••) stacking slider
        autoFrontOnAreaChange = true,   -- current-area sheet jumps to the top when you enter a new area
        hideWhenNothingNearby = false,  -- hide the parchment entirely when the current area has nothing to gather
        showTrackerOptionsButton = true,-- gear button above "All Objectives"
        inkEffects = true,              -- tally text glows in an item's hunting grounds / burns for a mob that drops it
        mapPreview = true,              -- hovering a tally item shows a little map of where it's gathered
        minimapPins = true,             -- looted-here spots of the super-tracked quest's items on the minimap
    },
    parchmentFont = "QUILL",            -- handwriting on the parchment: "QUILL", "SCRAWL" or "PLAIN"
    parchmentStyle = "HANDKERCHIEF",    -- the tally's look: "HANDKERCHIEF", "PARCHMENT" or "NATIVE" (transparent window)
    huntSpots = {},                     -- [progKey] = { { m = mapID, x, y, a = subzone }, ... } where the item was looted
    learnedDroppers = {},               -- ["npc:ID"] = { label = name, loots = n, tries = {}, [progKey] = times the item dropped }
    pageRadiusPercent = 16,             -- own page radius (% of the zone map) when not following the tracker
    nearRadiusPercent = 10,             -- "Near me" page: how close (% of the zone map) the items must be
    pageGrouping = "AREA",              -- area pages by "AREA" (map areas), "ZONE" or "RADIUS" (distance)
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
local shoppingListScope = "AREA"    -- no longer used; kept so older saved settings still load
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
local flashObjectiveUntil = {}      -- [questID .. "_" .. objIdx] = GetTime() + 1.8

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
    QRF_SavedState.pageGrouping = CFQ.pageGrouping
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
        end
        if type(QRF_SavedState.learnedQuestAreas) == "table" then
            CFQ.learnedQuestAreas = QRF_SavedState.learnedQuestAreas
        end
        local ps = QRF_SavedState.parchmentStyle
        if ps == "HANDKERCHIEF" or ps == "PARCHMENT" or ps == "NATIVE" then
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
-- "progressbar", "spell", "player", "log", ... Only "item" objectives belong on the tally.
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

-- Extracts structured quantity/collection/kill objectives for the Shopping List
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

            -- Track live tick-ups so the shopping list can flash newly progressed rows
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

            if qData.isComplete then
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
            local itemObjs = {}   -- the subset the parchment tally shows: things you actually collect
            for _, o in ipairs(qtyObjs) do
                if o.isItem then table.insert(itemObjs, o) end
            end

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
-- FIELD TALLY: the handwritten list of quest items still to gather
-- A pile of pages, one per area with items to gather ("Near me" always on top). Gathered items
-- are ticked and struck through until the quest is turned in; the dog-eared corner turns pages.
-- EDIT: P.MAX_AREAS = how many pages at most; INK colours are the defaults before a look applies
--       (the real colours of each look are in P.STYLES further down).
-- ============================================================================
local P = {
    CURRENT_KEY = "__HERE__",
    MAX_AREAS = 8,              -- current area + up to 7 other-area pages
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
-- Each sheet is a body quad plus torn "deckle" strips along all four edges.
-- Vertex offsets give every strip a jagged outer edge and rotate the whole
-- sheet a few degrees (back sheets) without any custom art files.
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
    sheet.body:SetColorTexture(pc[1], pc[2], pc[3], pc[4])
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
    { key = "SCRAWL", label = "Rough scrawl", path = "Fonts\\SKURRI.TTF",   item = 12, title = 14, small = 10 },
    { key = "PLAIN",  label = "Plain print",  path = nil,                   item = 11, title = 12, small = 9 },
}

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

-- Applies the chosen handwriting face; falls back to the standard UI font if the client can't load it
function P.SetInkFont(fs, kind, flags)
    local look = P.GetStyle()
    local st = P.GetFontStyle()
    if look.font then
        for _, f in ipairs(P.FONT_STYLES) do if f.key == look.font then st = f end end
    end
    local cacheKey = st.key .. ":" .. look.key
    if fs.inkKey == cacheKey and fs.inkKind == kind then return end
    local ok = st.path and fs:SetFont(st.path, st[kind] or st.item, flags or "")
    if not st.path or ok == false then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", P.FONT_STYLES[3][kind] or 11, flags or "")
    end
    if fs.SetShadowColor then
        if look.textShadow then
            fs:SetShadowColor(0, 0, 0, 1)                 -- UI text: the usual drop shadow
            if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        else
            fs:SetShadowColor(0, 0, 0, 0)                 -- ink doesn't cast drop shadows
        end
    end
    fs.inkKey, fs.inkKind = cacheKey, kind
end

-- ----------------------------------------------------------------------------
-- LOOKS: handkerchief notes (default), the parchment pile, or a see-through WoW window
-- Every colour the tally draws with comes from here.
-- EDIT: colours are { red, green, blue, opacity } from 0 to 1. Per look:
--   paper = the sheet, back = the pages underneath, ink / inkRed / inkGreen = writing, counts and
--   "(turn in)", title / footer / faded = heading, footer and ticked-off items, hem = the
--   handkerchief border, cloth = its lace edge (scallop = size of each scallop), pad = space
--   between the edge and the writing. To make a different look the default, change
--   parchmentStyle near the top of the file to that look's key.
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
        textShadow = true, font = "PLAIN", name = { 0.95, 0.95, 0.95 },
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

-- Repaints the whole pile and its chrome for the current look
function P.ApplyStyle(f)
    f = f or shoppingListFrame
    if not f then return end
    local st = P.GetStyle()
    P.INK, P.INK_RED, P.INK_GREEN = st.ink, st.inkRed, st.inkGreen
    f.styleKey = st.key

    local cl = st.cloth
    P.RestyleSheet(f.shadowSheet, { paper = { 0, 0, 0, st.shadowAlpha or 0 }, depth = st.depth + 0.5, minDepth = 1, segW = 14, overlap = 0,
        cloth = cl and { radius = cl.radius + 1 } or nil })      -- a soft rounded shadow, no lace
    for k, sh in ipairs(f.backSheets) do
        local bp = st.back[k]
        P.RestyleSheet(sh, { paper = bp, rim = st.backRim, depth = st.backDepth, minDepth = st.backMinDepth, segW = st.backSegW,
            cloth = cl and { radius = cl.radius, scallop = cl.scallop, step = cl.step, ripple = cl.ripple,
                lace = { math.min(1, bp[1] * 1.03), math.min(1, bp[2] * 1.03), math.min(1, bp[3] * 1.03), bp[4] },
                thread = st.backThread } or nil })
    end
    P.RestyleSheet(f.topSheet, {
        paper = st.paper, rim = st.rim, depth = st.depth, minDepth = st.minDepth, segW = st.segW,
        grain = st.grain, shade = st.shade, hem = st.hem, cloth = cl,
    })
    if f.corner then
        -- on cloth the folded corner sits inside the rounded corner instead of poking past it
        local ci = st.cornerInset or 0
        f.corner:ClearAllPoints()
        f.corner:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", 3 - ci, -3 + ci)
    end
    f.shadowSheet:SetShown((st.shadowAlpha or 0) > 0)

    local cc = st.close
    if f.closeBtn then f.closeBtn.txt:SetTextColor(cc[1], cc[2], cc[3]) end
    if f.optBtn then
        f.optBtn.iconColor = { st.gear[1], st.gear[2], st.gear[3] }
        CFQ.SetGearHover(f.optBtn, false)
    end
    if f.gripTex then f.gripTex:SetVertexColor(st.grip[1], st.grip[2], st.grip[3], st.grip[4]) end

    -- keep the writing off the handkerchief's hem
    local pad = st.pad or 0
    f.pad = pad
    if f.closeBtn then
        f.closeBtn:ClearAllPoints()
        f.closeBtn:SetPoint("TOPRIGHT", f.chrome, "TOPRIGHT", -5 - pad, -5 - pad)
    end
    if f.titleFS then
        f.titleFS:ClearAllPoints()
        f.titleFS:SetPoint("TOPLEFT", f.chrome, "TOPLEFT", 10 + pad, -6 - pad)
        f.titleFS:SetPoint("RIGHT", f.optBtn, "LEFT", -4, 0)
    end
    if f.content then
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT", f.chrome, "TOPLEFT", 6 + pad, -28 - pad)
        f.content:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", -6 - pad, 17 + pad)
    end
    if f.footerFS then
        f.footerFS:ClearAllPoints()
        f.footerFS:SetPoint("BOTTOMLEFT", f.chrome, "BOTTOMLEFT", 22 + pad, 5 + pad)
        f.footerFS:SetPoint("BOTTOMRIGHT", f.chrome, "BOTTOMRIGHT", -30 - pad, 5 + pad)
        f.footerFS:SetTextColor(st.footer[1], st.footer[2], st.footer[3], 0.95)
    end
    if f.corner then f.corner.drawnKey = nil; P.DrawCorner(f.corner) end
    P.ApplyStackLayout(f)
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
    s.bleed:SetThickness(thick + 1.0)
    s.bleed:SetColorTexture(ink[1], ink[2], ink[3], alpha * 0.25)
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
-- Built from 1px scanline strips so it needs no art files or vertex offsets:
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

function P.DrawCorner(c)
    local S = math.max(2, math.min(P.CORNER_MAX, c.size or P.CORNER_REST))
    local key = math.floor(S * 4 + 0.5)
    if c.drawnKey == key then return end
    c.drawnKey = key

    local ox = P.CORNER_MAX - S              -- the active corner sits in the bottom-right of the button
    local lift = (S - P.CORNER_REST) / (P.CORNER_HOVER - P.CORNER_REST)   -- 0 at rest, 1 fully lifted
    if lift < 0 then lift = 0 elseif lift > 1 then lift = 1 end
    local n = math.floor(S + 0.5)
    local cs = P.GetStyle().corner
    local u1, u2, tip, cr = cs.u1, cs.u2, cs.tip, cs.crease
    local tipK = 1 - 0.06 * lift
    for j = 1, P.CORNER_MAX do
        local under, flap = c.under[j], c.flap[j]
        if j <= n then
            local y = -(ox + j - 1)
            local cut = S - (j - 0.5)              -- where the fold line crosses this row
            if cut < 0 then cut = 0 end
            local uw = S - cut
            under:ClearAllPoints()
            under:SetPoint("TOPLEFT", c, "TOPLEFT", ox + cut, y)
            under:SetSize(math.max(0.5, uw), 1)
            -- the page beneath, darkened right under the fold where the flap shades it
            P.HGradient(under, u1[1], u1[2], u1[3], 1, u2[1], u2[2], u2[3], 1)
            under:Show()

            if cut > 0.4 then
                flap:ClearAllPoints()
                flap:SetPoint("TOPLEFT", c, "TOPLEFT", ox, y)
                flap:SetSize(cut, 1)
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
            GameTooltip:AddLine(string.format("Next: %s  (%d to gather)", nxt.title or "Elsewhere", nxt.remaining or 0), 0.9, 0.9, 0.9)
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
    if multi then P.DrawCorner(f.corner) end
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
    for k = 1, P.MAX_BACK_SHEETS do
        local s = f.backSheets[k]
        if k <= visible then
            local slot = P.BACK_SLOTS[k]
            local sign = (k % 2 == 0) and -1 or 1
            s:Show()
            s:Layout(w, h, slot.angle + wob * 0.02 * sign, slot.dx - pulse * dir * 3 * k, slot.dy)
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
-- target is something that drops it, and a red ink circle round the item shown on the map
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
        GameTooltip:AddLine("Bring it back in Handkerquest Options (gear above the tracker) or with /hanky list", 0.85, 0.85, 0.85, true)
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

    -- Options gear -> Handkerquest options panel
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
        GameTooltip:AddLine("Handkerquest Options", 1, 0.82, 0)
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

    -- Page heading (area name) in handwriting, with a quill-ruled underline
    local titleFS = chrome:CreateFontString(nil, "OVERLAY")
    P.SetInkFont(titleFS, "title")
    titleFS:SetPoint("TOPLEFT", chrome, "TOPLEFT", 10, -6)
    titleFS:SetPoint("RIGHT", optBtn, "LEFT", -4, 0)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
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
-- Which item quests are "near me" (within the proximity radius, or just worked on), plus every
-- eligible item quest so the rest can be filed onto area pages.
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
        if not qData.isFromMap and qData.itemObjectives and #qData.itemObjectives > 0 and DoesQuestMatchFilter(qID) then
            table.insert(eligible, qData)
            local near, learnHere = false, false

            -- 1) Distance from you to where the items are gathered (same map only)
            local comparable = playerMapID and px and py and qData.mapID == playerMapID and qData.x and qData.y
            qData.playerDist = nil
            if comparable then
                local dx, dy = px - qData.x, py - qData.y
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
                local isSameZone = (realZone ~= "" and (lowerHeader == realZone
                    or string.find(realZone, lowerHeader, 1, true) or string.find(lowerHeader, realZone, 1, true)))
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

function P.FlattenQuests(quests)
    local items = {}
    local doneCount = 0
    for _, qData in ipairs(quests) do
        for _, obj in ipairs(qData.itemObjectives or {}) do
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
            })
        end
    end
    return items, doneCount
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

-- "Near me" radius (% of the zone map): how close you must be to where a quest's items are gathered
function P.GetNearRadius()
    return CFQ.nearRadiusPercent or 10
end

-- ----------------------------------------------------------------------------
-- AREA PAGE NAMES
-- ----------------------------------------------------------------------------
P.GROUPINGS = {
    { key = "AREA",   label = "Map areas" },   -- the explored subzone the items are in (world-map area names)
    { key = "ZONE",   label = "Zones" },       -- one page per zone
    { key = "RADIUS", label = "Distance" },    -- clusters by the Area page size slider
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
    -- Page 1 is always "Near me": what you can gather from where you stand
    local current = { key = P.CURRENT_KEY, title = "Near me", subtitle = here, isCurrent = true, quests = {} }
    local areas = { current }

    local rest = {}
    for _, q in ipairs(eligible) do
        if nearSet[q.questID] then
            table.insert(current.quests, q)
        elseif not q.isComplete then        -- area pages only carry what still needs gathering
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
    local pad = st.pad or 0

    -- Heading: fresh red ink for a few seconds after you arrive in a new area
    P.SetInkFont(f.titleFS, "title")
    P.SetInkFont(f.footerFS, "small")
    local title = area.title or (area.isCurrent and "Field Tally" or "Elsewhere")
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
    local ruleW = math.min(w - 20 - 2 * pad, math.max(60, (f.titleFS:GetStringWidth() or 80) + 22))
    P.DrawStroke(f.titleRule, f.chrome, 8 + pad, -25 - pad, 8 + pad + ruleW, -24 - pad, 1.2, 0.70)
    P.DrawStroke(f.titleRule2, f.chrome, 14 + pad, -27.5 - pad, 8 + pad + ruleW * 0.55, -27 - pad, 0.7, 0.40)

    if #items == 0 then
        local row = AcquireShoppingListRow(1, f.content)
        P.StyleRow(row)
        P.SetRowFX(row, nil)
        P.SetRowLasso(row, false)
        row.box:Hide()
        P.HideStrikes(row)
        row.suffixText:Hide()
        P.SetInkFont(row.itemText, "item")
        row.itemText:SetWidth(math.max(120, w - 30 - 2 * pad))
        row.itemText:SetTextColor(st.faded[1], st.faded[2], st.faded[3], 1)
        row.itemText:SetText((area.isCurrent and "Nothing to gather near you." or "Nothing left to gather here.") ..
            ((pageCount > 1) and "\nTurn the page corner to see other areas." or ""))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -2)
        row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -2)
        row:SetHeight(36)
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

    local contentW = math.max(150, w - 12 - 2 * pad)
    local contentH = math.max(55, (f:GetHeight() or 175) - 45 - 2 * pad)
    local yCursor = 0
    local shownRows = 0
    P.SetInkFont(f.measureFS, "item")
    local huntCtx = CFQ.BuildHuntContext()
    local countHex, nameHex = P.Hex(st.inkRed), P.Hex(st.name or st.ink)
    local trackedID = P.GetSuperTrackedID()

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
        local countStr = string.format("%d/%d", entry.numFulfilled or 0, entry.numRequired or 1)
        local nameStr = entry.itemName or ""
        local strH

        local wa = st.wash
        if entry.finished then
            P.ShowTick(row.box, row.seed)
            row.box.wash:SetColorTexture(wa[1], wa[2], wa[3], wa[4])

            -- Faded ink, wrapped by hand so every line gets a strike exactly as long as its words
            local lines, widths = P.WrapLines(f.measureFS, countStr .. "  " .. nameStr, textW)
            row.itemText:SetTextColor(st.faded[1], st.faded[2], st.faded[3], 1)
            row.itemText:SetText(table.concat(lines, "\n"))
            strH = math.max(14, math.ceil(row.itemText:GetStringHeight() or 14))
            local lineH = strH / #lines
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
            row.itemText:SetText(string.format("|c%s%s|r  |c%s%s|r", countHex, countStr, nameHex, nameStr))
            strH = math.max(14, math.ceil(row.itemText:GetStringHeight() or 14))
        end

        -- glow in its hunting grounds, flames when your target drops it, red ink circle round the
        -- items of the quest you're tracking
        local fxMode = CFQ.GetItemFXMode(entry, huntCtx)
        P.SetRowFX(row, fxMode, countStr .. "  " .. nameStr, textW, entry.progKey)
        P.SetRowLasso(row, trackedID ~= nil and trackedID == entry.questID)

        local rowH = strH + 7

        if (math.abs(yCursor) + rowH) > (contentH + 4) and shownRows > 0 then
            row:Hide()
            break
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
            GameTooltip:AddLine(string.format("%s: %d / %d", entry.itemName or "Objective", entry.numFulfilled or 0, entry.numRequired or 1), 0.9, 0.9, 0.9)
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

    local doneCount = area.doneCount or 0
    if #items > shownRows then
        f.footerFS:SetText(string.format("%d of %d gathered  ·  %d-%d shown%s",
            doneCount, #items, shoppingScrollOffset + 1, shoppingScrollOffset + shownRows, pageStr))
    else
        f.footerFS:SetText(string.format("%d of %d gathered%s", doneCount, #items, pageStr))
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

    local anyItems = false
    for _, a in ipairs(areas) do
        if #a.items > 0 then anyItems = true break end
    end
    if not anyItems or (#current.items == 0 and (#areas == 1 or CFQ.parchmentOpts.hideWhenNothingNearby)) then
        f:Hide()
        return
    end

    -- one page per area: the pile under the top page shows how many other pages there are
    -- (the see-through window has no pile; its footer still reads "page n of m")
    f.visibleBackSheets = P.GetStyle().pile and math.max(0, math.min(#areas - 1, P.MAX_BACK_SHEETS)) or 0
    f:Show()
    P.Render(f)
    P.UpdateCorner(f)
    P.ApplyStackLayout(f)
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
-- record, per npc id: how many of its corpses you looted while you still needed items ("loots"),
-- and how many times each tally item was in the loot ([progKey] = hits). Hits make a mob a sure
-- dropper; many loots and no hit rule a mob out even if its name looks right.
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

function CFQ.GetItemFXMode(entry, ctx)
    if not CFQ.parchmentOpts.inkEffects or entry.finished then return nil end
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
    -- spots you looted in: amber. The quest's objective area: the tally's red ink.
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

-- moves with you: refreshed a few times a second while a tracked quest has known spots
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
        handler("Handkerquest: " .. msg)
    else
        print("|cFFFF5555Handkerquest error:|r " .. msg)
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
    local out = function(s) print("|cFFFFD100CFQ|r " .. s) end
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

-- /hanky items: every counted objective, its type, and whether it is on the tally (for "why is X listed?")
function CFQ.DebugDumpItems()
    print("|cFFFFD100Handkerquest items:|r objectives with counts (+ = on the Field Tally)")
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
-- BUTTON LABELS & QUEST LOG CURRENCY LINE ALIGNMENT BELOW OBJECTIVES
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
    optionsRow.label:SetText("|cFFFFD100Handkerquest Options...|r |cFF888888(parchment & more)|r")
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
    if not CFQ.ApplyGearIcon(optBtn, 0.85, 0.70, 0.30, "CfQ", 10) then
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
        self.label:SetText("|cFFFFD100Handkerquest|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Handkerquest Options", 1, 0.82, 0)
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

function CFQ.BuildOptionsPanel()
    if CFQ.optionsPanel then return CFQ.optionsPanel end

    local p = CreateFrame("Frame", "QRF_OptionsPanel")
    p.name = CONFIG.ADDON_NAME
    p:Hide()
    local y = -16

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
    title:SetText(CONFIG.ADDON_NAME .. " |cFF888888v" .. CONFIG.VERSION .. "|r")
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

    local function Check(label, tip, getFn, setFn)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
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
        "The checklist of quest items you still need to gather around you.",
        function() return showShoppingList end,
        function(v) showShoppingList = v; RefreshParchment() end)
    -- Radius slider row: label, 1-50% slider, value, hint. get() returns the value; set(v) applies it.
    local function RadiusSlider(labelText, tipTitle, tipBody, get, set, hintFn, enabledFn)
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
        slider:SetMinMaxValues(1, 50)
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
            fill:SetWidth(math.max(1, (v - 1) / 49 * 168))
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

    -- "Near me" (page 1): how close you must be to where the items are gathered
    CFQ.nearRadiusRow = RadiusSlider("Near me distance", "Near me distance",
        "Page 1 lists quest items gathered within this distance of where you're standing (as % of the zone map), plus anything you've progressed in the last few minutes.",
        function() return P.GetNearRadius() end,
        function(v) CFQ.nearRadiusPercent = v; SaveState(); RefreshParchment() end)

    Check("Pages for other areas",
        "Each area with items still to gather gets its own page in the pile. Click the dog-eared corner to turn to the next page (right-click to go back).",
        function() return CFQ.parchmentOpts.showTabs end,
        function(v) CFQ.parchmentOpts.showTabs = v; RefreshParchment() end)

    -- How area pages (page 2+) are divided up
    local groupBtn = Button("Area pages by: Map areas", 210, 48, function()
        P.CycleGrouping()
        shoppingScrollOffset = 0
        SaveState()
        RefreshParchment()
    end, function(self)
        self:SetText("Area pages by: " .. P.GetGrouping().label)
        self:SetAlpha(CFQ.parchmentOpts.showTabs and 1 or 0.45)
    end)
    groupBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Area pages by", 1, 0.82, 0)
        GameTooltip:AddLine("Map areas: one page per explored subzone your quest items are in (the names on your world map).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Zones: one page per zone.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Distance: quests near each other share a page, sized by the Area page size slider below.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Pages with the same name are always merged.", 0.55, 0.85, 0.55, true)
        GameTooltip:Show()
    end)
    groupBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 30

    local function DistanceMode() return CFQ.parchmentOpts.showTabs and P.GetGrouping().key == "RADIUS" end
    local followCb = Check("Area page size follows the tracker's (•••) stacking slider",
        "Distance grouping only. On: quests within the same radius you use for (•••) stacks in the Objective Tracker share a page. Off: set the area page size yourself below.",
        function() return CFQ.parchmentOpts.pagesFollowTracker end,
        function(v) CFQ.parchmentOpts.pagesFollowTracker = v; RefreshParchment() end)
    local baseRefresh = followCb.Refresh
    followCb.Refresh = function(self)
        baseRefresh(self)
        self:SetAlpha(DistanceMode() and 1 or 0.45)
    end


    -- Area pages (page 2+): how far apart quests can be and still share a page
    CFQ.pageRadiusRow = RadiusSlider("Area page size", "Area page size",
        "Distance grouping only. Quests whose items lie within this distance of each other (as % of the zone map) share an area page. Smaller = more, tighter pages.",
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
    Check("Hide the parchment when nothing is nearby",
        "Off: the pile stays up so you can leaf through other areas. On: it only appears when the area you're in has something to gather.",
        function() return CFQ.parchmentOpts.hideWhenNothingNearby end,
        function(v) CFQ.parchmentOpts.hideWhenNothingNearby = v; RefreshParchment() end)

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

    y = y - 4
    local lookBtn = Button("Look: Handkerchief notes", 210, 24, function()
        P.CycleStyle()
        SaveState()
        P.ApplyStyle()
        RefreshParchment()
    end, function(self)
        self:SetText("Look: " .. P.GetStyle().label)
    end)
    lookBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Look of the Field Tally", 1, 0.82, 0)
        GameTooltip:AddLine("Handkerchief notes: scribbled on a hemmed, folded handkerchief.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Parchment: a pile of torn parchment pages.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Transparent window: a see-through WoW-style panel in the standard font.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    lookBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 28
    Button("Handwriting: Quill script", 190, 24, function()
        P.CycleFontStyle()
        SaveState()
        RefreshParchment()
    end, function(self)
        self:SetText("Handwriting: " .. P.GetFontStyle().label)
        self:SetAlpha(P.GetStyle().font and 0.45 or 1)     -- the see-through window always uses the UI font
    end)
    Button("Reset Position & Size", 160, 220, function()
        showShoppingList = true
        ResetShoppingListPosition()
    end)
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
        "Off: the level and rewards appear in the pin's tooltip instead.",
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

    p:SetScript("OnShow", function() CFQ.RefreshOptionsPanel() end)
    CFQ.optionsPanel = p
    CFQ.optionsPanelHeight = math.abs(y) + 30
    return p
end

function CFQ.RegisterOptions()
    if CFQ.optionsRegistered then return end
    CFQ.optionsRegistered = true
    local p = CFQ.BuildOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, p, CONFIG.ADDON_NAME)
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
        host:SetSize(520, (CFQ.optionsPanelHeight or 560) + 10)
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
            print("|cFFFFD100Handkerquest:|r options will open after combat.")
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
        showShoppingList = not showShoppingList
        UpdateShoppingListUI()
        SaveState()
        CFQ.RefreshOptionsPanel()
    elseif cmd == "resetlist" then
        showShoppingList = true
        ResetShoppingListPosition()
        CFQ.RefreshOptionsPanel()
    elseif cmd == "debug" then
        CFQ.DebugDumpTracker()
    elseif cmd == "items" then
        CFQ.DebugDumpItems()
    elseif cmd == "look" or cmd == "style" or string.find(cmd, "^look ") or string.find(cmd, "^style ") then
        local want = string.match(cmd, "^%a+%s+(%a+)")
        local alias = { handkerchief = "HANDKERCHIEF", hanky = "HANDKERCHIEF", parchment = "PARCHMENT",
            window = "NATIVE", transparent = "NATIVE", native = "NATIVE" }
        if want and alias[want] then CFQ.parchmentStyle = alias[want] else P.CycleStyle() end
        SaveState()
        P.ApplyStyle()
        UpdateShoppingListUI()
        CFQ.RefreshOptionsPanel()
        print("|cFFFFD100Handkerquest:|r Field Tally look: " .. P.GetStyle().label)
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
loader:RegisterEvent("LOOT_OPENED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
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

        -- Lightweight 1.2s proximity ticker so the Shopping List updates as you walk into/out of quest hubs
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
        -- a mob that may drop a tally item sets its line alight (cleared when you change target)
        local hadFire = CFQ.P.fire ~= nil
        local ok, err = pcall(CFQ.OnTargetChanged)
        if not ok then CFQ.P.fire = nil; CFQ.ReportError(err) end
        if (targetName and targetName ~= "") or hadFire or CFQ.P.fire then
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