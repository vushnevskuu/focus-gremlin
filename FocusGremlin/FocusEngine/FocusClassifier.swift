import Foundation

/// Rule-based классификация без CV. Браузер оценивается по заголовку окна/вкладки.
struct FocusClassifier: Sendable {
    var configuration: FocusRuleConfiguration

    func classify(_ snapshot: FocusSnapshot) -> FocusCategory {
        let bundle = snapshot.bundleID
        let evidence = snapshot.classificationEvidenceText.lowercased()

        if configuration.productiveBundleIDs.contains(bundle) {
            return .productive
        }
        if configuration.distractingBundleIDs.contains(bundle) {
            return .distracting
        }

        if configuration.browserBundleIDs.contains(bundle) {
            if matchesAnyKeyword(evidence, configuration.workTitleKeywords) {
                return .productive
            }
            if matchesAnyKeyword(evidence, configuration.distractionTitleMarkers) {
                return .distracting
            }
            return .neutral
        }

        // Нативные клиенты (Instagram, TikTok и т.д.): по заголовку окна из Accessibility — bundle часто не в списке «браузеров».
        if matchesAnyKeyword(evidence, configuration.distractionTitleMarkers) {
            return .distracting
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
