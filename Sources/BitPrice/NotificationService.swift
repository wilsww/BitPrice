import Foundation
import UserNotifications

/// Submits local notifications.
///
/// `UserNotifications` invokes its completion handlers on its own queue. Two
/// separate things had to be true to stop the Swift 6 runtime from trapping in
/// `dispatch_assert_queue` — which killed the app the moment an alert fired:
///
/// 1. This type is not `@MainActor`, so its methods do not impose isolation.
/// 2. Each `withCheckedContinuation` body is explicitly `nonisolated`. Without
///    that, the body inherits the *caller's* isolation, and the caller is
///    `Task { @MainActor ... }` in `AppModel` — so the closure was still
///    main-actor isolated even after step 1. Fixing only step 1 did not stop
///    the crash.
///
/// `UNUserNotificationCenter` is not `Sendable`, so it is never stored or
/// captured across the boundary. Each method obtains the center on the queue it
/// is already running on, and only sendable values cross the continuation.
final class NotificationService: NotificationSubmitting {
    /// Resolves the center to use. Kept as a closure so tests can substitute a
    /// center without this type storing a non-sendable value.
    private let makeCenter: @Sendable () -> UNUserNotificationCenter

    init(makeCenter: @escaping @Sendable () -> UNUserNotificationCenter = { .current() }) {
        self.makeCenter = makeCenter
    }

    nonisolated func requestAuthorization() async -> Result<Bool, NetworkFailure> {
        let makeCenter = self.makeCenter
        return await withCheckedContinuation { @Sendable (continuation: CheckedContinuation<Result<Bool, NetworkFailure>, Never>) in
            makeCenter().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(returning: .failure(NetworkFailure.wrapping(error, domain: "notifications")))
                } else {
                    continuation.resume(returning: .success(granted))
                }
            }
        }
    }

    nonisolated func submit(itemID: UUID, symbol: String, price: Decimal, firedAt: Date) async -> Result<Void, NetworkFailure> {
        // Only sendable values are captured. `UNNotificationRequest` and
        // `UNMutableNotificationContent` are not `Sendable`, so they are built
        // inside the closure rather than passed into it.
        let title = "\(symbol) price alert"
        let body = "\(symbol) reached \(decimalString(price))"
        let identifier = "\(itemID.uuidString)-\(Int64(firedAt.timeIntervalSince1970 * 1_000))"
        let makeCenter = self.makeCenter
        return await withCheckedContinuation { @Sendable (continuation: CheckedContinuation<Result<Void, NetworkFailure>, Never>) in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            makeCenter().add(request) { error in
                if let error {
                    continuation.resume(returning: .failure(NetworkFailure.wrapping(error, domain: "notifications")))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }
}
