# FlipScan

A World of Warcraft retail addon that analyzes Auction House commodity listings in real time and visually marks items that are profitable to flip after accounting for the 5% AH transaction cut. Uses a gap + wall detection algorithm to find a concrete sell point from the visible price tiers. Works best with **Auctionator** for broader AH tab coverage.

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
  - Green: priced below the sell point -- profitable to buy and relist
  - Red: at or above the sell point, or no valid sell point found (e.g. blocked by a wall)
  - No overlay: insufficient listing data to detect a sell point
- **Margin % on every row** — each row shows margin text right-aligned (e.g. "+12.3%" in green rows, "-4.1%" in red rows). The sell point row displays a "SELL" label instead.
- **Sell-at display** — a "FlipScan: Sell at Xg Xs" indicator appears near the buy button showing the detected sell point for the item you are viewing
- **Gap + Wall sell point detection** — walks price tiers cheapest-to-expensive looking for a significant price gap (where buying at one tier and reselling at the next would be profitable after the AH cut). The tier above the gap is the sell point. A wall filter rejects sell points that sit behind a quantity wall (see below).
- **Purchase tracking** — after buying commodities, a chat message summarizes the quantity bought, total cost, average cost per item, and the minimum resell price needed to clear your configured margin
- **Tooltip injection** showing a "Sell Target" price and full profit breakdown when hovering AH listings
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

### Gap + Wall Sell Point Algorithm

FlipScan determines its sell point by scanning the visible AH price tiers for a profitable gap:

1. All visible commodity listings are bucketed into price tiers (price + quantity), sorted cheapest-to-expensive.
2. Tiers above `maxPriceTiers` (default 50) are discarded to exclude extreme outliers.
3. FlipScan walks consecutive tiers looking for the first **price gap** where buying at tier N and reselling at tier N+1 would be profitable after the 5% AH cut (using the configured minimum margin and minimum profit settings).
4. The tier above the gap (tier N+1) becomes the **sell point candidate** -- the price at which you should list your items.
5. **Wall detection**: Before accepting the candidate, FlipScan checks every tier from the cheapest through the sell point. If any single tier holds more than `wallFractionPercent` (default 40%) of the total supply in that range, the candidate is rejected as being behind a wall that would be impractical to undercut. The algorithm then continues searching for the next gap.
6. If a valid sell point is found, rows below it are marked green (profitable to buy), the sell point row shows a "SELL" label, and a "Sell at" display appears near the buy button. If no valid sell point exists (no gap found, or every candidate is behind a wall), all rows show red.

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
| `maxPriceTiers` | `50` | Cap on the number of price tiers considered; tiers beyond this are discarded as outliers |
| `wallFractionPercent` | `40` | A single tier holding more than this percentage of total supply between the cheapest listing and the sell point candidate is treated as a wall, causing the candidate to be rejected |

## Known Limitations

- **Deposit costs are not factored in.** The AH deposit (refunded on successful sale) is not subtracted from profit calculations. For expensive items with long listing durations, actual profit may be slightly lower.
- **Commodity-focused.** The gap + wall algorithm operates on the visible commodity listing tiers. Browse-level summary rows (one row per item) are intentionally skipped because they lack the listing depth needed for meaningful analysis.
- **Visible listings only.** The sell point is computed from whichever tiers are currently loaded in the AH window. If the full listing depth has not loaded yet, the algorithm will be working with a partial dataset.
- **No Classic/Wrath support.** Targets the retail WoW API (`C_AuctionHouse`).

## How the Sell Point Pipeline Works

FlipScan determines its sell point from the raw AH listings visible on screen. No external price source is required.

1. **AuctioneerHook** collects every visible listing (price + quantity) and buckets them into price tiers.
2. **Calculator.FindSellPoint()** walks the tiers looking for a profitable gap and validates the candidate against the wall filter.
3. **AuctioneerHook** feeds each row's buy price and the sell point into **Calculator.IsFlippable()** and applies green/red overlays accordingly.

## File Structure

```
FlipScan/
├── FlipScan.toc          # Addon metadata and load order
├── FlipScan.lua          # Init, event registration, namespace setup
├── Config.lua            # SavedVariables, defaults, get/set helpers
├── Calculator.lua        # Profit math and gap + wall sell point algorithm
├── ListingCollector.lua  # Batch-collects AH listings into price tiers
├── AuctioneerHook.lua    # Hook layer into Blizzard & Auctionator AH rows; builds tiers and drives sell point detection
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
