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

    /// Открывает нужный раздел приватности (несколько схем URL — на новых macOS часто срабатывает только extension).
    static func openPrivacyPane(anchor: String) {
        let candidates: [String]
        if #available(macOS 13.0, *) {
            candidates = [
                "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_\(anchor)",
                "x-apple.systemsettings:com.apple.preference.security?Privacy_\(anchor)"
            ]
        } else {
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)"
            ]
        }
        for s in candidates {
            guard let url = URL(string: s) else { continue }
            NSWorkspace.shared.open(url)
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
