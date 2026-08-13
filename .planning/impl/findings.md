# BitPrice implementation findings

## Required constraints

- No SwiftPM or `Package.swift`; all production and test compilation uses `swiftc` directly.
- Swift 6 strict concurrency, warnings as errors, arm64, target `arm64-apple-macosx14.0`.
- The executable must live in an ad-hoc-signed `.app` with `LSUIElement=true` and minimum macOS 14.0.
- App launch, notification presentation, and live network behavior cannot be verified without an Aqua session/network acceptance run.
- Preserve the redesign choices: no `AsyncStream` feed buffer, consumer epoch, dynamic subscription protocol, app ping loop, or ticker-silence reconnect.

## Defect-resolution ledger

| # | Resolution | Code / evidence |
|---:|---|---|
| 1 | One WebSocket session is created once per controller and invalidated only at shutdown. The controller and delegate both register task ID → connection UUID, and callbacks verify both. | `BinanceFeedController.init`, `taskConnectionRegistry`, `WebSocketDelegateAdapter.register`; tests 09–10, 13 |
| 2 | All substitutable dependencies have minimal constructor-injected protocols: wall/continuous/suspending clocks, HTTP transport, request pacer, WebSocket factory/session/task, atomic writer/support root, feed sink, and notifications. Production composition is explicit. | `DomainModels.swift` protocols, `AppModel.production()`; fakes in `Tests/TestMain.swift` |
| 3 | One Coinbase `TokenBucketPacer` is shared by catalogs (highest priority), stats, and candles, at 10/s burst 15. A 429 blocks the entire gate via `Retry-After` or 60 seconds. Binance uses one weighted client gate (catalog cost 20, klines cost 2) with shared 418/429 backoff. | `TokenBucketPacer`, `RESTClients`; test 08b |
| 4 | Every chart request carries request/item/venue/product/revision/exact-bounds authorization. Superseded work is canceled and equality is checked immediately after the REST await and immediately before publication. | `ChartRequestToken`, `AppModel.refreshChart`; test 17b |
| 5 | Every REST transport operation is raced against an injected continuous-clock 15-second cancellation task; `URLRequest.timeoutInterval` remains a secondary idle/resource guard. | `RESTClients.load`; test 16 |
| 6 | Exact v0/v1 DTOs pin every key. Decimals are JSON strings, UUID/enums are strings, dates are ISO-8601, optional nested values may be absent/null, and v1 root always emits `primaryItemID` (null when absent). Migration is the pure `migrateV0ToV1`. | `PersistenceStore.swift`, canonical `Tests/Fixtures/watchlist-v{0,1}.json`; test 06 |
| 7 | Current schema remains 1. The impossible positive-older fixture was dropped. The unregistered-older branch remains and is tested by simulating current version 2; the source comment explains why. | `schemaDispatch`; test 07 |
| 8 | Coinbase `last` is required, positive, and numeric. `open` is lossy-optional: absent/null/malformed/zero/negative accepts the quote with `.unavailable`, never a fabricated percentage. | `CoinbaseStats`, `coinbaseStats`; test 15 |
| 9 | `transportFailureAttempt` is controller/client-wide and is not reset on product changes or wake. Those transitions may connect promptly but retain earned outage history. Only a sufficiently stable five-minute lease resets it. | `BinanceFeedController.replaceProducts`, `resumeAfterWake`, lease; test 11 |
| 10 | Chart selection follows the active quote when its mapping exists. Every rendered series independently labels its venue and quote asset, so a retained/loading mismatch is disclosed. | `AppModel.chartSelection`, `WatchRow` label |
| 11 | `AlertDecision` includes item UUID and exact expected alert. Apply rechecks both before mutation. | `AlertDecision`, `AppModel.applyAlertDecision`; tests 19, 21 |
| 12 | REST bodies over 64 MiB are rejected before decoding and each WebSocket task receives a 1 MiB `maximumMessageSize`, with a second application-level size check. | `RESTClients.load`, `BinanceFeedController.connect/accept`; tests 12, 18 |
| 13 | Structural edits and fire/rearm are synchronous main-actor full-state read/validate/atomic-write/publish transactions with no `await`; notification submission starts only afterward. | `AppModel.commitEdit`, `applyAlertDecision`; tests 04, 21 |
| 14 | `ProcessLock` retains its descriptor until deinit. Atomic replacement targets sibling `watchlist.json`, never `instance.lock`. | `ProcessLock`, `PersistenceStore`; tests 02, 04 |
| 15 | The real HTTP adapter converts framework values/errors to sendable values internally. Every REST method checks size and non-2xx before private DTO decode, validates numerics/timestamps, and exposes domain values only. | `SystemHTTPTransport`, `RESTClients`; tests 15–18 |

### Rate-bound correction

“Immediate” means enqueued immediately. Fifty Coinbase launch requests drain in bounded paced time. There is no honest fixed hourly bound for user-driven add/wake traffic: sequential adds alone enqueue 325 candle calls (`1+...+25`), plus stats and wakes. The 100/hour figure applies only to the steady 15-minute candle cadence at 25 rows.

## Architecture ownership

- `AppModel`: wall clock, continuous clock, persistence store, notifications, all UI/request tokens and periodic tasks.
- `BinanceFeedController`: sink attachment, suspending/continuous clocks, one lifetime WebSocket session, socket identities and transport backoff.
- REST client suite: typed HTTP transport, continuous clock/deadline race, and shared venue pacers.
- Production composition: `BitPriceApp` constructs system implementations; tests construct fakes.

## Additional specification defects

- §12 test 1 requires launching in an Aqua session, while §1 and the task’s host facts say this machine has no Aqua GUI session. The implementation follows the task override: compilation/package checks run automatically and launch/UI presence is explicitly skipped, never reported as passed.
- The Command Line Tools image contains no XCTest framework or `xctest` runner. This is an environment limitation rather than a product-spec semantic defect; the separate target therefore uses a small assertion harness.

## Deviations from `SPEC.md`

- Product-set changes and wake do **not** reset Binance transport backoff, overriding §5.3/§5.4 and §12 test 11 per confirmed defect 9.
- Charts are not permanently Binance-first. They follow the active quote when possible and always show an independent venue/asset label, overriding §6.3 per defect 10.
- Coinbase malformed/missing `open` is accepted as unavailable change, overriding the general malformed-required-field wording in §6.1 per defect 8.
- The specification’s undefined v0/v1 nested wire shape is concretized by the DTOs/fixtures above; no specification file was changed.
- The stated blanket candle hourly bound is narrowed to steady periodic cadence; add/wake work is paced but user-driven and therefore has no fixed hourly total.
- The automatic launch part of acceptance is skipped for lack of Aqua; it was not attempted.
