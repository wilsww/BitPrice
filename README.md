# BitPrice

A macOS menu bar app that shows one cryptocurrency price in the menu bar and the rest of your watchlist in a panel behind it.

<!-- screenshot: menu bar label next to the open panel -->

Prices arrive over live WebSocket feeds from Binance and OKX, and over a 60-second poll from Coinbase. You pick the exact market for each coin — there is no automatic ticker matching, because ticker symbols are not unique. Price alerts fire as macOS notifications while the app is running.

No accounts, no telemetry, no third-party dependencies. macOS 14.0 or later, Apple silicon.

## Install

There is no prebuilt release. Build from source:

```bash
git clone <this repo>
cd BitPrice
bash scripts/build-app.sh
open build/BitPrice.app
```

The build needs the Xcode command line tools (`xcode-select --install`) and takes well under a minute. It compiles with Swift 6 in strict concurrency mode and treats warnings as errors, so a successful build is a clean one.

To keep it around, drag `build/BitPrice.app` into `/Applications` or `~/Applications`.

## Using it

### Starting

BitPrice has no Dock icon and no window — `LSUIElement` is set, so it lives entirely in the menu bar. After launching, look for it at the top right of the screen. It shows `BitPrice` until you have a coin with a price, then switches to that coin's symbol and price.

Click the menu bar label to open the panel. Click anywhere else to dismiss it.

Only one copy runs at a time.

<!-- screenshot: the menu bar label -->

### Adding a coin

Press the **+** button in the panel header.

1. **Search** by name or symbol. Results come from a coin catalogue, and each result shows the project name and its identifier.
2. **Pick the market.** This is the step that matters. Selecting a search result identifies the *project*, not the market — several unrelated coins can share one ticker, and wrapped or bridged assets share tickers with the originals. So the app shows every candidate market it found across Binance, Coinbase, and OKX, and you choose exactly one.
3. Press **Add**.

The market you choose is that coin's only price source. The confirmation screen says so directly: if that feed stops, the row stops updating and its alerts cannot fire. Choosing a Coinbase market also warns you that a 60-second poll can miss a brief alert breach that a live feed would have caught.

Quote assets are not restricted to USDT — any quote asset the venue lists is legal, so a market like `BTC-EUR` is available if the venue offers it.

The watchlist holds up to 25 coins. The first launch seeds Bitcoin.

<!-- screenshot: the market confirmation screen -->

### Choosing what shows in the menu bar

Each row has a star on its left. Click it to make that coin the **primary** — the one whose symbol and price appear in the menu bar itself. The star fills yellow on the current primary.

The label reads as `SYMBOL price`, for example `BTC 67,432.10`. Prices show two decimals at or above 1 and up to six below it, so small-denomination coins stay legible.

If the watchlist is empty, or the primary has no price yet, the label falls back to `BitPrice`.

Deleting the primary promotes the first remaining coin.

### Reading a row

A row shows the coin's symbol and quote asset, its latest price, and its 24-hour change. A dash means the value is not available yet.

Selecting a row opens a chart beneath the list, over **24h**, **7d**, or **30d**. The chart is drawn from the same venue that supplies the row's price. A diamond marks the series' opening close. If a refresh fails, the chart keeps showing the last data it had and says so rather than going blank.

Rows dim when their source is offline.

Use the arrows on a row to reorder it, or the remove button to delete it.

<!-- screenshot: the panel with a row selected and its chart open -->

### Price alerts

Open a row's alert editor to set one alert per coin.

- **Direction and threshold** — fire when the price goes **Above** or **Below** a price you set.
- **Cooldown** — the minimum time before the same alert can fire again.
- **Hysteresis percent** — how far the price must retreat past the threshold before the alert re-arms. At 0 the alert re-arms as soon as the price crosses back, and the cooldown alone limits repeats.

After firing, an alert disarms and waits for the re-arm price; the editor tells you when it is in that state.

Two things to know:

- **Alerts stop when the app is closed.** So do price updates. Nothing runs in the background — the Settings screen repeats this under the Quit button.
- **Alerts have a global switch.** Turning them off silences every alert. Turning them back on can fire immediately for a coin already past its threshold, which is the intended behaviour and is warned about in Settings.

Alerts on a Coinbase-sourced coin inherit the 60-second poll's blind spot: a breach that begins and ends between two polls is not seen.

<!-- screenshot: the alert editor -->

### Settings

The gear button in the panel header opens Settings.

| Setting | What it does |
|---|---|
| Launch at login | Starts BitPrice when you sign in |
| Price alerts | Global on/off for every alert |
| Alert defaults | Cooldown and hysteresis seeded into *new* alerts; existing alerts are unchanged |
| Text size | Small, Medium, Large, or Extra Large |

Text size scales everything in the panel, and the panel widens with it — so a larger size does not squeeze the columns.

**Quit** is at the bottom left of Settings.

<!-- screenshot: the settings screen -->

## Development

```bash
bash scripts/run-tests.sh    # acceptance tests
bash scripts/build-app.sh    # build and sign the app bundle
```

The tests are a plain executable with an array of named cases, not XCTest. Two cases skip when run without an Aqua session; that is expected on a headless run.

Source is in [Sources/BitPrice/](Sources/BitPrice/). The current behavioural contract is [docs/SPEC.md](docs/SPEC.md) — it is kept in step with the implementation and is the right place to look before changing anything.

Superseded design documents are in [docs/history/](docs/history/). They record how the app got here, including several rounds of adversarial review, but they describe architectures the code has since replaced. Do not treat them as current.

## Limits

- Apple silicon only; the build targets `arm64-apple-macosx14.0`.
- One market per coin. There is no failover to a second venue if that market's feed goes quiet.
- Coinbase-sourced coins update every 60 seconds rather than continuously.
- Up to 25 coins.
- The app is signed ad-hoc, so first launch may need a right-click → Open.
