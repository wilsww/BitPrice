# BitPrice implementation specification

## 0. Purpose and normative language

BitPrice is a personal macOS menu-bar application that shows live cryptocurrency prices, a configurable watchlist, truthful 24-hour charts, and durable price alerts. This document is the complete implementation contract. An implementer must not need `IMPLEMENTATION.md` or any planning file.

“Must” is required behavior. “May” is optional. Values described as runtime-only must never be encoded. No third-party dependency is permitted.

The design deliberately uses one `@MainActor` serialization domain for the watchlist, live quotes, alert transitions, and Binance connection authorization. This removes the cross-actor epoch handoff and buffered-event invalidation problems rather than attempting to patch them.

## 1. Fixed measured facts

The following were established by direct measurement on the target machine and are not design choices:

- macOS 15.6.1, Apple Swift 6.1.2, SDK 15.5, Command Line Tools 16.4, **no Xcode**.
- **SwiftPM is unusable**: tools versions 6.1 and 5.9 both fail manifest linking with `Undefined symbols: PackageDescription.Package.__allocating_init`. The build script must never invoke `swift build`. There is no `Package.swift`.
- Build with `swiftc` directly, Swift language mode 6, **warnings as errors**, arm64, deployment target **macOS 14.0** (`.v15` does not resolve in this toolchain; `LSMinimumSystemVersion=14.0`, `-target arm64-apple-macosx14.0`).
- **A bare executable crashes**: `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil`. A hand-assembled, ad-hoc-signed `.app` bundle is required. Verify with `plutil -lint`, `codesign --verify`, `otool -L`.
- `LSUIElement=true` (menu bar only, no Dock icon).
- Binance klines REST **has no batch mode**: `symbols=` returns `-1102 Mandatory parameter 'symbol' was not sent`.
- CoinGecko free tier (10k/month) **cannot** support real-time polling — measured as 4–17x over quota. Prices must come from the Binance WebSocket (no key, no quota).
- CoinGecko `coins/markets?sparkline=true` is the only endpoint giving batched sparklines (one call for the whole watchlist, ~168 points each).
- Coinbase `/v2/prices/{pair}/spot` returns amount/base/currency only — **no 24h change**. `/products/{id}/stats` gives `last`/`open`; change must be computed and is unavailable when `open <= 0`. **Never fabricate 0.00%.**
- CoinGecko symbols are **not unique** (multiple coins share `SOL`). A ticker match is a candidate filter, never an identity assertion.
- `URLSessionWebSocketTask` handles WebSocket control frames below the `.string`/`.data` boundary; the framework answers server Pings automatically. Application code must not add a ping loop — Binance counts all control traffic against 5 messages/second.
- Notification delivery could not be verified: no Aqua GUI session on the measured host.

## 2. Product behavior

### 2.1 Menu bar and panel

Use SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`. The app has no ordinary app window and no Dock icon.

The menu-bar title is `SYMBOL price` for the primary item when it has a quote. It is `BitPrice` when the watchlist is empty, the primary reference is absent, or the primary has no quote. Use grouping separators, two fractional digits for prices at least 1, and up to six fractional digits below 1.

The panel is approximately 380 points wide and contains:

- a header with the app name, the single connection presentation, and Add;
- a vertically scrollable ordered watchlist;
- a row for every watched coin showing symbol, current venue quote asset, 24-hour sparkline, price, and 24-hour change;
- controls to remove and reorder items, choose the primary item, inspect mappings, and edit the item’s alert;
- compact persistent banners for recovery mode and current errors.

The quote asset is derived from the mapping for `Quote.source`: Binance normally shows USDT and Coinbase normally shows USD. With no quote, prefer the Binance mapping’s quote asset, then the Coinbase mapping’s. An unavailable change renders `—`, never `0.00%`. Change direction uses an arrow or sign as well as color. A stale row is visibly dimmed and labeled stale.

Only three user-facing connection presentations exist: `live`, `stale`, and `offline`. Internal lifecycle states are not additional presentations.

### 2.2 Watchlist semantics and bounds

The watchlist order is user-controlled. `primaryItemID` is a UUID, not a row index. Deleting the primary selects the first remaining item. Deleting the last item sets the primary to `nil`. An empty watchlist is valid and must remain empty across relaunch.

The maximum watchlist size is 25. Before an add is committed, the app must also construct the prospective Binance combined-stream URL and reject the add if its UTF-8 representation would exceed 2,048 bytes. These two checks bound both request count and URL size. CoinGecko IDs are not put into a batch URL in this design.

Duplicate item UUIDs, CoinGecko IDs, Binance product IDs, or Coinbase product IDs are forbidden. Product-ID uniqueness is per venue. A watch item must have at least one venue mapping.

The first launch seeds exactly one item:

- CoinGecko ID `bitcoin`, symbol `BTC`, name `Bitcoin`;
- Binance product `BTCUSDT`, base `BTC`, quote `USDT`;
- Coinbase product `BTC-USD`, base `BTC`, quote `USD`;
- both mappings have curated built-in provenance;
- this item is primary and has no alert.

The seed UUID is generated once and immediately persisted. A missing file means first launch; a successfully decoded empty file never reseeds. If the initial seed write fails, run with that in-memory seed in read-only mode, disable alerts/edits, and show the write error; do not pretend the first launch was durable.

### 2.3 Search and explicit venue confirmation

Search CoinGecko with:

`GET https://api.coingecko.com/api/v3/search?query={query}`

Build the URL with `URLComponents`. Search begins after 300 milliseconds of awake typing inactivity. Empty input cancels the debounce and request and clears results. Each query has a UUID owned by `AppModel`; completion is accepted only if that UUID is still current. `Task.cancel()` cancels the older request, but the UUID check remains required because cancellation is cooperative.

Consume only CoinGecko `id`, `name`, `symbol`, `market_cap_rank`, and thumbnail URL. Selecting a result identifies a CoinGecko project only. It does not identify an exchange asset.

The next sheet fetches and displays candidates from both venues:

- Binance: `GET https://api.binance.com/api/v3/exchangeInfo`; candidate base asset equals the selected symbol case-insensitively, quote asset is `USDT`, status is `TRADING`.
- Coinbase: `GET https://api.exchange.coinbase.com/products`; candidate base currency equals the selected symbol case-insensitively, quote currency is `USD`, status is `online`, and the product is tradable rather than disabled/cancel-only.

For each venue the user must explicitly choose one candidate or “No market.” The sheet must say, “Candidates matched by ticker; verify the market.” Confirmation remains mandatory even when there is one candidate. Both venues cannot be “No market.” Persist the exact selected IDs, base assets, quote assets, and user-confirmed provenance. Never reconstruct a product ID from a symbol on launch, retry, fallback, or chart refresh.

Before saving, reject a duplicate CoinGecko ID, a venue product already used by another row, the 25-item limit, or a prospective combined URL over 2,048 bytes. Every row’s detail view exposes its persisted CoinGecko and venue IDs so a mistaken confirmation is visible.

### 2.4 Alerts

Each item has at most one optional alert. An alert contains direction (`above` or `below`), `Decimal` threshold, integer cooldown seconds, `Decimal` hysteresis percent, enabled state, armed latch, and optional wall-clock last-fire date.

Validation is normative:

- threshold is greater than zero;
- cooldown is in `0...604800` seconds;
- hysteresis is in `0..<100` percent;
- all decimal input must parse exactly and be finite;
- equality is neither a breach nor a re-arm.

New alerts start armed with no last-fire date. Editing direction, threshold, or hysteresis, or enabling a disabled alert, also sets armed to true and clears the last-fire date. Editing only cooldown preserves both latch fields. The editor warns that 60-second Coinbase polling can miss a brief breach.

Notification permission is requested when the first alert is enabled, not at launch. There is no in-app alert history in this version.

Enabling uses the ordinary `commitEdit` transaction first. Only after the enabled state is durably published does `NotificationService` request permission. Denial does not undo the saved alert; it produces a visible warning that fires will be latched but macOS banners are unavailable.

## 3. Architecture and modules

### 3.1 Source layout

The implementation should use this module/file split:

```text
Sources/BitPrice/
  BitPriceApp.swift
  AppModel.swift
  DomainModels.swift
  PersistenceStore.swift
  ProcessLock.swift
  BinanceFeedController.swift
  WebSocketDelegateAdapter.swift
  RESTClients.swift
  AlertEngine.swift
  NotificationService.swift
  Views.swift
Info.plist
scripts/build-app.sh
Tests/
```

This is one executable module, not Swift packages.

### 3.2 Ownership and isolation

`@MainActor final class AppModel` is the sole owner of UI-visible and persisted state. It owns the items, primary ID, runtime quotes, chart series, request tokens, errors, recovery mode, the user-facing connection presentation, and long-lived periodic tasks.

`@MainActor final class BinanceFeedController` owns the Binance product set, configuration UUID, current connection UUID, current URL-session task identifier, current suspending-clock open instant, `URLSessionWebSocketTask`, receive task, lease task, retry task, retry counter, and authoritative detailed lifecycle state. It has no `AsyncStream` and no continuation.

`AppModel` conforms to a main-actor-only `BinanceFeedSink` interface with two members:

- `feedDidAccept(_ tick: BinanceTick)` supplies a parsed tick that passed the current-connection check;
- `feedStateDidChange(_ state: BinanceLifecycle)` supplies authoritative state changes.

Because both objects are main-actor isolated, these calls are synchronous actor-isolated calls with no `await` between the final connection-ID check and quote application.
`feedDidAccept` maps `tick.productID` to an item only by looking up the current persisted Binance mapping. If no exact current mapping exists, it drops the tick. The controller supplies the product ID; the persisted mapping supplies the item identity.

REST clients are actors that own `URLSession` work and private wire DTOs. Their public methods return explicit `Sendable` domain values only. They never return `HTTPURLResponse`, a task object, a raw framework error, or a wire DTO.

`PersistenceStore`, `AlertEngine`, and `NotificationService` are called only by `AppModel`. Persistence encoding and writing are synchronous on the main actor because the file is bounded to 25 items. The accepted tradeoff is a possible short UI hitch.

All value types crossing an actor boundary explicitly conform to `Sendable`. Persisted values also conform to `Codable`. Do not use `Task.detached`, broad `@preconcurrency` imports, or broad `@unchecked Sendable` conformance to suppress Swift 6 diagnostics. At callback boundaries, convert `Error` to a small sendable failure value and extract only sendable strings, data, status codes, and headers.

`WebSocketDelegateAdapter` implements `URLSessionWebSocketDelegate`. The `URLSession` is created with this delegate and `OperationQueue.main`. Its nonisolated delegate entry points extract only `webSocketTask.taskIdentifier` and a `NetworkFailure`; they do not capture or forward the task or raw `Error`. They schedule a main-actor call to `BinanceFeedController.didOpen(taskIdentifier:)` or `didClose(taskIdentifier:failure:)`. The controller accepts either only when the integer task ID is still current. `didOpen` is the concrete signal that changes connecting to connected and records the current `SuspendingClock.Instant`.

### 3.3 AppModel lifecycle

Startup order is fixed:

1. resolve and create the Application Support/BitPrice directory;
2. acquire `ProcessLock` before reading or writing the JSON file;
3. load, migrate, and validate persistence;
4. publish the loaded or recovery-seed state;
5. attach `AppModel` as the Binance sink;
6. call `replaceProducts(_:)` with the derived Binance product-ID set;
7. if the watchlist is nonempty, immediately run fallback eligibility and candle refresh, then start the 60-second fallback, 15-minute candle, and 15-second freshness loops;
8. install sleep/wake observers.

Every structural edit uses `commitEdit(_:)`:

1. copy the complete persisted state;
2. apply the proposed transformation to the copy;
3. validate all root invariants and request bounds;
4. atomically save the complete copy;
5. only after save success, publish it as current state;
6. synchronously clear runtime data for removed or remapped items, call `replaceProducts(_:)`, and reconcile periodic loops.

If saving fails, the current state and network configuration remain unchanged and the UI reports the error. There is no persistence debounce and therefore no termination flush window.

When the watchlist becomes empty, `AppModel` cancels the fallback, candle, and freshness tasks and passes an empty Binance set. Adding the first item performs the immediate cycles and restarts those same tasks. A Coinbase-only nonempty list keeps all three periodic tasks even though its Binance set is empty.

## 4. Domain and persisted data

### 4.1 Persisted shape

The current schema version is `1`. The JSON root contains exactly:

- `schemaVersion: Int`;
- `items: [WatchItem]`, whose order is display order;
- `primaryItemID: UUID?`.

A `WatchItem` contains:

- immutable UUID `id`;
- immutable CoinGecko ID;
- display symbol and name;
- optional Binance mapping and optional Coinbase mapping;
- optional `PriceAlert`.

A venue mapping contains exchange, exact product ID, base asset, quote asset, and provenance (`builtInBTC` or `userConfirmedTickerMatch`). A mapping’s exchange must match the property in which it is stored.

`PriceAlert` contains direction, threshold, cooldown seconds, hysteresis percent, enabled, armed, and optional `lastFiredAt`.

Quotes, charts, active source, lifecycle state, request/configuration/connection UUIDs, retry counters, task handles, and monotonic instants are runtime-only.

### 4.2 Runtime values

`BinanceTick` supplies product ID, `Decimal` price, `Decimal` 24-hour percent, venue event `Date`, and current `ContinuousClock.Instant` receipt time.

`Quote` supplies item ID, `Decimal` price, price change (`percent(Decimal)` or `unavailable`), source venue, venue event/display date, and current continuous receipt instant.

`CandlePoint` supplies an absolute UTC `Date` bucket start and `Decimal` close. `ChartSeries` also records source venue, requested start/end, received continuous instant, and whether the latest refresh failed.

`NetworkFailure` is a sendable value with domain, integer code, and human-readable message. It is not a raw `Error` existential.

### 4.3 Root validation

After decoding or migration and before every save, one validator enforces all of the following:

- schema is current;
- item count is 0...25;
- item UUIDs and CoinGecko IDs are unique;
- Binance product IDs are unique among Binance mappings;
- Coinbase product IDs are unique among Coinbase mappings;
- every item has at least one mapping;
- IDs, symbols, names, base assets, and quote assets are nonempty;
- empty items require `primaryItemID == nil`; nonempty items require a primary UUID that matches exactly one item;
- every mapping has the correct exchange and provenance;
- every alert meets §2.4 validation;
- the sorted combined-stream URL can be constructed and is at most 2,048 UTF-8 bytes.

A decoded semantic violation is treated exactly like malformed JSON: enter recovery mode and do not normalize or silently repair it.

### 4.4 Versioned decoding and migration

Do not use one synthesized decoder for every version. Synthesized `Decodable` fails when a non-optional key such as `schemaVersion` or `isArmed` is absent.

Loading is a two-stage operation using `JSONDecoder.decode`:

1. Decode a `VersionProbe` whose `schemaVersion` is optional. Missing resolves to version `0`.
2. Dispatch to a DTO defined for that exact version, transform it to current values, then run root validation.

Version `0` is the pre-versioning shape. Its legacy alert DTO declares `isArmed` and `lastFiredAt` as optional, so synthesized decoding accepts their absence. Transformation rules are:

- missing `isArmed` becomes `false`, preventing a launch burst when historical latch state is unknown;
- missing `lastFiredAt` becomes `nil`;
- all other fields retain their decoded values.

Version `1` decodes the current DTO directly. In version 1, `isArmed` is required; a missing or null value is malformed and must not receive the version-0 default.

For future versions, maintain an explicit migration registry. A positive older version without a registered transform enters recovery mode. A version greater than the current version enters recovery mode. Never guess a transform.

A successfully migrated v0 value is atomically saved as v1 before networking starts. If that save fails, keep the migrated state visible but make it read-only, disable alerts, preserve the original file, and report the persistence failure.

### 4.5 File location, atomicity, and recovery

The only persisted application-data file is:

`~/Library/Application Support/BitPrice/watchlist.json`

Obtain the Application Support directory with `FileManager.default.urls(for:in:)` and create the `BitPrice` directory with `FileManager.createDirectory(at:withIntermediateDirectories:)` before lock or file operations.

Encode with `JSONEncoder` using `.prettyPrinted`, `.sortedKeys`, and `.iso8601` date encoding; decode dates with matching `.iso8601`. Write the complete state with `Data.write(to:options: .atomic)`. Partial writes are forbidden.

Malformed JSON, semantic invariant failure, unknown older schema, and newer schema enter read-only recovery mode. In that mode:

- retain the original file byte-for-byte;
- run from an in-memory BTC seed;
- show a persistent explanation including the file path and reason;
- disable structural editing and alert evaluation;
- reject every ordinary write without touching the file;
- offer Reset as the only operation allowed to replace it.

Reset atomically writes a fresh v1 BTC seed, exits recovery, publishes it, and starts networking. A Reset write failure leaves recovery and the original file intact.

### 4.6 Atomic single-instance lock

Before loading `watchlist.json`, open `~/Library/Application Support/BitPrice/instance.lock` with Darwin `open` using create/read-write flags and mode `0600`, then acquire `flock(fd, LOCK_EX | LOCK_NB)`. Keep the file descriptor open for the process lifetime.

Failure with `EWOULDBLOCK` means another instance owns the lock: exit before loading or mutating persistence. Any other open/lock error is a startup error and also prevents persistence access. `flock` is atomic and the kernel releases it on process exit or crash; the harmless lock file may remain. `NSRunningApplication.runningApplications` must not be used as the correctness mechanism because it is a check-then-act race.

## 5. Binance live-feed contract

### 5.1 Public interface and supplied inputs

`BinanceFeedController` exposes these main-actor members:

- `replaceProducts(_ productIDs: Set<String>)`: the only start, idempotent replacement, empty-set stop, and post-empty restart entry point;
- `suspendForSleep()`: closes the current task, cancels receive/lease/retry tasks, and enters suspended state while retaining the configured set;
- `resumeAfterWake()`: starts immediately for a retained nonempty set or enters stopped for an empty set;
- `shutdown()`: invalidates identity, cancels all owned tasks, closes the socket, and stops;
- read-only `state: BinanceLifecycle` and `currentProductIDs: Set<String>`.

There is deliberately no `events()`, epoch query, `reconnectForHealth`, or public parameterless reconnect. The sink methods in §3.2 are the only output interface.

`BinanceLifecycle` has internal cases `stopped`, `connecting`, `connected`, `backingOff(attempt, delay)`, and `suspended`. The controller owns this value and reports every transition synchronously to its sink. Callers never infer current state from previously buffered events.

### 5.2 URL and message contract

Normalize product IDs to lowercase stream names, sort them, append `@ticker`, and build one URL with `URLComponents`:

`wss://stream.binance.com:9443/stream?streams=btcusdt@ticker/ethusdt@ticker`

An empty set has no URL and no network task. A nonempty URL exceeding 2,048 UTF-8 bytes is a validation failure and must never be started.

Use `URLSession(configuration:delegate:delegateQueue:)`, `URLSession.webSocketTask(with:)`, `URLSessionWebSocketTask.resume()`, async `receive()`, the delegate’s `urlSession(_:webSocketTask:didOpenWithProtocol:)` / `didCloseWith:reason:`, and `cancel(with:reason:)`. Never invoke `sendPing` and never send subscribe/unsubscribe JSON; the URL defines the complete subscription set.

From each combined message consume wrapper `stream` and data fields:

- `s`: exact persisted Binance product ID;
- `c`: last price decimal string;
- `P`: 24-hour change-percent decimal string;
- `E`: venue event time in milliseconds.

Accept only a string or data message that decodes to the expected wrapper, names a currently configured product, has matching `stream` and `s`, contains a positive finite price, a finite percent, and a valid event time. Unknown, null, mismatched, or malformed data is ignored and logged as a compact failure; it is not evidence of connection health and never evaluates an alert.

### 5.3 Connection identity and stale-result exclusion

The controller holds a configuration UUID and a connection UUID. Both are runtime-only.

`replaceProducts(_:)` compares normalized sets inside the controller:

- equal set: no-op, including during connect/backoff;
- different set: synchronously mint a configuration UUID and connection UUID, install them as current, clear current task ID/open instant, reset retry attempts, cancel old receive/lease/retry tasks, close the old socket, then start the new URL;
- empty set: perform the same invalidation/cancellation, clear the socket, and enter stopped without starting a replacement.

The “start the new URL” clause applies only while awake. If lifecycle is suspended, a different nonempty set replaces the retained configuration and resets attempts but starts no task and remains suspended. An empty replacement while suspended records the empty set and enters stopped. `resumeAfterWake()` starts exactly once for a retained nonempty set, with a newly reserved connection UUID, cleared open instant, and reset attempts; it is a no-op for an empty set. `suspendForSleep()` on a nonempty set synchronously installs a new invalid connection UUID and clears task ID/open instant before cancellation, then enters suspended; on an empty set it remains stopped. `shutdown()` clears the set as well as invalidating all identity.

Each receive and lease task captures both UUIDs and the integer URL-session task identifier. Each retry captures the configuration UUID and the successor connection UUID reserved for that attempt. After every `await` and before every state mutation or sink call, it checks all captured identity values applicable to it against the controller’s current values. A mismatch returns without effect. Delegate open/close calls perform the same integer task-ID check.

This ordering is the authorization barrier: new identity is installed synchronously before old work is canceled. An old `receive()` that finishes later can reach the main actor but fails the identity check before quote application. There is no app-level buffer to purge. A tick applied immediately before replacement was current at its serialization point; the subsequent structural edit clears removed/remapped runtime rows synchronously.

Autonomous retry uses the existing configuration UUID and a new connection UUID, so it follows the same check without handing identity to a consumer.

### 5.4 Start, receive, retry, lease, and set changes

For a current nonempty configuration:

1. reserve a connection UUID, create a socket, record its integer `taskIdentifier`, enter connecting, and call `resume()`;
2. start one receive task and one five-minute lease task;
3. matching delegate `didOpen` changes connecting to connected; a ticker may be accepted only after this transition;
4. loop over async `receive()` sequentially and synchronously deliver each accepted current tick; accepting a message does not reset retry attempts;
5. a current `receive()` error or matching delegate close calls one private `failCurrent(expectedConnectionID:taskIdentifier:failure:)` method;
6. `failCurrent` is idempotent: it acts only if both identities are current and lifecycle is connecting or connected. It synchronously installs a successor connection UUID, clears the current task identifier and open instant, closes the socket, cancels receive/lease, chooses the current delay, increments the attempt index with saturation, enters backing off, and schedules exactly one retry capturing that successor UUID;
7. when retry sleep completes, re-check configuration and reserved successor identities plus the nonempty set, then create the socket for that reserved connection UUID;
8. when the five-minute lease completes without `failCurrent`, re-check both UUIDs and task ID. Reset retry attempts only if matching `didOpen` occurred and at least 60 awake seconds elapsed since its recorded open instant. Then synchronously install a successor connection UUID, clear task ID/open instant, cancel and close the old socket, and immediately create the replacement for the same configuration.

Retry delays are exactly 1, 2, 4, 8, 16, then 30 seconds, with every later failure remaining at 30. The counter resets only when a current connection reaches its five-minute lease deadline without `receive()` failing **and** has been delegate-confirmed open for at least the final 60 awake seconds, on an exact product-set replacement, or on wake. It does not reset on `resume()`, socket creation, handshake acceptance by itself, or a ticker. A server that repeatedly accepts, optionally emits one message, and closes before lease completion therefore reaches and stays at the cap; a handshake that hangs or opens during the lease’s last minute also preserves the counter. The evidence is connection-level and is not keyed to individual product activity.

Only one receive task, one lease task, or one retry task may be current. Starting one path cancels incompatible tasks first. A same-set `replaceProducts` cannot create another task.

If the product set changes during connect, receive, lease sleep, or backoff, the controller invalidates the old IDs, cancels all old work, resets attempts for the new URL, and starts the new nonempty set immediately. The old retry or lease cannot affect the replacement because its captured configuration UUID differs.

### 5.5 Half-open and quiet-market policy

The app has no application-visible Pong timestamp, and it must not send its own Pings. A per-product no-tick deadline is also not a reliable transport test for a legitimately quiet market. Therefore:

- ticker silence never marks a product dead and never triggers a reconnect;
- quote age is tracked independently per item and controls only row freshness and fallback;
- one quiet item can become stale without interrupting its active neighbors;
- the unconditional five-minute awake connection lease bounds a silently half-open socket to at most five minutes plus connection/backoff time;
- a healthy quiet product is also carried across a planned lease rotation, but it is never classified as a connection failure;
- sleep closes the socket and wake creates a fresh one, so sleep time is not added to the lease.

This is intentionally bounded repair rather than a claim that Foundation exposes an operation it does not. The cost is one brief planned reconnect every five awake minutes.

## 6. REST and chart contracts

### 6.1 Common HTTP rules

All REST URLs use `URLComponents` and exact persisted IDs. Every `URLRequest` has `timeoutInterval = 15`. Use `URLSession.data(for:)`; require a 2xx status before decoding; reject any body larger than 64 MiB before JSON decoding; reject null required fields, malformed decimals, invalid timestamps, and structurally invalid JSON. The deliberately generous bound accommodates Binance’s whole-market `exchangeInfo` catalog while still bounding decode memory. Set each WebSocket task’s `maximumMessageSize` to 1 MiB.

On cancellation, non-2xx, timeout, or decode failure, retain prior valid runtime data and update the relevant request status. Convert response status and required headers to sendable values inside the client actor.

### 6.2 Coinbase fallback

Stats use:

`GET https://api.exchange.coinbase.com/products/{percent-encoded-product-id}/stats`

Consume decimal strings `last` and `open`. `last` must be positive. When `open > 0`, change is `(last - open) / open × 100` using `Decimal`. Otherwise change is unavailable. Do not use `/v2/prices/{pair}/spot` for row data.

An item is eligible for Coinbase when it has a Coinbase mapping and any of these is true:

- it has no Binance mapping;
- Binance lifecycle is not connected;
- it has no accepted Binance quote;
- its accepted Binance quote is older than 120 continuous seconds.

Poll an item immediately when it becomes eligible and every 60 awake seconds while eligible. One polling coordinator may issue eligible item requests concurrently, but at most one request per item may be current.

Every request captures a `FallbackRequestToken` containing request UUID, item UUID, exact Coinbase product ID, item market revision, and continuous start instant. `marketRevision` increments on mapping changes and every accepted Binance tick for that item. On completion, `AppModel` accepts the response only if:

- the request UUID is still current for the item;
- item and product mapping still match the token;
- the item is still Coinbase-eligible;
- current market revision equals the captured revision, proving no fresher Binance tick or remap occurred;
- continuous elapsed request time is at most 15 seconds.

The request’s `Task` is canceled when a Binance tick makes the item ineligible, but token validation is still mandatory. A rejected late response cannot change the displayed source and cannot enter alert evaluation. An accepted response records its completion instant as quote receipt and then evaluates the alert.

The first accepted Binance tick immediately becomes active again, increments market revision, invalidates Coinbase work, and may visibly flap if Binance is unstable. If no Coinbase mapping exists, retain an old Binance quote as stale and show “No fallback market”; show unavailable only when there is no prior quote.

### 6.3 Truthful 24-hour sparkline

Do not use CoinGecko `sparkline_in_7d` for this chart. It has no timestamps and its point spacing/count is not contractual, so selecting the last 24 values cannot establish a 24-hour interval.

For each item, choose Binance candles when it has a Binance mapping; otherwise choose Coinbase candles. The source stays deterministic and does not flap with the live quote source.

Binance request:

`GET https://api.binance.com/api/v3/klines?symbol={id}&interval=1h&startTime={start-ms}&endTime={end-ms}&limit=25`

Consume kline open timestamp and close price. Binance klines are per-symbol; do not send `symbols=`.

Coinbase request:

`GET https://api.exchange.coinbase.com/products/{percent-encoded-id}/candles?granularity=3600&start={ISO-8601}&end={ISO-8601}`

Consume timestamp and close from each candle. Coinbase can omit intervals with no ticks; absence is a gap, not an error and not permission to invent a point.

For both venues, set `end = wallNow` and `start = end - 24 hours`. Reject points outside that closed interval, invalid timestamps, nonpositive closes, and duplicates; sort by timestamp. The chart x-coordinate is timestamp-relative within that exact requested interval, not array index. Break the path across a gap greater than 90 minutes. Render no chart with fewer than two valid points; render a centered horizontal line for a constant series.

Refresh all nonempty rows immediately at launch/add/wake and every 15 awake minutes. This is one request per item, at most 100 requests/hour under the 25-item limit. Retain an older series on failure and dim it after 30 continuous minutes. The UI may show a partial line when the venue has missing quiet intervals, but it must still label the requested range as 24h.

CoinGecko’s batched sparkline endpoint remains a measured capability but is intentionally unused because it cannot satisfy the timestamp contract.

### 6.4 CoinGecko rate limiting

CoinGecko is used only for user-initiated search. A 429 creates a client-wide search deadline. Parse `Retry-After` as either integer seconds or an HTTP date. Convert either form to a `ContinuousClock.Instant`; if absent or invalid, use 60 seconds. A search attempted before the deadline reports the remaining wait instead of issuing a request.

CoinGecko is never polled for live prices.

## 7. Quote freshness and connection presentation

Quote age is `continuousNow - receivedInstant`. A Binance or Coinbase quote is fresh through 120 seconds and stale when age is strictly greater than 120 seconds. Clamp any computed duration at zero defensively, although monotonic time should not move backward.

The 15-second freshness loop republishes time-derived state so SwiftUI changes at the boundary. It does not reconnect. It also reconciles Coinbase eligibility.

Per-row state is:

- `live`: the active quote is fresh and its source is usable now (Binance lifecycle connected for a Binance quote; for Coinbase, the most recent completed current-eligibility request succeeded). An in-progress Coinbase request does not invalidate its preceding success;
- `stale`: a quote exists but is old or its source just disconnected; or no quote exists while at least one applicable source is connected, connecting, or has a request in progress;
- `offline`: no quote exists and no applicable source is connected, connecting, or requesting — every mapped source is absent, stopped, failed, or backing off.

The panel’s single presentation is the worst row state: offline outranks stale, which outranks live. While a nonempty first launch is actively connecting and has no failure yet, presentation is stale, not offline. For an empty watchlist, omit the badge and show the empty state; no fourth presentation string is introduced.

Binance’s detailed `state` is read directly from `BinanceFeedController` on the main actor. Coinbase request state is owned directly by `AppModel`. No consumer reconstructs current state from historical events.

## 8. Alert engine and durability

### 8.1 Pure evaluation

`AlertEngine.evaluate(alert:price:wallNow:)` consumes the complete alert, an accepted fresh quote price, and current wall-clock `Date`. It returns exactly `noChange`, `rearm`, or `fire`. It performs no I/O.

Evaluation order is normative:

1. disabled: `noChange`;
2. disarmed and strictly beyond the re-arm boundary: `rearm`, without checking cooldown;
3. disarmed and not beyond the re-arm boundary: `noChange`;
4. armed and threshold not strictly breached: `noChange`;
5. armed and breached, but cooldown age is below cooldown: `noChange` and remain armed;
6. otherwise: `fire`.

For above alerts, breach is `price > threshold` and re-arm is `price < threshold × (1 - hysteresis/100)`. For below alerts, breach is `price < threshold` and re-arm is `price > threshold × (1 + hysteresis/100)`. Equality does nothing. A re-arming quote never fires.

Cooldown age is `max(0, wallNow.timeIntervalSince(lastFiredAt))`. A backward wall-clock change can lengthen cooldown but cannot create a negative age or early fire.

Only accepted fresh Binance or accepted token-current Coinbase quotes enter evaluation. Chart closes, malformed ticks, late fallback results, and stale cached quotes never do.

### 8.2 Durable transition transaction

`AppModel.applyAlertDecision` is the only latch-mutating interface. For `rearm`:

1. copy complete persisted state;
2. set `isArmed = true` on the copy;
3. atomically save the complete copy;
4. on success publish it; on failure retain old state and report an error.

For `fire`:

1. capture wall `now` once;
2. copy complete persisted state;
3. set `isArmed = false` and `lastFiredAt = now` on the copy;
4. atomically save the complete copy;
5. on failure retain old state, report an error, and do not notify;
6. on success publish the copy, then submit one OS notification.

This ordering gives at-most-once notification intent across crashes. A crash before atomic replace leaves the old armed state but no notification. A crash after replace cannot fire the same latch again after restart. A crash after replace but before notification submission may miss the banner; that is an accepted at-most-once tradeoff. Re-arm is equally durable, so a crash cannot lose the next legitimate breach.

Recovery/read-only mode disables evaluation because neither transition can meet its persistence precondition.

### 8.3 Notification service

Use `UNUserNotificationCenter.current()`. On first alert enable, call `requestAuthorization(options: [.alert, .sound])`. For a durable fire, create `UNMutableNotificationContent` and an immediate `UNNotificationRequest`, then call `add`.

A unique identifier combines item UUID and persisted fire timestamp. Submission success means scheduled, not displayed. Authorization denial and submission failure produce a nonmodal app error but never roll back a durable latch. No delivery guarantee or alert history is claimed.

## 9. Clock discipline and sleep/wake

The implementation must inject testable wrappers for the three time domains. Monotonic instants are runtime-only.

| Timed quantity | Duration | Clock/API | Reason and sleep behavior |
|---|---:|---|---|
| Alert cooldown and persisted fire time | user setting | `Date` | Must survive restart. Clamp negative age; sleep consumes cooldown. |
| Binance/Coinbase quote freshness | 120 s | `ContinuousClock` | Real elapsed age; eight-hour sleep makes quotes stale. |
| Chart freshness | 30 min | `ContinuousClock` | Real elapsed age; sleep makes an old chart stale. |
| Coinbase late-response acceptance | 15 s | `ContinuousClock` | Reject a response whose end-to-end real age exceeds the request contract, including sleep. |
| CoinGecko `Retry-After` deadline | header or 60 s | `ContinuousClock`, with `Date` only to parse HTTP-date | Server cooldown elapses in real time and during sleep. |
| Binance retry backoff | 1/2/4/8/16/30 s | `SuspendingClock` | No retry work executes while asleep. Sleep handler cancels it; wake reconnects immediately. |
| Binance connection lease | 5 min | `SuspendingClock` | Bounds awake half-open duration; sleep has its own teardown/restart path. |
| Minimum open evidence for retry reset | 60 s at lease completion | `SuspendingClock` instant recorded by matching delegate `didOpen` | Prevents a hung or last-second-open attempt from clearing accumulated backoff; no product cadence is involved. |
| Coinbase poll cadence | 60 s | `SuspendingClock` | Do not replay missed polls. Wake performs one immediate reconciliation. |
| Candle refresh cadence | 15 min | `SuspendingClock` | Do not replay missed refreshes. Wake performs one immediate refresh. |
| Freshness publication cadence | 15 s | `SuspendingClock` | UI boundary updates only while running; wake recomputes immediately. |
| Search debounce | 300 ms | `SuspendingClock` plus explicit cancellation on sleep | Sleep must not complete a pending typing debounce; wake has no retained query task. |
| REST transport timeout | 15 s | `URLRequest.timeoutInterval` | Concrete URL loading timeout; completion still undergoes token and continuous-age checks. |
| Candle query interval | exact previous 24 h | `Date` in UTC request parameters | Venue APIs require absolute timestamps; this is a query range, not a duration-health decision. |
| Candle path gap threshold | 90 min | Difference between two server-supplied UTC `Date` values | Preserves an observed missing interval instead of drawing a fabricated continuous segment. |
| Venue event timestamp | server supplied | `Date` for display only | Never used for freshness because server and local clocks can differ. |

Observe `NSWorkspace.willSleepNotification` and `didWakeNotification` through `NSWorkspace.shared.notificationCenter`, scheduling callbacks on `OperationQueue.main`. Do not capture or pass the `Notification` object; translate it immediately to a small sleep/wake enum and invoke main-actor methods.

On sleep, cancel search/debounce, all REST work, periodic loops, receive/lease/retry tasks, and close the socket; set Binance lifecycle suspended. On wake, recompute freshness, reconnect immediately for a nonempty Binance set, immediately reconcile Coinbase fallback and charts, and restart periodic loops once. Do not replay any missed interval.

After an eight-hour sleep, old quotes and charts are stale, the old socket cannot survive because it was closed, no missed polls are replayed, and the pre-sleep search debounce cannot issue a request.

## 10. Build and packaging

### 10.1 Info.plist contract

The root `Info.plist` must contain:

- `CFBundleName` and `CFBundleDisplayName`: `BitPrice`;
- `CFBundleIdentifier`: `com.wayne.bitprice`;
- `CFBundleExecutable`: `BitPrice`;
- `CFBundlePackageType`: `APPL`;
- `CFBundleShortVersionString`: `1.0`;
- `CFBundleVersion`: `1`;
- `LSMinimumSystemVersion`: `14.0`;
- `LSUIElement`: boolean true;
- `NSHighResolutionCapable`: boolean true.

### 10.2 Direct build script

`scripts/build-app.sh` must:

1. use `set -euo pipefail` and change to the repository root;
2. recreate only `build/BitPrice.app` with `Contents/MacOS` and `Contents/Resources`;
3. collect `Sources/BitPrice/**/*.swift` with null-delimited `find` output and fail if none exist;
4. invoke `swiftc` directly with `-parse-as-library`, `-swift-version 6`, `-warnings-as-errors`, optimization, `-target arm64-apple-macosx14.0`, and `-sdk "$(xcrun --show-sdk-path)"`;
5. write the executable to `Contents/MacOS/BitPrice` and copy `Info.plist` to `Contents/Info.plist`;
6. run `plutil -lint` on the bundled plist;
7. ad-hoc sign with `codesign --force --sign -`;
8. run `codesign --verify --verbose=2` on the app and `otool -L` on the executable;
9. print `open build/BitPrice.app` as the launch command.

The script must not create or invoke `Package.swift`, `swift build`, or a bare executable launch. Ad-hoc signing is for this local personal build only; distribution requires Developer ID signing and notarization.

## 11. Mechanism accountability ledger

This table is normative. It identifies every important mechanism’s inputs and the actual API that performs its operation.

| Mechanism | Interface member supplying every input | Concrete operation/API |
|---|---|---|
| Initial/set-change/empty/restart Binance lifecycle | `AppModel` derives exact persisted Binance IDs and calls `BinanceFeedController.replaceProducts(_:)` | `URLComponents`; `URLSession.webSocketTask(with:)`; `resume()`; `cancel(with:reason:)` |
| Old-connection exclusion | Controller-owned `configurationID`, `connectionID`, and IDs captured by each owned task | Main-actor equality check after every `await`, before state/sink mutation; `Task.cancel()` for old work |
| Autonomous retry | Current product set, configuration UUID, receive error, and controller-owned attempt index | `SuspendingClock.sleep(for:)`, then private current-ID-checked connect |
| Retry reset and cap | Current connection reaching lease completion with matching delegate-open age at least 60 awake seconds, or exact set/wake transition; saturating attempt index | `didOpen`-recorded `SuspendingClock.Instant`, current-ID-checked lease completion, controller state update; delays 1/2/4/8/16/30 |
| Half-open bound | Current connection UUID and five-minute lease task | `SuspendingClock.sleep(for:)`; `URLSessionWebSocketTask.cancel(with:reason:)`; private replacement connect |
| Quiet-product distinction | Per-item quote `receivedInstant`; no product-silence reconnect input exists | `ContinuousClock.now` age comparison; fallback reconciliation only |
| Connection observability | Current integer task ID, read-only controller `state`, and `feedStateDidChange` sink member | `URLSessionWebSocketDelegate.didOpen`/`didClose` on `OperationQueue.main`; current-ID check; main-actor state transition |
| Sleep/wake | `NSWorkspace` notification translated to sleep/wake enum | `NSWorkspace.shared.notificationCenter`, `OperationQueue.main`, task cancellation, socket close/restart |
| Search late-result exclusion | AppModel query UUID captured by search task | `Task.cancel()` plus UUID equality before publishing results |
| Venue mapping identity | User-confirmed exact candidate IDs passed to `commitEdit` | Binance `exchangeInfo`, Coinbase `products`, JSON persistence; never symbol derivation |
| Coinbase fallback eligibility | Item mappings, controller state, per-item Binance quote age | AppModel’s 60-second reconciliation loop and immediate transition checks |
| Slow fallback exclusion | `FallbackRequestToken` with request/item/product/revision/start inputs | `Task.cancel()`, token equality, `ContinuousClock` elapsed check before quote/alert application |
| 24-hour chart | Mapping product ID and explicit wall start/end from chart request | Binance `/api/v3/klines` or Coinbase `/candles`; timestamp sort/filter; SwiftUI `Path`/`Canvas` |
| Structural persistence | Complete draft supplied to `PersistenceStore.save(_:)` | `JSONEncoder`; `FileManager.createDirectory`; `Data.write(options: .atomic)` |
| Corrupt/newer preservation | Persistence mode set by version probe/decode/validator | All save paths reject in recovery; only `reset()` calls atomic replace |
| Schema migration | `VersionProbe` selects version-specific DTO; v0 optional latch fields | `JSONDecoder.decode`; pure v0-to-v1 transform; validator; atomic v1 save |
| Alert re-arm durability | Evaluator result and complete draft state | `PersistenceStore.save(_:)` before publishing `isArmed = true` |
| Alert fire durability | Accepted quote, alert, one captured wall `Date`, and complete draft | Atomic save of disarmed/date state, then `UNUserNotificationCenter.add` |
| Single instance | Fixed lock path and process-lifetime descriptor | Darwin `open`, `flock(LOCK_EX | LOCK_NB)`, `close` on shutdown |
| Three-state presentation | Current per-row quotes, continuous ages, Binance state, Coinbase request states | AppModel computed property; SwiftUI observes only `live/stale/offline` |

If implementation work discovers a mechanism whose required input or operation is absent from this table and its owning interface, the implementer must stop and revise the specification rather than invent a hidden channel.

## 12. Focused acceptance verification

Tests use injected wall/continuous/suspending clocks, mock URL loading, a temporary Application Support root, and controllable socket adapters. Public-network smoke tests are separate from deterministic acceptance tests.

1. **Strict bundle build:** compile the entire source tree with the specified Swift 6/warnings-as-errors flags; lint plist, verify signature, inspect links, and launch the bundle in an Aqua session with one menu item and no Dock icon.
2. **Atomic instance ownership:** start two processes against one temporary support directory simultaneously; exactly one acquires `flock`, and the loser exits before reading or changing JSON. Crash the winner and verify a later process can acquire the kernel-released lock.
3. **First launch and valid empty state:** missing JSON persists only curated BTC; deleting it persists an empty list; relaunch remains empty with no Binance, fallback, candle, or freshness task.
4. **Immediate edit durability:** add/reorder/set primary and terminate immediately after the method returns; every successful edit is present after relaunch. Force a write error and verify neither UI state nor networking changes.
5. **Root validation and preservation:** fixtures with duplicate item IDs, CoinGecko IDs, either venue product ID, dangling/missing primary, no mapping, 26 items, or oversized combined URL enter recovery; subsequent edit and alert attempts leave original bytes unchanged; only successful Reset replaces them.
6. **Schema migration:** an actual v0 JSON fixture missing `schemaVersion`, `isArmed`, and `lastFiredAt` migrates with the alert disarmed and persists v1. A v1 alert missing/null `isArmed`, a newer version, and an unregistered older positive version enter recovery without overwrite.
7. **Search ordering and rate gate:** 300 ms of awake quiet issues one encoded query; empty/cancelled/older UUID results cannot publish; sleep cancels rather than completes debounce; 429 handles integer and HTTP-date `Retry-After` through sleep.
8. **Venue confirmation and bounds:** shared `SOL` results remain distinct; even one candidate requires explicit confirmation; both “No market” is rejected; exact dual IDs survive relaunch; duplicate IDs, item 26, and a URL over 2,048 bytes are rejected before save.
9. **Product lifecycle:** nonempty start, changed-set replacement, same-set no-op, empty stop, and later restart all use one controller instance. Reorder, primary, alert, and Coinbase-only edits call `replaceProducts` but do not change connection identity when the set is equal. A set replacement while suspended starts nothing; wake starts the retained nonempty set exactly once, while a retained empty set stays stopped.
10. **Superseded result race:** hold an old `receive()` completion, replace the set, then deliver old ticker and failure. Both fail connection-ID checks and cannot touch quote or state. Deliver a current ticker and verify it applies synchronously. No `AsyncStream`, consumer epoch, or purge operation exists.
11. **Autonomous retry and bound:** repeated accept-optional-tick-close cycles shorter than five minutes walk 1/2/4/8/16/30 and remain at 30; neither socket acceptance nor a valid tick resets the counter. A connection reaching lease completion resets only when matching delegate-open age is at least 60 awake seconds; a hung handshake and one opening in the final minute preserve the count. A product-set change and wake reset independently; only one retry task exists.
12. **Half-open and quiet product:** in a two-product session, make one product update every 90 seconds and keep the other active. The 90-second item is not reconnected or marked dead. Freeze the entire socket; rows become stale/fallback by quote age and the five-minute lease replaces the connection exactly once. A set change during lease sleep makes the old lease harmless.
13. **Lifecycle observability:** assert stopped/connecting/connected/backingOff/suspended directly from matching delegate open/close and controller transitions; deliver late delegate calls for an old integer task ID and prove they do nothing; assert UI exposes only live/stale/offline and never reconstructs state from event history.
14. **Binance parsing:** accept a valid combined ticker and reject unknown product, wrapper/symbol mismatch, invalid/null/nonpositive price, non-finite percent, malformed event time, binary garbage, messages over 1 MiB, and stale-connection messages.
15. **Coinbase contract:** compute percent only for `open > 0`; invalid/missing/nonpositive open renders `—`; Coinbase-only items poll immediately without a Binance failure; no mapping shows “No fallback market.”
16. **Slow fallback race:** hold Coinbase completion, accept a newer Binance tick, then complete Coinbase. Token/revision checks reject it and it cannot change source or evaluate an alert. Also reject a response completing after 15 continuous seconds and a response for a remapped item.
17. **Truthful chart and HTTP boundary:** requests use exact 24-hour bounds and timestamped 1h candles; points outside the range and duplicates are removed, ordering is chronological, gaps over 90 minutes break the path, flat/two-point/empty inputs render safely, and no test treats “last 24 un-timestamped points” as 24 hours. Every REST client rejects non-2xx and bodies over 64 MiB before decoding and enforces a 15-second request timeout.
18. **Sleep and clocks:** simulate eight-hour sleep. Quotes/charts become stale, socket is closed then newly connected, periodic work executes once immediately and never replays missed cycles, backoff does not complete asleep, and pre-sleep search cannot fire.
19. **Alert boundary table:** test above/below breach, equality, both re-arm formulas and boundary equality, zero hysteresis, disabled state, material vs cooldown-only edits, and re-arm during cooldown. Cooldown gates firing only.
20. **Durable alert transactions:** crash simulations before save, after atomic fire save, and before notification prove no duplicate; re-arm save survives restart; forced fire/re-arm write failure rolls back and fire sends no notification; a later qualifying tick can retry.
21. **Notification boundary:** permission is requested on first enable, not launch; durable fire precedes `add`; denial/submission failure reports error without changing latch. Manual Aqua-session smoke test records presentation but does not redefine core correctness.
22. **Presentation and formatting:** source switch changes quote asset both ways, unavailable change stays `—`, stale rows dim, aggregate worst-state rules hold, menu title formatting matches §2.1, and empty/no-primary-quote displays `BitPrice`.
23. **Packaging prohibitions:** repository has no `Package.swift`; scripts never invoke `swift build`; launching the bundled app is the documented path and the build verifies `LSMinimumSystemVersion=14.0` and arm64 linkage.

Implementation is accepted when deterministic tests 1–20 and 22–23 pass, strict build passes, and test 21’s programmatic authorization/submission cases pass. Actual notification presentation remains a recorded manual observation because the measured host has no Aqua GUI session.

## 13. Deliberate omissions and accepted limits

- **No buffered feed stream or consumer epoch.** Previous designs could not atomically hand off authorization or purge `AsyncStream` buffers. Main-actor identity checking removes both mechanisms.
- **No health-reconnect command.** A delayed external repair request needs a connection identity and can tear down a healthy successor. The owning controller’s lease and retry paths perform all replacement internally.
- **No per-product dead detector.** Tick cadence cannot reliably distinguish a quiet product. Quiet rows may become stale and use fallback; they do not churn the combined socket.
- **Five-minute planned reconnects.** This bounds otherwise invisible half-opens but briefly interrupts healthy sockets and may take almost five awake minutes to repair one.
- **No application Ping loop.** Foundation handles server control frames and Binance counts client control traffic. The app does not pretend it can observe framework Pong state.
- **No dynamic subscribe/ack protocol.** Product changes rebuild the combined URL, briefly interrupting all Binance rows but avoiding desired/confirmed/ack state.
- **Watchlist capped at 25.** Larger lists are rejected. This bounds combined URL size, per-item candle requests, UI load, and synchronous persistence cost.
- **Per-item candle requests.** CoinGecko batching is intentionally unused because it lacks timestamped spacing. Up to 100 venue candle requests/hour are accepted; quiet Coinbase periods can leave visible chart gaps.
- **Immediate synchronous saves.** Small full-state writes may cause a short main-thread hitch. They eliminate edit-loss debounce and async write ordering.
- **No notification history.** A crash after durable fire but before notification submission, Focus, denial, or OS suppression can hide a fire. Durable latch state still prevents duplicates.
- **Coinbase polling can miss brief breaches.** The editor discloses the 60-second granularity.
- **Immediate Binance failback can flap.** The first valid Binance tick wins; no dwell or source holdout is implemented.
- **Retry has no circuit breaker.** A long outage continues at one attempt every 30 awake seconds.
- **User confirmation can be wrong.** IDs are exposed, but the app makes no cryptographic cross-venue identity claim.
- **Backward wall-clock changes can extend cooldown.** Negative age is clamped, preventing early fire but not delayed re-eligibility.
- **Ad-hoc signing is local-only.** Distribution and notarization are outside this version.

## 14. Protocol references

- Binance Spot WebSocket streams: `https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md`
- Binance Spot REST klines: `https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md`
- Coinbase Exchange product candles: `https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles`
- Apple `URLSessionWebSocketTask`: `https://developer.apple.com/documentation/foundation/urlsessionwebsockettask`
