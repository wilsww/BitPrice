import Darwin
import SwiftUI

#if !BITPRICE_TESTING
@main
struct BitPriceApp: App {
    // `@State`, not `@StateObject`: the app must not observe the model, or every
    // publish would re-evaluate `body` and bypass the panel's visibility gate.
    @State private var model: AppModel

    init() {
        do {
            let productionModel = try AppModel.production()
            _model = State(wrappedValue: productionModel)
        } catch {
            fputs("BitPrice startup failed: \(error.localizedDescription)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            MenuBarLabel(title: model.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var title: MenuBarTitleModel

    var body: some View {
        Text(title.title)
    }
}
#endif
