import AppKit
import SwiftUI

/// Плавающая `NSPanel`: все Spaces, неактивируемая, клики проходят сквозь оверлей.
@MainActor
final class OverlayPanelController: NSObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<CompanionBubbleView>
    let viewModel: CompanionViewModel

    private var smoothedLocation: CGPoint = .zero
    private var hasLocation = false
    private var windowFocusObservers: [NSObjectProtocol] = []
    /// Верх панели в координатах экрана (Y снизу), чтобы при росте текста голова не «уезжала» вверх.
    private var lockedPanelTopY: CGFloat?
    private var lastPinCursor: CGPoint = .zero
    private var lastLaidOutHeight: CGFloat = 0

    private var cachedContentSize = NSSize(width: 0, height: 0)
    private var lastSizeMeasureUptime: TimeInterval = 0
    private var lastMeasuredPhase: BubblePhase = .idle
    private var lastMeasuredTextCount: Int = -1

    init(viewModel: CompanionViewModel) {
        self.viewModel = viewModel
        let root = CompanionBubbleView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        super.init()

        panel.level = .floating
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

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
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
        panel.orderFrontRegardless()
    }

    /// Сразу подставить позицию курсора и пересчитать frame (нужно для теста, если агент выключен — таймер не крутится).
    func snapPanelToCursorNow() {
        let mouse = NSEvent.mouseLocation
        smoothedLocation = mouse
        hasLocation = true
        cachedContentSize = .zero
        lastMeasuredTextCount = -1
        layoutPanelAtSmoothedCursor()
    }

    func tickCursorFollow() {
        updateMainWindowInteractionFlag()
        guard !viewModel.isInteractionFocusedOnMainAppWindow else { return }

        let mouse = NSEvent.mouseLocation
        if !hasLocation {
            smoothedLocation = mouse
            hasLocation = true
        } else {
            // Выше частота тика → чуть сильнее сглаживание за кадр, чтобы не «нырял» за курсором.
            let t: CGFloat = 0.32
            smoothedLocation.x += (mouse.x - smoothedLocation.x) * t
            smoothedLocation.y += (mouse.y - smoothedLocation.y) * t
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
        let bubbleUp = viewModel.bubbleOpacity > 0.05 || viewModel.isBusy
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

        let offsetX: CGFloat = 18
        let offsetY: CGFloat = 20
        let pinMoveThreshold: CGFloat = 1.5

        let cursorJump = hypot(smoothedLocation.x - lastPinCursor.x, smoothedLocation.y - lastPinCursor.y)
        if cursorJump > pinMoveThreshold || lockedPanelTopY == nil {
            lastPinCursor = smoothedLocation
            lockedPanelTopY = smoothedLocation.y + offsetY + size.height
        } else if size.height < lastLaidOutHeight - 2 {
            lastPinCursor = smoothedLocation
            lockedPanelTopY = smoothedLocation.y + offsetY + size.height
        }

        var origin = CGPoint(
            x: smoothedLocation.x + offsetX,
            y: (lockedPanelTopY ?? smoothedLocation.y + offsetY + size.height) - size.height
        )

        if let screen = screenContaining(point: smoothedLocation) {
            let frame = screen.visibleFrame
            let w = max(frame.width, 1)
            let nx = (smoothedLocation.x - frame.minX) / w
            viewModel.updateCursorZone(normalizedScreenX: nx)

            origin.x = min(max(frame.minX, origin.x), frame.maxX - size.width)
            origin.y = min(max(frame.minY, origin.y), frame.maxY - size.height)
            lockedPanelTopY = origin.y + size.height
        } else {
            lockedPanelTopY = origin.y + size.height
        }

        lastLaidOutHeight = size.height
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height), display: false)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        let nsPoint = NSPoint(x: point.x, y: point.y)
        return NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) }
            ?? NSScreen.main
    }
}
