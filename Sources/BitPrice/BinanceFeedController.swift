import Foundation

private struct BinanceCombinedTicker: Decodable {
    let stream: String
    let data: Ticker

    struct Ticker: Decodable {
        let symbol: String
        let close: String
        let percent: String
        let eventTime: Int64

        enum CodingKeys: String, CodingKey {
            case symbol = "s"
            case close = "c"
            case percent = "P"
            case eventTime = "E"
        }
    }
}

@MainActor
final class BinanceFeedController: PriceFeed, WebSocketLifecycleReceiving {
    let venue = Venue.binance
    private weak var sink: (any PriceFeedSink)?
    private let continuousClock: any ContinuousTimeSource
    private let suspendingClock: any SuspendingTimeSource
    private let delegateAdapter: WebSocketDelegateAdapter
    private var session: (any WebSocketSessionTransport)?

    private(set) var state: FeedLifecycle = .stopped
    private(set) var currentProductIDs: Set<String> = []
    private(set) var configurationID = UUID()
    private(set) var connectionID = UUID()
    private(set) var currentTaskIdentifier: Int?
    private(set) var transportFailureAttempt = 0

    private var taskConnectionRegistry: [Int: UUID] = [:]
    private var currentSocket: (any WebSocketTaskTransport)?
    private var receiveTask: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var openedAt: MonotonicInstant?
    private var isAwake = true
    private var isShutdown = false

    init(
        sessionFactory: any WebSocketSessionFactory,
        continuousClock: any ContinuousTimeSource,
        suspendingClock: any SuspendingTimeSource,
        sink: (any PriceFeedSink)? = nil
    ) {
        self.continuousClock = continuousClock
        self.suspendingClock = suspendingClock
        self.sink = sink
        let adapter = WebSocketDelegateAdapter(venue: venue)
        delegateAdapter = adapter
        adapter.attach(receiver: self)
        // One session is created once, reused for every connection, and invalidated only
        // by shutdown. taskIdentifier is therefore never treated as a global identity.
        session = sessionFactory.makeLifetimeSession(delegate: adapter)
    }

    func attachSink(_ sink: any PriceFeedSink) {
        self.sink = sink
        sink.feedStateDidChange(state, venue: .binance)
    }

    func replaceProducts(_ productIDs: Set<String>) {
        guard !isShutdown else { return }
        let normalized = Set(productIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        guard normalized != currentProductIDs else { return }
        configurationID = UUID()
        invalidateConnection()
        currentProductIDs = normalized
        guard !normalized.isEmpty else {
            transition(to: .stopped)
            return
        }
        guard isAwake else {
            transition(to: .suspended)
            return
        }
        // A changed subscription may reconnect promptly, but transportFailureAttempt is
        // deliberately client-wide and survives set churn (defect 9).
        connect(configurationID: configurationID, reservedConnectionID: connectionID)
    }

    func suspendForSleep() {
        guard !isShutdown else { return }
        isAwake = false
        invalidateConnection()
        transition(to: currentProductIDs.isEmpty ? .stopped : .suspended)
    }

    func resumeAfterWake() {
        guard !isShutdown else { return }
        isAwake = true
        guard !currentProductIDs.isEmpty else {
            transition(to: .stopped)
            return
        }
        invalidateConnection()
        // Wake is immediate but does not erase outage history.
        connect(configurationID: configurationID, reservedConnectionID: connectionID)
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        currentProductIDs = []
        invalidateConnection()
        session?.invalidate()
        session = nil
        transition(to: .stopped)
    }

    func didOpen(taskIdentifier: Int, connectionID callbackConnectionID: UUID) {
        guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: callbackConnectionID),
              state == .connecting else { return }
        openedAt = suspendingClock.now()
        transition(to: .connected)
    }

    func didClose(taskIdentifier: Int, connectionID callbackConnectionID: UUID, failure: NetworkFailure) {
        failCurrent(expectedConnectionID: callbackConnectionID, taskIdentifier: taskIdentifier, failure: failure)
    }

    private func connect(configurationID expectedConfigurationID: UUID, reservedConnectionID: UUID) {
        guard isAwake, !isShutdown, !currentProductIDs.isEmpty,
              configurationID == expectedConfigurationID,
              connectionID == reservedConnectionID,
              let url = binanceCombinedStreamURL(productIDs: currentProductIDs),
              url.absoluteString.utf8.count <= maximumCombinedStreamURLBytes,
              let session else { return }

        receiveTask?.cancel()
        leaseTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
        let socket = session.makeTask(url: url)
        socket.maximumMessageSize = maximumWebSocketMessageBytes
        let taskIdentifier = socket.taskIdentifier
        currentSocket = socket
        currentTaskIdentifier = taskIdentifier
        taskConnectionRegistry[taskIdentifier] = reservedConnectionID
        delegateAdapter.register(taskIdentifier: taskIdentifier, connectionID: reservedConnectionID)
        openedAt = nil
        transition(to: .connecting)
        socket.resume()
        startReceive(
            socket: socket,
            configurationID: expectedConfigurationID,
            connectionID: reservedConnectionID,
            taskIdentifier: taskIdentifier
        )
        startLease(
            configurationID: expectedConfigurationID,
            connectionID: reservedConnectionID,
            taskIdentifier: taskIdentifier
        )
    }

    private func startReceive(
        socket: any WebSocketTaskTransport,
        configurationID expectedConfigurationID: UUID,
        connectionID expectedConnectionID: UUID,
        taskIdentifier: Int
    ) {
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard self.configurationID == expectedConfigurationID,
                          self.callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
                    self.accept(message, expectedConnectionID: expectedConnectionID, taskIdentifier: taskIdentifier)
                } catch {
                    guard !Task.isCancelled else { return }
                    let failure = NetworkFailure.wrapping(error, domain: "websocket-receive")
                    guard self.configurationID == expectedConfigurationID else { return }
                    self.failCurrent(expectedConnectionID: expectedConnectionID, taskIdentifier: taskIdentifier, failure: failure)
                    return
                }
            }
        }
    }

    private func startLease(configurationID expectedConfigurationID: UUID, connectionID expectedConnectionID: UUID, taskIdentifier: Int) {
        leaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.suspendingClock.sleep(for: 300) } catch { return }
            guard self.configurationID == expectedConfigurationID,
                  self.callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
            if let openedAt = self.openedAt,
               self.suspendingClock.now().seconds(since: openedAt) >= 60 {
                self.transportFailureAttempt = 0
            }
            self.rotateCurrent(configurationID: expectedConfigurationID, connectionID: expectedConnectionID, taskIdentifier: taskIdentifier)
        }
    }

    private func rotateCurrent(configurationID expectedConfigurationID: UUID, connectionID expectedConnectionID: UUID, taskIdentifier: Int) {
        guard configurationID == expectedConfigurationID,
              callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
        invalidateConnection()
        connect(configurationID: expectedConfigurationID, reservedConnectionID: connectionID)
    }

    private func failCurrent(expectedConnectionID: UUID, taskIdentifier: Int, failure: NetworkFailure) {
        guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID),
              state == .connecting || state == .connected else { return }
        let expectedConfigurationID = configurationID
        invalidateConnection()
        guard isAwake, !isShutdown, !currentProductIDs.isEmpty else {
            transition(to: currentProductIDs.isEmpty ? .stopped : .suspended)
            return
        }
        let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
        let index = min(transportFailureAttempt, delays.count - 1)
        let delay = delays[index]
        transportFailureAttempt = min(transportFailureAttempt + 1, delays.count - 1)
        let successor = connectionID
        transition(to: .backingOff(attempt: transportFailureAttempt, delay: delay))
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.suspendingClock.sleep(for: delay) } catch { return }
            guard self.configurationID == expectedConfigurationID,
                  self.connectionID == successor,
                  self.isAwake, !self.isShutdown, !self.currentProductIDs.isEmpty else { return }
            self.connect(configurationID: expectedConfigurationID, reservedConnectionID: successor)
        }
        _ = failure
    }

    private func accept(_ message: WebSocketInboundMessage, expectedConnectionID: UUID, taskIdentifier: Int) {
        guard state == .connected,
              callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
        let data: Data
        switch message {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        }
        guard data.count <= maximumWebSocketMessageBytes,
              let wrapper = try? JSONDecoder().decode(BinanceCombinedTicker.self, from: data),
              currentProductIDs.contains(wrapper.data.symbol),
              wrapper.stream == wrapper.data.symbol.lowercased() + "@ticker",
              let price = positiveDecimal(from: wrapper.data.close),
              let percent = finiteDecimal(from: wrapper.data.percent),
              wrapper.data.eventTime >= 0 else { return }
        let tick = PriceTick(
            venue: .binance,
            productID: wrapper.data.symbol,
            price: price,
            changePercent: percent,
            eventDate: Date(timeIntervalSince1970: TimeInterval(wrapper.data.eventTime) / 1_000),
            receivedInstant: continuousClock.now()
        )
        guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
        sink?.feedDidAccept(tick)
    }

    private func callbackIsCurrent(taskIdentifier: Int, connectionID expectedConnectionID: UUID) -> Bool {
        currentTaskIdentifier == taskIdentifier &&
            connectionID == expectedConnectionID &&
            taskConnectionRegistry[taskIdentifier] == expectedConnectionID
    }

    private func invalidateConnection() {
        connectionID = UUID()
        receiveTask?.cancel()
        leaseTask?.cancel()
        retryTask?.cancel()
        receiveTask = nil
        leaseTask = nil
        retryTask = nil
        if let taskIdentifier = currentTaskIdentifier,
           let registeredConnection = taskConnectionRegistry.removeValue(forKey: taskIdentifier) {
            delegateAdapter.unregister(taskIdentifier: taskIdentifier, connectionID: registeredConnection)
        }
        currentTaskIdentifier = nil
        openedAt = nil
        currentSocket?.cancel()
        currentSocket = nil
    }

    private func transition(to newState: FeedLifecycle) {
        guard state != newState else { return }
        state = newState
        sink?.feedStateDidChange(newState, venue: .binance)
    }
}

private struct OKXSubscriptionRequest: Encodable {
    struct Argument: Encodable {
        let channel: String
        let instId: String
    }

    let op: String
    let args: [Argument]
}

private struct OKXWebSocketEvent: Decodable {
    let event: String
    let code: String?
    let msg: String?
}

private struct OKXTickerFrame: Decodable {
    struct Argument: Decodable {
        let channel: String
        let instId: String
    }

    struct Ticker: Decodable {
        let instId: String
        let last: String
        let open24h: String?
        let ts: String
    }

    let arg: Argument
    let data: [Ticker]
}

@MainActor
// This feed owns its lifecycle state just as Binance owns its own above. The
// duplication is deliberate: neither venue can mutate the other's identity,
// lease, or client-wide backoff ladder through shared coordinator state.
final class OKXFeed: PriceFeed, WebSocketLifecycleReceiving {
    let venue = Venue.okx
    private weak var sink: (any PriceFeedSink)?
    private let continuousClock: any ContinuousTimeSource
    private let suspendingClock: any SuspendingTimeSource
    private let delegateAdapter: WebSocketDelegateAdapter
    private var session: (any WebSocketSessionTransport)?

    private(set) var state: FeedLifecycle = .stopped
    private(set) var currentProductIDs: Set<String> = []
    private(set) var configurationID = UUID()
    private(set) var connectionID = UUID()
    private(set) var currentTaskIdentifier: Int?
    private(set) var transportFailureAttempt = 0

    private var taskConnectionRegistry: [Int: UUID] = [:]
    private var currentSocket: (any WebSocketTaskTransport)?
    private var receiveTask: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?
    private var openedAt: MonotonicInstant?
    private var isAwake = true
    private var isShutdown = false

    init(
        sessionFactory: any WebSocketSessionFactory,
        continuousClock: any ContinuousTimeSource,
        suspendingClock: any SuspendingTimeSource,
        sink: (any PriceFeedSink)? = nil
    ) {
        self.continuousClock = continuousClock
        self.suspendingClock = suspendingClock
        self.sink = sink
        let adapter = WebSocketDelegateAdapter(venue: venue)
        delegateAdapter = adapter
        adapter.attach(receiver: self)
        session = sessionFactory.makeLifetimeSession(delegate: adapter)
    }

    func attachSink(_ sink: any PriceFeedSink) {
        self.sink = sink
        sink.feedStateDidChange(state, venue: venue)
    }

    func replaceProducts(_ productIDs: Set<String>) {
        guard !isShutdown else { return }
        let normalized = Set(productIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        guard normalized != currentProductIDs else { return }
        configurationID = UUID()
        invalidateConnection()
        currentProductIDs = normalized
        guard !normalized.isEmpty else {
            transition(to: .stopped)
            return
        }
        guard isAwake else {
            transition(to: .suspended)
            return
        }
        // Like Binance, outage history belongs to the feed rather than one
        // subscription set, so changing products does not erase the backoff.
        connect(configurationID: configurationID, reservedConnectionID: connectionID)
    }

    func suspendForSleep() {
        guard !isShutdown else { return }
        isAwake = false
        invalidateConnection()
        transition(to: currentProductIDs.isEmpty ? .stopped : .suspended)
    }

    func resumeAfterWake() {
        guard !isShutdown else { return }
        isAwake = true
        guard !currentProductIDs.isEmpty else {
            transition(to: .stopped)
            return
        }
        invalidateConnection()
        connect(configurationID: configurationID, reservedConnectionID: connectionID)
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        currentProductIDs = []
        invalidateConnection()
        session?.invalidate()
        session = nil
        transition(to: .stopped)
    }

    func didOpen(taskIdentifier: Int, connectionID callbackConnectionID: UUID) {
        guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: callbackConnectionID),
              state == .connecting,
              let currentSocket else { return }
        openedAt = suspendingClock.now()
        startSubscription(
            socket: currentSocket,
            configurationID: configurationID,
            connectionID: callbackConnectionID,
            taskIdentifier: taskIdentifier
        )
    }

    func didClose(taskIdentifier: Int, connectionID callbackConnectionID: UUID, failure: NetworkFailure) {
        failCurrent(expectedConnectionID: callbackConnectionID, taskIdentifier: taskIdentifier, failure: failure)
    }

    private func connect(configurationID expectedConfigurationID: UUID, reservedConnectionID: UUID) {
        guard isAwake, !isShutdown, !currentProductIDs.isEmpty,
              configurationID == expectedConfigurationID,
              connectionID == reservedConnectionID,
              let url = URL(string: "wss://ws.okx.com:8443/ws/v5/public"),
              let session else { return }

        receiveTask?.cancel()
        leaseTask?.cancel()
        retryTask?.cancel()
        subscriptionTask?.cancel()
        retryTask = nil
        subscriptionTask = nil
        let socket = session.makeTask(url: url)
        socket.maximumMessageSize = maximumWebSocketMessageBytes
        let taskIdentifier = socket.taskIdentifier
        currentSocket = socket
        currentTaskIdentifier = taskIdentifier
        taskConnectionRegistry[taskIdentifier] = reservedConnectionID
        delegateAdapter.register(taskIdentifier: taskIdentifier, connectionID: reservedConnectionID)
        openedAt = nil
        transition(to: .connecting)
        socket.resume()
        startReceive(
            socket: socket,
            configurationID: expectedConfigurationID,
            connectionID: reservedConnectionID,
            taskIdentifier: taskIdentifier
        )
        startLease(
            configurationID: expectedConfigurationID,
            connectionID: reservedConnectionID,
            taskIdentifier: taskIdentifier
        )
    }

    private func startSubscription(
        socket: any WebSocketTaskTransport,
        configurationID expectedConfigurationID: UUID,
        connectionID expectedConnectionID: UUID,
        taskIdentifier: Int
    ) {
        let frame: String
        do {
            frame = try subscriptionFrame(productIDs: currentProductIDs)
        } catch {
            failCurrent(
                expectedConnectionID: expectedConnectionID,
                taskIdentifier: taskIdentifier,
                failure: NetworkFailure.wrapping(error, domain: "okx-subscribe")
            )
            return
        }
        subscriptionTask?.cancel()
        subscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await socket.send(frame)
                guard self.configurationID == expectedConfigurationID,
                      self.callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID),
                      self.state == .connecting else { return }
                self.subscriptionTask = nil
                self.transition(to: .connected)
            } catch {
                guard !Task.isCancelled,
                      self.configurationID == expectedConfigurationID else { return }
                self.failCurrent(
                    expectedConnectionID: expectedConnectionID,
                    taskIdentifier: taskIdentifier,
                    failure: NetworkFailure.wrapping(error, domain: "okx-subscribe")
                )
            }
        }
    }

    private func startReceive(
        socket: any WebSocketTaskTransport,
        configurationID expectedConfigurationID: UUID,
        connectionID expectedConnectionID: UUID,
        taskIdentifier: Int
    ) {
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard self.configurationID == expectedConfigurationID,
                          self.callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
                    self.accept(message, expectedConnectionID: expectedConnectionID, taskIdentifier: taskIdentifier)
                } catch {
                    guard !Task.isCancelled else { return }
                    let failure = NetworkFailure.wrapping(error, domain: "websocket-receive")
                    guard self.configurationID == expectedConfigurationID else { return }
                    self.failCurrent(expectedConnectionID: expectedConnectionID, taskIdentifier: taskIdentifier, failure: failure)
                    return
                }
            }
        }
    }

    private func startLease(configurationID expectedConfigurationID: UUID, connectionID expectedConnectionID: UUID, taskIdentifier: Int) {
        leaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.suspendingClock.sleep(for: 300) } catch { return }
            guard self.configurationID == expectedConfigurationID,
                  self.callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
            if let openedAt = self.openedAt,
               self.suspendingClock.now().seconds(since: openedAt) >= 60 {
                self.transportFailureAttempt = 0
            }
            self.rotateCurrent(configurationID: expectedConfigurationID, connectionID: expectedConnectionID, taskIdentifier: taskIdentifier)
        }
    }

    private func rotateCurrent(configurationID expectedConfigurationID: UUID, connectionID expectedConnectionID: UUID, taskIdentifier: Int) {
        guard configurationID == expectedConfigurationID,
              callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
        invalidateConnection()
        connect(configurationID: expectedConfigurationID, reservedConnectionID: connectionID)
    }

    private func failCurrent(expectedConnectionID: UUID, taskIdentifier: Int, failure: NetworkFailure) {
        guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID),
              state == .connecting || state == .connected else { return }
        let expectedConfigurationID = configurationID
        invalidateConnection()
        guard isAwake, !isShutdown, !currentProductIDs.isEmpty else {
            transition(to: currentProductIDs.isEmpty ? .stopped : .suspended)
            return
        }
        let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
        let index = min(transportFailureAttempt, delays.count - 1)
        let delay = delays[index]
        transportFailureAttempt = min(transportFailureAttempt + 1, delays.count - 1)
        let successor = connectionID
        transition(to: .backingOff(attempt: transportFailureAttempt, delay: delay))
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.suspendingClock.sleep(for: delay) } catch { return }
            guard self.configurationID == expectedConfigurationID,
                  self.connectionID == successor,
                  self.isAwake, !self.isShutdown, !self.currentProductIDs.isEmpty else { return }
            self.connect(configurationID: expectedConfigurationID, reservedConnectionID: successor)
        }
        _ = failure
    }

    private func accept(_ message: WebSocketInboundMessage, expectedConnectionID: UUID, taskIdentifier: Int) {
        guard state == .connected,
              callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
        let data: Data
        switch message {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        }
        guard data.count <= maximumWebSocketMessageBytes else { return }
        if let event = try? JSONDecoder().decode(OKXWebSocketEvent.self, from: data) {
            if event.event == "error" {
                let message = event.msg.flatMap { $0.isEmpty ? nil : $0 } ?? "OKX subscription failed"
                failCurrent(
                    expectedConnectionID: expectedConnectionID,
                    taskIdentifier: taskIdentifier,
                    failure: NetworkFailure(domain: "okx-websocket", code: Int(event.code ?? "") ?? -5, message: message)
                )
            }
            return
        }
        guard let frame = try? JSONDecoder().decode(OKXTickerFrame.self, from: data),
              frame.arg.channel == "tickers",
              currentProductIDs.contains(frame.arg.instId) else { return }
        for ticker in frame.data {
            guard ticker.instId == frame.arg.instId,
                  currentProductIDs.contains(ticker.instId),
                  let price = positiveDecimal(from: ticker.last),
                  let rawOpen = ticker.open24h,
                  let open = finiteDecimal(from: rawOpen), open > 0,
                  let millis = Int64(ticker.ts), millis >= 0 else { continue }
            let tick = PriceTick(
                venue: venue,
                productID: ticker.instId,
                price: price,
                changePercent: (price - open) / open * 100,
                eventDate: Date(timeIntervalSince1970: TimeInterval(millis) / 1_000),
                receivedInstant: continuousClock.now()
            )
            guard callbackIsCurrent(taskIdentifier: taskIdentifier, connectionID: expectedConnectionID) else { return }
            sink?.feedDidAccept(tick)
        }
    }

    private func subscriptionFrame(productIDs: Set<String>) throws -> String {
        let request = OKXSubscriptionRequest(
            op: "subscribe",
            args: productIDs.sorted().map { .init(channel: "tickers", instId: $0) }
        )
        let data = try JSONEncoder().encode(request)
        guard let frame = String(data: data, encoding: .utf8) else {
            throw NetworkFailure(domain: "okx-subscribe", code: -1, message: "Could not encode OKX subscription")
        }
        return frame
    }

    private func callbackIsCurrent(taskIdentifier: Int, connectionID expectedConnectionID: UUID) -> Bool {
        currentTaskIdentifier == taskIdentifier &&
            connectionID == expectedConnectionID &&
            taskConnectionRegistry[taskIdentifier] == expectedConnectionID
    }

    private func invalidateConnection() {
        connectionID = UUID()
        receiveTask?.cancel()
        leaseTask?.cancel()
        retryTask?.cancel()
        subscriptionTask?.cancel()
        receiveTask = nil
        leaseTask = nil
        retryTask = nil
        subscriptionTask = nil
        if let taskIdentifier = currentTaskIdentifier,
           let registeredConnection = taskConnectionRegistry.removeValue(forKey: taskIdentifier) {
            delegateAdapter.unregister(taskIdentifier: taskIdentifier, connectionID: registeredConnection)
        }
        currentTaskIdentifier = nil
        openedAt = nil
        currentSocket?.cancel()
        currentSocket = nil
    }

    private func transition(to newState: FeedLifecycle) {
        guard state != newState else { return }
        state = newState
        sink?.feedStateDidChange(newState, venue: venue)
    }
}
