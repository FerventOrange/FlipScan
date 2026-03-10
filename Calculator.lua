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
-- @param minProfit        (number|nil) Optional minimum net profit in copper.
--                         0 or nil disables this check.
--
-- @return isFlippable      (boolean) True if net profit meets the minimum margin.
-- @return netProfit        (number)  Estimated profit in copper (can be negative).
-- @return netMarginPercent (number)  Net margin as a percentage of purchase cost.
function FlipScan.Calculator.IsFlippable(buyoutPerItem, referencePrice, minMarginPercent, minProfit)
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
    local revenueAfterCut = referencePrice * SELLER_KEEPS

    -- Net profit = what you receive minus what you paid
    local netProfit = revenueAfterCut - purchaseCost

    -- Net margin as a percentage of the purchase cost
    -- e.g. if you paid 100g and net 10g, margin = 10%
    local netMarginPercent = (netProfit / purchaseCost) * 100

    -- A flip qualifies if the margin meets or exceeds the minimum threshold
    -- and (optionally) the absolute profit meets the minimum floor
    local isFlippable = netMarginPercent >= (minMarginPercent or 0)
        and netProfit >= (minProfit or 0)

    return isFlippable, netProfit, netMarginPercent
end

--- Trim outlier tiers from the top of the price distribution.
--
-- Walks tiers top-down (highest to lowest). If the gap between a tier and the
-- one below it exceeds gapThreshold (fractional, e.g. 0.20 = 20%), the tier is
-- removed. Stops early if cumulative excluded supply exceeds 50% of totalQty
-- to avoid trimming the real market.
--
-- @param tiers        (table)  Array of { price, qty }, sorted by price ascending.
-- @param totalQty     (number) Sum of all tier quantities.
-- @param gapThreshold (number) Fractional gap threshold (e.g. 0.20 for 20%).
-- @return tiers    (table)  The trimmed tiers array (same reference, modified in-place).
-- @return totalQty (number) Recalculated total quantity from remaining tiers.
local function TrimOutlierTiers(tiers, totalQty, gapThreshold)
    local maxExclude = totalQty * 0.50
    local excluded = 0

    local i = #tiers
    while i >= 2 do
        local gap = (tiers[i].price - tiers[i - 1].price) / tiers[i - 1].price
        if gap >= gapThreshold then
            local tierQty = tiers[i].qty
            if excluded + tierQty > maxExclude then
                break
            end
            excluded = excluded + tierQty
            table.remove(tiers, i)
        else
            break
        end
        i = i - 1
    end

    if excluded > 0 then
        totalQty = totalQty - excluded
    end

    return tiers, totalQty
end

--- Find the resell anchor price from a sorted list of price tiers.
--
-- Uses a two-pass approach:
--   1. Gap detection: walk tiers low→high, find the first price jump ≥ gapThreshold%
--      where ≥ gapMinSupplyAbove% of total supply exists at or above the gap.
--      The tier after the gap is the anchor — that's where the market "really" sits.
--   2. Percentile fallback: if no gap qualifies, find the tier where cumulative
--      quantity reaches anchorPercentile% of total supply.
--
-- @param tiers    (table) Array of { price = number, qty = number }, sorted by price ascending.
-- @param totalQty (number) Sum of all tier quantities.
-- @return anchorPrice (number|nil) The resell anchor price in copper, or nil if no tiers.
function FlipScan.Calculator.FindAnchorPrice(tiers, totalQty)
    if not tiers or #tiers == 0 or not totalQty or totalQty <= 0 then
        return nil
    end

    -- Single tier — no spread to exploit, anchor is the only price
    if #tiers == 1 then
        return tiers[1].price
    end

    local gapThreshold = (FlipScan.Config:Get("gapThresholdPercent") or 20) / 100
    local gapMinSupplyAbove = (FlipScan.Config:Get("gapMinSupplyAbovePercent") or 20) / 100
    local anchorPercentile = (FlipScan.Config:Get("anchorPercentile") or 70) / 100

    -- Shallow-copy tiers so trimming does not mutate the caller's array
    local trimmed = {}
    for idx = 1, #tiers do trimmed[idx] = tiers[idx] end

    -- Trim outlier tiers from the top before anchor detection
    tiers, totalQty = TrimOutlierTiers(trimmed, totalQty, gapThreshold)

    -- After trimming, if only one tier remains, return it directly
    if #tiers == 1 then
        return tiers[1].price
    end
    if #tiers == 0 or totalQty <= 0 then
        return nil
    end

    -- Pass 1: Gap detection
    -- Walk tiers and find the first significant price jump with enough supply above it.
    -- Also require at least 2 distinct tiers above the gap — a single massive wall
    -- at one price is likely player manipulation, not real market depth.
    local cumulativeQty = 0
    for i = 1, #tiers - 1 do
        cumulativeQty = cumulativeQty + tiers[i].qty
        local jump = (tiers[i + 1].price - tiers[i].price) / tiers[i].price
        if jump >= gapThreshold then
            local supplyAbove = totalQty - cumulativeQty
            local tiersAbove = #tiers - i
            if supplyAbove / totalQty >= gapMinSupplyAbove and tiersAbove >= 2 then
                return tiers[i + 1].price
            end
        end
    end

    -- Pass 2: Percentile fallback
    -- Find the tier where cumulative quantity reaches the anchor percentile.
    local threshold = totalQty * anchorPercentile
    cumulativeQty = 0
    for i = 1, #tiers do
        cumulativeQty = cumulativeQty + tiers[i].qty
        if cumulativeQty >= threshold then
            return tiers[i].price
        end
    end

    -- Shouldn't reach here, but return the last tier as ultimate fallback
    return tiers[#tiers].price
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
