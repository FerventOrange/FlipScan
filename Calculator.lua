-- FlipScan: Profit Calculation Engine
-- Pure math — no UI or frame dependencies. All values are in copper.

local FlipScan = FlipScan

-- The Auction House takes a 5% cut from the sale price.
local AH_CUT = 0.05
local SELLER_KEEPS = 1 - AH_CUT  -- 0.95
FlipScan.Calculator.SELLER_KEEPS = SELLER_KEEPS

--- Determine if an item is a profitable flip.
--
-- @param buyoutPerItem    (number) The current listing price per item in copper.
--                         This is what you would pay to buy the item right now.
-- @param referencePrice   (number) The expected market value per item in copper.
--                         This is what you expect to resell it for.
-- @param minMarginPercent (number) The minimum net profit margin (%) to qualify
--                         as "flippable". For example, 5 means at least 5% profit.
--
-- @return isFlippable      (boolean) True if net profit meets the minimum margin.
-- @return netProfit        (number)  Estimated profit in copper (can be negative).
-- @return netMarginPercent (number)  Net margin as a percentage of purchase cost.
function FlipScan.Calculator.IsFlippable(buyoutPerItem, referencePrice, minMarginPercent)
    -- Guard against invalid inputs
    if not buyoutPerItem or buyoutPerItem <= 0 then
        return false, 0, 0
    end
    if not referencePrice or referencePrice <= 0 then
        return false, 0, 0
    end

    -- The purchase cost is what you pay for the item right now.
    local purchaseCost = buyoutPerItem

    -- When you resell at the reference price, the AH takes its 5% cut.
    -- You receive: referencePrice * 0.95
    local proceedsAfterCut = referencePrice * SELLER_KEEPS

    -- Net profit = what you receive minus what you paid
    local netProfit = proceedsAfterCut - purchaseCost

    -- Net margin as a percentage of the purchase cost
    -- e.g. if you paid 100g and net 10g, margin = 10%
    local netMarginPercent = (netProfit / purchaseCost) * 100

    -- A flip qualifies if the margin meets or exceeds the minimum threshold
    local isFlippable = netMarginPercent >= (minMarginPercent or 0)

    return isFlippable, netProfit, netMarginPercent
end

--- Get a reference (market) price for an item, checking sources in priority order.
--
-- Priority:
--   1. Auctioneer's market value (historical average — best for flip detection)
--   2. Auctionator's auction price (current market snapshot — good fallback)
--   3. Vendor sell price as an absolute floor fallback
--
-- @param itemLink (string) A WoW item link.
-- @return price   (number|nil) Reference price in copper, or nil if unknown.
-- @return source  (string)     Label for which source provided the price.
function FlipScan.Calculator.GetReferencePrice(itemLink)
    if not itemLink then
        return nil, "none"
    end

    -- Source 1: Auctioneer market value (historical average)
    if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
        local marketValue = AucAdvanced.API.GetMarketValue(itemLink)
        if marketValue and marketValue > 0 then
            return marketValue, "Auctioneer"
        end
    end

    -- Source 2: Auctionator auction price (recent market snapshot)
    if Auctionator and Auctionator.API and Auctionator.API.v1
            and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local ok, atrPrice = pcall(
            Auctionator.API.v1.GetAuctionPriceByItemLink, "FlipScan", itemLink
        )
        if ok and atrPrice and atrPrice > 0 then
            return atrPrice, "Auctionator"
        end
    end

    -- Source 3: Vendor sell price (absolute floor — items are always worth at least this)
    local vendorPrice
    if C_Item and C_Item.GetItemInfo then
        _, _, _, _, _, _, _, _, _, _, vendorPrice = C_Item.GetItemInfo(itemLink)
    end
    if not vendorPrice and GetItemInfo then
        _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)
    end
    if vendorPrice and vendorPrice > 0 then
        return vendorPrice, "Vendor"
    end

    return nil, "none"
end

--- Format a copper amount into a human-readable gold/silver/copper string.
--
-- @param copperAmount (number) Value in copper (e.g. 1234567).
-- @return (string) Formatted string like "123g 45s 67c".
function FlipScan.Calculator.FormatGold(copperAmount)
    if not copperAmount or copperAmount == 0 then
        return "0c"
    end

    local negative = copperAmount < 0
    copperAmount = math.abs(copperAmount)

    local gold   = math.floor(copperAmount / 10000)
    local silver = math.floor((copperAmount % 10000) / 100)
    local copper = math.floor(copperAmount % 100)

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if copper > 0 or #parts == 0 then
        parts[#parts + 1] = copper .. "c"
    end

    local result = table.concat(parts, " ")
    if negative then
        result = "-" .. result
    end
    return result
end
