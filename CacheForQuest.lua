-- ============================================================================
-- CacheForQuest.lua (v1.2.0 - WoW Forever Edition)
-- Fixed Tracker Block/Filter Layout + Collapse-Delayed Stack Top Promotion
-- + Dynamic Parchment "Shopping List" for Local Cluster Quantity Quests
-- v1.2.0: Single-button lvl / dist cycle sorts, filter-menu Reset, stack toggle
--         no longer drops quests, rough-cut parchment sheet stack with physics
--         ribbon area tabs, chat-side default position, Cache ForQuest options
--         panel (parchment gear, tracker gear, Options > AddOns).
-- ============================================================================
local CONFIG = {
    ADDON_NAME          = "Cache ForQuest",
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

-- Namespaced state for v1.2 features (keeps the main chunk well under Lua's 200-local limit)
local CFQ = {
    parchmentOpts = {
        showTabs = true,                -- ribbon tabs for other areas
        ribbonPhysics = true,           -- ribbons sway when dragged / resized / selected
        autoFrontOnAreaChange = true,   -- current-area sheet jumps to the top when you enter a new area
        hideWhenNothingNearby = false,  -- hide the parchment entirely when the current area has nothing to gather
        showTrackerOptionsButton = true,-- gear button above "All Objectives"
    },
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

local showShoppingList = true       -- Dynamic Parchment Shopping List for local quantity quests
local shoppingListScope = "AREA"    -- "AREA" (Local radius/cluster), "ZONE" (Current zone), or "ALL"
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
-- (v1.2 forward declarations live on CFQ: CFQ.OpenOptions, CFQ.RefreshSortButtons,
--  CFQ.UpdateQuestDistances, CFQ.UpdateTrackerOptionsButton, CFQ.RefreshOptionsPanel)

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
    QRF_SavedState.shoppingListCfg = shoppingListCfg
    QRF_SavedState.lastSelectedQuestID = lastSelectedQuestID
    QRF_SavedState.distSortMode = distSortMode
    QRF_SavedState.primarySortKey = primarySortKey
    QRF_SavedState.parchmentOpts = CFQ.parchmentOpts
    QRF_SavedState.learnedQuestAreas = CFQ.learnedQuestAreas
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
        if QRF_SavedState.shoppingListScope then shoppingListScope = QRF_SavedState.shoppingListScope end
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
                -- v1.1 save: only migrate to the new chat-side default if the list was never moved
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
-- (current count missing), which is what produced the redundant "0/6 /6 Gnarlpine Ambusher slain".
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
            local prevCur = prevObjectiveProgress[progKey]
            if prevCur ~= nil and cur > prevCur then
                flashObjectiveUntil[progKey] = GetTime() + 2.0
                recentActiveQuests[questID] = GetTime()
            end
            prevObjectiveProgress[progKey] = cur

            table.insert(results, {
                index = idx,
                progKey = progKey,
                text = cleanText,
                itemName = itemName,
                numFulfilled = cur,
                numRequired = max,
                finished = isDone,
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
-- DYNAMIC PARCHMENT "SHOPPING LIST" FOR CLUSTER QUANTITY / COLLECTION QUESTS
-- Checks off & crosses out completed items with an ink line until turned in!
-- v1.2: a stack of rough-cut parchment sheets (one per area) with hanging
--       ribbon tabs that sway when the stack is dragged, resized or shuffled.
-- ============================================================================
local P = {
    CURRENT_KEY = "__HERE__",
    MAX_AREAS = 6,              -- current area + up to 5 other-area sheets
    MAX_BACK_SHEETS = 3,
    RIBBON_N = 5,               -- ribbon segments (root -> swallowtail)
    RIBBON_W = 15,
    RIBBON_REST  = { 0.05, 0.11, 0.42, 0.80, 1.10 },   -- radians below horizontal (progressive droop)
    RIBBON_K     = { 170, 140, 85, 58, 42 },           -- stiffer near the root, floppier at the tail
    RIBBON_LEVER = { 0.35, 0.60, 1.00, 1.35, 1.60 },
    RIBBON_COLORS = {
        { 0.58, 0.11, 0.09 },   -- oxblood (always the current area)
        { 0.14, 0.27, 0.55 },   -- lapis
        { 0.16, 0.42, 0.19 },   -- forest
        { 0.42, 0.17, 0.50 },   -- royal purple
        { 0.64, 0.42, 0.09 },   -- ochre
        { 0.09, 0.42, 0.44 },   -- teal
        { 0.50, 0.25, 0.12 },   -- umber
    },
    BACK_SLOTS = {
        { angle =  0.026, dx =  2, dy = -3 },
        { angle = -0.040, dx = -3, dy = -6 },
        { angle =  0.055, dx =  4, dy = -9 },
    },
    ribbonPool = {},
    ribbonByKey = {},
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

    PQ(sheet, sheet.body, -hw, -hh, hw, hh)
    if sheet.grain then PQ(sheet, sheet.grain, -hw, -hh, hw, hh) end
    if sheet.shadeTop then
        PQ(sheet, sheet.shadeTop, -hw, hh - 20, hw, hh)
        PQ(sheet, sheet.shadeBot, -hw, -hh, hw, -hh + 14)
        PQ(sheet, sheet.shadeL, -hw, -hh, -hw + 9, hh)
        PQ(sheet, sheet.shadeR, hw - 9, -hh, hw, hh)
    end

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

function P.CreateSheet(parent, seed, opts)
    local sheet = CreateFrame("Frame", nil, parent)
    sheet:SetAllPoints(parent)
    sheet.seed = seed
    sheet.opts = opts
    sheet.cosA, sheet.sinA = 1, 0
    sheet.segs = { {}, {} }

    sheet.body = sheet:CreateTexture(nil, "BACKGROUND", nil, 3)
    sheet.body:SetColorTexture(opts.paper[1], opts.paper[2], opts.paper[3], opts.paper[4])

    if opts.grain then
        sheet.grain = sheet:CreateTexture(nil, "BACKGROUND", nil, 4)
        sheet.grain:SetTexture("Interface\\QuestFrame\\UI-QuestGreeting-TopLeft")
        sheet.grain:SetTexCoord(0.10, 0.70, 0.25, 0.75)
        sheet.grain:SetVertexColor(1.0, 0.94, 0.80, 0.30)
    end
    if opts.shade then
        sheet.shadeTop = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        ApplyTwoColorVerticalGradient(sheet.shadeTop, 0.42, 0.28, 0.12, 0.0, 0.35, 0.22, 0.08, 0.34)
        sheet.shadeBot = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        ApplyTwoColorVerticalGradient(sheet.shadeBot, 0.35, 0.22, 0.08, 0.30, 0.42, 0.28, 0.12, 0.0)
        sheet.shadeL = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        ApplyHorizontalGradient(sheet.shadeL, 0.36, 0.23, 0.09, 0.26, 0.0)
        sheet.shadeR = sheet:CreateTexture(nil, "BACKGROUND", nil, 5)
        ApplyHorizontalGradient(sheet.shadeR, 0.36, 0.23, 0.09, 0.0, 0.26)
    end

    sheet.Layout = P.LayoutSheet
    return sheet
end

-- ----------------------------------------------------------------------------
-- POSITIONING (default: just above the chat box, left side of the screen)
-- ----------------------------------------------------------------------------
function P.ComputeDefaultAnchor()
    local cf = ChatFrame1
    if cf and cf.GetLeft and cf:GetLeft() and cf:GetTop() then
        local ratio = (cf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local left = cf:GetLeft() * ratio
        local top = cf:GetTop() * ratio
        -- +32 clears the chat tabs that sit on top of the chat frame
        return math.floor(left + 0.5), math.floor(top + 32 + 0.5)
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
        P.UpdateRibbonSide(shoppingListFrame, true)
    end
    SaveState()
    if UpdateShoppingListUI then UpdateShoppingListUI() end
end
CFQ.ResetShoppingListPosition = ResetShoppingListPosition

-- ----------------------------------------------------------------------------
-- HANGING RIBBON TABS (one per area) WITH ANGULAR-SPRING PHYSICS
-- ----------------------------------------------------------------------------
function P.SetLine(ln, r, x0, y0, x1, y1)
    ln:SetStartPoint("CENTER", r, x0, y0)
    ln:SetEndPoint("CENTER", r, x1, y1)
end

function P.ResetRibbonPhysics(r)
    for i = 1, P.RIBBON_N do
        r.ang[i] = P.RIBBON_REST[i]
        r.vel[i] = 0
    end
    r.prevX, r.prevY, r.prevVX, r.prevVY = nil, nil, 0, 0
    r.ax, r.ay = 0, 0
    r.atRest = false
    r.dirty = true
end

function P.KickRibbon(r, amount)
    if not r or not r.inUse then return end
    for i = 1, P.RIBBON_N do
        r.vel[i] = (r.vel[i] or 0) + amount * (0.5 + 0.25 * i)
    end
    r.atRest = false
    r.dirty = true
end

function P.AcquireRibbon(f)
    for _, r in ipairs(P.ribbonPool) do
        if not r.inUse then
            r.inUse = true
            return r
        end
    end

    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local W = P.RIBBON_W
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(1, 1)
    r.inUse = true
    r.ang, r.vel, r.lens, r.pts = {}, {}, {}, {}
    for i = 0, P.RIBBON_N do r.pts[i] = { 0, 0 } end
    r.lines = { shadow = {}, glow = {}, edge = {}, main = {}, sheen = {}, jEdge = {}, jMain = {}, pEdge = {}, pMain = {} }

    local function NewLine(list, layer, sub, thick)
        local ln = r:CreateLine(nil, layer, nil, sub)
        ln:SetThickness(thick)
        table.insert(list, ln)
    end
    for _ = 1, P.RIBBON_N do
        NewLine(r.lines.shadow, "BACKGROUND", 0, W + 1)
        NewLine(r.lines.glow, "BACKGROUND", 1, W + 9)
        NewLine(r.lines.edge, "ARTWORK", 0, W)
        NewLine(r.lines.main, "ARTWORK", 1, W - 3)
        NewLine(r.lines.sheen, "ARTWORK", 3, 2)
    end
    for _ = 1, P.RIBBON_N - 1 do
        NewLine(r.lines.jEdge, "ARTWORK", 0, W)
        NewLine(r.lines.jMain, "ARTWORK", 2, W - 3)
    end
    for _ = 1, 2 do
        NewLine(r.lines.pEdge, "ARTWORK", 0, W * 0.5 + 1)
        NewLine(r.lines.pMain, "ARTWORK", 1, W * 0.5 - 1.5)
    end
    for _, ln in ipairs(r.lines.shadow) do ln:SetColorTexture(0, 0, 0, 0.32) end

    -- Brass tack pinning the selected ribbon onto the top sheet
    r.tackRim = r:CreateTexture(nil, "OVERLAY", nil, 1)
    r.tackRim:SetSize(8, 8)
    r.tackRim:SetColorTexture(0.18, 0.10, 0.02, 1)
    r.tack = r:CreateTexture(nil, "OVERLAY", nil, 2)
    r.tack:SetSize(5.5, 5.5)
    r.tack:SetColorTexture(0.95, 0.77, 0.26, 1)
    for _, t in ipairs({ r.tackRim, r.tack }) do
        local m = r:CreateMaskTexture()
        m:SetAllPoints(t)
        m:SetTexture(CIRCLE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        t:AddMaskTexture(m)
    end

    r.text = r:CreateFontString(nil, "OVERLAY", nil, 4)
    r.text:SetFont(fontPath, 10, "")
    r.text:SetShadowOffset(1, -1)
    r.text:SetShadowColor(0, 0, 0, 0.9)
    r.text:SetWordWrap(false)

    r.btn = CreateFrame("Button", nil, f)
    r.btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.btn.ribbon = r
    r.btn:SetScript("OnClick", function(self)
        if self.ribbon.key then P.SelectArea(self.ribbon.key, true) end
    end)
    r.btn:SetScript("OnEnter", function(self) P.OnRibbonEnter(self.ribbon, self) end)
    r.btn:SetScript("OnLeave", function(self)
        self.ribbon.hover = false
        P.ApplyRibbonColors(self.ribbon)
        GameTooltip:Hide()
    end)

    P.ResetRibbonPhysics(r)
    table.insert(P.ribbonPool, r)
    return r
end

function P.ApplyRibbonColors(r)
    local c = r.color or P.RIBBON_COLORS[1]
    local m = r.isSelected and 1.15 or 0.78
    if r.hover then m = m + 0.18 end
    local cr, cg, cb = math.min(1, c[1] * m), math.min(1, c[2] * m), math.min(1, c[3] * m)
    local L = r.lines
    for _, ln in ipairs(L.main) do ln:SetColorTexture(cr, cg, cb, 1) end
    for _, ln in ipairs(L.jMain) do ln:SetColorTexture(cr, cg, cb, 1) end
    for _, ln in ipairs(L.pMain) do ln:SetColorTexture(cr, cg, cb, 1) end
    for _, ln in ipairs(L.edge) do ln:SetColorTexture(cr * 0.45, cg * 0.45, cb * 0.45, 1) end
    for _, ln in ipairs(L.jEdge) do ln:SetColorTexture(cr * 0.45, cg * 0.45, cb * 0.45, 1) end
    for _, ln in ipairs(L.pEdge) do ln:SetColorTexture(cr * 0.45, cg * 0.45, cb * 0.45, 1) end
    for _, ln in ipairs(L.sheen) do
        ln:SetColorTexture(math.min(1, cr * 1.6 + 0.10), math.min(1, cg * 1.6 + 0.10), math.min(1, cb * 1.6 + 0.10), 0.35)
    end
    if r.isSelected then
        r.text:SetTextColor(1.0, 0.95, 0.80, 1)
        r.tack:Show()
        r.tackRim:Show()
    else
        r.text:SetTextColor(0.90, 0.84, 0.70, 0.95)
        r.tack:Hide()
        r.tackRim:Hide()
    end
end

function P.AnchorRibbon(r, f)
    local s = f.ribbonSide or 1
    r.side = s
    r:ClearAllPoints()
    if s > 0 then
        r:SetPoint("CENTER", f, "TOPRIGHT", -8, r.rootY or -30)
    else
        r:SetPoint("CENTER", f, "TOPLEFT", 8, r.rootY or -30)
    end
end

function P.RibbonTargetY(f, slotIndex, slotCount)
    local h = f:GetHeight() or 175
    local spacing = math.max(12, math.min(19, (h - 44) / math.max(1, slotCount)))
    return -30 - (slotIndex - 1) * spacing
end

function P.ConfigureRibbon(r, f, area, slotIndex, slotCount, isSelected)
    r.key = area.key
    r.area = area
    r.isSelected = isSelected
    r.color = area.color
    r.slotIndex, r.slotCount = slotIndex, slotCount
    r.glowUntil = area.isCurrent and (P.currentGlowUntil or 0) or 0

    local title = area.title or "Area"
    if string.len(title) > 22 then title = string.sub(title, 1, 20) .. ".." end
    local label = (area.remaining or 0) > 0 and string.format("%s |cFFFFE7A0%d|r", title, area.remaining) or title
    if r.label ~= label then
        r.label = label
        r.text:SetText(label)
        local tw = math.min(120, math.max(24, r.text:GetStringWidth() or 40))
        r.textW = tw
        r.lens[1] = 8 + tw * 0.5 + 7
        r.lens[2] = tw * 0.5 + 9
        r.lens[3] = 13
        r.lens[4] = 11
        r.lens[5] = 9
        r.dirty = true
    end

    local base = f.baseLevel or 30
    r:SetFrameLevel(isSelected and (base + 15) or (base + 5 + slotIndex))
    r.btn:SetFrameLevel(base + 22)

    r.targetRootY = P.RibbonTargetY(f, slotIndex, slotCount)
    if not r.rootY or r.side ~= (f.ribbonSide or 1) then
        r.rootY = r.targetRootY
        P.AnchorRibbon(r, f)
        P.ResetRibbonPhysics(r)
    end

    r:Show()
    r.btn:Show()
    P.ApplyRibbonColors(r)
end

function P.UpdateRibbons(f, areas)
    local used = {}
    if CFQ.parchmentOpts.showTabs then
        for idx, area in ipairs(areas) do
            local r = P.ribbonByKey[area.key]
            if not r or not r.inUse then
                r = P.AcquireRibbon(f)
                P.ribbonByKey[area.key] = r
                r.rootY = nil
                r.label = nil
                P.ResetRibbonPhysics(r)
            end
            used[r] = true
            P.ConfigureRibbon(r, f, area, idx, #areas, area.key == P.selectedKey)
        end
    end
    for _, r in ipairs(P.ribbonPool) do
        if r.inUse and not used[r] then
            r.inUse = false
            r:Hide()
            r.btn:Hide()
            if r.key and P.ribbonByKey[r.key] == r then P.ribbonByKey[r.key] = nil end
            r.key, r.label, r.rootY = nil, nil, nil
        end
    end
end

function P.RefreshRibbonTargets(f)
    for _, r in ipairs(P.ribbonPool) do
        if r.inUse and r.slotIndex then
            r.targetRootY = P.RibbonTargetY(f, r.slotIndex, r.slotCount or 1)
        end
    end
end

function P.UpdateRibbonSide(f, force)
    local cx = f:GetCenter()
    local uiW = UIParent:GetWidth()
    local side = 1
    if cx and uiW and uiW > 0 then
        local fx = cx * (f:GetEffectiveScale() or 1)
        local mid = uiW * (UIParent:GetEffectiveScale() or 1) * 0.5
        side = (fx < mid) and 1 or -1     -- left half of the screen: ribbons hang off the right edge
    end
    if force or side ~= f.ribbonSide then
        f.ribbonSide = side
        for _, r in ipairs(P.ribbonPool) do
            if r.inUse then
                P.AnchorRibbon(r, f)
                P.ResetRibbonPhysics(r)
            end
        end
        if f.SetClampRectInsets then
            if side > 0 then f:SetClampRectInsets(0, 60, 0, 0) else f:SetClampRectInsets(-60, 0, 0, 0) end
        end
        P.ApplyStackLayout(f)
    end
end

-- Returns true when the ribbon's angles changed and it needs redrawing
function P.StepRibbon(r, dt, physicsOn)
    local N, REST = P.RIBBON_N, P.RIBBON_REST

    -- Root motion (drag, resize, slot slide) measured in screen space
    local cx, cy = r:GetCenter()
    if cx and cy then
        if r.prevX then
            local vx, vy = (cx - r.prevX) / dt, (cy - r.prevY) / dt
            local ax = (vx - (r.prevVX or 0)) / dt
            local ay = (vy - (r.prevVY or 0)) / dt
            if ax > 15000 then ax = 15000 elseif ax < -15000 then ax = -15000 end
            if ay > 15000 then ay = 15000 elseif ay < -15000 then ay = -15000 end
            local blend = math.min(1, dt * 30)
            r.ax = (r.ax or 0) + (ax - (r.ax or 0)) * blend
            r.ay = (r.ay or 0) + (ay - (r.ay or 0)) * blend
            r.prevVX, r.prevVY = vx, vy
        else
            r.ax, r.ay, r.prevVX, r.prevVY = 0, 0, 0, 0
        end
        r.prevX, r.prevY = cx, cy
    end

    if not physicsOn then
        local changed = false
        for i = 1, N do
            if r.ang[i] ~= REST[i] or r.vel[i] ~= 0 then
                r.ang[i], r.vel[i] = REST[i], 0
                changed = true
            end
        end
        return changed
    end

    local ax, ay = r.ax or 0, r.ay or 0
    if r.atRest and math.abs(ax) < 5 and math.abs(ay) < 5 then
        return false
    end

    local K, LEV = P.RIBBON_K, P.RIBBON_LEVER
    local s = r.side or 1
    local h = dt * 0.5
    for _ = 1, 2 do
        for i = 1, N do
            local a = r.ang[i]
            local acc = -K[i] * (a - REST[i]) - 7.5 * r.vel[i]
            if i > 1 then acc = acc - 45 * ((a - r.ang[i - 1]) - (REST[i] - REST[i - 1])) end
            if i < N then acc = acc + 22 * ((r.ang[i + 1] - a) - (REST[i + 1] - REST[i])) end
            -- inertia: the ribbon lags behind whatever the root is doing
            acc = acc + LEV[i] * (s * ax * math.sin(a) + ay * math.cos(a)) * 0.012
            r.vel[i] = r.vel[i] + acc * h
        end
        for i = 1, N do
            local na = r.ang[i] + r.vel[i] * h
            if na < -0.9 then na, r.vel[i] = -0.9, 0
            elseif na > 1.65 then na, r.vel[i] = 1.65, 0 end
            r.ang[i] = na
        end
    end

    local energy = 0
    for i = 1, N do
        energy = energy + math.abs(r.vel[i]) + math.abs(r.ang[i] - REST[i])
    end
    if energy < 0.004 and math.abs(ax) < 5 and math.abs(ay) < 5 then
        for i = 1, N do r.ang[i], r.vel[i] = REST[i], 0 end
        r.atRest = true
    else
        r.atRest = false
    end
    return true
end

function P.DrawRibbon(r, now)
    local N, W = P.RIBBON_N, P.RIBBON_W
    local s = r.side or 1
    local pts = r.pts
    local L = r.lines
    local SL = P.SetLine

    local x, y = 0, 0
    pts[0][1], pts[0][2] = 0, 0
    for i = 1, N do
        local a = r.ang[i]
        local len = r.lens[i] or 10
        x = x + s * math.cos(a) * len
        y = y - math.sin(a) * len
        pts[i][1], pts[i][2] = x, y
    end

    for i = 1, N do
        local x0, y0, x1, y1 = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
        local dx, dy = x1 - x0, y1 - y0
        local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len, dy / len
        local nx, ny = -uy, ux
        if ny < 0 then nx, ny = -nx, -ny end
        local ex, ey = x1, y1
        if i == N then ex, ey = x1 - ux * 4, y1 - uy * 4 end   -- leave room for the swallowtail
        SL(L.edge[i], r, x0, y0, ex, ey)
        SL(L.main[i], r, x0, y0, ex, ey)
        SL(L.glow[i], r, x0, y0, x1, y1)
        SL(L.shadow[i], r, x0 + 1.5, y0 - 2, x1 + 1.5, y1 - 2)
        SL(L.sheen[i], r, x0 + nx * 3, y0 + ny * 3, ex + nx * 3, ey + ny * 3)
    end

    -- Joint caps hide the wedge gaps where segments bend
    for i = 1, N - 1 do
        local px, py = pts[i][1], pts[i][2]
        local dx, dy = pts[i + 1][1] - pts[i - 1][1], pts[i + 1][2] - pts[i - 1][2]
        local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len, dy / len
        local hl = W * 0.32
        SL(L.jEdge[i], r, px - ux * hl, py - uy * hl, px + ux * hl, py + uy * hl)
        SL(L.jMain[i], r, px - ux * hl, py - uy * hl, px + ux * hl, py + uy * hl)
    end

    -- Swallowtail prongs
    do
        local dx, dy = pts[N][1] - pts[N - 1][1], pts[N][2] - pts[N - 1][2]
        local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len, dy / len
        local nx, ny = -uy, ux
        local bx, by = pts[N][1] - ux * 5, pts[N][2] - uy * 5
        for k = 1, 2 do
            local sg = (k == 1) and 1 or -1
            local sx, sy = bx + nx * (W * 0.22) * sg, by + ny * (W * 0.22) * sg
            local tx, ty = pts[N][1] + ux * 6 + nx * (W * 0.42) * sg, pts[N][2] + uy * 6 + ny * (W * 0.42) * sg
            SL(L.pEdge[k], r, sx, sy, tx, ty)
            SL(L.pMain[k], r, sx, sy, tx, ty)
        end
    end

    -- Title text rides the first joint (tilts with it where the client supports rotated text)
    r.text:ClearAllPoints()
    r.text:SetPoint("CENTER", r, "CENTER", pts[1][1], pts[1][2] + 0.5)
    if r.text.SetRotation then
        local a = (r.ang[1] + r.ang[2]) * 0.5
        pcall(r.text.SetRotation, r.text, (s > 0) and -a or a)
    end

    r.btn:ClearAllPoints()
    r.btn:SetPoint("CENTER", r, "CENTER", pts[1][1], pts[1][2])
    r.btn:SetSize((r.textW or 40) + 18, W + 4)

    r.tackRim:ClearAllPoints()
    r.tackRim:SetPoint("CENTER", r, "CENTER", s * 2, 0)
    r.tack:ClearAllPoints()
    r.tack:SetPoint("CENTER", r, "CENTER", s * 2, 0)

    local glowA = 0
    if (r.glowUntil or 0) > now then
        glowA = (0.30 + 0.25 * math.sin(now * 5.5)) * math.min(1, r.glowUntil - now)
    end
    for _, ln in ipairs(L.glow) do
        if glowA > 0.01 then
            ln:SetColorTexture(1.0, 0.80, 0.25, glowA)
            ln:Show()
        else
            ln:Hide()
        end
    end
end

function P.OnRibbonEnter(r, btn)
    r.hover = true
    P.ApplyRibbonColors(r)
    P.KickRibbon(r, -0.9)
    GameTooltip:SetOwner(btn, ((r.side or 1) > 0) and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    local a = r.area
    GameTooltip:AddLine((a and a.title) or "Area", 1, 0.82, 0)
    if a then
        local qn = a.quests and #a.quests or 0
        GameTooltip:AddLine(string.format("%d of %d still to gather  •  %d %s",
            a.remaining or 0, a.items and #a.items or 0, qn, qn == 1 and "quest" or "quests"), 0.9, 0.9, 0.9)
        if a.isCurrent then
            GameTooltip:AddLine("Where you are now. Rises to the top whenever you enter a new area.", 0.7, 0.7, 0.7, true)
        end
    end
    if r.isSelected then
        GameTooltip:AddLine("This sheet is on top", 0.55, 0.85, 0.55)
    else
        GameTooltip:AddLine("Click: shuffle this sheet to the top", 0.65, 0.65, 0.65)
    end
    GameTooltip:Show()
end

-- ----------------------------------------------------------------------------
-- STACK LAYOUT, SHUFFLE ANIMATION & PER-FRAME DRIVER
-- ----------------------------------------------------------------------------
function P.ApplyStackLayout(f)
    if not f.topSheet then return end
    local w, h = f:GetWidth(), f:GetHeight()
    if not w or w < 20 or not h or h < 20 then return end
    local s = f.ribbonSide or 1
    local t = f.shuffle and math.min(1, f.shuffle.t) or 0
    local pulse = math.sin(math.pi * t)
    local wob = math.sin(2 * math.pi * t)

    f.shadowSheet:Layout(w, h, 0.004, 3, -4)
    local visible = f.visibleBackSheets or 1
    for k = 1, P.MAX_BACK_SHEETS do
        local sh = f.backSheets[k]
        if k <= visible then
            local slot = P.BACK_SLOTS[k]
            local sign = (k % 2 == 0) and -1 or 1
            sh:Show()
            -- back sheets fan out toward the ribbons while the top sheet is pulled the other way
            sh:Layout(w, h, slot.angle + wob * 0.025 * sign, slot.dx + pulse * s * 6 * k, slot.dy)
        else
            sh:Hide()
        end
    end
    f.topSheet:Layout(w, h, s * 0.06 * pulse, -s * 30 * pulse, 6 * pulse)
    f.chrome:SetAlpha(f.shuffle and math.abs(1 - 2 * t) or 1)
end

function P.SelectArea(key, animate)
    local f = shoppingListFrame
    if not f or not key then return end
    if key == P.selectedKey and not f.shuffle then
        P.KickRibbon(P.ribbonByKey[key], -2.2)
        return
    end
    for _, r in ipairs(P.ribbonPool) do
        if r.inUse then P.KickRibbon(r, (r.key == key) and -3.2 or 1.2) end
    end
    if animate and f:IsShown() then
        f.shuffle = { t = 0, dur = 0.42, key = key, swapped = false }
    else
        P.selectedKey = key
        shoppingScrollOffset = 0
        UpdateShoppingListUI()
    end
end

function P.OnUpdate(f, elapsed)
    local dt = math.min(math.max(elapsed or 0, 0.001), 0.05)
    local now = GetTime()

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

    local physicsOn = CFQ.parchmentOpts.ribbonPhysics
    for _, r in ipairs(P.ribbonPool) do
        if r.inUse and r:IsShown() then
            local need = r.dirty
            if r.targetRootY and r.rootY and r.rootY ~= r.targetRootY then
                local d = r.targetRootY - r.rootY
                if math.abs(d) < 0.25 then
                    r.rootY = r.targetRootY
                else
                    r.rootY = r.rootY + d * math.min(1, dt * 9)
                end
                P.AnchorRibbon(r, f)
                need = true
            end
            if P.StepRibbon(r, dt, physicsOn) then need = true end
            local glowing = (r.glowUntil or 0) > now
            if glowing or r.wasGlowing then need = true end
            r.wasGlowing = glowing
            if need then
                P.DrawRibbon(r, now)
                r.dirty = false
            end
        end
    end
end

-- When the player enters a new area: the current-area sheet glows and (optionally) shuffles to the top
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
            f.shuffle = { t = 0, dur = 0.42, key = P.CURRENT_KEY, swapped = false }
            for _, r in ipairs(P.ribbonPool) do
                if r.inUse then P.KickRibbon(r, (r.key == P.CURRENT_KEY) and -3.2 or 1.2) end
            end
        elseif not f.shuffle then
            P.selectedKey = P.CURRENT_KEY
            shoppingScrollOffset = 0
        end
    else
        P.KickRibbon(P.ribbonByKey[P.CURRENT_KEY], -2.4)
    end
end

-- ----------------------------------------------------------------------------
-- CHECKLIST ROWS
-- ----------------------------------------------------------------------------
local function AcquireShoppingListRow(idx, parent)
    local row = shoppingListRowPool[idx]
    if row then return row end

    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.45, 0.30, 0.08, 0.14)

    -- Hand-drawn style ink checkbox [ ] / [✓]
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(12, 12)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)

    box.border = box:CreateTexture(nil, "BACKGROUND")
    box.border:SetAllPoints()
    box.border:SetColorTexture(0.24, 0.15, 0.06, 0.90)

    box.bg = box:CreateTexture(nil, "ARTWORK")
    box.bg:SetPoint("TOPLEFT", 1, -1)
    box.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    box.bg:SetColorTexture(0.92, 0.84, 0.66, 0.85)

    box.checkMark = box:CreateFontString(nil, "OVERLAY")
    box.checkMark:SetFont(fontPath, 11, "OUTLINE")
    box.checkMark:SetPoint("CENTER", box, "CENTER", 0, 0)
    box.checkMark:SetText("|cFF1F6E1F✓|r")
    box.checkMark:Hide()
    row.box = box

    -- Objective text (wraps dynamically when the parchment is resized!)
    row.itemText = row:CreateFontString(nil, "OVERLAY")
    row.itemText:SetFont(fontPath, 11, "")
    row.itemText:SetPoint("TOPLEFT", box, "TOPRIGHT", 5, 1)
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetJustifyV("TOP")
    row.itemText:SetWordWrap(true)
    row.itemText:SetTextColor(0.16, 0.09, 0.03, 1.0)

    -- Horizontal ink strikethrough line across completed items
    row.strikeLine = row:CreateTexture(nil, "OVERLAY", nil, 4)
    row.strikeLine:SetHeight(1.5)
    row.strikeLine:SetColorTexture(0.25, 0.16, 0.07, 0.88)
    row.strikeLine:Hide()

    -- Subtle divider under each item
    row.divider = row:CreateTexture(nil, "BACKGROUND")
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    row.divider:SetColorTexture(0.45, 0.32, 0.15, 0.22)

    shoppingListRowPool[idx] = row
    return row
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
    f.ribbonSide = 1
    f.visibleBackSheets = 1
    shoppingListFrame = f
    P.ApplyPosition(f)

    f:SetScript("OnDragStart", function(self)
        if not self.isResizing then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, xOfs, yOfs = self:GetPoint(1)
        if pt then
            shoppingListCfg.point = pt
            shoppingListCfg.relPoint = relPt or pt
            shoppingListCfg.x = math.floor((xOfs or 0) + 0.5)
            shoppingListCfg.y = math.floor((yOfs or 0) + 0.5)
            shoppingListCfg.useDefaultAnchor = false
            SaveState()
        end
        P.UpdateRibbonSide(self)
    end)

    -- Sheet stack (bottom to top): drop shadow, up to 3 back sheets, top sheet
    local base = f.baseLevel
    f.shadowSheet = P.CreateSheet(f, 11, {
        paper = { 0, 0, 0, 0.36 }, depth = 4, minDepth = 1, segW = 14, overlap = 0,
    })
    f.shadowSheet:SetFrameLevel(base + 1)

    local backPaper = {
        { 0.86, 0.77, 0.58, 0.98 },
        { 0.80, 0.71, 0.53, 0.98 },
        { 0.74, 0.65, 0.48, 0.98 },
    }
    f.backSheets = {}
    for k = 1, P.MAX_BACK_SHEETS do
        local sh = P.CreateSheet(f, 20 + k * 7, {
            paper = backPaper[k], rim = { 0.34, 0.22, 0.09, 0.95 }, depth = 4, minDepth = 0.8, segW = 11,
        })
        sh:SetFrameLevel(base + 5 - k)   -- back1 (closest) = base+4 ... back3 = base+2
        f.backSheets[k] = sh
    end

    f.topSheet = P.CreateSheet(f, 7, {
        paper = { 0.93, 0.85, 0.67, 0.97 }, rim = { 0.40, 0.27, 0.12, 0.95 },
        depth = 4.5, minDepth = 0.8, segW = 8, grain = true, shade = true,
    })
    f.topSheet:SetFrameLevel(base + 12)

    -- Chrome: everything printed on the top sheet (moves & fades with it during a shuffle)
    local chrome = CreateFrame("Frame", nil, f.topSheet)
    chrome:SetAllPoints(f.topSheet)
    chrome:SetFrameLevel(base + 17)
    f.chrome = chrome

    -- Decorative Brass Tack at Top Center
    local tack = CreateFrame("Frame", nil, chrome)
    tack:SetSize(10, 10)
    tack:SetPoint("TOP", chrome, "TOP", 0, 3)
    tack:SetFrameLevel(base + 19)
    local tackRim = tack:CreateTexture(nil, "BACKGROUND")
    tackRim:SetAllPoints()
    tackRim:SetColorTexture(0.18, 0.10, 0.02, 1.0)
    local tackHead = tack:CreateTexture(nil, "ARTWORK")
    tackHead:SetPoint("TOPLEFT", 1, -1)
    tackHead:SetPoint("BOTTOMRIGHT", -1, 1)
    tackHead:SetColorTexture(0.92, 0.74, 0.24, 1.0)

    -- Close Button (Top-Right)
    local closeBtn = CreateFrame("Button", nil, chrome)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel(base + 19)
    closeBtn.txt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtn.txt:SetFont(fontPath, 12, "OUTLINE")
    closeBtn.txt:SetPoint("CENTER")
    closeBtn.txt:SetText("|cFF6E4720×|r")
    closeBtn:SetScript("OnEnter", function(self)
        self.txt:SetText("|cFFFFD100×|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Hide Field Tally Parchment", 1, 0.82, 0)
        GameTooltip:AddLine("Turn it back on in Cache ForQuest Options (gear above the tracker) or with /cfq list", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self.txt:SetText("|cFF6E4720×|r")
        GameTooltip:Hide()
    end)
    closeBtn:SetScript("OnClick", function()
        showShoppingList = false
        f:Hide()
        SaveState()
        if CFQ.RefreshOptionsPanel then CFQ.RefreshOptionsPanel() end
    end)

    -- Scope Pill Button ([Area] / [Zone] / [All])
    local scopeBtn = CreateFrame("Button", nil, chrome)
    scopeBtn:SetSize(44, 14)
    scopeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    scopeBtn:SetFrameLevel(base + 19)
    scopeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    scopeBtn.txt = scopeBtn:CreateFontString(nil, "OVERLAY")
    scopeBtn.txt:SetFont(fontPath, 10, "OUTLINE")
    scopeBtn.txt:SetPoint("RIGHT", scopeBtn, "RIGHT", 0, 0)
    scopeBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ResetShoppingListPosition()
            return
        end
        if shoppingListScope == "AREA" then
            shoppingListScope = "ZONE"
        elseif shoppingListScope == "ZONE" then
            shoppingListScope = "ALL"
        else
            shoppingListScope = "AREA"
        end
        shoppingScrollOffset = 0
        SaveState()
        UpdateShoppingListUI()
        if CFQ.RefreshOptionsPanel then CFQ.RefreshOptionsPanel() end
    end)
    scopeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Current-Area Sheet Scope", 1, 0.82, 0)
        GameTooltip:AddLine("Left-Click: Cycle [Area] -> [Zone] -> [All]", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-Click: Reset Size & Position", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    scopeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.scopeBtn = scopeBtn

    -- Options gear -> Cache ForQuest options panel
    local optBtn = CreateFrame("Button", nil, chrome)
    optBtn:SetSize(14, 14)
    optBtn:SetPoint("RIGHT", scopeBtn, "LEFT", -6, 0)
    optBtn:SetFrameLevel(base + 19)
    if not CFQ.ApplyGearIcon(optBtn, 0.42, 0.26, 0.09, "opt", 9) then
        optBtn:SetSize(20, 14)
    end
    optBtn:SetScript("OnClick", function()
        if CFQ.OpenOptions then CFQ.OpenOptions() end
    end)
    optBtn:SetScript("OnEnter", function(self)
        CFQ.SetGearHover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Cache ForQuest Options", 1, 0.82, 0)
        GameTooltip:AddLine("Parchment, ribbon tabs, tracker & map settings", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    optBtn:SetScript("OnLeave", function(self)
        CFQ.SetGearHover(self, false)
        GameTooltip:Hide()
    end)
    f.optBtn = optBtn

    -- Header Title (area name)
    local titleFS = chrome:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(fontPath, 11, "OUTLINE")
    titleFS:SetPoint("TOPLEFT", chrome, "TOPLEFT", 8, -5)
    titleFS:SetPoint("RIGHT", optBtn, "LEFT", -4, 0)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    f.titleFS = titleFS

    -- Ruled Ink Header Line
    local headerLine = chrome:CreateTexture(nil, "ARTWORK", nil, 3)
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", chrome, "TOPLEFT", 6, -20)
    headerLine:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -6, -20)
    headerLine:SetColorTexture(0.38, 0.24, 0.09, 0.70)

    -- Content Container for Checklist Rows
    local content = CreateFrame("Frame", nil, chrome)
    content:SetPoint("TOPLEFT", chrome, "TOPLEFT", 6, -23)
    content:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -6, 14)
    content:SetFrameLevel(base + 18)
    f.content = content

    -- Footer Status / Scroll Hint
    local footerFS = chrome:CreateFontString(nil, "OVERLAY")
    footerFS:SetFont(fontPath, 9, "")
    footerFS:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 8, 4)
    footerFS:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -20, 4)
    footerFS:SetJustifyH("LEFT")
    footerFS:SetWordWrap(false)
    footerFS:SetTextColor(0.36, 0.22, 0.08, 0.90)
    f.footerFS = footerFS

    f:SetScript("OnMouseWheel", function(_, delta)
        local total = f.totalItems or 0
        local maxScroll = math.max(0, total - 1)
        shoppingScrollOffset = math.min(maxScroll, math.max(0, shoppingScrollOffset - delta))
        P.Render(f)
    end)

    -- Bottom-Right Resize Grip (Wraps text dynamically as you resize!)
    local resizeGrip = CreateFrame("Button", nil, chrome)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -1, 1)
    resizeGrip:SetFrameLevel(base + 21)
    resizeGrip:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local gripTex = resizeGrip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip.gripTex = gripTex

    resizeGrip:SetScript("OnEnter", function(self)
        self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Resize Parchment List", 1, 0.82, 0)
        GameTooltip:AddLine("Left-Click & Drag: Resize Width & Height", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-Click: Reset Size & Position", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function(self)
        self.gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
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
            local scale = f:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            f.resizeStartX = cx / scale
            f.resizeStartY = cy / scale
            f.resizeStartW = f:GetWidth()
            f.resizeStartH = f:GetHeight()
            f.resizeStartLeft = f:GetLeft()
            f.resizeStartTop = f:GetTop()

            self:SetScript("OnUpdate", function()
                if not f.isResizing then return end
                local s = f:GetEffectiveScale() or 1
                local mx, my = GetCursorPosition()
                mx = mx / s
                my = my / s

                local newW = math.max(185, math.min(520, f.resizeStartW + (mx - f.resizeStartX)))
                local newH = math.max(95, math.min(520, f.resizeStartH - (my - f.resizeStartY)))

                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f.resizeStartLeft, f.resizeStartTop)
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
            shoppingListCfg.width = math.floor((f:GetWidth() or 230) + 0.5)
            shoppingListCfg.height = math.floor((f:GetHeight() or 175) + 0.5)
            local pt, _, relPt, xOfs, yOfs = f:GetPoint(1)
            if pt then
                shoppingListCfg.point = pt
                shoppingListCfg.relPoint = relPt or pt
                shoppingListCfg.x = math.floor((xOfs or 0) + 0.5)
                shoppingListCfg.y = math.floor((yOfs or 0) + 0.5)
                shoppingListCfg.useDefaultAnchor = false
            end
            SaveState()
            P.UpdateRibbonSide(f)
            UpdateShoppingListUI()
        end
    end)

    f:SetScript("OnSizeChanged", function(self)
        P.ApplyStackLayout(self)
        P.RefreshRibbonTargets(self)
    end)
    f:SetScript("OnShow", function(self)
        for _, r in ipairs(P.ribbonPool) do
            r.prevX, r.prevY = nil, nil     -- no phantom whip-crack from a stale position
        end
        P.UpdateRibbonSide(self)
    end)
    f:SetScript("OnHide", function(self)
        self.shuffle = nil
        self.chrome:SetAlpha(1)
    end)
    f:SetScript("OnUpdate", P.OnUpdate)

    P.ApplyStackLayout(f)
    P.UpdateRibbonSide(f, true)
    f:Hide()
    return f
end

-- ----------------------------------------------------------------------------
-- AREA GROUPING
-- ----------------------------------------------------------------------------
-- Which quantity quests belong to the player's current area (by proximity / cluster / activity),
-- plus every eligible quantity quest so the rest can be filed under other-area sheets.
function P.CollectQuests()
    local playerMapID, px, py = GetPlayerMapPositionSafe()
    local realZoneRaw = strtrim((GetRealZoneText and GetRealZoneText()) or "")
    local subZoneRaw  = strtrim((GetSubZoneText and GetSubZoneText()) or "")
    local realZone = string.lower(realZoneRaw)
    local subZone  = string.lower(subZoneRaw)
    local areaName = (subZoneRaw ~= "" and subZoneRaw) or (realZoneRaw ~= "" and realZoneRaw) or nil
    local radiusTol = math.max(turnInRadiusPercent or 16, incompleteRadiusPercent or 16, 18) / 100.0
    local now = GetTime()

    -- Step 1: Identify quests directly within radius or active in the player's current subzone/session
    local nearbyClusterIDs = {}
    local directQuestMatch = {}
    local anyCoordMatched = false

    for qID, qData in pairs(questRewardMap) do
        if not qData.isFromMap and qData.quantityObjectives and #qData.quantityObjectives > 0 then
            if DoesQuestMatchFilter(qID) then
                local learnHere = false

                -- Check 1: Coordinate distance to player
                if playerMapID and px and py and qData.mapID == playerMapID and qData.x and qData.y then
                    local dx = px - qData.x
                    local dy = py - qData.y
                    if math.sqrt(dx * dx + dy * dy) <= radiusTol then
                        directQuestMatch[qID] = true
                        anyCoordMatched = true
                        learnHere = true
                        if qData.clusterID then
                            nearbyClusterIDs[qData.clusterID] = true
                        end
                    end
                end

                -- Check 2: Recently progressed objective or targeted mob (within last 3 minutes)
                if recentActiveQuests[qID] and (now - recentActiveQuests[qID] < 180) then
                    directQuestMatch[qID] = true
                    if now - recentActiveQuests[qID] < 20 then learnHere = true end
                    if qData.clusterID then
                        nearbyClusterIDs[qData.clusterID] = true
                    end
                end

                -- Check 3: Subzone name appears in the quest title or objective text
                if subZone ~= "" and string.len(subZone) >= 4 then
                    local lowerTitle = string.lower(qData.title or "")
                    local lowerObj   = string.lower(qData.objectiveText or "")
                    if string.find(lowerTitle, subZone, 1, true) or string.find(lowerObj, subZone, 1, true) then
                        directQuestMatch[qID] = true
                        learnHere = true
                        if qData.clusterID then
                            nearbyClusterIDs[qData.clusterID] = true
                        end
                    end
                end

                -- Check 4: Currently SuperTracked quest in the same zone
                if IsQuestSuperTracked(qID) then
                    local lowerHeader = string.lower(qData.header or "")
                    if realZone == "" or lowerHeader == realZone or string.find(realZone, lowerHeader, 1, true) then
                        directQuestMatch[qID] = true
                        if qData.clusterID then
                            nearbyClusterIDs[qData.clusterID] = true
                        end
                    end
                end

                -- Remember where this quest's objectives are worked so its other-area ribbon gets a real name
                if learnHere and areaName then
                    CFQ.learnedQuestAreas[qID] = areaName
                end
            end
        end
    end

    -- Step 2: Collect quests according to the active scope ("AREA", "ZONE", or "ALL")
    local matchedQuests = {}
    local eligible = {}
    for qID, qData in pairs(questRewardMap) do
        if not qData.isFromMap and qData.quantityObjectives and #qData.quantityObjectives > 0 and DoesQuestMatchFilter(qID) then
            table.insert(eligible, qData)
            local include = false
            local lowerHeader = string.lower(qData.header or "")
            local isSameZone = (realZone ~= "" and (lowerHeader == realZone or string.find(realZone, lowerHeader, 1, true) or string.find(lowerHeader, realZone, 1, true)))

            if shoppingListScope == "ALL" then
                include = true
            elseif shoppingListScope == "ZONE" then
                include = isSameZone or directQuestMatch[qID] == true
            else
                -- "AREA" mode: include direct matches + any quest sharing the same proximity cluster!
                if directQuestMatch[qID] or (qData.clusterID and nearbyClusterIDs[qData.clusterID]) then
                    include = true
                elseif not anyCoordMatched and isSameZone and IsQuestWatched(qID) then
                    -- In Classic/Forever zones where quests lack API waypoints, include watched quantity quests in your current zone
                    include = true
                end
            end

            if include then
                table.insert(matchedQuests, qData)
            end
        end
    end

    local headerTitle
    if shoppingListScope == "ALL" then
        headerTitle = "All Areas"
    elseif shoppingListScope == "ZONE" then
        headerTitle = (realZoneRaw ~= "" and realZoneRaw) or "Field Tally"
    else
        headerTitle = areaName or "Field Tally"
    end
    return matchedQuests, eligible, headerTitle
end

function P.FlattenQuests(quests)
    local items = {}
    local doneCount = 0
    for _, qData in ipairs(quests) do
        for _, obj in ipairs(qData.quantityObjectives) do
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

function P.GetAreaColor(name, isCurrent)
    if isCurrent then return P.RIBBON_COLORS[1] end
    local sum = 0
    local str = name or ""
    for i = 1, string.len(str) do
        sum = sum + string.byte(str, i) * i
    end
    local n = #P.RIBBON_COLORS - 1
    return P.RIBBON_COLORS[2 + (sum % n)]
end

function P.BuildAreas()
    local nearby, eligible, headerTitle = P.CollectQuests()
    local current = { key = P.CURRENT_KEY, title = headerTitle, isCurrent = true, quests = nearby }
    local areas = { current }

    if CFQ.parchmentOpts.showTabs and shoppingListScope ~= "ALL" then
        local inCurrent = {}
        for _, q in ipairs(nearby) do inCurrent[q.questID] = true end
        local curLower = string.lower(headerTitle or "")
        local groups, list = {}, {}

        for _, q in ipairs(eligible) do
            -- other-area sheets only carry quests that still need gathering
            if not inCurrent[q.questID] and not q.isComplete then
                local name = CFQ.learnedQuestAreas[q.questID] or q.header or "Elsewhere"
                local lname = string.lower(name)
                if lname == curLower then
                    table.insert(nearby, q)        -- worked here before: it belongs on the current sheet
                    inCurrent[q.questID] = true
                else
                    local g = groups[lname]
                    if not g then
                        g = { key = "AREA:" .. lname, title = name, quests = {} }
                        groups[lname] = g
                        table.insert(list, g)
                    end
                    table.insert(g.quests, q)
                end
            end
        end

        local maxOthers = P.MAX_AREAS - 1
        if #list > maxOthers then
            table.sort(list, function(a, b)
                if #a.quests ~= #b.quests then return #a.quests > #b.quests end
                return a.title < b.title
            end)
            local overflow = { key = "AREA:__elsewhere", title = "Elsewhere", quests = {}, isOverflow = true }
            for i = maxOthers, #list do
                for _, q in ipairs(list[i].quests) do table.insert(overflow.quests, q) end
            end
            for i = #list, maxOthers, -1 do table.remove(list, i) end
            table.insert(list, overflow)
        end
        table.sort(list, function(a, b)
            if (a.isOverflow == true) ~= (b.isOverflow == true) then return not a.isOverflow end
            return a.title < b.title
        end)
        for _, g in ipairs(list) do table.insert(areas, g) end
    end

    for _, a in ipairs(areas) do
        table.sort(a.quests, CompareQuestsForTracker)
        a.items, a.doneCount = P.FlattenQuests(a.quests)
        a.remaining = #a.items - a.doneCount
        a.color = P.GetAreaColor(a.title, a.isCurrent)
    end
    return areas
end

-- ----------------------------------------------------------------------------
-- RENDER THE SELECTED SHEET
-- ----------------------------------------------------------------------------
function P.Render(f)
    local area = nil
    for _, a in ipairs(P.areas) do
        if a.key == P.selectedKey then area = a break end
    end
    area = area or P.areas[1]
    if not area then return end

    local items = area.items or {}
    f.totalItems = #items
    for _, row in ipairs(shoppingListRowPool) do
        row:Hide()
    end

    local scopeLabel = (shoppingListScope == "AREA" and "Area")
        or (shoppingListScope == "ZONE" and "Zone")
        or "All"
    f.scopeBtn.txt:SetText("|cFF5A3814[" .. scopeLabel .. "]|r")
    if area.isCurrent then
        f.titleFS:SetText("|cFFFFF0C2" .. (area.title or "Field Tally") .. "|r")
    else
        f.titleFS:SetText("|cFFFFF0C2" .. (area.title or "Elsewhere") .. "|r |cFFD9C49A(away)|r")
    end

    if #items == 0 then
        local row = AcquireShoppingListRow(1, f.content)
        row.box:Hide()
        row.strikeLine:Hide()
        row.itemText:SetWidth(math.max(120, (f:GetWidth() or 230) - 30))
        row.itemText:SetText("|cFF6B5233Nothing to gather nearby.|r\n|cFF8A7050Pick a ribbon to see other areas.|r")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -2)
        row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -2)
        row:SetHeight(32)
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
        f.footerFS:SetText("0 items here")
        return
    end

    if shoppingScrollOffset > math.max(0, #items - 1) then
        shoppingScrollOffset = math.max(0, #items - 1)
    end

    local contentW = math.max(150, (f:GetWidth() or 230) - 12)
    local contentH = math.max(55, (f:GetHeight() or 175) - 38)
    local yCursor = 0
    local now = GetTime()
    local shownRows = 0

    for i = 1 + shoppingScrollOffset, #items do
        if shownRows >= MAX_SHOPPING_ROWS then break end
        local entry = items[i]
        local row = AcquireShoppingListRow(shownRows + 1, f.content)
        row.box:Show()

        local textW = math.max(120, contentW - 22)
        row.itemText:SetWidth(textW)

        local isFlashing = flashObjectiveUntil[entry.progKey] and (now < flashObjectiveUntil[entry.progKey])
        local countStr = string.format("%d/%d", entry.numFulfilled or 0, entry.numRequired or 1)
        local readySuffix = entry.isQuestComplete and " |cFF1F6E1F(Turn in)|r" or ""

        if entry.finished then
            row.box.checkMark:Show()
            row.box.bg:SetColorTexture(0.78, 0.84, 0.68, 0.90)
            row.itemText:SetText(string.format("|cFF5C5346%s  %s|r%s", countStr, entry.itemName or "", readySuffix))
        elseif isFlashing then
            row.box.checkMark:Hide()
            row.box.bg:SetColorTexture(1.0, 0.90, 0.35, 1.0)
            row.itemText:SetText(string.format("|cFF8A4B00%s|r  |cFF1E1004%s|r", countStr, entry.itemName or ""))
        else
            row.box.checkMark:Hide()
            row.box.bg:SetColorTexture(0.95, 0.89, 0.74, 0.90)
            row.itemText:SetText(string.format("|cFF7A2E00%s|r  |cFF1A0E04%s|r", countStr, entry.itemName or ""))
        end

        local strH = math.max(14, math.ceil(row.itemText:GetStringHeight() or 14))
        local rowH = strH + 6

        if (math.abs(yCursor) + rowH) > (contentH + 4) and shownRows > 0 then
            row:Hide()
            break
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, yCursor)
        row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, yCursor)
        row:SetHeight(rowH)

        -- Position the horizontal ink strikethrough line across completed items
        if entry.finished then
            local lineW = math.min(textW - 4, math.max(40, (row.itemText:GetStringWidth() or 80)))
            row.strikeLine:ClearAllPoints()
            row.strikeLine:SetPoint("LEFT", row.itemText, "TOPLEFT", 0, -7)
            row.strikeLine:SetWidth(lineW)
            row.strikeLine:Show()
        else
            row.strikeLine:Hide()
        end

        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(entry.questID)
                end
            else
                ActivateQuestTarget(entry.questID)
                if LayoutObjectiveTrackerWithStacks then
                    LayoutObjectiveTrackerWithStacks()
                end
            end
        end)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local lvlStr = string.format("|c%s[%d]|r ", entry.levelHex or "FFFFFF00", entry.level or 0)
            GameTooltip:AddLine(lvlStr .. "|cFFFFD100" .. (entry.questTitle or "Quest") .. "|r")
            GameTooltip:AddLine(string.format("%s: %d / %d", entry.itemName or "Objective", entry.numFulfilled or 0, entry.numRequired or 1), 0.9, 0.9, 0.9)
            if entry.isQuestComplete then
                GameTooltip:AddLine("All objectives complete — Ready for turn-in!", 0.25, 0.95, 0.25)
            end
            GameTooltip:AddLine("Left-Click: Track Quest | Right-Click: Open Log", 0.65, 0.65, 0.65)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Show()
        yCursor = yCursor - rowH
        shownRows = shownRows + 1
    end

    local questCount = area.quests and #area.quests or 0
    local doneCount = area.doneCount or 0
    if #items > shownRows then
        f.footerFS:SetText(string.format("%d/%d checked  •  Scroll (%d-%d of %d)", doneCount, #items, shoppingScrollOffset + 1, shoppingScrollOffset + shownRows, #items))
    else
        f.footerFS:SetText(string.format("%d/%d checked off  (%d %s)", doneCount, #items, questCount, questCount == 1 and "quest" or "quests"))
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

    f.visibleBackSheets = math.max(1, math.min(#areas - 1, P.MAX_BACK_SHEETS))
    f:Show()
    P.Render(f)
    P.UpdateRibbons(f, areas)
    P.ApplyStackLayout(f)
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
        tBtn:SetScript("OnClick", function()
            if turnInStackEnabled then
                CFQ.PreserveStackedQuestWatches(true)   -- keep every stacked quest on the tracker
            end
            turnInStackEnabled = not turnInStackEnabled
            ApplyFilterChanges()
            CFQ.ScheduleTrackerRelayout(0.15)           -- catch Blizzard's block rebuild after new watches
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
            if incompleteStackEnabled then
                CFQ.PreserveStackedQuestWatches(false)
            end
            incompleteStackEnabled = not incompleteStackEnabled
            ApplyFilterChanges()
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

-- Decks show EVERY quest in a cluster, including ones the native tracker isn't watching.
-- Before a stack type is switched off, make sure those quests are actually watched so they
-- keep a native tracker block instead of vanishing with the deck.
function CFQ.PreserveStackedQuestWatches(isCompleteType)
    if not C_QuestLog or not C_QuestLog.AddQuestWatch then return end
    local filterActive = autoUntrack and ((GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0))
    for _, deck in ipairs(trackerStackDeckPool) do
        local cg = deck.clusterData
        if deck:IsShown() and cg and cg.quests and (cg.isComplete == true) == (isCompleteType == true) then
            for _, q in ipairs(cg.quests) do
                if not IsQuestWatched(q.questID) and (not filterActive or DoesQuestMatchFilter(q.questID)) then
                    pcall(C_QuestLog.AddQuestWatch, q.questID)
                end
            end
        end
    end
end

function CFQ.ReportError(err)
    local msg = tostring(err)
    if CFQ.reportedErrors[msg] then return end
    CFQ.reportedErrors[msg] = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler("Cache ForQuest: " .. msg)
    else
        print("|cFFFF5555Cache ForQuest error:|r " .. msg)
    end
end

function CFQ.ErrorWithStack(err)
    return tostring(err) .. ((debugstack and ("\n" .. debugstack(2))) or "")
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

        for _, blkEntry in ipairs(rawBlocks) do
            local qData = blkEntry.qData
            local blk = blkEntry.frame
            local poiBtn = blkEntry.poiBtn
            local cID = qData and qData.clusterID
            local cGroup = cID and clusterGroupsMap[cID]

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

-- Guarded wrapper: an error anywhere in a layout pass used to leave isReorderingTrackerUI stuck
-- at true, which froze every later layout with stacked blocks still hidden.
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
    optionsRow.label:SetText("|cFFFFD100Cache ForQuest Options...|r |cFF888888(parchment & more)|r")
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
        self.label:SetText("|cFFFFD100Cache ForQuest|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Cache ForQuest Options", 1, 0.82, 0)
        GameTooltip:AddLine("Parchment list, ribbon tabs, tracker & map settings", 0.85, 0.85, 0.85, true)
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
-- CACHE FORQUEST OPTIONS PANEL
-- Lives in Options > AddOns (Settings canvas), opens from the parchment gear, the gear
-- above "All Objectives", the filter menu, or /cfq options. Falls back to a standalone
-- window on clients without the Settings API.
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
    title:SetText(CONFIG.ADDON_NAME .. " |cFF888888v1.2.0|r")
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
        "The checklist of items to collect & mobs to slay for quests around you.",
        function() return showShoppingList end,
        function(v) showShoppingList = v; RefreshParchment() end)
    Check("Ribbon tabs for other areas",
        "Each area with unfinished collection quests gets its own sheet in the stack and a hanging ribbon tab. Click a ribbon to shuffle that sheet to the top.",
        function() return CFQ.parchmentOpts.showTabs end,
        function(v) CFQ.parchmentOpts.showTabs = v; RefreshParchment() end)
    Check("Ribbon physics",
        "Ribbons sway and droop when the parchment is dragged, resized, or shuffled.",
        function() return CFQ.parchmentOpts.ribbonPhysics end,
        function(v) CFQ.parchmentOpts.ribbonPhysics = v end)
    Check("Bring the current area to the top on arrival",
        "When you enter a new area, its sheet shuffles to the top of the stack and its ribbon glows.",
        function() return CFQ.parchmentOpts.autoFrontOnAreaChange end,
        function(v) CFQ.parchmentOpts.autoFrontOnAreaChange = v end)
    Check("Hide the parchment when nothing is nearby",
        "Off: the stack stays up so you can browse other areas. On: it only appears when the area you're in has something to gather.",
        function() return CFQ.parchmentOpts.hideWhenNothingNearby end,
        function(v) CFQ.parchmentOpts.hideWhenNothingNearby = v; RefreshParchment() end)

    y = y - 4
    Button("Scope: Area", 120, 24, function()
        if shoppingListScope == "AREA" then shoppingListScope = "ZONE"
        elseif shoppingListScope == "ZONE" then shoppingListScope = "ALL"
        else shoppingListScope = "AREA" end
        shoppingScrollOffset = 0
        SaveState()
        RefreshParchment()
    end, function(self)
        local lbl = (shoppingListScope == "AREA" and "Area") or (shoppingListScope == "ZONE" and "Zone") or "All"
        self:SetText("Scope: " .. lbl)
    end)
    Button("Reset Position & Size", 160, 150, function()
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
    hint:SetText("Slash: /cfq (filter menu), /cfq options, /cfq lvl, /cfq dist, /cfq list, /cfq resetlist, /cfq reset")

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
            print("|cFFFFD100Cache ForQuest:|r options will open after combat.")
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

-- Slash Commands (/cfq or /cacheforquest)
SLASH_CACHEFORQUEST1 = "/cfq"
SLASH_CACHEFORQUEST2 = "/cacheforquest"
SlashCmdList["CACHEFORQUEST"] = function(msg)
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
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if CFQ.openOptionsAfterCombat then
            CFQ.openOptionsAfterCombat = false
            CFQ.OpenOptions()
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == "CacheForQuest" then
        LoadState()
    elseif event == "PLAYER_ENTERING_WORLD" then
        LoadState()
        CreateQuestLogUI()
        CreateObjectiveTrackerButton()
        EnsureShoppingListFrame()
        HookAllMapTooltips()
        CFQ.RegisterOptions()

        -- Chat frames settle into their Edit Mode layout a moment after login; re-seat the
        -- parchment above the chat box if it is still on its default anchor.
        if C_Timer and C_Timer.After then
            C_Timer.After(1.5, function()
                if shoppingListCfg.useDefaultAnchor and shoppingListFrame then
                    CFQ.P.ApplyPosition(shoppingListFrame)
                    CFQ.P.UpdateRibbonSide(shoppingListFrame, true)
                end
            end)
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