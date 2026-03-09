-- FlipScan: AH Hook Layer
-- Hooks into Auctionator's and/or Blizzard's AH result row rendering
-- to feed listing data to the overlay system.
--
-- Two hook systems run in parallel:
--   1. Auctionator hooks: Hook Populate on each row mixin for Auctionator's
--      custom tabs (Shopping, Selling, Cancelling, etc.)
--   2. Blizzard hooks: Hook ScrollBox events + scan rowData on Blizzard's
--      native tabs (Buy, Sell, Auctions) which Auctionator does not replace.

local FlipScan = FlipScan

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
    -- Auctionator's row mixins are created via CreateFromMixins(), which copies
    -- function references at definition time. Hooking the base mixin only
    -- catches derived mixins that explicitly call the base Populate — those
    -- that inherit without overriding get a stale copy. We must hook each
    -- derived mixin's Populate individually to cover all tabs.
    local populateHook = function(rowFrame, rowData, dataIndex)
        if not FlipScan.Config:Get("enabled") then
            FlipScan.Overlay:ClearRowOverlay(rowFrame)
            return
        end
        FlipScan.Hooks:OnAuctionatorRowPopulate(rowFrame, rowData, dataIndex)
    end

    -- All known Auctionator row mixins that display prices.
    -- Each inherits from AuctionatorResultsRowTemplateMixin.
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
    -- Try the global GetItemInfo first (most reliable across WoW versions)
    if GetItemInfo then
        local _, link = GetItemInfo(itemID)
        if link then return link end
    end
    -- Fallback to C_Item API
    if C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(itemID)
        if link then return link end
    end
    return nil
end

--- Extract an item link from row data and/or the row frame context.
-- Different Auctionator tabs provide item identification differently:
--   Cancelling tab:      rowData.itemLink (direct)
--   Shopping tab:        rowData.itemKey.itemID -> GetItemInfo
--   Buy Item/Commodity:  No item in rowData; must find from parent frame context
-- @param rowFrame (Frame) The AH result row frame.
-- @param rowData  (table) The data passed to Populate.
-- @return (string|nil) The item link, or nil if it cannot be determined.
local function ExtractItemLink(rowFrame, rowData)
    -- 1. Direct itemLink in row data (Cancelling tab, some search results)
    if rowData.itemLink then
        return rowData.itemLink
    end

    -- 2. Build from itemKey in row data (Shopping tab)
    if rowData.itemKey then
        local link = GetItemLinkFromID(rowData.itemKey.itemID)
        if link then return link end
    end

    -- 3. Check row frame for a GetItemLink method (some Auctionator mixins expose this)
    if type(rowFrame.GetItemLink) == "function" then
        local ok, link = pcall(rowFrame.GetItemLink, rowFrame)
        if ok and link then return link end
    end

    -- 4. Traverse parent frames for item context (Buy Item/Commodity tabs).
    --    In these views, the item is known at the list/panel level, not per-row.
    local parent = rowFrame:GetParent()
    local depth = 0
    while parent and depth < 8 do
        -- Check for itemKey on the parent frame
        if parent.itemKey then
            local link = GetItemLinkFromID(parent.itemKey.itemID)
            if link then return link end
        end
        -- Check for a direct itemLink property
        if type(parent.itemLink) == "string" then
            return parent.itemLink
        end
        parent = parent:GetParent()
        depth = depth + 1
    end

    return nil
end

--- Called each time Auctionator populates a result row with data.
-- Extracts the buyout price from the row data and applies an overlay.
-- Uses a generation counter to skip duplicate calls (derived mixins that
-- override Populate and call the base will trigger hooks on both tables).
function FlipScan.Hooks:OnAuctionatorRowPopulate(rowFrame, rowData, dataIndex)
    -- Deduplicate: if we already processed this exact frame+dataIndex combo
    -- in this Populate cycle, skip it. The dataIndex changes on each recycle.
    if rowFrame._flipScanLastIndex == dataIndex and rowFrame._flipScanLastData == rowData then
        return
    end
    rowFrame._flipScanLastIndex = dataIndex
    rowFrame._flipScanLastData = rowData
    if not rowData then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    -- Extract the buyout price from the row data.
    -- Auctionator uses different field names depending on the view:
    --   Shopping results: rowData.minPrice (lowest buyout for that item key)
    --   Buy item results: rowData.price (per-unit buyout)
    --   Buy commodity:    rowData.price (per-unit price)
    local buyoutPerItem = rowData.price or rowData.minPrice
    if not buyoutPerItem or buyoutPerItem <= 0 then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    -- Get the item link via multiple fallback methods
    local itemLink = ExtractItemLink(rowFrame, rowData)

    if not itemLink then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    -- Look up the reference (market) price for this item
    local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)
    if not refPrice then
        FlipScan.Overlay:ClearRowOverlay(rowFrame)
        return
    end

    -- Calculate flip profitability and apply the overlay
    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5
    local isFlippable, netProfit, marginPct =
        FlipScan.Calculator.IsFlippable(buyoutPerItem, refPrice, minMargin)

    FlipScan.Overlay:ApplyRowOverlay(rowFrame, {
        itemLink = itemLink,
        buyoutPerItem = buyoutPerItem,
        referencePrice = refPrice,
        source = source,
        netProfit = netProfit,
        marginPct = marginPct,
        isFlippable = isFlippable,
    })
end

-----------------------------------------------------------------------
-- Blizzard Native AH Hooks
-- These cover the default Buy/Sell/Auctions tabs that Auctionator
-- does not replace. Both hook systems run in parallel.
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
            return
        end

        if not FlipScan.Config:Get("enabled") then return end

        if event == "AUCTION_HOUSE_SHOW" then
            FlipScan:Debug("AH opened.")
            FlipScan.Hooks:TryHookBlizzardScrollBoxes()
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
            -- Item search results updated — scan after a brief delay to let
            -- the TableBuilder finish populating rowData on each frame.
            C_Timer.After(0.05, function()
                if FlipScan.Config:Get("enabled") then
                    FlipScan.Hooks:ScanBlizzardRows()
                end
            end)
        else
            -- Browse results updated/added
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
-- Called once when the AH opens. Safe to call multiple times.
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

    -- Hook all ItemList ScrollBoxes in the Blizzard AH frame.
    -- BrowseResultsFrame.ItemList: the category/item browse list
    -- ItemBuyFrame.ItemList: the per-auction listing when buying items
    -- CommoditiesBuyFrame.ItemList: commodity buy listings
    -- AuctionsFrame.ItemList / SummaryList: the player's own auctions
    local itemLists = {}
    local function CollectItemList(name, frame)
        if frame and frame.ItemList and frame.ItemList.ScrollBox then
            itemLists[#itemLists + 1] = { name = name, scrollBox = frame.ItemList.ScrollBox }
        end
    end

    CollectItemList("Browse", AuctionHouseFrame.BrowseResultsFrame)
    CollectItemList("ItemBuy", AuctionHouseFrame.ItemBuyFrame)

    -- CommoditiesBuyFrame uses a different list structure
    if AuctionHouseFrame.CommoditiesBuyFrame and AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay then
        local buyDisplay = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay
        if buyDisplay.ItemList and buyDisplay.ItemList.ScrollBox then
            itemLists[#itemLists + 1] = { name = "CommodityBuy", scrollBox = buyDisplay.ItemList.ScrollBox }
        end
    end

    -- AuctionsFrame (player's own listings)
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
-- Blizzard's TableBuilder populates button.rowData on each visible row frame.
function FlipScan.Hooks:ScanBlizzardRows()
    if not AuctionHouseFrame then return end

    -- Scan item buy results (individual item listings)
    if AuctionHouseFrame.ItemBuyFrame and AuctionHouseFrame.ItemBuyFrame.ItemList then
        self:ScanBlizzardItemList(AuctionHouseFrame.ItemBuyFrame.ItemList, "ItemBuy")
    end

    -- Scan commodity buy results
    if AuctionHouseFrame.CommoditiesBuyFrame and AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay then
        local buyDisplay = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay
        if buyDisplay.ItemList then
            self:ScanBlizzardItemList(buyDisplay.ItemList, "CommodityBuy")
        end
    end

    -- Scan player's own auctions
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

--- Scan a single Blizzard AuctionHouseItemList for visible row frames
--- and apply overlays based on their rowData.
function FlipScan.Hooks:ScanBlizzardItemList(itemList, debugLabel)
    if not itemList or not itemList.ScrollBox then return end

    local frames = itemList.ScrollBox:GetFrames()
    if not frames then return end

    for _, rowFrame in ipairs(frames) do
        if rowFrame:IsVisible() and rowFrame.rowData then
            local rowData = rowFrame.rowData

            -- Skip if this frame is managed by Auctionator (has _flipScanLastData set)
            if rowFrame._flipScanLastData then
                -- Already handled by Auctionator hook
            else
                self:ProcessBlizzardRow(rowFrame, rowData, debugLabel)
            end
        end
    end
end

--- Process a single Blizzard AH row and apply overlay.
function FlipScan.Hooks:ProcessBlizzardRow(rowFrame, rowData, debugLabel)
    -- Blizzard browse results have itemKey (not a direct price per item)
    -- Item search results have buyoutAmount and itemLink
    local buyoutPerItem = nil
    local itemLink = nil

    -- Item search results (ItemBuyFrame)
    if rowData.buyoutAmount and rowData.buyoutAmount > 0 then
        buyoutPerItem = rowData.buyoutAmount
        itemLink = rowData.itemLink
    -- Commodity results
    elseif rowData.unitPrice and rowData.unitPrice > 0 then
        buyoutPerItem = rowData.unitPrice
        -- Commodity rows don't always carry an itemLink; try from parent context
        itemLink = rowData.itemLink
        if not itemLink and rowData.itemID then
            itemLink = GetItemLinkFromID(rowData.itemID)
        end
    -- Browse results have minPrice and itemKey
    elseif rowData.minPrice and rowData.minPrice > 0 and rowData.itemKey then
        buyoutPerItem = rowData.minPrice
        itemLink = GetItemLinkFromID(rowData.itemKey.itemID)
    end

    if not buyoutPerItem or not itemLink then
        return
    end

    local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)
    if not refPrice then return end

    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5
    local isFlippable, netProfit, marginPct =
        FlipScan.Calculator.IsFlippable(buyoutPerItem, refPrice, minMargin)

    FlipScan.Overlay:ApplyRowOverlay(rowFrame, {
        itemLink = itemLink,
        buyoutPerItem = buyoutPerItem,
        referencePrice = refPrice,
        source = source,
        netProfit = netProfit,
        marginPct = marginPct,
        isFlippable = isFlippable,
    })
end
