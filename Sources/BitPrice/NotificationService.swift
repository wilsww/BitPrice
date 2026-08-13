import Foundation
import UserNotifications

@MainActor
final class NotificationService: NotificationSubmitting {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Result<Bool, NetworkFailure> {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(returning: .failure(NetworkFailure.wrapping(error, domain: "notifications")))
                } else {
                    continuation.resume(returning: .success(granted))
                }
            }
        }
    }

    func submit(itemID: UUID, symbol: String, price: Decimal, firedAt: Date) async -> Result<Void, NetworkFailure> {
        let content = UNMutableNotificationContent()
        content.title = "\(symbol) price alert"
        content.body = "\(symbol) reached \(decimalString(price))"
        content.sound = .default
        let identifier = "\(itemID.uuidString)-\(Int64(firedAt.timeIntervalSince1970 * 1_000))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        return await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error {
                    continuation.resume(returning: .failure(NetworkFailure.wrapping(error, domain: "notifications")))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }
}
