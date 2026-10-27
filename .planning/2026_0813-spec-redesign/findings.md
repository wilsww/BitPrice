# Findings and decisions — redesign

## Fixed inputs

- This is a specification-only redesign; no Swift implementation is authorized.
- The existing specification is evidence, not a coherent design. Its measured platform/API facts must survive, but its mechanisms may be discarded.
- The critical review rule is structural: every mechanism must identify the interface member supplying every input and the concrete platform API performing every operation.
- The venue-confirmation workflow is retained: a CoinGecko identity and an exchange product are distinct, ticker equality is only a candidate filter, and exact confirmed product IDs are persisted.

## Initial design direction to validate

- Avoid a cross-actor buffered event stream for Binance. Keep the socket controller and UI model in the same `@MainActor` serialization domain, and guard every post-suspension result with controller-owned connection identity. This eliminates stale-event filtering rather than attempting to repair it with epochs or barriers.
- Treat health at per-product granularity; connection silence alone cannot identify a dead product, and a low-volume product cannot be judged by a fixed message interval.
- Use atomic full-file replacement for persisted state and serialize alert evaluation with the persistence commit so notification occurs only after durable latch state.

## Rejected alternatives (provisional)

- Consumer-held epoch: producer changes epochs during autonomous retry, so the consumer cannot reliably acquire authorization state.
- In-band `AsyncStream` supersession barrier: `AsyncStream.Continuation` cannot purge buffered values, and a serial consumer necessarily commits earlier buffered values before observing a later barrier.
- Session-wide missing-tick health: the defect to detect is per product and legitimate trade cadence varies.

## Today’s two-lens rejection

Both lenses independently establish the same structural failures:

- A post-hoc ordered barrier cannot revoke values already dequeued or committed. `AsyncStream.Continuation` has no purge or transaction operation.
- A parameterless health reconnect cannot bind a delayed request to the connection it diagnosed; it can tear down a healthy autonomous successor.
- Consumer-observed status is not actor-authoritative current state, and stale lifecycle events can corrupt UI state just like stale quotes.
- A fixed missing-ticker interval has no documented relationship to market activity, so it confuses quiet products with dead ones.
- The retry counter is client/session-wide while the evidence was per-product, and product-set replacement did not define rekey/reset behavior.
- Lifecycle observability was incomplete: connecting/backoff/stopped were not supplied, yet downstream behavior required those distinctions.
- The previous document directly contradicted itself about both `FeedEvent.epoch` and caller-vs-client product-set comparison.

### Consequence for the redesign

Move the half-open decision and health-triggered reconnect into the same actor that owns the current socket. This removes the delayed cross-actor repair interface entirely. Publish read-only snapshots, not a buffered sequence of actionable lifecycle events. Product-set idempotence belongs solely inside the owner actor.

## Prior specification facts retained from §§1–3

- UI: menu label fallback, window-style menu-bar panel, per-row source-aware quote asset, unavailable change as `—`, first-launch BTC seed, persisted empty list, UUID primary selection, and duplicate CoinGecko ID prohibition.
- Mapping: at least one explicitly confirmed venue; exact Binance/Coinbase product IDs persist; duplicate product IDs per venue are invalid; built-in BTC is the one curated confirmation.
- Data sources: Binance combined `@ticker` for live price/change, Coinbase `/products/{id}/stats` for fallback, one CoinGecko `coins/markets?sparkline=true` batch, CoinGecko search, and venue catalogs for candidate selection.
- Coinbase change is computed only when `open > 0`; otherwise unavailable. Fallback eligibility includes Coinbase-only rows.
- REST clients require 2xx, URL construction/escaping, numeric validation, and bounded requests. CoinGecko 429 is client-wide.
- Persistence needs custom root/version decoding and version-aware alert decoding. A missing non-optional property fails synthesized `Decodable`; schema 0 must supply the historical latch default, while current-schema omissions are malformed.

## Prior mechanisms not retained

- The old “last 24 points” sparkline rule cannot truthfully claim 24 hours because the values have no timestamps and spacing/count are not contractual. The redesign uses timestamped venue candles and does not use the CoinGecko sparkline payload.
- The old 60-second per-product no-tick rule is unsupported and rejected. Apple’s `sendPing` exists but is disallowed here by the measured no-application-ping constraint. A five-minute connection lease is the selected bounded mitigation; market tick arrival remains quote freshness, not transport liveness.

## Review-history lessons from rounds 1–4

- Combined URL rebuilding is simpler than dynamic subscribe/unsubscribe because the latter requires desired/confirmed/in-flight sets, request identities, acknowledgements, acknowledgement timeouts, and generation-scoped reconciliation. Those mechanisms were later removed for complexity; the redesign keeps combined URLs.
- One valid tick is not proof that every product stream is healthy, but “every product must tick” has no justified time bound. Transport health and per-product quote freshness must be separate concepts.
- Alert correctness is about ordering, not merely data fields: update latch and last-fire date, durably replace the complete state, then submit a notification. Re-arm uses the same durable transition. Persistence failure means rollback and no notification.
- Cross-actor framework callbacks must convert payloads to owned `Sendable` values before actor hops; do not use broad `@unchecked Sendable`, `@preconcurrency`, or `Task.detached` as escape hatches.
- A compact specification should not reintroduce optional complexity (rich per-source states, history, dynamic subscription acknowledgements) unless it prevents a required concrete failure.

## Ground-up architecture decisions

### Concurrency boundary

- `AppModel` and `BinanceFeedController` are both `@MainActor`. The controller uses one owned `Task` and calls `URLSession.webSocketTask(with:)`, `resume()`, async `receive()`, and `cancel(with:reason:)`.
- Every suspension point resumes on the main actor and checks the task’s captured connection UUID against the controller’s current UUID before mutating connection state or applying a quote. Product replacement changes the UUID synchronously before cancellation. There is no cross-actor epoch handoff and no buffered app-level event channel.
- The controller owns its authoritative detailed state (`stopped`, `connecting`, `connected`, `backingOff`, `suspended`) and exposes a read-only property to `AppModel`; UI maps it to only `live`, `stale`, or `offline`.
- WebSocket handshake state comes from the platform’s `URLSessionWebSocketDelegate.didOpen`/`didClose` callbacks on a main delegate queue. The adapter extracts only the integer `taskIdentifier` and sendable failure fields; the controller rejects IDs that are no longer current. `resume()` alone is not treated as proof of connection.

### Half-open handling

- Apple exposes `URLSessionWebSocketTask.sendPing`, but using it periodically would be the explicitly forbidden application ping loop and consumes Binance control-message budget. It will not be used.
- No documented application-visible Pong or per-product maximum ticker interval exists at the message boundary. Therefore the app will not claim traffic silence detects a dead product.
- Instead, every awake connection has a fixed `SuspendingClock` lease and is replaced unconditionally when the lease expires. This bounds a silently half-open socket without classifying quiet products as dead. Sleep explicitly closes the task; wake starts a new lease. Per-product quote age controls stale presentation/fallback only and never triggers socket repair.
- This is deliberately a mitigation rather than a fictional detector: a half-open may remain until lease expiry, and a listed but quiet product may show stale/fallback without causing connection churn.
- Official Binance documentation labels individual `@ticker` “Update Speed: 1000ms,” but does not state a hard maximum delivery gap or say the update is emitted when statistics do not change. Given the task’s confirmed 90-second quiet-market case, this label is not sufficient evidence for a per-product deadline.
- Binance documents server Ping frames every 20 seconds and a required Pong within one minute, but `URLSessionWebSocketTask` handles those below the app’s `.string`/`.data` boundary. The app has no API to inspect the framework-managed Pong, so it cannot use that fact as an application-visible health timestamp.

### Retry granularity

- Retry state belongs to the exact normalized Binance product set. A changed set (including empty-to-nonempty) creates a new configuration generation and resets attempts because failures from the prior URL are irrelevant.
- Same-configuration failures before a connection reaches its five-minute lease end walk 1/2/4/8/16/30 seconds and remain capped. Reset at lease completion additionally requires at least 60 awake seconds since matching delegate `didOpen`; a hung or last-second handshake is not stable evidence. Neither socket acceptance alone nor an early valid message resets attempts; otherwise an accept-one-tick-close peer could churn at one second. Exact set replacement or wake also resets. Product silence does not initiate repair, so one product cannot create an unbounded health-repair loop.

### Sparkline correctness

- CoinGecko’s batched `sparkline_in_7d` has neither per-point timestamps nor contractual spacing, so it cannot prove a 24-hour window. It will not be used for the required chart even though its measured batch capability is retained as a fact.
- Use timestamped one-hour venue candles over an explicit `[now-24h, now]` range: Binance `/api/v3/klines` for Binance-mapped items and public Coinbase Exchange `/products/{id}/candles` for Coinbase-only items. Coinbase documents timestamped buckets, one-hour granularity, up to 300 points, and possible missing intervals for quiet products. Missing buckets remain gaps; they are not fabricated.
- This costs one REST request per item per refresh. The watchlist cap and a 15-minute refresh bound it to at most 100 requests/hour at 25 items. The accepted tradeoff is loss of CoinGecko batching in exchange for an honest 24-hour axis.
- Official Binance REST documentation supplies kline open/close timestamps, one-hour intervals, weight 2, and a 1000-point maximum. Official Coinbase Exchange documentation supplies timestamped one-hour buckets, a 300-point maximum, and explicitly warns that quiet intervals may be absent. These are concrete inputs for a truthful time axis.

### Persistence and single instance

- Remove structural-save debounce. Every user edit is a small, immediate, full-state atomic transaction; failed writes do not publish the edit. This eliminates termination-window data loss and the need for a flush hook.
- Acquire an atomic process lock before loading state using Darwin `open` plus nonblocking `flock(LOCK_EX | LOCK_NB)` on an Application Support lock file; retain the descriptor until exit. This replaces the rejected `NSRunningApplication` check-then-act.

## Round-7 open-defect disposition

| Open defect | Disposition |
|---|---|
| Unbounded list and single URLs | Designed away: hard cap 25, prospective Binance combined URL capped at 2,048 UTF-8 bytes, and CoinGecko IDs are no longer batched into a URL. |
| Debounced save lost at termination | Designed away: no debounce; every successful edit completes an immediate atomic full-state save before publication. |
| Slow Coinbase overwrites Binance / evaluates stale alert | Designed away: request token includes item, product, request UUID, market revision, and continuous start; completion must still be eligible, current, unchanged, and at most 15 seconds old before quote or alert use. |
| Root invariants not validated | Designed away: one validator checks all unique IDs, mappings, primary reference, bounds, alert values, and URL length after decode and before every save. |
| Timestamp-free points claimed as 24h | Designed away: CoinGecko points are not used; timestamped one-hour venue candles are filtered to an explicit 24-hour interval and gaps remain gaps. |
| Non-atomic single-instance check | Designed away: Darwin `flock(LOCK_EX | LOCK_NB)` is acquired before JSON load and held for process life. |

## Accepted limits

- A connection half-open can remain until the five-minute awake lease expires; planned rotations briefly interrupt healthy sockets.
- Up to 100 per-item candle requests/hour replace one CoinGecko batch so the chart can have a truthful time axis.
- Immediate main-actor atomic saves may cause a short UI hitch for the bounded small file.
- No notification history means a durable fire can be invisible if the process crashes before submission or macOS suppresses it.
- Coinbase polling can miss a breach shorter than its 60-second interval; immediate Binance failback may flap.
- Backward wall-clock movement can extend but cannot shorten an alert cooldown.
- User-confirmed market identity can still be wrong; exposing exact IDs makes the error inspectable.

## Final audit result

- Every measured fact is present in `SPEC.md`.
- The seven named design problems are resolved by concrete owning interfaces and platform operations; none is deferred.
- Every timed quantity found in the document is assigned a wall, continuous, suspending, request-timeout, or server-timestamp domain.
- All six round-7 open defects are designed away rather than accepted.
- The final specification contains no Swift implementation code, placeholder, unbalanced code fence, or dependency on the prior specification.
- The pre-existing root `IMPLEMENTATION.md`, `task_plan.md`, `findings.md`, and `progress.md` were read but not edited during this redesign.

## Tooling note

- `rg` is unavailable on this host; repository inspection uses `find`, `grep`, and `sed`.
