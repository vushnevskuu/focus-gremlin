import Foundation

/// Накопление скролла в текущем «окне внимания» (без привязки к конкретному API событий).
struct ScrollSessionTracker: Sendable {
    private var timestamps: [Date] = []

    mutating func recordScroll(at date: Date = Date()) {
        timestamps.append(date)
        let cutoff = date.addingTimeInterval(-180)
        timestamps.removeAll { $0 < cutoff }
    }

    func isHeavyScrolling(threshold: Int = 28, within seconds: TimeInterval = 60, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-seconds)
        let count = timestamps.filter { $0 >= cutoff }.count
        return count >= threshold
    }

    mutating func reset() {
        timestamps.removeAll()
    }
}
