import Foundation

let currentSchemaVersion = 2
let maximumWatchlistCount = 25
let maximumCombinedStreamURLBytes = 2_048
let maximumHTTPBodyBytes = 64 * 1_024 * 1_024
let maximumWebSocketMessageBytes = 1 * 1_024 * 1_024

enum Venue: String, Codable, Sendable, CaseIterable {
    case binance
    case coinbase
    case okx
}

enum SourceLiveness: Equatable, Sendable {
    case push
    case polled(seconds: Int)
}

enum MappingProvenance: String, Codable, Sendable {
    case builtInBTC
    case userConfirmedTickerMatch
}

struct VenueMapping: Codable, Equatable, Sendable {
    let exchange: Venue
    let productID: String
    let baseAsset: String
    let quoteAsset: String
    let provenance: MappingProvenance
}

enum AlertDirection: String, Codable, Sendable {
    case above
    case below
}

enum TextSizePreference: String, Codable, CaseIterable, Hashable, Sendable {
    case small
    case medium
    case large
    case extraLarge
}

enum ChartRange: String, Codable, CaseIterable, Hashable, Sendable {
    case hours24 = "24h"
    case days7 = "7d"
    case days30 = "30d"

    var lookbackSeconds: TimeInterval {
        switch self {
        case .hours24: 86_400
        case .days7: 604_800
        case .days30: 2_592_000
        }
    }

    var binanceInterval: String {
        switch self {
        case .hours24: "15m"
        case .days7: "6h"
        case .days30: "1d"
        }
    }

    var coinbaseGranularity: Int {
        switch self {
        case .hours24: 900
        case .days7: 21_600
        case .days30: 86_400
        }
    }

    var okxBar: String {
        switch self {
        case .hours24: "15m"
        case .days7: "6H"
        case .days30: "1D"
        }
    }

    var candleCount: Int {
        switch self {
        case .hours24: 96
        case .days7: 29
        case .days30: 31
        }
    }
}

struct PriceAlert: Codable, Equatable, Sendable {
    var direction: AlertDirection
    var threshold: Decimal
    var cooldownSeconds: Int
    var hysteresisPercent: Decimal
    var isEnabled: Bool
    var isArmed: Bool
    var lastFiredAt: Date?
}

struct WatchItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let coinGeckoID: String
    var symbol: String
    var name: String
    var mapping: VenueMapping?
    var alert: PriceAlert?
}

struct PersistedState: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var items: [WatchItem]
    var primaryItemID: UUID?
    var alertsEnabled: Bool = true
    var textSize: TextSizePreference = .medium
    var chartRange: ChartRange = .hours24
    var defaultAlertCooldownSeconds: Int = 30
    var defaultAlertHysteresisPercent: Decimal = 10

    static func bitcoinSeed(id: UUID = UUID()) -> PersistedState {
        let binance = VenueMapping(
            exchange: .binance,
            productID: "BTCUSDT",
            baseAsset: "BTC",
            quoteAsset: "USDT",
            provenance: .builtInBTC
        )
        let item = WatchItem(
            id: id,
            coinGeckoID: "bitcoin",
            symbol: "BTC",
            name: "Bitcoin",
            mapping: binance,
            alert: nil
        )
        return PersistedState(
            schemaVersion: currentSchemaVersion,
            items: [item],
            primaryItemID: id,
            alertsEnabled: true,
            textSize: .medium,
            chartRange: .hours24,
            defaultAlertCooldownSeconds: 30,
            defaultAlertHysteresisPercent: 10
        )
    }
}

struct MonotonicInstant: Sendable, Comparable, Hashable {
    let offset: Duration

    static func < (lhs: MonotonicInstant, rhs: MonotonicInstant) -> Bool {
        lhs.offset < rhs.offset
    }

    func advanced(by seconds: TimeInterval) -> MonotonicInstant {
        MonotonicInstant(offset: offset + .seconds(seconds))
    }

    func seconds(since earlier: MonotonicInstant) -> TimeInterval {
        let value = offset - earlier.offset
        let parts = value.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

protocol WallClock: Sendable {
    func now() -> Date
}

protocol ContinuousTimeSource: Sendable {
    func now() -> MonotonicInstant
    func sleep(for seconds: TimeInterval) async throws
}

protocol SuspendingTimeSource: Sendable {
    func now() -> MonotonicInstant
    func sleep(for seconds: TimeInterval) async throws
}

struct SystemWallClock: WallClock {
    func now() -> Date { Date() }
}

struct SystemContinuousTimeSource: ContinuousTimeSource {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> MonotonicInstant {
        MonotonicInstant(offset: origin.duration(to: clock.now))
    }

    func sleep(for seconds: TimeInterval) async throws {
        try await clock.sleep(for: .seconds(seconds))
    }
}

struct SystemSuspendingTimeSource: SuspendingTimeSource {
    private let clock = SuspendingClock()
    private let origin: SuspendingClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> MonotonicInstant {
        MonotonicInstant(offset: origin.duration(to: clock.now))
    }

    func sleep(for seconds: TimeInterval) async throws {
        try await clock.sleep(for: .seconds(seconds))
    }
}

enum QuoteChange: Equatable, Sendable {
    case percent(Decimal)
    case unavailable
}

struct PriceTick: Equatable, Sendable {
    let productID: String
    let price: Decimal
    let changePercent: Decimal
    let eventDate: Date
    let receivedInstant: MonotonicInstant
}

struct Quote: Equatable, Sendable {
    let itemID: UUID
    let price: Decimal
    let change: QuoteChange
    let source: Venue
    let eventDate: Date
    let receivedInstant: MonotonicInstant
}

struct CandlePoint: Equatable, Sendable {
    let bucketStart: Date
    let close: Decimal
}

struct ChartSeries: Equatable, Sendable {
    let source: Venue
    let quoteAsset: String
    let range: ChartRange
    let requestedStart: Date
    let requestedEnd: Date
    let points: [CandlePoint]
    let receivedInstant: MonotonicInstant
    var latestRefreshFailed: Bool
}

struct NetworkFailure: Error, Equatable, Sendable, CustomStringConvertible {
    let domain: String
    let code: Int
    let message: String

    var description: String { message }

    static func wrapping(_ error: any Error, domain: String = "network") -> NetworkFailure {
        if let known = error as? NetworkFailure { return known }
        let nsError = error as NSError
        return NetworkFailure(domain: domain, code: nsError.code, message: nsError.localizedDescription)
    }
}

enum FeedLifecycle: Equatable, Sendable {
    case stopped
    case connecting
    case connected
    case backingOff(attempt: Int, delay: TimeInterval)
    case suspended
}

enum ConnectionPresentation: String, Sendable {
    case live
    case stale
    case offline
}

struct ChartRequestToken: Equatable, Sendable {
    let requestID: UUID
    let itemID: UUID
    let venue: Venue
    let productID: String
    let range: ChartRange
    let marketRevision: UInt64
    let requestedStart: Date
    let requestedEnd: Date
}

struct SearchResult: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let thumbnailURL: URL?
}

struct VenueCandidate: Equatable, Identifiable, Sendable {
    var id: String { "\(venue.rawValue):\(productID)" }
    let venue: Venue
    let productID: String
    let baseAsset: String
    let quoteAsset: String
}

enum VenueCandidateOrdering {
    static func sorted(_ candidates: [VenueCandidate]) -> [VenueCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsRank = quotePriority(lhs.quoteAsset)
            let rhsRank = quotePriority(rhs.quoteAsset)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let quoteOrder = lhs.quoteAsset.caseInsensitiveCompare(rhs.quoteAsset)
            if quoteOrder != .orderedSame { return quoteOrder == .orderedAscending }
            let venueOrder = lhs.venue.rawValue.caseInsensitiveCompare(rhs.venue.rawValue)
            if venueOrder != .orderedSame { return venueOrder == .orderedAscending }
            let productOrder = lhs.productID.caseInsensitiveCompare(rhs.productID)
            if productOrder != .orderedSame { return productOrder == .orderedAscending }
            return lhs.productID < rhs.productID
        }
    }

    private static func quotePriority(_ quoteAsset: String) -> Int {
        switch quoteAsset.uppercased() {
        case "USD", "USDT": 0
        case "USDC": 1
        case "FDUSD": 2
        default: 3
        }
    }
}

struct SourceQuote: Equatable, Sendable {
    let price: Decimal
    let change: QuoteChange
}

protocol PriceSource: Sendable {
    var venue: Venue { get }
    var liveness: SourceLiveness { get }
    func candidates(symbol: String) async throws -> [VenueCandidate]
    func quote(productID: String) async throws -> SourceQuote
    func candles(
        productID: String,
        range: ChartRange,
        start: Date,
        end: Date
    ) async throws -> [CandlePoint]
    func supports(_ range: ChartRange) -> Bool
}

struct HTTPResponseData: Sendable {
    let statusCode: Int
    let body: Data
    let headers: [String: String]
}

protocol HTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> HTTPResponseData
}

enum RESTRequestPriority: Int, Sendable, Comparable {
    case productCatalog = 0
    case quote = 1
    case candle = 2
    case search = 3

    static func < (lhs: RESTRequestPriority, rhs: RESTRequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol RequestPacer: Sendable {
    func acquire(priority: RESTRequestPriority, cost: Int) async throws
    func applyRateLimitBackoff(seconds: TimeInterval) async
}

@MainActor
protocol PriceFeedSink: AnyObject {
    func feedDidAccept(_ tick: PriceTick)
    func feedStateDidChange(_ state: FeedLifecycle)
}

enum WebSocketInboundMessage: Sendable {
    case string(String)
    case data(Data)
}

@MainActor
protocol WebSocketTaskTransport: AnyObject {
    var taskIdentifier: Int { get }
    var maximumMessageSize: Int { get set }
    func resume()
    func receive() async throws -> WebSocketInboundMessage
    func cancel()
}

@MainActor
protocol WebSocketSessionTransport: AnyObject {
    func makeTask(url: URL) -> any WebSocketTaskTransport
    func invalidate()
}

@MainActor
protocol WebSocketDelegateReceiving: AnyObject {}

@MainActor
protocol WebSocketSessionFactory: AnyObject {
    func makeLifetimeSession(delegate: any WebSocketDelegateReceiving) -> any WebSocketSessionTransport
}

@MainActor
protocol NotificationSubmitting: AnyObject {
    func requestAuthorization() async -> Result<Bool, NetworkFailure>
    func submit(itemID: UUID, symbol: String, price: Decimal, firedAt: Date) async -> Result<Void, NetworkFailure>
}

enum AlertDecision: Equatable, Sendable {
    case noChange(itemID: UUID)
    case rearm(itemID: UUID, expectedAlert: PriceAlert)
    case fire(itemID: UUID, expectedAlert: PriceAlert, firedAt: Date)
}

enum PersistenceMode: Equatable, Sendable {
    case writable
    case readOnly(reason: String)
    case recovery(reason: String, originalBytes: Data)
}

enum PersistenceLoadResult: Sendable {
    case firstLaunch(PersistedState)
    case loaded(PersistedState)
    case migrated(PersistedState)
    case recovery(seed: PersistedState, reason: String, originalBytes: Data)
}

enum ValidationFailure: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): message
        }
    }

    var errorDescription: String? { description }
}

func decimalIsFinite(_ value: Decimal) -> Bool {
    !value.isNaN
}

func positiveDecimal(from string: String) -> Decimal? {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
          decimalIsFinite(value), value > 0 else { return nil }
    return value
}

func finiteDecimal(from string: String) -> Decimal? {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
          decimalIsFinite(value) else { return nil }
    return value
}

func decimalString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

func binanceCombinedStreamURL(productIDs: Set<String>) -> URL? {
    guard !productIDs.isEmpty else { return nil }
    let streams = productIDs.map { $0.lowercased() + "@ticker" }.sorted().joined(separator: "/")
    var components = URLComponents()
    components.scheme = "wss"
    components.host = "stream.binance.com"
    components.port = 9443
    components.path = "/stream"
    components.queryItems = [URLQueryItem(name: "streams", value: streams)]
    return components.url
}

func validatePersistedState(_ state: PersistedState) throws {
    guard state.schemaVersion == currentSchemaVersion else {
        throw ValidationFailure.invalid("Unsupported schema version \(state.schemaVersion)")
    }
    guard state.items.count <= maximumWatchlistCount else {
        throw ValidationFailure.invalid("The watchlist exceeds \(maximumWatchlistCount) items")
    }
    guard (0...604_800).contains(state.defaultAlertCooldownSeconds) else {
        throw ValidationFailure.invalid("Default alert cooldown is out of range")
    }
    guard decimalIsFinite(state.defaultAlertHysteresisPercent),
          state.defaultAlertHysteresisPercent >= 0,
          state.defaultAlertHysteresisPercent < 100 else {
        throw ValidationFailure.invalid("Default alert hysteresis is out of range")
    }
    guard Set(state.items.map(\.id)).count == state.items.count else {
        throw ValidationFailure.invalid("Duplicate item UUID")
    }
    let mappingsByVenue = Dictionary(grouping: state.items.compactMap(\.mapping), by: \.exchange)
    for venue in Venue.allCases {
        let productIDs = mappingsByVenue[venue, default: []].map(\.productID)
        guard Set(productIDs).count == productIDs.count else {
            throw ValidationFailure.invalid("Duplicate \(venue.rawValue.capitalized) product ID")
        }
    }
    if state.items.isEmpty {
        guard state.primaryItemID == nil else { throw ValidationFailure.invalid("Empty watchlist has a primary item") }
    } else {
        guard let primary = state.primaryItemID, state.items.contains(where: { $0.id == primary }) else {
            throw ValidationFailure.invalid("Primary item is missing or dangling")
        }
    }
    for item in state.items {
        guard !item.coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationFailure.invalid("Item identity fields must not be empty")
        }
        guard let mapping = item.mapping else {
            throw ValidationFailure.invalid("Every item needs a venue mapping")
        }
        try validateMapping(mapping)
        if let alert = item.alert { try validateAlert(alert) }
    }
    let binanceIDs = mappingsByVenue[.binance, default: []].map(\.productID)
    if let url = binanceCombinedStreamURL(productIDs: Set(binanceIDs)),
       url.absoluteString.utf8.count > maximumCombinedStreamURLBytes {
        throw ValidationFailure.invalid("The Binance combined-stream URL exceeds \(maximumCombinedStreamURLBytes) bytes")
    }
}

private func validateMapping(_ mapping: VenueMapping) throws {
    guard !mapping.productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !mapping.baseAsset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !mapping.quoteAsset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationFailure.invalid("Mapping fields must not be empty")
    }
}

func validateAlert(_ alert: PriceAlert) throws {
    guard decimalIsFinite(alert.threshold), alert.threshold > 0 else {
        throw ValidationFailure.invalid("Alert threshold must be positive")
    }
    guard (0...604_800).contains(alert.cooldownSeconds) else {
        throw ValidationFailure.invalid("Alert cooldown is out of range")
    }
    guard decimalIsFinite(alert.hysteresisPercent), alert.hysteresisPercent >= 0,
          alert.hysteresisPercent < 100 else {
        throw ValidationFailure.invalid("Alert hysteresis is out of range")
    }
}
