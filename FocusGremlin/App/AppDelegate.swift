import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct CachedVisionArtifacts {
        let cacheKey: String
        let capturedAt: Date
        let windowJPEG: Data
        let cursorJPEG: Data?
    }

    private var overlay: OverlayPanelController!
    private var focusEngine: FocusEngineService!
    private var smartMode: SmartModeController!
    private var orchestrator: GremlinOrchestrator!
    private var cursorTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isPerformingLine = false
    private var lastFocusCategory: FocusCategory?
    private var cachedVisionArtifacts: CachedVisionArtifacts?
    /// Не спамить «финалом» при частом alt-tab.
    private var lastWorkReturnFinalAt: Date?
    /// Короткий антидребезг: 22 с давали «второй уход в продуктив» без финала и мгновенное пропадание спрайта.
    private static let workReturnFinalCooldown: TimeInterval = 3.5
    private static let visionFrameReuseWindow: TimeInterval = 1.6

    func applicationWillFinishLaunching(_ notification: Notification) {
        let bid = Bundle.main.bundleIdentifier ?? ""
        guard !bid.isEmpty else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0.processIdentifier != pid }
        for app in others {
            app.terminate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared
        let policy = InterruptionPolicy(
            cooldown: settings.cooldownSeconds,
            maxPerHour: settings.maxInterruptionsPerHour
        )
        orchestrator = GremlinOrchestrator(policy: policy)

        let vm = CompanionViewModel()
        overlay = OverlayPanelController(viewModel: vm)
        smartMode = SmartModeController(settings: settings)
        focusEngine = FocusEngineService(settings: settings, smartMode: smartMode)

        CompanionSession.overlay = overlay
        CompanionSession.orchestrator = orchestrator
        CompanionSession.focusEngine = focusEngine

        overlay.show()
        focusEngine.start()

        warmUpGremlinSpriteCache()

        // Таймер с selector: без Task { @MainActor } на каждом тике — иначе кадры откладываются за SwiftUI.
        // После капа drawable и облегчения шейдера можно чаще — гоблин ближе к курсору; без лишнего GPU штрафа.
        cursorTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 50.0,
            target: self,
            selector: #selector(cursorFollowFire),
            userInfo: nil,
            repeats: true
        )
        if let cursorTimer {
            RunLoop.main.add(cursorTimer, forMode: .common)
        }

        focusEngine.$latestOutput
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                Task { @MainActor in
                    // Сначала «финал» при уходе в продуктив — поднимаем `workReturnFinalActive`, иначе после sync гоблин на кадр пропадает из `shouldShowCompanionSprite`.
                    self?.handleReturnToProductiveSprite(output)
                    self?.overlay.viewModel.syncFocusOverlayContext(
                        category: output?.category,
                        agentEnabled: SettingsStore.shared.agentEnabled
                    )
                    let vision = await self?.sharedVisionArtifacts(for: output)
                    let windowJPEG = vision?.window
                    let cursorJPEG = vision?.cursor
                    if let out = output, out.doomscrollPageDidChange {
                        self?.overlay.viewModel.reactToNewDoomscrollPage(at: out.snapshot.timestamp)
                        let skim = await self?.runNeuralDoomscrollPageSkim(
                            snapshot: out.snapshot,
                            screenshotJPEG: windowJPEG
                        )
                        self?.overlay.viewModel.setNeuralDoomscrollPageDigest(skim)
                        // Сначала реально показать `idle_2`, потом уже пускать реплику.
                        await Task.yield()
                        let leadDelay = self?.overlay.viewModel.idle2LeadInDelayForPageReaction() ?? 0
                        if leadDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(leadDelay * 1_000_000_000))
                        } else {
                            try? await Task.sleep(nanoseconds: 96_000_000)
                        }
                    }
                    await self?.evaluate(
                        output,
                        windowScreenshotJPEG: windowJPEG,
                        cursorNeighborhoodJPEG: cursorJPEG
                    )
                }
            }
            .store(in: &cancellables)

        settings.$agentEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.overlay.viewModel.applyAgentEnabledState(enabled)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.focusEngine.restartScrollMonitorIfNeeded()
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.app.info("Focus Gremlin запущен.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsStore.shared.flushPersistentStateToDisk()
    }

    @objc private func cursorFollowFire() {
        guard SettingsStore.shared.agentEnabled else { return }
        overlay.tickCursorFollow()
    }

    /// Прогрев ImageIO-кэша: все ленты из манифеста (idle, talking, final), аналогично preload текстур до появления сцены.
    private func warmUpGremlinSpriteCache() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let resolver = try? GremlinCharacterAnimationResolver() else { return }
            let frames = resolver.allManifestFrameRefsForWarmup()
            guard !frames.isEmpty else { return }
            let h = resolver.displayHeight()
            let head = min(80, frames.count)
            Task.detached(priority: .userInitiated) {
                GremlinSpriteThumbnailLoader.prefetch(
                    frames: Array(frames.prefix(head)),
                    displayHeight: h,
                    priority: .userInitiated
                )
            }
            if frames.count > head {
                Task.detached(priority: .utility) {
                    GremlinSpriteThumbnailLoader.prefetch(
                        frames: Array(frames.dropFirst(head)),
                        displayHeight: h,
                        priority: .utility
                    )
                }
            }
        }
    }

    private func handleReturnToProductiveSprite(_ output: FocusEngineOutput?) {
        guard SettingsStore.shared.agentEnabled else {
            lastFocusCategory = nil
            return
        }
        guard let output else { return }
        defer { lastFocusCategory = output.category }

        guard let prev = lastFocusCategory else { return }
        guard prev == .distracting, output.category != .distracting else { return }
        let now = Date()
        if let t = lastWorkReturnFinalAt, now.timeIntervalSince(t) < Self.workReturnFinalCooldown {
            return
        }
        lastWorkReturnFinalAt = now
        if overlay.viewModel.isBusy {
            overlay.viewModel.abortDeliveryForProductiveEscape()
        }
        overlay.viewModel.playWorkReturnFinalCelebration()
    }

    private func evaluate(
        _ output: FocusEngineOutput?,
        windowScreenshotJPEG: Data?,
        cursorNeighborhoodJPEG: Data?
    ) async {
        guard SettingsStore.shared.agentEnabled else { return }
        guard !isPerformingLine, !overlay.viewModel.blocksNewGremlinLine, !overlay.viewModel.linePipelineLocked else { return }
        guard let output else { return }

        let trigger = output.doomscrollPageDidChange ? DistractionTrigger.pageChange : output.trigger
        guard let trigger else { return }
        guard output.category == .distracting || trigger == .pageChange else { return }

        isPerformingLine = true
        overlay.viewModel.setLinePipelineLocked(true)
        defer {
            isPerformingLine = false
            overlay.viewModel.setLinePipelineLocked(false)
        }

        let llm = makeLLMProvider()
        let settings = SettingsStore.shared
        let visionCategory = smartMode.freshVision(at: output.snapshot.timestamp)
        let hoverSummary = CursorHoverInspector.accessibilitySummaryUnderMouse()
        let interventionContext = GremlinInterventionContext(
            trigger: trigger,
            bundleID: output.snapshot.bundleID,
            windowTitle: output.snapshot.windowTitle,
            pageTitle: output.snapshot.pageTitle,
            pageURL: output.snapshot.pageURL,
            pageSemanticSnippet: output.snapshot.pageSemanticSnippet,
            focusCategory: output.category,
            visionCategory: visionCategory,
            neuralPageChangeDigest: overlay.viewModel.neuralDoomscrollPageDigest,
            pointerAccessibilitySummary: hoverSummary
        )

        guard let line = await orchestrator.maybeProduceLine(
            context: interventionContext,
            settings: settings,
            llm: llm,
            screenshotJPEG: windowScreenshotJPEG,
            cursorNeighborhoodJPEG: cursorNeighborhoodJPEG
        ) else {
            AppLogger.focus.debug(
                "Вмешательство пропущено: кулдаун/лимит часа (trigger=\(trigger.rawValue, privacy: .public))"
            )
            return
        }

        guard overlay.viewModel.canAcceptDistractionInterventionLine else {
            AppLogger.focus.debug(
                "Вмешательство отброшено как устаревшее: финал/выход из doomscroll уже наступил"
            )
            return
        }

        let finished = await overlay.viewModel.runLiveDelivery(line, isDistractionIntervention: true)
        if finished, trigger != .pageChange {
            focusEngine.markInterventionShown()
        }
    }

    private func runNeuralDoomscrollPageSkim(snapshot: FocusSnapshot, screenshotJPEG: Data?) async -> String? {
        guard SettingsStore.shared.agentEnabled else { return nil }
        let settings = SettingsStore.shared
        guard settings.useLLMForLines else { return nil }
        let llm = makeLLMProvider()
        return await orchestrator.evaluateNewDoomscrollPage(
            bundleID: snapshot.bundleID,
            windowTitle: snapshot.windowTitle,
            pageTitle: snapshot.pageTitle,
            pageURL: snapshot.pageURL,
            pageSemanticSnippet: snapshot.pageSemanticSnippet,
            settings: settings,
            llm: llm,
            screenshotJPEG: screenshotJPEG
        )
    }

    private func makeLLMProvider() -> any LLMProvider {
        GremlinLLMProviderFactory.makeProvider(settings: SettingsStore.shared)
    }

    private struct VisionArtifacts {
        let window: Data?
        let cursor: Data?
    }

    private func sharedVisionArtifacts(for output: FocusEngineOutput?) async -> VisionArtifacts? {
        guard let output, output.category == .distracting || output.doomscrollPageDidChange else { return nil }
        guard SettingsStore.shared.smartVisionConsent, PermissionGate.screenRecordingAuthorized else { return nil }
        // Два вызова CGDisplayCreateImage на каждом тике Combine (≈1 Гц) без триггера вешали приложение.
        let effectiveTrigger: DistractionTrigger? = output.doomscrollPageDidChange ? .pageChange : output.trigger
        guard effectiveTrigger != nil else { return nil }

        let mouse = NSEvent.mouseLocation
        let mq = "\(Int(mouse.x / 40))/\(Int(mouse.y / 40))"
        let key = visionFrameCacheKey(snapshot: output.snapshot, mouseCell: mq)
        let now = Date()
        if let cached = cachedVisionArtifacts,
           cached.cacheKey == key,
           now.timeIntervalSince(cached.capturedAt) < Self.visionFrameReuseWindow {
            let v = VisionArtifacts(window: cached.windowJPEG, cursor: cached.cursorJPEG)
            logVisionArtifactsIfNeeded(v, cacheHit: true)
            return v
        }

        let windowTarget = await MainActor.run { ScreenCaptureService.focusedWindowCaptureTarget() }
        let cursorTarget = await MainActor.run { ScreenCaptureService.cursorNeighborhoodCaptureTarget() }

        let windowJPEG = await Task.detached {
            // Главный кадр: целый фрейм переднего окна для общего смысла страницы.
            ScreenCaptureService.captureJPEG(target: windowTarget, maxDimension: 1120, quality: 0.56)
        }.value
        let cursorJPEG = await Task.detached {
            // Локальный кроп вокруг курсора: точечный контекст того места, где пользователь прямо сейчас завис.
            ScreenCaptureService.captureJPEG(target: cursorTarget, maxDimension: 800, quality: 0.62)
        }.value

        if let w = windowJPEG {
            cachedVisionArtifacts = CachedVisionArtifacts(
                cacheKey: key,
                capturedAt: now,
                windowJPEG: w,
                cursorJPEG: cursorJPEG
            )
        }
        let fresh = VisionArtifacts(window: windowJPEG, cursor: cursorJPEG)
        logVisionArtifactsIfNeeded(fresh, cacheHit: false)
        return fresh
    }

    private func logVisionArtifactsIfNeeded(_ v: VisionArtifacts, cacheHit: Bool) {
        guard SettingsStore.shared.gremlinPipelineDebugLogging else { return }
        AppLogger.llm.debug(
            "visionCapture cached=\(cacheHit, privacy: .public) windowJPEG_B=\(v.window?.count ?? -1, privacy: .public) cursorJPEG_B=\(v.cursor?.count ?? -1, privacy: .public)"
        )
    }

    private func visionFrameCacheKey(snapshot: FocusSnapshot, mouseCell: String) -> String {
        let title = snapshot.effectivePageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = snapshot.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [snapshot.bundleID, title, url, mouseCell].joined(separator: "\u{1e}")
    }
}
