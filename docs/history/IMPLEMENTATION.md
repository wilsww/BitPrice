# BitPrice — Simplified Implementation Specification

## 1. Functional requirements

### 1.1 Product scope

BitPrice is a personal macOS menu bar application maintained by one developer. It has no account system, server component, telemetry, or distribution requirement. The deployment target is macOS 14.0.

The menu bar label shows exactly one primary watch item as `SYMBOL price`. If the watchlist is empty, or the primary item has no quote, it shows `BitPrice`. Prices use grouping separators, two decimals at or above 1, and up to six below 1.

Clicking the label opens a `.menuBarExtraStyle(.window)` panel. Each watchlist row shows:

- symbol and the quote asset **of the venue currently supplying the price**;
- a shape-only 24-hour sparkline;
- latest price;
- 24-hour change percentage, or `—` when unavailable.

Dual-mapped items quote USDT on Binance and USD on Coinbase, so the displayed quote asset is derived
from `Quote.source` and that venue's persisted mapping — never stored on the row and never assumed.
The label changes when the source changes, in both directions. With no quote at all, show the Binance
mapping's quote asset when one exists, otherwise the Coinbase mapping's, and render the price and
change as unavailable.

The user can search for a coin, add it, delete it, reorder the list, and set the primary item. Duplicate CoinGecko IDs cannot be added. The primary item is stored by UUID, not inferred from row order. Deleting the primary chooses the first remaining item; deleting the last item leaves no primary.

The first launch seeds BTC only. A valid persisted empty watchlist remains empty on later launches. No socket or periodic network task runs while the watchlist is empty.

The watchlist and alert state persist across launches. The application has no Dock icon because `LSUIElement` is true. Only one running instance is supported.

### 1.2 Search and market confirmation

Search queries CoinGecko by name or symbol after a 300 ms debounce. An empty query cancels the request and clears results. Starting a new query cancels the prior task; late results are discarded by query UUID.

Selecting a CoinGecko result confirms only the CoinGecko project. It does not confirm that a Binance or Coinbase market with the same ticker is that project. Ticker symbols are not unique, and originals, wrapped assets, bridged assets, and unrelated coins can share one.

The add flow therefore shows venue candidates before saving the item. For each venue, the user explicitly selects a product ID or selects “No market.” The sheet says: “Candidates matched by ticker; verify the market.” This confirmation is required even if a venue has exactly one candidate. At least one venue must be selected.

This is part of selecting the search result, not a later settings ceremony. Selecting a search result alone is insufficient: that click identifies the CoinGecko result but supplies no evidence about the venue asset. The remaining risk is plain user error: the user can still confirm the wrong market. Every row detail exposes the persisted venue and product IDs so that error is inspectable.

The built-in BTC seed is the sole curated exception: `bitcoin`, `BTCUSDT`, and `BTC-USD` are shipped as explicit, inspectable identifiers.

### 1.3 Alerts

Each watch item may have one optional alert. An alert has direction (`above` or `below`), threshold, cooldown, hysteresis, and enabled state. Threshold and all alert comparisons use `Decimal`.

An above alert breaches only when `price > threshold`. A below alert breaches only when `price < threshold`. Equality is not a breach.

After firing, the alert disarms. It re-arms only after price leaves the hysteresis band:

- above: `price < threshold × (1 - hysteresisPercent / 100)`;
- below: `price > threshold × (1 + hysteresisPercent / 100)`.

Equality at a band edge does not re-arm. The re-arming tick never fires. A cooldown-suppressed breach leaves the alert armed.

New or materially edited alerts start armed with no last-fire date. Material edits are direction, threshold, hysteresis, or enabling a disabled alert. Changing only cooldown preserves latch state. Migrated alerts missing `isArmed` start disarmed to prevent a launch burst.

The app asks for notification permission when the first alert is enabled, not at launch. Notification delivery is best effort and is not claimed as verified on the measured machine. Coinbase polling can miss a brief breach between polls; the alert editor states this.

## 2. Data architecture and API contracts

### 2.1 Source responsibilities

The display is assembled by field, not by a single authoritative venue.

| Data | Source | Cadence |
|---|---|---|
| Live price and 24h change | Binance `@ticker` WebSocket | push |
| Fallback price and 24h change | Coinbase product stats | 60 s while needed |
| Sparkline | CoinGecko markets batch | immediately, then every 10 min |
| Search metadata | CoinGecko search | user initiated |
| Venue candidates | Binance exchange info and Coinbase products | add flow |

CoinGecko's free tier is limited to 10,000 calls per month. One batch sparkline call every 10 minutes is about 4,320 calls per 30 days. Search calls use the remaining budget and are user initiated. CoinGecko is not polled for real-time prices.

Sparkline values and displayed quotes may come from different venues and differ slightly. The sparkline has no numeric axis and is never used to validate the displayed change percentage.
Binance `/api/v3/klines` is not used because it has no multi-symbol batch; `symbols=` returns `-1102`.

### 2.2 Binance contracts

For all mapped Binance items, build one combined-stream URL:

```text
wss://stream.binance.com:9443/stream?streams=btcusdt@ticker/ethusdt@ticker
```

Stream names are lowercase and sorted for deterministic tests. An empty Binance mapping set stops the task.

Reconnection is driven by the **Binance product-ID set**, not by watchlist edits in general.
Compare the old and new sets on every watchlist change and rebuild the URL only when that set differs.
Reordering rows, changing the primary item, editing an alert, and adding or removing a Coinbase-only
item all leave the set unchanged and must not interrupt the socket.

Fields consumed from each combined-stream message are:

```json
{
  "stream": "btcusdt@ticker",
  "data": { "s": "BTCUSDT", "c": "62794.13", "P": "-0.659", "E": 1754000000000 }
}
```

`s` is the persisted product ID, `c` is price, `P` is 24-hour change percent, and `E` is venue event time in milliseconds. Reject unknown product IDs, invalid decimal strings, null values, and non-finite percentages. Map product ID back to an item only through persisted mappings.

A venue product ID maps to **at most one** watch item. The add flow rejects confirming a venue
product ID already mapped by another item, for the same reason duplicate CoinGecko IDs are rejected:
two rows quoting one market are the same row displayed twice. Enforcing uniqueness at entry keeps
tick delivery a lookup rather than a fan-out, and keeps the per-product staleness key of §4.1.1
unambiguous. A decoded file violating this enters read-only recovery (§4.2) rather than being
silently fanned out.

Candidate discovery uses:

```text
GET https://api.binance.com/api/v3/exchangeInfo
```

Keep candidates whose `baseAsset` equals the selected CoinGecko symbol case-insensitively,
whose `quoteAsset` is `USDT`, and whose `status` is `TRADING`.
Ticker equality makes a candidate, not an identity assertion.

The socket client uses capped exponential retry delays of 1, 2, 4, 8, 16, then 30 seconds.
Connection replacement is idempotent: each supersede cancels at most one current task and creates at
most one replacement (§4.3.3).

The attempt counter that indexes that delay sequence **persists across connect and close cycles**.
It resets to zero only after the current session has accepted a valid ticker update **for every
product it subscribed to** — never on socket open, and never on a health-triggered reconnect.
Resetting on connection would let a server that accepts and immediately closes the socket produce
continuous one-second reconnect churn that never reaches the 30-second cap, contradicting §7's claim
that attempts continue every 30 seconds. Requiring the full product set is what stops one live
product in a combined stream from resetting the counter on behalf of a permanently silent neighbor;
§4.3.5 gives the full rule.

Each connection carries a **client-local epoch**: a UUID minted when the connection task starts.
It is connection identity **internal to the actor**. It is not stamped on events, not returned to
callers, and not compared by `AppModel`. Superseded connections are excluded by the actor-side
identity check plus the ordered `.superseded` barrier described in §4.3.3.

No component outside `BinanceStreamClient` mints, reads, or propagates an epoch, and there is no
application-wide generation number.

### 2.2.1 Liveness and half-open detection

`URLSessionWebSocketTask` handles WebSocket control frames **below** the `.string`/`.data` message
boundary. The framework answers server-originated Ping frames with Pong automatically. Application
code must not attempt to read, decode, or reply to control frames, and must not add an
application-level ping loop: Binance counts all control traffic against its 5 messages per second
limit, and manual pings would duplicate work the framework already performs correctly.

Framework Pong keeps the transport honest but does not detect every half-open path. Detection of a
silently dead connection therefore rests on the staleness rule in §2.5 plus the reconnect action below.

While the machine is awake, worst-case detection latency is the 60-second staleness threshold plus
one 15-second stale-check interval: **just over 60 seconds and under 75 seconds**, not 60 seconds.

No proactive 23-hour reconnect is scheduled. If Binance closes its connection at 24 hours, normal retry causes one brief interruption.

### 2.3 Coinbase contracts

Candidate discovery uses:

```text
GET https://api.exchange.coinbase.com/products
```

Keep candidates whose `base_currency` matches the CoinGecko symbol,
whose `quote_currency` is `USD`, whose `status` is `online`, and which are tradable.
Persist the selected `id` verbatim, for example `BTC-USD`.

Fallback polling uses:

```text
GET https://api.exchange.coinbase.com/products/{percent-encoded-product-id}/stats
```

Consume decimal-string fields `last` and `open`.
Price is `last`.
When `open > 0`, change is `(last - open) / open × 100`.
When `open` is missing, invalid, or not greater than zero, change is unavailable.
The row renders `—`; it must never fabricate `0.00%`.

The `/v2/prices/{pair}/spot` endpoint is not used for row data because it has no 24-hour change.

An item needs Coinbase polling when:

```swift
needsCoinbase = coinbaseMapped && (binanceUnmapped || binanceSessionUnhealthy || binanceQuoteStale)
```

`binanceUnmapped` is essential and is not merely a failure case. §1.2 permits selecting “No market”
for Binance while confirming a Coinbase product; such an item can never experience a Binance failure
or a stale Binance quote, so a fallback keyed only on those two conditions would leave it without
any price source for the lifetime of the app.

A qualifying item is polled immediately on becoming qualified — at launch, on add, or on the
transition to unhealthy — and every 60 seconds while it remains qualified.

An item without a Coinbase mapping remains stale/unavailable and says “No fallback market.”
Keep the last Binance quote visible but dimmed until a Coinbase response succeeds.
After the first valid Binance tick following reconnection, switch that item back immediately.
No failback dwell or source holdout is implemented; source flapping is an accepted risk.

### 2.4 CoinGecko contracts

Search uses:

```text
GET https://api.coingecko.com/api/v3/search?query={percent-encoded-query}
```

Consume `coins[].id`, `name`, `symbol`, `market_cap_rank`, and `thumb`.
Build queries with `URLComponents`.

Sparkline refresh uses one request containing all watchlist CoinGecko IDs:

```text
GET https://api.coingecko.com/api/v3/coins/markets
    ?vs_currency=usd&ids=bitcoin,ethereum&sparkline=true&price_change_percentage=24h
```

Consume `id` and `sparkline_in_7d.price` only.
Measured responses contained 168 points, but the count and spacing are not contractual.
Drop null and non-finite values, take at most the last 24 valid values, and render fewer if supplied.
If the array is absent, retain the prior series; if none exists, render no chart.
A constant series draws a centered horizontal line.

All REST clients require a 2xx status before decoding and use a 15-second timeout.
A CoinGecko 429 sets the client-wide rate-limit deadline defined in §2.5, suppressing both sparkline
and search until it passes; `Retry-After` supplies the deadline when present, otherwise 60 seconds.
Other failures retain prior data and expose a compact stale/offline message.

### 2.5 Time sources

Wall clock and monotonic clocks are intentionally mixed.

| Use | Clock | Contract |
|---|---|---|
| Alert cooldown | `Date` | persisted across restarts; `age = max(0, now.timeIntervalSince(last))` |
| Periodic sparkline, fallback, and stale-check loops | `SuspendingClock` | sleep pauses the interval; never replay missed ticks |
| Persistence debounce | `SuspendingClock` | requires 500 ms of running-time quiet |
| Search debounce (300 ms) | `SuspendingClock` | typing pause is running-time; sleep must not complete it |
| Socket retry backoff (1/2/4/8/16/30 s) | `SuspendingClock` | a sleeping machine is not retrying; the delay resumes on wake |
| REST request timeout (15 s) | `URLRequest.timeoutInterval` | delegated to URLSession; not measured by app clocks |
| CoinGecko rate-limit deadline | `ContinuousClock` for delta seconds, `Date` for HTTP-date form | see below |
| Quote staleness | `ContinuousClock` | advances during system sleep |
| Socket last-success/health window | `ContinuousClock` | a long sleep makes the old socket unhealthy |

`Retry-After` arrives in one of two forms and both must be handled: an integer count of seconds, or
an HTTP date. Convert a delta to a `ContinuousClock.Instant` deadline so that sleeping consumes it —
the server's cooldown elapses in real time whether or not this machine is awake. Interpret an HTTP
date with `Date`, then convert to the same deadline representation.

The resulting deadline is **client-wide, not per-endpoint**. CoinGecko rate limits the API key, so a
429 from the sparkline batch also suppresses search, and vice versa. A suppressed search reports the
wait to the user rather than silently returning nothing. Absent a usable `Retry-After`, the deadline
is 60 seconds out.

`Quote` stores `Date` only for display and a runtime `ContinuousClock.Instant` for staleness.
Monotonic instants are never encoded.
On launch, restored quotes do not exist; new quotes establish fresh instants.
A Binance quote and its socket session are stale/unhealthy after 60 seconds without a valid tick.
The 15-second stale-check loop publishes that transition and triggers the reconnect described in §4.1.
Because the check is periodic, worst-case awake detection is over 60 and under 75 seconds.

A connection that has never delivered a valid tick has no `lastSuccess` to age. §4.1 therefore records
`connectedInstant` when a session reaches `connected`, and ages the session from whichever of the two
is later. Without this, a socket that opens and then never speaks is never judged unhealthy.

Failback dwell and source holdout are deliberately absent.
If later added, failback dwell must use `SuspendingClock` because sleep is not observed health,
while a real-elapsed source holdout must use `ContinuousClock` so sleep consumes the holdout.
An eight-hour sleep must not count as failback health, but must make quotes and sockets stale.

## 3. Data models

All value types crossing actors explicitly conform to `Sendable`.
Persisted types also conform to `Codable`.

```swift
enum Exchange: String, Codable, Sendable { case binance, coinbase }

struct VenueMapping: Codable, Hashable, Sendable {
    let exchange: Exchange
    let productID: String
    let baseAsset: String
    let quoteAsset: String
    let provenance: Provenance
}

enum Provenance: String, Codable, Sendable {
    case builtInBTC
    case userConfirmedTickerMatch
}

struct WatchItemMapping: Codable, Hashable, Sendable {
    var binance: VenueMapping?
    var coinbase: VenueMapping?
}

struct WatchItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let coinGeckoID: String
    let symbol: String
    let name: String
    var mapping: WatchItemMapping
    var alert: PriceAlert?
}
```

Array order is display order.
The persisted root stores `primaryItemID` separately.
Venue product IDs are never re-derived from symbols on launch, reconnect, or fallback.

```swift
struct PriceAlert: Codable, Hashable, Sendable {
    enum Direction: String, Codable, Sendable { case above, below }
    var direction: Direction
    var threshold: Decimal
    var cooldownSeconds: TimeInterval
    var hysteresisPercent: Decimal
    var isEnabled: Bool
    var isArmed: Bool
    var lastFiredAt: Date?
}

struct PersistedState: Codable, Sendable {
    var schemaVersion: Int
    var items: [WatchItem]
    var primaryItemID: UUID?
}
```

Validation requires threshold greater than zero, cooldown finite and nonnegative,
and hysteresis finite and in `0 ..< 100`.
Invalid decoded alerts remain visible but disabled.

`PriceAlert` must declare a custom `init(from:)`. Synthesized decoding treats a missing
non-optional `isArmed` as a decoding failure, which fails the whole `PersistedState` decode and
routes a merely-older file into the malformed-file recovery path of §4.2. That directly contradicts
§1.3's rule that migrated alerts load disarmed. The decoder reads:

```swift
isArmed = try container.decodeIfPresent(Bool.self, forKey: .isArmed) ?? false
```

**This default applies only when the root `schemaVersion` resolved to `0`.** At the current version
the field is mandatory: a version-`1` file whose alert is missing `isArmed`, or carries it as
`null`, was not written by any build of this app and is malformed — it enters the recovery mode of
§4.2 rather than silently decoding as disarmed. Applying the fallback unconditionally would
contradict the "equal to the current version — decode directly" branch below and would let durable
alert state change without the user being told. The decoder therefore needs the resolved version in
scope, which it takes from the root decoder via `userInfo`.

`PersistedState` must also declare a custom `init(from:)`, for the same reason. `schemaVersion` is a
non-optional `Int`, so synthesized decoding of a pre-versioning file fails on the missing key before
any migration branch can run — the "absent" case below would be unreachable and such a file would be
misclassified as malformed:

```swift
let raw = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
```

Version is read first and dispatched on before the rest of the payload is interpreted:

- `0`, meaning absent or explicitly zero — pre-versioning file; apply the `isArmed` default above and
  every later migration step in ascending order;
- greater than `0` and below the current version — a known older file; apply the migration steps from
  that version upward. Each version needs its own step; an unrecognized older version has no defined
  transform and enters read-only recovery rather than being guessed at;
- equal to the current version — decode directly;
- greater than the current version — a newer build wrote this file. Do not decode and do not
  overwrite; enter the read-only recovery mode of §4.2 and report a version mismatch.

The current version is `1`, so at this point the only live branches are `0`, `1`, and "too new."
The intermediate branch exists to make the contract complete before a second version needs it.

Migration is a pure function from decoded old shape to current shape, and is tested against a
committed fixture of real older JSON rather than a hand-built in-memory value.

```swift
enum PriceChange: Hashable, Sendable {
    case percent(Double)
    case unavailable
}

struct Quote: Hashable, Sendable {
    let price: Decimal
    let change: PriceChange
    let source: Exchange
    let displayDate: Date
    let receivedInstant: ContinuousClock.Instant
}

struct TickerUpdate: Sendable {
    let productID: String
    let price: Decimal
    let changePercent24h: Double
    let eventDate: Date
    let receivedInstant: ContinuousClock.Instant
}

enum FeedEvent: Sendable {
    case ticker(TickerUpdate)
    case connected
    case failed(NetworkFailure)
    /// Ordered in-band barrier. Everything read before it belongs to a superseded
    /// connection; everything after it belongs to the replacement. See §4.3.3.
    case superseded
}

struct NetworkFailure: Error, Sendable {
    let domain: String
    let code: Int
    let message: String
}
```

`FeedEvent` carries **no** epoch. Connection identity stays inside `BinanceStreamClient` and is
never handed across an actor boundary; `AppModel` holds no epoch variable and performs no epoch
comparison. Staleness is decided by stream position relative to the `.superseded` barrier, which the
client emits when it replaces a connection for any reason — external set change, health repair, or
its own autonomous retry. §4.3.1 records why the previous per-event epoch stamp was removed: it made
recovery from autonomous retry unreachable, and its handoff was not atomic against MainActor
suspension.

`AppModel` must not commit a quote-affecting event to published state and then rely on a later check
to undo it. It buffers events consumed since the last barrier, and on `.superseded` discards the
uncommitted ones.

Runtime dictionaries are keyed by watch-item UUID, not symbol.
Runtime source choice, epochs, and monotonic timestamps are not persisted.

## 4. Components and concurrency

### 4.1 AppModel

`@MainActor final class AppModel: ObservableObject` is the sole UI-state owner.
It owns items, primary ID, quotes, sparklines, visible errors, and cancellable loop tasks.
SwiftUI views read it directly and invoke its main-actor methods.

On launch it loads `PersistedState`, obtains the single `events()` stream and starts consuming it,
calls `setProducts` once with the mapped Binance set, performs one sparkline refresh, then starts
periodic loops.

After **every** watchlist change it saves state and calls `setProducts` with the newly derived
Binance product-ID set. `setProducts` is idempotent (§4.3.2), so `AppModel` does not compare sets
itself: reordering rows, changing the primary, editing an alert, and adding or removing a
Coinbase-only item all derive an unchanged set and are absorbed by the client without touching the
socket. Suppression of needless reconnects is a property of one contract, not a caller-side
precondition that each call site must remember to re-check — the caller-side version of this rule
is what shipped a reconnect on the previous URL.

An empty Binance set is passed to `setProducts` like any other and tears the socket down; it is a
valid steady state, not a special case. The periodic sparkline, fallback, and stale-check loops keep
running **whenever the watchlist is nonempty**, gated on the watchlist rather than on the Binance
set, because a list of Coinbase-only items has an empty Binance set and still needs polling (§2.3).
Only a genuinely empty watchlist cancels the periodic loops, and adding the first item restarts them
through the same launch path — an empty list is a state the app returns from, not one it gets stuck
in.

`AppModel` holds no epoch. On `.superseded` it drops the uncommitted events it consumed since the
previous barrier (§4.3.3) and continues reading the same stream.

### 4.1.1 Staleness drives reconnect

Publishing a stale label is not a recovery action. `AppModel` owns the only code path that turns
socket unhealth into a reconnect, and without it a half-open receive task stays the current session
indefinitely while the UI shows stale data or silently runs on Coinbase.

`AppModel` records `connectedInstant` when a session's `.connected` event is accepted, and tracks
`lastValidTick` **per subscribed product ID**, not per session. Each product's age is measured from
the later of its own last tick and `connectedInstant`, so a stream that opens and never speaks still
ages.

Per-product is load-bearing. A single combined stream carries many products, and they fail
independently: a delisted or malfunctioning stream can go permanently silent while its neighbors
tick normally. One session-wide timestamp would be refreshed by the healthy products and the silent
one would never be noticed — quietly falsifying §6 item 4's claim that a bad stream turns into an
ordinary reconnect.

Session age is therefore the age of the **oldest** subscribed product, and the session is unhealthy
when any subscribed product exceeds the threshold.

On each 15-second stale check:

1. if no session is currently connected — it is connecting, or sleeping in backoff — do nothing;
2. if no subscribed product has exceeded 60 seconds, do nothing;
3. otherwise mark the affected products' quotes stale, call `reconnectForHealth()` once, and record
   that the current connection has been health-repaired.

Condition 1 is evaluated from the `.connected`/`.failed`/`.superseded` events `AppModel` has already
read, not by querying the client — `AppModel` asks for repair and observes the result; it does not
inspect the client's internal state.

Reconnect is whole-session because the transport is one combined URL; a single silent product cannot
be resubscribed on its own. If reconnection does not revive it — a delisted symbol, for example —
the product stays stale, §2.3 keeps it on Coinbase when it is mapped, and the retry backoff prevents
the repair attempt from becoming a loop.

A connection is health-repaired at most once: the flag is cleared when the next `.connected` arrives,
so each replacement earns one repair rather than one per stale check. The successor is a new
connection with its own `connectedInstant`.

The backoff that bounds this loop only works at the granularity of §4.3.5. A permanently silent
product does not reset the attempt counter, because reset requires a valid tick from **every**
subscribed product — so repeated repairs of the same silent stream walk 1/2/4/8/16/30 and settle at
the cap. Under the earlier session-wide reset rule a healthy neighbor cleared the counter each time
and this repair path was an unbounded 60-to-75-second interruption loop, not a backoff.
At startup it exits if `NSRunningApplication.runningApplications(withBundleIdentifier:)` finds another BitPrice instance.

Source presentation is intentionally small: `live`, `stale`, or `offline`.
`lastSuccess` per network client is retained internally only to make those labels honest.

### 4.2 PersistenceStore

Persistence is one JSON file at:

```text
~/Library/Application Support/BitPrice/watchlist.json
```

Missing file means first launch and creates the curated BTC state.
A successfully decoded empty array remains empty.

Three conditions put the store into **read-only recovery mode**: malformed JSON, a `schemaVersion`
newer than this build, and an older `schemaVersion` with no defined migration step. The third is the
`0 < version < current` branch of §3 — a valid-looking file the app has no transform for. All three
are one rule here, so the store cannot promise recovery for a case §3 dispatches to it and this
section fails to accept. In that mode the app runs from an in-memory BTC seed, shows a persistent recovery banner, and
**every write path returns an error without touching the file** — structural edits, alert latch
transitions, and the debounced save alike. Refusing writes is what makes the preservation promise
real: without it, the first reorder or alert fire silently overwrites the file the user was told was
being preserved, before they ever see the Reset button.

Reset is the sole operation permitted to replace the file. It writes a fresh seeded state, clears
recovery mode, and re-enables normal writes.

Before the first ordinary write, create the parent directory:

```swift
try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
```

`~/Library/Application Support/BitPrice/` does not exist on a clean machine, and an atomic write into
a missing directory fails.

Encode with sorted keys and write with `Data.write(options: .atomic)`.
Ordinary structural edits use a 500 ms `SuspendingClock` debounce.
The file is expected to remain small, so encoding and the atomic write occur synchronously on `@MainActor`.
This may cause a short UI hitch; that is accepted in exchange for one serialization domain.

Alert latch transitions bypass debounce and call `saveNow()` before returning.
The fire transaction is:

1. retain the old alert value;
2. set `isArmed = false` and `lastFiredAt = now` in the complete state;
3. atomically save the complete state;
4. on failure, restore the old value, show an error, and do not notify;
5. on success, request the OS notification.

The re-arm transaction uses the same save-or-restore rule with `isArmed = true`.
This is bidirectional latch durability.
In read-only recovery mode step 3 fails by definition, so latch transitions restore and report
without notifying. Alerts therefore do not fire while a malformed file is awaiting Reset — an
accepted consequence of never overwriting a file the user was promised would be preserved.
A crash before the atomic replace leaves the old state and no notification.
A crash after replace cannot duplicate the alert on restart.
A crash after replace but before notification submission can miss a banner; this at-most-once tradeoff is accepted.

There is no separate alert history and therefore no history/state split-brain.

### 4.3 BinanceStreamClient

`actor BinanceStreamClient` exclusively owns the web socket, the receive task, the retry attempt
counter, and the typed `AsyncStream<FeedEvent>.Continuation`.

#### 4.3.1 Why the previous epoch-handshake interface was replaced

Four consecutive revisions patched a three-method interface — `events(for:)`, `reconnect()`,
`currentEpoch()` — and each patch produced the next revision's blocking defect. The interface is
therefore replaced outright rather than amended a fifth time. The specific failures it produced,
recorded so a future revision does not reintroduce the shape:

1. `events(for:)` accepted a product set but returned no epoch; `reconnect()` returned an epoch but
   accepted no product set. Startup and set-change each had exactly half of what they needed, so a
   watchlist edit rebuilt the **previous** URL.
2. The client owns its own retry, so it mints successor epochs autonomously. The only channel to
   `AppModel` was `reconnect()`'s return value, which autonomous retry does not call — and the rule
   forbidding adoption of an epoch mid-stream closed the sole alternative. Every event after any
   spontaneous socket failure was rejected forever: Binance recovery was permanently wedged.
3. Even along the paths that did work, epoch handoff was not atomic. `AppModel` had to `await` a call
   into another actor, and the MainActor ran the stream consumer during that suspension — buffered
   events from the old epoch passed the filter before the new epoch was installed.

The common root is not any one of these. It is that **`AppModel` held the authorization state**, and
had to acquire it out-of-band from a component that changes it independently. No return value can
close that gap, because the component does not always return.

#### 4.3.2 The lifecycle contract

Authorization moves inside the actor. The client emits events from exactly one live connection at a
time and never emits an event from a superseded one. `AppModel` performs **no epoch filtering** and
holds no epoch variable. `AsyncStream` buffering — the window every previous revision failed to
close — is closed by construction below, not by a consumer-side check.

```swift
actor BinanceStreamClient {
    /// The single entry point for start, product-set replacement, and stop.
    /// Empty `productIDs` tears the connection down and is a valid steady state.
    /// Idempotent: calling with the current set is a no-op that leaves the socket untouched.
    func setProducts(_ productIDs: Set<String>)

    /// Exactly one stream for the client's whole lifetime, obtained once at startup
    /// before any `setProducts` call. It never terminates on reconnect, and is not
    /// re-obtained on product change.
    func events() -> AsyncStream<FeedEvent>

    /// Health-triggered repair of the current connection, per §4.1.1.
    /// Idempotent and set-preserving: it reconnects the products already configured.
    /// Returns nothing. Nothing outside the actor needs to know the epoch.
    func reconnectForHealth()
}
```

Three methods become three **distinct intents** — replace the set, observe, repair — rather than
three partial views of one lifecycle. There is no `currentEpoch()`, no epoch return value, and no
`stop()`: stopping is `setProducts([])`.

#### 4.3.3 Sequencing rules that make buffered events unreachable

The epoch still exists inside the actor, as connection identity. It is no longer a token handed
across an actor boundary.

1. Each connection task holds the epoch it was created with as a local constant.
2. A connection task yields to the continuation **only** after re-checking, inside the actor, that
   its own epoch still equals the actor's current epoch. A superseded task's yield is dropped at the
   source.
3. Superseding a connection — from `setProducts`, `reconnectForHealth`, or the client's own retry —
   is one synchronous actor-isolated step: mint the new epoch, cancel the old task, and **drain**.

Rule 3's drain is what removes consumer-side filtering. Because the actor owns the continuation and
a replaced task can no longer yield, the only stale events that can exist are those already sitting
in the stream buffer. The supersede step yields a `.superseded` barrier after cancelling.
`AppModel` treats it as a barrier: on receipt it discards every quote-affecting event it had
consumed since the previous barrier and had not yet committed, then resumes. The barrier is
delivered **in-band, in order**, on the same stream — so it cannot be raced by an `await` on another
actor, which is exactly how the previous design's handoff failed.

Equivalently: staleness is decided by **position in a single ordered stream**, not by comparing a
consumer-held identifier against an event-carried one. Ordering is a property `AsyncStream` already
guarantees; identifier agreement across two actors is not.

`FeedEvent` therefore drops its `epoch` field (§3). Events are unconditionally current when read,
because the barrier has already invalidated everything before it.

#### 4.3.4 Autonomous retry

The client retries on its own, using the capped 1/2/4/8/16/30-second `SuspendingClock` delays of
§2.2. Autonomous retry supersedes exactly like an external call: it mints an epoch, emits the
barrier, and connects. Because no epoch crosses the boundary, autonomous retry needs no channel to
`AppModel` and cannot wedge recovery. This is defect 2 above, removed structurally rather than
patched.

`.connected` and `.failed` remain on the stream so `AppModel` can render `live`/`stale`/`offline`,
but they are status reports, not authorization.

#### 4.3.5 Retry counter granularity

§2.2's counter resets only after the current session accepts a valid ticker update. In a combined
stream that rule is wrong at the granularity it is stated: any one live product resets the counter
on behalf of a permanently silent neighbor, so a health reconnect restarts the sequence at one
second forever and never reaches the 30-second cap.

The counter therefore resets only when a session accepts a valid tick **for every product it
subscribed to**. A session where one product never speaks does not reset it, so repeated
health-triggered repairs of the same silent product walk 1/2/4/8/16/30 and settle at the cap.

A session that accepted at least one tick but not a full set still counts as reachable, so
`.offline` is not entered — the circuit-breaker condition of §2.2 stays tied to sessions that
produced no valid tick at all.
Backoff sleeping uses `SuspendingClock`; health and last-success ages use `ContinuousClock`.

### 4.4 REST clients

`actor CoinGeckoClient`, `actor BinanceCatalogClient`, and `actor CoinbaseClient`
own their URLSession work and decode private wire DTOs inside the actor.
Their public return values are explicit `Sendable` domain structs.
They never return `HTTPURLResponse`, `URLSessionTask`, or raw framework errors.

### 4.5 Callback boundary rules

Framework callback payloads (`Error`, `Notification`, and `URLSessionWebSocketTask.Message`) are not `Sendable` as delivered.
Do not silence diagnostics with `@unchecked Sendable` or broad `@preconcurrency` imports.

At the callback boundary, before creating a `Task` or calling an actor:

- convert `Error` to `NetworkFailure` using domain, code, and message;
- convert `URLSessionWebSocketTask.Message` to owned `String` or `Data`;
- never capture `Notification`; extract needed value fields or pass no payload;
- convert `HTTPURLResponse` to status code and required string headers;
- convert notification-center completion data to identifier/status value types.

Only converted `Sendable` values cross isolation boundaries.
For `NSWorkspace` sleep/wake observers, ignore the `Notification` argument and call
`Task { @MainActor in appModel.handleWakeOrSleep(...) }` with an enum value created by the closure.

All long-lived tasks are stored and cancelled explicitly.
Do not use `Task.detached`.
Periodic work is a `Task` loop using an injected clock, never `Foundation.Timer`.
The full source tree must compile in Swift 6 mode with warnings treated as errors.

### 4.6 AlertEngine and NotificationService

`AlertEngine` is a pure namespace or `@MainActor` helper; it owns no timer.
It evaluates only fresh accepted quotes and returns `noChange`, `rearm`, or `fire`.
`AppModel` performs the durable transaction for `rearm` and `fire`.

Evaluation order is normative. Cooldown gates firing only — it never gates re-arming:

1. alert disabled — `noChange`;
2. disarmed and price strictly outside the re-arm band — `rearm`, **without consulting cooldown**;
3. disarmed and price still inside the band — `noChange`;
4. armed and threshold not breached — `noChange`;
5. armed, breached, but inside cooldown — `noChange`, and the alert **stays armed**;
6. otherwise — `fire`.

Placing the cooldown guard before step 2 is the natural reading of a bare guard clause and is wrong:
a disarmed alert whose price had already left the band would refuse to re-arm for the whole cooldown,
so a later genuine breach could not fire. §1.3 requires the opposite. Only one transaction is
persisted per evaluation.

Cooldown uses wall-clock `Date` because it survives restarts. Applied at step 5 only:

```swift
let age = max(0, now.timeIntervalSince(lastFiredAt))
guard age >= cooldownSeconds else { return .noChange }
```

Clamping prevents a negative age and the premature fire it would cause. It does not neutralize a
clock rollback: a backward jump can lengthen the effective cooldown until wall time catches up,
which §7 records as an accepted limit.

`@MainActor final class NotificationService` wraps `UNUserNotificationCenter`.
It requests `.alert` and `.sound`, submits a local notification after durable fire state,
and reports authorization denial or submission failure as a nonmodal UI error.
Submission success means scheduled, not delivered.

### 4.7 Views

`BitPriceApp` uses `MenuBarExtra` with window style.
`WatchlistPanel` is approximately 380 points wide with a scrollable list.
`WatchRow` dims stale data and uses arrows as well as color for change direction.
Unavailable percentage is `—`, never zero.

`SparklineView` uses SwiftUI `Canvas` or `Path`, has no axes, and handles an empty or flat series.
`SearchSheet` presents CoinGecko results, then the required venue confirmation sheet.
`AlertSheet` validates values inline and warns about Coinbase's 60-second precision.

Suggested source layout:

```text
Sources/BitPrice/
  BitPriceApp.swift
  AppModel.swift
  Models.swift
  PersistenceStore.swift
  BinanceStreamClient.swift
  RESTClients.swift
  AlertEngine.swift
  NotificationService.swift
  Views.swift
Info.plist
scripts/build-app.sh
```

## 5. Build and packaging

### 5.1 Required toolchain path

The measured environment is macOS 15.6.1, Apple Swift 6.1.2, SDK 15.5,
Command Line Tools 16.4, no Xcode.
SwiftPM is unusable here: tools versions 6.1 and 5.9 both fail manifest linking with
`Undefined symbols: PackageDescription.Package.__allocating_init`.
This toolchain's `PackageDescription` supports at most `.macOS(.v14)`; `.v15` does not resolve.
Do not invoke `swift build` in the build script.

Build directly with `swiftc`, Swift language version 6, and warnings as errors.
The deployment target is arm64 macOS 14.0.
A bare executable crashes because the process has no bundle proxy.
The measured exception was `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil`.
Assemble, sign, and launch an application bundle with `open`.

### 5.2 Info.plist

Create this file verbatim as project-root `Info.plist` during implementation:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BitPrice</string>
  <key>CFBundleDisplayName</key><string>BitPrice</string>
  <key>CFBundleIdentifier</key><string>com.wayne.bitprice</string>
  <key>CFBundleExecutable</key><string>BitPrice</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

### 5.3 Build script

Create this as `scripts/build-app.sh` during implementation:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/BitPrice.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

SOURCES=()
while IFS= read -r -d '' source; do
  SOURCES+=("$source")
done < <(find Sources/BitPrice -type f -name '*.swift' -print0)

if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "error: no Swift sources found" >&2
  exit 1
fi

swiftc \
  -parse-as-library \
  -swift-version 6 \
  -warnings-as-errors \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  "${SOURCES[@]}" \
  -o "$CONTENTS/MacOS/BitPrice"

cp Info.plist "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose=2 "$APP"
otool -L "$CONTENTS/MacOS/BitPrice"

echo "built: $APP"
echo "launch: open $APP"
```

Ad-hoc signing is sufficient for this local personal build.
It is not a distribution or notarization solution.
Never launch `Contents/MacOS/BitPrice` directly; use `open build/BitPrice.app`.

## 6. Deliberately omitted

These omissions are decisions, not deferred hidden requirements.

1. **Six-state socket state machine.** Use stopped/connecting/connected plus one owned task. If lifecycle races appear, a reconnect may cause a brief extra outage; add states only from a reproduced case.
2. **Application-wide generation tokens.** Cancellation plus one client-local epoch stamped on every `FeedEvent` guards the socket (§2.2). The epoch reaches `AppModel` because buffered events outlive their connection, but no other component mints or forwards one. If another client later develops late-result corruption, give that client its own local request UUID rather than a global generation protocol.
3. **Desired/confirmed subscription sets and command queue.** Rebuild the combined-stream URL on mapping changes. A large watchlist edit reconnects and briefly interrupts all Binance prices.
4. **Subscription acknowledgement timeout and recovery.** Combined-stream URLs have no subscribe commands to acknowledge. A bad stream manifests as missing/stale data, which §4.1.1 converts into one reconnect per epoch and §2.3 into Coinbase fallback.
5. **Three-condition acknowledgement-timeout guard.** There is no acknowledgement state to protect. If dynamic subscriptions return later, this guard must return with that design.
6. **Circuit breaker.** Retry forever with a 30-second cap. A long outage produces continuing low-rate connection attempts and log noise instead of entering a terminal offline state.
7. **Four-timestamp composite socket health.** Keep current-epoch identity plus `connectedInstant` and last valid success. A half-open connection is detected in over 60 and under 75 seconds while awake (§2.2.1), and one reconnect follows (§4.1.1).
8. **Revision-numbered asynchronous snapshot worker.** One main-actor owner performs small atomic writes. If the file grows or writes visibly hitch, move encoding/I/O to one actor and add ordering then.
9. **Mandatory in-app alert history and badge.** Only durable latch state and OS notifications remain. If macOS suppresses a notification, there is no audit trail and the user may never know it fired.
10. **Rich per-source health state.** UI exposes only live/stale/offline. Simultaneous partial failures may have less diagnostic detail.
11. **Failback dwell and escalating source holdout.** First valid Binance tick wins. An unstable Binance connection can flap rows between sources and change alert precision.
12. **Eighty-three clause-level tests.** Use the 43 behavior and failure-boundary tests below — one assertion group per specified behavior, not one per clause. A rare protocol edge not represented by those behaviors may escape until observed.
13. **Listing-cache refresh machinery and automatic re-resolution.** Candidate lists are fetched during add. A later delisting leaves a row stale until the user removes and re-adds it.
14. **Proactive 23-hour reconnect and application pings.** Let receive failure and staleness drive reconnect. A half-open socket may recover more slowly, and Binance's daily close causes a brief gap.
15. **Automatic identity verification from contract metadata.** No reliable cross-venue contract is specified. Every non-seeded mapping is explicitly user-confirmed instead.

Per-coin venue confirmation is intentionally **not** omitted.
Without it, a unique ticker candidate can still be a wrapped, bridged, or unrelated asset,
and the app can show the wrong project's price while falsely appearing correct.

## 7. Risks and accepted limits

| Risk | Behavior or mitigation |
|---|---|
| Binance is blocked or unavailable | Poll the persisted Coinbase product when present; until it answers, keep showing the last Binance quote dimmed as stale. Show unavailable only when there is no Coinbase mapping and no prior quote |
| Coinbase stats has no valid open | Show change as `—`; never fabricate flat performance |
| User confirms wrong venue asset | Expose venue/product IDs; no claim of cryptographic identity |
| Binance flaps during failback | Immediate source switching may flicker and alter alert precision |
| CoinGecko quota or 429 | Retain old sparkline, honor retry delay, never real-time poll |
| Sparkline shape differs from Binance change | Expected cross-venue difference; no axis and no consistency assertion |
| Alert state write fails | Restore prior latch, do not notify, show persistence error, retry on next qualifying tick |
| Crash after durable fire but before notification | Banner can be missed; duplicate is prevented |
| Notification denied, Focused, or suppressed | No delivery guarantee and no in-app history in this version |
| Coinbase 60-second polling | Brief price breaches can be missed entirely |
| System clock moves backward | Cooldown age clamps to zero; a rollback can lengthen cooldown but cannot make age negative |
| Eight-hour sleep | Quotes/socket become stale; periodic tasks resume without replaying missed cycles |
| Corrupt persistence file | Do not overwrite it; run from an in-memory seed and offer Reset. All writes are refused until Reset, so alerts do not fire and edits do not stick while in recovery mode |
| Persisted file written by a newer build | Treated as recovery mode rather than downgraded; no data is destroyed by an older version |
| Atomic write blocks main actor | Small personal file may cause a short hitch; measure before adding a worker |
| Capped retry has no breaker | Network attempts continue every 30 seconds throughout a long outage |
| Ad-hoc signing | Local use only; sharing needs Developer ID signing and notarization |
| Notification delivery on measured host | Unverified because no Aqua GUI session was available |

## 8. Focused verification plan

Automated tests use injected clocks, mock URL loading, and a temporary persistence directory.
No test depends on live public APIs except the separately marked smoke test.

1. **Strict build:** compile the full tree with the documented `swiftc` flags; zero warnings; lint and verify the signed bundle.
2. **Bundle launch:** in an Aqua session, `open build/BitPrice.app`; confirm one menu item, no Dock icon, and a bare executable is never used.
3. **First launch:** absent state file seeds only curated BTC and makes it primary.
4. **Valid empty state:** delete BTC, persist, relaunch, keep empty, and assert zero network/periodic tasks.
5. **Watchlist behavior:** add, reject duplicate CoinGecko ID, reorder, set primary, delete primary, and verify deterministic replacement.
6. **Search ordering:** a slow old query completing after a new query cannot replace the newer results; special characters are percent-encoded.
7. **Identity boundary:** two CoinGecko results sharing `SOL` remain distinct; no venue candidate, including a unique one, is accepted without explicit confirmation.
8. **Dual mappings:** confirm Binance and Coinbase IDs, relaunch, and prove both exact strings are used without symbol recomputation.
9. **Binance parsing:** accept a valid combined ticker; reject unknown product, malformed Decimal, null field, and non-finite percentage.
10. **Idempotent reconnect:** call reconnect concurrently/repeatedly; at most one task remains and events from the replaced session are ignored.
11. **Combined URL rebuild:** a mapping edit produces one sorted combined URL and cancellation; removing all Binance mappings closes the socket.
12. **Retry boundary:** failures produce 1/2/4/8/16/30-second suspending-clock delays and stay capped.
13. **Coinbase change contract:** compute `(last-open)/open*100`; missing, invalid, zero, or negative open produces `.unavailable` rendered as `—`.
14. **Fallback behavior:** stale/failed Binance activates only mapped Coinbase items; unmapped items say no fallback; first valid Binance tick switches back.
15. **Sparkline boundary:** batch IDs once; drop bad points, keep fewer than 24, trim to last 24, retain prior on missing data, and draw flat input safely.
16. **HTTP boundary:** reject non-2xx before decoding; a 429 honors `Retry-After`; timeout keeps prior UI data.
17. **Clock sleep semantics:** simulated eight-hour sleep makes ContinuousClock quote/socket ages stale but does not replay SuspendingClock periodic work.
18. **Write debounce clock:** structural edits coalesce only after 500 ms of running time; sleep alone does not complete the debounce.
19. **Alert validation:** reject/disable zero threshold, negative/non-finite cooldown, and hysteresis outside `0 ..< 100`; equality never breaches or re-arms.
20. **Above alert fire:** an armed breach atomically persists disarmed state and wall-clock fire date before one notification request.
21. **Below alert re-arm:** leaving the band persists armed state immediately, the re-arm tick cannot fire, and restart preserves the armed latch.
22. **Cooldown and rollback:** a breach inside cooldown stays armed and silent; negative wall-clock age clamps to zero; restart uses the persisted fire date.
23. **Persistence failure:** failed fire and re-arm saves restore old in-memory state; fire sends no notification; a later tick can retry.

The following cover behavior specified above that tests 1–23 leave unasserted. They are core
contracts, not rare protocol edges.

24. **Stale drives reconnect:** the threshold is strict — at exactly 60 seconds no reconnect occurs, and the first stale check past 60 seconds produces exactly one `reconnectForHealth()` for the current connection, with no further repair until the next `.connected`. Awake detection therefore lands above 60 and below 75 seconds. A session already backing off is not restarted; a socket that connects and never ticks still ages from `connectedInstant`.
25. **Superseded-connection isolation:** a `.failed` and a `.ticker` yielded by a connection that is then superseded, and sitting in the `AsyncStream` buffer when the replacement connects, do not mark the replacement failed and do not update a quote. The barrier ordering is asserted directly: the consumer reads the stale events *before* `.superseded`, and the barrier discards them. No epoch value appears anywhere in the test, because `AppModel` holds none.
26. **Partial stream silence:** in a two-product combined stream where one product keeps ticking and the other stays silent past 60 seconds, the session is judged unhealthy and reconnects once; only the silent product's quote is marked stale. A session-wide timestamp would refresh on the live product and never fire — that is the regression this test exists to catch. The same strict boundary as test 24 applies: at exactly 60 seconds of silence, nothing happens.
27. **Absent schemaVersion:** a fixture with no `schemaVersion` key decodes as version `0` and migrates, rather than failing the decode into recovery mode; this is asserted separately from the missing-`isArmed` case, since either alone would fail synthesized decoding for a different reason.
28. **Backoff reset rule:** the attempt counter survives connect/close cycles and resets only after a valid ticker update **from every subscribed product**; a server that accepts then immediately closes walks 1/2/4/8/16/30 rather than repeating 1. A two-product session in which only one product ever ticks does **not** reset the counter — assert across at least three successive health repairs that the delays increase and reach the cap, since a single-repair test cannot distinguish this from the session-wide rule it replaces.
29. **Reconnect trigger scope:** reordering rows, changing the primary, editing an alert, and adding or removing a Coinbase-only item each call `setProducts` and each leave the socket untouched, because the derived set is unchanged and `setProducts` is idempotent; only a changed Binance product-ID set rebuilds the URL. Assert idempotence at the client, not suppression at the caller.
29a. **Autonomous retry recovery:** with no external call of any kind, a socket failure followed by the client's own successful retry delivers `.superseded`, then `.connected`, then a `.ticker` that **updates the quote**. This is the permanent-wedge regression: under the previous design every post-retry event was rejected forever.
29b. **Empty-set lifecycle:** `setProducts([])` closes the socket and is a steady state; a later nonempty `setProducts` on the same client and the same stream reconnects without re-obtaining `events()`. Deleting the last watch item cancels the periodic loops and adding an item restarts them. A watchlist of only Coinbase-only items keeps the periodic loops running while the Binance set is empty.
29c. **Duplicate venue product ID:** confirming a venue product ID already mapped by another item is rejected at the add flow; a persisted file containing the duplicate enters read-only recovery rather than fanning one tick out to two rows.
30. **Coinbase-only item:** an item with Binance “No market” and a confirmed Coinbase product is polled immediately at launch and every 60 seconds thereafter, with no Binance failure required.
31. **Active quote asset:** a dual-mapped row shows USDT under Binance and USD under Coinbase, updating on failover in both directions; with no quote it falls back to the mapped venue's asset rather than blank.
32. **Search debounce and cancellation:** keystrokes within 300 ms of running time issue one request; sleep does not complete the debounce; an emptied query cancels the in-flight task and clears results.
33. **Candidate confirmation:** venue candidates are filtered by base asset, quote asset, and trading status; selecting “No market” for both venues is rejected; a single candidate still requires explicit confirmation.
34. **Alert edit semantics:** changing direction, threshold, or hysteresis, or enabling a disabled alert, re-arms and clears the fire date; changing only cooldown preserves latch state.
35. **Evaluation order:** a disarmed alert outside its band re-arms while inside cooldown; a cooldown-suppressed breach stays armed; only one transaction persists per evaluation.
36. **Both directions:** below-alert firing uses `price < threshold` and above-alert re-arming uses `price < threshold × (1 - h/100)`; band-edge equality neither fires nor re-arms.
37. **Migration from a real fixture:** a committed older JSON file lacking `isArmed` decodes to a disarmed alert rather than entering recovery mode; a `schemaVersion` above the current build enters recovery mode without overwriting; a positive `schemaVersion` below the current build with no defined migration step also enters recovery mode without overwriting, rather than being decoded on a guess. A version-`1` file missing `isArmed`, or carrying it as `null`, enters recovery mode — the §3 fallback is scoped to version `0` and must not rescue it.
38. **Recovery-mode write protection:** with a malformed file present, a reorder and an alert latch transition both fail without touching the file; only Reset replaces it; a missing Application Support directory is created before the first ordinary write.
39. **Shared rate-limit gate:** a 429 from the sparkline batch also suppresses search until the deadline; `Retry-After` is honored in both integer-seconds and HTTP-date form; the deadline is consumed by system sleep; the REST timeout is exactly 15 seconds.
40. **Notification authorization:** permission is requested when the first alert is enabled, not at launch; denial and submission failure each surface a nonmodal error while the durable latch transition still stands.
41. **Formatting:** prices use grouping separators with two decimals at or above 1 and up to six below; the menu label shows `SYMBOL price` for the primary item and `BitPrice` when the list is empty or the primary has no quote.
42. **Single instance:** with another BitPrice already running, startup exits without mutating the persisted file.
43. **Notification smoke test, manual:** in a real desktop GUI session, grant permission and trigger one alert; record whether macOS presents it, but do not fail core alert logic if presentation is suppressed.

Implementation is complete only when tests 1–42 pass.
Test 43 records the currently unverified OS integration fact.
