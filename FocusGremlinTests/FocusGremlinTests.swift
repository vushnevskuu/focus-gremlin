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

    func testBrowserDistractionMarkerCanComeFromPageURL() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Watch later",
            pageTitle: "Watch later",
            pageURL: "https://www.youtube.com/watch?v=abc123",
            timestamp: Date()
        )
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

    func testNativeAppDistractionByWindowTitle() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["instagram"]
        )
        let classifier = FocusClassifier(configuration: config)
        let snap = FocusSnapshot(
            bundleID: "com.burbn.instagram",
            windowTitle: "Instagram",
            timestamp: Date()
        )
        XCTAssertEqual(classifier.classify(snap), .distracting)
    }
}

@MainActor
final class CompanionViewModelPageReactionTests: XCTestCase {
    func testPageReactionRevivesLifecycleAndUsesIdle2() {
        let viewModel = CompanionViewModel()
        viewModel.forceLifecycleTerminalForTesting()
        viewModel.syncFocusOverlayContext(category: .neutral, agentEnabled: true)

        XCTAssertEqual(viewModel.companionLifecycleState, .terminal)
        XCTAssertFalse(viewModel.shouldShowCompanionSprite)

        viewModel.reactToNewDoomscrollPage(at: Date())

        XCTAssertEqual(viewModel.companionLifecycleState, .active)
        XCTAssertEqual(viewModel.activeIdleStripFilename, "idle_2.png")
        XCTAssertTrue(viewModel.transientPageReactionActive)
        XCTAssertTrue(viewModel.shouldShowCompanionSprite)
    }

    func testFinalCelebrationRejectsLateDistractingDelivery() async {
        let viewModel = CompanionViewModel()
        viewModel.syncFocusOverlayContext(category: .distracting, agentEnabled: true)
        viewModel.playWorkReturnFinalCelebration()

        let accepted = await viewModel.runLiveDelivery(
            "still scrolling the same sludge",
            isDistractionIntervention: true
        )

        XCTAssertFalse(accepted)
        XCTAssertTrue(viewModel.workReturnFinalActive)
        XCTAssertEqual(viewModel.visibleText, "")
    }

    func testAmbientSpitAddsStainsForOverlay() {
        let viewModel = CompanionViewModel()
        viewModel.forceAmbientSpitForTesting()

        XCTAssertTrue(viewModel.ambientSpitActive)
        XCTAssertFalse(viewModel.spitStains.isEmpty)
        XCTAssertTrue(viewModel.shouldShowSpitOverlay)
    }

    func testAmbientSpitStainsSpawnNearCenter() {
        let viewModel = CompanionViewModel()
        viewModel.forceAmbientSpitForTesting()

        XCTAssertFalse(viewModel.spitStains.isEmpty)
        for stain in viewModel.spitStains {
            XCTAssertTrue((0.45...0.55).contains(stain.normalizedX))
            XCTAssertTrue((0.44...0.56).contains(stain.normalizedY))
        }
    }

    func testFinalCelebrationBeginsSpitDissolve() {
        let viewModel = CompanionViewModel()
        viewModel.forceAmbientSpitForTesting()

        viewModel.playWorkReturnFinalCelebration()

        XCTAssertFalse(viewModel.ambientSpitActive)
        XCTAssertFalse(viewModel.spitStains.isEmpty)
        XCTAssertTrue(viewModel.spitStains.allSatisfy { $0.phase == .dissolving })
    }

    func testPageReactionIdle2LeadDelayIsExposedWhileIdle2IsActive() {
        let viewModel = CompanionViewModel()
        viewModel.reactToNewDoomscrollPage(at: Date())

        XCTAssertEqual(viewModel.activeIdleStripFilename, "idle_2.png")
        XCTAssertGreaterThan(viewModel.idle2LeadInDelayForPageReaction(), 0.18)
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

final class BrowserDistractionPinTests: XCTestCase {
    /// Регрессия: merge(.distracting, .productive) даёт .neutral — движок обязан закреплять rule-based отвлечение по вкладке.
    func testRuleDistractingPinnedAgainstVisionProductive() {
        let merged = SmartCategoryMerge.merge(rule: .distracting, vision: .productive)
        XCTAssertEqual(merged, .neutral)
        var category = merged
        let ruleCategory = FocusCategory.distracting
        if ruleCategory == .distracting {
            category = .distracting
        }
        XCTAssertEqual(category, .distracting)
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

final class GremlinResolvedFrameSequenceTimingTests: XCTestCase {
    func testMinimumStreamingWaitsForCompositeIntro() {
        let url = URL(fileURLWithPath: "/tmp/goblin.png")
        let frames = (0 ..< 48).map {
            GremlinSpriteFrameRef(url: url, stripCellIndex: $0 % 24, stripCellCount: 24)
        }
        let seq = GremlinResolvedFrameSequence(
            frames: frames,
            fps: 14,
            loops: true,
            loopTailStartIndex: 24,
            tailFps: 12
        )
        XCTAssertEqual(seq.minimumElapsedInStreamingBeforeHolding(), 24.0 / 14.0 + 1.0 / 14.0, accuracy: 0.001)
    }

    func testMinimumStreamingWithoutTailCapsLoopWait() {
        let url = URL(fileURLWithPath: "/tmp/talk.png")
        let frames = (0 ..< 24).map {
            GremlinSpriteFrameRef(url: url, stripCellIndex: $0, stripCellCount: 24)
        }
        let seq = GremlinResolvedFrameSequence(frames: frames, fps: 12, loops: true, loopTailStartIndex: nil, tailFps: nil)
        let oneLoop = 24.0 / 12.0
        XCTAssertEqual(seq.minimumElapsedInStreamingBeforeHolding(), oneLoop + 1.0 / 12.0, accuracy: 0.001)
    }
}

final class MessageSelectorTests: XCTestCase {
    func testRecentMemoryNormalization() {
        XCTAssertEqual(RecentMessageMemory.normalize(" Привет "), RecentMessageMemory.normalize("привет"))
    }

    func testNormalizeForDedup_IgnoresPunctuationAndCase() {
        let a = RecentMessageMemory.normalizeForDedup("Same trash again, fool!")
        let b = RecentMessageMemory.normalizeForDedup("same  TRASH   again fool")
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }

    func testLaughLineSkippedForSessionQuoteDedup() {
        XCTAssertTrue(RecentMessageMemory.isLaughOrPureReactionLine("ha ha ha"))
        XCTAssertTrue(RecentMessageMemory.isLaughOrPureReactionLine("pfft"))
        XCTAssertFalse(RecentMessageMemory.isLaughOrPureReactionLine("still doomscrolling genius"))
        var memory = RecentMessageMemory()
        memory.record("ha ha", trackAsSessionQuote: false)
        memory.record("youtube again pathetic", trackAsSessionQuote: true)
        XCTAssertFalse(memory.containsSubstantiveSessionDuplicate("ha ha"))
        XCTAssertTrue(memory.containsSubstantiveSessionDuplicate("YouTube again pathetic"))
    }

    func testNearDuplicateSubstantiveSessionQuotesDetected() {
        var memory = RecentMessageMemory()
        memory.record("hacker news graveyard again", trackAsSessionQuote: true)

        XCTAssertTrue(memory.containsNearDuplicateSubstantiveSession("hacker news sludge again"))
        XCTAssertFalse(memory.containsNearDuplicateSubstantiveSession("subscribe button carnival"))
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

final class FocusEngineServiceLogicTests: XCTestCase {
    func testHeavyScrollInNeutralBrowserEscalatesToDistracting() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["company.thebrowser.Browser"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["instagram"]
        )

        let category = FocusEngineService.effectiveCategory(
            ruleCategory: .neutral,
            visionCategory: nil,
            bundleID: "company.thebrowser.Browser",
            heavyScrolling: true,
            configuration: config,
            classifierWasProductive: false
        )

        XCTAssertEqual(category, .distracting)
    }

    func testHeavyScrollDoesNotOverrideProductiveBrowserContext() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["instagram"]
        )

        let category = FocusEngineService.effectiveCategory(
            ruleCategory: .productive,
            visionCategory: nil,
            bundleID: "com.google.Chrome",
            heavyScrolling: true,
            configuration: config,
            classifierWasProductive: true
        )

        XCTAssertEqual(category, .productive)
    }

    func testNeutralBrowserStillEligibleForPageAgent() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )

        XCTAssertTrue(
            FocusEngineService.pageAgentEligible(
                bundleID: "com.google.Chrome",
                ruleCategory: .neutral,
                effectiveCategory: .neutral,
                configuration: config
            )
        )
    }

    func testProductiveBrowserStillEligibleForPageAgent() {
        let config = FocusRuleConfiguration(
            productiveBundleIDs: [],
            distractingBundleIDs: [],
            browserBundleIDs: ["com.google.Chrome"],
            workTitleKeywords: ["github"],
            distractionTitleMarkers: ["youtube"]
        )

        XCTAssertTrue(
            FocusEngineService.pageAgentEligible(
                bundleID: "com.google.Chrome",
                ruleCategory: .productive,
                effectiveCategory: .productive,
                configuration: config
            )
        )
    }
}

final class FocusSnapshotTests: XCTestCase {
    func testPageIdentityIncludesQueryAndTitleWhenAvailable() {
        let snapshot = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Some title",
            pageTitle: "Watch Swift Again",
            pageURL: "https://www.youtube.com/watch?v=abc123&t=42",
            timestamp: Date()
        )

        XCTAssertEqual(
            snapshot.pageIdentityKey,
            "com.google.Chrome\u{1e}youtube.com/watch?v=abc123&t=42\u{1f}watch swift again"
        )
    }

    func testPageNavigationStabilityKeyIgnoresTitle() {
        let a = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Win A",
            pageTitle: "First title",
            pageURL: "https://www.youtube.com/watch?v=abc123",
            timestamp: Date()
        )
        let b = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Win B",
            pageTitle: "Second title",
            pageURL: "https://www.youtube.com/watch?v=abc123",
            timestamp: Date()
        )
        XCTAssertEqual(a.pageNavigationStabilityKey, b.pageNavigationStabilityKey)
        XCTAssertNotEqual(a.pageIdentityKey, b.pageIdentityKey)
    }

    func testPageNavigationStabilityKeyChangesWhenVisiblePageTextChanges() {
        let a = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Feed",
            pageTitle: "Feed",
            pageURL: "https://example.com/feed",
            pageSemanticSnippet: "watch later | comments | autoplay",
            timestamp: Date()
        )
        let b = FocusSnapshot(
            bundleID: "com.google.Chrome",
            windowTitle: "Feed",
            pageTitle: "Feed",
            pageURL: "https://example.com/feed",
            pageSemanticSnippet: "new channel | sponsor | skip ad",
            timestamp: Date()
        )

        XCTAssertNotEqual(a.pageNavigationStabilityKey, b.pageNavigationStabilityKey)
    }
}

final class GremlinSpeechContextTests: XCTestCase {
    func testLaughLikeLineUsesGiggleStyle() {
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "ha ha ha"), .giggle)
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "pfft"), .giggle)
    }

    func testMixedLaughLineStillUsesGiggleStyle() {
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "ha another reddit sermon"), .giggle)
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "pfft that subscribe button again"), .giggle)
    }

    func testNegationStillUsesNegationStyle() {
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "Don't scroll."), .negation)
        XCTAssertEqual(GremlinSpeechContext.inferSpeechStyle(for: "nope"), .negation)
    }
}

final class GremlinPageSkimPromptTests: XCTestCase {
    func testNewPageSkimPromptUsesPageTitleAndURLHint() {
        let prompt = GremlinPrompts.newDoomscrollPageSkimPrompt(
            bundleID: "com.google.Chrome",
            windowTitle: "Window fallback",
            pageTitle: "Swift releases melting your focus",
            pageURL: "https://www.reddit.com/r/swift/comments/12345/releases",
            pageSemanticSnippet: "Swift 6 release notes | release blockers | benchmarks",
            hasAttachedScreenshot: false
        )

        XCTAssertTrue(prompt.contains("Swift releases melting your focus"), prompt)
        XCTAssertTrue(prompt.contains("reddit.com/r/swift/comments/12345/releases"), prompt)
        XCTAssertTrue(prompt.contains("Swift 6 release notes"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("specific to this page"), prompt)
    }
}

@MainActor
final class GremlinOrchestratorPageChangeTests: XCTestCase {
    actor QueuedLLMProvider: LLMProvider {
        private var responses: [String]

        init(responses: [String]) {
            self.responses = responses
        }

        func complete(
            systemPrompt: String,
            userPrompt: String,
            jpegImages: [Data],
            chatModel: String?
        ) async throws -> String {
            _ = systemPrompt
            _ = userPrompt
            _ = jpegImages
            _ = chatModel
            guard !responses.isEmpty else { return "fallback page sludge" }
            return responses.removeFirst()
        }
    }

    func testPageChangeBypassesLLMMinInterval() async {
        let orchestrator = GremlinOrchestrator(policy: InterruptionPolicy(cooldown: 0, maxPerHour: 10))
        orchestrator.resetMemoryForTesting()

        let settings = SettingsStore.shared
        let prevUseLLM = settings.useLLMForLines
        let prevInterval = settings.llmMinIntervalSeconds
        let prevVisionConsent = settings.smartVisionConsent
        defer {
            settings.useLLMForLines = prevUseLLM
            settings.llmMinIntervalSeconds = prevInterval
            settings.smartVisionConsent = prevVisionConsent
        }

        settings.useLLMForLines = true
        settings.llmMinIntervalSeconds = 900
        settings.smartVisionConsent = false

        let llm = QueuedLLMProvider(
            responses: [
                "feed sludge again",
                "another feed sludge"
            ]
        )

        let firstContext = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: "Feed",
            pageTitle: "Feed",
            pageURL: "https://example.com/feed",
            pageSemanticSnippet: nil,
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )
        let pageChangeContext = GremlinInterventionContext(
            trigger: .pageChange,
            bundleID: "com.google.Chrome",
            windowTitle: "Another Feed",
            pageTitle: "Another Feed",
            pageURL: "https://example.com/feed/next",
            pageSemanticSnippet: nil,
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )

        let first = await orchestrator.maybeProduceLine(
            context: firstContext,
            settings: settings,
            llm: llm
        )
        let second = await orchestrator.maybeProduceLine(
            context: pageChangeContext,
            settings: settings,
            llm: llm
        )

        XCTAssertEqual(first, "feed sludge again")
        XCTAssertFalse(second?.isEmpty ?? true)
        XCTAssertNotEqual(second, first)
    }

    func testTextOnlyPathRejectsAnchorlessGenericLineAndRetriesForPageAnchor() async {
        let orchestrator = GremlinOrchestrator(policy: InterruptionPolicy(cooldown: 0, maxPerHour: 10))
        orchestrator.resetMemoryForTesting()

        let settings = SettingsStore.shared
        let prevUseLLM = settings.useLLMForLines
        let prevInterval = settings.llmMinIntervalSeconds
        let prevVisionConsent = settings.smartVisionConsent
        defer {
            settings.useLLMForLines = prevUseLLM
            settings.llmMinIntervalSeconds = prevInterval
            settings.smartVisionConsent = prevVisionConsent
        }

        settings.useLLMForLines = true
        settings.llmMinIntervalSeconds = 0
        settings.smartVisionConsent = false

        let llm = QueuedLLMProvider(
            responses: [
                "same sludge again",
                "hacker news graveyard again"
            ]
        )

        let context = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: "Hacker News",
            pageTitle: nil,
            pageURL: "https://news.ycombinator.com/news",
            pageSemanticSnippet: "Show HN | Ask HN | Who is hiring",
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )

        let line = await orchestrator.maybeProduceLine(
            context: context,
            settings: settings,
            llm: llm
        )

        XCTAssertEqual(line, "hacker news graveyard again")
    }

    func testDecorateLineForDeliveryCanInjectGigglePrefixOnPageChange() {
        let context = GremlinInterventionContext(
            trigger: .pageChange,
            bundleID: "com.google.Chrome",
            windowTitle: "Another Feed",
            pageTitle: "Another Feed",
            pageURL: "https://example.com/feed/next",
            pageSemanticSnippet: "another feed | autoplay | reactions",
            focusCategory: .neutral,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )

        let decorated = GremlinOrchestrator.decorateLineForDelivery(
            "another feed sludge",
            context: context
        )

        XCTAssertTrue(
            decorated == "another feed sludge"
                || decorated.hasPrefix("ha ")
                || decorated.hasPrefix("pfft ")
                || decorated.hasPrefix("heh "),
            decorated
        )
    }
}

final class ScreenCaptureServiceTests: XCTestCase {
    func testPixelCropRectMapsWindowAreaIntoDisplayPixels() {
        let rect = ScreenCaptureService.pixelCropRect(
            cropRectInDisplayPoints: CGRect(x: 100, y: 100, width: 400, height: 200),
            displayBoundsInPoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        XCTAssertEqual(rect?.origin.x ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(rect?.origin.y ?? -1, 1200, accuracy: 0.01)
        XCTAssertEqual(rect?.width ?? -1, 800, accuracy: 0.01)
        XCTAssertEqual(rect?.height ?? -1, 400, accuracy: 0.01)
    }

    func testPixelCropRectClampsOffscreenArea() {
        let rect = ScreenCaptureService.pixelCropRect(
            cropRectInDisplayPoints: CGRect(x: -40, y: 760, width: 220, height: 220),
            displayBoundsInPoints: CGRect(x: 0, y: 0, width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        XCTAssertEqual(rect?.origin.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(rect?.origin.y ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(rect?.width ?? -1, 360, accuracy: 0.01)
        XCTAssertEqual(rect?.height ?? -1, 280, accuracy: 0.01)
    }
}

final class GremlinSpriteActionMappingTests: XCTestCase {
    private func assertPingPongIntro(
        _ introFrames: ArraySlice<GremlinSpriteFrameRef>,
        sheetFilename: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let intro = Array(introFrames)
        XCTAssertFalse(intro.isEmpty, file: file, line: line)
        XCTAssertTrue(
            intro.allSatisfy { $0.url.lastPathComponent == sheetFilename },
            file: file,
            line: line
        )

        let forward = Array(0 ..< 24)
        let reverse = Array((0 ..< 23).reversed())
        XCTAssertEqual(
            intro.map(\.stripCellIndex),
            forward + reverse,
            file: file,
            line: line
        )
    }

    @MainActor
    func testAppearingUsesCompactIdleLeadIn() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let sequence = resolver.resolveFrameSequence(
            phase: .appearing,
            distractionInterventionActive: false
        )

        XCTAssertFalse(sequence.loops)
        XCTAssertEqual(sequence.frames.first?.url.lastPathComponent, "idle_1.png")
        XCTAssertEqual(sequence.frames.first?.stripCellIndex, 0)
        XCTAssertEqual(sequence.frames.last?.stripCellIndex, 5)
        XCTAssertEqual(sequence.frameCount, 6)
    }

    @MainActor
    func testDismissingUsesReversedCompactIdleLeadOut() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let sequence = resolver.resolveFrameSequence(
            phase: .dismissing,
            distractionInterventionActive: false
        )

        XCTAssertFalse(sequence.loops)
        XCTAssertEqual(sequence.frames.first?.url.lastPathComponent, "idle_1.png")
        XCTAssertEqual(sequence.frames.first?.stripCellIndex, 5)
        XCTAssertEqual(sequence.frames.last?.stripCellIndex, 0)
        XCTAssertEqual(sequence.frameCount, 6)
    }

    func testInterventionNeverPrefersFinalSpriteInTypingDots() {
        XCTAssertEqual(
            GremlinCharacterAnimationResolver.preferredStates(for: .typingDots, distractionInterventionActive: true),
            [.idle]
        )
        XCTAssertFalse(
            GremlinCharacterAnimationResolver.preferredStates(for: .typingDots, distractionInterventionActive: true).contains(.final)
        )
    }

    func testInterventionStreamingUsesTalkingNotFinal() {
        XCTAssertEqual(
            GremlinCharacterAnimationResolver.preferredStates(for: .streaming, distractionInterventionActive: true),
            [.talking, .idle]
        )
    }

    @MainActor
    func testGiggleStreamUsesSmileSheet() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let seq = resolver.resolveFrameSequence(
            phase: .streaming,
            distractionInterventionActive: false,
            workReturnFinalActive: false,
            talkingStripFilename: "talking_1.png",
            idleStripFilename: "idle_1.png",
            useShortPhraseStream: true,
            deliverySpeechStyle: .giggle
        )
        let introEnd = seq.loopTailStartIndex
        XCTAssertNotNil(introEnd)
        XCTAssertGreaterThan(introEnd!, 0)
        assertPingPongIntro(seq.frames.prefix(introEnd!), sheetFilename: "smile.png")
        XCTAssertTrue(seq.frames.dropFirst(introEnd!).allSatisfy { $0.url.lastPathComponent == "idle_1.png" })
    }

    @MainActor
    func testShortPhraseStreamUsesShortPhraseSheet() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let seq = resolver.resolveFrameSequence(
            phase: .streaming,
            distractionInterventionActive: false,
            workReturnFinalActive: false,
            talkingStripFilename: "talking_1.png",
            idleStripFilename: "idle_1.png",
            useShortPhraseStream: true
        )
        let introEnd = seq.loopTailStartIndex
        XCTAssertNotNil(introEnd)
        XCTAssertGreaterThan(introEnd!, 0)
        XCTAssertTrue(seq.frames.prefix(introEnd!).allSatisfy { $0.url.lastPathComponent == "short_phrase.png" })
        XCTAssertTrue(seq.frames.dropFirst(introEnd!).allSatisfy { $0.url.lastPathComponent == "idle_1.png" })
    }

    @MainActor
    func testAmbientSpitUsesSpitSheetThenIdle() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let seq = resolver.resolveFrameSequence(
            phase: .idle,
            distractionInterventionActive: false,
            workReturnFinalActive: false,
            ambientSpitActive: true,
            idleStripFilename: "idle_1.png"
        )

        let introEnd = seq.loopTailStartIndex
        XCTAssertNotNil(introEnd)
        XCTAssertGreaterThan(introEnd!, 0)
        XCTAssertTrue(seq.frames.prefix(introEnd!).allSatisfy { $0.url.lastPathComponent == "spit.png" })
        XCTAssertTrue(seq.frames.dropFirst(introEnd!).allSatisfy { $0.url.lastPathComponent == "idle_1.png" })
    }

    @MainActor
    func testTalkingStripFilenameLimitsToOneSheet() throws {
        let resolver = try GremlinCharacterAnimationResolver()
        let seq = resolver.resolveFrameSequence(
            phase: .streaming,
            distractionInterventionActive: false,
            workReturnFinalActive: false,
            talkingStripFilename: "talking_2.png"
        )
        XCTAssertFalse(seq.frames.isEmpty)
        XCTAssertNotNil(seq.loopTailStartIndex)
        let introEnd = seq.loopTailStartIndex!
        XCTAssertGreaterThan(introEnd, 0)
        assertPingPongIntro(seq.frames.prefix(introEnd), sheetFilename: "talking_2.png")
        XCTAssertTrue(seq.frames.dropFirst(introEnd).allSatisfy { $0.url.lastPathComponent == "idle_1.png" })
    }

    func testRegularHoldingKeepsTalkingWhileLineVisible() {
        XCTAssertEqual(
            GremlinCharacterAnimationResolver.preferredStates(for: .holding, distractionInterventionActive: false),
            [.idle]
        )
    }

    func testInterventionHoldingKeepsTalkingWhileLineVisible() {
        XCTAssertEqual(
            GremlinCharacterAnimationResolver.preferredStates(for: .holding, distractionInterventionActive: true),
            [.idle]
        )
    }

    func testTextFallingUsesIdleOnly() {
        XCTAssertEqual(
            GremlinCharacterAnimationResolver.preferredStates(for: .textFalling, distractionInterventionActive: true),
            [.idle]
        )
    }
}

final class GremlinSpriteSheetGeometryTests: XCTestCase {
    func testUniformCellAndViewportWideFrame() {
        let cell = GremlinSpriteSheetGeometry.uniformCellSize(
            source: CGSize(width: 28224, height: 784),
            columns: 24,
            rows: 1
        )
        XCTAssertEqual(cell.width, 1176, accuracy: 0.01)
        XCTAssertEqual(cell.height, 784, accuracy: 0.01)
        let vp = GremlinSpriteSheetGeometry.displayViewportSize(logicalCell: cell, displayHeight: 120)
        XCTAssertEqual(vp.height, 120, accuracy: 0.01)
        XCTAssertEqual(vp.width, 180, accuracy: 0.01)
    }

    func testHorizontalStripIntegerRectsStableWidth() {
        let r0 = GremlinSpriteSheetGeometry.horizontalStripCellPixelRect(
            cellIndex: 0,
            columns: 20,
            sourcePixelWidth: 1280,
            sourcePixelHeight: 128
        )
        XCTAssertEqual(r0.x, 0)
        XCTAssertEqual(r0.width, 64)
        XCTAssertEqual(r0.height, 128)
        let r19 = GremlinSpriteSheetGeometry.horizontalStripCellPixelRect(
            cellIndex: 19,
            columns: 20,
            sourcePixelWidth: 1280,
            sourcePixelHeight: 128
        )
        XCTAssertEqual(r19.x, 1216)
        XCTAssertEqual(r19.width, 64)
    }
}

final class GremlinSpriteThumbnailLoaderTests: XCTestCase {
    func testLogicalFrameSizeForIdleSheetMatchesSourceCell() {
        let url = characterSheetURL("idle_1.png")
        let size = GremlinSpriteThumbnailLoader.logicalFramePixelSize(url: url, stripCellCount: 24)
        XCTAssertNotNil(size)
        XCTAssertEqual(size?.width ?? 0, 1176, accuracy: 0.01)
        XCTAssertEqual(size?.height ?? 0, 784, accuracy: 0.01)
    }

    func testLogicalFrameSizeForFinalSheetStaysStableAcrossNonIntegralSourceWidth() {
        let url = characterSheetURL("final_1.png")
        let size = GremlinSpriteThumbnailLoader.logicalFramePixelSize(url: url, stripCellCount: 23)
        XCTAssertNotNil(size)
        XCTAssertEqual(size?.width ?? 0, 27048.0 / 23.0, accuracy: 0.01)
        XCTAssertEqual(size?.height ?? 0, 784, accuracy: 0.01)
    }

    func testCachedStripCanServeNeighborFrameWithoutRedecodingWholeSheet() {
        let url = characterSheetURL("final_1.png")
        let maxPx = GremlinSpriteThumbnailLoader.maxPixelDimension(forDisplayHeightPoints: 120)
        GremlinSpriteThumbnailLoader.clearMemoryCache()

        let first = GremlinSpriteThumbnailLoader.cgImage(
            url: url,
            maxPixelDimension: maxPx,
            stripCellCount: 23,
            stripCellIndex: 0
        )
        XCTAssertNotNil(first)

        let second = GremlinSpriteThumbnailLoader.imageIfCached(
            url: url,
            maxPixelDimension: maxPx,
            stripCellCount: 23,
            stripCellIndex: 1
        )
        XCTAssertNotNil(second)
    }

    private func characterSheetURL(_ filename: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FocusGremlin/Resources/CharacterSheets")
            .appendingPathComponent(filename)
    }
}

// MARK: - Контекст браузера → промпт (без живого VLM)

/// Живой тест «видит ли модель страницу в Safari/Chrome» требует на твоей машине: Ollama + vision-модель, Screen Recording,
/// запущенный Focus Gremlin и открытый браузер — этого нет в headless CI. Здесь проверяем **цепочку данных** до LLM.
final class GremlinBrowserContextPipelineTests: XCTestCase {
    func testBrowserLocationHint_StripsWWWAndJoinsPath() {
        XCTAssertEqual(
            GremlinContextBuilder.browserLocationHint(pageURL: "https://www.youtube.com/watch?v=abc"),
            "youtube.com/watch"
        )
    }

    func testBrowserLocationHint_HostOnlyForRootPath() {
        XCTAssertEqual(
            GremlinContextBuilder.browserLocationHint(pageURL: "https://www.reddit.com/"),
            "reddit.com"
        )
    }

    func testSituationBlock_WhenTitleMissing_AddsUrlGroundingAndFullURL() {
        let ctx = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: nil,
            pageTitle: nil,
            pageURL: "https://www.youtube.com/watch?v=xyz",
            pageSemanticSnippet: "Recommended | Up next | watch later",
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )
        let block = GremlinContextBuilder.situationBlock(context: ctx)
        XCTAssertTrue(block.contains("Grounding from URL"), block)
        XCTAssertTrue(block.contains("youtube.com/watch"), block)
        XCTAssertTrue(block.contains("Browser page URL:"), block)
        XCTAssertTrue(block.contains("Recommended"), block)
        XCTAssertFalse(block.localizedCaseInsensitiveContains("window/tab title empty or unavailable"))
    }

    func testUserPrompt_WithPointerVisionEmbedsSituationAndPageSignals() {
        let ctx = GremlinInterventionContext(
            trigger: .scrollSession,
            bundleID: "com.google.Chrome",
            windowTitle: "Legacy",
            pageTitle: "   ",
            pageURL: "https://news.ycombinator.com/news",
            pageSemanticSnippet: "Show HN | Ask HN | Who is hiring",
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: "orange site threads",
            pointerAccessibilitySummary: "link «Comments»"
        )
        let prompt = GremlinPrompts.userPrompt(
            context: ctx,
            avoidRepeatingNormalizedLines: [],
            duplicateRetry: false,
            visionLayout: .pointerNeighborhoodOnly
        )
        XCTAssertTrue(prompt.contains("═══ Situation"), prompt)
        XCTAssertTrue(prompt.contains("ycombinator.com") || prompt.contains("news.ycombinator"), prompt)
        XCTAssertTrue(prompt.contains("Comments") || prompt.contains("Pointer"), prompt)
        XCTAssertTrue(prompt.contains("orange site threads"), prompt)
        XCTAssertTrue(prompt.contains("Show HN"), prompt)
    }

    @MainActor
    func testOrchestratorPassesVisionPayloadToLLMWhenJPEGProvided() async {
        final class RecordingLLM: LLMProvider, @unchecked Sendable {
            var lastJPEGCount = 0
            var lastUserHasSituation = false
            func complete(
                systemPrompt: String,
                userPrompt: String,
                jpegImages: [Data],
                chatModel: String?
            ) async throws -> String {
                lastJPEGCount = jpegImages.count
                lastUserHasSituation = userPrompt.contains("═══ Situation")
                return "Subscribe red button trash"
            }
        }

        let policy = InterruptionPolicy(cooldown: 0, maxPerHour: 999, recentFireTimes: [])
        let orch = GremlinOrchestrator(policy: policy)
        orch.resetMemoryForTesting()

        let recorder = RecordingLLM()
        let settings = SettingsStore.shared
        let prevConsent = settings.smartVisionConsent
        let prevModel = settings.smartVisionModel
        let prevUseLLM = settings.useLLMForLines
        let prevInterval = settings.llmMinIntervalSeconds
        settings.smartVisionConsent = true
        settings.smartVisionModel = "any-vision-model"
        settings.useLLMForLines = true
        settings.llmMinIntervalSeconds = 0
        defer {
            settings.smartVisionConsent = prevConsent
            settings.smartVisionModel = prevModel
            settings.useLLMForLines = prevUseLLM
            settings.llmMinIntervalSeconds = prevInterval
        }

        let ctx = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: nil,
            pageTitle: nil,
            pageURL: "https://example.com/video",
            pageSemanticSnippet: nil,
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: "AXLink"
        )

        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xDB, 0])
        let line = await orch.maybeProduceLine(
            context: ctx,
            settings: settings,
            llm: recorder,
            screenshotJPEG: nil,
            cursorNeighborhoodJPEG: fakeJPEG
        )
        XCTAssertEqual(recorder.lastJPEGCount, 1)
        XCTAssertTrue(recorder.lastUserHasSituation)
        XCTAssertFalse(line?.isEmpty ?? true)
    }

    @MainActor
    func testOrchestratorPassesWindowAndPointerJPEGsWhenBothProvided() async {
        final class RecordingLLM: LLMProvider, @unchecked Sendable {
            var lastJPEGCount = 0
            var lastUserMentionsFullWindowFrame = false
            var lastUserMentionsPointerNeighborhood = false
            func complete(
                systemPrompt: String,
                userPrompt: String,
                jpegImages: [Data],
                chatModel: String?
            ) async throws -> String {
                lastJPEGCount = jpegImages.count
                lastUserMentionsFullWindowFrame =
                    userPrompt.localizedCaseInsensitiveContains("frontmost")
                    || userPrompt.localizedCaseInsensitiveContains("full window")
                lastUserMentionsPointerNeighborhood =
                    userPrompt.localizedCaseInsensitiveContains("pointer neighborhood")
                    || userPrompt.localizedCaseInsensitiveContains("hovered/control spot")
                return "Orange site thread rot"
            }
        }

        let policy = InterruptionPolicy(cooldown: 0, maxPerHour: 999, recentFireTimes: [])
        let orch = GremlinOrchestrator(policy: policy)
        orch.resetMemoryForTesting()

        let recorder = RecordingLLM()
        let settings = SettingsStore.shared
        let prevConsent = settings.smartVisionConsent
        let prevModel = settings.smartVisionModel
        let prevUseLLM = settings.useLLMForLines
        let prevInterval = settings.llmMinIntervalSeconds
        settings.smartVisionConsent = true
        settings.smartVisionModel = "any-vision-model"
        settings.useLLMForLines = true
        settings.llmMinIntervalSeconds = 0
        defer {
            settings.smartVisionConsent = prevConsent
            settings.smartVisionModel = prevModel
            settings.useLLMForLines = prevUseLLM
            settings.llmMinIntervalSeconds = prevInterval
        }

        let ctx = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: nil,
            pageTitle: nil,
            pageURL: "https://example.com/feed",
            pageSemanticSnippet: nil,
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )

        let windowJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 1])
        let cursorJPEG = Data([0xFF, 0xD8, 0xFF, 0xDB, 2])
        let line = await orch.maybeProduceLine(
            context: ctx,
            settings: settings,
            llm: recorder,
            screenshotJPEG: windowJPEG,
            cursorNeighborhoodJPEG: cursorJPEG
        )
        XCTAssertEqual(recorder.lastJPEGCount, 2)
        XCTAssertTrue(recorder.lastUserMentionsFullWindowFrame)
        XCTAssertTrue(recorder.lastUserMentionsPointerNeighborhood)
        XCTAssertFalse(line?.isEmpty ?? true)
    }

    func testUserPrompt_DualVisionExplainsWindowThenPointer() {
        let ctx = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: "Tab",
            pageTitle: nil,
            pageURL: "https://reddit.com/r/all",
            pageSemanticSnippet: "hot posts | upvote | doomscroll",
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: "AXButton «Upvote»"
        )
        let prompt = GremlinPrompts.userPrompt(
            context: ctx,
            avoidRepeatingNormalizedLines: [],
            duplicateRetry: false,
            visionLayout: .focusedWindowAndPointerNeighborhood
        )
        XCTAssertTrue(prompt.contains("two JPEGs"), prompt)
        XCTAssertTrue(prompt.contains("Focused window") || prompt.contains("focused window"), prompt)
        XCTAssertTrue(prompt.contains("Pointer neighborhood") || prompt.contains("pointer neighborhood"), prompt)
        XCTAssertTrue(prompt.contains("primary"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("exact hovered/control spot"), prompt)
    }

    func testUserPrompt_FullWindowMentionsForegroundFrame() {
        let ctx = GremlinInterventionContext(
            trigger: .sustained,
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube",
            pageTitle: nil,
            pageURL: "https://youtube.com/watch",
            pageSemanticSnippet: nil,
            focusCategory: .distracting,
            visionCategory: nil,
            neuralPageChangeDigest: nil,
            pointerAccessibilitySummary: nil
        )
        let prompt = GremlinPrompts.userPrompt(
            context: ctx,
            avoidRepeatingNormalizedLines: [],
            duplicateRetry: false,
            visionLayout: .focusedWindowOnly
        )
        XCTAssertTrue(
            prompt.localizedCaseInsensitiveContains("frontmost")
                || prompt.localizedCaseInsensitiveContains("full window"),
            prompt
        )
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("distance from the mouse"), prompt)
    }
}
