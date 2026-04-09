import Foundation

enum FocusCategory: String, Codable, Sendable {
    case productive
    case neutral
    case distracting
}

struct FocusSnapshot: Sendable, Equatable {
    var bundleID: String
    var windowTitle: String?
    var timestamp: Date
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
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]

    static let defaultDistractionMarkers: [String] = [
        "youtube", "youtu.be", "reddit", "instagram", "tiktok", "twitter",
        "x.com", "facebook", "twitch", "threads.net", "vk.com", "ok.ru"
    ]
}
