import Foundation

/// Кольцевой буфер для шаблонов + **сессионный** набор «цитат» (смешки/чистые междометия в сессию не кладём — их можно повторять).
struct RecentMessageMemory: Sendable {
    private var items: [String] = []
    private var sessionSubstantiveQuotes: Set<String> = []
    private let capacity: Int
    private let maxSessionQuotesPrompt: Int

    init(capacity: Int = 14, maxSessionQuotesPrompt: Int = 48) {
        self.capacity = max(1, capacity)
        self.maxSessionQuotesPrompt = max(8, maxSessionQuotesPrompt)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Чистый смех/междометие без смысловой «цитаты» — не участвует в запрете повторов за сессию.
    static func isLaughOrPureReactionLine(_ text: String) -> Bool {
        let raw = normalize(text)
        guard !raw.isEmpty else { return false }
        let parts = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard !parts.isEmpty else { return false }
        let strip = CharacterSet(charactersIn: ".,!?\"'…").union(.whitespaces)
        for p in parts {
            let stripped = p.trimmingCharacters(in: strip)
            guard !stripped.isEmpty else { continue }
            if !Self.laughLexicon.contains(stripped) {
                return false
            }
        }
        return true
    }

    func containsRecent(_ text: String) -> Bool {
        let n = Self.normalize(text)
        return items.contains(n)
    }

    func containsSubstantiveSessionDuplicate(_ text: String) -> Bool {
        sessionSubstantiveQuotes.contains(Self.normalize(text))
    }

    mutating func record(_ text: String, trackAsSessionQuote: Bool) {
        let n = Self.normalize(text)
        items.append(n)
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
        if trackAsSessionQuote, !n.isEmpty {
            sessionSubstantiveQuotes.insert(n)
        }
    }

    /// Нормализованные хвосты (шаблоны, короткое окно).
    func recentLinesSuffix(_ maxCount: Int) -> [String] {
        guard maxCount > 0 else { return [] }
        return Array(items.suffix(maxCount))
    }

    /// Все **смысловые** цитаты за сессию (для промпта «не повторяй»).
    func substantiveSessionLinesForPrompt() -> [String] {
        let sorted = sessionSubstantiveQuotes.sorted()
        if sorted.count <= maxSessionQuotesPrompt { return sorted }
        return Array(sorted.suffix(maxSessionQuotesPrompt))
    }

    private static let laughLexicon: Set<String> = [
        "ha", "hah", "haha", "hahaha", "hahahaha",
        "heh", "hehe", "hehehe", "hee", "heehee",
        "lol", "kek", "lul",
        "pfft", "pff", "pfht", "psh", "pish",
        "snort", "snorts", "giggle", "giggles", "chuckle", "chuckles",
        "teehee", "tehe", "huehue",
        "ugh", "argh", "ahh", "ah", "ohh", "oh", "ooh",
        "mm", "mmm", "hm", "hmm", "hmph", "umph",
        "tsk", "tch",
        "mwahaha", "muahaha", "bwahaha",
        "rawr", "grr", "grrr", "meh", "feh", "bah", "pah",
        "yawn", "yawns", "humph"
    ]
}
