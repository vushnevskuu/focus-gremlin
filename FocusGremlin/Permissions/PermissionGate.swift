import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionGate {
    static var accessibilityTrusted: Bool {
        WindowContextProvider.isAccessibilityTrusted
    }

    /// Для глобального мониторинга скролла обычно нужен доступ из настроек приватности (Input Monitoring).
    static var inputMonitoringLikelyAvailable: Bool {
        accessibilityTrusted
    }

    /// `CGPreflightScreenCaptureAccess` на части версий macOS расходится с TCC (в настройках уже «вкл», а preflight — false).
    /// `CGRequestScreenCaptureAccess` при уже сохранённом ответе пользователя не показывает диалог и отражает фактический доступ.
    static var screenRecordingAuthorized: Bool {
        if #available(macOS 10.15, *) {
            if CGPreflightScreenCaptureAccess() { return true }
            return CGRequestScreenCaptureAccess()
        }
        return true
    }

    /// Deep link в подраздел приватности. Схема `…PrivacySecurity.extension?…` на части сборок macOS не зарегистрирована и даёт диалог Finder «нет приложения для URL».
    static func openPrivacyPane(anchor: String) {
        let query = "Privacy_\(anchor)"
        let candidates: [String]
        if #available(macOS 13.0, *) {
            candidates = [
                "x-apple.systemsettings:com.apple.preference.security?\(query)",
                "x-apple.systempreferences:com.apple.preference.security?\(query)"
            ]
        } else {
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?\(query)"
            ]
        }
        for s in candidates {
            guard let url = URL(string: s) else { continue }
            NSWorkspace.shared.open(url)
            return
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

    /// Запросить доступ к записи экрана (покажет системный диалог при необходимости).
    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
}
