import Foundation

/// Кулдаун и лимит вмешательств в час — чистая логика для тестов.
struct InterruptionPolicy: Sendable {
    var cooldown: TimeInterval
    var maxPerHour: Int
    private(set) var recentFireTimes: [Date]

    init(cooldown: TimeInterval, maxPerHour: Int, recentFireTimes: [Date] = []) {
        self.cooldown = cooldown
        self.maxPerHour = maxPerHour
        self.recentFireTimes = recentFireTimes
    }

    mutating func prune(now: Date = Date()) {
        let hourAgo = now.addingTimeInterval(-3600)
        recentFireTimes.removeAll { $0 < hourAgo }
    }

    /// Можно ли сейчас показать вмешательство.
    func canFire(now: Date = Date()) -> Bool {
        var copy = self
        copy.prune(now: now)
        guard let last = copy.recentFireTimes.last else { return true }
        if now.timeIntervalSince(last) < cooldown { return false }
        return copy.recentFireTimes.count < maxPerHour
    }

    mutating func recordFire(at date: Date = Date()) {
        prune(now: date)
        recentFireTimes.append(date)
    }
}
