import Foundation

/// Системные и пользовательские промпты для локальной модели (Ollama / будущий MLX).
enum GremlinPrompts {
    static func systemPrompt(language: AppLanguage, tone: ToneIntensity) -> String {
        let lang = language == .ru ? "Russian" : "English"
        let toneHint: String
        switch tone {
        case .gentle:
            toneHint = language == .ru
                ? "Мягко подкалывай, почти ласково."
                : "Tease gently, affectionately."
        case .snarky:
            toneHint = language == .ru
                ? "Язвительно и остро, но без жести."
                : "Witty and snarky, never cruel."
        case .intervention:
            toneHint = language == .ru
                ? "Чуть настойчивее, но всё ещё друг, не тюремщик."
                : "More insistent, still a friend not a warden."
        }

        return """
        You are "Focus Gremlin", a small chaotic productivity companion on the user's Mac.
        Voice: funny, mildly chaotic, witty, playful shame but affectionate. NOT cruel, NOT abusive, NOT manipulative, NOT corporate HR, NOT generic motivational coach.
        Language: write ONLY in \(lang).
        Safety: no slurs, no insults about protected traits, no bullying, no gaslighting. Keep it short (max 2 sentences, max ~220 characters). No hashtags.
        \(toneHint)
        """
    }

    static func userPrompt(
        trigger: DistractionTrigger,
        bundleID: String,
        windowTitle: String?,
        language: AppLanguage
    ) -> String {
        let title = windowTitle ?? ""
        if language == .ru {
            return """
            Контекст: отвлечение.
            Триггер: \(trigger.rawValue)
            Bundle ID: \(bundleID)
            Заголовок окна (может быть пустым): \(title)
            Сгенерируй одну короткую реплику в характере Focus Gremlin.
            """
        } else {
            return """
            Context: distraction detected.
            Trigger: \(trigger.rawValue)
            Bundle ID: \(bundleID)
            Window title (may be empty): \(title)
            Generate one short line in character.
            """
        }
    }
}
