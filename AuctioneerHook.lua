-- FlipScan: AH Hook Layer
-- Hooks into Blizzard's native Auction House UI to feed listing data
-- to the overlay and tooltip systems.

local FlipScan = FlipScan

--- Initialize the hook system. Called from FlipScan:OnAddonLoaded().
function FlipScan.Hooks:Init()
    self:HookBlizzardAH()
    FlipScan:Debug("AH hook layer initialized.")
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

    hookFrame:SetScript("OnEvent", function(_, event)
        if not FlipScan.Config:Get("enabled") then return end

        if event == "AUCTION_HOUSE_SHOW" then
            FlipScan:Debug("AH opened.")
        else
            FlipScan:Debug("Search results updated — refreshing overlays.")
            FlipScan.Hooks:ScanVisibleRows()
        end
    end)

    FlipScan.Hooks.hookFrame = hookFrame
end

--- Scan all currently visible result rows and send data to the Overlay system.
function FlipScan.Hooks:ScanVisibleRows()
    if not FlipScan.Config:Get("enabled") then
        FlipScan.Overlay:HideAll()
        return
    end

    local results = {}

    local ok, data = pcall(function()
        return FlipScan.Hooks:ReadBlizzardResults()
    end)
    if ok and data then
        results = data
    end

    -- Pass the results to the Overlay system for visual rendering
    if FlipScan.Overlay.UpdateRows then
        FlipScan.Overlay:UpdateRows(results)
    end
end

--- Read result data from Blizzard's C_AuctionHouse API.
-- @return (table) Array of { rowIndex, itemLink, buyoutPerItem, referencePrice, source, rowFrame }
function FlipScan.Hooks:ReadBlizzardResults()
    local results = {}

    if not C_AuctionHouse then return results end

    -- Read item search results from the native API
    local numResults = C_AuctionHouse.GetNumItemSearchResults() or 0
    for i = 1, numResults do
        local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(i)
        if resultInfo and resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0 then
            local itemLink = resultInfo.itemLink
            local buyoutPerItem = resultInfo.buyoutAmount
            local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)

            -- Try to find the corresponding row frame in the AH UI
            local rowFrame = nil
            if AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame then
                local listFrame = AuctionHouseFrame.BrowseResultsFrame.ItemList
                if listFrame and listFrame.ScrollBox then
                    -- Retail uses ScrollBox with data provider
                    local frames = listFrame.ScrollBox:GetFrames()
                    if frames and frames[i] then
                        rowFrame = frames[i]
                    end
                end
            end

            results[#results + 1] = {
                rowIndex = i,
                itemLink = itemLink,
                buyoutPerItem = buyoutPerItem,
                referencePrice = refPrice,
                source = source,
                rowFrame = rowFrame,
            }
        end
    end

    return results
end
