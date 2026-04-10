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
        if let rawURL = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty {
            if let url = URL(string: rawURL) {
                let host = url.host?.lowercased() ?? ""
                let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let path = url.path
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .lowercased()
                let body = [trimmedHost, path].filter { !$0.isEmpty }.joined(separator: "/")
                if !body.isEmpty {
                    return bundleID + "\u{1e}" + body
                }
            }
            return bundleID + "\u{1e}" + rawURL.lowercased()
        }
        guard let title = effectivePageTitle?.lowercased(), !title.isEmpty else { return nil }
        return bundleID + "\u{1e}" + title
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
