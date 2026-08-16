BitPrice keeps one cryptocurrency price in your menu bar and the rest of your watchlist in a panel behind it.

This is the first release.

## What it does

- **Live prices.** Binance and OKX push over WebSocket; Coinbase is polled every 60 seconds. Each coin is served by exactly one market that you choose.
- **You pick the market, not a matcher.** Ticker symbols are not unique — wrapped assets, bridged assets, and unrelated projects share them. Adding a coin shows every candidate market across all three venues, labelled by venue, and you confirm one. Quote assets are unrestricted: USD, USDT, USDC, FDUSD, and national currencies such as EUR, AUD, BRL, and ARS.
- **Charts** over 24 hours, 7 days, or 30 days for the selected coin, drawn from that coin's own venue and captioned with it.
- **Price alerts** as macOS notifications, with a direction, threshold, cooldown, and hysteresis percentage that controls re-arming.
- **Menu bar label** showing your primary coin's symbol and price, chosen with the star on any row.
- **Four text sizes.** The panel widens as the type grows, so larger text does not squeeze the columns.
- **Launch at login**, and a header status word — live, stale, or offline — summarising feed health.

Up to 25 coins. No account, no telemetry, no third-party dependencies.

## Requirements

**Apple silicon Mac, macOS 14.0 or later.** This build is `arm64` only and will not run on an Intel Mac.

## Installing

Download `BitPrice-1.0.zip`, expand it, move `BitPrice.app` into `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/BitPrice.app
```

**This step is required.** Without it macOS reports that the app "is damaged and can't be opened" and offers to move it to the Trash. The app is not damaged. BitPrice is ad-hoc signed rather than notarized with a paid Apple Developer ID, and macOS refuses downloaded software it cannot verify with Apple. The command clears the quarantine flag behind that refusal.

Building from source avoids the step entirely — locally built copies are never quarantined.

## Known limits

- **One market per coin.** There is no failover to a second venue. If the market you chose goes quiet, that row stops updating and its alerts cannot fire. The app says so on the row and in the header.
- **Coinbase-sourced coins update every 60 seconds**, so an alert breach that begins and ends between two polls is not seen. The confirmation screen warns you when you pick such a market.
- **Nothing runs while the app is closed.** Price updates and alerts both stop.
- **Ticker matching is a string guess.** Confirming the wrong market shows a plausible-looking wrong price. Every row exposes the venue and product ID it is using, so the mistake is inspectable.
- Alerts require notification permission; Settings reports whether macOS will actually deliver them.
