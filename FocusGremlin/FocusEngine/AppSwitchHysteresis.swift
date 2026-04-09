import Foundation

/// Отслеживание частых переключений work ↔ distraction с дебаунсом.
struct AppSwitchHysteresis: Sendable {
    private var lastCategory: FocusCategory?
    private var lastChange: Date?
    private var flipTimestamps: [Date] = []

    mutating func register(category: FocusCategory, now: Date = Date()) {
        defer { lastCategory = category; lastChange = now }
        guard let prev = lastCategory, prev != category else { return }
        flipTimestamps.append(now)
        let windowStart = now.addingTimeInterval(-120)
        flipTimestamps.removeAll { $0 < windowStart }
    }

    /// Возвращает true, если за последние ~2 минуты было много переключений между разными классами.
    func isChaoticFlipping(minFlips: Int = 5, now: Date = Date()) -> Bool {
        let windowStart = now.addingTimeInterval(-120)
        let recent = flipTimestamps.filter { $0 >= windowStart }
        return recent.count >= minFlips
    }
}
