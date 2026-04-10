import Foundation

/// Какой вариант «говорения» показывать поверх базового idle/dismiss.
enum GremlinDeliverySpeechStyle: Equatable {
    /// Лево / центр / право по положению курсора.
    case spatial
    /// Говорит и качает головой «нет» (отрицание, упрёк).
    case negation
    /// Смех / хихиканье — лента `smile.png` и отдельный звук.
    case giggle
}

/// Выбор анимации по тексту реплики: отрицание, смех/реакция или обычная речь.
enum GremlinSpeechContext {
    static func inferSpeechStyle(for line: String) -> GremlinDeliverySpeechStyle {
        if isGiggleLike(line) {
            return .giggle
        }

        let t = " \(line.lowercased()) "

        let negationNeedles = [
            "don't", " do not ", " no ", " nope", "stop ", "enough", "quit ", " not ",
            "never ", "nah ", "won't", "can't", "cannot ", "halt", "nope."
        ]
        for needle in negationNeedles where t.contains(needle) {
            return .negation
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("no ") || trimmed.hasPrefix("don't") || trimmed.hasPrefix("nope") {
            return .negation
        }

        return .spatial
    }

    static func isGiggleLike(_ line: String) -> Bool {
        let normalized = line
            .lowercased()
            .replacingOccurrences(of: "[^a-z\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        guard !normalized.isEmpty else { return false }
        let laughTokens: Set<String> = [
            "ha", "haha", "hah", "heh", "hehe", "lol", "lmao", "rofl",
            "pfft", "snort", "snorts", "giggle", "giggles", "chuckle", "chuckles"
        ]

        return normalized.allSatisfy { token in
            laughTokens.contains(token) || token.hasPrefix("ha") || token.hasPrefix("heh")
        }
    }
}
