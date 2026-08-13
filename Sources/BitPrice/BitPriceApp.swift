import Darwin
import SwiftUI

#if !BITPRICE_TESTING
@main
struct BitPriceApp: App {
    @StateObject private var model: AppModel

    init() {
        do {
            let productionModel = try AppModel.production()
            _model = StateObject(wrappedValue: productionModel)
        } catch {
            fputs("BitPrice startup failed: \(error.localizedDescription)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
