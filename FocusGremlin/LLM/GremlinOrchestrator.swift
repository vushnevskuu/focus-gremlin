import Foundation

@MainActor
final class GremlinOrchestrator {
    private var interruptionPolicy: InterruptionPolicy
    private var lastLLMCall: Date?
    private let selector = MessageSelector()
    private var recentMemory = RecentMessageMemory()

    init(policy: InterruptionPolicy) {
        self.interruptionPolicy = policy
    }

    func updatePolicy(cooldown: TimeInterval, maxPerHour: Int) {
        interruptionPolicy = InterruptionPolicy(
            cooldown: cooldown,
            maxPerHour: maxPerHour,
            recentFireTimes: interruptionPolicy.recentFireTimes
        )
    }

    func resetMemoryForTesting() {
        recentMemory = RecentMessageMemory()
    }

    /// Возвращает nil, если сейчас нельзя вмешиваться (кулдаун/лимит).
    func maybeProduceLine(
        trigger: DistractionTrigger,
        bundleID: String,
        windowTitle: String?,
        settings: SettingsStore,
        llm: any LLMProvider
    ) async -> String? {
        updatePolicy(cooldown: settings.cooldownSeconds, maxPerHour: settings.maxInterruptionsPerHour)
        guard interruptionPolicy.canFire() else { return nil }

        var useLLM = settings.useLLMForLines
        let minInterval = settings.llmMinIntervalSeconds

        if useLLM {
            if let last = lastLLMCall, Date().timeIntervalSince(last) < minInterval {
                useLLM = false
            }
        }

        let template = selector.selectTemplate(
            language: settings.language,
            tone: settings.toneIntensity,
            trigger: trigger,
            memory: recentMemory
        )

        let final: String
        if useLLM {
            do {
                let sys = GremlinPrompts.systemPrompt(language: settings.language, tone: settings.toneIntensity)
                let user = GremlinPrompts.userPrompt(
                    trigger: trigger,
                    bundleID: bundleID,
                    windowTitle: windowTitle,
                    language: settings.language
                )
                let line = try await llm.complete(systemPrompt: sys, userPrompt: user)
                let trimmed = String(line.prefix(400))
                final = trimmed.isEmpty ? template : trimmed
                lastLLMCall = Date()
            } catch {
                AppLogger.llm.error("LLM failed: \(error.localizedDescription, privacy: .public)")
                final = template
            }
        } else {
            final = template
        }

        let cleaned = sanitize(final) ?? template
        interruptionPolicy.recordFire()
        selector.registerDelivered(cleaned, memory: &recentMemory)
        return cleaned
    }

    /// Упрощённый путь без сети (кнопка «Тест» в настройках).
    func previewLine(
        trigger: DistractionTrigger,
        settings: SettingsStore
    ) -> String {
        let line = selector.selectTemplate(
            language: settings.language,
            tone: settings.toneIntensity,
            trigger: trigger,
            memory: recentMemory
        )
        return sanitize(line) ?? line
    }

    private func sanitize(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return t
    }
}
