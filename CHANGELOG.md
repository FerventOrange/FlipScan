# Changelog

All notable changes to FlipScan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.6.0]

### Changed
- Replaced IQM (Interquartile Mean) market value algorithm with gap-based sell point detection and wall filtering. The IQM could land behind quantity walls; the new algorithm finds the first significant price gap between consecutive tiers and validates no wall blocks the sell point.
- Tooltip label renamed from "Market Value" to "Sell Target".
- Config `iqmTrimPercent` replaced with `wallFractionPercent` (default 40%).

### Removed
- `ListingCollector` is no longer called (dead code); tier data is now built directly from visible row data in `AuctioneerHook`.

### Fixed
- SELL label displayed garbled text (`%€2x97x84 SELL` instead of `◄ SELL`) because WoW's Lua 5.1 doesn't support `\xNN` hex escapes. Now uses `\ddd` decimal escapes.

## [0.4.0] - 2026-03-09

### Added
- IQM (Interquartile Mean) market value algorithm replacing the 70th-percentile anchor. Trims bottom/top 25% of supply, computes weighted mean, snaps to first real tier price >= IQM. Resistant to quantity walls and outliers.
- Margin % text on every AH overlay row (+X.X% for green, -X.X% for red).
- "SELL" label on the first red row indicating the sell point.
- "Sell at" display near the buy button showing the current market value.
- Purchase tracking: chat summary after commodity buys showing qty, total cost, avg cost, min resell price.
- `iqmTrimPercent` config option (default 25).
- New `PurchaseTracker.lua` module.
- Optional `minProfitGold` config (default 0 = disabled) -- sets an absolute minimum profit floor in gold for flip detection.
- Settings panel margin slider now supports 0.5% increments with decimal display.

### Changed
- `maxPriceTiers` default raised from 15 to 50.
- Tooltip now shows "Market Value" instead of "Resell Anchor".
- Source label changed from "Anchor" to "IQM".
- Default minimum margin raised from 5% to 7.5% to prevent marginal spreads from showing as profitable after the 5% AH cut.

### Removed
- `gapThresholdPercent`, `gapMinSupplyAbovePercent`, `anchorPercentile` config options.
- `TrimOutlierTiers` and `FindAnchorPrice` functions (replaced by `FindMarketValue`).

### Fixed
- Outlier/joke listings far above market price no longer inflate the anchor price. `FindAnchorPrice` now trims outlier tiers from the top of the price distribution before anchor detection (50% supply cap prevents over-trimming).

## [0.3.0] - 2026-03-09

### Fixed
- Browse scanning removed to fix item-detail race condition on the Blizzard AH.
- Misleading overlays on thin markets suppressed via row-count filter.
- Commodity item extraction corrected for accurate overlay display.
- `C_Timer.NewTimer` replaced with `C_Timer.After` for Blizzard API compatibility.
- `COMMODITY_SEARCH_RESULTS_UPDATED` event registered to support commodity scan results.

### Added
- Bulk supply anchor pricing algorithm replaces `GetReferencePrice` for more accurate reference prices.
- Blizzard native AH tabs now hooked alongside Auctionator for overlay support.
- Debug logging added to Blizzard scan and hook systems.

## [0.2.0] - 2026-02-22

### Added
- Auctionator integration as primary price source (Auctioneer dependency removed).
- Overlay and tooltip systems rewritten for Auctionator row rendering.
- All Auctionator row mixins hooked individually for full tab coverage (Buy Item, Commodity, Shopping).

### Fixed
- Auctionator highlighting restored on Buy Item/Commodity/Shopping tabs.

## [0.1.0] - 2026-01-17

### Added
- Initial addon implementation with flip detection, overlay highlighting, and tooltip display.
- Settings panel with configurable minimum margin.
- Slash commands for configuration and status.
- `FlipScanDB` saved variables for persistent settings.
- Interface version set to 120000 for The War Within (Midnight) expansion.
