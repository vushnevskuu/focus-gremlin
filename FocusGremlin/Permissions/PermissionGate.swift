import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionGate {
    /// Системный флаг + запасной **функциональный** тест (на части macOS AXTrusted врёт до перезапуска или после смены сборки .app).
    static var accessibilityTrusted: Bool {
        WindowContextProvider.accessibilityAvailable
    }

    /// Для глобального мониторинга скролла обычно нужен доступ из настроек приватности (Input Monitoring).
    static var inputMonitoringLikelyAvailable: Bool {
        accessibilityTrusted
    }

    /// Пассивная проверка разрешения на запись экрана. Без пробного захвата:
    /// он может сам поднять системный TCC-диалог, чего мы как раз хотим избежать.
    static var screenRecordingPreflightGranted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// Для Smart Mode и захвата — то же, что отображаем в настройках.
    static var screenRecordingAuthorized: Bool { screenRecordingPreflightGranted }

    /// Deep link в подраздел приватности. Схема `…PrivacySecurity.extension?…` на части сборок macOS не зарегистрирована и даёт диалог Finder «нет приложения для URL».
    /// Раздел «Мониторинг ввода» (Input Monitoring) — нужен для `NSEvent.addGlobalMonitorForEvents(.scrollWheel)`.
    static func openInputMonitoringPane() {
        openPrivacyPane(anchor: "ListenEvent")
    }

    static func openPrivacyPane(anchor: String) {
        let query = "Privacy_\(anchor)"
        let candidates: [String]
        if #available(macOS 13.0, *) {
            // На части сборок `systemsettings` не привязан к хэндлеру → диалог Finder; `systempreferences` часто открывает System Settings.
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?\(query)",
                "x-apple.systemsettings:com.apple.preference.security?\(query)"
            ]
        } else {
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?\(query)"
            ]
        }
        for s in candidates {
            guard let url = URL(string: s) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        openSystemPrivacySettingsFallback()
    }

    /// Если ни один URL не собрался — открываем хотя бы приложение «Настройки».
    private static func openSystemPrivacySettingsFallback() {
        let paths = [
            "/System/Applications/System Settings.app",
            "/System/Applications/System Preferences.app"
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
            return
        }
    }

    /// Не вызываем системный prompt автоматически. Вместо этого просто открываем нужный раздел настроек.
    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        openPrivacyPane(anchor: "ScreenCapture")
        return screenRecordingAuthorized
    }
}
