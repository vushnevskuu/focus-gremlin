import Foundation

/// Обрезка реплики до короткой «цитаты» (нейросеть + шаблоны).
enum GremlinLineFormatter {
    /// Достаточно для одной **законченной** едкой реплики; режется после ответа модели.
    static let maxWordsPerQuote = 12

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
    /// Последняя **смысловая** реплика (отпечаток `normalizeForDedup`) — не показывать ту же подряд.
    private var lastSubstantiveDedupKey: String?

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
        lastSubstantiveDedupKey = nil
    }

    /// Короткая оценка новой страницы doomscroll (после смены вкладки). Не использует кулдаун вмешательств и не пишет реплику в сессию.
    func evaluateNewDoomscrollPage(
        bundleID: String,
        windowTitle: String?,
        pageTitle: String?,
        pageURL: String?,
        pageSemanticSnippet: String?,
        settings: SettingsStore,
        llm: any LLMProvider,
        screenshotJPEG: Data?
    ) async -> String? {
        guard settings.useLLMForLines else { return nil }
        if let t = lastPageSkimAt, Date().timeIntervalSince(t) < 3.5 { return nil }

        let visionModel = settings.smartVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsVisionBase = screenshotJPEG != nil && settings.smartVisionConsent
        let visionChatModel = settings.effectiveModelForMultimodalCall(smartVisionModel: visionModel, attachVision: wantsVisionBase)
        let useVision = wantsVisionBase && visionChatModel != nil
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
            pageTitle: pageTitle,
            pageURL: pageURL,
            pageSemanticSnippet: pageSemanticSnippet,
            hasAttachedScreenshot: useVision
        )

        do {
            let raw = try await llm.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                jpegImages: jpegPayload,
                chatModel: useVision ? visionChatModel : nil
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
    /// `screenshotJPEG`: целый кадр **переднего** окна; `cursorNeighborhoodJPEG` — локальный кроп у курсора.
    /// Если есть оба, даём модели и общий контекст страницы, и точечную мишень под курсором.
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

        let useLLM = settings.useLLMForLines
        let minInterval = settings.llmMinIntervalSeconds

        // Не подменяем нейросеть шаблонами/междометиями — иначе «агент» бесконечно повторяет мусор, пока ждём интервал Ollama.
        if useLLM, !pageChangeBypass, let last = lastLLMCall, Date().timeIntervalSince(last) < minInterval {
            AppLogger.llm.debug(
                "intervention skipped: LLM min interval \(minInterval, privacy: .public)s not elapsed (no template filler)"
            )
            return nil
        }

        let template = selector.selectTemplate(
            language: .en,
            tone: settings.toneIntensity,
            trigger: context.trigger,
            memory: recentMemory
        )

        let visionModel = settings.smartVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMultimodalModel = settings.effectiveModelForMultimodalCall(smartVisionModel: visionModel, attachVision: true) != nil
        let visionConsent = settings.smartVisionConsent && hasMultimodalModel
        let windowJ = screenshotJPEG
        let cursorJ = cursorNeighborhoodJPEG
        let jpegPayload: [Data] = {
            guard visionConsent else { return [] }
            if let w = windowJ, let c = cursorJ { return [w, c] }
            if let w = windowJ { return [w] }
            if let c = cursorJ { return [c] }
            return []
        }()
        let useVisionAttachment = !jpegPayload.isEmpty
        let visionChatModel = settings.effectiveModelForMultimodalCall(smartVisionModel: visionModel, attachVision: useVisionAttachment)
        let visionLayout: GremlinInterventionVisionLayout = {
            guard useVisionAttachment else { return .none }
            if windowJ != nil, cursorJ != nil { return .focusedWindowAndPointerNeighborhood }
            if windowJ != nil { return .focusedWindowOnly }
            return .pointerNeighborhoodOnly
        }()
        let avoidLines = recentMemory.substantiveSessionLinesForPrompt()
        let requiredTextAnchorTokens = Self.extractAnchorTokens(from: context)
        let hasContextAnchor = useVisionAttachment || !requiredTextAnchorTokens.isEmpty

        func satisfiesTextAnchorRequirement(_ raw: String) -> Bool {
            guard !useVisionAttachment else { return true }
            guard !requiredTextAnchorTokens.isEmpty else { return true }
            let lineTokens = Set(Self.extractAnchorTokens(from: raw))
            guard !lineTokens.isEmpty else { return false }
            return !lineTokens.intersection(requiredTextAnchorTokens).isEmpty
        }

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
                        || recentMemory.containsNearDuplicateSubstantiveSession(c)
                }
                func lineIsAcceptable(_ raw: String) -> Bool {
                    let trimmed = String(raw.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, sanitize(trimmed) != nil else { return false }
                    guard satisfiesTextAnchorRequirement(trimmed) else { return false }
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
                    chatModel: visionChatModel
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
                        chatModel: visionChatModel
                    )
                    trimmed = String(line.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if lineIsAcceptable(trimmed) {
                    chosenRaw = trimmed
                }

                if chosenRaw == nil, hasContextAnchor {
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
                        chatModel: visionChatModel
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
                } else if hasContextAnchor {
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
                if hasContextAnchor {
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
                            chatModel: visionChatModel
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
        } else {
            final = template
        }

        let raw = sanitize(final) ?? template
        let cleaned = GremlinLineFormatter.clampToMaxWords(raw, maxWords: GremlinLineFormatter.maxWordsPerQuote)
        let deliveryLine = Self.decorateLineForDelivery(cleaned, context: context)

        let dedupKey = RecentMessageMemory.normalizeForDedup(deliveryLine)
        if !RecentMessageMemory.isLaughOrPureReactionLine(deliveryLine),
           !dedupKey.isEmpty,
           dedupKey == lastSubstantiveDedupKey {
            AppLogger.llm.debug(
                "intervention suppressed: same substantive line as previous delivery (dedup match)"
            )
            return nil
        }

        if pageChangeBypass {
            lastPageChangeLineAt = now
            lastPageChangeContextKey = context.pageIdentityKey
        } else {
            interruptionPolicy.recordFire()
        }
        selector.registerDelivered(deliveryLine, memory: &recentMemory)
        if !RecentMessageMemory.isLaughOrPureReactionLine(deliveryLine), !dedupKey.isEmpty {
            lastSubstantiveDedupKey = dedupKey
        }
        return deliveryLine
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
        let pointerTokens = Self.extractAnchorTokens(
            from: context.pointerAccessibilitySummary ?? ""
        )
        let pageTokens = Self.extractAnchorTokens(
            from: [
                context.pageTitle,
                context.windowTitle,
                GremlinContextBuilder.browserLocationHint(pageURL: context.pageURL),
                context.pageSemanticSnippet,
                context.neuralPageChangeDigest
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        let digestTokens = Self.extractAnchorTokens(from: context.neuralPageChangeDigest ?? "")

        var anchors: [String] = []
        for token in pointerTokens + pageTokens + digestTokens where !anchors.contains(token) {
            anchors.append(token)
        }
        let local = anchors.first ?? "this"
        let page = anchors.first(where: { $0 != local }) ?? "page"
        let third = anchors.first(where: { $0 != local && $0 != page }) ?? "rot"

        let pools = [
            "\(local) smeared all over \(page) again, parasite",
            "\(page) with \(local) and \(third), same swamp",
            "Still licking \(local) in that \(page) gutter",
            "\(third) glued to \(page), your brain applauds",
            "\(local) plus \(page) again, hopeless slime pilgrim",
            "That \(page) \(local) ritual reeks of old failure",
            "\(third) crawling through \(page), and you stayed",
            "You found \(local) on \(page) and called it living",
            "\(page) soaked in \(third), perfect snack for your focus",
            "\(local) blinking on \(page), same pathetic bait"
        ]
        for pick in pools.shuffled() {
            let clamped = GremlinLineFormatter.clampToMaxWords(pick, maxWords: GremlinLineFormatter.maxWordsPerQuote)
            if !recentMemory.containsSubstantiveSessionDuplicate(clamped)
                && !recentMemory.containsNearDuplicateSubstantiveSession(clamped) {
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
        let urlHint = GremlinContextBuilder.browserLocationHint(pageURL: context.pageURL)
        let blob = [
            context.pointerAccessibilitySummary,
            context.pageTitle,
            context.windowTitle,
            urlHint,
            context.pageSemanticSnippet,
            context.neuralPageChangeDigest
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        return extractAnchorTokens(from: blob)
    }

    private static func extractAnchorTokens(from blob: String) -> [String] {
        let normalizedBlob = blob
            .replacingOccurrences(of: "«", with: " ")
            .replacingOccurrences(of: "»", with: " ")
            .replacingOccurrences(of: "‹", with: " ")
            .replacingOccurrences(of: "›", with: " ")

        let rawWords = latinTokens(from: normalizedBlob)
            .filter { $0.count >= 3 && !anchorStopwords.contains($0) }

        var seen = Set<String>()
        var words: [String] = []
        for w in rawWords where seen.insert(w).inserted {
            words.append(w)
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

    static func decorateLineForDelivery(_ line: String, context: GremlinInterventionContext) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return line }
        guard !GremlinSpeechContext.isGiggleLike(trimmed) else { return trimmed }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard words.count <= 10 else { return trimmed }

        let seedSource = [
            context.trigger.rawValue,
            context.pageIdentityKey ?? context.pageURL ?? context.pageTitle ?? context.windowTitle ?? context.bundleID,
            trimmed
        ].joined(separator: "|")
        let bucket = stableDeterministicChecksum(seedSource) % 9

        let shouldPrefix: Bool
        switch context.trigger {
        case .pageChange:
            shouldPrefix = bucket <= 5
        case .scrollSession, .boomerang:
            shouldPrefix = bucket <= 3 || bucket == 6
        case .sustained, .chaoticSwitching, .smartVision:
            shouldPrefix = bucket <= 1
        }
        guard shouldPrefix else { return trimmed }

        let prefixes = ["ha", "pfft", "heh"]
        let prefix = prefixes[stableDeterministicChecksum(seedSource + "|giggle") % prefixes.count]
        let decorated = "\(prefix) \(trimmed)"
        return GremlinLineFormatter.clampToMaxWords(decorated, maxWords: GremlinLineFormatter.maxWordsPerQuote)
    }

    private static func stableDeterministicChecksum(_ text: String) -> Int {
        var result = 0
        for scalar in text.unicodeScalars {
            result = (result &* 33 &+ Int(scalar.value)) & 0x7fffffff
        }
        return result
    }
}
