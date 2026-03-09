-- FlipScan: AH Hook Layer
-- Hooks into Auctionator's and/or Blizzard's AH result row rendering
-- to feed listing data to the ListingCollector for batch anchor pricing.
--
-- Two hook systems run in parallel:
--   1. Auctionator hooks: Hook Populate on each row mixin for Auctionator's
--      custom tabs (Shopping, Selling, Cancelling, etc.)
--      Each Populate adds a listing to ListingCollector; a deferred timer
--      fires after all rows populate to compute anchor and apply overlays.
--   2. Blizzard hooks: Hook ScrollBox events + scan rowData on Blizzard's
--      native tabs (Buy, Sell, Auctions) which Auctionator does not replace.
--      Collects all visible listings first, then computes anchor and applies.

local FlipScan = FlipScan

-- Pending batch data for Auctionator deferred processing.
-- Keyed by itemID, each entry holds the list of row frames to overlay.
local pendingAuctionatorRows = {}
local auctionatorBatchTimer = nil

--- Extract an itemID from an item link via string match.
-- @param itemLink (string) A WoW item link.
-- @return (number|nil) The item ID, or nil if it cannot be extracted.
local function ExtractItemID(itemLink)
    if not itemLink then return nil end
    local id = itemLink:match("item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

--- Initialize the hook system. Called from FlipScan:OnAddonLoaded().
function FlipScan.Hooks:Init()
    if FlipScan.hasAuctionator and AuctionatorResultsRowTemplateMixin then
        self:HookAuctionator()
    end

    -- Always register Blizzard AH events as a baseline / fallback
    self:HookBlizzardAH()

    FlipScan:Debug("AH hook layer initialized.")
end

-----------------------------------------------------------------------
-- Auctionator Hooks
-----------------------------------------------------------------------

function FlipScan.Hooks:HookAuctionator()
    local populateHook = function(rowFrame, rowData, dataIndex)
        if not FlipScan.Config:Get("enabled") then
            FlipScan.Overlay:ClearRowOverlay(rowFrame)
            return
        end
        FlipScan.Hooks:OnAuctionatorRowPopulate(rowFrame, rowData, dataIndex)
    end

    -- All known Auctionator row mixins that display prices.
    local rowMixins = {
        { name = "Base",           mixin = AuctionatorResultsRowTemplateMixin },
        { name = "Shopping",       mixin = AuctionatorShoppingResultsRowMixin },
        { name = "BuyItem",        mixin = AuctionatorBuyItemRowMixin },
        { name = "BuyCommodity",   mixin = AuctionatorBuyCommodityRowMixin },
        { name = "SellSearch",     mixin = AuctionatorSellSearchRowMixin },
        { name = "Cancelling",     mixin = AuctionatorCancellingListResultsRowMixin },
    }

    local hookedCount = 0
    for _, entry in ipairs(rowMixins) do
        if entry.mixin and entry.mixin.Populate then
            local ok, err = pcall(function()
                hooksecurefunc(entry.mixin, "Populate", populateHook)
            end)
            if ok then
                hookedCount = hookedCount + 1
                FlipScan:Debug("Hooked Auctionator " .. entry.name .. " row Populate.")
            else
                FlipScan:Debug("Failed to hook " .. entry.name .. ": " .. tostring(err))
            end
        end
    end

    if hookedCount > 0 then
        self._auctionatorHooked = true
        FlipScan:Debug("Hooked " .. hookedCount .. " Auctionator row mixin(s).")
    end
end

--- Try to get an item link from an item ID, using available APIs.
-- @param itemID (number) The item ID.
-- @return (string|nil) The item link, or nil if unavailable.
local function GetItemLinkFromID(itemID)
    if not itemID then return nil end
    if GetItemInfo then
        local _, link = GetItemInfo(itemID)
        if link then return link end
    end
    if C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(itemID)
        if link then return link end
    end
    return nil
end

--- Extract an item link from row data and/or the row frame context.
-- @param rowFrame (Frame) The AH result row frame.
-- @param rowData  (table) The data passed to Populate.
-- @return (string|nil) The item link, or nil if it cannot be determined.
local function ExtractItemLink(rowFrame, rowData)
    if rowData.itemLink then
        return rowData.itemLink
    end

    if rowData.itemKey then
        local link = GetItemLinkFromID(rowData.itemKey.itemID)
        if link then return link end
    end

    if type(rowFrame.GetItemLink) == "function" then
        local ok, link = pcall(rowFrame.GetItemLink, rowFrame)
        if ok and link then return link end
    end

    local parent = rowFrame:GetParent()
    local depth = 0
    while parent and depth < 8 do
        if parent.itemKey then
            local link = GetItemLinkFromID(parent.itemKey.itemID)
            if link then return link end
        end
        if type(parent.itemLink) == "string" then
            return parent.itemLink
        end
        parent = parent:GetParent()
        depth = depth + 1
    end

    return nil
end

--- Extract quantity from Auctionator row data.
-- Different tabs expose quantity differently.
-- @param rowData (table) The data passed to Populate.
-- @return (number) The quantity (defaults to 1).
local function ExtractQuantity(rowData)
    return rowData.quantity or rowData.numItems or rowData.totalQuantity or 1
end

--- Called each time Auctionator populates a result row with data.
-- Collects the listing into ListingCollector and schedules a deferred
-- batch overlay pass after all rows in this cycle have populated.
function FlipScan.Hooks:OnAuctionatorRowPopulate(rowFrame, rowData, dataIndex)
    -- Deduplicate
    if rowFrame._flipScanLastIndex == dataIndex and rowFrame._flipScanLastData == rowData then
        return
    end
    rowFrame._flipScanLastIndex = dataIndex
    rowFrame._flipScanLastData = rowData
    if not rowData then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    local buyoutPerItem = rowData.price or rowData.minPrice
    if not buyoutPerItem or buyoutPerItem <= 0 then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    local itemLink = ExtractItemLink(rowFrame, rowData)
    if not itemLink then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    local itemID = ExtractItemID(itemLink)
    if not itemID then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    local quantity = ExtractQuantity(rowData)

    -- Add listing to collector
    FlipScan.ListingCollector:AddListing(itemID, buyoutPerItem, quantity)

    -- Store pending row for deferred batch overlay
    if not pendingAuctionatorRows[itemID] then
        pendingAuctionatorRows[itemID] = {}
    end
    local pending = pendingAuctionatorRows[itemID]
    pending[#pending + 1] = {
        rowFrame = rowFrame,
        itemLink = itemLink,
        buyoutPerItem = buyoutPerItem,
    }

    -- Schedule deferred batch apply (reset timer on each row so we wait
    -- until all rows in this populate cycle have been collected)
    if auctionatorBatchTimer then
        auctionatorBatchTimer:Cancel()
    end
    auctionatorBatchTimer = C_Timer.NewTimer(0.1, function()
        FlipScan.Hooks:ApplyAuctionatorBatch()
        auctionatorBatchTimer = nil
    end)
end

--- Apply overlays to all pending Auctionator rows using the computed anchor price.
function FlipScan.Hooks:ApplyAuctionatorBatch()
    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5

    for itemID, rows in pairs(pendingAuctionatorRows) do
        local anchorPrice = FlipScan.ListingCollector:GetAnchorPrice(itemID)
        if anchorPrice then
            for _, entry in ipairs(rows) do
                local isFlippable, netProfit, marginPct =
                    FlipScan.Calculator.IsFlippable(entry.buyoutPerItem, anchorPrice, minMargin)

                FlipScan.Overlay:ApplyRowOverlay(entry.rowFrame, {
                    itemLink = entry.itemLink,
                    buyoutPerItem = entry.buyoutPerItem,
                    referencePrice = anchorPrice,
                    source = "Anchor",
                    netProfit = netProfit,
                    marginPct = marginPct,
                    isFlippable = isFlippable,
                })
            end
        else
            for _, entry in ipairs(rows) do
                FlipScan.Overlay:ClearRowOverlay(entry.rowFrame)
            end
        end
    end

    -- Clear pending data for next cycle; also reset collector so next
    -- populate cycle starts fresh with whatever rows are visible.
    pendingAuctionatorRows = {}
    FlipScan.ListingCollector:Reset()
end

-----------------------------------------------------------------------
-- Blizzard Native AH Hooks
-----------------------------------------------------------------------

function FlipScan.Hooks:HookBlizzardAH()
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    hookFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    hookFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
    hookFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    hookFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

    hookFrame:SetScript("OnEvent", function(_, event)
        if event == "AUCTION_HOUSE_CLOSED" then
            FlipScan.Overlay:HideAll()
            FlipScan.ListingCollector:Reset()
            return
        end

        if not FlipScan.Config:Get("enabled") then return end

        if event == "AUCTION_HOUSE_SHOW" then
            FlipScan:Debug("AH opened.")
            FlipScan.Hooks:TryHookBlizzardScrollBoxes()
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
            C_Timer.After(0.05, function()
                if FlipScan.Config:Get("enabled") then
                    FlipScan.Hooks:ScanBlizzardRows()
                end
            end)
        else
            C_Timer.After(0.05, function()
                if FlipScan.Config:Get("enabled") then
                    FlipScan.Hooks:ScanBlizzardBrowseRows()
                end
            end)
        end
    end)

    FlipScan.Hooks.hookFrame = hookFrame
end

--- Hook Blizzard's ScrollBox scroll events to refresh overlays on scroll.
function FlipScan.Hooks:TryHookBlizzardScrollBoxes()
    if self._blizzardScrollHooked then return end
    if not AuctionHouseFrame then return end

    local function OnScrollChanged()
        if not FlipScan.Config:Get("enabled") then return end
        C_Timer.After(0.05, function()
            FlipScan.Hooks:ScanBlizzardRows()
            FlipScan.Hooks:ScanBlizzardBrowseRows()
        end)
    end

    local itemLists = {}
    local function CollectItemList(name, frame)
        if frame and frame.ItemList and frame.ItemList.ScrollBox then
            itemLists[#itemLists + 1] = { name = name, scrollBox = frame.ItemList.ScrollBox }
        end
    end

    CollectItemList("Browse", AuctionHouseFrame.BrowseResultsFrame)
    CollectItemList("ItemBuy", AuctionHouseFrame.ItemBuyFrame)

    if AuctionHouseFrame.CommoditiesBuyFrame and AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay then
        local buyDisplay = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay
        if buyDisplay.ItemList and buyDisplay.ItemList.ScrollBox then
            itemLists[#itemLists + 1] = { name = "CommodityBuy", scrollBox = buyDisplay.ItemList.ScrollBox }
        end
    end

    if AuctionHouseFrame.AuctionsFrame then
        CollectItemList("Auctions", AuctionHouseFrame.AuctionsFrame)
        if AuctionHouseFrame.AuctionsFrame.SummaryList and AuctionHouseFrame.AuctionsFrame.SummaryList.ScrollBox then
            itemLists[#itemLists + 1] = {
                name = "AuctionsSummary",
                scrollBox = AuctionHouseFrame.AuctionsFrame.SummaryList.ScrollBox,
            }
        end
    end

    local hookedCount = 0
    for _, entry in ipairs(itemLists) do
        local ok, err = pcall(function()
            entry.scrollBox:RegisterCallback(
                ScrollBoxListMixin.Event.OnDataRangeChanged,
                OnScrollChanged,
                self
            )
        end)
        if ok then
            hookedCount = hookedCount + 1
            FlipScan:Debug("Hooked Blizzard " .. entry.name .. " ScrollBox.")
        else
            FlipScan:Debug("Failed to hook " .. entry.name .. " ScrollBox: " .. tostring(err))
        end
    end

    if hookedCount > 0 then
        self._blizzardScrollHooked = true
    end
end

--- Scan visible row frames in Blizzard's native item search results.
function FlipScan.Hooks:ScanBlizzardRows()
    if not AuctionHouseFrame then return end

    if AuctionHouseFrame.ItemBuyFrame and AuctionHouseFrame.ItemBuyFrame.ItemList then
        self:ScanBlizzardItemList(AuctionHouseFrame.ItemBuyFrame.ItemList, "ItemBuy")
    end

    if AuctionHouseFrame.CommoditiesBuyFrame and AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay then
        local buyDisplay = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay
        if buyDisplay.ItemList then
            self:ScanBlizzardItemList(buyDisplay.ItemList, "CommodityBuy")
        end
    end

    if AuctionHouseFrame.AuctionsFrame then
        if AuctionHouseFrame.AuctionsFrame.ItemList then
            self:ScanBlizzardItemList(AuctionHouseFrame.AuctionsFrame, "Auctions")
        end
    end
end

--- Scan visible row frames in Blizzard's browse results.
function FlipScan.Hooks:ScanBlizzardBrowseRows()
    if not AuctionHouseFrame then return end
    if not AuctionHouseFrame.BrowseResultsFrame then return end

    self:ScanBlizzardItemList(AuctionHouseFrame.BrowseResultsFrame.ItemList, "Browse")
end

--- Scan a single Blizzard AuctionHouseItemList for visible row frames.
-- Two-pass approach: first collect all listings into ListingCollector,
-- then compute anchor prices and apply overlays.
function FlipScan.Hooks:ScanBlizzardItemList(itemList, debugLabel)
    if not itemList or not itemList.ScrollBox then return end

    local frames = itemList.ScrollBox:GetFrames()
    if not frames then return end

    -- Reset collector for this scan
    FlipScan.ListingCollector:Reset()

    -- Pass 1: Collect all listings
    local rowEntries = {}
    for _, rowFrame in ipairs(frames) do
        if rowFrame:IsVisible() and rowFrame.rowData then
            -- Skip Auctionator-managed frames
            if not rowFrame._flipScanLastData then
                local rowData = rowFrame.rowData
                local buyoutPerItem, itemLink, itemID, quantity = self:ExtractBlizzardRowData(rowFrame, rowData)

                if buyoutPerItem and itemLink and itemID then
                    FlipScan.ListingCollector:AddListing(itemID, buyoutPerItem, quantity)
                    rowEntries[#rowEntries + 1] = {
                        rowFrame = rowFrame,
                        itemLink = itemLink,
                        itemID = itemID,
                        buyoutPerItem = buyoutPerItem,
                    }
                end
            end
        end
    end

    -- Pass 2: Compute anchors and apply overlays
    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5
    for _, entry in ipairs(rowEntries) do
        local anchorPrice = FlipScan.ListingCollector:GetAnchorPrice(entry.itemID)
        if anchorPrice then
            local isFlippable, netProfit, marginPct =
                FlipScan.Calculator.IsFlippable(entry.buyoutPerItem, anchorPrice, minMargin)

            FlipScan.Overlay:ApplyRowOverlay(entry.rowFrame, {
                itemLink = entry.itemLink,
                buyoutPerItem = entry.buyoutPerItem,
                referencePrice = anchorPrice,
                source = "Anchor",
                netProfit = netProfit,
                marginPct = marginPct,
                isFlippable = isFlippable,
            })
        else
            FlipScan.Overlay:ClearRowOverlay(entry.rowFrame)
        end
    end
end

--- Extract price, item link, item ID, and quantity from a Blizzard row.
-- @param rowFrame (Frame) The AH result row frame.
-- @param rowData  (table) The rowData from Blizzard's TableBuilder.
-- @return buyoutPerItem (number|nil), itemLink (string|nil), itemID (number|nil), quantity (number)
function FlipScan.Hooks:ExtractBlizzardRowData(rowFrame, rowData)
    local buyoutPerItem = nil
    local itemLink = nil
    local itemID = nil
    local quantity = 1

    -- Item search results (ItemBuyFrame)
    if rowData.buyoutAmount and rowData.buyoutAmount > 0 then
        buyoutPerItem = rowData.buyoutAmount
        itemLink = rowData.itemLink
        quantity = rowData.quantity or 1
    -- Commodity results
    elseif rowData.unitPrice and rowData.unitPrice > 0 then
        buyoutPerItem = rowData.unitPrice
        itemLink = rowData.itemLink
        if not itemLink and rowData.itemID then
            itemLink = GetItemLinkFromID(rowData.itemID)
        end
        quantity = rowData.quantity or 1
    -- Browse results have minPrice and itemKey
    elseif rowData.minPrice and rowData.minPrice > 0 and rowData.itemKey then
        buyoutPerItem = rowData.minPrice
        itemLink = GetItemLinkFromID(rowData.itemKey.itemID)
        quantity = rowData.totalQuantity or 1
    end

    if itemLink then
        itemID = ExtractItemID(itemLink)
    end

    return buyoutPerItem, itemLink, itemID, quantity
end
