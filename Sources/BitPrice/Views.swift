import AppKit
import SwiftUI

/// Which editor the panel is currently showing.
///
/// A `MenuBarExtra(.window)` panel closes as soon as it stops being the key
/// window, and presenting a `sheet` does exactly that. Editors are therefore
/// routed inline, replacing the panel's own content, instead of being presented
/// as separate windows.
enum PanelRoute: Equatable {
    case list
    case add
    case alert(WatchItem.ID)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var route: PanelRoute = .list
    @State private var confirmingQuit = false

    var body: some View {
        Group {
            switch route {
            case .list:
                listContent
            case .add:
                AddCoinView(model: model) { route = .list }
            case let .alert(itemID):
                if let item = model.items.first(where: { $0.id == itemID }) {
                    AlertEditorView(model: model, item: item) { route = .list }
                } else {
                    // The item was removed while its editor was open.
                    Color.clear.onAppear { route = .list }
                }
            }
        }
        .padding(12)
        .frame(width: 380, height: 520)
    }

    private var listContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text("BitPrice").font(.headline)
                if let presentation = model.aggregatePresentation {
                    Text(presentation.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(color(for: presentation))
                }
                Spacer()
                Button { route = .add } label: { Image(systemName: "plus") }
                    .disabled(model.isReadOnly || model.items.count >= maximumWatchlistCount)
                // LSUIElement hides the Dock icon and the app menu, so the panel
                // carries the only quit affordance the user has.
                // LSUIElement hides the Dock icon and the app menu, so the panel
                // carries the only quit affordance the user has.
                //
                // Deliberately no keyboard shortcut. A shortcut here made the
                // button eligible for the key event that dismissed the alert
                // editor, so saving an alert quit the app. Quitting is also
                // confirmed, because a single stray click ends the process.
                if confirmingQuit {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .foregroundStyle(.red)
                    Button("Cancel") { confirmingQuit = false }
                } else {
                    Button { confirmingQuit = true } label: {
                        Image(systemName: "power")
                    }
                    .help("Quit BitPrice")
                }
            }
            if let recovery = model.recoveryMessage {
                BannerView(text: recovery, color: .orange)
                Button("Reset protected file") { model.resetRecovery() }
            }
            if let error = model.lastError { BannerView(text: error, color: .red) }
            if model.items.isEmpty {
                ContentUnavailableView("No watched coins", systemImage: "bitcoinsign.circle", description: Text("Add a market to begin."))
                    .frame(height: 180)
            } else {
                List {
                    ForEach(model.items) { item in
                        WatchRow(model: model, item: item) { route = .alert(item.id) }
                    }
                    .onMove { source, destination in
                        do { try model.moveItems(fromOffsets: source, toOffset: destination) }
                        catch { /* AppModel keeps the durable error surface. */ }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            do { try model.removeItem(id: model.items[index].id) }
                            catch { break }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func color(for presentation: ConnectionPresentation) -> Color {
        switch presentation {
        case .live: .green
        case .stale: .orange
        case .offline: .red
        }
    }
}

private struct BannerView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct WatchRow: View {
    @ObservedObject var model: AppModel
    let item: WatchItem
    let editAlert: () -> Void

    var body: some View {
        let presentation = model.rowPresentation(for: item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    do { try model.setPrimary(item.id) } catch {}
                } label: {
                    Image(systemName: model.primaryItemID == item.id ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                Text(item.symbol).font(.headline)
                Text(model.quoteAsset(for: item)).font(.caption).foregroundStyle(.secondary)
                if presentation != .live {
                    Text(presentation.rawValue).font(.caption2).foregroundStyle(presentation == .stale ? .orange : .red)
                }
                Spacer()
                if let quote = model.quotes[item.id] {
                    VStack(alignment: .trailing) {
                        Text(AppModel.formatPrice(quote.price)).monospacedDigit()
                        Text(AppModel.formatChange(quote.change))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(changeColor(quote.change))
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if let chart = model.charts[item.id] {
                Sparkline(series: chart)
                    .frame(height: 42)
                HStack {
                    Text("24h chart · \(chart.source.rawValue.capitalized)/\(chart.quoteAsset)")
                    if chart.latestRefreshFailed { Text("refresh failed") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("24h chart unavailable").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("CG: \(item.coinGeckoID)")
                if let id = item.binanceMapping?.productID { Text("BN: \(id)") }
                if let id = item.coinbaseMapping?.productID { Text("CB: \(id)") }
                Spacer()
                Button("Alert", action: editAlert).buttonStyle(.link)
                Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(presentation == .stale ? 0.62 : 1)
    }

    private func changeColor(_ change: QuoteChange) -> Color {
        guard case .percent(let value) = change else { return .secondary }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }

    private func move(by offset: Int) {
        guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard model.items.indices.contains(destination) else { return }
        do { try model.moveItems(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? destination + 1 : destination) }
        catch {}
    }
}

private struct Sparkline: View {
    let series: ChartSeries

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard series.points.count >= 2 else { return }
                let values = series.points.map { NSDecimalNumber(decimal: $0.close).doubleValue }
                guard let minimum = values.min(), let maximum = values.max() else { return }
                let span = maximum - minimum
                var path = Path()
                var previousDate: Date?
                for (index, point) in series.points.enumerated() {
                    let xFraction = point.bucketStart.timeIntervalSince(series.requestedStart) /
                        series.requestedEnd.timeIntervalSince(series.requestedStart)
                    let value = values[index]
                    let yFraction = span == 0 ? 0.5 : (value - minimum) / span
                    let position = CGPoint(x: size.width * xFraction, y: size.height * (1 - yFraction))
                    if let previousDate, point.bucketStart.timeIntervalSince(previousDate) <= 5_400 {
                        path.addLine(to: position)
                    } else {
                        path.move(to: position)
                    }
                    previousDate = point.bucketStart
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            }
            .opacity(series.latestRefreshFailed ? 0.45 : 1)
        }
    }
}

private struct AddCoinView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var searchText = ""
    @State private var project: SearchResult?
    @State private var binanceCandidates: [VenueCandidate] = []
    @State private var coinbaseCandidates: [VenueCandidate] = []
    @State private var selectedBinance: String?
    @State private var selectedCoinbase: String?
    @State private var loadingCandidates = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project == nil ? "Add coin" : "Confirm markets").font(.headline)
                Spacer()
                Button("Cancel", action: close)
            }
            if let project {
                confirmation(project)
            } else {
                TextField("Search CoinGecko", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, value in model.search(query: value) }
                List(model.searchResults) { result in
                    Button {
                        choose(result)
                    } label: {
                        HStack {
                            Text(result.symbol).font(.headline)
                            VStack(alignment: .leading) {
                                Text(result.name)
                                Text(result.id).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private func confirmation(_ result: SearchResult) -> some View {
        Text("Candidates matched by ticker; verify the market.")
            .font(.callout).foregroundStyle(.orange)
        Text("\(result.name) (\(result.id))")
        if loadingCandidates {
            ProgressView()
        } else {
            candidatePicker(title: "Binance / USDT", candidates: binanceCandidates, selection: $selectedBinance)
            candidatePicker(title: "Coinbase / USD", candidates: coinbaseCandidates, selection: $selectedCoinbase)
            Text("Coinbase polling is every 60 seconds and can miss a brief alert breach.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Back") { project = nil }
                Spacer()
                Button("Add") { confirm(result) }
                    .disabled(selectedBinance == nil || selectedCoinbase == nil ||
                              selectedBinance == "__none__" && selectedCoinbase == "__none__")
            }
        }
    }

    /// Inline selection rather than a `Picker`.
    ///
    /// A `Picker`'s popup menu takes key status away from the `MenuBarExtra`
    /// window, which dismisses the whole panel. Every control here must resolve
    /// inside the panel itself.
    private func candidatePicker(title: String, candidates: [VenueCandidate], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            candidateRow(label: "No market", value: "__none__", selection: selection)
            ForEach(candidates) { candidate in
                candidateRow(
                    label: "\(candidate.productID) (\(candidate.baseAsset)/\(candidate.quoteAsset))",
                    value: candidate.productID,
                    selection: selection
                )
            }
            if candidates.isEmpty {
                Text("No ticker-matched candidates.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func candidateRow(label: String, value: String, selection: Binding<String?>) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.wrappedValue == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection.wrappedValue == value ? Color.accentColor : .secondary)
                Text(label).font(.caption)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ result: SearchResult) {
        project = result
        loadingCandidates = true
        selectedBinance = nil
        selectedCoinbase = nil
        Task { @MainActor in
            switch await model.loadCandidates(for: result) {
            case .success(let values):
                binanceCandidates = values.0
                coinbaseCandidates = values.1
            case .failure(let failure):
                localError = failure.message
            }
            loadingCandidates = false
        }
    }

    private func confirm(_ result: SearchResult) {
        let binance = binanceCandidates.first { $0.productID == selectedBinance }
        let coinbase = coinbaseCandidates.first { $0.productID == selectedCoinbase }
        let item = WatchItem(
            id: UUID(), coinGeckoID: result.id, symbol: result.symbol.uppercased(), name: result.name,
            binanceMapping: binance.map(mapping), coinbaseMapping: coinbase.map(mapping), alert: nil
        )
        do {
            try model.addItem(item)
            close()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func mapping(_ candidate: VenueCandidate) -> VenueMapping {
        VenueMapping(
            exchange: candidate.venue, productID: candidate.productID,
            baseAsset: candidate.baseAsset, quoteAsset: candidate.quoteAsset,
            provenance: .userConfirmedTickerMatch
        )
    }
}

private struct AlertEditorView: View {
    @ObservedObject var model: AppModel
    let item: WatchItem
    let close: () -> Void
    @State private var enabled: Bool
    @State private var direction: AlertDirection
    @State private var threshold: String
    @State private var cooldown: String
    @State private var hysteresis: String
    @State private var localError: String?

    init(model: AppModel, item: WatchItem, close: @escaping () -> Void) {
        self.model = model
        self.item = item
        self.close = close
        let alert = item.alert
        _enabled = State(initialValue: alert?.isEnabled ?? false)
        _direction = State(initialValue: alert?.direction ?? .above)
        _threshold = State(initialValue: alert.map { decimalString($0.threshold) } ?? "")
        _cooldown = State(initialValue: String(alert?.cooldownSeconds ?? 0))
        _hysteresis = State(initialValue: alert.map { decimalString($0.hysteresisPercent) } ?? "0")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alert · \(item.symbol)").font(.headline)
                Spacer()
                Button("Cancel", action: close)
            }
            Toggle("Enabled", isOn: $enabled)
            // Segmented style renders inline; a menu-style Picker would take key
            // status from the MenuBarExtra window and dismiss the panel.
            Picker("Direction", selection: $direction) {
                Text("Above").tag(AlertDirection.above)
                Text("Below").tag(AlertDirection.below)
            }
            .pickerStyle(.segmented)
            LabeledContent("Threshold") { TextField("", text: $threshold).textFieldStyle(.roundedBorder) }
            LabeledContent("Cooldown seconds") { TextField("", text: $cooldown).textFieldStyle(.roundedBorder) }
            LabeledContent("Hysteresis percent") { TextField("", text: $hysteresis).textFieldStyle(.roundedBorder) }
            rearmExplanation
            if let alert = item.alert, alert.isEnabled, !alert.isArmed {
                Text("Currently disarmed — it already fired and is waiting for the re-arm price above.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Coinbase polls every 60 seconds and can miss a brief breach.")
                .font(.caption).foregroundStyle(.secondary)
            if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
            Spacer()
            HStack {
                Button("Remove alert") { remove() }
                Spacer()
                // No .defaultAction: the editor is replaced by the list view on
                // save, and the same key event would then reach whatever became
                // the default control there.
                Button("Save") { save() }
            }
        }
    }

    /// Spells out the re-arm price.
    ///
    /// Hysteresis is a percentage, so its real effect is invisible until it is
    /// converted back into a price: 1% on a 63,966 threshold means the alert
    /// stays silent until the price falls 640. Without this line the alert
    /// looks broken — it fires once and never again.
    @ViewBuilder
    private var rearmExplanation: some View {
        if let thresholdValue = finiteDecimal(from: threshold),
           let hysteresisValue = finiteDecimal(from: hysteresis),
           thresholdValue > 0 {
            let fraction = hysteresisValue / 100
            let boundary = direction == .above
                ? thresholdValue * (1 - fraction)
                : thresholdValue * (1 + fraction)
            VStack(alignment: .leading, spacing: 2) {
                Text(direction == .above
                     ? "Fires above \(AppModel.formatPrice(thresholdValue))."
                     : "Fires below \(AppModel.formatPrice(thresholdValue)).")
                Text(direction == .above
                     ? "Silent until the price falls below \(AppModel.formatPrice(boundary)), then it can fire again."
                     : "Silent until the price rises above \(AppModel.formatPrice(boundary)), then it can fire again.")
                if hysteresisValue == 0 {
                    Text("Hysteresis 0 re-arms as soon as the price crosses back; cooldown alone limits repeats.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let thresholdValue = finiteDecimal(from: threshold),
              let cooldownValue = Int(cooldown),
              let hysteresisValue = finiteDecimal(from: hysteresis) else {
            localError = "Enter valid decimal and integer values."
            return
        }
        let prior = item.alert
        let alert = PriceAlert(
            direction: direction, threshold: thresholdValue, cooldownSeconds: cooldownValue,
            hysteresisPercent: hysteresisValue, isEnabled: enabled,
            isArmed: prior?.isArmed ?? true, lastFiredAt: prior?.lastFiredAt
        )
        do { try model.saveAlert(itemID: item.id, proposed: alert); close() }
        catch { localError = error.localizedDescription }
    }

    private func remove() {
        do { try model.saveAlert(itemID: item.id, proposed: nil); close() }
        catch { localError = error.localizedDescription }
    }
}
