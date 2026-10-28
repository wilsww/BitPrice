import Combine
import Foundation

/// The only model the panel's views observe.
///
/// A `MenuBarExtra(.window)` panel keeps its views alive after it closes, so
/// every `AppModel` publish would still lay out a window nobody can see. This
/// forwards those publishes while the panel is visible and swallows them while
/// it is hidden, remembering only that something changed. Showing the panel
/// then sends one publish, so it never opens on stale data.
@MainActor
final class PanelModel: ObservableObject {
    // Hidden until the window reports otherwise: the first report arrives
    // before the panel has ever been shown.
    private(set) var isVisible = false
    private(set) var isDirty = false
    private var subscription: AnyCancellable?

    func observe(_ source: ObservableObjectPublisher) {
        subscription = source.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.modelDidChange() }
        }
    }

    /// Also called by the model's one-second tick when quotes changed, since
    /// quotes are not `@Published`.
    func modelDidChange() {
        if isVisible {
            objectWillChange.send()
        } else {
            isDirty = true
        }
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible, isDirty {
            isDirty = false
            objectWillChange.send()
        }
    }
}

/// Holds the menu bar text so the label re-renders only when the text does.
@MainActor
final class MenuBarTitleModel: ObservableObject {
    @Published private(set) var title = "BitPrice"

    func update(_ newTitle: String) {
        if newTitle != title { title = newTitle }
    }
}
