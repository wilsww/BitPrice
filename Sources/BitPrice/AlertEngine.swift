import Foundation

enum AlertEngine {
    static func evaluate(itemID: UUID, alert: PriceAlert, price: Decimal, wallNow: Date) -> AlertDecision {
        guard alert.isEnabled else { return .noChange(itemID: itemID) }
        if !alert.isArmed {
            if isBeyondRearmBoundary(alert: alert, price: price) {
                return .rearm(itemID: itemID, expectedAlert: alert)
            }
            return .noChange(itemID: itemID)
        }
        guard isBreached(alert: alert, price: price) else { return .noChange(itemID: itemID) }
        if let lastFiredAt = alert.lastFiredAt {
            let age = max(0, wallNow.timeIntervalSince(lastFiredAt))
            guard age >= TimeInterval(alert.cooldownSeconds) else {
                return .noChange(itemID: itemID)
            }
        }
        return .fire(itemID: itemID, expectedAlert: alert, firedAt: wallNow)
    }

    private static func isBreached(alert: PriceAlert, price: Decimal) -> Bool {
        switch alert.direction {
        case .above: price > alert.threshold
        case .below: price < alert.threshold
        }
    }

    private static func isBeyondRearmBoundary(alert: PriceAlert, price: Decimal) -> Bool {
        let fraction = alert.hysteresisPercent / 100
        switch alert.direction {
        case .above:
            return price < alert.threshold * (1 - fraction)
        case .below:
            return price > alert.threshold * (1 + fraction)
        }
    }
}
