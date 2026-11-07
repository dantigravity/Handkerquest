-- ============================================================================
-- CacheForQuest.lua (v1.0.0 - WoW Forever Edition)
-- Objective Tracker Stacks + Level Sort + Lowered Quest Log Currency Lines
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

local turnInStackEnabled = true     -- (?) Turn-in quest stacking toggle (Objective Tracker only)
local turnInRadiusPercent = 16      -- 1% to 50% of zone map
local incompleteStackEnabled = false-- (•••) Incomplete quest stacking toggle (Objective Tracker only)
local incompleteRadiusPercent = 16  -- 1% to 50% of zone map

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

local dropdownRowPool = {}
local customListRowPool = {}
local trackerStackDeckPool = {}

local savedWatchedQuests = nil
local isSyncingTracker = false
local isReorderingTrackerUI = false
local lastWatchOrderSignature = ""
local lastCompletionSignature = ""

local nativeTitleFont, nativeTitleSize, nativeTitleFlags = nil, nil, nil
local nativeLineFont, nativeLineSize, nativeLineFlags = nil, nil, nil

local customScrollOffset = 0
local dropdownScrollOffset = 0
local dropdownSearchText = ""

local MAX_CUSTOM_ROWS = 11
local MAX_DROPDOWN_ROWS = 12
local MAX_CARDS_PER_STACK = 8

local sharedMenuFrame = nil
local questLogBar = nil
local trackerFilterBtn = nil
local trackerControlBar = nil
local LayoutObjectiveTrackerWithStacks
local ScanQuestLogRewards
local SyncObjectiveTracker

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
    end
end

-- ============================================================================
-- QUEST LEVEL, OBJECTIVES, SUPER-TRACKING & COORDINATE HELPERS
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

local function GetFirstQuestObjectiveText(questID, logIndex, isComplete, headerName)
    if isComplete then
        return string.format("Ready for turn-in (%s)", headerName or "Hub")
    end
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and objs and #objs > 0 then
            for _, obj in ipairs(objs) do
                if not obj.finished and obj.text and obj.text ~= "" then
                    return "- " .. obj.text
                end
            end
            if objs[1].text and objs[1].text ~= "" then
                return "- " .. objs[1].text
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
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        return C_SuperTrack.GetSuperTrackedQuestID() == questID
    end
    return false
end

local function ActivateQuestTarget(questID)
    if not questID then return end
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
-- FILTER COUNT, MATCHING & FIXED-ORDER SORT COMPARATORS
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

local function IsTrackerSortingOrClusteringActive()
    return (levelSortMode ~= "NONE") or turnInStackEnabled or incompleteStackEnabled
end

local function IsQuestLogOverrideActive()
    return (GetActiveRewardFilterCount() > 0) or (GetActiveLevelFilterCount() > 0) or (levelSortMode ~= "NONE")
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

local function CompareQuestsForTracker(a, b)
    if not a or not b then return false end
    if a.isFromMap ~= b.isFromMap then
        return not a.isFromMap
    end

    if levelSortMode == "ASC" then
        if a.level ~= b.level then return a.level < b.level end
    elseif levelSortMode == "DESC" then
        if a.level ~= b.level then return a.level > b.level end
    end

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

local function CompareQuestsForQuestLog(a, b)
    if not a or not b then return false end
    if a.isFromMap ~= b.isFromMap then
        return not a.isFromMap
    end
    if levelSortMode == "ASC" then
        if a.level ~= b.level then return a.level < b.level end
        if a.header ~= b.header then return a.header < b.header end
        return a.title < b.title
    elseif levelSortMode == "DESC" then
        if a.level ~= b.level then return a.level > b.level end
        if a.header ~= b.header then return a.header < b.header end
        return a.title < b.title
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

                clusterGroupsMap[cID] = {
                    id = cID,
                    index = multiIdx,
                    zone = zoneLabel,
                    isComplete = isCompleteGroup,
                    quests = group,
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
end

-- ============================================================================
-- INTERACTIVE STACKED (? & •••) CARD DECK WIDGET (OBJECTIVE TRACKER ONLY)
-- ============================================================================
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
        local topQuest = self.clusterData.quests[1]
        if button == "RightButton" then
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(topQuest.questID)
            end
        else
            ActivateQuestTarget(topQuest.questID)
            if LayoutObjectiveTrackerWithStacks then
                LayoutObjectiveTrackerWithStacks()
            end
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

            if LayoutObjectiveTrackerWithStacks then
                LayoutObjectiveTrackerWithStacks(true)
            end
        end
    end)

    ApplyNativeTrackerFontsToDeck(deck)
    trackerStackDeckPool[index] = deck
    return deck
end

local function PopulateTrackerStackDeck(deck, clusterGroup)
    if deck.clusterID ~= clusterGroup.id then
        deck.expandProgress = 0
        deck.isHovered = false
        deck.hoverGraceTimer = 0
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

    local quests = clusterGroup.quests
    table.sort(quests, CompareQuestsForTracker)

    local count = math.min(#quests, MAX_CARDS_PER_STACK)
    deck.numActiveCards = count
    local isCompCluster = clusterGroup.isComplete == true

    local anySelectedInStack = false
    for i = 1, count do
        if quests[i] and IsQuestSuperTracked(quests[i].questID) then
            anySelectedInStack = true
            break
        end
    end

    local topQuest = quests[1]
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

    for i = 1, MAX_CARDS_PER_STACK do
        local card = deck.cards[i]
        local qData = quests[i]
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

            card:SetScript("OnClick", function(_, button)
                if IsShiftKeyDown() then
                    if IsQuestWatched(qData.questID) then
                        if C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, qData.questID) end
                    else
                        if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, qData.questID) end
                    end
                    PopulateTrackerStackDeck(deck, clusterGroup)
                elseif button == "RightButton" then
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(qData.questID)
                    elseif QuestMapFrame_ShowQuestDetails then
                        QuestMapFrame_ShowQuestDetails(qData.questID)
                    end
                else
                    ActivateQuestTarget(qData.questID)
                    PopulateTrackerStackDeck(deck, clusterGroup)
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
            turnInStackEnabled = not turnInStackEnabled
            ApplyFilterChanges()
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
-- ============================================================================
LayoutObjectiveTrackerWithStacks = function(isAnimationTick)
    if isReorderingTrackerUI or InCombatLockdown() then return end
    isReorderingTrackerUI = true

    if not isAnimationTick then
        ScanQuestLogRewards()
        for _, deck in ipairs(trackerStackDeckPool) do
            deck:Hide()
        end
    end

    local deckPoolIdx = 0
    local controlBarPlaced = false

    local function ProcessTrackerModule(trackerModule)
        if not trackerModule or not trackerModule.ContentsFrame then return end
        local contents = trackerModule.ContentsFrame
        local rawBlocks = {}

        local children = { contents:GetChildren() }
        for _, child in ipairs(children) do
            local isOurDeck = (child.clusterData ~= nil) or (child == trackerControlBar)
            if child and not isOurDeck then
                local qID = child.id or child.questID or (child.parentBlock and child.parentBlock.id)
                if type(qID) == "number" and questRewardMap[qID] then
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

                    local qData = questRewardMap[qID]
                    if child:IsShown() or child.qrfHiddenByStack then
                        table.insert(rawBlocks, {
                            frame = child,
                            questID = qID,
                            qData = qData,
                        })
                    end
                elseif child.qrfHiddenByStack then
                    child.qrfHiddenByStack = false
                    child:SetAlpha(1)
                    if child.EnableMouse then child:EnableMouse(true) end
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
            local cID = qData and qData.clusterID
            local cGroup = cID and clusterGroupsMap[cID]

            if cGroup and #cGroup.quests >= 2 and IsQuestStackingEnabledFor(qData) then
                blk.qrfHiddenByStack = true
                blk:SetAlpha(0)
                if blk.EnableMouse then blk:EnableMouse(false) end
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
                        deckPoolIdx = deckPoolIdx + 1
                        deck = AcquireTrackerStackDeck(deckPoolIdx, contents)
                        PopulateTrackerStackDeck(deck, cGroup)
                        deck:Show()
                    end
                    table.insert(layoutItems, {
                        isDeck = true,
                        frame = deck,
                        qData = cGroup.quests[1],
                    })
                end
            else
                if blk.qrfHiddenByStack then
                    blk.qrfHiddenByStack = false
                    blk:SetAlpha(1)
                    if blk.EnableMouse then blk:EnableMouse(true) end
                end

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
                    qData = qData,
                })
            end
        end

        if #layoutItems > 0 then
            if IsTrackerSortingOrClusteringActive() then
                table.sort(layoutItems, function(itemA, itemB)
                    return CompareQuestsForTracker(itemA.qData, itemB.qData)
                end)
            else
                table.sort(layoutItems, function(itemA, itemB)
                    return (itemA.qData.logIndex or 0) < (itemB.qData.logIndex or 0)
                end)
            end

            local prevFrame = nil
            for idx, item in ipairs(layoutItems) do
                local f = item.frame
                f:ClearAllPoints()
                local leftX = item.isDeck and -26 or 0
                if idx == 1 then
                    if activeBar and activeBar:IsShown() then
                        local deltaX = item.isDeck and 0 or 26
                        f:SetPoint("TOPLEFT", activeBar, "BOTTOMLEFT", deltaX, -5)
                        f:SetPoint("TOPRIGHT", activeBar, "BOTTOMRIGHT", -4, -5)
                    elseif trackerModule.Header and trackerModule.Header:IsShown() then
                        f:SetPoint("TOPLEFT", trackerModule.Header, "BOTTOMLEFT", leftX, -4)
                        f:SetPoint("TOPRIGHT", trackerModule.Header, "BOTTOMRIGHT", -10, -4)
                    else
                        f:SetPoint("TOPLEFT", contents, "TOPLEFT", leftX, -4)
                        f:SetPoint("TOPRIGHT", contents, "TOPRIGHT", -10, -4)
                    end
                else
                    f:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", leftX - (prevFrame.clusterData and -26 or 0), -6)
                    f:SetPoint("TOPRIGHT", prevFrame, "BOTTOMRIGHT", 0, -6)
                end
                prevFrame = f
            end
        end
    end

    if QuestObjectiveTracker then
        ProcessTrackerModule(QuestObjectiveTracker)
    end
    if CampaignQuestObjectiveTracker then
        ProcessTrackerModule(CampaignQuestObjectiveTracker)
    end
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.modules then
        for _, mod in pairs(ObjectiveTrackerFrame.modules) do
            if mod ~= QuestObjectiveTracker and mod ~= CampaignQuestObjectiveTracker then
                ProcessTrackerModule(mod)
            end
        end
    end

    isReorderingTrackerUI = false
end

SyncObjectiveTracker = function()
    if isSyncingTracker or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
    isSyncingTracker = true

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

    if IsTrackerSortingOrClusteringActive() then
        table.sort(targetWatchList, CompareQuestsForTracker)
    else
        table.sort(targetWatchList, function(a, b)
            return (a.logIndex or 0) < (b.logIndex or 0)
        end)
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

        if IsTrackerSortingOrClusteringActive() and C_QuestLog.RemoveQuestWatch and C_QuestLog.AddQuestWatch and not InCombatLockdown() then
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
    isSyncingTracker = false
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
local function GetShortSortSuffix()
    if levelSortMode == "ASC" then return " " .. ICON_ARROW_UP
    elseif levelSortMode == "DESC" then return " " .. ICON_ARROW_DOWN
    end
    return ""
end

local function UpdateAllButtonLabels()
    local rCount = GetActiveRewardFilterCount()
    local lCount = GetActiveLevelFilterCount()
    local totalActive = rCount + lCount
    local hasSnapshot = (savedWatchedQuests ~= nil)
    local sortTag = GetShortSortSuffix()

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

        if totalActive > 0 or (levelSortMode ~= "NONE") or hasSnapshot then
            questLogBar.resetBtn:Enable()
        else
            questLogBar.resetBtn:Disable()
        end
    end

    if trackerFilterBtn then
        if totalActive == 0 then
            if levelSortMode ~= "NONE" then
                trackerFilterBtn:SetText("Sort: " .. (levelSortMode == "ASC" and ("Asc " .. ICON_ARROW_UP) or ("Desc " .. ICON_ARROW_DOWN)))
            else
                trackerFilterBtn:SetText(CONFIG.TRACKER_BTN_ALL)
            end
        else
            trackerFilterBtn:SetText("Filter (" .. totalActive .. ")" .. sortTag)
        end
    end

    UpdateTrackerControlBarVisuals()
end

-- Walks up a frame's SetPoint(1) anchor chain to see if it is an objective line anchored under `button`
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

-- Finds the lowest objective frame (from QuestScrollFrame.objectiveFramePool or Contents) anchored under `button`
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

    -- 1. Check QuestScrollFrame.objectiveFramePool (where WoW places Quest Log objective lines)
    if QuestScrollFrame and QuestScrollFrame.objectiveFramePool and QuestScrollFrame.objectiveFramePool.EnumerateActive then
        for objFrame in QuestScrollFrame.objectiveFramePool:EnumerateActive() do
            CheckCandidate(objFrame)
        end
    end

    -- 2. Also check direct children of QuestScrollFrame.Contents & button
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
    if levelSortMode == "ASC" then sortDesc = " • Asc " .. ICON_ARROW_UP
    elseif levelSortMode == "DESC" then sortDesc = " • Desc " .. ICON_ARROW_DOWN
    end

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

local function UpdateQuestLogUI(fromBlizzardQuestLogUpdate)
    if isUpdatingQuestLogLayout then return end
    isUpdatingQuestLogLayout = true

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

                        -- Capture Blizzard's fresh native height (which includes Title + all Objective lines)
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
                                    -- Anchor 4px below the bottom-most objective line (left-aligned with the objective text)
                                    button.qrfBadge:SetPoint("TOPLEFT", lowestAnchor, "BOTTOMLEFT", 0, -4)
                                    button.qrfBadge:SetPoint("RIGHT", button, "RIGHT", -28, 0)
                                elseif baseH > 26 then
                                    -- Fallback if objectives are included in baseH: place at the bottom of the native span
                                    button.qrfBadge:SetPoint("TOPLEFT", button, "TOPLEFT", leftX, -(baseH - 1))
                                    button.qrfBadge:SetPoint("RIGHT", button, "RIGHT", -28, 0)
                                else
                                    -- Quest has no objective lines (title only): anchor 4px below the quest title
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

    isUpdatingQuestLogLayout = false
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

    local listStartY = -76
    if isLevelTab then
        menuFrame.levelControlsBar:Show()
        menuFrame.sortOffBtn:SetText(levelSortMode == "NONE" and "|cFFFFD100Off|r" or "|cFF888888Off|r")
        menuFrame.sortAscBtn:SetText((levelSortMode == "ASC" and "|cFFFFD100Asc |r" or "|cFFCCCCCCAsc |r") .. ICON_ARROW_UP)
        menuFrame.sortDescBtn:SetText((levelSortMode == "DESC" and "|cFFFFD100Desc |r" or "|cFFCCCCCCDesc |r") .. ICON_ARROW_DOWN)
        listStartY = -102
    else
        menuFrame.levelControlsBar:Hide()
    end

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

    menuFrame.doneBtn:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -8, 8)

    local finalWidth = math.min(math.max(maxWidth, 285), 340)
    local finalHeight = math.abs(yOffset) + 72
    menuFrame:SetSize(finalWidth, finalHeight)
end

-- ============================================================================
-- SHARED DROPDOWN MENU FRAME CREATION
-- ============================================================================
local function ResetAllFilters()
    wipe(selectedFilters)
    wipe(selectedLevelFilters)
    levelSortMode = "NONE"
    dropdownSearchText = ""
    if sharedMenuFrame and sharedMenuFrame.searchBox then
        sharedMenuFrame.searchBox:SetText("")
    end
    ApplyFilterChanges()
    if sharedMenuFrame and sharedMenuFrame:IsShown() then
        RebuildDropdownMenu(sharedMenuFrame, false)
    end
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

    local levelControlsBar = CreateFrame("Frame", nil, menuFrame)
    levelControlsBar:SetHeight(22)
    levelControlsBar:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, -74)
    levelControlsBar:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, -74)

    levelControlsBar.bg = levelControlsBar:CreateTexture(nil, "BACKGROUND")
    levelControlsBar.bg:SetAllPoints()
    levelControlsBar.bg:SetColorTexture(0.12, 0.14, 0.18, 0.90)

    levelControlsBar.label = levelControlsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelControlsBar.label:SetPoint("LEFT", levelControlsBar, "LEFT", 6, 0)
    levelControlsBar.label:SetText("|cFFFFD100Sort Level:|r")

    local sortDescBtn = CreateFrame("Button", nil, levelControlsBar, "UIPanelButtonTemplate")
    sortDescBtn:SetSize(60, 18)
    sortDescBtn:SetPoint("RIGHT", levelControlsBar, "RIGHT", -4, 0)
    sortDescBtn:SetScript("OnClick", function()
        levelSortMode = (levelSortMode == "DESC") and "NONE" or "DESC"
        ApplyFilterChanges()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.sortDescBtn = sortDescBtn

    local sortAscBtn = CreateFrame("Button", nil, levelControlsBar, "UIPanelButtonTemplate")
    sortAscBtn:SetSize(56, 18)
    sortAscBtn:SetPoint("RIGHT", sortDescBtn, "LEFT", -3, 0)
    sortAscBtn:SetScript("OnClick", function()
        levelSortMode = (levelSortMode == "ASC") and "NONE" or "ASC"
        ApplyFilterChanges()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.sortAscBtn = sortAscBtn

    local sortOffBtn = CreateFrame("Button", nil, levelControlsBar, "UIPanelButtonTemplate")
    sortOffBtn:SetSize(38, 18)
    sortOffBtn:SetPoint("RIGHT", sortAscBtn, "LEFT", -3, 0)
    sortOffBtn:SetScript("OnClick", function()
        levelSortMode = "NONE"
        ApplyFilterChanges()
        RebuildDropdownMenu(menuFrame, false)
    end)
    menuFrame.sortOffBtn = sortOffBtn
    menuFrame.levelControlsBar = levelControlsBar

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
    mapBadgeRow.label:SetText("|cFFCCCCCCShow lvl & currency icons|r")
    mapBadgeRow:SetScript("OnClick", function()
        showMapBadges = not showMapBadges
        mapBadgeRow.check:SetChecked(showMapBadges)
        SaveState()
        UpdateWorldMapPins()
    end)
    menuFrame.mapBadgeRow = mapBadgeRow

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

        -- Line 1: Quest Title
        row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
        row.titleText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.titleText:SetJustifyH("LEFT")
        row.titleText:SetWordWrap(false)

        -- Line 2: Objective Description
        row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.zoneText:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -3)
        row.zoneText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.zoneText:SetJustifyH("LEFT")
        row.zoneText:SetWordWrap(false)

        -- Line 3: Left-Aligned Currency / Reward Line Under the Description
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

-- Slash Commands (/cfq or /cacheforquest)
SLASH_CACHEFORQUEST1 = "/cfq"
SLASH_CACHEFORQUEST2 = "/cacheforquest"
SlashCmdList["CACHEFORQUEST"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    if cmd == "reset" then
        ResetAllFilters()
    elseif cmd == "asc" then
        levelSortMode = "ASC"
        ApplyFilterChanges()
    elseif cmd == "desc" then
        levelSortMode = "DESC"
        ApplyFilterChanges()
    else
        local anchor = trackerFilterBtn or (questLogBar and questLogBar.rewardBtn) or UIParent
        ToggleMenuAtButton(anchor, true, "LEVELS")
    end
end

-- ============================================================================
-- INITIALIZATION & OBJECTIVE TRACKER HOOKS
-- ============================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("QUEST_LOG_UPDATE")
loader:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
loader:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
loader:RegisterEvent("SUPER_TRACKING_CHANGED")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "CacheForQuest" then
        LoadState()
    elseif event == "PLAYER_ENTERING_WORLD" then
        LoadState()
        CreateQuestLogUI()
        CreateObjectiveTrackerButton()
        HookAllMapTooltips()

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

        ApplyFilterChanges()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "SUPER_TRACKING_CHANGED" then
        LayoutObjectiveTrackerWithStacks()
        if QuestScrollFrame and QuestScrollFrame:IsShown() and IsQuestLogOverrideActive() then
            RenderCustomFilteredList()
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_WATCH_LIST_CHANGED" or event == "PLAYER_LEVEL_UP" then
        if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
        if not isSyncingTracker then
            ScanQuestLogRewards()
            SyncObjectiveTracker()
            UpdateQuestLogUI(false)
            if sharedMenuFrame and sharedMenuFrame:IsShown() then
                RebuildDropdownMenu(sharedMenuFrame, false)
            end
        end
    end
end)