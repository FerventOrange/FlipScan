-- FlipScan: AH Hook Layer
-- Hooks into Auctionator's and/or Blizzard's AH result row rendering
-- to feed listing data to the overlay system.
--
-- When Auctionator is present, we hook AuctionatorResultsRowTemplateMixin:Populate
-- so every row gets an overlay applied the moment it receives data. This also
-- handles scroll recycling automatically since Populate fires on reuse.
--
-- Without Auctionator, we fall back to Blizzard AH events + C_AuctionHouse API.

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

    -- Build an item link from the item key if available
    local itemLink = nil
    if rowData.itemLink then
        itemLink = rowData.itemLink
    elseif rowData.itemKey then
        -- Auctionator stores itemKey as { itemID, itemLevel, itemSuffix, battlePetSpeciesID }
        local itemID = rowData.itemKey.itemID
        if itemID then
            -- Get the item link from the item ID
            local _, link = C_Item.GetItemInfo(itemID)
            if not link and GetItemInfo then
                _, link = GetItemInfo(itemID)
            end
            itemLink = link
        end
    end

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
-- Blizzard Native AH Hooks (fallback when Auctionator is absent)
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

        -- If Auctionator is handling overlays via Populate hooks, skip the
        -- Blizzard fallback scan to avoid double-processing.
        if FlipScan.Hooks._auctionatorHooked then return end

        if event == "AUCTION_HOUSE_SHOW" then
            FlipScan:Debug("AH opened.")
        else
            FlipScan:Debug("Search results updated — refreshing overlays.")
            FlipScan.Hooks:ScanBlizzardRows()
        end
    end)

    FlipScan.Hooks.hookFrame = hookFrame
end

--- Fallback: scan Blizzard's native AH results when Auctionator is not present.
function FlipScan.Hooks:ScanBlizzardRows()
    if not FlipScan.Config:Get("enabled") then
        FlipScan.Overlay:HideAll()
        return
    end

    if not C_AuctionHouse then return end

    local numResults = C_AuctionHouse.GetNumItemSearchResults() or 0
    for i = 1, numResults do
        local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(i)
        if resultInfo and resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0 then
            local itemLink = resultInfo.itemLink
            local buyoutPerItem = resultInfo.buyoutAmount
            local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)

            -- Try to find the row frame in Blizzard's native ScrollBox
            local rowFrame = nil
            if AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame then
                local listFrame = AuctionHouseFrame.BrowseResultsFrame.ItemList
                if listFrame and listFrame.ScrollBox then
                    local frames = listFrame.ScrollBox:GetFrames()
                    if frames and frames[i] then
                        rowFrame = frames[i]
                    end
                end
            end

            if rowFrame and refPrice then
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
        end
    end
end
