import AppKit
import ApplicationServices

/// Заголовок фронтального окна через Accessibility. Без доверия возвращает nil — это нормальный graceful fallback.
enum WindowContextProvider {
    static func frontmostWindowTitle() -> String? {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary) else {
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
}
