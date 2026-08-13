import Foundation

actor SystemHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func response(for request: URLRequest) async throws -> HTTPResponseData {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkFailure(domain: "http", code: -1, message: "Response was not HTTP")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            return HTTPResponseData(statusCode: http.statusCode, body: data, headers: headers)
        } catch {
            throw NetworkFailure.wrapping(error, domain: "urlsession")
        }
    }
}

actor TokenBucketPacer: RequestPacer {
    private struct Waiter {
        let sequence: UInt64
        let priority: RESTRequestPriority
        let cost: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let clock: any ContinuousTimeSource
    private let ratePerSecond: Double
    private let burst: Double
    private var tokens: Double
    private var lastRefill: MonotonicInstant
    private var blockedUntil: MonotonicInstant?
    private var waiters: [Waiter] = []
    private var nextSequence: UInt64 = 0
    private var processor: Task<Void, Never>?

    init(clock: any ContinuousTimeSource, ratePerSecond: Double, burst: Int) {
        self.clock = clock
        self.ratePerSecond = ratePerSecond
        self.burst = Double(burst)
        self.tokens = Double(burst)
        self.lastRefill = clock.now()
    }

    func acquire(priority: RESTRequestPriority, cost: Int = 1) async throws {
        try Task.checkCancellation()
        await withCheckedContinuation { continuation in
            nextSequence &+= 1
            waiters.append(Waiter(
                sequence: nextSequence,
                priority: priority,
                cost: max(1, cost),
                continuation: continuation
            ))
            startProcessorIfNeeded()
        }
        try Task.checkCancellation()
    }

    func applyRateLimitBackoff(seconds: TimeInterval) {
        let proposed = clock.now().advanced(by: max(0, seconds))
        if blockedUntil == nil || proposed > blockedUntil! {
            blockedUntil = proposed
        }
        startProcessorIfNeeded()
    }

    private func startProcessorIfNeeded() {
        guard processor == nil, !waiters.isEmpty else { return }
        processor = Task { await self.drain() }
    }

    private func drain() async {
        while !waiters.isEmpty {
            let now = clock.now()
            refill(at: now)
            if let blockedUntil, blockedUntil > now {
                do { try await clock.sleep(for: blockedUntil.seconds(since: now)) } catch {}
                continue
            }
            blockedUntil = nil
            guard let index = waiters.indices.min(by: { lhs, rhs in
                let left = waiters[lhs]
                let right = waiters[rhs]
                if left.priority == right.priority { return left.sequence < right.sequence }
                return left.priority < right.priority
            }) else { break }
            let waiter = waiters[index]
            if tokens >= Double(waiter.cost) {
                tokens -= Double(waiter.cost)
                waiters.remove(at: index).continuation.resume()
                continue
            }
            let delay = (Double(waiter.cost) - tokens) / ratePerSecond
            do { try await clock.sleep(for: delay) } catch {}
        }
        processor = nil
        if !waiters.isEmpty { startProcessorIfNeeded() }
    }

    private func refill(at now: MonotonicInstant) {
        let elapsed = max(0, now.seconds(since: lastRefill))
        tokens = min(burst, tokens + elapsed * ratePerSecond)
        lastRefill = now
    }
}

private struct CoinGeckoSearchEnvelope: Decodable {
    let coins: [Coin]

    struct Coin: Decodable {
        let id: String
        let name: String
        let symbol: String
        let marketCapRank: Int?
        let thumb: String?

        enum CodingKeys: String, CodingKey {
            case id, name, symbol, thumb
            case marketCapRank = "market_cap_rank"
        }
    }
}

private struct BinanceExchangeInfo: Decodable {
    let symbols: [Symbol]

    struct Symbol: Decodable {
        let symbol: String
        let status: String
        let baseAsset: String
        let quoteAsset: String
    }
}

private struct CoinbaseProduct: Decodable {
    let id: String
    let baseCurrency: String
    let quoteCurrency: String
    let status: String
    let tradingDisabled: Bool?
    let cancelOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, status
        case baseCurrency = "base_currency"
        case quoteCurrency = "quote_currency"
        case tradingDisabled = "trading_disabled"
        case cancelOnly = "cancel_only"
    }
}

private struct CoinbaseStats: Decodable {
    let last: String
    let open: String?

    enum CodingKeys: String, CodingKey { case last, open }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        last = try container.decode(String.self, forKey: .last)
        open = try? container.decode(String.self, forKey: .open)
    }
}

private enum JSONScalar: Decodable {
    case number(Double)
    case string(String)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { self = .number(number); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        self = .other
    }

    var double: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        case .other: nil
        }
    }

    var decimal: Decimal? {
        switch self {
        case .number(let value): finiteDecimal(from: String(value))
        case .string(let value): finiteDecimal(from: value)
        case .other: nil
        }
    }
}

actor RESTClients {
    private let transport: any HTTPTransport
    private let continuousClock: any ContinuousTimeSource
    private let wallClock: any WallClock
    private let coinbasePacer: any RequestPacer
    private let binancePacer: any RequestPacer
    private let coinGeckoPacer: any RequestPacer
    private var coinGeckoBlockedUntil: MonotonicInstant?

    init(
        transport: any HTTPTransport,
        continuousClock: any ContinuousTimeSource,
        wallClock: any WallClock,
        coinbasePacer: any RequestPacer,
        binancePacer: any RequestPacer,
        coinGeckoPacer: any RequestPacer
    ) {
        self.transport = transport
        self.continuousClock = continuousClock
        self.wallClock = wallClock
        self.coinbasePacer = coinbasePacer
        self.binancePacer = binancePacer
        self.coinGeckoPacer = coinGeckoPacer
    }

    static func production(
        transport: any HTTPTransport = SystemHTTPTransport(),
        continuousClock: any ContinuousTimeSource = SystemContinuousTimeSource(),
        wallClock: any WallClock = SystemWallClock()
    ) -> RESTClients {
        RESTClients(
            transport: transport,
            continuousClock: continuousClock,
            wallClock: wallClock,
            coinbasePacer: TokenBucketPacer(clock: continuousClock, ratePerSecond: 10, burst: 15),
            binancePacer: TokenBucketPacer(clock: continuousClock, ratePerSecond: 20, burst: 100),
            coinGeckoPacer: TokenBucketPacer(clock: continuousClock, ratePerSecond: 5, burst: 5)
        )
    }

    func searchCoinGecko(query: String) async throws -> [SearchResult] {
        let now = continuousClock.now()
        if let deadline = coinGeckoBlockedUntil, deadline > now {
            let remaining = Int(ceil(deadline.seconds(since: now)))
            throw NetworkFailure(domain: "coingecko", code: 429, message: "Search rate-limited for \(remaining) seconds")
        }
        try await coinGeckoPacer.acquire(priority: .search, cost: 1)
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        let response = try await load(url: try requireURL(components), priority: .search)
        if response.statusCode == 429 {
            let delay = retryAfterSeconds(headers: response.headers)
            coinGeckoBlockedUntil = continuousClock.now().advanced(by: delay)
            await coinGeckoPacer.applyRateLimitBackoff(seconds: delay)
            throw statusFailure(response, domain: "coingecko")
        }
        try requireSuccess(response, domain: "coingecko")
        let envelope: CoinGeckoSearchEnvelope = try decode(response.body, domain: "coingecko")
        return envelope.coins.map {
            SearchResult(
                id: $0.id,
                name: $0.name,
                symbol: $0.symbol.uppercased(),
                marketCapRank: $0.marketCapRank,
                thumbnailURL: $0.thumb.flatMap(URL.init(string:))
            )
        }
    }

    func binanceCandidates(symbol: String) async throws -> [VenueCandidate] {
        try await binancePacer.acquire(priority: .productCatalog, cost: 20)
        let response = try await load(url: URL(string: "https://api.binance.com/api/v3/exchangeInfo")!, priority: .productCatalog)
        if response.statusCode == 429 || response.statusCode == 418 {
            await binancePacer.applyRateLimitBackoff(seconds: retryAfterSeconds(headers: response.headers))
        }
        try requireSuccess(response, domain: "binance")
        let catalog: BinanceExchangeInfo = try decode(response.body, domain: "binance")
        return catalog.symbols.compactMap { product in
            guard product.baseAsset.caseInsensitiveCompare(symbol) == .orderedSame,
                  product.quoteAsset == "USDT", product.status == "TRADING" else { return nil }
            return VenueCandidate(venue: .binance, productID: product.symbol, baseAsset: product.baseAsset, quoteAsset: product.quoteAsset)
        }
    }

    func coinbaseCandidates(symbol: String) async throws -> [VenueCandidate] {
        try await coinbasePacer.acquire(priority: .productCatalog, cost: 1)
        let response = try await load(url: URL(string: "https://api.exchange.coinbase.com/products")!, priority: .productCatalog)
        if response.statusCode == 429 {
            await coinbasePacer.applyRateLimitBackoff(seconds: retryAfterSeconds(headers: response.headers))
        }
        try requireSuccess(response, domain: "coinbase")
        let catalog: [CoinbaseProduct] = try decode(response.body, domain: "coinbase")
        return catalog.compactMap { product in
            guard product.baseCurrency.caseInsensitiveCompare(symbol) == .orderedSame,
                  product.quoteCurrency == "USD", product.status == "online",
                  product.tradingDisabled != true, product.cancelOnly != true else { return nil }
            return VenueCandidate(venue: .coinbase, productID: product.id, baseAsset: product.baseCurrency, quoteAsset: product.quoteCurrency)
        }
    }

    func coinbaseStats(productID: String) async throws -> CoinbaseQuoteValue {
        try await coinbasePacer.acquire(priority: .quote, cost: 1)
        let response = try await load(url: try coinbaseURL(productID: productID, suffix: "stats"), priority: .quote)
        if response.statusCode == 429 {
            await coinbasePacer.applyRateLimitBackoff(seconds: retryAfterSeconds(headers: response.headers))
        }
        try requireSuccess(response, domain: "coinbase")
        let stats: CoinbaseStats = try decode(response.body, domain: "coinbase")
        guard let last = positiveDecimal(from: stats.last) else {
            throw NetworkFailure(domain: "coinbase", code: -2, message: "Coinbase last price is missing, malformed, or nonpositive")
        }
        guard let rawOpen = stats.open,
              let open = finiteDecimal(from: rawOpen), open > 0 else {
            return CoinbaseQuoteValue(price: last, change: .unavailable)
        }
        return CoinbaseQuoteValue(price: last, change: .percent((last - open) / open * 100))
    }

    func binanceCandles(productID: String, start: Date, end: Date) async throws -> [CandlePoint] {
        try await binancePacer.acquire(priority: .candle, cost: 2)
        var components = URLComponents(string: "https://api.binance.com/api/v3/klines")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: productID),
            URLQueryItem(name: "interval", value: "1h"),
            URLQueryItem(name: "startTime", value: String(Int64(start.timeIntervalSince1970 * 1_000))),
            URLQueryItem(name: "endTime", value: String(Int64(end.timeIntervalSince1970 * 1_000))),
            URLQueryItem(name: "limit", value: "25")
        ]
        let response = try await load(url: try requireURL(components), priority: .candle)
        if response.statusCode == 429 || response.statusCode == 418 {
            await binancePacer.applyRateLimitBackoff(seconds: retryAfterSeconds(headers: response.headers))
        }
        try requireSuccess(response, domain: "binance")
        let rows: [[JSONScalar]] = try decode(response.body, domain: "binance")
        let candidates = rows.compactMap { row -> CandlePoint? in
            guard row.count > 4, let millis = row[0].double, millis.isFinite,
                  let close = row[4].decimal, close > 0 else { return nil }
            return CandlePoint(bucketStart: Date(timeIntervalSince1970: millis / 1_000), close: close)
        }
        return normalizedCandles(candidates, start: start, end: end)
    }

    func coinbaseCandles(productID: String, start: Date, end: Date) async throws -> [CandlePoint] {
        try await coinbasePacer.acquire(priority: .candle, cost: 1)
        var components = URLComponents(url: try coinbaseURL(productID: productID, suffix: "candles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "granularity", value: "3600"),
            URLQueryItem(name: "start", value: Self.iso8601.string(from: start)),
            URLQueryItem(name: "end", value: Self.iso8601.string(from: end))
        ]
        let response = try await load(url: try requireURL(components), priority: .candle)
        if response.statusCode == 429 {
            await coinbasePacer.applyRateLimitBackoff(seconds: retryAfterSeconds(headers: response.headers))
        }
        try requireSuccess(response, domain: "coinbase")
        let rows: [[JSONScalar]] = try decode(response.body, domain: "coinbase")
        let candidates = rows.compactMap { row -> CandlePoint? in
            guard row.count > 4, let seconds = row[0].double, seconds.isFinite,
                  let close = row[4].decimal, close > 0 else { return nil }
            return CandlePoint(bucketStart: Date(timeIntervalSince1970: seconds), close: close)
        }
        return normalizedCandles(candidates, start: start, end: end)
    }

    private func load(url: URL, priority: RESTRequestPriority) async throws -> HTTPResponseData {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("BitPrice/1", forHTTPHeaderField: "User-Agent")
        let finalizedRequest = request
        let requestDescription = String(describing: priority)
        let response = try await withThrowingTaskGroup(of: HTTPResponseData.self) { group in
            group.addTask { @Sendable [transport, finalizedRequest] in
                try await transport.response(for: finalizedRequest)
            }
            group.addTask { @Sendable [continuousClock, requestDescription] in
                try await continuousClock.sleep(for: 15)
                throw NetworkFailure(domain: "deadline", code: -1, message: "\(requestDescription) request exceeded its 15-second total deadline")
            }
            guard let first = try await group.next() else {
                throw NetworkFailure(domain: "deadline", code: -2, message: "Request ended without a result")
            }
            group.cancelAll()
            return first
        }
        guard response.body.count <= maximumHTTPBodyBytes else {
            throw NetworkFailure(domain: "http", code: -3, message: "Response body exceeds 64 MiB")
        }
        return response
    }

    private func requireSuccess(_ response: HTTPResponseData, domain: String) throws {
        guard (200...299).contains(response.statusCode) else { throw statusFailure(response, domain: domain) }
    }

    private func statusFailure(_ response: HTTPResponseData, domain: String) -> NetworkFailure {
        NetworkFailure(domain: domain, code: response.statusCode, message: "HTTP \(response.statusCode)")
    }

    private func decode<T: Decodable>(_ data: Data, domain: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw NetworkFailure(domain: domain, code: -4, message: "Invalid JSON: \(error.localizedDescription)") }
    }

    private func requireURL(_ components: URLComponents) throws -> URL {
        guard let url = components.url else { throw NetworkFailure(domain: "url", code: -1, message: "Could not construct request URL") }
        return url
    }

    private func coinbaseURL(productID: String, suffix: String) throws -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let encodedProductID = productID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw NetworkFailure(domain: "url", code: -2, message: "Could not encode Coinbase product ID")
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.exchange.coinbase.com"
        components.percentEncodedPath = "/products/\(encodedProductID)/\(suffix)"
        return try requireURL(components)
    }

    private func retryAfterSeconds(headers: [String: String]) -> TimeInterval {
        guard let value = headers["retry-after"]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return 60 }
        if let seconds = TimeInterval(value), seconds >= 0 { return seconds }
        if let date = Self.httpDate.date(from: value) { return max(0, date.timeIntervalSince(wallClock.now())) }
        return 60
    }

    private func normalizedCandles(_ candidates: [CandlePoint], start: Date, end: Date) -> [CandlePoint] {
        var unique: [Date: CandlePoint] = [:]
        for point in candidates where point.bucketStart >= start && point.bucketStart <= end {
            unique[point.bucketStart] = point
        }
        return unique.values.sorted { $0.bucketStart < $1.bucketStart }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}
