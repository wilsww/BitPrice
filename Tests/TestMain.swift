import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

struct FixedWallClock: WallClock {
    let value: Date
    func now() -> Date { value }
}

struct FixedContinuousClock: ContinuousTimeSource {
    let value = MonotonicInstant(offset: .zero)
    func now() -> MonotonicInstant { value }
    func sleep(for seconds: TimeInterval) async throws {
        try await ContinuousClock().sleep(for: .seconds(seconds))
    }
}

struct ImmediateContinuousClock: ContinuousTimeSource {
    func now() -> MonotonicInstant { MonotonicInstant(offset: .zero) }
    func sleep(for seconds: TimeInterval) async throws {}
}

struct FixedSuspendingClock: SuspendingTimeSource {
    func now() -> MonotonicInstant { MonotonicInstant(offset: .zero) }
    func sleep(for seconds: TimeInterval) async throws {
        try await ContinuousClock().sleep(for: .seconds(seconds))
    }
}

actor NoopPacer: RequestPacer {
    private(set) var acquisitions: [(RESTRequestPriority, Int)] = []
    private(set) var backoffs: [TimeInterval] = []

    func acquire(priority: RESTRequestPriority, cost: Int) {
        acquisitions.append((priority, cost))
    }

    func applyRateLimitBackoff(seconds: TimeInterval) {
        backoffs.append(seconds)
    }
}

actor StubHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponseData]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [HTTPResponseData]) { self.responses = responses }

    func response(for request: URLRequest) async throws -> HTTPResponseData {
        requests.append(request)
        guard !responses.isEmpty else {
            throw NetworkFailure(domain: "test", code: 1, message: "No stub response")
        }
        return responses.removeFirst()
    }

    func capturedRequests() -> [URLRequest] { requests }
}

actor HangingHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponseData {
        try await ContinuousClock().sleep(for: .seconds(3_600))
        throw NetworkFailure(domain: "test", code: 2, message: "Unexpected wake")
    }
}

actor DelayedHTTPTransport: HTTPTransport {
    private var pending: [CheckedContinuation<HTTPResponseData, any Error>] = []
    private(set) var requests: [URLRequest] = []

    func response(for request: URLRequest) async throws -> HTTPResponseData {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    func pendingCount() -> Int { pending.count }

    func completeFirst(_ response: HTTPResponseData) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: response)
    }
}

struct FailingWriter: AtomicFileWriting {
    func write(_ data: Data, to url: URL) throws {
        throw NetworkFailure(domain: "test-write", code: 1, message: "forced write failure")
    }
}

enum FakeSocketError: Error { case cancelled }

@MainActor
final class FakeSocket: WebSocketTaskTransport {
    let taskIdentifier: Int
    var maximumMessageSize = 0
    private(set) var resumeCount = 0
    private(set) var cancelCount = 0
    private var pending: CheckedContinuation<WebSocketInboundMessage, any Error>?
    private var queued: [WebSocketInboundMessage] = []

    init(id: Int) { taskIdentifier = id }
    func resume() { resumeCount += 1 }

    func receive() async throws -> WebSocketInboundMessage {
        if !queued.isEmpty { return queued.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in pending = continuation }
    }

    func enqueue(_ message: WebSocketInboundMessage) {
        if let pending {
            self.pending = nil
            pending.resume(returning: message)
        } else {
            queued.append(message)
        }
    }

    func cancel() {
        cancelCount += 1
        if let pending {
            self.pending = nil
            pending.resume(throwing: FakeSocketError.cancelled)
        }
    }
}

@MainActor
final class FakeWebSocketSession: WebSocketSessionTransport {
    private(set) var sockets: [FakeSocket] = []
    private(set) var urls: [URL] = []
    private(set) var invalidationCount = 0
    var nextIdentifier = 1

    func makeTask(url: URL) -> any WebSocketTaskTransport {
        let socket = FakeSocket(id: nextIdentifier)
        nextIdentifier += 1
        sockets.append(socket)
        urls.append(url)
        return socket
    }

    func invalidate() { invalidationCount += 1 }
}

@MainActor
final class FakeWebSocketFactory: WebSocketSessionFactory {
    let session: FakeWebSocketSession
    private(set) var creationCount = 0
    init(session: FakeWebSocketSession) { self.session = session }
    func makeLifetimeSession(delegate: any WebSocketDelegateReceiving) -> any WebSocketSessionTransport {
        creationCount += 1
        return session
    }
}

@MainActor
final class TestFeedSink: BinanceFeedSink {
    private(set) var ticks: [BinanceTick] = []
    private(set) var states: [BinanceLifecycle] = []
    func feedDidAccept(_ tick: BinanceTick) { ticks.append(tick) }
    func feedStateDidChange(_ state: BinanceLifecycle) { states.append(state) }
}

@MainActor
final class FakeNotifications: NotificationSubmitting {
    private(set) var permissionRequests = 0
    private(set) var submissions: [(UUID, String, Decimal, Date)] = []

    func requestAuthorization() async -> Result<Bool, NetworkFailure> {
        permissionRequests += 1
        return .success(true)
    }

    func submit(itemID: UUID, symbol: String, price: Decimal, firedAt: Date) async -> Result<Void, NetworkFailure> {
        submissions.append((itemID, symbol, price, firedAt))
        return .success(())
    }
}

@MainActor
struct AcceptanceTest {
    let name: String
    let body: @MainActor () async throws -> Void
}

@main
struct BitPriceTests {
    @MainActor
    static func main() async {
        let tests = makeTests()
        var failures = 0
        for test in tests {
            do {
                try await test.body()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }
        print("SKIP notification presentation: no Aqua GUI session is available on this host")
        print("SKIP app launch/UI presence: no Aqua GUI session is available on this host")
        print("RESULT \(tests.count - failures) passed, \(failures) failed, 2 skipped")
        if failures != 0 { exit(EXIT_FAILURE) }
    }

    @MainActor
    static func makeTests() -> [AcceptanceTest] {
        [
            AcceptanceTest(name: "01 strict domain validation") {
                let seed = PersistedState.bitcoinSeed(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
                try validatePersistedState(seed)
                try expect(seed.items.count == 1, "seed count")
            },
            AcceptanceTest(name: "02 atomic process lock ownership") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let first = try ProcessLock(rootDirectory: root)
                do {
                    _ = try ProcessLock(rootDirectory: root)
                    throw TestFailure(description: "second lock unexpectedly succeeded")
                } catch ProcessLockFailure.alreadyRunning {}
                withExtendedLifetime(first) {}
            },
            AcceptanceTest(name: "03 first launch and persisted empty state") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                guard case .firstLaunch(let seed) = store.load() else { throw TestFailure(description: "not first launch") }
                try store.save(seed)
                try store.save(PersistedState(schemaVersion: 1, items: [], primaryItemID: nil))
                guard case .loaded(let empty) = store.load() else { throw TestFailure(description: "empty state did not load") }
                try expect(empty.items.isEmpty && empty.primaryItemID == nil, "empty state reseeded")
            },
            AcceptanceTest(name: "04 atomic write failure preserves prior bytes") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let normal = try PersistenceStore(rootDirectory: root)
                let seed = PersistedState.bitcoinSeed()
                try normal.save(seed)
                let before = try Data(contentsOf: normal.stateURL)
                let failing = try PersistenceStore(rootDirectory: root, writer: FailingWriter())
                do { try failing.save(PersistedState(schemaVersion: 1, items: [], primaryItemID: nil)) }
                catch {}
                let after = try Data(contentsOf: normal.stateURL)
                try expect(after == before, "failed save changed bytes")
            },
            AcceptanceTest(name: "05 root invariant rejection") {
                let seed = PersistedState.bitcoinSeed()
                var duplicate = seed
                duplicate.items.append(seed.items[0])
                do { try validatePersistedState(duplicate); throw TestFailure(description: "duplicate accepted") }
                catch is ValidationFailure {}
                var noMapping = seed
                noMapping.items[0].binanceMapping = nil
                noMapping.items[0].coinbaseMapping = nil
                do { try validatePersistedState(noMapping); throw TestFailure(description: "mappingless accepted") }
                catch is ValidationFailure {}
            },
            AcceptanceTest(name: "06 exact v0 migration and v1 fixture") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v0.json"))
                try fixture.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .migrated(let state) = store.load() else { throw TestFailure(description: "v0 did not migrate") }
                try expect(state.items[0].alert?.isArmed == false, "unknown legacy latch was armed")
                try store.save(state)
                guard case .loaded = store.load() else { throw TestFailure(description: "v1 reload failed") }
                let v1Root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: v1Root) }
                let v1Fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                try v1Fixture.write(to: v1Root.appendingPathComponent("watchlist.json"))
                let v1Store = try PersistenceStore(rootDirectory: v1Root)
                guard case .loaded(let fixtureState) = v1Store.load() else { throw TestFailure(description: "canonical v1 fixture failed") }
                try expect(fixtureState.items[0].alert?.threshold == Decimal(string: "100000.25"), "decimal string changed")
            },
            AcceptanceTest(name: "06b v1 without global alert flag defaults on") {
                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                guard var object = try JSONSerialization.jsonObject(with: fixture) as? [String: Any] else {
                    throw TestFailure(description: "v1 fixture was not a JSON object")
                }
                object.removeValue(forKey: "alertsEnabled")
                object.removeValue(forKey: "textSize")
                let legacyV1 = try JSONSerialization.data(withJSONObject: object)
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                try legacyV1.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .loaded(let state) = store.load() else {
                    throw TestFailure(description: "v1 without alertsEnabled entered recovery")
                }
                try expect(state.alertsEnabled, "absent alertsEnabled did not default to on")
                try expect(state.textSize == .medium, "absent textSize did not default to medium")
                try expect(!store.recoveryProtected, "valid v1 without alertsEnabled was protected")
                let encoded = try store.encodedData(for: state)
                let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                try expect(encodedObject?["alertsEnabled"] as? Bool == true, "alertsEnabled was not encoded")
                try expect(encodedObject?["textSize"] as? String == "medium", "textSize was not encoded")
            },
            AcceptanceTest(name: "06c unrecognized text size defaults without recovery") {
                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                guard var object = try JSONSerialization.jsonObject(with: fixture) as? [String: Any] else {
                    throw TestFailure(description: "v1 fixture was not a JSON object")
                }
                object["textSize"] = "gigantic"
                let invalidPreference = try JSONSerialization.data(withJSONObject: object)
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                try invalidPreference.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .loaded(let state) = store.load() else {
                    throw TestFailure(description: "unrecognized textSize entered recovery")
                }
                try expect(state.textSize == .medium, "unrecognized textSize did not default to medium")
                try expect(!store.recoveryProtected, "unrecognized textSize protected a valid v1 file")
            },
            AcceptanceTest(name: "06d text size preference round trips through persistence") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                var state = PersistedState.bitcoinSeed()
                state.textSize = .extraLarge
                try store.save(state)
                guard case .loaded(let reloaded) = store.load() else {
                    throw TestFailure(description: "saved textSize did not load")
                }
                try expect(reloaded.textSize == .extraLarge, "saved textSize changed during round trip")
            },
            AcceptanceTest(name: "07 future unregistered-older dispatch path") {
                try expect(schemaDispatch(version: 1, current: 2, registeredVersions: [0, 2]) == .unregisteredOlder,
                           "unregistered older path missing")
                try expect(schemaDispatch(version: 3, current: 2, registeredVersions: [0, 2]) == .newer,
                           "newer path missing")
            },
            AcceptanceTest(name: "08 encoded search and exact candidate filters") {
                let searchBody = Data(#"{"coins":[]}"#.utf8)
                let transport = StubHTTPTransport([response(body: searchBody)])
                let clients = clients(transport: transport)
                _ = try await clients.searchCoinGecko(query: "btc & usd")
                let request = try expectOne(await transport.capturedRequests())
                try expect(request.url?.absoluteString.contains("btc%20%26%20usd") == true, "query not encoded")
            },
            AcceptanceTest(name: "08b Coinbase-wide 10/s burst-15 pacing") {
                let pacer = TokenBucketPacer(clock: SystemContinuousTimeSource(), ratePerSecond: 10, burst: 15)
                let start = Date()
                for _ in 0..<25 { try await pacer.acquire(priority: .candle, cost: 1) }
                let elapsed = Date().timeIntervalSince(start)
                try expect(elapsed >= 0.85, "25 requests escaped the shared sustained limit")
                try expect(elapsed < 2.5, "pacer latency was unexpectedly unbounded")
            },
            AcceptanceTest(name: "09 product lifecycle and same-set no-op") {
                let parts = controllerParts()
                let controller = parts.controller
                controller.replaceProducts(["BTCUSDT"])
                try expect(parts.factory.creationCount == 1, "more than one lifetime session")
                try expect(parts.session.sockets.count == 1, "start missing")
                controller.replaceProducts(["btcusdt"])
                try expect(parts.session.sockets.count == 1, "same set restarted")
                controller.replaceProducts([])
                try expect(controller.state == .stopped, "empty did not stop")
                controller.replaceProducts(["ETHUSDT"])
                try expect(parts.session.sockets.count == 2, "restart missing")
                controller.shutdown()
                try expect(parts.session.invalidationCount == 1, "lifetime session not invalidated once")
            },
            AcceptanceTest(name: "10 stale UUID plus task identity exclusion") {
                let parts = controllerParts()
                let controller = parts.controller
                controller.replaceProducts(["BTCUSDT"])
                let oldTask = controller.currentTaskIdentifier!
                let oldConnection = controller.connectionID
                controller.replaceProducts(["ETHUSDT"])
                let currentConnection = controller.connectionID
                controller.didClose(taskIdentifier: oldTask, connectionID: oldConnection,
                                    failure: NetworkFailure(domain: "test", code: 1, message: "old"))
                try expect(controller.connectionID == currentConnection && controller.state == .connecting,
                           "old callback changed replacement")
                controller.shutdown()
            },
            AcceptanceTest(name: "11 client-wide retry survives set and wake") {
                let parts = controllerParts()
                let controller = parts.controller
                controller.replaceProducts(["BTCUSDT"])
                let task = controller.currentTaskIdentifier!
                let connection = controller.connectionID
                controller.didOpen(taskIdentifier: task, connectionID: connection)
                controller.didClose(taskIdentifier: task, connectionID: connection,
                                    failure: NetworkFailure(domain: "test", code: 1, message: "close"))
                try expect(controller.transportFailureAttempt == 1, "failure did not earn backoff")
                controller.replaceProducts(["ETHUSDT"])
                try expect(controller.transportFailureAttempt == 1, "set change reset backoff")
                controller.suspendForSleep(); controller.resumeAfterWake()
                try expect(controller.transportFailureAttempt == 1, "wake reset backoff")
                controller.shutdown()
            },
            AcceptanceTest(name: "12 socket message size bound") {
                let parts = controllerParts()
                parts.controller.replaceProducts(["BTCUSDT"])
                try expect(parts.session.sockets[0].maximumMessageSize == maximumWebSocketMessageBytes, "socket cap missing")
                parts.controller.shutdown()
            },
            AcceptanceTest(name: "13 lifecycle delegate authorization") {
                let parts = controllerParts()
                parts.controller.replaceProducts(["BTCUSDT"])
                let task = parts.controller.currentTaskIdentifier!
                let connection = parts.controller.connectionID
                parts.controller.didOpen(taskIdentifier: task, connectionID: UUID())
                try expect(parts.controller.state == .connecting, "wrong UUID opened")
                parts.controller.didOpen(taskIdentifier: task, connectionID: connection)
                try expect(parts.controller.state == .connected, "matching open rejected")
                parts.controller.shutdown()
            },
            AcceptanceTest(name: "14 Binance combined ticker parsing") {
                let parts = controllerParts()
                let sink = TestFeedSink()
                parts.controller.attachSink(sink)
                parts.controller.replaceProducts(["BTCUSDT"])
                let task = parts.controller.currentTaskIdentifier!
                let connection = parts.controller.connectionID
                parts.controller.didOpen(taskIdentifier: task, connectionID: connection)
                parts.session.sockets[0].enqueue(.string(#"{"stream":"btcusdt@ticker","data":{"s":"BTCUSDT","c":"65000.25","P":"1.5","E":1700000000000}}"#))
                await Task.yield(); await Task.yield()
                try expect(sink.ticks.count == 1 && sink.ticks[0].productID == "BTCUSDT", "valid ticker rejected")
                parts.controller.shutdown()
            },
            AcceptanceTest(name: "15 Coinbase optional open contract") {
                let bodies = [
                    #"{"last":"100"}"#,
                    #"{"last":"100","open":null}"#,
                    #"{"last":"100","open":{"bad":1}}"#,
                    #"{"last":"100","open":"0"}"#,
                    #"{"last":"100","open":"-1"}"#,
                    #"{"last":"110","open":"100"}"#
                ].map { response(body: Data($0.utf8)) }
                let clients = clients(transport: StubHTTPTransport(bodies))
                for _ in 0..<5 {
                    let value = try await clients.coinbaseStats(productID: "BTC-USD")
                    try expect(value.change == .unavailable, "invalid open fabricated change")
                }
                let valid = try await clients.coinbaseStats(productID: "BTC-USD")
                try expect(valid.change == .percent(10), "valid open percent wrong")
            },
            AcceptanceTest(name: "16 total deadline cancels hanging transport") {
                let clients = RESTClients(
                    transport: HangingHTTPTransport(), continuousClock: ImmediateContinuousClock(),
                    wallClock: FixedWallClock(value: Date()), coinbasePacer: NoopPacer(),
                    binancePacer: NoopPacer(), coinGeckoPacer: NoopPacer()
                )
                do {
                    _ = try await clients.coinbaseStats(productID: "BTC-USD")
                    throw TestFailure(description: "hanging transport escaped deadline")
                } catch let failure as NetworkFailure {
                    try expect(failure.domain == "deadline", "wrong deadline failure")
                }
            },
            AcceptanceTest(name: "17 truthful candle normalization and HTTP status") {
                let start = Date(timeIntervalSince1970: 10_000)
                let end = start.addingTimeInterval(86_400)
                let inside = Int64((start.addingTimeInterval(3_600).timeIntervalSince1970) * 1_000)
                let outside = Int64((start.addingTimeInterval(-3_600).timeIntervalSince1970) * 1_000)
                let body = Data("[[\(inside),\"1\",\"1\",\"1\",\"2\"],[\(inside),\"1\",\"1\",\"1\",\"3\"],[\(outside),\"1\",\"1\",\"1\",\"4\"]]".utf8)
                let candleClient = clients(transport: StubHTTPTransport([response(body: body)]))
                let points = try await candleClient.binanceCandles(productID: "BTCUSDT", start: start, end: end)
                try expect(points.count == 1 && points[0].close == 3, "range/dedup normalization wrong")
                let failing = clients(transport: StubHTTPTransport([response(status: 500, body: Data(#"[]"#.utf8))]))
                do { _ = try await failing.coinbaseCandles(productID: "BTC-USD", start: start, end: end); throw TestFailure(description: "500 decoded") }
                catch let failure as NetworkFailure { try expect(failure.code == 500, "wrong status") }
            },
            AcceptanceTest(name: "17b stale chart completion after remap is rejected") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: 1, items: [], primaryItemID: nil))
                let lock = try ProcessLock(rootDirectory: root)
                let delayed = DelayedHTTPTransport()
                let parts = controllerParts()
                let model = AppModel(
                    persistenceStore: store, processLock: lock, restClients: clients(transport: delayed),
                    feedController: parts.controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 100_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                let id = UUID()
                let originalMapping = VenueMapping(exchange: .binance, productID: "OLDUSDT", baseAsset: "OLD",
                                                   quoteAsset: "USDT", provenance: .userConfirmedTickerMatch)
                let item = WatchItem(id: id, coinGeckoID: "old", symbol: "OLD", name: "Old",
                                     binanceMapping: originalMapping, coinbaseMapping: nil, alert: nil)
                try model.addItem(item)
                for _ in 0..<100 {
                    if await delayed.pendingCount() > 0 { break }
                    await Task.yield()
                }
                let heldCount = await delayed.pendingCount()
                try expect(heldCount == 1, "old chart request was not held")
                try model.commitEdit { draft in
                    let replacement = VenueMapping(exchange: .binance, productID: "NEWUSDT", baseAsset: "NEW",
                                                   quoteAsset: "USDT", provenance: .userConfirmedTickerMatch)
                    draft.items[0].binanceMapping = replacement
                }
                await delayed.completeFirst(response(body: Data(#"[]"#.utf8)))
                await Task.yield(); await Task.yield()
                try expect(model.charts[id] == nil, "superseded chart published after remap")
                model.shutdown()
            },
            AcceptanceTest(name: "18 64 MiB boundary before decode") {
                let oversized = Data(count: maximumHTTPBodyBytes + 1)
                let clients = clients(transport: StubHTTPTransport([response(body: oversized)]))
                do { _ = try await clients.searchCoinGecko(query: "btc"); throw TestFailure(description: "oversized decoded") }
                catch let failure as NetworkFailure { try expect(failure.code == -3, "body bound failure missing") }
            },
            AcceptanceTest(name: "19 alert boundary table and target identity") {
                let id = UUID()
                let base = PriceAlert(direction: .above, threshold: 100, cooldownSeconds: 60,
                                      hysteresisPercent: 10, isEnabled: true, isArmed: true, lastFiredAt: nil)
                let now = Date(timeIntervalSince1970: 1_000)
                try expect(AlertEngine.evaluate(itemID: id, alert: base, price: 100, wallNow: now) == .noChange(itemID: id), "equality breached")
                try expect(AlertEngine.evaluate(itemID: id, alert: base, price: 101, wallNow: now) == .fire(itemID: id, expectedAlert: base, firedAt: now), "breach did not fire")
                var disarmed = base; disarmed.isArmed = false
                try expect(AlertEngine.evaluate(itemID: id, alert: disarmed, price: 89, wallNow: now) == .rearm(itemID: id, expectedAlert: disarmed), "strict rearm failed")
                try expect(AlertEngine.evaluate(itemID: id, alert: disarmed, price: 90, wallNow: now) == .noChange(itemID: id), "rearm equality changed")
            },
            AcceptanceTest(name: "20 recovery protection and reset-only overwrite") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let original = Data("not json".utf8)
                try original.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .recovery = store.load() else { throw TestFailure(description: "malformed file not protected") }
                do { try store.save(.bitcoinSeed()); throw TestFailure(description: "ordinary recovery save succeeded") }
                catch {}
                let protectedBytes = try Data(contentsOf: store.stateURL)
                try expect(protectedBytes == original, "original bytes changed")
                try store.save(.bitcoinSeed(), allowRecoveryReset: true)
                guard case .loaded = store.load() else { throw TestFailure(description: "reset did not recover") }
            },
            AcceptanceTest(name: "21 durable fire precedes injected notification submission") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let lock = try ProcessLock(rootDirectory: root)
                let store = try PersistenceStore(rootDirectory: root)
                let transport = StubHTTPTransport([])
                let rest = clients(transport: transport)
                let parts = controllerParts()
                let notifications = FakeNotifications()
                let wall = FixedWallClock(value: Date(timeIntervalSince1970: 2_000))
                let model = AppModel(
                    persistenceStore: store, processLock: lock, restClients: rest,
                    feedController: parts.controller, notifications: notifications,
                    wallClock: wall, continuousClock: FixedContinuousClock(),
                    suspendingClock: FixedSuspendingClock(), startNetworking: false, observeSleepWake: false
                )
                let item = model.items[0]
                let alert = PriceAlert(direction: .above, threshold: 10, cooldownSeconds: 0,
                                       hysteresisPercent: 0, isEnabled: true, isArmed: true, lastFiredAt: nil)
                try model.saveAlert(itemID: item.id, proposed: alert)
                await Task.yield()
                model.feedDidAccept(BinanceTick(
                    productID: "BTCUSDT", price: 11, changePercent: 1,
                    eventDate: wall.now(), receivedInstant: FixedContinuousClock().now()
                ))
                await Task.yield(); await Task.yield()
                try expect(model.items[0].alert?.isArmed == false, "fire latch was not durable")
                let reloaded = try PersistenceStore(rootDirectory: root)
                guard case .loaded(let saved) = reloaded.load() else { throw TestFailure(description: "fire state did not reload") }
                try expect(saved.items[0].alert?.isArmed == false, "notification preceded durable fire")
                try expect(notifications.permissionRequests == 1 && notifications.submissions.count == 1,
                           "notification boundary count wrong")
                model.shutdown()
            },
            AcceptanceTest(name: "21b global alerts suspend evaluation and fire after re-enable") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let lock = try ProcessLock(rootDirectory: root)
                let store = try PersistenceStore(rootDirectory: root)
                let parts = controllerParts()
                let wall = FixedWallClock(value: Date(timeIntervalSince1970: 3_000))
                let model = AppModel(
                    persistenceStore: store,
                    processLock: lock,
                    restClients: clients(transport: StubHTTPTransport([])),
                    feedController: parts.controller,
                    notifications: FakeNotifications(),
                    wallClock: wall,
                    continuousClock: FixedContinuousClock(),
                    suspendingClock: FixedSuspendingClock(),
                    startNetworking: false,
                    observeSleepWake: false
                )
                let itemID = model.items[0].id
                try model.saveAlert(
                    itemID: itemID,
                    proposed: PriceAlert(
                        direction: .above,
                        threshold: 10,
                        cooldownSeconds: 0,
                        hysteresisPercent: 0,
                        isEnabled: true,
                        isArmed: true,
                        lastFiredAt: nil
                    )
                )
                try model.setAlertsEnabled(false)
                model.feedDidAccept(BinanceTick(
                    productID: "BTCUSDT",
                    price: 11,
                    changePercent: 1,
                    eventDate: wall.now(),
                    receivedInstant: FixedContinuousClock().now()
                ))
                let disabledAlert = model.items[0].alert
                try expect(!model.alertsEnabled, "global alert switch did not turn off")
                try expect(disabledAlert?.isArmed == true && disabledAlert?.lastFiredAt == nil,
                           "disabled alert evaluation changed latch state")

                try model.setAlertsEnabled(true)
                model.feedDidAccept(BinanceTick(
                    productID: "BTCUSDT",
                    price: 11,
                    changePercent: 1,
                    eventDate: wall.now(),
                    receivedInstant: FixedContinuousClock().now()
                ))
                try expect(model.items[0].alert?.isArmed == false && model.items[0].alert?.lastFiredAt != nil,
                           "re-enabled alert did not fire on the next tick")
                model.shutdown()
            },
            AcceptanceTest(name: "22 presentation formatting") {
                try expect(AppModel.formatPrice(Decimal(string: "1234.5")!) == "1,234.50", "price formatting")
                try expect(AppModel.formatChange(.unavailable) == "—", "unavailable change fabricated")
                try expect(AppModel.formatChange(.percent(1)).hasPrefix("+"), "positive direction missing")
                // Regression: whole-number rounding rendered +1.34% as "+1%" and
                // any sub-half-percent move as "+0%", which read as a parse bug.
                try expect(AppModel.formatChange(.percent(Decimal(string: "1.34")!)) == "+1.34%", "change lost decimals")
                try expect(AppModel.formatChange(.percent(Decimal(string: "0.12")!)) == "+0.12%", "small change collapsed to zero")
                try expect(AppModel.formatChange(.percent(Decimal(string: "-2.5")!)) == "-2.50%", "negative change formatting")

                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let model = AppModel(
                    persistenceStore: try PersistenceStore(rootDirectory: root),
                    processLock: try ProcessLock(rootDirectory: root),
                    restClients: clients(transport: StubHTTPTransport([])),
                    feedController: controllerParts().controller,
                    notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 2_000)),
                    continuousClock: FixedContinuousClock(),
                    suspendingClock: FixedSuspendingClock(),
                    startNetworking: false,
                    observeSleepWake: false
                )
                try expect(model.menuBarTitle == "BitPrice", "menu title without a primary quote")
                model.feedDidAccept(BinanceTick(
                    productID: "BTCUSDT",
                    price: Decimal(string: "63928.65")!,
                    changePercent: Decimal(string: "1.34")!,
                    eventDate: Date(timeIntervalSince1970: 2_000),
                    receivedInstant: FixedContinuousClock().now()
                ))
                try expect(model.menuBarTitle == "BTC 63,928.65", "menu title omitted the primary symbol and price")
                model.shutdown()
            },
            AcceptanceTest(name: "22b chart axis calculations") {
                let start = Date(timeIntervalSince1970: 1_000)
                let normal = [
                    CandlePoint(bucketStart: start, close: 10),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: 20),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: 30),
                    CandlePoint(bucketStart: start.addingTimeInterval(7_200), close: 40)
                ]
                try expect(
                    ChartAxisCalculator.priceTicks(for: normal) == [10, 20, 30, 40],
                    "normal price range ticks do not span the actual minimum and maximum"
                )
                let ondo = [
                    CandlePoint(bucketStart: start, close: Decimal(string: "0.3268")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: Decimal(string: "0.3306666667")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: Decimal(string: "0.3345333333")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(5_400), close: Decimal(string: "0.3384")!)
                ]
                try expect(ChartAxisCalculator.pricePrecision(for: ondo) == 4, "ONDO span selected the wrong precision")
                try expect(
                    ChartAxisCalculator.priceTicks(for: ondo) == [
                        Decimal(string: "0.3268")!,
                        Decimal(string: "0.3307")!,
                        Decimal(string: "0.3345")!,
                        Decimal(string: "0.3384")!
                    ],
                    "ONDO ticks were not rounded to one shared precision"
                )
                try expect(
                    ChartAxisCalculator.priceBounds(for: ondo) == ChartPriceBounds(
                        minimum: Decimal(string: "0.3268")!, maximum: Decimal(string: "0.3384")!
                    ),
                    "ONDO plot bounds were rounded instead of retaining the true range"
                )
                try expect(
                    ChartAxisCalculator.priceFraction(Decimal(string: "0.3268")!, minimum: 0.3268, maximum: 0.3384) == 0 &&
                    ChartAxisCalculator.priceFraction(Decimal(string: "0.3384")!, minimum: 0.3268, maximum: 0.3384) == 1,
                    "ONDO plot range did not span true min and max"
                )

                let bitcoinScale = [
                    CandlePoint(bucketStart: start, close: Decimal(string: "63824.731")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: Decimal(string: "63824.931")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: Decimal(string: "63825.131")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(5_400), close: Decimal(string: "63825.329")!)
                ]
                try expect(ChartAxisCalculator.pricePrecision(for: bitcoinScale) == 2,
                           "63,824 span selected the wrong precision")
                try expect(
                    ChartAxisCalculator.priceTicks(for: bitcoinScale) == [
                        Decimal(string: "63824.73")!,
                        Decimal(string: "63824.93")!,
                        Decimal(string: "63825.13")!,
                        Decimal(string: "63825.33")!
                    ],
                    "63,824 ticks collapsed or lost their shared precision"
                )
                try expect(
                    ChartAxisCalculator.priceBounds(for: bitcoinScale) == ChartPriceBounds(
                        minimum: Decimal(string: "63824.731")!, maximum: Decimal(string: "63825.329")!
                    ),
                    "63,824 plot bounds were rounded instead of retaining the true range"
                )
                try expect(
                    ChartAxisCalculator.priceFraction(
                        Decimal(string: "63824.731")!, minimum: Decimal(string: "63824.731")!, maximum: Decimal(string: "63825.329")!
                    ) == 0 &&
                    ChartAxisCalculator.priceFraction(
                        Decimal(string: "63825.329")!, minimum: Decimal(string: "63824.731")!, maximum: Decimal(string: "63825.329")!
                    ) == 1,
                    "63,824 plot range did not span true min and max"
                )
                try expect(
                    ChartAxisCalculator.formattedPrice(Decimal(string: "63824.73")!, fractionDigits: 2) == "63,824.73",
                    "large-scale axis label formatting lost its precision"
                )
                try expect(
                    ChartAxisCalculator.timeTicks(for: normal) == [
                        start,
                        start.addingTimeInterval(3_600),
                        start.addingTimeInterval(7_200)
                    ],
                    "time ticks were not selected from actual point timestamps"
                )

                let flat = [
                    CandlePoint(bucketStart: start, close: Decimal(string: "0.33")!),
                    CandlePoint(bucketStart: start.addingTimeInterval(60), close: Decimal(string: "0.33")!)
                ]
                try expect(
                    ChartAxisCalculator.priceTicks(for: flat) == [Decimal(string: "0.33")!],
                    "flat price range did not collapse to one truthful tick"
                )
                try expect(
                    ChartAxisCalculator.priceFraction(
                        Decimal(string: "0.33")!,
                        minimum: Decimal(string: "0.33")!,
                        maximum: Decimal(string: "0.33")!
                    ) == 0.5,
                    "flat price range did not stay centered"
                )

                let single = [CandlePoint(bucketStart: start, close: Decimal(string: "63824.73")!)]
                try expect(
                    ChartAxisCalculator.priceTicks(for: single) == [Decimal(string: "63824.73")!],
                    "single-point price range fabricated ticks"
                )
                try expect(ChartAxisCalculator.timeTicks(for: single) == [start], "single-point time range fabricated ticks")
                try expect(ChartAxisCalculator.priceTicks(for: []).isEmpty, "empty price range fabricated ticks")
                try expect(ChartAxisCalculator.timeTicks(for: []).isEmpty, "empty time range fabricated ticks")
            },
            AcceptanceTest(name: "23 packaging prohibitions and plist facts") {
                try expect(!FileManager.default.fileExists(atPath: "Package.swift"), "Package.swift exists")
                let script = try String(contentsOfFile: "scripts/build-app.sh", encoding: .utf8)
                try expect(!script.contains("swift build"), "build script invokes forbidden tool")
                let plist = NSDictionary(contentsOfFile: "Info.plist")
                try expect(plist?["LSUIElement"] as? Bool == true, "LSUIElement missing")
                try expect(plist?["LSMinimumSystemVersion"] as? String == "14.0", "minimum system wrong")
                try expect(plist?["CFBundleIconFile"] as? String == "AppIcon.icns", "app icon reference missing")
            }
        ]
    }

    @MainActor
    static func clients(transport: any HTTPTransport) -> RESTClients {
        RESTClients(
            transport: transport, continuousClock: FixedContinuousClock(),
            wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 1_700_000_000)),
            coinbasePacer: NoopPacer(), binancePacer: NoopPacer(), coinGeckoPacer: NoopPacer()
        )
    }

    @MainActor
    static func controllerParts() -> (controller: BinanceFeedController, session: FakeWebSocketSession, factory: FakeWebSocketFactory) {
        let session = FakeWebSocketSession()
        let factory = FakeWebSocketFactory(session: session)
        let controller = BinanceFeedController(
            sessionFactory: factory, continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock()
        )
        return (controller, session, factory)
    }

    static func response(status: Int = 200, body: Data) -> HTTPResponseData {
        HTTPResponseData(statusCode: status, body: body, headers: [:])
    }

    static func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BitPriceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func expectOne<T>(_ values: [T]) throws -> T {
        guard values.count == 1, let first = values.first else { throw TestFailure(description: "expected one value") }
        return first
    }
}
