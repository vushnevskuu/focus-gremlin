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

    /// Склейка «одной и той же» цитаты для анти-повтора: только буквы/цифры, слова ≥2 символов, без пунктуации.
    static func normalizeForDedup(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let parts = folded.components(separatedBy: Self.nonWordScalars)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return parts.joined(separator: " ")
    }

    private static let nonWordScalars = CharacterSet.alphanumerics.inverted

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
        let n = Self.normalizeForDedup(text)
        guard !n.isEmpty else { return false }
        return items.contains(n)
    }

    func containsSubstantiveSessionDuplicate(_ text: String) -> Bool {
        let n = Self.normalizeForDedup(text)
        guard !n.isEmpty else { return false }
        return sessionSubstantiveQuotes.contains(n)
    }

    func containsNearDuplicateSubstantiveSession(_ text: String) -> Bool {
        let candidate = Self.similarityTokenSet(text)
        guard candidate.count >= 2 else { return false }
        for existing in sessionSubstantiveQuotes {
            let sample = Self.similarityTokenSet(existing)
            guard sample.count >= 2 else { continue }
            let intersection = candidate.intersection(sample).count
            guard intersection >= 2 else { continue }
            let union = candidate.union(sample).count
            guard union > 0 else { continue }
            let jaccard = Double(intersection) / Double(union)
            if jaccard >= 0.5 {
                return true
            }
        }
        return false
    }

    mutating func record(_ text: String, trackAsSessionQuote: Bool) {
        let n = Self.normalizeForDedup(text)
        if !n.isEmpty {
            items.append(n)
        }
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

    private static let similarityStopwords: Set<String> = [
        "again", "still", "this", "that", "with", "your", "you", "the", "and", "for",
        "from", "into", "page", "site", "tab", "same", "more", "just", "here"
    ]

    private static func similarityTokenSet(_ text: String) -> Set<String> {
        let normalized = normalizeForDedup(text)
        guard !normalized.isEmpty else { return [] }
        return Set(
            normalized
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 3 && !similarityStopwords.contains($0) }
        )
    }
}
