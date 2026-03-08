-- FlipScan: Visual Overlay System
-- Manages a pool of colored overlay frames attached to AH result rows.
-- Green = profitable flip, Red = loses money, Hidden = no price data.

local FlipScan = FlipScan

-- Frame pool — reuse overlays instead of creating new ones on every scroll
local overlayPool = {}
local activeOverlays = {}

--- Initialize the overlay system.
function FlipScan.Overlay:Init()
    FlipScan:Debug("Overlay system initialized.")
end

--- Get or create an overlay frame from the pool.
-- @return (Frame) A reusable overlay frame with a color texture.
local function AcquireOverlay()
    local overlay = table.remove(overlayPool)
    if not overlay then
        overlay = CreateFrame("Frame", nil, UIParent)
        overlay:SetFrameStrata("MEDIUM")
        -- Place below Auctioneer's highlight layer so clicks pass through
        overlay:SetFrameLevel(2)
        overlay:EnableMouse(false)  -- Never intercept clicks

        local tex = overlay:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(overlay)
        overlay.texture = tex
    end
    overlay:Show()
    return overlay
end

--- Return an overlay frame to the pool for reuse.
local function ReleaseOverlay(overlay)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetParent(UIParent)
    overlayPool[#overlayPool + 1] = overlay
end

--- Hide and recycle all active overlays.
function FlipScan.Overlay:HideAll()
    for i = #activeOverlays, 1, -1 do
        ReleaseOverlay(activeOverlays[i])
        activeOverlays[i] = nil
    end
end

--- Update overlays for a set of visible result rows.
-- Called by the hook system whenever the browse list changes.
--
-- @param rows (table) Array from FlipScan.Hooks:ScanVisibleRows(), each entry:
--   { rowIndex, itemLink, buyoutPerItem, referencePrice, source, rowFrame }
function FlipScan.Overlay:UpdateRows(rows)
    -- Recycle all existing overlays first
    self:HideAll()

    if not FlipScan.Config:Get("enabled") then return end
    if not rows then return end

    local minMargin = FlipScan.Config:Get("minMarginPercent") or 5
    local goodColor = FlipScan.Config:Get("highlightColor")
    local badColor  = FlipScan.Config:Get("noFlipColor")

    for _, row in ipairs(rows) do
        -- Skip rows where we have no reference price (can't evaluate)
        if row.referencePrice and row.rowFrame then
            local isFlippable, netProfit, marginPct =
                FlipScan.Calculator.IsFlippable(
                    row.buyoutPerItem,
                    row.referencePrice,
                    minMargin
                )

            local overlay = AcquireOverlay()

            -- Parent the overlay to the row frame so it moves/scrolls with it
            overlay:SetParent(row.rowFrame)
            overlay:SetAllPoints(row.rowFrame)
            -- Keep strata below interactive elements
            overlay:SetFrameStrata("MEDIUM")
            overlay:SetFrameLevel(row.rowFrame:GetFrameLevel() + 1)

            if isFlippable then
                overlay.texture:SetColorTexture(
                    goodColor.r, goodColor.g, goodColor.b, goodColor.a
                )
            else
                overlay.texture:SetColorTexture(
                    badColor.r, badColor.g, badColor.b, badColor.a
                )
            end

            -- Store metadata on the overlay for tooltip use
            overlay.flipData = {
                itemLink = row.itemLink,
                buyoutPerItem = row.buyoutPerItem,
                referencePrice = row.referencePrice,
                source = row.source,
                netProfit = netProfit,
                marginPct = marginPct,
                isFlippable = isFlippable,
            }

            activeOverlays[#activeOverlays + 1] = overlay

            FlipScan:Debug(string.format(
                "Row %d: %s | buy=%s ref=%s profit=%s margin=%.1f%% flip=%s",
                row.rowIndex,
                row.itemLink or "?",
                FlipScan.Calculator.FormatGold(row.buyoutPerItem),
                FlipScan.Calculator.FormatGold(row.referencePrice),
                FlipScan.Calculator.FormatGold(netProfit),
                marginPct,
                tostring(isFlippable)
            ))
        end
    end
end

--- Return active overlay count (for debug / status display).
function FlipScan.Overlay:GetActiveCount()
    return #activeOverlays
end
