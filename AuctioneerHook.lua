-- FlipScan: Auctioneer Hook Layer
-- Hooks into Auctioneer's result row rendering to feed data to the overlay system.
-- Falls back to Blizzard's native AH frame if Auctioneer is unavailable.

local FlipScan = FlipScan

local hasAuctioneer = false

--- Initialize the hook system. Called from FlipScan:OnAddonLoaded().
function FlipScan.Hooks:Init()
    hasAuctioneer = (AucAdvanced ~= nil)

    if hasAuctioneer then
        FlipScan:Debug("Auctioneer detected. Attempting to hook result rows.")
        self:HookAuctioneer()
    else
        FlipScan:Print("Auctioneer not detected. Operating in standalone mode with limited price data.")
        self:HookBlizzardAH()
    end
end

-----------------------------------------------------------------------
-- Auctioneer Hooks
-----------------------------------------------------------------------

function FlipScan.Hooks:HookAuctioneer()
    -- Auctioneer renders search results via its SearchUI module.
    -- We hook the frame update cycle so we can scan visible rows after
    -- Auctioneer finishes populating them.

    -- Strategy: Hook the AuctionFrame's Show event to watch for the browse tab,
    -- then hook Auctioneer's result list scroll frame updates.

    -- Wait for AuctionFrame to be available (it loads on demand when visiting an AH NPC)
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    hookFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    hookFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")

    hookFrame:SetScript("OnEvent", function(_, event)
        if not FlipScan.Config:Get("enabled") then return end

        if event == "AUCTION_HOUSE_SHOW" then
            FlipScan:Debug("AH opened — setting up Auctioneer row hooks.")
            FlipScan.Hooks:TryHookAuctioneerRows()
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or
               event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            FlipScan:Debug("Browse results updated — refreshing overlays.")
            FlipScan.Hooks:ScanVisibleRows()
        end
    end)

    FlipScan.Hooks.hookFrame = hookFrame
end

--- Attempt to hook Auctioneer's browse result buttons.
-- Auctioneer's SearchUI typically creates buttons named like
-- AucAdvSrchPgBtmList[N] or similar. We look for the scroll frame
-- and hook its update function.
function FlipScan.Hooks:TryHookAuctioneerRows()
    local ok, err = pcall(function()
        -- Check for Auctioneer's SearchUI scroll frame
        local searchFrame = AucAdvanced and AucAdvanced.Modules
            and AucAdvanced.Modules.Util
            and AucAdvanced.Modules.Util.SearchUI

        if searchFrame and searchFrame.Frame and not self._aucHooked then
            -- Hook the Update method on the search frame's result list
            local resultList = searchFrame.Frame
            if resultList.Update then
                hooksecurefunc(resultList, "Update", function()
                    if FlipScan.Config:Get("enabled") then
                        FlipScan.Hooks:ScanVisibleRows()
                    end
                end)
                self._aucHooked = true
                FlipScan:Debug("Hooked Auctioneer SearchUI Update.")
            end
        end

        -- Also attempt to hook the scroll frame's SetPoint or Show
        -- to catch scrolling events
        if BrowseScrollFrame and not self._scrollHooked then
            hooksecurefunc(BrowseScrollFrame, "update", function()
                if FlipScan.Config:Get("enabled") then
                    FlipScan.Hooks:ScanVisibleRows()
                end
            end)
            self._scrollHooked = true
            FlipScan:Debug("Hooked BrowseScrollFrame update.")
        end
    end)

    if not ok then
        FlipScan:Debug("Could not hook Auctioneer rows: " .. tostring(err))
    end
end

--- Scan all currently visible result rows and send data to the Overlay system.
-- Works with both Auctioneer and Blizzard native frames.
function FlipScan.Hooks:ScanVisibleRows()
    if not FlipScan.Config:Get("enabled") then
        FlipScan.Overlay:HideAll()
        return
    end

    local results = {}

    -- Try to read from Auctioneer's data first
    if hasAuctioneer and AucAdvanced and AucAdvanced.API then
        local ok, data = pcall(function()
            return FlipScan.Hooks:ReadAuctioneerResults()
        end)
        if ok and data then
            results = data
        end
    end

    -- If Auctioneer didn't yield results, try the native AH API
    if #results == 0 then
        local ok, data = pcall(function()
            return FlipScan.Hooks:ReadBlizzardResults()
        end)
        if ok and data then
            results = data
        end
    end

    -- Pass the results to the Overlay system for visual rendering
    if FlipScan.Overlay.UpdateRows then
        FlipScan.Overlay:UpdateRows(results)
    end
end

--- Read result data from Auctioneer's internal structures.
-- @return (table) Array of { rowIndex, itemLink, buyoutPerItem, referencePrice, source, rowFrame }
function FlipScan.Hooks:ReadAuctioneerResults()
    local results = {}

    -- Auctioneer SearchUI maintains a list of visible row buttons.
    -- Each button stores item data we can read.
    -- Iterate visible buttons (typically 8-14 rows on screen)
    for i = 1, 50 do
        local buttonName = "BrowseButton" .. i
        local button = _G[buttonName]
        if not button or not button:IsVisible() then break end

        local itemLink = button.itemLink or (button.GetItemLink and button:GetItemLink())
        local buyout = button.buyoutPrice or 0
        local count = button.count or 1

        if itemLink and buyout and buyout > 0 then
            local buyoutPerItem = buyout / count
            local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)

            results[#results + 1] = {
                rowIndex = i,
                itemLink = itemLink,
                buyoutPerItem = buyoutPerItem,
                referencePrice = refPrice,
                source = source,
                rowFrame = button,
            }
        end
    end

    return results
end

-----------------------------------------------------------------------
-- Blizzard Native AH Hooks (fallback / standalone mode)
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
            FlipScan:Debug("AH opened (standalone mode).")
        else
            FlipScan:Debug("Search results updated (standalone) — refreshing overlays.")
            FlipScan.Hooks:ScanVisibleRows()
        end
    end)

    FlipScan.Hooks.hookFrame = hookFrame
end

--- Read result data from Blizzard's C_AuctionHouse API.
-- @return (table) Array of { rowIndex, itemLink, buyoutPerItem, referencePrice, source }
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
