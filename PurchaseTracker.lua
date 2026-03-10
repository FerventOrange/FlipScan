-- FlipScan: Purchase Tracker
-- Hooks commodity purchases and prints a buy summary to chat
-- showing quantity, total cost, average cost, and minimum resell price.

local FlipScan = FlipScan

-- Pending purchase data (set when a commodity purchase starts, cleared on success/failure)
local pending = nil

--- Initialize the purchase tracker. Called from FlipScan:OnAddonLoaded().
function FlipScan.PurchaseTracker:Init()
    -- Hook StartCommoditiesPurchase to capture what the player is buying
    if C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase then
        hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, qty)
            FlipScan.PurchaseTracker:OnPurchaseStarted(itemID, qty)
        end)
    end

    -- Register for purchase result events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
    eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "COMMODITY_PURCHASE_SUCCEEDED" then
            FlipScan.PurchaseTracker:OnPurchaseSucceeded()
        elseif event == "COMMODITY_PURCHASE_FAILED" then
            pending = nil
        end
    end)

    FlipScan:Debug("PurchaseTracker initialized.")
end

--- Called when the player starts a commodity purchase.
-- Walks the current search results to compute the total cost for the requested quantity.
-- @param itemID  (number) The item being purchased.
-- @param quantity (number) How many units the player is buying.
function FlipScan.PurchaseTracker:OnPurchaseStarted(itemID, quantity)
    if not itemID or not quantity or quantity <= 0 then
        pending = nil
        return
    end

    -- Get the item link for display
    local itemLink = nil
    if GetItemInfo then
        local _, link = GetItemInfo(itemID)
        itemLink = link
    end
    if not itemLink and C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(itemID)
        itemLink = link
    end

    -- Walk search results cheapest-first to compute total cost
    local totalCost = 0
    local remaining = quantity
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0

    for i = 1, numResults do
        if remaining <= 0 then break end
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if result and result.unitPrice and result.quantity then
            local take = math.min(result.quantity, remaining)
            totalCost = totalCost + (result.unitPrice * take)
            remaining = remaining - take
        end
    end

    pending = {
        itemID = itemID,
        quantity = quantity,
        totalCost = totalCost,
        itemLink = itemLink or ("item:" .. itemID),
    }

    FlipScan:Debug(string.format(
        "PurchaseTracker: started purchase of %dx %s for %s",
        quantity, tostring(pending.itemLink),
        FlipScan.Calculator.FormatGold(totalCost)
    ))
end

--- Called when a commodity purchase succeeds. Prints the buy summary.
function FlipScan.PurchaseTracker:OnPurchaseSucceeded()
    if not pending then return end

    local avgCost = math.floor(pending.totalCost / pending.quantity)
    local minMargin = FlipScan.Config:Get("minMarginPercent") or 7.5
    local minResell = math.ceil(avgCost * (1 + minMargin / 100))

    -- Format total cost with comma-separated gold
    local totalGold = math.floor(pending.totalCost / 10000)
    local totalSilver = math.floor((pending.totalCost % 10000) / 100)
    local formattedTotal = string.format("%sg %02ds", FormatLargeNumber(totalGold), totalSilver)

    FlipScan:Print(string.format(
        "Bought %dx %s for %s (%s avg). Min resell: %s",
        pending.quantity,
        pending.itemLink,
        formattedTotal,
        FlipScan.Calculator.FormatGold(avgCost),
        FlipScan.Calculator.FormatGold(minResell)
    ))

    pending = nil
end
