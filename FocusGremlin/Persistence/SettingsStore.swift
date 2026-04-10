import Foundation
import Combine

enum ToneIntensity: String, CaseIterable, Codable {
    case gentle
    case snarky
    case intervention
}

enum AppLanguage: String, CaseIterable, Codable {
    case ru
    case en
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var agentEnabled: Bool {
        didSet { schedulePersistToDisk() }
    }
    @Published var toneIntensity: ToneIntensity {
        didSet { schedulePersistToDisk() }
    }
    @Published var language: AppLanguage {
        didSet { schedulePersistToDisk() }
    }
    @Published var productiveBundleIDs: [String] {
        didSet { schedulePersistToDisk() }
    }
    @Published var distractingBundleIDs: [String] {
        didSet { schedulePersistToDisk() }
    }
    @Published var browserWorkKeywords: [String] {
        didSet { schedulePersistToDisk() }
    }
    @Published var cooldownSeconds: Double {
        didSet { schedulePersistToDisk() }
    }
    @Published var maxInterruptionsPerHour: Int {
        didSet { schedulePersistToDisk() }
    }
    @Published var distractionSecondsBeforeNudge: Double {
        didSet { schedulePersistToDisk() }
    }
    @Published var soundEffectsEnabled: Bool {
        didSet { schedulePersistToDisk() }
    }
    @Published var startAtLogin: Bool {
        didSet { schedulePersistToDisk() }
    }
    @Published var smartModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartModeEnabled, forKey: "fg.feature.smartVision")
            schedulePersistToDisk()
        }
    }
    /// Явное согласие на анализ кадров (только память + локальный Ollama; опционально debug-файл).
    @Published var smartVisionConsent: Bool {
        didSet {
            if !smartVisionConsent {
                smartModeEnabled = false
                smartDebugSaveFrames = false
            }
            schedulePersistToDisk()
        }
    }
    @Published var smartSamplingIntervalSeconds: Double {
        didSet { schedulePersistToDisk() }
    }
    @Published var smartVisionModel: String {
        didSet { schedulePersistToDisk() }
    }
    @Published var smartDebugSaveFrames: Bool {
        didSet { schedulePersistToDisk() }
    }
    @Published var ollamaModel: String {
        didSet { schedulePersistToDisk() }
    }
    @Published var ollamaBaseURL: String {
        didSet { schedulePersistToDisk() }
    }
    @Published var useLLMForLines: Bool {
        didSet { schedulePersistToDisk() }
    }
    @Published var llmMinIntervalSeconds: Double {
        didSet { schedulePersistToDisk() }
    }
    @Published var onboardingCompleted: Bool {
        didSet { schedulePersistToDisk() }
    }

    /// Подробный лог цепочки «контекст → промпт → JPEG» в Console (категория `llm`). Хранится в UserDefaults, не в JSON настроек.
    @Published var gremlinPipelineDebugLogging = false {
        didSet {
            UserDefaults.standard.set(gremlinPipelineDebugLogging, forKey: Self.gremlinPipelineDebugLoggingKey)
        }
    }

    private static let gremlinPipelineDebugLoggingKey = "fg.gremlinPipelineDebugLogging"

    /// Не сохраняется: почему могли идти шаблоны вместо нейросети (ошибка Ollama, пустой ответ и т.д.).
    @Published private(set) var gremlinLLMDiagnosticLine: String = ""

    private var persistWorkItem: DispatchWorkItem?

    func noteGremlinLLMSuccess() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeStyle = .medium
        f.dateStyle = .none
        gremlinLLMDiagnosticLine = "Ollama: реплика сгенерирована (\(f.string(from: Date())))."
    }

    func noteGremlinLLMFailure(_ message: String) {
        gremlinLLMDiagnosticLine = "Нет ответа нейросети — показан запасной текст. \(message)"
    }

    /// Ручная проверка: `ollama serve` запущен, модель `ollama pull …` скачана.
    func runGremlinOllamaSmokeTest() async {
        gremlinLLMDiagnosticLine = "Проверка Ollama…"
        let base = ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base), url.scheme != nil else {
            noteGremlinLLMFailure("Некорректный базовый URL.")
            return
        }
        guard !m.isEmpty else {
            noteGremlinLLMFailure("Имя модели пустое.")
            return
        }
        let provider = OllamaProvider(baseURL: url, model: m)
        do {
            let line = try await provider.complete(
                systemPrompt: "Reply with exactly one word: OK",
                userPrompt: "Test."
            )
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if t.contains("OK") {
                noteGremlinLLMSuccess()
                gremlinLLMDiagnosticLine = "Проверка OK: Ollama отвечает, модель «\(m)» доступна."
            } else {
                noteGremlinLLMFailure("Странный ответ: «\(line.prefix(100))»")
            }
        } catch {
            noteGremlinLLMFailure(error.localizedDescription)
        }
    }

    /// Немедленная запись (выход из приложения); иначе настройки пишутся с небольшой задержкой, чтобы не душить главный поток при наборе в списках.
    func flushPersistentStateToDisk() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        persistToDisk()
    }

    private func schedulePersistToDisk() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.persistToDisk()
            self?.persistWorkItem = nil
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private let defaults = UserDefaults.standard
    private let key = "fg.settings.v2"
    private let legacyKey = "fg.settings.v1"
    /// Одноразово добавляет bundle нативного Instagram в старые сохранённые списки (раньше в дефолтах не было).
    private static let migrationInstagramBundleKey = "fg.migration.instagramBundle.202604"
    /// Раньше дефолт был `llama3.2` без тега — у Ollama такой модели часто нет, есть `llama3.2:3b` и т.д.
    private static let migrationOllamaLlama32ExactKey = "fg.migration.ollamaModel.llama32exact.20260410"

    private init() {
        let state: Persisted
        var didMigrateFromLegacy = false
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            state = decoded
        } else if let data = defaults.data(forKey: legacyKey),
                  let old = try? JSONDecoder().decode(LegacyPersisted.self, from: data) {
            state = Self.persisted(fromLegacy: old)
            defaults.removeObject(forKey: legacyKey)
            didMigrateFromLegacy = true
        } else {
            state = Self.defaultPersisted()
        }

        agentEnabled = state.agentEnabled
        toneIntensity = state.toneIntensity
        language = state.language
        productiveBundleIDs = state.productiveBundleIDs
        distractingBundleIDs = state.distractingBundleIDs
        browserWorkKeywords = state.browserWorkKeywords
        cooldownSeconds = min(600, max(8, state.cooldownSeconds))
        maxInterruptionsPerHour = min(60, max(1, state.maxInterruptionsPerHour))
        distractionSecondsBeforeNudge = min(600, max(8, state.distractionSecondsBeforeNudge))
        soundEffectsEnabled = state.soundEffectsEnabled
        startAtLogin = state.startAtLogin
        smartModeEnabled = state.smartModeEnabled
        smartVisionConsent = state.smartVisionConsent
        smartSamplingIntervalSeconds = min(240, max(25, state.smartSamplingIntervalSeconds))
        smartVisionModel = state.smartVisionModel
        smartDebugSaveFrames = state.smartDebugSaveFrames
        ollamaModel = state.ollamaModel
        ollamaBaseURL = state.ollamaBaseURL
        useLLMForLines = state.useLLMForLines
        llmMinIntervalSeconds = min(900, max(1, state.llmMinIntervalSeconds))
        onboardingCompleted = state.onboardingCompleted
        if UserDefaults.standard.object(forKey: Self.gremlinPipelineDebugLoggingKey) != nil {
            gremlinPipelineDebugLogging = UserDefaults.standard.bool(forKey: Self.gremlinPipelineDebugLoggingKey)
        } else {
            #if DEBUG
            gremlinPipelineDebugLogging = true
            #else
            gremlinPipelineDebugLogging = false
            #endif
        }

        var didFixOllamaModel = false
        if !defaults.bool(forKey: Self.migrationOllamaLlama32ExactKey) {
            let trimmed = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "llama3.2" {
                ollamaModel = "llama3.2:3b"
                didFixOllamaModel = true
            }
            defaults.set(true, forKey: Self.migrationOllamaLlama32ExactKey)
        }

        var didAugmentInstagramBundles = false
        if !defaults.bool(forKey: Self.migrationInstagramBundleKey) {
            if !distractingBundleIDs.contains("com.burbn.instagram") {
                distractingBundleIDs.append("com.burbn.instagram")
                didAugmentInstagramBundles = true
            }
            defaults.set(true, forKey: Self.migrationInstagramBundleKey)
        }

        UserDefaults.standard.set(smartModeEnabled, forKey: "fg.feature.smartVision")
        if didMigrateFromLegacy || didAugmentInstagramBundles || didFixOllamaModel {
            persistToDisk()
        }
    }

    private static func persisted(fromLegacy old: LegacyPersisted) -> Persisted {
        Persisted(
            agentEnabled: old.agentEnabled,
            toneIntensity: old.toneIntensity,
            language: old.language,
            productiveBundleIDs: old.productiveBundleIDs,
            distractingBundleIDs: old.distractingBundleIDs,
            browserWorkKeywords: old.browserWorkKeywords,
            cooldownSeconds: old.cooldownSeconds,
            maxInterruptionsPerHour: old.maxInterruptionsPerHour,
            distractionSecondsBeforeNudge: old.distractionSecondsBeforeNudge,
            soundEffectsEnabled: old.soundEffectsEnabled,
            startAtLogin: old.startAtLogin,
            smartModeEnabled: old.smartModeEnabled,
            smartVisionConsent: false,
            smartSamplingIntervalSeconds: 75,
            smartVisionModel: "llava",
            smartDebugSaveFrames: false,
            ollamaModel: old.ollamaModel,
            ollamaBaseURL: old.ollamaBaseURL,
            useLLMForLines: old.useLLMForLines,
            llmMinIntervalSeconds: old.llmMinIntervalSeconds,
            onboardingCompleted: old.onboardingCompleted
        )
    }

    private static func defaultPersisted() -> Persisted {
        Persisted(
            agentEnabled: true,
            toneIntensity: .intervention,
            language: .ru,
            productiveBundleIDs: SettingsStore.defaultProductive,
            distractingBundleIDs: SettingsStore.defaultDistracting,
            browserWorkKeywords: ["github", "notion", "linear", "jira", "figma", "docs.google", "stackoverflow"],
            cooldownSeconds: 12,
            maxInterruptionsPerHour: 48,
            distractionSecondsBeforeNudge: 16,
            soundEffectsEnabled: true,
            startAtLogin: false,
            smartModeEnabled: false,
            smartVisionConsent: false,
            smartSamplingIntervalSeconds: 45,
            smartVisionModel: "llava",
            smartDebugSaveFrames: false,
            ollamaModel: "llama3.2:3b",
            ollamaBaseURL: "http://127.0.0.1:11434",
            useLLMForLines: true,
            llmMinIntervalSeconds: 2,
            onboardingCompleted: false
        )
    }

    private struct Persisted: Codable {
        var agentEnabled: Bool
        var toneIntensity: ToneIntensity
        var language: AppLanguage
        var productiveBundleIDs: [String]
        var distractingBundleIDs: [String]
        var browserWorkKeywords: [String]
        var cooldownSeconds: Double
        var maxInterruptionsPerHour: Int
        var distractionSecondsBeforeNudge: Double
        var soundEffectsEnabled: Bool
        var startAtLogin: Bool
        var smartModeEnabled: Bool
        var smartVisionConsent: Bool
        var smartSamplingIntervalSeconds: Double
        var smartVisionModel: String
        var smartDebugSaveFrames: Bool
        var ollamaModel: String
        var ollamaBaseURL: String
        var useLLMForLines: Bool
        var llmMinIntervalSeconds: Double
        var onboardingCompleted: Bool
    }

    private struct LegacyPersisted: Codable {
        var agentEnabled: Bool
        var toneIntensity: ToneIntensity
        var language: AppLanguage
        var productiveBundleIDs: [String]
        var distractingBundleIDs: [String]
        var browserWorkKeywords: [String]
        var cooldownSeconds: Double
        var maxInterruptionsPerHour: Int
        var distractionSecondsBeforeNudge: Double
        var soundEffectsEnabled: Bool
        var startAtLogin: Bool
        var smartModeEnabled: Bool
        var ollamaModel: String
        var ollamaBaseURL: String
        var useLLMForLines: Bool
        var llmMinIntervalSeconds: Double
        var onboardingCompleted: Bool
    }

    private func persistToDisk() {
        let p = Persisted(
            agentEnabled: agentEnabled,
            toneIntensity: toneIntensity,
            language: language,
            productiveBundleIDs: productiveBundleIDs,
            distractingBundleIDs: distractingBundleIDs,
            browserWorkKeywords: browserWorkKeywords,
            cooldownSeconds: cooldownSeconds,
            maxInterruptionsPerHour: maxInterruptionsPerHour,
            distractionSecondsBeforeNudge: distractionSecondsBeforeNudge,
            soundEffectsEnabled: soundEffectsEnabled,
            startAtLogin: startAtLogin,
            smartModeEnabled: smartModeEnabled,
            smartVisionConsent: smartVisionConsent,
            smartSamplingIntervalSeconds: smartSamplingIntervalSeconds,
            smartVisionModel: smartVisionModel,
            smartDebugSaveFrames: smartDebugSaveFrames,
            ollamaModel: ollamaModel,
            ollamaBaseURL: ollamaBaseURL,
            useLLMForLines: useLLMForLines,
            llmMinIntervalSeconds: llmMinIntervalSeconds,
            onboardingCompleted: onboardingCompleted
        )
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: key)
        }
    }

    private static let defaultProductive: [String] = [
        "com.apple.dt.Xcode",
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "notion.id",
        "com.figma.Desktop",
        "com.tinyspeck.slackmacgap"
    ]

    private static let defaultDistracting: [String] = [
        "com.burbn.instagram",
        "com.twitter.twitter-mac",
        "ru.keepcoder.Telegram",
        "com.hnc.Discord",
        "com.openai.chat"
    ]
}
