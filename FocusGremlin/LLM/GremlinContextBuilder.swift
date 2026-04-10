import AppKit
import Foundation

/// Контекст для одной реплики Скрежета: что видит движок фокуса + опционально Smart Mode.
struct GremlinInterventionContext: Sendable {
    let trigger: DistractionTrigger
    let bundleID: String
    let windowTitle: String?
    let pageTitle: String?
    let pageURL: String?
    let focusCategory: FocusCategory
    let visionCategory: FocusCategory?
    /// Краткая оценка LLM/VLM сразу после смены страницы doomscroll (`idle_2` реакция).
    let neuralPageChangeDigest: String?
    /// Элемент UI под курсором (Accessibility); может быть пусто в вебе или без прав.
    let pointerAccessibilitySummary: String?

    var pageIdentityKey: String? {
        let snapshot = FocusSnapshot(
            bundleID: bundleID,
            windowTitle: windowTitle,
            pageTitle: pageTitle,
            pageURL: pageURL,
            timestamp: Date()
        )
        return snapshot.pageIdentityKey
    }
}

/// Собирает описание обстановки для LLM (всегда на английском — единый язык инструкций и фактов).
enum GremlinContextBuilder {
    private static let bundleDisplayNames: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
        "com.google.Chrome": "Chrome",
        "com.google.Chrome.canary": "Chrome Canary",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Microsoft Edge",
        "org.mozilla.firefox": "Firefox",
        "org.chromium.Chromium": "Chromium",
        "company.thebrowser.Browser": "Arc",
        "app.zen-browser.zen": "Zen Browser",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi"
    ]

    static func appDisplayName(bundleID: String) -> String {
        if let n = bundleDisplayNames[bundleID] { return n }
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = url.deletingPathExtension().lastPathComponent
            if !name.isEmpty { return name.replacingOccurrences(of: ".app", with: "") }
        }
        return bundleID.isEmpty ? "unknown_app" : bundleID
    }

    static func isBrowserBundle(_ bundleID: String) -> Bool {
        FocusRuleConfiguration.defaultBrowsers.contains(bundleID)
    }

    /// Heuristic bullets only; model must not invent detail beyond this list.
    static func situationBullets(title: String, bundleID: String, pageURL: String?) -> [String] {
        let urlText = pageURL?.folding(options: .diacriticInsensitive, locale: .current).lowercased() ?? ""
        let t = [title, urlText].joined(separator: " ").folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var lines: [String] = []

        if isBrowserBundle(bundleID) {
            lines.append("Context: web browser (infer site from tab title, page URL, and attached image; title may be missing while the tab still has content).")
        }

        if let pageURL,
           let parsed = URL(string: pageURL),
           let host = parsed.host?.lowercased() {
            let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            lines.append("Browser page host: \(trimmedHost).")
        }

        let pairs: [(String, String)] = [
            ("youtube", "Looks like YouTube / video content."),
            ("youtu.be", "Looks like YouTube / video content."),
            ("reddit", "Looks like Reddit / feed."),
            ("instagram", "Looks like Instagram."),
            ("tiktok", "Looks like TikTok."),
            ("twitter", "Looks like Twitter/X."),
            ("x.com", "Looks like Twitter/X."),
            ("facebook", "Looks like Facebook."),
            ("twitch", "Looks like Twitch / streams."),
            ("threads.net", "Looks like Threads."),
            ("vk.com", "Looks like VK."),
            ("ok.ru", "Looks like OK.ru."),
            ("github", "Looks like GitHub / code."),
            ("gitlab", "Looks like GitLab."),
            ("notion", "Looks like Notion."),
            ("linear", "Looks like Linear."),
            ("jira", "Looks like Jira."),
            ("figma", "Looks like Figma."),
            ("stackoverflow", "Looks like Stack Overflow."),
            ("wikipedia", "Looks like Wikipedia / reference reading."),
            ("news", "Looks like a news site."),
            ("mail", "Looks like email."),
            ("netflix", "Looks like Netflix / shows.")
        ]

        for (needle, en) in pairs where t.contains(needle) {
            lines.append(en)
        }

        if lines.count == 1, isBrowserBundle(bundleID), t.split(whereSeparator: { $0.isWhitespace }).joined().isEmpty == false {
            lines.append("There is a title—tie your roast to visible words in the tab title; do not invent the full article.")
        }

        return lines
    }

    static func visionBullet(vision: FocusCategory?) -> String? {
        guard let v = vision else { return nil }
        switch v {
        case .productive:
            return "Smart Mode (last screen frame): classified as likely work."
        case .neutral:
            return "Smart Mode: frame looks neutral (not clearly work or distraction)."
        case .distracting:
            return "Smart Mode: frame looks like distraction (social, video, games, idle scroll, etc.)."
        }
    }

    static func focusCategoryLine(_ c: FocusCategory) -> String {
        switch c {
        case .distracting: return "Focus classifier: current mode is distraction."
        case .productive: return "Focus classifier: current mode is productive."
        case .neutral: return "Focus classifier: neutral context."
        }
    }

    static func triggerLine(_ t: DistractionTrigger) -> String {
        switch t {
        case .sustained: return "Trigger: sustained distraction."
        case .scrollSession: return "Trigger: heavy scroll session."
        case .chaoticSwitching: return "Trigger: chaotic window switching."
        case .boomerang: return "Trigger: boomerang back to distraction."
        case .smartVision: return "Trigger: smart vision signal."
        case .pageChange: return "Trigger: a fresh distracting page just opened."
        }
    }

    /// Короткая подсказка из URL, когда заголовок вкладки не пришёл из AppleScript (часто в браузерах).
    static func browserLocationHint(pageURL: String?) -> String? {
        let raw = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        guard !host.isEmpty else { return nil }
        var path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count > 56 {
            path = String(path.prefix(53)) + "…"
        }
        if path.isEmpty || path == "/" {
            return host
        }
        return "\(host)\(path)"
    }

    /// Full block for the user prompt (English only).
    static func situationBlock(context: GremlinInterventionContext) -> String {
        let app = appDisplayName(bundleID: context.bundleID)
        let title = (context.pageTitle ?? context.windowTitle)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var parts: [String] = []
        parts.append("═══ Situation (use for a targeted line) ═══")
        parts.append("Application: \(app) (bundle: \(context.bundleID))")
        parts.append(triggerLine(context.trigger))
        parts.append(focusCategoryLine(context.focusCategory))
        if title.isEmpty {
            parts.append(
                "Window or tab title: **not returned by browser automation** (Safari/Chrome may omit it while loading or for security). The page can still be full of content—use the URL line below and any attached image to infer what the user is viewing."
            )
            if let hint = browserLocationHint(pageURL: context.pageURL) {
                parts.append("• **Grounding from URL (use if title missing):** \(hint)")
            }
        } else {
            parts.append("Window or tab title: \(title)")
        }
        if let pageURL = context.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !pageURL.isEmpty {
            parts.append("Browser page URL: \(pageURL)")
        }

        let bullets = situationBullets(title: title, bundleID: context.bundleID, pageURL: context.pageURL)
        for b in bullets {
            parts.append("• \(b)")
        }

        if let vb = visionBullet(vision: context.visionCategory) {
            parts.append("• \(vb)")
        } else {
            parts.append("• Smart Mode: no fresh screen summary (off, no permission, or stale)—rely on title and trigger.")
        }

        if let skim = context.neuralPageChangeDigest?.trimmingCharacters(in: .whitespacesAndNewlines), !skim.isEmpty {
            parts.append("• Agent skim after new page navigation: \(skim)")
        }

        if let hover = context.pointerAccessibilitySummary?.trimmingCharacters(in: .whitespacesAndNewlines), !hover.isEmpty {
            parts.append("• Pointer / hover target (macOS Accessibility, may be vague in browsers): \(hover)")
        }

        parts.append("═══ End situation ═══")
        return parts.joined(separator: "\n")
    }
}
