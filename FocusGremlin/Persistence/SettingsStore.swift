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

    private var persistWorkItem: DispatchWorkItem?

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
        cooldownSeconds = state.cooldownSeconds
        maxInterruptionsPerHour = state.maxInterruptionsPerHour
        distractionSecondsBeforeNudge = state.distractionSecondsBeforeNudge
        soundEffectsEnabled = state.soundEffectsEnabled
        startAtLogin = state.startAtLogin
        smartModeEnabled = state.smartModeEnabled
        smartVisionConsent = state.smartVisionConsent
        smartSamplingIntervalSeconds = state.smartSamplingIntervalSeconds
        smartVisionModel = state.smartVisionModel
        smartDebugSaveFrames = state.smartDebugSaveFrames
        ollamaModel = state.ollamaModel
        ollamaBaseURL = state.ollamaBaseURL
        useLLMForLines = state.useLLMForLines
        llmMinIntervalSeconds = state.llmMinIntervalSeconds
        onboardingCompleted = state.onboardingCompleted

        UserDefaults.standard.set(smartModeEnabled, forKey: "fg.feature.smartVision")
        if didMigrateFromLegacy {
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
            toneIntensity: .snarky,
            language: .ru,
            productiveBundleIDs: SettingsStore.defaultProductive,
            distractingBundleIDs: SettingsStore.defaultDistracting,
            browserWorkKeywords: ["github", "notion", "linear", "jira", "figma", "docs.google", "stackoverflow"],
            cooldownSeconds: 90,
            maxInterruptionsPerHour: 8,
            distractionSecondsBeforeNudge: 45,
            soundEffectsEnabled: false,
            startAtLogin: false,
            smartModeEnabled: false,
            smartVisionConsent: false,
            smartSamplingIntervalSeconds: 75,
            smartVisionModel: "llava",
            smartDebugSaveFrames: false,
            ollamaModel: "llama3.2",
            ollamaBaseURL: "http://127.0.0.1:11434",
            useLLMForLines: true,
            llmMinIntervalSeconds: 120,
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
        "com.twitter.twitter-mac",
        "ru.keepcoder.Telegram",
        "com.hnc.Discord",
        "com.openai.chat"
    ]
}
