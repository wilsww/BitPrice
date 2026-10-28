import AppKit
import os
import SwiftUI

/// Reports whether the hosting window is actually on screen.
///
/// A `MenuBarExtra(.window)` panel is hidden, not destroyed, when it closes, so
/// SwiftUI keeps laying out its content. Occlusion state is the signal that
/// tells a visible panel from a hidden one. Key-window notifications are logged
/// alongside it for comparison only; they never reach `onChange`.
struct PanelWindowObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> PanelObserverView {
        let view = PanelObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: PanelObserverView, context: Context) {
        view.onChange = onChange
    }
}

final class PanelObserverView: NSView {
    var onChange: (Bool) -> Void = { _ in }

    private static let logger = Logger(subsystem: "com.wayne.bitprice", category: "panel")

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(occlusionStateChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(keyStateChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(keyStateChanged(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        reportVisibility(event: "attached", window: window)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func occlusionStateChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        reportVisibility(event: "occlusion", window: window)
    }

    @objc private func keyStateChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let event = notification.name == NSWindow.didBecomeKeyNotification ? "didBecomeKey" : "didResignKey"
        log(event: event, window: window)
    }

    private func reportVisibility(event: String, window: NSWindow) {
        log(event: event, window: window)
        onChange(window.occlusionState.contains(.visible))
    }

    private func log(event: String, window: NSWindow) {
        let visible = window.occlusionState.contains(.visible)
        Self.logger.info(
            "\(event, privacy: .public) visible=\(visible, privacy: .public) window=\(window.windowNumber, privacy: .public) isVisible=\(window.isVisible, privacy: .public) isKey=\(window.isKeyWindow, privacy: .public)"
        )
    }
}
