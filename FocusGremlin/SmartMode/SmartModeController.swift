import AppKit
import Foundation

struct SmartModeSettingsSnapshot: Sendable {
    var smartModeEnabled: Bool
    var smartVisionConsent: Bool
    var smartSamplingIntervalSeconds: Double
    var smartVisionModel: String
    var smartDebugSaveFrames: Bool
    var ollamaBaseURL: String
    var language: AppLanguage
}

/// Редкие захваты экрана + вызов локальной VLM. Состояние обновляется асинхронно; `freshVision` отдаёт кэш с TTL.
@MainActor
final class SmartModeController: ObservableObject {
    private let settings: SettingsStore
    private var lastAnalysisAt: Date?
    /// Время последней попытки (включая неудачную), чтобы не долбить Ollama при ошибках.
    private var lastAttemptAt: Date?
    private(set) var lastVisionCategory: FocusCategory?
    private var inFlight: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Запланировать анализ, если прошёл интервал семплинга.
    func scheduleCaptureIfNeeded() {
        let snap = snapshot()
        guard snap.smartModeEnabled, snap.smartVisionConsent else { return }
        guard PermissionGate.screenRecordingAuthorized else { return }

        let now = Date()
        if let last = lastAttemptAt, now.timeIntervalSince(last) < snap.smartSamplingIntervalSeconds {
            return
        }
        lastAttemptAt = now

        inFlight?.cancel()
        inFlight = Task { [weak self] in
            await self?.performAnalysis(snapshot: snap)
        }
    }

    /// Категория vision, если кэш ещё «свежий».
    func freshVision(at date: Date) -> FocusCategory? {
        guard settings.smartModeEnabled, settings.smartVisionConsent else { return nil }
        guard let last = lastAnalysisAt, let cat = lastVisionCategory else { return nil }
        let ttl = settings.smartSamplingIntervalSeconds * 2.8
        guard date.timeIntervalSince(last) < ttl else { return nil }
        return cat
    }

    private func snapshot() -> SmartModeSettingsSnapshot {
        SmartModeSettingsSnapshot(
            smartModeEnabled: settings.smartModeEnabled,
            smartVisionConsent: settings.smartVisionConsent,
            smartSamplingIntervalSeconds: settings.smartSamplingIntervalSeconds,
            smartVisionModel: settings.smartVisionModel,
            smartDebugSaveFrames: settings.smartDebugSaveFrames,
            ollamaBaseURL: settings.ollamaBaseURL,
            language: settings.language
        )
    }

    private func performAnalysis(snapshot: SmartModeSettingsSnapshot) async {
        guard snapshot.smartModeEnabled, snapshot.smartVisionConsent else { return }

        let jpeg: Data?
        jpeg = await Task.detached {
            ScreenCaptureService.captureMainDisplayJPEG()
        }.value

        guard let jpeg else {
            AppLogger.focus.debug("Smart Mode: нет кадра (Screen Recording или сбой захвата).")
            return
        }

        if snapshot.smartDebugSaveFrames {
            await Task.detached {
                Self.saveDebugJPEG(jpeg)
            }.value
        }

        guard let url = URL(string: snapshot.ollamaBaseURL) else { return }
        let classifier = OllamaVisionClassifier(baseURL: url, model: snapshot.smartVisionModel, urlSession: .shared)

        do {
            let category = try await classifier.classifyScreen(jpegData: jpeg, language: snapshot.language)
            guard !Task.isCancelled else { return }
            lastVisionCategory = category
            lastAnalysisAt = Date()
            AppLogger.focus.debug("Smart Mode vision: \(category.rawValue, privacy: .public)")
        } catch {
            AppLogger.llm.error("Smart Mode vision: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func saveDebugJPEG(_ data: Data) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FocusGremlin", isDirectory: true)
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("debug_last_frame.jpg")
        try? data.write(to: file, options: .atomic)
    }
}
