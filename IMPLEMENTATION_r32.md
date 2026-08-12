# BitPrice — Implementation Specification

Revision 3.2 (2026-08-03). Four rounds of Codex review, all in thread `019fc726-637f-74b2-aff1-3c344477d7ee` (rounds 3 and 4 at high reasoning effort).

## Revision 3.2 changelog (round-4 findings)

Round 4 confirmed the round-3 blocker closed, but found a **new blocker introduced by revision 3.1 itself**, plus 7 majors. Two were durability bugs in opposite directions on the same latch.

| Change | Origin |
|--------|--------|
| **§5.10 fire path is one transaction** — append history, mutate latch, enqueue **one** snapshot, *then* notify. Revision 3.1 notified before mutating the latch, so a crash in between left durable proof the alert fired next to durable state saying it had not → **duplicate fire** on relaunch | Codex round-4 **blocker** |
| **Re-arm is persisted too** — revision 3.1 persisted only on fire, so a crash after re-arming left the alert disarmed and it **missed the next legitimate breach** | Codex round-4 major 7 |
| **Timeout/ack/reconnect precedence** — timeout acts only if generation matches, `pending[requestID]` is still that same command, and the socket is `connected`; `reconnect()` is idempotent | Codex round-4 major 3 |
| **Circuit breaker** — 5 consecutive command failures → terminal `.offline(reason)` + 5-minute retry. "Retried once" was bounded per generation but looped across them | Codex round-4 major 6 |
| **Failback needs sustained proof** — first valid tick + 60s dwell, plus 5→30 min source hysteresis after a failure. Connect+ack alone allowed 30-second flapping | Codex round-4 major 5 |
| **Coinbase-only items initialize to Coinbase** — the "absent entry means Binance" rule would have started them on a venue they have no mapping for | Codex round-4 major 4 |
| **`Sendable` payload conversion at the callback boundary** — hopping alone does not make a captured `Error`, `Notification`, or WebSocket message `Sendable` | Codex round-4 major 8 |
| Stale `inFlight` references purged from §5.2.2, the risk table, and test 36c; stale "absent entry ⇒ Binance" comment removed | Codex round-4 major 2 (self-found, incompletely fixed) |
| Tests 70–83 added, including a specification-hygiene grep for retired identifiers | Round-4 fixes |

## Revision 3.1 changelog (round-3 findings)

macOS menu bar cryptocurrency price app. SwiftUI `MenuBarExtra`, zero third-party dependencies, built with `swiftc` (SwiftPM is unavailable on this machine — see §0).

## Revision 3 changelog

Round-2 closed 7 of 10 round-1 issues. Three were only partially closed, and two new blockers were found. Revision 3 addresses all of them.

| Change | Origin |
|--------|--------|
| **Dual-venue mapping** `WatchItemMapping{binance:, coinbase:}` — a single-venue mapping made the geo-block fallback in §7 impossible to honor | Codex blocker B-new-1 |
| **Ticker matching demoted to a candidate filter** — a unique ticker match no longer auto-accepts; identity requires a stronger signal or explicit user confirmation | Codex blocker B-new-2 |
| **Confirmed subscription set** + serialized control commands + reconcile-after-every-ack — the desired-set design alone still had an acknowledgement race | Codex major M-new-1 |
| Sleep clears the confirmed set; wake reconciles the full desired set | Codex major M-new-2 |
| `hysteresisPercent` becomes `Decimal`; alert configuration validated; migration defaults defined | Codex major M-new-3 |
| Alert persistence moved off the main actor with a revision counter for ordering | Codex major M-new-4 |
| Explicit `Sendable` on every stream element and DTO; `Task { @MainActor }` loops replace Foundation timers | Codex major M-new-5 |
| §0's "verified working" claim narrowed to the frameworks actually tested | Codex major M-new-6 |
| **In-app alert history is now mandatory**, independent of OS notification success | Codex major M-new-7 |
| Alert boundary tests added (equality at threshold, invalid config, persistence failure, multi-alert ticks) | Codex major M-new-8 |
| Coinbase products filtered to `status == online`; per-source timestamps; injectable scheduler for tests; socket wording corrected | Codex minors 9–12 |
| "Crossing" renamed "threshold breach" (the algorithm is level-triggered, not edge-triggered); `Package.swift` labelled as future path | Codex nits 13–14 |

Round 3 closed 9 of 14 round-2 items outright and found **1 blocker** — a contradiction introduced by revision 3 itself.

| Change | Origin |
|--------|--------|
| **Latch initialization split into three cases** — new alert `isArmed = true`, migrated `false`, edited resets. Revision 3 defined only the migration default, which would have made a newly created already-breached alert **never fire** | Codex round-3 **blocker** |
| **Lost-acknowledgement recovery** — typed `SubscriptionCommand` with generation + requestID + operation, 10s timeout, reconnect-not-retry, all-or-nothing batch semantics, error acks no longer blamed on the mapping | Codex round-3 major 2 |
| **One `AppSnapshot`** carrying items, alert state, history, and unread count under a single revision counter; history persisted **before** the notification attempt | Codex round-3 major 3 |
| **§2.4.1 active source and failback** — `activeExchange` is runtime state, not persisted; Binance retried on backoff; fail back only after subscription ack; no blank row during handover | Codex round-3 major 4 |
| **`.verifiedIdentity` explicitly not implemented in v1** — the auto-accept branch depended on contract-address metadata the spec never defined; every v1 mapping is `.userConfirmed` | Codex round-3 major 5 |
| **Observer isolation requirements** — `NSWorkspace` sleep/wake and all `NotificationCenter` callbacks must hop; `PersistenceWorker` owns file state exclusively; scheduler protocol `Sendable` | Codex round-3 major 6 |
| `NotificationStatus` named `.scheduled` not `.delivered`; null-delimited source list in the build script; test 6 asserts client lifecycle too; test 20a marked manual-only/not-a-CI-failure; §0 opening de-staled | Codex round-3 minors 1–4, nit 2 |
| "Crossing" eliminated from F13, notification body, risk table, and tests 39–46 | Codex round-3 nit 1 |
| Tests 36g–36p, 61–69 added for lost acks, failback, and latch initialization | Round-3 fixes |

### Carried forward from revision 2

| Change | Origin |
|--------|--------|
| Coinbase fallback contract using the Exchange stats endpoint; `PriceChange.unavailable` | Codex blocker B1 (closed) |
| Binance dynamic `SUBSCRIBE`/`UNSUBSCRIBE` | Codex recommendation |
| Generation-token task ownership; explicit socket state machine | Codex M3/M4 |
| Composite health from four timestamps; per-source connection state | Codex M5/M6 (closed) |
| Server ping handling; sparkline length unguaranteed; listing-cache refresh; parsing hardening | Codex M1/M2/M7/M8 (closed) |
| Price alerts with hysteresis latch + cooldown | User requirement |
| Watchlist starts with BTC only; empty is a valid state | User decision |
| `.macOS(.v14)` deployment target | Measured |

---

## 0. Build Preconditions

**The toolchain has known defects.** The stale-modulemap repair is applied and verified; SwiftPM remains unavailable; the complete app build is unverified. Details below (Codex nit 2 — revision 3's opening line said the toolchain was broken and nothing would compile, which was true when written but stale after the repair).

Measured on 2026-08-03:

```
$ swiftc bare.swift          # print("hello") only
hello                        # OK

$ swiftc fnd.swift           # import Foundation
/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap:13:8:
  error: redefinition of module 'SwiftBridging'
```

Root cause — two modulemaps declare the same module:

```
/Library/Developer/CommandLineTools/usr/include/swift/
  bridging.modulemap   Apr 16 2025   current
  module.modulemap     Aug 18 2023   stale leftover from an older CLT
```

Both declare `module SwiftBridging {` at line 13. Current `swiftc` reads both and the module collides, which fails every `import Foundation` transitively.

Repair (requires `sudo`, reversible by renaming back):

```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.disabled
```

**Status: applied and verified 2026-08-03.** `import Foundation` now compiles (`swiftc fnd.swift` → runs, prints `fnd ok`). The stale file is preserved as `module.modulemap.disabled`, so the change is reversible.

A second defect is **independent and still present** after the modulemap repair: SwiftPM fails at manifest link time regardless of manifest content —

```
Undefined symbols for architecture arm64:
  "PackageDescription.Package.__allocating_init(name:defaultLocalization:platforms:
   pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:
   cLanguageStandard:cxxLanguageStandard:) -> PackageDescription.Package"
```

Reproduced with tools-version 6.1 and 5.9, with and without a `platforms:` clause, and again after the modulemap repair. Fixing it requires reinstalling CommandLineTools (`sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install`) or installing full Xcode.

**This is not on the critical path.** §6.3's `swiftc`-only build path is the **primary** build route; §6.2's SwiftPM script is aspirational until the reinstall happens.

**Scope of what was actually measured** (narrowed per Codex M-new-6 — revision 2 overstated this as "verified working"):

```
$ swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
         -sdk "$(xcrun --show-sdk-path)" main.swift -o bin
# exit 0
```

| Verified | Not yet verified |
|----------|------------------|
| `import Foundation` | SwiftUI, `MenuBarExtra` |
| `import UserNotifications` | `Canvas` / `Path` |
| `import AppKit` | `URLSessionWebSocketTask` |
| `-swift-version 6` accepted on a single file | `ObservableObject` / Combine |
| | Actor boundaries across the full source tree |

The single-file probe proves the toolchain links against those three frameworks. It does **not** prove the complete app compiles under Swift 6 strict concurrency. §8 test 1 is therefore the authoritative gate: a full `build-app-direct.sh` run over every source file with `-warnings-as-errors`. Treat the build path as unproven until that passes.

### 0.1 Notification delivery — untested, not confirmed

Attempting to verify `UNUserNotificationCenter` end-to-end in this environment failed for an unrelated reason. A minimal AppKit probe crashes at startup:

```
EXC_BREAKPOINT (SIGTRAP)
  SkyLight  CGSLookupServerPort
  SkyLight  SLWindowServerCreateServerPort
  HIToolbox _FirstEventTime
```

`NSApplication` cannot reach the **WindowServer** — this shell has no Aqua GUI session attached, so *any* AppKit app dies before its run loop starts, regardless of bundle structure or signing. The probe's `getNotificationSettings` callback never ran.

What this does and does not establish:

| Claim | Status |
|-------|--------|
| A bare executable cannot deliver notifications | **Confirmed, and worse than expected** — it throws `NSInternalInconsistencyException: 'bundleProxyForCurrentProcess is nil'` and terminates, rather than failing silently |
| A bundle resolves its identifier correctly | **Confirmed** — probe logged `bundleID=com.wayne.notiftest` |
| `plutil -lint` / `codesign --verify` pass on a hand-assembled ad-hoc bundle | **Confirmed** — "valid on disk", "satisfies its Designated Requirement" |
| Notifications are actually delivered from an ad-hoc signed bundle | **UNVERIFIED** — blocked by the WindowServer issue, not by a notification defect |

§8 test 20a must therefore be run **by the user in a normal desktop GUI session**, not from an automated shell. Until it passes, treat notification delivery as an assumption. Test 20a is **environment-gated, not a build failure** — an automated run that cannot reach a GUI session must skip it, not fail the build.

Codex reviewed this handling and found the disclosure adequate, but flagged that the fallback was only mentioned in prose. Per M-new-7 it is now a **hard requirement**: OS notification delivery can also be defeated by authorization status, Focus modes, and Notification Center settings, none of which the app controls. Therefore **every fired alert writes to an in-app alert history regardless of whether the OS notification succeeds** (§5.11). The OS notification is an enhancement; the in-app record is the source of truth.

Measured toolchain facts that constrain this spec:

| Fact | Value | Consequence |
|------|-------|-------------|
| `swift --version` | Apple Swift 6.1.2 | Swift 6 language mode available |
| SDK (`xcrun --show-sdk-version`) | 15.5 | macOS 15 APIs available at compile time |
| CommandLineTools | 16.4.0 | — |
| Max `PackageDescription` platform | `.macOS(.v14)` | `.v15` and `.v16` fail with `cannot be resolved`; deployment target is 14.0, not 15.0 |
| Manifest compile target | `arm64-apple-macosx14.0` | Matches the above |

Deployment target is therefore **macOS 14.0**. `MenuBarExtra` requires macOS 13+, so this is not a constraint on the design.

---

## 1. Functional Requirements

| ID | Requirement |
|----|-------------|
| F1 | Menu bar shows a single primary coin: symbol + live price (e.g. `BTC 62,788.01`) |
| F2 | Clicking the menu bar item opens a dropdown panel with the full watchlist |
| F3 | Each row shows: symbol, quote pair, 24h sparkline, price, 24h change % |
| F4 | Sparkline covers 24 hours, matching the 24h change % range |
| F5 | User can search coins by name/symbol and add them to the watchlist |
| F6 | User can delete rows, reorder them, and designate the primary coin |
| F7 | Watchlist persists across app restarts |
| F8 | No Dock icon (`LSUIElement = true`) |
| F9 | Price updates arrive in real time via WebSocket push, not polling |
| F10 | Per-source network state is surfaced in the UI and recovers automatically |
| **F11** | **Watchlist ships with BTC only; the user builds the rest via search** |
| **F12** | **Empty watchlist is a valid state with its own UI and no open socket** |
| **F13** | **Per-item price alerts: notify when price breaches a threshold, above or below** |
| **F14** | **Alerts have a configurable cooldown to suppress repeat notifications** |
| **F15** | **Alerts use a hysteresis latch so threshold jitter cannot spam notifications** |
| **F16** | **Every fired alert is recorded in-app and badged, whether or not the OS notification succeeds** |
| **F17** | **A market is never claimed as a coin's identity unless verified; otherwise the user confirms it** |

---

## 2. Data Architecture

Three layers. The split exists because CoinGecko's free Demo tier caps at 10,000 calls/month, which cannot sustain real-time price polling — a 60s interval alone needs ~43,200 calls/month.

The division is **by field, not by coin**. A single row draws its price from Binance and its sparkline from CoinGecko simultaneously.

| Field on screen | Source | Cadence | Why not the other |
|-----------------|--------|---------|-------------------|
| Price | Binance WebSocket `@ticker` field `c` | Real-time push | CoinGecko REST cannot afford the frequency |
| 24h change % | Binance WebSocket `@ticker` field `P` | Same push as price | Arrives in the same message, so it is inherently consistent with the price |
| 24h sparkline | CoinGecko `/coins/markets?sparkline=true` | Every 10 min | Binance klines has no multi-symbol batch (measured: `symbols=` returns `-1102`), so N coins would cost N calls |
| Coin search / metadata | CoinGecko `/search` | On debounced keystroke | Binance exposes no coin metadata or search |
| Fallback price | Coinbase (see §2.3) | 60s poll, only for affected items | Only used for coins Binance does not list |

Quota: sparkline at 10-minute intervals = 144 calls/day ≈ 4,320/month against a 10,000 cap. 2.3x headroom.

**Cross-venue consequence:** Binance and CoinGecko report from different venues, so their numbers differ slightly. The sparkline is therefore rendered **without y-axis labels** — shape only. This is deliberate: it prevents a visible numeric contradiction next to the Binance price. It also means the sparkline's direction **must not** be used to validate the sign of Binance's 24h change (Codex M2).

### 2.1 Binance WebSocket Contract

Connect to the combined-stream endpoint **without** a stream list, then subscribe dynamically:

```
wss://stream.binance.com:9443/stream
```

Subscribe / unsubscribe over the open socket:

```json
{ "method": "SUBSCRIBE",   "params": ["btcusdt@ticker", "ethusdt@ticker"], "id": 1 }
{ "method": "UNSUBSCRIBE", "params": ["ethusdt@ticker"],                   "id": 2 }
```

The server replies `{"result":null,"id":1}` on success, or an error object. Revision 1 rebuilt the URL and reconnected on every watchlist change; this protocol makes a watchlist edit a message on a live socket instead, which is what removes the multi-source reconnect race (Codex M4).

Ticker payload, fields used:

```json
{
  "stream": "btcusdt@ticker",
  "data": { "s": "BTCUSDT", "c": "62794.13", "P": "-0.659", "E": 1754000000000 }
}
```

`s` symbol, `c` last price, `P` 24h change percent, `E` event time. Revision 1 also parsed `h`/`l` (24h high/low) but nothing consumed them — **dropped** (Codex nit).

Protocol requirements, corrected per Codex M1:

| Requirement | Detail |
|-------------|--------|
| Stream names | Lowercase. `BTCUSDT@ticker` is rejected |
| Server-originated ping frames | **Must be answered with a pong.** `URLSessionWebSocketTask` replies automatically at the protocol level, but the app must not assume a fixed server ping interval — treat any received ping as a liveness signal and never depend on its timing |
| Application-level ping | `sendPing` every 30s, independently of server pings. Purpose is detecting half-open sockets that surface neither data nor error. Three consecutive failures force a reconnect. This **does not substitute** for answering server pings |
| Control-traffic budget | Binance limits incoming messages to ~5/second, counting **all** control traffic — SUBSCRIBE, UNSUBSCRIBE, and pong alike, not just subscribe frames. Batch subscription changes into a single message and coalesce watchlist edits over 1s |
| Connection lifetime | Connections are valid for 24h. Schedule a proactive reconnect at 23h, anchored to the **actual socket-open timestamp**, not to app launch |
| Stream cap | 1024 streams per connection. Irrelevant at this scale, but §5.1 caps the watchlist at 100 items to keep it that way |

### 2.2 CoinGecko Contracts

Batch price + sparkline:

```
GET https://api.coingecko.com/api/v3/coins/markets
      ?vs_currency=usd&ids=bitcoin,ethereum&sparkline=true&price_change_percentage=24h
```

Fields used per element: `id`, `symbol`, `current_price`, `price_change_percentage_24h`, `sparkline_in_7d.price`.

**The 168-point / 1-hour-spacing shape is an observation, not an API guarantee** (Codex M2). Measured 168 points on 2026-08-03, but the implementation must handle:

| Case | Behavior |
|------|----------|
| `sparkline_in_7d` absent or null | Keep the previously cached series; render nothing if there is none |
| Array shorter than 24 | Render what exists; do not pad |
| Array longer than expected | Take the last 24 elements |
| Contains null / non-finite values | Drop those points |
| All values equal | Flat-line branch in `SparklineView` (§5.8) |

Because spacing is not guaranteed, the last 24 points are treated as "approximately the last 24 hours" and the sparkline is never used as a correctness oracle for Binance's 24h percentage.

Search:

```
GET https://api.coingecko.com/api/v3/search?query=sol
```

Returns `coins[]` with `id`, `name`, `symbol`, `market_cap_rank`, `thumb`, `large`.

Both endpoints: send `x-cg-demo-api-key` when a key is configured; 15s timeout; the query string must be percent-encoded via `URLComponents` (Codex M8). On HTTP 429, honor `Retry-After` when present, otherwise back off 60s and skip the cycle — never retry a 429 immediately. Treat 429 as the authoritative rate signal rather than trusting the documented "5–15 calls/min" figure (Codex nit).

### 2.3 Coinbase Fallback Contract — rewritten (Codex blocker B1)

Revision 1 specified `/v2/prices/{pair}/spot` as the fallback. That endpoint returns only:

```json
{ "data": { "amount": "62723.915", "base": "BTC", "currency": "USD" } }
```

**No 24h change field.** A fallback coin therefore could not populate the required price + 24h-change row — revision 1's design was self-contradictory.

Resolution, three parts:

**(a) Use a fallback endpoint that carries 24h statistics.** Coinbase Exchange's public ticker provides open/high/low plus last price:

```
GET https://api.exchange.coinbase.com/products/{product_id}/stats
→ { "open": "...", "high": "...", "low": "...", "last": "...", "volume": "..." }
```

24h change is computed as `(last - open) / open * 100`, **guarded by `open > 0`** — a zero or missing `open` yields `.unavailable`, never a division by zero (Codex B-new-1). Codex confirmed this endpoint is documented as returning 24-hour statistics including `open` and `last`, so the formula is valid. Still verified live before implementation (§8 test 0b); if fields differ, fall back to part (b) rather than inventing a value.

**(b) When 24h change genuinely cannot be obtained, say so.** `Quote.change` is an enum, not a `Double` — an unavailable change renders as `—`, never as `0.00%`. A fabricated zero would read as "flat market" and is unacceptable.

**(c) Product IDs are resolved explicitly and persisted, never derived from a symbol.** Coinbase product IDs (`BTC-USD`) do not follow from a CoinGecko id or symbol. Resolution goes through `GET https://api.exchange.coinbase.com/products`, matched at add time and never recomputed later.

Only products with **`status == "online"`** are eligible (Codex minor 9). The listing also contains `offline`, `internal`, and `delisted` products, plus per-product `trading_disabled` and `cancel_only` flags; all of those are rejected at resolution time rather than producing a mapping that silently never quotes.

Fallback items poll every 60s. §2's table and §5.7 agree on this figure — revision 1 said "on demand" in one place and 60s in another (Codex minor). If no item uses the fallback, the poller does not run.

**Coverage is conditional.** A geo-block can only move an item to Coinbase if that item has a persisted Coinbase mapping (§2.4). Items without one show an unavailable state; §7 states this rather than promising universal fallback.

Fallback precision is lower than a push stream: a 60s poll can miss a threshold breach entirely. Rows and alerts backed by the fallback are marked accordingly in the UI (§5.8, §5.9).

### 2.4 Identifier Mapping — rewritten (Codex blocker B2)

The sources use three different identifier spaces:

| Space | Example | Notes |
|-------|---------|-------|
| CoinGecko id | `bitcoin` | Canonical key throughout the app |
| Binance symbol pair | `BTCUSDT` | Base + quote concatenated, no separator |
| Coinbase product id | `BTC-USD` | Hyphenated |

Revision 1 derived the Binance pair as `uppercase(symbol) + quoteAsset` and validated it against `exchangeInfo`. Codex correctly rejected this: **existence of a pair does not prove it is the same project as the selected CoinGecko coin.** CoinGecko symbols are not unique — a query for `SOL` returns Solana alongside unrelated tokens, and wrapped/bridged variants share tickers with their originals. A user could select coin A and be shown coin B's price.

Revision 2 fixed the recomputation problem but Codex found it still auto-accepted an unverified identity (B-new-2):

> "If exactly one venue candidate exists, the spec accepts it. That still proves only ticker equality, not that the exchange asset represents the selected CoinGecko project. A CoinGecko search result can be the wrong project, a wrapped token, or a token sharing a ticker with an unrelated exchange asset. 'CoinGecko search returned more than once' is also not a sufficient test: the selected result has one ID even when other results share its symbol."

Revision 3 design — **both venues are resolved and stored** (B-new-1), and **ticker matching is only a candidate filter, never proof of identity** (B-new-2):

```swift
struct MarketMapping: Codable, Hashable, Sendable {
    let exchange: Exchange           // .binance | .coinbase
    let productID: String            // "BTCUSDT" or "BTC-USD" — verbatim from the venue
    let baseAsset: String            // as the venue reports it
    let quoteAsset: String           // as the venue reports it
    let confidence: MappingConfidence
    let resolvedAt: Date
}

/// Both venues, so a geo-block or delisting has somewhere to fall back to.
struct WatchItemMapping: Codable, Hashable, Sendable {
    var binance: MarketMapping?
    var coinbase: MarketMapping?

    var preferred: MarketMapping? { binance ?? coinbase }
}

enum MappingConfidence: String, Codable, Sendable {
    case userConfirmed      // the user explicitly picked this market
    case verifiedIdentity   // a stronger signal than the ticker agreed (e.g. contract address)
    case tickerMatchOnly    // ticker agreed and nothing contradicted it — displayed as such
}
```

**Why both venues are resolved up front:** §7 promises that a Binance geo-block falls back to Coinbase. With one mapping per item, a coin added via Binance has no Coinbase product id, so that promise could not be kept — and prompting for disambiguation mid-outage is unacceptable. Coinbase resolution therefore runs at add time too, opportunistically: failure to find a Coinbase market is not an error, it simply means that item has no fallback and §7 says so explicitly rather than implying universal coverage.

Resolution at add time:

1. **Candidate gathering.** Query each venue's own listing (`exchangeInfo` / `products`) for markets whose `baseAsset` case-insensitively equals the coin's symbol, filtered to tradable status (`TRADING` / `online`). This is a **filter, not an identity test**.
2. **Identity check — deferred in v1.** `.verifiedIdentity` requires comparing a CoinGecko contract address against exchange asset metadata, but §2.5 retains only symbol, base asset, quote asset, and status; no venue metadata endpoint or comparison rule is specified. Codex flagged this as a promise the spec cannot currently keep (major 5). **Decision for v1: the auto-accept branch is not implemented.** `MappingConfidence.verifiedIdentity` stays in the model as a forward-compatible case, but no code path produces it, so every mapping in v1 is `.userConfirmed`. This keeps the safety property deterministic instead of resting on an unspecified mechanism.
3. ~~Auto-accept on `.verifiedIdentity`~~ — unreachable in v1 by the decision above. Reinstating it requires specifying the CoinGecko and venue endpoints, response fields, normalization rules, and failure behavior first.
4. **The user confirms every mapping**, including when there is exactly one candidate. `DisambiguationSheet` lists venue, product id, quote asset, and states plainly that the match is by ticker symbol only. Confirmation yields `.userConfirmed`.
5. **No venue on either exchange** → the coin cannot be added; `SearchSheet` says why rather than adding a permanently blank row.
6. The accepted mapping is persisted. **`productID` is never recomputed from `symbol`** — not on launch, not on reconnect, not on migration.

Rows carry a provenance indicator, and the detail view names the venue and product id, so a user who was shown the wrong project can spot it. **The UI never claims project identity it has not verified** — wording is "matched by ticker", not "verified".

Residual risk, stated plainly: a user can confirm the wrong market. That is now an explicit, visible user choice rather than an implicit identity claim by the app — which is the property B2/B-new-2 was about.

### 2.4.1 Active Source and Failback (Codex major 4)

`WatchItemMapping` is **persisted identity**; which venue is currently serving a row is **runtime state**. Conflating them was the gap: revision 3 defined the Binance → Coinbase switch during a geo-block but never defined the way back, so a temporary outage would leave the user on 60-second polling indefinitely, silently losing the real-time behavior that motivated the whole architecture.

- `activeExchange` is **not persisted** — it is derived at runtime from mapping availability and live source health, and therefore **lives in `PriceCoordinator` as `[UUID: Exchange]`, not as a field on `WatchItem`** (§5.7). `WatchItem` is `Codable`, so a field there would be written into `AppSnapshot` and silently persist the very state this rule says must not survive a relaunch.

- **Initialization is by mapping availability, not a blanket default** (Codex round-4 major 4). Revision 3.1 said an absent entry "means Binance", which is wrong for a Coinbase-only item — it would start on a venue it has no mapping for and never quote:

  ```text
  if mapping.binance  != nil → .binance
  else if mapping.coinbase != nil → .coinbase
  else → unavailable (should not exist; §2.4 step 5 refuses such an item)
  ```

  The map starts empty on launch and is populated by this rule, so a Coinbase-only item begins on Coinbase both on first launch and after every relaunch.
- **Degrade:** on a Binance geo-block or connect failure, items with a Coinbase mapping move to 60-second polling; items without one show unavailable.
- **Retry:** while degraded, Binance is retried on the §5.4 backoff schedule, capped at 30s. The retry does not depend on the user reopening the panel.
- **Fail back only on sustained proof, not a momentary success** (Codex round-4 major 5). Connect + ack shows Binance *can* serve the item, not that it *will keep* serving it. Revision 3.1 stopped there, which lets a socket that dies right after acking reclaim and lose the item every 30 seconds — flapping the active source, the alert precision disclosure, and the Coinbase poller. Failback requires **all** of:
  1. socket `connected`,
  2. that item's subscription acknowledged (§5.2.1),
  3. the **first valid Binance tick** for the item received,
  4. Binance health (§5.4) sustained for a **60-second dwell**.

- **Source hysteresis:** after a Binance failure, that item cannot return to Binance for **5 minutes**, regardless of how healthy the socket looks. Repeated failures escalate the hold (5 → 10 → 20 min, capped at 30). This is the same principle as the alert latch — a threshold plus a buffer, because "healthy right now" is not a stable signal.

- **No gap during handover:** the last Coinbase quote is retained until conditions 3 and 4 are both met. The row never blanks while switching, and Coinbase polling stops **only after** the dwell completes — not at ack time.
- Alert evaluation follows the active source, so precision disclosure in `AlertSheet` (§5.8) reflects the current source, not the originally resolved one.

### 2.5 Exchange Listing Cache (Codex M7)

`exchangeInfo` is ~2 MB; only `symbols[].symbol`, `baseAsset`, `quoteAsset` where `status == "TRADING"` is retained.

A cached listing goes stale — pairs get halted or delisted after a `MarketMapping` was persisted. Refresh triggers:

- On launch, if the cache is older than 24h
- On any rejected `SUBSCRIBE` for a pair the cache claims is tradable
- On repeated connect failures

A subscription error naming a specific pair marks that mapping as needing re-resolution; the affected row shows a warning and offers re-resolution rather than silently displaying a frozen price.

---

## 3. Project Layout

```
BitPrice/
├── Package.swift
├── Info.plist
├── scripts/
│   ├── build-app.sh              # SwiftPM path
│   ├── build-app-direct.sh       # swiftc-only path, no SwiftPM
│   └── verify-app.sh
├── Sources/BitPrice/
│   ├── BitPriceApp.swift
│   ├── Models/
│   │   ├── WatchItem.swift
│   │   ├── MarketMapping.swift
│   │   ├── Quote.swift
│   │   ├── PriceAlert.swift
│   │   └── SearchResult.swift
│   ├── Store/
│   │   ├── WatchlistStore.swift
│   │   └── PersistenceWorker.swift   # actor: off-main-actor encode + write
│   ├── Network/
│   │   ├── BinanceStreamClient.swift
│   │   ├── BinanceRESTClient.swift
│   │   ├── CoinGeckoClient.swift
│   │   └── CoinbaseClient.swift
│   ├── Alerts/
│   │   ├── AlertEngine.swift
│   │   ├── AlertHistory.swift        # mandatory in-app record (§5.11)
│   │   └── NotificationService.swift
│   ├── Coordinator/
│   │   └── PriceCoordinator.swift
│   └── Views/
│       ├── MenuBarLabel.swift
│       ├── WatchlistPanel.swift
│       ├── EmptyStateView.swift
│       ├── WatchRow.swift
│       ├── SparklineView.swift
│       ├── SearchSheet.swift
│       ├── DisambiguationSheet.swift
│       ├── AlertSheet.swift
│       └── AlertHistoryView.swift
└── build/
    └── BitPrice.app
```

### Package.swift — future path, not the current build (Codex nit 13)

**This manifest is not used to build the app today.** SwiftPM cannot link a manifest on this machine (§0), so the authoritative build is §6.3's `swiftc` invocation. The manifest is kept so the project converts cleanly once CommandLineTools is reinstalled — treat it as documentation of intent, and do not add it to any build instruction until §0's SwiftPM defect is resolved.

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BitPrice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BitPrice", path: "Sources/BitPrice")
    ]
)
```

Revision 1 declared `.macOS(.v15)` and tools-version 6.1. Both were wrong for this toolchain: `.v15` fails with `reference to member 'v15' cannot be resolved`, and neither tools-version currently links. Swift 6 language mode is requested via a compiler flag in the build scripts (§6) rather than a manifest setting, so the strict-concurrency requirement survives the downgrade to tools-version 5.9.

Strict concurrency is a deliberate requirement, not incidental: it is what prevents the WebSocket receive loop from racing UI state.

---

## 4. Data Models

```swift
struct WatchItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let coinGeckoID: String          // canonical key
    let symbol: String               // display, e.g. "BTC"
    let name: String                 // display, e.g. "Bitcoin"
    var mapping: WatchItemMapping    // §2.4 — BOTH venues
    var sortIndex: Int
    var alert: PriceAlert?
    // NOTE: activeExchange is deliberately NOT a field here — see below.
}

/// Which venue is currently serving each row. Runtime state, NOT persisted (§2.4.1).
/// `WatchItem` is Codable, so putting activeExchange there would persist it and
/// contradict §2.4.1 — it lives in the coordinator instead.
/// Held by PriceCoordinator as `[UUID: Exchange]`, initialized by mapping
/// availability per §2.4.1 — Binance if that mapping exists, else Coinbase.

/// Element of the Binance AsyncStream. Explicitly Sendable (§5.7.1).
struct TickerUpdate: Sendable, Equatable {
    let productID: String            // "BTCUSDT"
    let price: Decimal
    let changePercent24h: Double
    let eventTime: Date
}

enum PriceChange: Codable, Hashable, Sendable {
    case percent(Double)
    case unavailable               // renders "—", never 0.00%
}

struct Quote: Sendable, Equatable {
    let price: Decimal
    let change: PriceChange
    let updatedAt: Date
    let source: Exchange
}

enum Exchange: String, Codable, Sendable { case binance, coinbase }

struct SearchResult: Identifiable, Sendable {
    let id: String                 // CoinGecko id
    let name: String
    let symbol: String
    let marketCapRank: Int?
}
```

`Decimal` for price, not `Double`: prices arrive as decimal strings and are rendered to the user; binary floating point produces visible artifacts on values like `62794.13`. Percentages stay `Double` — display-only, never accumulated.

Staleness is **not** a computed property on `Quote`. Revision 1 had `var isStale: Bool { Date().timeIntervalSince(updatedAt) > 60 }`, which never triggers a UI update because nothing publishes at the 60-second boundary (Codex minor). Instead `PriceCoordinator` holds a `staleIDs: Set<String>` recomputed by a 15-second `@MainActor` timer, so crossing the boundary actually redraws.

### 4.1 PriceAlert (new — F13/F14/F15)

```swift
struct PriceAlert: Codable, Hashable, Sendable {
    var direction: Direction          // .above | .below
    var threshold: Decimal            // must be > 0
    var cooldown: TimeInterval        // default 900 (15 min), must be >= 0
    var hysteresisPercent: Decimal    // default 0.5, must be 0 ..< 100
    var isEnabled: Bool

    // Runtime state — MUST persist (see below)
    var isArmed: Bool
    var lastFiredAt: Date?

    enum Direction: String, Codable, Sendable { case above, below }
}
```

**`hysteresisPercent` is `Decimal`, not `Double`** (Codex M-new-3). Revision 2 declared it `Double` and computed `Decimal(alert.hysteresisPercent / 100)`, which pushes binary floating-point error into threshold arithmetic that is otherwise exact. Parsed from the user's input as a validated decimal string.

**Validation** — enforced at construction and on decode, since revision 2 constrained none of it:

| Field | Rule | On violation |
|-------|------|--------------|
| `threshold` | `> 0`, finite | Reject at the sheet; a decoded bad value disables the alert |
| `hysteresisPercent` | `0 ..< 100`, finite | Same |
| `cooldown` | `>= 0`, finite | Same |

A decoded alert that fails validation is **disabled rather than dropped**, so the user sees it and can correct it instead of silently losing a configured alert.

### Latch initialization — the three cases must not be conflated

Revision 3 initially defined only the migration default, which Codex correctly identified as a blocker: a **new** alert defaulting to `isArmed = false` enters the re-arm branch, finds the price still beyond the threshold, and therefore **never fires** — contradicting `AlertSheet`'s "will fire on the next tick" warning and §8 test 46. The three cases have opposite correct answers:

| Case | `isArmed` | `lastFiredAt` | Reason |
|------|-----------|---------------|--------|
| **Newly created alert** | **`true`** | `nil` | The user just asked to be told about this threshold. If it is already breached, firing on the next tick is the intended behavior and is what `AlertSheet` warns about |
| **Migrated alert** missing the field | **`false`** | `nil` | Historical armed state is unknown. Assuming armed would fire for every already-breached alert at once — the launch burst the latch exists to prevent |
| **Edited alert** (threshold, direction, or hysteresis changed) | **`true`** | **`nil`** | An edit makes prior latch state meaningless. Reset so the new threshold behaves like a new alert; clearing `lastFiredAt` prevents an old cooldown from suppressing the first breach of a new threshold |

Enabling a previously disabled alert counts as an edit. Changing only `cooldown` does not reset the latch — it does not alter what counts as a breach.

**No quote yet at creation:** evaluation is deferred until the first accepted quote for that item. An alert never fires against a stale or absent price.

**Missing-field defaults on decode:**

| Missing field | Default |
|---------------|---------|
| `isArmed` | `false` (migration case above) |
| `lastFiredAt` | `nil` |
| `hysteresisPercent` | `0.5` |

**Arithmetic range guard** (Codex major 3): `Decimal` has finite precision, so `threshold * hysteresisPercent / 100` can overflow or lose significance at extreme magnitudes. The band computation is checked for a finite, non-NaN result; if it fails, the alert is disabled and flagged in the UI rather than evaluated against a garbage band. Field-level validation alone does not cover this, since two individually valid values can still produce a bad product.

Two independent suppression mechanisms are required, and the reason matters:

**Cooldown alone is insufficient.** Binance pushes roughly once per second. A price hovering at the threshold breaches it on dozens of ticks per minute. A cooldown limits notifications to one per interval — but the user still receives one every 15 minutes, indefinitely, while the price sits near the threshold. That reads as spam.

**The hysteresis latch is what actually fixes it.** After firing, the alert disarms. It only re-arms once the price has left a buffer band around the threshold:

- `.above` re-arms when `price < threshold × (1 − hysteresis)`
- `.below` re-arms when `price > threshold × (1 + hysteresis)`

`isArmed` and `lastFiredAt` **must be persisted**. If they live only in memory, every relaunch re-arms every alert; if the price is still on the far side of a threshold, the user gets a burst of notifications at launch.

---

## 5. Component Specifications

### 5.1 WatchlistStore

`@MainActor final class WatchlistStore: ObservableObject`

- Persists to `~/Library/Application Support/BitPrice/watchlist.json` via `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`.
- One file holds items **and** their alerts. A separate `alerts.json` would allow the two to drift out of sync.
- Atomic writes (`.atomic`) so a crash mid-write cannot truncate the list.
- Write debounce 500 ms — reordering emits many mutations in quick succession.
- **Persistence runs off the main actor** (Codex M-new-4). Revision 2 had alert transitions "flush immediately" from `@MainActor` code, which means a synchronous atomic JSON write on the thread that draws the menu bar — during active price movement, exactly when responsiveness matters.

- **One snapshot carries the entire application state** (Codex major 3). A `WatchlistSnapshot(items:)` plus a separate history write would share the revision counter while carrying disjoint state, so the worker's "discard older revisions" rule would let a newer watchlist write silently drop a newer history record. There is exactly one persisted value:

  ```swift
  struct AppSnapshot: Codable, Sendable {
      let items: [WatchItem]           // includes each item's PriceAlert and latch state
      let alertHistory: [AlertRecord]
      let unreadAlertCount: Int
      let revision: UInt64
  }
  ```

  ```swift
  // On the main actor: snapshot only, always complete.
  let snapshot = AppSnapshot(items: items,
                             alertHistory: history.records,
                             unreadAlertCount: history.unreadCount,
                             revision: nextRevision())
  Task { await persistenceWorker.write(snapshot) }   // encode + file I/O off-actor
  ```

  `AppSnapshot` is `Sendable` and immutable; `PersistenceWorker` is an `actor` that **exclusively** owns the file URL and handle — `WatchlistStore` never touches the filesystem itself (§5.7.1). The monotonic `revision` accompanies every snapshot and the worker **discards any snapshot older than the last it wrote**. Because every snapshot is complete, a discard can never lose state that a newer snapshot does not already contain.

  **Partial writes are prohibited.** There is no alert-only, history-only, or items-only write path.

- Alert transitions skip the 500 ms debounce (losing them causes launch spam) but are still asynchronous — immediacy means not debounced, not blocking the UI.
- **First launch seeds BTC only** (F11). Revision 1 seeded BTC/ETH/SOL.
- Missing file, empty file, or malformed JSON never throws — a corrupt file must not brick launch. The corrupt file is preserved before being replaced, at `watchlist.corrupt.<ISO8601-timestamp>.json`; revision 1 used a fixed name that would overwrite a prior corrupt copy (Codex minor).
- **Empty is a valid state** (F12). The user may delete every row. This is not an error, and §5.4 must not open a socket for it.
- Watchlist capped at 100 items, keeping the 1024-stream limit unreachable (Codex nit).
- Publishes `items: [WatchItem]` sorted by `sortIndex`. `primary` is the lowest `sortIndex`, or `nil` when empty.

### 5.2 Socket State Machine (Codex M4)

Revision 1 let five independent sources mutate the socket: watchlist edits, the 23h reconnect, backoff retries, receive failures, and sleep/wake. They raced.

Revision 2 funnels all of them through one state machine owned by `BinanceStreamClient`:

```
stopped ──connect()──▶ connecting ──success──▶ connected
   ▲                        │                      │
   │                     failure                 failure
   │                        ▼                      ▼
   └──stop()───────── reconnecting ◀──────────────┘
                            │
connected ──sleep()──▶ suspending ──▶ suspended ──wake()──▶ connecting
```

Rules:

- **Watchlist edits never transition state.** They update a *desired subscription set*. The client diffs desired against confirmed and emits SUBSCRIBE/UNSUBSCRIBE when `connected`; in any other state the desired set is stored and reconciled on reaching `connected`.
- **Desired set empty → target state is `stopped`.** No socket is held open for an empty watchlist (F12).
- Only the state machine may open, close, or replace a socket.
- **At most one socket exists at a time.** Revision 2 said "one socket for the whole app lifetime", which contradicts the `stopped` and `suspended` states (Codex minor 11). The socket is recreated across those transitions; it is not a process-lifetime singleton.

### 5.2.1 Subscription Reconciliation (Codex M-new-1)

The desired-set design removed reconnect races but left an **acknowledgement race**. Codex's sequence:

1. desired = `{BTC}`
2. client sends `SUBSCRIBE BTC`
3. user removes BTC before the ack arrives → desired = `{}`
4. the subscribe ack arrives
5. if the ack sets actual state to `{BTC}` without an immediate re-diff, **BTC stays subscribed forever**

The inverse ordering produces a duplicate subscribe, or an unsubscribe for a stream that was never acknowledged.

Fix — two sets, a typed command queue, and a timeout:

```swift
private var desired: Set<String>      // what the watchlist wants
private var confirmed: Set<String>    // what the server has acknowledged

private var pending: [Int: SubscriptionCommand]   // keyed by requestID

struct SubscriptionCommand: Sendable {
    let generation: UInt64            // the socket this belongs to
    let requestID: Int                // Binance echoes this in the ack
    let operation: Operation          // .subscribe | .unsubscribe
    let streams: Set<String>
    let sentAt: Date
}
```

Revision 3's first draft tracked `inFlight` as a bare `Set<String>`, which Codex correctly rejected: it records *which* streams are outstanding but not *what was asked of them*, so an ack cannot tell a subscribe from an unsubscribe, and nothing binds the command to a socket generation.

- **Control commands are serialized per socket.** One outstanding batch at a time; new edits queue rather than interleave. This also keeps the ~5 messages/second control budget (§2.1) satisfiable by construction.
- **Every command carries its generation and is dropped on ack if the generation is stale** (§5.3). A completion from a replaced socket can never mutate the new socket's bookkeeping.
- **Every ack triggers an immediate re-diff.** On a success ack, apply the command's operation to `confirmed`, remove it from `pending`, then recompute both `desired − confirmed` (to subscribe) and `confirmed − desired` (to unsubscribe). Non-empty → send the next batch. This is what closes the original race: a stale ack updates bookkeeping and is immediately corrected by the re-diff.
- **Reconciliation is idempotent** — running it when `desired == confirmed` sends nothing.

**Lost acknowledgements** (Codex major 2). Convergence above assumes acks arrive. If a `SUBSCRIBE` reaches Binance and the ack is lost, the server streams data the client never recorded as confirmed, and the command sits in `pending` forever on an otherwise healthy socket.

- **Every command has a 10-second acknowledgement timeout.** On expiry the client cannot know whether the server applied it, so local bookkeeping is untrustworthy and cannot be repaired by guessing.
- **Recovery is a reconnect, not a retry.** The socket is torn down and a new generation opened, which clears `confirmed` and `pending` (§5.2.2) and reconciles the full desired set against a known-empty server state. Retrying the individual command cannot work precisely because the server's state is unknown.
- A timeout-driven reconnect is logged and counts toward `binance` health (§5.4) — repeated timeouts are a degraded connection, not a healthy one.

**Timeout / ack / reconnect precedence** (Codex round-4 major 3). The generation check stops callbacks from a *replaced* socket, but does not by itself prevent duplicate reconnects **within** one generation, nor resolve a timeout and an ack racing each other. A timeout handler therefore acts only if all three hold:

1. `currentGeneration == command.generation`
2. `pending[command.requestID]` is still **that same command** (identity, not just presence)
3. the socket is `connected` in that generation

Any failure means the event has already been superseded — the handler no-ops. This resolves the specific races: an ack arriving exactly at timeout removes the entry from `pending`, so condition 2 fails and the timeout does nothing; a timeout firing after a new generation was allocated fails condition 1; a timeout during an in-progress reconnect fails condition 3.

**`reconnect()` is idempotent.** If the state machine is already `reconnecting`, further timeout or failure events only record health state — they never start a second reconnect. The same applies to a generic-error retry arriving while a reconnect is in flight.

**Consecutive-failure circuit breaker** (Codex round-4 major 6). "Retried once" is bounded within a generation, but a persistent generic error loops across generations: error → retry → reconnect → new generation → retry → reconnect, forever. The 30s backoff cap limits the *rate*, not the loop.

- A counter tracks **consecutive** command failures across generations, reset by any successful ack.
- After **5** consecutive failures the client enters a terminal `.offline(reason)` state (§5.7), retains `desired`, and stops the fast retry cycle.
- From there it retries on a slow schedule (5 minutes) or immediately on a meaningful external change — network reachability regained, wake from sleep, or a user-initiated retry from the panel.
- The UI shows the terminal state with its reason, so a permanently failing subscription is visible rather than silently burning battery.

**Batch and error semantics.** Binance acknowledges at request level, not per stream, so a batch is treated as **all-or-nothing**: a success ack applies every stream in the command, an error ack applies none.

- **An error ack is a transport/protocol signal, not evidence of a bad mapping.** Revision 3's first draft marked the affected mapping for re-resolution on any error ack, which Codex flagged as wrong — a transient error would wrongly cast doubt on a valid market. Instead: the command is retried once; if it fails again with an error naming a specific invalid stream, *then* that mapping is marked for re-resolution (§2.5). Generic errors escalate to a reconnect.
- **An unknown or duplicate `requestID`** (no matching `pending` entry) is ignored, and logged — it means bookkeeping already moved on.
- **Single-stream commands are used when a batch error must be attributed** to a particular stream, since request-level acks cannot otherwise identify the culprit.

### 5.2.2 Sleep and Wake (Codex M-new-2)

Revision 2 did not say whether the confirmed set survived suspension. Both readings are broken: retaining it means wake sends nothing and receives nothing; discarding it silently was never stated as a rule. Made explicit:

**On `sleep()`:**
1. Cancel the receive loop, ping timer, reconnect timer, and command queue for the current generation.
2. Close the socket.
3. **Clear `confirmed` and cancel/discard every entry in `pending`** — server-side subscription state is no longer trustworthy once the socket is gone, and a command belonging to the old socket must never be inherited by the new one. All pending commands are discarded on generation replacement, not carried over.
4. **Preserve `desired`** — it is the user's watchlist, unaffected by sleep.

**On `wake()`:** allocate a new generation, connect, then reconcile the **entire** desired set from an empty confirmed set. The same rule applies to any reconnect, not just wake: a new socket always starts with `confirmed` empty.

### 5.3 Generation-Token Task Ownership (Codex M3)

Every socket instance is assigned a monotonically increasing `generation: UInt64`. Receive loop, ping timer, reconnect timer, and teardown all capture their generation at creation.

**A task's effect is applied only if its generation equals the client's current generation.** A late callback from a replaced socket is dropped, not acted upon.

- All tasks of generation *n* are cancelled before generation *n+1* opens a socket.
- The `AsyncStream` continuation is owned by the client for the app's lifetime, not per socket; stream termination cancels all internal tasks.
- `Task.detached` is prohibited across the actor boundary — it defeats isolation checking and was the latent race Codex flagged. Child tasks inherit actor isolation.

### 5.4 BinanceStreamClient

`actor BinanceStreamClient`, built on `URLSessionWebSocketTask`. Exposes `AsyncStream<TickerUpdate>`.

- **At most one socket at a time** (§5.2 — not "one for the app lifetime", which contradicts the `stopped` and `suspended` states). The menu bar label is always visible, so the stream is *not* closed when the panel closes. It closes only on `NSWorkspace.willSleepNotification` (§5.2.2) or when the desired set empties, and reopens on `didWakeNotification` or the first item added.
- **Backoff:** 1s, 2s, 4s, 8s, 16s, capped at 30s, ±20% jitter.
- **Backoff reset requires composite health** (Codex M5). Revision 1 said "healthy for 60s" without defining health. Four timestamps are tracked separately:

  | Timestamp | Meaning |
  |-----------|---------|
  | `socketOpenedAt` | Handshake completed |
  | `lastValidTickerAt` | A well-formed ticker was parsed |
  | `lastPongAt` | Application ping was answered |
  | `lastServerEventAt` | Any frame arrived, including server pings |

  Health = socket open **and** a valid ticker within 60s **and** a pong within 90s. Backoff resets only after health holds continuously for 60s. Resetting on connect alone produces a tight loop when the server accepts and immediately drops.

- Geo-blocking (HTTP 451/403 on connect) is detected and reported distinctly, not as a generic failure; §7 covers the fallback path.

### 5.5 BinanceRESTClient

`actor BinanceRESTClient`. Fetches and caches the tradable-pair listing per §2.5, answers **candidate** queries for §2.4 resolution (candidates only — it never asserts project identity), and exposes an explicit `refresh()` for the triggers in §2.5.

`CoinbaseClient` (§5.6) does the same against `GET /products`, filtered to `status == "online"`, so both venues can be resolved at add time (§2.4).

### 5.6 CoinGeckoClient / CoinbaseClient

`actor` each. Contracts per §2.2 and §2.3. Shared hardening (Codex M8):

- Check `HTTPURLResponse.statusCode` **before** decoding. A 4xx/5xx body is often JSON and would otherwise decode into a confusing model error.
- Build URLs with `URLComponents`; never string-interpolate a user-supplied query.
- Reject non-finite `Double` values (`isFinite == false`) and null numerics rather than propagating NaN into a chart or a comparison.
- 15s timeout on every request; a hung fetch must not block the next cycle.
- CoinGecko `ids` chunked at 250 per request.

### 5.7 PriceCoordinator

`@MainActor final class PriceCoordinator: ObservableObject`. Sole owner of merged state.

- `quotes: [String: Quote]`, `sparklines: [String: [Double]]`, `staleIDs: Set<String>` — all keyed by `coinGeckoID`.
- Maps incoming `BTCUSDT` back to `coinGeckoID` through a reverse index built from persisted `WatchItemMapping` product ids — never by re-deriving from symbols (§2.4). The index covers both venues, so a geo-block switch needs no rebuild.
- **Per-source connection state** (Codex M6). Revision 1 had one `.live`/`.offline` flag, conflating Binance connectivity with CoinGecko and Coinbase health:

  ```swift
  struct SourceHealth: Sendable {
      var binance: SourceStatus
      var coinGecko: SourceStatus
      var coinbase: SourceStatus
  }

  struct SourceStatus: Sendable {
      var state: SourceState
      var lastSuccessAt: Date?        // per-source, not global
  }

  enum SourceState: Sendable { case idle, live, degraded(String), offline(String) }
  ```

  `idle` matters: with an empty watchlist, Binance is idle rather than offline, and the UI must not show an error for it.

  `lastSuccessAt` is **per source** (Codex minor 10). Revision 2 had one global `lastSuccessfulUpdate`, which is ambiguous when Binance is live but CoinGecko is degraded — the timestamp would keep advancing while sparklines silently went stale. Any aggregate shown in the footer is derived from the three.

- Sparkline timer: 600s, fires immediately on launch rather than waiting out the first interval, cancelled and restarted on watchlist change, and **not scheduled at all when the watchlist is empty**.
- Coinbase poller: 60s, only for items resolved to Coinbase (or fell back to it); not scheduled when that set is empty.
- Staleness timer: 15s, recomputes `staleIDs` (§4).
- Feeds every accepted tick to `AlertEngine` (§5.10).

**Timers are `Task` loops, not `Foundation.Timer`** (Codex M-new-5). A `Timer` closure captured by a `@MainActor` object produces sendability diagnostics under strict concurrency; a main-actor task loop avoids them and is cancellable by construction:

```swift
private func startSparklineLoop() {
    sparklineTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
            await self?.refreshSparklines()
            try? await self?.scheduler.sleep(for: .seconds(600))
        }
    }
}
```

**Schedulers and clients are injected, not constructed inline** (Codex minor 12). "No timers scheduled when the watchlist is empty" is an internal claim that UI-level testing cannot observe. `PriceCoordinator` takes its scheduler and clients as dependencies and exposes `activeTaskCount` / `scheduledLoops` for tests, so §8 tests 6–7 can assert zero active network work rather than merely observing that the screen looks idle.

### 5.7.1 Swift 6 Strict Concurrency Requirements (Codex M-new-5)

Codex flagged that the measured single-file probe does not establish that the full app compiles under strict checking, and named the pressure points. Requirements, not suggestions:

| Item | Requirement |
|------|-------------|
| `TickerUpdate` and every stream element | Explicitly `Sendable`; no implicit conformance relied upon |
| Every DTO and callback payload | Explicitly `Sendable` |
| `URLSessionWebSocketTask` receive/ping callbacks | Cross into the actor via `await`, never mutate actor state from the callback thread |
| `AsyncStream` continuation | Concretely typed, owned by the client actor, isolation stated; termination cancels internal tasks |
| Periodic work | `Task { @MainActor in ... }` loops, not `Foundation.Timer` |
| `UNUserNotificationCenter` completion handlers | Hop to the actor before mutating state; nonisolated callbacks must not touch `@MainActor` properties directly |
| `AlertEngine` → `WatchlistStore` | Explicit same-actor API (both `@MainActor`), so persistence calls need no cross-actor hop |
| `Task.detached` | Prohibited across actor boundaries; child tasks inherit isolation |
| **`NSWorkspace` sleep/wake observers** | Must capture only `Sendable` data and hop explicitly: `Task { await binanceClient.handleSleep() }`. **Never** call an actor-isolated socket method directly from the observer closure (Codex major 6) |
| **Any other `NotificationCenter` observer** (notification-authorization changes, app lifecycle) | Same rule — capture `Sendable` values only, hop before touching isolated state |
| **Subscription ack completions** | Same generation check and actor isolation as receive and ping callbacks (§5.2.1); they are not a separate, looser path |
| **`PersistenceWorker`** | Exclusively owns the file URL and handle. `WatchlistStore` must not share or duplicate that state — it only passes immutable complete `AppSnapshot` values (§5.1) |
| **`AlertHistory` updates from notification completions** | Only via an explicit `@MainActor` method; a nonisolated completion never mutates history directly (§5.11) |
| **Injected scheduler protocol** | Declared `Sendable`, with explicit isolation on `sleep(for:)`; a scheduler captured by a main-actor task loop must not require a nonisolated hop |
| **`URLSessionWebSocketTask`** | Owned by the Binance actor; never captured into a `Sendable` closure in a way that lets another isolation domain call it |
| Build | `-swift-version 6` **plus** `-warnings-as-errors` over the full source tree (§8 test 1) |

**Hopping is not sufficient — the payload itself must be `Sendable`** (Codex round-4 major 8). Revision 3.1's table said callbacks must hop to an actor, but strict concurrency also checks *what crosses* the boundary. Framework callbacks deliver values that are not `Sendable` in the form given, so `Task { await actor.handle(value) }` still diagnoses. Convert **at the callback boundary**, before the hop:

| Callback value | Convert to |
|----------------|-----------|
| `Error` | A `Sendable` struct carrying code + message — never the error object |
| `URLSessionWebSocketTask.Message` | `String` or `Data` extracted at the boundary |
| `Notification` | Nothing — never captured. Extract the needed `Sendable` fields, or pass no payload at all |
| `HTTPURLResponse` | Status code and the specific headers needed, as value types |
| `UNNotificationRequest` / response | The identifier and status only |

Only `Sendable` structs are passed into actor methods.

A requirements table is not a compile proof. §8 test 1 remains the gate, and a dedicated fixture exercising observer callbacks and payload conversion under Swift 6 is part of it.

### 5.8 Views

**MenuBarLabel** — `"\(symbol) \(formattedPrice)"` for the primary item. `NumberFormatter` with grouping separators and adaptive fraction digits: 2 for values ≥ 1, 6 below 1, so `DOGE 0.104235` is not truncated to `0.10`. Shows `"BitPrice"` when the watchlist is empty or no quote has arrived. Never includes the change percent — menu bar width is scarce.

**WatchlistPanel** — `.menuBarExtraStyle(.window)` is mandatory; the default `.menu` style cannot host a scroll view or custom rows. Width 380, max height 520, `ScrollView` inside. Header: gear, title, plus. Footer surfaces `SourceHealth` only when something is not `.live`/`.idle`.

**EmptyStateView** (new, F12) — shown when the watchlist is empty: a short line explaining no coins are tracked, and a button opening `SearchSheet`. This is a first-run screen, not an error.

**WatchRow** — `HStack`: symbol (`.headline`) + `/quoteAsset` (`.caption`, secondary) | `SparklineView` (60×24) | right-aligned price + change. Green up, red down, secondary at zero; `PriceChange.unavailable` renders `—`. The ▲/▼ glyph is retained so color is never the sole carrier of meaning (red-green color blindness). Stale rows (§4) dim, so a frozen price is never mistaken for a live one.

Glyphs, each with a distinct meaning:

| Glyph | Meaning |
|-------|---------|
| Bell | An alert is configured and enabled |
| Warning | Stale mapping needing re-resolution (§2.5), **or** a Coinbase-served quote whose 60s polling is coarser than a push stream (§2.3) |
| Question mark | `.tickerMatchOnly` provenance (§2.4) — identity was not verified beyond the ticker. Tapping shows venue and product id |

**SparklineView** — `Canvas`/`Path` over the point array. Normalize y over `[min, max]`; when `max == min`, draw a centered horizontal line instead of dividing by zero. Stroke 1.5pt in the row's change color. No axes, no labels, no interaction — see §2's cross-venue note.

**SearchSheet** — text field, 300 ms debounce, results with rank and name. **Out-of-order results must not clobber newer ones** (Codex minor): each query carries a generation id, in-flight requests are cancelled on new input, and a response whose generation is not current is discarded. Selecting a result runs §2.4 resolution, which may open `DisambiguationSheet`. Duplicate `coinGeckoID` is refused inline, not silently added twice.

**DisambiguationSheet** (§2.4 step 4) — lists candidate markets with venue, product id, and quote asset. No default selection; the user must pick. Shown **even for a single candidate** unless identity was independently verified, and states plainly that matching was by ticker symbol.

**AlertSheet** (F13) — direction, threshold, cooldown, hysteresis, enable toggle, with the validation in §4.1 enforced inline. Warns when the threshold is **already breached** at creation, since the alert would fire on the next tick. For Coinbase-served items, states that evaluation happens on a 60s poll and brief breaches can be missed. When notification authorization is denied, says so and points at System Settings — while noting alerts still record in-app (§5.11).

**AlertHistoryView** (new, §5.11) — reverse-chronological fired alerts with symbol, direction, threshold, actual price, and time. Reachable from the panel; opening it clears the unread badge.

**MenuBarLabel badge** — a dot when unread alert records exist, so a fired alert is visible even if the OS notification never appeared.

### 5.9 NotificationService (new)

`@MainActor final class NotificationService`, wrapping `UNUserNotificationCenter`.

- Requests `.alert` + `.sound` authorization on the first alert creation, not at launch — asking before the user has expressed intent gets denied.
- Handles `UNAuthorizationStatus.denied` by surfacing it in `AlertSheet` with a pointer to System Settings. Alerts remain **fully functional** — they still fire, still record, and still badge (§5.11); only the OS banner is lost.
- Completion handlers are nonisolated. They must hop to the actor before touching state (§5.7.1) — never mutate `@MainActor` properties from the callback directly.
- **A valid bundle identifier is required.** Notifications are dropped for a bare executable. The app must be launched as a bundle (`open build/BitPrice.app`); running `./BitPrice.app/Contents/MacOS/BitPrice` directly causes silent notification failure. §8 test 21 covers this explicitly.
- No `Info.plist` usage-description key is needed for local notifications.
- Notification body: symbol, direction, threshold, and the actual price at breach.

### 5.10 AlertEngine (new)

`@MainActor final class AlertEngine`. Pure decision logic plus persistence; owns no timers.

**Terminology** (Codex nit 14): this is a **level-triggered threshold breach**, not an edge-triggered crossing. There is no previous-price comparison — the alert fires on the first eligible tick where the price sits beyond the threshold. "Crossing" is avoided throughout because it implies edge detection the algorithm does not perform. The hysteresis latch is what supplies edge-like behavior.

Evaluated on every accepted tick, with all arithmetic in `Decimal`:

```
guard alert.isEnabled, alert.isValid else { return }

let band = alert.threshold * alert.hysteresisPercent / 100   // all Decimal

if !alert.isArmed {
    // re-arm only after leaving the hysteresis band
    let leftBand = switch alert.direction {
    case .above: price < alert.threshold - band
    case .below: price > alert.threshold + band
    }
    if leftBand {
        alert.isArmed = true
        enqueueSnapshot()                   // re-arm is ALSO a durable transition
    }
    return                                  // never fire on the re-arming tick
}

switch alert.direction {                    // breached? (strict inequality)
case .above: guard price > alert.threshold else { return }
case .below: guard price < alert.threshold else { return }
}

if let last = alert.lastFiredAt,
   now.timeIntervalSince(last) < alert.cooldown {
    return                                  // cooldown: suppress, STAY ARMED
}

// ONE transaction on the main actor: history AND latch mutate together,
// then a single complete snapshot, and only then the notification.
appendRecord(alert, price)                  // §5.11 in-app history — always
alert.isArmed = false                       // latch BEFORE the snapshot
alert.lastFiredAt = now
enqueueSnapshot()                           // one AppSnapshot carrying both (§5.1)

notify(alert, price)                        // best effort, AFTER the snapshot
// completion may update only the record's NotificationStatus — never the latch
```

**Ordering is a correctness requirement, not a style choice** (Codex round-4 blocker). Revision 3.1 called `notify` before mutating the latch and persisted afterward, so a crash in between left durable evidence that the alert fired (the history record) alongside durable state saying it had not (`isArmed == true`, `lastFiredAt == nil`) — and the next quote fired the same alert again. History and latch must land in the **same** snapshot, enqueued before the notification is attempted.

**Every latch transition is persisted, in both directions** (Codex round-4 major 7). Revision 3.1 persisted only on fire. If an alert re-armed after leaving the band and the app crashed before the next breach, the stored state still said `isArmed = false` — so on relaunch the alert stayed disarmed and **missed the next legitimate breach**, waiting for the price to exit the band a second time. The latch is a durable state machine; arming is as much a transition as firing.

Five details that are easy to get wrong:

- A cooldown-suppressed tick **does not disarm**. Disarming there would let the alert re-arm and re-fire as soon as the price wobbled, defeating the latch.
- The re-arming tick never fires, even if it is also beyond the threshold. Firing on re-arm reintroduces the jitter spam the latch exists to prevent.
- **Comparisons are strict** (`>`, `<`). A price exactly equal to the threshold does not breach it, and a price exactly at the band edge does not re-arm. Chosen for determinism rather than correctness — either convention works, but it must be one of them, and §8 tests it explicitly.
- **The in-app record is written before the OS notification is attempted**, and unconditionally. If the notification fails, the user still has the record (§5.11).

Codex reviewed the revision-2 ordering and confirmed the latch logic is correct; the changes here are the `Decimal` arithmetic, the validity guard, the equality convention, and the mandatory in-app record.

Fallback-sourced items (§2.3) are evaluated on their 60s poll, so a brief breach between polls is missed entirely. `AlertSheet` states this for those items rather than implying push-grade precision.

**Multiple alerts on one tick:** each watchlist item holds at most one alert, but a single ticker message can satisfy several items when the same market backs more than one row. Each alert is evaluated and persisted independently; one failing notification must not prevent the others from recording.

### 5.11 AlertHistory (new — mandatory per Codex M-new-7)

`@MainActor final class AlertHistory: ObservableObject`

OS notification delivery is not under the app's control: authorization may be denied, Focus modes suppress banners, Notification Center settings vary, and §0.1 could not verify delivery on this machine at all. Revision 2 mentioned an in-app fallback in prose only. It is now a requirement.

- **Every fired alert appends a record, and that record is enqueued for persistence *before* `UNUserNotificationCenter` is called** (Codex major 3). Revision 3's first draft appended in memory and persisted only after the notification attempt, so a crash in between could lose a record the spec calls mandatory. Ordering is now: append → enqueue complete `AppSnapshot` (§5.1) → attempt notification.
- Record:

  ```swift
  struct AlertRecord: Codable, Identifiable, Sendable {
      let id: UUID
      let itemID: UUID
      let symbol: String
      let direction: PriceAlert.Direction
      let threshold: Decimal
      let priceAtBreach: Decimal
      let firedAt: Date
      var notification: NotificationStatus
      let source: Exchange          // which venue produced the breach price
  }

  enum NotificationStatus: String, Codable, Sendable {
      case pending      // not yet attempted, or attempt in flight
      case scheduled    // UNUserNotificationCenter accepted the request
      case failed       // center.add returned an error
  }
  ```

  The field is `scheduled`, not `delivered` or `accepted` (Codex minor 2): `center.add` succeeding means the request was **accepted for scheduling**, not that a banner was shown — Focus modes and Notification Center settings can still suppress presentation. Naming it `delivered` would overclaim.

- The completion handler may update **only** `notification`, via an explicit `@MainActor` method (§5.7.1). It must never re-fire the alert or touch latch state.
- Surfaced two ways: a badge/dot on the menu bar item while unread records exist, and a history section in the panel. Opening the panel clears unread state.
- Capped at 100 records, oldest evicted. Part of `AppSnapshot`, so history, unread count, and alert latch state are always written together and can never diverge.
- **A notification failure is not an alert failure.** The record is already persisted and the badge already shows; the error is recorded as `.failed` and logged, not surfaced as a modal.

This also means alerts remain fully functional with notifications denied — degraded, but not broken.

---

## 6. Build & Packaging

### 6.1 Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>BitPrice</string>
    <key>CFBundleDisplayName</key>       <string>BitPrice</string>
    <key>CFBundleIdentifier</key>        <string>com.wayne.bitprice</string>
    <key>CFBundleExecutable</key>        <string>BitPrice</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
```

`LSUIElement` makes this menu-bar-only with no Dock icon. `CFBundleIdentifier` is also what makes notifications deliverable (§5.9). `LSMinimumSystemVersion` is 14.0 per §0.

### 6.2 scripts/build-app.sh — SwiftPM path (currently non-functional, see §0)

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/BitPrice.app"

swift build -c "$CONFIG" -Xswiftc -swift-version -Xswiftc 6
BIN="$(swift build -c "$CONFIG" --show-bin-path)/BitPrice"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BitPrice"
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "built: $APP"
```

Revision 1 wrote `"$APP/Contents/Contents/Info.plist"` — a duplicated path component that would have produced a bundle macOS refuses to launch. Also dropped `--deep`, which is unnecessary here (no nested frameworks) and deprecated for signing.

Ad-hoc signing (`--sign -`) suffices for local use; networking and notifications both work. **It is not sufficient for distribution or notarization** — that needs a Developer ID and a separate `notarytool` step.

### 6.3 scripts/build-app-direct.sh — swiftc-only path (**primary**, verified working)

The SwiftPM defect in §0 is unresolved, so this is the build route to use. A single-file probe with this invocation compiled Foundation + UserNotifications + AppKit under Swift 6 mode and produced a runnable binary — but per §0 that is **not** proof the full app compiles. `-warnings-as-errors` is included deliberately: strict concurrency diagnostics arrive as warnings in some configurations, and a warning here is a design defect (§5.7.1). Skips SwiftPM entirely:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/BitPrice.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Null-delimited so paths with spaces cannot word-split (Codex minor 1).
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done \
  < <(find Sources/BitPrice -name '*.swift' -print0)

swiftc -swift-version 6 -warnings-as-errors -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  "${SOURCES[@]}" \
  -o "$APP/Contents/MacOS/BitPrice"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built: $APP"
```

### 6.4 scripts/verify-app.sh (Codex build recommendation)

Bundle correctness is checkable before launching:

```bash
#!/bin/bash
set -euo pipefail
APP="${1:-build/BitPrice.app}"

plutil -lint "$APP/Contents/Info.plist"
codesign --verify --verbose=4 "$APP"
otool -L "$APP/Contents/MacOS/BitPrice" | head -20
lipo -archs "$APP/Contents/MacOS/BitPrice"
otool -l "$APP/Contents/MacOS/BitPrice" | grep -A3 LC_BUILD_VERSION | head -8
plutil -extract LSUIElement raw "$APP/Contents/Info.plist"
```

Checks, in order: plist is well-formed, signature verifies, no unexpected dynamic links, architecture is as intended, minimum-OS matches §0, and `LSUIElement` is actually set.

**Duplicate-instance policy** (Codex build recommendation): launching a second copy would produce two menu bar items writing the same JSON. On launch the app checks for another running instance with the same bundle id via `NSRunningApplication.runningApplications(withBundleIdentifier:)` and exits immediately if one exists.

Run with `open build/BitPrice.app` — required for notifications (§5.9).

---

## 7. Known Risks

| Risk | Mitigation |
|------|-----------|
| ~~Toolchain cannot compile `import Foundation`~~ | **Resolved** 2026-08-03 — stale modulemap disabled (§0) |
| **SwiftPM manifest link failure — still present** | §6.3 swiftc-only path is verified working and is the primary build route; §6.2 needs a CLT reinstall |
| **Notification delivery unverified** | §0.1 — could not be tested (no GUI session). §8 test 20a must be run by hand. Fallback: in-app alert indicator, no entitlement needed |
| Binance geo-blocks some regions (451/403) | Detected distinctly at connect. Items **with a resolved Coinbase mapping** fall back to 60s polling; items **without one** show a clear unavailable state. Coverage is not universal and the UI must not imply otherwise (§2.4) |
| Ticker symbol collision across CoinGecko coins | §2.4 — ticker match is a filter only; auto-accept requires `.verifiedIdentity`, otherwise the user confirms. Rows show `.tickerMatchOnly` provenance |
| Wrong project shown despite a unique ticker match | §2.4 — the residual risk B-new-2 named. Mitigated by never claiming verified identity in the UI, and by naming venue + product id in the row detail so the user can catch it |
| Subscription ack races leaving a stream subscribed forever | §5.2.1 — `desired`/`confirmed` sets plus typed `pending` commands, serialized, re-diff after every ack |
| Wake finds a socket the server no longer has subscriptions on | §5.2.2 — `confirmed` cleared on sleep and on every reconnect; full reconciliation from `desired` |
| Alert persistence blocking the menu bar | §5.1 — snapshot on main actor, encode/write in an actor, revision counter preserves ordering |
| Float error in threshold arithmetic | §4.1 — `hysteresisPercent` is `Decimal`; all alert math in `Decimal` |
| Invalid alert config (negative cooldown, NaN hysteresis) | §4.1 — validated at construction and on decode; bad values disable the alert visibly rather than dropping it |
| Alert burst after migrating alerts that predate `isArmed` | §4.1 — migration defaults `isArmed = false` |
| OS notification suppressed by Focus mode / denied authorization | §5.11 — in-app history and badge are mandatory and unconditional; notifications are an enhancement |
| Coinbase product resolved but never quotes (offline/delisted) | §2.3 — only `status == "online"` accepted; `trading_disabled` / `cancel_only` rejected |
| `open == 0` in Coinbase stats | §2.3 — guarded; yields `.unavailable`, not a division by zero |
| Binance closes the socket at 24h | Proactive reconnect at 23h, anchored to actual socket-open time |
| Half-open socket delivers neither data nor error | 30s application ping, 3 strikes, plus composite health (§5.4) |
| Server ping frames ignored → disconnect | Always answered; app ping is additive, not a substitute (§2.1) |
| Late callbacks from a replaced socket corrupt state | Generation tokens (§5.3) |
| Concurrent sources racing socket state | Single state machine; watchlist edits only mutate the desired set (§5.2) |
| CoinGecko 429 | `Retry-After` honored, else 60s backoff and cycle skipped; 429 treated as authoritative |
| Sparkline array absent, short, or null-bearing | Explicit per-case behavior (§2.2); never a correctness oracle for Binance's 24h % |
| Flat sparkline divides by zero | Explicit `max == min` branch |
| Corrupt watchlist.json bricks launch | Preserved as timestamped `.corrupt.<ISO8601>.json`, seeded with BTC |
| Empty watchlist opens an invalid socket URL | Desired-set-empty → `stopped`; no timers scheduled (§5.2, §5.7) |
| Coinbase fallback lacks 24h change | `PriceChange.unavailable` renders `—`; never fabricated as 0.00% (§2.3) |
| Fallback 60s poll misses a threshold breach | Disclosed in `AlertSheet` and marked on the row |
| Alert spam from threshold jitter | Hysteresis latch **and** cooldown, which solve different halves (§5.10) |
| Alert burst on relaunch | `isArmed`/`lastFiredAt` persisted, flushed immediately on change |
| Notifications silently dropped | Requires bundle launch via `open`; authorization denial surfaced in UI (§5.9) |
| Delisted pair yields a frozen price | Listing cache refresh + per-row re-resolution prompt (§2.5) |
| Two instances writing the same file | Duplicate-instance check on launch (§6.4) |
| Swift 6 strict concurrency rejects the design | Actor-isolated clients, `AsyncStream` boundary, no `Task.detached`, no shared mutable state |
| Ad-hoc signature insufficient for distribution | Documented; Developer ID + notarization needed for sharing |

---

## 8. Verification Plan

Revision 1 had 15 tests. Codex identified 17 uncovered cases; the plan now covers them plus the new alert and empty-state features.

### Preconditions

| # | Test | Expected |
|---|------|----------|
| 0a | `swiftc` a file containing `import Foundation` | Compiles — confirms §0 repair worked |
| 0b | `curl https://api.exchange.coinbase.com/products/BTC-USD/stats` | Returns `open`/`high`/`low`/`last`; confirms §2.3(a) before relying on it |
| 0c | `curl https://api.exchange.coinbase.com/products` | Product listing available for §2.4 resolution |
| **20a** | **Notification delivery — MANUAL ONLY, requires a real desktop GUI session** (§0.1). Build the bundle, `open` it, create an alert, force a breach. **Not a CI failure when skipped** — an automated run without an Aqua session must report "skipped", never "failed" (Codex minor 3) | Banner appears in Notification Center. Highest-priority unverified assumption in the spec. Failure does **not** break alerts — §5.11's in-app history and badge are mandatory and independent |

### Build

| # | Test | Expected |
|---|------|----------|
| 1 | **`scripts/build-app-direct.sh` over the full source tree** — the authoritative build gate (§0, §6.3). Not `swift build`, which cannot run on this machine | Compiles clean with `-swift-version 6 -warnings-as-errors`. This is what actually establishes Swift 6 strict-concurrency compliance; §0's single-file probe does not |
| 2 | `scripts/verify-app.sh` | plist lints, signature verifies, arch and min-OS correct, `LSUIElement` = true |
| 3 | `open build/BitPrice.app` | Menu bar item appears, **no Dock icon** |
| 4 | Launch a second instance | Second exits immediately; one menu bar item remains |

### First run and empty state

| # | Test | Expected |
|---|------|----------|
| 5 | First launch, no existing JSON | Watchlist contains **BTC only** |
| 6 | Delete every row | `EmptyStateView` shows. Asserted on **both** axes (Codex minor 4): scheduler `activeTaskCount == 0` **and** client lifecycle state — socket `stopped`, no in-flight HTTP request, no pending teardown task. Scheduler count alone would not catch an already-running request |
| 7 | Add a coin from the empty state | Socket opens, subscription succeeds, price arrives |
| 8 | Corrupt the JSON by hand, relaunch | Seeds BTC; original preserved as `.corrupt.<timestamp>.json` |
| 9 | Corrupt it twice | Two distinct corrupt files; neither overwritten |

### Live data

| # | Test | Expected |
|---|------|----------|
| 10 | Observe menu bar 60s | Price updates with no interaction |
| 11 | Inspect a row | Symbol, pair, sparkline, price, signed change % all present |
| 12 | Coin priced under $1 (DOGE) | 6 fraction digits, not truncated to 2 |
| 13 | Reorder rows, set a new primary | Menu bar label switches immediately |
| 14 | Add a coin, then remove it | SUBSCRIBE then UNSUBSCRIBE on the **same** socket — no reconnect |
| 15 | Add three coins rapidly | Edits coalesce into one subscribe message; control-traffic budget respected |
| 16 | Watch >250 coins (synthetic) | `ids` chunked; all sparklines populate |

### Resilience

| # | Test | Expected |
|---|------|----------|
| 17 | Disable Wi-Fi 90s | `binance` state offline, quotes dim as stale at the 60s boundary, no crash |
| 18 | Re-enable Wi-Fi | Reconnects within ~30s, prices resume, state returns to live |
| 19 | Sleep 5 min, wake | Stream resumes, prices refresh within 30s |
| 20 | Sleep during an in-flight request | No crash, no duplicate socket after wake |
| 21 | Force-kill the socket server-side (or simulate) | Reconnect fires; backoff does **not** reset until composite health holds 60s |
| 22 | Rapid connect/drop cycles | Backoff grows monotonically to the 30s cap; no tight loop |
| 23 | Simulate a 24h-old connection | Proactive reconnect at 23h; watchlist edits during it are not lost |
| 24 | Watchlist edit concurrent with a reconnect | Desired set reconciled after connect; no lost or duplicated subscription |
| 25 | Inject a late callback from a replaced socket | Dropped by generation check; no state mutation |
| 26 | Server sends a ping frame | Pong sent; connection survives past 10 min idle |
| 27 | CoinGecko returns 429 | `Retry-After` honored or 60s backoff; cycle skipped, not retried immediately |
| 28 | HTTP 200 with malformed JSON | Decode error handled; prior data retained; source marked degraded |
| 29 | HTTP 500 with a JSON error body | Status checked before decode; not reported as a model error |
| 30 | Sparkline array null / 5 points / all-equal | Cached series kept / partial render / flat line — no crash, no divide-by-zero |

### Mapping and fallback

| # | Test | Expected |
|---|------|----------|
| 31 | Search an ambiguous symbol (e.g. `SOL`) | `DisambiguationSheet` appears; no automatic guess |
| 31a | Add a coin with **exactly one** venue candidate but no stronger identity signal | **Still asks the user to confirm** (§2.4 step 4); row records `.tickerMatchOnly` |
| 31b | Inspect a `.tickerMatchOnly` row's detail | Names venue and product id; wording says "matched by ticker", never "verified" |
| 32 | Add a coin Binance does not list | Resolves to Coinbase; price populates; row marked lower-precision |
| 32a | Add a coin listed on **both** venues | Both mappings persisted (§2.4); `activeExchange` is Binance |
| 32b | Simulate a Binance geo-block (451) | Items **with** a Coinbase mapping switch to 60s polling; items **without** show unavailable — not a false claim of coverage |
| 33 | Fallback item's 24h change | Computed from `open`, or `—` if unavailable — **never 0.00%** |
| 33a | Coinbase stats returns `open == 0` or omits `open` | `.unavailable`; no division by zero |
| 33b | Coinbase product with `status != "online"` or `trading_disabled` | Rejected at resolution; not persisted as a mapping |
| 34 | Persisted pair delisted (simulate rejected SUBSCRIBE) | Listing refreshed; row warns and offers re-resolution; no frozen price |
| 35 | Relaunch after adding coins | Mappings reused verbatim; product ids not recomputed |
| 36 | Duplicate add of the same CoinGecko id | Refused with an inline message |

### Subscription reconciliation (added per Codex M-new-1 / M-new-2)

| # | Test | Expected |
|---|------|----------|
| 36a | Remove a coin **before** its SUBSCRIBE ack arrives | Ack updates bookkeeping, immediate re-diff sends UNSUBSCRIBE; the stream does **not** stay subscribed (the exact race Codex identified) |
| 36b | Add and remove the same coin rapidly, repeatedly | Converges to the correct set; no duplicate subscribe, no unsubscribe for an unacknowledged stream |
| 36c | Error ack for a SUBSCRIBE | Command removed from `pending`, stream not added to `confirmed`; retried once before any mapping is blamed (§5.2.1) |
| 36d | Sleep, then wake | `confirmed` was cleared on sleep; wake reconciles the **full** desired set; prices resume |
| 36e | Watchlist edit while `suspended` | Desired set updated; nothing sent until `connected`; reconciled correctly on wake |
| 36f | Reconcile when `desired == confirmed` | Sends nothing (idempotent) |
| 36g | **Drop a SUBSCRIBE ack** (server applied it, ack lost) | 10s timeout fires → **reconnect**, not retry; new generation reconciles from empty `confirmed`; counts toward degraded health (§5.2.1) |
| 36h | Ack arrives after a generation change | Dropped by the generation check; new socket's bookkeeping untouched |
| 36i | Error ack, transient (generic) | Retried once, then escalates to reconnect. Mapping **not** marked for re-resolution — a transport error is not evidence of a bad market |
| 36j | Error ack naming a specific invalid stream, twice | *That* mapping marked for re-resolution (§2.5); others unaffected |
| 36k | Unknown / duplicate `requestID` in an ack | Ignored and logged; no state mutation |
| 36l | Batch command partially rejected | Treated as all-or-nothing; no stream is assumed applied |

### Active source and failback (added per Codex major 4)

| # | Test | Expected |
|---|------|----------|
| 36m | Geo-block, then Binance recovers | Item returns to Binance only after connect **and** subscription ack — not on TCP connect alone |
| 36n | During handover back to Binance | Last Coinbase quote retained until the first Binance tick; row never blanks |
| 36o | Relaunch while degraded | `activeExchange` is runtime state, not persisted — starts at Binance, degrades again only if Binance actually fails |
| 36p | Alert on an item that fails over mid-session | Evaluation follows the active source; `AlertSheet` precision disclosure reflects the current source |

### Search

| # | Test | Expected |
|---|------|----------|
| 37 | Type fast, let responses arrive out of order | Only the newest query's results render |
| 38 | Query with spaces and symbols | Percent-encoded correctly; no malformed URL |

### Alerts

| # | Test | Expected |
|---|------|----------|
| 39 | Set an above-alert, price breaches it | One notification, containing symbol, threshold, actual price |
| 40 | Price oscillates around the threshold for 5 min | **Exactly one** notification — latch holds while inside the hysteresis band |
| 41 | Price exits the band, then breaches again after cooldown | Second notification fires |
| 42 | Price exits the band and breaches again **within** cooldown | Suppressed; alert stays armed (does not disarm on a cooldown skip) |
| 43 | Quit while disarmed, relaunch with price still past threshold | **No notification burst** — persisted `isArmed` respected |
| 44 | Deny notification authorization | `AlertSheet` states it; no silent failure |
| 45 | Run the bare executable instead of the bundle | **Crashes** with `bundleProxyForCurrentProcess is nil` (measured) — must launch via the bundle |
| 46 | Set a threshold already breached at creation | Sheet warns it will fire on the next tick — **and it does**, because new alerts initialize `isArmed = true` (§4.1). This is the blocker Codex found in revision 3's first draft |
| 47 | Alert on a fallback (Coinbase) item | Fires on the 60s poll; sheet discloses reduced precision |
| 48 | Delete an item that has an alert | Alert removed with it; no orphan evaluation |

### Alert boundary cases (added per Codex M-new-8)

Tests 49–58 are **table-driven unit tests over `AlertEngine`** with injected fixed timestamps and `Decimal` prices — deliberately separated from notification-delivery testing, which depends on the environment (§0.1).

| # | Test | Expected |
|---|------|----------|
| 49 | Price exactly equals the threshold | **No breach** — comparisons are strict (§5.10) |
| 50 | Price exactly at the hysteresis band edge | **No re-arm** — strict there too |
| 51 | `hysteresisPercent == 0` | Re-arms as soon as price returns past the threshold; no divide-by-zero, no infinite latch |
| 52 | Cooldown expires while price is still beyond the threshold | Fires again on the next tick — alert was still armed (test that the cooldown skip did not disarm) |
| 53 | Re-arm, then breach again without leaving the band | Does not fire; latch holds |
| 54 | Invalid config: negative cooldown, NaN/negative/≥100 hysteresis, threshold ≤ 0 | Rejected at the sheet; a decoded bad value **disables** the alert and shows it, rather than dropping it |
| 55 | Decode an alert missing `isArmed` / `lastFiredAt` | Migration defaults applied (`isArmed = false`); **no notification burst** even if price is already beyond the threshold |
| 56 | Persistence write fails (unwritable directory) | Alert state stays consistent in memory; failure surfaced; no crash |
| 57 | Notification scheduling fails **after** alert state was persisted | In-app record exists and badge shows (§5.11); no duplicate fire on the next tick |
| 58 | Two alerts satisfied by one ticker message | Both evaluated and recorded independently; one failure does not suppress the other |
| 59 | Delete or edit an alert while a notification completion is pending | Pending completion is ignored safely; no write to a removed alert |
| 60 | Out-of-order persistence snapshots (revision N+1 written before N) | Worker discards the stale snapshot; newest state survives (§5.1) |
| 61 | **New alert created while price is already beyond the threshold** | **Fires on the next tick** — `isArmed = true` for new alerts (§4.1). Guards the blocker Codex found: `isArmed = false` here would silently never fire |
| 62 | Edit an existing alert's threshold or direction | Latch resets (`isArmed = true`, `lastFiredAt = nil`); an old cooldown does not suppress the first breach of the new threshold |
| 63 | Edit only `cooldown` | Latch state **preserved** — cooldown does not change what counts as a breach |
| 64 | Create an alert before any quote has arrived | Evaluation deferred until the first accepted quote; never fires against an absent price |
| 65 | Extreme threshold magnitudes (very large / very small) | Band computation checked finite; on overflow the alert is disabled and flagged, not evaluated against a garbage band (§4.1) |
| 66 | Crash between appending a history record and the OS notification call | Record survives — it was enqueued for persistence **before** the notification attempt (§5.11) |
| 67 | Notification completion arrives after the alert was deleted | Ignored safely; no write to a removed alert, no re-fire |
| 68 | Inspect a record's `notification` field | `.pending` → `.scheduled` / `.failed`. Named `scheduled`, not `delivered` — acceptance is not presentation (§5.11) |
| 69 | History and watchlist written concurrently | One `AppSnapshot` carries both; they cannot diverge (§5.1) |

### Round-4 fixes

| # | Test | Expected |
|---|------|----------|
| 70 | **Crash between the history append and the notification call** | On relaunch the record exists **and** `isArmed == false` with `lastFiredAt` set — **no duplicate fire** on the next quote. Guards the round-4 blocker: they are one snapshot, one transaction (§5.10) |
| 71 | **Re-arm, then quit before any further breach, then relaunch** | Alert is still **armed**; the next legitimate breach fires. Guards major 7 — a memory-only re-arm would leave it disarmed and miss the breach |
| 72 | Ack arrives in the same instant the 10s timeout fires | Exactly one takes effect. The ack removes the `pending` entry, so the timeout fails its identity check and no-ops (§5.2.1) |
| 73 | Timeout fires while a reconnect is already in progress | No second reconnect; only health state is recorded. `reconnect()` is idempotent |
| 74 | Timeout fires after a new generation was allocated | No-op via the generation check; new socket's `pending`/`confirmed` untouched |
| 75 | Persistent generic subscription error | Circuit breaker trips after 5 consecutive failures → terminal `.offline(reason)`, slow 5-minute retry, reason shown in UI. **No unbounded reconnect loop** (major 6) |
| 76 | Circuit breaker open, then network reachability returns | Retries immediately on the external change rather than waiting out the slow schedule |
| 77 | Successful ack after some failures | Consecutive-failure counter resets to zero |
| 78 | **Coinbase-only item, first launch and after relaunch** | Starts on **Coinbase**, not Binance; quotes populate. Guards major 4 — the old "absent means Binance" rule would have left it silent |
| 79 | Binance acks, then dies 2s later, repeatedly | Item does **not** flap. Failback needs a first valid tick plus a 60s dwell; a failed source is held out 5 min, escalating to 30 (major 5) |
| 80 | Coinbase poller during a failback attempt | Keeps polling until the dwell completes; stops only after, never at ack time. Row never blanks |
| 81 | Sleep or reconnect with commands outstanding | Every `pending` entry cancelled and discarded; nothing inherited by the new generation (major 2) |
| 82 | Swift 6 fixture: observer callbacks and payload conversion | Compiles clean with `-warnings-as-errors`; no `Error`, `Notification`, or raw WebSocket message crosses an actor boundary (major 8) |

### Specification hygiene

| # | Test | Expected |
|---|------|----------|
| 83 | Grep the spec for retired identifiers (`inFlight`, `WatchlistSnapshot`, `activeExchange` as a `WatchItem` field, "crossing" in alert contexts) | No hits. Round 4 found stale `inFlight` in three places after revision 3.1 claimed it was removed — a renamed concept that survives in prose leads an implementer to clear the wrong variable |

---

## 9. Open Questions

1. Should the CoinGecko Demo API key be user-configurable in a settings pane, or read from an environment variable / config file at launch?
2. Should non-USDT quote pairs be supported (the reference app shows `ETH/BTC`)? `MarketMapping` already carries `quoteAsset`, so this is a UI question, not a model change.
3. Is a launch-at-login toggle (`SMAppService`) wanted for v1?
4. Should alerts support a percentage-move trigger ("notify on ±5% in 24h") in addition to absolute thresholds?
5. When the primary coin is deleted, should the next item auto-promote, or should the menu bar go blank until the user chooses?
6. ~~Is a contract-address identity check worth implementing for v1?~~ **Decided (round 3): no.** v1 requires explicit user confirmation for every mapping; `.verifiedIdentity` remains a forward-compatible enum case with no code path producing it (§2.4 step 2). Reinstating auto-accept requires specifying the venue metadata endpoints and comparison rules first.
7. ~~Should more than one alert per item be allowed?~~ **Deferred (round 3).** v1 is one `PriceAlert?` per item; the limitation is stated in the UI. Migrating to `[PriceAlert]` happens only if the product requirement is accepted — Codex agreed this is safe to defer.
