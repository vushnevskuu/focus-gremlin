import XCTest
@testable import FocusGremlin

final class FocusClassifierTests: XCTestCase {
    func testProductiveBundleOverridesBrowserHeuristics() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: ["com.apple.dt.Xcode"],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.apple.Safari"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(bundleID: "com.apple.dt.Xcode", windowTitle: "youtube.com", timestamp: Date())
        XCTAssertEqual(classifier.classify(snap), .productive)
    }

    func testBrowserWorkKeyword() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.apple.Safari"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: FocusRuleConfiguration.defaultDistractionMarkers
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(bundleID: "com.apple.Safari", windowTitle: "issues · myrepo — github", timestamp: Date())
        XCTAssertEqual(classifier.classify(snap), .productive)
    }

    func testBrowserDistractionMarker() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(bundleID: "com.google.Chrome", windowTitle: "cute cats - YouTube", timestamp: Date())
        XCTAssertEqual(classifier.classify(snap), .distracting)
    }

    func testDenylistBundle() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: ["ru.keepcoder.Telegram"],
            browserBundleIDs: ["com.apple.Safari"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(bundleID: "ru.keepcoder.Telegram", windowTitle: "чаты", timestamp: Date())
        XCTAssertEqual(classifier.classify(snap), .distracting)
    }
}

final class InterruptionPolicyTests: XCTestCase {
    func testCooldownBlocksRapidFire() {
        var policy = InterruptionPolicy(cooldown: 10, maxPerHour: 10)
        let t0 = Date()
        XCTAssertTrue(policy.canFire(now: t0))
        policy.recordFire(at: t0)
        XCTAssertFalse(policy.canFire(now: t0.addingTimeInterval(2)))
        XCTAssertTrue(policy.canFire(now: t0.addingTimeInterval(11)))
    }

    func testHourlyCap() {
        var policy = InterruptionPolicy(cooldown: 0, maxPerHour: 3)
        let t0 = Date()
        policy.recordFire(at: t0)
        policy.recordFire(at: t0.addingTimeInterval(1))
        policy.recordFire(at: t0.addingTimeInterval(2))
        XCTAssertFalse(policy.canFire(now: t0.addingTimeInterval(3)))
    }

    func testPruneOldEvents() {
        var policy = InterruptionPolicy(cooldown: 0, maxPerHour: 2)
        let t0 = Date().addingTimeInterval(-4000)
        policy.recordFire(at: t0)
        policy.recordFire(at: t0.addingTimeInterval(1))
        XCTAssertTrue(policy.canFire(now: Date()))
    }
}

final class SmartCategoryMergeTests: XCTestCase {
    func testVisionEscalatesNeutralToDistracting() {
        let m = SmartCategoryMerge.merge(rule: .neutral, vision: .distracting)
        XCTAssertEqual(m, .distracting)
    }

    func testVisionSoftensFalseDistracting() {
        let m = SmartCategoryMerge.merge(rule: .distracting, vision: .productive)
        XCTAssertEqual(m, .neutral)
    }

    func testNilVisionUsesRule() {
        XCTAssertEqual(SmartCategoryMerge.merge(rule: .productive, vision: nil), .productive)
    }
}

final class MessageSelectorTests: XCTestCase {
    func testRecentMemoryNormalization() {
        XCTAssertEqual(RecentMessageMemory.normalize(" Привет "), RecentMessageMemory.normalize("привет"))
    }

    func testSelectorReturnsNonEmptyLine() {
        let selector = MessageSelector()
        let line = selector.selectTemplate(
            language: .ru,
            tone: .gentle,
            trigger: .chaoticSwitching,
            memory: RecentMessageMemory()
        )
        XCTAssertFalse(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
