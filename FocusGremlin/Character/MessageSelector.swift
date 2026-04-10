import Foundation

struct MessageSelector: Sendable {
    /// Выбирает финальную строку: несколько попыток избежать недавних повторов.
    func selectTemplate(
        language: AppLanguage,
        tone: ToneIntensity,
        trigger: DistractionTrigger,
        memory: RecentMessageMemory
    ) -> String {
        for _ in 0..<12 {
            let candidate = TemplatePhraseBank.fallbackLine(language: language, tone: tone, trigger: trigger)
            if !memory.containsRecent(candidate) {
                return candidate
            }
        }
        return TemplatePhraseBank.fallbackLine(language: language, tone: tone, trigger: trigger)
    }

    func registerDelivered(_ text: String, memory: inout RecentMessageMemory) {
        let trackSession = !RecentMessageMemory.isLaughOrPureReactionLine(text)
        memory.record(text, trackAsSessionQuote: trackSession)
    }
}
