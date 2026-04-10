import AppKit
import ApplicationServices

struct FrontmostWindowSnapshot: Sendable {
    let title: String?
    let frame: CGRect?
}

struct FrontmostBrowserPageContext: Sendable {
    let title: String?
    let url: String?
}

/// Заголовок фронтального окна через Accessibility. Без доверия возвращает nil — это нормальный graceful fallback.
enum WindowContextProvider {
    private struct BrowserPageCacheEntry {
        let bundleID: String
        let fetchedAt: Date
        let context: FrontmostBrowserPageContext?
    }

    private static var browserPageCache: BrowserPageCacheEntry?

    static func frontmostWindowTitle() -> String? {
        frontmostWindowSnapshot()?.title
    }

    static func frontmostWindowSnapshot() -> FrontmostWindowSnapshot? {
        guard accessibilityAvailable else {
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        guard let axWindow = focusedWindowElement(appElement: appEl) else { return nil }

        let title = readStringAttribute(element: axWindow, attribute: kAXTitleAttribute as CFString)
        let position = readPointAttribute(element: axWindow, attribute: kAXPositionAttribute as CFString)
        let size = readSizeAttribute(element: axWindow, attribute: kAXSizeAttribute as CFString)
        let frame: CGRect? = {
            guard let position, let size, size.width > 0, size.height > 0 else { return nil }
            return CGRect(origin: position, size: size).standardized
        }()

        if title == nil, frame == nil {
            return nil
        }
        return FrontmostWindowSnapshot(title: title, frame: frame)
    }

    @MainActor
    static func frontmostBrowserPageContext(bundleID: String) -> FrontmostBrowserPageContext? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return nil
        }
        guard browserScriptKind(for: bundleID) != .unsupported else { return nil }

        let now = Date()
        if let cached = browserPageCache, cached.bundleID == bundleID {
            let ttl: TimeInterval = cached.context == nil ? 4.0 : 0.8
            if now.timeIntervalSince(cached.fetchedAt) < ttl {
                return cached.context
            }
        }

        let context = queryBrowserPageContext(bundleID: bundleID)
        browserPageCache = BrowserPageCacheEntry(bundleID: bundleID, fetchedAt: now, context: context)
        return context
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

    private static func focusedWindowElement(appElement: AXUIElement) -> AXUIElement? {
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard focusResult == .success, let windowEl = focused else { return nil }
        return (windowEl as! AXUIElement)
    }

    private static func readStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref as? String
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readPointAttribute(element: AXUIElement, attribute: CFString) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func readSizeAttribute(element: AXUIElement, attribute: CFString) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private enum BrowserScriptKind {
        case safari
        case chromium
        case unsupported
    }

    private static func browserScriptKind(for bundleID: String) -> BrowserScriptKind {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return .safari
        case "com.google.Chrome",
             "com.google.Chrome.canary",
             "com.brave.Browser",
             "com.microsoft.edgemac",
             "org.chromium.Chromium",
             "company.thebrowser.Browser",
             "com.operasoftware.Opera",
             "com.vivaldi.Vivaldi":
            return .chromium
        default:
            return .unsupported
        }
    }

    private static func queryBrowserPageContext(bundleID: String) -> FrontmostBrowserPageContext? {
        guard let source = appleScriptSource(bundleID: bundleID),
              let script = NSAppleScript(source: source)
        else { return nil }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            AppLogger.focus.debug(
                "Browser page context unavailable bundle=\(bundleID, privacy: .public) error=\(String(describing: errorInfo[NSAppleScript.errorMessage]), privacy: .public)"
            )
            return nil
        }

        let title = trimmedDescriptorString(descriptor.atIndex(1))
        let url = trimmedDescriptorString(descriptor.atIndex(2))
        if title == nil, url == nil {
            return nil
        }
        return FrontmostBrowserPageContext(title: title, url: url)
    }

    private static func appleScriptSource(bundleID: String) -> String? {
        switch browserScriptKind(for: bundleID) {
        case .safari:
            return """
            tell application id "\(bundleID)"
                if not (exists front window) then return {"", ""}
                set tabRef to current tab of front window
                set pageTitle to name of tabRef
                set pageURL to URL of tabRef
                return {pageTitle, pageURL}
            end tell
            """
        case .chromium:
            return """
            tell application id "\(bundleID)"
                if not (exists front window) then return {"", ""}
                set tabRef to active tab of front window
                set pageTitle to title of tabRef
                set pageURL to URL of tabRef
                return {pageTitle, pageURL}
            end tell
            """
        case .unsupported:
            return nil
        }
    }

    private static func trimmedDescriptorString(_ descriptor: NSAppleEventDescriptor?) -> String? {
        let value = descriptor?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
