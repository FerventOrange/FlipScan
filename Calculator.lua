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

--- Find the sell point price using gap detection with wall filtering.
--
-- Walks tiers cheapest-to-expensive looking for the first significant price gap
-- (where IsFlippable passes between consecutive tiers). The tier above the gap
-- is the sell point candidate. If a quantity wall blocks the candidate, try the
-- next gap. Returns nil if no valid sell point exists.
--
-- @param tiers         (table)  Array of { price, qty } sorted by price ascending.
-- @param minMargin     (number) Min margin % passed to IsFlippable.
-- @param minProfit     (number) Min absolute profit in copper passed to IsFlippable.
-- @param wallFraction  (number) Max fraction (0-1) any single tier can hold (e.g. 0.4).
-- @return sellPoint    (number|nil) The sell point price in copper, or nil.
function FlipScan.Calculator.FindSellPoint(tiers, minMargin, minProfit, wallFraction)
    if not tiers or #tiers < 2 then
        return nil
    end

    for i = 1, #tiers - 1 do
        local isGap = FlipScan.Calculator.IsFlippable(
            tiers[i].price, tiers[i + 1].price, minMargin, minProfit
        )

        if isGap then
            -- Compute total quantity from tiers[1] through tiers[i+1]
            local totalQty = 0
            for j = 1, i + 1 do
                totalQty = totalQty + tiers[j].qty
            end

            -- Wall check: reject if any single tier dominates the supply
            local isWall = false
            if wallFraction and wallFraction > 0 and totalQty > 0 then
                for j = 1, i + 1 do
                    if tiers[j].qty > wallFraction * totalQty then
                        isWall = true
                        break
                    end
                end
            end

            if not isWall then
                return tiers[i + 1].price
            end
        end
    end

    return nil
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
