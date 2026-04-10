import AppKit
import Combine
import Foundation

enum DistractionTrigger: String, Sendable {
    case sustained
    case scrollSession
    case chaoticSwitching
    case boomerang
    case smartVision
}

struct FocusEngineOutput: Sendable {
    let category: FocusCategory
    let snapshot: FocusSnapshot
    let trigger: DistractionTrigger?
}

@MainActor
final class FocusEngineService: ObservableObject {
    private var timer: Timer?
    private lazy var scrollMonitor: ScrollWheelMonitor = ScrollWheelMonitor { [weak self] in
        Task { @MainActor in
            self?.scrollTracker.recordScroll()
        }
    }
    private var scrollTracker = ScrollSessionTracker()
    private var lastFrontmostBundleID: String?
    private var hysteresis = AppSwitchHysteresis()
    private var distractionEnteredAt: Date?
    private var lastWarningAt: Date?
    private var leftDistractionAfterWarning = false

    @Published private(set) var latestOutput: FocusEngineOutput?

    private weak var settings: SettingsStore?
    private weak var smartMode: SmartModeController?

    init(settings: SettingsStore, smartMode: SmartModeController) {
        self.settings = settings
        self.smartMode = smartMode
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)

        if FeatureFlags.globalScrollMonitoringPreferred {
            scrollMonitor.start()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scrollMonitor.stop()
    }

    private func tick() {
        guard let settings else { return }
        guard settings.agentEnabled else {
            latestOutput = nil
            return
        }

        smartMode?.scheduleCaptureIfNeeded()

        let app = NSWorkspace.shared.frontmostApplication
        let bundle = app?.bundleIdentifier ?? ""
        let title = WindowContextProvider.frontmostWindowTitle()

        if let lastFrontmostBundleID, lastFrontmostBundleID != bundle {
            scrollTracker.reset()
        }
        lastFrontmostBundleID = bundle

        let snapshot = FocusSnapshot(bundleID: bundle, windowTitle: title, timestamp: Date())
        let config = FocusRuleConfiguration(
            productiveBundleIDs: Set(settings.productiveBundleIDs),
            distractingBundleIDs: Set(settings.distractingBundleIDs),
            browserBundleIDs: FocusRuleConfiguration.defaultBrowsers,
            workTitleKeywords: settings.browserWorkKeywords,
            distractionTitleMarkers: FocusRuleConfiguration.defaultDistractionMarkers
        )
        let heavyScroll = scrollTracker.isHeavyScrolling(now: snapshot.timestamp)
        let classifier = FocusClassifier(configuration: config)
        let ruleCategory = classifier.classify(snapshot)
        let visionCategory = smartMode?.freshVision(at: snapshot.timestamp)
        let category = Self.effectiveCategory(
            ruleCategory: ruleCategory,
            visionCategory: visionCategory,
            bundleID: bundle,
            heavyScrolling: heavyScroll,
            configuration: config
        )

        hysteresis.register(category: category)

        var trigger: DistractionTrigger?
        let keepScrollSessionAlive = Self.shouldKeepScrollSession(
            bundleID: bundle,
            ruleCategory: ruleCategory,
            configuration: config
        )

        if category != .distracting {
            if let lw = lastWarningAt, snapshot.timestamp.timeIntervalSince(lw) < 120 {
                leftDistractionAfterWarning = true
            }
            distractionEnteredAt = nil
            if !keepScrollSessionAlive {
                scrollTracker.reset()
            }
        }

        if category == .distracting {
            if distractionEnteredAt == nil {
                distractionEnteredAt = snapshot.timestamp
            }
            let entered = distractionEnteredAt ?? snapshot.timestamp
            let sustained = snapshot.timestamp.timeIntervalSince(entered) >= settings.distractionSecondsBeforeNudge
            let chaotic = hysteresis.isChaoticFlipping()

            if leftDistractionAfterWarning, lastWarningAt != nil,
               snapshot.timestamp.timeIntervalSince(lastWarningAt!) < 90 {
                trigger = .boomerang
                leftDistractionAfterWarning = false
            } else if chaotic {
                trigger = .chaoticSwitching
            } else if heavyScroll {
                trigger = .scrollSession
            } else if sustained {
                trigger = .sustained
            }

            if trigger == nil,
               visionCategory == .distracting,
               ruleCategory != .distracting {
                trigger = .smartVision
            }
        }

        let next = FocusEngineOutput(category: category, snapshot: snapshot, trigger: trigger)
        if let cur = latestOutput,
           cur.category == next.category,
           cur.trigger == next.trigger,
           cur.snapshot.bundleID == next.snapshot.bundleID,
           cur.snapshot.windowTitle == next.snapshot.windowTitle {
            return
        }
        AppLogger.focus.debug(
            "Focus update bundle=\(next.snapshot.bundleID, privacy: .public) title=\((next.snapshot.windowTitle ?? "<nil>"), privacy: .public) category=\(next.category.rawValue, privacy: .public) trigger=\((next.trigger?.rawValue ?? "none"), privacy: .public)"
        )
        latestOutput = next
    }

    func markInterventionShown() {
        lastWarningAt = Date()
        leftDistractionAfterWarning = false
    }

    nonisolated static func effectiveCategory(
        ruleCategory: FocusCategory,
        visionCategory: FocusCategory?,
        bundleID: String,
        heavyScrolling: Bool,
        configuration: FocusRuleConfiguration
    ) -> FocusCategory {
        if heavyScrolling,
           configuration.browserBundleIDs.contains(bundleID),
           ruleCategory != .productive {
            return .distracting
        }
        return SmartCategoryMerge.merge(rule: ruleCategory, vision: visionCategory)
    }

    nonisolated static func shouldKeepScrollSession(
        bundleID: String,
        ruleCategory: FocusCategory,
        configuration: FocusRuleConfiguration
    ) -> Bool {
        configuration.browserBundleIDs.contains(bundleID) && ruleCategory != .productive
    }
}
