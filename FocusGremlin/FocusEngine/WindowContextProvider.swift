import AppKit
import ApplicationServices

struct FrontmostWindowSnapshot: Sendable {
    let title: String?
    let frame: CGRect?
}

struct FrontmostBrowserPageContext: Sendable {
    let title: String?
    let url: String?
    let semanticSnippet: String?
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
        let semanticSnippet = normalizedSemanticSnippet(
            trimmedDescriptorString(descriptor.atIndex(3))
        )
        if title == nil, url == nil, semanticSnippet == nil {
            return nil
        }
        return FrontmostBrowserPageContext(title: title, url: url, semanticSnippet: semanticSnippet)
    }

    private static func appleScriptSource(bundleID: String) -> String? {
        switch browserScriptKind(for: bundleID) {
        case .safari:
            return """
            tell application id "\(bundleID)"
                if not (exists front window) then return {"", "", ""}
                set tabRef to current tab of front window
                set pageTitle to name of tabRef
                set pageURL to URL of tabRef
                set pageSnippet to ""
                try
                    set pageSnippet to text of tabRef
                on error
                    set pageSnippet to ""
                end try
                return {pageTitle, pageURL, pageSnippet}
            end tell
            """
        case .chromium:
            let jsSource = semanticSnippetJavaScript().replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            set jsSource to "\(jsSource)"
            tell application id "\(bundleID)"
                if not (exists front window) then return {"", "", ""}
                set tabRef to active tab of front window
                set pageTitle to title of tabRef
                set pageURL to URL of tabRef
                set pageSnippet to ""
                try
                    set pageSnippet to execute tabRef javascript jsSource
                on error
                    set pageSnippet to ""
                end try
                return {pageTitle, pageURL, pageSnippet}
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

    private static func normalizedSemanticSnippet(_ raw: String?) -> String? {
        let blob = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !blob.isEmpty else { return nil }

        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "|"))
        let rawParts = blob.components(separatedBy: separators)
        var seen = Set<String>()
        var kept: [String] = []
        kept.reserveCapacity(4)

        for part in rawParts {
            var token = part
                .replacingOccurrences(of: "\u{2028}", with: " ")
                .replacingOccurrences(of: "\u{2029}", with: " ")
                .split(whereSeparator: { $0.isNewline })
                .joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count >= 4 else { continue }
            if token.count > 120 {
                token = String(token.prefix(117)) + "..."
            }
            let key = token.lowercased()
            guard seen.insert(key).inserted else { continue }
            kept.append(token)
            if kept.count >= 4 { break }
        }

        guard !kept.isEmpty else { return nil }
        let joined = kept.joined(separator: " | ")
        if joined.count <= 240 {
            return joined
        }
        return String(joined.prefix(237)) + "..."
    }

    private static func semanticSnippetJavaScript() -> String {
        """
        (() => { const clean = value => (value || '').replace(/\\s+/g, ' ').trim(); const out = []; const seen = new Set(); const add = value => { let text = clean(value); if (!text || text.length < 4) return; const key = text.toLowerCase(); if (seen.has(key)) return; seen.add(key); if (text.length > 120) text = text.slice(0, 117) + '...'; out.push(text); }; try { add(window.getSelection && window.getSelection().toString()); } catch (e) {} try { const active = document.activeElement; if (active) { add(active.getAttribute && active.getAttribute('aria-label')); add('value' in active ? active.value : ''); add(active.innerText || active.textContent); } } catch (e) {} const selectors = ['main h1', 'article h1', 'h1', 'h2', '[role=\"heading\"]', 'main p', 'article p', 'main li', 'article li', 'button', 'a', '[aria-label]']; const visible = el => { try { const rect = el.getBoundingClientRect(); return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight * 1.2; } catch (e) { return false; } }; outer: for (const selector of selectors) { const nodes = document.querySelectorAll(selector); for (const node of nodes) { if (!visible(node)) continue; add(node.innerText || node.textContent || ('value' in node ? node.value : '')); if (out.length >= 6 || out.join(' | ').length >= 260) break outer; } } return clean(out.join(' | ')).slice(0, 260); })()
        """
    }
}
