import AppKit
import ApplicationServices

/// Читает элемент Accessibility под курсором (macOS); для веба часто грубо, но даёт кнопки/ссылки в нативных UI.
enum CursorHoverInspector {
    /// Краткая строка для промпта (English-oriented факты из AX); `nil` если нет прав или данных.
    static func accessibilitySummaryUnderMouse(maxLength: Int = 300) -> String? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        guard WindowContextProvider.accessibilityAvailable else { return nil }

        let point = NSEvent.mouseLocation
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        guard err == .success, let start = element else { return nil }

        var segments: [String] = []
        var current: AXUIElement? = start
        var depth = 0
        while let el = current, depth < 3 {
            if let part = snippet(for: el), !part.isEmpty {
                segments.append(part)
            }
            current = parent(of: el)
            depth += 1
        }

        guard !segments.isEmpty else { return nil }
        var joined = segments.joined(separator: " · ")
        if joined.count > maxLength {
            joined = String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return joined
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              let ref
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func snippet(for element: AXUIElement) -> String? {
        let roleDesc = readString(element, kAXRoleDescriptionAttribute as CFString)
            ?? readString(element, kAXRoleAttribute as CFString).map {
                $0.replacingOccurrences(of: "AX", with: "").lowercased()
            }
        let title = readString(element, kAXTitleAttribute as CFString)
        let value = readString(element, kAXValueAttribute as CFString).map { clip($0, 88) }
        let description = readString(element, kAXDescriptionAttribute as CFString).map { clip($0, 88) }

        var parts: [String] = []
        if let r = roleDesc, !r.isEmpty { parts.append(r) }
        if let t = title, !t.isEmpty { parts.append("«\(t)»") }
        if let v = value, !v.isEmpty, v != title { parts.append(v) }
        if let d = description, !d.isEmpty, d != title, d != value { parts.append(d) }

        let joined = parts.joined(separator: " ")
        if joined.isEmpty { return nil }

        let lowerRole = (roleDesc ?? "").lowercased()
        let vagueOnly = ["group", "unknown", "window"].contains(where: { lowerRole == $0 })
        if vagueOnly, title == nil, value == nil, description == nil { return nil }

        return joined
    }

    private static func clip(_ s: String, _ max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func readString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref
        else { return nil }
        if let s = ref as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let att = ref as? NSAttributedString {
            let t = att.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }
}
