-- FlipScan: Visual Overlay System
-- Manages colored overlay textures attached to AH result rows.
-- Green = profitable flip, Red = loses money, Hidden = no price data.
--
-- Overlays are stored directly on the row frame (rowFrame._flipScanOverlay)
-- so they survive ScrollBox recycling — when Auctionator re-populates a
-- recycled row, the Populate hook clears or updates the existing overlay.

local FlipScan = FlipScan

-- Track all frames that have an overlay for bulk cleanup
local overlaidFrames = {}

--- Initialize the overlay system.
function FlipScan.Overlay:Init()
    FlipScan:Debug("Overlay system initialized.")
end

--- Get or create the overlay texture for a specific row frame.
-- Each row frame gets at most one overlay, stored as rowFrame._flipScanOverlay.
-- @param rowFrame (Frame) The AH result row frame.
-- @return (Texture) The overlay texture.
local function GetOrCreateOverlay(rowFrame)
    if rowFrame._flipScanOverlay then
        return rowFrame._flipScanOverlay
    end

    -- Create a child frame to hold the overlay texture.
    -- Using a child frame lets us control strata/level independently.
    local overlayFrame = CreateFrame("Frame", nil, rowFrame)
    overlayFrame:SetAllPoints(rowFrame)
    overlayFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
    overlayFrame:EnableMouse(false)  -- Never intercept clicks

    local tex = overlayFrame:CreateTexture(nil, "ARTWORK", nil, -8)
    tex:SetAllPoints(overlayFrame)

    -- Margin/label text right-aligned on the row
    local text = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("RIGHT", overlayFrame, "RIGHT", -8, 0)
    overlayFrame.marginText = text

    -- Store references
    rowFrame._flipScanOverlay = overlayFrame
    overlayFrame.texture = tex

    return overlayFrame
end

--- Apply a colored overlay to a single row frame based on flip data.
-- @param rowFrame (Frame) The result row frame.
-- @param flipData (table) { isFlippable, netProfit, marginPct, itemLink, buyoutPerItem, referencePrice, source }
function FlipScan.Overlay:ApplyRowOverlay(rowFrame, flipData)
    if not rowFrame then return end

    local overlay = GetOrCreateOverlay(rowFrame)
    local goodColor = FlipScan.Config:Get("highlightColor")
    local badColor  = FlipScan.Config:Get("noFlipColor")

    if flipData.isFlippable then
        overlay.texture:SetColorTexture(goodColor.r, goodColor.g, goodColor.b, goodColor.a)
    else
        overlay.texture:SetColorTexture(badColor.r, badColor.g, badColor.b, badColor.a)
    end

    -- Update margin text or SELL label
    if overlay.marginText then
        if flipData.noSellPoint then
            -- No sell point found — red overlay only, no margin text
            overlay.marginText:SetText("")
            overlay.marginText:Hide()
        elseif flipData.isFirstRed then
            overlay.marginText:SetText("\226\151\132 SELL")
            overlay.marginText:SetTextColor(1, 1, 1, 1)
            overlay.marginText:Show()
        else
            local sign = flipData.marginPct >= 0 and "+" or ""
            overlay.marginText:SetText(string.format("%s%.1f%%", sign, flipData.marginPct))
            overlay.marginText:SetTextColor(1, 1, 1, 0.9)
            overlay.marginText:Show()
        end
    end

    -- Store the flip data on the row frame for tooltip access
    rowFrame._flipScanData = flipData
    overlay:Show()

    -- Track for bulk cleanup
    overlaidFrames[rowFrame] = true

    FlipScan:Debug(string.format(
        "Overlay: %s | buy=%s ref=%s profit=%s margin=%.1f%% flip=%s",
        flipData.itemLink or "?",
        FlipScan.Calculator.FormatGold(flipData.buyoutPerItem),
        FlipScan.Calculator.FormatGold(flipData.referencePrice),
        FlipScan.Calculator.FormatGold(flipData.netProfit),
        flipData.marginPct,
        tostring(flipData.isFlippable)
    ))
end

--- Clear the overlay on a single row frame (e.g. when no price data is available).
function FlipScan.Overlay:ClearRowOverlay(rowFrame)
    if not rowFrame then return end
    if rowFrame._flipScanOverlay then
        rowFrame._flipScanOverlay:Hide()
        if rowFrame._flipScanOverlay.marginText then
            rowFrame._flipScanOverlay.marginText:SetText("")
        end
    end
    rowFrame._flipScanData = nil
end

--- Hide and clear all active overlays across all tracked row frames.
function FlipScan.Overlay:HideAll()
    for rowFrame in pairs(overlaidFrames) do
        self:ClearRowOverlay(rowFrame)
    end
    overlaidFrames = {}
end

--- Return active overlay count (for debug / status display).
function FlipScan.Overlay:GetActiveCount()
    local count = 0
    for rowFrame in pairs(overlaidFrames) do
        if rowFrame._flipScanOverlay and rowFrame._flipScanOverlay:IsShown() then
            count = count + 1
        end
    end
    return count
end
