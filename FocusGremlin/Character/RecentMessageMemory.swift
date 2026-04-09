import Foundation

/// Кольцевой буфер нормализованных строк для анти-повтора.
struct RecentMessageMemory: Sendable {
    private var items: [String] = []
    private let capacity: Int

    init(capacity: Int = 14) {
        self.capacity = max(1, capacity)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func containsRecent(_ text: String) -> Bool {
        let n = Self.normalize(text)
        return items.contains(n)
    }

    mutating func record(_ text: String) {
        let n = Self.normalize(text)
        items.append(n)
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
    }
}
