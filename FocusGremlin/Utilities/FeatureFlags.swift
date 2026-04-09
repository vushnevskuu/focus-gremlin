import Foundation

/// Флаги для постепенного включения функций без перекомпиляции всего приложения.
enum FeatureFlags {
    static var smartVisionModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "fg.feature.smartVision")
    }

    static var globalScrollMonitoringPreferred: Bool {
        UserDefaults.standard.object(forKey: "fg.feature.scrollMonitor") as? Bool ?? true
    }
}
