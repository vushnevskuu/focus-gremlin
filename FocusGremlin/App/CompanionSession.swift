import Foundation

/// Тонкая точка связи UI настроек с оверлеем без глобального разрастания зависимостей.
@MainActor
enum CompanionSession {
    static weak var overlay: OverlayPanelController?
    static weak var orchestrator: GremlinOrchestrator?
    static weak var focusEngine: FocusEngineService?

    static func playTestMessage() async {
        guard let overlay, let orchestrator else { return }
        guard !overlay.viewModel.blocksNewGremlinLine, !overlay.viewModel.linePipelineLocked else { return }
        overlay.snapPanelToCursorNow()
        overlay.show()
        let settings = SettingsStore.shared
        let line = orchestrator.previewLine(trigger: .sustained, settings: settings)
        await overlay.viewModel.runLiveDelivery(line)
    }
}
