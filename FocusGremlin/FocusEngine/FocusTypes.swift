import Foundation

enum FocusCategory: String, Codable, Sendable {
    case productive
    case neutral
    case distracting
}

struct FocusSnapshot: Sendable, Equatable {
    var bundleID: String
    var windowTitle: String?
    var pageTitle: String? = nil
    var pageURL: String? = nil
    var pageSemanticSnippet: String? = nil
    var timestamp: Date

    var effectivePageTitle: String? {
        let page = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !page.isEmpty { return page }
        let window = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return window.isEmpty ? nil : window
    }

    var pageHost: String? {
        guard let raw = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let url = URL(string: raw), let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Текст, по которому rule-based классификатор может искать и work keywords, и маркеры отвлечения.
    var classificationEvidenceText: String {
        [effectivePageTitle, pageURL, windowTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{1e} ")
    }

    var pageIdentityKey: String? {
        let title = effectivePageTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let rawURL = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty {
            if let url = URL(string: rawURL) {
                let host = url.host?.lowercased() ?? ""
                let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let path = url.path
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .lowercased()
                let query = url.query?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                var body = [trimmedHost, path].filter { !$0.isEmpty }.joined(separator: "/")
                if let query, !query.isEmpty {
                    body += "?" + query
                }
                if let title, !title.isEmpty {
                    body += "\u{1f}" + title
                }
                if !body.isEmpty {
                    return bundleID + "\u{1e}" + body
                }
            }
            let urlKey = rawURL.lowercased()
            if let title, !title.isEmpty {
                return bundleID + "\u{1e}" + urlKey + "\u{1f}" + title
            }
            return bundleID + "\u{1e}" + urlKey
        }
        guard let title, !title.isEmpty else { return nil }
        return bundleID + "\u{1e}" + title
    }

    private var semanticNavigationSignature: String? {
        let raw = pageSemanticSnippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        let parts = raw
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }

        guard !parts.isEmpty else { return nil }
        var seen = Set<String>()
        var kept: [String] = []
        for token in parts where seen.insert(token).inserted {
            kept.append(token)
            if kept.count >= 3 { break }
        }
        guard !kept.isEmpty else { return nil }
        return kept.joined(separator: "+")
    }

    /// Ключ смены **навигации** без заголовка вкладки: SPA и браузер часто обновляют `pageTitle` между тиками,
    /// из‑за чего полный `pageIdentityKey` «дрожит» и `doomscrollPageDidChange` не срабатывает.
    var pageNavigationStabilityKey: String? {
        let rawURL = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawURL.isEmpty else { return pageIdentityKey }
        if let url = URL(string: rawURL) {
            let host = url.host?.lowercased() ?? ""
            let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let path = url.path
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            let query = url.query?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            var body = [trimmedHost, path].filter { !$0.isEmpty }.joined(separator: "/")
            if let query, !query.isEmpty {
                body += "?" + query
            }
            if let semanticNavigationSignature, !semanticNavigationSignature.isEmpty {
                body += "\u{1f}" + semanticNavigationSignature
            }
            if !body.isEmpty {
                return bundleID + "\u{1e}" + body
            }
        }
        var fallback = rawURL.lowercased()
        if let semanticNavigationSignature, !semanticNavigationSignature.isEmpty {
            fallback += "\u{1f}" + semanticNavigationSignature
        }
        return bundleID + "\u{1e}" + fallback
    }
}

/// Конфигурация правил для юнит-тестов и продакшена.
struct FocusRuleConfiguration: Sendable, Equatable {
    var productiveBundleIDs: Set<String>
    var distractingBundleIDs: Set<String>
    var browserBundleIDs: Set<String>
    var workTitleKeywords: [String]
    var distractionTitleMarkers: [String]

    static let defaultBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "app.zen-browser.zen",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]

    static let defaultDistractionMarkers: [String] = [
        "youtube", "youtu.be", "reddit", "instagram", "tiktok", "twitter",
        "x.com", "facebook", "twitch", "threads.net", "vk.com", "ok.ru"
    ]
}
