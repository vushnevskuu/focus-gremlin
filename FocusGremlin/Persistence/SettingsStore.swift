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
    /// Провайдер для реплик гоблина и скима страницы (Ollama / OpenAI-совместимый / Anthropic).
    @Published var llmBackend: GremlinLLMBackend {
        didSet { schedulePersistToDisk() }
    }
    /// Базовый URL для OpenAI-совместимого API, с суффиксом `/v1` (например `https://api.openai.com/v1`).
    @Published var cloudAPIBaseURL: String {
        didSet { schedulePersistToDisk() }
    }
    /// Модель для облака (vision-capable, если шлём JPEG): например `gpt-4o-mini`, `claude-3-5-sonnet-20241022`.
    @Published var cloudChatModel: String {
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
        gremlinLLMDiagnosticLine = "\(llmBackend.successLogTag): реплика сгенерирована (\(f.string(from: Date())))."
    }

    func noteGremlinLLMFailure(_ message: String) {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // OpenAI часто шлёт HTTP 429 + JSON с billing_not_active — это не «неверный ключ» и не баг приложения.
        if Self.isOpenAIBillingBlockedMessage(m) {
            gremlinLLMDiagnosticLine =
                "OpenAI отклонил запрос: у аккаунта этого API-ключа нет активной оплаты (billing). Приложение и ключ тут ни при чём — зайдите на https://platform.openai.com/account/billing , включите оплату и пополните баланс (или выберите другую организацию в настройках ключа)."
            return
        }
        gremlinLLMDiagnosticLine = "Нет ответа нейросети — показан запасной текст. \(m)"
    }

    private static func isOpenAIBillingBlockedMessage(_ m: String) -> Bool {
        let lower = m.lowercased()
        if lower.contains("billing_not_active") { return true }
        if lower.contains("your account is not active") { return true }
        if lower.contains("check your billing") { return true }
        if lower.contains("\"type\":\"billing_not_active\"") { return true }
        if lower.contains("не активен биллинг") { return true }
        return false
    }

    /// Ручная проверка текущего провайдера (без картинки).
    func runGremlinLLMSmokeTest() async {
        gremlinLLMDiagnosticLine = "Проверка \(llmBackend.settingsLabel)…"
        let provider = GremlinLLMProviderFactory.makeProvider(settings: self)
        if provider is MockLLMProvider {
            noteGremlinLLMFailure("Провайдер не сконфигурирован (см. подсказку в настройках).")
            return
        }
        let modelHint: String
        switch llmBackend {
        case .ollama:
            modelHint = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            modelHint = cloudChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !modelHint.isEmpty else {
            noteGremlinLLMFailure("Имя модели пустое.")
            return
        }
        do {
            let line = try await provider.complete(
                systemPrompt: "Reply with exactly one word: OK",
                userPrompt: "Test.",
                jpegImages: [],
                chatModel: nil
            )
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if t.contains("OK") {
                noteGremlinLLMSuccess()
                gremlinLLMDiagnosticLine = "Проверка OK: \(llmBackend.successLogTag), модель «\(modelHint)» отвечает."
            } else {
                noteGremlinLLMFailure("Странный ответ: «\(line.prefix(100))»")
            }
        } catch {
            noteGremlinLLMFailure(error.localizedDescription)
        }
    }

    /// Имя модели для вызова с JPEG: у Ollama — vision-модель из Smart Mode; у облака — `cloudChatModel`.
    func effectiveModelForMultimodalCall(smartVisionModel: String, attachVision: Bool) -> String? {
        guard attachVision else { return nil }
        switch llmBackend {
        case .ollama:
            let v = smartVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        default:
            let m = cloudChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : m
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
        cooldownSeconds = min(600, max(5, state.cooldownSeconds))
        maxInterruptionsPerHour = min(240, max(1, state.maxInterruptionsPerHour))
        distractionSecondsBeforeNudge = min(600, max(8, state.distractionSecondsBeforeNudge))
        soundEffectsEnabled = state.soundEffectsEnabled
        startAtLogin = state.startAtLogin
        smartModeEnabled = state.smartModeEnabled
        smartVisionConsent = state.smartVisionConsent
        smartSamplingIntervalSeconds = min(240, max(5, state.smartSamplingIntervalSeconds))
        smartVisionModel = state.smartVisionModel
        smartDebugSaveFrames = state.smartDebugSaveFrames
        ollamaModel = state.ollamaModel
        ollamaBaseURL = state.ollamaBaseURL
        llmBackend = state.llmBackend
        cloudAPIBaseURL = state.cloudAPIBaseURL
        cloudChatModel = state.cloudChatModel
        useLLMForLines = state.useLLMForLines
        llmMinIntervalSeconds = min(900, max(3, state.llmMinIntervalSeconds))
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
            llmBackend: .ollama,
            cloudAPIBaseURL: "https://api.openai.com/v1",
            cloudChatModel: "gpt-4o-mini",
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
            cooldownSeconds: 5,
            maxInterruptionsPerHour: 120,
            distractionSecondsBeforeNudge: 12,
            soundEffectsEnabled: true,
            startAtLogin: false,
            smartModeEnabled: false,
            smartVisionConsent: false,
            smartSamplingIntervalSeconds: 5,
            smartVisionModel: "llava",
            smartDebugSaveFrames: false,
            ollamaModel: "llama3.2:3b",
            ollamaBaseURL: "http://127.0.0.1:11434",
            llmBackend: .ollama,
            cloudAPIBaseURL: "https://api.openai.com/v1",
            cloudChatModel: "gpt-4o-mini",
            useLLMForLines: true,
            llmMinIntervalSeconds: 5,
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
        var llmBackend: GremlinLLMBackend
        var cloudAPIBaseURL: String
        var cloudChatModel: String
        var useLLMForLines: Bool
        var llmMinIntervalSeconds: Double
        var onboardingCompleted: Bool

        enum CodingKeys: String, CodingKey {
            case agentEnabled, toneIntensity, language, productiveBundleIDs, distractingBundleIDs
            case browserWorkKeywords, cooldownSeconds, maxInterruptionsPerHour, distractionSecondsBeforeNudge
            case soundEffectsEnabled, startAtLogin, smartModeEnabled, smartVisionConsent
            case smartSamplingIntervalSeconds, smartVisionModel, smartDebugSaveFrames
            case ollamaModel, ollamaBaseURL, llmBackend, cloudAPIBaseURL, cloudChatModel
            case useLLMForLines, llmMinIntervalSeconds, onboardingCompleted
        }

        init(
            agentEnabled: Bool,
            toneIntensity: ToneIntensity,
            language: AppLanguage,
            productiveBundleIDs: [String],
            distractingBundleIDs: [String],
            browserWorkKeywords: [String],
            cooldownSeconds: Double,
            maxInterruptionsPerHour: Int,
            distractionSecondsBeforeNudge: Double,
            soundEffectsEnabled: Bool,
            startAtLogin: Bool,
            smartModeEnabled: Bool,
            smartVisionConsent: Bool,
            smartSamplingIntervalSeconds: Double,
            smartVisionModel: String,
            smartDebugSaveFrames: Bool,
            ollamaModel: String,
            ollamaBaseURL: String,
            llmBackend: GremlinLLMBackend,
            cloudAPIBaseURL: String,
            cloudChatModel: String,
            useLLMForLines: Bool,
            llmMinIntervalSeconds: Double,
            onboardingCompleted: Bool
        ) {
            self.agentEnabled = agentEnabled
            self.toneIntensity = toneIntensity
            self.language = language
            self.productiveBundleIDs = productiveBundleIDs
            self.distractingBundleIDs = distractingBundleIDs
            self.browserWorkKeywords = browserWorkKeywords
            self.cooldownSeconds = cooldownSeconds
            self.maxInterruptionsPerHour = maxInterruptionsPerHour
            self.distractionSecondsBeforeNudge = distractionSecondsBeforeNudge
            self.soundEffectsEnabled = soundEffectsEnabled
            self.startAtLogin = startAtLogin
            self.smartModeEnabled = smartModeEnabled
            self.smartVisionConsent = smartVisionConsent
            self.smartSamplingIntervalSeconds = smartSamplingIntervalSeconds
            self.smartVisionModel = smartVisionModel
            self.smartDebugSaveFrames = smartDebugSaveFrames
            self.ollamaModel = ollamaModel
            self.ollamaBaseURL = ollamaBaseURL
            self.llmBackend = llmBackend
            self.cloudAPIBaseURL = cloudAPIBaseURL
            self.cloudChatModel = cloudChatModel
            self.useLLMForLines = useLLMForLines
            self.llmMinIntervalSeconds = llmMinIntervalSeconds
            self.onboardingCompleted = onboardingCompleted
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            agentEnabled = try c.decode(Bool.self, forKey: .agentEnabled)
            toneIntensity = try c.decode(ToneIntensity.self, forKey: .toneIntensity)
            language = try c.decode(AppLanguage.self, forKey: .language)
            productiveBundleIDs = try c.decode([String].self, forKey: .productiveBundleIDs)
            distractingBundleIDs = try c.decode([String].self, forKey: .distractingBundleIDs)
            browserWorkKeywords = try c.decode([String].self, forKey: .browserWorkKeywords)
            cooldownSeconds = try c.decode(Double.self, forKey: .cooldownSeconds)
            maxInterruptionsPerHour = try c.decode(Int.self, forKey: .maxInterruptionsPerHour)
            distractionSecondsBeforeNudge = try c.decode(Double.self, forKey: .distractionSecondsBeforeNudge)
            soundEffectsEnabled = try c.decode(Bool.self, forKey: .soundEffectsEnabled)
            startAtLogin = try c.decode(Bool.self, forKey: .startAtLogin)
            smartModeEnabled = try c.decode(Bool.self, forKey: .smartModeEnabled)
            smartVisionConsent = try c.decode(Bool.self, forKey: .smartVisionConsent)
            smartSamplingIntervalSeconds = try c.decode(Double.self, forKey: .smartSamplingIntervalSeconds)
            smartVisionModel = try c.decode(String.self, forKey: .smartVisionModel)
            smartDebugSaveFrames = try c.decode(Bool.self, forKey: .smartDebugSaveFrames)
            ollamaModel = try c.decode(String.self, forKey: .ollamaModel)
            ollamaBaseURL = try c.decode(String.self, forKey: .ollamaBaseURL)
            llmBackend = try c.decodeIfPresent(GremlinLLMBackend.self, forKey: .llmBackend) ?? .ollama
            cloudAPIBaseURL = try c.decodeIfPresent(String.self, forKey: .cloudAPIBaseURL) ?? "https://api.openai.com/v1"
            cloudChatModel = try c.decodeIfPresent(String.self, forKey: .cloudChatModel) ?? "gpt-4o-mini"
            useLLMForLines = try c.decode(Bool.self, forKey: .useLLMForLines)
            llmMinIntervalSeconds = try c.decode(Double.self, forKey: .llmMinIntervalSeconds)
            onboardingCompleted = try c.decode(Bool.self, forKey: .onboardingCompleted)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(agentEnabled, forKey: .agentEnabled)
            try c.encode(toneIntensity, forKey: .toneIntensity)
            try c.encode(language, forKey: .language)
            try c.encode(productiveBundleIDs, forKey: .productiveBundleIDs)
            try c.encode(distractingBundleIDs, forKey: .distractingBundleIDs)
            try c.encode(browserWorkKeywords, forKey: .browserWorkKeywords)
            try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
            try c.encode(maxInterruptionsPerHour, forKey: .maxInterruptionsPerHour)
            try c.encode(distractionSecondsBeforeNudge, forKey: .distractionSecondsBeforeNudge)
            try c.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
            try c.encode(startAtLogin, forKey: .startAtLogin)
            try c.encode(smartModeEnabled, forKey: .smartModeEnabled)
            try c.encode(smartVisionConsent, forKey: .smartVisionConsent)
            try c.encode(smartSamplingIntervalSeconds, forKey: .smartSamplingIntervalSeconds)
            try c.encode(smartVisionModel, forKey: .smartVisionModel)
            try c.encode(smartDebugSaveFrames, forKey: .smartDebugSaveFrames)
            try c.encode(ollamaModel, forKey: .ollamaModel)
            try c.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
            try c.encode(llmBackend, forKey: .llmBackend)
            try c.encode(cloudAPIBaseURL, forKey: .cloudAPIBaseURL)
            try c.encode(cloudChatModel, forKey: .cloudChatModel)
            try c.encode(useLLMForLines, forKey: .useLLMForLines)
            try c.encode(llmMinIntervalSeconds, forKey: .llmMinIntervalSeconds)
            try c.encode(onboardingCompleted, forKey: .onboardingCompleted)
        }
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
            llmBackend: llmBackend,
            cloudAPIBaseURL: cloudAPIBaseURL,
            cloudChatModel: cloudChatModel,
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
