import AppKit
import ApplicationServices

/// Заголовок фронтального окна через Accessibility. Без доверия возвращает nil — это нормальный graceful fallback.
enum WindowContextProvider {
    static func frontmostWindowTitle() -> String? {
        guard accessibilityAvailable else {
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focused)
        guard focusResult == .success, let windowEl = focused else { return nil }
        let axWindow = windowEl as! AXUIElement
        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let t = titleRef as? String else { return nil }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    /// На части macOS/TCC после пересборки ad-hoc приложения системный флаг может временно врать.
    /// Держим тот же функциональный fallback, что и в UI статуса прав, чтобы browser title не пропадал.
    static var accessibilityAvailable: Bool {
        if isAccessibilityTrusted { return true }
        return accessibilitySelfWindowsProbeSucceeds()
    }

    /// Реально ли читается список окон своего процесса через AX (признак выданного Accessibility).
    private static func accessibilitySelfWindowsProbeSucceeds() -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windows)
        guard err == .success else { return false }
        if let arr = windows as? [Any] { return !arr.isEmpty }
        return windows != nil
    }
}
