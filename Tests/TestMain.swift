import Foundation
import SwiftUI

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

actor RoutingHTTPTransport: HTTPTransport {
    private let responses: [String: HTTPResponseData]
    private let fallback: HTTPResponseData

    init(responses: [String: HTTPResponseData], fallback: HTTPResponseData) {
        self.responses = responses
        self.fallback = fallback
    }

    func response(for request: URLRequest) async throws -> HTTPResponseData {
        let path = request.url?.path ?? ""
        for (suffix, response) in responses where path.hasSuffix(suffix) { return response }
        return fallback
    }
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

actor DelayedPathHTTPTransport: HTTPTransport {
    private struct Pending {
        let path: String
        let continuation: CheckedContinuation<HTTPResponseData, any Error>
    }

    private var pending: [Pending] = []

    func response(for request: URLRequest) async throws -> HTTPResponseData {
        let path = request.url?.path ?? ""
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(path: path, continuation: continuation))
        }
    }

    func pendingPaths() -> [String] { pending.map(\.path) }

    func completeFirst(pathSuffix: String, response: HTTPResponseData) {
        guard let index = pending.firstIndex(where: { $0.path.hasSuffix(pathSuffix) }) else { return }
        pending.remove(at: index).continuation.resume(returning: response)
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
final class TestFeedSink: PriceFeedSink {
    private(set) var ticks: [PriceTick] = []
    private(set) var states: [FeedLifecycle] = []
    func feedDidAccept(_ tick: PriceTick) { ticks.append(tick) }
    func feedStateDidChange(_ state: FeedLifecycle) { states.append(state) }
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
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
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
                do { try failing.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil)) }
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
                noMapping.items[0].mapping = nil
                do { try validatePersistedState(noMapping); throw TestFailure(description: "mappingless accepted") }
                catch is ValidationFailure {}
            },
            AcceptanceTest(name: "05b same coin may use different markets") {
                let firstID = UUID()
                let secondID = UUID()
                let firstMapping = VenueMapping(
                    exchange: .binance, productID: "ETHUSDT", baseAsset: "ETH", quoteAsset: "USDT",
                    provenance: .userConfirmedTickerMatch
                )
                let secondMapping = VenueMapping(
                    exchange: .binance, productID: "ETHBTC", baseAsset: "ETH", quoteAsset: "BTC",
                    provenance: .userConfirmedTickerMatch
                )
                let first = WatchItem(
                    id: firstID, coinGeckoID: "ethereum", symbol: "ETH", name: "Ethereum",
                    mapping: firstMapping, alert: nil
                )
                let second = WatchItem(
                    id: secondID, coinGeckoID: "ethereum", symbol: "ETH", name: "Ethereum",
                    mapping: secondMapping, alert: nil
                )
                var state = PersistedState(schemaVersion: currentSchemaVersion, items: [first, second], primaryItemID: firstID)
                try validatePersistedState(state)

                state.items[1].mapping = firstMapping
                do {
                    try validatePersistedState(state)
                    throw TestFailure(description: "same CoinGecko ID and market were accepted")
                } catch is ValidationFailure {}
            },
            AcceptanceTest(name: "05c validation failure keeps its message") {
                let failure = ValidationFailure.invalid("Duplicate Binance product ID")
                try expect(
                    failure.localizedDescription == "Duplicate Binance product ID",
                    "ValidationFailure lost its user-facing message"
                )
            },
            AcceptanceTest(name: "06 exact v0 and v1 migration") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v0.json"))
                try fixture.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .migrated(let state) = store.load() else { throw TestFailure(description: "v0 did not migrate") }
                try expect(state.items[0].alert?.isArmed == false, "unknown legacy latch was armed")
                try expect(state.defaultAlertCooldownSeconds == 30 && state.defaultAlertHysteresisPercent == 10,
                           "v0 migration did not apply alert defaults")
                try expect(state.schemaVersion == currentSchemaVersion, "v0 did not migrate through to the current schema")
                try expect(state.items[0].mapping?.exchange == .binance,
                           "v0 dual mappings did not preserve the Binance-first runtime rule")
                try store.save(state)
                guard case .loaded = store.load() else { throw TestFailure(description: "v2 reload failed") }
                let v1Root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: v1Root) }
                let v1Fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                try v1Fixture.write(to: v1Root.appendingPathComponent("watchlist.json"))
                let v1Store = try PersistenceStore(rootDirectory: v1Root)
                guard case .migrated(let fixtureState) = v1Store.load() else {
                    throw TestFailure(description: "canonical v1 fixture did not migrate")
                }
                try expect(fixtureState.items[0].alert?.threshold == Decimal(string: "100000.25"), "decimal string changed")
                try expect(fixtureState.items[0].mapping?.exchange == .binance &&
                               fixtureState.items[0].mapping?.productID == "BTCUSDT",
                           "v1 dual mappings did not choose Binance")
                try expect(!v1Store.recoveryProtected, "valid dual-mapping v1 fixture entered recovery")

                guard var coinbaseOnlyObject = try JSONSerialization.jsonObject(with: v1Fixture) as? [String: Any],
                      var coinbaseOnlyItems = coinbaseOnlyObject["items"] as? [[String: Any]],
                      !coinbaseOnlyItems.isEmpty else {
                    throw TestFailure(description: "v1 fixture was not mutable JSON")
                }
                coinbaseOnlyItems[0].removeValue(forKey: "binanceMapping")
                coinbaseOnlyObject["items"] = coinbaseOnlyItems
                let coinbaseOnlyRoot = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: coinbaseOnlyRoot) }
                try JSONSerialization.data(withJSONObject: coinbaseOnlyObject)
                    .write(to: coinbaseOnlyRoot.appendingPathComponent("watchlist.json"))
                let coinbaseOnlyStore = try PersistenceStore(rootDirectory: coinbaseOnlyRoot)
                guard case .migrated(let coinbaseOnlyState) = coinbaseOnlyStore.load() else {
                    throw TestFailure(description: "Coinbase-only v1 fixture did not migrate")
                }
                try expect(coinbaseOnlyState.items[0].mapping?.exchange == .coinbase &&
                               coinbaseOnlyState.items[0].mapping?.productID == "BTC-USD",
                           "v1 single mapping did not preserve Coinbase")
            },
            AcceptanceTest(name: "06b v1 without global alert flag defaults on") {
                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                guard var object = try JSONSerialization.jsonObject(with: fixture) as? [String: Any] else {
                    throw TestFailure(description: "v1 fixture was not a JSON object")
                }
                object.removeValue(forKey: "alertsEnabled")
                object.removeValue(forKey: "textSize")
                object.removeValue(forKey: "chartRange")
                object.removeValue(forKey: "defaultAlertCooldownSeconds")
                object.removeValue(forKey: "defaultAlertHysteresisPercent")
                let legacyV1 = try JSONSerialization.data(withJSONObject: object)
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                try legacyV1.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .migrated(let state) = store.load() else {
                    throw TestFailure(description: "v1 without alertsEnabled entered recovery")
                }
                try expect(state.alertsEnabled, "absent alertsEnabled did not default to on")
                try expect(state.textSize == .medium, "absent textSize did not default to medium")
                try expect(state.chartRange == .hours24, "absent chart range did not default to 24h")
                try expect(state.defaultAlertCooldownSeconds == 30 && state.defaultAlertHysteresisPercent == 10,
                           "absent alert defaults did not use documented defaults")
                try expect(!store.recoveryProtected, "valid v1 without alertsEnabled was protected")
                let encoded = try store.encodedData(for: state)
                let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                try expect(encodedObject?["alertsEnabled"] as? Bool == true, "alertsEnabled was not encoded")
                try expect(encodedObject?["textSize"] as? String == "medium", "textSize was not encoded")
                try expect(encodedObject?["chartRange"] as? String == "24h", "chart range was not encoded")
                try expect(encodedObject?["defaultAlertCooldownSeconds"] as? Int == 30,
                           "default cooldown was not encoded")
                try expect(encodedObject?["defaultAlertHysteresisPercent"] as? String == "10",
                           "default hysteresis was not encoded as a decimal string")
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
                guard case .migrated(let state) = store.load() else {
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
            AcceptanceTest(name: "06e alert defaults persist and validate") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                var state = PersistedState.bitcoinSeed()
                state.defaultAlertCooldownSeconds = 300
                state.defaultAlertHysteresisPercent = Decimal(string: "12.5")!
                try store.save(state)
                guard case .loaded(let reloaded) = store.load() else {
                    throw TestFailure(description: "saved alert defaults did not load")
                }
                try expect(reloaded.defaultAlertCooldownSeconds == 300,
                           "saved default cooldown changed during round trip")
                try expect(reloaded.defaultAlertHysteresisPercent == Decimal(string: "12.5"),
                           "saved default hysteresis changed during round trip")
                let encoded = try store.encodedData(for: reloaded)
                let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                try expect(encodedObject?["defaultAlertCooldownSeconds"] as? Int == 300,
                           "custom default cooldown was not encoded")
                try expect(encodedObject?["defaultAlertHysteresisPercent"] as? String == "12.5",
                           "custom default hysteresis was not encoded as a decimal string")

                var invalidCooldown = state
                invalidCooldown.defaultAlertCooldownSeconds = 604_801
                do {
                    try validatePersistedState(invalidCooldown)
                    throw TestFailure(description: "out-of-range default cooldown was accepted")
                } catch is ValidationFailure {}
                var invalidHysteresis = state
                invalidHysteresis.defaultAlertHysteresisPercent = 100
                do {
                    try validatePersistedState(invalidHysteresis)
                    throw TestFailure(description: "out-of-range default hysteresis was accepted")
                } catch is ValidationFailure {}
            },
            AcceptanceTest(name: "06f chart range persistence and fallback") {
                for range in ChartRange.allCases {
                    let root = try temporaryRoot()
                    defer { try? FileManager.default.removeItem(at: root) }
                    let store = try PersistenceStore(rootDirectory: root)
                    var state = PersistedState.bitcoinSeed()
                    state.chartRange = range
                    try store.save(state)
                    guard case .loaded(let reloaded) = store.load() else {
                        throw TestFailure(description: "saved chart range did not load")
                    }
                    try expect(reloaded.chartRange == range, "saved chart range changed during round trip")
                }

                let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/watchlist-v1.json"))
                guard var object = try JSONSerialization.jsonObject(with: fixture) as? [String: Any] else {
                    throw TestFailure(description: "v1 fixture was not a JSON object")
                }
                object["chartRange"] = "90d"
                let unknownRange = try JSONSerialization.data(withJSONObject: object)
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                try unknownRange.write(to: root.appendingPathComponent("watchlist.json"))
                let store = try PersistenceStore(rootDirectory: root)
                guard case .migrated(let state) = store.load() else {
                    throw TestFailure(description: "unrecognized chart range entered recovery")
                }
                try expect(state.chartRange == .hours24, "unrecognized chart range did not default to 24h")
                try expect(!store.recoveryProtected, "unrecognized chart range protected a valid v1 file")
            },
            AcceptanceTest(name: "06g persisted single mapping round trips") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                let original = PersistedState.bitcoinSeed()
                try store.save(original)
                guard case .loaded(let reloaded) = store.load(),
                      let originalItem = original.items.first,
                      let reloadedItem = reloaded.items.first else {
                    throw TestFailure(description: "persisted single-mapping item did not load")
                }
                try expect(
                    reloadedItem.mapping == originalItem.mapping,
                    "loading a current item changed its mapping"
                )
                try expect(!store.recoveryProtected, "persisted single-mapping item entered recovery")
                let encoded = try store.encodedData(for: reloaded)
                guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
                      let items = object["items"] as? [[String: Any]],
                      let item = items.first else {
                    throw TestFailure(description: "v2 encoding was not a JSON object")
                }
                try expect(object["schemaVersion"] as? Int == currentSchemaVersion,
                           "current schema version was not encoded")
                try expect(item["mapping"] != nil && item["binanceMapping"] == nil && item["coinbaseMapping"] == nil,
                           "v2 encoding retained named mapping fields")
            },
            AcceptanceTest(name: "07 future unregistered-older dispatch path") {
                try expect(schemaDispatch(version: 1, current: 2, registeredVersions: [0, 2]) == .unregisteredOlder,
                           "unregistered older path missing")
                try expect(schemaDispatch(version: 3, current: 2, registeredVersions: [0, 2]) == .newer,
                           "newer path missing")
            },
            AcceptanceTest(name: "08 encoded search and candidate ordering") {
                let searchBody = Data(#"{"coins":[]}"#.utf8)
                let transport = StubHTTPTransport([response(body: searchBody)])
                let clients = clients(transport: transport)
                _ = try await clients.searchCoinGecko(query: "btc & usd")
                let request = try expectOne(await transport.capturedRequests())
                try expect(request.url?.absoluteString.contains("btc%20%26%20usd") == true, "query not encoded")
                let candidates = [
                    VenueCandidate(venue: .binance, productID: "ETHBTC", baseAsset: "ETH", quoteAsset: "BTC"),
                    VenueCandidate(venue: .binance, productID: "ETHUSDC", baseAsset: "ETH", quoteAsset: "USDC"),
                    VenueCandidate(venue: .coinbase, productID: "ETH-USD", baseAsset: "ETH", quoteAsset: "USD"),
                    VenueCandidate(venue: .binance, productID: "ETHUSDT", baseAsset: "ETH", quoteAsset: "USDT")
                ]
                let ordered = VenueCandidateOrdering.sorted(candidates)
                try expect(
                    ordered.map(\.productID) == ["ETH-USD", "ETHUSDT", "ETHUSDC", "ETHBTC"],
                    "venue candidates were not ordered by preferred quote asset"
                )
                let sources = configuredPriceSources(clients: clients)
                try expect(sources.map(\.venue) == [.binance, .coinbase], "configured source order changed")
                try expect(sources[0].liveness == .push && sources[1].liveness == .polled(seconds: 60),
                           "configured source liveness changed")
                try expect(sources.allSatisfy { source in
                    ChartRange.allCases.allSatisfy(source.supports)
                }, "a configured source stopped supporting a current chart range")
            },
            AcceptanceTest(name: "08c CoinGecko HTML entity decoding") {
                let searchBody = Data(#"{"coins":[{"id":"sand","name":"S&amp;L &lt;token&gt; &quot;quoted&quot; &#39;single&#39; &apos;apostrophe&apos; &#38; &#x26; & bare","symbol":"s&AMP;l","market_cap_rank":null,"thumb":null}]}"#.utf8)
                let clients = clients(transport: StubHTTPTransport([response(body: searchBody)]))
                let results = try await clients.searchCoinGecko(query: "sand")
                try expect(results.count == 1, "entity fixture result count changed")
                try expect(
                    results[0].symbol == "S&L",
                    "symbol entity was not decoded at the search boundary"
                )
                try expect(
                    results[0].name == "S&L <token> \"quoted\" 'single' 'apostrophe' & & & bare",
                    "name entities were not decoded at the search boundary"
                )
                let plain = "SAND"
                try expect(decodeHTMLEntities(plain) == plain, "plain text was changed by entity decoding")
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
            AcceptanceTest(name: "15 Coinbase quote change is unavailable without a positive open") {
                let bodies = [
                    Data(#"{"last":"100","open":"0"}"#.utf8),
                    Data(#"{"last":"100","open":"-1"}"#.utf8),
                    Data(#"{"last":"100"}"#.utf8),
                    Data(#"{"last":"100","open":null}"#.utf8),
                    Data(#"{"last":"100","open":{"unexpected":true}}"#.utf8),
                    Data(#"{"last":"110","open":"100"}"#.utf8)
                ]
                let client = clients(transport: StubHTTPTransport(bodies.map { response(body: $0) }))
                for _ in 0..<5 {
                    let value = try await client.coinbaseStats(productID: "ETH-USD")
                    try expect(value.change == .unavailable, "invalid Coinbase open fabricated a percentage")
                }
                let valid = try await client.coinbaseStats(productID: "ETH-USD")
                try expect(valid.price == 110 && valid.change == .percent(10), "Coinbase percentage calculation changed")

                let invalidLast = clients(transport: StubHTTPTransport([
                    response(body: Data(#"{"last":"0","open":"100"}"#.utf8))
                ]))
                do {
                    _ = try await invalidLast.coinbaseStats(productID: "ETH-USD")
                    throw TestFailure(description: "nonpositive Coinbase last price was accepted")
                } catch is NetworkFailure {}
            },
            AcceptanceTest(name: "16 Coinbase primary quote makes a row live") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
                let lock = try ProcessLock(rootDirectory: root)
                let transport = RoutingHTTPTransport(
                    responses: ["/stats": response(body: Data(#"{"last":"100","open":"90"}"#.utf8))],
                    fallback: response(body: Data("[]".utf8))
                )
                let parts = controllerParts()
                let model = AppModel(
                    persistenceStore: store, processLock: lock, restClients: clients(transport: transport),
                    feedController: parts.controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 100_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                let id = UUID()
                let mapping = VenueMapping(exchange: .coinbase, productID: "ETH-USD", baseAsset: "ETH",
                                           quoteAsset: "USD", provenance: .userConfirmedTickerMatch)
                try model.addItem(WatchItem(id: id, coinGeckoID: "ethereum", symbol: "ETH", name: "Ethereum",
                                            mapping: mapping, alert: nil))
                for _ in 0..<1_000 {
                    if model.quotes[id] != nil { break }
                    try await Task.sleep(for: .milliseconds(1))
                }
                try expect(model.quotes[id]?.source == .coinbase, "Coinbase quote was not applied")
                try expect(model.rowPresentation(for: model.items[0]) == .live, "fresh Coinbase quote was not live")
                model.shutdown()
            },
            AcceptanceTest(name: "16b Coinbase response after remap is rejected") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
                let lock = try ProcessLock(rootDirectory: root)
                let transport = DelayedPathHTTPTransport()
                let parts = controllerParts()
                let model = AppModel(
                    persistenceStore: store, processLock: lock, restClients: clients(transport: transport),
                    feedController: parts.controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 100_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                let id = UUID()
                let original = VenueMapping(exchange: .coinbase, productID: "OLD-USD", baseAsset: "OLD",
                                             quoteAsset: "USD", provenance: .userConfirmedTickerMatch)
                try model.addItem(WatchItem(id: id, coinGeckoID: "old", symbol: "OLD", name: "Old",
                                            mapping: original, alert: nil))
                for _ in 0..<100 {
                    if (await transport.pendingPaths()).contains(where: { $0.hasSuffix("/stats") }) { break }
                    await Task.yield()
                }
                let pendingPaths = await transport.pendingPaths()
                try expect(
                    pendingPaths.contains(where: { $0.hasSuffix("/stats") }),
                    "Coinbase quote request was not held"
                )
                try model.commitEdit { draft in
                    draft.items[0].mapping = VenueMapping(
                        exchange: .coinbase, productID: "NEW-USD", baseAsset: "NEW", quoteAsset: "USD",
                        provenance: .userConfirmedTickerMatch
                    )
                }
                await transport.completeFirst(
                    pathSuffix: "/stats", response: response(body: Data(#"{"last":"100","open":"90"}"#.utf8))
                )
                await Task.yield(); await Task.yield()
                try expect(model.quotes[id] == nil, "superseded Coinbase quote published after remap")
                model.shutdown()
            },
            AcceptanceTest(name: "17 truthful candle normalization and HTTP status") {
                let start = Date(timeIntervalSince1970: 10_000)
                let end = start.addingTimeInterval(86_400)
                let inside = Int64((start.addingTimeInterval(3_600).timeIntervalSince1970) * 1_000)
                let outside = Int64((start.addingTimeInterval(-3_600).timeIntervalSince1970) * 1_000)
                let body = Data("[[\(inside),\"1\",\"1\",\"1\",\"2\"],[\(inside),\"1\",\"1\",\"1\",\"3\"],[\(outside),\"1\",\"1\",\"1\",\"4\"]]".utf8)
                let candleClient = clients(transport: StubHTTPTransport([response(body: body)]))
                let points = try await candleClient.binanceCandles(
                    productID: "BTCUSDT", range: .hours24, start: start, end: end
                )
                try expect(points.count == 1 && points[0].close == 3, "range/dedup normalization wrong")
                let failing = clients(transport: StubHTTPTransport([response(status: 500, body: Data(#"[]"#.utf8))]))
                do {
                    _ = try await failing.coinbaseCandles(
                        productID: "BTC-USD", range: .hours24, start: start, end: end
                    )
                    throw TestFailure(description: "500 decoded")
                }
                catch let failure as NetworkFailure { try expect(failure.code == 500, "wrong status") }
            },
            AcceptanceTest(name: "17c chart range table and Coinbase limits") {
                let expected: [(ChartRange, TimeInterval, String, Int, Int)] = [
                    (.hours24, 86_400, "15m", 900, 96),
                    (.days7, 604_800, "6h", 21_600, 29),
                    (.days30, 2_592_000, "1d", 86_400, 31)
                ]
                for (range, lookback, interval, granularity, candles) in expected {
                    try expect(
                        range.lookbackSeconds == lookback &&
                            range.binanceInterval == interval &&
                            range.coinbaseGranularity == granularity &&
                            range.candleCount == candles,
                        "chart range table changed for \(range.rawValue)"
                    )
                }
                let legalCoinbaseGranularities: Set<Int> = [60, 300, 900, 3_600, 21_600, 86_400]
                try expect(
                    Set(ChartRange.allCases.map(\.coinbaseGranularity)).isSubset(of: legalCoinbaseGranularities),
                    "ChartRange emitted an illegal Coinbase granularity"
                )
            },
            AcceptanceTest(name: "17d normalized candles at every range granularity") {
                let start = Date(timeIntervalSince1970: 10_000)
                for range in ChartRange.allCases {
                    let step = TimeInterval(range.coinbaseGranularity)
                    let inside = start.addingTimeInterval(step)
                    let candidates = [
                        CandlePoint(bucketStart: start.addingTimeInterval(-step), close: 1),
                        CandlePoint(bucketStart: inside, close: 2),
                        CandlePoint(bucketStart: inside, close: 3),
                        CandlePoint(bucketStart: inside.addingTimeInterval(step), close: 4)
                    ]
                    let points = normalizedCandles(
                        candidates,
                        start: start,
                        end: start.addingTimeInterval(range.lookbackSeconds)
                    )
                    try expect(
                        points == [
                            CandlePoint(bucketStart: inside, close: 3),
                            CandlePoint(bucketStart: inside.addingTimeInterval(step), close: 4)
                        ],
                        "candle normalization changed for \(range.rawValue)"
                    )
                }
            },
            AcceptanceTest(name: "17e chart gap threshold follows range granularity") {
                let start = Date(timeIntervalSince1970: 10_000)
                for range in ChartRange.allCases {
                    let bucket = TimeInterval(range.coinbaseGranularity)
                    try expect(
                        !ChartGapCalculator.isGap(
                            from: start,
                            to: start.addingTimeInterval(bucket),
                            range: range
                        ),
                        "normal \(range.rawValue) bucket spacing was treated as a gap"
                    )
                    try expect(
                        ChartGapCalculator.isGap(
                            from: start,
                            to: start.addingTimeInterval(bucket * 2),
                            range: range
                        ),
                        "missing \(range.rawValue) bucket was not treated as a gap"
                    )
                }
            },
            AcceptanceTest(name: "17b stale chart completion after remap is rejected") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
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
                                     mapping: originalMapping, alert: nil)
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
                    draft.items[0].mapping = replacement
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
            AcceptanceTest(name: "20b read failure recovery preserves the file") {
                let root = try temporaryRoot()
                let stateURL = root.appendingPathComponent("watchlist.json")
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stateURL.path)
                    try? FileManager.default.removeItem(at: root)
                }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(.bitcoinSeed())
                let originalBytes = try Data(contentsOf: stateURL)

                // A real file with mode 000 reliably fails to read for this non-root process,
                // so the recovery branch can be tested while comparing the original bytes.
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stateURL.path)
                guard case .recovery(_, let reason, _) = store.load() else {
                    throw TestFailure(description: "read failure did not enter recovery")
                }
                try expect(reason.contains("Could not read"), "read failure recovery reason omitted the read error")

                var ordinarySaveFailed = false
                do {
                    try store.save(.bitcoinSeed())
                } catch {
                    ordinarySaveFailed = true
                }
                try expect(ordinarySaveFailed, "ordinary save succeeded during read recovery")

                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stateURL.path)
                let protectedBytes = try Data(contentsOf: stateURL)
                try expect(protectedBytes == originalBytes, "read recovery changed the original file")
                try store.save(.bitcoinSeed(), allowRecoveryReset: true)
                guard case .loaded = store.load() else {
                    throw TestFailure(description: "read recovery reset did not produce a loaded state")
                }
            },
            AcceptanceTest(name: "20c newer schema recovery preserves the file") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let newerVersion = currentSchemaVersion + 1
                let originalBytes = Data("{\"schemaVersion\":\(newerVersion)}".utf8)
                let stateURL = root.appendingPathComponent("watchlist.json")
                try originalBytes.write(to: stateURL)
                let store = try PersistenceStore(rootDirectory: root)
                guard case .recovery(_, let reason, let recoveryBytes) = store.load() else {
                    throw TestFailure(description: "newer schema did not enter recovery")
                }
                let expectedReason = "Schema version \(newerVersion) is newer than this app supports"
                try expect(reason == expectedReason, "newer schema recovery reason did not identify the unsupported version")
                try expect(recoveryBytes == originalBytes, "newer schema recovery lost the original bytes")

                var ordinarySaveFailed = false
                do {
                    try store.save(.bitcoinSeed())
                } catch {
                    ordinarySaveFailed = true
                }
                try expect(ordinarySaveFailed, "ordinary save succeeded during newer schema recovery")

                let protectedBytes = try Data(contentsOf: stateURL)
                try expect(protectedBytes == originalBytes, "newer schema recovery changed the original file")
                try store.save(.bitcoinSeed(), allowRecoveryReset: true)
                guard case .loaded = store.load() else {
                    throw TestFailure(description: "newer schema recovery reset did not produce a loaded state")
                }
            },
            AcceptanceTest(name: "20d recovery message explains the data and reset") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let newerVersion = currentSchemaVersion + 1
                let stateURL = root.appendingPathComponent("watchlist.json")
                try Data("{\"schemaVersion\":\(newerVersion)}".utf8).write(to: stateURL)
                let reason = "Schema version \(newerVersion) is newer than this app supports"

                do {
                    let model = try recoveryModel(root: root)
                    defer { model.shutdown() }
                    guard let message = model.recoveryMessage else {
                        throw TestFailure(description: "recovery did not produce a user-facing message")
                    }
                    try expect(
                        message.contains("Your watchlist was not loaded"),
                        "recovery message did not explain that the watchlist was not loaded"
                    )
                    try expect(message.contains(reason), "recovery message omitted the specific recovery reason")
                    // The seam is the point. The reasons carry no trailing
                    // punctuation, so composing them without one produced
                    // "...app supports Your watchlist..." on a desktop.
                    try expect(
                        message.hasPrefix("\(reason). Your watchlist was not loaded.\n"),
                        "recovery reason ran into the next sentence"
                    )
                    try expect(
                        message.contains("\n\(stateURL.path)\n"),
                        "recovery message omitted the preserved file's location"
                    )
                    try expect(
                        message.contains("Starting over saves a copy alongside it first."),
                        "recovery message did not say that starting over keeps a copy"
                    )
                    // Three lines. A longer version swallowed the top of the panel.
                    try expect(
                        message.split(separator: "\n").count == 3,
                        "recovery message grew past the three lines the panel can spare"
                    )
                }

                let views = try String(contentsOfFile: "Sources/BitPrice/Views.swift", encoding: .utf8)
                try expect(
                    views.contains("Button(\"Discard file and start over\")"),
                    "recovery reset button still hides its destructive action"
                )
            },
            AcceptanceTest(name: "20e recovery reset replaces its backup copy") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                let firstDamagedBytes = Data("first damaged watchlist".utf8)
                try firstDamagedBytes.write(to: store.stateURL)

                do {
                    let model = try recoveryModel(root: root)
                    defer { model.shutdown() }
                    model.resetRecovery()
                    try expect(model.recoveryMessage == nil, "first recovery reset did not leave recovery mode")
                }
                let firstBackupBytes = try Data(contentsOf: store.recoveryBackupURL)
                try expect(firstBackupBytes == firstDamagedBytes, "first recovery reset did not preserve the damaged bytes")

                let secondDamagedBytes = Data("second damaged watchlist".utf8)
                try secondDamagedBytes.write(to: store.stateURL)
                do {
                    let model = try recoveryModel(root: root)
                    defer { model.shutdown() }
                    model.resetRecovery()
                    try expect(model.recoveryMessage == nil, "second recovery reset did not leave recovery mode")
                }
                let secondBackupBytes = try Data(contentsOf: store.recoveryBackupURL)
                try expect(
                    secondBackupBytes == secondDamagedBytes,
                    "second recovery reset did not replace the previous backup bytes"
                )
                let backupFiles = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil
                ).filter { $0.lastPathComponent.contains("recovery-backup") }
                try expect(backupFiles.count == 1, "recovery resets accumulated multiple backup files")
            },
            // An unreadable original is the one case where the backup cannot run and
            // the reset must proceed anyway. The read-failure branch is entered
            // *because* the file cannot be read, so refusing to reset without a
            // backup would trap the user in recovery mode with no way out short of
            // deleting the file in Finder — and there is nothing to protect, since
            // bytes that cannot be read cannot be salvaged from a copy either.
            AcceptanceTest(name: "20f an unreadable original still lets the user start over") {
                let root = try temporaryRoot()
                let store = try PersistenceStore(rootDirectory: root)
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.stateURL.path)
                    try? FileManager.default.removeItem(at: root)
                }
                try store.save(.bitcoinSeed())
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.stateURL.path)

                let model = try recoveryModel(root: root)
                defer { model.shutdown() }
                try expect(model.recoveryMessage != nil, "unreadable file did not enter recovery")
                model.resetRecovery()
                try expect(model.lastError == nil, "reset reported a failure it should have tolerated")
                try expect(model.recoveryMessage == nil, "reset did not leave recovery mode")
                try expect(!model.isReadOnly, "reset left the store read-only")
                try expect(
                    !FileManager.default.fileExists(atPath: store.recoveryBackupURL.path),
                    "a backup was claimed for bytes that could not be read"
                )
            },
            AcceptanceTest(name: "20g a failed backup write aborts the reset") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                let damaged = Data("not json".utf8)
                try damaged.write(to: store.stateURL)

                // Only the backup path is made unwritable, by occupying it with a
                // directory. Making the whole folder read-only would fail the seed
                // write too, so the reset would abort either way and this test would
                // pass without the backup step existing at all.
                try FileManager.default.createDirectory(at: store.recoveryBackupURL, withIntermediateDirectories: true)

                let model = try recoveryModel(root: root)
                defer { model.shutdown() }
                // The original reads fine here, so it is real salvageable data.
                // Overwriting it after failing to save it elsewhere is exactly what
                // the backup exists to prevent.
                model.resetRecovery()

                try expect(model.lastError?.hasPrefix("Reset failed:") == true,
                           "a failed backup write was not reported")
                try expect(model.recoveryMessage != nil, "a failed backup write left recovery mode")
                try expect(model.isReadOnly, "a failed backup write left the store writable")
                let preserved = try Data(contentsOf: store.stateURL)
                try expect(preserved == damaged, "a failed backup write still replaced the original")
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
                model.feedDidAccept(PriceTick(
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
                model.feedDidAccept(PriceTick(
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
                model.feedDidAccept(PriceTick(
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
                try expect(AppModel.formatPrice(Decimal(string: "0.024")!) == "0.024", "non-dollar price formatting")
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
                model.feedDidAccept(PriceTick(
                    productID: "BTCUSDT",
                    price: Decimal(string: "63928.65")!,
                    changePercent: Decimal(string: "1.34")!,
                    eventDate: Date(timeIntervalSince1970: 2_000),
                    receivedInstant: FixedContinuousClock().now()
                ))
                try expect(model.menuBarTitle == "BTC 63,928.65", "menu title omitted the primary symbol and price")
                model.shutdown()
            },
            // Desktop review on 2026-08-16 confirmed both halves of this by hand:
            // deleting the primary promoted the next row, and deleting the last
            // item left the menu bar reading "BitPrice" rather than the price of
            // a coin that is no longer watched. Nothing held either behaviour in
            // place afterwards, which is what these two tests are for.
            AcceptanceTest(name: "22e deleting the primary promotes the next item") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
                let model = AppModel(
                    persistenceStore: store, processLock: try ProcessLock(rootDirectory: root),
                    restClients: clients(transport: StubHTTPTransport([])),
                    feedController: controllerParts().controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 2_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                let firstID = UUID()
                let secondID = UUID()
                try model.addItem(WatchItem(
                    id: firstID, coinGeckoID: "bitcoin", symbol: "BTC", name: "Bitcoin",
                    mapping: VenueMapping(exchange: .binance, productID: "BTCUSDT", baseAsset: "BTC",
                                          quoteAsset: "USDT", provenance: .userConfirmedTickerMatch),
                    alert: nil
                ))
                try model.addItem(WatchItem(
                    id: secondID, coinGeckoID: "ethereum", symbol: "ETH", name: "Ethereum",
                    mapping: VenueMapping(exchange: .binance, productID: "ETHUSDT", baseAsset: "ETH",
                                          quoteAsset: "USDT", provenance: .userConfirmedTickerMatch),
                    alert: nil
                ))
                try expect(model.primaryItemID == firstID, "the first added item did not become primary")

                try model.removeItem(id: firstID)
                try expect(model.primaryItemID == secondID,
                           "deleting the primary did not promote the remaining item")
                try expect(model.items.count == 1, "delete removed the wrong number of items")
                model.shutdown()
            },
            AcceptanceTest(name: "22f deleting the last item clears the primary and the menu title") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
                let model = AppModel(
                    persistenceStore: store, processLock: try ProcessLock(rootDirectory: root),
                    restClients: clients(transport: StubHTTPTransport([])),
                    feedController: controllerParts().controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 2_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                let id = UUID()
                try model.addItem(WatchItem(
                    id: id, coinGeckoID: "bitcoin", symbol: "BTC", name: "Bitcoin",
                    mapping: VenueMapping(exchange: .binance, productID: "BTCUSDT", baseAsset: "BTC",
                                          quoteAsset: "USDT", provenance: .userConfirmedTickerMatch),
                    alert: nil
                ))
                model.feedDidAccept(PriceTick(
                    productID: "BTCUSDT",
                    price: Decimal(string: "63928.65")!,
                    changePercent: Decimal(string: "1.34")!,
                    eventDate: Date(timeIntervalSince1970: 2_000),
                    receivedInstant: FixedContinuousClock().now()
                ))
                try expect(model.menuBarTitle == "BTC 63,928.65", "the primed menu title was not in place")

                try model.removeItem(id: id)
                try expect(model.primaryItemID == nil, "deleting the last item left a dangling primary")
                try expect(model.items.isEmpty, "the watchlist was not emptied")
                // The quote for the deleted item may still sit in `quotes`; the
                // guard that matters is that no item resolves it, so the title
                // must not print a price for a coin that is no longer watched.
                try expect(model.menuBarTitle == "BitPrice",
                           "the menu bar kept the price of a deleted coin")
                model.shutdown()
            },
            AcceptanceTest(name: "22g polling disclosure is derived from source liveness") {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try PersistenceStore(rootDirectory: root)
                try store.save(PersistedState(schemaVersion: currentSchemaVersion, items: [], primaryItemID: nil))
                let model = AppModel(
                    persistenceStore: store, processLock: try ProcessLock(rootDirectory: root),
                    restClients: clients(transport: StubHTTPTransport([])),
                    feedController: controllerParts().controller, notifications: FakeNotifications(),
                    wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 2_000)),
                    continuousClock: FixedContinuousClock(), suspendingClock: FixedSuspendingClock(),
                    startNetworking: false, observeSleepWake: false
                )
                // Both the add-coin candidate list and the alert editor show a
                // "polls every N seconds and can miss a brief breach" line, and
                // both decide whether to show it by pattern-matching this value.
                // Before the PriceSource change the alert editor printed that
                // sentence unconditionally, naming Coinbase even for a Binance
                // market, so these two expectations are what keep the sentence
                // attached to the venue it actually describes.
                try expect(model.sourceLiveness(for: .binance) == .push,
                           "Binance stopped reporting a push feed, so the alert editor would claim it polls")
                try expect(model.sourceLiveness(for: .coinbase) == .polled(seconds: 60),
                           "Coinbase stopped reporting a 60-second poll, so its missed-breach caveat would vanish")
                try expect(model.configuredSourceNames == "Binance or Coinbase",
                           "the no-market message no longer names the configured sources")
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
                try expect(ChartAxisCalculator.openingClose(for: normal) == 10,
                           "normal series opening close was not the first candle")
                try expect(
                    ChartAxisCalculator.priceTicks(for: normal) == [10, 20, 30, 40],
                    "normal price range ticks do not span the actual minimum and maximum"
                )
                let farBaseline = [
                    CandlePoint(bucketStart: start, close: 25),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: 10),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: 20),
                    CandlePoint(bucketStart: start.addingTimeInterval(5_400), close: 30),
                    CandlePoint(bucketStart: start.addingTimeInterval(7_200), close: 40)
                ]
                let farAxisTicks = ChartAxisCalculator.axisTicks(
                    for: farBaseline,
                    plotHeight: 100,
                    minimumPixelSeparation: 8
                )
                try expect(
                    farAxisTicks.map(\.value) == [10, 20, 25, 30, 40] &&
                        farAxisTicks.filter(\.isBaseline).map(\.value) == [25],
                    "far baseline did not preserve all ordinary ticks and its own tick"
                )

                let collidingBaseline = [
                    CandlePoint(bucketStart: start, close: 21),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: 10),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: 20),
                    CandlePoint(bucketStart: start.addingTimeInterval(5_400), close: 30),
                    CandlePoint(bucketStart: start.addingTimeInterval(7_200), close: 40)
                ]
                let collidingAxisTicks = ChartAxisCalculator.axisTicks(
                    for: collidingBaseline,
                    plotHeight: 100,
                    minimumPixelSeparation: 8
                )
                try expect(
                    collidingAxisTicks.map(\.value) == [10, 21, 30, 40] &&
                        collidingAxisTicks.filter(\.isBaseline).map(\.value) == [21],
                    "colliding ordinary tick was not dropped in favor of the baseline"
                )

                let minimumBaseline = [
                    CandlePoint(bucketStart: start, close: 10),
                    CandlePoint(bucketStart: start.addingTimeInterval(1_800), close: 20),
                    CandlePoint(bucketStart: start.addingTimeInterval(3_600), close: 30),
                    CandlePoint(bucketStart: start.addingTimeInterval(5_400), close: 40)
                ]
                let minimumAxisTicks = ChartAxisCalculator.axisTicks(
                    for: minimumBaseline,
                    plotHeight: 100,
                    minimumPixelSeparation: 8
                )
                try expect(
                    minimumAxisTicks.map(\.value) == [10, 20, 30, 40] &&
                        minimumAxisTicks.first?.isBaseline == true,
                    "minimum baseline did not replace the coincident bound tick"
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
                    ChartAxisCalculator.openingClose(for: flat) == Decimal(string: "0.33")!,
                    "flat series opening close did not equal both plot bounds"
                )
                try expect(
                    ChartAxisCalculator.priceTicks(for: flat) == [Decimal(string: "0.33")!],
                    "flat price range did not collapse to one truthful tick"
                )
                let flatAxisTicks = ChartAxisCalculator.axisTicks(
                    for: flat,
                    plotHeight: 100,
                    minimumPixelSeparation: 8
                )
                try expect(
                    flatAxisTicks == [ChartAxisTick(value: Decimal(string: "0.33")!, isBaseline: true)],
                    "flat baseline did not remain the single axis tick"
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
                try expect(ChartAxisCalculator.openingClose(for: single) == nil,
                           "single-point series fabricated an opening baseline")
                try expect(
                    ChartAxisCalculator.priceTicks(for: single) == [Decimal(string: "63824.73")!],
                    "single-point price range fabricated ticks"
                )
                try expect(ChartAxisCalculator.timeTicks(for: single) == [start], "single-point time range fabricated ticks")
                try expect(ChartAxisCalculator.openingClose(for: []) == nil,
                           "empty series fabricated an opening baseline")
                try expect(ChartAxisCalculator.priceTicks(for: []).isEmpty, "empty price range fabricated ticks")
                try expect(ChartAxisCalculator.timeTicks(for: []).isEmpty, "empty time range fabricated ticks")
            },
            AcceptanceTest(name: "22c panel font multiplier mapping") {
                let preferences: [TextSizePreference] = [.small, .medium, .large, .extraLarge]
                let factors = preferences.map(PanelFont.multiplier)
                try expect(factors[1] == 1.0, "medium font multiplier changed")
                try expect(factors == factors.sorted() && Set(factors).count == factors.count,
                           "text-size font multipliers are not strictly increasing")
                let base = PanelFont.basePointSize(for: Font.TextStyle.body)
                try expect(
                    PanelFont.pointSize(for: .body, preference: .medium) == base,
                    "medium derived font size does not equal its base size"
                )
            },
            AcceptanceTest(name: "22d alert default picker options") {
                let retainedCooldown = AlertDefaultPickerOption(label: "45s", value: 45)
                let currentCooldown = 60
                let cooldownOptions = AlertDefaultPickerOptions.options(
                    retainedCustom: retainedCooldown,
                    standard: AlertDefaultPickerOptions.cooldown
                )
                try expect(
                    cooldownOptions.contains(where: { $0.value == Decimal(currentCooldown) }) &&
                        cooldownOptions.first == retainedCooldown,
                    "retained cooldown custom segment disappeared after selection"
                )
                try expect(
                    cooldownOptions.first(where: { $0.label == "45s" })?.value == 45,
                    "retained cooldown custom segment changed its exact value"
                )
                try expect(
                    cooldownOptions.filter { option in
                        !AlertDefaultPickerOptions.cooldown.contains(option)
                    }.count == 1,
                    "cooldown options contained more than one custom segment"
                )
                let customCooldown = AlertDefaultPickerOptions.customOptionIfOffList(
                    stored: 45,
                    standard: AlertDefaultPickerOptions.cooldown,
                    suffix: "s"
                )
                try expect(
                    customCooldown == retainedCooldown,
                    "off-list cooldown custom segment was not formatted at appearance"
                )
                let onListCooldownCustom = AlertDefaultPickerOptions.customOptionIfOffList(
                    stored: 30,
                    standard: AlertDefaultPickerOptions.cooldown,
                    suffix: "s"
                )
                try expect(
                    onListCooldownCustom == nil &&
                        AlertDefaultPickerOptions.options(
                            retainedCustom: nil,
                            standard: AlertDefaultPickerOptions.cooldown
                        ) == AlertDefaultPickerOptions.cooldown,
                    "on-list cooldown created an unexpected custom segment"
                )
                let retainedHysteresis = AlertDefaultPickerOption(
                    label: "2.5%",
                    value: Decimal(string: "2.5")!
                )
                let hysteresisOptions = AlertDefaultPickerOptions.options(
                    retainedCustom: retainedHysteresis,
                    standard: AlertDefaultPickerOptions.hysteresis
                )
                try expect(
                    hysteresisOptions.first == retainedHysteresis &&
                        hysteresisOptions.first(where: { $0.label == "2.5%" })?.value == Decimal(string: "2.5")!,
                    "retained hysteresis custom segment changed its exact value"
                )
                try expect(
                    hysteresisOptions.filter { option in
                        !AlertDefaultPickerOptions.hysteresis.contains(option)
                    }.count == 1,
                    "hysteresis options contained more than one custom segment"
                )
                let onListHysteresisCustom = AlertDefaultPickerOptions.customOptionIfOffList(
                    stored: 10,
                    standard: AlertDefaultPickerOptions.hysteresis,
                    suffix: "%"
                )
                try expect(
                    onListHysteresisCustom == nil &&
                        AlertDefaultPickerOptions.options(
                            retainedCustom: nil,
                            standard: AlertDefaultPickerOptions.hysteresis
                        ) == AlertDefaultPickerOptions.hysteresis,
                    "on-list hysteresis created an unexpected custom segment"
                )
                let customHysteresis = AlertDefaultPickerOptions.customOptionIfOffList(
                    stored: Decimal(string: "2.5")!,
                    standard: AlertDefaultPickerOptions.hysteresis,
                    suffix: "%"
                )
                try expect(
                    customHysteresis == retainedHysteresis,
                    "off-list hysteresis custom segment was not formatted at appearance"
                )
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

    @MainActor
    static func recoveryModel(root: URL) throws -> AppModel {
        let store = try PersistenceStore(rootDirectory: root)
        let lock = try ProcessLock(rootDirectory: root)
        let parts = controllerParts()
        return AppModel(
            persistenceStore: store,
            processLock: lock,
            restClients: clients(transport: StubHTTPTransport([])),
            feedController: parts.controller,
            notifications: FakeNotifications(),
            wallClock: FixedWallClock(value: Date(timeIntervalSince1970: 100_000)),
            continuousClock: FixedContinuousClock(),
            suspendingClock: FixedSuspendingClock(),
            startNetworking: false,
            observeSleepWake: false
        )
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
