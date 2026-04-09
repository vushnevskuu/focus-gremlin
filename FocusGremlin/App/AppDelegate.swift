import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayPanelController!
    private var focusEngine: FocusEngineService!
    private var smartMode: SmartModeController!
    private var orchestrator: GremlinOrchestrator!
    private var cursorTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isPerformingLine = false

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

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard SettingsStore.shared.agentEnabled else { return }
                self?.overlay.tickCursorFollow()
            }
        }
        if let cursorTimer {
            RunLoop.main.add(cursorTimer, forMode: .common)
        }

        focusEngine.$latestOutput
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                Task { @MainActor in
                    await self?.evaluate(output)
                }
            }
            .store(in: &cancellables)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.app.info("Focus Gremlin запущен.")
    }

    private func evaluate(_ output: FocusEngineOutput?) async {
        guard SettingsStore.shared.agentEnabled else { return }
        guard !isPerformingLine, !overlay.viewModel.isBusy else { return }
        guard let output, output.category == .distracting, let trigger = output.trigger else { return }

        let llm = makeLLMProvider()
        guard let line = await orchestrator.maybeProduceLine(
            trigger: trigger,
            bundleID: output.snapshot.bundleID,
            windowTitle: output.snapshot.windowTitle,
            settings: SettingsStore.shared,
            llm: llm
        ) else {
            return
        }

        isPerformingLine = true
        defer { isPerformingLine = false }

        await overlay.viewModel.runLiveDelivery(line)
        focusEngine.markInterventionShown()
    }

    private func makeLLMProvider() -> any LLMProvider {
        guard let url = URL(string: SettingsStore.shared.ollamaBaseURL) else {
            return MockLLMProvider(cannedResponse: "Локальная модель недоступна: проверь URL в настройках.")
        }
        return OllamaProvider(baseURL: url, model: SettingsStore.shared.ollamaModel)
    }
}
