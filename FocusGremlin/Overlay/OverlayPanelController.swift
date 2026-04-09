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

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func tickCursorFollow() {
        let mouse = NSEvent.mouseLocation
        if !hasLocation {
            smoothedLocation = mouse
            hasLocation = true
        } else {
            let t: CGFloat = 0.14
            smoothedLocation.x += (mouse.x - smoothedLocation.x) * t
            smoothedLocation.y += (mouse.y - smoothedLocation.y) * t
        }

        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        let offsetX: CGFloat = 18
        let offsetY: CGFloat = 20
        var origin = CGPoint(x: smoothedLocation.x + offsetX, y: smoothedLocation.y + offsetY)

        if let screen = screenContaining(point: smoothedLocation) {
            let frame = screen.visibleFrame
            let w = max(frame.width, 1)
            let nx = (smoothedLocation.x - frame.minX) / w
            viewModel.updateCursorZone(normalizedScreenX: nx)

            origin.x = min(max(frame.minX, origin.x), frame.maxX - size.width)
            origin.y = min(max(frame.minY, origin.y), frame.maxY - size.height)
        }

        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height), display: false)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        let nsPoint = NSPoint(x: point.x, y: point.y)
        return NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) }
            ?? NSScreen.main
    }
}
