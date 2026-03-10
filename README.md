# FlipScan

A World of Warcraft retail addon that analyzes Auction House listings in real time and visually marks items that are profitable to flip after accounting for the 5% AH transaction cut. Works best with **Auctionator** for market pricing data.

**FlipScan is read-only and display-only.** It never automatically buys, sells, or posts auctions.

## Installation

1. Download or clone this repository.
2. Copy the `FlipScan` folder into your WoW addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/FlipScan/
   ```
3. For best results, install **Auctionator** (optional but recommended). FlipScan will run standalone using vendor prices only if Auctionator is not present.
4. Restart WoW or type `/reload` in-game.

## Features

- **Color-coded overlays** on AH browse result rows:
  - Green: profitable flip above your minimum margin threshold
  - Red: would lose money (or fail to meet margin) after the 5% AH cut
  - No overlay: item has no known market value
- **Tooltip injection** showing a full profit breakdown when hovering AH listings
- **Outlier-trimmed anchor pricing** — joke and far-above-market listings are stripped before computing the sale reference price
- **Configurable minimum margin** to filter out low-profit flips (default 7.5%, adjustable in 0.5% steps)
- **Optional minimum profit floor** — set an absolute gold threshold so marginal copper-level "flips" are ignored
- **Settings UI** under Game Menu > Interface > AddOns > FlipScan
- **Slash commands** for quick runtime control

## Slash Commands

| Command | Action |
|---|---|
| `/flipscan` | Print status and available commands |
| `/flipscan on` | Enable FlipScan |
| `/flipscan off` | Disable FlipScan |
| `/flipscan margin <number>` | Set minimum profit margin % (e.g. `/flipscan margin 10`) |
| `/flipscan tooltip` | Toggle tooltip detail on/off |
| `/flipscan reset` | Reset all settings to defaults |
| `/flipscan debug` | Toggle debug output (prints hook activity to chat) |
| `/flipscan help` | Show command list |

The shorthand `/fs` also works for all commands.

## How the Profit Formula Works

When you buy an item on the AH and resell it, Blizzard takes a **5% cut** from your sale price. FlipScan calculates:

```
Net Proceeds   = Sale Price * 0.95
Net Profit     = Net Proceeds - Purchase Price
Margin %       = (Net Profit / Purchase Price) * 100
```

An item is flagged as "flippable" when `Margin % >= your configured minimum margin` (default: 7.5%).

Before computing the anchor (sale) price, `FindAnchorPrice` trims outlier and joke listings from the top of the price distribution. This prevents items with a small raw price spread from appearing as profitable flips when the anchor would otherwise be inflated by far-above-market outliers.

### Price Reference Sources (priority order)

1. **Auctionator market price** (`Auctionator.API.v1.GetAuctionPriceByItemLink`) — market data from recent AH scans
2. **Vendor sell price** — absolute floor fallback from `GetItemInfo`

## Configuration

Settings persist across `/reload` and login/logout via SavedVariables.

| Setting | Default | Description |
|---|---|---|
| `enabled` | `true` | Master on/off toggle |
| `minMarginPercent` | `7.5` | Minimum net profit % to flag as flippable (slider supports 0.5% increments) |
| `highlightColor` | Green (0,1,0,0.4) | Overlay color for profitable flips |
| `noFlipColor` | Red (1,0,0,0.4) | Overlay color for money-losing listings |
| `minProfitGold` | `0` | Minimum absolute profit in gold required for a flip (0 = disabled) |
| `showTooltipDetail` | `true` | Show profit breakdown in item tooltips |

## Known Limitations

- **Deposit costs are not factored in.** The AH deposit (refunded on successful sale) is not subtracted from profit calculations. For expensive items with long listing durations, actual profit may be slightly lower.
- **Commodity pricing** relies on Auctionator market data or vendor price. Real-time commodity undercuts are not tracked.
- **Price data freshness** — FlipScan is only as accurate as Auctionator's last scan. Stale market data will produce stale flip recommendations.
- **No Classic/Wrath support.** Targets the retail WoW API (`C_AuctionHouse`).

## Extending with New Price Sources

To add a new price source, edit `Calculator.lua` and add a check in `FlipScan.Calculator.GetReferencePrice()` before the vendor-price fallback:

```lua
-- Example: TradeSkillMaster price source
if TSMAPI and TSMAPI.GetCustomPriceValue then
    local tsmPrice = TSMAPI.GetCustomPriceValue("DBMarket", itemLink)
    if tsmPrice and tsmPrice > 0 then
        return tsmPrice, "TSM"
    end
end
```

## File Structure

```
FlipScan/
├── FlipScan.toc          # Addon metadata and load order
├── FlipScan.lua          # Init, event registration, namespace setup
├── Config.lua            # SavedVariables, defaults, get/set helpers
├── Calculator.lua        # Pure profit math, no UI dependencies
├── AuctioneerHook.lua    # Hook layer into Blizzard AH result rows
├── Overlay.lua           # Frame pool, texture coloring per row
├── Tooltip.lua           # GameTooltip profit injection
├── Commands.lua          # /flipscan slash command handler
├── SettingsPanel.lua     # Interface Options panel
├── FlipScan.xml          # Reserved XML frame declarations
├── libs/                 # Library folder (unused currently)
└── README.md
```

## License

This project is provided as-is for personal use.
