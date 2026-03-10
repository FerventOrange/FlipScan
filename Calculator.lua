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

--- Compute the market value using an Interquartile Mean, then snap to a real tier.
--
-- The IQM trims the bottom and top portions of the supply distribution by quantity,
-- then computes a weighted mean of the remaining middle portion. This is naturally
-- resistant to quantity walls and cheap/expensive outliers.
--
-- After computing the IQM, the result is "snapped" to the first real tier price
-- that is >= the IQM. This ensures the market value is a concrete, listable price.
--
-- @param tiers    (table)  Array of { price = number, qty = number }, sorted by price ascending.
-- @param totalQty (number) Sum of all tier quantities.
-- @return marketValue (number|nil) The market value in copper, or nil if no tiers.
function FlipScan.Calculator.FindMarketValue(tiers, totalQty)
    if not tiers or #tiers == 0 or not totalQty or totalQty <= 0 then
        return nil
    end

    -- Single tier — market value is the only price
    if #tiers == 1 then
        return tiers[1].price
    end

    -- Determine how much supply to trim from each end
    local trimFraction = math.min((FlipScan.Config:Get("iqmTrimPercent") or 25) / 100, 0.49)
    local trimQty = totalQty * trimFraction

    -- Bottom trim: walk cheapest→expensive, exclude up to trimQty units
    local bottomExclude = {}
    local bottomRemaining = trimQty
    for i = 1, #tiers do
        local exclude = math.min(tiers[i].qty, bottomRemaining)
        bottomExclude[i] = exclude
        bottomRemaining = bottomRemaining - exclude
        if bottomRemaining <= 0 then break end
    end

    -- Top trim: walk expensive→cheapest, exclude up to trimQty units
    local topExclude = {}
    local topRemaining = trimQty
    for i = #tiers, 1, -1 do
        local exclude = math.min(tiers[i].qty, topRemaining)
        topExclude[i] = exclude
        topRemaining = topRemaining - exclude
        if topRemaining <= 0 then break end
    end

    -- Compute weighted mean of the included middle portion
    local weightedSum = 0
    local includedQty = 0
    for i = 1, #tiers do
        local included = tiers[i].qty - (bottomExclude[i] or 0) - (topExclude[i] or 0)
        if included > 0 then
            weightedSum = weightedSum + tiers[i].price * included
            includedQty = includedQty + included
        end
    end

    if includedQty <= 0 then
        return tiers[1].price
    end

    local iqm = weightedSum / includedQty

    -- Snap to the first real tier price >= IQM
    for i = 1, #tiers do
        if tiers[i].price >= iqm then
            return tiers[i].price
        end
    end

    -- Fallback: return the highest tier price
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
