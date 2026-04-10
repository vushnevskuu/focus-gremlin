import Foundation

/// Обрезка реплики до короткой «цитаты» (нейросеть + шаблоны).
enum GremlinLineFormatter {
    static let maxWordsPerQuote = 5

    static func clampToMaxWords(_ text: String, maxWords: Int) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard parts.count > maxWords else { return parts.joined(separator: " ") }
        return parts.prefix(maxWords).joined(separator: " ")
    }
}

@MainActor
final class GremlinOrchestrator {
    private static let pageChangeCommentCooldown: TimeInterval = 6
    private static let samePageCommentCooldown: TimeInterval = 45
    private var interruptionPolicy: InterruptionPolicy
    private var lastLLMCall: Date?
    private var lastPageSkimAt: Date?
    private var lastPageChangeLineAt: Date?
    private var lastPageChangeContextKey: String?
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

    /// Короткая оценка новой страницы doomscroll (после смены вкладки). Не использует кулдаун вмешательств и не пишет реплику в сессию.
    func evaluateNewDoomscrollPage(
        bundleID: String,
        windowTitle: String?,
        settings: SettingsStore,
        llm: any LLMProvider,
        screenshotJPEG: Data?
    ) async -> String? {
        guard settings.useLLMForLines else { return nil }
        if let t = lastPageSkimAt, Date().timeIntervalSince(t) < 3.5 { return nil }

        let visionModel = settings.smartVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let useVision = screenshotJPEG != nil && settings.smartVisionConsent && !visionModel.isEmpty
        let jpegPayload: [Data] = {
            guard useVision, let j = screenshotJPEG else { return [] }
            return [j]
        }()

        let systemPrompt = """
        Reply with exactly one short English phrase. Hard cap: 12 words total. Describe the visible distracting page and what the user is doing there. No quotation marks, no emoji, Latin script only. No second sentence. If unsure, say generic web sludge.
        """

        let userPrompt = GremlinPrompts.newDoomscrollPageSkimPrompt(
            bundleID: bundleID,
            windowTitle: windowTitle,
            hasAttachedScreenshot: useVision
        )

        do {
            let raw = try await llm.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                jpegImages: jpegPayload,
                chatModel: useVision ? visionModel : nil
            )
            let trimmed = String(raw.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let sanitized = sanitize(trimmed) else { return nil }
            let out = GremlinLineFormatter.clampToMaxWords(sanitized, maxWords: 12)
            guard !out.isEmpty else { return nil }
            lastPageSkimAt = Date()
            return out
        } catch {
            AppLogger.llm.debug("Page skim: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Возвращает nil, если сейчас нельзя вмешиваться (кулдаун/лимит).
    /// `screenshotJPEG`: целый кадр **переднего** окна; `cursorNeighborhoodJPEG` — только запас, если окно не снялось (кроп у курсора не смешивается с окном в одном запросе).
    func maybeProduceLine(
        context: GremlinInterventionContext,
        settings: SettingsStore,
        llm: any LLMProvider,
        screenshotJPEG: Data? = nil,
        cursorNeighborhoodJPEG: Data? = nil
    ) async -> String? {
        let now = Date()
        let pageChangeBypass = context.trigger == .pageChange
        if pageChangeBypass {
            if let last = lastPageChangeLineAt, now.timeIntervalSince(last) < Self.pageChangeCommentCooldown {
                return nil
            }
            if let key = context.pageIdentityKey,
               let lastKey = lastPageChangeContextKey,
               key == lastKey,
               let last = lastPageChangeLineAt,
               now.timeIntervalSince(last) < Self.samePageCommentCooldown {
                return nil
            }
        } else {
            updatePolicy(cooldown: settings.cooldownSeconds, maxPerHour: settings.maxInterruptionsPerHour)
            guard interruptionPolicy.canFire() else { return nil }
        }

        var useLLM = settings.useLLMForLines
        var llmHeldByInterval = false
        let minInterval = settings.llmMinIntervalSeconds

        if useLLM {
            if let last = lastLLMCall, Date().timeIntervalSince(last) < minInterval {
                useLLM = false
                llmHeldByInterval = true
            }
        }

        let template = selector.selectTemplate(
            language: .en,
            tone: settings.toneIntensity,
            trigger: context.trigger,
            memory: recentMemory
        )

        let visionModel = settings.smartVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let visionConsent = settings.smartVisionConsent && !visionModel.isEmpty
        let windowJ = screenshotJPEG
        let cursorJ = cursorNeighborhoodJPEG
        /// Один кадр: **целое переднее окно** (foreground), если захватился; иначе запасной кроп у курсора. Без «двух картинок» — модель читает весь фрейм окна, а не квадрат по расстоянию от мыши.
        let jpegPayload: [Data] = {
            guard visionConsent else { return [] }
            if let w = windowJ { return [w] }
            if let c = cursorJ { return [c] }
            return []
        }()
        let useVisionAttachment = !jpegPayload.isEmpty
        let visionLayout: GremlinInterventionVisionLayout = {
            guard useVisionAttachment else { return .none }
            if windowJ != nil { return .focusedWindowOnly }
            return .pointerNeighborhoodOnly
        }()
        let avoidLines = recentMemory.substantiveSessionLinesForPrompt()
        let pointerTrimmed = context.pointerAccessibilitySummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasVisualAnchor = useVisionAttachment || !pointerTrimmed.isEmpty

        logInterventionPipelineSummary(
            settings: settings,
            context: context,
            visionLayout: visionLayout,
            jpegPayload: jpegPayload,
            windowBytes: windowJ?.count,
            cursorBytes: cursorJ?.count,
            visionModel: visionModel,
            useLLM: useLLM,
            visionConsent: visionConsent
        )

        let final: String
        if useLLM {
            do {
                let sys = GremlinPrompts.systemPrompt(language: .en, tone: settings.toneIntensity)
                func clamped(_ raw: String) -> String {
                    GremlinLineFormatter.clampToMaxWords(
                        sanitize(raw) ?? "",
                        maxWords: GremlinLineFormatter.maxWordsPerQuote
                    )
                }
                func isDup(_ s: String) -> Bool {
                    let c = clamped(s)
                    guard !RecentMessageMemory.isLaughOrPureReactionLine(c) else { return false }
                    return recentMemory.containsSubstantiveSessionDuplicate(c)
                }
                func lineIsAcceptable(_ raw: String) -> Bool {
                    let trimmed = String(raw.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, sanitize(trimmed) != nil else { return false }
                    return !isDup(clamped(trimmed))
                }

                var chosenRaw: String?

                var user = GremlinPrompts.userPrompt(
                    context: context,
                    avoidRepeatingNormalizedLines: avoidLines,
                    duplicateRetry: false,
                    visionLayout: visionLayout
                )
                logUserPromptChunk(settings: settings, label: "main_a", prompt: user)
                var line = try await llm.complete(
                    systemPrompt: sys,
                    userPrompt: user,
                    jpegImages: jpegPayload,
                    chatModel: useVisionAttachment ? visionModel : nil
                )
                var trimmed = String(line.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !lineIsAcceptable(trimmed) {
                    user = GremlinPrompts.userPrompt(
                        context: context,
                        avoidRepeatingNormalizedLines: avoidLines,
                        duplicateRetry: true,
                        visionLayout: visionLayout
                    )
                    logUserPromptChunk(settings: settings, label: "main_b_retry", prompt: user)
                    line = try await llm.complete(
                        systemPrompt: sys,
                        userPrompt: user,
                        jpegImages: jpegPayload,
                        chatModel: useVisionAttachment ? visionModel : nil
                    )
                    trimmed = String(line.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if lineIsAcceptable(trimmed) {
                    chosenRaw = trimmed
                }

                if chosenRaw == nil, hasVisualAnchor {
                    let hailSys = GremlinPrompts.visionAnchorHailMarySystemPrompt(tone: settings.toneIntensity)
                    let hailUser = GremlinPrompts.visionAnchorHailMaryUserPrompt(
                        context: context,
                        bannedNormalizedLines: avoidLines
                    )
                    logUserPromptChunk(settings: settings, label: "hail_mary", prompt: hailUser)
                    line = try await llm.complete(
                        systemPrompt: hailSys,
                        userPrompt: hailUser,
                        jpegImages: jpegPayload,
                        chatModel: useVisionAttachment ? visionModel : nil
                    )
                    trimmed = String(line.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if lineIsAcceptable(trimmed) {
                        chosenRaw = trimmed
                    }
                }

                if let picked = chosenRaw {
                    final = picked
                    lastLLMCall = Date()
                    settings.noteGremlinLLMSuccess()
                    logLineOutcome(settings: settings, source: "llm", line: picked)
                } else if hasVisualAnchor {
                    settings.noteGremlinLLMFailure("Fallback: контекстный якорь без шаблона.")
                    final = contextAnchoredFallbackEnglish(context: context)
                    lastLLMCall = Date()
                    logLineOutcome(settings: settings, source: "anchor_fallback", line: final)
                } else {
                    settings.noteGremlinLLMFailure("Модель не дала строку — шаблон.")
                    final = template
                    logLineOutcome(settings: settings, source: "template", line: final)
                }
            } catch {
                AppLogger.llm.error("LLM failed: \(error.localizedDescription, privacy: .public)")
                settings.noteGremlinLLMFailure(error.localizedDescription)
                if hasVisualAnchor {
                    do {
                        let hailSys = GremlinPrompts.visionAnchorHailMarySystemPrompt(tone: settings.toneIntensity)
                        let hailUser = GremlinPrompts.visionAnchorHailMaryUserPrompt(
                            context: context,
                            bannedNormalizedLines: avoidLines
                        )
                        logUserPromptChunk(settings: settings, label: "hail_after_error", prompt: hailUser)
                        let line = try await llm.complete(
                            systemPrompt: hailSys,
                            userPrompt: hailUser,
                            jpegImages: jpegPayload,
                            chatModel: useVisionAttachment ? visionModel : nil
                        )
                        let trimmed = String(line.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, sanitize(trimmed) != nil {
                            final = trimmed
                            lastLLMCall = Date()
                            settings.noteGremlinLLMSuccess()
                            logLineOutcome(settings: settings, source: "llm_hail_recover", line: final)
                        } else {
                            final = contextAnchoredFallbackEnglish(context: context)
                            lastLLMCall = Date()
                            logLineOutcome(settings: settings, source: "anchor_after_hail_fail", line: final)
                        }
                    } catch {
                        final = contextAnchoredFallbackEnglish(context: context)
                        lastLLMCall = Date()
                        logLineOutcome(settings: settings, source: "anchor_after_double_fail", line: final)
                    }
                } else {
                    final = template
                    logLineOutcome(settings: settings, source: "template_after_error", line: final)
                }
            }
        } else if llmHeldByInterval, settings.useLLMForLines {
            final = TemplatePhraseBank.vocalInterjection(language: .en, memory: recentMemory)
        } else {
            final = template
        }

        let raw = sanitize(final) ?? template
        let cleaned = GremlinLineFormatter.clampToMaxWords(raw, maxWords: GremlinLineFormatter.maxWordsPerQuote)
        if pageChangeBypass {
            lastPageChangeLineAt = now
            lastPageChangeContextKey = context.pageIdentityKey
        } else {
            interruptionPolicy.recordFire()
        }
        selector.registerDelivered(cleaned, memory: &recentMemory)
        return cleaned
    }

    private func logInterventionPipelineSummary(
        settings: SettingsStore,
        context: GremlinInterventionContext,
        visionLayout: GremlinInterventionVisionLayout,
        jpegPayload: [Data],
        windowBytes: Int?,
        cursorBytes: Int?,
        visionModel: String,
        useLLM: Bool,
        visionConsent: Bool
    ) {
        guard settings.gremlinPipelineDebugLogging else { return }
        let title = (context.pageTitle ?? context.windowTitle)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlHint = GremlinContextBuilder.browserLocationHint(pageURL: context.pageURL) ?? "-"
        let sizes = jpegPayload.enumerated().map { "img\($0.offset)=\($0.element.count)B" }.joined(separator: ",")
        AppLogger.llm.debug(
            "intervention useLLM=\(useLLM, privacy: .public) visionConsent=\(visionConsent, privacy: .public) layout=\(String(describing: visionLayout), privacy: .public) visionModel_nonempty=\(!visionModel.isEmpty, privacy: .public) bundle=\(context.bundleID, privacy: .public) trigger=\(context.trigger.rawValue, privacy: .public) titleEmpty=\(title.isEmpty, privacy: .public) urlHint=\(urlHint, privacy: .public) windowJPEG_B=\(windowBytes ?? -1, privacy: .public) cursorJPEG_B=\(cursorBytes ?? -1, privacy: .public) attach=\(sizes, privacy: .public) pointerLen=\(context.pointerAccessibilitySummary?.count ?? 0, privacy: .public)"
        )
    }

    private func logUserPromptChunk(settings: SettingsStore, label: String, prompt: String) {
        guard settings.gremlinPipelineDebugLogging else { return }
        let snip = String(prompt.prefix(900))
        AppLogger.llm.debug(
            "userPrompt[\(label, privacy: .public)] chars=\(prompt.count, privacy: .public) :: \(snip, privacy: .public)"
        )
    }

    private func logLineOutcome(settings: SettingsStore, source: String, line: String) {
        guard settings.gremlinPipelineDebugLogging else { return }
        AppLogger.llm.debug(
            "delivered[\(source, privacy: .public)] \(String(line.prefix(220)), privacy: .public)"
        )
    }

    /// Упрощённый путь без сети (кнопка «Тест» в настройках).
    func previewLine(
        trigger: DistractionTrigger,
        settings: SettingsStore
    ) -> String {
        let line = selector.selectTemplate(
            language: .en,
            tone: settings.toneIntensity,
            trigger: trigger,
            memory: recentMemory
        )
        let raw = sanitize(line) ?? line
        return GremlinLineFormatter.clampToMaxWords(raw, maxWords: GremlinLineFormatter.maxWordsPerQuote)
    }

    /// Короткая строка из реальных слов вкладки / AX — не из `TemplatePhraseBank`.
    private func contextAnchoredFallbackEnglish(context: GremlinInterventionContext) -> String {
        let tokens = Self.extractAnchorTokens(from: context)
        let a = tokens.first ?? "this"
        let b = tokens.dropFirst().first ?? "tab"
        let pools = [
            "\(a) \(b) trash habit",
            "Really \(a) right now",
            "\(a) click circus loser",
            "That \(a) junk obsession",
            "\(a) \(b) waste clown",
            "Mate \(a) \(b) really",
            "\(a) tab rot garbage"
        ]
        for pick in pools.shuffled() {
            let clamped = GremlinLineFormatter.clampToMaxWords(pick, maxWords: GremlinLineFormatter.maxWordsPerQuote)
            if !recentMemory.containsSubstantiveSessionDuplicate(clamped) {
                return pick
            }
        }
        return GremlinLineFormatter.clampToMaxWords(pools[0], maxWords: GremlinLineFormatter.maxWordsPerQuote)
    }

    private static let anchorStopwords: Set<String> = [
        "the", "and", "for", "you", "your", "that", "this", "with", "from", "link", "button", "window",
        "group", "unknown", "web", "area", "application", "chrome", "safari", "firefox", "edge", "brave"
    ]

    private static func extractAnchorTokens(from context: GremlinInterventionContext) -> [String] {
        let blob = [
            context.pointerAccessibilitySummary,
            context.pageTitle,
            context.windowTitle
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .replacingOccurrences(of: "«", with: " ")
        .replacingOccurrences(of: "»", with: " ")
        .replacingOccurrences(of: "‹", with: " ")
        .replacingOccurrences(of: "›", with: " ")

        let rawWords = latinTokens(from: blob)
            .filter { $0.count >= 3 && !anchorStopwords.contains($0) }

        var seen = Set<String>()
        var words: [String] = []
        for w in rawWords where seen.insert(w).inserted {
            words.append(w)
        }

        if words.isEmpty, let urlStr = context.pageURL,
           let url = URL(string: urlStr),
           let host = url.host?.lowercased() {
            let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if let first = h.split(separator: ".").first, first.count >= 2 {
                words = [String(first)]
            }
        }
        if words.isEmpty {
            words = ["this"]
        }
        return Array(words.prefix(4))
    }

    private static func latinTokens(from text: String) -> [String] {
        let parts = text.split { !$0.isLetter && !$0.isNumber }
        var result: [String] = []
        for p in parts {
            let w = String(p).lowercased()
            guard w.count >= 2 else { continue }
            let ok = w.unicodeScalars.allSatisfy { scalar in
                let v = scalar.value
                return (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0x30...0x39).contains(v)
            }
            guard ok else { continue }
            result.append(w)
        }
        return result
    }

    private func sanitize(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        t = Self.stripEmojiUnicodeScalars(from: t)
        t = Self.stripQuotationMarksAndDecorators(from: t)
        t = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if Self.containsCyrillic(t) { return nil }
        return t
    }

    /// В оверлей не показываем кавычки и типографские аналоги — только слова.
    private static func stripQuotationMarksAndDecorators(from s: String) -> String {
        var t = s
        // ASCII apostrophe и U+2019 оставляем — сокращения вроде don't.
        let stripSet = [
            "\"", "`",
            "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}",
            "\u{2018}", "\u{201A}", "\u{201B}",
            "«", "»", "„", "‟", "「", "」", "『", "』",
            "\u{FF02}"
        ]
        for ch in stripSet {
            t = t.replacingOccurrences(of: ch, with: "")
        }
        return t
    }

    /// Убирает эмодзи и прочие emoji-представления из скаляров (реплики гоблина без пиктограмм).
    private static func stripEmojiUnicodeScalars(from s: String) -> String {
        String(
            s.unicodeScalars.filter { scalar in
                !scalar.properties.isEmojiPresentation && !scalar.properties.isEmoji
            }
        )
    }

    private static func containsCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) || (0x0500...0x052F).contains($0.value) }
    }
}
