# FlipScan

A World of Warcraft retail addon that analyzes Auction House commodity listings in real time and visually marks items that are profitable to flip after accounting for the 5% AH transaction cut. Works best with **Auctionator** for market pricing data.

## Installation

1. Download or clone this repository.
2. Copy the `FlipScan` folder into your WoW addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/FlipScan/
   ```
3. For best results, install **Auctionator** (optional but recommended). FlipScan hooks into Auctionator's AH tabs for broader coverage and also works with Blizzard's native AH frames.
4. Restart WoW or type `/reload` in-game.

## Features

- **Color-coded overlays** on AH commodity result rows:
  - Green: profitable flip above your minimum margin threshold
  - Red: would lose money (or fail to meet margin) after the 5% AH cut
  - No overlay: item has no known market value
- **Margin % on every row** — each row shows margin text right-aligned (e.g. "+12.3%" in green rows, "-4.1%" in red rows). The first red row (the sell point) displays a "SELL" label instead.
- **Sell-at display** — a "FlipScan: Sell at Xg Xs" indicator appears near the buy button showing the current IQM market value for the item you are viewing
- **IQM market value** — an Interquartile Mean algorithm trims the bottom and top 25% of supply by quantity, computes a weighted mean of the middle 50%, then snaps to the first real tier price at or above the IQM. This is resistant to quantity walls and outlier listings.
- **Purchase tracking** — after buying commodities, a chat message summarizes the quantity bought, total cost, average cost per item, and the minimum resell price needed to clear your configured margin
- **Tooltip injection** showing a full profit breakdown when hovering AH listings
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

### IQM Market Value Algorithm

FlipScan computes its sale reference price using an **Interquartile Mean (IQM)** of currently visible AH listings:

1. All visible commodity listings are bucketed into price tiers (price + quantity).
2. Tiers above `maxPriceTiers` (default 50) are discarded to exclude extreme outliers.
3. The bottom 25% and top 25% of supply (by quantity) are trimmed. The trim percentage is configurable via `iqmTrimPercent`.
4. A quantity-weighted mean is computed over the remaining middle 50% of supply.
5. The IQM is "snapped" to the first real tier price at or above the computed mean, so the market value is always a concrete, listable price.

This approach is naturally resistant to quantity walls (large stacks at a single price point) and outlier listings at both ends of the distribution.

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
| `maxPriceTiers` | `50` | Cap on the number of price tiers used for IQM calculation; tiers beyond this are discarded |
| `iqmTrimPercent` | `25` | Percentage of supply trimmed from each end (bottom and top) before computing the IQM weighted mean |

## Known Limitations

- **Deposit costs are not factored in.** The AH deposit (refunded on successful sale) is not subtracted from profit calculations. For expensive items with long listing durations, actual profit may be slightly lower.
- **Commodity-focused.** The IQM algorithm operates on the visible commodity listing tiers. Browse-level summary rows (one row per item) are intentionally skipped because they lack the listing depth needed for meaningful analysis.
- **Visible listings only.** The market value is computed from whichever tiers are currently loaded in the AH window. If the full listing depth has not loaded yet, the IQM will be based on a partial dataset.
- **No Classic/Wrath support.** Targets the retail WoW API (`C_AuctionHouse`).

## How the Market Value Pipeline Works

FlipScan computes its own market value from the raw AH listings visible on screen. No external price source is required.

1. **ListingCollector** receives every visible listing (price + quantity) and buckets them into price tiers.
2. **Calculator.FindMarketValue()** runs the IQM algorithm on the collected tiers to produce a single market value.
3. **AuctioneerHook** feeds each row's buy price and the computed market value into **Calculator.IsFlippable()** and applies green/red overlays accordingly.

## File Structure

```
FlipScan/
├── FlipScan.toc          # Addon metadata and load order
├── FlipScan.lua          # Init, event registration, namespace setup
├── Config.lua            # SavedVariables, defaults, get/set helpers
├── Calculator.lua        # Profit math and IQM market value algorithm
├── ListingCollector.lua  # Batch-collects AH listings into price tiers
├── AuctioneerHook.lua    # Hook layer into Blizzard & Auctionator AH rows
├── Overlay.lua           # Colored overlays and margin text per row
├── Tooltip.lua           # GameTooltip profit injection
├── PurchaseTracker.lua   # Post-purchase chat summary (cost, avg, resell)
├── Commands.lua          # /flipscan slash command handler
├── SettingsPanel.lua     # Interface Options panel
├── FlipScan.xml          # Reserved XML frame declarations
├── libs/                 # Library folder (unused currently)
└── README.md
```

## License

This project is provided as-is for personal use.
