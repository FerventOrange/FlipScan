-- FlipScan: Tooltip Injection
-- Injects net profit breakdown into GameTooltip when hovering AH result rows.

local FlipScan = FlipScan

local ADDON_COLOR   = "|cFF00CCFF"  -- Cyan for the header
local PROFIT_COLOR  = "|cFF00FF00"  -- Green for profit
local LOSS_COLOR    = "|cFFFF0000"  -- Red for loss
local LABEL_COLOR   = "|cFFAAAAAA"  -- Grey for labels
local RESET_COLOR   = "|r"

--- Initialize the tooltip hook system.
function FlipScan.Tooltip:Init()
    -- Use TooltipDataProcessor if available (retail 10.0.2+), otherwise fall back
    -- to hooking OnTooltipSetItem directly.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Item,
            function(tooltip, data)
                FlipScan.Tooltip:OnTooltipItem(tooltip)
            end
        )
        FlipScan:Debug("Tooltip: hooked via TooltipDataProcessor.")
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            FlipScan.Tooltip:OnTooltipItem(tooltip)
        end)
        FlipScan:Debug("Tooltip: hooked via OnTooltipSetItem.")
    end
end

--- Called when a tooltip is about to display an item.
-- Only injects data when the tooltip owner is an AH-context frame.
function FlipScan.Tooltip:OnTooltipItem(tooltip)
    if not FlipScan.Config:Get("enabled") then return end
    if not FlipScan.Config:Get("showTooltipDetail") then return end

    -- Only inject in AH context — check if the tooltip's owner is part of
    -- the AuctionHouseFrame hierarchy or an Auctioneer frame
    if not self:IsAuctionHouseContext(tooltip) then return end

    -- Get the item link from the tooltip
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    -- Look up the reference (market) price
    local refPrice, source = FlipScan.Calculator.GetReferencePrice(itemLink)
    if not refPrice then return end

    -- Try to determine the buyout price from the tooltip's owner row
    local buyout = self:GetBuyoutFromOwner(tooltip)
    if not buyout or buyout <= 0 then return end

    -- Calculate flip profitability
    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5
    local isFlippable, netProfit, marginPct =
        FlipScan.Calculator.IsFlippable(buyout, refPrice, minMargin)

    -- Net proceeds after the 5% AH cut when reselling at market value
    local netAfterCut = refPrice * FlipScan.Calculator.SELLER_KEEPS

    -- Inject lines into the tooltip
    tooltip:AddLine(" ")  -- Blank separator
    tooltip:AddLine(ADDON_COLOR .. "FlipScan:" .. RESET_COLOR)

    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Market Value:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(refPrice) .. " (" .. source .. ")"
    )
    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Your Cost:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(buyout)
    )
    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Net After 5% Cut:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(math.floor(netAfterCut))
    )

    -- Profit line with color coding
    local profitStr
    local profitColor
    if netProfit >= 0 then
        profitStr = "+" .. FlipScan.Calculator.FormatGold(math.floor(netProfit))
        profitColor = PROFIT_COLOR
    else
        profitStr = "-" .. FlipScan.Calculator.FormatGold(math.floor(math.abs(netProfit)))
        profitColor = LOSS_COLOR
    end

    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Est. Profit:" .. RESET_COLOR,
        profitColor .. profitStr .. string.format("  (%.1f%%)", marginPct) .. RESET_COLOR
    )

    tooltip:Show()  -- Resize the tooltip to fit the new lines
end

--- Check if the tooltip is being shown in an Auction House context.
function FlipScan.Tooltip:IsAuctionHouseContext(tooltip)
    local owner = tooltip:GetOwner()
    if not owner then return false end

    -- Walk up the parent chain looking for known AH frame names
    local frame = owner
    for _ = 1, 10 do
        if not frame then break end
        local name = frame:GetName()
        if name then
            -- Match Auctioneer frames or Blizzard's native AH frame
            if name:find("AuctionFrame") or
               name:find("AucAdvanced") or
               name:find("AuctionHouseFrame") or
               name:find("Browse") then
                return true
            end
        end
        frame = frame:GetParent()
    end

    return false
end

--- Try to read the buyout price from the tooltip owner's row data.
function FlipScan.Tooltip:GetBuyoutFromOwner(tooltip)
    local owner = tooltip:GetOwner()
    if not owner then return nil end

    -- Auctioneer-style buttons store buyoutPrice directly
    if owner.buyoutPrice then
        local count = owner.count or 1
        return owner.buyoutPrice / count
    end

    -- Blizzard native AH rows may store result info
    if owner.rowData and owner.rowData.buyoutAmount then
        return owner.rowData.buyoutAmount
    end

    -- Check if the owner has an auction ID we can query via the replicate API
    -- GetReplicateItemInfo returns multiple scalars, not a table
    if owner.auctionID and C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo then
        local _, _, _, _, _, _, _, _, _, buyoutPrice =
            C_AuctionHouse.GetReplicateItemInfo(owner.auctionID)
        if buyoutPrice and buyoutPrice > 0 then
            return buyoutPrice
        end
    end

    return nil
end
