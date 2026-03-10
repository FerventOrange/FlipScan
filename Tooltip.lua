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
-- Only injects data when the tooltip owner is an AH-context frame with FlipScan data.
function FlipScan.Tooltip:OnTooltipItem(tooltip)
    if not FlipScan.Config:Get("enabled") then return end
    if not FlipScan.Config:Get("showTooltipDetail") then return end

    -- Find the flip data by walking up from the tooltip owner to find
    -- a frame tagged with _flipScanData by the overlay system.
    local flipData = self:GetFlipDataFromOwner(tooltip)
    if not flipData then return end

    -- Net proceeds after the 5% AH cut when reselling at anchor price
    local netAfterCut = flipData.referencePrice * FlipScan.Calculator.SELLER_KEEPS

    -- Inject lines into the tooltip
    tooltip:AddLine(" ")  -- Blank separator
    tooltip:AddLine(ADDON_COLOR .. "FlipScan:" .. RESET_COLOR)

    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Sell Target:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(flipData.referencePrice) .. " (" .. flipData.source .. ")"
    )
    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Your Cost:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(flipData.buyoutPerItem)
    )
    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Net After 5% Cut:" .. RESET_COLOR,
        FlipScan.Calculator.FormatGold(math.floor(netAfterCut))
    )

    -- Profit line with color coding
    local profitStr
    local profitColor
    if flipData.netProfit >= 0 then
        profitStr = "+" .. FlipScan.Calculator.FormatGold(math.floor(flipData.netProfit))
        profitColor = PROFIT_COLOR
    else
        profitStr = "-" .. FlipScan.Calculator.FormatGold(math.floor(math.abs(flipData.netProfit)))
        profitColor = LOSS_COLOR
    end

    tooltip:AddDoubleLine(
        LABEL_COLOR .. "  Est. Profit:" .. RESET_COLOR,
        profitColor .. profitStr .. string.format("  (%.1f%%)", flipData.marginPct) .. RESET_COLOR
    )

    tooltip:Show()  -- Resize the tooltip to fit the new lines
end

--- Walk up the parent chain from the tooltip owner looking for _flipScanData.
-- The overlay system tags row frames with this table when it applies a color.
-- @return (table|nil) The flip data, or nil if not in an AH context.
function FlipScan.Tooltip:GetFlipDataFromOwner(tooltip)
    local owner = tooltip:GetOwner()
    if not owner then return nil end

    -- Check the owner and its parents (up to 5 levels) for flip data
    local frame = owner
    for _ = 1, 5 do
        if not frame then break end
        if frame._flipScanData then
            return frame._flipScanData
        end
        frame = frame:GetParent()
    end

    return nil
end
