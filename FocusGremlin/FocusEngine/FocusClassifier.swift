import Foundation

/// Rule-based классификация без CV. Браузер оценивается по заголовку окна/вкладки.
struct FocusClassifier: Sendable {
    var configuration: FocusRuleConfiguration

    func classify(_ snapshot: FocusSnapshot) -> FocusCategory {
        let bundle = snapshot.bundleID
        let title = snapshot.windowTitle?.lowercased() ?? ""

        if configuration.productiveBundleIDs.contains(bundle) {
            return .productive
        }
        if configuration.distractingBundleIDs.contains(bundle) {
            return .distracting
        }

        if configuration.browserBundleIDs.contains(bundle) {
            if matchesAnyKeyword(title, configuration.workTitleKeywords) {
                return .productive
            }
            if matchesAnyKeyword(title, configuration.distractionTitleMarkers) {
                return .distracting
            }
            return .neutral
        }

        return .neutral
    }

    private func matchesAnyKeyword(_ haystack: String, _ keywords: [String]) -> Bool {
        for k in keywords {
            let needle = k.lowercased()
            if !needle.isEmpty, haystack.contains(needle) {
                return true
            }
        }
        return false
    }
}
