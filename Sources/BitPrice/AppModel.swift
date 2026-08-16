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
final class PriceFeedCoordinator: PriceFeedSink {
    private let feeds: [any PriceFeed]
    private weak var sink: (any PriceFeedSink)?

    init(feeds: [any PriceFeed]) {
        self.feeds = feeds
    }

    func attachSink(_ sink: any PriceFeedSink) {
        self.sink = sink
        for feed in feeds { feed.attachSink(self) }
    }

    func replaceProducts(_ productIDsByVenue: [Venue: Set<String>]) {
        for feed in feeds {
            feed.replaceProducts(productIDsByVenue[feed.venue] ?? [])
        }
    }

    func suspendForSleep() {
        for feed in feeds { feed.suspendForSleep() }
    }

    func resumeAfterWake() {
        for feed in feeds { feed.resumeAfterWake() }
    }

    func shutdown() {
        for feed in feeds { feed.shutdown() }
    }

    func feedDidAccept(_ tick: PriceTick) {
        sink?.feedDidAccept(tick)
    }

    func feedStateDidChange(_ state: FeedLifecycle, venue: Venue) {
        sink?.feedStateDidChange(state, venue: venue)
    }
}

@MainActor
final class AppModel: ObservableObject, PriceFeedSink {
    @Published private(set) var persistedState: PersistedState
    @Published private(set) var quotes: [UUID: Quote] = [:]
    @Published private(set) var charts: [UUID: ChartSeries] = [:]
    /// Rows whose most recent chart request failed with nothing already drawn.
    /// Kept apart from `charts` because there is no series to attach it to.
    @Published private(set) var chartFailures: Set<UUID> = []
    @Published private(set) var connectionStates: [Venue: FeedLifecycle] = [:]
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchActivity: RequestActivity = .idle
    @Published private(set) var sourceActivity: [UUID: RequestActivity] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var freshnessPulse = false

    let persistenceStore: PersistenceStore
    private let processLock: ProcessLock
    private let restClients: RESTClients
    private let priceSources: [any PriceSource]
    private let priceSourcesByVenue: [Venue: any PriceSource]
    private let feedCoordinator: PriceFeedCoordinator
    private let notifications: any NotificationSubmitting
    private let wallClock: any WallClock
    private let continuousClock: any ContinuousTimeSource
    private let suspendingClock: any SuspendingTimeSource

    private var persistenceMode: PersistenceMode = .writable
    private var marketRevisions: [UUID: UInt64] = [:]
    private var quoteRequestIDs: [UUID: UUID] = [:]
    private var chartTokens: [UUID: ChartRequestToken] = [:]
    private var quoteTasks: [UUID: Task<Void, Never>] = [:]
    private var chartTasks: [UUID: Task<Void, Never>] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchRequestID: UUID?
    private var quoteLoops: [Venue: Task<Void, Never>] = [:]
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
    var alertsEnabled: Bool { persistedState.alertsEnabled }

    init(
        persistenceStore: PersistenceStore,
        processLock: ProcessLock,
        restClients: RESTClients,
        priceSources: [any PriceSource]? = nil,
        priceFeeds: [any PriceFeed],
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
        let sources = priceSources ?? configuredPriceSources(clients: restClients)
        self.priceSources = sources
        self.priceSourcesByVenue = Dictionary(sources.map { ($0.venue, $0) }, uniquingKeysWith: { first, _ in first })
        self.feedCoordinator = PriceFeedCoordinator(feeds: priceFeeds)
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
            // Three lines, and each earns its place: what went wrong, where the
            // untouched file is, and whether pressing the button below costs
            // anything. A longer version was tried on the desktop and swallowed
            // the top of the panel — the reason and the path are what a user
            // needs, and the situation sentence merely restated the reason in
            // other words. The button label carries the rest.
            //
            // The read-failure branch hands back empty bytes because it never got
            // to read the file. Promising a copy of them would be a lie, and it is
            // the one case where starting over saves nothing aside.
            let copyLine = originalBytes.isEmpty
                ? "It cannot be read, so starting over saves no copy."
                : "Starting over saves a copy alongside it first."
            recoveryMessage = """
            \(reason). Your watchlist was not loaded.
            \(persistenceStore.stateURL.path)
            \(copyLine)
            """
        }
        for item in persistedState.items { marketRevisions[item.id] = 0 }
        feedCoordinator.attachSink(self)
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
        let feeds: [any PriceFeed] = [
            BinanceFeedController(
                sessionFactory: SystemWebSocketSessionFactory(),
                continuousClock: continuousClock,
                suspendingClock: suspendingClock
            ),
            OKXFeed(
                sessionFactory: SystemWebSocketSessionFactory(),
                continuousClock: continuousClock,
                suspendingClock: suspendingClock
            )
        ]
        return AppModel(
            persistenceStore: store,
            processLock: lock,
            restClients: clients,
            priceFeeds: feeds,
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
        feedCoordinator.replaceProducts(productIDsByVenue(in: draft))
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
        requestQuoteIfNeeded(itemID: item.id)
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

    func setAlertsEnabled(_ enabled: Bool) throws {
        try commitEdit { draft in
            draft.alertsEnabled = enabled
        }
    }

    func setChartRange(_ range: ChartRange, for itemID: UUID) throws {
        guard persistedState.chartRange != range else { return }
        do {
            try commitEdit { draft in
                draft.chartRange = range
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        lastError = nil
        // The range is one global setting, so every chart is now at the wrong
        // range -- not only the row whose picker was used. Clearing just that row
        // left the others holding a stale series that nothing re-requested until
        // their view happened to appear again, which for a row already on screen
        // is never.
        for item in items { charts[item.id] = nil }
        refreshAllCharts()
    }

    func refreshChartIfNeeded(for itemID: UUID) {
        guard charts[itemID]?.range != persistedState.chartRange,
              chartTasks[itemID] == nil else { return }
        refreshChart(itemID: itemID)
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
            try persistenceStore.backupRecoveryFile()
            try persistenceStore.save(seed, allowRecoveryReset: true)
            persistedState = seed
            persistenceMode = .writable
            recoveryMessage = nil
            lastError = nil
            quotes.removeAll()
            charts.removeAll()
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

    func loadCandidates(for result: SearchResult) async -> Result<[VenueCandidate], NetworkFailure> {
        do {
            let candidates = try await withThrowingTaskGroup(of: [VenueCandidate].self) { group in
                for source in priceSources {
                    group.addTask { try await source.candidates(symbol: result.symbol) }
                }
                var combined: [VenueCandidate] = []
                for try await values in group { combined.append(contentsOf: values) }
                return combined
            }
            return .success(VenueCandidateOrdering.sorted(candidates))
        } catch {
            return .failure(NetworkFailure.wrapping(error))
        }
    }

    func feedDidAccept(_ tick: PriceTick) {
        guard let item = persistedState.items.first(where: {
            $0.mapping?.exchange == tick.venue && $0.mapping?.productID == tick.productID
        }), let mapping = item.mapping else { return }
        // Deliberately does NOT bump marketRevisions. That counter means "this
        // row now points at a different market", which is what makes an in-flight
        // chart request stale. A new price on the same market is not that, and
        // bumping it here discarded any chart request slower than the next tick --
        // on a push feed, most of them.
        let quote = Quote(
            itemID: item.id,
            price: tick.price,
            change: .percent(tick.changePercent),
            source: mapping.exchange,
            eventDate: tick.eventDate,
            receivedInstant: tick.receivedInstant
        )
        let hadQuote = quotes[item.id] != nil
        quotes[item.id] = quote
        evaluateAlert(item: item, quote: quote)
        // The first tick draws the chart for a row that has none. Going through
        // refreshChart directly would cancel the request already in flight from
        // startup and start it over, and on a busy market the next first-tick
        // could do it again -- so the chart was repeatedly restarted rather than
        // finished. refreshChartIfNeeded leaves an in-flight request alone.
        if !hadQuote { refreshChartIfNeeded(for: item.id) }
    }

    func feedStateDidChange(_ state: FeedLifecycle, venue: Venue) {
        connectionStates[venue] = state
    }

    func handleSleep() {
        searchTask?.cancel()
        searchTask = nil
        searchRequestID = nil
        cancelRESTAndLoops()
        feedCoordinator.suspendForSleep()
    }

    func handleWake() {
        freshnessPulse.toggle()
        feedCoordinator.resumeAfterWake()
        pollQuotes()
        refreshAllCharts()
        reconcilePeriodicLoops()
    }

    func shutdown() {
        cancelRESTAndLoops()
        feedCoordinator.shutdown()
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
        item.mapping?.quoteAsset ?? ""
    }

    func sourceLiveness(for venue: Venue) -> SourceLiveness? {
        priceSourcesByVenue[venue]?.liveness
    }

    var configuredSourceNames: String {
        let names = priceSources.map { $0.venue.displayName }
        guard let last = names.last else { return "configured sources" }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }

    func rowPresentation(for item: WatchItem) -> ConnectionPresentation {
        guard let source = primaryVenue(for: item),
              let liveness = sourceLiveness(for: source) else { return .offline }
        let connectionState = connectionStates[source] ?? .stopped
        if let quote = quotes[item.id] {
            // A 60-second poll plus request latency can approach the push-feed
            // window; retaining 120 seconds avoids marking a normal polling
            // cycle stale while preserving the existing freshness semantics.
            let fresh = continuousClock.now().seconds(since: quote.receivedInstant) <= 120
            guard quote.source == source else { return .stale }
            switch liveness {
            case .push:
                return fresh && connectionState == .connected ? .live : .stale
            case .polled:
                return fresh ? .live : .stale
            }
        }
        switch liveness {
        case .push:
            if connectionState == .connecting || connectionState == .connected { return .stale }
            return .offline
        case .polled:
            return sourceActivity[item.id] == .requesting ? .stale : .offline
        }
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
        feedCoordinator.replaceProducts(productIDsByVenue(in: persistedState))
        guard !persistedState.items.isEmpty else { return }
        pollQuotes()
        refreshAllCharts()
        reconcilePeriodicLoops()
    }

    private func reconcilePeriodicLoops() {
        guard !items.isEmpty else {
            quoteLoops.values.forEach { $0.cancel() }; quoteLoops.removeAll()
            candleLoop?.cancel(); candleLoop = nil
            freshnessLoop?.cancel(); freshnessLoop = nil
            return
        }
        for source in priceSources {
            guard case .polled(let seconds) = source.liveness,
                  seconds > 0,
                  quoteLoops[source.venue] == nil else { continue }
            let venue = source.venue
            quoteLoops[venue] = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do { try await self.suspendingClock.sleep(for: TimeInterval(seconds)) } catch { return }
                    self.pollQuotes(from: venue)
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
                }
            }
        }
    }

    private func pollQuotes() {
        for source in priceSources where source.liveness != .push {
            pollQuotes(from: source.venue)
        }
    }

    private func pollQuotes(from venue: Venue) {
        for item in items where primaryVenue(for: item) == venue {
            requestQuoteIfNeeded(itemID: item.id)
        }
    }

    private func requestQuoteIfNeeded(itemID: UUID) {
        guard quoteTasks[itemID] == nil,
              let item = items.first(where: { $0.id == itemID }),
              let mapping = item.mapping,
              let source = priceSourcesByVenue[mapping.exchange],
              case .polled = source.liveness else { return }

        let revision = marketRevisions[itemID, default: 0]
        let requestID = UUID()
        quoteRequestIDs[itemID] = requestID
        sourceActivity[itemID] = .requesting
        quoteTasks[itemID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.quoteRequestIDs[itemID] == requestID {
                    self.quoteTasks[itemID] = nil
                    self.quoteRequestIDs[itemID] = nil
                }
            }
            do {
                let value = try await source.quote(productID: mapping.productID)
                guard !Task.isCancelled,
                      self.quoteRequestIDs[itemID] == requestID,
                      let current = self.items.first(where: { $0.id == itemID }),
                      current.mapping?.exchange == source.venue,
                      current.mapping?.productID == mapping.productID,
                      self.marketRevisions[itemID, default: 0] == revision else { return }
                let completed = self.continuousClock.now()
                let quote = Quote(
                    itemID: itemID, price: value.price, change: value.change, source: source.venue,
                    eventDate: self.wallClock.now(), receivedInstant: completed
                )
                self.quotes[itemID] = quote
                self.sourceActivity[itemID] = .succeeded
                self.evaluateAlert(item: current, quote: quote)
            } catch {
                guard !Task.isCancelled, self.quoteRequestIDs[itemID] == requestID else { return }
                self.sourceActivity[itemID] = .failed(NetworkFailure.wrapping(error).message)
            }
        }
    }

    private func refreshAllCharts() {
        for item in items { refreshChart(itemID: item.id) }
    }

    private func refreshChart(itemID: UUID) {
        let range = persistedState.chartRange
        guard let item = items.first(where: { $0.id == itemID }),
              let selection = chartSelection(for: item, range: range) else { return }
        chartTasks[itemID]?.cancel()
        let end = wallClock.now()
        let start = end.addingTimeInterval(-range.lookbackSeconds)
        let token = ChartRequestToken(
            requestID: UUID(), itemID: itemID, venue: selection.source.venue, productID: selection.mapping.productID,
            range: range, marketRevision: marketRevisions[itemID, default: 0], requestedStart: start, requestedEnd: end
        )
        chartTokens[itemID] = token
        chartFailures.remove(itemID)
        chartTasks[itemID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let points = try await selection.source.candles(
                    productID: token.productID, range: token.range, start: start, end: end
                )
                guard self.chartTokens[itemID] == token,
                      self.chartTokenStillMatches(token),
                      self.marketRevisions[itemID, default: 0] == token.marketRevision else { return }
                let series = ChartSeries(
                    source: token.venue, quoteAsset: selection.mapping.quoteAsset,
                    range: token.range,
                    requestedStart: token.requestedStart, requestedEnd: token.requestedEnd,
                    points: points, receivedInstant: self.continuousClock.now(), latestRefreshFailed: false
                )
                guard self.chartTokens[itemID] == token, self.chartTokenStillMatches(token) else { return }
                self.charts[itemID] = series
                self.chartFailures.remove(itemID)
            } catch {
                guard !Task.isCancelled, self.chartTokens[itemID] == token, self.chartTokenStillMatches(token) else { return }
                if var retained = self.charts[itemID] {
                    retained.latestRefreshFailed = true
                    self.charts[itemID] = retained
                } else {
                    // Nothing to mark as stale, because nothing was ever drawn.
                    // Without this the row is indistinguishable from one that is
                    // still loading, and stays that way.
                    self.chartFailures.insert(itemID)
                }
            }
            guard self.chartTokens[itemID] == token else { return }
            self.chartTasks[itemID] = nil
        }
    }

    private func chartSelection(
        for item: WatchItem,
        range: ChartRange
    ) -> (source: any PriceSource, mapping: VenueMapping)? {
        guard let mapping = item.mapping,
              let source = priceSourcesByVenue[mapping.exchange],
              source.supports(range) else { return nil }
        return (source, mapping)
    }

    private func primaryVenue(for item: WatchItem) -> Venue? {
        item.mapping?.exchange
    }

    private func chartTokenStillMatches(_ token: ChartRequestToken) -> Bool {
        guard let item = items.first(where: { $0.id == token.itemID }) else { return false }
        return item.mapping?.exchange == token.venue &&
            item.mapping?.productID == token.productID &&
            token.range == persistedState.chartRange &&
            token.requestedStart < token.requestedEnd
    }

    private func evaluateAlert(item: WatchItem, quote: Quote) {
        guard !isReadOnly, persistedState.alertsEnabled, let alert = item.alert else { return }
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
        var mappingChanged = false
        for oldItem in oldState.items {
            guard let newItem = newByID[oldItem.id] else {
                clearRuntime(itemID: oldItem.id)
                continue
            }
            if oldItem.mapping != newItem.mapping {
                clearRuntime(itemID: oldItem.id)
                marketRevisions[oldItem.id, default: 0] &+= 1
                mappingChanged = true
            }
        }
        for item in newState.items where marketRevisions[item.id] == nil { marketRevisions[item.id] = 0 }
        if mappingChanged { pollQuotes() }
    }

    private func clearRuntime(itemID: UUID) {
        quoteTasks[itemID]?.cancel()
        quoteTasks[itemID] = nil
        quoteRequestIDs[itemID] = nil
        chartTasks[itemID]?.cancel()
        chartTasks[itemID] = nil
        chartTokens[itemID] = nil
        quotes[itemID] = nil
        charts[itemID] = nil
        sourceActivity[itemID] = nil
        marketRevisions[itemID] = nil
    }

    private func cancelRESTAndLoops() {
        quoteTasks.values.forEach { $0.cancel() }
        chartTasks.values.forEach { $0.cancel() }
        quoteTasks.removeAll(); quoteRequestIDs.removeAll()
        for itemID in Array(sourceActivity.keys) { sourceActivity[itemID] = .idle }
        chartTasks.removeAll(); chartTokens.removeAll()
        quoteLoops.values.forEach { $0.cancel() }; quoteLoops.removeAll()
        candleLoop?.cancel(); candleLoop = nil
        freshnessLoop?.cancel(); freshnessLoop = nil
    }

    private func productIDsByVenue(in state: PersistedState) -> [Venue: Set<String>] {
        var result: [Venue: Set<String>] = [:]
        for mapping in state.items.compactMap(\.mapping) {
            result[mapping.exchange, default: []].insert(mapping.productID)
        }
        return result
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
