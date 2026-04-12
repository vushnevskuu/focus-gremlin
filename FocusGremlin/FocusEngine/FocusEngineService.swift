import AppKit
import Combine
import Foundation

enum DistractionTrigger: String, Sendable {
    case sustained
    case scrollSession
    case chaoticSwitching
    case boomerang
    case smartVision
    case pageChange
}

struct FocusEngineOutput: Sendable {
    let category: FocusCategory
    let snapshot: FocusSnapshot
    let trigger: DistractionTrigger?
    /// Сменилась вкладка/окно в режиме отвлечения (для реакции idle_2 + ским страницы нейросетью).
    let doomscrollPageDidChange: Bool
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
    /// С какого момента передний план — известный браузер с `ruleCategory == .neutral` (нет ни work keywords, ни маркеров отвлечения).
    private var neutralBrowserFrontmostSince: Date?
    /// Последний стабильный ключ «приложение + заголовок» в distracting; `nil` пока заголовок неизвестен или вне doomscroll.
    private var lastDistractingPageKey: String?
    /// Новый ключ сначала должен пережить короткую стабилизацию, иначе быстрые перерисовки вкладки рвут idle-реакцию.
    private var pendingDistractingPageKey: String?
    private var pendingDistractingPageFirstSeenAt: Date?

    @Published private(set) var latestOutput: FocusEngineOutput?

    private weak var settings: SettingsStore?
    private weak var smartMode: SmartModeController?

    init(settings: SettingsStore, smartMode: SmartModeController) {
        self.settings = settings
        self.smartMode = smartMode
    }

    /// Глобальный монитор колеса мыши (нужен Input Monitoring). Без него нет `scrollSession` и часть эскалации в браузере.
    var isGlobalScrollMonitorActive: Bool {
        scrollMonitor.hasActiveGlobalMonitor
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

    /// Вызов из AppDelegate при `didBecomeActive`: пользователь мог включить Input Monitoring.
    func restartScrollMonitorIfNeeded() {
        guard FeatureFlags.globalScrollMonitoringPreferred else { return }
        scrollMonitor.restart()
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
        let windowSnapshot = WindowContextProvider.frontmostWindowSnapshot()
        let pageContext = WindowContextProvider.frontmostBrowserPageContext(bundleID: bundle)

        if let lastFrontmostBundleID, lastFrontmostBundleID != bundle {
            scrollTracker.reset()
        }
        lastFrontmostBundleID = bundle

        let snapshot = FocusSnapshot(
            bundleID: bundle,
            windowTitle: windowSnapshot?.title,
            pageTitle: pageContext?.title,
            pageURL: pageContext?.url,
            pageSemanticSnippet: pageContext?.semanticSnippet,
            timestamp: Date()
        )
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
        let isBrowser = config.browserBundleIDs.contains(bundle)

        if isBrowser, ruleCategory == .neutral {
            if neutralBrowserFrontmostSince == nil {
                neutralBrowserFrontmostSince = snapshot.timestamp
            }
        } else {
            neutralBrowserFrontmostSince = nil
        }

        let neutralDwellExceeded: Bool = {
            guard isBrowser, ruleCategory == .neutral, let since = neutralBrowserFrontmostSince else { return false }
            return snapshot.timestamp.timeIntervalSince(since) >= settings.distractionSecondsBeforeNudge
        }()

        let engineRule: FocusCategory = neutralDwellExceeded ? .distracting : ruleCategory

        let visionCategory = smartMode?.freshVision(at: snapshot.timestamp)
        var category = Self.effectiveCategory(
            ruleCategory: engineRule,
            visionCategory: visionCategory,
            bundleID: bundle,
            heavyScrolling: heavyScroll,
            configuration: config,
            classifierWasProductive: ruleCategory == .productive
        )
        // Долгое «нейтральное» окно браузера — отвлечение по правилам; VLM не должен опускать это в .neutral.
        if neutralDwellExceeded {
            category = .distracting
        }
        // Заголовок/маркеры (YouTube, Reddit…) уже классифицировали отвлечение — не даём VLM свести это в .neutral
        // (иначе при Smart Mode гоблин «не запускается в браузере», хотя вкладка явно отвлекающая).
        if ruleCategory == .distracting {
            category = .distracting
        }

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
                if neutralDwellExceeded, let since = neutralBrowserFrontmostSince {
                    distractionEnteredAt = since
                } else {
                    distractionEnteredAt = snapshot.timestamp
                }
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
            } else if ruleCategory == .distracting {
                // Маркеры в заголовке (youtube, reddit…) — не ждём полный порог «sustained» по таймеру.
                trigger = .sustained
            } else if sustained {
                trigger = .sustained
            }

            if trigger == nil,
               visionCategory == .distracting,
               ruleCategory != .distracting {
                trigger = .smartVision
            }
        }

        var doomscrollPageDidChange = false
        if Self.pageAgentEligible(
            bundleID: bundle,
            ruleCategory: ruleCategory,
            effectiveCategory: category,
            configuration: config
        ) {
            if let key = snapshot.pageNavigationStabilityKey {
                doomscrollPageDidChange = registerStableDistractingPageKey(key, now: snapshot.timestamp)
            }
        } else {
            lastDistractingPageKey = nil
            pendingDistractingPageKey = nil
            pendingDistractingPageFirstSeenAt = nil
        }

        let next = FocusEngineOutput(
            category: category,
            snapshot: snapshot,
            trigger: trigger,
            doomscrollPageDidChange: doomscrollPageDidChange
        )
        if doomscrollPageDidChange {
            AppLogger.focus.debug(
                "Page agent trigger bundle=\(bundle, privacy: .public) title=\((snapshot.effectivePageTitle ?? "<nil>"), privacy: .public) url=\((snapshot.pageURL ?? "<nil>"), privacy: .public)"
            )
        }
        // Не дедуплицируем полностью: иначе после кулдауна orchestrator подписчик не получает новое событие
        // и реплика никогда не повторяется при том же заголовке вкладки.
        AppLogger.focus.debug(
            "Focus update bundle=\(next.snapshot.bundleID, privacy: .public) title=\((next.snapshot.effectivePageTitle ?? "<nil>"), privacy: .public) category=\(next.category.rawValue, privacy: .public) trigger=\((next.trigger?.rawValue ?? "none"), privacy: .public)"
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
        configuration: FocusRuleConfiguration,
        classifierWasProductive: Bool
    ) -> FocusCategory {
        if heavyScrolling,
           configuration.browserBundleIDs.contains(bundleID),
           !classifierWasProductive {
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

    nonisolated static func pageAgentEligible(
        bundleID: String,
        ruleCategory: FocusCategory,
        effectiveCategory: FocusCategory,
        configuration: FocusRuleConfiguration
    ) -> Bool {
        if configuration.browserBundleIDs.contains(bundleID) {
            return true
        }
        if effectiveCategory == .distracting {
            return true
        }
        _ = ruleCategory
        return false
    }

    private func registerStableDistractingPageKey(_ key: String, now: Date) -> Bool {
        guard let last = lastDistractingPageKey else {
            lastDistractingPageKey = key
            pendingDistractingPageKey = nil
            pendingDistractingPageFirstSeenAt = nil
            return false
        }

        if key == last {
            pendingDistractingPageKey = nil
            pendingDistractingPageFirstSeenAt = nil
            return false
        }

        if pendingDistractingPageKey != key {
            pendingDistractingPageKey = key
            pendingDistractingPageFirstSeenAt = now
            return false
        }

        let firstSeen = pendingDistractingPageFirstSeenAt ?? now
        // Короче — быстрее реагируем на смену ссылки во вкладке (idle_2 + агент).
        guard now.timeIntervalSince(firstSeen) >= 0.28 else { return false }
        lastDistractingPageKey = key
        pendingDistractingPageKey = nil
        pendingDistractingPageFirstSeenAt = nil
        return true
    }
}
