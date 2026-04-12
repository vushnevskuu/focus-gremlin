import AppKit
import QuartzCore
import SwiftUI

/// Плавающая `NSPanel`: все Spaces, неактивируемая, клики проходят сквозь оверлей.
@MainActor
final class OverlayPanelController: NSObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<CompanionBubbleView>
    private let spitPanel: NSPanel
    private let spitHostingView: NSHostingView<GoblinSpitOverlayView>
    let viewModel: CompanionViewModel

    private var smoothedLocation: CGPoint = .zero
    private var windowFocusObservers: [NSObjectProtocol] = []
    /// Верх панели (origin.y + height) для якорения при скачке высоты текста.
    private var lastPanelTopY: CGFloat?
    private var lastLaidOutHeight: CGFloat = 0

    private var cachedContentSize = NSSize(width: 0, height: 0)
    private var lastSizeMeasureUptime: TimeInterval = 0
    private var lastMeasuredPhase: BubblePhase = .idle
    private var lastMeasuredTextCount: Int = -1
    /// Когда плевков нет, `updateSpitPanel` не нужен каждый тик — режем лишние `setFrame`/`orderFront`.
    private var cursorFollowTickCounter = 0
    private var lastSpitTickMouse = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    /// Обновлять `cursorZone` только если курсор реально сдвинулся (меньше лишних публикаций в VM).
    private var cursorMovedThisTick = false

    init(viewModel: CompanionViewModel) {
        self.viewModel = viewModel
        let root = CompanionBubbleView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)
        let spitRoot = GoblinSpitOverlayView(viewModel: viewModel)
        self.spitHostingView = NSHostingView(rootView: spitRoot)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        let spitPanel = NSPanel(
            contentRect: NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.spitPanel = spitPanel

        super.init()

        // Выше обычных окон (в т.ч. часть полноэкранных клиентов вроде Instagram), но ниже screenSaver.
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = hostingView
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        spitPanel.level = .mainMenu
        spitPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        spitPanel.isFloatingPanel = true
        spitPanel.hidesOnDeactivate = false
        spitPanel.isOpaque = false
        spitPanel.backgroundColor = .clear
        spitPanel.hasShadow = false
        spitPanel.ignoresMouseEvents = true
        spitPanel.becomesKeyOnlyIfNeeded = true
        spitPanel.titleVisibility = .hidden
        spitPanel.titlebarAppearsTransparent = true
        spitPanel.contentView = spitHostingView
        spitHostingView.layer?.backgroundColor = NSColor.clear.cgColor

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        spitHostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spitHostingView.leadingAnchor.constraint(equalTo: spitPanel.contentView!.leadingAnchor),
            spitHostingView.trailingAnchor.constraint(equalTo: spitPanel.contentView!.trailingAnchor),
            spitHostingView.topAnchor.constraint(equalTo: spitPanel.contentView!.topAnchor),
            spitHostingView.bottomAnchor.constraint(equalTo: spitPanel.contentView!.bottomAnchor)
        ])

        let center = NotificationCenter.default
        windowFocusObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateMainWindowInteractionFlag()
            }
        })
        windowFocusObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateMainWindowInteractionFlag()
            }
        })
        updateMainWindowInteractionFlag()
    }

    deinit {
        let center = NotificationCenter.default
        windowFocusObservers.forEach { center.removeObserver($0) }
    }

    /// Пока фокус в обычном окне нашего приложения (не плавающая панель), не делаем тяжёлый layout оверлея и не крутим спрайт на полном FPS.
    private func updateMainWindowInteractionFlag() {
        let on: Bool
        if NSApp.isActive, let key = NSApp.keyWindow {
            on = key !== panel && key.level == .normal
        } else {
            on = false
        }
        viewModel.setMainWindowInteractionFocused(on)
    }

    func show() {
        updateSpitPanel(on: screenContaining(point: NSEvent.mouseLocation), refreshZOrder: true)
        panel.orderFrontRegardless()
    }

    /// Сразу выставить `visibleFrame`, размер для SwiftUI и показать панель — нужно в тот же момент, когда появляются пятна (до следующего тика курсора).
    func syncSpitPanelWithCursorScreen() {
        updateSpitPanel(on: screenContaining(point: NSEvent.mouseLocation), refreshZOrder: true)
    }

    /// Сразу подставить позицию курсора и пересчитать frame (нужно для теста, если агент выключен — таймер не крутится).
    func snapPanelToCursorNow() {
        let mouse = NSEvent.mouseLocation
        smoothedLocation = mouse
        cachedContentSize = .zero
        lastMeasuredTextCount = -1
        lastPanelTopY = nil
        layoutPanelAtSmoothedCursor()
    }

    func tickCursorFollow() {
        updateMainWindowInteractionFlag()
        let mouse = NSEvent.mouseLocation
        let firstMouseSample = lastSpitTickMouse.x.isNaN
        let mouseMoved: Bool
        if firstMouseSample {
            mouseMoved = true
        } else {
            mouseMoved = hypot(mouse.x - lastSpitTickMouse.x, mouse.y - lastSpitTickMouse.y) > 0.75
        }
        lastSpitTickMouse = mouse
        cursorMovedThisTick = mouseMoved
        cursorFollowTickCounter += 1

        let spitVisible = viewModel.shouldShowSpitOverlay
        let spitLayoutTick =
            mouseMoved
            || cursorFollowTickCounter.isMultiple(of: 6)
            || (spitVisible && cursorFollowTickCounter.isMultiple(of: 3))
            || (spitVisible && cursorFollowTickCounter.isMultiple(of: 10))
        let spitZOrderTick = mouseMoved || cursorFollowTickCounter.isMultiple(of: 10)
        if spitLayoutTick {
            updateSpitPanel(on: screenContaining(point: mouse), refreshZOrder: spitZOrderTick)
        }

        // Как в стабильной ветке репозитория: позиция панели = курсор (без лерпа). При фокусе в своём окне — не двигаем, но layout делаем (размер текста).
        if !viewModel.isInteractionFocusedOnMainAppWindow {
            smoothedLocation = mouse
        }
        layoutPanelAtSmoothedCursor()
    }

    private func remeasureContentSize() {
        hostingView.layoutSubtreeIfNeeded()
        cachedContentSize = hostingView.fittingSize
        lastSizeMeasureUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Без вызова на каждом тике: `fittingSize` + полный layout SwiftUI дорогие.
    private func contentSizeForLayout() -> NSSize {
        let now = ProcessInfo.processInfo.systemUptime
        let phase = viewModel.phase
        let textCount = viewModel.visibleText.count
        let phaseChanged = phase != lastMeasuredPhase
        let textChanged = textCount != lastMeasuredTextCount
        let bubbleUp = viewModel.bubbleOpacity > 0.05 || viewModel.isBusy || viewModel.shouldShowCompanionSprite
        let elapsed = now - lastSizeMeasureUptime

        var needMeasure = phaseChanged || textChanged || cachedContentSize.width < 1
        if !needMeasure {
            if bubbleUp {
                // Текст/фаза стабильны — не дёргаем SwiftUI layout на каждом тике курсора.
                needMeasure = elapsed >= 2.0
            } else {
                needMeasure = elapsed >= 0.45
            }
        }

        if needMeasure {
            lastMeasuredPhase = phase
            lastMeasuredTextCount = textCount
            remeasureContentSize()
        }
        return cachedContentSize
    }

    private func layoutPanelAtSmoothedCursor() {
        let size = contentSizeForLayout()

        /// Левый край панели чуть правее hotspot курсора — первым идёт столбец гоблина.
        let offsetX: CGFloat = 8
        let offsetY: CGFloat = 20
        /// Рост/сжатие пузыря (текст) — не дёргаем верх панели по экрану.
        let heightChanged = lastLaidOutHeight > 0 && abs(size.height - lastLaidOutHeight) > 1

        var origin = CGPoint.zero
        origin.x = smoothedLocation.x + offsetX
        if heightChanged, let top = lastPanelTopY {
            origin.y = top - size.height
        } else {
            origin.y = smoothedLocation.y + offsetY
        }

        if let screen = screenContaining(point: smoothedLocation) {
            let frame = screen.visibleFrame
            let w = max(frame.width, 1)
            let nx = (smoothedLocation.x - frame.minX) / w
            if cursorMovedThisTick {
                viewModel.updateCursorZone(normalizedScreenX: nx)
            }

            origin.x = min(max(frame.minX, origin.x), frame.maxX - size.width)
            origin.y = min(max(frame.minY, origin.y), frame.maxY - size.height)
        }

        lastPanelTopY = origin.y + size.height
        lastLaidOutHeight = size.height

        let newFrame = NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        let old = panel.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if abs(newFrame.width - old.width) < 0.5 && abs(newFrame.height - old.height) < 0.5 {
            panel.setFrameOrigin(newFrame.origin)
        } else {
            panel.setFrame(newFrame, display: false)
        }
        CATransaction.commit()
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        let nsPoint = NSPoint(x: point.x, y: point.y)
        return NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) }
            ?? NSScreen.main
    }

    private func updateSpitPanel(on screen: NSScreen?, refreshZOrder: Bool) {
        guard let screen else {
            spitPanel.orderOut(nil)
            // Всегда поднимаем панель с гоблином: иначе после orderOut плевка она может оказаться под чужими окнами и «пропасть».
            if refreshZOrder {
                panel.orderFrontRegardless()
            }
            return
        }
        // Только видимая область (без меню/дока): 0.5×0.5 в SwiftUI = реальный центр экрана для пользователя.
        let frame = screen.visibleFrame
        let old = spitPanel.frame
        if abs(old.origin.x - frame.origin.x) > 0.5
            || abs(old.origin.y - frame.origin.y) > 0.5
            || abs(old.size.width - frame.size.width) > 0.5
            || abs(old.size.height - frame.size.height) > 0.5 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spitPanel.setFrame(frame, display: false)
            CATransaction.commit()
        }

        viewModel.setSpitPanelContentSize(frame.size)

        guard viewModel.shouldShowSpitOverlay else {
            spitPanel.orderOut(nil)
            if refreshZOrder {
                panel.orderFrontRegardless()
            }
            return
        }
        if refreshZOrder {
            spitPanel.orderFrontRegardless()
            panel.orderFrontRegardless()
        }
    }
}
