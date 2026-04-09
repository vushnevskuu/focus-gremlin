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

    static var screenRecordingAuthorized: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func openPrivacyPane(anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)")!
        NSWorkspace.shared.open(url)
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
