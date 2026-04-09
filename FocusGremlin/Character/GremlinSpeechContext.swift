import Foundation

/// Какой вариант «говорения» показывать поверх базового idle/dismiss.
enum GremlinDeliverySpeechStyle: Equatable {
    /// Лево / центр / право по положению курсора.
    case spatial
    /// Говорит и качает головой «нет» (отрицание, упрёк).
    case negation
}

/// Выбор анимации по смыслу строки (эвристики RU/EN; при необходимости расширяй маркеры).
enum GremlinSpeechContext {
    static func inferSpeechStyle(for line: String) -> GremlinDeliverySpeechStyle {
        let t = " \(line.lowercased()) "

        let negationNeedles = [
            " не ", " не,", " не.", "нет,", "нет.", " нет ", " нет,", " нет.",
            "не надо", "хватит", "достаточно", "отстань", "отвали", "нельзя",
            "перестань", "прекрати", "стоп", "уйми", "прочь", "не туда",
            "don't", " do not ", " no ", "stop ", "enough", "quit ", " not "
        ]
        for needle in negationNeedles where t.contains(needle) {
            return .negation
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("нет") || trimmed.hasPrefix("no ") || trimmed.hasPrefix("don't") {
            return .negation
        }

        return .spatial
    }
}
