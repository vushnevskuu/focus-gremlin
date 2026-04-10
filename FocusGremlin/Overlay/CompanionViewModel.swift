import SwiftUI

private enum GremlinTalkingSpritePool {
    /// Совпадает с `talking.files` в `GremlinSpriteManifest.json`; на каждую реплику выбирается один лист.
    static let stripFilenames = ["talking_1.png", "talking_2.png", "talking_3.png"]
}

private enum GremlinIdleSpritePool {
    /// Основной idle между репликами; хвост стрима совпадает с `activeIdleStripFilename` (см. `streamTailIdleStripFilename: nil` в резолвере).
    static let primaryStrip = "idle_1.png"
    /// Вариант на одну паузу между репликами; после него снова только primary.
    static let secondaryStrip = "idle_2.png"
}

private enum CompanionOverlayTiming {
    static let companionEntranceSpringResponse: Double = 0.44
    static let companionEntranceSpringDamping: Double = 0.76
    static let companionOnScreenNudgeResponse: Double = 0.34
    static let companionOnScreenNudgeDamping: Double = 0.72
    static let companionOnScreenNudgeScale: CGFloat = 1.07
    static let textRevealResponse: Double = 0.32
    static let textRevealDamping: Double = 0.86
    static let textRevealOffset: CGFloat = 12
    static let textHideOffset: CGFloat = 8
    static let textRevealScale: CGFloat = 0.985
    static let textHideScale: CGFloat = 0.992
    static let textHiddenBlur: CGFloat = 4
    static let textHideDuration: TimeInterval = 0.18
    static let typingDotsSeconds: ClosedRange<UInt64> = 280_000_000...520_000_000
    /// Текст стоит после допечатывания, затем «падение» букв.
    static let quoteHoldAfterTyping: TimeInterval = 5
    /// Пауза без текста перед следующей репликой (следующий вызов `runLiveDelivery`).
    static let pauseBeforeNextQuote: TimeInterval = 3
    static let charFallStaggerNanoseconds: UInt64 = 48_000_000
    static let charFallDuration: TimeInterval = 0.44
}

enum BubblePhase: Equatable {
    case idle
    case appearing
    case typingDots
    case streaming
    case holding
    /// Буквы «падают» перед очисткой текста.
    case textFalling
    case dismissing
}

/// Горизонтальная зона курсора на текущем экране (для выбора варианта «говорит»).
enum GremlinCursorZone: Equatable {
    case left
    case center
    case right
}

@MainActor
final class CompanionViewModel: ObservableObject {
    private static let pageReactionCooldown: TimeInterval = 2.4
    private static let pageReactionPresenceDuration: TimeInterval = 2.1

    @Published var phase: BubblePhase = .idle
    @Published var visibleText: String = ""
    /// Прозрачность только текстового пузыря и точек (спрайт управляется отдельно через `shouldShowCompanionSprite`).
    @Published var bubbleOpacity: Double = 0
    @Published var bubbleOffsetY: CGFloat = CompanionOverlayTiming.textRevealOffset
    @Published var bubbleScale: CGFloat = CompanionOverlayTiming.textRevealScale
    @Published var bubbleBlurRadius: CGFloat = CompanionOverlayTiming.textHiddenBlur
    /// Появление колонки спрайта: при первом показе — с нуля; если гоблин уже в idle между репликами — лёгкий пульс без исчезновения.
    @Published private(set) var companionPresentOpacity: Double = 1
    @Published private(set) var companionPresentScale: CGFloat = 1
    /// Новый цикл анимации кадров с начала при каждом сообщении.
    @Published private(set) var typingSpriteEpoch = UUID()
    /// Случайный лист `talking_1/2/3` на текущую доставку реплики (цикл только по выбранному PNG).
    @Published private(set) var activeTalkingStripFilename: String = GremlinTalkingSpritePool.stripFilenames[0]
    /// Лист idle между репликами: `idle_1` по умолчанию; `idle_2` только как реакция на **смену страницы** doomscroll (см. `reactToNewDoomscrollPage()`).
    @Published private(set) var activeIdleStripFilename: String = GremlinIdleSpritePool.primaryStrip
    /// После `idle_2` (новая страница) следующая пауза принудительно `idle_1`.
    private var nextIdleStripMustBePrimary = false
    /// Если новая страница пришла посреди речи, не рвём текущий спрайт — откладываем реакцию на ближайшую idle-паузу.
    private var pendingSecondaryIdleReaction = false
    private var lastPageReactionAt: Date?
    @Published private(set) var transientPageReactionActive = false
    /// Краткая оценка LLM/VLM после навигации на новую страницу отвлечения — строка в следующий контекст реплики.
    @Published private(set) var neuralDoomscrollPageDigest: String?
    /// Реплика из 1–2 слов: во время `.streaming` лента `short_phrase.png` вместо `talking_*`.
    @Published private(set) var deliveryUsesShortPhraseSprite = false
    /// Смещение по Y для каждого символа `visibleText` в фазе `.textFalling`.
    @Published var charFallOffsetsY: [CGFloat] = []
    /// Обновляется из оверлея по сглаженной позиции курсора.
    @Published private(set) var cursorZone: GremlinCursorZone = .center
    /// Вариант речи на время текущей доставки (по тексту или явной подсказке).
    @Published private(set) var deliverySpeechStyle: GremlinDeliverySpeechStyle = .spatial
    /// Сообщение от FocusEngine: акцентный кадр `final` во время набора/речи.
    @Published private(set) var distractionInterventionActive = false
    /// Пользователь вернулся к продуктивному приложению — один проход ленты `final` в idle.
    @Published private(set) var workReturnFinalActive = false
    /// Пользователь в основном окне (настройки и т.п.) — оверлей не должен грузить CPU анимацией и постоянным layout.
    @Published private(set) var isInteractionFocusedOnMainAppWindow = false
    /// Активный контекст отвлечения (doomscroll) по данным FocusEngine.
    @Published private(set) var isDoomscrollContextActive = false
    /// `active` в doomscroll; `terminal` только сразу после финала в продуктивном контексте (до следующего отвлечения).
    @Published private(set) var companionLifecycleState: GremlinCompanionLifecycleState = .active
    /// Удерживается с начала запроса реплики (LLM) до конца `runLiveDelivery`, чтобы не было второй параллельной реплики и отмены печати.
    @Published private(set) var linePipelineLocked = false
    /// Сброс реплики при уходе в продуктив (`abortDeliveryForProductiveEscape`): не считать вмешательство показанным.
    private var liveDeliveryAbortedExternally = false

    /// Фаза пузырька не `idle` (набор, удержание, падение и т.д.).
    var isBusy: Bool { phase != .idle }
    /// Нельзя запускать новую реплику, пока идёт сценарий или проигрывается `final` (иначе срывается анимация финала).
    var blocksNewGremlinLine: Bool { phase != .idle || workReturnFinalActive }

    func setLinePipelineLocked(_ locked: Bool) {
        guard locked != linePipelineLocked else { return }
        linePipelineLocked = locked
    }

    /// Спрайт виден при отвлечении между репликами, во время доставки текста и на единственном проигрывании `final`.
    /// `linePipelineLocked`: пока идёт запрос реплики (скрин + LLM), не гасим гоблина, если FocusEngine на кадр дал продуктивный контекст.
    var shouldShowCompanionSprite: Bool {
        guard companionLifecycleState == .active else { return false }
        return isDoomscrollContextActive || transientPageReactionActive || isBusy || workReturnFinalActive || linePipelineLocked
    }

    func setMainWindowInteractionFocused(_ on: Bool) {
        guard on != isInteractionFocusedOnMainAppWindow else { return }
        isInteractionFocusedOnMainAppWindow = on
    }

    func syncFocusOverlayContext(category: FocusCategory?, agentEnabled: Bool) {
        guard agentEnabled else {
            isDoomscrollContextActive = false
            neuralDoomscrollPageDigest = nil
            return
        }
        // Новое «попадание» в doomscroll после финала — снова показываем гоблина (terminal только между финалом и следующим отвлечением).
        if category == .distracting, companionLifecycleState == .terminal {
            companionLifecycleState = .active
            typingSpriteEpoch = UUID()
        }
        isDoomscrollContextActive = (category == .distracting)
        if category != .distracting {
            neuralDoomscrollPageDigest = nil
        }
    }

    /// Реакция на новую вкладку/страницу в doomscroll: лист `idle_2` + сброс кадров; оценка экрана — отдельным вызовом в AppDelegate.
    func reactToNewDoomscrollPage(at now: Date = Date()) {
        if let last = lastPageReactionAt, now.timeIntervalSince(last) < Self.pageReactionCooldown {
            return
        }
        lastPageReactionAt = now
        activateTransientPageReactionPresence()
        if isBusy {
            pendingSecondaryIdleReaction = true
            nextIdleStripMustBePrimary = true
            return
        }
        activeIdleStripFilename = GremlinIdleSpritePool.secondaryStrip
        nextIdleStripMustBePrimary = true
        typingSpriteEpoch = UUID()
    }

    func setNeuralDoomscrollPageDigest(_ text: String?) {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        neuralDoomscrollPageDigest = t.isEmpty ? nil : t
    }

    /// Выкл/вкл агента в настройках: сбрасываем терминальное состояние, чтобы новая сессия могла начаться.
    func applyAgentEnabledState(_ enabled: Bool) {
        if enabled {
            companionLifecycleState = .active
            return
        }
        workReturnFinalTask?.cancel()
        workReturnFinalTask = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        companionLifecycleState = .active
        isDoomscrollContextActive = false
        resetVisuals()
    }

    /// После финальной анимации гоблин скрывается в продуктивном контексте; при следующем `distracting` сессия снова активируется в `syncFocusOverlayContext`.
    private func markLifecycleTerminalAfterFinal() {
        companionLifecycleState = .terminal
        isDoomscrollContextActive = false
    }

    /// `normalizedScreenX` — 0…1 внутри `visibleFrame` экрана под курсором.
    func updateCursorZone(normalizedScreenX: CGFloat) {
        let next: GremlinCursorZone
        if normalizedScreenX < 0.34 {
            next = .left
        } else if normalizedScreenX > 0.66 {
            next = .right
        } else {
            next = .center
        }
        guard next != cursorZone else { return }
        cursorZone = next
    }

    private var deliveryTask: Task<Void, Never>?
    private var workReturnFinalTask: Task<Void, Never>?
    private var pageReactionPresenceTask: Task<Void, Never>?

    func cancelDelivery() {
        GremlinTypingVoicePlayer.shared.stop()
        workReturnFinalTask?.cancel()
        workReturnFinalTask = nil
        pageReactionPresenceTask?.cancel()
        pageReactionPresenceTask = nil
        transientPageReactionActive = false
        workReturnFinalActive = false
        deliveryTask?.cancel()
        deliveryTask = nil
        setLinePipelineLocked(false)
        resetVisuals()
    }

    /// Прервать текущую реплику (текст на экране / набор) и очистить оверлей — перед немедленным `final` при переходе на продуктив.
    func abortDeliveryForProductiveEscape() {
        liveDeliveryAbortedExternally = true
        GremlinTypingVoicePlayer.shared.stop()
        workReturnFinalTask?.cancel()
        workReturnFinalTask = nil
        pageReactionPresenceTask?.cancel()
        pageReactionPresenceTask = nil
        transientPageReactionActive = false
        workReturnFinalActive = false
        deliveryTask?.cancel()
        deliveryTask = nil
        setLinePipelineLocked(false)
        resetVisuals()
    }

    private func resetVisuals() {
        GremlinTypingVoicePlayer.shared.stop()
        workReturnFinalTask?.cancel()
        workReturnFinalTask = nil
        pageReactionPresenceTask?.cancel()
        pageReactionPresenceTask = nil
        transientPageReactionActive = false
        linePipelineLocked = false
        phase = .idle
        visibleText = ""
        charFallOffsetsY = []
        hideBubbleTextImmediately()
        deliverySpeechStyle = .spatial
        distractionInterventionActive = false
        workReturnFinalActive = false
        deliveryUsesShortPhraseSprite = false
        activeIdleStripFilename = GremlinIdleSpritePool.primaryStrip
        nextIdleStripMustBePrimary = false
        pendingSecondaryIdleReaction = false
        lastPageReactionAt = nil
        neuralDoomscrollPageDigest = nil
        companionPresentOpacity = 1
        companionPresentScale = 1
    }

    private func hideBubbleTextImmediately() {
        bubbleOpacity = 0
        bubbleOffsetY = CompanionOverlayTiming.textRevealOffset
        bubbleScale = CompanionOverlayTiming.textRevealScale
        bubbleBlurRadius = CompanionOverlayTiming.textHiddenBlur
    }

    private func activateTransientPageReactionPresence() {
        pageReactionPresenceTask?.cancel()
        transientPageReactionActive = true
        pageReactionPresenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.pageReactionPresenceDuration * 1_000_000_000)
            )
            guard let self, !Task.isCancelled else { return }
            self.transientPageReactionActive = false
        }
    }

    /// Вход в реплику: полное появление с нуля или короткий пульс, если гоблин уже показан в idle между фразами.
    private func playCompanionRevealPreflight(alreadyOnScreen: Bool) {
        if alreadyOnScreen {
            companionPresentOpacity = 1
            companionPresentScale = 1
            withAnimation(
                .spring(
                    response: CompanionOverlayTiming.companionOnScreenNudgeResponse,
                    dampingFraction: CompanionOverlayTiming.companionOnScreenNudgeDamping
                )
            ) {
                companionPresentScale = CompanionOverlayTiming.companionOnScreenNudgeScale
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                    self.companionPresentScale = 1
                }
            }
        } else {
            companionPresentOpacity = 0.02
            companionPresentScale = 0.88
            withAnimation(
                .spring(
                    response: CompanionOverlayTiming.companionEntranceSpringResponse,
                    dampingFraction: CompanionOverlayTiming.companionEntranceSpringDamping
                )
            ) {
                companionPresentOpacity = 1
                companionPresentScale = 1
            }
        }
    }

    private func animateBubbleTextIn() {
        withAnimation(.spring(response: CompanionOverlayTiming.textRevealResponse, dampingFraction: CompanionOverlayTiming.textRevealDamping)) {
            bubbleOpacity = 1
            bubbleOffsetY = 0
            bubbleScale = 1
            bubbleBlurRadius = 0
        }
    }

    private func animateBubbleTextOut() {
        withAnimation(.easeIn(duration: CompanionOverlayTiming.textHideDuration)) {
            bubbleOpacity = 0
            bubbleOffsetY = CompanionOverlayTiming.textHideOffset
            bubbleScale = CompanionOverlayTiming.textHideScale
            bubbleBlurRadius = 2.5
        }
    }

    private func sequenceDuration(
        for phase: BubblePhase,
        distractionInterventionActive: Bool,
        workReturnFinalActive: Bool = false,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard let resolver = GremlinCharacterAnimationResolver.sharedResolver() else { return fallback }
        let sequence = resolver.resolveFrameSequence(
            phase: phase,
            distractionInterventionActive: distractionInterventionActive,
            workReturnFinalActive: workReturnFinalActive,
            talkingStripFilename: activeTalkingStripFilename,
            idleStripFilename: activeIdleStripFilename,
            streamTailIdleStripFilename: nil,
            useShortPhraseStream: deliveryUsesShortPhraseSprite,
            deliverySpeechStyle: deliverySpeechStyle
        )
        return max(sequence.duration, fallback)
    }

    /// Реакция на переход «отвлечение → продуктив»: показать `final` один раз (по манифесту), затем скрыть пузырь.
    func playWorkReturnFinalCelebration() {
        workReturnFinalTask?.cancel()
        deliveryTask?.cancel()
        deliveryTask = nil
        linePipelineLocked = false
        liveDeliveryAbortedExternally = false
        distractionInterventionActive = false
        phase = .idle
        visibleText = ""
        charFallOffsetsY = []
        hideBubbleTextImmediately()
        GremlinTypingVoicePlayer.shared.stop()

        workReturnFinalActive = true
        typingSpriteEpoch = UUID()
        workReturnFinalTask = Task { [weak self] in
            await self?.runWorkReturnFinalCelebrationBody()
        }
    }

    private func runWorkReturnFinalCelebrationBody() async {
        deliveryTask?.cancel()
        deliveryTask = nil
        linePipelineLocked = false
        phase = .idle
        visibleText = ""
        charFallOffsetsY = []
        hideBubbleTextImmediately()
        GremlinTypingVoicePlayer.shared.stop()

        guard let resolver = GremlinCharacterAnimationResolver.sharedResolver() else {
            workReturnFinalActive = false
            typingSpriteEpoch = UUID()
            hideBubbleTextImmediately()
            return
        }
        playCompanionRevealPreflight(alreadyOnScreen: shouldShowCompanionSprite && phase == .idle)
        let seq = resolver.resolveFrameSequence(
            phase: .idle,
            distractionInterventionActive: false,
            workReturnFinalActive: true
        )
        let duration: TimeInterval
        if seq.frameCount > 0 {
            duration = Double(seq.frameCount) / max(seq.fps, 0.01) + 0.35
        } else {
            duration = 1.0
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        guard !Task.isCancelled else {
            workReturnFinalActive = false
            typingSpriteEpoch = UUID()
            return
        }
        workReturnFinalActive = false
        typingSpriteEpoch = UUID()
        markLifecycleTerminalAfterFinal()
        hideBubbleTextImmediately()
    }

    /// Живой цикл: точки → печать с редким «передумал» → удержание → исчезновение.
    /// `speechStyle`: если `nil`, стиль из текста (`GremlinSpeechContext`) и с вероятностью 1/5 — смех (кроме negation).
    @discardableResult
    func runLiveDelivery(
        _ fullText: String,
        speechStyle: GremlinDeliverySpeechStyle? = nil,
        isDistractionIntervention: Bool = false
    ) async -> Bool {
        liveDeliveryAbortedExternally = false
        deliveryTask?.cancel()
        deliveryTask = Task {
            await animate(fullText, speechStyle: speechStyle, isDistractionIntervention: isDistractionIntervention)
        }
        await deliveryTask?.value
        let completed = !liveDeliveryAbortedExternally
        liveDeliveryAbortedExternally = false
        return completed
    }

    private func animate(
        _ fullText: String,
        speechStyle: GremlinDeliverySpeechStyle?,
        isDistractionIntervention: Bool
    ) async {
        workReturnFinalTask?.cancel()
        workReturnFinalTask = nil
        workReturnFinalActive = false
        distractionInterventionActive = isDistractionIntervention
        var resolvedSpeech = speechStyle ?? GremlinSpeechContext.inferSpeechStyle(for: fullText)
        if speechStyle == nil, resolvedSpeech != .negation, Int.random(in: 0..<5) == 0 {
            resolvedSpeech = .giggle
        }
        deliverySpeechStyle = resolvedSpeech
        let wordCount = fullText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        deliveryUsesShortPhraseSprite = (1...2).contains(wordCount) && deliverySpeechStyle != .giggle
        typingSpriteEpoch = UUID()
        activeTalkingStripFilename = GremlinTalkingSpritePool.stripFilenames.randomElement() ?? GremlinTalkingSpritePool.stripFilenames[0]
        visibleText = ""
        hideBubbleTextImmediately()
        let gremlinAlreadyVisible = isDoomscrollContextActive && phase == .idle
        playCompanionRevealPreflight(alreadyOnScreen: gremlinAlreadyVisible)
        phase = .appearing

        let entryDuration = sequenceDuration(
            for: .appearing,
            distractionInterventionActive: isDistractionIntervention,
            fallback: 0.9
        )
        try? await Task.sleep(nanoseconds: UInt64(entryDuration * 1_000_000_000))
        if Task.isCancelled { return }

        // Сразу `.streaming`: лента «речь → idle» крутится во время точек и печати без сброса плеера (раньше `.typingDots` давал idle и обрывал говорящий спрайт).
        phase = .streaming
        let streamingStartedAt = Date()
        animateBubbleTextIn()
        try? await Task.sleep(nanoseconds: UInt64.random(in: CompanionOverlayTiming.typingDotsSeconds))
        if Task.isCancelled { return }

        let streamResolver = GremlinCharacterAnimationResolver.sharedResolver()

        let soundsOn = SettingsStore.shared.soundEffectsEnabled
        if soundsOn {
            if deliverySpeechStyle == .giggle {
                GremlinTypingVoicePlayer.shared.playGiggleOnceIfAllowed(soundsEnabled: true)
            } else if (1...2).contains(wordCount) {
                GremlinTypingVoicePlayer.shared.playShortWordsGoblinOnceIfAllowed(soundsEnabled: true, wordCount: wordCount)
            } else if !fullText.isEmpty {
                GremlinTypingVoicePlayer.shared.playTypingVoiceOnceIfAllowed(soundsEnabled: true, textNonEmpty: true)
            }
        }
        defer { GremlinTypingVoicePlayer.shared.stop() }

        let chars = Array(fullText)
        var idx = 0
        while idx < chars.count {
            if Task.isCancelled { return }
            let chunkEnd = min(idx + Int.random(in: 1...2), chars.count)
            visibleText.append(contentsOf: chars[idx..<chunkEnd])
            idx = chunkEnd
            try? await Task.sleep(nanoseconds: UInt64.random(in: 22_000_000...42_000_000))
        }

        // Не рвём talking/smile/short: пока идёт печать, интро часто короче одного прохода ленты.
        if let streamResolver {
            let streamSeq = streamResolver.resolveFrameSequence(
                phase: .streaming,
                distractionInterventionActive: isDistractionIntervention,
                workReturnFinalActive: false,
                talkingStripFilename: activeTalkingStripFilename,
                idleStripFilename: activeIdleStripFilename,
                streamTailIdleStripFilename: nil,
                useShortPhraseStream: deliveryUsesShortPhraseSprite,
                deliverySpeechStyle: deliverySpeechStyle
            )
            let minStream = streamSeq.minimumElapsedInStreamingBeforeHolding()
            let typedFor = Date().timeIntervalSince(streamingStartedAt)
            let remainder = max(0, minStream - typedFor)
            if remainder > 0 {
                let ns = max(UInt64(remainder * 1_000_000_000), 1)
                try? await Task.sleep(nanoseconds: ns)
            }
        }

        phase = .holding
        try? await Task.sleep(nanoseconds: UInt64(CompanionOverlayTiming.quoteHoldAfterTyping * 1_000_000_000))
        if Task.isCancelled { return }

        await animateTextFallAndClear()
        if Task.isCancelled { return }

        if isDistractionIntervention {
            animateBubbleTextOut()
            try? await Task.sleep(nanoseconds: UInt64(CompanionOverlayTiming.textHideDuration * 1_000_000_000))
            if Task.isCancelled { return }
            rotateIdleStripAfterPhrase()
            phase = .idle
            distractionInterventionActive = false
            typingSpriteEpoch = UUID()
            try? await Task.sleep(nanoseconds: UInt64(CompanionOverlayTiming.pauseBeforeNextQuote * 1_000_000_000))
            return
        }

        phase = .dismissing
        animateBubbleTextOut()
        let dismissDuration = sequenceDuration(
            for: .dismissing,
            distractionInterventionActive: false,
            fallback: 0.9
        )
        let dismissNs = UInt64(dismissDuration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: dismissNs)
        if Task.isCancelled { return }
        rotateIdleStripAfterPhrase()
        try? await Task.sleep(nanoseconds: UInt64(CompanionOverlayTiming.pauseBeforeNextQuote * 1_000_000_000))
        if Task.isCancelled { return }
        resetVisuals()
    }

    private func rotateIdleStripAfterPhrase() {
        if pendingSecondaryIdleReaction {
            activeIdleStripFilename = GremlinIdleSpritePool.secondaryStrip
            nextIdleStripMustBePrimary = true
            pendingSecondaryIdleReaction = false
            return
        }
        if nextIdleStripMustBePrimary {
            activeIdleStripFilename = GremlinIdleSpritePool.primaryStrip
            nextIdleStripMustBePrimary = false
            return
        }
        if activeIdleStripFilename == GremlinIdleSpritePool.secondaryStrip {
            activeIdleStripFilename = GremlinIdleSpritePool.primaryStrip
            return
        }
        activeIdleStripFilename = GremlinIdleSpritePool.primaryStrip
    }

    /// Поштучное смещение вниз; затем текст очищается.
    private func animateTextFallAndClear() async {
        let text = visibleText
        let n = text.count
        guard n > 0 else { return }
        phase = .textFalling
        charFallOffsetsY = Array(repeating: 0, count: n)
        for i in 0..<n {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: CompanionOverlayTiming.charFallStaggerNanoseconds)
            let drop = CGFloat.random(in: 96...172)
            withAnimation(.easeIn(duration: CompanionOverlayTiming.charFallDuration)) {
                var copy = charFallOffsetsY
                if i < copy.count {
                    copy[i] = drop
                    charFallOffsetsY = copy
                }
            }
        }
        let lastStartDelay = Double(max(0, n - 1)) * Double(CompanionOverlayTiming.charFallStaggerNanoseconds) / 1_000_000_000
        let settle = lastStartDelay + CompanionOverlayTiming.charFallDuration + 0.06
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
        if Task.isCancelled { return }
        var endTx = Transaction()
        endTx.animation = nil
        withTransaction(endTx) {
            visibleText = ""
            charFallOffsetsY = []
        }
    }
}
