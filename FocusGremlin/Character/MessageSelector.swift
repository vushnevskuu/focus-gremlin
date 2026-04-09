import Foundation

struct MessageSelector: Sendable {
    /// Выбирает финальную строку: несколько попыток избежать недавних повторов.
    func selectTemplate(
        language: AppLanguage,
        tone: ToneIntensity,
        trigger: DistractionTrigger,
        memory: RecentMessageMemory
    ) -> String {
        var mem = memory
        for _ in 0..<12 {
            let candidate = TemplatePhraseBank.fallbackLine(language: language, tone: tone, trigger: trigger)
            if !mem.containsRecent(candidate) {
                return candidate
            }
        }
        return TemplatePhraseBank.fallbackLine(language: language, tone: tone, trigger: trigger)
    }

    func registerDelivered(_ text: String, memory: inout RecentMessageMemory) {
        memory.record(text)
    }
}
