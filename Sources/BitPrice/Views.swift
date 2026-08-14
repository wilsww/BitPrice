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
    case settings
}

struct ChartPriceBounds: Equatable {
    let minimum: Decimal
    let maximum: Decimal
}

private extension TextSizePreference {
    var panelWidth: CGFloat {
        switch self {
        case .small: 560
        case .medium: 660
        case .large: 760
        case .extraLarge: 860
        }
    }

    var panelHeight: CGFloat {
        switch self {
        case .small: 700
        case .medium: 780
        case .large: 880
        case .extraLarge: 980
        }
    }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

enum PanelFont {
    static func multiplier(for preference: TextSizePreference) -> CGFloat {
        switch preference {
        case .small: 0.85
        case .medium: 1.0
        case .large: 1.2
        case .extraLarge: 1.45
        }
    }

    static func basePointSize(for style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: appKitTextStyle(for: style)).pointSize
    }

    static func pointSize(for style: Font.TextStyle, preference: TextSizePreference) -> CGFloat {
        basePointSize(for: style) * multiplier(for: preference)
    }

    static func scaledFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        preference: TextSizePreference
    ) -> Font {
        let defaultWeight: Font.Weight = style == .headline ? .semibold : .regular
        return .system(size: pointSize(for: style, preference: preference), weight: weight ?? defaultWeight)
    }

    private static func appKitTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
        if style == .largeTitle { return .largeTitle }
        if style == .title { return .title1 }
        if style == .title2 { return .title2 }
        if style == .title3 { return .title3 }
        if style == .headline { return .headline }
        if style == .subheadline { return .subheadline }
        if style == .callout { return .callout }
        if style == .footnote { return .footnote }
        if style == .caption { return .caption1 }
        if style == .caption2 { return .caption2 }
        return .body
    }
}

private struct PanelTextSizeKey: EnvironmentKey {
    static let defaultValue = TextSizePreference.medium
}

private extension EnvironmentValues {
    var panelTextSize: TextSizePreference {
        get { self[PanelTextSizeKey.self] }
        set { self[PanelTextSizeKey.self] = newValue }
    }
}

private struct PanelFontModifier: ViewModifier {
    @Environment(\.panelTextSize) private var panelTextSize
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(PanelFont.scaledFont(style, weight: weight, preference: panelTextSize))
    }
}

private extension View {
    func panelFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(PanelFontModifier(style: style, weight: weight))
    }
}

/// Presentation-only axis values derived from the chart points themselves.
///
/// Keeping this calculation separate from drawing makes the flat and sparse
/// cases explicit and lets the acceptance tests cover them without a GUI.
enum ChartAxisCalculator {
    static func priceBounds(for points: [CandlePoint]) -> ChartPriceBounds? {
        guard let minimum = points.map(\.close).min(),
              let maximum = points.map(\.close).max() else { return nil }
        return ChartPriceBounds(minimum: minimum, maximum: maximum)
    }

    static func pricePrecision(for points: [CandlePoint], desiredCount: Int = 4) -> Int {
        guard let bounds = priceBounds(for: points) else { return 0 }
        guard bounds.minimum != bounds.maximum else {
            return decimalFractionDigits(bounds.minimum)
        }
        let tickCount = min(5, max(3, desiredCount))
        let step = (bounds.maximum - bounds.minimum) / Decimal(tickCount - 1)
        let stepDouble = abs(NSDecimalNumber(decimal: step).doubleValue)
        guard stepDouble.isFinite, stepDouble > 0 else { return 0 }

        var precision = max(0, Int(ceil(-log10(stepDouble))) + 1)
        let rawTicks = (0..<tickCount).map { index in
            bounds.minimum + step * Decimal(index)
        }
        while precision < 12 {
            let rounded = rawTicks.map { round($0, fractionDigits: precision) }
            if Set(rounded).count == rounded.count { break }
            precision += 1
        }
        return precision
    }

    static func priceTicks(for points: [CandlePoint], desiredCount: Int = 4) -> [Decimal] {
        guard let bounds = priceBounds(for: points) else { return [] }
        guard bounds.minimum != bounds.maximum else { return [bounds.minimum] }

        let tickCount = min(5, max(3, desiredCount))
        let step = (bounds.maximum - bounds.minimum) / Decimal(tickCount - 1)
        let precision = pricePrecision(for: points, desiredCount: desiredCount)
        return (0..<tickCount).map { index in
            round(bounds.minimum + step * Decimal(index), fractionDigits: precision)
        }
    }

    static func formattedPrice(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalString(value)
    }

    static func timeTicks(for points: [CandlePoint]) -> [Date] {
        let dates = points.map(\.bucketStart).sorted()
        guard let start = dates.first, let end = dates.last else { return [] }
        guard start != end else { return [start] }

        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        let middle = dates.min { left, right in
            let leftDistance = abs(left.timeIntervalSince(midpoint))
            let rightDistance = abs(right.timeIntervalSince(midpoint))
            return leftDistance == rightDistance ? left < right : leftDistance < rightDistance
        }

        var ticks = [start]
        if let middle, middle > start, middle < end { ticks.append(middle) }
        ticks.append(end)
        return ticks
    }

    static func priceFraction(_ value: Decimal, minimum: Decimal, maximum: Decimal) -> Double {
        guard minimum != maximum else { return 0.5 }
        let numerator = NSDecimalNumber(decimal: value - minimum).doubleValue
        let denominator = NSDecimalNumber(decimal: maximum - minimum).doubleValue
        return numerator / denominator
    }

    static func timeFraction(_ value: Date, start: Date, end: Date) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration != 0 else { return 0.5 }
        return value.timeIntervalSince(start) / duration
    }

    private static func round(_ value: Decimal, fractionDigits: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, fractionDigits, .plain)
        return result
    }

    private static func decimalFractionDigits(_ value: Decimal) -> Int {
        let text = decimalString(value)
        guard let separator = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: text.index(after: separator), to: text.endIndex)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var route: PanelRoute = .list
    @State private var selectedItemID: WatchItem.ID?

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
            case .settings:
                SettingsView(model: model) { route = .list }
            }
        }
        .padding(16)
        .environment(\.panelTextSize, model.persistedState.textSize)
        .frame(
            width: model.persistedState.textSize.panelWidth,
            height: model.persistedState.textSize.panelHeight
        )
        .onAppear { reconcileSelection() }
        .onChange(of: model.items.map(\.id)) { _, _ in reconcileSelection() }
    }

    private var listContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text("BitPrice").panelFont(.title3, weight: .bold)
                if let presentation = model.aggregatePresentation {
                    Text(presentation.rawValue)
                        .panelFont(.body, weight: .bold)
                        .foregroundStyle(color(for: presentation))
                }
                Spacer()
                Button { route = .add } label: { Image(systemName: "plus.circle") }
                    .panelFont(.title2)
                    .disabled(model.isReadOnly || model.items.count >= maximumWatchlistCount)
                Button { route = .settings } label: { Image(systemName: "gearshape.circle") }
                    .panelFont(.title2)
                    .help("Settings")
            }
            if let recovery = model.recoveryMessage {
                BannerView(text: recovery, color: .orange)
                Button("Reset protected file") { model.resetRecovery() }
            }
            if let error = model.lastError { BannerView(text: error, color: .red) }
            if model.items.isEmpty {
                ContentUnavailableView("No watched coins", systemImage: "bitcoinsign.circle", description: Text("Add a market to begin."))
                    .frame(maxHeight: .infinity)
                Divider()
                EmptyDetailView(hasItems: false)
                    .frame(height: 350)
            } else {
                List(selection: $selectedItemID) {
                    ForEach(model.items) { item in
                        WatchRow(model: model, item: item) { route = .alert(item.id) }
                            .tag(item.id)
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
                .frame(maxHeight: .infinity)
                Divider()
                if let selectedItem {
                    ScrollView {
                        SelectedCoinDetail(model: model, item: selectedItem) {
                            removeSelectedItem()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 350)
                } else {
                    EmptyDetailView(hasItems: true)
                        .frame(height: 350)
                }
            }
        }
    }

    private var selectedItem: WatchItem? {
        guard let selectedItemID else { return nil }
        return model.items.first { $0.id == selectedItemID }
    }

    private func reconcileSelection() {
        if let selectedItemID, model.items.contains(where: { $0.id == selectedItemID }) { return }
        if let primaryItemID = model.primaryItemID,
           model.items.contains(where: { $0.id == primaryItemID }) {
            selectedItemID = primaryItemID
        } else {
            selectedItemID = model.items.first?.id
        }
    }

    private func removeSelectedItem() {
        guard let selectedItemID else { return }
        do {
            try model.removeItem(id: selectedItemID)
            reconcileSelection()
        } catch {
            // AppModel retains the durable error surface.
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

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("Settings")
                    .panelFont(.title2, weight: .bold)
                HStack {
                    Button { close() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .panelFont(.headline)
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Quit BitPrice", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                    .panelFont(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Price alerts")
                        .panelFont(.headline, weight: .bold)
                    Toggle("", isOn: alertsBinding)
                        .panelFont(.headline)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Enable price alerts")
                        .disabled(model.isReadOnly)
                    Text("Turning alerts back on can fire immediately for a coin already past its threshold.")
                        .panelFont(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text size")
                        .panelFont(.headline, weight: .bold)
                    Picker("", selection: textSizeBinding) {
                        ForEach(TextSizePreference.allCases, id: \.self) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .panelFont(.headline)
                    .labelsHidden()
                    .accessibilityLabel("Text size")
                    Text("Scales text throughout the panel; the panel grows with it.")
                        .panelFont(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer(minLength: 14)

            Text("Price updates and alerts stop while the app is closed.")
                .panelFont(.body)
                .foregroundStyle(.secondary)
            if let localError {
                Text(localError)
                    .panelFont(.body)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { model.alertsEnabled },
            set: { enabled in
                do { try model.setAlertsEnabled(enabled) }
                catch { localError = error.localizedDescription }
            }
        )
    }

    private var textSizeBinding: Binding<TextSizePreference> {
        Binding(
            get: { model.persistedState.textSize },
            set: { preference in
                do {
                    try model.commitEdit { draft in draft.textSize = preference }
                    localError = nil
                } catch {
                    localError = error.localizedDescription
                }
            }
        )
    }
}

private struct BannerView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .panelFont(.body)
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
        let isPrimary = model.primaryItemID == item.id
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Button {
                    do { try model.setPrimary(item.id) } catch {}
                } label: {
                    Image(systemName: isPrimary ? "star.fill" : "star")
                        .panelFont(.title2)
                        .foregroundStyle(isPrimary ? Color.yellow : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.borderless)
                .help(isPrimary ? "Currently shown in the menu bar" : "Show this coin in the menu bar")
                Text(item.symbol)
                    .panelFont(.title, weight: .bold)
                    .lineLimit(1)
                Text(model.quoteAsset(for: item))
                    .panelFont(.headline)
                    .foregroundStyle(.secondary)
                if presentation != .live {
                    Text(presentation.rawValue)
                        .panelFont(.body, weight: .bold)
                        .foregroundStyle(presentation == .stale ? .orange : .red)
                }
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            if let quote = model.quotes[item.id] {
                Text(AppModel.formatPrice(quote.price))
                    .panelFont(.title2, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 170, alignment: .trailing)
            } else {
                Text("—")
                    .panelFont(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 170, alignment: .trailing)
            }

            VStack(alignment: .trailing, spacing: 3) {
                if let quote = model.quotes[item.id] {
                    Text(AppModel.formatChange(quote.change))
                        .panelFont(.title3)
                        .monospacedDigit()
                        .foregroundStyle(changeColor(quote.change))
                } else {
                    Text("—")
                        .panelFont(.title3)
                        .foregroundStyle(.secondary)
                }
                Button(action: editAlert) {
                    Text(model.alertsEnabled ? "Alert" : "Alert · Off")
                        .panelFont(.headline)
                        .foregroundStyle(model.alertsEnabled ? .primary : .secondary)
                        .strikethrough(!model.alertsEnabled)
                }
                .buttonStyle(.borderless)
            }
            .frame(width: 105, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .opacity(presentation == .stale ? 0.62 : 1)
    }

    private func changeColor(_ change: QuoteChange) -> Color {
        guard case .percent(let value) = change else { return .secondary }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }

}

private struct EmptyDetailView: View {
    let hasItems: Bool

    var body: some View {
        ContentUnavailableView(
            hasItems ? "Select a coin" : "No coin details",
            systemImage: "chart.xyaxis.line",
            description: Text(hasItems ? "Select a row to inspect its chart and market mappings." : "Add a market to inspect its chart and mappings.")
        )
    }
}

private struct SelectedCoinDetail: View {
    @ObservedObject var model: AppModel
    let item: WatchItem
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(item.symbol) details")
                    .panelFont(.title2, weight: .bold)
                Text(model.quoteAsset(for: item))
                    .panelFont(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { move(by: -1) } label: {
                    Image(systemName: "chevron.up")
                        .panelFont(.title2)
                }
                    .buttonStyle(.borderless)
                    .disabled(itemIndex == 0)
                    .help("Move up")
                Button { move(by: 1) } label: {
                    Image(systemName: "chevron.down")
                        .panelFont(.title2)
                }
                    .buttonStyle(.borderless)
                    .disabled(itemIndex == nil || itemIndex == model.items.count - 1)
                    .help("Move down")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                        .panelFont(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(model.isReadOnly)
                .help("Remove \(item.symbol)")
            }

            if let chart = model.charts[item.id] {
                Sparkline(series: chart)
                    .frame(height: 200)
                Text("24h chart · \(chart.source.rawValue.capitalized)/\(chart.quoteAsset)")
                    .panelFont(.body)
                    .foregroundStyle(.secondary)
                if chart.latestRefreshFailed {
                    Text("Refresh failed; showing the last available chart.")
                        .panelFont(.body)
                        .foregroundStyle(.orange)
                }
            } else {
                Label("24h chart unavailable", systemImage: "chart.xyaxis.line")
                    .panelFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

            mappingDetails
        }
    }

    private var itemIndex: Int? {
        model.items.firstIndex { $0.id == item.id }
    }

    private var mappingDetails: some View {
        Text(mappingSummary)
            .panelFont(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(mappingSummary)
            .textSelection(.enabled)
    }

    private var mappingSummary: String {
        let binance = item.binanceMapping.map { "BN: \($0.productID)" } ?? "BN: none"
        let coinbase = item.coinbaseMapping.map { "CB: \($0.productID)" } ?? "CB: none"
        return ["CG: \(item.coinGeckoID)", binance, coinbase].joined(separator: " · ")
    }

    private func move(by offset: Int) {
        guard let index = itemIndex else { return }
        let destination = index + offset
        guard model.items.indices.contains(destination) else { return }
        do {
            try model.moveItems(
                fromOffsets: IndexSet(integer: index),
                toOffset: offset > 0 ? destination + 1 : destination
            )
        } catch {
            // AppModel retains the durable error surface.
        }
    }
}

private struct Sparkline: View {
    let series: ChartSeries
    @Environment(\.panelTextSize) private var panelTextSize

    var body: some View {
        Canvas { context, size in
            let priceTicks = ChartAxisCalculator.priceTicks(for: series.points)
            let priceBounds = ChartAxisCalculator.priceBounds(for: series.points)
            let pricePrecision = ChartAxisCalculator.pricePrecision(for: series.points)
            let timeTicks = ChartAxisCalculator.timeTicks(for: series.points)
            guard let priceBounds,
                  let start = timeTicks.first,
                  let end = timeTicks.last else { return }

            let yAxisWidth: CGFloat = 108
            let plotRect = CGRect(
                x: yAxisWidth,
                y: 14,
                width: max(0, size.width - yAxisWidth - 10),
                height: max(0, size.height - 50)
            )
            guard plotRect.width > 0, plotRect.height > 0 else { return }

            drawAxes(
                context: context,
                plotRect: plotRect,
                priceTicks: priceTicks,
                pricePrecision: pricePrecision,
                timeTicks: timeTicks,
                minimumPrice: priceBounds.minimum,
                maximumPrice: priceBounds.maximum,
                start: start,
                end: end
            )
            drawSeries(
                context: context,
                plotRect: plotRect,
                minimumPrice: priceBounds.minimum,
                maximumPrice: priceBounds.maximum,
                start: start,
                end: end
            )
        }
        .opacity(series.latestRefreshFailed ? 0.45 : 1)
    }

    private func drawAxes(
        context: GraphicsContext,
        plotRect: CGRect,
        priceTicks: [Decimal],
        pricePrecision: Int,
        timeTicks: [Date],
        minimumPrice: Decimal,
        maximumPrice: Decimal,
        start: Date,
        end: Date
    ) {
        for tick in priceTicks {
            let fraction = ChartAxisCalculator.priceFraction(tick, minimum: minimumPrice, maximum: maximumPrice)
            let y = plotRect.maxY - plotRect.height * fraction
            var gridline = Path()
            gridline.move(to: CGPoint(x: plotRect.minX, y: y))
            gridline.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(gridline, with: .color(.secondary.opacity(0.22)), lineWidth: 1)

            let label = context.resolve(
                Text(ChartAxisCalculator.formattedPrice(tick, fractionDigits: pricePrecision))
                    .font(PanelFont.scaledFont(.body, preference: panelTextSize))
                    .foregroundColor(.secondary)
            )
            context.draw(label, at: CGPoint(x: plotRect.minX - 9, y: y), anchor: .trailing)
        }

        var xAxis = Path()
        xAxis.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        xAxis.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(xAxis, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

        for (index, tick) in timeTicks.enumerated() {
            let fraction = ChartAxisCalculator.timeFraction(tick, start: start, end: end)
            let x = plotRect.minX + plotRect.width * fraction
            var mark = Path()
            mark.move(to: CGPoint(x: x, y: plotRect.maxY))
            mark.addLine(to: CGPoint(x: x, y: plotRect.maxY + 5))
            context.stroke(mark, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

            let label = context.resolve(
                Text(tick.formatted(date: .omitted, time: .shortened))
                    .font(PanelFont.scaledFont(.body, preference: panelTextSize))
                    .foregroundColor(.secondary)
            )
            let anchor: UnitPoint
            if index == 0 {
                anchor = .topLeading
            } else if index == timeTicks.count - 1 {
                anchor = .topTrailing
            } else {
                anchor = .top
            }
            context.draw(label, at: CGPoint(x: x, y: plotRect.maxY + 8), anchor: anchor)
        }
    }

    private func drawSeries(
        context: GraphicsContext,
        plotRect: CGRect,
        minimumPrice: Decimal,
        maximumPrice: Decimal,
        start: Date,
        end: Date
    ) {
        guard series.points.count >= 2 else { return }
        var path = Path()
        var previousDate: Date?
        for point in series.points {
            let xFraction = ChartAxisCalculator.timeFraction(point.bucketStart, start: start, end: end)
            let yFraction = ChartAxisCalculator.priceFraction(
                point.close,
                minimum: minimumPrice,
                maximum: maximumPrice
            )
            let position = CGPoint(
                x: plotRect.minX + plotRect.width * xFraction,
                y: plotRect.maxY - plotRect.height * yFraction
            )
            if let previousDate, point.bucketStart.timeIntervalSince(previousDate) <= 5_400 {
                path.addLine(to: position)
            } else {
                path.move(to: position)
            }
            previousDate = point.bucketStart
        }
        context.stroke(path, with: .color(.accentColor), lineWidth: 2)
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
            ZStack {
                Text(project == nil ? "Add coin" : "Confirm markets")
                    .panelFont(.title2, weight: .bold)
                HStack {
                    Button("Cancel", action: close)
                        .panelFont(.headline)
                        .buttonStyle(.borderless)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            if let project {
                confirmation(project)
            } else {
                TextField("Search CoinGecko", text: $searchText)
                    .panelFont(.title3)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, value in model.search(query: value) }
                List(model.searchResults) { result in
                    Button {
                        choose(result)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(result.symbol)
                                .panelFont(.title2, weight: .bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 140, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .panelFont(.headline)
                                Text(result.id)
                                    .panelFont(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
            if let localError { Text(localError).panelFont(.body).foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private func confirmation(_ result: SearchResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    "Ticker matches are string guesses, not verified identities. A wrong choice can show a plausible-looking wrong price.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                    .panelFont(.headline)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coin")
                        .panelFont(.headline)
                        .foregroundStyle(.secondary)
                    Text(result.symbol)
                        .panelFont(.title2, weight: .bold)
                    Text("\(result.name) · \(result.id)")
                        .panelFont(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                if loadingCandidates {
                    ProgressView()
                } else {
                    Text("Markets")
                        .panelFont(.headline)
                        .foregroundStyle(.secondary)
                    candidatePicker(
                        title: "Binance · Live price source",
                        description: "WebSocket ticks provide the primary live price.",
                        candidates: binanceCandidates,
                        selection: $selectedBinance
                    )
                    candidatePicker(
                        title: "Coinbase · Fallback",
                        description: "Polled every 60 seconds when Binance is missing or unavailable.",
                        candidates: coinbaseCandidates,
                        selection: $selectedCoinbase
                    )
                    Text("Coinbase polling is every 60 seconds and can miss a brief alert breach.")
                        .panelFont(.body)
                        .foregroundStyle(.secondary)
                    Text("Add is enabled after both venues are answered and at least one has a market.")
                        .panelFont(.body)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Back") { project = nil }
                            .panelFont(.headline)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        Button("Add") { confirm(result) }
                            .panelFont(.headline)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!canAdd)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Inline selection rather than a `Picker`.
    ///
    /// A `Picker`'s popup menu takes key status away from the `MenuBarExtra`
    /// window, which dismisses the whole panel. Every control here must resolve
    /// inside the panel itself.
    private func candidatePicker(
        title: String,
        description: String,
        candidates: [VenueCandidate],
        selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .panelFont(.title3, weight: .bold)
            Text(description)
                .panelFont(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            candidateRow(label: "No market", value: "__none__", selection: selection)
            ForEach(candidates) { candidate in
                candidateRow(
                    label: "\(candidate.productID) (\(candidate.baseAsset)/\(candidate.quoteAsset))",
                    value: candidate.productID,
                    selection: selection
                )
            }
            if candidates.isEmpty {
                Text("No ticker-matched candidates.")
                    .panelFont(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 7)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var canAdd: Bool {
        guard let selectedBinance, let selectedCoinbase else { return false }
        return selectedBinance != "__none__" || selectedCoinbase != "__none__"
    }

    private func candidateRow(label: String, value: String, selection: Binding<String?>) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selection.wrappedValue == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection.wrappedValue == value ? Color.accentColor : .secondary)
                    .frame(width: 20, alignment: .center)
                Text(label)
                    .panelFont(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
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
                Text("Alert · \(item.symbol)").panelFont(.title2, weight: .bold)
                Spacer()
                Button("Cancel", action: close)
            }
            Toggle("Enabled", isOn: $enabled)
            if !model.alertsEnabled {
                Text("Alerts are globally off. This alert will not fire until they are re-enabled.")
                    .panelFont(.body)
                    .foregroundStyle(.orange)
            }
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
                    .panelFont(.body).foregroundStyle(.orange)
            }
            Text("Coinbase polls every 60 seconds and can miss a brief breach.")
                .panelFont(.body).foregroundStyle(.secondary)
            if let localError { Text(localError).panelFont(.body).foregroundStyle(.red) }
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
        .panelFont(.headline)
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
            .panelFont(.body)
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
