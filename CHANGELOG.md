# Changelog

All notable changes to FlipScan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Outlier/joke listings far above market price no longer inflate the anchor price. `FindAnchorPrice` now trims outlier tiers from the top of the price distribution before anchor detection (50% supply cap prevents over-trimming).

### Changed
- Default minimum margin raised from 5% to 7.5% to prevent marginal spreads from showing as profitable after the 5% AH cut.

### Added
- Optional `minProfitGold` config (default 0 = disabled) -- sets an absolute minimum profit floor in gold for flip detection.
- Settings panel margin slider now supports 0.5% increments with decimal display.

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
