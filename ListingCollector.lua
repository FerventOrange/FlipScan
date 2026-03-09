-- FlipScan: Listing Collector
-- Batch-collects visible AH listings per item, buckets them into price tiers,
-- and computes a resell anchor price via Calculator.FindAnchorPrice().

local FlipScan = FlipScan

-- Internal storage: _items[itemKey] = { tiers = {}, totalQty = 0, anchorPrice = nil, dirty = true }
-- tiers is a price→qty lookup that gets converted to a sorted array when computing the anchor.
FlipScan.ListingCollector._items = {}

--- Clear collected data for an item, or all items if no key is given.
-- @param itemKey (string|number|nil) The item grouping key. If nil, clears everything.
function FlipScan.ListingCollector:Reset(itemKey)
    if itemKey then
        self._items[itemKey] = nil
    else
        self._items = {}
    end
end

--- Record a listing for an item.
-- @param itemKey  (string|number) The item grouping key (itemID).
-- @param price    (number) Per-unit price in copper.
-- @param quantity (number) Number of items at this price.
function FlipScan.ListingCollector:AddListing(itemKey, price, quantity)
    if not itemKey or not price or price <= 0 then return end
    quantity = quantity or 1

    if not self._items[itemKey] then
        self._items[itemKey] = { priceBuckets = {}, totalQty = 0, anchorPrice = nil, dirty = true }
    end

    local data = self._items[itemKey]
    data.priceBuckets[price] = (data.priceBuckets[price] or 0) + quantity
    data.totalQty = data.totalQty + quantity
    data.dirty = true
end

--- Compute and return the resell anchor price for an item.
-- Caches the result until new listings are added or the item is reset.
-- @param itemKey (string|number) The item grouping key (itemID).
-- @return anchorPrice (number|nil) The resell anchor price in copper, or nil if no data.
function FlipScan.ListingCollector:GetAnchorPrice(itemKey)
    if not itemKey then return nil end

    local data = self._items[itemKey]
    if not data then return nil end

    -- Return cached value if clean
    if not data.dirty and data.anchorPrice then
        return data.anchorPrice
    end

    -- Build sorted tiers array from price buckets
    local tiers = {}
    for price, qty in pairs(data.priceBuckets) do
        tiers[#tiers + 1] = { price = price, qty = qty }
    end

    if #tiers == 0 then return nil end

    table.sort(tiers, function(a, b) return a.price < b.price end)

    -- Cap at maxPriceTiers to exclude outlier joke listings
    local maxTiers = FlipScan.Config:Get("maxPriceTiers") or 15
    local cappedQty = 0
    if #tiers > maxTiers then
        -- Recalculate totalQty for capped tiers only
        for i = 1, maxTiers do
            cappedQty = cappedQty + tiers[i].qty
        end
        -- Trim excess tiers
        for i = #tiers, maxTiers + 1, -1 do
            tiers[i] = nil
        end
    else
        cappedQty = data.totalQty
    end

    -- Delegate to Calculator for the pure-math anchor computation
    data.anchorPrice = FlipScan.Calculator.FindAnchorPrice(tiers, cappedQty)
    data.dirty = false

    FlipScan:Debug(string.format(
        "ListingCollector: item=%s tiers=%d totalQty=%d anchor=%s",
        tostring(itemKey), #tiers, cappedQty,
        data.anchorPrice and FlipScan.Calculator.FormatGold(data.anchorPrice) or "nil"
    ))

    return data.anchorPrice
end
