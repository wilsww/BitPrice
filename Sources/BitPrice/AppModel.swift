import AppKit
import Combine
import Foundation

enum RequestActivity: Equatable, Sendable {
    case idle
    case requesting
    case succeeded
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject, BinanceFeedSink {
    @Published private(set) var persistedState: PersistedState
    @Published private(set) var quotes: [UUID: Quote] = [:]
    @Published private(set) var charts: [UUID: ChartSeries] = [:]
    @Published private(set) var connectionState: BinanceLifecycle = .stopped
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchActivity: RequestActivity = .idle
    @Published private(set) var coinbaseActivity: [UUID: RequestActivity] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var freshnessPulse = false

    let persistenceStore: PersistenceStore
    private let processLock: ProcessLock
    private let restClients: RESTClients
    private let feedController: BinanceFeedController
    private let notifications: any NotificationSubmitting
    private let wallClock: any WallClock
    private let continuousClock: any ContinuousTimeSource
    private let suspendingClock: any SuspendingTimeSource

    private var persistenceMode: PersistenceMode = .writable
    private var binanceQuotes: [UUID: Quote] = [:]
    private var marketRevisions: [UUID: UInt64] = [:]
    private var fallbackTokens: [UUID: FallbackRequestToken] = [:]
    private var chartTokens: [UUID: ChartRequestToken] = [:]
    private var fallbackTasks: [UUID: Task<Void, Never>] = [:]
    private var chartTasks: [UUID: Task<Void, Never>] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchRequestID: UUID?
    private var fallbackLoop: Task<Void, Never>?
    private var candleLoop: Task<Void, Never>?
    private var freshnessLoop: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObserver: NSObjectProtocol?

    var items: [WatchItem] { persistedState.items }
    var primaryItemID: UUID? { persistedState.primaryItemID }
    var isReadOnly: Bool {
        switch persistenceMode {
        case .writable: false
        case .readOnly, .recovery: true
        }
    }

    init(
        persistenceStore: PersistenceStore,
        processLock: ProcessLock,
        restClients: RESTClients,
        feedController: BinanceFeedController,
        notifications: any NotificationSubmitting,
        wallClock: any WallClock,
        continuousClock: any ContinuousTimeSource,
        suspendingClock: any SuspendingTimeSource,
        seedID: UUID = UUID(),
        startNetworking: Bool = true,
        observeSleepWake: Bool = true
    ) {
        self.persistenceStore = persistenceStore
        self.processLock = processLock
        self.restClients = restClients
        self.feedController = feedController
        self.notifications = notifications
        self.wallClock = wallClock
        self.continuousClock = continuousClock
        self.suspendingClock = suspendingClock

        switch persistenceStore.load(seedID: seedID) {
        case .firstLaunch(let seed):
            persistedState = seed
            do {
                try persistenceStore.save(seed)
            } catch {
                let reason = "First-launch state could not be saved: \(error.localizedDescription)"
                persistenceMode = .readOnly(reason: reason)
                lastError = reason
            }
        case .loaded(let state):
            persistedState = state
        case .migrated(let state):
            persistedState = state
            do {
                try persistenceStore.save(state)
            } catch {
                let reason = "Migrated state is visible but could not be saved: \(error.localizedDescription)"
                persistenceMode = .readOnly(reason: reason)
                lastError = reason
            }
        case .recovery(let seed, let reason, let originalBytes):
            persistedState = seed
            persistenceMode = .recovery(reason: reason, originalBytes: originalBytes)
            recoveryMessage = "\(reason) Original file preserved at \(persistenceStore.stateURL.path)."
        }
        for item in persistedState.items { marketRevisions[item.id] = 0 }
        feedController.attachSink(self)
        if observeSleepWake { installSleepWakeObservers() }
        if startNetworking { startNetworkWork() }
    }

    static func production() throws -> AppModel {
        let wallClock = SystemWallClock()
        let continuousClock = SystemContinuousTimeSource()
        let suspendingClock = SystemSuspendingTimeSource()
        let root = try PersistenceStore.productionRoot()
        let lock = try ProcessLock(rootDirectory: root)
        let store = try PersistenceStore(rootDirectory: root)
        let transport = SystemHTTPTransport()
        let clients = RESTClients.production(
            transport: transport,
            continuousClock: continuousClock,
            wallClock: wallClock
        )
        let feed = BinanceFeedController(
            sessionFactory: SystemWebSocketSessionFactory(),
            continuousClock: continuousClock,
            suspendingClock: suspendingClock
        )
        return AppModel(
            persistenceStore: store,
            processLock: lock,
            restClients: clients,
            feedController: feed,
            notifications: NotificationService(),
            wallClock: wallClock,
            continuousClock: continuousClock,
            suspendingClock: suspendingClock
        )
    }

    func commitEdit(_ transformation: (inout PersistedState) throws -> Void) throws {
        guard !isReadOnly else {
            throw NetworkFailure(domain: "persistence", code: 3, message: "Editing is disabled while the original file is protected")
        }
        let oldState = persistedState
        var draft = oldState
        try transformation(&draft)
        try validatePersistedState(draft)
        // No await may split this read-modify-write. Structural edits and alert latch
        // transactions are synchronous main-actor full-state replacements.
        try persistenceStore.save(draft)
        persistedState = draft
        reconcileRuntimeAfterEdit(oldState: oldState, newState: draft)
        feedController.replaceProducts(binanceProductIDs(in: draft))
        reconcilePeriodicLoops()
    }

    func addItem(_ item: WatchItem) throws {
        try commitEdit { draft in
            guard draft.items.count < maximumWatchlistCount else {
                throw ValidationFailure.invalid("The watchlist is limited to \(maximumWatchlistCount) items")
            }
            draft.items.append(item)
            if draft.primaryItemID == nil { draft.primaryItemID = item.id }
        }
        requestFallbackIfEligible(itemID: item.id)
        refreshChart(itemID: item.id)
    }

    func removeItem(id: UUID) throws {
        try commitEdit { draft in
            draft.items.removeAll { $0.id == id }
            if draft.primaryItemID == id { draft.primaryItemID = draft.items.first?.id }
        }
    }

    func moveItems(fromOffsets: IndexSet, toOffset: Int) throws {
        try commitEdit { draft in
            let moving = fromOffsets.sorted().map { draft.items[$0] }
            for index in fromOffsets.sorted(by: >) { draft.items.remove(at: index) }
            let removedBefore = fromOffsets.filter { $0 < toOffset }.count
            draft.items.insert(contentsOf: moving, at: max(0, min(draft.items.count, toOffset - removedBefore)))
        }
    }

    func setPrimary(_ id: UUID) throws {
        try commitEdit { draft in
            guard draft.items.contains(where: { $0.id == id }) else {
                throw ValidationFailure.invalid("Primary item does not exist")
            }
            draft.primaryItemID = id
        }
    }

    func saveAlert(itemID: UUID, proposed: PriceAlert?) throws {
        var shouldRequestPermission = false
        try commitEdit { draft in
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else {
                throw ValidationFailure.invalid("Alert item no longer exists")
            }
            let old = draft.items[index].alert
            var adjusted = proposed
            if var alert = adjusted {
                try validateAlert(alert)
                let materialChange = old == nil || old?.direction != alert.direction ||
                    old?.threshold != alert.threshold || old?.hysteresisPercent != alert.hysteresisPercent ||
                    old?.isEnabled == false && alert.isEnabled
                if materialChange {
                    alert.isArmed = true
                    alert.lastFiredAt = nil
                } else if let old {
                    alert.isArmed = old.isArmed
                    alert.lastFiredAt = old.lastFiredAt
                }
                shouldRequestPermission = old?.isEnabled != true && alert.isEnabled
                adjusted = alert
            }
            draft.items[index].alert = adjusted
        }
        if shouldRequestPermission {
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch await self.notifications.requestAuthorization() {
                case .success(true): break
                case .success(false): self.lastError = "Notification permission denied; alerts will latch without a macOS banner."
                case .failure(let failure): self.lastError = failure.message
                }
            }
        }
    }

    func resetRecovery() {
        guard case .recovery = persistenceMode else { return }
        let seed = PersistedState.bitcoinSeed()
        do {
            try persistenceStore.save(seed, allowRecoveryReset: true)
            persistedState = seed
            persistenceMode = .writable
            recoveryMessage = nil
            lastError = nil
            quotes.removeAll()
            charts.removeAll()
            binanceQuotes.removeAll()
            marketRevisions = [seed.items[0].id: 0]
            startNetworkWork()
        } catch {
            lastError = "Reset failed: \(error.localizedDescription)"
        }
    }

    func search(query: String) {
        searchTask?.cancel()
        searchTask = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchRequestID = nil
            searchResults = []
            searchActivity = .idle
            return
        }
        let requestID = UUID()
        searchRequestID = requestID
        searchActivity = .requesting
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.suspendingClock.sleep(for: 0.3)
                guard self.searchRequestID == requestID else { return }
                let results = try await self.restClients.searchCoinGecko(query: trimmed)
                guard self.searchRequestID == requestID else { return }
                self.searchResults = results
                self.searchActivity = .succeeded
            } catch {
                guard !Task.isCancelled, self.searchRequestID == requestID else { return }
                self.searchActivity = .failed(NetworkFailure.wrapping(error).message)
            }
        }
    }

    func loadCandidates(for result: SearchResult) async -> Result<([VenueCandidate], [VenueCandidate]), NetworkFailure> {
        do {
            async let binance = restClients.binanceCandidates(symbol: result.symbol)
            async let coinbase = restClients.coinbaseCandidates(symbol: result.symbol)
            return .success(try await (binance, coinbase))
        } catch {
            return .failure(NetworkFailure.wrapping(error))
        }
    }

    func feedDidAccept(_ tick: BinanceTick) {
        guard let item = persistedState.items.first(where: { $0.binanceMapping?.productID == tick.productID }) else { return }
        marketRevisions[item.id, default: 0] &+= 1
        invalidateFallback(itemID: item.id)
        let quote = Quote(
            itemID: item.id,
            price: tick.price,
            change: .percent(tick.changePercent),
            source: .binance,
            eventDate: tick.eventDate,
            receivedInstant: tick.receivedInstant
        )
        binanceQuotes[item.id] = quote
        let oldSource = quotes[item.id]?.source
        quotes[item.id] = quote
        evaluateAlert(item: item, quote: quote)
        if oldSource != .binance || charts[item.id]?.source != .binance { refreshChart(itemID: item.id) }
    }

    func feedStateDidChange(_ state: BinanceLifecycle) {
        connectionState = state
        reconcileFallbacks()
    }

    func handleSleep() {
        searchTask?.cancel()
        searchTask = nil
        searchRequestID = nil
        cancelRESTAndLoops()
        feedController.suspendForSleep()
    }

    func handleWake() {
        freshnessPulse.toggle()
        feedController.resumeAfterWake()
        reconcileFallbacks()
        refreshAllCharts()
        reconcilePeriodicLoops()
    }

    func shutdown() {
        cancelRESTAndLoops()
        feedController.shutdown()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        if let applicationObserver {
            NotificationCenter.default.removeObserver(applicationObserver)
            self.applicationObserver = nil
        }
        _ = processLock
    }

    func quoteAsset(for item: WatchItem) -> String {
        if let source = quotes[item.id]?.source {
            if source == .binance, let mapping = item.binanceMapping { return mapping.quoteAsset }
            if source == .coinbase, let mapping = item.coinbaseMapping { return mapping.quoteAsset }
        }
        return item.binanceMapping?.quoteAsset ?? item.coinbaseMapping?.quoteAsset ?? ""
    }

    func rowPresentation(for item: WatchItem) -> ConnectionPresentation {
        if let quote = quotes[item.id] {
            let fresh = continuousClock.now().seconds(since: quote.receivedInstant) <= 120
            let usable = quote.source == .coinbase || connectionState == .connected
            return fresh && usable ? .live : .stale
        }
        let coinbase = coinbaseActivity[item.id] ?? .idle
        if connectionState == .connecting || connectionState == .connected || coinbase == .requesting { return .stale }
        return .offline
    }

    var aggregatePresentation: ConnectionPresentation? {
        guard !items.isEmpty else { return nil }
        let states = items.map(rowPresentation)
        if states.contains(.offline) { return .offline }
        if states.contains(.stale) { return .stale }
        return .live
    }

    var menuBarTitle: String {
        guard let primaryItemID,
              let item = items.first(where: { $0.id == primaryItemID }),
              let quote = quotes[primaryItemID] else { return "BitPrice" }
        return "\(item.symbol) \(Self.formatPrice(quote.price))"
    }

    static func formatPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = value >= 1 ? 2 : 6
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalString(value)
    }

    static func formatChange(_ change: QuoteChange) -> String {
        guard case .percent(let value) = change else { return "—" }
        // Two decimals, matching how venues quote 24-hour change. Rounding to a
        // whole number rendered a real +1.34% as "+1%", and anything under half
        // a percent as "+0%", which read as a parsing failure.
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        let number = NSDecimalNumber(decimal: value)
        guard let text = formatter.string(from: number) else { return "—" }
        return "\(text)%"
    }

    private func startNetworkWork() {
        feedController.replaceProducts(binanceProductIDs(in: persistedState))
        guard !persistedState.items.isEmpty else { return }
        reconcileFallbacks()
        refreshAllCharts()
        reconcilePeriodicLoops()
    }

    private func reconcilePeriodicLoops() {
        guard !items.isEmpty else {
            fallbackLoop?.cancel(); fallbackLoop = nil
            candleLoop?.cancel(); candleLoop = nil
            freshnessLoop?.cancel(); freshnessLoop = nil
            return
        }
        if fallbackLoop == nil {
            fallbackLoop = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do { try await self.suspendingClock.sleep(for: 60) } catch { return }
                    self.reconcileFallbacks()
                }
            }
        }
        if candleLoop == nil {
            candleLoop = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do { try await self.suspendingClock.sleep(for: 900) } catch { return }
                    self.refreshAllCharts()
                }
            }
        }
        if freshnessLoop == nil {
            freshnessLoop = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do { try await self.suspendingClock.sleep(for: 15) } catch { return }
                    self.freshnessPulse.toggle()
                    self.reconcileFallbacks()
                }
            }
        }
    }

    private func reconcileFallbacks() {
        for item in items {
            if isCoinbaseEligible(item) { requestFallbackIfEligible(itemID: item.id) }
            else { invalidateFallback(itemID: item.id) }
        }
    }

    private func requestFallbackIfEligible(itemID: UUID) {
        guard fallbackTasks[itemID] == nil,
              let item = items.first(where: { $0.id == itemID }),
              let productID = item.coinbaseMapping?.productID,
              isCoinbaseEligible(item) else { return }
        let token = FallbackRequestToken(
            requestID: UUID(), itemID: itemID, productID: productID,
            marketRevision: marketRevisions[itemID, default: 0], startedAt: continuousClock.now()
        )
        fallbackTokens[itemID] = token
        coinbaseActivity[itemID] = .requesting
        fallbackTasks[itemID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await self.restClients.coinbaseStats(productID: productID)
                guard self.fallbackTokens[itemID] == token,
                      let current = self.items.first(where: { $0.id == itemID }),
                      current.coinbaseMapping?.productID == token.productID,
                      self.isCoinbaseEligible(current),
                      self.marketRevisions[itemID, default: 0] == token.marketRevision,
                      self.continuousClock.now().seconds(since: token.startedAt) <= 15 else { return }
                let completed = self.continuousClock.now()
                let quote = Quote(
                    itemID: itemID, price: value.price, change: value.change, source: .coinbase,
                    eventDate: self.wallClock.now(), receivedInstant: completed
                )
                let oldSource = self.quotes[itemID]?.source
                self.quotes[itemID] = quote
                self.coinbaseActivity[itemID] = .succeeded
                self.evaluateAlert(item: current, quote: quote)
                if oldSource != .coinbase || self.charts[itemID]?.source != .coinbase {
                    self.marketRevisions[itemID, default: 0] &+= 1
                    self.refreshChart(itemID: itemID)
                }
            } catch {
                guard !Task.isCancelled, self.fallbackTokens[itemID] == token else { return }
                self.coinbaseActivity[itemID] = .failed(NetworkFailure.wrapping(error).message)
            }
            guard self.fallbackTokens[itemID] == token else { return }
            self.fallbackTasks[itemID] = nil
            self.fallbackTokens[itemID] = nil
        }
    }

    private func isCoinbaseEligible(_ item: WatchItem) -> Bool {
        guard item.coinbaseMapping != nil else { return false }
        guard item.binanceMapping != nil else { return true }
        guard connectionState == .connected,
              let quote = binanceQuotes[item.id] else { return true }
        return continuousClock.now().seconds(since: quote.receivedInstant) > 120
    }

    private func invalidateFallback(itemID: UUID) {
        fallbackTasks[itemID]?.cancel()
        fallbackTasks[itemID] = nil
        fallbackTokens[itemID] = nil
    }

    private func refreshAllCharts() {
        for item in items { refreshChart(itemID: item.id) }
    }

    private func refreshChart(itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              let selection = chartSelection(for: item) else { return }
        chartTasks[itemID]?.cancel()
        let end = wallClock.now()
        let start = end.addingTimeInterval(-86_400)
        let token = ChartRequestToken(
            requestID: UUID(), itemID: itemID, venue: selection.venue, productID: selection.mapping.productID,
            marketRevision: marketRevisions[itemID, default: 0], requestedStart: start, requestedEnd: end
        )
        chartTokens[itemID] = token
        chartTasks[itemID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let points: [CandlePoint]
                switch token.venue {
                case .binance:
                    points = try await self.restClients.binanceCandles(productID: token.productID, start: start, end: end)
                case .coinbase:
                    points = try await self.restClients.coinbaseCandles(productID: token.productID, start: start, end: end)
                }
                guard self.chartTokens[itemID] == token,
                      self.chartTokenStillMatches(token),
                      self.marketRevisions[itemID, default: 0] == token.marketRevision else { return }
                let series = ChartSeries(
                    source: token.venue, quoteAsset: selection.mapping.quoteAsset,
                    requestedStart: token.requestedStart, requestedEnd: token.requestedEnd,
                    points: points, receivedInstant: self.continuousClock.now(), latestRefreshFailed: false
                )
                guard self.chartTokens[itemID] == token, self.chartTokenStillMatches(token) else { return }
                self.charts[itemID] = series
            } catch {
                guard !Task.isCancelled, self.chartTokens[itemID] == token, self.chartTokenStillMatches(token) else { return }
                if var retained = self.charts[itemID] {
                    retained.latestRefreshFailed = true
                    self.charts[itemID] = retained
                }
            }
            guard self.chartTokens[itemID] == token else { return }
            self.chartTasks[itemID] = nil
        }
    }

    private func chartSelection(for item: WatchItem) -> (venue: Venue, mapping: VenueMapping)? {
        if quotes[item.id]?.source == .coinbase, let mapping = item.coinbaseMapping { return (.coinbase, mapping) }
        if quotes[item.id]?.source == .binance, let mapping = item.binanceMapping { return (.binance, mapping) }
        if let mapping = item.binanceMapping { return (.binance, mapping) }
        if let mapping = item.coinbaseMapping { return (.coinbase, mapping) }
        return nil
    }

    private func chartTokenStillMatches(_ token: ChartRequestToken) -> Bool {
        guard let item = items.first(where: { $0.id == token.itemID }) else { return false }
        let mapping = token.venue == .binance ? item.binanceMapping : item.coinbaseMapping
        return mapping?.productID == token.productID &&
            token.requestedStart < token.requestedEnd
    }

    private func evaluateAlert(item: WatchItem, quote: Quote) {
        guard !isReadOnly, let alert = item.alert else { return }
        let decision = AlertEngine.evaluate(itemID: item.id, alert: alert, price: quote.price, wallNow: wallClock.now())
        applyAlertDecision(decision, price: quote.price, symbol: item.symbol)
    }

    private func applyAlertDecision(_ decision: AlertDecision, price: Decimal, symbol: String) {
        let itemID: UUID
        let expected: PriceAlert?
        switch decision {
        case .noChange: return
        case .rearm(let id, let alert): itemID = id; expected = alert
        case .fire(let id, let alert, _): itemID = id; expected = alert
        }
        guard let index = persistedState.items.firstIndex(where: { $0.id == itemID }),
              persistedState.items[index].alert == expected else { return }
        var draft = persistedState
        switch decision {
        case .noChange: return
        case .rearm:
            draft.items[index].alert?.isArmed = true
        case .fire(_, _, let firedAt):
            draft.items[index].alert?.isArmed = false
            draft.items[index].alert?.lastFiredAt = firedAt
        }
        do {
            // Synchronous and await-free: no structural edit can interleave with this
            // full-state atomic replacement on the main actor.
            try persistenceStore.save(draft)
            persistedState = draft
        } catch {
            lastError = "Alert state could not be saved: \(error.localizedDescription)"
            return
        }
        if case .fire(_, _, let firedAt) = decision {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failure(let failure) = await self.notifications.submit(
                    itemID: itemID, symbol: symbol, price: price, firedAt: firedAt
                ) {
                    self.lastError = failure.message
                }
            }
        }
    }

    private func reconcileRuntimeAfterEdit(oldState: PersistedState, newState: PersistedState) {
        let newByID = Dictionary(uniqueKeysWithValues: newState.items.map { ($0.id, $0) })
        for oldItem in oldState.items {
            guard let newItem = newByID[oldItem.id] else {
                clearRuntime(itemID: oldItem.id)
                continue
            }
            if oldItem.binanceMapping != newItem.binanceMapping || oldItem.coinbaseMapping != newItem.coinbaseMapping {
                clearRuntime(itemID: oldItem.id)
                marketRevisions[oldItem.id, default: 0] &+= 1
            }
        }
        for item in newState.items where marketRevisions[item.id] == nil { marketRevisions[item.id] = 0 }
    }

    private func clearRuntime(itemID: UUID) {
        invalidateFallback(itemID: itemID)
        chartTasks[itemID]?.cancel()
        chartTasks[itemID] = nil
        chartTokens[itemID] = nil
        quotes[itemID] = nil
        binanceQuotes[itemID] = nil
        charts[itemID] = nil
        coinbaseActivity[itemID] = nil
        marketRevisions[itemID] = nil
    }

    private func cancelRESTAndLoops() {
        fallbackTasks.values.forEach { $0.cancel() }
        chartTasks.values.forEach { $0.cancel() }
        fallbackTasks.removeAll(); fallbackTokens.removeAll()
        chartTasks.removeAll(); chartTokens.removeAll()
        fallbackLoop?.cancel(); fallbackLoop = nil
        candleLoop?.cancel(); candleLoop = nil
        freshnessLoop?.cancel(); freshnessLoop = nil
    }

    private func binanceProductIDs(in state: PersistedState) -> Set<String> {
        Set(state.items.compactMap { $0.binanceMapping?.productID })
    }

    private func installSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shutdown() }
        }
    }
}
